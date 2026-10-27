/** `#RRGGBB` 颜色文本的规范化，供设置读写与取色控件共用。 */
export class HexColor {
  /** ArkUI uses #AARRGGBB. Keep the existing RGB-only API for unrelated settings. */
  static parseAlpha(value: string): string {
    const color = (value || '').trim().replace(/^#/, '');
    return /^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(color) ? `#${color.toUpperCase()}` : '';
  }

  static normalizeAlpha(value: string, fallback: string): string {
    return HexColor.parseAlpha(value) || HexColor.parseAlpha(fallback) || '#007DFF';
  }

  static rgb(value: string): string {
    const color = HexColor.normalizeAlpha(value, '#007DFF');
    return color.length === 9 ? `#${color.substring(3)}` : color;
  }

  static alpha(value: string): number {
    const color = HexColor.parseAlpha(value);
    return color.length === 9 ? parseInt(color.substring(1, 3), 16) : 255;
  }

  static withOpacity(value: string, opacity: number): string {
    const alpha = Math.round(Math.max(0, Math.min(1, opacity)) * 255).toString(16).padStart(2, '0').toUpperCase();
    return `#${alpha}${HexColor.rgb(value).substring(1)}`;
  }

  private static readonly WITH_HASH: RegExp = /^#[0-9a-fA-F]{6}$/;
  private static readonly WITHOUT_HASH: RegExp = /^[0-9a-fA-F]{6}$/;

  /** 合法的六位十六进制颜色（可不带 #）返回大写的 `#RRGGBB`，否则返回空串。 */
  static parse(value: string): string {
    const text = (value || '').trim();
    if (HexColor.WITH_HASH.test(text)) return text.toUpperCase();
    if (HexColor.WITHOUT_HASH.test(text)) return `#${text.toUpperCase()}`;
    return '';
  }

  /**
   * value 不合法时退回 fallback。给了 lastResort 时 fallback 也会被校验，两者都不合法就用 lastResort；
   * 不给 lastResort 时 fallback 原样返回（调用方自己保证它可用）。
   */
  static normalize(value: string, fallback: string, lastResort: string = ''): string {
    const parsed = HexColor.parse(value);
    if (parsed) return parsed;
    if (!lastResort) return fallback;
    return HexColor.parse(fallback) || lastResort;
  }
}
