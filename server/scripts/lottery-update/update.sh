#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
usage() { echo 'Usage: bash update.sh [--check] [--origin https://抽奖页域名]' >&2; }
mode=apply
origin=''
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check ;;
    --origin) origin=${2:-}; shift ;;
    --origin=*) origin=${1#--origin=} ;;
    *) usage; exit 1 ;;
  esac
  shift
done
(cd "$stage" && sha256sum --quiet -c SHA256SUMS)
if [ -n "$origin" ] && ! [[ "$origin" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
  echo 'The origin is scheme and host only, e.g. https://huodong.example.com (no path, no trailing slash)' >&2; exit 1
fi
systemctl is-active --quiet "$service"
test -f "$env_file" && test ! -L "$env_file"
current_origin=$(sed -n 's/^LOTTERY_PAGE_ORIGIN=//p' "$env_file" | tail -n 1)
target_origin=${origin:-$current_origin}
if [ "$mode" = apply ] && [ -z "$target_origin" ]; then
  echo 'Pass --origin https://<抽奖页域名>; the page cannot submit anything without it.' >&2; exit 1
fi
for name in "${patched[@]}"; do test -f "$live/$name" && test ! -L "$live/$name"; done
for name in "${added[@]}"; do
  test ! -L "$live/$name"
  # Refuse overwriting a different or newer implementation.
  if [ -e "$live/$name" ]; then cmp "$stage/runtime/$name" "$live/$name"; fi
done
test -d "$live/node_modules" && test -f "$live/package.json"
test "$("${psql[@]}" -c "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN
  ('app_users','point_wallets','membership_orders','membership_products','cloud_files');")" = 5

backup=$(mktemp -d /root/qingye-lottery-backup.XXXXXX)
mkdir "$backup/candidate"
for name in "${patched[@]}"; do cp -p "$live/$name" "$backup/$name"; done
for name in "${added[@]}"; do
  if [ -f "$live/$name" ]; then cp -p "$live/$name" "$backup/$name"; else touch "$backup/$name.absent"; fi
done
cp -p "$env_file" "$backup/environment.before"
(cd "$backup" && sha256sum "${patched[@]}" environment.before > ORIGINAL_SHA256SUMS)
"$node" "$stage/patch.mjs" "$backup" "$backup/candidate"
for name in "${added[@]}"; do cp "$stage/runtime/$name" "$backup/candidate/$name"; done
for name in "${patched[@]}" "${added[@]}"; do "$node" --input-type=module --check < "$backup/candidate/$name"; done
write_env "$env_file" "$backup/environment.candidate" "${target_origin:-https://preflight.invalid}"

# Preflight copy of the whole runtime with the candidates on top; postgres must be able to read it.
preview=$(umask 022 && mktemp -d /tmp/qingye-lottery-preflight.XXXXXX)
trap 'rm -rf -- "$preview"' EXIT
chmod 755 "$preview"
cp "$live"/*.js "$preview/"
cp "$backup/candidate"/*.js "$preview/"
cp "$live/package.json" "$preview/package.json"
ln -s "$live/node_modules" "$preview/node_modules"
mkdir "$preview/migrations"
cp "$stage/test-migrations"/*.sql "$preview/migrations/"
chmod -R a+rX "$preview"
systemd-run --quiet --wait --pipe -p EnvironmentFile="$backup/environment.candidate" -p WorkingDirectory="$preview" \
  "$node" "$stage/check.mjs" "${target_origin:-https://preflight.invalid}"
# Real PostgreSQL concurrency checks, in a new disposable database only.
(cd "$preview" && runuser -u postgres -- "$node" --input-type=module < "$stage/lottery-pg-concurrency.mjs")
echo "Backup: $backup"
if [ "$mode" = check ]; then echo 'PASS: preflight only; database, configuration and service unchanged'; exit 0; fi

# Additive, transactional and rerunnable. Tables stay on rollback; the old code ignores them.
for file in "${migrations[@]}"; do "${psql[@]}" < "$stage/migrations/$file" > /dev/null; done
test "$("${psql[@]}" -c "SELECT count(*) FROM lottery_prizes WHERE campaign_id='double11-2026'")" = 5

same=1
for name in "${patched[@]}" "${added[@]}"; do cmp -s "$backup/candidate/$name" "$live/$name" || same=0; done
cmp -s "$backup/environment.candidate" "$env_file" || same=0
if [ "$same" -eq 1 ]; then echo 'Already installed; migrations checked, no restart needed.'; exit 0; fi

changed=0
finish() {
  code=$?
  trap - EXIT
  rm -rf -- "$preview"
  if [ "$code" -ne 0 ] && [ "$changed" -eq 1 ]; then
    echo "Update failed; restoring files and environment from $backup (database retained)" >&2
    if systemctl stop "$service" && [ "$(systemctl show "$service" -p MainPID --value)" = 0 ] && restore_files; then
      systemctl start "$service" && health || echo "Recovery needs attention: $backup" >&2
    else echo "Recovery failed; inspect service and backup: $backup" >&2; fi
  fi
  exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for name in "${patched[@]}"; do cmp "$backup/$name" "$live/$name"; done
cmp "$backup/environment.before" "$env_file"
systemctl stop "$service"
changed=1
test "$(systemctl show "$service" -p MainPID --value)" = 0
for name in "${patched[@]}" "${added[@]}"; do
  if [ -f "$live/$name" ]; then
    cat "$backup/candidate/$name" > "$live/$name"
  else
    install -m "$(stat -c %a "$live/index.js")" -o "$(stat -c %u "$live/index.js")" -g "$(stat -c %g "$live/index.js")" \
      "$backup/candidate/$name" "$live/$name"
  fi
  cmp "$backup/candidate/$name" "$live/$name"
done
cat "$backup/environment.candidate" > "$env_file"
systemctl start "$service"
health
pid=$(systemctl show "$service" -p MainPID --value)
restarts=$(systemctl show "$service" -p NRestarts --value)
curl -q --proxy '' --noproxy '*' --fail --silent --max-time 5 http://127.0.0.1:8080/lottery/api/state | "$node" -e \
  'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{const j=JSON.parse(s);process.exit(j.campaign?.id==="double11-2026"&&j.prizes?.length===5?0:1)})'
status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
  -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:8080/lottery/api/draw)
test "$status" = 403
curl -q --proxy '' --noproxy '*' --fail --silent --max-time 10 https://qingye.icynol.com/health | json_ok
sleep 3
systemctl is-active --quiet "$service"
test "$(systemctl show "$service" -p MainPID --value)" = "$pid"
test "$(systemctl show "$service" -p NRestarts --value)" = "$restarts"
echo 'PASS: lottery update installed (campaign still disabled)'
echo "LOTTERY_PAGE_ORIGIN=$target_origin"
echo "Manual rollback: bash $stage/rollback.sh $backup"
