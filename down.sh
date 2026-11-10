#!/usr/bin/env bash
# Stop the demo environment: shares servers, ssh-agents, PostgreSQL and DID host containers. Keeps run/ logs.
set -uo pipefail
source "$(dirname "$0")/env.sh"

for server in "${SERVERS[@]}"; do
    read -r name _ _ pg_port <<<"$server"
    # match by this demo's properties file, so servers are found even if the pid file is stale
    if pkill -f -- "$RUN_DIR/$name.properties" 2>/dev/null; then
        for _ in $(seq 1 30); do
            pgrep -f -- "$RUN_DIR/$name.properties" >/dev/null || break
            sleep 1
        done
        echo "stopped $name"
    fi
    rm -f "$RUN_DIR/$name.pid"
    docker rm -f "ruhnu-demo-db-$pg_port" >/dev/null 2>&1 && echo "removed ruhnu-demo-db-$pg_port"
done

docker rm -f "$DID_HOST_CONTAINER" >/dev/null 2>&1 && echo "removed $DID_HOST_CONTAINER"
if [[ -f "$RUN_DIR/mallory-agent.env" ]]; then
    (source "$RUN_DIR/mallory-agent.env" >/dev/null && ssh-agent -k >/dev/null 2>&1) && echo "stopped Mallory's ssh-agent"
    rm -f "$RUN_DIR/mallory-agent.env" "$RUN_DIR/mallory.sock" "$RUN_DIR/mallory" "$RUN_DIR/mallory.pub"
fi

if [[ -f "$RUN_DIR/agent.env" ]]; then
    # shellcheck disable=SC1091
    (source "$RUN_DIR/agent.env" >/dev/null && ssh-agent -k >/dev/null 2>&1) && echo "stopped ssh-agent"
    rm -f "$RUN_DIR/agent.env" "$DEMO_AGENT_SOCK"
fi
rm -f "$DEMO_KEY" "$DEMO_KEY.pub"
