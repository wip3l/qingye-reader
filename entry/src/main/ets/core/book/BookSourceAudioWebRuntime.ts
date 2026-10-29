import { webview } from '@kit.ArkWeb';
import { AudioRuleSupport } from './AudioRuleSupport';

class AudioWebResolveTask {
  url: string = '';
  sourceRegex: string = '';
  resolve: ((value: string) => void) | null = null;
  reject: ((error: Error) => void) | null = null;
  timeoutId: number = -1;
}

/**
 * Small, isolated ArkWeb host used by legacy audio rules whose chapter URL carries
 * `{webView:true}` and whose `sourceRegex` selects the actual media request. It never
 * shares a controller with the source-script runtime, so loading a real page cannot
 * invalidate an in-flight search, catalog or content script.
 */
export class BookSourceAudioWebRuntime {
  private static instance: BookSourceAudioWebRuntime | null = null;
  private controller: webview.WebviewController | null = null;
  private ready: boolean = false;
  private task: AudioWebResolveTask | null = null;
  private controllers: webview.WebviewController[] = [];
  private readyControllers: Set<webview.WebviewController> = new Set();

  static get(): BookSourceAudioWebRuntime {
    if (!BookSourceAudioWebRuntime.instance) {
      BookSourceAudioWebRuntime.instance = new BookSourceAudioWebRuntime();
    }
    return BookSourceAudioWebRuntime.instance;
  }

  /**
   * 首页常驻一个宿主（书架后台下载用），听书页打开时再挂一个。后挂的优先；
   * 它关闭后退回前一个，书架上的下载才不会因为关了听书页而失去解析环境。
   */
  attach(controller: webview.WebviewController): void {
    this.controllers = this.controllers.filter((item: webview.WebviewController): boolean => item !== controller);
    this.controllers.push(controller);
    this.controller = controller;
    this.ready = this.readyControllers.has(controller);
  }

  detach(controller: webview.WebviewController): void {
    this.controllers = this.controllers.filter((item: webview.WebviewController): boolean => item !== controller);
    this.readyControllers.delete(controller);
    if (this.controller !== controller) return;
    this.cancel('听书网页解析环境已关闭');
    this.controller = this.controllers.length > 0 ? this.controllers[this.controllers.length - 1] : null;
    this.ready = !!this.controller && this.readyControllers.has(this.controller);
  }

  setReady(ready: boolean, controller: webview.WebviewController): void {
    if (ready) this.readyControllers.add(controller);
    else this.readyControllers.delete(controller);
    if (this.controller !== controller) return;
    this.ready = ready;
    if (ready && this.task) this.inspectLoadedPage(controller);
  }

  isAvailable(): boolean {
    return !!this.controller && this.ready;
  }

  async waitUntilAvailable(timeoutMs: number = 2500): Promise<boolean> {
    if (this.isAvailable()) return true;
    const startedAt = Date.now();
    while (Date.now() - startedAt < Math.max(100, timeoutMs)) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
      if (this.isAvailable()) return true;
    }
    return this.isAvailable();
  }

  resolveAudioUrl(url: string, sourceRegex: string, userAgent: string = '',
    timeoutMs: number = 15000): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      if (!this.controller || !this.ready) {
        reject(new Error('听书网页解析环境未就绪'));
        return;
      }
      if (this.task) {
        reject(new Error('已有听书网页解析任务正在执行'));
        return;
      }
      const target = this.cleanUrl(url);
      if (!/^https?:\/\//i.test(target)) {
        reject(new Error('听书网页地址无效'));
        return;
      }
      const task = new AudioWebResolveTask();
      task.url = target;
      task.sourceRegex = sourceRegex || '';
      task.resolve = resolve;
      task.reject = reject;
      task.timeoutId = setTimeout((): void => {
        if (this.task !== task) return;
        this.finish('', new Error('网页未捕获到可播放音频地址'));
      }, Math.max(3000, timeoutMs));
      this.task = task;
      try {
        if (userAgent) this.controller.setCustomUserAgent(userAgent);
        this.controller.loadUrl(target);
      } catch (error) {
        this.finish('', error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  observeRequestUrl(url: string): void {
    const task = this.task;
    if (!task) return;
    const candidate = this.cleanUrl(url);
    if (!candidate || !this.matches(candidate, task.sourceRegex)) return;
    this.finish(candidate, null);
  }

  private inspectLoadedPage(controller: webview.WebviewController): void {
    const task = this.task;
    if (!task || this.controller !== controller) return;
    const script = `(function(){const out=[];const add=v=>{v=String(v||'');if(v&&!out.includes(v))out.push(v)};` +
      `add(location.href);try{performance.getEntriesByType('resource').forEach(e=>add(e.name))}catch(e){}` +
      `try{document.querySelectorAll('audio,source,video').forEach(e=>add(e.currentSrc||e.src||` +
      `e.getAttribute('data-src')||e.getAttribute('data-url')))}catch(e){}` +
      `try{const h=document.documentElement.outerHTML||'';const m=h.match(/(?:https?:)?\\/\\/[^\\s"'<>\\\\]+/g)||[];` +
      `m.slice(0,512).forEach(add)}catch(e){}return JSON.stringify(out.slice(0,1024))})()`;
    setTimeout((): void => {
      if (this.task !== task || this.controller !== controller) return;
      controller.runJavaScript(script).then((raw: string): void => {
        if (this.task !== task) return;
        for (const value of this.parseResultList(raw)) {
          this.observeRequestUrl(value);
          if (this.task !== task) return;
        }
      }).catch((): void => {});
    }, 350);
  }

  private parseResultList(raw: string): string[] {
    let value = String(raw || '');
    if (value.startsWith('"') && value.endsWith('"')) {
      try { value = String(JSON.parse(value)); } catch (_) {}
    }
    try {
      const parsed = JSON.parse(value) as Object;
      if (!Array.isArray(parsed)) return [];
      return (parsed as Object[]).map((item: Object): string => String(item || ''));
    } catch (_) {
      return [];
    }
  }

  private matches(url: string, rawRegex: string): boolean {
    const value = this.cleanUrl(url);
    if (!value) return false;
    return AudioRuleSupport.matchesSourceRegex(value, rawRegex);
  }

  private cleanUrl(url: string): string {
    return String(url || '').replace(/&amp;/gi, '&').replace(/\\\//g, '/').trim();
  }

  private cancel(message: string): void {
    if (!this.task) return;
    this.finish('', new Error(message));
  }

  private finish(value: string, error: Error | null): void {
    const task = this.task;
    if (!task) return;
    this.task = null;
    if (task.timeoutId >= 0) clearTimeout(task.timeoutId);
    try { this.controller?.stop(); } catch (_) {}
    try { this.controller?.loadUrl('about:blank'); } catch (_) {}
    if (value) {
      if (task.resolve) task.resolve(value);
    } else if (task.reject) {
      task.reject(error || new Error('网页未捕获到可播放音频地址'));
    }
  }
}
