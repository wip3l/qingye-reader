import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import {
  BUBBLE_FRAME_SLICE_MAX,
  COMMENT_IMAGE_OVERHANG_BOTTOM,
  COMMENT_IMAGE_OVERHANG_TOP,
  CommentImageBreak,
  commentImageOverhang,
  commentImageSliceOrDefault,
  commentImageTextOrDefault,
  defaultCommentImageSlice,
  defaultCommentImageText,
  ThemePackageBubbleSlice,
  ThemePackageCommentBubble
} from '../../theme/share/ThemePackageFormat';
import {
  ReaderCommentBubbleImage,
  ReaderCommentBubblePainter,
  ReaderCommentBubbleStyle
} from '../../core/reader/ReaderCommentBubble';
import { ReaderV2Color } from '../../core/reader/ReaderV2Style';
import { ThemeBubbleFrameStretcher } from './ThemeBubbleFrameStretcher';

/** 一次调整：气泡图和已有的设置，以及小样用的阅读底色、正文色、段评文字色和底色（染色时用）。 */
export class CommentImageStretchRequest {
  uri: string = '';
  settings: ThemePackageCommentBubble = new ThemePackageCommentBubble();
  paperColor: string = '#FAF6EE';
  inkColor: string = '#2B2620';
  textColor: string = '#4A3423';
  fillColor: string = '#B98546';
  modeLabel: string = '浅色';
}

const STRETCH_COLOR: string = '#E0393E';
const TEXT_BOX_COLOR: string = '#F0A04B';
/** 小样里依次画的四个气泡：数字、99+、带字的本章说，以及折行时不带尾巴的前一段。 */
const SAMPLE_LABELS: string[] = ['3', '99+', '本章说', '段评'];

/**
 * 段评气泡图的拉伸与文字区页：两条红线定左右两端（之间的部分随文字变长而拉伸），橙色框是文字区
 * （拖左上、右下两个圆点），下面的正文小样按阅读页的画法实时重画。外观沿用气泡边框的拉伸页。
 */
@Component
export struct ThemeCommentImageStretcher {
  @Prop request: CommentImageStretchRequest = new CommentImageStretchRequest();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  onDone: (settings: ThemePackageCommentBubble) => void = (_settings: ThemePackageCommentBubble): void => {};
  onCancel: () => void = (): void => {};
  @State private pixelMap: PixelMap | undefined = undefined;
  @State private aspect: number = 3;
  @State private failed: boolean = false;
  @State private opaque: boolean = false;
  @State private sliceLeft: number = 0;
  @State private sliceRight: number = 0;
  @State private textLeft: number = 0;
  @State private textRight: number = 0;
  @State private textTop: number = 0;
  @State private textBottom: number = 0;
  @State private full: boolean = false;
  @State private areaWidth: number = 0;
  @State private samples: ReaderCommentBubbleImage[] = [];
  private startA: number = 0;
  private startB: number = 0;
  private retired: ReaderCommentBubbleImage[] = [];

  aboutToAppear(): void {
    this.full = this.request.settings.imageBreak === CommentImageBreak.FULL;
    this.decode();
  }

  aboutToDisappear(): void {
    const map = this.pixelMap;
    this.pixelMap = undefined;
    if (map) map.release().catch((): void => {});
    for (const sample of this.samples.concat(this.retired)) sample.pixelMap.release().catch((): void => {});
    this.samples = [];
    this.retired = [];
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
        Text('拉伸与文字区')
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
          .padding({ top: 32, bottom: 32 })
          .backgroundColor('#1D2024')

          if (this.pixelMap) {
            Row({ space: AppSpacing.LG }) {
              this.legend(STRETCH_COLOR, '拉伸线')
              this.legend(TEXT_BOX_COLOR, '文字区')
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
            Text(this.readout())
              .fontSize(AppFontSize.CAPTION)
              .fontColor('#9DA5AE')
              .textAlign(TextAlign.Center)
              .width('100%')
          }

          Column({ space: AppSpacing.SM }) {
            if (this.overhangWarning()) {
              this.warning(this.overhangWarning())
            }
            if (this.opaque) {
              this.warning('这是不透明的图，正文里会露出方形底色。建议换成透明底的 PNG 或 SVG。')
            }
            this.sampleCard()
            this.optionRow('换行处', '裁掉尾巴', '整图', !this.full, (first: boolean) => {
              this.full = !first;
              this.refreshSamples();
            })
            Text('恢复默认位置')
              .fontSize(AppFontSize.CAPTION)
              .fontColor('#9CC8FF')
              .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
              .onClick(() => this.resetGuides())
          }
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })

          Text('拖红线定两端，两线之间随文字变长拉伸；拖橙色圆点定文字区，它的高度对齐正文里的气泡高')
            .fontSize(AppFontSize.CAPTION)
            .fontColor('#8E969F')
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.XXL + this.navBarHeight })
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
      if (Math.abs(width - this.areaWidth) > 0.5) this.areaWidth = width;
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
      Column()
        .width(Math.max(2, (1 - this.textLeft - this.textRight) * this.displayWidth()))
        .height(Math.max(2, (1 - this.textTop - this.textBottom) * this.displayHeight()))
        .border({ width: 2, color: TEXT_BOX_COLOR })
        .backgroundColor('#22F0A04B')
        .position({ x: this.textLeft * this.displayWidth(), y: this.textTop * this.displayHeight() })
        .hitTestBehavior(HitTestMode.None)
      this.stretchGuide(true)
      this.stretchGuide(false)
      this.textHandle(true)
      this.textHandle(false)
    }
    .width(this.displayWidth())
    .height(this.displayHeight())
  }

  @Builder
  stretchGuide(left: boolean) {
    Stack({ alignContent: Alignment.Bottom }) {
      Column().width(2).height('100%').backgroundColor(STRETCH_COLOR)
      Column()
        .width(16)
        .height(16)
        .borderRadius(8)
        .backgroundColor(STRETCH_COLOR)
        .border({ width: 2, color: '#FFFFFF' })
        .margin({ bottom: -6 })
    }
    .width(28)
    .height(this.displayHeight() + 44)
    .position({ x: (left ? this.sliceLeft : 1 - this.sliceRight) * this.displayWidth() - 14, y: -22 })
    .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
      .onActionStart(() => {
        this.startA = left ? this.sliceLeft : this.sliceRight;
      })
      .onActionUpdate((event: GestureEvent) => {
        const delta = event.offsetX / Math.max(1, this.displayWidth());
        if (left) {
          this.sliceLeft = this.clampEnd(this.startA + delta, this.sliceRight);
        } else {
          this.sliceRight = this.clampEnd(this.startA - delta, this.sliceLeft);
        }
      })
      .onActionEnd(() => this.refreshSamples()))
  }

  /** 文字区的左上角（topLeft 为 true）或右下角圆点，可以向任意方向拖。 */
  @Builder
  textHandle(topLeft: boolean) {
    Stack() {
      Column()
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(TEXT_BOX_COLOR)
        .border({ width: 2, color: '#FFFFFF' })
    }
    .width(36)
    .height(36)
    .position({
      x: (topLeft ? this.textLeft : 1 - this.textRight) * this.displayWidth() - 18,
      y: (topLeft ? this.textTop : 1 - this.textBottom) * this.displayHeight() - 18
    })
    .accessibilityText(topLeft ? '文字区左上角' : '文字区右下角')
    .gesture(PanGesture({ direction: PanDirection.All, distance: 1 })
      .onActionStart(() => {
        this.startA = topLeft ? this.textLeft : this.textRight;
        this.startB = topLeft ? this.textTop : this.textBottom;
      })
      .onActionUpdate((event: GestureEvent) => {
        const dx = event.offsetX / Math.max(1, this.displayWidth());
        const dy = event.offsetY / Math.max(1, this.displayHeight());
        if (topLeft) {
          this.textLeft = this.clampEnd(this.startA + dx, this.textRight);
          this.textTop = this.clampEnd(this.startB + dy, this.textBottom);
        } else {
          this.textRight = this.clampEnd(this.startA - dx, this.textLeft);
          this.textBottom = this.clampEnd(this.startB - dy, this.textTop);
        }
      })
      .onActionEnd(() => this.refreshSamples()))
  }

  @Builder
  legend(color: string, label: string) {
    Row({ space: AppSpacing.XS }) {
      Column().width(14).height(3).borderRadius(1.5).backgroundColor(color)
      Text(label).fontSize(AppFontSize.CAPTION).fontColor('#C9CED4')
    }
  }

  @Builder
  warning(message: string) {
    Text(message)
      .fontSize(AppFontSize.CAPTION)
      .fontColor('#F4C26B')
      .backgroundColor('#2E2614')
      .borderRadius(8)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
      .width('100%')
  }

  /** 和阅读页一样：正文里嵌着数字、99+、本章说三个气泡，第二行是折到两行时不带尾巴的前一段。 */
  @Builder
  sampleCard() {
    Column({ space: AppSpacing.SM }) {
      Text(`${this.request.modeLabel} · 小样`)
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.request.inkColor)
        .opacity(0.6)
      if (this.samples.length === SAMPLE_LABELS.length) {
        Text() {
          Span('　　“走吧。”他推开门')
          ImageSpan(this.samples[0].pixelMap)
            .width(this.px2vp(this.samples[0].width))
            .height(this.px2vp(this.samples[0].height))
            .verticalAlign(ImageSpanAlignment.CENTER)
          Span('，风一下灌了进来。')
          ImageSpan(this.samples[1].pixelMap)
            .width(this.px2vp(this.samples[1].width))
            .height(this.px2vp(this.samples[1].height))
            .verticalAlign(ImageSpanAlignment.CENTER)
          Span('雨还没有停。')
          ImageSpan(this.samples[2].pixelMap)
            .width(this.px2vp(this.samples[2].width))
            .height(this.px2vp(this.samples[2].height))
            .verticalAlign(ImageSpanAlignment.CENTER)
        }
        .fontSize(16)
        .lineHeight(32)
        .fontColor(this.request.inkColor)
        Row({ space: AppSpacing.XS }) {
          Text('折行时前一段：').fontSize(AppFontSize.CAPTION).fontColor(this.request.inkColor).opacity(0.7)
          Image(this.samples[3].pixelMap)
            .width(this.px2vp(this.samples[3].width))
            .height(this.px2vp(this.samples[3].height))
            .objectFit(ImageFit.Contain)
            .draggable(false)
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.LG)
    .borderRadius(12)
    .backgroundColor(this.request.paperColor)
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

  px2vp(value: number): number {
    return this.getUIContext().px2vp(value);
  }

  displayWidth(): number {
    const maxWidth = Math.max(60, this.areaWidth - 72);
    return Math.min(maxWidth, 150 * this.aspect);
  }

  displayHeight(): number {
    return this.displayWidth() / Math.max(0.05, this.aspect);
  }

  /** 单项不超过 BUBBLE_FRAME_SLICE_MAX，和对面那项合起来至少留出 2%。 */
  clampEnd(value: number, other: number): number {
    return Math.max(0, Math.min(BUBBLE_FRAME_SLICE_MAX, 0.98 - other, value));
  }

  readout(): string {
    const pct = (value: number): string => `${Math.round(value * 100)}%`;
    return `左端 ${pct(this.sliceLeft)} · 右端 ${pct(this.sliceRight)} · 文字区占图高 ` +
      `${pct(1 - this.textTop - this.textBottom)}`;
  }

  textBox(): ThemePackageBubbleSlice {
    const box = new ThemePackageBubbleSlice();
    box.left = this.textLeft;
    box.right = this.textRight;
    box.top = this.textTop;
    box.bottom = this.textBottom;
    return box;
  }

  overhangWarning(): string {
    const reach = commentImageOverhang(this.textBox());
    const parts: string[] = [];
    if (reach[0] > COMMENT_IMAGE_OVERHANG_TOP) {
      parts.push(`上方超出气泡高 ${Math.round(reach[0] * 100)}%（建议不超过 ${Math.round(COMMENT_IMAGE_OVERHANG_TOP * 100)}%）`);
    }
    if (reach[1] > COMMENT_IMAGE_OVERHANG_BOTTOM) {
      parts.push(`下方超出 ${Math.round(reach[1] * 100)}%（建议不超过 ${Math.round(COMMENT_IMAGE_OVERHANG_BOTTOM * 100)}%）`);
    }
    return parts.length > 0 ? `文字区${parts.join('，')}，正文行距小时可能压到上下行。` : '';
  }

  resetGuides(): void {
    const slice = defaultCommentImageSlice(this.aspect);
    const box = defaultCommentImageText(this.aspect);
    this.sliceLeft = slice.left;
    this.sliceRight = slice.right;
    this.textLeft = box.left;
    this.textRight = box.right;
    this.textTop = box.top;
    this.textBottom = box.bottom;
    this.refreshSamples();
  }

  result(): ThemePackageCommentBubble {
    const settings = new ThemePackageCommentBubble();
    const slice = new ThemePackageBubbleSlice();
    slice.left = Math.round(this.sliceLeft * 1000) / 1000;
    slice.right = Math.round(this.sliceRight * 1000) / 1000;
    settings.imageSlice = slice;
    const box = this.textBox();
    box.left = Math.round(box.left * 1000) / 1000;
    box.right = Math.round(box.right * 1000) / 1000;
    box.top = Math.round(box.top * 1000) / 1000;
    box.bottom = Math.round(box.bottom * 1000) / 1000;
    settings.imageText = box;
    settings.imageRepeat = this.request.settings.imageRepeat;
    settings.imageBreak = this.full ? CommentImageBreak.FULL : '';
    settings.imageTint = this.request.settings.imageTint;
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
      const targetHeight = 300;
      const targetWidth = Math.max(1, Math.min(2400, Math.round(targetHeight * this.aspect)));
      this.pixelMap = await source.createPixelMap({ desiredSize: { width: targetWidth, height: targetHeight } });
      const slice = commentImageSliceOrDefault(this.request.settings, this.aspect);
      const box = commentImageTextOrDefault(this.request.settings, this.aspect);
      this.sliceLeft = slice.left;
      this.sliceRight = slice.right;
      this.textLeft = box.left;
      this.textRight = box.right;
      this.textTop = box.top;
      this.textBottom = box.bottom;
      this.opaque = ThemeBubbleFrameStretcher.isOpaque(this.request.uri, this.pixelMap);
      this.refreshSamples();
    } catch (e) {
      console.error('读取段评气泡图失败:', e);
      this.failed = true;
    } finally {
      if (source) source.release().catch((): void => {});
      if (file) fs.closeSync(file);
    }
  }

  // ---- 小样 ----

  sampleStyle(): ReaderCommentBubbleStyle {
    const style = new ReaderCommentBubbleStyle();
    style.styleId = 'image';
    style.image = this.request.uri;
    style.imageAspect = this.aspect;
    style.sliceLeft = this.sliceLeft;
    style.sliceRight = this.sliceRight;
    style.textLeft = this.textLeft;
    style.textRight = this.textRight;
    style.textTop = this.textTop;
    style.textBottom = this.textBottom;
    style.imageRound = this.request.settings.imageRepeat === 'round';
    style.imageCut = !this.full;
    style.imageTint = this.request.settings.imageTint;
    style.fill = ReaderV2Color.parse(this.request.fillColor, 0xFFB98546);
    style.text = ReaderV2Color.parse(this.request.textColor, 0xFF4A3423);
    style.stroke = 0;
    return style;
  }

  /** 拖动松手后重画；旧位图过一会儿再释放，免得正在显示的那张被提前收走。 */
  refreshSamples(): void {
    if (!this.pixelMap) return;
    const style = this.sampleStyle();
    const fontPx = this.getUIContext().vp2px(11);
    const next: ReaderCommentBubbleImage[] = [];
    for (let index = 0; index < SAMPLE_LABELS.length; index++) {
      const rendered = ReaderCommentBubblePainter.renderLabel(style, SAMPLE_LABELS[index], fontPx,
        index !== SAMPLE_LABELS.length - 1);
      if (!rendered) return;
      next.push(rendered);
    }
    const old = this.samples;
    this.samples = next;
    for (const item of this.retired) item.pixelMap.release().catch((): void => {});
    this.retired = old;
  }
}
