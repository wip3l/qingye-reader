import { webview } from '@kit.ArkWeb';
import { WebRuntimeAvailability } from '../utils/WebRuntimeAvailability';
import { WebBookFetchRuntime } from '@legado/sourceengine';

/** Invisible ArkWeb transport for source rules that explicitly opt into `webView: true`. */
@Component
export struct WebBookFetchRuntimeHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private attachRetryId: number = -1;
  private disappearing: boolean = false;
  private initialPageReady: boolean = false;
  private registered: boolean = false;

  aboutToAppear(): void {
    this.disappearing = false;
    this.initialPageReady = false;
    this.registered = false;
    this.scheduleAttachFallback(0);
  }

  aboutToDisappear(): void {
    this.disappearing = true;
    if (this.attachRetryId >= 0) clearTimeout(this.attachRetryId);
    this.attachRetryId = -1;
    WebBookFetchRuntime.get().detach(this.controller);
  }

  private attachRuntime(): void {
    if (this.disappearing) return;
    if (this.attachRetryId >= 0) clearTimeout(this.attachRetryId);
    this.attachRetryId = -1;
    this.registered = true;
    WebBookFetchRuntime.get().attach(this.controller);
  }

  private scheduleAttachFallback(attempt: number): void {
    if (this.disappearing) return;
    this.attachRetryId = setTimeout((): void => {
      if (this.disappearing) return;
      // Association alone is not enough on a cold ArkWeb: the component's initial src
      // navigation can overwrite the first loadUrl. Prefer its first onPageEnd. Some routed
      // hosts omit that event, so retain a bounded fallback after initialization has settled.
      if (!this.initialPageReady && attempt < 10) {
        this.scheduleAttachFallback(attempt + 1);
        return;
      }
      try {
        // A successful getWebId proves the controller is associated with a Web component. On
        // some routed/hidden Web nodes ArkWeb omits onControllerAttached, so use this as fallback.
        this.controller.getWebId();
        this.attachRuntime();
        return;
      } catch (_) {}
      if (attempt < 100) this.scheduleAttachFallback(attempt + 1);
    }, attempt === 0 ? 0 : 100);
  }

  build() {
    if (WebRuntimeAvailability.isAvailable()) {
      Web({ src: 'about:blank', controller: this.controller })
        .width(1)
        .height(1)
        .opacity(0.01)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onlineImageAccess(true)
        .onControllerAttached((): void => { this.scheduleAttachFallback(0); })
        .onVisibleAreaChange([0], (visible: boolean): void => {
          if (visible && !this.disappearing) this.scheduleAttachFallback(0);
        })
        .onPageBegin((): void => { WebBookFetchRuntime.get().onPageBegin(this.controller); })
        .onPageEnd((): void => {
          this.initialPageReady = true;
          if (!this.registered) this.attachRuntime();
          WebBookFetchRuntime.get().onPageEnd(this.controller);
        })
    }
  }
}
