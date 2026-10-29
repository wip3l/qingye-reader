// Tap-to-scroll motion for webtoon mode: exact totals, gentle start, continuous velocity when chained.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const sandbox = vm.createContext({ console, px2vp: value => value / 2,
  ReaderTtsFloatingSession: { isActive: () => false } });
vm.runInContext(stripTypeScriptTypes(readEtsModule('core/reader/ReaderScreenScrollMotion.ts')
  .replace(/^export /gm, '')) + '\nglobalThis.Motion = ReaderScreenScrollMotion;', sandbox);
const Motion = sandbox.Motion;
const D = Motion.DURATION_MS;

const run = (motion, start, frameMs, until = Infinity) => {
  const deltas = [];
  let now = start;
  while (motion.isRunning() && now <= until) { deltas.push(motion.step(now)); now += frameMs; }
  return { deltas, now };
};
const sum = values => values.reduce((a, b) => a + b, 0);

// Every frame rate lands exactly on the requested distance, and never overshoots.
for (const frameMs of [1000 / 120, 1000 / 60, 1000 / 30, 47]) {
  const motion = new Motion();
  motion.add(1000);
  const { deltas } = run(motion, 5000, frameMs);
  assert.ok(Math.abs(sum(deltas) - 1000) < 1e-6, `total at ${frameMs}ms frames`);
  assert.ok(deltas.every(d => d >= -1e-9), 'monotonic');
  assert.equal(motion.remaining(), 0);
}

// Timing starts at the first frame, so the first frame moves nothing and the start is gentle.
{
  const motion = new Motion();
  motion.add(1000);
  const { deltas } = run(motion, 123456, 1000 / 120);
  assert.ok(Math.abs(deltas[0]) < 1e-6);
  const peak = Math.max(...deltas);
  assert.ok(deltas[1] < peak * 0.25, 'eases in instead of jumping to full speed');
  const peakAt = deltas.indexOf(peak) * (1000 / 120) / D;
  assert.ok(peakAt > 0.05 && peakAt < 0.4, `peak speed early, long deceleration (${peakAt})`);
  assert.ok(deltas.at(-1) < peak * 0.05, 'settles softly');
}

// Tapping again mid-scroll adds the new screen without a speed dip, and still totals exactly.
{
  const motion = new Motion();
  motion.add(800);
  const frame = 1000 / 120;
  const first = run(motion, 0, frame, D * 0.3);
  const before = first.deltas.at(-1);
  motion.add(800);
  const second = run(motion, first.now, frame);
  const after = second.deltas[1];
  assert.ok(after > before * 0.8, `velocity continues (${before.toFixed(2)} -> ${after.toFixed(2)})`);
  assert.ok(Math.abs(sum(first.deltas) + sum(second.deltas) - 1600) < 1e-6);
}

// Reversing direction mid-scroll starts the new motion from rest and ends at the net distance.
{
  const motion = new Motion();
  motion.add(800);
  const first = run(motion, 0, 10, D * 0.5);
  motion.add(-800);
  const second = run(motion, first.now, 10);
  assert.ok(Math.abs(sum(first.deltas) + sum(second.deltas)) < 1e-6);
}

// stop() discards the remainder; a new tap after stopping starts fresh.
{
  const motion = new Motion();
  motion.add(500);
  run(motion, 0, 10, 100);
  motion.stop();
  assert.equal(motion.isRunning(), false);
  assert.equal(motion.remaining(), 0);
  motion.add(300);
  assert.ok(Math.abs(sum(run(motion, 9999, 10).deltas) - 300) < 1e-6);
}
// Exercise the actual hardware-key route and frame driver: novels must move one viewport, not one List chunk.
const reader = readEtsModule('pages/ReadBook.ets');
function method(name) {
  const start = reader.search(new RegExp(`^  (?:private |async )?${name}\\(`, 'm'));
  assert.notEqual(start, -1, name);
  return reader.slice(start, reader.indexOf('\n  }', start) + 4);
}
vm.runInContext(stripTypeScriptTypes(`class Reader {
${['handleHardwareKeyTurn', 'scrollReaderComicByPage', 'advanceReaderComicScreenScroll', 'turnNext', 'turnPrev']
  .map(method).join('\n')}
}\nglobalThis.Reader = Reader;`), sandbox);
function fixture() {
  const p = new sandbox.Reader();
  const steps = [], loads = [], moves = [], stops = [];
  let offset = 800, end = false;
  Object.assign(p, {
    readerPageVisible: true, isTtsSpeaking: false, chapters: [{}, {}, {}],
    ttsReader: { isSpeaking: () => false }, readerComicChapterSwitching: false,
    contentPages: ['chunk-1', 'chunk-2', 'chunk-3', 'chunk-4'], currentPageIndex: 0,
    isReaderComicModeActive: () => false, isReaderContinuousScrollSurfaceActive: () => true,
    isReaderComicPagedMode: () => false, pauseReaderAutoScroll() {},
    // A 900vp surface with 50vp top and 100vp bottom reserved leaves 750vp of正文.
    pageViewHeight: 900, getEffectiveReaderMarginTop: () => 50,
    getReaderContinuousScrollBottomPadding: () => 100,
    readerContinuousV2ViewportPx: () => [200, 1700],
    readerComicScreenScrollMotion: new Motion(),
    startReaderComicScreenScroll: distance => { steps.push(distance); p.readerComicScreenScrollMotion.add(distance); },
    stopReaderComicScreenScroll: () => p.readerComicScreenScrollMotion.stop(),
    readerComicScroller: {
      currentOffset: () => ({ xOffset: 0, yOffset: offset }), isAtEnd: () => end,
      scrollTo: options => stops.push(options),
      scrollBy: (_x, delta) => { offset += delta; moves.push(delta); },
      scrollToIndex: () => assert.fail('a screen turn must never snap to a render chunk'),
    },
    isCurrentReaderPaginationComplete: () => true, isPreviousChapterTurnReady: () => true,
    loadNextChapter: () => loads.push(1), loadPrevChapter: () => loads.push(-1),
    preloadPreviousChapterPaginationLater: () => loads.push('preload-previous'),
  });
  return { p, steps, loads, moves, stops, edge: () => { end = true; }, top: () => { offset = 0; } };
}
for (const direction of [-1, 1]) {
  const h = fixture();
  h.p.handleHardwareKeyTurn(direction, true);
  assert.deepEqual(h.steps, [direction * 750]);
  assert.equal(h.stops.length, 1, 'stop an active manual fling before starting a screen turn');
  for (let time = 1000; h.p.advanceReaderComicScreenScroll(time); time += 10) {}
  assert.ok(Math.abs(sum(h.moves) - direction * 750) < 1e-6, 'novel frame driver completes exactly one screen');
  assert.deepEqual(h.loads, [], 'ordinary screen movement cannot load/skip a chapter');
}
{
  const h = fixture();
  h.p.handleHardwareKeyTurn(1, true);
  h.p.handleHardwareKeyTurn(1, true);
  assert.equal(h.stops.length, 1, 'repeated keys preserve the running motion');
  for (let time = 1000; h.p.advanceReaderComicScreenScroll(time); time += 10) {}
  assert.ok(Math.abs(sum(h.moves) - 1500) < 1e-6, 'two keys accumulate exactly two screens');
}
{
  const h = fixture();
  h.p.currentPageIndex = 3;
  h.p.handleHardwareKeyTurn(1, true);
  assert.deepEqual(h.steps, [750], 'the last chunk can still contain several unread screens');
  assert.deepEqual(h.loads, []);
  h.edge(); h.p.handleHardwareKeyTurn(1, true);
  assert.deepEqual(h.loads, [1], 'load next chapter only at the physical list end');
  h.top(); h.p.handleHardwareKeyTurn(-1, true);
  assert.deepEqual(h.loads, [1, -1]);
}
{
  const h = fixture();
  h.p.readerContinuousV2ViewportPx = () => [];
  await h.p.turnNext(); await h.p.turnPrev();
  assert.deepEqual(h.steps, [750, -750], 'keyboard/general turn routes share the viewport fallback');
  h.p.showMenu = true; h.p.handleHardwareKeyTurn(1, true);
  h.p.showMenu = false; h.p.handleHardwareKeyTurn(1, false);
  assert.equal(h.steps.length, 2, 'disabled keys and overlays do not scroll');
  h.p.readerPageVisible = false;
  assert.equal(h.p.advanceReaderComicScreenScroll(1000), false);
  assert.equal(h.p.readerComicScreenScrollMotion.isRunning(), false);
}
{
  const h = fixture();
  h.p.isReaderComicModeActive = () => true;
  h.p.scrollReaderComicByScreen = direction => h.steps.push(`comic:${direction}`);
  h.p.handleHardwareKeyTurn(1, true);
  assert.deepEqual(h.steps, ['comic:1'], 'comic scrolling keeps its existing screen policy');
}
console.log('Reader screen scroll: exact animation totals, novel hardware-key viewport turns, repeated keys, boundaries, fallback and comic routing passed.');
