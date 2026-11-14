import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ReaderThemeDecorationLayout } from '../core/reader/ReaderThemeDecorationLayout';

/**
 * Responsive reader background for builtin themes.
 *
 * Builtin artwork is deliberately rendered as proportional corner ornaments
 * over a native, size-aware surface instead of stretching or cropping the old
 * 9:16 wallpaper. User-selected images still keep their chosen fit mode.
 */
@Component
export struct ReaderThemeBackground {
  @Prop surfaceColor: ResourceColor = Color.Transparent;
  @Prop backgroundAssetId: string = '';
  @Prop customImage: ResourceStr = '';
  @Prop customImageFit: ImageFit = ImageFit.Cover;
  @Prop compact: boolean = false;
  @Prop viewportWidthHint: number = 0;
  @Prop viewportHeightHint: number = 0;
  // ThemeAssetRegistry.readerDecorationSignature：主题包角饰换图或调大小而背景 ID 不变时，靠它触发重画。
  @Prop decorationSignature: string = '';
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.surfaceColor)

      if (this.customImage) {
        Image(this.customImage)
          .width('100%')
          .height('100%')
          .objectFit(this.customImageFit)
          .syncLoad(true)
          .draggable(false)
          .hitTestBehavior(HitTestMode.None)
      } else if (ThemeAssetRegistry.readerBackgroundImage(this.backgroundAssetId)) {
        // 主题包（含方案自己上传）的整图背景；阅读页走 ReaderThemeHelper 转成 customImage，预览面板直接到这里。
        Image(ThemeAssetRegistry.readerBackgroundImage(this.backgroundAssetId))
          .width('100%')
          .height('100%')
          .objectFit(this.packImageFit())
          .syncLoad(true)
          .draggable(false)
          .hitTestBehavior(HitTestMode.None)
      } else if (this.backgroundAssetId) {
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
      if (this.viewportWidthHint <= 0 && width > 0 && Math.abs(width - this.viewportWidth) >= 1) {
        this.viewportWidth = width;
      }
      if (this.viewportHeightHint <= 0 && height > 0 && Math.abs(height - this.viewportHeight) >= 1) {
        this.viewportHeight = height;
      }
    })
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
      }
      .width('100%')
      .height('100%')
      .padding(this.decorationInset())
      .hitTestBehavior(HitTestMode.None)
    }
  }

  packImageFit(): ImageFit {
    const fit = ThemeAssetRegistry.readerBackgroundImageFit(this.backgroundAssetId);
    if (fit === 'contain') return ImageFit.Contain;
    if (fit === 'fill') return ImageFit.Fill;
    return ImageFit.Cover;
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

  decorationInset(): Padding {
    const inset = ReaderThemeDecorationLayout.inset(this.effectiveViewportWidth(), this.effectiveViewportHeight(),
      this.compact);
    return { left: inset, right: inset, top: inset, bottom: inset };
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
