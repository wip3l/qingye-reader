/**
 * "Look above the top edge of the screen" gesture for the face-landmark eye-turn model.
 *
 * Input samples come from the face mesh: `iris` is the iris centre below the eye-corner line divided by eye width
 * (looking up makes it smaller) and `open` is the lid gap divided by eye width (looking up makes it larger). Both are
 * measured against a reading baseline that follows the reader's posture, and combined into one score where 1 means
 * "as far up as the calibrated above-the-screen fixation". On device the mesh separates looking up clearly but cannot
 * tell the middle of the page from its bottom, so there is no "dwell at the bottom" stage: holding the gaze above
 * the screen edge for a moment turns the page.
 *
 * Pure logic with no kit imports, so Node regression checks can run it.
 */

export interface GazeUpSample {
  iris: number;
  open: number;
  presence: number;
  /** Capture time in ms. */
  at: number;
}

export interface GazeUpCalibration {
  /** Reading baseline measured during calibration; the runtime baseline starts here and then follows posture. */
  baseIris: number;
  baseOpen: number;
  /** Change from the baseline to the above-the-screen fixation (iris drop, lid opening), both positive. */
  irisSpan: number;
  openSpan: number;
  irisWeight: number;
  openWeight: number;
  /** Score that counts as "above the screen". */
  threshold: number;
}

export interface GazeUpResult {
  /** Score of this sample, NaN when the sample was unusable. */
  score: number;
  /** Cue fill 0..1: how close the gaze is to the threshold, then how far through the hold. */
  progress: number;
  /** True exactly once per gesture, when the page should turn. */
  turn: boolean;
}

export interface GazeUpCalibrationOutcome {
  calibration: GazeUpCalibration | null;
  error: string;
}

const CALIBRATION_PREFIX: string = 'm1';
// Spans below this are noise on device (frame-to-frame jitter is about 0.005-0.01).
const MIN_SPAN: number = 0.012;
// Fixation medians from calibration: text top must stay clearly below the above-the-screen level.
const MAX_TOP_SCORE: number = 0.72;
const MIN_THRESHOLD: number = 0.5;
const MAX_THRESHOLD: number = 0.9;
// Normal frames report 0.98-1.00; broken frames seen on device came at 0.63 and 0.73.
const PRESENCE_MIN: number = 0.8;
// A blink collapses the lid gap; looking up widens it. Frames below this share of the baseline gap are blinks.
const BLINK_OPEN_RATIO: number = 0.55;
const MAX_MISSING: number = 2;
const BASELINE_SAMPLES: number = 4;
const BASELINE_FOLLOW: number = 0.08;
// Samples below this score count as reading: they feed the baseline and re-arm the gesture after a turn.
const READING_SCORE: number = 0.35;
const HOLD_KEEP_RATIO: number = 0.8;
const MAX_ABS_IRIS: number = 0.25;
// The footer cue starts filling once the score passes this share of the threshold (reading the top lines shows a
// partly filled cue), reaches CUE_APPROACH_MAX at the threshold, and the hold fills the rest.
const CUE_START_RATIO: number = 0.5;
const CUE_APPROACH_MAX: number = 0.7;
const MAX_OPEN: number = 0.8;

export const GAZE_UP_HOLD_MS: number = 250;
export const GAZE_UP_COOLDOWN_MS: number = 700;

/**
 * Used before the reader has calibrated the model. Spans are a bit larger than the text-top change measured on
 * device (about 0.05 for both channels), so reading the top lines scores near 0.6 and stays under the threshold.
 */
export function defaultGazeUpCalibration(): GazeUpCalibration {
  return {
    baseIris: Number.NaN,
    baseOpen: Number.NaN,
    irisSpan: 0.08,
    openSpan: 0.08,
    irisWeight: 1,
    openWeight: 1,
    threshold: 0.75
  };
}

export function encodeGazeUpCalibration(calibration: GazeUpCalibration): string {
  return [CALIBRATION_PREFIX, calibration.baseIris.toFixed(4), calibration.baseOpen.toFixed(4),
    calibration.irisSpan.toFixed(4), calibration.openSpan.toFixed(4), calibration.irisWeight.toFixed(0),
    calibration.openWeight.toFixed(0), calibration.threshold.toFixed(3)].join(',');
}

export function parseGazeUpCalibration(raw: string): GazeUpCalibration | null {
  const parts = (raw || '').split(',');
  if (parts.length !== 8 || parts[0] !== CALIBRATION_PREFIX) return null;
  const values = parts.slice(1).map((part: string): number => Number(part));
  for (const value of values) {
    if (!Number.isFinite(value)) return null;
  }
  const calibration: GazeUpCalibration = {
    baseIris: values[0],
    baseOpen: values[1],
    irisSpan: values[2],
    openSpan: values[3],
    irisWeight: values[4],
    openWeight: values[5],
    threshold: values[6]
  };
  if (calibration.irisWeight + calibration.openWeight <= 0) return null;
  if (calibration.irisWeight > 0 && calibration.irisSpan < MIN_SPAN) return null;
  if (calibration.openWeight > 0 && calibration.openSpan < MIN_SPAN) return null;
  if (calibration.threshold < MIN_THRESHOLD || calibration.threshold > MAX_THRESHOLD) return null;
  return calibration;
}

function median(values: number[]): number {
  if (values.length === 0) return Number.NaN;
  const sorted = [...values].sort((a: number, b: number): number => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle];
}

export function gazeUpScore(calibration: GazeUpCalibration, baseIris: number, baseOpen: number,
  iris: number, open: number): number {
  let sum = 0;
  let weight = 0;
  if (calibration.irisWeight > 0) {
    sum += calibration.irisWeight * (baseIris - iris) / calibration.irisSpan;
    weight += calibration.irisWeight;
  }
  if (calibration.openWeight > 0) {
    sum += calibration.openWeight * (open - baseOpen) / calibration.openSpan;
    weight += calibration.openWeight;
  }
  return weight > 0 ? sum / weight : Number.NaN;
}

/**
 * Builds the calibration from three held fixations: reading the middle of the page, the top line of text, and
 * above the top edge of the screen. The threshold sits halfway between the text top and above the screen, so reading
 * the top lines does not turn the page.
 */
export function buildGazeUpCalibration(center: GazeUpSample[], top: GazeUpSample[],
  above: GazeUpSample[]): GazeUpCalibrationOutcome {
  const usable = (samples: GazeUpSample[]): GazeUpSample[] => samples.filter((sample: GazeUpSample): boolean =>
    sample.presence >= PRESENCE_MIN && Number.isFinite(sample.iris) && Number.isFinite(sample.open));
  const c = usable(center);
  const t = usable(top);
  const a = usable(above);
  if (c.length < 4 || t.length < 4 || a.length < 4) {
    return { calibration: null, error: `有效样本不足（中央 ${c.length}／顶部 ${t.length}／上沿以外 ${a.length}），请正对屏幕重试` };
  }
  const iris = (samples: GazeUpSample[]): number => median(samples.map((s: GazeUpSample): number => s.iris));
  const open = (samples: GazeUpSample[]): number => median(samples.map((s: GazeUpSample): number => s.open));
  const baseIris = iris(c);
  const baseOpen = open(c);
  const irisSpan = baseIris - iris(a);
  const openSpan = open(a) - baseOpen;
  const irisWeight = irisSpan >= MIN_SPAN ? 1 : 0;
  const openWeight = openSpan >= MIN_SPAN ? 1 : 0;
  if (irisWeight + openWeight === 0) {
    return { calibration: null, error: '没有测到向上看的变化，请在第 3 步把视线移到屏幕上沿以外并保持住' };
  }
  const calibration: GazeUpCalibration = {
    baseIris: baseIris,
    baseOpen: baseOpen,
    irisSpan: Math.max(irisSpan, MIN_SPAN),
    openSpan: Math.max(openSpan, MIN_SPAN),
    irisWeight: irisWeight,
    openWeight: openWeight,
    threshold: 0
  };
  const topScore = gazeUpScore(calibration, baseIris, baseOpen, iris(t), open(t));
  if (topScore > MAX_TOP_SCORE) {
    return { calibration: null, error: '屏幕上沿以外和正文顶部太接近，请在第 3 步再往上看一些' };
  }
  calibration.threshold = Math.max(MIN_THRESHOLD, Math.min(MAX_THRESHOLD, (Math.max(0, topScore) + 1) / 2));
  return { calibration: calibration, error: '' };
}

export class GazeUpDetector {
  private calibration: GazeUpCalibration;
  private baseIris: number = Number.NaN;
  private baseOpen: number = Number.NaN;
  private warmup: GazeUpSample[] = [];
  private holdStartedAt: number = 0;
  private holdSamples: number = 0;
  private missing: number = 0;
  private cooldownUntil: number = 0;
  private needReturn: boolean = false;
  private lastProgress: number = 0;

  constructor(calibration: GazeUpCalibration) {
    this.calibration = calibration;
    this.reset();
  }

  setCalibration(calibration: GazeUpCalibration): void {
    this.calibration = calibration;
    this.reset();
  }

  reset(): void {
    // Start from the calibrated reading baseline when there is one and let it follow posture from there. A warm-up
    // of live samples is only used without calibration: right after calibrating, the first live samples still come
    // from the "look above the screen" step and made the baseline itself look up (seen on device).
    this.baseIris = this.calibration.baseIris;
    this.baseOpen = this.calibration.baseOpen;
    this.warmup = [];
    this.holdStartedAt = 0;
    this.holdSamples = 0;
    this.missing = 0;
    this.cooldownUntil = 0;
    this.lastProgress = 0;
    // Arm only after the gaze has been seen at reading level: a reset follows calibration (eyes may still be on the
    // above-the-screen step), a mode switch or a camera restart.
    this.needReturn = true;
  }

  baselineReady(): boolean {
    return Number.isFinite(this.baseIris) && Number.isFinite(this.baseOpen);
  }

  /** A frame without a usable face (none detected, low presence or mesh failure). */
  pushMissing(): GazeUpResult {
    this.missing++;
    // A blink or one lost frame keeps the cue as it was; a longer gap clears it.
    if (this.missing > MAX_MISSING) {
      this.clearHold();
      this.lastProgress = 0;
    }
    return { score: Number.NaN, progress: this.lastProgress, turn: false };
  }

  push(sample: GazeUpSample): GazeUpResult {
    if (sample.presence < PRESENCE_MIN || !Number.isFinite(sample.iris) || !Number.isFinite(sample.open)) {
      return this.pushMissing();
    }
    // The mesh occasionally returns a broken frame (on device: iris -2.6 at presence 0.63, scoring 16). Real values
    // stay within a fraction of the eye width.
    if (Math.abs(sample.iris) > MAX_ABS_IRIS || sample.open < 0 || sample.open > MAX_OPEN) {
      return this.pushMissing();
    }
    if (this.baselineReady() && sample.open < this.baseOpen * BLINK_OPEN_RATIO) {
      return this.pushMissing();
    }
    this.missing = 0;
    if (!this.baselineReady()) {
      this.warmup.push(sample);
      if (this.warmup.length >= BASELINE_SAMPLES) {
        this.baseIris = median(this.warmup.map((s: GazeUpSample): number => s.iris));
        this.baseOpen = median(this.warmup.map((s: GazeUpSample): number => s.open));
        this.warmup = [];
      }
      return { score: Number.NaN, progress: 0, turn: false };
    }
    const score = gazeUpScore(this.calibration, this.baseIris, this.baseOpen, sample.iris, sample.open);
    if (score < READING_SCORE) {
      this.baseIris += (sample.iris - this.baseIris) * BASELINE_FOLLOW;
      this.baseOpen += (sample.open - this.baseOpen) * BASELINE_FOLLOW;
      this.needReturn = false;
    }
    if (sample.at < this.cooldownUntil || this.needReturn) {
      this.clearHold();
      return this.result(score, 0, false);
    }
    const keep = this.holdSamples > 0 ? this.calibration.threshold * HOLD_KEEP_RATIO : this.calibration.threshold;
    if (score < keep) {
      this.clearHold();
      return this.result(score, this.approachProgress(score), false);
    }
    if (this.holdSamples === 0) this.holdStartedAt = sample.at;
    this.holdSamples++;
    if (this.holdSamples >= 2 && sample.at - this.holdStartedAt >= GAZE_UP_HOLD_MS) {
      this.clearHold();
      this.cooldownUntil = sample.at + GAZE_UP_COOLDOWN_MS;
      this.needReturn = true;
      return this.result(score, 1, true);
    }
    return this.result(score, this.holdProgress(sample.at), false);
  }

  private result(score: number, progress: number, turn: boolean): GazeUpResult {
    this.lastProgress = progress;
    return { score: score, progress: progress, turn: turn };
  }

  /** Below the threshold: fill in steps of 0.1 as the gaze rises from half the threshold towards it. */
  private approachProgress(score: number): number {
    const start = this.calibration.threshold * CUE_START_RATIO;
    if (!(score > start)) return 0;
    const ratio = Math.min(1, (score - start) / (this.calibration.threshold - start));
    return Math.round(ratio * CUE_APPROACH_MAX * 10) / 10;
  }

  private holdProgress(now: number): number {
    const ratio = Math.max(0, Math.min(1, (now - this.holdStartedAt) / GAZE_UP_HOLD_MS));
    return Math.min(0.9, Math.round((CUE_APPROACH_MAX + (1 - CUE_APPROACH_MAX) * ratio) * 10) / 10);
  }

  private clearHold(): void {
    this.holdStartedAt = 0;
    this.holdSamples = 0;
  }
}
