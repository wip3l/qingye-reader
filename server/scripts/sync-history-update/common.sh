#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
test "$(id -u)" -eq 0
live=/www/wwwroot/qingye.icynol.com
node=/www/server/nodejs/v22.23.1/bin/node
service=legado-account.service
env_file=/etc/legado-account.env
# sync.js, index.js and accountAuth.js get exact compiled hunks; no new files.
patched=(sync.js index.js accountAuth.js)
migrations=(037_sync_entity_history.sql)
psql=(runuser -u postgres -- /www/server/pgsql/bin/psql -X -w -h /tmp -d legado_commerce -v ON_ERROR_STOP=1 -At)
exec 9>/root/qingye-sync-history-update.lock
flock -n 9
test -x "$node"
test "$(systemctl show "$service" -p WorkingDirectory --value)" = "$live"

code_sum() { tr -d ' \t\r\n' < "$1" | sha256sum | cut -d' ' -f1; }
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
# The service role (owner of point_wallets) must be able to read, write and prune the new table.
history_ready() {
  "${psql[@]}" -c "SELECT CASE WHEN r IS NULL THEN 'no-role' ELSE
      (has_table_privilege(r, 'public.sync_entity_history', 'SELECT')
       AND has_table_privilege(r, 'public.sync_entity_history', 'INSERT')
       AND has_table_privilege(r, 'public.sync_entity_history', 'DELETE')
       AND has_sequence_privilege(r, 'public.sync_entity_history_id_seq', 'USAGE'))::text END
    FROM (SELECT tableowner AS r FROM pg_tables WHERE schemaname='public' AND tablename='point_wallets') owner"
}
