# toy-deploy

A toy deployment whose secrets are committed only encrypted, as `secret.env.cdoc2`. `docker compose up`
decrypts them through the ssh-agent of whoever deploys, usually forwarded from their laptop with `ssh -A`, and
nginx serves a page that shows them. Nothing on the server can start the service without a key holder's agent.

This repository is public, so anyone can download `secret.env.cdoc2`, but only its recipients can decrypt it.
It uses the live shares servers (share1 and share2) and the `ghcr.io/ruhnu/ruhnu-cli` image, as in
[../live/README.md](../live/README.md). **Demo only: don't put real secrets here.**

| File | Purpose |
|---|---|
| `secret.env.cdoc2` | the secrets, encrypted (created by `./ruhnu encrypt`) |
| `recipients` | who can decrypt: DIDs or SSH public keys (P-256) |
| `secret.env.example` | the format: `KEY=value` lines |
| `ruhnu` | `./ruhnu decrypt`, `./ruhnu encrypt`, `./ruhnu info`, with the CLI image; needs only Docker |
| `compose.yaml` | `decrypt` (one-shot), then `web` (nginx); `secrets-holder` keeps the tmpfs volume |
| `ruhnu-cli/` | scripts run inside the CLI image: client configuration, the `decrypt` service |
| `web/render-page.sh` | nginx start hook that builds the page from the decrypted secrets |

`secret.env`, the plaintext, is ignored by git.

## How `docker compose up` decrypts

```
secrets-holder ──── keeps tmpfs volume "secrets" mounted
decrypt  (ruhnu-cli, one-shot)   secret.env.cdoc2 ──▶ /secrets/secret.env
   │ signs one auth token through /ssh-agent.sock = $SSH_AUTH_SOCK of the deployer
   │   (forwarded agent ──▶ laptop agent ──▶ confirmation dialog when the key was added with ssh-add -c)
   ▼ exit 0  (depends_on: condition: service_completed_successfully)
web  (nginx)   reads /run/secrets/secret.env, writes index.html to a tmpfs, listens on 127.0.0.1:8088
```

- **The plaintext is only in memory**: in the `secrets` volume (tmpfs) and the page (tmpfs). `docker compose
  down` or a reboot removes it, and starting again needs a key holder's agent. Nothing restarts by itself
  after a reboot.
- **`web` starts only if decryption succeeded.** Otherwise `docker compose up` stops with
  `service "decrypt" didn't complete successfully: exit 1`, and `docker compose logs decrypt` says why:
  - no agent: `decrypt: no ssh-agent (SSH_AUTH_SOCK was not set for docker compose)`
  - the dialog was denied: `ERROR: ssh-agent refused to sign`
  - the agent has no recipient's key: `ERROR: No matching key found in ssh-agent ...`
  - a revoked DID key or an expired share: `ERROR: Shares server ... refused share ID ...`
- **`ssh-add -c` works** with the forwarded agent. Each decryption, `./ruhnu decrypt` or `docker compose up`,
  asks once, on the laptop. One signed token covers both shares servers. Encryption needs no confirmation:
  it uses only public keys.
- The `decrypt` container runs as root, so that it can use the forwarded agent socket, which only its owner
  can open. sshd and ssh-agent both accept root. `./ruhnu` runs the CLI as you instead, so that
  `secret.env` belongs to you.
- A tmpfs volume loses its files as soon as no running container mounts it, which would happen between the
  end of `decrypt` and the start of `web`. That's why `secrets-holder` exists.

## Before the first demo: encrypt to your key

The committed `secret.env.cdoc2` must be encrypted to the presenter's key:

1. Put your DID in `recipients`, for example `did:web:<username>.github.io`, whose document lists your P-256
   key ([../live/README.md](../live/README.md), section 4). An SSH public key line works too, but its shares
   live at most 14 days on the live servers. After that the committed file can't be decrypted, so you'd have
   to re-encrypt it before then.
2. Encrypt the example secrets and commit:

   ```bash
   cd toy-deploy
   cp secret.env.example secret.env
   ./ruhnu encrypt      # prints the pinned key fingerprints: check them against ssh-add -l
   ./ruhnu info
   rm secret.env
   git add recipients secret.env.cdoc2 && git commit -m "toy-deploy: secrets for <name>" && git push
   ```

On the VM, the user needs Docker without `sudo` (`docker` group), and port 8088 must be free. Use
`TOY_PORT=<port> docker compose up -d` for another port. To pull the images before the demo, run
`docker compose pull` in `toy-deploy` there.

## The demo

### Laptop

```bash
# 1. agent with confirmation: ruhnu-ops README-ssh.md, "Quick test" (needs ssh-askpass)
#    https://github.com/ruhnu/ruhnu-ops/blob/main/README-ssh.md#quick-test
eval $(ssh-agent)
ssh-add -c ~/.ssh/id_ecdsa_cdoc2       # the key in your DID document
ssh-add -c ~/.ssh/<github key>         # for git push
ssh-add -c ~/.ssh/<share2 login key>   # if it's another key

# 2.
git clone git@github.com:ruhnu/ruhnu-demo.git && cd ruhnu-demo/toy-deploy

# 3. dialog: allow the key
./ruhnu decrypt && cat secret.env

# 4.
nano secret.env                        # change a value, add a KEY=value line

# 5. no dialog: encryption uses public keys only
./ruhnu encrypt && rm secret.env

# 6. commits only the encrypted file; dialog for the GitHub key
git commit -m "toy-deploy: change the secrets" secret.env.cdoc2 && git push

# 7. agent forwarding, plus a tunnel for the browser
ssh -A -L 8088:localhost:8088 ubuntu@192.168.145.46     # share2; or "ssh -L 8088:localhost:8088 share2-ruhnu"
                                                        # with README-ssh.md section 3, which forwards the agent
```

With README-ssh.md section 3, `share2-ruhnu` uses the agent socket of that section, not the agent started
in step 1. In that case, `export SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent-confirm.socket` instead of
`eval $(ssh-agent)`.

### VM

```bash
git clone https://github.com/ruhnu/ruhnu-demo.git && cd ruhnu-demo/toy-deploy     # public: no key needed
./ruhnu decrypt && cat secret.env      # dialog: the same secrets, decrypted on the VM
rm secret.env
docker compose up -d                   # dialog: the decrypt service; web starts after it
docker compose logs decrypt
```

Open <http://localhost:8088> on the laptop. The page shows the edited values.

The page is bound to `127.0.0.1` on the VM, so only the SSH tunnel reaches it.

### Optional extras

- **Locked without you:** `docker compose down`, log in again *without* `-A`, then `docker compose up -d`:
  `decrypt` fails with "no ssh-agent" and `web` doesn't start.
- **Deny the dialog:** `docker compose up -d --force-recreate` and click *Deny*. `decrypt` fails with
  `ssh-agent refused to sign`, and the page goes down: `web` is recreated, but not started.
- **Revoke:** remove the key from your DID document (`"authentication": []`) and push. About a minute later,
  `docker compose up -d --force-recreate` fails with `refused share ID`, and the page goes down. Put the key
  back to restore access.

### After changing the secrets

`git pull`, then `docker compose up -d --force-recreate`. A plain `docker compose up -d` decrypts again, but
doesn't restart `web`, which still shows the old values.

## Notes

- **While you're logged in with `-A`, root on the VM can ask your agent to sign**, and so can every member of
  the `docker` group, which is root-equivalent. That's why the keys are added with `-c`. The dialog shows the
  key, not what is being signed, so deny any dialog you didn't cause.
- Root on the VM can also read the running service's secrets. That's true of any deployment; this only
  keeps them off the disk and out of git.
- Other shares servers: set `RUHNU_CONFIG_DIR` to a directory with `key-shares.properties` and its truststore,
  for `./ruhnu`. For compose, mount that directory at `/config` in `decrypt` (see `ruhnu-cli/cli.sh`).

## Tested

2026-11-12, in the ruhnu sandbox, against the local stack in [../local](../local/README.md) (two shares
servers and a DID host) instead of share1 and share2, with `ghcr.io/ruhnu/ruhnu-cli:latest`. An ssh-agent held
the demo key added with `ssh-add -c`, with an askpass that logged each confirmation. This was before the
directory moved into ruhnu-demo; the scripts are unchanged.

- `./ruhnu encrypt`, `info` and `decrypt` worked for a DID and an SSH key recipient, one confirmation per
  decryption.
- `docker compose up -d` started `web` only after `decrypt` had exited 0. The page showed the values,
  HTML-escaped. The plaintext was only on the two tmpfs mounts, and in neither container's writable layer.
- With no agent, a denied dialog, or an agent without the key, `decrypt` failed with the messages above, and
  `web` was not started.
- Through `ssh -A` into an sshd container sharing the host's Docker daemon, standing in for the VM:
  `./ruhnu decrypt` and `docker compose up -d` each asked once on the laptop-side agent, and the page was
  served. It was still served after logging out.
- After a re-encrypted change, `up -d --force-recreate` showed the new value. With the dialog denied, it
  left `web` created but not started.
