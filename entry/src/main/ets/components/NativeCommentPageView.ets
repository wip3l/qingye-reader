import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { NativeCommentPage } from '@legado/sourceengine';
import { NativeCommentDocumentPolicy } from '../core/book/NativeCommentDocumentPolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';

/** Dedicated offline Web: never reuse the remote comment Web or its navigation bridge. */
@Component
export struct NativeCommentPageView {
  @Prop @Watch('pageChanged') page: NativeCommentPage = new NativeCommentPage();
  @Prop darkMode: boolean = false;
  @State loading: boolean = true;
  @State error: string = '';
  /** 每次显示尝试先报 start，再报一次 ready / failed / cancelled，调试页据此单独记录显示结果。 */
  onDisplay: (state: string, message: string) => void = (): void => {};
  private displayOpen: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private timer: number = -1;
  private readyTimer: number = -1;
  private attached: boolean = false;
  private initialPageReady: boolean = false;
  private serial: number = 0;
  private documentBase64: string = '';

  private pageChanged(): void { this.load(); }

  private surfaceColor(): string {
    return this.darkMode ? '#18191B' : '#FFFFFF';
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.initialPageReady = false;
    this.serial++;
    this.documentBase64 = '';
    this.clearTimer();
    try { this.controller.stop(); } catch (_) { }
    this.endDisplay('cancelled', '预览已关闭');
  }

  private beginDisplay(): void {
    this.endDisplay('cancelled', '已重新加载');
    this.displayOpen = true;
    this.onDisplay('start', '');
  }

  private endDisplay(state: string, message: string): void {
    if (!this.displayOpen) return;
    this.displayOpen = false;
    this.onDisplay(state, message);
  }

  private clearTimer(): void {
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    if (this.readyTimer >= 0) clearTimeout(this.readyTimer);
    this.readyTimer = -1;
  }

  private scheduleReady(): void {
    if (!this.attached || this.error) return;
    if (this.readyTimer >= 0) clearTimeout(this.readyTimer);
    const serial = this.serial;
    this.readyTimer = setTimeout((): void => {
      this.readyTimer = -1;
      this.controller.runJavaScript(`window.__NATIVE_PAGE_READY__ === true && window.__NATIVE_PAGE_GENERATION__ === ${serial}`)
        .then((ready: string): void => {
          if (!this.attached || serial !== this.serial || this.error) return;
          if (ready === 'true') { this.clearTimer(); this.loading = false; this.endDisplay('ready', ''); }
          else this.scheduleReady();
        }).catch((): void => {
          if (this.attached && serial === this.serial && !this.error) this.scheduleReady();
        });
    }, 100);
  }

  private fail(message: string): void {
    this.clearTimer();
    this.serial++;
    this.attached = false;
    this.documentBase64 = '';
    this.error = message;
    try { this.controller.stop(); } catch (_) { }
    // The error branch unmounts Web instead of leaving a failed document attached to the panel.
    this.endDisplay('failed', message);
  }

  private retry(): void {
    this.attached = false;
    this.initialPageReady = false;
    this.documentBase64 = '';
    this.controller = new webview.WebviewController();
    this.loading = true;
    this.error = '';
  }

  private load(): void {
    if (!this.attached || !this.initialPageReady) return;
    this.serial++;
    this.clearTimer();
    this.loading = true;
    this.error = '';
    this.beginDisplay();
    try {
      const document = NativeCommentPage.document(this.page, this.serial);
      this.documentBase64 = new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(document));
      const serial = this.serial;
      this.timer = setTimeout((): void => {
        if (this.attached && serial === this.serial) this.fail('评论页渲染超过 15 秒');
      }, 15000);
      // ArkWeb navigates loadData through data:text/html. Base64 preserves #, %, Unicode and srcdoc markup;
      // the interceptors below accept only this exact host-generated document in the main frame.
      this.controller.loadData(this.documentBase64, 'text/html', 'base64');
      this.scheduleReady();
    } catch (error) {
      this.fail(error instanceof Error ? error.message : '评论页渲染失败');
    }
  }

  private pageEnded(url: string): void {
    if (!this.attached || this.error) return;
    if (!this.initialPageReady) {
      if (url !== 'about:blank') return;
      this.initialPageReady = true;
      this.load();
      return;
    }
    // The generated document sits on top of the initial blank in Web history, and ArkWeb consumes the
    // system back gesture to go back while it can. Drop that entry so one back swipe closes the panel.
    try { this.controller.clearHistory(); } catch (_) { }
    this.scheduleReady();
  }

  build() {
    Column() {
      Stack() {
        if (!this.error) {
        Web({ src: 'about:blank', controller: this.controller, incognitoMode: true,
          renderMode: RenderMode.SYNC_RENDER })
          .width('100%').height('100%')
          .backgroundColor(this.surfaceColor())
          // ArkWeb defaults to Off, even when the host app is dark. Let source CSS handle its own colours.
          .darkMode(this.darkMode ? WebDarkMode.On : WebDarkMode.Off)
          .forceDarkAccess(false)
          .javaScriptAccess(true)
          .blockNetwork(true)
          .fileAccess(false)
          .domStorageAccess(false)
          .databaseAccess(false)
          .geolocationAccess(false)
          .onlineImageAccess(false)
          .multiWindowAccess(false)
          .allowWindowOpenMethod(false)
          .onPermissionRequest((event: OnPermissionRequestEvent): void => event.request.deny())
          .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => {
            event.result.handleFileList([]);
            return true;
          })
          .onAlert((event: OnAlertEvent): boolean => { event.result.handleCancel(); return true; })
          .onConfirm((event: OnConfirmEvent): boolean => { event.result.handleCancel(); return true; })
          .onPrompt((event: OnPromptEvent): boolean => { event.result.handleCancel(); return true; })
          .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
            return !NativeCommentDocumentPolicy.allowsNavigation(request.getRequestUrl(), request.isMainFrame(),
              this.documentBase64);
          })
          .onLoadIntercept((event?: OnLoadInterceptEvent): boolean => {
            return !!event?.data && !NativeCommentDocumentPolicy.allowsNavigation(event.data.getRequestUrl(),
              event.data.isMainFrame(), this.documentBase64);
          })
          .onInterceptRequest((event?: OnInterceptRequestEvent): WebResourceResponse | null => {
            const url = event?.request?.getRequestUrl() || '';
            if (NativeCommentDocumentPolicy.allowsResource(url, event?.request?.isMainFrame() === true,
              this.documentBase64)) return null;
            const response = new WebResourceResponse();
            response.setResponseData('');
            response.setResponseCode(403);
            response.setReasonMessage('Offline page');
            return response;
          })
          // The declarative src navigation follows controller attachment. Wait for that initial blank;
          // otherwise it cancels loadData and silently replaces the generated document with an empty page.
          .onControllerAttached((): void => { this.attached = true; })
          .onPageEnd((event: OnPageEndEvent): void => this.pageEnded(event.url))
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            if (event.request.isMainFrame()) this.fail('评论页渲染失败');
          })
        }
        if (this.loading || this.error) {
          Column({ space: 12 }) {
            if (!this.error) { LoadingProgress().width(32).height(32) }
            Text(this.error || '评论页面加载中…')
              .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            if (this.error) { Button('重试').onClick((): void => this.retry()) }
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(this.surfaceColor())
        }
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(this.surfaceColor())
  }
}
