# 搜索／发现 WebView 报告逐项代码核查

后续状态：本文保留实施前的核查结论和当时行号；本轮修复及最新验收结果见 [对原报告的回复](search-explore-webview-report-response.md)。

核查日期：2026-10-29。对象为用户提供的《轻页-搜索发现阶段WebView宿主缺失报告.md》。本次只核查，不将报告里的修复建议视为实施指令。

## 版本与证据边界

- 当前主仓库 HEAD：`327beff`，应用版本 4.4.940；书源引擎 HEAD：`536a6fd`。
- 追溯到主仓库 `dc10311`，当时应用版本已核对为 4.4.938，主页已有 `WebBookFetchRuntimeHost`，对应引擎提交为 `b1389e1`。
- `b1389e1` 到当前引擎 HEAD，本文涉及的 `WebBookFetchRuntime.ts`、`NativeScriptHost.ts`、`CookieStore.ts` 无差异。因此这些能力不是仅在 4.4.940 才增加。
- 报告没有提供其实际安装包的构建提交、完整书源、字段探测脚本及原始请求轨迹，不能断言它运行的就是上述 4.4.938 构建。
- 本次无真实站点访问、无真机操作、无打包安装。Node 测试验证代码行为，不替代 ArkWeb／Cloudflare 现场复现。保留用户既有改动。

## 四项缺口逐项核查

### 1. 搜索／发现上下文没有 WebView 宿主：源码不支持该结论

实际调用链：

```text
Index → SearchPage / ExplorePage
      → SearchCoordinator / ExploreCoordinator
      → NativeSourceService → NativeSourceRunner
      → NativeScriptHost → NativeHost.fetch
      → AnalyzeUrl → HttpClient → WebBookFetchRuntime
```

- `entry/src/main/ets/pages/Index.ets:591` 在主页根 Stack 挂载抓取宿主，位于两种 Tabs 分支之外，也不受 `stageRuntimeMounted` 控制。不要将旁边的兼容脚本运行时与抓取宿主混为一谈。
- `entry/src/main/ets/pages/NativeSourceSettings.ets:560` 设置页自行挂载同一组件。
- `NativeScriptHost.ts:111` 的 `@http` 与 `:180` 的 `@render` 不检查 interactive；`:176` 限制的是 browser.open。`:211` 在非交互阶段让 browser.verify 登记验证并提示用户重试。
- `NativeSourceRunner.ts:1384` 将搜索、发现标为非交互，影响弹出网页，不禁止 HTTP WebView 或 browser.render。
- `WebBookFetchRuntime.ts:80` 起管理多个控制器，`:114` 起在当前控制器退出时恢复前一个控制器。GET 迁移复用原截止时间，已发出的 POST 不重放。
- 宿主组件仍依赖 ArkWeb 能力检测、控制器关联及生命周期回调。组件存在不保证现场每次关联成功；这类运行时故障不能由静态挂载点排除。

**结论：能力和挂载点已存在。若现场失败，应查宿主注册、恢复、网页加载和排队，而不是默认再加一套宿主。**

### 2. HttpOnly／分区 Cookie 没进入请求层：源码不支持笼统判断

引擎路径均相对于 `harmony-book-source-engine/sourceengine/src/main/ets/`：

- `core/http/CookieStore.ts:14`：API 26 调用 `fetchCookieSync(url,false,true)`；低于 API 26 使用旧读取，801 不支持错误也回退。低版本回退不意味着拥有 API 26 的分区读取能力。
- `core/nativesource/NativeSourceService.ts:244`：cookie.get 优先调用 getRequestCookie。
- `core/http/HttpClient.ts:98`：文本和二进制请求发出前通过 getRequestCookie 补入 Cookie；调用点分别位于 `:298`、`:541`。
- 原生读取不是只依靠 document.cookie。VerifyWeb 的 document.cookie 同步只是补充路径，不能据此认定所有 HttpOnly Cookie 都会丢失。
- 显式 Cookie 头优先；关闭 CookieJar 时不自动注入；跨 origin 重定向有凭据隔离。这些分支需要结合完整书源核对。
- 验证 UA 由上下文 token 传入 VerifyWeb；`device.ua` 按书源顶层头求值；WebBookFetchRuntime 加载前设置请求 UA。单次 HTTP 手工覆盖 UA 后另行验证，仍需要调用方传同一 UA，不能宣称所有组合自动一致。

**结论：请求层已有读取和发送实现；报告中具体 clearance 为何不可读或无效仍未定位。**

### 3. errorCode／errorStage／statusCodeAvailable 缺失：当前标准脚本通道不符合该现象

- `HttpClient.ts:239` 已产生 `WEB_HOST_UNAVAILABLE / host`。
- `NativeSourceService.ts:211` 转发结构化错误、状态及耗时。
- `NativeScriptHost.ts:329` 无条件构造三个字段，即使底层没有分类，也返回空字符串／false，字段仍存在。
- `NativeScriptSessions.ts:23` 将返回对象 JSON 序列化；`NativeJsPrelude.ts:66` 的 wrap 只添加 json()，不会删除这些字段。
- 补充测试通过真实 NativeSourceRunner、NativeScriptHost、NativeJsPrelude 和 Node worker 桥接，分别在搜索、发现、动作中验证字段存在且值相同。

**结论：若报告通过 hasOwnProperty 或 Object.keys 确认字段缺失，应核对实际构建／执行通道。若通过 `if(r.errorCode)` 或 `if(r.statusCodeAvailable)` 判断“存在”，空字符串和 false 会被误判为缺失；报告未附探测代码，不能确定是哪一种。**

### 4. 文档写可用但实现不支持：接口层面不成立，验收边界仍须保留

声明式 webView 在 `NativeSourceRunner.ts:1555` 解析，脚本 webView 在 `NativeScriptHost.ts:354` 解析，两者都进入请求层。设置页和搜索／发现支持网页加载这两句话并不冲突。

文档中的“可调用”不等于特定 CF 站点已经验收通过；公开说明已保留真实 CF 人工验证验收边界。需要改进的是可观测性、失败处理和真实页面兼容性，不能把现场失败直接写成接口未实现。

## 本次确认的具体薄弱点

### A. body 已存在，也可能完全不进入选择器检查

`WebBookFetchRuntime.ts:320` 的 inspect 在 `pageEnded=false` 时直接返回；`:349` 还要求 readyState=complete 且页面签名稳定两轮，之后才执行 waitFor。页面签名包含 HTML 长度及首尾内容。

所以即使 body 存在，只要 onPageEnd 没到、文档未 complete 或签名持续变化，就可能一直等到超时。补充控制器测试已复现“宿主已挂载，DOM 可读取，但未收到 onPageEnd；最终空正文，且未尝试读取 DOM”。测试并不证明真实站点正好缺少该回调。

优化方向：对显式 waitFor 增加有界的 DOM 就绪探测，满足业务条件后允许提取，保留防止读到 about:blank／旧导航内容的校验；普通无条件抓取继续使用稳定性策略。

### B. 部分超时会丢弃已见页面

`WebBookFetchRuntime.ts:422` 的选择器重试耗尽分支保留 HTML；但是 `:285` 起的定时器、总截止时间及通用 failure（`:517`）返回空正文。inspect 取得的 HTML 未统一保存在 task 上用于这些失败返回。

因此文档“body 等待也 len=0 更符合宿主缺失”的判断不充分。优化方向：保留有大小上限、关联当前导航的最后快照，失败仍保持 ok=false，同时给出准确失败阶段和快照可用性。

### C. 发现页旧任务只有结果失效，没有贯通请求取消

- `ExplorePage.ets:1648` 的 beginExploreLoad 增加版本号，结果回来后按版本号忽略。
- `ExploreCoordinator.ts:608` 调用 NativeSourceService.explore，未传页面取消函数。
- `NativeSourceService.ts:775` 构造 runner 时使用 `(): boolean => false`，动态分类也是如此。
- 网页运行时为单活动任务、共享队列，上限 32。切分类后的旧请求可能继续占用队列和预算，影响新请求；不能据此断言本报告已触发该情况。

优化方向：将页面加载代次转换成取消信号，贯通分类、发现列表、脚本及请求层；取消当前页面旧任务，不全局取消其他页面请求。

### D. 诊断字段存在，但诊断仍不完整

- NativeSourceService 转发了 hostWaitMs／queueMs／renderMs，NativeScriptHost 返回对象未包含这些耗时，脚本拿不到。补充测试确认此行为；这是诊断增强点，不是已有公开字段缺失。
- browser.render 失败时在 `NativeScriptHost.ts:238` 转成只含文案的 Error，丢失结构化错误字段。
- NativeScriptHost 捕获底层异常时只保留 message，随后 errorCode/errorStage 为空。字段存在与错误都已分类是两回事。
- HTTP 层总截止时间先返回时，也可能只有 REQUEST_DEADLINE，缺少更细的当时等待状态。

优化方向：在异常包装和 render 错误中保留结构化原因，补齐脚本可见耗时；超时携带当时阶段，避免再次依靠 ok/len 猜原因。

## 报告其余判断

- 普通 HTTP 403、域名当日可达性、实际 Cookie 内容属于运行数据，源码不能确认；本次没有独立复现。
- 设置页和发现页使用不同 URL，不能排除页面加载行为差异；报告没有搜索阶段直接失败证据。
- VerifyWeb.ets:364 在不要求登录 Cookie 时允许保存会话；并未核验业务页是否通过挑战。当前提示是“网页会话已保存，请重试搜索或刷新目录”。点击完成不构成过盾证明。
- WebView 成功响应固定为兼容 status=200、statusCodeAvailable=false（WebBookFetchRuntime.ts:513），所以 ok=true、len>1000 不能作过盾验收标准。
- 脚本 HTTP 请求 primary=false（NativeScriptHost.ts:364），不会自动走主请求的挑战识别。书源需要识别响应后主动 browser.verify；完整脚本未提供，无法确认该逻辑。
- 解析单测通过只能证明所测 HTML／JSON 的规则正确，不能证明完整书源、请求、预算和状态处理均正确。
- 补齐或改善宿主不能承诺支持全部 CF 站点；应按具体业务内容验收。

## 已执行验证

- 本轮：`node --experimental-strip-types scripts/native-script-check.mjs`（引擎目录），125 项断言通过。
- 本轮：`node scripts/network-compatibility-check.mjs`，网络兼容、分区 Cookie 注入、显式头优先和 UA 大小写检查通过。
- 本轮补充：`node --experimental-strip-types .codex_tmp/webview-report-code-probe.mjs`，搜索／发现／动作同请求与字段保留、耗时未暴露、宿主存在但无 onPageEnd 返回空正文四组检查通过。
- 同会话前一轮：web-verification-check 与 web-request-deadline-check 通过，覆盖宿主恢复、取消、POST 不重放、Cookie API 分支与总预算。

以上使用受控替身；没有宣称实际 CF 站点已经修复。

## 建议顺序

1. 核对现场构建，补齐能穿过脚本与 UI 的失败原因和耗时。
2. 改善显式 waitFor 的就绪判定与失败快照，分别测试持续加载、持续 DOM 变化、缺失回调和真实选择器不匹配。
3. 贯通发现页取消，测试快速切分类、刷新与共享队列竞争。
4. 同一构建、同一 URL、同一 UA 和参数对照三个入口；以业务内容及解析结果验收 Cookie／CF 全链路。
