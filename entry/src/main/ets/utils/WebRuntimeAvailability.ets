import { webview } from '@kit.ArkWeb';

/**
 * Whether the ArkWeb runtime exists in this process. The DevEco previewer and devices without the Web system
 * capability do not register the Web component's event attributes; building a Web node there throws
 * "undefined is not callable" and blanks the whole page. The always-mounted hidden Web hosts check this first.
 *
 * Errs on the side of "available": book-source scripts depend on these hosts, so only a missing capability or a
 * missing API counts as unavailable, never an ordinary runtime error.
 */
export class WebRuntimeAvailability {
  private static cachedResult: boolean | null = null;

  static isAvailable(): boolean {
    if (WebRuntimeAvailability.cachedResult === null) {
      WebRuntimeAvailability.cachedResult = WebRuntimeAvailability.probe();
      if (!WebRuntimeAvailability.cachedResult) {
        console.warn('[WebRuntime] ArkWeb 不可用，隐藏的 Web 宿主不会挂载，依赖脚本运行层的书源将无法使用');
      }
    }
    return WebRuntimeAvailability.cachedResult;
  }

  private static probe(): boolean {
    if (!canIUse('SystemCapability.Web.Webview.Core')) return false;
    try {
      // false is already the default, so this changes nothing where the runtime exists.
      webview.WebviewController.setWebDebuggingAccess(false);
      return true;
    } catch (error) {
      // A system error object carries a numeric code and means the runtime is there; a bare TypeError means the
      // API itself is absent.
      const code = Number((error as Record<string, Object>)?.['code'] || 0);
      return code !== 0 || !(error instanceof TypeError);
    }
  }
}
