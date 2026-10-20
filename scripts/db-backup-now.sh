#!/usr/bin/env bash
# Run the nightly database backup immediately and show its result.
set -euo pipefail
job="db-backup-manual-$(date -u +%Y%m%d%H%M%S)"
kubectl -n stagecoach create job "$job" --from=cronjob/db-backup >/dev/null
kubectl -n stagecoach wait --for=condition=complete "job/$job" --timeout=900s >/dev/null \
  || { kubectl -n stagecoach logs "job/$job" --tail=20; exit 1; }
kubectl -n stagecoach logs "job/$job" | tail -1
kubectl -n stagecoach delete job "$job" >/dev/null
