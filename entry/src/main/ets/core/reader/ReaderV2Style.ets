export class ReaderV2SpanStyleRange {
  start: number = 0;
  end: number = 0;
  fontSizePx: number = 0;
  fontFamily: string = '';
  fontWeight: number = 0;
  colorEnabled: boolean = false;
  color: number = 0;
  backgroundEnabled: boolean = false;
  backgroundColor: number = 0;
  radiusTopLeftPx: number = 0;
  radiusTopRightPx: number = 0;
  radiusBottomRightPx: number = 0;
  radiusBottomLeftPx: number = 0;
  shadowEnabled: boolean = false;
  shadowColor: number = 0;
  shadowRadiusPx: number = 0;
  shadowOffsetXPx: number = 0;
  shadowOffsetYPx: number = 0;
  decorationEnabled: boolean = false;
  decorationStyleId: string = '';
  decorationSizePx: number = 0;
  /** Chapter-title decorations are enclosed independently on every visual line. */
  repeatCaps: boolean = false;

  constructor(start: number = 0, end: number = 0) {
    this.start = start;
    this.end = end;
  }
}

export class ReaderV2Color {
  static parse(value: string, fallback: number): number {
    let text = (value || '').trim().replace('#', '');
    if (text.length === 3) {
      text = `FF${text[0]}${text[0]}${text[1]}${text[1]}${text[2]}${text[2]}`;
    } else if (text.length === 6) {
      text = `FF${text}`;
    } else if (text.length !== 8) {
      return fallback;
    }
    const parsed = Number.parseInt(text, 16);
    return Number.isFinite(parsed) ? (parsed >>> 0) : fallback;
  }

  /** 按感知亮度判断颜色是否偏亮（深色主题的文字色）。 */
  static isLight(color: number): boolean {
    const value = color >>> 0;
    const red = (value >>> 16) & 0xFF;
    const green = (value >>> 8) & 0xFF;
    const blue = value & 0xFF;
    return red * 0.299 + green * 0.587 + blue * 0.114 > 150;
  }
}
