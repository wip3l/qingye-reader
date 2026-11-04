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

  static readonly PHASE_COUNT: number = 3;
  static readonly PREVIEW_TOP_VP: number = 18;

  promptVisible(): boolean {
    return (this.status || '').indexOf('向上看，翻下一页') >= 0;
  }

  targetLabel(): string {
    if (this.calibrationStep === 0) return '中央';
    if (this.calibrationStep === 1) return '底部';
    return '顶部';
  }

  instruction(): string {
    return `第 ${this.calibrationStep + 1}/3 步：注视${this.targetLabel()}目标点`;
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
    const progress = Math.max(0, Math.min(1, (this.calibrationTargetY + 1) / 2));
    return top + (bottom - top) * progress;
  }
}
