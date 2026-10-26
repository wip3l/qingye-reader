#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export NO_PROXY='*' no_proxy='*'
test "$(id -u)" -eq 0
mode=${1:-apply}
case "$mode" in apply|--check) ;; *) echo 'Usage: bash scripts/comic-color-model-update/update.sh [--check]' >&2; exit 1;; esac
stage=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
live=/www/wwwroot/qingye.icynol.com
node=/www/server/nodejs/v22.23.1/bin/node
service=legado-account.service
names=(index.js comicColorModels.js comicColorModelRoutes.js)
exec 9>/root/qingye-comic-color-model-update.lock
flock -n 9
(cd "$stage" && sha256sum -c SHA256SUMS)
test -x "$node"
test "$(systemctl show "$service" -p WorkingDirectory --value)" = "$live"
systemctl is-active --quiet "$service"
test -f "$live/index.js" && test ! -L "$live/index.js"
test -d "$live/node_modules"
for name in "${names[@]}"; do test ! -L "$live/$name"; done
backup=$(mktemp -d /root/qingye-comic-color-model-backup.XXXXXX)
mkdir "$backup/candidate"
for name in "${names[@]}"; do
  if [ -f "$live/$name" ]; then cp -p "$live/$name" "$backup/$name"; else touch "$backup/$name.absent"; fi
done
"$node" "$stage/scripts/comic-color-model-update/patch.mjs" "$backup" "$backup/candidate"
for name in comicColorModels.js comicColorModelRoutes.js; do cp "$stage/dist/$name" "$backup/candidate/$name"; done
for name in "${names[@]}"; do "$node" --input-type=module --check < "$backup/candidate/$name"; done
"$node" "$stage/scripts/publish-comic-color-models.mjs" "$stage/models"
echo "Backup: $backup"
if [ "$mode" = --check ]; then echo 'PASS: preflight; no upload or service restart'; exit 0; fi
# The upload SDK resolves from the existing deployment; no npm install or new secrets.
test ! -e "$stage/node_modules" || test -L "$stage/node_modules"
if [ ! -e "$stage/node_modules" ]; then ln -s "$live/node_modules" "$stage/node_modules"; fi
pid=$(systemctl show "$service" -p MainPID --value)
"$node" "$stage/scripts/comic-color-model-update/with-obs-env.mjs" "$pid" "$stage/models" --upload
if cmp -s "$backup/candidate/index.js" "$live/index.js" &&
   cmp -s "$backup/candidate/comicColorModels.js" "$live/comicColorModels.js" &&
   cmp -s "$backup/candidate/comicColorModelRoutes.js" "$live/comicColorModelRoutes.js"; then
  echo 'PASS: models verified; API already installed, no restart needed'; exit 0
fi
health() {
  for attempt in {1..20}; do
    if curl -q --proxy '' --noproxy '*' --fail --silent --max-time 3 http://127.0.0.1:8080/health | "$node" -e \
      'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{try{process.exit(JSON.parse(s).ok===true?0:1)}catch{process.exit(1)}})'; then return 0; fi
    sleep 1
  done
  return 1
}
changed=0
finish() {
  code=$?
  trap - EXIT
  if [ "$code" -ne 0 ] && [ "$changed" -eq 1 ]; then
    echo "Update failed; restoring $backup" >&2
    if systemctl stop "$service" && [ "$(systemctl show "$service" -p MainPID --value)" = 0 ]; then
      for name in "${names[@]}"; do
        if [ -f "$backup/$name.absent" ]; then rm -f -- "$live/$name"; else cp -p "$backup/$name" "$live/$name"; fi
      done
      systemctl start "$service" && health || echo "Recovery needs attention: $backup" >&2
    else echo "Unable to stop service for recovery: $backup" >&2; fi
  fi
  exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for name in "${names[@]}"; do
  if [ -f "$backup/$name.absent" ]; then test ! -e "$live/$name"; else cmp "$backup/$name" "$live/$name"; fi
done
changed=1
systemctl stop "$service"
test "$(systemctl show "$service" -p MainPID --value)" = 0
for name in "${names[@]}"; do
  if [ -f "$backup/$name" ]; then cp -p "$backup/$name" "$backup/$name.install";
  else cp -p "$backup/index.js" "$backup/$name.install"; fi
  cat "$backup/candidate/$name" > "$backup/$name.install"
  cp -p "$backup/$name.install" "$live/$name"
done
systemctl start "$service"
health
status=$(curl -q --proxy '' --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 \
  -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:8080/v1/ai/color-models/alac.ms/download-ticket)
test "$status" = 401
echo 'PASS: models uploaded and verified; download API installed'
echo "Server backup: $backup"
