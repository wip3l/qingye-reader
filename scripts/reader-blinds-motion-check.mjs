// Auto-scroll blinds mode: line slats never overlap, flips are timed per slat, spreads read column by column.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const sandbox = vm.createContext({ console });
vm.runInContext(stripTypeScriptTypes(readEtsModule('core/reader/ReaderBlindsMotion.ts')
  .replace(/^export /gm, '')) + '\nglobalThis.Motion = ReaderBlindsMotion;\nglobalThis.Spread = ReaderBlindsSpread;',
sandbox);
const { Motion, Spread } = sandbox;
const plain = value => JSON.parse(JSON.stringify(value));

// Merging: touching lines stay separate, a bubble spanning two lines joins them, junk is dropped.
assert.deepEqual(plain(Motion.mergeBands([[30, 60], [0, 30], [60, 90]])), [[0, 30], [30, 60], [60, 90]]);
assert.deepEqual(plain(Motion.mergeBands([[0, 30], [30, 60], [26, 64], [100, 140]])), [[0, 64], [100, 140]]);
assert.deepEqual(plain(Motion.mergeBands([[0, 30], [29.8, 60]])), [[0, 30], [29.8, 60]],
  'sub-pixel overlap from glyph rounding keeps two slats');
assert.deepEqual(plain(Motion.mergeBands([[5, 5], [10, 2], [NaN, 4], [0, 20]])), [[0, 20]]);

// Current page has a tall title then 30px lines; next page has 34px lines that do not line up.
const current = [[0, 44], [66, 96], [96, 126], [126, 156], [165, 195]];
const next = [[0, 34], [34, 68], [68, 102], [102, 136], [136, 170], [170, 204]];
const overlap = (a, b) => Math.min(a[1], b[1]) - Math.max(a[0], b[0]) > 0;

let now = 0;
const m = new Motion();
m.reset(current, null);
assert.equal(m.advance(50, now), 0);
assert.equal(m.position(), 0, 'unknown next page holds the reading line');
assert.equal(m.reachedEnd(), false);
m.setNext(next);
for (let cursor = 0; cursor <= 220; cursor += 1) {
  m.advance(1, now += 16);
  const reveal = m.reveal();
  const visibleCurrent = current.slice(m.hiddenCount());
  const visibleNext = next.slice(0, m.shownCount());
  for (const a of visibleCurrent) for (const b of visibleNext) {
    assert.equal(overlap(a, b), false, `slats overlap at cursor ${m.position()}`);
  }
  for (const b of visibleNext) assert.ok(b[1] <= reveal + 1e-9, 'next page lines appear only above the line');
  for (const a of visibleCurrent) assert.ok(a[0] >= reveal - 1e-9, 'current lines stay below the line');
  if (m.position() < 44) assert.equal(m.hiddenCount(), 0, 'a line flips only after it is fully read');
}
assert.equal(m.endY(), 204);
assert.equal(m.reachedEnd(), true, 'reading line stops at the lower of the two pages');
assert.equal(m.hiddenCount(), current.length);
assert.equal(m.shownCount(), next.length);
assert.equal(m.position(), 204, 'cursor never runs past the end');

// The first next-page line waits until the current line under it is gone.
const w = new Motion();
w.reset(current, next);
w.advance(43, 0);
assert.equal(w.shownCount(), 0);
w.advance(1, 0);
assert.equal(w.hiddenCount(), 1, 'title flips at its bottom edge');
assert.equal(w.reveal(), 44);
assert.equal(w.shownCount(), 1, 'next line fully inside the freed height appears');
w.advance(52, 0);
assert.equal(w.reveal(), 96);
assert.equal(w.shownCount(), 2, 'next line straddling a still-visible current line waits');

// Flip timing: out first, in after a delay, independent of frame cadence.
const t = new Motion();
t.reset([[0, 30], [30, 60]], [[0, 30], [30, 60]]);
t.advance(30, 1000);
assert.equal(t.outProgress(0, 1000), 0);
assert.equal(t.outProgress(0, 1000 + Motion.OUT_MS / 2), 0.5);
assert.equal(t.outProgress(0, 1000 + Motion.OUT_MS), 1);
assert.equal(t.inProgress(0, 1000 + Motion.IN_DELAY_MS), 0, 'incoming slat waits for the outgoing one');
assert.equal(t.inProgress(0, 1000 + Motion.IN_DELAY_MS + Motion.IN_MS), 1);
assert.equal(t.outProgress(1, 5000), 0, 'unread slat never animates');
assert.equal(t.animating(1100), true);
assert.equal(t.animating(1000 + Motion.IN_DELAY_MS + Motion.IN_MS), false);
assert.equal(t.guideY(1000), 0, 'guide starts from the previous boundary');
assert.equal(t.guideY(1000 + Motion.OUT_MS + Motion.IN_DELAY_MS), 30, 'guide settles on the new boundary');

// Empty next column (spread whose right page does not exist): current simply clears.
const e = new Motion();
e.reset([[0, 30]], []);
e.advance(40, 0);
assert.equal(e.reachedEnd(), true);
assert.equal(e.hiddenCount(), 1);

// Spread: left column first, then right; leftover distance carries across.
const s = new Spread();
s.ensureColumns(2);
s.columns[0].reset([[0, 30], [30, 60]], [[0, 60]]);
s.columns[1].reset([[0, 30]], null);
s.advance(70, 0);
assert.equal(s.columns[0].position(), 0, 'nothing moves until every column knows its next page');
s.columns[1].setNext([[0, 30]]);
s.advance(70, 0);
assert.equal(s.columns[0].position(), 60);
assert.equal(s.columns[1].position(), 10, 'overflow continues in the right column');
assert.equal(s.reachedEnd(), false);
s.advance(100, 0);
assert.equal(s.reachedEnd(), true);
s.ensureColumns(1);
assert.equal(s.columns.length, 1, 'switching to single page drops the right column');

// Dragging back: seek moves the line up, passed slats flip back in reverse, mid-flip reversals keep progress.
{
  const d = new Motion();
  d.reset(current, next);
  let t = 1000;
  d.seek(130, t);
  const hiddenBefore = d.hiddenCount();
  const shownBefore = d.shownCount();
  assert.ok(hiddenBefore >= 3 && shownBefore >= 2);
  t += 1000;
  d.seek(50, t);
  assert.equal(d.position(), 50);
  assert.equal(d.hiddenCount(), 1, 'only the title stays flipped above the dragged-back line');
  assert.equal(d.shownCount(), 1);
  assert.equal(d.outProgress(2, t), 1, 'a restored slat starts fully flipped');
  assert.equal(d.inProgress(1, t), 1, 'a retracting next-page slat starts fully shown');
  assert.ok(d.outExtent() >= hiddenBefore, 'restoring slats are painted one by one');
  assert.ok(d.inExtent() >= shownBefore);
  assert.equal(d.animating(t), true);
  assert.equal(d.inProgress(1, t + Motion.IN_MS), 0, 'next-page slat retracts first');
  assert.equal(d.outProgress(2, t + Motion.IN_DELAY_MS + Motion.OUT_MS), 0, 'current slat returns after it');
  t += 2000;
  assert.equal(d.animating(t), false);
  assert.equal(d.outExtent(), 1, 'finished restores are dropped');
  assert.equal(d.inExtent(), 1);
  // Reverse halfway through a flip: the slat continues from where it was instead of jumping.
  t += 1000;
  d.seek(100, t);
  const mid = t + Motion.OUT_MS / 2;
  const half = d.outProgress(1, mid);
  assert.ok(half > 0.4 && half < 0.6);
  d.seek(50, mid);
  assert.ok(Math.abs(d.outProgress(1, mid) - half) < 0.01, 'reversal keeps flip progress');
  assert.ok(d.outProgress(1, mid + 30) < half, 'and then runs backward');
  d.seek(-20, mid + 1);
  assert.equal(d.position(), 0, 'cannot drag above the page top');
  d.seek(9999, mid + 2);
  assert.equal(d.position(), d.endY(), 'cannot drag past the end');
  // Guide follows the finger while dragging, then eases back to the slat boundary.
  d.reset(current, next);
  d.setFollow(true, 0);
  d.seek(80, 0);
  assert.equal(d.guideY(0), 80, 'guide sticks to the finger');
  d.setFollow(false, 0);
  assert.equal(d.guideY(0), 80);
  assert.equal(d.guideY(1000), d.reveal(), 'guide settles on the slat boundary after release');
  const unknown = new Motion();
  unknown.reset(current, null);
  unknown.seek(60, 0);
  assert.equal(unknown.position(), 0, 'unknown next page cannot be dragged');
}
// Spread drag: forward fills the left column first, backward empties the right column first.
{
  const s2 = new Spread();
  s2.ensureColumns(2);
  s2.columns[0].reset([[0, 30], [30, 60]], [[0, 30], [30, 60]]);
  s2.columns[1].reset([[0, 30], [30, 60]], [[0, 30], [30, 60]]);
  s2.shift(80, 0);
  assert.deepEqual([s2.columns[0].position(), s2.columns[1].position()], [60, 20]);
  s2.shift(-30, 0);
  assert.deepEqual([s2.columns[0].position(), s2.columns[1].position()], [50, 0], 'back through the right column');
  s2.shift(-500, 0);
  assert.deepEqual([s2.columns[0].position(), s2.columns[1].position()], [0, 0]);
}
console.log('PASS reader blinds motion: slat merging, no overlap, per-slat flip timing, empty columns and spreads');
