package io.legado.read;

import android.content.Context;
import android.webkit.CookieManager;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * Cookie 桥：书源请求与网页组件共用安卓的 CookieManager，相当于鸿蒙上的 ArkWeb Cookie 库。
 *
 * ArkUI-X 的 webview.WebCookieManager 在安卓上只实现了异步接口，书源内核用的同步接口全部失败，
 * 所以安卓构建给内核装一个经这里读写的 Cookie 端口（android/overlay/.../platform/Cookies.ts）。
 * ArkTS 侧用 callMethodSync 调用，在调用线程上直接执行；CookieManager 本身线程安全。
 * 返回值是纯字符串，不是 JSON。
 */
public class CookieBridge extends BridgePlugin {
    /** 与 Cookies.ts 里的 COOKIE_BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/cookie";

    public CookieBridge(Context context, BridgeManager bridgeManager) {
        super(context, NAME, bridgeManager);
        CookieManager.getInstance().setAcceptCookie(true);
    }

    /** 发往 url 时会带上的 Cookie，形如 "a=1; b=2"；没有时返回空串。 */
    public String getCookie(String url) {
        try {
            String value = CookieManager.getInstance().getCookie(url);
            return value == null ? "" : value;
        } catch (RuntimeException e) {
            return "";
        }
    }

    /** 写入一条 Set-Cookie 形式的记录。返回空串表示成功，否则是错误信息。 */
    public String setCookie(String url, String value) {
        try {
            CookieManager.getInstance().setCookie(url, value);
            return "";
        } catch (RuntimeException e) {
            return e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
        }
    }

    public String clearAll() {
        CookieManager.getInstance().removeAllCookies(null);
        CookieManager.getInstance().flush();
        return "";
    }

    public String flush() {
        CookieManager.getInstance().flush();
        return "";
    }
}
