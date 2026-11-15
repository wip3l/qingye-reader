import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import {
  BUBBLE_FRAME_SLICE_MAX,
  BubbleFrameBreak,
  BubbleFrameRepeat,
  bubbleFrameSliceOrDefault,
  ThemePackageBubble,
  ThemePackageBubbleSlice
} from '../../theme/share/ThemePackageFormat';
import { BubbleFramePreviewPainter, BubbleFramePreviewParams, BubbleFramePreviewPart } from './BubbleFramePreviewPainter';

/** 一次调整：边框图片和已有的拉伸设置，以及预览用的强调颜色。 */
export class BubbleFrameStretchRequest {
  uri: string = '';
  settings: ThemePackageBubble = new ThemePackageBubble();
  textColor: string = '#FFFFFF';
  bubbleColor: string = '#86191E';
}

const STRETCH_SAMPLE: BubbleFramePreviewPart[] = [
  new BubbleFramePreviewPart('雨停了，他敲敲柜台：', false),
  new BubbleFramePreviewPart('“这本账簿是谁送来的？”', true),
  new BubbleFramePreviewPart('老人答：', false),
  new BubbleFramePreviewPart('“昨夜一个穿灰大衣的年轻人放下就走了，连名字都没留。”', true)
];
const GUIDE_COLOR: string = '#E0393E';

/**
 * 气泡边框的拉伸区域页：四条红线定左右两端和文字行上下沿，下面的正文小样按和阅读页一样的规则实时画出。
 * 外观沿用取景页（深色底，左上取消、右上使用）。
 */
@Component
export struct ThemeBubbleFrameStretcher {
  @Prop request: BubbleFrameStretchRequest = new BubbleFrameStretchRequest();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  onDone: (settings: ThemePackageBubble) => void = (_settings: ThemePackageBubble): void => {};
  onCancel: () => void = (): void => {};
  @State private pixelMap: PixelMap | undefined = undefined;
  @State private aspect: number = 3;
  @State private failed: boolean = false;
  @State private opaque: boolean = false;
  @State private sliceLeft: number = 0;
  @State private sliceRight: number = 0;
  @State private sliceTop: number = 0;
  @State private sliceBottom: number = 0;
  @State private round: boolean = false;
  @State private cut: boolean = false;
  @State private tint: boolean = false;
  @State private areaWidth: number = 0;
  @State private previewHeight: number = BubbleFramePreviewPainter.LINE * 3 + BubbleFramePreviewPainter.PADDING;
  private startValue: number = 0;
  private readonly canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);

  aboutToAppear(): void {
    const settings = this.request.settings;
    this.round = settings.frameRepeat === BubbleFrameRepeat.ROUND;
    this.cut = settings.frameBreak === BubbleFrameBreak.CUT;
    this.tint = settings.frameTint === true;
    this.decode();
  }

  aboutToDisappear(): void {
    const map = this.pixelMap;
    this.pixelMap = undefined;
    if (map) map.release().catch((): void => {});
  }

  build() {
    Column() {
      Row({ space: AppSpacing.MD }) {
        Button('取消', { type: ButtonType.Capsule })
          .height(36)
          .fontSize(AppFontSize.BODY)
          .fontColor('#FFFFFF')
          .backgroundColor('#2A2F35')
          .onClick(() => this.onCancel())
        Text('拉伸区域')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
        Button('使用', { type: ButtonType.Capsule })
          .height(36)
          .fontSize(AppFontSize.BODY)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeRuntime.accentColor(true))
          .enabled(!!this.pixelMap)
          .onClick(() => this.onDone(this.result()))
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: this.statusBarHeight })

      Scroll() {
        Column({ space: AppSpacing.MD }) {
          Stack() {
            if (this.pixelMap && this.areaWidth > 0) {
              this.guideStage()
            } else {
              Text(this.failed ? '这张图片打不开，换一张试试' : '正在读取图片…')
                .fontSize(AppFontSize.BODY)
                .fontColor('#C9CED4')
                .padding(AppSpacing.XXL)
            }
          }
          .width('100%')
          .padding({ top: 28, bottom: 28 })
          .backgroundColor('#1D2024')

          if (this.pixelMap) {
            Text(this.readout())
              .fontSize(AppFontSize.CAPTION)
              .fontColor('#9DA5AE')
              .textAlign(TextAlign.Center)
              .width('100%')
          }

          Column() {
            Canvas(this.canvas)
              .width('100%')
              .height(this.previewHeight)
              .backgroundColor('#FAF6EE')
              .borderRadius(12)
              .onReady(() => this.drawPreview())
          }
          .width('100%')
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })

          Column({ space: AppSpacing.SM }) {
            if (this.opaque) {
              Text('这是不透明的图，正文里会露出底色。建议换成透明底的 PNG 或 SVG。')
                .fontSize(AppFontSize.CAPTION)
                .fontColor('#F4C26B')
                .backgroundColor('#2E2614')
                .borderRadius(8)
                .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
                .width('100%')
            }
            this.optionRow('中段', '拉伸', '平铺花纹', !this.round, (first: boolean) => {
              this.round = !first;
              this.drawPreview();
            })
            this.optionRow('换行处', '每行两端', '断开平切', !this.cut, (first: boolean) => {
              this.cut = !first;
              this.drawPreview();
            })
            this.optionRow('颜色', '保留原色', '染成气泡色', !this.tint, (first: boolean) => {
              this.tint = !first;
              this.drawPreview();
            })
          }
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })

          Text('拖动红线：左右之间会被拉长，上下之间对齐文字行')
            .fontSize(AppFontSize.CAPTION)
            .fontColor('#8E969F')
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ bottom: AppSpacing.XXL + this.navBarHeight })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#111417')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_old: Area, area: Area) => {
      const width = Number(area.width);
      if (Math.abs(width - this.areaWidth) > 0.5) {
        this.areaWidth = width;
        this.drawPreview();
      }
    })
  }

  @Builder
  guideStage() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.pixelMap)
        .width(this.displayWidth())
        .height(this.displayHeight())
        .objectFit(ImageFit.Fill)
        .draggable(false)
      this.verticalGuide(true)
      this.verticalGuide(false)
      this.horizontalGuide(true)
      this.horizontalGuide(false)
    }
    .width(this.displayWidth())
    .height(this.displayHeight())
  }

  @Builder
  verticalGuide(left: boolean) {
    Stack({ alignContent: Alignment.Bottom }) {
      Column().width(2).height('100%').backgroundColor(GUIDE_COLOR)
      Column()
        .width(16)
        .height(16)
        .borderRadius(8)
        .backgroundColor(GUIDE_COLOR)
        .border({ width: 2, color: '#FFFFFF' })
        .margin({ bottom: -6 })
    }
    .width(28)
    .height(this.displayHeight() + 40)
    .position({ x: (left ? this.sliceLeft : 1 - this.sliceRight) * this.displayWidth() - 14, y: -20 })
    .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
      .onActionStart(() => {
        this.startValue = left ? this.sliceLeft : this.sliceRight;
      })
      .onActionUpdate((event: GestureEvent) => {
        const delta = event.offsetX / Math.max(1, this.displayWidth());
        if (left) {
          this.sliceLeft = this.clampEnd(this.startValue + delta, this.sliceRight);
        } else {
          this.sliceRight = this.clampEnd(this.startValue - delta, this.sliceLeft);
        }
        this.drawPreview();
      }))
  }

  @Builder
  horizontalGuide(top: boolean) {
    Stack({ alignContent: Alignment.End }) {
      Column().width('100%').height(2).backgroundColor(GUIDE_COLOR)
      Column()
        .width(16)
        .height(16)
        .borderRadius(8)
        .backgroundColor(GUIDE_COLOR)
        .border({ width: 2, color: '#FFFFFF' })
        .margin({ right: -6 })
    }
    .width(this.displayWidth() + 40)
    .height(28)
    .position({ x: -20, y: (top ? this.sliceTop : 1 - this.sliceBottom) * this.displayHeight() - 14 })
    .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 1 })
      .onActionStart(() => {
        this.startValue = top ? this.sliceTop : this.sliceBottom;
      })
      .onActionUpdate((event: GestureEvent) => {
        const delta = event.offsetY / Math.max(1, this.displayHeight());
        if (top) {
          this.sliceTop = this.clampEnd(this.startValue + delta, this.sliceBottom);
        } else {
          this.sliceBottom = this.clampEnd(this.startValue - delta, this.sliceTop);
        }
        this.drawPreview();
      }))
  }

  @Builder
  optionRow(label: string, first: string, second: string, firstSelected: boolean, onPick: (first: boolean) => void) {
    Row({ space: AppSpacing.SM }) {
      Text(label).fontSize(AppFontSize.CAPTION).fontColor('#C9CED4').width(52)
      Row() {
        this.optionChip(first, firstSelected, () => onPick(true))
        this.optionChip(second, !firstSelected, () => onPick(false))
      }
      .layoutWeight(1)
      .padding(2)
      .borderRadius(18)
      .backgroundColor('#22262B')
    }
    .width('100%')
  }

  @Builder
  optionChip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(selected ? '#FFFFFF' : '#C9CED4')
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(15)
      .backgroundColor(selected ? '#3A4048' : Color.Transparent)
      .onClick(onTap)
  }

  // ---- 尺寸与数值 ----

  displayWidth(): number {
    const maxWidth = Math.max(60, this.areaWidth - 68);
    const maxHeight = 160;
    return Math.min(maxWidth, maxHeight * this.aspect);
  }

  displayHeight(): number {
    return this.displayWidth() / Math.max(0.05, this.aspect);
  }

  /** 单项不超过 BUBBLE_FRAME_SLICE_MAX，和对面那项合起来至少留出 2% 的中间。 */
  clampEnd(value: number, other: number): number {
    return Math.max(0, Math.min(BUBBLE_FRAME_SLICE_MAX, 0.98 - other, value));
  }

  readout(): string {
    const pct = (value: number): string => `${Math.round(value * 100)}%`;
    return `左端 ${pct(this.sliceLeft)} · 中段 ${pct(1 - this.sliceLeft - this.sliceRight)} · ` +
      `右端 ${pct(this.sliceRight)} · 文字行占图高 ${pct(1 - this.sliceTop - this.sliceBottom)}`;
  }

  result(): ThemePackageBubble {
    const settings = new ThemePackageBubble();
    const slice = new ThemePackageBubbleSlice();
    slice.left = this.sliceLeft;
    slice.right = this.sliceRight;
    slice.top = this.sliceTop;
    slice.bottom = this.sliceBottom;
    settings.frameSlice = slice;
    settings.frameRepeat = this.round ? BubbleFrameRepeat.ROUND : '';
    settings.frameBreak = this.cut ? BubbleFrameBreak.CUT : '';
    settings.frameTint = this.tint;
    return settings;
  }

  // ---- 读图 ----

  async decode(): Promise<void> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(this.request.uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const width = Math.max(1, info.size.width);
      const height = Math.max(1, info.size.height);
      this.aspect = width / height;
      // 预览只需要几百像素高；SVG 必须给目标尺寸才会按需要的大小栅格化。
      const targetHeight = 240;
      const targetWidth = Math.max(1, Math.min(2400, Math.round(targetHeight * this.aspect)));
      this.pixelMap = await source.createPixelMap({ desiredSize: { width: targetWidth, height: targetHeight } });
      const slice = bubbleFrameSliceOrDefault(this.request.settings.frameSlice, this.aspect);
      this.sliceLeft = slice.left;
      this.sliceRight = slice.right;
      this.sliceTop = slice.top;
      this.sliceBottom = slice.bottom;
      this.opaque = ThemeBubbleFrameStretcher.isOpaque(this.request.uri, this.pixelMap);
      this.drawPreview();
    } catch (e) {
      console.error('读取气泡边框失败:', e);
      this.failed = true;
    } finally {
      if (source) source.release().catch((): void => {});
      if (file) fs.closeSync(file);
    }
  }

  static isOpaque(uri: string, map: PixelMap): boolean {
    if (/\.jpe?g$/i.test(uri)) return true;
    try {
      return map.getImageInfoSync().alphaType === image.AlphaType.OPAQUE;
    } catch (_) {
      return false;
    }
  }

  // ---- 正文小样 ----

  drawPreview(): void {
    const params = new BubbleFramePreviewParams();
    params.map = this.pixelMap;
    params.aspect = this.aspect;
    params.sliceLeft = this.sliceLeft;
    params.sliceRight = this.sliceRight;
    params.sliceTop = this.sliceTop;
    params.sliceBottom = this.sliceBottom;
    params.round = this.round;
    params.cut = this.cut;
    params.tint = this.tint;
    params.textColor = this.request.textColor;
    params.bubbleColor = this.request.bubbleColor;
    const height = BubbleFramePreviewPainter.draw(this.canvas, params, STRETCH_SAMPLE);
    if (height > 0 && Math.abs(height - this.previewHeight) > 0.5) this.previewHeight = height;
  }
}
