#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
mode=apply
case "${1:-}" in '') ;; --check) mode=check ;; *) echo 'Usage: bash update.sh [--check]' >&2; exit 1 ;; esac
(cd "$stage" && sha256sum --quiet -c SHA256SUMS)
systemctl is-active --quiet "$service"
test -f "$live/package.json" && test -d "$live/node_modules"
for name in "${patched[@]}"; do test -f "$live/$name" && test ! -L "$live/$name"; done
# New files: absent, or exactly this build (rerun after a completed install).
for name in "${added[@]}"; do
  if [ -e "$live/$name" ] && ! cmp -s "$stage/runtime/$name" "$live/$name"; then
    echo "UNEXPECTED_FILE: $live/$name exists and is not from this package; no live files changed" >&2
    exit 1
  fi
done
# 034 references app_users; credits touch the wallet, ledger and debt tables.
test "$("${psql[@]}" -c "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN
  ('app_users','point_wallets','point_ledger','account_debts','iap_orders');")" = 5

backup=$(mktemp -d /root/qingye-recharge-backup.XXXXXX)
mkdir "$backup/candidate"
for name in "${patched[@]}"; do cp -p "$live/$name" "$backup/$name"; done
(cd "$backup" && sha256sum "${patched[@]}" > ORIGINAL_SHA256SUMS)
# Exits with BASELINE_MISMATCH before anything live changes when an installed module differs.
"$node" "$stage/patch.mjs" "$backup" "$backup/candidate"
for name in "${added[@]}"; do cp "$stage/runtime/$name" "$backup/candidate/$name"; done
for name in "${patched[@]}" "${added[@]}"; do "$node" --input-type=module --check < "$backup/candidate/$name"; done
# The patched modules may differ from the reference build in whitespace only, never in code.
for name in "${patched[@]}"; do [ "$(code_sum "$backup/candidate/$name")" = "$(code_sum "$stage/runtime/$name")" ] || {
  echo "PATCH_RESULT_MISMATCH: patched $name differs from the reference build beyond whitespace; no live files changed" >&2
  exit 1; }; done

# Preflight copy of the whole runtime with the candidates on top; postgres must be able to read it.
preview=$(umask 022 && mktemp -d /tmp/qingye-recharge-preflight.XXXXXX)
trap 'rm -rf -- "$preview"' EXIT
chmod 755 "$preview"
cp "$live"/*.js "$preview/"
cp "$backup/candidate"/* "$preview/"
cp "$live/package.json" "$preview/package.json"
ln -s "$live/node_modules" "$preview/node_modules"
mkdir "$preview/migrations"
cp "$stage/test-migrations"/*.sql "$preview/migrations/"
cp "$stage/check.mjs" "$preview/.recharge-check.mjs"
chmod -R a+rX "$preview"
# Same user as the service, so Alipay key files it cannot read fail here instead of at restart.
run_as=()
svc_user=$(systemctl show "$service" -p User --value)
if [ -n "$svc_user" ]; then run_as=(-p User="$svc_user"); fi
systemd-run --quiet --wait --pipe -p EnvironmentFile="$env_file" -p WorkingDirectory="$preview" "${run_as[@]}" \
  "$node" "$preview/.recharge-check.mjs"
# The real credit, Alipay and redeem code paths against real PostgreSQL, in a new disposable database only.
(cd "$preview" && runuser -u postgres -- "$node" --input-type=module < "$stage/recharge-pg-check.mjs")
echo "Backup: $backup"
if [ "$mode" = check ]; then echo 'PASS: preflight only; database and service unchanged'; exit 0; fi

# Transactional and rerunnable: two new tables, granted to the service role.
for file in "${migrations[@]}"; do "${psql[@]}" < "$stage/migrations/$file" > /dev/null; done
test "$("${psql[@]}" -c "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN
  ('recharge_orders','redeem_codes');")" = 2
# The service connects as the role owning the existing tables, not as postgres; it must reach the new ones.
test "$("${psql[@]}" -c "SELECT has_table_privilege(o, 'recharge_orders', 'SELECT,INSERT,UPDATE')
  AND has_table_privilege(o, 'redeem_codes', 'SELECT,INSERT,UPDATE')
  FROM (SELECT tableowner AS o FROM pg_tables WHERE schemaname='public' AND tablename='point_wallets') r")" = t

same=1
for name in "${patched[@]}" "${added[@]}"; do cmp -s "$backup/candidate/$name" "$live/$name" || same=0; done
if [ "$same" -eq 1 ]; then echo 'Already installed; migration checked, no restart needed.'; exit 0; fi

changed=0
finish() {
  code=$?
  trap - EXIT
  rm -rf -- "$preview"
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
for name in "${patched[@]}"; do cmp "$backup/$name" "$live/$name"; done
systemctl stop "$service"
changed=1
test "$(systemctl show "$service" -p MainPID --value)" = 0
# Add the new files first so the patched index.js never runs without them.
for name in "${added[@]}" "${patched[@]}"; do
  cat "$backup/candidate/$name" > "$live/$name"
  cmp "$backup/candidate/$name" "$live/$name"
done
for name in "${added[@]}"; do chown --reference="$live/index.js" "$live/$name"; chmod --reference="$live/index.js" "$live/$name"; done
systemctl start "$service"
health
pid=$(systemctl show "$service" -p MainPID --value)
restarts=$(systemctl show "$service" -p NRestarts --value)
# New routes are mounted: channels needs a session; an unsigned Alipay notify is refused.
status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
  http://127.0.0.1:8080/v1/recharge/channels)
test "$status" = 401
body=$(curl -q --proxy '' --noproxy '*' --silent --max-time 10 -X POST -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'out_trade_no=preflight&trade_status=TRADE_SUCCESS' http://127.0.0.1:8080/v1/recharge/notify/alipay)
test "$body" = failure || { echo "Unexpected notify response: $body" >&2; exit 1; }
curl -q --proxy '' --noproxy '*' --fail --silent --max-time 10 https://qingye.icynol.com/health | json_ok
sleep 3
systemctl is-active --quiet "$service"
test "$(systemctl show "$service" -p MainPID --value)" = "$pid"
test "$(systemctl show "$service" -p NRestarts --value)" = "$restarts"
if grep -q '^ALIPAY_APP_ID=.' "$env_file"; then alipay_state=configured; else alipay_state='not configured (redeem codes only)'; fi
echo "PASS: Android recharge installed; Alipay $alipay_state"
echo "Manual rollback: bash $stage/rollback.sh $backup"
