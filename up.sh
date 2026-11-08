#!/usr/bin/env bash
# Bring up the demo environment:
#  - two PostgreSQL containers and two cdoc2-shares-server instances (N_OF_N), with cdoc2.ruhnu.enabled=true,
#    ruhnu/pk/ share lifetime $SHARE_LIFETIME and the expired share clean-up job disabled
#  - a demo ssh-agent holding a fresh ECDSA P-256 key
#  - key-shares.properties for cdoc2-cli
# Run ./build.sh first.
set -euo pipefail
source "$(dirname "$0")/env.sh"

[[ -f "$SERVER_JAR" && -f "$CLI_JAR" ]] || fail "jars missing, run ./build.sh first"
for cmd in docker java mvn ssh-agent ssh-keygen ssh-add; do
    command -v "$cmd" >/dev/null || fail "$cmd not found"
done

"$DEMO_DIR/down.sh" >/dev/null 2>&1 || true
mkdir -p "$RUN_DIR"

for server in "${SERVERS[@]}"; do
    read -r name port mgmt_port pg_port <<<"$server"

    step "$name: PostgreSQL on port $pg_port"
    docker run -d --name "ruhnu-demo-db-$pg_port" -p "$pg_port:5432" \
        -e POSTGRES_DB=cdoc2-shares -e POSTGRES_PASSWORD=secret postgres:14.17 >/dev/null
    for _ in $(seq 1 60); do
        docker exec "ruhnu-demo-db-$pg_port" pg_isready -U postgres -q 2>/dev/null && break
        sleep 1
    done
    sleep 2
    (cd "$SHARES_SERVER_REPO/server-db" && mvn -B -q liquibase:update \
        -Dliquibase.url="jdbc:postgresql://localhost:$pg_port/cdoc2-shares" >/dev/null)
    ok "$name database migrated"

    cat >"$RUN_DIR/$name.properties" <<EOF
# demo overrides on top of cdoc2-shares-server/shares-server/config/application-local.properties
server.port=$port
management.server.port=$mgmt_port
spring.datasource.url=jdbc:postgresql://localhost:$pg_port/cdoc2-shares
logging.level.ee.cyber.cdoc2=info
cdoc2.ruhnu.enabled=true
cdoc2.ruhnu.pk.default-expiration-duration=$SHARE_LIFETIME
cdoc2.ruhnu.pk.max-expiration-duration=$SHARE_LIFETIME
# disabled, to show that expired shares are refused before they are deleted
key-share.expired.clean-up.cron=-
EOF

    step "$name: cdoc2-shares-server on https://localhost:$port"
    # application-local.properties uses paths relative to shares-server/. Only java is put in the background,
    # so that $! is the java pid and no helper shell keeps this script's stdout open.
    (
        cd "$SHARES_SERVER_REPO/shares-server"
        nohup java \
            -Dspring.config.location="file:config/application-local.properties,file:$RUN_DIR/$name.properties" \
            -jar "$SERVER_JAR" </dev/null >"$RUN_DIR/$name.log" 2>&1 &
        echo $! >"$RUN_DIR/$name.pid"
    )
done

for server in "${SERVERS[@]}"; do
    read -r name port _ _ <<<"$server"
    for _ in $(seq 1 120); do
        grep -q "Started Cdoc2KeySharesServerApplication" "$RUN_DIR/$name.log" 2>/dev/null && break
        kill -0 "$(cat "$RUN_DIR/$name.pid")" 2>/dev/null || fail "$name exited, see $RUN_DIR/$name.log"
        sleep 1
    done
    grep -q "Started Cdoc2KeySharesServerApplication" "$RUN_DIR/$name.log" || fail "$name did not start"
    ok "$name started (log: $RUN_DIR/$name.log)"
done

step "demo ssh-agent with an ECDSA P-256 key"
# ssh-agent keeps the inherited stderr open, which would block a caller reading this script's output
ssh-agent -a "$DEMO_AGENT_SOCK" </dev/null >"$RUN_DIR/agent.env" 2>"$RUN_DIR/agent.log"
ssh-keygen -q -t ecdsa -b 256 -N '' -C "ruhnu-demo" -f "$DEMO_KEY"
SSH_AUTH_SOCK="$DEMO_AGENT_SOCK" ssh-add -q "$DEMO_KEY"
SSH_AUTH_SOCK="$DEMO_AGENT_SOCK" ssh-add -l
ok "agent socket $DEMO_AGENT_SOCK"

urls=""
for server in "${SERVERS[@]}"; do
    read -r _ port _ _ <<<"$server"
    urls="${urls:+$urls, }https://localhost:$port"
done
cat >"$KEY_SHARES_PROPERTIES" <<EOF
key-shares.servers.urls=$urls
key-shares.servers.min_num=${#SERVERS[@]}
key-shares.algorithm=n-of-n
cdoc2.key-shares.client.ssl.trust-store=$REF_IMPL_REPO/cdoc2-cli/config/localhost/clienttruststore.jks
cdoc2.key-shares.client.ssl.trust-store.type=JKS
cdoc2.key-shares.client.ssl.trust-store-password=passwd
key-shares.client.read-timeout=5000
key-shares.client.connect-timeout=5000
EOF
ok "cdoc2-cli key-shares.properties: $KEY_SHARES_PROPERTIES"

step "environment is up"
echo "share lifetime: $SHARE_LIFETIME, stop with ./down.sh"
