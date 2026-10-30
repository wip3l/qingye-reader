import display from '@ohos.display';

/** 书架点开书时交给阅读页的封面外观，只在进程内经 AppStorage 传递。 */
export interface ShelfOpeningCover {
  bookUrl: string;
  /** 空串表示没有封面，用纯色加首字代替。 */
  cover: ResourceStr;
  /** 主题书框，没有时为空串。 */
  frame: ResourceStr;
  color: string;
  initial: string;
}

export const SHELF_OPENING_COVER_KEY: string = 'shelfOpeningCover';

/** 翻开后的角度：越过 90° 一点，封面完全转到侧面后才移除。 */
export const SHELF_COVER_OPEN_ANGLE: number = -118;

/**
 * 叠在阅读页最上层的封面。阅读页整页是书架封面的共享元素，这一层随转场放大，
 * 然后沿左侧书脊翻开露出正文；返回时先合上，再随转场缩回书架。
 */
@Component
export struct ReaderShelfCoverOpening {
  @Prop angle: number = 0;
  @Prop shade: number = 0;
  cover: ShelfOpeningCover = { bookUrl: '', cover: '', frame: '', color: '#007DFF', initial: '书' };
  private perspective: number = ReaderShelfCoverOpening.defaultPerspective();

  /** 视距（px）取屏幕长边的 1.4 倍：竖屏透视柔和，横屏翻到侧面时右边缘也不会穿过视点。 */
  private static defaultPerspective(): number {
    try {
      const screen = display.getDefaultDisplaySync();
      return Math.max(screen.width, screen.height) * 1.4;
    } catch (_e) {
      return 3600;
    }
  }

  build() {
    Stack() {
      if (this.cover.cover) {
        Image(this.cover.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else {
        Column() {
          Text(this.cover.initial)
            .fontSize(96)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.cover.color)
      }
      if (this.cover.frame) {
        Image(this.cover.frame)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .draggable(false)
      }
      // 书脊的折痕阴影。
      Column()
        .width(18)
        .height('100%')
        .position({ x: 0, y: 0 })
        .linearGradient({ angle: 90, colors: [['#55000000', 0], ['#00000000', 1]] })
      // 转向侧面时背光变暗。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(this.shade)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.cover.color)
    .rotate({ x: 0, y: 1, z: 0, angle: this.angle, centerX: 0, centerY: '50%', perspective: this.perspective })
    .hitTestBehavior(HitTestMode.Block)
  }
}
