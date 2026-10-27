# 原生书源补充能力：实施与验证记录

日期：2026-10-26。对应 [实施清单](native-source-capability-followup-plan.md)。本轮实现属于 4.4.934 开发构建，尚未发布正式安装包；设备端完整验收仍有待完成项。

## 已实现

| 项目 | 结果 |
| --- | --- |
| 响应头 | 原生脚本增加 headers、headersAvailable、requestId；小写键名、多值规范化、失败 HTTP 响应保留头；WebView DOM 不冒充原始响应头。底层兼容接口保留原有头格式 |
| 请求诊断 | 现有调试页显示通道、请求编号、策略重试次数/原因、传输尝试、请求/响应头；传输层入参不标为抓包结果；字符数与未测量的网络字节数分开 |
| 聚合 | http.all 默认保持逐项返回；failOnPartial:true 等批次完成后抛成功/失败数和零基失败索引；取消、参数错误、脚本预算仍独立处理 |
| 重试 | retry 数字兼容；对象支持 times/onStatus/backoff/base/maxDelay/respectRetryAfter。GET/HEAD 无请求体时可重放；对象策略关闭叠加的自动协议/超时/浏览器回退；退避支持取消且不刷新预算 |
| 变量类型 | options/default 显式支持字符串和有限数字，使用时转文本；拒绝对象、布尔值、null 等非约定类型 |
| 脚本耗时 | QuickJS 会话输出 cpuMs 和总耗时，超时包含已用毫秒；保留 2 秒上限 |
| 媒体请求 | 漫画链路允许合法自定义头，拒绝传输控制头和换行；带头缓存使用 SHA-256 身份。带自定义头时截停 SDK 自动重定向，由应用逐跳请求；跨 origin 移除自定义头和凭据，最多 8 跳且共享截止时间。要求 API 22+ 且拦截器可用；不支持时请求前失败。音频本已支持显式自定义头，本轮未改播放器 |
| 文档 | 更新响应模型、严格聚合、条件退避、WebView 与交互验证区别、变量、keep、脚本命名空间及选择器示例 |

入口位于引擎 core/http、core/nativesource、BookSourceDebugModels，以及宿主 BookSourceDebug.ets 和 ComicImagePipeline.ts。公开接口说明见 [书源开发文档](../harmony-book-source-engine/docs/book-source-development.md)。

## 已执行验证

以下检查在 Node 中执行。网络与设备 API 使用替身，验证真实业务代码的调用和状态变化，不代替设备 SDK 行为。

| 检查 | 结果 |
| --- | --- |
| native-source-check | 250 项断言通过 |
| native-js-check | 34 项断言通过 |
| native-script-check | 114 项断言通过，含工作线程响应头、失败状态、乱序聚合、严格模式、空批次与数字变量 |
| network-compatibility-check | 通过；含最终响应头、默认 UA、自定义头入参、429/503 重试、403 不匹配、次数上限、Retry-After 秒/日期、超大等待不提前重试、取消、总超时、POST 不重放、禁止重复降级、媒体跨域凭据与旧 API 失败 |
| source-followup-diagnostics-check | 通过；含头/地址脱敏、单位、QuickJS 成功/超时计时回调、设备测试源格式校验 |
| comic-image-pipeline-check | 通过；含自定义头、非法头、缓存身份隔离、不支持拦截时明确失败，以及原有图片处理回归 |
| audio-rule-support-check | 39 项断言通过 |
| web-request-deadline-check | 通过；浏览器排队、超时、取消和迁移 |
| native-comment-page-check / native-comment-page-service-check | 通过；评论上下文、预算、取消及响应大小 |
| 主仓库和引擎中立性检查 | 通过 |
| 两仓库 git diff --check | 通过 |

首轮源码修改后 HAP 构建成功（57 个任务，29.318 秒）；媒体逐跳修复构建成功（30.796 秒）；补齐空重定向响应体处理后成功（14.360 秒）；增加报告性能摘要后成功（13.166 秒）；最后增加显式大目录检查开关后成功（13.603 秒），已安装并启动最新包。构建使用本地安装的 @deveco-codegenie/mcp 0.2.6 的 build_project，目标 entry@default、debug。完整日志保存在工作区 `.codex_tmp/native-followup-build.log`。构建保留项目原有废弃 API 等警告，不宣称零警告。

check_ets_files 已尝试，工具返回“LSP 未初始化，请尝试调用 project_sync”；该安装版本未提供 project_sync。独立 LSP 检查未完成，以完整 HAP 编译的 ArkTS 检查结果作为构建验证。

## 设备验证边界

- 已识别连接设备为 API 26，并通过 start_app 安装、启动本轮构建包。
- 首轮自动 UI 输入未完成；随后由用户手动导入并执行网络测试源，服务端已收到请求和通过报告，结果见下。
- 协助验收使用两个本地服务和三个 HDC 反向端口映射（18390、18391、18392）。基础验收结束后已停止对应 Node 进程，并确认这三个端口无监听、HDC 映射列表为空。用户导入的三个临时源与测试书可在设备内按“Codex临时验收”分组清理。
- 已通过媒体同 origin / 跨 origin 302 的真机验收，用户确认两图显示，服务端确认跨 origin 移除测试头。
- 数字变量已实测：设置页依次选择并保存 3000、600、1000，脚本获取的变量值、服务端请求 count 与实际章节数一致。
- 600 / 1000 / 3000 章完整目录基线已采集，含 3000 章重启后首轮与热运行，以及三档各 6 轮局部解析数据。没有采用外部文档的“慢 8 倍”估算，也未提高计算预算。
- 尚未完成完整设备矩阵：WebView 交互验证入口、取消和超时真机操作、API 20/21 的明确失败提示、其他设备/复杂 HTML 大目录及滚动帧率。

## 可重复的受控设备测试

仓库提供 [测试服务](../scripts/source-followup-device-fixture.cjs)，只监听开发机 127.0.0.1:18390，不访问第三方站点，不保存 Cookie/Authorization。默认测试源禁用搜索与发现参与，仅供手动调试。

```powershell
node scripts/source-followup-device-fixture.cjs
# 另一终端，用已配置的 hdc 可执行文件：
hdc rport tcp:18390 tcp:18390
```

在书源管理 → 从 URL 导入中输入 `http://127.0.0.1:18390/source.json`。选择“Codex网络验收临时源”，在调试页输入任意关键词并开始调试。当前 UI 默认运行全链路，没有阶段切换按钮；该样本的验收依据为搜索阶段的 PASS 报告，后续空目录不作为网络失败。它会验证自定义头、响应头、503 后重试、严格聚合和搜索中的 WebView；通过时返回以 PASS 开头的结果，并把报告送回测试服务。

样本还会在同一脚本会话中对 600、1000、3000 条虚构 JSON 目录各做 6 轮解析，报告每轮 Date.now() 差值。它是合成工作负载的墙钟测量，不能等同复杂 HTML 目录或完整阶段的 CPU 开销；阶段 cpuMs 看调试页 timing 记录。重复运行用于比较热会话，重启应用后再取冷会话数据，记录设备和系统版本。

记录写入 `.codex_tmp/source-device-requests.jsonl`。确认请求头应以服务端日志为准，调试页只显示传给传输层的参数。

结束后删除临时测试源，停止 Node 服务，移除本任务映射：

```powershell
hdc fport rm tcp:18390 tcp:18390
```

## 用户协助的网络实测

设备：HPR-W72；API 26；系统参数 `OpenHarmony-7.0.0.109`，软件版本 `HPR-W72 7.0.0.111(SP12C00E100R12P5)`。应用 4.4.934、本地调试构建；引擎基线 4a11266 加本轮修改（现归档于提交 984bfc8），QuickJS 绑定包 @devzeng/quickjs 0.1.0（包版本不等于上游 QuickJS 核心版本）。

服务端 UTC 2026-10-27 02:35:54–02:35:56 收到设备请求；用户提供的调试报告 sessionId 为 `debug_1793068564149_58797`，搜索步骤 2432 ms、会话 2435 ms。设备与开发机时钟有偏差，跨设备时间不直接相减。

- `/echo` 服务端确认 `X-Probe-Header: probe-value` 与 User-Agent 到达；设备报告读到 `x-probe-response: visible`，`headersAvailable=true`。
- `/retry` 两次请求间隔 88 ms；第一次设备报告状态 503。随后脚本检查第二次为成功且 attempt=2，通过。
- 严格聚合检查 2 成功、1 失败；`browser.render` 返回 render-ok；`http.get({webView:true})` 成功且不伪造响应头可用性。脚本全部通过才会调用 `/report`，服务端已收到 `PASS headers/retry/strict/WebView`。
- `responseChars=327`、`responseBytes=-1`，未把字符数误报为线路字节数。

同一脚本会话内的 JSON 解析与映射墙钟样本（毫秒）：

| 条数 | 六轮实测 |
| --- | --- |
| 600 | 1 / 1 / 2 / 1 / 1 / 1 |
| 1000 | 2 / 2 / 2 / 1 / 2 / 2 |
| 3000 | 5 / 6 / 5 / 6 / 6 / 5 |

以上不代表完整目录阶段 CPU、UI 渲染或冷启动性能。用户粘贴的报告在第三个请求处截断；不据此推断尚未提供的 timing 字段。

## 媒体与完整目录样本

[配套服务](../scripts/source-media-performance-device-fixture.cjs) 监听 127.0.0.1:18391 和 18392，分别作为原始 origin 与跨 origin 目标。同 IP 不同端口属于不同 origin；这覆盖跨 origin 重定向，尚不覆盖不同主机、HTTPS 降级或音频播放器跳转。

```powershell
node scripts/source-media-performance-device-fixture.cjs
hdc rport tcp:18391 tcp:18391
hdc rport tcp:18392 tcp:18392
```

导入 `http://127.0.0.1:18391/sources.json`，得到两个默认禁用的临时源，可在书源操作菜单选择单源“搜索”或“调试”：

关键词需与样本书名匹配：用户用 `a` 搜索媒体源时，服务端正常返回，但应用相关性过滤后结果为空。因此使用下面指定的“媒体”或“目录”，不要按“任意关键词”操作。

1. **Codex媒体跨域验收**：单源搜索关键词“媒体”，打开结果、阅读第一章。蓝图经同 origin 302，必须保留 X-Media-Token；绿图经跨 origin 302，目标必须不收到该头。服务端条件不满足就返回 403。每次生成正文使用新图片地址，避免已有图片缓存掩盖下载。以实际图片显示与服务端记录共同验收，单独正文调试只生成图片地址，不足以证明图片已下载。
2. **Codex大目录验收**：在书源设置选章节数 600 / 1000 / 3000 并保存；调试页输入关键词“目录”，开启开关至“目录检查：最多 3000 章”，再开始全链路。默认关闭时仍只取前 32 章；每次重新进入页面需确认开关。目录脚本真实请求 JSON 并返回全部章节。记录 chapterCount、目录步骤 elapsedMs、toc timing 的计算/总耗时；分别取应用重启后的首轮与连续重复轮次。局部 fetch/parse/map 日志只作辅助。实际阅读页目录滚动性能另行观察。

服务端证据位于 `.codex_tmp/source-media-performance-requests.jsonl`，只记录测试头是否存在及是否匹配，不记录 Cookie/Authorization。`hostCheck=true` 是开发机自检，必须从设备结论中排除。服务端路由、图片格式、头条件和目录条数已通过开发机自检；媒体与完整目录的设备结果见下。

### 媒体首轮发现与修复

用户首轮只看到蓝图。UTC 02:40:38 与 02:40:44 两轮记录均显示：同 origin 图片保留测试头成功；跨 origin 的 18392 目标仍收到 X-Media-Token，因此按测试约定返回 403。原 NETWORK_CONNECT 拦截方式未能保护 SDK 内部重定向，原模拟测试错误地在最终 URL 上调用所有拦截器，不能代表真机行为。

修复改为 REDIRECTION 阶段返回 false，截停自动重定向；HttpClient 以新的请求对象逐跳下载，跨 origin 移除自定义头、Cookie、Authorization、Proxy-Authorization 和 Origin，并禁止 CookieStore 重新注入。最多 8 次、检测循环、共用截止时间与取消控制；跳回原 origin 不恢复移除的头。按 URL 标准解析相对地址、协议相对地址及默认端口；拒绝非 HTTP(S) 和带用户凭据的跳转。

回归模拟已按拦截阶段重写，验证截停跳转、下一次实际发送的头、默认端口归一化、跨域后再跳回、不支持拦截、跳转循环/次数和共享截止时间。首个逐跳包暴露空 302 响应体问题（设备提示 Cannot read property byteLength of undefined），已改为直接读取重定向状态与头、不编码空响应体，并加入缺少 result 的重定向回归。网络、漫画、诊断及中立性检查通过。

最终包真机复测通过：用户确认蓝色、绿色均显示。UTC 02:47:58 的 run=1793069278824 记录中，18391 同 origin 最终图片 `mediaTokenPresent=true` 且匹配；18392 跨 origin 最终图片 `mediaTokenPresent=false`。两条均为 `hostCheck=false` 的真实设备请求。结论限定本 API 26 设备、HTTP 同主机不同端口的 302 场景；其他状态码/多跳、旧系统、HTTPS 和音频不冒充真机通过。

### 完整目录数据采集

首个 3000 章配置的全链路报告 `debug_1793069358792_44811` 状态 passed、总耗时 140 ms；服务端确认请求 `/perf/toc?count=3000` 后进入第一章。但用户输入框截断了报告，未读到目录步骤与 chapterCount，不用全链路耗时替代脚本计算时间。为此复制与导出报告增加前置 summary，包含各阶段耗时、章节数及脚本 timing，完整 session 仍保留。

摘要版重启后首轮 `debug_1793069592424_73804`：3000 条输入的 toc 脚本计算 18.548438 ms、脚本墙钟 94 ms；目录步骤 117 ms、全链路 133 ms，但 chapterCount=32。原因是原调试页硬编码 32 章上限，脚本处理完整输入后只物化前 32 章。因此该轮仅作为脚本 CPU 样本，不作为完整目录阶段基准。现增加显式 3000 章检查开关，默认仍为 32，并在摘要同时显示 chapterCount 与检查上限，防止将抽样误报为全量。

完整目录阶段（开启 3000 章检查上限；毫秒）：

| 样本与会话 | 实际章节数 | 脚本计算 | 脚本墙钟 | 目录阶段 | 全链路 | 状态 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 3000，最新包重启后首轮 `debug_1793069895172_34507` | 3000 | 18.217032 | 117 | 587 | 604 | passed |
| 3000，连续热运行 `debug_1793070057026_8376` | 3000 | 21.929063 | 69 | 574 | 593 | passed |
| 600，同进程切换变量 `debug_1793070103610_35542` | 600 | 5.986719 | 101 | 202 | 214 | passed |
| 1000，同进程切换变量 `debug_1793070176609_78888` | 1000 | 9.014532 | 37 | 186 | 198 | passed |

1000 章的前一轮 `debug_1793070137258_41166` 未开启大目录检查，实际只返回 32 章（计算 10.034687 ms、脚本墙钟 63 ms、目录 85 ms、全链路 97 ms），已从完整目录对照中排除；上表使用补跑的完整 1000 章结果。

这些结果证明样本在当前设备能完成各档目录，且脚本计算远低于默认 2000 ms 预算；不支持据此增加预算，也不把脚本墙钟、目录物化/规则处理及 UI 滚动帧率混为同一指标。此基准使用本地 USB 回环服务与简化 JSON，不代表复杂 HTML 或公网网站表现。完整阶段仅有 3000 章首轮/热运行各 1 次、600 与 1000 各 1 次，不能计算有意义的 P95 或推断冷/热性能差异；600 章墙钟高于 1000 章不构成规模回归结论。

验收结束后删除临时源、停止两项服务，并分别移除三个映射：

```powershell
hdc fport rm tcp:18390 tcp:18390
hdc fport rm tcp:18391 tcp:18391
hdc fport rm tcp:18392 tcp:18392
```
