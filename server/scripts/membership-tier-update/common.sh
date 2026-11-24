#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
test "$(id -u)" -eq 0
live=/www/wwwroot/qingye.icynol.com
node=/www/server/nodejs/v22.23.1/bin/node
service=legado-account.service
# membershipService.js gets one anchored edit (the tier query); nothing else changes, no migration.
patched=(membershipService.js)
psql=(runuser -u postgres -- /www/server/pgsql/bin/psql -X -w -h /tmp -d legado_commerce -v ON_ERROR_STOP=1 -At)
exec 9>/root/qingye-membership-tier-update.lock
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
# Active periodic members whose displayed tier changes: the old rule (term covering now) against the new one
# (highest unfinished term). Read-only.
tier_changes() {
  "${psql[@]}" -c "WITH active AS (
      SELECT a.user_id, p.id AS period_id, p.sku FROM membership_accounts a
      JOIN membership_periods p ON p.id = a.period_id WHERE p.expires_at > now()),
    old AS (SELECT DISTINCT ON (o.period_id) o.period_id, o.sku FROM membership_orders o JOIN active USING (period_id)
      WHERE o.term_starts_at <= now() AND o.term_ends_at > now() ORDER BY o.period_id, o.term_starts_at DESC),
    new AS (SELECT DISTINCT ON (o.period_id) o.period_id, o.sku FROM membership_orders o JOIN active USING (period_id)
      WHERE o.term_ends_at > now()
      ORDER BY o.period_id, array_position(ARRAY['MONTHLY','ANNUAL','LIFETIME','SUPER_LIFETIME'], o.sku) DESC, o.term_starts_at)
    SELECT count(*) FROM active a LEFT JOIN old USING (period_id) LEFT JOIN new USING (period_id)
    WHERE COALESCE(old.sku, a.sku) <> COALESCE(new.sku, a.sku)"
}
