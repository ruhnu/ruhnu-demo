# ruhnu-demo

End-to-end demos of CDOC2 SSH key recipients: SSH public key recipients (`ruhnu/pk/`) and DID recipients
(`ruhnu/did/`). Encrypt a secret to an SSH key, or to the keys a `did:web` DID document lists, and decrypt it
through `ssh-agent`.

| Directory | What |
|---|---|
| [local/](local/README.md) | two shares servers, a DID host and a demo ssh-agent on this machine, built from the repositories next to `ruhnu-demo`. Scripts for encryption, expiry and revocation, and for DID recipients |
| [live/](live/README.md) | the live shares servers `share1-ruhnu.duckdns.org` and `share2-ruhnu.cyber.ee` with the published CLI image `ghcr.io/ruhnu/ruhnu-cli`. Nothing to build. Revocation is not covered |
| [toy-deploy/](toy-deploy/README.md) | a toy deployment whose secrets are committed only encrypted: `docker compose up` decrypts them through the deployer's forwarded ssh-agent, then starts nginx. Uses the live servers |
