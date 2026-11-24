#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
test "$(id -u)" -eq 0
live=/www/wwwroot/qingye.icynol.com
node=/www/server/nodejs/v22.23.1/bin/node
service=legado-account.service
env_file=/etc/legado-account.env
# Both files came in whole with the recharge update (qingye-recharge-20261123); they are replaced whole.
# runtime/previous/ holds exactly what that update installed, so anything else on the server is refused.
replaced=(rechargeRoutes.js redeem-codes.mjs)
migrations=(035_membership_redeem_codes.sql)
# Command wrapper for the code tool, outside the runtime directory.
command_path=/usr/local/bin/qingye-codes
psql=(runuser -u postgres -- /www/server/pgsql/bin/psql -X -w -h /tmp -d legado_commerce -v ON_ERROR_STOP=1 -At)
exec 9>/root/qingye-membership-codes-update.lock
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
restore_files() {
  local name
  for name in "${replaced[@]}"; do cat "$backup/$name" > "$live/$name" || return 1; done
  # The wrapper only existed because of this update.
  rm -f -- "$command_path" || return 1
}
