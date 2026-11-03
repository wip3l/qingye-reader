import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const text = fs.readFileSync(new URL('../entry/src/main/ets/core/reader/ReaderPageTextureCache.ets', import.meta.url), 'utf8');
const Cache = vm.runInNewContext(stripTypeScriptTypes(text.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' }) + '\nReaderPageTextureCache');
function bitmap() { return { releases: 0, release() { this.releases++; return Promise.resolve(); } }; }
const cache = new Cache();
const front = bitmap(), second = bitmap(), third = bitmap();
const lease = cache.put('front', front, 4);
cache.put('second', second, 4).release();
cache.put('third', third, 4).release();
assert.equal(cache.acquire('front'), null, 'oldest cached entry is evicted');
assert.equal(front.releases, 0, 'an active draw lease survives eviction');
lease.release(); lease.release();
assert.equal(front.releases, 1, 'the underlying bitmap is released exactly once');
const draw = cache.acquire('second');
cache.clear();
assert.equal(second.releases, 0, 'clearing a cache cannot invalidate an active frame');
assert.equal(third.releases, 1);
draw.release(); assert.equal(second.releases, 1);
assert.equal(cache.bytes, 0);

const old = bitmap(), fresh = bitmap();
const oldLease = cache.put('same', old, 100);
const replacement = cache.put('same', fresh, 100);
assert.equal(old.releases, 0);
oldLease.release(); assert.equal(old.releases, 1);
replacement.release(); cache.clear(); assert.equal(fresh.releases, 1);

const huge = bitmap();
const hugeLease = cache.put('oversized', huge, 25 * 1024 * 1024);
assert.equal(cache.acquire('oversized'), null, 'oversized frames are not retained as idle cache');
assert.equal(huge.releases, 0); hugeLease.release(); assert.equal(huge.releases, 1);
assert.equal(cache.bytes, 0);
console.log('PASS: bounded page texture cache, active-frame leases, replacement, eviction and idempotent release');
