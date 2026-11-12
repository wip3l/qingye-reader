import { common } from '@kit.AbilityKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import image from '@ohos.multimedia.image';

/** 揭开动画时长：从按钮处扩到铺满整屏。 */
export const READER_THEME_REVEAL_DURATION: number = 460;

class RevealFrameCallback extends FrameCallback {
  private notify: () => void;
  constructor(notify: () => void) { super(); this.notify = notify; }
  onFrame(_frameTimeInNano: number): void { this.notify(); }
}

/**
 * 日夜切换的揭开层。
 *
 * 切换深浅色要走 setColorMode，ArkUI 会把整棵组件树（连同栈里的首页）重建一遍、主线程卡住两百多毫秒，
 * 之后还有 400ms 的系统颜色过渡；阅读页还要按新配色重新分页，期间会先露出一帧没有排版的纯文本。
 * 所以切换前先把窗口截下来盖在最上面，底下的重建、重排都在截图后面完成，等画面稳定后，
 * 从点按的位置挖一个不断扩大的圆洞，把新配色一次揭开。洞是截图上的 DST_OUT 圆，只改缩放，由渲染服务驱动。
 */
@Component
export struct ReaderThemeReveal {
  snapshot: image.PixelMap | null = null;
  /** 圆心（vp，相对本层左上角）。 */
  centerX: number = 0;
  centerY: number = 0;
  /** 圆洞铺满整层时的直径（vp）。 */
  diameter: number = 0;
  @Prop progress: number = 0;

  build() {
    Stack() {
      if (this.snapshot) {
        Image(this.snapshot)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .draggable(false)
      }
      Circle()
        .width(this.diameter)
        .height(this.diameter)
        .fill(Color.Black)
        .position({ x: this.centerX - this.diameter / 2, y: this.centerY - this.diameter / 2 })
        .scale({ x: Math.max(0.001, this.progress), y: Math.max(0.001, this.progress) })
        .blendMode(BlendMode.DST_OUT, BlendApplyType.OFFSCREEN)
    }
    .width('100%')
    .height('100%')
    .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
    // 截图下面是还在重建的旧画面，揭开结束前不接收点按。
    .hitTestBehavior(HitTestMode.Block)
  }
}

export class ReaderThemeRevealHelper {
  /** 同步截下当前窗口；不支持或失败时返回 null，调用方直接切换、不做动画。 */
  static capture(context: common.UIAbilityContext): image.PixelMap | null {
    try {
      return context.windowStage.getMainWindowSync().snapshotSync();
    } catch (e) {
      console.warn('日夜切换截图失败:', JSON.stringify(e));
      return null;
    }
  }

  /** 圆心到最远一角的距离再留一点余量，保证扩到最后整层都被挖空。 */
  static coverDiameter(centerX: number, centerY: number, width: number, height: number): number {
    const dx = Math.max(centerX, width - centerX);
    const dy = Math.max(centerY, height - centerY);
    return Math.ceil(Math.sqrt(dx * dx + dy * dy) * 2) + 8;
  }

  /**
   * 下一帧开始时返回。量的是帧节奏，所以用 onFrame：系统颜色过渡期间每帧都排满，onIdle 根本不会来。
   */
  private static nextFrame(uiContext: UIContext, timeoutMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      let done = false;
      let timer = -1;
      const finish = (): void => {
        if (done) return;
        done = true;
        if (timer >= 0) clearTimeout(timer);
        resolve();
      };
      timer = setTimeout(finish, timeoutMs);
      try {
        uiContext.postFrameCallback(new RevealFrameCallback(finish));
      } catch (_) {
        finish();
      }
    });
  }

  /**
   * 等底下的画面稳定：页面自己判断已就绪（重排完成等），并且连续两帧间隔都不长（配置更新引起的整树重建已经过去）。
   * 配置更新是异步送达的，刚切换的头几帧可能还在它之前，所以没见过一次长帧时至少等 250ms。
   * 最长等 maxWaitMs，超时也照样揭开，免得一直盖着。
   */
  static async waitSettled(uiContext: UIContext, isReady: () => boolean, maxWaitMs: number = 1500): Promise<void> {
    const startedAt = Date.now();
    const deadline = startedAt + maxWaitMs;
    let quickFrames = 0;
    let sawLongFrame = false;
    let last = startedAt;
    while (Date.now() < deadline) {
      await ReaderThemeRevealHelper.nextFrame(uiContext, 100);
      const now = Date.now();
      if (now - last <= 40) {
        quickFrames++;
      } else {
        quickFrames = 0;
        sawLongFrame = true;
      }
      last = now;
      if (quickFrames >= 2 && (sawLongFrame || now - startedAt >= 250) && isReady()) return;
    }
  }
}
