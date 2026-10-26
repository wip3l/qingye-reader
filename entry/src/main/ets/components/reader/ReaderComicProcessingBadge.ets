import { ReaderComicColorSession } from '@legado/aiengine';
import { ReaderComicProcessing } from '../../core/reader/ReaderComicProcessing';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ThemeRuntime } from '../../theme/ThemeRuntime';

/** 固定在阅读视口内，长条图滚动和缩放时仍然可见，不拦截手势。 */
@Component
export struct ReaderComicProcessingBadge {
  /** 缓存命中或直接跳过的图片很快结束，处理超过这么久才显示，避免一闪而过。 */
  private static readonly SHOW_DELAY_MS: number = 400;
  processing: ReaderComicProcessing = new ReaderComicProcessing();
  colorSession: ReaderComicColorSession | null = null;
  @State private message: string = '';
  @State private shown: boolean = false;
  private pending: string = '';
  private showTimer: number = -1;
  private unsubscribeProcessing: (() => void) | null = null;
  private unsubscribeColor: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubscribeProcessing = this.processing.subscribe((): void => this.refresh());
    this.unsubscribeColor = this.colorSession?.subscribe((): void => this.refresh()) || null;
    this.refresh();
  }

  aboutToDisappear(): void {
    this.unsubscribeProcessing?.();
    this.unsubscribeColor?.();
    this.unsubscribeProcessing = null;
    this.unsubscribeColor = null;
    clearTimeout(this.showTimer);
    this.showTimer = -1;
  }

  private refresh(): void {
    const message = this.processing.message(this.colorSession?.processingVisible() || false);
    if (message === this.pending) return;
    this.pending = message;
    if (!message) {
      clearTimeout(this.showTimer);
      this.showTimer = -1;
      this.shown = false;
      return;
    }
    if (this.shown) {
      this.message = message;
      return;
    }
    if (this.showTimer >= 0) return;
    this.showTimer = setTimeout((): void => {
      this.showTimer = -1;
      if (!this.pending) return;
      this.message = this.pending;
      this.shown = true;
    }, ReaderComicProcessingBadge.SHOW_DELAY_MS);
  }

  build() {
    Row({ space: AppSpacing.SM }) {
      if (this.message) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(ThemeRuntime.onAccentColor())
        Text(this.message)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.onAccentColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
      }
    }
    .padding(this.message ? AppSpacing.SM : 0)
    .borderRadius(10)
    .backgroundColor(this.message ? ThemeRuntime.scrimColor(true) : Color.Transparent)
    .constraintSize({ maxWidth: '90%' })
    .opacity(this.shown ? 1 : 0)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .hitTestBehavior(HitTestMode.None)
  }
}
