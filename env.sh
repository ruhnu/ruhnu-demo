# Common settings for the ruhnu SSH public key and DID recipient demo. Sourced by the other scripts.

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# repositories are expected next to ruhnu-demo, on branch $DEMO_BRANCH
DEMO_BRANCH="${DEMO_BRANCH:-feat/add-did-recipient}"
WORKSPACE="${WORKSPACE:-$(cd "$DEMO_DIR/.." && pwd)}"
SHARES_SERVER_REPO="$WORKSPACE/cdoc2-shares-server"
REF_IMPL_REPO="$WORKSPACE/cdoc2-java-ref-impl"

RUN_DIR="$DEMO_DIR/run"

# lifetime of ruhnu/pk/ shares on the demo servers (default and max), ISO-8601 duration
SHARE_LIFETIME="${SHARE_LIFETIME:-PT2M}"

# shares servers: name, HTTPS port, management port, PostgreSQL port
SERVERS=("server1 8443 18443 55441" "server2 8442 18442 55442")

SERVER_JAR="$SHARES_SERVER_REPO/shares-server/target/cdoc2-shares-server-0.9.0-SNAPSHOT.jar"
CLI_JAR="$REF_IMPL_REPO/cdoc2-cli/target/cdoc2-cli-1.10.0-SNAPSHOT.jar"

KEY_SHARES_PROPERTIES="$RUN_DIR/key-shares.properties"
DEMO_KEY="$RUN_DIR/demo_key"
# ssh-agent of the demo, so the user's own agent is not touched
DEMO_AGENT_SOCK="$RUN_DIR/agent.sock"

# DID recipients: an nginx DID host on https://localhost:$DID_PORT serves $DID_DOCS
DID_PORT=8444
DID="did:web:localhost%3A${DID_PORT}:p:alice"
DID_DOCS="$RUN_DIR/did-docs"
DID_DOC="$DID_DOCS/p/alice/did.json"
DID_HOST_CONTAINER="ruhnu-demo-did-host"
# trusts the shares servers' "localhost" test certificate, which the DID host reuses. cdoc2-cli and the shares
# servers fetch DID documents trusting the JVM default trust store, so both get it as javax.net.ssl.trustStore
TRUSTSTORE="$REF_IMPL_REPO/cdoc2-cli/config/localhost/clienttruststore.jks"
TRUSTSTORE_JVM=(-Djavax.net.ssl.trustStore="$TRUSTSTORE" -Djavax.net.ssl.trustStorePassword=passwd
    -Djavax.net.ssl.trustStoreType=JKS)

export LANG=C.UTF-8

cdoc2() {
    java "${TRUSTSTORE_JVM[@]}" -jar "$CLI_JAR" "$@"
}

psql_on() { # psql_on <PostgreSQL port> <sql>
    docker exec "ruhnu-demo-db-$1" psql -U postgres -d cdoc2-shares -tAc "$2"
}

step() {
    printf '\n\033[1m== %s\033[0m\n' "$*"
}

fail() {
    printf '\033[31mFAIL: %s\033[0m\n' "$*" >&2
    exit 1
}

ok() {
    printf '\033[32mOK: %s\033[0m\n' "$*"
}
