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
   * 卷页动画用的页面截图比例。截图交给 Canvas 每帧贴图，整页原尺寸截图的离屏渲染与回读会落在翻页起始帧，
   * 贴图填充也随像素数增长。仿真 0.42 在高密度屏上移动中仍清晰；3D 仿真每帧只画两次贴图，0.6 折中正文清晰与回读开销。
   * 平移、推页、淡入、叠页直接显示截图本身，保持原尺寸。
   */
  static snapshotScale(type: number): number {
    if (type === this.THREE_D) return 0.6;
    if (type === this.SIMULATION) return 0.42;
    return 1;
  }

  static normalize(value: number): number {
    const rounded = Math.round(value);
    return this.types().includes(rounded) ? rounded : this.SLIDE;
  }
}
