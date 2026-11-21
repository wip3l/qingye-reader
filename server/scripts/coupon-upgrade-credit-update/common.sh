#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
test "$(id -u)" -eq 0
live=/www/wwwroot/qingye.icynol.com
node=/www/server/nodejs/v22.23.1/bin/node
service=legado-account.service
# membershipPolicy.js gets exact compiled hunks; nothing else changes.
patched=(membershipPolicy.js)
migrations=(033_coupon_upgrade_credit.sql)
psql=(runuser -u postgres -- /www/server/pgsql/bin/psql -X -w -h /tmp -d legado_commerce -v ON_ERROR_STOP=1 -At)
exec 9>/root/qingye-coupon-upgrade-credit-update.lock
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
  for name in "${patched[@]}"; do cat "$backup/$name" > "$live/$name" || return 1; done
}
# Lifetime memberships bought with a coupon whose upgrade credit is still net of it (what migration 033 corrects).
pending_credits() {
  "${psql[@]}" -c "SELECT count(*) FROM membership_periods p JOIN membership_orders o ON o.period_id = p.id
    WHERE o.sku = 'LIFETIME' AND o.coupon_points > 0 AND p.sku = 'LIFETIME' AND p.expires_at IS NULL
      AND p.permanent_credit_points = o.list_points - o.coupon_points"
}
