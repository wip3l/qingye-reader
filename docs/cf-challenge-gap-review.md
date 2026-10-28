# Cloudflare 人机验证能力缺口报告核查

核查日期：2026-10-28。

后续状态：2026-10-29 已按用户要求实施通用修复，详见 [实施与验收记录](cf-challenge-repair-validation.md)。下文保留修复前的核查结论与当时的验证范围。

核查对象：用户提供的《轻页-CF人机验证站点能力缺口报告.md》。该文档中的修复建议作为待评估内容，本次只核实问题，不实施修复。

## 结论

报告反映的访问受阻有事实依据，但不能接受“四个根因均已确认”“搜索/发现结构上无法使用 WebView”“只增加该能力即可解锁全部 CF 站点”等结论。

当前源码已经允许搜索/发现使用 WebView，并提供用户主动点击的验证入口。可以确认的是：设置页没有自行挂载网页抓取宿主；抓取依赖页面控制器；超时提示可能掩盖实际等待阶段。Cookie 方面发现一个报告未识别的具体缺口：读取接口没有启用第一方分区 Cookie。该缺口与 CF 的 Partitioned Cookie 有直接关联，但是否就是两个案例的实际根因，仍须真机验证。

## 核查范围与版本

- 主仓库：`c6287f9`，源码应用版本 **4.4.938**。
- 书源引擎：`6ac9bb6`；核查开始时两仓库工作区均无未提交改动。
- 报告基于 **4.4.933**，因此本次源码结论不冒充旧安装包复现。
- 已阅读原报告、请求/脚本/验证/Cookie/UI 代码、本机 SDK API 声明和 Cloudflare 官方文档，并从开发机直连访问相关站点。
- 未安装新包、未操作真机验证页面，未取得报告中的完整书源 JSON、原始调试日志或四阶段单测材料。

## 四项根因逐项核对

| 报告判断 | 核查结果 | 证据与边界 |
| --- | --- | --- |
| 搜索/发现禁止一切网页交互，因此不能用 WebView | **表述错误，P0 选项 1 的核心能力已存在** | `NativeScriptHost.browserVerify` 在非交互阶段登记验证请求并提示“去验证”；`browser.open` 被限制，但 `render` 和 HTTP WebView 请求没有这个交互权限判断。主页 `Index.ets:558` 已挂载 `WebBookFetchRuntimeHost`；搜索/发现 UI 有主动验证入口。当前公开文档第 1498 行明确说明搜索/发现支持加载和渲染网页。 |
| 设置页/后台不能可靠使用 `browser.render` | **页面宿主依赖属实；设置页缺少自有宿主属实** | `NativeSourceSettings.ets` 执行动作、动态选项及登录脚本，但没有挂载 `WebBookFetchRuntimeHost`。`HttpClient.ts:189` 等待现有宿主，超时后返回“环境未挂载”。后台不存在独立创建控制器的机制。但运行时是全局单例；若其他页面仍保留控制器，设置页可能借用，不能概括为每次必失败。 |
| `http.request({webView})` 报连接超时，证明 WebView 没启动 | **错误提示存在歧义，不能据此定位根因** | `browser.render` 与 `http.request` 最终走同一网页抓取通道。`NetworkErrorText.ts:21` 把 `2300028` 或英文 timeout 都转成“连接…超时”。`WebBookFetchRuntime` 的排队过期、总预算过期也会产生 `2300028`，并不等价于 TCP 连接失败或控制器没有启动。 |
| 宿主只持久化非 HttpOnly Cookie，导致 cf_clearance 丢失 | **证据不足；更具体的分区 Cookie 缺口已发现** | 主读取路径是 ArkWeb 原生 `WebCookieManager.fetchCookieSync`，不是仅靠 `document.cookie`；写入还显式传入 `includeHttpOnly=true`。不能从“没读到 cf_clearance”直接推出 HttpOnly 被排除。当前读取未传 API 26 新增的 `includePartitionedCookies`，默认 false，见下文。 |

## Cookie 与 UA 的关键发现

### 分区 Cookie 未纳入读取

`CookieStore.ts:19` 调用：

```ts
webview.WebCookieManager.fetchCookieSync(target)
```

本机 SDK `@ohos.web.webview.d.ts:1525` 的 API 26 签名为：

```ts
fetchCookieSync(url: string, incognito?: boolean, includePartitionedCookies?: boolean): string
```

声明明确：第三个参数控制是否包含第一方分区 Cookie，默认 **false**。Cloudflare 官方说明 `cf_clearance` 带有 `SameSite=None; Secure; Partitioned` 属性：[Cloudflare Cookies](https://developers.cloudflare.com/fundamentals/reference/policies-compliances/cloudflare-cookies/)。

因此可以确认当前应用没有主动读取这类分区 Cookie。若设备实际获得的 clearance 是分区 Cookie，网页可以保留它，而 `cookie.get()` 和原生 HTTP 组装 Cookie 的路径可能拿不到它。这是源码与官方定义支持的解释，尚未以两个站点的设备 Cookie 元数据验证。

建议后续先在 API 26 真机比较普通读取与 `fetchCookieSync(url, false, true)` 的 **Cookie 名称及存在性**，不要输出值；同时核对是否确实成功获得 clearance、域/路径、有效期和分区。若修复，必须考虑项目最低 API 20 的兼容性和 Cookie 分区语义。

### 默认 UA 一致，自定义 UA 才有明显风险

- `HttpClient.ts:81` 的默认 UA 与 `VerifyWeb.ets:171` 的验证页 UA 字符串相同，均为 Android 14 / Chrome 120。
- 隐藏抓取页在 `WebBookFetchRuntime.ts:239` 按请求头设置自定义 UA。
- 可见验证页固定返回 `mobileUserAgent`，没有采用该书源求值后的自定义 UA。因此书源自行覆盖 UA 时，存在 HTTP/隐藏抓取页与验证页不一致的风险。
- 已有 `device.ua` 接口，但它表示书源请求采用的 UA，不是独立读取当前验证页 UA 的接口。

故不能认定“HTTP 与 ArkWeb 默认 UA 必定不同”。两个案例是否配置了不同 UA，需要原始书源和同次会话记录。Cloudflare 官方将会话中 UA 变化、网络/IP 不一致等列为失败原因，但对齐 UA 并不构成通过验证的充分保证：[Challenge solve issues](https://developers.cloudflare.com/cloudflare-challenges/troubleshooting/challenge-solve-issues/)、[How Challenges work](https://developers.cloudflare.com/cloudflare-challenges/concepts/how-challenges-work/)。

## 报告遗漏的行为差异

1. **脚本请求不会自动沿用主请求的验证判定。** `NativeScriptHost.ts:348` 将脚本 HTTP 请求设为 `primary:false`，`NativeSourceService.ts:194` 只在 `request.primary` 时自动登记挑战页验证。脚本可以在识别挑战后主动调用 `browser.verify`，搜索/发现会出现“去验证”。这是明确的调用契约，不是所有脚本请求都自动提示，也不能说书源作者完全没有处理途径。
2. **WebView 的 200 是抓取层成功状态。** `WebBookFetchRuntime.ts:447` 在成功取得 DOM 或表达式结果后统一返回 `statusCode:200`，不是原站响应状态。`waitFor:'body'` 在挑战页上也可能满足，因此“200 + ok=true”不能单独证明过盾。若确实解析出了有效且匹配关键词的 100 本书，则是更强证据，但本次没有这些原始结果。
3. **“已登录”不等于“已经获得 CF clearance”。** `NativeSourceService.ts:522` 在未声明 `login.cookies` 名称列表时，只要该 URL 存在任何 Cookie 就可显示已登录。另一个路径中，登录 Cookie 启发式明确忽略 `cf_clearance` 与 `__cf_bm`（`VerificationSupport.ts:135`）；设置页 `login.url` 入口要求登录 Cookie，可能把“仅完成 CF 验证”与“账户登录”混淆。
4. **脚本返回条数不等于 UI 最终条数。** `SearchCoordinator.ts:1061` 按书名、作者和元数据相关性过滤，另有精确匹配、去重、上限和取消预算。必须对照同一关键词、同一返回内容和过滤结果，才能定位“调试有结果、UI 无结果”；当前证据不足以断言 UI 丢数据，也不足以宣称规则完全无误。
5. **报告的最小复现不完整。** 给出的 JSON 没有 `login` 或 `webView`，后续却要求从该源登录并预期调试成功；也未提供可直接导入的诊断动作与函数定义。该片段不能稳定证明“调试可用、UI 不可用”。

## 站点直连复查

从开发机发起 HTTPS 首页 GET，清除当前进程代理环境变量，使用不读取代理配置的 Node `https`，UA 与应用默认值相同；未携带用户 Cookie，未执行挑战 JS，未自动重试挑战。

| 域名 | 本次结果 |
| --- | --- |
| www.pilishuwu.com | 403，`cf-mitigated: challenge`，Cloudflare 挑战页 |
| www.pilibook.net | 同上 |
| www.pili45.com | 同上 |
| www.pilisf.com | 同上 |
| www.qiufengshuwu.com | 同上；**不能继续标为域名已失效** |
| www.pilixiaoshuo.com | 200 公告页；本次直连读取到全站质询和一周信任期的说明 |
| m.ciweiku.com / www.ciweiku.com | TLS 阶段 `EPROTO`，未取得 HTTP 状态；本次未复现其 403 |

该结果仅证明本次开发机出口访问这些首页的状态，不证明全部 HTML 路径、真机出口或过盾后的请求状态。“没有其他无盾线路”也不能靠有限域名枚举严格证明。

导航站确实宣称一周信任期，但不应将其推广成所有 CF 站点的保证。官方说明有效时长由站点 Challenge Passage 配置，默认 30 分钟：[Challenge Passage](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/challenge-passage/)。

## 已运行检查与后续优先级

- `node --experimental-strip-types scripts/native-script-check.mjs`（引擎目录）：**120 项断言通过**，包含非交互搜索提示验证及脚本请求不自动触发主请求验证的契约。
- `node scripts/web-request-deadline-check.mjs`：**通过**，覆盖排队过期、控制器迁移、活动请求停止和截止时间。
- 这些是受控 Node 检查，不替代 ArkWeb 真机、CF 挑战或设备 Cookie 测试。

建议优先做：设置页网页宿主生命周期补齐；分区 Cookie 的设备对照验证；区分宿主等待/队列/网页渲染/网络超时。随后检查自定义 UA 对齐、登录与过盾状态区分，以及脚本挑战处理的文档与诊断。无需重新实现已经存在的“搜索/发现允许 webView”，也不应承诺一次改动即可支持全部 CF 站点。

若继续定位两个具体书源，需要同一安装包版本下的完整书源、同一关键词的 UI 与调试结果，以及验证前后脱敏的 Cookie 存在性、UA 和网页最终地址记录。
