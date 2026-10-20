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
# Builds run at the lowest priority with a soft memory cap: a full-speed build
# on this 1-vCPU host once starved k3s's datastore and made it restart.
low_prio=(systemd-run --scope --quiet -p CPUWeight=10 -p IOWeight=10 -p MemoryHigh=768M nice -n 19 ionice -c 3)
"${low_prio[@]}" buildah build --layers --pull=missing -f docker/caddy/Dockerfile -t "$ref" docker/caddy
buildah push "$ref" "docker-archive:$work/caddy.tar:$ref"
k3s ctr -n k8s.io images import "$work/caddy.tar" >/dev/null
sed -i "\#name: localhost/stagecoach/caddy\$#{n;s#newTag: .*#newTag: \"$TAG\"#}" edge/kustomization.yaml
echo ">> imported $ref and pinned it in edge/kustomization.yaml"
