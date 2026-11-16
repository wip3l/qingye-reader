import { LengthMetrics } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { ThemePackageChapterHead } from '../../theme/share/ThemePackageFormat';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { ReaderRasterAssets } from '../../core/reader/ReaderRasterAssets';

/**
 * 主题预览（编辑器预览、主题详情的阅读页）里的章首装饰：标题饰图、序号行颜色、首字装饰。
 * 阅读页用自绘排版（ReaderV2ChapterHeadLayout、ReaderV2Paginator 的首字），这里用 ArkUI 组件按同一套比例画个样子：
 * - 饰图左侧时高 = 整组标题按每块一行估出的高度 × 倍数，宽最多占 30%；上方、下方时高 = 标题字号 × 0.9 × 倍数。
 * - 有序号行颜色时把标题画成分段的样子：序号一行用这个颜色、字号是标题名的 1/1.4（阅读页分段标题的默认比例）。
 * - 首字方框 = (行数 − 1) × 行距 + 首行文字高 − 0.1 字号，首段前几行让出方框宽 + 0.3 字号。
 */
export class ThemeChapterHeadSampleMetrics {
  private static readonly LINE_BOX: number = 1.25;
  private static readonly SECONDARY_SCALE: number = 1.4;
  static readonly NUMBER_GAP: number = 4;

  static showsNumber(head: ThemePackageChapterHead, numberText: string): boolean {
    return !!head.numberColor && !!numberText;
  }

  /** 阅读页的“标题字号”：分段时是序号那一段的字号，标题名再放大 1.4 倍。 */
  static baseSize(titleSize: number, number: boolean): number {
    return number ? titleSize / ThemeChapterHeadSampleMetrics.SECONDARY_SCALE : titleSize;
  }

  static numberSize(titleSize: number): number {
    return titleSize / ThemeChapterHeadSampleMetrics.SECONDARY_SCALE;
  }

  /** 整组标题按每块一行估出的高度。 */
  static textHeight(titleSize: number, number: boolean): number {
    const box = ThemeChapterHeadSampleMetrics.LINE_BOX;
    return titleSize * box + (number ? ThemeChapterHeadSampleMetrics.NUMBER_GAP +
      ThemeChapterHeadSampleMetrics.numberSize(titleSize) * box : 0);
  }

  /** 饰图宽高比；没有饰图或读不出尺寸时为 0。 */
  static aspect(head: ThemePackageChapterHead): number {
    if (!head.image) return 0;
    const aspect = ReaderRasterAssets.imageAspect(head.image);
    return aspect > 0 ? Math.max(0.05, Math.min(20, aspect)) : 0;
  }

  static scale(head: ThemePackageChapterHead): number {
    return Math.max(0.5, Math.min(2, head.scale > 0 ? head.scale : 1));
  }

  static side(head: ThemePackageChapterHead): boolean {
    return head.placement !== 'top' && head.placement !== 'bottom';
  }

  /** 标题区（含饰图）的高度上限；左侧饰图被 30% 宽度限住时实际会矮一些。 */
  static estimateHeight(head: ThemePackageChapterHead, titleSize: number, numberText: string): number {
    const number = ThemeChapterHeadSampleMetrics.showsNumber(head, numberText);
    const textHeight = ThemeChapterHeadSampleMetrics.textHeight(titleSize, number);
    if (ThemeChapterHeadSampleMetrics.aspect(head) <= 0) return textHeight;
    const scale = ThemeChapterHeadSampleMetrics.scale(head);
    if (ThemeChapterHeadSampleMetrics.side(head)) return Math.max(textHeight, textHeight * scale);
    const base = ThemeChapterHeadSampleMetrics.baseSize(titleSize, number);
    return textHeight + base * 0.9 * scale + base * 0.3;
  }

  /** 正文第一个字能不能做首字（和阅读页一样只认汉字）。 */
  static dropCapApplies(head: ThemePackageChapterHead, paragraph: string): boolean {
    return head.dropCapLines >= 2 && paragraph.length > 1 && /[㐀-鿿豈-﫿]/.test(paragraph[0]);
  }
}

/** 章节标题加饰图与序号行；标题本身由调用方画（content），这样各处原有的标题强调画法不变。 */
@Component
export struct ThemeChapterHeadTitle {
  @Prop head: ThemePackageChapterHead = new ThemePackageChapterHead();
  /** 序号一行的文字（如“第十二章”）；主题设了序号行颜色时才画。 */
  @Prop numberText: string = '';
  /** 标题名的字号。 */
  @Prop titleSize: number = 18;
  @Prop fontFamily: string = '';
  @Prop titleWeight: number = 500;
  @BuilderParam content: () => void = this.emptyContent;
  @State boxWidth: number = 0;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      if (this.hasArtwork() && this.head.placement === 'top') {
        this.artwork('top')
      }
      if (this.hasArtwork() && ThemeChapterHeadSampleMetrics.side(this.head)) {
        Row() {
          this.artwork('side')
          Column() {
            this.textGroup()
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        this.textGroup()
      }
      if (this.hasArtwork() && this.head.placement === 'bottom') {
        this.artwork('bottom')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
      this.boxWidth = Number(size.width ?? 0);
    })
  }

  @Builder
  textGroup() {
    if (this.showsNumber()) {
      Text(this.numberText)
        .fontFamily(this.fontFamily)
        .fontSize(ThemeChapterHeadSampleMetrics.numberSize(this.titleSize))
        .fontWeight(this.titleWeight)
        .fontColor(this.head.numberColor)
        .maxLines(1)
        .margin({ bottom: ThemeChapterHeadSampleMetrics.NUMBER_GAP })
    }
    this.content()
  }

  /** edge：饰图在标题的哪一边，空隙留在饰图和标题之间。 */
  @Builder
  artwork(edge: string) {
    Image(ThemeAssetRegistry.chapterArtwork(this.head.image))
      .width(this.artworkWidth())
      .height(this.artworkHeight())
      .margin({
        bottom: edge === 'top' ? this.artworkGap() : 0,
        right: edge === 'side' ? this.artworkGap() : 0,
        top: edge === 'bottom' ? this.artworkGap() : 0
      })
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }

  showsNumber(): boolean {
    return ThemeChapterHeadSampleMetrics.showsNumber(this.head, this.numberText);
  }

  hasArtwork(): boolean {
    return ThemeChapterHeadSampleMetrics.aspect(this.head) > 0;
  }

  base(): number {
    return ThemeChapterHeadSampleMetrics.baseSize(this.titleSize, this.showsNumber());
  }

  artworkGap(): number {
    return this.base() * (ThemeChapterHeadSampleMetrics.side(this.head) ? 0.35 : 0.3);
  }

  /** 先按高度定尺寸，超出可用宽度（左侧时 30%）再按宽度缩。 */
  artworkSize(): number[] {
    const aspect = ThemeChapterHeadSampleMetrics.aspect(this.head);
    const scale = ThemeChapterHeadSampleMetrics.scale(this.head);
    const side = ThemeChapterHeadSampleMetrics.side(this.head);
    let height = side ? ThemeChapterHeadSampleMetrics.textHeight(this.titleSize, this.showsNumber()) * scale :
      this.base() * 0.9 * scale;
    let width = height * aspect;
    const maxWidth = this.boxWidth > 0 ? this.boxWidth * (side ? 0.3 : 1) : width;
    if (width > maxWidth) {
      width = maxWidth;
      height = width / aspect;
    }
    return [width, height];
  }

  artworkWidth(): number {
    return this.artworkSize()[0];
  }

  artworkHeight(): number {
    return this.artworkSize()[1];
  }
}

let dropCapPlaceholder: image.PixelMap | null = null;

/** 首字占位用的透明 1×1 图：系统按占位图的高度决定段落前几行缩进（阅读页选字层同样的做法）。 */
function placeholderPixelMap(): image.PixelMap | null {
  if (!dropCapPlaceholder) {
    try {
      dropCapPlaceholder = image.createPixelMapSync(new ArrayBuffer(4), { size: { width: 1, height: 1 } });
    } catch (error) {
      console.warn('[ThemeChapterHeadSample] create placeholder failed:', error);
    }
  }
  return dropCapPlaceholder;
}

/**
 * 带首字装饰的第一段正文。text 不带段首缩进（阅读页做首字时也去掉缩进）。
 * 首字方框的上下边按首行文字实际占的范围定：先按字号估一次，排好后量第二个字（首行第一个字）的范围再校正。
 */
@Component
export struct ThemeDropCapParagraph {
  @Prop @Watch('refresh') text: string = '';
  @Prop @Watch('refresh') head: ThemePackageChapterHead = new ThemePackageChapterHead();
  @Prop @Watch('refresh') fontSize: number = 16;
  @Prop @Watch('refresh') lineHeight: number = 28;
  @Prop @Watch('refresh') fontFamily: string = '';
  @Prop @Watch('refresh') textColor: string = '#000000';
  @Prop @Watch('refresh') letterSpacing: number = 0;
  @Prop @Watch('refresh') textAlign: TextAlign = TextAlign.JUSTIFY;
  /** 0 表示不限。 */
  @Prop @Watch('refresh') maxLines: number = 0;
  @Prop @Watch('refresh') ellipsis: boolean = true;
  /** 首字用标题字体与字重。 */
  @Prop capFontFamily: string = '';
  @Prop capFontWeight: number = 500;
  // 首行文字（TIGHT 范围）相对段落顶边的上沿与高度；-1 表示还没量，用估计值。
  @State inkTop: number = -1;
  @State inkHeight: number = -1;
  private controller: TextController = new TextController();
  private appeared: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Text(undefined, { controller: this.controller })
        .width('100%')
        .onAppear(() => {
          this.appeared = true;
          this.apply();
        })
        .onSizeChange(() => this.measure())
      if (this.applies()) {
        Stack() {
          if (this.head.dropCapImage) {
            Image(ThemeAssetRegistry.chapterArtwork(this.head.dropCapImage))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .draggable(false)
          }
          Text(this.text[0])
            .fontFamily(this.capFontFamily || this.fontFamily)
            .fontWeight(this.capFontWeight)
            .fontSize(this.capFontSize())
            .fontColor(this.head.dropCapColor || this.textColor)
            .textAlign(TextAlign.Center)
            .maxLines(1)
        }
        .width(this.box())
        .height(this.box())
        .position({ x: 0, y: this.boxTop() })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
  }

  refresh(): void {
    this.inkTop = -1;
    this.inkHeight = -1;
    this.apply();
  }

  applies(): boolean {
    return ThemeChapterHeadSampleMetrics.dropCapApplies(this.head, this.text);
  }

  lines(): number {
    return this.head.dropCapLines === 3 ? 3 : 2;
  }

  measuredInkTop(): number {
    return this.inkTop >= 0 ? this.inkTop : (this.lineHeight - this.fontSize * 1.1) / 2;
  }

  measuredInkHeight(): number {
    return this.inkHeight > 0 ? this.inkHeight : this.fontSize * 1.1;
  }

  box(): number {
    return (this.lines() - 1) * this.lineHeight + this.measuredInkHeight() - this.fontSize * 0.1;
  }

  boxTop(): number {
    return this.measuredInkTop() + this.fontSize * 0.05;
  }

  reserve(): number {
    return this.box() + this.fontSize * 0.3;
  }

  capFontSize(): number {
    const box = this.box();
    if (this.head.dropCapImage) return box * Math.max(0.4, Math.min(0.9, this.head.dropCapRatio || 0.62));
    // 字框（基线上 0.92、下 0.12 个字号）正好填满方框。
    return box / 1.04;
  }

  apply(): void {
    if (!this.appeared) return;
    const applies = this.applies();
    const body = applies ? this.text.substring(1) : this.text;
    const styles: StyleOptions[] = [
      {
        start: 0,
        length: body.length,
        styledKey: StyledStringKey.FONT,
        styledValue: new TextStyle({
          fontSize: LengthMetrics.vp(this.fontSize),
          fontFamily: this.fontFamily,
          fontColor: this.textColor
        })
      },
      {
        start: 0,
        length: body.length,
        styledKey: StyledStringKey.LINE_HEIGHT,
        styledValue: new LineHeightStyle(LengthMetrics.vp(this.lineHeight))
      },
      {
        start: 0,
        length: body.length,
        styledKey: StyledStringKey.PARAGRAPH_STYLE,
        styledValue: new ParagraphStyle({
          textAlign: this.textAlign,
          leadingMargin: applies ? this.leadingMargin() : LengthMetrics.vp(0),
          maxLines: this.maxLines > 0 ? this.maxLines : undefined,
          overflow: this.ellipsis ? TextOverflow.Ellipsis : TextOverflow.Clip,
          wordBreak: WordBreak.BREAK_WORD
        })
      }
    ];
    if (this.letterSpacing !== 0) {
      styles.push({
        start: 0,
        length: body.length,
        styledKey: StyledStringKey.LETTER_SPACING,
        styledValue: new LetterSpacingStyle(LengthMetrics.vp(this.letterSpacing))
      });
    }
    this.controller.setStyledString(new StyledString(body, styles));
    // 段落尺寸没变时不会再回调 onSizeChange，排好后补量一次。
    if (applies) setTimeout(() => this.measure(), 32);
  }

  leadingMargin(): LengthMetrics | LeadingMarginPlaceholder {
    const pixelMap = placeholderPixelMap();
    if (!pixelMap) return LengthMetrics.vp(this.reserve());
    const span = (this.lines() - 1) * this.lineHeight + this.lineHeight * 0.5;
    return { pixelMap: pixelMap, size: [`${this.reserve()}vp`, `${span}vp`] };
  }

  /** 排好后量首行第一个字的 TIGHT 范围；方框宽度变了再排一次（首行位置不随缩进宽度变，量一次就够）。 */
  measure(): void {
    if (!this.applies() || this.inkHeight > 0) return;
    try {
      const rects = this.controller.getLayoutManager().getRectsForRange({ start: 0, end: 1 },
        text.RectWidthStyle.TIGHT, text.RectHeightStyle.TIGHT);
      if (rects.length === 0) return;
      const ui = this.getUIContext();
      const top = ui.px2vp(rects[0].rect.top);
      const height = ui.px2vp(rects[0].rect.bottom - rects[0].rect.top);
      if (height <= this.fontSize * 0.2) return;
      const before = this.reserve();
      this.inkTop = top;
      this.inkHeight = height;
      if (Math.abs(this.reserve() - before) > 0.5) this.apply();
    } catch (error) {
      console.warn('[ThemeChapterHeadSample] measure drop cap failed:', error);
    }
  }
}
