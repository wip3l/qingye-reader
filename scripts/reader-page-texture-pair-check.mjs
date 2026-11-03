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
const methodStart = readerSource.indexOf('  async warmReaderPageTexture(');
const warmMethod = readerSource.slice(methodStart, readerSource.indexOf('\n  }', methodStart) + 4);
const Cache = vm.runInNewContext(stripTypeScriptTypes(fs.readFileSync(
  new URL('../entry/src/main/ets/core/reader/ReaderPageTextureCache.ets', import.meta.url), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '')) + '\nReaderPageTextureCache');
const Reader = vm.runInNewContext(stripTypeScriptTypes(`class Reader { ${warmMethod} }; Reader`), {
  ReaderPageTexturePair: Pair, ReaderRenderFrame: { wait: async () => {} },
});
function readerFixture() {
  const reader = new Reader();
  Object.assign(reader, { readerPageVisible: true, readerInitialPageReady: true,
    usesReaderPageCurlCanvas: () => true, pageSlideDirection: 0, isPageTurning: false, isTtsSpeaking: false,
    hasReaderTextSelection: () => false, isLandscapeDoublePageActive: () => true,
    readerSettledTextureKey: direction => `leaf-${direction}`, readerPageTextureWarmSerial: 1,
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
preparedRight.release(); preparedLeft.release(); warm.readerPageTextureCache.clear();
assert(bitmaps.slice(warmStart).every(target => target.releases === 1));
const stale = readerFixture(); const staleStart = bitmaps.length;
stale.getUIContext = () => ({ getComponentSnapshot: () => ({ get: async () => {
  const map = nativeBitmap(); stale.readerPageTextureWarmSerial++; return map;
} }) });
await stale.warmReaderPageTexture(1);
assert.equal(stale.readerPageTextureCache.acquire('leaf-1'), null);
assert(bitmaps.slice(staleStart).every(target => target.releases === 1), 'late captures cannot leak or replace live leaves');
console.log('PASS: paired reader warm-up, stale capture cleanup and cache ownership transfer');
