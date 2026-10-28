import { router } from '@kit.ArkUI';
import { Context } from '@kit.AbilityKit';
import { NativeBrowserRequest, NativeBrowserResult, NativeSourceInteractionHandler, VerificationSupport } from '@legado/sourceengine';
import { HdsFeedback } from './HdsFeedback';
import { ExploreResultCache } from './ExploreResultCache';

/**
 * 原生书源脚本的界面端口：ui.toast、ui.refreshExplore、browser.verify / browser.open。
 *
 * 网页沿用 VerifyWeb 页面：带上等待令牌打开，用户点「完成」时页面把内容写回 AppStorage，这里轮询取回；
 * 用户返回或关闭页面时得到“网页操作已取消”。与兼容书源 startBrowserAwait 用的是同一套机制。
 */
export class AppSourceInteraction implements NativeSourceInteractionHandler {
  private static readonly WAIT_LIMIT_MS: number = 10 * 60 * 1000;
  private static readonly POLL_MS: number = 250;
  private context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  toast(sourceName: string, message: string): void {
    const text = (message || '').trim();
    if (!text) return;
    HdsFeedback.showToast(sourceName ? `${sourceName}：${text}` : text);
  }

  async refreshExplore(sourceUrl: string): Promise<void> {
    await ExploreResultCache.invalidateSources(this.context, [sourceUrl]);
  }

  async openBrowser(request: NativeBrowserRequest, wait: boolean): Promise<NativeBrowserResult> {
    const token = wait ? `${Date.now()}_${Math.floor(Math.random() * 1000000000)}` : '';
    if (wait) {
      AppStorage.setOrCreate('bookSourceBrowserAwaitResultToken', '');
      AppStorage.setOrCreate('bookSourceBrowserAwaitResultBody', '');
      AppStorage.setOrCreate('bookSourceBrowserAwaitResultError', '');
    }
    // 记下书源，网页里登录得到的 Cookie 按书源保存。
    AppStorage.setOrCreate('pendingVerificationSourceUrl', request.sourceUrl);
    try {
      await router.pushUrl({
        url: 'pages/VerifyWeb',
        params: {
          url: request.url,
          verificationContextToken: VerificationSupport.createContext(request.url, request.sourceUrl, request.userAgent || ''),
          title: request.title || request.sourceName || '网页',
          requireLoginCookie: 'false',
          readerCommentMode: 'false',
          bookSourceBrowserAwaitToken: token
        }
      });
    } catch (e) {
      return { body: '', error: `打开网页失败：${(e as Error).message || e}` };
    }
    if (!wait) return { body: '', error: '' };
    return await this.waitForResult(token);
  }

  private waitForResult(token: string): Promise<NativeBrowserResult> {
    return new Promise<NativeBrowserResult>((resolve: (result: NativeBrowserResult) => void): void => {
      const startedAt = Date.now();
      const timer = setInterval((): void => {
        if ((AppStorage.get<string>('bookSourceBrowserAwaitResultToken') || '') === token) {
          clearInterval(timer);
          const body = AppStorage.get<string>('bookSourceBrowserAwaitResultBody') || '';
          const error = AppStorage.get<string>('bookSourceBrowserAwaitResultError') || '';
          AppStorage.setOrCreate('bookSourceBrowserAwaitResultToken', '');
          AppStorage.setOrCreate('bookSourceBrowserAwaitResultBody', '');
          AppStorage.setOrCreate('bookSourceBrowserAwaitResultError', '');
          resolve({ body: body, error: error });
        } else if (Date.now() - startedAt > AppSourceInteraction.WAIT_LIMIT_MS) {
          clearInterval(timer);
          resolve({ body: '', error: '等待网页操作超时' });
        }
      }, AppSourceInteraction.POLL_MS);
    });
  }
}
