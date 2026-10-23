#!/usr/bin/env bash
# Create cluster secrets once. Existing secrets are never overwritten, so this
# is safe to re-run (e.g. after adding the Cloudflare token).
set -euo pipefail
cd "$(dirname "$0")/.."

rand() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
exists() { kubectl -n "$1" get secret "$2" >/dev/null 2>&1; }
create() { # namespace name --from-literal...
  local ns=$1 name=$2; shift 2
  if exists "$ns" "$name"; then echo "secret $ns/$name exists, leaving it"; return; fi
  kubectl -n "$ns" create secret generic "$name" "$@" >/dev/null
  echo "secret $ns/$name created"
}

kubectl apply -f base/namespace.yaml -f edge/namespace.yaml -f control/namespace.yaml >/dev/null

create stagecoach mariadb \
  --from-literal=password="$(rand 32)" --from-literal=root-password="$(rand 32)"
create stagecoach drupal \
  --from-literal=hash-salt="$(rand 64)" --from-literal=admin-password="$(rand 24)"
redis_pw=$(rand 32)
create stagecoach redis-auth \
  --from-literal=password="$redis_pw" --from-literal=auth.conf="requirepass $redis_pw"

# Stagecoach: Basic auth for its own UI, and the API token the Drupal module
# sends. The token lives in both namespaces — stage-coach checks it, Drupal reads
# it as STAGE_COACH_API_TOKEN — so it is minted once and copied, never re-minted
# on one side only.
create stage-coach stage-coach \
  --from-literal=auth="admin:$(rand 32)" --from-literal=api-token="$(rand 48)"
if ! exists stagecoach stage-coach-api; then
  kubectl -n stage-coach get secret stage-coach -o jsonpath='{.data.api-token}' | base64 -d \
    | kubectl -n stagecoach create secret generic stage-coach-api --from-file=token=/dev/stdin >/dev/null
  echo "secret stagecoach/stage-coach-api created (copy of the Stagecoach API token)"
fi

token_file=secrets/cloudflare-api-token
if [ -s "$token_file" ]; then
  token=$(tr -d '[:space:]' < "$token_file")
  kubectl -n stagecoach-edge create secret generic cloudflare-api-token \
    --from-literal=token="$token" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "secret stagecoach-edge/cloudflare-api-token applied from $token_file"
else
  echo "NOTE: $token_file is missing; the edge Caddy will wait for it." >&2
fi
