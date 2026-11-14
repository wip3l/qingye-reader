// 阅读页把这份状态当 @State 在构造时就建好；它单独成模块，眼动翻页的相机与视觉识别（协调器）才能 lazy 导入，
// 没开眼动的阅读页不加载它们。
/** What the reader page and the calibration panel render; every field is observed. */
@Observed
export class ReaderEyeTurnViewState {
  status: string = '未启用';
  showCalibration: boolean = false;
  calibrationStep: number = 1;
  calibrationCapturing: boolean = false;
  calibrationProgress: number = 0;
  calibrationTargetY: number = 0;
  calibrationSessionActive: boolean = false;
  overlayWidth: number = 0;
  overlayHeight: number = 0;
  arHostMounted: boolean = false;
  arFaceActive: boolean = false;
  /** 注视底部的停留进度 0–1，驱动页脚上方那条主题色细线。 */
  cueProgress: number = 0;
  /** 停留够久、正在等待抬眼确认；页脚换成“抬眼翻页”。 */
  cueArmed: boolean = false;
  /** 提示是否显示：旧版有进度或 armed 时显示；新版识别到人脸后常驻显示淡色提示。 */
  cueVisible: boolean = false;
  /** 新版识别模型：校准三步改为正文中央/正文顶部/屏幕上沿以外，页脚提示改为“上看翻页”。 */
  modelMode: boolean = false;

  static readonly PHASE_COUNT: number = 3;
  static readonly PREVIEW_TOP_VP: number = 18;

  setCue(progress: number, armed: boolean, visible: boolean): void {
    if (this.cueProgress !== progress) this.cueProgress = progress;
    if (this.cueArmed !== armed) this.cueArmed = armed;
    if (this.cueVisible !== visible) this.cueVisible = visible;
  }

  targetLabel(): string {
    if (this.modelMode) {
      if (this.calibrationStep === 0) return '正文中央';
      if (this.calibrationStep === 1) return '正文顶部';
      return '屏幕上沿以外';
    }
    if (this.calibrationStep === 0) return '中央';
    if (this.calibrationStep === 1) return '底部';
    return '顶部';
  }

  /** The model's last step has no on-screen target: the reader looks past the top edge of the screen. */
  aboveScreenStep(): boolean {
    return this.modelMode && this.calibrationStep === 2;
  }

  instruction(): string {
    if (this.aboveScreenStep()) return '第 3/3 步：视线越过屏幕上沿，看向手机上方';
    return `第 ${this.calibrationStep + 1}/3 步：注视${this.targetLabel()}目标点`;
  }

  /** 页脚提示文字：旧版是看底部后抬眼，新版是看向屏幕上方。 */
  cueLabel(): string {
    return this.modelMode ? '上看翻页' : '抬眼翻页';
  }

  previewHint(): string {
    if (!this.calibrationCapturing) return '请让完整面部位于虚线框内';
    if (this.status.indexOf('未检测到') >= 0) return '未检测到面部，请调整距离和角度';
    if (this.status.indexOf('不稳定') >= 0) return '请保证正面光线充足';
    return '面部保持在框内，仅在本机处理';
  }

  // The camera preview keeps this size in normal reading too (see the surface comment in the reader page), so the
  // geometry falls back to the reader viewport until the calibration overlay has been measured.
  previewWidthVp(viewportWidth: number, viewportHeight: number): number {
    const overlayWidth = this.overlayWidth > 0 ? this.overlayWidth : Math.max(1, viewportWidth);
    const overlayHeight = this.overlayHeight > 0 ? this.overlayHeight : Math.max(1, viewportHeight);
    return Math.max(150, Math.min(300, overlayWidth - 48, overlayHeight * 0.40 / 0.75));
  }

  previewHeightVp(viewportWidth: number, viewportHeight: number): number {
    return this.previewWidthVp(viewportWidth, viewportHeight) * 0.75;
  }

  previewLeftVp(viewportWidth: number, viewportHeight: number): number {
    const overlayWidth = this.overlayWidth > 0 ? this.overlayWidth : Math.max(1, viewportWidth);
    return Math.max(0, (overlayWidth - this.previewWidthVp(viewportWidth, viewportHeight)) / 2);
  }

  targetTopVp(viewportHeight: number, statusBarHeight: number, navBarHeight: number): number {
    const overlayHeight = this.overlayHeight > 0 ? this.overlayHeight : Math.max(1, viewportHeight);
    // Keep both targets clear of the system bars so they stay visible and reachable.
    const top = 4 + Math.max(0, statusBarHeight);
    const bottom = Math.max(top, overlayHeight - 28 - Math.max(0, navBarHeight));
    // -2 (above the screen edge) has no dot; clamping keeps the geometry valid if it is ever asked for.
    const progress = Math.max(0, Math.min(1, (this.calibrationTargetY + 1) / 2));
    return top + (bottom - top) * progress;
  }
}
