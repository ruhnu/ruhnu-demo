# Common settings for the ruhnu SSH public key recipient demo. Sourced by the other scripts.

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# repositories are expected next to ruhnu-demo, on branch feat/add-ssh-pk-recipient
WORKSPACE="${WORKSPACE:-$(cd "$DEMO_DIR/../.." && pwd)}"
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

export LANG=C.UTF-8

cdoc2() {
    java -jar "$CLI_JAR" "$@"
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
