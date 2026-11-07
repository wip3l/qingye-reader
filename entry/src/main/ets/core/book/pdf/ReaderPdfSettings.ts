/** Global PDF defaults; physical book variables override only explicitly customized options. */
export class ReaderPdfSettings {
  static readonly CONTINUOUS: string = 'pdfContinuous';
  static readonly DOUBLE_PAGE: string = 'pdfDoublePage';
  static readonly FIT_PAGE: string = 'pdfFitPage';
  static readonly SUPER_RESOLUTION: string = 'pdfSuperResolution';
  /** 夜间页面：original 原样、dim 调暗、invert 反色；只在应用夜间模式时生效。全局设置，不按书覆盖。 */
  static readonly NIGHT_ORIGINAL: string = 'original';
  static readonly NIGHT_DIM: string = 'dim';
  static readonly NIGHT_INVERT: string = 'invert';
  static readonly NIGHT_MODES: string[] = ['original', 'dim', 'invert'];
  static readonly NIGHT_LABELS: string[] = ['原样', '调暗', '反色'];
  continuous: boolean = true;
  doublePage: boolean = false;
  fitPage: boolean = false;
  superResolution: boolean = false;
  nightMode: string = ReaderPdfSettings.NIGHT_ORIGINAL;
  /** 阅读时右下角的页码角标（目录标题、页码、时间、电量），全局设置。 */
  pageBadge: boolean = true;

  static normalizeNightMode(value: string): string {
    return ReaderPdfSettings.NIGHT_MODES.indexOf(value) >= 0 ? value : ReaderPdfSettings.NIGHT_ORIGINAL;
  }

  copy(): ReaderPdfSettings {
    const next = new ReaderPdfSettings();
    next.continuous = this.continuous; next.doublePage = this.doublePage;
    next.fitPage = this.fitPage; next.superResolution = this.superResolution;
    next.nightMode = this.nightMode; next.pageBadge = this.pageBadge;
    return next;
  }

  toJson(): string {
    return JSON.stringify({ 'continuous': this.continuous, 'doublePage': this.doublePage,
      'fitPage': this.fitPage, 'superResolution': this.superResolution, 'nightMode': this.nightMode,
      'pageBadge': this.pageBadge });
  }

  static parse(raw: string): ReaderPdfSettings {
    const settings = new ReaderPdfSettings();
    try {
      const data = JSON.parse(raw) as Record<string, boolean | string>;
      if (!data || typeof data !== 'object' || Array.isArray(data)) return settings;
      if (typeof data['continuous'] === 'boolean') settings.continuous = data['continuous'];
      if (typeof data['doublePage'] === 'boolean') settings.doublePage = data['doublePage'];
      if (typeof data['fitPage'] === 'boolean') settings.fitPage = data['fitPage'];
      if (typeof data['superResolution'] === 'boolean') settings.superResolution = data['superResolution'];
      if (typeof data['nightMode'] === 'string') settings.nightMode = ReaderPdfSettings.normalizeNightMode(data['nightMode']);
      if (typeof data['pageBadge'] === 'boolean') settings.pageBadge = data['pageBadge'];
    } catch (_) {}
    return settings;
  }

  withOverrides(variables: Record<string, string>): ReaderPdfSettings {
    const next = this.copy();
    if (variables[ReaderPdfSettings.CONTINUOUS] === '0' || variables[ReaderPdfSettings.CONTINUOUS] === '1') {
      next.continuous = variables[ReaderPdfSettings.CONTINUOUS] === '1';
    }
    if (variables[ReaderPdfSettings.DOUBLE_PAGE] === '0' || variables[ReaderPdfSettings.DOUBLE_PAGE] === '1') {
      next.doublePage = variables[ReaderPdfSettings.DOUBLE_PAGE] === '1';
    }
    if (variables[ReaderPdfSettings.FIT_PAGE] === '0' || variables[ReaderPdfSettings.FIT_PAGE] === '1') {
      next.fitPage = variables[ReaderPdfSettings.FIT_PAGE] === '1';
    }
    if (variables[ReaderPdfSettings.SUPER_RESOLUTION] === '0' || variables[ReaderPdfSettings.SUPER_RESOLUTION] === '1') {
      next.superResolution = variables[ReaderPdfSettings.SUPER_RESOLUTION] === '1';
    }
    return next;
  }

  bookVariables(customized: string[]): Record<string, string> {
    const all: Record<string, string> = {
      'pdfContinuous': this.continuous ? '1' : '0', 'pdfDoublePage': this.doublePage ? '1' : '0',
      'pdfFitPage': this.fitPage ? '1' : '0', 'pdfSuperResolution': this.superResolution ? '1' : '0'
    };
    const result: Record<string, string> = {};
    for (const key of customized) { if (all[key] !== undefined) result[key] = all[key]; }
    return result;
  }
}
