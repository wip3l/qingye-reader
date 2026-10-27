/** Shared numeric weights for typography controls, persistence and layout. */
export class ReaderFontWeight {
  static readonly DEFAULT: number = 400;
  static readonly MIN: number = 50;
  static readonly MAX: number = 900;
  static readonly STEP: number = 50;
  // Only positively identified single static faces opt into outline thickening.
  private static staticFamilies: Map<string, string> = new Map<string, string>();
  private static variableRanges: Map<string, number[]> = new Map<string, number[]>();

  static registerStatic(family: string, nativeFamily: string): void {
    ReaderFontWeight.unregister(family);
    ReaderFontWeight.staticFamilies.set(family, nativeFamily);
  }

  static registerVariable(family: string, min: number, max: number): void {
    ReaderFontWeight.unregister(family);
    ReaderFontWeight.variableRanges.set(family, [min, max]);
  }

  static unregister(family: string): void {
    ReaderFontWeight.staticFamilies.delete(family);
    ReaderFontWeight.variableRanges.delete(family);
  }

  static isStatic(family: string): boolean {
    return ReaderFontWeight.staticFamilies.has(family);
  }

  static matchesStaticFace(family: string, nativeFamily: string): boolean {
    return ReaderFontWeight.staticFamilies.get(family) === nativeFamily && nativeFamily.length > 0;
  }

  static layoutWeight(family: string, weight: number): number {
    if (ReaderFontWeight.isStatic(family)) return ReaderFontWeight.DEFAULT;
    const range = ReaderFontWeight.variableRanges.get(family);
    const normalized = ReaderFontWeight.normalize(weight);
    return range ? Math.max(range[0], Math.min(range[1], normalized)) : normalized;
  }

  static strokeWidth(family: string, weight: number, fontSize: number): number {
    if (!ReaderFontWeight.isStatic(family)) return 0;
    // Full stroke width: at 900, each edge grows by 1.5% em. Zero means no pen at all.
    return Math.max(0, fontSize) * 0.03 *
      Math.max(0, ReaderFontWeight.normalize(weight) - ReaderFontWeight.DEFAULT) / 500;
  }

  static readonly HELP: string = '可变字体调节字重；单个静态字体以 400 为原始，400 以上微调加粗，低于 400 保持原样。';

  static normalize(value: number): number {
    if (!Number.isFinite(value)) return ReaderFontWeight.DEFAULT;
    return Math.max(ReaderFontWeight.MIN, Math.min(ReaderFontWeight.MAX,
      Math.round(value)));
  }
}
