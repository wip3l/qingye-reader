#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
mode=apply
case "${1:-}" in '') ;; --check) mode=check ;; *) echo 'Usage: bash update.sh [--check]' >&2; exit 1 ;; esac
(cd "$stage" && sha256sum --quiet -c SHA256SUMS)
systemctl is-active --quiet "$service"
for name in "${patched[@]}"; do test -f "$live/$name" && test ! -L "$live/$name"; done
# 033 reads the coupon amount recorded on orders by migration 026.
test "$("${psql[@]}" -c "SELECT count(*) FROM information_schema.columns
  WHERE table_name = 'membership_orders' AND column_name = 'coupon_points'")" = 1

backup=$(mktemp -d /root/qingye-coupon-upgrade-credit-backup.XXXXXX)
mkdir "$backup/candidate"
for name in "${patched[@]}"; do cp -p "$live/$name" "$backup/$name"; done
(cd "$backup" && sha256sum "${patched[@]}" > ORIGINAL_SHA256SUMS)
# Exits with BASELINE_MISMATCH (naming the change it cannot place) before anything live changes.
"$node" "$stage/patch.mjs" "$backup" "$backup/candidate"
for name in "${patched[@]}"; do "$node" --input-type=module --check < "$backup/candidate/$name"; done
# The live module is not byte-identical to any clean build, so the patched copy is verified by running it.
"$node" "$stage/check.mjs" "$backup/candidate"
echo "Backup: $backup"
echo "Memberships whose upgrade credit will be corrected: $(pending_credits)"
if [ "$mode" = check ]; then echo 'PASS: preflight only; database and service unchanged'; exit 0; fi

same=1
for name in "${patched[@]}"; do cmp -s "$backup/candidate/$name" "$live/$name" || same=0; done
if [ "$same" -eq 1 ]; then
  for file in "${migrations[@]}"; do "${psql[@]}" < "$stage/migrations/$file" > /dev/null; done
  test "$(pending_credits)" = 0
  echo 'Already installed; migration checked, no restart needed.'
  exit 0
fi

changed=0
finish() {
  code=$?
  trap - EXIT
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
for name in "${patched[@]}"; do
  cat "$backup/candidate/$name" > "$live/$name"
  cmp "$backup/candidate/$name" "$live/$name"
done
# Run while the service is stopped, so no purchase made by the old code can slip in after the correction.
# Transactional and rerunnable.
for file in "${migrations[@]}"; do "${psql[@]}" < "$stage/migrations/$file" > /dev/null; done
test "$(pending_credits)" = 0
systemctl start "$service"
health
pid=$(systemctl show "$service" -p MainPID --value)
restarts=$(systemctl show "$service" -p NRestarts --value)
status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
  http://127.0.0.1:8080/v1/membership)
test "$status" = 401
curl -q --proxy '' --noproxy '*' --fail --silent --max-time 10 https://qingye.icynol.com/health | json_ok
sleep 3
systemctl is-active --quiet "$service"
test "$(systemctl show "$service" -p MainPID --value)" = "$pid"
test "$(systemctl show "$service" -p NRestarts --value)" = "$restarts"
echo 'PASS: coupon upgrade credit installed'
echo "Manual rollback: bash $stage/rollback.sh $backup"
