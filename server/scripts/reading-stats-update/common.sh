#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
test "$(id -u)" -eq 0
live=/www/wwwroot/qingye.icynol.com
node=/www/server/nodejs/v22.23.1/bin/node
service=legado-account.service
exec 9>/root/qingye-reading-stats-update.lock
flock -n 9
test -x "$node"
test "$(systemctl show "$service" -p WorkingDirectory --value)" = "$live"
health() {
  local attempt
  for attempt in {1..20}; do
    if curl -q --proxy '' --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:8080/health | "$node" -e \
      'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{try{process.exit(JSON.parse(s).ok===true?0:1)}catch{process.exit(1)}})'; then return 0; fi
    sleep 1
  done
  return 1
}
restore_files() {
  cp -p "$backup/index.js" "$live/index.js" || return 1
  if [ -f "$backup/readingStats.js.absent" ]; then
    rm -f -- "$live/readingStats.js" || return 1
  else
    cp -p "$backup/readingStats.js" "$live/readingStats.js" || return 1
  fi
}
