#!/bin/sh
# Runs inside the ruhnu-cli image, for ../ruhnu and the compose service "decrypt": writes the client
# configuration, then runs cdoc2-cli with the given command and options.
#
# - If /config/key-shares.properties is mounted, it is used as it is (other shares servers, local tests).
# - Otherwise the configuration goes to a temporary directory in the container: share1 and share2, both
#   needed to decrypt (N-of-N), trusting only the Let's Encrypt roots ISRG Root X1 and X2, copied from the
#   image's Java CA store. This is the configuration of live/init.sh.
set -eu

props=/config/key-shares.properties
if [ ! -f "$props" ]; then
    dir="$(mktemp -d)"
    for root in letsencryptisrgx1 letsencryptisrgx2; do
        if ! keytool -importkeystore -noprompt \
                -srckeystore "$JAVA_HOME/lib/security/cacerts" -srcstorepass changeit -srcalias "$root [jdk]" \
                -destkeystore "$dir/truststore.jks" -deststoretype JKS -deststorepass changeit \
                -destalias "$root" >/dev/null 2>&1; then
            echo "cli.sh: could not copy $root from the image's CA store" >&2
            exit 1
        fi
    done
    props="$dir/key-shares.properties"
    # the truststore holds public CA certificates only, so its password protects nothing
    cat >"$props" <<EOF
key-shares.servers.urls=https://share1-ruhnu.duckdns.org, https://share2-ruhnu.cyber.ee
key-shares.servers.min_num=2
key-shares.algorithm=n-of-n
cdoc2.key-shares.client.ssl.trust-store=$dir/truststore.jks
cdoc2.key-shares.client.ssl.trust-store.type=JKS
cdoc2.key-shares.client.ssl.trust-store-password=changeit
EOF
fi

cmd="$1"
shift
exec java -jar /opt/cdoc2/cdoc2-cli.jar "$cmd" -Dkey-shares.properties="$props" "$@"
