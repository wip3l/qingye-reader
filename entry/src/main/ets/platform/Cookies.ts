// 应用侧 Cookie 读写的统一出口。安卓构建会用 android/overlay 里的同名文件替换本文件。
// 鸿蒙上直接用书源内核的 CookieStore（ArkWeb Cookie 库），不给内核装 Cookie 端口。
import { CookieStore, SourceCookieJar } from '@legado/sourceengine';

/** 应用代码读写 Cookie 用它，不直接调 CookieStore 的静态方法。 */
export const AppCookies: SourceCookieJar = CookieStore;

/** 应用启动、执行任何书源之前调用一次。鸿蒙上什么也不做。 */
export function installCookiePort(): void {
}
