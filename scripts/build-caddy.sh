#!/usr/bin/env bash
# Build the edge Caddy image (with the Cloudflare DNS plugin) using buildah,
# import it into k3s's containerd, and pin the tag in edge/kustomization.yaml.
# The Drupal image is built from the stagecoach_d12app repo (scripts/build.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

sha=$(git rev-parse --short HEAD)
dirty=$(git status --porcelain | grep -q . && echo -dirty || true)
TAG=${TAG:-$(date -u +%Y%m%d%H%M)-${sha}${dirty}}
ref="localhost/stagecoach/caddy:$TAG"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

echo ">> building $ref"
buildah build --layers --pull=missing -f docker/caddy/Dockerfile -t "$ref" docker/caddy
buildah push "$ref" "docker-archive:$work/caddy.tar:$ref"
k3s ctr -n k8s.io images import "$work/caddy.tar" >/dev/null
sed -i "\#name: localhost/stagecoach/caddy\$#{n;s#newTag: .*#newTag: \"$TAG\"#}" edge/kustomization.yaml
echo ">> imported $ref and pinned it in edge/kustomization.yaml"
