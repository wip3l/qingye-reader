import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { harness } from './lib/reader-cache-test-harness.mjs';

const h = harness();
const root = '/cache/comic_images/';
const original = root + '12345678.jpg';
const color = root + 'color_version_' + 'a'.repeat(64) + '.jpg';
h.put(original, 100); h.put(color, 200);
h.put(root + 'inflight.jpg.tmp', 9999, 0); h.put(root + 'inflight.jpg.part', 9999, 0);
assert.equal(await h.Budget.comicUsageBytes(), 300);
const initialScans = h.metrics.scans;
const sr = root + 'sr_' + 'b'.repeat(64) + '.jpg'; h.put(sr, 300, 0);
h.Budget.noteComicWrite(sr); await h.Budget.chain;
const total = () => [...h.Budget.comicIndex.values()].reduce((sum, item) => sum + item.bytes, 0);
assert.equal(total(), 600);
assert.equal(h.metrics.scans, initialScans, 'completed write is accounted without directory enumeration');
h.put(sr, 350, 0); h.Budget.noteComicWrite(sr); await h.advance(15000);
assert.equal(total(), 650); assert.equal(h.metrics.scans, initialScans);
h.Budget.touchComicFile(original);
assert.equal((await h.Budget.clearComic()).removed, 1);
assert.ok(!h.files.has(color)); assert.equal(total(), 450);

h.put(root + 'legacy.png', 75); h.Budget.noteComicWrite(); await h.advance(15000);
assert.equal(total(), 525);
const beforeTTL = h.metrics.scans;
h.files.delete(root + 'legacy.png'); h.age(300001);
h.Budget.noteComicWrite(sr); await h.advance(15000);
assert.ok(h.metrics.scans > beforeTTL); assert.equal(total(), 450);
const racing = root + 'racing.jpg'; h.put(racing, 10);
h.onStat(async path => { if (path === racing) h.Budget.touchComicFile(path); });
await h.Budget.clearComic(); assert.ok(h.files.has(racing)); h.onStat(null);

let written;
h.onStat(async path => {
  if (path === original && !written) { written = root + 'during-scan.jpg'; h.put(written, 10, 0); h.Budget.noteComicWrite(written); }
});
await h.Budget.comicUsageBytes(); await h.Budget.chain;
assert.ok(h.Budget.comicIndex.has(written), 'writes during an asynchronous directory scan are indexed afterwards');
h.onStat(null);
const notifications = [];
h.Budget.noteComicWrite = value => notifications.push(value);
h.load('utils/AppAiHost.ets');
const Host = vm.runInContext('AppAiHost', h.context);
new Host().noteComicWrite('/cache/comic_images/done.jpg'); new Host().noteComicWrite();
assert.deepEqual(notifications, ['/cache/comic_images/done.jpg', undefined]);
const release = new Host().retainComicFile(original);
assert.ok(h.Coordinator.fileInUse(original)); release(); assert.ok(!h.Coordinator.fileInUse(original));
const ability = fs.readFileSync(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
assert.match(ability, /onMemoryLevel\(level: AbilityConstant.MemoryLevel\): void\s*\{\s*ComicColorizer.onMemoryPressure\(level\)/);
assert.match(ability, /onForeground\(\): void\s*\{\s*ReaderCacheBudget.scheduleStartupTrim/);
h.close();
console.log('AI host: incremental accounting, overwrite, TTL, recent-use/scan races, file leases and lifecycle forwarding passed.');
