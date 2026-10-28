import { webview } from '@kit.ArkWeb';
import { CookieStore, HttpClient, WebBookFetchRuntime } from '@legado/sourceengine';
import { WebBookFetchRuntimeHost } from '../../../main/ets/components/WebBookFetchRuntimeHost';

/** Disposable cookies use an invalid, reserved host and expire in one minute. No user cookies are read. */
@Entry
@Component
struct WebVerificationTest {
  @State result: string = '运行网页验证测试';
  @State secondHost: boolean = false;

  aboutToAppear(): void { this.run(); }

  private async pause(ms: number): Promise<void> {
    await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
  }

  private require(value: boolean, message: string): void { if (!value) throw new Error(message); }

  private async run(): Promise<void> {
    let cookieReport = '';
    try {
      this.require(await WebBookFetchRuntime.get().waitUntilAttached(8000), 'host attach');
      const target = 'https://cf-cookie-probe.invalid/';
      const tag = String(Date.now());
      const plain = 'probe_plain_' + tag;
      const partitioned = 'probe_partitioned_' + tag;
      webview.WebCookieManager.configCookieSync(target, `${plain}=fixture; Secure; HttpOnly; Path=/; Max-Age=60`, false, true);
      webview.WebCookieManager.configCookieSync(target, `${partitioned}=fixture; Secure; HttpOnly; SameSite=None; Partitioned; Path=/; Max-Age=60`, false, true);
      const ordinary = webview.WebCookieManager.fetchCookieSync(target, false);
      const inclusive = webview.WebCookieManager.fetchCookieSync(target, false, true);
      cookieReport = `Cookie API: httpOnly=${ordinary.includes(plain + '=')}, partitionDefault=${ordinary.includes(partitioned + '=')}, partitionIncluded=${inclusive.includes(partitioned + '=')}`;
      this.require(ordinary.includes(plain + '='), 'HttpOnly fixture absent');
      this.require(CookieStore.getRequestCookie(target).includes(partitioned + '='), 'request cookie excludes partition');
      CookieStore.removeCookie(target, partitioned);
      this.require(!CookieStore.getRequestCookie(target).includes(partitioned + '='), 'partition removal');
      CookieStore.removeCookie(target, plain);
      const http = new HttpClient(8000);
      const root = 'http://127.0.0.1:18393';
      const headers: Record<string, string> = { 'User-Agent': 'Legado-WebVerification-Fixture' };
      const first = await http.execute({ url: root + '/page', method: 'GET', headers: headers, useWebView: true,
        deadlineAt: Date.now() + 15000 });
      this.require(first.success && first.body.includes('fixture-ready') && first.statusCodeAvailable === false, 'first host fetch: ' + first.error + ' code=' + first.errorCode + ' observed=' + first.statusCodeAvailable + ' body=' + first.body.substring(0, 120));
      const native = await http.execute({ url: root + '/page', method: 'GET', headers: headers, deadlineAt: Date.now() + 5000 });
      this.require(native.success && native.body.includes('fixture-ready'), 'native loopback: ' + native.error);
      this.secondHost = true;
      await this.pause(800);
      const second = await http.execute({ url: root + '/page', method: 'GET', headers: headers, useWebView: true,
        deadlineAt: Date.now() + 15000 });
      this.require(second.success && second.body.includes('fixture-ready'), 'second host fetch');
      this.secondHost = false;
      await this.pause(800);
      const restored = await http.execute({ url: root + '/page', method: 'GET', headers: headers, useWebView: true,
        deadlineAt: Date.now() + 15000 });
      this.require(restored.success && restored.body.includes('fixture-ready'), 'restored host fetch');
      let cancelled = false;
      const pending = http.execute({ url: root + '/slow', method: 'GET', headers: headers, useWebView: true,
        deadlineAt: Date.now() + 15000, cancelCheck: (): boolean => cancelled });
      setTimeout((): void => { cancelled = true; }, 200);
      const stopped = await pending;
      this.require(stopped.errorCode === 'CANCELLED', 'cancel metadata');
      this.result = 'PASS WebVerification: hosts/restoration/cancel/status; ' + cookieReport;
    } catch (error) {
      this.result = 'FAIL WebVerification: ' + (error as Error).message + '; ' + cookieReport;
    }
    AppStorage.setOrCreate('webVerificationTestResult', this.result);
  }

  build() {
    Stack() {
      Text(this.result).fontColor(Color.Black).padding(24)
      WebBookFetchRuntimeHost()
      if (this.secondHost) { WebBookFetchRuntimeHost() }
    }.width('100%').height('100%').backgroundColor(Color.White)
  }
}
