#!/usr/bin/env bash
set -Eeuo pipefail
stage=$(cd -- "$(dirname -- "$0")" && pwd -P)
source "$stage/common.sh"
(cd "$stage" && sha256sum -c SHA256SUMS)
backup=$(realpath -e -- "${1:?Pass the backup directory printed by update.sh}")
case "$backup" in /root/qingye-reading-stats-backup.*) ;; *) echo 'Unexpected backup directory' >&2; exit 1;; esac
(cd "$backup" && sha256sum -c ORIGINAL_SHA256SUMS)
(cd "$backup/candidate" && sha256sum -c SHA256SUMS)
for name in index.js readingStats.js; do
  test -f "$live/$name" && test ! -L "$live/$name"
  cmp "$backup/candidate/$name" "$live/$name"
done
"$node" --input-type=module --check < "$backup/index.js"
systemctl stop "$service"
test "$(systemctl show "$service" -p MainPID --value)" = 0
restore_files
systemctl start "$service"
health
echo 'PASS: previous code restored; reading statistics tables retained'
