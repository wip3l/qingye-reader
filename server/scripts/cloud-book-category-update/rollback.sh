#!/usr/bin/env bash
set -Eeuo pipefail
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
test "$(id -u)" -eq 0
backup=$(realpath -e -- "${1:?Pass the backup directory printed by update.sh}")
case "$backup" in /root/qingye-cloud-book-category-backup.*) ;; *) echo 'Unexpected backup directory' >&2; exit 1;; esac
live=/www/wwwroot/qingye.icynol.com
node=/www/server/nodejs/v22.23.1/bin/node
service=legado-account.service
names=(cloudFileService.js cloudFileRoutes.js)
exec 9>/root/qingye-cloud-book-category-update.lock
flock -n 9
test "$(systemctl show "$service" -p WorkingDirectory --value)" = "$live"
(cd "$backup" && sha256sum -c ORIGINAL_SHA256SUMS)
for name in "${names[@]}"; do
  test -f "$backup/$name" && test ! -L "$backup/$name"
  test -f "$live/$name" && test ! -L "$live/$name"
  cmp "$backup/candidate/$name" "$live/$name"
  "$node" --input-type=module --check < "$backup/$name"
done
systemctl stop "$service"
test "$(systemctl show "$service" -p MainPID --value)" = 0
for name in "${names[@]}"; do cp -p "$backup/$name" "$live/$name"; done
systemctl start "$service"
for attempt in {1..20}; do
  if curl -q --proxy '' --noproxy '*' --fail --silent --max-time 3 http://127.0.0.1:8080/health | "$node" -e \
    'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{try{process.exit(JSON.parse(s).ok===true?0:1)}catch{process.exit(1)}})'; then
    systemctl is-active --quiet "$service"
    echo 'PASS: previous cloud file modules restored'
    exit 0
  fi
  sleep 1
done
echo "Files restored, but service health needs attention: $backup" >&2
exit 1
