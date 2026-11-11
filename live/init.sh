# Client setup for the live shares servers. Source it (bash):
#
#   source live/init.sh
#
# Creates the configuration directory if missing: key-shares.properties for share1 and share2, and
# truststore.jks with the Let's Encrypt roots. Then defines `ruhnu <command> <options>`, which runs the CLI
# image as you, with the current directory at /work, the configuration directory at /config and your
# ssh-agent socket.
#
# Environment, read when sourcing:
#   RUHNU_CONFIG_DIR  configuration directory (default live/config, next to this script), for example
#                     RUHNU_CONFIG_DIR=~/.config/cdoc2 source live/init.sh
#   RUHNU_CLI_IMAGE   CLI image (default ghcr.io/ruhnu/ruhnu-cli:dev-cli-image-1)
# Sourced into your shell, so no `set -e`: errors return instead of exiting.
#
# The values are copied to _RUHNU_CONFIG_DIR and _RUHNU_CLI_IMAGE, which `ruhnu` uses: bash undoes a
# `VAR=value source ...` assignment once `source` returns. Source again to change them.

_RUHNU_CONFIG_DIR="${RUHNU_CONFIG_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config}"
# docker -v needs an absolute path
case "$_RUHNU_CONFIG_DIR" in
    /*) ;;
    *) _RUHNU_CONFIG_DIR="$PWD/$_RUHNU_CONFIG_DIR" ;;
esac
_RUHNU_CLI_IMAGE="${RUHNU_CLI_IMAGE:-ghcr.io/ruhnu/ruhnu-cli:dev-cli-image-1}"
export _RUHNU_CONFIG_DIR _RUHNU_CLI_IMAGE

_ruhnu_init() {
    mkdir -p "$_RUHNU_CONFIG_DIR" || return 1

    local props="$_RUHNU_CONFIG_DIR/key-shares.properties"
    if [ ! -f "$props" ]; then
        # paths are paths in the container: the configuration directory is mounted at /config
        cat > "$props" <<'EOF'
key-shares.servers.urls=https://share1-ruhnu.duckdns.org, https://share2-ruhnu.cyber.ee
key-shares.servers.min_num=2
key-shares.algorithm=n-of-n
cdoc2.key-shares.client.ssl.trust-store=/config/truststore.jks
cdoc2.key-shares.client.ssl.trust-store.type=JKS
cdoc2.key-shares.client.ssl.trust-store-password=changeit
EOF
        echo "created $props"
    fi

    # The client trusts only its truststore, not the JDK's CAs. It holds public CA certificates only, so the
    # password protects nothing. keytool comes from the CLI image, so no local Java is needed.
    local truststore="$_RUHNU_CONFIG_DIR/truststore.jks"
    if [ ! -f "$truststore" ]; then
        local root
        for root in isrgrootx1 isrg-root-x2; do
            if ! curl -fsSo "$_RUHNU_CONFIG_DIR/$root.pem" "https://letsencrypt.org/certs/$root.pem" \
                || ! docker run --rm --user "$(id -u):$(id -g)" -v "$_RUHNU_CONFIG_DIR:/config" \
                    --entrypoint keytool "$_RUHNU_CLI_IMAGE" -importcert -noprompt -alias "$root" \
                    -file "/config/$root.pem" -keystore /config/truststore.jks -storepass changeit >/dev/null
            then
                echo "init.sh: could not add $root to $truststore" >&2
                rm -f "$truststore"
                return 1
            fi
        done
        echo "created $truststore"
    fi
}

ruhnu() {
    local cmd="$1"; shift
    local agent=()
    if [ -n "${SSH_AUTH_SOCK:-}" ]; then
        agent=(-v "$SSH_AUTH_SOCK:/ssh-agent.sock" -e SSH_AUTH_SOCK=/ssh-agent.sock)
    fi
    docker run --rm --user "$(id -u):$(id -g)" \
        -v "$PWD:/work" -v "$_RUHNU_CONFIG_DIR:/config:ro" "${agent[@]}" \
        "$_RUHNU_CLI_IMAGE" "$cmd" -Dkey-shares.properties=/config/key-shares.properties "$@"
}
export -f ruhnu

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    _ruhnu_init && echo "configuration ready; to define ruhnu in your shell: source $0"
    exit
fi
_ruhnu_init && echo "ruhnu ready: image $_RUHNU_CLI_IMAGE, config $_RUHNU_CONFIG_DIR"
