# ruhnu-demo

End-to-end demos of CDOC2 SSH public key recipients (`ruhnu/pk/`): encrypt a secret to an SSH key and decrypt
it through `ssh-agent`.

| Directory | What |
|---|---|
| [local/](local/README.md) | two shares servers and a demo ssh-agent on this machine, built from the repositories next to `ruhnu-demo`. Scripts for encryption, expiry and revocation |
| [live/](live/README.md) | the live shares servers `share1-ruhnu.duckdns.org` and `share2-ruhnu.cyber.ee` with the published CLI image `ghcr.io/ruhnu/ruhnu-cli`. Nothing to build. Revocation is not covered |
