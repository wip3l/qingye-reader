import { HexColor } from '../../utils/HexColor';
import { AnimatedImagePolicy } from '../../utils/AnimatedImagePolicy';
import { ShelfBackdropLook, ShelfBackdropStore } from '../../utils/ShelfBackdropStore';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { ReaderThemeBackground } from '../ReaderThemeBackground';

/**
 * 书架的自定义背景（书架设置 › 书架背景）。书架根部、冷启动骨架和设置页的实景预览共用。
 * - 顶部淡出：和主题首页背景一样按 4 : 5 铺在顶部，向下淡成页面底色（渐变停点同 HomeThemeBackdrop）。
 * - 全屏：铺满父组件，图片显示方式交给 ReaderThemeBackground（裁切取景 / 完整显示加模糊垫底 / 拉伸 / 平铺），
 *   再盖一层页面底色（淡化）和顶部一段渐变，让顶栏文字压得住。
 */
@Component
export struct ShelfCustomBackdrop {
  @Prop look: ShelfBackdropLook = new ShelfBackdropLook();
  @Prop pageColor: string = '#FFFFFF';
  @Prop dark: boolean = false;
  @StorageProp('animatedImageRevision') animatedImageRevision: number = 0;
  /** 顶部渐变的高度：盖住状态栏和书架标题行。 */
  private static readonly SCRIM_HEIGHT: number = 200;

  build() {
    if (this.look.image) {
      if (this.look.display === ShelfBackdropStore.DISPLAY_TOP) {
        Stack({ alignContent: Alignment.Top }) {
          Image(this.imageSource())
            .width('100%')
            .aspectRatio(ThemeAssetRegistry.HOME_BACKDROP_ASPECT)
            .objectFit(ImageFit.Cover)
            // 书架开合、分组展开的截图都要带上背景，异步加载会截到空白。
            .syncLoad(true)
            .draggable(false)
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({ direction: GradientDirection.Bottom, colors: this.fadeColors() })
        }
        .width('100%')
        .aspectRatio(ThemeAssetRegistry.HOME_BACKDROP_ASPECT)
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
      } else {
        Stack({ alignContent: Alignment.Top }) {
          ReaderThemeBackground({
            surfaceColor: this.pageColor,
            customImage: this.imageSource(),
            customImageFit: this.look.fit,
            customImagePosition: this.look.position,
            customImageGap: this.look.gap
          })
            .width('100%')
            .height('100%')
            .blur(this.look.blur)
            // 内容模糊在边缘会透出底色，按模糊程度放大一点推到外面去，外层会裁掉。
            .scale({ x: this.blurScale(), y: this.blurScale() })
          if (this.look.wash > 0) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(HexColor.withOpacity(this.pageColor, this.look.wash / 100))
          }
          Column()
            .width('100%')
            .height(ShelfCustomBackdrop.SCRIM_HEIGHT)
            .linearGradient({ direction: GradientDirection.Bottom, colors: this.scrimColors() })
        }
        .width('100%')
        .height('100%')
        .clip(true)
        // 背景整层不随书架滚动，缓存成一张图，模糊也只算一次。
        .renderGroup(true)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
      }
    }
  }

  /** 动图由 AnimatedImagePolicy 决定播放还是只显示第一帧。 */
  imageSource(): string {
    if (this.animatedImageRevision < 0) return this.look.image;
    return AnimatedImagePolicy.display(getContext(this), this.look.image);
  }

  blurScale(): number {
    return this.look.blur > 0 ? 1 + this.look.blur * 0.012 : 1;
  }

  // 同 HomeThemeBackdrop：浅色只轻压一层底色，深色压得重一些。
  fadeColors(): Array<[ResourceColor, number]> {
    const stops: number[][] = this.dark ?
      [[0.25, 0], [0.55, 0.38], [0.9, 0.7], [1, 1]] :
      [[0.1, 0], [0.3, 0.38], [0.85, 0.72], [1, 1]];
    return stops.map((stop: number[]): [ResourceColor, number] =>
      [HexColor.withOpacity(this.pageColor, stop[0]), stop[1]]);
  }

  scrimColors(): Array<[ResourceColor, number]> {
    return [[HexColor.withOpacity(this.pageColor, 0.55), 0], [HexColor.withOpacity(this.pageColor, 0.2), 0.6],
      [HexColor.withOpacity(this.pageColor, 0), 1]];
  }
}
