/** 小说与漫画共用的横向翻页动画目录；数值兼容已有阅读设置。 */
export class ReaderPageTurnAnimation {
  static readonly NONE: number = 0;
  static readonly SLIDE: number = 1;
  static readonly FADE: number = 3;
  static readonly STACK: number = 4;
  static readonly SIMULATION: number = 6;
  static readonly THREE_D: number = 7;
  /** 两页贴着一起平移，接缝处有阴影、被压住的一页逐渐变淡。 */
  static readonly PUSH: number = 8;

  static types(horizontal: boolean = true): number[] {
    const result = [this.NONE, this.SLIDE, this.PUSH, this.FADE, this.STACK];
    if (horizontal) result.push(this.SIMULATION, this.THREE_D);
    return result;
  }

  static labels(horizontal: boolean = true): string[] {
    const result = ['无动画', '平移', '推页', '淡入', '叠页'];
    if (horizontal) result.push('仿真', '3D仿真');
    return result;
  }

  /**
   * 卷页动画用的页面截图/纹理比例（正文自绘纹理、文件排版与 PDF 的截图共用）。
   * 仿真按网格三角形逐块贴图，像素数直接决定每帧填充量，0.42 在高密度屏上移动中仍清晰。
   * 3D 仿真每帧只贴两次图，用原尺寸让起翻和翻动中的正文与静止时一样清晰；文件排版、PDF 的截图
   * 当前页多半已预截或沿用上次翻页的目标页，原尺寸只让翻动中现截的目标页多花些渲染服务回读时间
   * （文件排版实测单次截图约 17→27ms，纸色占位多停一两帧，翻动中掉帧与 0.6 无可分辨差别）。
   * 平移、推页、淡入、叠页直接显示截图本身，保持原尺寸。
   */
  static snapshotScale(type: number): number {
    if (type === this.SIMULATION) return 0.42;
    return 1;
  }

  static curlTextureScale(type: number): number {
    return this.snapshotScale(type);
  }

  static normalize(value: number): number {
    const rounded = Math.round(value);
    return this.types().includes(rounded) ? rounded : this.SLIDE;
  }

  /**
   * 双页并排的最小宽度（vp）与最小宽高比：书本式折叠屏展开时内屏略高于宽，只比宽高永远不会算宽；
   * 平板竖放（约 0.6~0.7）和分屏的半边仍算窄。
   */
  static readonly WIDE_MIN_WIDTH_VP: number = 600;
  static readonly WIDE_MIN_ASPECT: number = 0.8;

  /**
   * 阅读区是否够宽：宽大于高，或接近方形且至少 600vp 宽（折叠屏展开）。双页并排与横屏翻页动画共用此规则，
   * 文件排版网页里的 EpubOriginalScript.SPREAD_MEDIA 是同一规则的媒体查询写法，改这里要一起改。
   */
  static wideViewport(width: number, height: number): boolean {
    if (width <= 0 || height <= 0) return false;
    return width > height || (width >= this.WIDE_MIN_WIDTH_VP && width / height >= this.WIDE_MIN_ASPECT);
  }

  /**
   * 横竖屏分开设置翻页动画时，阅读区够宽（见 wideViewport，含折叠屏展开）就用横屏那份，与是否开双页无关。
   * 普通阅读页、文件排版和 PDF 共用这一判断；翻页方式不分横竖屏。
   */
  static usesLandscape(split: boolean, width: number, height: number): boolean {
    return split && this.wideViewport(width, height);
  }
}
