// Tap-to-scroll motion for webtoon mode: exact totals, gentle start, continuous velocity when chained.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const sandbox = vm.createContext({});
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
console.log('Reader screen scroll: exact totals at any frame rate, eased start, chained velocity, reversal and stop passed.');
