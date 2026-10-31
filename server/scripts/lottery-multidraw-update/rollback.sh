#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
backup=$(realpath -e -- "${1:?Pass the backup directory printed by update.sh}")
case "$backup" in /root/qingye-lottery-multidraw-backup.*) ;; *) echo 'Unexpected backup directory' >&2; exit 1;; esac
(cd "$backup" && sha256sum --quiet -c ORIGINAL_SHA256SUMS)
# Refuse to undo anything installed after this update.
for name in "${replaced[@]}"; do cmp "$backup/candidate/$name" "$live/$name"; done
for name in "${replaced[@]}"; do "$node" --input-type=module --check < "$backup/$name"; done
systemctl stop "$service"
test "$(systemctl show "$service" -p MainPID --value)" = 0
restore_files
systemctl start "$service"
if health; then
  systemctl is-active --quiet "$service"
  echo 'PASS: single-draw lottery modules restored (draw records and coupons kept)'
  exit 0
fi
echo "Files restored, but service health needs attention: $backup" >&2
exit 1
