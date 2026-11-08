import { image } from '@kit.ImageKit';
import { AnimatorResult } from '@kit.ArkUI';
import { ReaderHaptics } from '../../utils/ReaderHaptics';
import { ReaderInputKind } from '../../utils/ReaderInputScopes';
import { applyReaderTurnFrameRate } from '../../utils/ReaderTurnFrameRate';
import { ReaderPageTurnAnimation } from '../../core/reader/ReaderPageTurnAnimation';
import { ReaderPageCurlPainter } from '../ReaderPageCurlPainter';
import { ReaderEmulationFlipPainter, ReaderEmulationFlipRegion } from '../ReaderEmulationFlipPainter';

// 推页接缝阴影的宽度（vp），以及被压住那页在完全盖住时浅纱的不透明度；与正文阅读页、漫画翻页一致。
const PUSH_SHADOW_SIZE = 18;
const PUSH_SHADE_MAX_OPACITY = 0.45;
// 与普通阅读页相同的手势参数（ReadBook 的 readerTapSlop / readerPageTurn*）：移动 12vp 才算拖动，横向位移大于
// 竖向的 0.8 倍算翻页；慢拖到页宽 10%、快甩（≥800vp/s）到 3% 即提交，两者都至少 18vp。
const TOUCH_SLOP = 12;
const DIRECTION_RATIO = 0.8;
const COMMIT_RATIO = 0.1;
const FLICK_RATIO = 0.03;
const FLICK_VELOCITY = 800;
const COMMIT_MIN_DISTANCE = 18;
/** 目标页截图和起点一模一样（网页还没按新位置出帧）时，隔这么久重截，最多这么多次。 */
const STALE_RETRY_MS = 50;
// 重截上限。之前查明截图其实都是新帧，这只是保险；内容稀疏的页（大片空白、只有表格框）两页指纹本来就一样，
// 上限大了每次翻页都要白截好几轮（真机一次 40ms 回读加主线程读像素，累计近一秒）。
const STALE_RETRY_LIMIT = 2;
const PLACEHOLDER_SIZE = 32;

/**
 * 翻页层向页面要的几件事。页面负责截图、把底下的内容换页，翻页层只管两张图之间的动画。
 */
export class ReaderSnapshotTurnHost {
  /** 按 scale 截下当前显示的整页（含页眉页脚）；失败返回 null，本次翻页不播动画。 */
  capture: (scale: number) => Promise<image.PixelMap | null> = (_scale: number) => Promise.resolve(null);
  /** 当前页的渲染身份：相同就能直接用上次留下的截图当翻页起点。 */
  textureKey: () => string = () => '';
  /** 把底下的内容换到 direction 方向的下一页并等它画好；没有下一页或换不过去返回 false。 */
  advance: (direction: number) => Promise<boolean> = () => Promise.resolve(false);
  /** 取消翻页：把底下的内容换回 advance 之前那一页。 */
  revert: (direction: number) => Promise<void> = () => Promise.resolve();
  /** 翻页完成。 */
  committed: (direction: number) => void = () => {};
  /** 翻页开始 / 结束；开始后页面不能再改动底下的内容（预载换槽位之类）。 */
  activeChanged: (active: boolean) => void = () => {};
}

/** 页面向翻页层发的指令；组件挂载时填入实现。 */
export class ReaderSnapshotTurnController {
  /** 转发正文区域收到的触摸事件（不拦截，网页照常收到点按、链接与长按）。 */
  touch: (event: TouchEvent) => void = () => {};
  /** 点按翻页、按键翻页：1 下一页，-1 上一页。quiet：朗读跟随这类不是用户发起的翻页，不震动。 */
  turn: (direction: number, quiet?: boolean) => void = () => {};
  /** 空闲时预先截好当前页，下一次翻页起步不用等截图。 */
  prewarm: () => void = () => {};
  /** 版式、深浅之类变了：丢掉留着的截图。 */
  invalidate: () => void = () => {};
  busy: () => boolean = () => false;
}

/**
 * 截图翻页层：给自己不能分页绘制的内容（文件排版的网页）播放与应用排版相同的翻页动画。
 * 一次翻页：拿当前页截图盖住内容 → 页面把底下换到目标页 → 再截一张 → 两张图之间按所选动画跟手或自动翻过去；
 * 翻完撤掉遮盖时底下已经是目标页，取消时页面先换回原页再撤。仿真、3D 仿真用阅读页同一套卷页绘制器。
 * 本层不接收触摸（HitTestMode.None），手势由页面从正文区域转发进来。
 */
@Component
export struct ReaderSnapshotPageTurn {
  host: ReaderSnapshotTurnHost = new ReaderSnapshotTurnHost();
  controller: ReaderSnapshotTurnController = new ReaderSnapshotTurnController();
  /** 翻页震感按哪类阅读生效：PDF 页传 PDF，EPUB 原版排版算小说。 */
  hapticsKind: number = ReaderInputKind.NOVEL;
  @Prop @Watch('onAnimationTypeChanged') animationType: number = ReaderPageTurnAnimation.SLIDE;
  @Prop viewWidth: number = 0;
  @Prop viewHeight: number = 0;
  @Prop darkMode: boolean = false;
  /** 卷页背面与空白处的纸色，必须不透明。 */
  @Prop paperColor: string = '#FFFFFF';
  @State private active: boolean = false;
  @State private frontMap: image.PixelMap | null = null;
  @State private backMap: image.PixelMap | null = null;
  @State private backReady: boolean = false;
  @State @Watch('drawCurl') private turnOffset: number = 0;
  @State private turnDirection: number = 0;
  private curlContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private curlPainter: ReaderPageCurlPainter = new ReaderPageCurlPainter();
  private emulationPainter: ReaderEmulationFlipPainter = new ReaderEmulationFlipPainter();
  private curlRegion: number = ReaderEmulationFlipRegion.BOTTOM;
  private canvasReady: boolean = false;
  /** idle → preparing（截图、换页）→ ready（可以跟手）→ animating → finishing（取消后等换回）→ idle。 */
  private phase: string = 'idle';
  private serial: number = 0;
  /** 截图还没好时手指已经松开：1 翻过去，-1 退回，0 还没决定。 */
  private release: number = 0;
  private queued: number = 0;
  /** 这一次翻页不震动（朗读跟随翻页）；回到空闲时清掉。 */
  private quiet: boolean = false;
  private frontKey: string = '';
  private backKey: string = '';
  private cacheMap: image.PixelMap | null = null;
  private cacheKey: string = '';
  private prewarming: boolean = false;
  private animator: AnimatorResult | null = null;
  private animationWatchdog: number = -1;
  private tracking: boolean = false;
  private decided: boolean = false;
  /** 这次滑动开始时上一页还没翻完：不跟手，松手时判断成翻页就排队。 */
  private dragDeferred: boolean = false;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private touchStartTime: number = 0;
  /** 本次拖动的方向；无动画时拖动只记方向，松手才决定翻不翻。 */
  private dragDirection: number = 0;
  /** 最近的触摸采样，用来算松手时的速度。 */
  private sampleX: number = 0;
  private sampleTime: number = 0;
  private lastX: number = 0;
  private lastTime: number = 0;
  /**
   * 跟手拖动时目标页还没截好，先拿一张纸色的图顶上，动画立刻跟着手指走；底下换页、截图在后台进行，
   * 截好再换成真页面。pendingAdvance 是这次后台换页，结果为底下是否真的换了页。
   */
  private pendingAdvance: Promise<boolean> | null = null;
  private placeholderMap: image.PixelMap | null = null;
  private placeholderKey: string = '';
  private backIsPlaceholder: boolean = false;
  /** 这次翻页的纸色：从起点截图的左右页边取样（书页可能是黑底），取不到用 paperColor。 */
  private turnPaper: string = '';

  aboutToAppear(): void {
    this.controller.touch = (event: TouchEvent): void => this.handleTouch(event);
    this.controller.turn = (direction: number, quiet?: boolean): void => this.turn(direction, quiet === true);
    this.controller.prewarm = (): void => { this.prewarm(); };
    this.controller.invalidate = (): void => this.dropCache();
    this.controller.busy = (): boolean => this.phase !== 'idle';
  }

  aboutToDisappear(): void {
    this.serial++;
    this.cancelAnimator();
    this.releaseLater(this.frontMap);
    this.releaseLater(this.backMap);
    this.frontMap = null;
    this.backMap = null;
    this.dropCache();
    const placeholder = this.placeholderMap;
    this.placeholderMap = null;
    if (placeholder) setTimeout((): void => { placeholder.release().catch((): void => {}); }, 64);
    this.controller.touch = () => {};
    this.controller.turn = () => {};
    this.controller.prewarm = () => {};
    this.controller.invalidate = () => {};
    this.controller.busy = () => false;
  }

  onAnimationTypeChanged(): void {
    if (this.phase !== 'idle') return;
    this.emulationPainter.clearCorner();
    // 截图比例随动画类型变，留着的起点截图尺寸不对了。
    this.dropCache();
  }

  private viewW(): number {
    return Math.max(1, this.viewWidth);
  }

  private viewH(): number {
    return Math.max(1, this.viewHeight);
  }

  private usesCurl(): boolean {
    return this.animationType === ReaderPageTurnAnimation.SIMULATION ||
      this.animationType === ReaderPageTurnAnimation.THREE_D;
  }

  private progress(): number {
    return Math.min(1, Math.abs(this.turnOffset) / this.viewW());
  }

  // ---- 截图缓存：翻完一页时目标页的截图留下来，下一次翻页直接用作起点 ----

  private releaseLater(map: image.PixelMap | null): void {
    if (!map || map === this.placeholderMap) return;
    // 图片组件 / Canvas 的最后一帧提交到渲染线程后再释放。
    setTimeout((): void => { map.release().catch((): void => {}); }, 64);
  }

  private dropCache(): void {
    const map = this.cacheMap;
    this.cacheMap = null;
    this.cacheKey = '';
    this.releaseLater(map);
  }

  private keep(map: image.PixelMap, key: string): void {
    if (this.cacheMap && this.cacheMap !== map) this.releaseLater(this.cacheMap);
    this.cacheMap = map;
    this.cacheKey = key;
  }

  /** 取出与当前页相符的缓存截图（所有权交给调用方）；不符就丢掉。 */
  private takeCache(key: string): image.PixelMap | null {
    if (!this.cacheMap) return null;
    if (key && this.cacheKey === key) {
      const map = this.cacheMap;
      this.cacheMap = null;
      this.cacheKey = '';
      return map;
    }
    this.dropCache();
    return null;
  }

  private async captureSafe(): Promise<image.PixelMap | null> {
    try {
      return await this.host.capture(ReaderPageTurnAnimation.snapshotScale(this.animationType));
    } catch (error) {
      console.warn('[SnapshotTurn] capture failed:', error);
      return null;
    }
  }

  private async prewarm(): Promise<void> {
    if (this.phase !== 'idle' || this.prewarming ||
      this.animationType === ReaderPageTurnAnimation.NONE) return;
    const key = this.host.textureKey();
    if (!key || (this.cacheMap && this.cacheKey === key)) return;
    this.prewarming = true;
    const map = await this.captureSafe();
    this.prewarming = false;
    if (!map) return;
    // 截图期间翻了页或内容变了，这张就不能用了。
    if (this.phase !== 'idle' || this.host.textureKey() !== key) {
      this.releaseLater(map);
      return;
    }
    this.keep(map, key);
  }

  /**
   * 页面正文区域（去掉上下各 18%，避开页眉页脚里会变的页码）的三条竖向采样做个指纹，
   * 用来判断目标页截图是不是还停在旧页。
   */
  private async signature(map: image.PixelMap): Promise<number> {
    const info = await map.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    const top = Math.floor(height * 0.18);
    const rows = Math.max(1, Math.floor(height * 0.64));
    const stripe = 2;
    // 六条竖线并行读：只取三条时稀疏页容易全落在空白处，被误判成“还是旧页”。
    const areas: image.PositionArea[] = [0.12, 0.27, 0.42, 0.57, 0.72, 0.87].map((fraction: number) => {
      const area: image.PositionArea = {
        pixels: new ArrayBuffer(stripe * rows * 4),
        offset: 0,
        stride: stripe * 4,
        region: { size: { width: stripe, height: rows }, x: Math.min(width - stripe, Math.floor(width * fraction)), y: top }
      };
      return area;
    });
    await Promise.all(areas.map((area: image.PositionArea): Promise<void> => map.readPixels(area)));
    let hash = 2166136261;
    for (const area of areas) {
      const bytes = new Uint8Array(area.pixels);
      for (let i = 0; i < bytes.length; i += 4) {
        hash = Math.imul(hash ^ (bytes[i] | (bytes[i + 1] << 8) | (bytes[i + 2] << 16)), 16777619);
      }
    }
    return hash >>> 0;
  }

  /** 截目标页；和起点一模一样就说明网页还没出新帧，稍等重截。真的两页相同（空白页）时最后照用。 */
  private async captureFresh(front: image.PixelMap, serial: number): Promise<image.PixelMap | null> {
    const started = Date.now();
    let frontSignature = -1;
    try {
      frontSignature = await this.signature(front);
    } catch (error) {
      console.warn('[SnapshotTurn] signature failed:', error);
    }
    let back = await this.captureSafe();
    let tries = 0;
    while (back && frontSignature >= 0 && tries < STALE_RETRY_LIMIT && serial === this.serial) {
      let same = false;
      try {
        same = (await this.signature(back)) === frontSignature;
      } catch (_) {
        same = false;
      }
      if (!same) break;
      tries++;
      this.releaseLater(back);
      await new Promise<void>((resolve) => setTimeout(resolve, STALE_RETRY_MS));
      if (serial !== this.serial) return null;
      back = await this.captureSafe();
    }
    console.info(`[SnapshotTurn] target captured in ${Date.now() - started}ms, stale retries=${tries}`);
    return back;
  }

  /**
   * 纸色占位图，按纸色缓存；DMA 分配（交给 Canvas 反复绘制的图用堆内存会让 RS 泄漏显存）。
   * 纯色图拉伸后还是纯色，只做 32×32：以前按整屏像素逐个在 JS 里填，真机上第一次跟手拖动主线程卡 260ms。
   */
  private placeholder(): image.PixelMap | null {
    const width = PLACEHOLDER_SIZE;
    const height = PLACEHOLDER_SIZE;
    const paper = this.effectivePaper();
    const key = paper;
    if (this.placeholderMap && this.placeholderKey === key) return this.placeholderMap;
    const hex = (paper || '#FFFFFF').replace('#', '');
    const rgb = hex.length >= 6 ? hex.substring(hex.length - 6) : 'FFFFFF';
    const r = Number.parseInt(rgb.substring(0, 2), 16) || 0;
    const g = Number.parseInt(rgb.substring(2, 4), 16) || 0;
    const b = Number.parseInt(rgb.substring(4, 6), 16) || 0;
    const bytes = new Uint8Array(width * height * 4);
    // 小端序下一个 uint32 依次是 B、G、R、A 四个字节。
    new Uint32Array(bytes.buffer).fill(((255 << 24) | (r << 16) | (g << 8) | b) >>> 0);
    const options: image.InitializationOptions = {
      size: { width: width, height: height }, srcPixelFormat: image.PixelMapFormat.BGRA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888, editable: false
    };
    let map: image.PixelMap | null = null;
    try {
      map = image.createPixelMapUsingAllocatorSync(bytes.buffer, options, image.AllocatorType.DMA);
    } catch (_) {
      try {
        map = image.createPixelMapSync(bytes.buffer, options);
      } catch (error) {
        console.warn('[SnapshotTurn] placeholder failed:', error);
      }
    }
    const old = this.placeholderMap;
    this.placeholderMap = map;
    this.placeholderKey = map ? key : '';
    if (old) setTimeout((): void => { old.release().catch((): void => {}); }, 64);
    return map;
  }

  private effectivePaper(): string {
    return this.turnPaper || this.paperColor;
  }

  /**
   * 页面底色：在左右页边、上中下三处各取一小块，按亮度取中位数。页边一般只有书页背景，
   * 避开了页眉页脚和正文；黑底的书拿到的就是黑色，占位和卷起的纸背不会白得刺眼。
   */
  private async samplePaper(map: image.PixelMap): Promise<string> {
    try {
      const info = await map.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (width < 8 || height < 8) return '';
      const colors: number[][] = [];
      for (const fx of [0.015, 0.985]) {
        for (const fy of [0.3, 0.5, 0.7]) {
          const area: image.PositionArea = {
            pixels: new ArrayBuffer(4 * 4 * 4), offset: 0, stride: 4 * 4,
            region: { size: { width: 4, height: 4 }, x: Math.min(width - 4, Math.max(0, Math.round(width * fx) - 2)),
              y: Math.min(height - 4, Math.round(height * fy)) }
          };
          await map.readPixels(area);
          const bytes = new Uint8Array(area.pixels);
          let r = 0;
          let g = 0;
          let b = 0;
          for (let i = 0; i < bytes.length; i += 4) {
            b += bytes[i]; g += bytes[i + 1]; r += bytes[i + 2];
          }
          const n = bytes.length / 4;
          colors.push([r / n, g / n, b / n]);
        }
      }
      colors.sort((a: number[], c: number[]): number =>
        (0.2126 * a[0] + 0.7152 * a[1] + 0.0722 * a[2]) - (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]));
      const mid = colors[Math.floor(colors.length / 2)];
      const hex = (value: number): string => Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2, '0');
      return `#${hex(mid[0])}${hex(mid[1])}${hex(mid[2])}`.toUpperCase();
    } catch (error) {
      console.warn('[SnapshotTurn] paper sample failed:', error);
      return '';
    }
  }

  /** 跟手拖动时在后台换页并截目标页；截好就把纸色占位换成真页面。 */
  private async advanceInBackground(direction: number, front: image.PixelMap, serial: number): Promise<boolean> {
    await this.nextFrame();
    if (serial !== this.serial) return false;
    const moved = await this.host.advance(direction);
    if (serial !== this.serial) return moved;
    if (!moved) {
      // 已经到头（或换不过去）：手指还在拖也直接退回。
      this.tracking = false;
      if (this.phase === 'ready') {
        this.emulationPainter.releaseCorner();
        this.settle(false);
      }
      return false;
    }
    const back = await this.captureFresh(front, serial);
    if (serial !== this.serial) {
      this.releaseLater(back);
      return true;
    }
    if (back) {
      this.backMap = back;
      this.backKey = this.host.textureKey();
      this.backIsPlaceholder = false;
      this.drawCurl();
    }
    return true;
  }

  private nextFrame(): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, 20));
  }

  // ---- 一次翻页 ----

  private turn(direction: number, quiet: boolean = false): void {
    if (direction === 0) return;
    if (this.phase !== 'idle') {
      // 动画进行中又点了一下：记下一页，当前这页翻完马上接着翻。
      this.queued = direction;
      return;
    }
    this.quiet = quiet;
    this.begin(direction);
    if (this.phase !== 'idle') this.release = 1;
  }

  private async begin(direction: number, dragging: boolean = false): Promise<void> {
    const serial = ++this.serial;
    this.phase = 'preparing';
    this.turnDirection = direction;
    this.turnOffset = 0;
    this.release = 0;
    this.backReady = false;
    this.pendingAdvance = null;
    this.backIsPlaceholder = false;
    this.host.activeChanged(true);
    if (this.animationType === ReaderPageTurnAnimation.NONE) {
      this.dropCache();
      const moved = await this.host.advance(direction);
      if (serial !== this.serial) return;
      if (moved) {
        if (!this.quiet) ReaderHaptics.pageTurned(this.hapticsKind, false);
        this.host.committed(direction);
      }
      this.reset();
      return;
    }
    this.frontKey = this.host.textureKey();
    let front = this.takeCache(this.frontKey);
    if (!front) front = await this.captureSafe();
    if (serial !== this.serial) {
      this.releaseLater(front);
      return;
    }
    if (!front) {
      // 截不到图：照常翻页，只是没有动画。
      const moved = await this.host.advance(direction);
      if (serial !== this.serial) return;
      if (moved) {
        if (!this.quiet) ReaderHaptics.pageTurned(this.hapticsKind, false);
        this.host.committed(direction);
      }
      this.reset();
      return;
    }
    this.turnPaper = await this.samplePaper(front);
    if (serial !== this.serial) {
      this.releaseLater(front);
      return;
    }
    this.frontMap = front;
    this.active = true;
    const placeholder = dragging ? this.placeholder() : null;
    if (placeholder) {
      // 跟手：纸色占位当目标页，立刻进入可拖动状态；换页与截图在后台。
      this.backMap = placeholder;
      this.backIsPlaceholder = true;
      this.backKey = '';
      this.phase = 'ready';
      this.backReady = true;
      this.drawCurl();
      this.pendingAdvance = this.advanceInBackground(direction, front, serial);
      if (this.release !== 0) this.settle(this.release > 0);
      return;
    }
    // 遮盖先画出来，再去动底下的内容，免得闪出目标页。
    await this.nextFrame();
    if (serial !== this.serial) return;
    const moved = await this.host.advance(direction);
    if (serial !== this.serial) return;
    if (!moved) {
      this.frontMap = null;
      this.active = false;
      this.keep(front, this.frontKey);
      this.reset();
      return;
    }
    const back = await this.captureFresh(front, serial);
    if (serial !== this.serial) {
      this.releaseLater(back);
      return;
    }
    if (!back) {
      if (!this.quiet) ReaderHaptics.pageTurned(this.hapticsKind, false);
      this.host.committed(direction);
      this.hide(null, '');
      return;
    }
    this.backMap = back;
    this.backKey = this.host.textureKey();
    this.phase = 'ready';
    this.backReady = true;
    this.drawCurl();
    if (this.release !== 0) {
      this.settle(this.release > 0);
    } else if (!this.decided && !this.tracking) {
      // 手势在截图期间被系统取消，又没有松手事件：退回。
      this.settle(false);
    }
  }

  private settle(complete: boolean): void {
    if (this.phase === 'preparing') {
      this.release = complete ? 1 : -1;
      return;
    }
    if (this.phase !== 'ready') return;
    this.phase = 'animating';
    // 松手确定翻过去（或点按、按键翻页截图就绪）时震，不等动画播完。
    if (complete && !this.quiet) ReaderHaptics.pageTurned(this.hapticsKind, false);
    const serial = this.serial;
    const target = complete ? -this.turnDirection * this.viewW() : 0;
    let duration = this.usesCurl() ? 320 : 240;
    let easing = 'ease-out';
    if (this.animationType === ReaderPageTurnAnimation.THREE_D) {
      if (!complete) {
        duration = Math.max(80, Math.min(180, Math.round(180 * this.progress())));
        easing = 'cubic-bezier(0.65, 0, 0.35, 1)';
      } else {
        const released = this.emulationPainter.flatRemainingFraction(this.viewW(), 0);
        const fraction = released >= 0 ? released : 1 - this.progress();
        duration = Math.max(180, Math.round(400 * Math.pow(Math.max(0, fraction), 0.6)));
        easing = 'cubic-bezier(0.3, 0.4, 0.7, 1)';
      }
    }
    const finish = (): void => {
      if (serial !== this.serial || this.phase !== 'animating') return;
      this.cancelAnimator();
      this.turnOffset = target;
      if (complete) this.finishCommit(serial); else this.finishCancel(serial);
    };
    if (Math.abs(this.turnOffset - target) < 0.5) {
      finish();
      return;
    }
    try {
      const animator = this.getUIContext().createAnimator({
        duration: duration, easing: easing, delay: 0, fill: 'forwards',
        direction: 'normal', iterations: 1, begin: this.turnOffset, end: target
      });
      this.animator = animator;
      applyReaderTurnFrameRate(animator);
      animator.onFrame = (value: number): void => {
        if (serial === this.serial) this.turnOffset = value;
      };
      animator.onFinish = finish;
      this.animationWatchdog = setTimeout(finish, duration + 120);
      animator.play();
    } catch (error) {
      console.warn('[SnapshotTurn] animation failed:', error);
      finish();
    }
  }

  private cancelAnimator(): void {
    clearTimeout(this.animationWatchdog);
    this.animationWatchdog = -1;
    const animator = this.animator;
    this.animator = null;
    if (animator) animator.cancel();
  }

  private async finishCommit(serial: number): Promise<void> {
    const advance = this.pendingAdvance;
    this.pendingAdvance = null;
    if (advance) {
      this.phase = 'finishing';
      const moved = await advance;
      if (serial !== this.serial) return;
      if (!moved) {
        const front = this.frontMap;
        this.frontMap = null;
        this.hide(front, this.frontKey);
        return;
      }
    }
    this.host.committed(this.turnDirection);
    const back = this.backIsPlaceholder ? null : this.backMap;
    this.backMap = null;
    this.hide(back, back ? this.backKey : '');
  }

  private async finishCancel(serial: number): Promise<void> {
    this.phase = 'finishing';
    this.queued = 0;
    const advance = this.pendingAdvance;
    this.pendingAdvance = null;
    const moved = advance ? await advance : true;
    if (serial !== this.serial) return;
    if (moved) await this.host.revert(this.turnDirection);
    if (serial !== this.serial) return;
    const front = this.frontMap;
    this.frontMap = null;
    this.hide(front, this.frontKey);
  }

  /** 撤掉遮盖；keepMap 是底下现在这页的截图，留作下一次翻页的起点。 */
  private hide(keepMap: image.PixelMap | null, keepKey: string): void {
    const front = this.frontMap;
    const back = this.backMap;
    this.frontMap = null;
    this.backMap = null;
    if (front && front !== keepMap) this.releaseLater(front);
    if (back && back !== keepMap) this.releaseLater(back);
    if (keepMap) {
      if (keepKey && keepKey === this.host.textureKey()) this.keep(keepMap, keepKey);
      else this.releaseLater(keepMap);
    }
    this.active = false;
    if (this.canvasReady) this.curlContext.clearRect(0, 0, this.viewW(), this.viewH());
    this.reset();
  }

  private reset(): void {
    this.cancelAnimator();
    this.phase = 'idle';
    this.quiet = false;
    this.backReady = false;
    this.turnOffset = 0;
    this.turnDirection = 0;
    this.release = 0;
    this.backIsPlaceholder = false;
    this.pendingAdvance = null;
    this.emulationPainter.clearCorner();
    this.curlRegion = ReaderEmulationFlipRegion.BOTTOM;
    this.host.activeChanged(false);
    const queued = this.queued;
    this.queued = 0;
    if (queued !== 0) setTimeout((): void => this.turn(queued), 0);
  }

  // ---- 手势：页面转发的触摸事件，横向拖动跟手，竖向交给网页 ----

  private handleTouch(event: TouchEvent): void {
    const touches = event.touches && event.touches.length > 0 ? event.touches : event.changedTouches;
    const point = touches && touches.length > 0 ? touches[0] : undefined;
    if (event.type === TouchType.Down) {
      // 上一页还在翻（动画、换页或截图）时也要跟踪这次滑动，松手后排队接着翻；以前直接忽略，快速连滑会丢页。
      this.tracking = !!point && event.touches.length <= 1;
      this.decided = false;
      this.dragDeferred = false;
      if (point) {
        this.touchStartX = point.x;
        this.touchStartY = point.y;
      }
      this.touchStartTime = Date.now();
      this.sampleX = this.lastX = point ? point.x : 0;
      this.sampleTime = this.lastTime = this.touchStartTime;
      return;
    }
    if (!point) return;
    if (event.type === TouchType.Move) {
      const now = Date.now();
      // 速度取最近约 40ms 的位移，松手前停顿过就不算甩。
      if (now - this.lastTime > 40) {
        this.sampleX = this.lastX;
        this.sampleTime = this.lastTime;
      }
      this.lastX = point.x;
      this.lastTime = now;
      if (event.touches.length > 1) {
        if (this.decided) this.endDrag(false);
        this.tracking = false;
        return;
      }
      if (!this.tracking) return;
      const dx = point.x - this.touchStartX;
      const dy = point.y - this.touchStartY;
      if (!this.decided) {
        if (Math.abs(dx) < TOUCH_SLOP && Math.abs(dy) < TOUCH_SLOP) return;
        if (Math.abs(dx) <= Math.abs(dy) * DIRECTION_RATIO) {
          this.tracking = false;
          return;
        }
        this.decided = true;
        const direction = dx < 0 ? 1 : -1;
        this.dragDirection = direction;
        if (this.phase !== 'idle') {
          // 不跟手，只在松手时按同样的距离/速度判断是否翻页，交给 turn() 排队。
          this.dragDeferred = true;
          return;
        }
        if (this.animationType === ReaderPageTurnAnimation.NONE) return;
        if (this.animationType === ReaderPageTurnAnimation.THREE_D) {
          this.emulationPainter.clearCorner();
          const y = this.touchStartY;
          this.curlRegion = y < this.viewH() / 3 ? ReaderEmulationFlipRegion.TOP :
            (y > this.viewH() * 2 / 3 ? ReaderEmulationFlipRegion.BOTTOM : ReaderEmulationFlipRegion.MIDDLE);
        }
        this.begin(direction, true);
      }
      if (this.dragDeferred || (this.phase !== 'preparing' && this.phase !== 'ready')) return;
      if (this.animationType === ReaderPageTurnAnimation.THREE_D) this.emulationPainter.dragCorner(point.x, point.y);
      // 方向在起步时定下；往回拖只退到起点，不会变成反方向翻页。
      this.turnOffset = this.turnDirection > 0 ? Math.max(-this.viewW(), Math.min(0, dx)) :
        Math.min(this.viewW(), Math.max(0, dx));
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.decided) {
        const dx = point.x - this.touchStartX;
        const now = Date.now();
        const elapsed = Math.max(1, now - this.sampleTime);
        const velocity = now - this.lastTime > 80 ? 0 : (point.x - this.sampleX) / elapsed * 1000;
        const forward = this.dragDirection > 0 ? dx < 0 : dx > 0;
        const flickForward = this.dragDirection > 0 ? velocity < 0 : velocity > 0;
        const distance = Math.abs(dx);
        const commitDistance = Math.max(COMMIT_MIN_DISTANCE, this.viewW() * COMMIT_RATIO);
        const flickDistance = Math.max(COMMIT_MIN_DISTANCE, this.viewW() * FLICK_RATIO);
        const complete = event.type === TouchType.Up && forward && (distance >= commitDistance ||
          (flickForward && Math.abs(velocity) >= FLICK_VELOCITY && distance >= flickDistance));
        if (this.dragDeferred || this.animationType === ReaderPageTurnAnimation.NONE) {
          if (complete) this.turn(this.dragDirection);
        } else {
          this.endDrag(complete);
        }
      }
      this.tracking = false;
      this.decided = false;
      this.dragDeferred = false;
    }
  }

  private endDrag(complete: boolean): void {
    this.emulationPainter.releaseCorner();
    this.settle(complete);
  }

  // ---- 画面 ----

  private drawCurl(): void {
    if (!this.canvasReady || !this.backReady || !this.usesCurl() || !this.frontMap || !this.backMap) return;
    if (this.animationType === ReaderPageTurnAnimation.THREE_D) {
      this.emulationPainter.draw(this.curlContext, this.frontMap, this.backMap, this.viewW(), this.viewH(),
        this.progress(), this.turnDirection, this.curlRegion, false, this.viewW() / 2, this.viewW() / 2,
        1 / this.getUIContext().vp2px(1), this.effectivePaper(), this.darkMode);
    } else {
      this.curlPainter.draw(this.curlContext, this.frontMap, this.backMap, this.viewW(), this.viewH(),
        this.progress(), this.turnDirection, false, this.darkMode, 0, 0, this.effectivePaper());
    }
  }

  // 两张截图（起点、目标页）的摆放。@Builder 只收一个固定的布尔参数，位置、透明度都在里面读状态：
  // 按值传进去的数值不会随状态刷新，拖动时截图会停在起始位置不动。

  private sheetMap(back: boolean): image.PixelMap | null {
    return back ? this.backMap : this.frontMap;
  }

  /**
   * 目标页截好之前只显示起点。卷页时绘制器只画翻动的那张纸、掀开处留空，下面必须垫目标页
   * （与正文阅读页、漫画翻页相同）；垫起点的话掀开处露出的还是当前页的字。
   */
  private sheetVisible(back: boolean): boolean {
    if (!this.active || !this.frontMap) return false;
    if (back) return this.backReady && !!this.backMap;
    return !this.backReady || !this.usesCurl();
  }

  /** 平移、推页时起点跟着手指走；叠页、淡入时起点不动。目标页从翻页方向那一侧移进来，淡入原地。 */
  private sheetX(back: boolean): number {
    if (!this.backReady || this.usesCurl()) return 0;
    if (back) {
      return this.animationType === ReaderPageTurnAnimation.FADE ? 0 :
        this.turnOffset + this.turnDirection * this.viewW();
    }
    return this.animationType === ReaderPageTurnAnimation.SLIDE ||
      this.animationType === ReaderPageTurnAnimation.PUSH ? this.turnOffset : 0;
  }

  private sheetOpacity(back: boolean): number {
    return back && this.animationType === ReaderPageTurnAnimation.FADE ? this.progress() : 1;
  }

  /** 推页、平移时屏幕右侧那页压在上面；叠页、淡入时目标页在上面。 */
  private sheetZ(back: boolean): number {
    const backOnTop = this.animationType === ReaderPageTurnAnimation.PUSH ||
      this.animationType === ReaderPageTurnAnimation.SLIDE ? this.turnDirection > 0 : true;
    return back === backOnTop ? 1 : 0;
  }

  /** 推页：左侧那页随被盖住的比例蒙一层纱，右侧那页在左边缘向外投阴影。 */
  @Builder
  pushShade(back: boolean) {
    if (this.sheetX(back) < 0) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.darkMode ? Color.Black : Color.White)
        .opacity(PUSH_SHADE_MAX_OPACITY * Math.min(1, -this.sheetX(back) / this.viewW()))
        .hitTestBehavior(HitTestMode.None)
    } else if (this.sheetX(back) > 0) {
      Column()
        .width(PUSH_SHADOW_SIZE)
        .height('100%')
        .position({ x: -PUSH_SHADOW_SIZE, y: 0 })
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [['#00000000', 0], [this.darkMode ? '#66000000' : '#2E000000', 1]]
        })
        .opacity(Math.min(1, (this.viewW() - this.sheetX(back)) / PUSH_SHADOW_SIZE))
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  sheet(back: boolean) {
    Stack() {
      if (this.sheetMap(back)) {
        Image(this.sheetMap(back) as image.PixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .draggable(false)
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.animationType === ReaderPageTurnAnimation.PUSH && this.backReady) {
        this.pushShade(back)
      }
    }
    .width(this.viewW())
    .height(this.viewH())
    .position({ x: this.sheetX(back), y: 0 })
    .opacity(this.sheetOpacity(back))
    .zIndex(this.sheetZ(back))
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.sheetVisible(false)) {
        this.sheet(false)
      }
      if (this.sheetVisible(true)) {
        this.sheet(true)
      }
      if (this.usesCurl()) {
        Canvas(this.curlContext)
          .width(this.viewW())
          .height(this.viewH())
          .position({ x: 0, y: 0 })
          .opacity(this.active && this.backReady ? 1 : 0)
          .zIndex(2)
          // 父级的 HitTestMode.None 管不到子节点：这块常驻的全屏 Canvas 自己也要放行，否则挡住网页的点按和拖动。
          .hitTestBehavior(HitTestMode.None)
          .onReady((): void => {
            this.canvasReady = true;
            this.drawCurl();
          })
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }
}
