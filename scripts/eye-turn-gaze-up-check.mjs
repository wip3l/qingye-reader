// 眼动翻页“新版识别模型”的抬眼手势：校准阈值、保持时长、眨眼、翻页保护、基准跟随。
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/core/reader/GazeUpDetector.ts', import.meta.url), 'utf8');
const context = vm.createContext({ Math, Number, Date });
vm.runInContext(stripTypeScriptTypes(source.replace(/^export /gm, '')), context);
const api = vm.runInContext(`({ GazeUpDetector, buildGazeUpCalibration, defaultGazeUpCalibration,
  encodeGazeUpCalibration, parseGazeUpCalibration, gazeUpScore, GAZE_UP_HOLD_MS, GAZE_UP_COOLDOWN_MS })`, context);

// Values measured on device (2026-11-14): reading -0.03 / 0.28, text top -0.075 / 0.33.
const READ = { iris: -0.03, open: 0.28 };
const TOP = { iris: -0.075, open: 0.33 };
const ABOVE = { iris: -0.13, open: 0.39 };
const at = (point, time, presence = 1) => ({ iris: point.iris, open: point.open, presence, at: time });
const many = (point, n, jitter = 0.004) => Array.from({ length: n }, (_, i) =>
  ({ iris: point.iris + (i % 2 ? jitter : -jitter), open: point.open - (i % 2 ? jitter : -jitter), presence: 1, at: i * 200 }));

// Calibration: threshold halfway between the text top and above the screen.
const built = api.buildGazeUpCalibration(many(READ, 7), many(TOP, 7), many(ABOVE, 7));
assert.equal(built.error, '');
const cal = built.calibration;
assert.equal(cal.irisWeight, 1);
assert.equal(cal.openWeight, 1);
const topScore = api.gazeUpScore(cal, cal.baseIris, cal.baseOpen, TOP.iris, TOP.open);
assert.ok(topScore > 0.4 && topScore < 0.5, `top score ${topScore}`);
// Fixation medians include the alternating jitter, so compare with a small tolerance.
assert.ok(Math.abs(cal.threshold - (topScore + 1) / 2) < 0.05, `threshold ${cal.threshold}`);
assert.deepEqual({ ...api.parseGazeUpCalibration(api.encodeGazeUpCalibration(cal)) },
  { ...cal, baseIris: Number(cal.baseIris.toFixed(4)), baseOpen: Number(cal.baseOpen.toFixed(4)),
    irisSpan: Number(cal.irisSpan.toFixed(4)), openSpan: Number(cal.openSpan.toFixed(4)),
    threshold: Number(cal.threshold.toFixed(3)) });
assert.equal(api.parseGazeUpCalibration('v4,0,0,0,0.5,-0.04,0.04,0,1,1'), null, 'old calibration is not a model one');
assert.equal(api.parseGazeUpCalibration(''), null);

// Rejections: no upward change, or above-the-screen too close to the text top.
assert.match(api.buildGazeUpCalibration(many(READ, 6), many(TOP, 6), many(READ, 6)).error, /没有测到/);
assert.match(api.buildGazeUpCalibration(many(READ, 6), many(TOP, 6),
  many({ iris: -0.08, open: 0.335 }, 6)).error, /太接近/);
assert.match(api.buildGazeUpCalibration(many(READ, 2), many(TOP, 6), many(ABOVE, 6)).error, /样本不足/);
// Only one channel moved: the other gets no weight.
const lidOnly = api.buildGazeUpCalibration(many(READ, 6), many({ iris: -0.03, open: 0.31 }, 6),
  many({ iris: -0.031, open: 0.40 }, 6)).calibration;
assert.equal(lidOnly.irisWeight, 0);
assert.equal(lidOnly.openWeight, 1);

function run(detector, points) {
  return points.map(([point, time, presence]) => detector.push(at(point, time, presence)));
}

// Warm-up, then a held look above the screen turns the page once.
let d = new api.GazeUpDetector(cal);
let r = run(d, [[READ, 0], [READ, 200], [READ, 400], [READ, 600]]);
assert.ok(r.every(x => !x.turn && x.progress === 0));
assert.equal(d.baselineReady(), true);
r = run(d, [[ABOVE, 800], [ABOVE, 950], [ABOVE, 1100]]);
assert.deepEqual(r.map(x => x.turn), [false, false, true]);
assert.ok(r[0].progress > 0 && r[0].progress < 1, 'cue starts filling on the first sample above');

// Cooldown and return: staying up does not turn again; coming back to reading re-arms.
r = run(d, [[ABOVE, 1300], [ABOVE, 1500], [ABOVE, 2000], [ABOVE, 2300]]);
assert.ok(r.every(x => !x.turn), 'needs to return to reading before the next turn');
r = run(d, [[READ, 2500], [ABOVE, 2700], [ABOVE, 3000]]);
assert.deepEqual(r.map(x => x.turn), [false, false, true]);

// Reading the top lines never turns the page, but the footer cue fills part-way as a hint.
d = new api.GazeUpDetector(cal);
r = run(d, [[READ, 0], [READ, 200], [READ, 400], [READ, 600]]);
assert.ok(r.every(x => x.progress === 0), 'no cue while reading the middle of the page');
r = run(d, Array.from({ length: 10 }, (_, i) => [TOP, 800 + i * 200]));
assert.ok(r.every(x => !x.turn));
assert.ok(r.every(x => x.progress > 0 && x.progress < 0.7), `top-line cue ${r.map(x => x.progress)}`);
// Above the threshold the cue jumps to the hold range; a lost frame keeps it, three clear it.
r = run(d, [[ABOVE, 3000]]);
assert.ok(r[0].progress >= 0.7 && r[0].progress < 1);
assert.equal(d.pushMissing().progress, r[0].progress);
d.pushMissing(); assert.equal(d.pushMissing().progress, 0);

// A single high sample (glance) is not enough; the hold must last GAZE_UP_HOLD_MS over two samples.
d = new api.GazeUpDetector(cal);
run(d, [[READ, 0], [READ, 200], [READ, 400], [READ, 600]]);
r = run(d, [[ABOVE, 800], [READ, 1000], [ABOVE, 1200], [ABOVE, 1300]]);
assert.ok(r.every(x => !x.turn), 'second sample came only 100 ms later');
assert.equal(run(d, [[ABOVE, 1200 + api.GAZE_UP_HOLD_MS]])[0].turn, true);

// Blinks (lid gap collapses) and low presence count as missing frames, not as reading or looking up.
d = new api.GazeUpDetector(cal);
run(d, [[READ, 0], [READ, 200], [READ, 400], [READ, 600]]);
r = run(d, [[ABOVE, 800], [{ iris: -0.02, open: 0.05 }, 950], [ABOVE, 1100]]);
assert.equal(r[2].turn, true, 'one blink frame inside the hold does not break it');
d = new api.GazeUpDetector(cal);
run(d, [[READ, 0], [READ, 200], [READ, 400], [READ, 600]]);
r = run(d, [[ABOVE, 800], [ABOVE, 900, 0.1], [ABOVE, 950, 0.1], [ABOVE, 1000, 0.1], [ABOVE, 1300]]);
assert.ok(r.every(x => !x.turn), 'three missing frames reset the hold');

// The baseline follows posture while reading, so a slow drift does not end up "above the screen".
d = new api.GazeUpDetector(cal);
run(d, [[READ, 0], [READ, 200], [READ, 400], [READ, 600]]);
let time = 800;
for (let i = 1; i <= 60; i++, time += 200) {
  const drift = { iris: READ.iris - 0.0008 * i, open: READ.open + 0.0008 * i };
  assert.equal(d.push(at(drift, time)).turn, false, `drift step ${i}`);
}

// With a calibration the baseline is ready at once; samples still "looking up" right after calibrating must not
// become the baseline (seen on device), and the first real look above the screen still turns.
d = new api.GazeUpDetector(cal);
assert.equal(d.baselineReady(), true);
r = run(d, [[ABOVE, 0], [ABOVE, 200], [ABOVE, 400], [READ, 600], [READ, 800], [ABOVE, 1600], [ABOVE, 1900]]);
assert.ok(r.slice(0, 3).every(x => !x.turn), 'leftover look-up from calibration step 3 neither turns nor sets the baseline');
assert.equal(r[6].turn, true, 'after returning to reading the first real look above the screen turns');
// The uncalibrated default warms up from live samples instead.
assert.equal(new api.GazeUpDetector(api.defaultGazeUpCalibration()).baselineReady(), false);

// A broken mesh frame (iris -2.6 on device) is dropped, not scored.
d = new api.GazeUpDetector(cal);
r = run(d, [[{ iris: -2.6, open: 0.29 }, 0], [{ iris: -2.6, open: 0.29 }, 300]]);
assert.ok(r.every(x => !x.turn && Number.isNaN(x.score)));
// A milder broken frame (iris -0.33 at presence 0.73, scoring 4.6 on device) is dropped too.
assert.ok(Number.isNaN(d.push(at({ iris: -0.33, open: 0.36 }, 600, 0.73)).score));

// The uncalibrated default still keeps the measured text top below its threshold.
const def = api.defaultGazeUpCalibration();
assert.ok(api.gazeUpScore(def, READ.iris, READ.open, TOP.iris, TOP.open) < def.threshold);
assert.ok(api.gazeUpScore(def, READ.iris, READ.open, ABOVE.iris, ABOVE.open) > def.threshold);

console.log('Eye-turn gaze-up: calibration threshold and rejections, hold, cooldown/return, text top, blink, baseline drift, default.');
