import { ResolvedBubbleFrame } from '../../theme/ThemePackRegistry';

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
  /** Theme packs may ship a separate dark-mode cap; the page node picks the cap for this mode. */
  decorationDark: boolean = false;
  decorationSizePx: number = 0;
  /** Chapter-title decorations are enclosed independently on every visual line. */
  repeatCaps: boolean = false;
  /**
   * Theme-pack bubble frame (file URI) drawn line by line instead of the rounded background; empty = none.
   * The remaining frame* fields mirror ThemePackageBubble, already resolved to concrete values.
   */
  frameAsset: string = '';
  /** Source image width / height. */
  frameAspect: number = 3;
  /** Fractions of the source width (left/right ends) and height (outside the text band). */
  frameSliceLeft: number = 0;
  frameSliceRight: number = 0;
  frameSliceTop: number = 0;
  frameSliceBottom: number = 0;
  frameRound: boolean = false;
  /** Line breaks cut the frame flat instead of giving every line both ends. */
  frameCut: boolean = false;
  /** Tint the frame with backgroundColor. */
  frameTint: boolean = false;

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

/**
 * Geometry shared by pagination and painting for theme bubble frames. The frame's text band is a fixed multiple of
 * the run's font size, so the space reserved before/after a run is known while the paragraph is still being built.
 */
export class ReaderV2BubbleFrame {
  /** Text band height relative to the emphasised run's font size. */
  static readonly BAND_EM: number = 1.36;

  static bandPx(fontSizePx: number): number {
    return Math.max(1, fontSizePx) * ReaderV2BubbleFrame.BAND_EM;
  }

  /** Scale from source pixels (height normalised to 1) to page pixels for this style's band. */
  static scale(style: ReaderV2SpanStyleRange): number {
    const inner = Math.max(0.02, 1 - style.frameSliceTop - style.frameSliceBottom);
    return ReaderV2BubbleFrame.bandPx(style.fontSizePx) / inner;
  }

  static leadPx(style: ReaderV2SpanStyleRange): number {
    if (!style.frameAsset) return 0;
    return style.frameSliceLeft * style.frameAspect * ReaderV2BubbleFrame.scale(style);
  }

  static trailPx(style: ReaderV2SpanStyleRange): number {
    if (!style.frameAsset) return 0;
    return style.frameSliceRight * style.frameAspect * ReaderV2BubbleFrame.scale(style);
  }

  /** Whether the run is painted by the page node (caps and/or frame) rather than as a native text background. */
  static decorates(style: ReaderV2SpanStyleRange): boolean {
    return style.decorationEnabled && (style.decorationSizePx > 0 || !!style.frameAsset);
  }

  /** Space owned by the character before the run: cap outside, frame end inside. */
  static leadingReservation(style: ReaderV2SpanStyleRange): number {
    return (style.decorationSizePx > 0 ? style.decorationSizePx : 0) + ReaderV2BubbleFrame.leadPx(style);
  }

  /**
   * Fills the decoration fields of an emphasis style: caps when the bubble style has a cap, the frame when the
   * theme pack has one. Either alone is enough for the page node to paint the run.
   */
  static decorate(style: ReaderV2SpanStyleRange, enabled: boolean, styleId: string, hasCap: boolean,
    capSizePx: number, frame: ResolvedBubbleFrame | null, dark: boolean = false): void {
    style.decorationEnabled = enabled && (hasCap || !!frame);
    style.decorationStyleId = style.decorationEnabled ? styleId : '';
    style.decorationDark = style.decorationEnabled && dark;
    style.decorationSizePx = style.decorationEnabled && hasCap ? capSizePx : 0;
    style.frameAsset = '';
    if (!style.decorationEnabled || !frame) return;
    style.frameAsset = frame.asset;
    style.frameAspect = frame.aspect > 0 ? frame.aspect : 3;
    style.frameSliceLeft = frame.slice.left;
    style.frameSliceRight = frame.slice.right;
    style.frameSliceTop = frame.slice.top;
    style.frameSliceBottom = frame.slice.bottom;
    style.frameRound = frame.round;
    style.frameCut = frame.cut;
    style.frameTint = frame.tint;
  }

  static copyFrame(target: ReaderV2SpanStyleRange, source: ReaderV2SpanStyleRange): void {
    target.frameAsset = source.frameAsset;
    target.frameAspect = source.frameAspect;
    target.frameSliceLeft = source.frameSliceLeft;
    target.frameSliceRight = source.frameSliceRight;
    target.frameSliceTop = source.frameSliceTop;
    target.frameSliceBottom = source.frameSliceBottom;
    target.frameRound = source.frameRound;
    target.frameCut = source.frameCut;
    target.frameTint = source.frameTint;
  }

  static trailingReservation(style: ReaderV2SpanStyleRange): number {
    return (style.decorationSizePx > 0 ? style.decorationSizePx : 0) + ReaderV2BubbleFrame.trailPx(style);
  }
}
