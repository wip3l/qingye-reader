import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const source = fs.readFileSync(new URL('../entry/src/main/ets/core/reader/ReaderPageTexturePair.ets', import.meta.url), 'utf8');
const Pair = vm.runInNewContext(stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, '')) + '\nReaderPageTexturePair');
let captures = 0, clones = 0;
const bitmaps = [];
function bitmap() {
  const result = { releases: 0, crop: 0, getPixelBytesNumber: () => 4 * 1024 * 1024,
    release() { this.releases++; return Promise.resolve(); },
    clone() { clones++; return Promise.resolve(bitmap()); } };
  bitmaps.push(result); return result;
}
const capture = async () => { captures++; return bitmap(); };
const crop = async (target, direction) => { target.crop = direction; };
const pair = await Pair.capture(capture, crop);
assert.equal(captures, 1); assert.equal(clones, 1);
assert.notEqual(pair.left, pair.right);
assert.equal(pair.right.crop, 1); assert.equal(pair.left.crop, -1);
pair.release(); pair.release();
assert.equal(pair.right.releases, 1); assert.equal(pair.left.releases, 1);
for (const failDirection of [1, -1]) {
  const before = bitmaps.length;
  await assert.rejects(Pair.capture(capture, async (target, direction) => {
    target.crop = direction; if (direction === failDirection) throw new Error('crop failed');
  }), /crop failed/);
  assert(bitmaps.slice(before).every(target => target.releases === 1), 'failure releases both owned maps once');
}
const broken = bitmap(); broken.clone = () => Promise.reject(new Error('clone failed'));
await assert.rejects(Pair.capture(async () => broken, crop), /clone failed/);
assert.equal(broken.releases, 1);
const large = bitmap(); large.getPixelBytesNumber = () => 24 * 1024 * 1024;
const beforeCaptures = captures, beforeClones = clones;
const boundedPair = await Pair.capture(async () => { captures++; return captures === beforeCaptures + 1 ? large : bitmap(); }, crop);
assert.equal(captures - beforeCaptures, 2, 'large surfaces use sequential capture to bound temporary memory');
assert.equal(clones, beforeClones);
assert.equal(boundedPair.right.crop, 1); assert.equal(boundedPair.left.crop, -1); boundedPair.release();
console.log('PASS: one capture for both leaves, independent crops and complete failure/stale cleanup');

// Execute the real reader warm-up transaction: cancellation must release maps instead of caching stale leaves.
const readerSource = fs.readFileSync(new URL('../entry/src/main/ets/pages/ReadBook.ets', import.meta.url), 'utf8');
function readerMethod(signature) {
  const start = readerSource.indexOf(signature);
  assert(start >= 0, `ReadBook.ets no longer defines ${signature.trim()}`);
  return readerSource.slice(start, readerSource.indexOf('\n  }', start) + 4);
}
const warmMethod = ['  async warmReaderPageTexture(', '  private settledPageTextureStillWanted(',
  '  private async snapshotSettledPage(', '  private async captureSettledPageTexture(',
  '  private async captureSettledPageTexturePair(']
  .map(readerMethod).join('\n');
const Cache = vm.runInNewContext(stripTypeScriptTypes(fs.readFileSync(
  new URL('../entry/src/main/ets/core/reader/ReaderPageTextureCache.ets', import.meta.url), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '')) + '\nReaderPageTextureCache');
let frameWaits = 0;
const Reader = vm.runInNewContext(stripTypeScriptTypes(`class Reader { ${warmMethod} }; Reader`), {
  ReaderPageTexturePair: Pair, ReaderRenderFrame: { wait: async () => { frameWaits++; } },
});
function readerFixture() {
  const reader = new Reader();
  Object.assign(reader, { readerPageVisible: true, readerInitialPageReady: true,
    usesReaderPageCurlCanvas: () => true, pageSlideDirection: 0, isPageTurning: false, isTtsSpeaking: false,
    hasReaderTextSelection: () => false, isLandscapeDoublePageActive: () => true,
    readerSettledTextureKey: direction => `leaf-${direction}`, readerPageTextureWarmSerial: 1,
    readerPageTextureWarmInflight: new Map(), rasterSettledPageTexture: () => null,
    readerPageTextureCache: new Cache(), readerPageCurlSnapshotScale: () => 0.75,
    currentReaderSnapshotComponentId: () => 'current', cropReaderPageCurlFrontToTurningLeaf: crop,
    getUIContext: () => ({ getComponentSnapshot: () => ({ get: async () => {
      const map = bitmap(); map.getImageInfo = async () => ({ size: { width: 50, height: 100 } }); return map;
    } }) }),
  });
  return reader;
}
const warm = readerFixture(); const warmStart = bitmaps.length;
const nativeBitmap = () => {
  const map = bitmap();
  map.getImageInfo = async () => ({ size: { width: 50, height: 100 } });
  map.clone = async () => { clones++; return nativeBitmap(); }; return map;
};
warm.getUIContext = () => ({ getComponentSnapshot: () => ({ get: async () => nativeBitmap() }) });
await warm.warmReaderPageTexture(1);
const preparedRight = warm.readerPageTextureCache.acquire('leaf-1');
const preparedLeft = warm.readerPageTextureCache.acquire('leaf--1');
assert(preparedRight && preparedLeft); assert.equal(bitmaps.length - warmStart, 2);
assert.equal(frameWaits, 1, 'one completed frame flushes the settled surface (opacity 0 during the turn) before the snapshot');
preparedRight.release(); preparedLeft.release(); warm.readerPageTextureCache.clear();
assert(bitmaps.slice(warmStart).every(target => target.releases === 1));
const stale = readerFixture(); const staleStart = bitmaps.length;
stale.getUIContext = () => ({ getComponentSnapshot: () => ({ get: async () => {
  const map = nativeBitmap(); stale.readerPageTextureCache.clear(); return map;
} }) });
await stale.warmReaderPageTexture(1);
assert.equal(stale.readerPageTextureCache.acquire('leaf-1'), null);
assert(bitmaps.slice(staleStart).every(target => target.releases === 1), 'late captures cannot leak or replace live leaves');
assert.equal(stale.readerPageTextureWarmInflight.size, 0, 'finished captures leave the in-flight table');

// A turn that starts while RenderService is still rendering the warm snapshot does not change the settled page:
// the result is kept for that turn instead of being thrown away and captured a second time.
const turning = readerFixture(); const turningStart = bitmaps.length;
turning.getUIContext = () => ({ getComponentSnapshot: () => ({ get: async () => {
  const map = nativeBitmap(); turning.pageSlideDirection = 1; turning.isPageTurning = true; return map;
} }) });
await turning.warmReaderPageTexture(1);
const keptRight = turning.readerPageTextureCache.acquire('leaf-1');
const keptLeft = turning.readerPageTextureCache.acquire('leaf--1');
assert(keptRight && keptLeft, 'a turn starting during the warm snapshot keeps both leaves');
keptRight.release(); keptLeft.release(); turning.readerPageTextureCache.clear();
assert(bitmaps.slice(turningStart).every(target => target.releases === 1));

// The page-keyed node may reach the tree a frame later than the warm-up request: retry after one frame.
const late = readerFixture(); const lateStart = bitmaps.length; let lateGets = 0;
late.getUIContext = () => ({ getComponentSnapshot: () => ({ get: async () => {
  if (++lateGets === 1) throw new Error('100001: node not found');
  return nativeBitmap();
} }) });
frameWaits = 0;
await late.warmReaderPageTexture(1);
assert.equal(lateGets, 2); assert.equal(frameWaits, 2, 'the flush frame plus one frame wait per missing-node failure');
const lateRight = late.readerPageTextureCache.acquire('leaf-1');
assert(lateRight, 'the retried snapshot is cached'); lateRight.release(); late.readerPageTextureCache.clear();
assert(bitmaps.slice(lateStart).every(target => target.releases === 1));
const gone = readerFixture(); let goneGets = 0;
gone.getUIContext = () => ({ getComponentSnapshot: () => ({ get: async () => {
  goneGets++; throw new Error('100001: node not found');
} }) });
frameWaits = 0;
await gone.warmReaderPageTexture(1).catch(() => {});
assert(goneGets <= 4 * 2 && frameWaits <= 4 * 2, 'a node that never appears is given up on after a few frames');
assert.equal(gone.readerPageTextureWarmInflight.size, 0);

// A second warm-up (or a turn) for the same page waits for the snapshot already in flight.
const shared = readerFixture(); let pendingGets = 0; let resolveGet = null;
shared.getUIContext = () => ({ getComponentSnapshot: () => ({ get: () => {
  pendingGets++; return new Promise(resolve => { resolveGet = () => resolve(nativeBitmap()); });
} }) });
const firstWarm = shared.warmReaderPageTexture(1);
await new Promise(resolve => setTimeout(resolve, 0));
assert.equal(shared.readerPageTextureWarmInflight.size, 2, 'both leaf keys point at the one in-flight snapshot');
shared.readerPageTextureWarmSerial = 2;
const secondWarm = shared.warmReaderPageTexture(2);
await new Promise(resolve => setTimeout(resolve, 0));
assert.equal(pendingGets, 1, 'no second RenderService snapshot while one is in flight');
resolveGet(); await Promise.all([firstWarm, secondWarm]);
assert.equal(pendingGets, 1);
assert.equal(shared.readerPageTextureWarmInflight.size, 0);
const sharedRight = shared.readerPageTextureCache.acquire('leaf-1');
assert(sharedRight, 'the shared snapshot lands in the cache once'); sharedRight.release();
console.log('PASS: paired reader warm-up, invalidated capture cleanup, kept mid-turn result and in-flight sharing');
