import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/pages/ReadBook.ets', import.meta.url), 'utf8');
function method(name) {
  const start = source.search(new RegExp(`^  (?:async )?${name}\\(`, 'm'));
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const jobs = [];
let clock = 0;
const Reader = vm.runInNewContext(stripTypeScriptTypes(`class Reader {
  ${['readerFlapPaperColor', 'prepareReaderPageCurlPalette', 'readerPageCurlNeedsBackSnapshot', 'isDarkHexColor', 'drawReaderPageCurl',
    'captureReaderPageCurlSnapshots', 'resetReaderPageCurl', 'isCrossChapterPreviewWithinGrace',
    'ensureReaderPageCurlReady', 'requestReaderPageCurlCapture'].map(method).join('\n')}
}; Reader`), { console, px2vp: n => n, setTimeout: fn => jobs.push(fn), sleepMs: async () => { clock += 16; },
  Date: { now: () => clock }, READER_CROSS_CHAPTER_PREVIEW_GRACE_MS: 160,
  ReaderRenderFrame: { wait: async () => {} }, READER_CURL_REGION_UNSET: -1,
  ReaderEmulationFlipRegion: { BOTTOM: 2 } });

function fixture(threeD, theme) {
  const p = new Reader(), paints = [], bitmaps = [];
  let reads = 0, progress = 0, duringCapture = () => {};
  Object.assign(p, {
    appDarkMode: false, readerPageCurlCaptureSerial: 1, readerPageCurlCaptureKey: 'turn',
    readerPageCurlCapturePending: true, readerPageCurlSnapshotReady: false,
    readerPageCurlCanvasReady: true, pageSlideDirection: 1, pageTurnPreviewLoadingKey: '',
    readerPageCurlFront: null, readerPageCurlFrontLease: null, readerPageCurlBack: null,
    readerPageCurlAnimationSerial: 0, readerPageCurlContext: {}, readerCurlStartRegion: -1,
    currentReaderTheme: () => { reads++; return theme; },
    // A frame must never fall back to the expensive theme getters after snapshot publication.
    getBackgroundColor: () => { throw Error('theme lookup in animation frame'); },
    isReaderThemeDark: () => { throw Error('theme lookup in animation frame'); },
    is3DPageTurnAnimation: () => threeD, isLandscapeDoublePageActive: () => false,
    readerSettledTextureKey: () => 'front', readerPageTextureCache: { acquire: () => null },
    readerPageTextureWarmInflight: new Map(),
    currentReaderSnapshotComponentId: () => 'front', readerPageCurlSnapshotScale: () => 0.75,
    getPageTurnWidth: () => 600, getPageTurnHeight: () => 900, getReaderPageCurlCanvasHeight: () => 900,
    getPageTurnProgress: () => progress, getReaderPageColumnWidth: () => 600,
    getReaderDoublePageRightOrigin: () => 300, notifyReaderPageCurlCaptureWaiters() {},
    readerTurnTrace: { mark() {} },
    readerEmulationFlipPainter: { draw: (...args) => paints.push(args), clearCorner() {} },
    readerPageCurlPainter: { draw: (...args) => paints.push(args) },
    getUIContext: () => ({ vp2px: n => n * 2, getComponentSnapshot: () => ({ get: async () => {
      const bitmap = { releases: 0, getImageInfo: async () => ({ size: { width: 450, height: 675 } }),
        release() { this.releases++; return Promise.resolve(); } };
      bitmaps.push(bitmap); duringCapture(); return bitmap;
    } }) }),
  });
  return { p, paints, bitmaps, reads: () => reads, progress: n => { progress = n; },
    interrupt: fn => { duringCapture = fn; } };
}

for (const threeD of [false, true]) {
  const theme = { backgroundColor: '#F7F1E3', contentTone: 'light' };
  const h = fixture(threeD, theme);
  await h.p.captureReaderPageCurlSnapshots(1, 'turn');
  assert.equal(h.p.readerPageCurlSnapshotReady, true);
  assert.equal(h.bitmaps.length, threeD ? 1 : 2, '3D single-page turns never request the unused off-screen back');
  assert.equal(h.reads(), 1, 'one theme resolution per valid snapshot');
  for (let frame = 0; frame < 240; frame++) {
    h.progress(frame / 240); h.p.drawReaderPageCurl();
  }
  assert.equal(h.reads(), 1, '240 ordinary/3D animation frames perform no extra theme resolution');
  assert.equal(h.paints.length, 241);
  for (const args of h.paints) {
    assert.equal(args[threeD ? 13 : 8], false, 'daytime lighting stays identical');
    if (threeD) assert.equal(args[12], '#F7F1E3');
  }
  h.p.resetReaderPageCurl();
  assert.equal(h.p.readerPageCurlSnapshotReady, false);
  const before = h.paints.length; h.p.drawReaderPageCurl();
  assert.equal(h.paints.length, before, 'reset/hide cannot paint using stale textures or palette');
  theme.backgroundColor = '#101826'; theme.contentTone = 'dark';
  h.p.readerPageCurlCaptureKey = 'night'; h.p.pageSlideDirection = -1;
  await h.p.captureReaderPageCurlSnapshots(h.p.readerPageCurlCaptureSerial, 'night');
  assert.equal(h.reads(), 2, 'next turn resolves the changed theme');
  const night = h.paints.at(-1);
  assert.equal(night[threeD ? 13 : 8], true);
  if (threeD) assert.equal(night[12], '#101826');
}
const double = fixture(true, { backgroundColor: '#FFFFFF', contentTone: 'light' });
double.p.isLandscapeDoublePageActive = () => true;
assert.equal(double.p.readerPageCurlNeedsBackSnapshot(), true, 'double-page folds still require the destination back');
const singleSurface = source.slice(source.indexOf('  readerSimulationSinglePageTurnSurface('),
  source.indexOf('  readerSimulationDoublePageTurnSurface('));
assert.match(singleSurface, /if \(this\.readerPageCurlNeedsBackSnapshot\(\)\) \{\s*Stack\(\)/,
  'the declarative back tree must follow the same snapshot requirement as capture');

for (const [color, tone, systemDark, paper, dark] of [
  ['', '', false, '#FFFFFF', false], ['#FFFFFF00', 'dark', false, '#FFFFFF', true],
  ['#000000', '', false, '#000000', true], ['rgb(12,12,12)', '', true, 'rgb(12,12,12)', true],
  ['#000000', 'light', true, '#000000', false],
]) {
  const h = fixture(true, { backgroundColor: color, contentTone: tone });
  h.p.appDarkMode = systemDark;
  await h.p.captureReaderPageCurlSnapshots(1, 'turn');
  assert.equal(h.paints.at(-1)[12], paper, 'transparent/missing paper fallback is preserved');
  assert.equal(h.paints.at(-1)[13], dark, 'explicit tone and color-mode fallback are preserved');
}
// A warm snapshot still in RenderService when the turn starts is awaited and reused, not captured again.
const shared = fixture(true, { backgroundColor: '#FFFFFF', contentTone: 'light' });
const warmBitmap = { releases: 0, getImageInfo: async () => ({ size: { width: 450, height: 675 } }),
  release() { this.releases++; return Promise.resolve(); } };
let warmLease = null;
shared.p.readerPageTextureCache = { acquire: () => warmLease };
shared.p.readerPageTextureWarmInflight.set('front', new Promise(resolve => setTimeout(() => {
  warmLease = { bitmap: warmBitmap, release() {} }; resolve();
}, 0)));
await shared.p.captureReaderPageCurlSnapshots(1, 'turn');
assert.equal(shared.p.readerPageCurlSnapshotReady, true);
assert.equal(shared.bitmaps.length, 0, 'the in-flight warm snapshot replaces a second RenderService capture');
assert.equal(shared.p.readerPageCurlFront, warmBitmap);

const stale = fixture(true, { backgroundColor: '#FFFFFF', contentTone: 'light' });
stale.interrupt(() => { stale.p.readerPageCurlCaptureSerial++; });
await stale.p.captureReaderPageCurlSnapshots(1, 'turn');
assert.equal(stale.reads(), 0, 'stale capture cannot publish its palette');
assert.equal(stale.paints.length, 0);
assert.equal(stale.bitmaps[0].releases, 1);
// A slow adjacent chapter waits only the short grace, then the loading leaf is turned instead of freezing the sheet.
function curlWaitFixture(previewStartedAt) {
  const p = new Reader();
  Object.assign(p, {
    pageSlideDirection: 1, readerPageCurlCaptureKey: 'loading-leaf', readerPageCurlSnapshotReady: true,
    readerPageCurlCapturePending: false, readerPageCurlMotionLocked: false,
    pageTurnCrossChapterHandoff: true, pageTurnPreviewLoadingKey: 'next', pageTurnPreviewLoadingStartedAt: previewStartedAt,
    usesReaderPageCurlCanvas: () => true, requestReaderPageCurlCapture() {},
    waitReaderPageCurlCaptureSignal: async ms => { clock += ms; },
  });
  return p;
}
clock = 1000;
const slow = curlWaitFixture(clock);
assert.equal(await slow.ensureReaderPageCurlReady(), true, 'loading leaf turns once the grace has passed');
assert(clock - 1000 >= 160 && clock - 1000 < 200, `bounded wait for a slow next chapter, waited ${clock - 1000}ms`);
clock = 5000;
const dragged = curlWaitFixture(clock - 400);
assert.equal(await dragged.ensureReaderPageCurlReady(), true);
assert.equal(clock, 5000, 'a preview already loading since the drag began adds no wait on release');
clock = 9000;
const fast = curlWaitFixture(clock);
fast.waitReaderPageCurlCaptureSignal = async ms => {
  clock += ms;
  if (clock - 9000 >= 48 && fast.readerPageCurlCaptureKey === 'loading-leaf') {
    fast.pageTurnPreviewLoadingKey = ''; fast.readerPageCurlCaptureKey = 'real-leaf';
    fast.pageTurnIncomingDocumentSource = 'chapter';
  }
};
assert.equal(await fast.ensureReaderPageCurlReady(), true);
assert.equal(fast.readerPageCurlCaptureKey, 'real-leaf', 'a cached chapter inside the grace still turns its real first page');
assert(clock - 9000 < 160);
// Once the sheet is moving, a late preview must not recapture: that hides the canvas and flashes the old page.
const moving = new Reader();
Object.assign(moving, { readerPageCurlMotionLocked: true, readerPageCurlSnapshotReady: true,
  readerPageCurlCaptureKey: 'loading-leaf', readerPageCurlCaptureSerial: 3,
  pageSlideDirection: 1, usesReaderPageCurlCanvas: () => true, shouldRenderSlidingPageTurn: () => true,
  readerPageCurlKey: () => { throw Error('locked curl reached capture'); } });
moving.requestReaderPageCurlCapture();
assert.equal(moving.readerPageCurlSnapshotReady, true);
assert.equal(moving.readerPageCurlCaptureSerial, 3);
console.log('PASS: zero theme lookups during ordinary/3D frames, atomic snapshot/palette publication, theme reset and paper/tone parity');
