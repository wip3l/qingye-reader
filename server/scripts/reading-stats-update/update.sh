#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
mode=${1:-apply}
case "$mode" in apply|--check) ;; *) echo 'Usage: bash update.sh [--check]' >&2; exit 1;; esac
(cd "$stage" && sha256sum -c SHA256SUMS)
systemctl is-active --quiet "$service"
test -f "$live/index.js" && test ! -L "$live/index.js"
test -f "$live/sync.js" && test ! -L "$live/sync.js"
grep -Eq '^export class SyncApiError ' "$live/sync.js"
test ! -L "$live/readingStats.js"
if [ -e "$live/readingStats.js" ]; then
  # Refuse overwriting a different or newer implementation.
  cmp "$stage/runtime/readingStats.js" "$live/readingStats.js"
fi
psql=(runuser -u postgres -- /www/server/pgsql/bin/psql -X -w -h /tmp -d legado_commerce -v ON_ERROR_STOP=1 -At)
test "$("${psql[@]}" -c "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN ('app_users','sync_devices','point_wallets');")" = 3
backup=$(mktemp -d /root/qingye-reading-stats-backup.XXXXXX)
mkdir "$backup/candidate"
cp -p "$live/index.js" "$backup/index.js"
cp -p "$live/sync.js" "$backup/sync.js"
if [ -f "$live/readingStats.js" ]; then cp -p "$live/readingStats.js" "$backup/readingStats.js"; else touch "$backup/readingStats.js.absent"; fi
(cd "$backup" && sha256sum index.js sync.js readingStats.js* > ORIGINAL_SHA256SUMS)
"$node" "$stage/patch.mjs" "$backup/index.js" "$backup/candidate/index.js"
cp "$stage/runtime/readingStats.js" "$backup/candidate/readingStats.js"
for name in index.js readingStats.js; do "$node" --input-type=module --check < "$backup/candidate/$name"; done
"$node" "$stage/check.mjs" "$backup/candidate"
(cd "$backup/candidate" && sha256sum index.js readingStats.js > SHA256SUMS)
echo "Backup: $backup"
if [ "$mode" = --check ]; then echo 'PASS: preflight only; database and service unchanged'; exit 0; fi
# Additive, transactional migration. Keep tables on rollback to preserve synced records.
"${psql[@]}" < "$stage/migrations/025_reading_statistics.sql"
if cmp -s "$backup/index.js" "$backup/candidate/index.js" && cmp -s "$live/readingStats.js" "$backup/candidate/readingStats.js"; then
  echo 'Already installed; migration checked, no restart needed.'; exit 0
fi
changed=0
finish() {
  code=$?
  trap - EXIT
  if [ "$code" -ne 0 ] && [ "$changed" -eq 1 ]; then
    echo "Update failed; restoring files from $backup (database retained)" >&2
    if systemctl stop "$service" && [ "$(systemctl show "$service" -p MainPID --value)" = 0 ] && restore_files; then
      systemctl start "$service" && health || echo "Recovery needs attention: $backup" >&2
    else echo "Recovery failed; inspect service and backup: $backup" >&2; fi
  fi
  exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cmp "$backup/index.js" "$live/index.js"
cmp "$backup/sync.js" "$live/sync.js"
if [ -f "$backup/readingStats.js.absent" ]; then test ! -e "$live/readingStats.js"; else cmp "$backup/readingStats.js" "$live/readingStats.js"; fi
systemctl stop "$service"
changed=1
test "$(systemctl show "$service" -p MainPID --value)" = 0
for name in index.js readingStats.js; do
  cp -p "$backup/index.js" "$backup/$name.install"
  cat "$backup/candidate/$name" > "$backup/$name.install"
  cp -p "$backup/$name.install" "$live/$name"
  cmp "$backup/candidate/$name" "$live/$name"
done
systemctl start "$service"
health
pid=$(systemctl show "$service" -p MainPID --value)
restarts=$(systemctl show "$service" -p NRestarts --value)
status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
  -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:8080/v1/sync/reading-stats)
test "$status" = 401
curl -q --proxy '' --noproxy '*' --fail --silent --max-time 10 https://qingye.icynol.com/health | "$node" -e \
  'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{try{process.exit(JSON.parse(s).ok===true?0:1)}catch{process.exit(1)}})'
sleep 3
systemctl is-active --quiet "$service"
test "$(systemctl show "$service" -p MainPID --value)" = "$pid"
test "$(systemctl show "$service" -p NRestarts --value)" = "$restarts"
echo 'PASS: reading statistics update installed'
echo "Manual rollback: bash $stage/rollback.sh $backup"
