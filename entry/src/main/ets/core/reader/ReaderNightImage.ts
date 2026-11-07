/**
 * 夜间模式下书里插图的处理方式（“夜间图片”），应用排版与文件排版共用；漫画不受影响。
 * 值写入设置并参与同步，不能改名。
 */
export class ReaderNightImage {
  static readonly ORIGINAL: string = 'original';
  static readonly DIM: string = 'dim';
  static readonly INVERT: string = 'invert';
  static readonly AUTO: string = 'auto';

  static readonly VALUES: string[] = [
    ReaderNightImage.ORIGINAL, ReaderNightImage.DIM, ReaderNightImage.INVERT, ReaderNightImage.AUTO
  ];
  static readonly LABELS: string[] = ['保持原色', '调暗', '反色', '自动'];
  static readonly DESCRIPTION: string =
    '仅夜间模式生效。自动：白底少色的图（图表、文字图）反色，照片和插画只调暗';

  /** 调暗的亮度。 */
  static readonly DIM_BRIGHTNESS: number = 0.8;
  /** 反色后整体再压一点，白底变成接近阅读背景的深灰而不是纯黑，与文件排版的页面反色（invert .92）一致。 */
  static readonly INVERT_AMOUNT: number = 0.92;

  /** 自动判断用的阈值：采样像素的平均亮度不低于它、且彩色像素占比不超过 MAX_COLORFUL 才反色。 */
  static readonly AUTO_MIN_LUMA: number = 0.72;
  static readonly AUTO_MAX_COLORFUL: number = 0.12;
  /** 饱和度（max-min）超过它算彩色像素。 */
  static readonly AUTO_COLOR_SPREAD: number = 0.18;

  static normalize(value: string): string {
    const text = typeof value === 'string' ? value.trim().toLowerCase() : '';
    return ReaderNightImage.VALUES.indexOf(text) >= 0 ? text : ReaderNightImage.ORIGINAL;
  }

  /**
   * 按采样像素判断一张图该不该反色（自动模式）。pixels 为 RGBA 字节，透明处按白色书页计；
   * 大部分是浅色而且几乎没有彩色的图（白底线稿、表格、扫描文字）反色，其余只调暗。
   */
  static shouldInvert(pixels: Uint8Array | Uint8ClampedArray): boolean {
    let counted = 0;
    let lumaSum = 0;
    let colorful = 0;
    for (let i = 0; i + 3 < pixels.length; i += 4) {
      // 透明、半透明像素按白底合成（书页通常是白底），透明背景的线稿也算浅色。
      const alpha = pixels[i + 3] / 255;
      const r = (pixels[i] * alpha + 255 * (1 - alpha)) / 255;
      const g = (pixels[i + 1] * alpha + 255 * (1 - alpha)) / 255;
      const b = (pixels[i + 2] * alpha + 255 * (1 - alpha)) / 255;
      lumaSum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
      if (Math.max(r, g, b) - Math.min(r, g, b) > ReaderNightImage.AUTO_COLOR_SPREAD) colorful++;
      counted++;
    }
    if (counted === 0) return true;
    return lumaSum / counted >= ReaderNightImage.AUTO_MIN_LUMA && colorful / counted <= ReaderNightImage.AUTO_MAX_COLORFUL;
  }

  /** ArkUI ColorFilter / drawing.ColorFilter 用的 4x5 颜色矩阵（行优先，偏移量按 0–1 计）。 */
  static dimMatrix(): number[] {
    const k = ReaderNightImage.DIM_BRIGHTNESS;
    return [
      k, 0, 0, 0, 0,
      0, k, 0, 0, 0,
      0, 0, k, 0, 0,
      0, 0, 0, 1, 0
    ];
  }

  /**
   * 反色并保留色相（等同 CSS invert(a) hue-rotate(180deg) 的近似）：先按亮度反转，再把色度取反回来，
   * 白底变深灰、黑字变浅灰，红色仍偏红。a 为反色程度。
   */
  static invertMatrix(): number[] {
    const a = ReaderNightImage.INVERT_AMOUNT;
    // 亮度权重
    const wr = 0.2126;
    const wg = 0.7152;
    const wb = 0.0722;
    // out = c - 2*a*L + a   （c 为原色分量，L 为亮度）：亮度反转、色度保持。
    const row = (own: number): number[] => [
      (own === 0 ? 1 : 0) - 2 * a * wr,
      (own === 1 ? 1 : 0) - 2 * a * wg,
      (own === 2 ? 1 : 0) - 2 * a * wb,
      0,
      a
    ];
    return [...row(0), ...row(1), ...row(2), 0, 0, 0, 1, 0];
  }
}
