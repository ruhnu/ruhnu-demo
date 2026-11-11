# Live servers with the CLI image

Encrypt a file to an SSH key, or to the keys a `did:web` DID document lists, and decrypt it through
`ssh-agent`, using the two live shares servers and the published CLI image `ghcr.io/ruhnu/ruhnu-cli`. Nothing
is built or run locally apart from `docker run`.

**The live servers are for demos only: don't encrypt real secrets with them.** Both are run by the same
organisation, so the split across servers protects nothing yet, and they come with no availability or backup
guarantees.

For the local stack with its own servers (expiry and revocation scripts), see [../local/README.md](../local/README.md).

## What's used

| Component | Where |
|---|---|
| shares server 1 | `https://share1-ruhnu.duckdns.org`, Oracle Cloud, run by the Ruhnu team |
| shares server 2 | `https://share2-ruhnu.cyber.ee`, run by the Ruhnu team |
| CLI | `ghcr.io/ruhnu/ruhnu-cli:dev-did-1` (OpenSpec changes `add-cli-container-image` and `add-did-recipient`) |
| `ssh-agent` | yours, its socket mounted into the container for decryption |
| DID hosts | `jann0k.github.io` and `ruhnu.github.io` (GitHub Pages), for DID recipients |

Both servers run image tag `dev-did-1` with SSH public key and DID recipients enabled, and allow DIDs on
`jann0k.github.io` and `ruhnu.github.io` only (`RUHNU_DID_ALLOWED_HOSTS=jann0k.github.io,ruhnu.github.io`).
`ruhnu/pk/` shares live 14 days by default and at most; `ruhnu/did/` shares 3 years by default and at most 5,
since access to them can be revoked through the DID document. A shorter lifetime can be requested with
`--share-expiry`. Both servers have Let's Encrypt certificates.

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
- The image is `RUHNU_CLI_IMAGE`, `ghcr.io/ruhnu/ruhnu-cli:dev-did-1` unless set before sourcing.
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

## 4. DID recipients: revoke by editing a document

### What a DID is

A DID ([Decentralized Identifier](https://www.w3.org/TR/did-core/)) is an identifier you control that points
to a small JSON file, the *DID document*, listing your public keys. A `did:web` DID
([method spec](https://w3c-ccg.github.io/did-method-web/)) is the simplest kind: it is a web address, and the
document is a file on a website you control. Colons after the host name become path segments, and a DID
without a path uses `/.well-known/did.json`:

| DID | DID document |
|---|---|
| `did:web:alice.github.io` | `https://alice.github.io/.well-known/did.json` |
| `did:web:ruhnu.github.io:alice` | `https://ruhnu.github.io/alice/did.json` |

**Why use one here.** You encrypt to a DID instead of to a `.pub` line. `create --did` fetches the DID
document and pins each P-256 key listed under `authentication` by its fingerprint. On every decryption, each
shares server fetches the document again and releases its share only while the key is still listed. So you
revoke access yourself, on both servers at once, by removing the key from the document; no one has to delete
shares on the servers. Whoever controls the website can withdraw access, but can't add a key that opens
existing containers, because those pin the fingerprint.

### Which DID hosts the live servers accept

The servers fetch DID documents only from hosts on their allowlist, so that nobody can make them send
requests to arbitrary sites. Today that is `jann0k.github.io` and `ruhnu.github.io`. Until your own host is
allowed, ask the Ruhnu team for a path on `ruhnu.github.io` (`did:web:ruhnu.github.io:<you>`). Allowing every
`*.github.io` site, so that anyone can use their own GitHub Pages site, is implemented on cdoc2-shares-server
branch `feat/did-wildcard-hosts` but not deployed yet.

### Publish a DID document on GitHub Pages

[GitHub Pages](https://docs.github.com/en/pages/quickstart) serves the files of a repository as a website. A
repository named `<username>.github.io` is served at `https://<username>.github.io`, so your DID is
`did:web:<username>.github.io`. A working example, serving `did:web:jann0k.github.io`:
[jann0k/jann0k.github.io](https://github.com/jann0k/jann0k.github.io/tree/main).

1. Create a public repository named exactly `<username>.github.io`, as in GitHub's
   [Creating a GitHub Pages site](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site).
   Under *Settings → Pages*, the source should be *Deploy from a branch*, branch `main`, folder `/ (root)`.
2. Clone it, and make Pages publish the `.well-known` directory. By default Pages builds the site with Jekyll,
   which [skips files and directories that start with a dot](https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll).
   Either add a `_config.yml` containing `include: [".well-known"]`, as the example does, or an empty
   `.nojekyll` file, which turns Jekyll off.
3. Write the DID document from your public key with `make-did-json.py` from this repository's `local/`
   directory (with the local demo; it reaches `main` when the DID demo is merged):

   ```shell
   cd <username>.github.io
   mkdir -p .well-known
   python3 ~/workspace/ruhnu-workspace/ruhnu-demo/local/make-did-json.py \
     did:web:<username>.github.io ~/.ssh/id_ecdsa_cdoc2.pub > .well-known/did.json
   ```

   It lists each key as a `JsonWebKey2020` with its P-256 coordinates under `authentication`. To find the key
   in the document by the fingerprint `ssh-add -l` shows, you can rename its id from `#key-0` to
   `#SHA256:<fingerprint>`, in `verificationMethod` and in `authentication`, as the example does. The id is
   only a label: what counts is the fingerprint computed from the key, which `create` prints.
4. Commit and push. Pages deploys within about a minute (the repository's *Actions* tab shows a
   *pages build and deployment* run). Then check that the document is served:

   ```shell
   curl -s https://<username>.github.io/.well-known/did.json
   ```

For a DID with a path, such as `did:web:ruhnu.github.io:alice`, put the file at `alice/did.json` instead; no
dot directory is involved.

### Encrypt, inspect, decrypt

Use the DID from your document:

```shell
ruhnu create --did did:web:ruhnu.github.io:alice -f did.cdoc2 secret.env
#   Pinned ruhnu/did/did:web:ruhnu.github.io:alice/hash/… (SHA256:…)   <- check it against ssh-add -l
ruhnu info -f did.cdoc2
rm -rf out && mkdir out && ruhnu decrypt --ssh-agent -f did.cdoc2 -o out
```

- `create` trusts the DID host at that moment: check the pinned fingerprints it prints. It fetches the document
  with the CA certificates of the image's Java, not with `live/config/truststore.jks`, which is only for the
  shares servers.
- `info` shows `SSH key via DID: … DID did:web:…, key SHA256:…`.
- `--did` is repeatable and combines with `--ssh-pubkey`.

### Revoke and restore

Set `"authentication": []` in the document, then commit and push it. Once GitHub Pages serves the
new version, usually within a minute, decryption is refused by both servers:

```
ERROR: Shares server https://share1-ruhnu.duckdns.org refused share ID …: the share was not found, has expired, or the key is no longer listed in the DID document of did:web:ruhnu.github.io:alice
```

Put the key back and publish again, and decryption works again. Containers pin fingerprints, so a key you
rotate away must stay listed until the containers encrypted to it are re-encrypted.

### DID host outage

If a server can't reach the DID host, decryption fails with
`Shares server … could not reach the DID host of did:web:…; try again later` (503), and works again once the
host is reachable. The Ruhnu team can simulate this on a server for demos.

## Revoking SSH key recipients

Revoking a `ruhnu/pk/` recipient before its shares expire means deleting its share on at least one server, in
the database. On the live servers only the Ruhnu team, which runs both, can do that; there is no
self-service API, so it is not part of this walkthrough. The local stack shows it: `../local/revoke.sh`.
For self-service revocation, use a DID recipient (section 4).

## Verified

2026-11-11, from the ruhnu sandbox with `dev-cli-image-1`: truststore from the ISRG roots, `create` with
`--share-expiry PT10M` to a throwaway P-256 key, `info`, and `decrypt --ssh-agent` through a throwaway
agent, against share1 and share2. The decrypted file matched and was owned by the host user. After the 10 minutes,
decryption was refused: `Shares server https://share1-ruhnu.duckdns.org refused nonce for share ID …: share
not found (expired or deleted)`.

2026-11-11, with both servers and the CLI on `dev-did-1`:
- From the ruhnu sandbox: the servers refuse an unknown `ruhnu/` recipient kind and a DID on a host that is not
  allowed (`400`). `create --did did:web:jann0k.github.io` pinned the listed key and `info` showed it. An agent
  with another key got `No matching key found in ssh-agent`, and a validly signed DID token for that other key
  was refused by both servers (`404`, `../local/AttackerFetch.java`). The same SSH public key round trip as
  above passed with `dev-did-1`.
- From a laptop with the listed key: `decrypt --ssh-agent` worked, and failed with `could not reach the DID
  host` (`503`, naming share2) while share2 was cut off from the DID host.
