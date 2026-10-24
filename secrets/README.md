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
