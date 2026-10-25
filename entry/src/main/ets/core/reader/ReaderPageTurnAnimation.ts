/** 小说与漫画共用的横向翻页动画目录；数值兼容已有阅读设置。 */
export class ReaderPageTurnAnimation {
  static readonly NONE: number = 0;
  static readonly SLIDE: number = 1;
  static readonly FADE: number = 3;
  static readonly STACK: number = 4;
  static readonly SIMULATION: number = 6;
  static readonly THREE_D: number = 7;

  static types(horizontal: boolean = true): number[] {
    const result = [this.NONE, this.SLIDE, this.FADE, this.STACK];
    if (horizontal) result.push(this.SIMULATION, this.THREE_D);
    return result;
  }

  static labels(horizontal: boolean = true): string[] {
    const result = ['无动画', '平移', '淡入', '叠页'];
    if (horizontal) result.push('仿真', '3D仿真');
    return result;
  }

  static normalize(value: number): number {
    const rounded = Math.round(value);
    return this.types().includes(rounded) ? rounded : this.SLIDE;
  }
}
