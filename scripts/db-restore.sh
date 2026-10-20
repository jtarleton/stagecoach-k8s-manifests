#!/usr/bin/env bash
# List backups, or restore one into the Drupal database (or a scratch database).
#   scripts/db-restore.sh                        list backups
#   scripts/db-restore.sh FILE [TARGET_DB]       restore (TARGET_DB defaults to drupal)
# Restoring over "drupal" asks for confirmation; the site is unaffected until
# the import finishes, then caches are rebuilt and Varnish is cleared.
set -euo pipefail
ns=stagecoach

# One helper pod with the backup volume mounted read-only; commands run through
# `kubectl exec`, which streams binary data safely (unlike `kubectl run -i`).
helper="db-restore-$$"
start_helper() {
  local overrides
  overrides=$(python3 -I -c '
import json
img = "docker.io/library/mariadb:11.8.8"
print(json.dumps({"spec": {
  "securityContext": {"runAsNonRoot": True, "runAsUser": 999, "runAsGroup": 999,
                      "seccompProfile": {"type": "RuntimeDefault"}},
  "containers": [{"name": "r", "image": img, "command": ["sleep", "1800"],
    "securityContext": {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True,
                        "capabilities": {"drop": ["ALL"]}},
    "volumeMounts": [{"name": "b", "mountPath": "/backups", "readOnly": True}]}],
  "volumes": [{"name": "b", "persistentVolumeClaim": {"claimName": "db-backups"}}]}}))')
  kubectl -n $ns run "$helper" --restart=Never --image=docker.io/library/mariadb:11.8.8 \
    --labels=app.kubernetes.io/name=db-restore --overrides="$overrides" >/dev/null
  trap 'kubectl -n $ns delete pod "$helper" --wait=false >/dev/null 2>&1 || true' EXIT
  kubectl -n $ns wait --for=condition=Ready "pod/$helper" --timeout=120s >/dev/null
}
pod_with_backups() { kubectl -n $ns exec -i "$helper" -- sh -c "$1"; }

start_helper

if [ $# -eq 0 ]; then
  pod_with_backups 'cd /backups && ls -lh drupal-*.sql.gz && sha256sum -c --quiet *.sha256 && echo "all checksums OK"'
  exit
fi

file=$(basename "$1"); target=${2:-drupal}
[[ $file =~ ^drupal-[0-9TZ]+\.sql\.gz$ ]] || { echo "unexpected backup name: $file" >&2; exit 2; }
[[ $target =~ ^[a-z0-9_]+$ ]] || { echo "bad database name: $target" >&2; exit 2; }
if [ "$target" = drupal ]; then
  read -rp "Overwrite the LIVE drupal database with $file? Type 'restore' to continue: " ok
  [ "$ok" = restore ] || { echo aborted; exit 1; }
fi

echo ">> verifying $file"
pod_with_backups "cd /backups && sha256sum -c --quiet $file.sha256 && gzip -t $file && echo ok"
echo ">> importing into $target"
kubectl -n $ns exec -i mariadb-0 -- sh -c "export MYSQL_PWD=\"\$MARIADB_ROOT_PASSWORD\";
  mariadb -uroot -e 'CREATE DATABASE IF NOT EXISTS \`$target\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci' &&
  mariadb -uroot $target" < <(pod_with_backups "cat /backups/$file" | gunzip)
if [ "$target" = drupal ]; then
  kubectl -n $ns exec deploy/drupal -c frankenphp -- drush cr
  kubectl -n $ns rollout restart deploy/varnish
fi
echo ">> restored $file into $target"
