# stagecoach-k8s-manifests

Kubernetes (k3s) manifests for [stagecoach.sh](https://stagecoach.sh). The Drupal
application and its image live in
[stagecoach_d12app](https://github.com/jtarleton/stagecoach_d12app).

```
Cloudflare ─► Caddy (edge, TLS) ─► Varnish ─► FrankenPHP (Drupal 11) ─┬─► MariaDB 11.8
                                                                        └─► Redis 8.2
```

| Component | Namespace | Notes |
|---|---|---|
| Caddy 2.11 + caddy-dns/cloudflare | `stagecoach-edge` | Let's Encrypt/ZeroSSL via DNS-01, binds host ports 80/443, only accepts Cloudflare IPs |
| Varnish 8.0 | `stagecoach` | 64 MB full-page cache, tag-based BAN invalidation from Drupal |
| FrankenPHP 1.13 / Drupal 11.4 | `stagecoach` | Image from stagecoach_d12app; code read-only, files on a PVC |
| MariaDB 11.8 LTS | `stagecoach` | StatefulSet, 5 Gi PVC, tuned for a 2 GB host |
| Redis 8.2 | `stagecoach` | Cache only (no persistence), 48 MB LRU, password auth |
| Drupal cron | `stagecoach` | CronJob every 15 min (`drush cron`) |

## Layout

- `base/`: app namespace (Pod Security **restricted**, default-deny NetworkPolicies), MariaDB, Redis, Drupal, Varnish, cron. `base/config/` holds the VCL and `mariadb.cnf`.
- `edge/`: Caddy edge in its own namespace (hostPort isn't allowed under restricted), Caddyfile, Cloudflare IP allow-list.
- `docker/caddy/`: edge Caddy image (xcaddy + Cloudflare DNS provider).
- `scripts/`: `deploy.sh`, `secrets.sh`, `cloudflare-ips.sh`, `build-caddy.sh`.
- `secrets/`: git-ignored; holds `cloudflare-api-token` on the server.

**No secrets are committed.** Everything sensitive is a Kubernetes Secret created
on the server by `scripts/secrets.sh` (or by hand), and referenced by name:

| Secret (namespace) | Keys | Used by |
|---|---|---|
| `mariadb` (stagecoach) | `password`, `root-password` | MariaDB, Drupal, cron |
| `drupal` (stagecoach) | `hash-salt`, `admin-password` | Drupal, cron |
| `redis-auth` (stagecoach) | `password`, `auth.conf` | Redis, Drupal, cron |
| `smtp` (stagecoach) | `password` | Drupal (Brevo SMTP key), optional |
| `shield` (stagecoach) | `user`, `pass` | Drupal beta gate; delete to go public, optional |
| `cloudflare-api-token` (stagecoach-edge) | `token` | Caddy DNS-01 |

## Operations

```sh
scripts/secrets.sh        # create missing secrets (never overwrites existing ones)
scripts/deploy.sh         # kubectl apply -k base && -k edge, wait for rollouts
scripts/build-caddy.sh    # rebuild the edge image and pin its tag
scripts/cloudflare-ips.sh # refresh Cloudflare ranges (Caddy, NetworkPolicy, ufw)
```

Image tags are pinned in `base/kustomization.yaml` (drupal) and
`edge/kustomization.yaml` (caddy). The app repo's `scripts/build.sh` updates
the drupal tag here; commit that change together with the deploy.

**Clear Varnish completely:** `kubectl -n stagecoach rollout restart deploy/varnish`

**Database backup:**
```sh
kubectl -n stagecoach exec mariadb-0 -- sh -c \
  'mariadb-dump -udrupal -p"$MARIADB_PASSWORD" --single-transaction drupal' | gzip > drupal-$(date +%F).sql.gz
```

**Go public (remove the Shield beta gate):**
`kubectl -n stagecoach delete secret shield && kubectl -n stagecoach rollout restart deploy/drupal deploy/varnish`

## Cloudflare

- SSL/TLS mode **Full (strict)**; the origin has a real, publicly trusted certificate.
- Host-port traffic is DNAT'd to the pod and bypasses ufw's INPUT chain, so
  `edge/networkpolicy.yaml` (generated) is what limits the origin to Cloudflare,
  backed up by Caddy's own `remote_ip` check.
- The API token needs only **Zone → DNS → Edit** on `stagecoach.sh`.

## Memory budget (1 vCPU / 2 GB host)

Requests ≈ 650 MiB, limits ≈ 1.6 GiB, with 4 GiB swap as a safety net.
metrics-server is disabled; watch with `k3s crictl stats` and `free -h`.
