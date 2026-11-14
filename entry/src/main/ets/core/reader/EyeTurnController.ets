import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { faceDetector } from '@kit.CoreVisionKit';
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import lazy { FaceEyeLandmarks, FaceEyeSample } from '@legado/aiengine';
import {
  defaultGazeUpCalibration,
  GazeUpCalibration,
  GazeUpDetector,
  GazeUpResult,
  parseGazeUpCalibration
} from './GazeUpDetector';

export class EyeTurnCalibration {
  version: number = 1;
  top: number = 0;
  center: number = 0;
  bottom: number = 0;
  pitchCenter: number = 0;
  pitchScale: number = 0;
  pitchTopDelta: number = 0;
  pitchBottomDelta: number = 0;
  eyeCenter: number = 0.5;
  eyeScale: number = 0;
  eyeTopDelta: number = 0;
  eyeBottomDelta: number = 0;
  pitchWeight: number = 0;
  eyeWeight: number = 0;
  // True when the calibration defines an absolute zero (the top fixation), so the
  // runtime must NOT re-centre the score around the startup baseline.
  absolute: boolean = false;

  static parse(raw: string): EyeTurnCalibration | null {
    const parts = (raw || '').split(',');
    if (parts.length === 10 && parts[0] === 'v4') {
      const calibration = new EyeTurnCalibration();
      calibration.version = 4;
      calibration.top = -1;
      calibration.center = 0;
      calibration.bottom = 1;
      calibration.pitchCenter = Number(parts[1]);
      calibration.pitchTopDelta = Number(parts[2]);
      calibration.pitchBottomDelta = Number(parts[3]);
      calibration.pitchScale = (calibration.pitchBottomDelta - calibration.pitchTopDelta) / 2;
      calibration.eyeCenter = Number(parts[4]);
      calibration.eyeTopDelta = Number(parts[5]);
      calibration.eyeBottomDelta = Number(parts[6]);
      calibration.eyeScale = (calibration.eyeBottomDelta - calibration.eyeTopDelta) / 2;
      calibration.pitchWeight = Number(parts[7]);
      calibration.eyeWeight = Number(parts[8]);
      calibration.absolute = parts[9] === '1';
      return calibration.isValid() ? calibration : null;
    }
    if (parts.length === 9 && parts[0] === 'v3') {
      const calibration = new EyeTurnCalibration();
      calibration.version = 3;
      calibration.top = -1;
      calibration.center = 0;
      calibration.bottom = 1;
      calibration.pitchCenter = Number(parts[1]);
      calibration.pitchTopDelta = Number(parts[2]);
      calibration.pitchBottomDelta = Number(parts[3]);
      calibration.pitchScale = (calibration.pitchBottomDelta - calibration.pitchTopDelta) / 2;
      calibration.eyeCenter = Number(parts[4]);
      calibration.eyeTopDelta = Number(parts[5]);
      calibration.eyeBottomDelta = Number(parts[6]);
      calibration.eyeScale = (calibration.eyeBottomDelta - calibration.eyeTopDelta) / 2;
      calibration.pitchWeight = Number(parts[7]);
      calibration.eyeWeight = Number(parts[8]);
      return calibration.isValid() ? calibration : null;
    }
    if (parts.length === 7 && parts[0] === 'v2') {
      const calibration = new EyeTurnCalibration();
      calibration.version = 2;
      calibration.top = -1;
      calibration.center = 0;
      calibration.bottom = 1;
      calibration.pitchCenter = Number(parts[1]);
      calibration.pitchScale = Number(parts[2]);
      calibration.pitchTopDelta = -calibration.pitchScale;
      calibration.pitchBottomDelta = calibration.pitchScale;
      calibration.eyeCenter = Number(parts[3]);
      calibration.eyeScale = Number(parts[4]);
      calibration.eyeTopDelta = -calibration.eyeScale;
      calibration.eyeBottomDelta = calibration.eyeScale;
      calibration.pitchWeight = Number(parts[5]);
      calibration.eyeWeight = Number(parts[6]);
      return calibration.isValid() ? calibration : null;
    }
    if (parts.length !== 3) return null;
    const calibration = new EyeTurnCalibration();
    calibration.top = Number(parts[0]);
    calibration.center = Number(parts[1]);
    calibration.bottom = Number(parts[2]);
    return calibration.isValid() ? calibration : null;
  }

  encode(): string {
    if (this.version >= 3) {
      if (this.absolute) {
        return `v4,${this.pitchCenter.toFixed(5)},${this.pitchTopDelta.toFixed(5)},` +
          `${this.pitchBottomDelta.toFixed(5)},${this.eyeCenter.toFixed(5)},` +
          `${this.eyeTopDelta.toFixed(5)},${this.eyeBottomDelta.toFixed(5)},` +
          `${this.pitchWeight.toFixed(4)},${this.eyeWeight.toFixed(4)},1`;
      }
      return `v3,${this.pitchCenter.toFixed(5)},${this.pitchTopDelta.toFixed(5)},` +
        `${this.pitchBottomDelta.toFixed(5)},${this.eyeCenter.toFixed(5)},` +
        `${this.eyeTopDelta.toFixed(5)},${this.eyeBottomDelta.toFixed(5)},` +
        `${this.pitchWeight.toFixed(4)},${this.eyeWeight.toFixed(4)}`;
    }
    if (this.version >= 2) {
      return `v2,${this.pitchCenter.toFixed(5)},${this.pitchScale.toFixed(5)},` +
        `${this.eyeCenter.toFixed(5)},${this.eyeScale.toFixed(5)},` +
        `${this.pitchWeight.toFixed(4)},${this.eyeWeight.toFixed(4)}`;
    }
    return `${this.top.toFixed(4)},${this.center.toFixed(4)},${this.bottom.toFixed(4)}`;
  }

  isValid(): boolean {
    if (this.version >= 3) {
      const values = [this.pitchCenter, this.pitchTopDelta, this.pitchBottomDelta, this.eyeCenter,
        this.eyeTopDelta, this.eyeBottomDelta, this.pitchWeight, this.eyeWeight];
      for (const value of values) {
        if (!Number.isFinite(value)) return false;
      }
      const pitchAvailable = Math.abs(this.pitchTopDelta) >= 0.08 &&
        Math.abs(this.pitchBottomDelta) >= 0.08 && this.pitchTopDelta * this.pitchBottomDelta < 0 &&
        this.pitchWeight > 0;
      const eyeAvailable = Math.abs(this.eyeTopDelta) >= 0.0015 &&
        Math.abs(this.eyeBottomDelta) >= 0.0015 && this.eyeTopDelta * this.eyeBottomDelta < 0 &&
        this.eyeWeight > 0;
      return (pitchAvailable || eyeAvailable) && this.pitchWeight >= 0 && this.eyeWeight >= 0 &&
        this.pitchWeight + this.eyeWeight >= 0.9;
    }
    if (this.version >= 2) {
      const values = [this.pitchCenter, this.pitchScale, this.eyeCenter, this.eyeScale,
        this.pitchWeight, this.eyeWeight];
      for (const value of values) {
        if (!Number.isFinite(value)) return false;
      }
      const pitchAvailable = Math.abs(this.pitchScale) >= 0.08 && this.pitchWeight > 0;
      const eyeAvailable = Math.abs(this.eyeScale) >= 0.0015 && this.eyeWeight > 0;
      return (pitchAvailable || eyeAvailable) && this.pitchWeight >= 0 && this.eyeWeight >= 0 &&
        this.pitchWeight + this.eyeWeight >= 0.9;
    }
    if (!Number.isFinite(this.top) || !Number.isFinite(this.center) || !Number.isFinite(this.bottom)) return false;
    const topDelta = this.top - this.center;
    const bottomDelta = this.bottom - this.center;
    // The public face API does not expose an iris/gaze vector. Small, consistent pitch/eye-band changes are
    // therefore meaningful after a supervised three-point calibration; the runtime dwell filter still prevents
    // an isolated noisy frame from turning a page.
    return Math.abs(topDelta) >= 0.45 && Math.abs(bottomDelta) >= 0.45 && topDelta * bottomDelta < 0;
  }

  scoreForSample(sample: EyeTurnSample): number {
    if (this.version < 2) return sample.rawScore;
    // The iris channel is the primary signal: it is far steadier than the public face
    // API's head-pose pitch, which on some devices jumps tens of degrees per frame.
    // Pitch is only a coarse fallback for frames where the eye band was unavailable.
    const irisScore = this.irisScoreForSample(sample);
    if (Number.isFinite(irisScore)) return irisScore;
    return this.clampNormalized(sample.pitch / EyeTurnController.PITCH_FALLBACK_RANGE_DEG);
  }

  private irisScoreForSample(sample: EyeTurnSample): number {
    if (!sample.eyeAvailable) return Number.NaN;
    const eyeTopDelta = this.version >= 3 ? this.eyeTopDelta : -this.eyeScale;
    const eyeBottomDelta = this.version >= 3 ? this.eyeBottomDelta : this.eyeScale;
    if (Math.abs(eyeTopDelta) < 0.0015 && Math.abs(eyeBottomDelta) < 0.0015) return Number.NaN;
    // A calibration can fit a far too small iris span (for example +-0.02 when the real
    // ratio moves by 0.3). Substitute a plausible physical magnitude but keep the fitted
    // direction, so the channel neither saturates nor gets its polarity rewritten.
    const topDelta = Math.abs(eyeTopDelta) < EyeTurnController.EYE_MIN_TRUSTED_DELTA ?
      (eyeTopDelta < 0 ? -EyeTurnController.EYE_FALLBACK_RANGE : EyeTurnController.EYE_FALLBACK_RANGE) :
      eyeTopDelta;
    const bottomDelta = Math.abs(eyeBottomDelta) < EyeTurnController.EYE_MIN_TRUSTED_DELTA ?
      (eyeBottomDelta < 0 ? -EyeTurnController.EYE_FALLBACK_RANGE : EyeTurnController.EYE_FALLBACK_RANGE) :
      eyeBottomDelta;
    // Direction is taken from the calibration as fitted on this device. Both earlier attempts
    // to "correct" it (first forcing the bottom delta positive, then negative) made the
    // gesture point the wrong way, so the fitted sign is trusted here.
    return this.normalizeAsymmetric(sample.eyeRatio - this.eyeCenter, topDelta, bottomDelta);
  }

  private clampNormalized(value: number): number {
    return Math.max(-1.8, Math.min(1.8, value));
  }

  private normalizeAsymmetric(delta: number, topDelta: number, bottomDelta: number): number {
    const topProgress = delta / topDelta;
    const bottomProgress = delta / bottomDelta;
    if (topProgress > 0 && topProgress >= bottomProgress) return -this.clampNormalized(topProgress);
    if (bottomProgress > 0) return this.clampNormalized(bottomProgress);
    return 0;
  }
}

/** Pixel rectangle of one eye box inside the camera frame. */
class EyeRect {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;

  static fromBounds(startX: number, endX: number, startY: number, endY: number): EyeRect {
    const rect = new EyeRect();
    rect.x = startX;
    rect.y = startY;
    rect.width = Math.max(0, endX - startX);
    rect.height = Math.max(0, endY - startY);
    return rect;
  }
}

class EyeCenterPair {
  leftX: number = 0;
  leftY: number = 0;
  rightX: number = 0;
  rightY: number = 0;
}

export class EyeTurnSample {
  rawScore: number = 0;
  pitch: number = 0;
  eyeRatio: number = 0.5;
  eyeAvailable: boolean = false;
  confidence: number = 0;
  capturedAt: number = 0;
  // Face-mesh measurement (new model); only filled while the model mode is on.
  meshAvailable: boolean = false;
  meshIris: number = Number.NaN;
  meshOpen: number = Number.NaN;
  meshPresence: number = 0;
}

export type EyeTurnStatusCallback = (status: string) => void;
export type EyeTurnSampleCallback = (sample: EyeTurnSample) => void;
export type EyeTurnRequestCallback = (direction: number) => void;
export type EyeTurnAvailabilityCallback = () => boolean;
/**
 * 翻页提示：progress 0–1 是填色进度（按 0.1 取整），armed 表示旧版已在等待抬眼确认，visible 表示提示该显示。
 * 旧版只在有进度或 armed 时显示；新版识别到人脸后常驻显示淡色提示，往上看时填色。
 */
export type EyeTurnCueCallback = (progress: number, armed: boolean, visible: boolean) => void;
export type EyeTurnModelUnavailableCallback = () => void;

/**
 * Reader-only, fully local eye-turn runtime.
 *
 * The public face detector supplies a stable head pitch and face rectangle but no gaze coordinate. The runtime
 * therefore combines pitch with the dark-centroid movement inside both eye bands. A three-point user calibration
 * maps that device/camera-specific score to top, centre and bottom zones. No camera frame leaves the device.
 */
export class EyeTurnController {
  private static readonly FRAME_INTERVAL_MS: number = 120;
  private static readonly PREVIEW_MAX_FPS: number = 15;
  private static readonly PREVIEW_MIN_FPS: number = 10;
  // Face-mesh gaze can run beside the eye-band heuristic and log both values for on-device comparison. It stays off:
  // the extra crop and inference per frame stretched sampling from ~120 ms to ~300-450 ms, so a brief upward glance
  // produced a single low sample and the two-sample confirm never fired.
  private static readonly FACE_MESH_SHADOW: boolean = false;
  // In model mode the next frame is requested right after the previous one finishes; face detection, crop and
  // inference already take 100-200 ms, so a long fixed interval would make a short upward glance a single sample.
  private static readonly MODEL_FRAME_INTERVAL_MS: number = 40;
  private static readonly MODEL_MISSING_FRAME_INTERVAL_MS: number = 200;
  private static readonly TURN_COOLDOWN_MS: number = 700;
  // How long an ignored prompt stays before it is dropped (the reader must visit the
  // bottom again to raise it).
  private static readonly PROMPT_GIVEUP_MS: number = 2500;
  // Looking down has a smaller comfortable range than looking up on a handheld screen. Keep separate thresholds
  // so the next-page gesture does not require an exaggerated head tilt when the public face API has to fall back
  // to pose tracking. Dwell, centre re-arming and cooldown still guard against accidental turns while reading.
  private static readonly NEXT_ZONE_ENTRY_THRESHOLD: number = 0.35;
  private static readonly ZONE_KEEP_THRESHOLD: number = 0.25;
  private static readonly MIN_FACE_PROBABILITY: number = 0.42;
  private static readonly CALIBRATION_MIN_FACE_PROBABILITY: number = 0.30;
  private static readonly MAX_TRANSIENT_MISSING_FRAMES: number = 2;
  private static readonly BASELINE_SAMPLE_COUNT: number = 15;
  private static readonly SCORE_MEDIAN_WINDOW: number = 3;
  private static readonly CENTER_FRAME_INTERVAL_MS: number = 280;
  private static readonly MISSING_FRAME_INTERVAL_MS: number = 360;
  // Cap the baseline correction so a baseline captured during a bad moment cannot park
  // the signal permanently inside (or outside) the trigger zone.
  private static readonly MAX_RUNTIME_CENTER_OFFSET: number = 0.5;
  // Head-pose span used when the calibrated channels are unusable. The public face
  // API pitch here swings by tens of degrees, so this must be generous: a small span
  // saturates every reading and the score stops carrying information.
  static readonly PITCH_FALLBACK_RANGE_DEG: number = 12;
  // Iris-ratio span used when the calibration fitted an implausibly small eye range.
  // The real ratio on this hardware moves by roughly 0.3 across the screen.
  static readonly EYE_MIN_TRUSTED_DELTA: number = 0.03;
  // Iris-ratio span for a full top-to-bottom gaze swing. Measured on-device reading
  // gestures move the ratio by only ~0.045, so a larger span left every score below
  // the zone thresholds and the gesture never registered.
  static readonly EYE_FALLBACK_RANGE: number = 0.04;
  // A larger pitch change than this between two frames is a detector glitch, not a head move.
  private static readonly MAX_PITCH_JUMP_DEG: number = 25;

  private surfaceId: string = '';
  private surfaceWidth: number = 0;
  private surfaceHeight: number = 0;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private photoSession: camera.PhotoSession | null = null;
  private frameTimerId: number = -1;
  private runSerial: number = 0;
  private starting: boolean = false;
  private running: boolean = false;
  private detectorReady: boolean = false;
  private calibrationMode: boolean = false;
  private lastTrackingStatus: string = '';
  private lastTrackingStatusAt: number = 0;
  private calibration: EyeTurnCalibration | null = null;
  private nextDwellMs: number = 1000;
  // Stage-2 state: the bottom prompt has been raised and an upward move now turns the page.
  private nextConfirmArmed: boolean = false;
  // Score recorded when the bottom prompt was raised; the upward confirm is measured
  // as a large relative drop from it, so an offset or inverted-looking calibration
  // cannot stop the gesture.
  private promptScore: number = 0;
  private confirmStreak: number = 0;
  private promptCenterSince: number = 0;
  private smoothedScore: number = Number.NaN;
  private currentZone: number = 0;
  // True once the bottom-edge prompt has asked the reader to look up; an upward move then turns the page.
  private lastAcceptedPitch: number = Number.NaN;
  private lastDiagAt: number = 0;
  private lastNoSignalProbeAt: number = 0;
  private zoneSampleCount: number = 0;
  private missingFrameCount: number = 0;
  private zoneStartedAt: number = 0;
  private cooldownUntil: number = 0;
  private scoreWindow: number[] = [];
  private baselineScores: number[] = [];
  private baselineReady: boolean = false;
  private runtimeCenterOffset: number = 0;
  private nextFrameDelayMs: number = EyeTurnController.FRAME_INTERVAL_MS;
  private lastRuntimeStatus: string = '';
  private onStatus: EyeTurnStatusCallback = (_status: string): void => {};
  private onSample: EyeTurnSampleCallback = (_sample: EyeTurnSample): void => {};
  private onTurn: EyeTurnRequestCallback = (_direction: number): void => {};
  private canTurn: EyeTurnAvailabilityCallback = (): boolean => false;
  private onCue: EyeTurnCueCallback = (_progress: number, _armed: boolean, _visible: boolean): void => {};
  private lastCueProgress: number = 0;
  private lastCueArmed: boolean = false;
  private lastCueVisible: boolean = false;
  // Model mode: a face has been measured since the last reset, so the resting cue may show.
  private modelTracking: boolean = false;
  private faceMesh: FaceEyeLandmarks | null = null;
  private faceMeshLoading: boolean = false;
  private faceMeshFailed: boolean = false;
  // New model mode: the face mesh drives a "look above the screen" gesture instead of the eye-band heuristic.
  private modelMode: boolean = false;
  private gazeDetector: GazeUpDetector = new GazeUpDetector(defaultGazeUpCalibration());
  private modelCueProgress: number = 0;
  private onModelUnavailable: EyeTurnModelUnavailableCallback = (): void => {};
  private abilityContext: common.UIAbilityContext | null = null;

  static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    const manager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = ['ohos.permission.CAMERA'];
    const result: PermissionRequestResult = await manager.requestPermissionsFromUser(context, permissions);
    return result.authResults.length > 0 && result.authResults[0] === 0;
  }

  configure(calibrationRaw: string, nextDwellMs: number,
    onStatus: EyeTurnStatusCallback, onSample: EyeTurnSampleCallback,
    onTurn: EyeTurnRequestCallback, canTurn: EyeTurnAvailabilityCallback): void {
    this.calibration = EyeTurnCalibration.parse(calibrationRaw);
    const loaded = this.calibration;
    console.info(loaded !== null ?
      `[EyeTurn] calibration v=${loaded.version} pitchWeight=${loaded.pitchWeight} ` +
      `eyeWeight=${loaded.eyeWeight} pitchCenter=${loaded.pitchCenter.toFixed(2)} ` +
      `pitchTop=${loaded.pitchTopDelta.toFixed(2)} pitchBottom=${loaded.pitchBottomDelta.toFixed(2)} ` +
      `eyeCenter=${loaded.eyeCenter.toFixed(3)} eyeTop=${loaded.eyeTopDelta.toFixed(4)} ` +
      `eyeBottom=${loaded.eyeBottomDelta.toFixed(4)}` :
      '[EyeTurn] calibration missing or invalid');
    this.nextDwellMs = Math.max(400, Math.min(Math.round(nextDwellMs), 2000));
    this.onStatus = onStatus;
    this.onSample = onSample;
    this.onTurn = onTurn;
    this.canTurn = canTurn;
    this.resetDwellState();
  }

  /**
   * Switches between the eye-band heuristic (off) and the face-mesh model (on). The two keep separate calibrations;
   * an empty or invalid model calibration falls back to measured defaults. If the model cannot load on this device
   * `onUnavailable` runs once and the controller returns to the heuristic.
   */
  configureModel(enabled: boolean, calibrationRaw: string, onUnavailable: EyeTurnModelUnavailableCallback): void {
    this.onModelUnavailable = onUnavailable;
    const parsed: GazeUpCalibration | null = parseGazeUpCalibration(calibrationRaw);
    const calibration: GazeUpCalibration = parsed || defaultGazeUpCalibration();
    this.gazeDetector.setCalibration(calibration);
    const wasModel = this.modelMode;
    this.modelMode = enabled && !this.faceMeshFailed;
    console.info(`[EyeTurn] model mode=${this.modelMode} calibrated=${parsed !== null} ` +
      `threshold=${calibration.threshold.toFixed(2)}`);
    if (this.modelMode !== wasModel) this.resetDwellState();
    if (this.modelMode && this.abilityContext) this.loadFaceMesh(this.abilityContext);
    if (enabled && this.faceMeshFailed) onUnavailable();
  }

  isModelMode(): boolean {
    return this.modelMode;
  }

  /** 阅读页的翻页提示按它显示：状态文字会被眨眼等瞬时丢帧打断，提示不能跟着闪。 */
  setCueListener(onCue: EyeTurnCueCallback): void {
    this.onCue = onCue;
    this.lastCueProgress = -1;
    this.reportCue();
  }

  submitExternalScore(score: number, confidence: number = 1): void {
    if (!Number.isFinite(score)) return;
    const normalized = Math.max(-1.8, Math.min(1.8, score));
    const sample = new EyeTurnSample();
    sample.rawScore = normalized;
    sample.pitch = normalized;
    sample.confidence = confidence;
    sample.capturedAt = Date.now();
    this.onSample(sample);
    this.consumeScore(normalized);
  }

  setCalibration(raw: string): void {
    this.calibration = EyeTurnCalibration.parse(raw);
    this.resetDwellState();
  }

  setCalibrationMode(enabled: boolean): void {
    this.calibrationMode = enabled;
    this.lastTrackingStatus = '';
    this.lastTrackingStatusAt = 0;
    this.resetDwellState();
  }

  isRunning(): boolean {
    return this.running;
  }

  async start(context: common.UIAbilityContext, surfaceId: string): Promise<void> {
    if (!surfaceId) return;
    if (this.running && this.surfaceId === surfaceId) return;
    if (this.starting) return;
    this.starting = true;
    const serial = ++this.runSerial;
    await this.releaseCamera();
    this.surfaceId = surfaceId;
    try {
      this.onStatus('正在启动眼动识别');
      const detectorInitialized = await faceDetector.init();
      if (serial !== this.runSerial) return;
      if (!detectorInitialized) throw new Error('设备人脸检测服务初始化失败');
      this.detectorReady = true;
      const manager = camera.getCameraManager(context);
      const devices = manager.getSupportedCameras();
      let frontCamera: camera.CameraDevice | null = null;
      for (const device of devices) {
        if (device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT) {
          frontCamera = device;
          break;
        }
      }
      if (!frontCamera) throw new Error('设备没有可用的前置摄像头');
      const capability = manager.getSupportedOutputCapability(frontCamera, camera.SceneMode.NORMAL_PHOTO);
      const profile = this.choosePreviewProfile(capability.previewProfiles);
      if (!profile) throw new Error('前置摄像头没有可用的预览尺寸');
      this.surfaceWidth = profile.size.width;
      this.surfaceHeight = profile.size.height;
      this.cameraInput = manager.createCameraInput(frontCamera);
      await this.cameraInput.open();
      if (serial !== this.runSerial) return;
      this.previewOutput = manager.createPreviewOutput(profile, surfaceId);
      this.photoSession = manager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
      this.photoSession.beginConfig();
      this.photoSession.addInput(this.cameraInput);
      this.photoSession.addOutput(this.previewOutput);
      await this.photoSession.commitConfig();
      this.capPreviewFrameRate(this.previewOutput);
      await this.photoSession.start();
      if (serial !== this.runSerial) return;
      this.running = true;
      this.starting = false;
      console.info(`[EyeTurn] camera started ${this.surfaceWidth}x${this.surfaceHeight} ` +
        `(front camera session running; the system camera indicator should be visible now)`);
      this.resetDwellState();
      this.abilityContext = context;
      this.loadFaceMesh(context);
      this.onStatus(this.calibration ? '请注视屏幕中央' : '需要校准眼动翻页');
      this.scheduleFrame(serial, 260);
    } catch (error) {
      if (serial !== this.runSerial) return;
      this.starting = false;
      this.running = false;
      const message = error instanceof Error ? error.message : String(error);
      this.onStatus(`眼动识别不可用：${message}`);
      console.error('[EyeTurn] start failed:', error);
      await this.releaseCamera();
    }
  }

  async stop(): Promise<void> {
    ++this.runSerial;
    this.running = false;
    this.starting = false;
    if (this.frameTimerId >= 0) {
      clearTimeout(this.frameTimerId);
      this.frameTimerId = -1;
    }
    await this.releaseCamera();
    this.surfaceId = '';
    this.resetDwellState();
  }

  private choosePreviewProfile(profiles: camera.Profile[]): camera.Profile | null {
    let selected: camera.Profile | null = null;
    let selectedDistance = Number.MAX_SAFE_INTEGER;
    for (const profile of profiles) {
      const area = profile.size.width * profile.size.height;
      if (profile.size.width < 240 || profile.size.height < 180) continue;
      const aspectPenalty = Math.abs(profile.size.width / profile.size.height - 4 / 3) * 400000;
      const distance = Math.abs(area - 640 * 480) + aspectPenalty;
      if (distance < selectedDistance) {
        selected = profile;
        selectedDistance = distance;
      }
    }
    if (!selected && profiles.length > 0) selected = profiles[0];
    return selected;
  }

  /**
   * The sampler reads at most ~8 frames a second, so a 30 fps preview only burns power. Cap the stream at 15 fps and
   * let it drop to 10 fps so a dim bedside light can still get a long enough exposure for the eyes to show.
   */
  private capPreviewFrameRate(output: camera.PreviewOutput): void {
    try {
      const ranges = output.getSupportedFrameRates();
      if (!ranges || ranges.length === 0) return;
      let bestMin = -1;
      let bestMax = -1;
      for (const range of ranges) {
        if (range.min > EyeTurnController.PREVIEW_MAX_FPS) continue;
        const maxFps = Math.min(range.max, EyeTurnController.PREVIEW_MAX_FPS);
        const minFps = Math.max(range.min, Math.min(EyeTurnController.PREVIEW_MIN_FPS, maxFps));
        if (maxFps > bestMax || (maxFps === bestMax && minFps < bestMin)) {
          bestMin = minFps;
          bestMax = maxFps;
        }
      }
      if (bestMax <= 0) return;
      output.setFrameRate(bestMin, bestMax);
      console.info(`[EyeTurn] preview frame rate capped at ${bestMin}-${bestMax} fps`);
    } catch (error) {
      // Some drivers reject custom ranges; the sampler still works at the default rate.
      console.warn('[EyeTurn] preview frame rate cap unavailable:', error instanceof Error ? error.message : String(error));
    }
  }

  private scheduleFrame(serial: number, delayMs: number = EyeTurnController.FRAME_INTERVAL_MS): void {
    if (!this.running || serial !== this.runSerial) return;
    if (this.frameTimerId >= 0) clearTimeout(this.frameTimerId);
    this.frameTimerId = setTimeout((): void => {
      this.frameTimerId = -1;
      this.processFrame(serial).catch((error: Error): void => {
        console.warn('[EyeTurn] frame skipped:', error.message);
      });
    }, delayMs);
  }

  private async processFrame(serial: number): Promise<void> {
    if (!this.running || serial !== this.runSerial || !this.detectorReady || !this.surfaceId) return;
    const capturedAt = Date.now();
    let pixelMap: image.PixelMap | null = null;
    try {
      const region: image.Region = {
        x: 0,
        y: 0,
        size: { width: this.surfaceWidth, height: this.surfaceHeight }
      };
      pixelMap = await image.createPixelMapFromSurface(this.surfaceId, region);
      if (!pixelMap || serial !== this.runSerial) return;
      const faces = await faceDetector.detect({ pixelMap: pixelMap });
      if (serial !== this.runSerial) return;
      const face = this.selectPrimaryFace(faces);
      const minimumProbability = this.calibrationMode ?
        EyeTurnController.CALIBRATION_MIN_FACE_PROBABILITY : EyeTurnController.MIN_FACE_PROBABILITY;
      // CoreVision reports the front-camera frame in sensor coordinates on several landscape devices. A person
      // visibly centred in the preview can therefore carry 35-45 degrees of yaw/roll. Reject only genuinely
      // side-on frames; calibration already maps the device-specific pitch axis and confidence remains enforced.
      const maximumRotation = this.calibrationMode ? 62 : 58;
      const modelMode = this.modelMode;
      if (!face) {
        this.reportTrackingStatus('未检测到面部，请将手机保持在面部正前方');
        this.probeNoSignal('no face detected in frame');
        this.consumeNoFace();
        return;
      }
      if (face.probability < minimumProbability) {
        this.reportTrackingStatus('面部识别不稳定，请保证正面光线充足');
        this.probeNoSignal(`low probability ${face.probability.toFixed(2)}`);
        this.consumeNoFace();
        return;
      }
      // The model finds the face orientation itself, so in-plane roll (often 40-55 degrees in sensor coordinates)
      // is only a problem for the eye-band heuristic; a side-on face (yaw) is rejected in both modes.
      if (Math.abs(face.pose.yaw) > maximumRotation || (!modelMode && Math.abs(face.pose.roll) > maximumRotation)) {
        this.reportTrackingStatus('请将手机摆正并正对屏幕');
        this.probeNoSignal(`bad pose yaw=${face.pose.yaw.toFixed(0)} roll=${face.pose.roll.toFixed(0)}`);
        this.consumeNoFace();
        return;
      }
      if (modelMode) {
        await this.processModelFrame(pixelMap, face, capturedAt);
        return;
      }
      // Pixel-buffer reading is not implemented consistently by every camera driver. It refines the score when
      // available, but must not discard an otherwise valid face-pose sample or calibration will appear frozen.
      let eyeRatio = 0.5;
      let eyeBandAvailable = false;
      try {
        const detectedEyeRatio = await this.estimateEyeVerticalRatio(pixelMap, face);
        if (detectedEyeRatio >= 0) {
          eyeRatio = detectedEyeRatio;
          eyeBandAvailable = true;
        }
      } catch (error) {
        console.warn('[EyeTurn] eye-band refinement unavailable:', error instanceof Error ? error.message : String(error));
      }
      const sample = new EyeTurnSample();
      sample.pitch = face.pose.pitch;
      sample.eyeRatio = eyeRatio;
      sample.eyeAvailable = eyeBandAvailable;
      sample.rawScore = face.pose.pitch + (eyeRatio - 0.5) * 18;
      sample.confidence = face.probability;
      sample.capturedAt = capturedAt;
      // The public face API occasionally reports an impossible pose jump between two
      // frames (tens of degrees). Only guard the pitch fallback: the iris channel is
      // unaffected and dropping its samples would starve the primary signal.
      if (!eyeBandAvailable && Number.isFinite(this.lastAcceptedPitch) &&
        Math.abs(sample.pitch - this.lastAcceptedPitch) > EyeTurnController.MAX_PITCH_JUMP_DEG) {
        console.info(`[EyeTurn] dropped pitch glitch=${sample.pitch.toFixed(1)}`);
        return;
      }
      this.lastAcceptedPitch = sample.pitch;
      this.missingFrameCount = 0;
      if (!eyeBandAvailable) this.probeNoSignal('eye band unavailable (pitch fallback only)');
      this.reportTrackingStatus(eyeBandAvailable ? '已检测到视线，准备采样' : '已检测到面部，准备采样');
      this.onSample(sample);
      await this.probeFaceMesh(pixelMap, face, sample);
      if (serial !== this.runSerial) return;
      const normalizedScore = this.calibration ? this.calibration.scoreForSample(sample) : sample.rawScore;
      console.info(`[EyeTurn] accepted pitch=${sample.pitch.toFixed(2)}, eye=${sample.eyeAvailable ?
        sample.eyeRatio.toFixed(3) : 'n/a'}, score=${normalizedScore.toFixed(2)}`);
      this.consumeScore(normalizedScore);
    } finally {
      if (pixelMap) await pixelMap.release();
      this.scheduleFrame(serial, this.nextFrameDelayMs);
    }
  }

  /** The model loads once per controller and is kept across camera restarts (page turns, foreground changes). */
  private loadFaceMesh(context: common.UIAbilityContext): void {
    if (!(EyeTurnController.FACE_MESH_SHADOW || this.modelMode)) return;
    if (this.faceMesh || this.faceMeshLoading || this.faceMeshFailed) return;
    this.faceMeshLoading = true;
    FaceEyeLandmarks.create(context).then((mesh: FaceEyeLandmarks | null): void => {
      this.faceMesh = mesh;
      this.faceMeshLoading = false;
      this.probe(mesh ? 'face mesh ready' : 'face mesh unavailable');
      if (!mesh) this.handleModelUnavailable();
    }).catch((error: Error): void => {
      this.faceMeshLoading = false;
      this.probe(`face mesh load failed: ${error.message}`);
      this.handleModelUnavailable();
    });
  }

  private handleModelUnavailable(): void {
    this.faceMeshFailed = true;
    if (!this.modelMode) return;
    this.modelMode = false;
    this.resetDwellState();
    this.onModelUnavailable();
  }

  /** Model mode: one face-mesh measurement feeds either the calibration session or the gaze-up gesture. */
  private async processModelFrame(pixelMap: image.PixelMap, face: faceDetector.Face, capturedAt: number):
    Promise<void> {
    const mesh = this.faceMesh;
    if (!mesh) {
      this.reportTrackingStatus('正在加载新版识别模型');
      this.reportRuntimeStatus('正在加载新版识别模型');
      this.nextFrameDelayMs = EyeTurnController.MODEL_MISSING_FRAME_INTERVAL_MS;
      return;
    }
    const result: FaceEyeSample | null =
      await mesh.estimate(pixelMap, face.rect.left, face.rect.top, face.rect.width, face.rect.height);
    if (!result || result.metrics.presence < 0.5 || result.metrics.eyes === 0) {
      // Includes the first frames while the model tries the four camera orientations.
      this.reportTrackingStatus('正在识别眼睛，请正对屏幕');
      this.consumeNoFace();
      return;
    }
    const metrics = result.metrics;
    this.missingFrameCount = 0;
    this.modelTracking = true;
    this.nextFrameDelayMs = EyeTurnController.MODEL_FRAME_INTERVAL_MS;
    const sample = new EyeTurnSample();
    sample.pitch = face.pose.pitch;
    sample.confidence = face.probability;
    sample.capturedAt = capturedAt;
    sample.meshAvailable = true;
    sample.meshIris = metrics.irisOffset;
    sample.meshOpen = metrics.openness;
    sample.meshPresence = metrics.presence;
    this.reportTrackingStatus('已检测到视线，准备采样');
    this.onSample(sample);
    if (this.calibrationMode) return;
    const gaze: GazeUpResult = this.gazeDetector.push({
      iris: metrics.irisOffset,
      open: metrics.openness,
      presence: metrics.presence,
      at: capturedAt
    });
    this.modelCueProgress = gaze.progress;
    const now = Date.now();
    if (now - this.lastDiagAt >= 400 || gaze.turn) {
      this.lastDiagAt = now;
      this.probe(`model score=${Number.isFinite(gaze.score) ? gaze.score.toFixed(2) : 'warmup'} ` +
        `iris=${metrics.irisOffset.toFixed(4)} open=${metrics.openness.toFixed(3)} p=${metrics.presence.toFixed(2)} ` +
        `rot=${result.rotation} crop=${result.cropMs}ms prep=${result.prepMs}ms infer=${result.inferMs}ms/${result.backend} ` +
        `turn=${gaze.turn}`);
    }
    this.reportRuntimeStatus(this.gazeDetector.baselineReady() ? '眼动已就绪' : '请注视正文');
    if (gaze.turn) {
      const allowed = this.canTurn();
      this.probe(`model turn request available=${allowed}`);
      if (allowed) {
        this.reportRuntimeStatus('已翻下一页');
        this.onTurn(1);
      }
    }
    this.reportCue();
  }

  /** Logs the face-mesh gaze next to the eye-band value for the same frame; never affects the gesture. */
  private async probeFaceMesh(pixelMap: image.PixelMap, face: faceDetector.Face, sample: EyeTurnSample): Promise<void> {
    const mesh = this.faceMesh;
    if (!EyeTurnController.FACE_MESH_SHADOW || !mesh) return;
    const result: FaceEyeSample | null =
      await mesh.estimate(pixelMap, face.rect.left, face.rect.top, face.rect.width, face.rect.height);
    if (!result) return;
    const m = result.metrics;
    this.probe(`mesh band=${sample.eyeAvailable ? sample.eyeRatio.toFixed(3) : 'n/a'} ` +
      `iris=${m.irisOffset.toFixed(4)} open=${m.openness.toFixed(3)} lid=${m.lidRatio.toFixed(3)} ` +
      `p=${m.presence.toFixed(2)} rot=${result.rotation}${result.locked ? '' : '?'} eyes=${m.eyes} ` +
      `cal=${this.calibrationMode ? 1 : 0} rect=${Math.round(face.rect.left)},${Math.round(face.rect.top)},` +
      `${Math.round(face.rect.width)}x${Math.round(face.rect.height)} roll=${face.pose.roll.toFixed(0)} ` +
      `crop=${result.cropMs}ms infer=${result.inferMs}ms`);
  }

  private selectPrimaryFace(faces: faceDetector.Face[]): faceDetector.Face | null {
    let selected: faceDetector.Face | null = null;
    let selectedArea = 0;
    for (const face of faces) {
      const area = face.rect.width * face.rect.height;
      if (area > selectedArea) {
        selected = face;
        selectedArea = area;
      }
    }
    return selected;
  }

  private async estimateEyeVerticalRatio(pixelMap: image.PixelMap, face: faceDetector.Face): Promise<number> {
    const info = await pixelMap.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    if (width <= 0 || height <= 0) return -1;
    // Only the two eye boxes (a few thousand pixels) are copied out of the frame; copying the whole
    // 640x480 frame into script memory on every sample was the bulk of the per-frame cost.
    const eyeCenters = this.resolveEyeCenters(face);
    const leftRect = eyeCenters ?
      this.eyeRectAt(width, height, face, eyeCenters.leftX, eyeCenters.leftY) :
      this.eyeBandRect(width, height, face, 0.12, 0.47);
    const rightRect = eyeCenters ?
      this.eyeRectAt(width, height, face, eyeCenters.rightX, eyeCenters.rightY) :
      this.eyeBandRect(width, height, face, 0.53, 0.88);
    const left = await this.eyeBandRatioInRegion(pixelMap, leftRect);
    const right = await this.eyeBandRatioInRegion(pixelMap, rightRect);
    if (left < 0 && right < 0) return -1;
    if (left < 0) return right;
    if (right < 0) return left;
    return (left + right) / 2;
  }

  private resolveEyeCenters(face: faceDetector.Face): EyeCenterPair | null {
    if (!face.points || face.points.length < 2 || face.rect.width <= 0 || face.rect.height <= 0) return null;
    let bestLeftX = 0;
    let bestLeftY = 0;
    let bestRightX = 0;
    let bestRightY = 0;
    let bestQuality = -1;
    for (let leftIndex = 0; leftIndex < face.points.length; leftIndex++) {
      const left = face.points[leftIndex];
      const leftNx = (left.x - face.rect.left) / face.rect.width;
      const leftNy = (left.y - face.rect.top) / face.rect.height;
      if (leftNx < 0.14 || leftNx > 0.55 || leftNy < 0.20 || leftNy > 0.56) continue;
      for (let rightIndex = 0; rightIndex < face.points.length; rightIndex++) {
        const right = face.points[rightIndex];
        const rightNx = (right.x - face.rect.left) / face.rect.width;
        const rightNy = (right.y - face.rect.top) / face.rect.height;
        if (rightNx < 0.45 || rightNx > 0.86 || rightNy < 0.20 || rightNy > 0.56) continue;
        const separation = rightNx - leftNx;
        const verticalDifference = Math.abs(rightNy - leftNy);
        if (separation < 0.20 || verticalDifference > 0.16) continue;
        const quality = separation - verticalDifference * 1.8 -
          Math.abs((leftNy + rightNy) / 2 - 0.39) * 0.5;
        if (quality <= bestQuality) continue;
        bestQuality = quality;
        bestLeftX = left.x;
        bestLeftY = left.y;
        bestRightX = right.x;
        bestRightY = right.y;
      }
    }
    if (bestQuality < 0) return null;
    const pair = new EyeCenterPair();
    pair.leftX = bestLeftX;
    pair.leftY = bestLeftY;
    pair.rightX = bestRightX;
    pair.rightY = bestRightY;
    return pair;
  }

  private eyeRectAt(imageWidth: number, imageHeight: number, face: faceDetector.Face,
    centerX: number, centerY: number): EyeRect {
    const halfWidth = Math.max(5, face.rect.width * 0.105);
    return EyeRect.fromBounds(
      this.clampPixel(Math.round(centerX - halfWidth), imageWidth),
      this.clampPixel(Math.round(centerX + halfWidth), imageWidth),
      this.clampPixel(Math.round(centerY - face.rect.height * 0.045), imageHeight),
      this.clampPixel(Math.round(centerY + face.rect.height * 0.065), imageHeight));
  }

  private eyeBandRect(imageWidth: number, imageHeight: number, face: faceDetector.Face,
    xStartRatio: number, xEndRatio: number): EyeRect {
    // Exclude most of the eyebrow band; the remaining strip contains the sclera/iris on ordinary frontal poses.
    return EyeRect.fromBounds(
      this.clampPixel(Math.round(face.rect.left + face.rect.width * xStartRatio), imageWidth),
      this.clampPixel(Math.round(face.rect.left + face.rect.width * xEndRatio), imageWidth),
      this.clampPixel(Math.round(face.rect.top + face.rect.height * 0.34), imageHeight),
      this.clampPixel(Math.round(face.rect.top + face.rect.height * 0.53), imageHeight));
  }

  private async eyeBandRatioInRegion(pixelMap: image.PixelMap, rect: EyeRect): Promise<number> {
    if (rect.width < 8 || rect.height < 5) return -1;
    const stride = rect.width * 4;
    const area: image.PositionArea = {
      pixels: new ArrayBuffer(stride * rect.height),
      offset: 0,
      stride: stride,
      region: { x: rect.x, y: rect.y, size: { width: rect.width, height: rect.height } }
    };
    // readPixels(area) (API 7; readPixelsToArea needs API 26) always yields BGRA_8888, whatever the frame's format.
    await pixelMap.readPixels(area);
    const bytes = new Uint8Array(area.pixels);
    let lumaSum = 0;
    let sampleCount = 0;
    for (let y = 0; y < rect.height; y += 2) {
      for (let x = 0; x < rect.width; x += 2) {
        const offset = y * stride + x * 4;
        lumaSum += (bytes[offset + 2] * 30 + bytes[offset + 1] * 59 + bytes[offset] * 11) / 100;
        sampleCount++;
      }
    }
    if (sampleCount === 0) return -1;
    const mean = lumaSum / sampleCount;
    let weightedY = 0;
    let weightSum = 0;
    const bandHeight = Math.max(1, rect.height);
    for (let y = 0; y < rect.height; y++) {
      for (let x = 0; x < rect.width; x++) {
        const offset = y * stride + x * 4;
        const luma = (bytes[offset + 2] * 30 + bytes[offset + 1] * 59 + bytes[offset] * 11) / 100;
        // The preview stream is often softly exposed on front cameras. A high fixed contrast cut-off discarded
        // the iris entirely and silently produced a constant 0.5 signal. The local mean already rejects the
        // bright sclera, so a small margin preserves the vertical iris movement without amplifying flat bands.
        const weight = Math.max(0, mean - luma - 2);
        if (weight <= 0) continue;
        weightedY += (y / bandHeight) * weight;
        weightSum += weight;
      }
    }
    if (weightSum < 1) return -1;
    return Math.max(0, Math.min(weightedY / weightSum, 1));
  }

  private clampPixel(value: number, limit: number): number {
    return Math.max(0, Math.min(value, Math.max(0, limit - 1)));
  }

  private consumeNoFace(): void {
    this.missingFrameCount++;
    if (this.modelMode) {
      this.nextFrameDelayMs = EyeTurnController.MODEL_MISSING_FRAME_INTERVAL_MS;
      this.modelCueProgress = this.calibrationMode ? 0 : this.gazeDetector.pushMissing().progress;
      this.reportRuntimeStatus('未检测到面部');
      this.reportCue();
      return;
    }
    this.nextFrameDelayMs = EyeTurnController.MISSING_FRAME_INTERVAL_MS;
    this.reportRuntimeStatus('未检测到面部');
    // A blink, a page-turn animation or one blurred camera frame must not erase an otherwise stable dwell. Core
    // Vision sampling is deliberately sparse, so resetting on every missed frame made edge gaze very hard to hold.
    if (this.missingFrameCount <= EyeTurnController.MAX_TRANSIENT_MISSING_FRAMES) return;
    this.currentZone = 0;
    this.zoneSampleCount = 0;
    this.zoneStartedAt = 0;
    this.smoothedScore = Number.NaN;
    this.reportCue();
  }

  private reportCue(): void {
    // 短暂丢帧（眨眼、模糊帧）不收起提示，与停留计时的容忍度一致。
    const tracking = this.missingFrameCount <= EyeTurnController.MAX_TRANSIENT_MISSING_FRAMES;
    const armed = tracking && this.nextConfirmArmed && !this.modelMode;
    let progress = 0;
    if (this.modelMode) {
      // Model mode has no armed stage: the cue fills as the gaze rises towards the threshold, then through the hold.
      progress = tracking && !this.calibrationMode ? this.modelCueProgress : 0;
    } else if (armed) {
      progress = 1;
    } else if (tracking && this.currentZone === 1 && this.zoneStartedAt > 0 && Date.now() >= this.cooldownUntil) {
      const ratio = (Date.now() - this.zoneStartedAt) / Math.max(1, this.nextDwellMs);
      progress = Math.max(0, Math.min(1, Math.round(ratio * 10) / 10));
    }
    // Model mode cannot tell the middle of the page from its bottom, so the cue cannot wait for the end of the page
    // as the old mode does; it stays visible (unfilled) while a face is tracked and fills as the gaze rises.
    const visible = this.modelMode ?
      tracking && this.modelTracking && !this.calibrationMode && this.gazeDetector.baselineReady() :
      armed || progress > 0;
    if (progress === this.lastCueProgress && armed === this.lastCueArmed && visible === this.lastCueVisible) return;
    this.lastCueProgress = progress;
    this.lastCueArmed = armed;
    this.lastCueVisible = visible;
    this.onCue(progress, armed, visible);
  }

  private reportTrackingStatus(status: string): void {
    if (!this.calibrationMode) return;
    const now = Date.now();
    if (status === this.lastTrackingStatus && now - this.lastTrackingStatusAt < 700) return;
    this.lastTrackingStatus = status;
    this.lastTrackingStatusAt = now;
    this.onStatus(status);
  }

  /** Rate-limited probe for frames that produced no usable sample. */
  private probeNoSignal(reason: string): void {
    const now = Date.now();
    if (now - this.lastNoSignalProbeAt < 1000) return;
    this.lastNoSignalProbeAt = now;
    this.probe(`no signal: ${reason}`);
  }

  /** Diagnostics use warn level and a unique marker: plain info on this app is dropped by log rate limiting. */
  private probe(message: string): void {
    console.warn('[EyeTurnProbe] ' + message);
  }

  private reportRuntimeStatus(status: string): void {
    if (this.calibrationMode || status === this.lastRuntimeStatus) return;
    this.lastRuntimeStatus = status;
    this.onStatus(status);
  }

  private medianScore(values: number[]): number {
    if (values.length === 0) return 0;
    const sorted = [...values].sort((left: number, right: number): number => left - right);
    const middle = Math.floor(sorted.length / 2);
    return sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle];
  }

  private consumeScore(rawScore: number): void {
    const calibration = this.calibration;
    if (!calibration || this.calibrationMode) return;
    this.consumeCalibratedScore(rawScore, calibration);
    this.reportCue();
  }

  private consumeCalibratedScore(rawScore: number, calibration: EyeTurnCalibration): void {
    this.scoreWindow.push(rawScore);
    if (this.scoreWindow.length > EyeTurnController.SCORE_MEDIAN_WINDOW) this.scoreWindow.shift();
    const filteredScore = this.medianScore(this.scoreWindow);
    if (!this.baselineReady && calibration.absolute) {
      // An absolute calibration already defines where zero is (the top fixation), so the
      // startup baseline must not drag the reading position back to the centre.
      this.baselineReady = true;
      this.runtimeCenterOffset = 0;
      this.smoothedScore = 0;
    }
    if (!this.baselineReady) {
      this.baselineScores.push(filteredScore);
      this.nextFrameDelayMs = EyeTurnController.FRAME_INTERVAL_MS;
      this.reportRuntimeStatus('请注视屏幕中央');
      if (this.baselineScores.length < EyeTurnController.BASELINE_SAMPLE_COUNT) return;
      this.runtimeCenterOffset = Math.max(-EyeTurnController.MAX_RUNTIME_CENTER_OFFSET,
        Math.min(EyeTurnController.MAX_RUNTIME_CENTER_OFFSET, this.medianScore(this.baselineScores)));
      this.baselineReady = true;
      this.smoothedScore = 0;
      this.reportRuntimeStatus('眼动已就绪');
      console.info(`[EyeTurn] runtime center offset=${this.runtimeCenterOffset.toFixed(3)}`);
      return;
    }
    const centeredScore = filteredScore - this.runtimeCenterOffset;
    // Faster smoothing than before: the reader should not have to hold a gesture for
    // several frames before the runtime notices it.
    this.smoothedScore = Number.isFinite(this.smoothedScore) ?
      this.smoothedScore * 0.3 + centeredScore * 0.7 : centeredScore;
    const now = Date.now();
    const inBottom = this.smoothedScore >= (this.currentZone === 1 ?
      EyeTurnController.ZONE_KEEP_THRESHOLD : EyeTurnController.NEXT_ZONE_ENTRY_THRESHOLD);
    this.nextFrameDelayMs = inBottom ? EyeTurnController.FRAME_INTERVAL_MS :
      EyeTurnController.CENTER_FRAME_INTERVAL_MS;
    if (now - this.lastDiagAt >= 400) {
      this.lastDiagAt = now;
      this.probe(`score=${this.smoothedScore.toFixed(2)} bottom=${inBottom} ` +
        `prompt=${this.nextConfirmArmed} promptScore=${this.promptScore.toFixed(2)} ` +
        `hold=${this.zoneStartedAt > 0 ? now - this.zoneStartedAt : 0}`);
    }
    if (now < this.cooldownUntil) {
      // Short guard after a page turn: the eyes naturally travel away from the old page
      // position and that travel must not immediately trigger the next turn.
      this.resetZoneTracking();
      this.reportRuntimeStatus('翻页保护中');
      return;
    }
    if (this.nextConfirmArmed) {
      // Stage 2 — look up to confirm. Calibrated to the measured on-device gesture: a
      // look-up from the armed bottom level lowers the score by ~40% here, so requiring a
      // half or a zero crossing never fired. Two consecutive samples keep a noisy frame out.
      const droppedEnough = this.promptScore > 0.2 &&
        this.smoothedScore <= this.promptScore * 0.65;
      if (droppedEnough || this.smoothedScore <= EyeTurnController.ZONE_KEEP_THRESHOLD) {
        this.confirmStreak++;
        if (this.confirmStreak >= 2) {
          this.turnNextPage(now);
          return;
        }
        this.reportRuntimeStatus('向上看，翻下一页');
        return;
      }
      this.confirmStreak = 0;
      // Ignored while resting between the two zones: drop the prompt after a while so it
      // does not linger, and re-raise it only by returning to the bottom.
      if (this.smoothedScore < EyeTurnController.NEXT_ZONE_ENTRY_THRESHOLD) {
        if (this.promptCenterSince <= 0) this.promptCenterSince = now;
        if (now - this.promptCenterSince >= EyeTurnController.PROMPT_GIVEUP_MS) {
          this.nextConfirmArmed = false;
          this.promptCenterSince = 0;
          this.resetZoneTracking();
          this.reportRuntimeStatus('眼动已就绪');
          return;
        }
      } else {
        this.promptCenterSince = 0;
      }
      this.reportRuntimeStatus('向上看，翻下一页');
      return;
    }
    // Stage 1 — hold the bottom zone to raise the prompt.
    if (!inBottom) {
      this.resetZoneTracking();
      this.reportRuntimeStatus('眼动已就绪');
      return;
    }
    if (this.currentZone !== 1) {
      this.currentZone = 1;
      this.zoneStartedAt = now;
      this.reportRuntimeStatus('正在注视底部');
      return;
    }
    if (now - this.zoneStartedAt >= this.nextDwellMs) {
      this.nextConfirmArmed = true;
      this.promptScore = this.smoothedScore;
      this.confirmStreak = 0;
      this.promptCenterSince = 0;
      this.probe(`prompt armed at score=${this.smoothedScore.toFixed(2)}`);
      this.reportRuntimeStatus('向上看，翻下一页');
      return;
    }
    this.reportRuntimeStatus('正在注视底部');
  }

  private resetZoneTracking(): void {
    this.currentZone = 0;
    this.zoneSampleCount = 0;
    this.zoneStartedAt = 0;
  }

  private turnNextPage(now: number): void {
    const turnAvailable = this.canTurn();
    this.probe(`turn request available=${turnAvailable} score=${this.smoothedScore.toFixed(2)}`);
    if (!turnAvailable) return; // the reader will keep trying while the gaze stays low
    this.nextConfirmArmed = false;
    this.confirmStreak = 0;
    this.promptCenterSince = 0;
    this.resetZoneTracking();
    this.cooldownUntil = now + EyeTurnController.TURN_COOLDOWN_MS;
    this.reportRuntimeStatus('已翻下一页，请回看中央');
    this.onTurn(1);
  }

  private resetDwellState(): void {
    this.gazeDetector.reset();
    this.modelCueProgress = 0;
    this.modelTracking = false;
    this.smoothedScore = Number.NaN;
    this.currentZone = 0;
    this.nextConfirmArmed = false;
    this.confirmStreak = 0;
    this.promptCenterSince = 0;
    this.promptScore = 0;
    this.zoneSampleCount = 0;
    this.missingFrameCount = 0;
    this.zoneStartedAt = 0;
    this.cooldownUntil = 0;
    this.scoreWindow = [];
    this.baselineScores = [];
    this.baselineReady = false;
    this.runtimeCenterOffset = 0;
    this.nextFrameDelayMs = EyeTurnController.FRAME_INTERVAL_MS;
    this.lastRuntimeStatus = '';
    this.reportCue();
  }

  private async releaseCamera(): Promise<void> {
    if (this.frameTimerId >= 0) {
      clearTimeout(this.frameTimerId);
      this.frameTimerId = -1;
    }
    const session = this.photoSession;
    const preview = this.previewOutput;
    const input = this.cameraInput;
    this.photoSession = null;
    this.previewOutput = null;
    this.cameraInput = null;
    if (session) {
      try { await session.stop(); } catch (_error) {}
      try { await session.release(); } catch (_error) {}
    }
    if (preview) {
      try { await preview.release(); } catch (_error) {}
    }
    if (input) {
      try { await input.close(); } catch (_error) {}
    }
    if (this.detectorReady) {
      this.detectorReady = false;
      try { await faceDetector.release(); } catch (_error) {}
    }
    this.running = false;
  }
}
