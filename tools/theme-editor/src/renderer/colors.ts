// 颜色工具：格式校验、#AARRGGBB 转 CSS、对比度、浅色配色推一份深色初稿。

const HEX = /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;

export function isColor(value: string, allowAlpha: boolean): boolean {
  return HEX.test(value) && (allowAlpha || value.length === 7);
}

/** 应用的 #AARRGGBB（透明度在前）→ CSS rgba。 */
export function cssColor(hex: string): string {
  if (!hex || !HEX.test(hex)) return 'transparent';
  if (hex.length === 9) {
    const alpha = parseInt(hex.substring(1, 3), 16) / 255;
    const n = parseInt(hex.substring(3), 16);
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${alpha.toFixed(3)})`;
  }
  return hex;
}

function rgb(hex: string): number[] {
  const n = parseInt(hex.slice(-6), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export function luminance(hex: string): number {
  if (!HEX.test(hex)) return 0.5;
  const ch = rgb(hex).map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
}

export function contrast(a: string, b: string): number {
  const x = luminance(a);
  const y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

export function alphaOf(hex: string): number {
  return hex && hex.length === 9 ? parseInt(hex.substring(1, 3), 16) : 255;
}

export function withAlpha(hex: string, alpha: number): string {
  const body = hex.slice(-6).toUpperCase();
  return alpha >= 255 ? `#${body}` : `#${Math.max(0, Math.round(alpha)).toString(16).padStart(2, '0').toUpperCase()}${body}`;
}

function toHsl(hex: string): number[] {
  const [r, g, b] = rgb(hex).map((v) => v / 255);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let hue = 0;
  if (max === r) hue = (g - b) / d + (g < b ? 6 : 0);
  else if (max === g) hue = (b - r) / d + 2;
  else hue = (r - g) / d + 4;
  return [hue / 6, s, l];
}

function fromHsl(hue: number, s: number, l: number): string {
  const f = (n: number): number => {
    const k = (n + hue * 12) % 12;
    const a = s * Math.min(l, 1 - l);
    return Math.round(255 * (l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))));
  };
  return `#${[f(0), f(8), f(4)].map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`;
}

/** 保留色相，按角色重定明度与饱和度；只给初稿，作者再调。 */
function darkRole(hex: string, lightness: number, saturationScale: number): string {
  if (!isColor(hex, true)) return '';
  const [hue, s] = toHsl(hex);
  const out = fromHsl(hue, Math.min(1, s * saturationScale), lightness);
  return hex.length === 9 ? withAlpha(out, alphaOf(hex)) : out;
}

const COLOR_ROLES: Record<string, [number, number]> = {
  pageColor: [0.07, 0.35], cardColor: [0.11, 0.35], inputColor: [0.15, 0.3], dividerColor: [0.21, 0.25],
  primaryTextColor: [0.92, 0.25], subTextColor: [0.66, 0.2], accentColor: [0.72, 0.85], buttonColor: [0.46, 0.8],
  dangerColor: [0.68, 0.8]
};
const READER_ROLES: Record<string, [number, number]> = {
  backgroundColor: [0.085, 0.3], textColor: [0.86, 0.15], subTextColor: [0.62, 0.15]
};
const EMPHASIS_ROLES: Record<string, [number, number]> = { color: [0.24, 0.45], textColor: [0.88, 0.5] };

/** 浅色变体 → 深色初稿。只换颜色；素材、背景方式与强调方式原样保留。 */
export function darkDraft(light: any): any {
  const result: any = { colors: {}, reader: {}, emphasis: {} };
  for (const [group, roles] of [['colors', COLOR_ROLES], ['reader', READER_ROLES], ['emphasis', EMPHASIS_ROLES]] as const) {
    for (const [key, [l, s]] of Object.entries(roles)) {
      const value = light && light[group] ? light[group][key] : '';
      if (value) result[group][key] = darkRole(value, l, s);
    }
  }
  if (light && light.reader && light.reader.contentTone) result.reader.contentTone = 'dark';
  return result;
}
