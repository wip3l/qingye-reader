// platform/Cookies.ts 的安卓实现。
// ArkUI-X 的 webview.WebCookieManager 在安卓上只有异步接口，内核 CookieStore 用的同步接口全部失败。
// 这里经原生桥（CookieBridge.java）读写安卓的 CookieManager，网页组件（登录页、验证页）用的是同一个库，
// 再把它作为 Cookie 端口装进内核：内核取 Cookie 一律经 CookieStore.forSource，装了端口就走这里。
import bridge from '@arkui-x.bridge';
import { SetCookieParser, SourceCookieJar, SourceEngineHost } from '@legado/sourceengine';

/** 与 CookieBridge.NAME 一致。 */
const COOKIE_BRIDGE_NAME = 'io.legado.read/cookie';
/** 内核在 ArkWeb 删不掉 Cookie 时写入的占位值，读的时候过滤掉。 */
const TOMBSTONE_VALUE = '__removed__';

let cookieBridge: bridge.BridgeObject | null = null;

function callSync(method: string, ...args: string[]): string {
  if (!cookieBridge) cookieBridge = bridge.createBridge(COOKIE_BRIDGE_NAME);
  try {
    const value = cookieBridge.callMethodSync(method, ...args);
    return value === undefined || value === null ? '' : String(value);
  } catch (error) {
    console.warn(`[Cookies] ${method} 失败:`, (error as Error).message);
    return '';
  }
}

/** CookieManager 只认完整地址；内核偶尔传不带协议的域名。 */
function normalizeUrl(url: string): string {
  const value = (url || '').trim();
  if (!value) return '';
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) return value;
  if (/^[A-Za-z0-9.-]+(?::\d+)?(?:\/.*)?$/.test(value) && value.includes('.')) return `https://${value}`;
  return value;
}

function cookieNames(cookies: string): string[] {
  return cookies.split(';').map((item: string): string => item.trim().split('=')[0].trim())
    .filter((name: string): boolean => name.length > 0);
}

class AndroidCookieJar implements SourceCookieJar {
  getRequestCookie(url: string): string {
    return this.getCookie(url);
  }

  getCookie(url: string): string {
    const target = normalizeUrl(url);
    if (!target) return '';
    return callSync('getCookie', target).split(';').map((item: string): string => item.trim())
      .filter((pair: string): boolean => pair.includes('=') && pair.substring(pair.indexOf('=') + 1).trim() !== TOMBSTONE_VALUE)
      .join('; ');
  }

  getCookieValue(url: string, name: string): string {
    if (!name) return this.getCookie(url);
    for (const item of this.getCookie(url).split(';')) {
      const index = item.indexOf('=');
      if (index > 0 && item.substring(0, index).trim() === name) return item.substring(index + 1).trim();
    }
    return '';
  }

  setCookies(url: string, value: string): void {
    const target = normalizeUrl(url);
    if (!target || !value) return;
    for (const cookie of SetCookieParser.split(value)) {
      const error = callSync('setCookie', target, cookie);
      if (error) console.warn('[Cookies] 写入 Cookie 失败:', error);
    }
  }

  replaceCookies(url: string, value: string): void {
    if (!url) return;
    this.removeCookie(url);
    if (value) this.setCookies(url, value);
    this.saveAsync();
  }

  removeCookie(url: string, name?: string): void {
    const target = normalizeUrl(url);
    if (!target) return;
    const names = name ? [name] : cookieNames(callSync('getCookie', target));
    for (const cookieName of names) {
      // CookieManager 按“名字 + 域 + 路径”匹配，过期写入即删除；路径不确定，根路径和默认路径各写一次。
      for (const path of ['; Path=/', '']) {
        callSync('setCookie', target, `${cookieName}=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT${path}`);
      }
    }
    this.saveAsync();
  }

  copyCookies(from: string, to: string): void {
    if (!from || !to) return;
    for (const item of this.getCookie(from).split(';')) {
      const pair = item.trim();
      if (!pair || !pair.includes('=')) continue;
      // Cloudflare 的放行凭据只对签发它的站点有效，跟内核 CookieStore 的处理一致。
      if (/^(cf_clearance|__cf_bm)=/i.test(pair) && from !== to) continue;
      this.setCookies(to, pair);
    }
    this.saveAsync();
  }

  saveAsync(): void {
    callSync('flush');
  }

  saveSync(): void {
    callSync('flush');
  }

  clearAll(): void {
    callSync('clearAll');
  }
}

const jar = new AndroidCookieJar();

export const AppCookies: SourceCookieJar = jar;

export function installCookiePort(): void {
  SourceEngineHost.install({ cookies: (_sourceUrl: string): SourceCookieJar => jar });
}
