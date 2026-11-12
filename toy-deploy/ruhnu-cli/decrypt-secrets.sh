#!/bin/sh
# Compose service "decrypt": decrypts /toy/secret.env.cdoc2 to /secrets/secret.env, in the tmpfs volume
# "secrets". The shares servers' auth tokens are signed by the ssh-agent of whoever runs `docker compose up`,
# mounted at /ssh-agent.sock; with a key added by `ssh-add -c`, that agent asks once per shares server.
set -eu

[ -f /toy/secret.env.cdoc2 ] || { echo "decrypt: secret.env.cdoc2 not found in the project directory" >&2; exit 1; }
if [ ! -S /ssh-agent.sock ]; then
    echo "decrypt: no ssh-agent (SSH_AUTH_SOCK was not set for docker compose)." >&2
    echo "decrypt: log in with ssh -A, check that ssh-add -l lists your key, then run docker compose up again." >&2
    exit 1
fi

# cdoc2-cli doesn't overwrite files: decrypt into a new directory, then replace the old secret.env
out="$(mktemp -d /secrets/.decrypt.XXXXXX)"
trap 'rm -rf "$out"' EXIT
sh /toy/ruhnu-cli/cli.sh decrypt --ssh-agent -f /toy/secret.env.cdoc2 -o "$out"
chmod 600 "$out/secret.env"
mv -f "$out/secret.env" /secrets/secret.env
echo "decrypt: secret.env decrypted into the secrets volume (tmpfs)"
