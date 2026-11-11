# Live servers with the CLI image

Encrypt a file to an SSH key and decrypt it through `ssh-agent`, using the two live shares servers and the
published CLI image `ghcr.io/ruhnu/ruhnu-cli`. Nothing is built or run locally apart from `docker run`.

**The live servers are for demos only: don't encrypt real secrets with them.** Both are run by the same
organisation, so the split across servers protects nothing yet, and they come with no availability or backup
guarantees.

For the local stack with its own servers (expiry and revocation scripts), see [../local/README.md](../local/README.md).

## What's used

| Component | Where |
|---|---|
| shares server 1 | `https://share1-ruhnu.duckdns.org`, Oracle Cloud, run by the Ruhnu team |
| shares server 2 | `https://share2-ruhnu.cyber.ee`, on-prem OpenStack at cyber.ee, run by the Ruhnu team |
| CLI | `ghcr.io/ruhnu/ruhnu-cli:dev-cli-image-1` (OpenSpec change `add-cli-container-image`) |
| `ssh-agent` | yours, its socket mounted into the container for decryption |

Both servers run image tag `dev-ssh-pk-1` with SSH public key recipients enabled. `ruhnu/pk/` shares live
14 days by default and at most; a shorter lifetime can be requested with `--share-expiry`. Both servers have
Let's Encrypt certificates.

There is no `:latest` image yet: it's published only for `v*` tags, and so far there are only `dev-*` tags.

## Prerequisites

- Docker, runnable without `sudo`
- OpenSSH client (`ssh-agent`, `ssh-add`, `ssh-keygen`)
- an ECDSA P-256 key in your agent. Ed25519 and RSA are not supported yet. Check with
  `ssh-add -L | grep ecdsa-sha2-nistp256`. If nothing is listed, load a key, creating it only if it doesn't
  exist yet:

  ```shell
  [ -f ~/.ssh/id_ecdsa_cdoc2 ] || ssh-keygen -t ecdsa -b 256 -f ~/.ssh/id_ecdsa_cdoc2
  ssh-add ~/.ssh/id_ecdsa_cdoc2
  ```

Java is not needed: `keytool` for the truststore comes from the image too.

## 1. Setup: `init.sh`

Source it in bash, from anywhere:

```shell
source ~/workspace/ruhnu-workspace/ruhnu-demo/live/init.sh
```

- It creates `live/config/` if missing (ignored by git):
  - `key-shares.properties`, listing share1 and share2 with N-of-N;
  - `truststore.jks`, with the Let's Encrypt roots ISRG Root X1 and X2, downloaded from letsencrypt.org and
    imported with the image's `keytool`. The client trusts only this truststore, not the JDK's CAs. It holds
    only public CA certificates, so its password (`changeit`) protects nothing.
- It defines and exports the `ruhnu` function, which runs the image as your user, with the current directory
  at `/work`, `live/config` at `/config`, and your agent socket at `/ssh-agent.sock` when `SSH_AUTH_SOCK` is
  set. It's the function from `cdoc2-cli/README-ruhnu.md` in cdoc2-java-ref-impl, with the configuration
  directory changed.
- The image is `RUHNU_CLI_IMAGE`, `ghcr.io/ruhnu/ruhnu-cli:dev-cli-image-1` unless set before sourcing.
- The configuration directory is `RUHNU_CONFIG_DIR`, `live/config` unless set before sourcing. For a
  configuration that stays outside the repository:

  ```shell
  RUHNU_CONFIG_DIR=~/.config/cdoc2 source ~/workspace/ruhnu-workspace/ruhnu-demo/live/init.sh
  ```

  Existing files there are kept, so a `key-shares.properties` you wrote yourself is used as it is.
- `ruhnu` keeps the image and directory chosen when sourcing. To change them, source again with the new
  values; without them, sourcing again goes back to the defaults.

Running `live/init.sh` instead of sourcing it creates the configuration but can't define the function in your
shell. To start over, delete the configuration directory and source it again.

## 2. Encrypt, inspect, decrypt

`ruhnu` runs in a container that sees only the current directory, mounted at `/work`. Give file paths
relative to it, below it: `-f secret.cdoc2`, `-o out`. Absolute paths such as `/tmp/x` or `~/x`, and `../`,
point outside the mount and fail, for example with `Destination directory /tmp/x does not exist`. Worse,
`-o /tmp` succeeds, because `/tmp` exists in the container, and the decrypted file is lost with the container.
`cd` to the files' directory first. The output directory must already exist (`mkdir -p out`).

Containers store file names only, not directories: `dir/a.txt` is decrypted as `a.txt`, a directory can't be
added, and two files with the same name can't be added together. To keep a directory tree, encrypt a tar of it.

```shell
mkdir -p /tmp/ruhnu-live && cd /tmp/ruhnu-live
echo "DATABASE_PASSWORD=$(openssl rand -hex 8)" > secret.env

ruhnu create --ssh-pubkey "$(ssh-add -L | grep -m1 ecdsa-sha2-nistp256)" -f secret.cdoc2 secret.env
ruhnu info -f secret.cdoc2

mkdir -p out
ruhnu decrypt --ssh-agent -f secret.cdoc2 -o out
cmp secret.env out/secret.env && echo OK
```

- `create` stores one key share on each server. To encrypt to a teammate, give their `.pub` line instead:
  `--ssh-pubkey "$(cat alice.pub)"` (repeatable).
- `info` shows the recipient as `SN:ruhnu/pk:SHA256:…`, the same fingerprint `ssh-add -l` shows.
- `decrypt` signs an auth token for each server through your agent and gets both shares. With a key added by
  `ssh-add -c`, your agent asks once per server. The decrypted file belongs to you.

If the agent doesn't hold the container's key, `decrypt` fails with `No matching key found in ssh-agent`
before contacting any server.

GNOME's own agent (`SSH_AUTH_SOCK` ending in `keyring/ssh`) refuses to sign with keys added by `ssh-add -c`
(`agent refused operation`). Use OpenSSH's `ssh-agent` for confirmed keys (`eval $(ssh-agent)`).

## 3. Access ends by expiry

Request a short lifetime, decrypt at once, then again after it has passed:

```shell
ruhnu create --ssh-pubkey "$(ssh-add -L | grep -m1 ecdsa-sha2-nistp256)" \
  --share-expiry PT5M -f short.cdoc2 secret.env
ruhnu decrypt --ssh-agent -f short.cdoc2 -o out      # works
sleep 330
ruhnu decrypt --ssh-agent -f short.cdoc2 -o out      # refused: the shares have expired
```

## Revocation is not tested here

Revoking access before the shares expire means deleting the recipient's share on at least one server, in its
database. On the live servers only the Ruhnu team, which runs both, can do that; there is no
self-service API, so it is not part of this walkthrough. The local stack shows it:
`../local/revoke.sh`.

Self-service revocation is the follow-up: the OpenSpec change `add-did-recipient` binds a recipient to a
DID document, and removing the key from the document revokes access at once on every server. It will be
tested against the live servers once it is deployed there.

## Verified

2026-11-11, from the ruhnu sandbox with `dev-cli-image-1`: truststore from the ISRG roots, `create` with
`--share-expiry PT10M` to a throwaway P-256 key, `info`, and `decrypt --ssh-agent` through a throwaway
agent, against share1 and share2. The decrypted file matched and was owned by the host user. After the 10 minutes,
decryption was refused: `Shares server https://share1-ruhnu.duckdns.org refused nonce for share ID …: share
not found (expired or deleted)`.
