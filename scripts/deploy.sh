#!/usr/bin/env bash
# Apply both kustomizations and wait for the rollouts.
set -euo pipefail
cd "$(dirname "$0")/.."

kubectl apply -k base
kubectl apply -k edge
for w in statefulset/mariadb deploy/redis deploy/drupal deploy/varnish; do
  kubectl -n stagecoach rollout status "$w" --timeout=300s
done
if kubectl -n stagecoach-edge get secret cloudflare-api-token >/dev/null 2>&1; then
  kubectl -n stagecoach-edge rollout status deploy/caddy --timeout=180s
fi
