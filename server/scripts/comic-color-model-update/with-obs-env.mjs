// Read only OBS variables from the running service; never print its environment.
import { readFile } from 'node:fs/promises';
const pid = process.argv[2];
if (!/^[1-9][0-9]*$/.test(pid || '')) throw Error('Invalid service PID');
const raw = await readFile(`/proc/${pid}/environ`, 'utf8');
for (const entry of raw.split('\0')) {
  const split = entry.indexOf('=');
  const key = entry.slice(0,split);
  if (/^HUAWEICLOUD_OBS_(ENDPOINT|REGION|BUCKET|AK|SK)$/.test(key)) process.env[key] = entry.slice(split+1);
}
process.argv = [process.execPath, 'publish-comic-color-models.mjs', ...process.argv.slice(3)];
await import('../publish-comic-color-models.mjs');
