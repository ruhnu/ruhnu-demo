#!/usr/bin/env bash
# Full flow: encrypt a secret to the demo SSH key, decrypt it through ssh-agent, check the release audit log on
# both shares servers, then wait until the shares expire and check that decryption is refused (404) while the
# expired rows are still in the database (the clean-up job is disabled). Run ./up.sh first.
set -euo pipefail
source "$(dirname "$0")/env.sh"

[[ -S "$DEMO_AGENT_SOCK" ]] || fail "demo environment is not up, run ./up.sh"
export SSH_AUTH_SOCK="$DEMO_AGENT_SOCK"

work="$RUN_DIR/demo"
rm -rf "$work" && mkdir -p "$work"
echo "db_password=correct-horse-battery-staple" >"$work/secret.env"
recipient="ruhnu/pk/$(cut -d' ' -f2 "$DEMO_KEY.pub")"
fingerprint=$(ssh-keygen -lf "$DEMO_KEY.pub" | cut -d' ' -f2)

# rows created by this run (earlier runs may have left rows for the same key)
this_run="recipient = '$recipient' and created_at >= to_timestamp($(($(date +%s) - 1)))"

step "encrypt secret.env to the demo SSH key ($fingerprint)"
cdoc2 create -f "$work/secret.cdoc2" --ssh-pubkey "$DEMO_KEY.pub" \
    "-Dkey-shares.properties=$KEY_SHARES_PROPERTIES" "$work/secret.env"
cdoc2 info -f "$work/secret.cdoc2"

for server in "${SERVERS[@]}"; do
    read -r name _ _ pg_port <<<"$server"
    echo "$name stores: $(psql_on "$pg_port" \
        "select share_id || ' expires ' || expiry_time from key_material_share where $this_run")"
done

step "decrypt through ssh-agent"
mkdir -p "$work/out" "$work/out2"
cdoc2 decrypt -f "$work/secret.cdoc2" --ssh-agent -o "$work/out" "-Dkey-shares.properties=$KEY_SHARES_PROPERTIES"
diff "$work/secret.env" "$work/out/secret.env" || fail "decrypted file differs"
ok "decrypted file matches"

step "release audit log on both servers"
for server in "${SERVERS[@]}"; do
    read -r name _ _ _ <<<"$server"
    line=$(grep "Key share released" "$RUN_DIR/$name.log" | grep -- "$fingerprint" | tail -1) \
        || fail "$name has no audit line for $fingerprint"
    echo "$name: ${line##*: }"
done
ok "both servers logged the release"

step "wait until the shares expire ($SHARE_LIFETIME)"
expiry=$(psql_on "${SERVERS[0]##* }" \
    "select extract(epoch from max(expiry_time))::bigint from key_material_share where $this_run")
wait=$((expiry - $(date +%s) + 5))
if ((wait > 0)); then
    echo "waiting ${wait}s"
    sleep "$wait"
fi

step "decrypt after expiry"
if cdoc2 decrypt -f "$work/secret.cdoc2" --ssh-agent -o "$work/out2" \
    "-Dkey-shares.properties=$KEY_SHARES_PROPERTIES" >"$work/expired.out" 2>&1; then
    fail "decryption succeeded after expiry"
fi
grep -m1 "refused nonce" "$work/expired.out" | sed 's/.*Exception: //'
ok "decryption refused after expiry"

for server in "${SERVERS[@]}"; do
    read -r name _ _ pg_port <<<"$server"
    rows=$(psql_on "$pg_port" "select count(*) from key_material_share where $this_run")
    [[ "$rows" == "1" ]] || fail "$name: expected the expired row to be still in the database, found $rows"
done
ok "expired rows are still in both databases: refused because of expiry, not because the clean-up deleted them"

step "demo finished"
