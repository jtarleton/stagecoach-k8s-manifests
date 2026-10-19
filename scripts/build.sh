#!/usr/bin/env bash
# Build images with buildah and import them into k3s's containerd.
# Usage: scripts/build.sh [drupal|caddy|all]   (default: all)
# The new tag is written into the kustomizations; deploy with scripts/deploy.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

target=${1:-all}
sha=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
dirty=$(git status --porcelain 2>/dev/null | grep -q . && echo -dirty || true)
TAG=${TAG:-$(date -u +%Y%m%d%H%M)-${sha}${dirty}}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

build() { # name dockerfile context kustomization
  local name=$1 dockerfile=$2 context=$3 kust=$4 ref="localhost/stagecoach/$1:$TAG"
  echo ">> building $ref"
  buildah build --layers --pull=missing -f "$dockerfile" --build-arg APP_VERSION="$TAG" -t "$ref" "$context"
  buildah push "$ref" "docker-archive:$work/$name.tar:$ref"
  k3s ctr -n k8s.io images import "$work/$name.tar" >/dev/null
  rm -f "$work/$name.tar"
  # Pin the new tag in the kustomization (the line after the image name).
  sed -i "\#name: localhost/stagecoach/$name\$#{n;s#newTag: .*#newTag: \"$TAG\"#}" "$kust"
  echo ">> imported $ref"
}

case $target in
  drupal|all) build drupal docker/drupal/Dockerfile . k8s/base/kustomization.yaml ;;&
  caddy|all)  build caddy docker/caddy/Dockerfile docker/caddy k8s/edge/kustomization.yaml ;;
  drupal) ;;
  *) echo "usage: $0 [drupal|caddy|all]" >&2; exit 2 ;;
esac
