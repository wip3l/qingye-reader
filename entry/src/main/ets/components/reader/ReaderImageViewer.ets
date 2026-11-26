import { curves } from '@kit.ArkUI';
import { AppFontSize } from '../../theme/AppFontSize';
import { firstGestureFinger } from '../../utils/GestureFingers';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';

/**
 * 正文插图的全屏查看（纸面浮层）：背后是模糊、压暗的正文，插图从它在页面上的位置放大浮起，四周留白。
 * 双指缩放（最大 4 倍）、双击在点按处放大 2.5 倍再双击还原、放大后拖动看细节；未放大时往下拖松手关闭、
 * 点图外空白处关闭，关闭时图缩回原位。单击图片隐藏或显示底部按钮。只看点开的这一张。
 *
 * 由阅读页挂在最上层（铺满窗口，坐标与窗口一致），关闭动画播完后调 onClose 由阅读页卸载。
 * 保存、分享由阅读页处理（需要 UIAbilityContext 与原图路径）。
 */
@Component
export struct ReaderImageViewer {
  private static readonly SIDE: number = 22;
  private static readonly MAX_SCALE: number = 4;
  private static readonly DOUBLE_TAP_SCALE: number = 2.5;
  private static readonly DISMISS_DISTANCE: number = 110;
  private static readonly BAR_WIDTH: number = 252;
  private static readonly BAR_HEIGHT: number = 44;

  /** Image 能加载的地址（file:// 或网址）。 */
  @Prop src: string = '';
  @Prop caption: string = '';
  /** 插图在页面上实际画出的位置（窗口坐标，vp）；宽或高为 0 时从屏幕中央淡入。 */
  @Prop fromX: number = 0;
  @Prop fromY: number = 0;
  @Prop fromWidth: number = 0;
  @Prop fromHeight: number = 0;
  /** 原图宽高（只用比例）；不知道时用页面上的比例，图片加载完再按实际比例校正。 */
  @Prop naturalWidth: number = 0;
  @Prop naturalHeight: number = 0;
  @Prop viewWidth: number = 360;
  @Prop viewHeight: number = 720;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop darkMode: boolean = false;
  @Prop panelColor: ResourceColor = '#FFFFFF';
  @Prop textColor: ResourceColor = '#E6000000';
  @Prop dividerColor: ResourceColor = '#14000000';
  onSave: () => void = (): void => {};
  onShare: () => void = (): void => {};
  onClose: () => void = (): void => {};

  @State private aspect: number = 1;
  @State private viewScale: number = 1;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private backdropOpacity: number = 0;
  @State private chromeOpacity: number = 0;
  @State private chromeVisible: boolean = true;
  /** 关闭动画期间整层不接触摸，手指已经可以回到正文上。 */
  @State private closingState: boolean = false;
  /** 放大倍数（1 为适应屏幕），与拖动关闭时的临时缩小分开记。 */
  private zoom: number = 1;
  private pinchStartZoom: number = 1;
  private pinchStartX: number = 0;
  private pinchStartY: number = 0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private dismissing: boolean = false;
  private closing: boolean = false;

  aboutToAppear(): void {
    this.aspect = this.naturalWidth > 0 && this.naturalHeight > 0 ? this.naturalWidth / this.naturalHeight :
      (this.fromWidth > 0 && this.fromHeight > 0 ? this.fromWidth / this.fromHeight : 1);
    this.placeAtSource();
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 320, curve: curves.springMotion(0.42, 0.92) }, () => {
        this.viewScale = 1;
        this.offsetX = 0;
        this.offsetY = 0;
        this.backdropOpacity = 1;
        this.chromeOpacity = 1;
      });
    }, 0);
  }

  /** 适应屏幕时图片的矩形 [x, y, 宽, 高]：左右留白，上面让开状态栏，下面让出图注和按钮。 */
  private fitRect(): number[] {
    const top = this.topInset + 56;
    const bottom = this.bottomInset + 128;
    const areaWidth = Math.max(1, this.viewWidth - ReaderImageViewer.SIDE * 2);
    const areaHeight = Math.max(1, this.viewHeight - top - bottom);
    let width = areaWidth;
    let height = width / Math.max(0.01, this.aspect);
    if (height > areaHeight) {
      height = areaHeight;
      width = height * this.aspect;
    }
    return [(this.viewWidth - width) / 2, top + (areaHeight - height) / 2, width, height];
  }

  private placeAtSource(): void {
    const fit = this.fitRect();
    if (this.fromWidth <= 0 || this.fromHeight <= 0) {
      this.viewScale = 0.9;
      this.offsetX = 0;
      this.offsetY = 0;
      return;
    }
    this.viewScale = this.fromWidth / fit[2];
    this.offsetX = this.fromX + this.fromWidth / 2 - (fit[0] + fit[2] / 2);
    this.offsetY = this.fromY + this.fromHeight / 2 - (fit[1] + fit[3] / 2);
  }

  private close(): void {
    if (this.closing) return;
    this.closing = true;
    this.closingState = true;
    let finished = false;
    const finish = (): void => {
      if (finished) return;
      finished = true;
      this.onClose();
    };
    this.getUIContext().animateTo({
      duration: 280,
      curve: curves.springMotion(0.36, 1),
      onFinish: finish
    }, () => {
      this.zoom = 1;
      this.placeAtSource();
      this.backdropOpacity = 0;
      this.chromeOpacity = 0;
    });
    // 动画回调偶尔不来（页面切走等）时也要卸载。
    setTimeout(finish, 420);
  }

  /** 放大后把图限制在屏幕内：比屏幕小的方向居中，比屏幕大的方向不露出空白。 */
  private clampOffset(zoom: number, x: number, y: number): number[] {
    const fit = this.fitRect();
    const width = fit[2] * zoom;
    const height = fit[3] * zoom;
    const centerX = fit[0] + fit[2] / 2;
    const centerY = fit[1] + fit[3] / 2;
    const limitX = Math.max(0, (width - this.viewWidth) / 2);
    const limitY = Math.max(0, (height - this.viewHeight) / 2);
    const baseX = this.viewWidth / 2 - centerX;
    const baseY = this.viewHeight / 2 - centerY;
    const clampedX = width <= this.viewWidth ? (zoom > 1 ? baseX : 0) : Math.max(baseX - limitX, Math.min(baseX + limitX, x));
    const clampedY = height <= this.viewHeight ? (zoom > 1 ? baseY : 0) :
      Math.max(baseY - limitY, Math.min(baseY + limitY, y));
    return [clampedX, clampedY];
  }

  /** 以 (px, py) 为中心把放大倍数从 fromZoom/起点偏移 换到 toZoom，手指下的那一点不动。 */
  private zoomAround(px: number, py: number, fromZoom: number, startX: number, startY: number, toZoom: number): number[] {
    const fit = this.fitRect();
    const centerX = fit[0] + fit[2] / 2 + startX;
    const centerY = fit[1] + fit[3] / 2 + startY;
    const ratio = toZoom / Math.max(0.01, fromZoom);
    return [startX + (px - centerX) * (1 - ratio), startY + (py - centerY) * (1 - ratio)];
  }

  private onDoubleTap(px: number, py: number): void {
    const target = this.zoom > 1.01 ? 1 : ReaderImageViewer.DOUBLE_TAP_SCALE;
    const moved = target === 1 ? [0, 0] : this.zoomAround(px, py, this.zoom, this.offsetX, this.offsetY, target);
    const clamped = target === 1 ? [0, 0] : this.clampOffset(target, moved[0], moved[1]);
    this.zoom = target;
    this.getUIContext().animateTo({ duration: 260, curve: curves.springMotion(0.32, 1) }, () => {
      this.viewScale = target;
      this.offsetX = clamped[0];
      this.offsetY = clamped[1];
    });
  }

  private onSingleTap(px: number, py: number): void {
    const fit = this.fitRect();
    const width = fit[2] * this.viewScale;
    const height = fit[3] * this.viewScale;
    const left = fit[0] + fit[2] / 2 + this.offsetX - width / 2;
    const top = fit[1] + fit[3] / 2 + this.offsetY - height / 2;
    const onImage = px >= left && px <= left + width && py >= top && py <= top + height;
    if (!onImage && this.zoom <= 1.01) {
      this.close();
      return;
    }
    this.chromeVisible = !this.chromeVisible;
    this.getUIContext().animateTo({ duration: 180 }, () => {
      this.chromeOpacity = this.chromeVisible ? 1 : 0;
    });
  }

  private onPanUpdate(dx: number, dy: number): void {
    if (this.zoom > 1.01) {
      this.offsetX = this.panStartX + dx;
      this.offsetY = this.panStartY + dy;
      return;
    }
    // 未放大：往下拖缩小并淡出背景，往上拖只跟一点点。
    this.dismissing = true;
    const down = Math.max(0, dy);
    const progress = Math.min(1, down / 400);
    this.viewScale = 1 - progress * 0.35;
    this.offsetX = dx;
    this.offsetY = dy > 0 ? dy : dy / 4;
    this.backdropOpacity = 1 - progress;
    this.chromeOpacity = 0;
  }

  private onPanEnd(dy: number): void {
    if (this.zoom > 1.01) {
      const clamped = this.clampOffset(this.zoom, this.offsetX, this.offsetY);
      this.getUIContext().animateTo({ duration: 240, curve: curves.springMotion(0.32, 1) }, () => {
        this.offsetX = clamped[0];
        this.offsetY = clamped[1];
      });
      return;
    }
    if (!this.dismissing) return;
    this.dismissing = false;
    if (dy > ReaderImageViewer.DISMISS_DISTANCE) {
      this.close();
      return;
    }
    this.getUIContext().animateTo({ duration: 260, curve: curves.springMotion(0.32, 1) }, () => {
      this.viewScale = 1;
      this.offsetX = 0;
      this.offsetY = 0;
      this.backdropOpacity = 1;
      this.chromeOpacity = this.chromeVisible ? 1 : 0;
    });
  }

  build() {
    Stack() {
      // 背后的正文模糊并压暗，像把图从纸上拿起来看。
      Column()
        .width('100%')
        .height('100%')
        .backdropBlur(28)
        .backgroundColor(this.darkMode ? '#8C0A0B0D' : '#61221E18')
        .opacity(this.backdropOpacity)

      Image(this.src)
        .width(this.fitRect()[2])
        .height(this.fitRect()[3])
        .position({ x: this.fitRect()[0], y: this.fitRect()[1] })
        .objectFit(ImageFit.Fill)
        .interpolation(ImageInterpolation.High)
        .draggable(false)
        .borderRadius(6)
        .shadow({ radius: 36, color: '#59000000', offsetY: 14 })
        .scale({ x: this.viewScale, y: this.viewScale })
        .translate({ x: this.offsetX, y: this.offsetY })
        .onComplete((event) => {
          if (!event || event.width <= 0 || event.height <= 0) return;
          const aspect = event.width / event.height;
          if (Math.abs(aspect - this.aspect) > 0.01) this.aspect = aspect;
        })
        .accessibilityText(this.caption || '插图')

      if (this.caption) {
        Text(this.caption)
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FBFAF7')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .textShadow({ radius: 8, color: '#80000000', offsetY: 1 })
          .width(this.viewWidth - 48)
          .position({ x: 24, y: this.viewHeight - this.bottomInset - 34 - ReaderImageViewer.BAR_HEIGHT - 44 })
          .opacity(this.chromeOpacity)
          .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        ReaderMaterialPanel({
          panelWidth: ReaderImageViewer.BAR_WIDTH,
          panelHeight: ReaderImageViewer.BAR_HEIGHT,
          cornerRadius: ReaderImageViewer.BAR_HEIGHT / 2,
          darkMode: this.darkMode,
          fallbackColor: this.panelColor
        }) {
          this.bar()
        }
      }
      .width(ReaderImageViewer.BAR_WIDTH)
      .height(ReaderImageViewer.BAR_HEIGHT)
      .position({
        x: (this.viewWidth - ReaderImageViewer.BAR_WIDTH) / 2,
        y: this.viewHeight - this.bottomInset - 34 - ReaderImageViewer.BAR_HEIGHT
      })
      .opacity(this.chromeOpacity)
      .hitTestBehavior(this.chromeOpacity > 0.5 ? HitTestMode.Default : HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.closingState ? HitTestMode.None : HitTestMode.Default)
    .gesture(GestureGroup(GestureMode.Exclusive,
      TapGesture({ count: 2 }).onAction((event: GestureEvent) => {
        const finger = firstGestureFinger(event);
        if (finger && !this.closing) this.onDoubleTap(finger.localX, finger.localY);
      }),
      TapGesture({ count: 1 }).onAction((event: GestureEvent) => {
        const finger = firstGestureFinger(event);
        if (finger && !this.closing) this.onSingleTap(finger.localX, finger.localY);
      }),
      PinchGesture({ fingers: 2 })
        .onActionStart(() => {
          this.pinchStartZoom = this.zoom;
          this.pinchStartX = this.offsetX;
          this.pinchStartY = this.offsetY;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.closing) return;
          const zoom = Math.max(0.8, Math.min(ReaderImageViewer.MAX_SCALE + 0.5, this.pinchStartZoom * event.scale));
          const moved = this.zoomAround(event.pinchCenterX, event.pinchCenterY, this.pinchStartZoom,
            this.pinchStartX, this.pinchStartY, zoom);
          this.zoom = zoom;
          this.viewScale = zoom;
          this.offsetX = moved[0];
          this.offsetY = moved[1];
        })
        .onActionEnd(() => {
          const zoom = Math.max(1, Math.min(ReaderImageViewer.MAX_SCALE, this.zoom));
          const clamped = zoom <= 1.01 ? [0, 0] : this.clampOffset(zoom, this.offsetX, this.offsetY);
          this.zoom = zoom;
          this.getUIContext().animateTo({ duration: 240, curve: curves.springMotion(0.32, 1) }, () => {
            this.viewScale = zoom;
            this.offsetX = clamped[0];
            this.offsetY = clamped[1];
          });
        }),
      PanGesture({ fingers: 1, distance: 6 })
        .onActionStart(() => {
          this.panStartX = this.offsetX;
          this.panStartY = this.offsetY;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (!this.closing) this.onPanUpdate(event.offsetX, event.offsetY);
        })
        .onActionEnd((event: GestureEvent) => {
          if (!this.closing) this.onPanEnd(event.offsetY);
        })
    ))
  }

  @Builder
  bar() {
    Row() {
      this.barButton($r('sys.symbol.save'), '保存', () => this.onSave())
      Divider().vertical(true).height(18).strokeWidth(0.5).color(this.dividerColor)
      this.barButton($r('sys.symbol.share'), '分享', () => this.onShare())
      Divider().vertical(true).height(18).strokeWidth(0.5).color(this.dividerColor)
      this.barButton($r('sys.symbol.xmark'), '关闭', () => this.close())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  @Builder
  barButton(icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: 6 }) {
        SymbolGlyph(icon)
          .fontSize(17)
          .fontColor([this.textColor])
        Text(label)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.textColor)
          .maxLines(1)
      }
      .padding({ left: 12, right: 12 })
    }
    .height(36)
    .backgroundColor(Color.Transparent)
    .onClick(action)
  }
}
