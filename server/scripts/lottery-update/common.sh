#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
test "$(id -u)" -eq 0
live=/www/wwwroot/qingye.icynol.com
node=/www/server/nodejs/v22.23.1/bin/node
service=legado-account.service
env_file=/etc/legado-account.env
patched=(cloudFileService.js config.js index.js membershipPolicy.js membershipService.js sync.js)
added=(lotteryService.js lotteryRoutes.js)
migrations=(026_lottery_coupons.sql 027_double11_lottery.sql)
psql=(runuser -u postgres -- /www/server/pgsql/bin/psql -X -w -h /tmp -d legado_commerce -v ON_ERROR_STOP=1 -At)
exec 9>/root/qingye-lottery-update.lock
flock -n 9
test -x "$node"
test "$(systemctl show "$service" -p WorkingDirectory --value)" = "$live"

json_ok() {
  "$node" -e 'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{try{process.exit(JSON.parse(s).ok===true?0:1)}catch{process.exit(1)}})'
}
health() {
  local attempt
  for attempt in {1..20}; do
    if curl -q --proxy '' --noproxy '*' --fail --silent --max-time 3 http://127.0.0.1:8080/health | json_ok; then return 0; fi
    sleep 1
  done
  return 1
}
# Writes LOTTERY_PAGE_ORIGIN into a copy of the environment file, replacing any earlier value.
write_env() {
  local source=$1 target=$2 origin=$3
  "$node" --input-type=module - "$source" "$target" "$origin" <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';
const [source, target, origin] = process.argv.slice(2);
const lines = readFileSync(source, 'utf8').split('\n').filter(line => !line.startsWith('LOTTERY_PAGE_ORIGIN='));
while (lines.length && lines[lines.length - 1] === '') lines.pop();
lines.push(`LOTTERY_PAGE_ORIGIN=${origin}`, '');
writeFileSync(target, lines.join('\n'));
NODE
}
restore_files() {
  local name
  for name in "${patched[@]}"; do cp -p "$backup/$name" "$live/$name" || return 1; done
  for name in "${added[@]}"; do
    if [ -f "$backup/$name.absent" ]; then rm -f -- "$live/$name" || return 1
    else cp -p "$backup/$name" "$live/$name" || return 1; fi
  done
  cat "$backup/environment.before" > "$env_file" || return 1
}
