import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { EyeTurnCalibration, EyeTurnController, EyeTurnSample } from './EyeTurnController';
import { ArEyeSignal, ArEyeTurnHost } from './ArEyeTypes';
import { ReaderEyeCalibrationPoint } from './ReaderEyeModels';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { ReaderEyeTurnViewState } from './ReaderEyeTurnViewState';

const CALIBRATION_HOLD_MS: number = 1500;
const CALIBRATION_PHASE_COUNT: number = ReaderEyeTurnViewState.PHASE_COUNT;
const CALIBRATION_TICK_MS: number = 60;
const CALIBRATION_MIN_PHASE_SAMPLES: number = 5;
const CALIBRATION_MIN_DELTA: number = 0.005;
// AR Engine reports the gaze direction directly; a synthetic centre/top/bottom mapping is enough for it.
const AR_CALIBRATION_RAW: string = '-1,0,1';
// Used until the reader calibrates: the default iris mapping plus the runtime baseline is already usable.
const DEFAULT_CALIBRATION_RAW: string = 'v3,0,0,0,0.5,-0.04,0.04,0,1';
// AR Engine takes the camera exclusively and is not reliable enough yet, so the camera pipeline is used.
const AR_ENABLED: boolean = false;

export interface ReaderEyeTurnHost {
  abilityContext: () => common.UIAbilityContext;
  enabled: () => boolean;
  setEnabled: (enabled: boolean) => void;
  // stored calibration for one orientation, empty when the reader has not calibrated it
  calibration: (landscape: boolean) => string;
  setCalibration: (landscape: boolean, raw: string) => void;
  nextDwellMs: () => number;
  saveSettings: () => void;
  pageVisible: () => boolean;
  viewportWidth: () => number;
  viewportHeight: () => number;
  // whether a gaze turn may act on the page right now, and why not (diagnostics only)
  canTurn: () => boolean;
  blockReason: () => string;
  turnNext: () => void;
  // the calibration panel covers the page, so menus and the settings panel close first
  closePanels: () => void;
}

/**
 * Eye-turn for the reader page: camera permission, the gaze signal source (camera pipeline, or AR Engine when
 * enabled), orientation-specific calibration and the three-step calibration session.
 */
export class ReaderEyeTurnCoordinator {
  readonly state: ReaderEyeTurnViewState;
  arHost: ArEyeTurnHost | null = null;
  private readonly host: ReaderEyeTurnHost;
  private readonly controller: EyeTurnController = new EyeTurnController();
  private arHostLoading: boolean = false;
  private surfaceId: string = '';
  private configuredLandscape: boolean = false;
  private calibrationPoints: ReaderEyeCalibrationPoint[] = [];
  private calibrationTimerId: number = -1;
  private calibrationPhaseStartedAt: number = 0;
  private calibrationStartupAt: number = 0;
  private calibrationLandscape: boolean = false;
  private permissionRequestSerial: number = 0;

  constructor(state: ReaderEyeTurnViewState, host: ReaderEyeTurnHost) {
    this.state = state;
    this.host = host;
  }

  setEnabled(enabled: boolean): void {
    const serial = ++this.permissionRequestSerial;
    if (!enabled) {
      this.host.setEnabled(false);
      this.state.status = '未启用';
      this.state.showCalibration = false;
      this.release('disable');
      this.host.saveSettings();
      return;
    }
    this.state.status = '正在请求相机权限';
    EyeTurnController.requestPermission(this.host.abilityContext())
      .then((granted: boolean): void => {
        if (serial !== this.permissionRequestSerial) return;
        if (!granted) {
          this.host.setEnabled(false);
          this.state.status = '未获得相机权限';
          HdsFeedback.showToast('需要相机权限才能使用眼动翻页');
          this.host.saveSettings();
          return;
        }
        this.host.setEnabled(true);
        this.state.status = '正在启动眼动识别';
        this.host.saveSettings();
        // Conditional XComponent mounting happens after this state update; its onLoad callback starts the camera.
        setTimeout((): void => this.startIfReady(), 0);
      })
      .catch((error: Error): void => {
        if (serial !== this.permissionRequestSerial) return;
        this.host.setEnabled(false);
        this.state.status = '相机权限请求失败';
        HdsFeedback.showToast(`眼动翻页启用失败：${error.message}`);
        this.host.saveSettings();
      });
  }

  isLandscape(): boolean {
    // The reader viewport can be the width of one pane in landscape double-page mode, which is smaller than the page
    // height and previously saved a landscape calibration into the portrait slot. Display geometry represents the
    // physical screen orientation and must be the primary source for camera calibration selection.
    try {
      const currentDisplay = display.getDefaultDisplaySync();
      if (currentDisplay.width > 0 && currentDisplay.height > 0) {
        return currentDisplay.width > currentDisplay.height;
      }
    } catch (_error) {
      // Fall through to the measured reader viewport on devices without synchronous display geometry.
    }
    const width = this.host.viewportWidth();
    const height = this.host.viewportHeight();
    return width > 0 && height > 0 ? width > height : false;
  }

  /** True when the reader has calibrated at least one orientation. */
  hasStoredCalibration(): boolean {
    return !!(this.host.calibration(false) || this.host.calibration(true));
  }

  private calibrationRaw(): string {
    // AR Engine needs no per-device pitch/iris calibration; the top/centre/bottom recall calibration is for the
    // camera pipeline only.
    if (this.state.arFaceActive) return AR_CALIBRATION_RAW;
    const landscape = this.isLandscape();
    // Keep existing users functional after fixing the old double-page orientation misclassification. The next
    // explicit calibration is persisted into the correct orientation slot.
    const stored = this.host.calibration(landscape) || this.host.calibration(!landscape);
    // No stored calibration must not disable eye-turning: calibration stays optional.
    return stored || DEFAULT_CALIBRATION_RAW;
  }

  private configure(): void {
    this.configuredLandscape = this.isLandscape();
    this.controller.configure(
      this.calibrationRaw(),
      this.host.nextDwellMs(),
      (status: string): void => {
        if (this.state.status !== status) this.state.status = status;
      },
      (sample: EyeTurnSample): void => this.consumeCalibrationSample(sample),
      (direction: number): void => {
        if (direction <= 0) {
          this.state.status = '请回看屏幕中央';
          return;
        }
        if (!this.host.canTurn()) return;
        this.host.turnNext();
      },
      (): boolean => {
        const allowed = this.host.canTurn();
        if (!allowed) console.info('[EyeTurn] turn blocked: ' + this.host.blockReason());
        return allowed;
      }
    );
  }

  onSurfaceLoaded(surfaceId: string): void {
    this.surfaceId = surfaceId;
    console.info(`[EyeTurn] camera surface loaded id=${surfaceId ? 'set' : 'EMPTY'}`);
    this.startIfReady();
  }

  onSurfaceDestroyed(): void {
    this.surfaceId = '';
    this.release('release surface');
  }

  startIfReady(): void {
    if (!this.host.enabled() || !this.host.pageVisible() || !this.surfaceId) {
      console.info(`[EyeTurn] start skipped enabled=${this.host.enabled()} ` +
        `visible=${this.host.pageVisible()} surface=${this.surfaceId ? 'set' : 'EMPTY'}`);
      return;
    }
    this.configure();
    // AR Engine takes exclusive control of the camera, so the camera pipeline must not start in parallel: it would
    // lose the camera, leaving the preview and calibration without frames.
    this.startArHostIfAvailable();
  }

  /** Stops the signal source and frees the camera; the page calls this whenever it leaves the foreground. */
  release(reason: string): void {
    this.stopArHost();
    this.controller.stop().catch((error: Error): void => {
      console.warn(`[EyeTurn] ${reason} failed:`, error.message);
    });
  }

  refreshForViewport(): void {
    if (!this.host.enabled()) return;
    if (this.isLandscape() === this.configuredLandscape) return;
    this.configure();
  }

  /** Prefers AR Engine for gaze signals and falls back to the camera pipeline when the kit is unavailable. */
  private startArHostIfAvailable(): void {
    if (!AR_ENABLED) {
      this.startCamera();
      return;
    }
    // Page turns re-enter this path; keep a single AR session alive instead of rebuilding it on every call.
    if (this.arHost || this.arHostLoading) return;
    this.arHostLoading = true;
    import('./ArEngineEyeTracker').then((ar): void => {
      if (!this.host.enabled() || !this.host.pageVisible()) {
        this.arHostLoading = false;
        return;
      }
      if (!ar.ArEngineEyeTracker.isAvailable()) {
        this.arHostLoading = false;
        this.startCamera();
        return;
      }
      ar.createArEngineEyeTurnHost((signal: ArEyeSignal): void => {
        if (signal.blink > 0.65) return;
        this.controller.submitExternalScore(signal.lookDown - signal.lookUp, signal.confidence);
      }, (active: boolean): void => {
        this.state.arFaceActive = active;
        // Switching the signal source also switches the calibration strategy.
        this.configure();
        if (active) {
          if (!this.state.showCalibration) {
            // AR now owns the camera, so release the camera pipeline.
            this.controller.stop().catch((): void => {
            });
          }
        } else {
          // AR failed to start; fall back to the camera unless it already runs.
          this.startCamera();
        }
      }).then((host: ArEyeTurnHost | null): void => {
        this.arHostLoading = false;
        if (!host) {
          this.startCamera();
          return;
        }
        if (!this.host.enabled() || !this.host.pageVisible()) {
          host.stop();
          return;
        }
        this.stopArHost();
        this.arHost = host;
        this.state.arHostMounted = true;
      }).catch((error: Error): void => {
        this.arHostLoading = false;
        console.warn('[EyeTurn] AR host unavailable:', error.message);
        this.startCamera();
      });
    }).catch((error: Error): void => {
      // AR Engine is not present on this device; the camera path keeps working.
      this.arHostLoading = false;
      console.warn('[EyeTurn] AR kit not available:', error.message);
      this.startCamera();
    });
  }

  private startCamera(): void {
    if (!this.host.enabled() || !this.host.pageVisible() || !this.surfaceId) return;
    if (this.controller.isRunning()) return;
    this.controller.start(this.host.abilityContext(), this.surfaceId).catch((error: Error): void => {
      this.state.status = `眼动识别启动失败：${error.message}`;
    });
  }

  /** True when either AR Engine or the camera pipeline is producing gaze samples. */
  private signalReady(): boolean {
    return this.state.arFaceActive || this.controller.isRunning();
  }

  private stopArHost(): void {
    const host = this.arHost;
    this.arHost = null;
    this.state.arHostMounted = false;
    this.state.arFaceActive = false;
    if (host) host.stop();
  }

  openCalibration(): void {
    this.clearCalibrationTimer();
    this.calibrationLandscape = this.isLandscape();
    this.state.calibrationStep = 0;
    this.state.calibrationCapturing = false;
    this.state.calibrationProgress = 0;
    this.state.calibrationTargetY = 0;
    this.calibrationPoints = [];
    this.calibrationStartupAt = 0;
    this.controller.setCalibrationMode(true);
    this.host.closePanels();
    this.state.showCalibration = true;
  }

  beginCalibrationCapture(): void {
    this.clearCalibrationTimer();
    this.calibrationPoints = [];
    this.state.calibrationProgress = 0;
    this.state.calibrationStep = 0;
    this.state.calibrationTargetY = 0;
    this.calibrationPhaseStartedAt = 0;
    this.calibrationStartupAt = Date.now();
    this.state.calibrationCapturing = false;
    this.state.calibrationSessionActive = true;
    // Calibration must not turn pages: keep the controller in calibration mode for the whole session (zones,
    // prompts and turns are all suppressed while it is set).
    this.controller.setCalibrationMode(true);
    this.state.status = '请看向白色目标点，然后点击「开始采样」';
    if (!this.signalReady()) this.startIfReady();
  }

  /** Starts the 1.5s sampling window for the current fixation (the reader taps to advance). */
  startCalibrationPhaseSampling(): void {
    if (!this.state.showCalibration || this.state.calibrationStep >= CALIBRATION_PHASE_COUNT) return;
    this.calibrationStartupAt = Date.now();
    this.calibrationPhaseStartedAt = 0;
    this.state.calibrationProgress = 0;
    this.state.calibrationCapturing = true;
    this.state.status = '请保持视线不动';
    this.scheduleCalibrationTick(80);
  }

  cancelCalibration(): void {
    this.clearCalibrationTimer();
    this.state.calibrationCapturing = false;
    this.state.showCalibration = false;
    this.controller.setCalibrationMode(false);
  }

  private consumeCalibrationSample(sample: EyeTurnSample): void {
    if (!this.state.showCalibration || !this.state.calibrationCapturing) return;
    if (this.calibrationLandscape !== this.isLandscape()) {
      this.abortCalibrationAttempt('校准过程中屏幕方向发生变化，请重新开始');
      HdsFeedback.showToast('校准过程中屏幕方向发生变化，请重新开始');
      return;
    }
    const phaseStartedAt = this.calibrationPhaseStartedAt;
    if (phaseStartedAt <= 0) return;
    const capturedAt = sample.capturedAt > 0 ? sample.capturedAt : Date.now();
    const phaseElapsed = capturedAt - phaseStartedAt;
    // The reader aims before tapping, so the whole window is usable.
    if (phaseElapsed < 0 || phaseElapsed > CALIBRATION_HOLD_MS) return;
    if (!sample.eyeAvailable) return;
    const point = new ReaderEyeCalibrationPoint();
    point.score = sample.rawScore;
    point.pitch = sample.pitch;
    point.eyeRatio = sample.eyeRatio;
    point.eyeAvailable = true;
    point.targetY = this.state.calibrationTargetY;
    point.phase = this.state.calibrationStep;
    point.confidence = sample.confidence;
    this.calibrationPoints.push(point);
  }

  private scheduleCalibrationTick(delayMs: number = CALIBRATION_TICK_MS): void {
    if (!this.state.calibrationCapturing || !this.state.showCalibration) return;
    this.clearCalibrationTimer();
    this.calibrationTimerId = setTimeout((): void => {
      this.calibrationTimerId = -1;
      this.updateCalibrationSequence();
    }, delayMs);
  }

  private updateCalibrationSequence(): void {
    if (!this.state.calibrationCapturing || !this.state.showCalibration) return;
    if (this.calibrationLandscape !== this.isLandscape()) {
      this.abortCalibrationAttempt('屏幕方向已变化，请重新开始');
      return;
    }
    const now = Date.now();
    if (!this.signalReady()) {
      if (now - this.calibrationStartupAt > 8000) {
        this.abortCalibrationAttempt('眼动识别启动超时，请重试');
        return;
      }
      this.state.status = '正在启动眼动识别';
      this.scheduleCalibrationTick(120);
      return;
    }
    if (this.calibrationPhaseStartedAt <= 0) {
      this.calibrationPhaseStartedAt = now;
      this.scheduleCalibrationTick();
      return;
    }
    const phaseElapsed = now - this.calibrationPhaseStartedAt;
    if (phaseElapsed < CALIBRATION_HOLD_MS) {
      this.state.calibrationProgress = Math.max(0, Math.min(100, phaseElapsed * 100 / CALIBRATION_HOLD_MS));
      this.scheduleCalibrationTick();
      return;
    }
    // Sampling done: stop and wait for the reader to tap for the next fixation.
    this.state.calibrationCapturing = false;
    this.state.calibrationProgress = 100;
    this.calibrationPhaseStartedAt = 0;
    this.clearCalibrationTimer();
    const nextStep = this.state.calibrationStep + 1;
    if (nextStep >= CALIBRATION_PHASE_COUNT) {
      this.finishCalibrationFromFixation();
      return;
    }
    this.state.calibrationStep = nextStep;
    this.state.calibrationTargetY = nextStep === 1 ? 1 : -1;
    this.state.status = `请看向${this.state.targetLabel()}目标点，然后点击「开始采样」`;
  }

  /**
   * Builds the calibration from the three held fixations: centre, bottom zone, top zone. The sign of the deltas
   * comes straight from the measurements, so the gesture direction can no longer be guessed wrong.
   */
  private finishCalibrationFromFixation(): void {
    const centerRatios: number[] = [];
    const bottomRatios: number[] = [];
    const topRatios: number[] = [];
    const centerPitches: number[] = [];
    for (const point of this.calibrationPoints) {
      if (!point.eyeAvailable) continue;
      if (point.phase === 0) {
        centerRatios.push(point.eyeRatio);
        centerPitches.push(point.pitch);
      } else if (point.phase === 1) {
        bottomRatios.push(point.eyeRatio);
      } else if (point.phase === 2) {
        topRatios.push(point.eyeRatio);
      }
    }
    const minimum = CALIBRATION_MIN_PHASE_SAMPLES;
    if (centerRatios.length < minimum || bottomRatios.length < minimum || topRatios.length < minimum) {
      this.failCalibration(`有效样本不足（中央 ${centerRatios.length}／底部 ${bottomRatios.length}／顶部 ` +
        `${topRatios.length}），请正对屏幕重试`);
      return;
    }
    const topRatio = ReaderEyeTurnCoordinator.median(topRatios);
    const bottomRatio = ReaderEyeTurnCoordinator.median(bottomRatios);
    // On this hardware the reading position and the bottom line are nearly identical in iris terms, while the top
    // line is clearly distinct. So the TOP fixation becomes the zero crossing and the bottom/reading level the
    // positive end; the turn then fires when the gaze leaves that level upwards.
    const travel = bottomRatio - topRatio;
    const bottomSpread = ReaderEyeTurnCoordinator.spread(bottomRatios);
    const topSpread = ReaderEyeTurnCoordinator.spread(topRatios);
    console.info(`[EyeTurn] calibration top=${topRatio.toFixed(4)} bottom=${bottomRatio.toFixed(4)} ` +
      `travel=${travel.toFixed(4)} center=${ReaderEyeTurnCoordinator.median(centerRatios).toFixed(4)} ` +
      `spread=${ReaderEyeTurnCoordinator.spread(centerRatios).toFixed(4)}/${bottomSpread.toFixed(4)}/` +
      `${topSpread.toFixed(4)} samples=${centerRatios.length}/${bottomRatios.length}/${topRatios.length}`);
    if (Math.abs(travel) < CALIBRATION_MIN_DELTA) {
      this.failCalibration(`眼动差异不足（顶部 ${topRatio.toFixed(4)}／底部 ${bottomRatio.toFixed(4)}），` +
        '请分别注视正文顶部和底部并保持住后重试');
      return;
    }
    if (bottomSpread > Math.abs(travel) / 2.5 || topSpread > Math.abs(travel) / 2.5) {
      this.failCalibration('校准过程中视线不够稳定，请重新对准目标点并保持不动');
      return;
    }
    // The top side needs its own span; keep it a bounded fraction of the measured travel.
    const topDelta = (travel >= 0 ? -1 : 1) * Math.max(0.004, Math.abs(travel) * 0.15);
    const calibration = new EyeTurnCalibration();
    calibration.version = 3;
    calibration.top = -1;
    calibration.center = 0;
    calibration.bottom = 1;
    calibration.pitchCenter = ReaderEyeTurnCoordinator.median(centerPitches);
    calibration.pitchScale = 0;
    calibration.pitchTopDelta = 0;
    calibration.pitchBottomDelta = 0;
    calibration.eyeCenter = topRatio;
    calibration.eyeScale = (travel - topDelta) / 2;
    calibration.eyeTopDelta = topDelta;
    calibration.eyeBottomDelta = travel;
    calibration.eyeWeight = 1;
    calibration.pitchWeight = 0;
    // This mapping is anchored on the measured top fixation, so the runtime must not re-centre it (that used to
    // cancel the reading position out to zero).
    calibration.absolute = true;
    if (!calibration.isValid()) {
      this.failCalibration('眼动变化不足，请正对屏幕重新校准');
      return;
    }
    this.host.setCalibration(this.calibrationLandscape, calibration.encode());
    this.state.showCalibration = false;
    this.state.calibrationSessionActive = false;
    this.controller.setCalibrationMode(false);
    this.state.status = '眼动翻页已就绪';
    this.configure();
    this.host.saveSettings();
    HdsFeedback.showToast('眼动翻页校准完成');
  }

  private static median(values: number[]): number {
    if (values.length === 0) return 0;
    const sorted = [...values].sort((left: number, right: number): number => left - right);
    const middle = Math.floor(sorted.length / 2);
    return sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle];
  }

  /** Median absolute deviation: a robust spread used to reject an unsteady fixation. */
  private static spread(values: number[]): number {
    if (values.length === 0) return 0;
    const median = ReaderEyeTurnCoordinator.median(values);
    return ReaderEyeTurnCoordinator.median(values.map((value: number): number => Math.abs(value - median)));
  }

  private failCalibration(message: string): void {
    this.state.calibrationSessionActive = false;
    this.controller.setCalibrationMode(false);
    this.state.calibrationStep = 0;
    this.state.calibrationProgress = 0;
    this.state.calibrationTargetY = 0;
    this.state.status = message;
    HdsFeedback.showToast(message);
  }

  private abortCalibrationAttempt(message: string): void {
    this.state.calibrationSessionActive = false;
    this.clearCalibrationTimer();
    this.controller.setCalibrationMode(false);
    this.state.calibrationCapturing = false;
    this.state.calibrationStep = 0;
    this.state.calibrationProgress = 0;
    this.state.calibrationTargetY = 0;
    this.state.status = message;
  }

  private clearCalibrationTimer(): void {
    if (this.calibrationTimerId >= 0) {
      clearTimeout(this.calibrationTimerId);
      this.calibrationTimerId = -1;
    }
  }
}
