#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
mode=apply
case "${1:-}" in '') ;; --check) mode=check ;; *) echo 'Usage: bash update.sh [--check]' >&2; exit 1 ;; esac
(cd "$stage" && sha256sum --quiet -c SHA256SUMS)
systemctl is-active --quiet "$service"
test -f "$live/package.json" && test -d "$live/node_modules"
# Installed files must be exactly the recharge update's build, or already this build (rerun after install).
for name in "${replaced[@]}"; do
  test -f "$live/$name" && test ! -L "$live/$name"
  if ! cmp -s "$stage/runtime/previous/$name" "$live/$name" && ! cmp -s "$stage/runtime/$name" "$live/$name"; then
    echo "BASELINE_MISMATCH: $live/$name is neither the recharge update's build nor this one; install qingye-recharge-20261123 first" >&2
    exit 1
  fi
done
if [ -e "$command_path" ] && ! cmp -s "$stage/qingye-codes" "$command_path"; then
  echo "UNEXPECTED_FILE: $command_path exists and is not from this package; no live files changed" >&2
  exit 1
fi
# 035 alters redeem_codes, which the recharge update created.
test "$("${psql[@]}" -c "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN
  ('redeem_codes','recharge_orders','membership_orders','membership_quotes');")" = 4

backup=$(mktemp -d /root/qingye-membership-codes-backup.XXXXXX)
for name in "${replaced[@]}"; do cp -p "$live/$name" "$backup/$name"; done
(cd "$backup" && sha256sum "${replaced[@]}" > ORIGINAL_SHA256SUMS)
for name in "${replaced[@]}"; do "$node" --input-type=module --check < "$stage/runtime/$name"; done

# Preflight copy of the whole runtime with the new files on top; postgres must be able to read it.
preview=$(umask 022 && mktemp -d /tmp/qingye-membership-codes-preflight.XXXXXX)
trap 'rm -rf -- "$preview"' EXIT
chmod 755 "$preview"
cp "$live"/*.js "$preview/"
for name in "${replaced[@]}"; do cp "$stage/runtime/$name" "$preview/$name"; done
cp "$live/package.json" "$preview/package.json"
ln -s "$live/node_modules" "$preview/node_modules"
mkdir "$preview/migrations"
cp "$stage/test-migrations"/*.sql "$preview/migrations/"
cp "$stage/check.mjs" "$preview/.membership-codes-check.mjs"
chmod -R a+rX "$preview"
run_as=()
svc_user=$(systemctl show "$service" -p User --value)
if [ -n "$svc_user" ]; then run_as=(-p User="$svc_user"); fi
systemd-run --quiet --wait --pipe -p EnvironmentFile="$env_file" -p WorkingDirectory="$preview" "${run_as[@]}" \
  "$node" "$preview/.membership-codes-check.mjs"
# Membership codes and the code tool against real PostgreSQL, in a new disposable database only.
(cd "$preview" && runuser -u postgres -- "$node" --input-type=module < "$stage/membership-codes-pg-check.mjs")
echo "Backup: $backup"
if [ "$mode" = check ]; then echo 'PASS: preflight only; database and service unchanged'; exit 0; fi

# Transactional and rerunnable: one nullable column on redeem_codes (table grants from 034 cover it).
for file in "${migrations[@]}"; do "${psql[@]}" < "$stage/migrations/$file" > /dev/null; done
test "$("${psql[@]}" -c "SELECT count(*) FROM information_schema.columns
  WHERE table_schema='public' AND table_name='redeem_codes' AND column_name='membership_sku'")" = 1
test "$("${psql[@]}" -c "SELECT has_column_privilege(o, 'redeem_codes', 'membership_sku', 'SELECT,INSERT')
  FROM (SELECT tableowner AS o FROM pg_tables WHERE schemaname='public' AND tablename='point_wallets') r")" = t

same=1
for name in "${replaced[@]}"; do cmp -s "$stage/runtime/$name" "$live/$name" || same=0; done
cmp -s "$stage/qingye-codes" "$command_path" 2>/dev/null || same=0
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
for name in "${replaced[@]}"; do cmp "$backup/$name" "$live/$name"; done
systemctl stop "$service"
changed=1
test "$(systemctl show "$service" -p MainPID --value)" = 0
for name in "${replaced[@]}"; do
  cat "$stage/runtime/$name" > "$live/$name"
  cmp "$stage/runtime/$name" "$live/$name"
done
install -m 755 -o root -g root "$stage/qingye-codes" "$command_path"
systemctl start "$service"
health
pid=$(systemctl show "$service" -p MainPID --value)
restarts=$(systemctl show "$service" -p NRestarts --value)
# Redeem route still mounted (needs a session) and the tool answers with its usage line.
status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
  -X POST -H 'Content-Type: application/json' -d '{"code":"x"}' http://127.0.0.1:8080/v1/recharge/redeem)
test "$status" = 401
"$command_path" list > /dev/null
curl -q --proxy '' --noproxy '*' --fail --silent --max-time 10 https://qingye.icynol.com/health | json_ok
sleep 3
systemctl is-active --quiet "$service"
test "$(systemctl show "$service" -p MainPID --value)" = "$pid"
test "$(systemctl show "$service" -p NRestarts --value)" = "$restarts"
echo 'PASS: membership redeem codes installed; manage codes with: qingye-codes list'
echo "Manual rollback: bash $stage/rollback.sh $backup"
