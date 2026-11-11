# ruhnu-demo: local stack

End-to-end demo of CDOC2 SSH public key recipients (`ruhnu/pk/`): encrypt a secret to an SSH key, decrypt it
through `ssh-agent`, watch access end when the key shares expire, and revoke access early by deleting a share on
one server. Everything runs locally.

It belongs to the OpenSpec change `add-ssh-pk-recipient` (ruhnu-openspec), tasks 6.1–6.3.

## What runs

| Component                      | Where                                                              |
|--------------------------------|--------------------------------------------------------------------|
| shares server 1                | `https://localhost:8443`, PostgreSQL container on port 55441       |
| shares server 2                | `https://localhost:8442`, PostgreSQL container on port 55442       |
| `ssh-agent`                    | `run/agent.sock`, holding a fresh ECDSA P-256 key `run/demo_key`   |
| `cdoc2-cli`                    | `java -jar …/cdoc2-cli-1.10.0-SNAPSHOT.jar`, config `run/key-shares.properties` |

Both shares servers run with `cdoc2.ruhnu.enabled=true`. `ruhnu/pk/` shares live for `SHARE_LIFETIME`
(default `PT2M`, so the expiry step takes about two minutes), and the expired share clean-up job is disabled,
to show that expired shares are refused before they are deleted. The demo uses its own `ssh-agent`; your own
agent is not touched.

## Prerequisites

- Java 21, Maven, Docker (the user can run `docker` without sudo), OpenSSH client (`ssh-agent`, `ssh-add`,
  `ssh-keygen`)
- these repositories next to `ruhnu-demo`, on branch `feat/add-ssh-pk-recipient`:
  `cdoc2-openapi`, `cdoc2-auth`, `cdoc2-java-ref-impl`, `cdoc2-shares-server`.
  Set `WORKSPACE` if they are somewhere else.
- free ports 8442, 8443, 18442, 18443, 55441, 55442

## Run

```shell
./build.sh    # build and install the four repositories (mvn install -DskipTests)
./up.sh       # two databases, two shares servers, demo ssh-agent; about 20 s
./demo.sh     # 6.2: encrypt, decrypt, audit log, expiry
./revoke.sh   # 6.3: revoke on one server
./down.sh     # stop everything (logs stay in run/)
```

`SHARE_LIFETIME=PT5M ./up.sh` sets a different share lifetime.

## What the scripts check

`demo.sh`
1. encrypts `secret.env` to the demo key and shows the recipient (`cdoc2 info`) and the share stored on each server
2. decrypts through `ssh-agent` and compares the result
3. checks that both servers logged the release: `Key share released: shareId=…, recipient=ruhnu/pk:SHA256:…`
4. waits until the shares expire and checks that decryption is refused, with the refusing server named
5. checks that the expired rows are still in both databases, so the refusal comes from the expiry check, not
   from the clean-up job

`revoke.sh`
1. encrypts and decrypts a fresh secret
2. deletes the recipient's share on server 1 only (SQL; the share's nonces first, they reference it)
3. checks that decryption now fails at once, naming server 1, while server 2 still holds its share: with
   N-of-N shares, deleting on one server is enough to revoke

Each script stops with `FAIL: …` and a non-zero exit code if a check fails. Server logs are in
`run/server1.log` and `run/server2.log`.

## Using the demo stack by hand

```shell
export SSH_AUTH_SOCK=$PWD/run/agent.sock
CLI=../../cdoc2-java-ref-impl/cdoc2-cli/target/cdoc2-cli-1.10.0-SNAPSHOT.jar
java -jar $CLI create -Dkey-shares.properties=run/key-shares.properties \
    --ssh-pubkey run/demo_key.pub -f /tmp/secret.cdoc2 README.md
mkdir -p /tmp/out
java -jar $CLI decrypt -Dkey-shares.properties=run/key-shares.properties \
    --ssh-agent -f /tmp/secret.cdoc2 -o /tmp/out
```

The servers also match `cdoc2-cli/config/localhost/key-shares.properties` in cdoc2-java-ref-impl, so the
examples in the cdoc2-cli README work against this stack as well.
