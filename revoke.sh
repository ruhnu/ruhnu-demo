#!/usr/bin/env bash
# Revocation before expiry: delete the recipient's share on one shares server (out-of-band SQL). Decryption fails
# at once and names the refusing server, while the other server still holds its share: with N_OF_N one server
# is enough to revoke. Run ./up.sh first.
set -euo pipefail
source "$(dirname "$0")/env.sh"

[[ -S "$DEMO_AGENT_SOCK" ]] || fail "demo environment is not up, run ./up.sh"
export SSH_AUTH_SOCK="$DEMO_AGENT_SOCK"

work="$RUN_DIR/revoke"
rm -rf "$work" && mkdir -p "$work/out" "$work/out2"
echo "api_token=revoke-me" >"$work/secret.env"
recipient="ruhnu/pk/$(cut -d' ' -f2 "$DEMO_KEY.pub")"
this_run="recipient = '$recipient' and created_at >= to_timestamp($(($(date +%s) - 1)))"

read -r revoking_name revoking_port _ revoking_pg <<<"${SERVERS[0]}"
read -r other_name _ _ other_pg <<<"${SERVERS[1]}"

step "encrypt and decrypt"
cdoc2 create -f "$work/secret.cdoc2" --ssh-pubkey "$DEMO_KEY.pub" \
    "-Dkey-shares.properties=$KEY_SHARES_PROPERTIES" "$work/secret.env"
cdoc2 decrypt -f "$work/secret.cdoc2" --ssh-agent -o "$work/out" "-Dkey-shares.properties=$KEY_SHARES_PROPERTIES"
diff "$work/secret.env" "$work/out/secret.env" || fail "decrypted file differs"
ok "decrypted before revocation"

step "revoke: delete the recipient's share on $revoking_name only"
# nonces reference the share (foreign key), delete them first
psql_on "$revoking_pg" "delete from key_material_share_nonce where share_id in
    (select share_id from key_material_share where $this_run);
    delete from key_material_share where $this_run returning share_id"

step "decrypt after revocation"
if cdoc2 decrypt -f "$work/secret.cdoc2" --ssh-agent -o "$work/out2" \
    "-Dkey-shares.properties=$KEY_SHARES_PROPERTIES" >"$work/revoked.out" 2>&1; then
    fail "decryption succeeded after revocation"
fi
message=$(grep -m1 "refused nonce" "$work/revoked.out" | sed 's/.*Exception: //')
echo "$message"
[[ "$message" == *"https://localhost:$revoking_port"* ]] || fail "error does not name $revoking_name"
ok "decryption refused, $revoking_name (https://localhost:$revoking_port) named as the refusing server"

rows=$(psql_on "$other_pg" "select count(*) from key_material_share where $this_run")
[[ "$rows" == "1" ]] || fail "$other_name: expected its share to be still stored, found $rows"
ok "$other_name still holds its share, which alone is useless"

step "revocation demo finished"
