// Execute production gesture methods with a native-list double: one pointer stream must have one scroll owner.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const reader = readEtsModule('pages/ReadBook.ets');
const comic = readEtsModule('components/reader/ReaderComicView.ets');
function method(source, name) {
  const start = source.search(new RegExp(`^  (?:private )?${name}\\(`, 'm'));
  assert.notEqual(start, -1, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
let now = 1000;
const touch = { Down: 0, Move: 1, Up: 2, Cancel: 3 };
const sandbox = vm.createContext({ Date: { now: () => now }, TouchType: touch, console });
const readerMethods = ['beginReaderComicPan', 'updateReaderComicPan', 'finishReaderComicPan',
  'cancelReaderComicPan', 'comicBoundaryChapterSwipeDirection'];
vm.runInContext(stripTypeScriptTypes(`class Reader {
${readerMethods.map(name => method(reader, name)).join('\n')}
}
class Comic { ${method(comic, 'handleTouch')} }
globalThis.Reader = Reader; globalThis.Comic = Comic;`), sandbox);

function fixture() {
  const moves = [], flings = [], chapters = [];
  let y = 400, atEnd = false, stopped = 0;
  const p = new sandbox.Reader();
  Object.assign(p, {
    readerComicChapterSwitching: false, currentChapterIndex: 1, chapters: [{}, {}, {}],
    isReaderContinuousScrollSurfaceActive: () => true,
    stopReaderComicScreenScroll: () => stopped++,
    resetReaderComicBoundaryFeedback: () => {
      p.readerComicBoundaryDirection = 0;
      p.readerComicBoundaryReady = false;
    },
    switchComicBoundaryChapter: direction => chapters.push(direction),
    readerComicScroller: {
      scrollBy: (_x, dy) => { moves.push(dy); y += dy; },
      fling: velocity => flings.push(velocity),
      currentOffset: () => ({ xOffset: 0, yOffset: y }),
      isAtEnd: () => atEnd,
    },
  });
  return { p, moves, flings, chapters, position: () => y,
    edge: () => { atEnd = true; }, stopped: () => stopped };
}

for (const sign of [-1, 1]) {
  const h = fixture();
  h.p.beginReaderComicPan();
  for (const offset of [20, 40, 70]) {
    const dy = sign * offset;
    // Do not simulate a native move: the novel List disables built-in gesture scrolling.
    // This catches the regression where only an observer ran and the viewport never moved.
    h.p.updateReaderComicPan({ offsetY: dy });
    now += 30;
  }
  assert.equal(h.position(), 400 - sign * 70, 'novel pan alone must move exactly the finger distance');
  h.p.finishReaderComicPan({ velocityY: sign * 900 });
  assert.deepEqual(h.moves, [-sign * 20, -sign * 20, -sign * 30]);
  assert.deepEqual(h.flings, [sign * 900], 'novel release launches one system fling');
  assert.ok(h.p.readerComicSuppressClickUntil > now, 'drag cannot trigger a tap');
}

for (const sign of [-1, 1]) {
  const h = fixture();
  h.p.beginReaderComicPan();
  h.p.updateReaderComicPan({ offsetY: sign * 25 });
  h.p.updateReaderComicPan({ offsetY: sign * 80 });
  h.p.finishReaderComicPan({ velocityY: sign * 900 });
  assert.equal(h.position(), 400 - sign * 80, 'comic overlay still drives exactly one drag');
  assert.deepEqual(h.flings, [sign * 900], 'comic release keeps the gesture velocity and direction');
}

// Both gesture owners must retain the chapter-boundary pull without launching a second fling.
{
  const h = fixture();
  h.edge();
  h.p.beginReaderComicPan();
  h.p.updateReaderComicPan({ offsetY: -60 });
  h.p.finishReaderComicPan({ velocityY: -1000 });
  assert.deepEqual(h.chapters, [1]);
  assert.deepEqual(h.flings, []);
  const canceled = fixture();
  canceled.edge();
  canceled.p.beginReaderComicPan();
  canceled.p.updateReaderComicPan({ offsetY: -20 });
  canceled.p.cancelReaderComicPan();
  assert.deepEqual(canceled.chapters, []);
  assert.equal(canceled.p.readerComicBoundaryReady, false);
}
const stationary = fixture();
stationary.p.beginReaderComicPan();
stationary.p.updateReaderComicPan({ offsetY: -20 });
stationary.p.finishReaderComicPan({ velocityY: 0 });
assert.deepEqual(stationary.flings, [], 'zero fling velocity is invalid in ArkUI');

// The comic overlay receives DOWN instead of the List: stop the two animation owners before a pan is recognized.
const c = new sandbox.Comic();
const calls = [];
Object.assign(c, {
  touchDragged: true,
  colorSession: { touch: down => calls.push(['touch', down]) },
  onTouchStart: () => calls.push(['stop-screen']),
  scroller: {
    currentOffset: () => ({ xOffset: 0, yOffset: 735.5 }),
    scrollTo: options => calls.push(['stop-native', options.xOffset, options.yOffset, options.animation]),
  },
});
c.handleTouch({ type: touch.Down, touches: [{}] });
assert.deepEqual(calls, [['touch', true], ['stop-screen'], ['stop-native', 0, 735.5, false]]);
assert.equal(c.touchDragged, false);
calls.length = 0;
c.touchDragged = true;
c.handleTouch({ type: touch.Down, touches: [{}, {}] });
c.handleTouch({ type: touch.Move, touches: [{}, {}] });
c.handleTouch({ type: touch.Up, touches: [] });
assert.equal(c.touchDragged, true, 'pinch must not re-arm tap recognition');
assert.deepEqual(calls, [['touch', true], ['touch', false]], 'multi-touch/move/up do not restart or reposition scroll');

// Guard the ownership wiring at the two distinct surfaces, not only the standalone method defaults.
const novelSurface = reader.slice(reader.indexOf('  readerComicScrollSurface()'), reader.indexOf('  readerComicBoundaryHint()'));
assert.match(novelSurface, /updateReaderComicPan\(event\)/);
assert.match(novelSurface, /finishReaderComicPan\(event\)/);
assert.match(novelSurface, /enableScrollInteraction\(false\)/);
assert.match(novelSurface, /if \(!this.isReaderNovelContinuousScrollModeActive\(\) \|\| this.readerTextSelectionActive\) return;\s*this.updateReaderComicPan\(event\)/);
// HitTestMode.None on a parent does not exclude its descendants. A full-height footer spacer
// above List must also be excluded so long-press selection can reach the body.
assert.match(novelSurface, /Blank\(\)\s*\.layoutWeight\(1\)\s*(?:\/\/[^\n]*\n\s*)*\.hitTestBehavior\(HitTestMode.None\)/);
const comicSurface = reader.slice(reader.indexOf('  readerComicSurface()'), reader.indexOf('  readerComicEffectiveMode()'));
assert.match(comicSurface, /updateReaderComicPan\(event\)/);
assert.match(comicSurface, /onTouchStart:.*stopReaderComicScreenScroll\(\)/);
console.log('Reader scroll gestures: shared novel/comic drag/fling, chapter edges, cancellation and touch interruption passed.');
