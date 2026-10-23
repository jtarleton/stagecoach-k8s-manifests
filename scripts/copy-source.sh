#!/usr/bin/env bash
# Give Stagecoach's copy-down prod -> dev a read-only way into prod's database:
# a MariaDB user that can only dump (SELECT, SHOW VIEW, TRIGGER, LOCK TABLES,
# EVENT on drupal.*), and its credentials as secret stage-coach-source-stagecoach
# in stagecoach-dev, the name Stagecoach's shaped copy Job reads. Safe to re-run:
# each run rotates the password. The password never appears on a command line.
set -euo pipefail

src_ns=stagecoach dst_ns=stagecoach-dev user=stagecoach_copy db=drupal
pw=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)

printf "CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s';
ALTER USER '%s'@'%%' IDENTIFIED BY '%s';
GRANT SELECT, SHOW VIEW, TRIGGER, LOCK TABLES, EVENT ON \`%s\`.* TO '%s'@'%%';\n" \
  "$user" "$pw" "$user" "$pw" "$db" "$user" \
  | kubectl -n "$src_ns" exec -i mariadb-0 -c mariadb -- \
      sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot'

kubectl -n "$dst_ns" create secret generic "stage-coach-source-$src_ns" \
  --from-literal=SRC_DB_HOST="mariadb.$src_ns.svc.cluster.local" \
  --from-literal=SRC_DB_NAME="$db" \
  --from-literal=SRC_DB_USER="$user" \
  --from-file=SRC_DB_PASSWORD=<(printf %s "$pw") \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "read-only user $user ready; secret $dst_ns/stage-coach-source-$src_ns applied"
