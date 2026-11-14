import { webview } from '@kit.ArkWeb';
import { WebRuntimeAvailability } from '../utils/WebRuntimeAvailability';
import { BookSourceStageWebRuntime } from '@legado/sourceengine';

/** Keeps the shared full-JavaScript source runtime available on routed book pages. */
@Component
export struct BookSourceStageRuntimeHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State mounted: boolean = true;
  private resetScheduled: boolean = false;
  private disappearing: boolean = false;
  private attachRetryId: number = -1;

  aboutToAppear(): void {
    this.disappearing = false;
    this.scheduleAttachFallback(0);
  }

  aboutToDisappear(): void {
    this.disappearing = true;
    if (this.attachRetryId >= 0) clearTimeout(this.attachRetryId);
    this.attachRetryId = -1;
    BookSourceStageWebRuntime.get().clearResetHandler(this.controller);
    BookSourceStageWebRuntime.get().detach(this.controller);
  }

  private adoptController(): void {
    if (this.disappearing) return;
    if (this.attachRetryId >= 0) clearTimeout(this.attachRetryId);
    this.attachRetryId = -1;
    const runtime = BookSourceStageWebRuntime.get();
    runtime.attach(this.controller);
    runtime.setResetHandler((): void => this.resetHost(), this.controller);
  }

  private scheduleAttachFallback(attempt: number): void {
    if (this.disappearing) return;
    this.attachRetryId = setTimeout((): void => {
      if (this.disappearing) return;
      try {
        // A successful getWebId proves the controller is associated with a Web component. On
        // some routed/hidden Web nodes ArkWeb omits onControllerAttached — including nodes
        // rebuilt by resetHost() — so treat this poll as the authoritative attach path.
        this.controller.getWebId();
        this.adoptController();
        return;
      } catch (_) {}
      if (attempt < 100) this.scheduleAttachFallback(attempt + 1);
    }, attempt === 0 ? 0 : 100);
  }

  private resetHost(): void {
    if (this.resetScheduled) return;
    this.resetScheduled = true;
    if (this.attachRetryId >= 0) clearTimeout(this.attachRetryId);
    this.attachRetryId = -1;
    const previous = this.controller;
    BookSourceStageWebRuntime.get().clearResetHandler(previous);
    BookSourceStageWebRuntime.get().detach(previous);
    this.mounted = false;
    // Keep the unmounted state for at least one render frame. A zero-delay callback can be
    // coalesced with the preceding state change, leaving the retired Web controller in place.
    setTimeout(() => {
      this.controller = new webview.WebviewController();
      this.mounted = true;
      this.resetScheduled = false;
      this.scheduleAttachFallback(0);
    }, 50);
  }

  build() {
    if (this.mounted && WebRuntimeAvailability.isAvailable()) {
      Web({ src: 'about:blank', controller: this.controller })
        .width(1)
        // 隐藏的脚本运行环境，不参与焦点；安卓上 Web 拿到焦点会吞掉返回键。
        .focusable(false)
        .height(1)
        .opacity(0.01)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onControllerAttached(() => {
          this.adoptController();
        })
        .onPageBegin(() => {
          BookSourceStageWebRuntime.get().setReady(false, this.controller);
        })
        .onPageEnd(() => {
          BookSourceStageWebRuntime.get().setReady(true, this.controller);
        })
    }
  }
}
