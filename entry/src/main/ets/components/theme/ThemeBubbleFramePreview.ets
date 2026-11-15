import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { BubbleFrameBreak, BubbleFrameRepeat, bubbleFrameSliceOrDefault, ThemePackageBubble } from '../../theme/share/ThemePackageFormat';
import { BubbleFramePreviewPainter, BubbleFramePreviewParams, BubbleFramePreviewPart } from './BubbleFramePreviewPainter';

class DecodedImage {
  map: PixelMap | undefined = undefined;
  aspect: number = 3;
}

/**
 * 包内气泡边框的小样：强调气泡卡片、主题预览里的强调示例。边框（和端饰）按正文的规则逐行画，
 * 上传或调整后立即反映出来。文字、字号、缩进由调用方给，默认是卡片里的那句。
 */
@Component
export struct ThemeBubbleFramePreview {
  @Prop @Watch('reload') uri: string = '';
  @Prop @Watch('reload') capUri: string = '';
  @Prop @Watch('redraw') settings: ThemePackageBubble = new ThemePackageBubble();
  @Prop @Watch('redraw') leadText: string = '他忽然停下脚步：';
  @Prop @Watch('redraw') emphasisText: string = '“灯还亮着，说明有人比我们先到了这里。”';
  @Prop @Watch('redraw') textColor: string = '#FFFFFF';
  @Prop @Watch('redraw') bubbleColor: string = '#86191E';
  @Prop @Watch('redraw') paperColor: string = '#FAF6EE';
  @Prop @Watch('redraw') normalTextColor: string = '#2B2A28';
  @Prop @Watch('redraw') fontSize: number = BubbleFramePreviewPainter.FONT;
  @Prop @Watch('redraw') lineHeight: number = BubbleFramePreviewPainter.LINE;
  @Prop @Watch('redraw') fontFamily: string = '';
  @Prop @Watch('redraw') indentChars: number = 2;
  @Prop @Watch('redraw') paddingX: number = BubbleFramePreviewPainter.PADDING;
  @Prop @Watch('redraw') paddingY: number = BubbleFramePreviewPainter.PADDING / 2;
  @Prop @Watch('redraw') maxLines: number = 0;
  @Prop cornerRadius: number = 12;
  /**
   * 整段样张（含段评数气泡等行内小图）；给了就不用 leadText / emphasisText。不是状态变量，内容变了调用方要换
   * 组件的键让它重建。
   */
  partsProvider: (() => BubbleFramePreviewPart[]) | null = null;
  @State private sampleHeight: number = BubbleFramePreviewPainter.LINE * 2 + BubbleFramePreviewPainter.PADDING;
  private pixelMap: PixelMap | undefined = undefined;
  private capMap: PixelMap | undefined = undefined;
  private aspect: number = 3;
  private loadToken: number = 0;
  private readonly canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.loadToken++;
    this.releaseMaps();
  }

  build() {
    Canvas(this.canvas)
      .width('100%')
      .height(this.sampleHeight)
      .backgroundColor(this.paperColor)
      .borderRadius(this.cornerRadius)
      .onReady(() => this.redraw())
      .onAreaChange(() => this.redraw())
  }

  releaseMaps(): void {
    const map = this.pixelMap;
    const cap = this.capMap;
    this.pixelMap = undefined;
    this.capMap = undefined;
    if (map) map.release().catch((): void => {});
    if (cap) cap.release().catch((): void => {});
  }

  async reload(): Promise<void> {
    const token = ++this.loadToken;
    this.releaseMaps();
    const frame = await ThemeBubbleFramePreview.decode(this.uri, 160);
    const cap = await ThemeBubbleFramePreview.decode(this.capUri, 96);
    if (token !== this.loadToken) {
      ThemeBubbleFramePreview.releaseDecoded(frame);
      ThemeBubbleFramePreview.releaseDecoded(cap);
      return;
    }
    if (frame) {
      this.pixelMap = frame.map;
      this.aspect = frame.aspect;
    }
    if (cap) this.capMap = cap.map;
    this.redraw();
  }

  static releaseDecoded(decoded: DecodedImage | null): void {
    const map = decoded ? decoded.map : undefined;
    if (map) map.release().catch((): void => {});
  }

  /** 按目标高度解码（SVG 要给尺寸才会按需要的大小栅格化）。 */
  static async decode(uri: string, height: number): Promise<DecodedImage | null> {
    if (!uri) return null;
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const aspect = Math.max(1, info.size.width) / Math.max(1, info.size.height);
      const map = await source.createPixelMap({
        desiredSize: { width: Math.max(1, Math.min(1600, Math.round(height * aspect))), height: height }
      });
      const result = new DecodedImage();
      result.map = map;
      result.aspect = aspect;
      return result;
    } catch (e) {
      console.warn('读取气泡小样图片失败:', e);
      return null;
    } finally {
      if (source) source.release().catch((): void => {});
      if (file) fs.closeSync(file);
    }
  }

  redraw(): void {
    const params = new BubbleFramePreviewParams();
    const slice = bubbleFrameSliceOrDefault(this.settings.frameSlice, this.aspect);
    params.map = this.pixelMap;
    params.aspect = this.aspect;
    params.sliceLeft = slice.left;
    params.sliceRight = slice.right;
    params.sliceTop = slice.top;
    params.sliceBottom = slice.bottom;
    params.round = this.settings.frameRepeat === BubbleFrameRepeat.ROUND;
    params.cut = this.settings.frameBreak === BubbleFrameBreak.CUT;
    params.tint = this.settings.frameTint === true;
    params.capMap = this.capMap;
    // 与正文 decorationSizePx 同一规则：字号的 0.72 倍，夹在 15–22。
    params.capSize = Math.max(15, Math.min(22, this.fontSize * 0.72));
    params.textColor = this.textColor;
    params.bubbleColor = this.bubbleColor;
    params.normalTextColor = this.normalTextColor;
    params.fontSize = this.fontSize;
    params.lineHeight = this.lineHeight;
    params.fontFamily = this.fontFamily;
    params.indentChars = this.indentChars;
    params.paddingX = this.paddingX;
    params.paddingY = this.paddingY;
    params.maxLines = this.maxLines;
    const provider = this.partsProvider;
    const parts: BubbleFramePreviewPart[] = provider ? provider() : [
      new BubbleFramePreviewPart(this.leadText, false),
      new BubbleFramePreviewPart(this.emphasisText, true)
    ];
    const height = BubbleFramePreviewPainter.draw(this.canvas, params, parts);
    if (height > 0 && Math.abs(height - this.sampleHeight) > 0.5) this.sampleHeight = height;
  }
}
