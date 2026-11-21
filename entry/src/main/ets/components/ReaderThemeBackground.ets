import image from '@ohos.multimedia.image';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ReaderThemeDecorationLayout } from '../core/reader/ReaderThemeDecorationLayout';
import { ReaderRasterAssets } from '../core/reader/ReaderRasterAssets';
import { ReaderBackgroundDisplay } from '../utils/ReaderBackgroundDisplay';

/**
 * Responsive reader background for builtin themes.
 *
 * Builtin artwork is deliberately rendered as proportional corner ornaments
 * over a native, size-aware surface instead of stretching or cropping the old
 * 9:16 wallpaper. Whole images (user-selected or a theme pack's) are drawn by ReaderBackgroundDisplay:
 * cover with a crop position, contain over a blurred copy or the surface colour, fill, or tiled at native size.
 */
@Component
export struct ReaderThemeBackground {
  @Prop surfaceColor: ResourceColor = Color.Transparent;
  @Prop backgroundAssetId: string = '';
  @Prop customImage: ResourceStr = '';
  /** ReaderBackgroundDisplay.FITS 之一；下面两项分别只对 cover、contain 有效。 */
  @Prop customImageFit: string = 'cover';
  @Prop customImagePosition: number = 50;
  @Prop customImageGap: string = 'color';
  @Prop compact: boolean = false;
  @Prop viewportWidthHint: number = 0;
  @Prop viewportHeightHint: number = 0;
  // ThemeAssetRegistry.readerDecorationSignature：主题包角饰换图或调大小而背景 ID 不变时，靠它触发重画。
  @Prop decorationSignature: string = '';
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;
  // 实际铺出来的大小。取景偏移按它算：根背景会延伸进安全区，比 viewport 提示略大。
  @State measuredWidth: number = 0;
  @State measuredHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.surfaceColor)

      // 主题包（含方案自己上传）的整图背景；阅读页走 ReaderThemeHelper 转成 customImage（带上读者改的显示方式），
      // 主题页的预览直接到这里，按主题作者的设定显示。
      if (this.imageSource()) {
        this.wholeImage()
      }
      // 主题包整图模式也可以带角饰，叠在整图上面；内置主题和自定义图片不会同时带素材键和图片。
      if (this.backgroundAssetId) {
        this.builtinThemeDecoration()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .renderGroup(true)
    .hitTestBehavior(HitTestMode.None)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = this.areaDimension(newValue.width);
      const height = this.areaDimension(newValue.height);
      if (width > 0 && Math.abs(width - this.measuredWidth) >= 1) {
        this.measuredWidth = width;
      }
      if (height > 0 && Math.abs(height - this.measuredHeight) >= 1) {
        this.measuredHeight = height;
      }
      if (this.viewportWidthHint <= 0 && width > 0 && Math.abs(width - this.viewportWidth) >= 1) {
        this.viewportWidth = width;
      }
      if (this.viewportHeightHint <= 0 && height > 0 && Math.abs(height - this.viewportHeight) >= 1) {
        this.viewportHeight = height;
      }
    })
  }

  // 不带参数、全部从 this 读：按值传进 @Builder 的参数变了不会刷新。
  @Builder
  wholeImage() {
    if (this.imageFit() === ReaderBackgroundDisplay.FIT_TILE) {
      Row()
        .width('100%')
        .height('100%')
        .backgroundImage(this.imageSource(), ImageRepeat.XY)
        .backgroundImageSize(this.tileSize())
        .backgroundImagePosition(Alignment.TopStart)
        .hitTestBehavior(HitTestMode.None)
    } else {
      if (this.showsBlurBackdrop()) {
        Image(this.blurBackdrop())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .blur(ReaderBackgroundDisplay.BLUR_RADIUS)
          // 内容模糊在边缘会透出底色，放大一点把那圈推到外面去，外层 Stack 会裁掉。
          .scale({ x: 1.12, y: 1.12 })
          .draggable(false)
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.positionedCover()) {
        Image(this.imageSource())
          .width(this.coverRect()[2])
          .height(this.coverRect()[3])
          .position({ x: this.coverRect()[0], y: this.coverRect()[1] })
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .draggable(false)
          .hitTestBehavior(HitTestMode.None)
      } else {
        Image(this.imageSource())
          .width('100%')
          .height('100%')
          .objectFit(this.objectFit())
          .syncLoad(true)
          .draggable(false)
          .hitTestBehavior(HitTestMode.None)
      }
    }
  }

  imageSource(): ResourceStr {
    if (this.customImage) return this.customImage;
    return ThemeAssetRegistry.readerBackgroundImage(this.backgroundAssetId);
  }

  private sourcePath(): string {
    const source = this.imageSource();
    return typeof source === 'string' ? source : '';
  }

  imageFit(): string {
    if (this.customImage) return ReaderBackgroundDisplay.normalizeFit(this.customImageFit);
    return ReaderBackgroundDisplay.normalizeFit(ThemeAssetRegistry.readerBackgroundImageFit(this.backgroundAssetId));
  }

  objectFit(): ImageFit {
    const fit = this.imageFit();
    if (fit === ReaderBackgroundDisplay.FIT_CONTAIN) return ImageFit.Contain;
    if (fit === ReaderBackgroundDisplay.FIT_FILL) return ImageFit.Fill;
    return ImageFit.Cover;
  }

  showsBlurBackdrop(): boolean {
    return !!this.customImage && this.imageFit() === ReaderBackgroundDisplay.FIT_CONTAIN &&
      this.customImageGap === ReaderBackgroundDisplay.GAP_BLUR && !!this.blurBackdrop();
  }

  blurBackdrop(): image.PixelMap | undefined {
    return ReaderRasterAssets.backdropThumb(this.sourcePath()) ?? undefined;
  }

  /** 平铺按图片原始像素大小；读不出尺寸时交给系统按原图大小铺。 */
  tileSize(): SizeOptions | ImageSize {
    const size = ReaderRasterAssets.imageSize(this.sourcePath());
    if (!size) return ImageSize.Auto;
    const width = this.getUIContext().px2vp(size.width);
    return { width: width, height: width * size.height / size.width };
  }

  /** cover 且取景不在正中、这张图在这块屏幕上确实要裁时，自己算图片的位置；其余交给 ImageFit.Cover。 */
  positionedCover(): boolean {
    if (!this.customImage || this.imageFit() !== ReaderBackgroundDisplay.FIT_COVER) return false;
    if (ReaderBackgroundDisplay.normalizePosition(this.customImagePosition) === 50) return false;
    const aspect = ReaderRasterAssets.imageAspect(this.sourcePath());
    return ReaderBackgroundDisplay.croppedAxis(aspect, this.layoutWidth(), this.layoutHeight()) !== '';
  }

  coverRect(): number[] {
    return ReaderBackgroundDisplay.coverRect(ReaderRasterAssets.imageAspect(this.sourcePath()),
      this.layoutWidth(), this.layoutHeight(), this.customImagePosition);
  }

  layoutWidth(): number {
    return this.measuredWidth > 0 ? this.measuredWidth : this.effectiveViewportWidth();
  }

  layoutHeight(): number {
    return this.measuredHeight > 0 ? this.measuredHeight : this.effectiveViewportHeight();
  }

  @Builder
  builtinThemeDecoration() {
    if (this.hasOrnaments()) {
      Column() {
        // 主题包可以只有一角的角饰，空着的那角只留占位。
        Row() {
          if (this.leadingImage()) {
            Image(this.leadingImage())
              .width(this.decorationSize(false))
              .height(this.decorationSize(false))
              .objectFit(ImageFit.Contain)
              .syncLoad(true)
              .draggable(false)
          }
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: this.decorationInset(false), top: this.decorationInset(false) })

        Blank()
          .layoutWeight(1)

        Row() {
          Blank()
            .layoutWeight(1)
          if (this.trailingImage()) {
            Image(this.trailingImage())
              .width(this.decorationSize(true))
              .height(this.decorationSize(true))
              .objectFit(ImageFit.Contain)
              .syncLoad(true)
              .rotate({ angle: this.trailingRotation() })
              .draggable(false)
          }
        }
        .width('100%')
        .padding({ right: this.decorationInset(true), bottom: this.decorationInset(true) })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
  }

  // 下面几个取值都读一下 decorationSignature，让它变化时这些节点跟着更新。
  hasOrnaments(): boolean {
    return this.decorationSignature.length >= 0 &&
      ThemeAssetRegistry.readerBackgroundHasOrnaments(this.backgroundAssetId);
  }

  leadingImage(): ResourceStr {
    return this.decorationSignature.length >= 0 ?
      ThemeAssetRegistry.readerBackgroundDecoration(this.backgroundAssetId) : '';
  }

  trailingImage(): ResourceStr {
    return this.decorationSignature.length >= 0 ?
      ThemeAssetRegistry.readerBackgroundTrailingDecoration(this.backgroundAssetId) : '';
  }

  trailingRotation(): number {
    return this.decorationSignature.length >= 0 ?
      ThemeAssetRegistry.readerBackgroundTrailingRotation(this.backgroundAssetId) : 0;
  }

  // The placement math lives in ReaderThemeDecorationLayout, shared with the self-drawn page raster.
  decorationSize(trailing: boolean): number {
    if (this.decorationSignature.length < 0) return 0;
    return ReaderThemeDecorationLayout.size(this.effectiveViewportWidth(), this.effectiveViewportHeight(),
      this.compact, ThemeAssetRegistry.readerBackgroundOrnamentScale(this.backgroundAssetId, trailing));
  }

  // 左上、右下角饰各自有边距倍数，0 是贴着屏幕边缘。
  decorationInset(trailing: boolean): number {
    if (this.decorationSignature.length < 0) return 0;
    return ReaderThemeDecorationLayout.inset(this.effectiveViewportWidth(), this.effectiveViewportHeight(),
      this.compact, ThemeAssetRegistry.readerBackgroundOrnamentInset(this.backgroundAssetId, trailing));
  }

  shortEdge(): number {
    const width = this.effectiveViewportWidth();
    const height = this.effectiveViewportHeight();
    if (width <= 0 || height <= 0) return this.compact ? 58 : 480;
    return Math.min(width, height);
  }

  effectiveViewportWidth(): number {
    return this.viewportWidthHint > 0 ? this.viewportWidthHint : this.viewportWidth;
  }

  effectiveViewportHeight(): number {
    return this.viewportHeightHint > 0 ? this.viewportHeightHint : this.viewportHeight;
  }

  areaDimension(value: Length): number {
    if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
