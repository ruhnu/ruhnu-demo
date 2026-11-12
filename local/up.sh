#!/usr/bin/env bash
# Bring up the demo environment:
#  - two PostgreSQL containers and two cdoc2-shares-server instances (N_OF_N), with cdoc2.ruhnu.enabled=true,
#    ruhnu/pk/ share lifetime $SHARE_LIFETIME and the expired share clean-up job disabled
#  - an nginx DID host on https://localhost:$DID_PORT for "ruhnu/did/" recipients, allowed on both servers
#  - a demo ssh-agent holding a fresh ECDSA P-256 key
#  - key-shares.properties for cdoc2-cli
# Run ./build.sh first.
set -euo pipefail
source "$(dirname "$0")/env.sh"

[[ -f "$SERVER_JAR" && -f "$CLI_JAR" ]] || fail "jars missing, run ./build.sh first"
for cmd in docker java mvn ssh-agent ssh-keygen ssh-add openssl python3; do
    command -v "$cmd" >/dev/null || fail "$cmd not found"
done

"$DEMO_DIR/down.sh" >/dev/null 2>&1 || true
mkdir -p "$RUN_DIR"

step "DID host on https://localhost:$DID_PORT"
# reuses the shares servers' "localhost" test certificate and key
mkdir -p "$RUN_DIR/did-host-tls" "$(dirname "$DID_DOC")"
openssl pkcs12 -in "$SHARES_SERVER_REPO/keys/cdoc2server.p12" -passin pass:passwd -nokeys -clcerts \
    -out "$RUN_DIR/did-host-tls/cert.pem" 2>/dev/null
openssl pkcs12 -in "$SHARES_SERVER_REPO/keys/cdoc2server.p12" -passin pass:passwd -nocerts -nodes \
    -out "$RUN_DIR/did-host-tls/key.pem" 2>/dev/null
chmod a+r "$RUN_DIR"/did-host-tls/*.pem
python3 "$DEMO_DIR/make-did-json.py" "$DID" >"$DID_DOC"
docker run -d --name "$DID_HOST_CONTAINER" -p "127.0.0.1:$DID_PORT:$DID_PORT" \
    -v "$DEMO_DIR/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
    -v "$RUN_DIR/did-host-tls:/etc/nginx/tls:ro" \
    -v "$DID_DOCS:/usr/share/nginx/html:ro" nginx:alpine >/dev/null
ok "serving $DID_DOCS (did.sh writes the documents)"

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
# ruhnu/did/ recipients for the demo DID host
cdoc2.ruhnu.did.allowed-hosts=localhost:$DID_PORT
# disabled, to show that expired shares are refused before they are deleted
key-share.expired.clean-up.cron=-
EOF

    step "$name: cdoc2-shares-server on https://localhost:$port"
    # application-local.properties uses paths relative to shares-server/. Only java is put in the background,
    # so that $! is the java pid and no helper shell keeps this script's stdout open.
    (
        cd "$SHARES_SERVER_REPO/shares-server"
        # the server fetches DID documents trusting the JVM default trust store
        nohup java "${TRUSTSTORE_JVM[@]}" \
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
