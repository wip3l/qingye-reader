import { CollapsingHeader } from '../../utils/CollapsingHeader';

/**
 * 顶栏背后的实时毛玻璃。渐变只裁切材质，不影响上层标题、按钮和光感栏。
 * 外观“顶部磨砂”关闭时不模糊也不着色，顶栏完全透明；节点保留，照旧挡住顶栏区域下方列表的点击。
 */
@Component
export struct HeaderBackdrop {
  @StorageProp('headerFrosted') headerFrosted: boolean = true;
  @Prop backdropHeight: number = 0;
  @Prop backdropColor: string = '#FFFFFF';
  @Prop statusBarHeight: number = 0;
  /** 整块毛玻璃的显现程度；首页有主题背景图时随列表滚动从 0 到 1，其余场景保持 1。 */
  @Prop reveal: number = 1;

  fadeProgress(): number {
    if (this.statusBarHeight <= 0) return 0;
    return Math.max(0, Math.min(1,
      1 - (this.backdropHeight - this.statusBarHeight) / CollapsingHeader.SCRIM_FADE_HEIGHT));
  }

  surfaceHeight(): number {
    return Math.max(0, this.backdropHeight) + this.fadeProgress() * CollapsingHeader.SCRIM_FADE_HEIGHT;
  }

  gradientColors(): Array<[ResourceColor, number]> {
    const total = this.surfaceHeight();
    if (total <= 0) return [['#00000000', 0], ['#00000000', 1]];
    const feather = Math.min(total, CollapsingHeader.SCRIM_FADE_HEIGHT);
    return [
      ['#FFFFFFFF', 0],
      ['#FFFFFFFF', (total - feather) / total],
      ['#80FFFFFF', (total - feather * 0.5) / total],
      ['#00FFFFFF', 1]
    ];
  }

  tintColor(): string {
    // 约三成主题色保留页面色调，其余由实际滚动内容的模糊采样透出。
    return `#55${this.backdropColor.substring(1)}`;
  }

  surfaceEffect(): BackgroundEffectOptions {
    if (!this.headerFrosted) {
      const plain: BackgroundEffectOptions = { radius: 0, saturation: 1, brightness: 1 };
      return plain;
    }
    const frosted: BackgroundEffectOptions = { radius: 32, saturation: 1.05, brightness: 1, color: this.tintColor() };
    return frosted;
  }

  build() {
    Row() {
      Row()
        .width('100%')
        .height('100%')
        .linearGradient({ direction: GradientDirection.Bottom, colors: this.gradientColors() })
        .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
    }
      .width('100%')
      .height(this.surfaceHeight())
      // 背景采样放在混合容器上，避免子节点从空的离屏画布采样。
      .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
      .backgroundEffect(this.surfaceEffect())
      // 渐变尾部只绘制，不能挡住其下方常驻光感栏的点击。
      .opacity(this.reveal)
      .hitTestBehavior(this.fadeProgress() > 0 ? HitTestMode.None : HitTestMode.Block)
      .accessibilityLevel('no')
  }
}
