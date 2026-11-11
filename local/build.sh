#!/usr/bin/env bash
# Build everything the demo needs from the feat/add-ssh-pk-recipient branches, in dependency order.
# Artifacts are installed into the local Maven repository (~/.m2), nothing is deployed.
set -euo pipefail
source "$(dirname "$0")/env.sh"

for repo in cdoc2-openapi cdoc2-auth cdoc2-java-ref-impl cdoc2-shares-server; do
    branch=$(git -C "$WORKSPACE/$repo" branch --show-current)
    if [[ "$branch" != "feat/add-ssh-pk-recipient" ]]; then
        echo "WARNING: $repo is on branch '$branch', not feat/add-ssh-pk-recipient" >&2
    fi
done

step "cdoc2-openapi"
(cd "$WORKSPACE/cdoc2-openapi" && mvn -B -q install)
step "cdoc2-auth"
(cd "$WORKSPACE/cdoc2-auth" && mvn -B -q install -DskipTests)
step "cdoc2-java-ref-impl (schema, client, lib, cli)"
(cd "$REF_IMPL_REPO" && mvn -B -q install -DskipTests -pl cdoc2-schema,cdoc2-client,cdoc2-lib,cdoc2-cli)
step "cdoc2-shares-server"
(cd "$SHARES_SERVER_REPO" && mvn -B -q install -DskipTests)

ls -l "$SERVER_JAR" "$CLI_JAR"
ok "build done"
