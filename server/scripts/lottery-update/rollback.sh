#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
backup=$(realpath -e -- "${1:?Pass the backup directory printed by update.sh}")
case "$backup" in /root/qingye-lottery-backup.*) ;; *) echo 'Unexpected backup directory' >&2; exit 1;; esac
(cd "$backup" && sha256sum --quiet -c ORIGINAL_SHA256SUMS)
# Refuse to undo anything installed after this update.
for name in "${patched[@]}" "${added[@]}"; do
  cmp "$backup/candidate/$name" "$live/$name"
done
cmp "$backup/environment.candidate" "$env_file"
for name in "${patched[@]}"; do "$node" --input-type=module --check < "$backup/$name"; done
systemctl stop "$service"
test "$(systemctl show "$service" -p MainPID --value)" = 0
restore_files
systemctl start "$service"
if health; then
  systemctl is-active --quiet "$service"
  echo 'PASS: previous modules and environment restored (lottery tables and coupons kept)'
  exit 0
fi
echo "Files restored, but service health needs attention: $backup" >&2
exit 1
