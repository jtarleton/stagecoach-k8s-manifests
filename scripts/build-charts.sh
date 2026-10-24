#!/usr/bin/env bash
# Package the Helm charts from the stagecoach (Go) checkout into edge/charts/,
# the repository the edge serves at https://charts.stagecoach.sh:
#   STAGECOACH_DIR=/path/to/stagecoach_go scripts/build-charts.sh
# Then list any new .tgz in edge/kustomization.yaml (helm-charts), commit
# edge/charts/ and apply edge/ (scripts/deploy.sh).
# Packages already published keep their bytes: bump the chart's version to
# publish a change, as Helm clients cache by version.
set -euo pipefail
cd "$(dirname "$0")/.."

src=${STAGECOACH_DIR:-../stagecoach_go}/deploy/helm
out=edge/charts
url=https://charts.stagecoach.sh
helm_image=docker.io/alpine/helm:3.16.4
[ -d "$src" ] || { echo "charts not found at $src (set STAGECOACH_DIR)" >&2; exit 1; }
mkdir -p "$out"

c=$(buildah from --pull=missing -q "$helm_image")
trap 'buildah rm "$c" >/dev/null' EXIT
buildah run -v "$(realpath "$src")":/src:ro -v "$(realpath "$out")":/out "$c" sh -ec '
  for chart in /src/*/; do
    name=$(helm show chart "$chart" | sed -n "s/^name: //p")
    version=$(helm show chart "$chart" | sed -n "s/^version: //p")
    if [ -e "/out/$name-$version.tgz" ]; then
      echo "$name $version already published, kept"
    else
      helm lint "$chart" --set clusterName=x --set token=stg_live_x >/dev/null
      helm package "$chart" -d /out >/dev/null
      echo "$name $version packaged"
    fi
  done
  helm repo index /out --url '"$url"'
'
echo ">> $out: $(ls "$out" | tr '\n' ' ')"
