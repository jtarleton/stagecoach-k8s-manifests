Files in this directory are git-ignored. Put the Cloudflare API token in
`cloudflare-api-token` (one line, permissions 600), then run
`scripts/secrets.sh` to load it into the cluster.

## Shield (beta basic auth)

Shield was switched off for the public launch on 2026-10-24 by deleting the
`stagecoach/shield` secret (settings.php enables Shield only while it exists).
Its last value is kept here, uncommitted, as `secrets/shield-secret.yaml`. To
put the gate back:

    kubectl apply -f secrets/shield-secret.yaml
    kubectl -n stagecoach rollout restart deploy/drupal

## Health-check pings (healthchecks.io)

stage-coach pings one healthchecks.io check per status-page component
(`STAGE_COACH_HEALTH_PINGS`, control/stage-coach.yaml). The ping URLs let anyone
ping, so they live only in `secrets/health-pings.env` (uncommitted; one line,
`api=URL,relay=URL,previews=URL,copydown=URL,promotions=URL,portal=URL,email=URL`). To load them:

    kubectl -n stage-coach create secret generic stage-coach-health \
      --from-file=pings=secrets/health-pings.env --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n stage-coach rollout restart deploy/stage-coach
