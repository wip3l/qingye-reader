import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { PluginRegistry } from '@legado/pluginengine';
import { PluginWebAssetPolicy } from '../../core/plugin/PluginWebAssetPolicy';
import { AppPluginHost } from '../../core/plugin/AppPluginHost';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { WebRuntimeAvailability } from '../../utils/WebRuntimeAvailability';

@Component
export struct PluginSandboxWebView {
  @Prop @Watch('onPanelTargetChanged') pluginId: string = '';
  @Prop @Watch('onPanelTargetChanged') panelPath: string = '';
  @Prop initialDataJson: string = '{}';
  @Prop darkMode: boolean = false;
  onCloseRequest: () => void = (): void => {};

  @State loading: boolean = true;
  @State errorText: string = '';

  private controller: webview.WebviewController = new webview.WebviewController();
  private ports: webview.WebMessagePort[] = [];
  private attached: boolean = false;
  private blankReady: boolean = false;
  private navigatedUrl: string = '';
  private unsubscribeHostPush: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubscribeHostPush = AppPluginHost.subscribePanelMessages(this.pluginId, (data: Object | null) => {
      this.sendEventToPage('hostMessage', data);
    });
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.blankReady = false;
    this.navigatedUrl = '';
    if (this.unsubscribeHostPush) {
      this.unsubscribeHostPush();
      this.unsubscribeHostPush = null;
    }
    this.closePorts();
    try {
      this.controller.stop();
    } catch (_) {}
  }

  private closePorts(): void {
    try {
      if (this.ports.length > 0) {
        this.ports[0].close();
      }
    } catch (_) {}
    this.ports = [];
  }

  private onPanelTargetChanged(): void {
    if (this.attached && this.blankReady) {
      this.navigatedUrl = '';
      this.navigateToPanel();
    }
  }

  private retryLoad(): void {
    this.closePorts();
    this.attached = false;
    this.blankReady = false;
    this.navigatedUrl = '';
    this.controller = new webview.WebviewController();
    this.loading = true;
    this.errorText = '';
  }

  private sendEventToPage(kind: string, payload: Object | null): void {
    if (this.ports.length === 0) return;
    try {
      this.ports[0].postMessageEvent(JSON.stringify({ kind: kind, payload: payload }));
    } catch (_) {}
  }

  private setupMessageChannel(): void {
    this.closePorts();
    try {
      this.ports = this.controller.createWebMessagePorts();
      if (this.ports.length < 2) return;
      this.ports[0].onMessageEvent((result: webview.WebMessage) => {
        if (typeof result !== 'string') return;
        this.handleClientRpc(result);
      });
      const targetOrigin = 'https://plugin.qingye.local';
      this.controller.postMessage('__qingye_init_port__', [this.ports[1]], targetOrigin);
    } catch (e) {
      console.warn('[PluginSandboxWebView] setupMessageChannel failed:', e instanceof Error ? e.message : String(e));
    }
  }

  private handleClientRpc(rawText: string): void {
    let parsed: Record<string, Object> | null = null;
    try {
      parsed = JSON.parse(rawText) as Record<string, Object>;
    } catch (_) {
      return;
    }
    if (!parsed) return;
    const reqId = Number(parsed['id'] || 0);
    const method = String(parsed['method'] || '');
    const metaJson = JSON.stringify(parsed['payload'] ?? {});

    if (method === 'ui.closePanel') {
      this.onCloseRequest();
      this.replyRpc(reqId, true, 'true', undefined);
      return;
    }

    PluginRegistry.getInstance()
      .dispatchPanelHostCall(this.pluginId, method, metaJson)
      .then((res) => {
        const b64 = res.bytes ? new util.Base64Helper().encodeToStringSync(res.bytes) : undefined;
        this.replyRpc(reqId, true, res.metaJson, b64);
      })
      .catch((err: Object) => {
        const msg = err instanceof Error ? err.message : String(err);
        this.replyRpc(reqId, false, msg, undefined);
      });
  }

  private replyRpc(id: number, ok: boolean, metaOrError: string, bytesBase64?: string): void {
    if (this.ports.length === 0) return;
    try {
      this.ports[0].postMessageEvent(JSON.stringify({
        kind: 'rpcReply',
        id,
        ok,
        metaJson: ok ? metaOrError : '',
        error: ok ? '' : metaOrError,
        bytesBase64: bytesBase64 || ''
      }));
    } catch (_) {}
  }

  private buildInjectedPreamble(): string {
    const pageBg = ThemeRuntime.pageColor(this.darkMode);
    const cardBg = ThemeRuntime.cardColor(this.darkMode);
    const textPrimary = ThemeRuntime.primaryTextColor(this.darkMode);
    const textSub = ThemeRuntime.subTextColor(this.darkMode);
    const accent = ThemeRuntime.accentColor(this.darkMode);
    const divider = ThemeRuntime.dividerColor(this.darkMode);
    const initJson = this.initialDataJson || '{}';

    return `<meta http-equiv="Content-Security-Policy" content="default-src 'self' data:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'none'; frame-src 'none'; object-src 'none';">
<style id="qingye-theme-tokens">
:root {
  color-scheme: ${this.darkMode ? 'dark' : 'light'};
  --qy-page-bg: ${pageBg};
  --qy-card-bg: ${cardBg};
  --qy-text: ${textPrimary};
  --qy-subtext: ${textSub};
  --qy-accent: ${accent};
  --qy-divider: ${divider};
  --qy-radius: 14px;
}
body {
  background-color: var(--qy-page-bg);
  color: var(--qy-text);
  font-family: system-ui, -apple-system, sans-serif;
  margin: 0;
}
</style>
<script>
(function() {
  window.RTCPeerConnection = undefined;
  window.webkitRTCPeerConnection = undefined;
  let port = null;
  let nextId = 1;
  const pending = new Map();
  const listeners = new Set();
  const queue = [];

  window.__QINGYE_INIT__ = ${initJson};

  function decodeBase64(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  window.addEventListener('message', function(ev) {
    if (ev.data === '__qingye_init_port__' && ev.ports && ev.ports[0]) {
      port = ev.ports[0];
      port.onmessage = function(msgEv) {
        try {
          const msg = JSON.parse(msgEv.data);
          if (msg.kind === 'rpcReply') {
            const waiter = pending.get(msg.id);
            if (!waiter) return;
            pending.delete(msg.id);
            if (!msg.ok) {
              waiter.reject(new Error(msg.error || 'RPC failed'));
              return;
            }
            const parsed = msg.metaJson ? JSON.parse(msg.metaJson) : null;
            if (msg.bytesBase64) {
              const bytes = decodeBase64(msg.bytesBase64);
              if (parsed && typeof parsed === 'object') {
                parsed.bytes = bytes;
                waiter.resolve(parsed);
              } else {
                waiter.resolve(bytes);
              }
            } else {
              waiter.resolve(parsed);
            }
          } else if (msg.kind === 'hostMessage') {
            listeners.forEach(function(fn) { try { fn(msg.payload); } catch (_) {} });
          }
        } catch (_) {}
      };
      while (queue.length > 0) port.postMessage(queue.shift());
    }
  });

  function invoke(method, payload) {
    return new Promise(function(resolve, reject) {
      const id = nextId++;
      pending.set(id, { resolve: resolve, reject: reject });
      const wire = JSON.stringify({ id: id, method: method, payload: payload || {} });
      if (port) port.postMessage(wire);
      else queue.push(wire);
    });
  }

  window.qingye = Object.freeze({
    initData: window.__QINGYE_INIT__,
    invoke: invoke,
    callPlugin: function(handler, payload) { return invoke('plugin.call', { handler: handler, payload: payload || {} }); },
    onMessage: function(fn) { listeners.add(fn); return function() { listeners.delete(fn); }; },
    close: function() { return invoke('ui.closePanel', {}); },
    env: Object.freeze({ info: function() { return invoke('env.info', {}); } }),
    config: Object.freeze({
      get: function(key) { return invoke('config.get', { key: key || '' }); },
      set: function(key, value) { return invoke('config.set', { key: key, value: value }); }
    }),
    kv: Object.freeze({
      get: function(key) { return invoke('kv.get', { key: key }); },
      set: function(key, value) { return invoke('kv.set', { key: key, value: value }); },
      delete: function(key) { return invoke('kv.delete', { key: key }); },
      keys: function() { return invoke('kv.keys', {}); }
    }),
    http: Object.freeze({
      get: function(url, opts) { return invoke('http.request', Object.assign({}, opts || {}, { url: url, method: 'GET' })); },
      post: function(url, body, opts) { return invoke('http.request', Object.assign({}, opts || {}, { url: url, method: 'POST', body: body })); }
    }),
    reader: Object.freeze({
      getBookContext: function() { return invoke('reader.getBookContext', {}); },
      getAnnotations: function(chapterIndex) { return invoke('reader.getAnnotations', { chapterIndex: typeof chapterIndex === 'number' ? chapterIndex : -1 }); },
      addAnnotation: function(spec) { return invoke('reader.addAnnotation', spec || {}); }
    }),
    source: Object.freeze({
      getSummary: function() { return invoke('source.getSummary', {}); },
      openRoute: function(target) { return invoke('source.openRoute', { target: String(target || '') }); }
    }),
    ui: Object.freeze({
      toast: function(message) { return invoke('ui.toast', { message: message }); }
    })
  });
})();
</script>`;
  }

  private serveLocalAsset(url: string, isMainFrame: boolean): WebResourceResponse {
    const deny = (reason: string): WebResourceResponse => {
      const resp = new WebResourceResponse();
      resp.setResponseData('');
      resp.setResponseCode(403);
      resp.setReasonMessage(reason);
      return resp;
    };

    const resolved = PluginWebAssetPolicy.resolveVirtualAsset(url, this.pluginId);
    if (!resolved) {
      return deny('Blocked external resource');
    }

    const record = PluginRegistry.getInstance().getPlugin(this.pluginId);
    if (!record || !record.enabled) {
      return deny('Plugin disabled');
    }

    const absFile = `${record.installDir}/${resolved.relPath}`;
    try {
      const stat = fs.statSync(absFile);
      if (!stat.isFile() || stat.size > 16 * 1024 * 1024) {
        return deny('Asset unavailable');
      }
      const fd = fs.openSync(absFile, fs.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      try {
        if (stat.size > 0) fs.readSync(fd.fd, buf);
      } finally {
        fs.closeSync(fd);
      }

      const resp = new WebResourceResponse();
      resp.setResponseCode(200);
      resp.setReasonMessage('OK');
      const semiIdx = resolved.mimeType.indexOf(';');
      const pureMime = semiIdx >= 0 ? resolved.mimeType.slice(0, semiIdx).trim() : resolved.mimeType;
      resp.setResponseMimeType(pureMime);
      if (pureMime.startsWith('text/') || pureMime === 'application/javascript' || pureMime === 'application/json' ||
        pureMime === 'image/svg+xml') {
        resp.setResponseEncoding('utf-8');
      }

      if (isMainFrame && pureMime === 'text/html') {
        const htmlText = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
        const preamble = this.buildInjectedPreamble();
        const headClose = htmlText.search(/<\/head>/i);
        const injected = headClose >= 0
          ? `${htmlText.slice(0, headClose)}${preamble}${htmlText.slice(headClose)}`
          : `<!DOCTYPE html><html><head>${preamble}</head><body>${htmlText}</body></html>`;
        resp.setResponseData(injected);
      } else {
        resp.setResponseData(buf);
      }
      resp.setResponseIsReady(true);
      return resp;
    } catch (_) {
      return deny('Failed to read plugin asset');
    }
  }

  private navigateToPanel(): void {
    if (!this.attached || !this.blankReady || !this.pluginId || !this.panelPath) return;
    this.loading = true;
    this.errorText = '';
    try {
      const targetUrl = PluginWebAssetPolicy.buildPanelUrl(this.pluginId, this.panelPath);
      if (this.navigatedUrl === targetUrl) return;
      this.navigatedUrl = targetUrl;
      this.controller.loadUrl(targetUrl);
    } catch (e) {
      this.loading = false;
      this.errorText = e instanceof Error ? e.message : '无法加载插件面板';
    }
  }

  build() {
    Stack() {
      if (!WebRuntimeAvailability.isAvailable()) {
        Column({ space: 8 }) {
          Text('当前设备不支持 Web 面板运行环境')
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (!this.errorText) {
        Web({
          src: 'about:blank',
          controller: this.controller,
          incognitoMode: true,
          renderMode: RenderMode.SYNC_RENDER
        })
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeRuntime.pageColor(this.darkMode))
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
          .onAlert((event: OnAlertEvent): boolean => {
            event.result.handleCancel();
            return true;
          })
          .onConfirm((event: OnConfirmEvent): boolean => {
            event.result.handleCancel();
            return true;
          })
          .onPrompt((event: OnPromptEvent): boolean => {
            event.result.handleCancel();
            return true;
          })
          .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
            const url = request.getRequestUrl();
            if (PluginWebAssetPolicy.allowsNavigation(url, this.pluginId)) return false;
            return true;
          })
          .onLoadIntercept((event?: OnLoadInterceptEvent): boolean => {
            if (!event?.data) return false;
            const url = event.data.getRequestUrl();
            return !PluginWebAssetPolicy.allowsNavigation(url, this.pluginId) &&
              !PluginWebAssetPolicy.allowsInlineDataUrl(url);
          })
          .onInterceptRequest((event?: OnInterceptRequestEvent): WebResourceResponse | null => {
            const url = event?.request?.getRequestUrl() || '';
            if (url === 'about:blank' || url === 'about:srcdoc' || PluginWebAssetPolicy.allowsInlineDataUrl(url)) {
              return null;
            }
            return this.serveLocalAsset(url, event?.request?.isMainFrame() === true);
          })
          // ArkWeb dispatches the declarative src ('about:blank') after onControllerAttached; wait for
          // that initial blank to finish so it does not abort loadUrl() with ERR_ABORTED(-3).
          .onControllerAttached((): void => {
            this.attached = true;
            if (this.blankReady) {
              this.navigateToPanel();
            }
          })
          .onPageEnd((event: OnPageEndEvent): void => {
            if (event.url === 'about:blank' || event.url.startsWith('about:')) {
              if (!this.blankReady) {
                this.blankReady = true;
                this.navigateToPanel();
              }
              return;
            }
            this.setupMessageChannel();
            try {
              this.controller.clearHistory();
            } catch (_) {}
            this.loading = false;
          })
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            if (event.request.isMainFrame() && event.request.getRequestUrl() !== 'about:blank') {
              const code = event.error.getErrorCode();
              const info = event.error.getErrorInfo();
              console.warn('[PluginSandboxWebView] mainFrame load error:', code, info, event.request.getRequestUrl());
              this.loading = false;
              this.errorText = `插件面板加载失败 (${code})`;
            }
          })
          .onConsole((event): boolean => {
            if (event?.message) {
              const lvl = event.message.getMessageLevel();
              if (lvl === MessageLevel.Error || lvl === MessageLevel.Warn) {
                console.warn('[PluginSandboxWebView:console]', event.message.getMessage());
              }
            }
            return false;
          })
      }

      if (this.loading || this.errorText) {
        Column({ space: 12 }) {
          if (!this.errorText) {
            LoadingProgress().width(30).height(30).color(ThemeRuntime.accentColor(this.darkMode))
          }
          Text(this.errorText || '加载插件界面中…')
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          if (this.errorText) {
            Button('重试')
              .height(34)
              .fontColor('#FFFFFF')
              .backgroundColor(ThemeRuntime.accentColor(this.darkMode))
              .onClick((): void => this.retryLoad())
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeRuntime.pageColor(this.darkMode))
      }
    }
    .width('100%')
    .height('100%')
  }
}
