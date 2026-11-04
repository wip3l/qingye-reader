import { FrameCallback } from '@kit.ArkUI';

/** 书架点开书时交给阅读页的封面外观与位置，只在进程内经 AppStorage 传递。 */
export interface ShelfOpeningCover {
  bookUrl: string;
  /** 空串表示没有封面，用纯色加首字代替。 */
  cover: ResourceStr;
  /** 主题书框，没有时为空串。 */
  frame: ResourceStr;
  color: string;
  initial: string;
  /** 书架封面在窗口里的位置与尺寸（vp），连同当时的窗口尺寸；宽或高为 0 表示没量到。 */
  boundsX: number;
  boundsY: number;
  boundsWidth: number;
  boundsHeight: number;
  windowWidth: number;
  windowHeight: number;
  /** 书架上这枚封面按 ImageFit.Cover 裁切显示（否则是拉伸铺满）。 */
  cropImage: boolean;
}

/** 整页缩到这枚封面时封面图要还原的裁切比例：书架裁切显示时为封面宽高比，拉伸铺满时为 0。 */
export function shelfCoverCropAspect(cover: ShelfOpeningCover | null): number {
  return cover && cover.cropImage && cover.boundsWidth > 0 && cover.boundsHeight > 0 ?
    cover.boundsWidth / cover.boundsHeight : 0;
}

export const SHELF_OPENING_COVER_KEY: string = 'shelfOpeningCover';

/** 翻开后的角度：转到侧面，同时横向缩成书脊，整个过程封面一直贴着书页左边。 */
export const SHELF_COVER_OPEN_ANGLE: number = -90;

/** 打开动画与返回共享转场的时长。 */
export const SHELF_COVER_OPEN_DURATION: number = 500;

export const SHELF_COVER_CLOSE_DURATION: number = 320;
export const SHELF_COVER_FRAME_RATE: ExpectedFrameRateRange = { min: 60, max: 120, expected: 120 };
/** 仅延后书架刷新，不拦截进度落库；时间戳自动过期，异常退出也不会锁住书架。 */
export const SHELF_BOOK_MOTION_UNTIL_KEY: string = 'shelfBookMotionUntil';
export const SHELF_BOOK_MOTION_SETTLE: number = 60;

/**
 * 自己缩回书架时要摘掉阅读页的共享转场 id。挂过 id 的节点再改成空串不会生效，返回时仍和书架封面配对，
 * 已缩到封面大小的整页又按自身缩放平移飞一次（落在封面坐标两倍处缩没），所以换成一个书架上不存在的 id。
 */
export function detachedShelfSharedCoverId(sharedCoverId: string): string {
  return sharedCoverId ? `${sharedCoverId}#detached` : '';
}

/** 阅读页首帧画好、主线程空下来才开始放大；一直忙也最多等这么久。 */
export const SHELF_COVER_OPEN_START_CAP: number = 250;

/** 下一帧渲染完且有空闲时回调，用来在阅读页首帧的重活过去之后再开始打开动画。 */
export class ShelfOpeningIdleStarter extends FrameCallback {
  private start: () => void;

  constructor(start: () => void) {
    super();
    this.start = start;
  }

  onIdle(_timeLeftInNano: number): void {
    this.start();
  }
}

/**
 * 叠在阅读页最上层的封面。打开时阅读页整页从书架封面的位置放大（只做缩放，不重新排版），
 * 这一层同时沿左侧书脊翻开，翻开的过程中就能看到下面的正文；返回时先合上，再由共享转场缩回书架。
 */
@Component
export struct ReaderShelfCoverOpening {
  @Prop angle: number = 0;
  @Prop shade: number = 0;
  /** 横向缩放，以书脊为轴：和转角一起收到 0，翻开时不必再淡出。 */
  @Prop scaleX: number = 1;
  /**
   * 打开时整页按封面比例非等比缩放，封面图拉伸铺满，缩放后正好还原书架上的样子；
   * 返回时整页是满屏，改用裁切铺满，避免封面被拉长。
   */
  @Prop fillImage: boolean = false;
  /**
   * 书框是 SVG，返回的共享转场里不跟着整页缩放，而是按书架封面的目标尺寸画在左上角，飞行全程多出一个小框。
   * 合上后、缩回书架前隐藏，到书架上由格子自己的书框接上。
   */
  @Prop showFrame: boolean = true;
  /**
   * 书架封面裁切显示时它的宽高比（见 shelfCoverCropAspect）。整页按封面比例非等比缩放，图若只是拉伸铺满，
   * 缩到格子里是整张图被压扁，和书架上裁掉两边的样子不一样，落地一换成书架就跳一下；这时把图按缩放前的
   * 坐标放大到“缩放后正好是裁切铺满”，超出部分裁掉。
   */
  @Prop cropAspect: number = 0;
  @State imageAspect: number = 0;
  cover: ShelfOpeningCover = {
    bookUrl: '', cover: '', frame: '', color: '#007DFF', initial: '书',
    boundsX: 0, boundsY: 0, boundsWidth: 0, boundsHeight: 0, windowWidth: 0, windowHeight: 0, cropImage: false
  };

  /** 图宽高比与封面宽高比之比，大于 1 时图比封面宽、左右裁掉，小于 1 时上下裁掉；不需要裁切时为 1。 */
  croppedImageRatio(): number {
    if (!this.fillImage || this.cropAspect <= 0 || this.imageAspect <= 0) return 1;
    return this.imageAspect / this.cropAspect;
  }

  build() {
    Stack() {
      if (this.cover.cover) {
        Image(this.cover.cover)
          .width('100%')
          .height('100%')
          .objectFit(this.fillImage ? ImageFit.Fill : ImageFit.Cover)
          .scale({ x: Math.max(1, this.croppedImageRatio()), y: Math.max(1, 1 / this.croppedImageRatio()) })
          // 同步解码：异步加载时首帧只有底色，书架格子上会先闪一块纯色再出封面。封面是本地缓存文件，解码落在首帧建页面的时间里。
          .syncLoad(true)
          .draggable(false)
          .onComplete((event) => {
            if (event && event.width > 0 && event.height > 0) this.imageAspect = event.width / event.height;
          })
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
          .syncLoad(true)
          .draggable(false)
          .visibility(this.showFrame ? Visibility.Visible : Visibility.Hidden)
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
    .clip(true)
    .backgroundColor(this.cover.color)
    // 用系统默认视距：真机上自定义视距几乎看不出透视，默认值下外边缘转向眼前时明显变高。
    .rotate({ x: 0, y: 1, z: 0, angle: this.angle, centerX: 0, centerY: '50%' })
    .scale({ x: this.scaleX, y: 1, centerX: 0, centerY: '50%' })
    .hitTestBehavior(HitTestMode.Block)
  }
}
