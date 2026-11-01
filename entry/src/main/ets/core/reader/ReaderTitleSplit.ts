/** Title layout preferences. Splitting never inserts or removes source characters. */
export class ReaderTitleSplitSettings {
  mode: string = 'off';
  position: string = '6';
  marker: string = '：';
  regex: string = '^第[零一二三四五六七八九十百千万0-9]+章[：: ]*';
  secondaryScale: number = 1.4;
  lineGap: number = 14;
  alignment: string = 'center';
  marginTop: number = 0;
  marginBottom: number = 0;
  singlePage: boolean = false;
}

export class ReaderTitleSplit {
  static normalizeAlignment(alignment: string): string {
    return alignment === 'left' || alignment === 'right' ? alignment : 'center';
  }

  static normalizeMargin(margin: number): number {
    return Number.isFinite(margin) ? Math.round(Math.max(0, Math.min(120, margin))) : 0;
  }

  static normalizeMode(mode: string): string {
    return mode === 'position' || mode === 'marker' || mode === 'regex' ? mode : 'off';
  }

  static normalizeScale(scale: number): number {
    return Number.isFinite(scale) ? Math.round(Math.max(0.5, Math.min(2, scale)) * 10) / 10 : 1.4;
  }

  static normalizeGap(gap: number): number {
    return Number.isFinite(gap) ? Math.round(Math.max(0, Math.min(40, gap))) : 14;
  }

  static validationError(settings: ReaderTitleSplitSettings): string {
    if (settings.mode === 'position') {
      return /^\d+$/.test(settings.position) && Number(settings.position) >= 1 &&
        Number(settings.position) <= 160 ? '' : '请输入 1～160 的整数';
    }
    if (settings.mode === 'marker') return settings.marker ? '' : '请输入用于分段的标记';
    if (settings.mode !== 'regex') return '';
    if (!settings.regex) return '请输入分段正则';
    if (settings.regex.length > 180 || /\([^)]*[+*][^)]*\)[+*{]/.test(settings.regex)) {
      return '请使用简短的表达式，避免嵌套重复';
    }
    try {
      new RegExp(settings.regex, 'u');
      return '';
    } catch (_) {
      return '正则格式有误，请检查后重试';
    }
  }

  /** UTF-16 offset after the first matching delimiter, or -1 for an unchanged title. */
  static offset(title: string, settings: ReaderTitleSplitSettings): number {
    if (!title || settings.mode === 'off' || ReaderTitleSplit.validationError(settings)) return -1;
    let cut = -1;
    if (settings.mode === 'position') {
      cut = Array.from(title).slice(0, Number(settings.position)).join('').length;
    } else if (settings.mode === 'marker') {
      const index = title.indexOf(settings.marker);
      if (index >= 0) cut = index + settings.marker.length;
    } else if (settings.mode === 'regex') {
      try {
        const match = new RegExp(settings.regex, 'u').exec(title);
        if (match && match[0].length > 0) cut = match.index + match[0].length;
      } catch (_) {
        return -1;
      }
    }
    if (cut <= 0 || cut >= title.length || !title.substring(0, cut).trim() ||
      !title.substring(cut).trim()) return -1;
    const before = title.charCodeAt(cut - 1);
    const after = title.charCodeAt(cut);
    return before >= 0xD800 && before <= 0xDBFF && after >= 0xDC00 && after <= 0xDFFF ? -1 : cut;
  }

  static parts(title: string, settings: ReaderTitleSplitSettings): string[] {
    const cut = ReaderTitleSplit.offset(title, settings);
    return cut > 0 ? [title.substring(0, cut), title.substring(cut)] : [title];
  }
}
