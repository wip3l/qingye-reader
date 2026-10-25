#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
test "$(id -u)" -eq 0
mode=${1:-apply}
case "$mode" in apply|--check) ;; *) echo 'Usage: bash update.sh [--check]' >&2; exit 1;; esac
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
live=/www/wwwroot/qingye.icynol.com
node=/www/server/nodejs/v22.23.1/bin/node
service=legado-account.service
names=(cloudFileService.js cloudFileRoutes.js)
exec 9>/root/qingye-cloud-book-category-update.lock
flock -n 9
(cd "$stage" && sha256sum -c SHA256SUMS)
test -x "$node"
test "$(systemctl show "$service" -p WorkingDirectory --value)" = "$live"
systemctl is-active --quiet "$service"
for name in "${names[@]}"; do test -f "$live/$name" && test ! -L "$live/$name"; done
backup=$(mktemp -d /root/qingye-cloud-book-category-backup.XXXXXX)
mkdir "$backup/candidate"
for name in "${names[@]}"; do cp -p "$live/$name" "$backup/$name"; done
(cd "$backup" && sha256sum "${names[@]}" > ORIGINAL_SHA256SUMS)
"$node" "$stage/patch.mjs" "$backup" "$backup/candidate"
for name in "${names[@]}"; do "$node" --input-type=module --check < "$backup/candidate/$name"; done
"$node" "$stage/check.mjs" "$backup/candidate"
echo "Backup: $backup"
if [ "$mode" = --check ]; then echo 'PASS: preflight only; service was not changed or restarted'; exit 0; fi
if cmp -s "$backup/cloudFileService.js" "$backup/candidate/cloudFileService.js" &&
   cmp -s "$backup/cloudFileRoutes.js" "$backup/candidate/cloudFileRoutes.js"; then
  echo 'Already installed; no restart needed.'; exit 0
fi
health() {
  local attempt
  for attempt in {1..20}; do
    if curl -q --proxy '' --noproxy '*' --fail --silent --max-time 3 http://127.0.0.1:8080/health | "$node" -e \
      'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{try{process.exit(JSON.parse(s).ok===true?0:1)}catch{process.exit(1)}})'; then return 0; fi
    sleep 1
  done
  return 1
}
changed=0
finish() {
  code=$?
  trap - EXIT
  if [ "$code" -ne 0 ] && [ "$changed" -eq 1 ]; then
    echo "Update failed; restoring $backup" >&2
    if systemctl stop "$service" && [ "$(systemctl show "$service" -p MainPID --value)" = 0 ]; then
      restored=1
      for name in "${names[@]}"; do cp -p "$backup/$name" "$live/$name" || restored=0; done
      if [ "$restored" -eq 1 ]; then
        systemctl start "$service" && health || echo "Recovery needs attention: $backup" >&2
      else echo "File recovery failed; service remains stopped: $backup" >&2; fi
    else echo "Unable to stop service for recovery: $backup" >&2; fi
  fi
  exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for name in "${names[@]}"; do cmp "$backup/$name" "$live/$name"; done
changed=1
systemctl stop "$service"
test "$(systemctl show "$service" -p MainPID --value)" = 0
for name in "${names[@]}"; do cmp "$backup/$name" "$live/$name"; done
for name in "${names[@]}"; do
  cp -p "$backup/$name" "$backup/$name.install"
  cat "$backup/candidate/$name" > "$backup/$name.install"
  cp -p "$backup/$name.install" "$live/$name"
  cmp "$backup/candidate/$name" "$live/$name"
done
systemctl start "$service"
health
pid=$(systemctl show "$service" -p MainPID --value)
restarts=$(systemctl show "$service" -p NRestarts --value)
curl -q --proxy '' --noproxy '*' --fail --silent --max-time 10 https://qingye.icynol.com/health | "$node" -e \
  'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{try{process.exit(JSON.parse(s).ok===true?0:1)}catch{process.exit(1)}})'
status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
  -H 'Content-Type: application/json' -d '{"meta":{"mediaCategory":"comic"}}' \
  http://127.0.0.1:8080/v1/cloud-files/00000000-0000-0000-0000-000000000000/metadata)
test "$status" = 401
sleep 3
systemctl is-active --quiet "$service"
test "$(systemctl show "$service" -p MainPID --value)" = "$pid"
test "$(systemctl show "$service" -p NRestarts --value)" = "$restarts"
echo 'PASS: cloud book category update installed'
echo "Manual rollback: bash $stage/rollback.sh $backup"
systemctl show "$service" -p MainPID -p ActiveState -p SubState -p NRestarts
