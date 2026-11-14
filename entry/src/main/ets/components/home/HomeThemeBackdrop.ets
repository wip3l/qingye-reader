import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { HexColor } from '../../utils/HexColor';
import { AnimatedImagePolicy } from '../../utils/AnimatedImagePolicy';
import { ThemeImageSlots } from '../../theme/ThemePackRegistry';
import { ThemeImageCrop } from '../../theme/share/ThemePackageFormat';
import { ThemeCroppedImage } from '../theme/ThemeCroppedImage';

/**
 * 首页页签顶部的主题背景图：放在页面根部最底层，不随列表滚动，向下淡成页面底色。
 * 页面里铺满整页的列表、滚动区要改用 ThemeRuntime.homeSurfaceColor，否则会把它盖住。
 */
@Component
export struct HomeThemeBackdrop {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('animatedImageRevision') animatedImageRevision: number = 0;
  /** 显示高度；0 表示按图片宽高比整张显示（书架用），其他页签只衬在标题区。 */
  @Prop visibleHeight: number = 0;
  /** 图片不透明度：书架最强，搜索、发现弱一些，免得和结果列表抢。 */
  @Prop strength: number = 1;
  /** 书架页传当前书架布局：主题按布局单独配了背景时用那一张；其他页签不传，用通用背景。 */
  @Prop shelfLayout: string = '';

  themeBackdrop(): ResourceStr | null {
    return ThemeRuntime.homeBackdrop(this.appDarkMode, this.shelfLayout);
  }

  // 浅色只轻压一层底色；深色图里的金线更亮，压得重一些才不刺眼。
  gradientColors(): Array<[ResourceColor, number]> {
    const page = ThemeRuntime.pageColor(this.appDarkMode);
    const stops: number[][] = this.appDarkMode ?
      [[0.25, 0], [0.55, 0.38], [0.9, 0.7], [1, 1]] :
      [[0.1, 0], [0.3, 0.38], [0.85, 0.72], [1, 1]];
    return stops.map((stop: number[]): [ResourceColor, number] => [HexColor.withOpacity(page, stop[0]), stop[1]]);
  }

  /** 背景是动图时由 AnimatedImagePolicy 决定播放还是只显示第一帧。 */
  backdropImage(): ResourceStr {
    const image = this.themeBackdrop() as ResourceStr;
    if (typeof image !== 'string' || this.animatedImageRevision < 0) return image;
    return AnimatedImagePolicy.display(getContext(this), image);
  }

  /** 主题包动图背景取景时记下的显示区域。 */
  backdropCrop(): ThemeImageCrop | null {
    return ThemeAssetRegistry.imageCrop(ThemeImageSlots.BACKDROP, this.themeBackdrop(), this.appDarkMode,
      this.shelfLayout);
  }

  build() {
    if (this.themeBackdrop()) {
      if (this.visibleHeight > 0) {
        Stack({ alignContent: Alignment.Top }) {
          this.layers()
        }
        .width('100%')
        .height(this.visibleHeight)
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
      } else {
        Stack({ alignContent: Alignment.Top }) {
          this.layers()
        }
        .width('100%')
        .aspectRatio(ThemeAssetRegistry.HOME_BACKDROP_ASPECT)
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
      }
    }
  }

  @Builder
  layers() {
    if (this.backdropCrop()) {
      ThemeCroppedImage({ src: this.backdropImage(), crop: this.backdropCrop() as ThemeImageCrop, syncLoad: true })
        .width('100%')
        .aspectRatio(ThemeAssetRegistry.HOME_BACKDROP_ASPECT)
        .opacity(this.strength)
    } else {
      Image(this.backdropImage())
        .width('100%')
        .aspectRatio(ThemeAssetRegistry.HOME_BACKDROP_ASPECT)
        .objectFit(ImageFit.Cover)
        // 书架开合、分组展开的截图都要带上背景，异步加载会截到空白。
        .syncLoad(true)
        .opacity(this.strength)
    }
    Column()
      .width('100%')
      .height('100%')
      .linearGradient({ direction: GradientDirection.Bottom, colors: this.gradientColors() })
  }
}
