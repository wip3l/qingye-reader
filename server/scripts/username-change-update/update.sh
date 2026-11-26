#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
mode=apply
case "${1:-}" in '') ;; --check) mode=check ;; *) echo 'Usage: bash update.sh [--check]' >&2; exit 1 ;; esac
(cd "$stage" && sha256sum --quiet -c SHA256SUMS)
systemctl is-active --quiet "$service"
test -f "$live/package.json" && test -d "$live/node_modules"
for name in "${patched[@]}" accountCredentials.js; do test -f "$live/$name" && test ! -L "$live/$name"; done
# 031 must already be in place: the change edits its username columns.
test "$("${psql[@]}" -c "SELECT count(*) FROM information_schema.columns WHERE table_schema='public'
  AND table_name='app_users' AND column_name IN ('username','username_key','password_hash')")" = 3

backup=$(mktemp -d /root/qingye-username-change-backup.XXXXXX)
mkdir "$backup/candidate"
for name in "${patched[@]}"; do cp -p "$live/$name" "$backup/$name"; done
(cd "$backup" && sha256sum "${patched[@]}" > ORIGINAL_SHA256SUMS)
# Exits with BASELINE_MISMATCH before anything live changes when the installed module differs.
"$node" "$stage/patch.mjs" "$backup" "$backup/candidate"
for name in "${patched[@]}"; do "$node" --input-type=module --check < "$backup/candidate/$name"; done
# The patched module may differ from a reference build in whitespace only, never in code.
matched=''
for ref in "${references[@]}"; do
  if [ "$(code_sum "$backup/candidate/accountAuth.js")" = "$(code_sum "$stage/$ref")" ]; then matched=$ref; fi
done
[ -n "$matched" ] || {
  echo 'PATCH_RESULT_MISMATCH: patched accountAuth.js matches no reference build beyond whitespace; no live files changed' >&2
  exit 1; }
echo "Patched accountAuth.js matches $matched"

# Preflight copy of the whole runtime with the candidate on top; postgres must be able to read it.
preview=$(umask 022 && mktemp -d /tmp/qingye-username-change-preflight.XXXXXX)
trap 'rm -rf -- "$preview"' EXIT
chmod 755 "$preview"
cp "$live"/*.js "$preview/"
cp "$backup/candidate"/* "$preview/"
cp "$live/package.json" "$preview/package.json"
ln -s "$live/node_modules" "$preview/node_modules"
mkdir "$preview/migrations"
cp "$stage/test-migrations"/*.sql "$preview/migrations/"
chmod -R a+rX "$preview"
(cd "$preview" && "$node" "$stage/check.mjs")
# The real rename, cooldown and race paths against real PostgreSQL, in a new disposable database only.
(cd "$preview" && runuser -u postgres -- "$node" --input-type=module < "$stage/username-change-pg-check.mjs")
echo "Backup: $backup"
if [ "$mode" = check ]; then echo 'PASS: preflight only; database and service unchanged'; exit 0; fi

# Transactional and rerunnable: one nullable column on app_users, covered by the existing table grants.
for file in "${migrations[@]}"; do "${psql[@]}" < "$stage/migrations/$file" > /dev/null; done
test "$(column_present)" = 1

same=1
for name in "${patched[@]}"; do cmp -s "$backup/candidate/$name" "$live/$name" || same=0; done
if [ "$same" -eq 1 ]; then echo 'Already installed; migration checked, no restart needed.'; exit 0; fi

changed=0
finish() {
  code=$?
  trap - EXIT
  rm -rf -- "$preview"
  if [ "$code" -ne 0 ] && [ "$changed" -eq 1 ]; then
    echo "Update failed; restoring files from $backup (database column retained)" >&2
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
for name in "${patched[@]}"; do
  cat "$backup/candidate/$name" > "$live/$name"
  cmp "$backup/candidate/$name" "$live/$name"
done
systemctl start "$service"
health
pid=$(systemctl show "$service" -p MainPID --value)
restarts=$(systemctl show "$service" -p NRestarts --value)
# The new route is mounted and needs a session; the existing ones still answer.
for path in /v1/account/username /v1/account/password; do
  status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
    -X POST -H 'Content-Type: application/json' --data '{}' "http://127.0.0.1:8080$path")
  test "$status" = 401 || { echo "Unexpected status $status for $path" >&2; exit 1; }
done
status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
  http://127.0.0.1:8080/v1/account/login-methods)
test "$status" = 401
curl -q --proxy '' --noproxy '*' --fail --silent --max-time 10 https://qingye.icynol.com/health | json_ok
sleep 3
systemctl is-active --quiet "$service"
test "$(systemctl show "$service" -p MainPID --value)" = "$pid"
test "$(systemctl show "$service" -p NRestarts --value)" = "$restarts"
echo 'PASS: username change installed'
echo "Manual rollback: bash $stage/rollback.sh $backup"
