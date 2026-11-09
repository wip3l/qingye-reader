/** 双页中缝的书脊阴影宽度：画在两页交界上方，不占排版宽度。 */
export const READER_SPREAD_SPINE_WIDTH = 44;

/**
 * 双页中缝色标：像摊开的书，两页朝中间逐渐压暗，中缝最深；深色页面加大不透明度才看得出来。
 * 文件排版（EpubOriginalScript.spineStyle）用同一组色标。
 */
export function readerSpreadSpineColors(dark: boolean): Array<[ResourceColor, number]> {
  const k = dark ? 2.6 : 1;
  const shade = (alpha: number): string => `rgba(0,0,0,${Math.min(0.4, alpha * k).toFixed(3)})`;
  return [[shade(0), 0], [shade(0.02), 0.22], [shade(0.06), 0.42], [shade(0.11), 0.5],
    [shade(0.05), 0.57], [shade(0.015), 0.76], [shade(0), 1]];
}

/** 一段中缝阴影，宽度固定、高度由外部决定；只画不接触摸。 */
@Component
export struct ReaderSpreadSpine {
  @Prop dark: boolean = false;

  build() {
    Column()
      .width(READER_SPREAD_SPINE_WIDTH)
      .height('100%')
      .linearGradient({ angle: 90, colors: readerSpreadSpineColors(this.dark) })
      .hitTestBehavior(HitTestMode.None)
  }
}
