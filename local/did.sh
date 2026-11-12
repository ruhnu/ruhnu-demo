#!/usr/bin/env bash
# DID recipients ("ruhnu/did/", add-did-recipient 6.2-6.5): encrypt a secret to the DID $DID, whose document
# lists the demo SSH key, decrypt it through ssh-agent and check the release audit log; revoke by removing the
# key from the DID document; stop the DID host (outage); and add Mallory's key to the DID document (compromised
# DID host), which must not open the existing container. Run ./up.sh first.
set -euo pipefail
source "$(dirname "$0")/env.sh"

[[ -S "$DEMO_AGENT_SOCK" ]] || fail "demo environment is not up, run ./up.sh"
export SSH_AUTH_SOCK="$DEMO_AGENT_SOCK"

work="$RUN_DIR/did"
rm -rf "$work" && mkdir -p "$work"
echo "db_password=correct-horse-battery-staple" >"$work/secret.env"
KS="-Dkey-shares.properties=$KEY_SHARES_PROPERTIES"

decrypt() { # <agent socket> -> exit code; stderr in $work/decrypt.err
    rm -rf "$work/out" && mkdir -p "$work/out"
    SSH_AUTH_SOCK="$1" cdoc2 decrypt -f "$work/secret.cdoc2" --ssh-agent -o "$work/out" "$KS" \
        >"$work/decrypt.out" 2>"$work/decrypt.err"
}

expect_decrypted() { # <agent socket> <what>
    decrypt "$1" || { cat "$work/decrypt.err" >&2; fail "$2: decryption failed"; }
    diff -q "$work/secret.env" "$work/out/secret.env" >/dev/null || fail "$2: decrypted file differs"
    ok "$2"
}

expect_refused() { # <agent socket> <expected message> <what>
    if decrypt "$1"; then
        fail "$3: decryption succeeded"
    fi
    grep -q -- "$2" "$work/decrypt.err" || { cat "$work/decrypt.err" >&2; fail "$3: expected \"$2\""; }
    grep -m1 '^ERROR: ' "$work/decrypt.err" || true
    ok "$3"
}

did_document() { # <public key file>... : the DID document lists these keys
    python3 "$DEMO_DIR/make-did-json.py" "$DID" "$@" >"$DID_DOC.tmp" && mv "$DID_DOC.tmp" "$DID_DOC"
}

step "encrypt secret.env to $DID"
did_document "$DEMO_KEY.pub"
cdoc2 create -f "$work/secret.cdoc2" --did "$DID" "$KS" "$work/secret.env" >"$work/create.out" 2>&1 \
    || { cat "$work/create.out" >&2; fail "create"; }
grep '^Pinned ' "$work/create.out" || fail "create did not print the pinned recipient"
fingerprint=$(ssh-keygen -lf "$DEMO_KEY.pub" | cut -d' ' -f2)
grep -q "($fingerprint)" "$work/create.out" || fail "pinned key is not the demo key $fingerprint"
cdoc2 info -f "$work/secret.cdoc2" 2>/dev/null
ok "pinned the demo key $fingerprint"

step "decrypt through ssh-agent"
expect_decrypted "$DEMO_AGENT_SOCK" "decrypted file matches"

step "release audit log on both servers"
for server in "${SERVERS[@]}"; do
    read -r name _ _ _ <<<"$server"
    line=$(grep "Key share released" "$RUN_DIR/$name.log" | grep -- "recipient=ruhnu/did/$DID/hash/" | tail -1) \
        || fail "$name has no audit line for $DID"
    echo "$name: ${line##*: }"
done
ok "both servers logged the release with the ruhnu/did/ recipient"

step "revoke: remove the key from the DID document"
did_document
expect_refused "$DEMO_AGENT_SOCK" "no longer listed in the DID document" "decryption refused at once (404)"
did_document "$DEMO_KEY.pub"
expect_decrypted "$DEMO_AGENT_SOCK" "decrypted again after the key is back in the DID document"

step "outage: stop the DID host"
docker stop "$DID_HOST_CONTAINER" >/dev/null
expect_refused "$DEMO_AGENT_SOCK" "could not reach the DID host" "decryption refused while the DID host is down (503)"
docker start "$DID_HOST_CONTAINER" >/dev/null
for _ in $(seq 1 30); do
    curl -sfk "https://localhost:$DID_PORT/p/alice/did.json" >/dev/null && break
    sleep 1
done
expect_decrypted "$DEMO_AGENT_SOCK" "decrypted again after the DID host is back"

step "compromised DID host: Mallory's key added to the DID document"
mallory_sock="$RUN_DIR/mallory.sock"
# stop Mallory's agent from an earlier run, otherwise every run leaves one behind
if [[ -f "$RUN_DIR/mallory-agent.env" ]]; then
    (source "$RUN_DIR/mallory-agent.env" >/dev/null && ssh-agent -k >/dev/null 2>&1) || true
fi
rm -f "$mallory_sock" "$RUN_DIR/mallory" "$RUN_DIR/mallory.pub"
ssh-agent -a "$mallory_sock" </dev/null >"$RUN_DIR/mallory-agent.env" 2>/dev/null
ssh-keygen -q -t ecdsa -b 256 -N '' -C "mallory" -f "$RUN_DIR/mallory"
SSH_AUTH_SOCK="$mallory_sock" ssh-add -q "$RUN_DIR/mallory"
did_document "$DEMO_KEY.pub" "$RUN_DIR/mallory.pub"
expect_refused "$mallory_sock" "No matching key found in ssh-agent" \
    "Mallory's agent can't decrypt: the container pins the demo key, not Mallory's"
SSH_AUTH_SOCK="$mallory_sock" java -cp "$CLI_JAR" "$DEMO_DIR/AttackerFetch.java" \
    "$work/secret.cdoc2" "$DID" "$TRUSTSTORE" passwd >"$work/attacker.out" 2>&1 \
    || { cat "$work/attacker.out" >&2; fail "a shares server did not refuse Mallory's DID token"; }
grep -v "Picked up" "$work/attacker.out"
ok "both servers refuse Mallory's validly signed DID token for the demo key's shares (404)"
expect_decrypted "$DEMO_AGENT_SOCK" "the demo key still decrypts"
did_document "$DEMO_KEY.pub"

step "DID demo finished"
