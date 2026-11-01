#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
mode=apply
case "${1:-}" in '') ;; --check) mode=check ;; *) echo 'Usage: bash update.sh [--check]' >&2; exit 1 ;; esac
(cd "$stage" && sha256sum --quiet -c SHA256SUMS)
systemctl is-active --quiet "$service"
test -f "$live/package.json" && test -d "$live/node_modules"
installed=1
for name in "${replaced[@]}"; do
  test -f "$live/$name" && test ! -L "$live/$name"
  sum=$(lf_sum "$live/$name")
  if [ "$sum" = "$(sed -n "s/^target $name //p" "$stage/BASELINE")" ]; then continue; fi
  installed=0
  if [ "$sum" != "$(sed -n "s/^baseline $name //p" "$stage/BASELINE")" ]; then
    echo "BASELINE_MISMATCH: $live/$name is not the membership routes build from the super theme update; no live files changed" >&2
    exit 1
  fi
done
# The new route reads these; membershipService.js must already export the two helpers it imports.
test "$("${psql[@]}" -c "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN
  ('app_users','membership_accounts','membership_periods','account_debts');")" = 4
grep -q 'export async function readMembership' "$live/membershipService.js"
grep -q 'export async function membershipPriority' "$live/membershipService.js"

backup=$(mktemp -d /root/qingye-mimo-key-backup.XXXXXX)
mkdir "$backup/candidate"
for name in "${replaced[@]}"; do
  cp -p "$live/$name" "$backup/$name"
  cp "$stage/runtime/$name" "$backup/candidate/$name"
  "$node" --input-type=module --check < "$backup/candidate/$name"
done
(cd "$backup" && sha256sum "${replaced[@]}" > ORIGINAL_SHA256SUMS)

# Preflight copy of the whole runtime with the candidates on top; postgres must be able to read it.
preview=$(umask 022 && mktemp -d /tmp/qingye-mimo-key-preflight.XXXXXX)
trap 'rm -rf -- "$preview"' EXIT
chmod 755 "$preview"
cp "$live"/*.js "$preview/"
cp "$backup/candidate"/*.js "$preview/"
cp "$live/package.json" "$preview/package.json"
ln -s "$live/node_modules" "$preview/node_modules"
mkdir "$preview/migrations"
cp "$stage/test-migrations"/*.sql "$preview/migrations/"
chmod -R a+rX "$preview"
systemd-run --quiet --wait --pipe -p EnvironmentFile="$env_file" -p WorkingDirectory="$preview" "$node" "$stage/check.mjs"
# The real route against real PostgreSQL, in a new disposable database only.
(cd "$preview" && runuser -u postgres -- "$node" --input-type=module < "$stage/mimo-key-pg-check.mjs")
echo "Backup: $backup"
if [ "$mode" = check ]; then echo 'PASS: preflight only; database and service unchanged'; exit 0; fi

# Transactional and rerunnable; only creates two new tables.
for file in "${migrations[@]}"; do "${psql[@]}" < "$stage/migrations/$file" > /dev/null; done
test "$("${psql[@]}" -c "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN
  ('shared_provider_keys','shared_provider_key_grants');")" = 2
if [ "$installed" -eq 1 ]; then echo 'Already installed; migration checked, no restart needed.'; exit 0; fi

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
  cat "$backup/candidate/$name" > "$live/$name"
  cmp "$backup/candidate/$name" "$live/$name"
done
systemctl start "$service"
health
pid=$(systemctl show "$service" -p MainPID --value)
restarts=$(systemctl show "$service" -p NRestarts --value)
# The new route exists and refuses a request without a session.
status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
  -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:8080/v1/membership/mimo-key)
test "$status" = 401
curl -q --proxy '' --noproxy '*' --fail --silent --max-time 10 https://qingye.icynol.com/health | json_ok
sleep 3
systemctl is-active --quiet "$service"
test "$(systemctl show "$service" -p MainPID --value)" = "$pid"
test "$(systemctl show "$service" -p NRestarts --value)" = "$restarts"
echo 'PASS: lifetime MiMo key route installed'
if [ "$("${psql[@]}" -c "SELECT count(*) FROM shared_provider_keys WHERE provider='mimo' AND enabled")" = 0 ]; then
  echo 'NEXT: no MiMo key stored yet; insert it with the SQL in README.md before members can use one-click fill.'
fi
echo "Manual rollback: bash $stage/rollback.sh $backup"
