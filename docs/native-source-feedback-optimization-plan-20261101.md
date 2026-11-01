# 原生书源反馈复核与优化方案

日期：2026-11-01。基线：应用 `97095afd`，内核 `06f6491`，最低 API 20、目标 API 26。本文是可实施方案，尚未开始修改业务代码。原始判断及逐项核对见 [反馈核查](native-source-feedback-review-20261101.md)。

后续实施进展：变量指纹与 CRLF 已有后续内核修复；评论页已完成主文档导航及初始空白页竞态修复，并通过 API 26 真机验证，详见 [修复记录](native-comment-display-fix-20261101.md)。以下正文保留制定方案时的任务划分；其他扩展任务不视为已完成。

## 1. 目标与复核结论

本轮优先解决评论入口错误失效、评论页失败无法定位、文本清理不一致三类问题。评论页真机超时按高优先级故障调查处理，具体原因待设备证据确认。加载更多和原生评论列表分别作为后续能力建设，不作为修复上述问题的前置条件。

| 编号 | 本轮复核结果 | 优先级与处理 |
|---|---|---|
| R1 | 默认变量未落盘时，脚本保存变量后，当前 Runner 与后续 Runner 的指纹状态不一致 | P1，直接修复 |
| R2 | 声明变量写入数字，保存时转为文本；仅变量对象键顺序变化也会误使入口失效 | P1，与 R1 一并修复 |
| R3 | 评论页依赖 iframe onload 置位，JS 轮询异常被吞掉；没有渲染退出及控制台诊断 | P1，补齐诊断与就绪协议，再按设备证据修复 |
| R4 | 调试页在页面生成结束即记为通过；组件后续显示失败没有回写 | P1，分别记录生成结果与显示结果 |
| R5 | 15 秒显示计时器在 controller 挂载后才创建，挂载前没有对应期限保护 | P1，纳入整个显示尝试的生命周期；尚无“挂载失败”真机复现 |
| R6 | AnalyzeRule.stripHtml 未统一 CRLF；原生表达式与最终正文规范化已有归一化 | P1，限定函数修复，保留现有段间空行策略 |
| R7 | max/height 仅数字、图片脚本无日志、无交互式加载更多、data 不引用兄弟键 | P2，按收益和兼容范围分批处理 |
| R8 | 附件跨站评论只按段落编号加固定偏移匹配，章名存在宽松回退 | 书源自身优化；不通过引擎猜测映射补救 |

复核程序新增 5 组变量对照，结果如下：

| 用例 | 当前结果 | 优化后的目标 |
|---|---|---|
| 空保存记录，使用默认 mode 后写 chapterState | 入口失效 | 当前状态未再改变时可打开 |
| mode 已保存，再写 chapterState | 正常 | 保持正常 |
| limit 已保存为文本，脚本写数字 2000 | 入口失效 | 按声明变量的文本语义保持可打开 |
| 同上，脚本写文本 '2000' | 正常 | 保持正常 |
| a/b 两个变量的值不变，仅 JSON 键顺序互换 | 入口失效 | 保持可打开 |

另外，对实际组件方法注入已失效的超时回调，会终止新一代显示尝试。它暴露了超时闭包缺少代次校验；该受控回调测试不证明 ArkWeb 或定时器在真机上必然产生同样交错，也不作为本次超时根因。

## 2. 当前链路与目标链路

```mermaid
flowchart LR
    A[正文与评论统计] --> B[生成入口和有界上下文]
    B --> C[点击时校验状态与段落]
    C --> D[取评论并生成 HTML/data]
    D --> E[独立离线 Web]
    E --> F[沙箱 iframe]
    F --> G[内容就绪信号]
    G --> H[显示结果回写调试记录]
```

- 内核负责变量身份、上下文、规则求值与生成预算；应用负责 Web 挂载、显示期限、渲染生命周期和用户反馈。
- 调试页和阅读器共用同一显示组件及同一诊断契约，避免预览通过、阅读页行为不同。
- 保留独立无痕 Web、沙箱不授予同源、禁用文件/存储/出站网络和无宿主代理桥。DOM 层的有限就绪消息只更新显示状态，不增加请求、存储或其他宿主操作能力。
- 生成仍有 15 秒总预算，显示尝试另有 15 秒总预算。显示预算从组件收到有效页面并开始本次显示尝试起算，覆盖控制器等待，而不是等挂载成功才起算。

## 3. 第一阶段：直接修复已确认的内核问题

### T1. 统一变量快照和评论身份

主要位置：

- [NativeSourceRunner](../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeSourceRunner.ts:1102)：构造、setVar、inlineKey、缓存重建。
- [NativeSourceService](../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeSourceService.ts:462)：确认宿主保存、读取和同源实例间的一致性。
- `harmony-book-source-engine/scripts/native-comment-page-check.mjs`、`native-script-check.mjs`：加入行为回归。

推荐设计：抽出统一的“有效变量快照”，内容为已保存变量叠加当前声明变量的文本值，等价于现在保存时的 `Object.assign({}, storedVars, varValues)`。保存和 inlineKey 使用同一份值语义，快照应与后续修改隔离。

仅对变量记录使用确定性的 JSON 序列化：对象键按固定顺序编码，数组顺序、值类型及未知脚本变量保留。声明变量按现有文本约定处理，未声明变量不一律转成字符串。序列化只在生成或校验入口时执行，不放入每段循环。

不要将整个 definition 递归排序后参与身份计算：顶层 let 和 fetch 的声明顺序有执行语义，改顺序需要使旧上下文失效。其他身份输入继续保留书源、账号、书籍、章节和段落内容校验。

本项不扩张 vars 的可见作用域，也不把脚本内部变量从失效判据中整体剔除；实际变量值改变仍可能影响请求或页面内容。无效选项值、空值及保存失败保持明确语义，不通过宽松匹配旧摘要来绕过变化检测。

验收：

- 上表 5 组全部符合目标；数字默认值、布尔/空值、嵌套未知变量和数组顺序另有边界用例。
- 相同值重复写入、默认值显式落盘和 JSON 键顺序变化不误失效。
- 真实变量变化、账号变化、书源规则变化、换章、段落变化仍拒绝旧入口；数组重排不能当作相同变量值。
- 暖上下文、5 分钟过期重建和 4 章淘汰后重建保持相同身份规则。若重建脚本又产生真实新状态，不强行沿用旧入口。
- 不改变变量实际持久化格式，不增加数据库迁移。更新前缓存的旧摘要可要求刷新本章一次，发布说明明确这一点；不永久兼容两种摘要而放宽失效检查。

### T2. 修复 CRLF 并明确处理顺序

主要位置：

- [AnalyzeRule.stripHtml](../harmony-book-source-engine/sourceengine/src/main/ets/core/rule/AnalyzeRule.ts:2926)。
- `harmony-book-source-engine/scripts/analyze-rule-check.mjs` 及 HTML 选择器样例。
- [WebBookService.normalizeReaderContent](../entry/src/main/ets/core/book/WebBookService.ts:1391) 和原生表达式 stripHtml 仅作为链路对照，避免重复改动。

在 AnalyzeRule 的 HTML→文本过程中先统一 CRLF/CR，再保留既有标签边界与最多一个段间空行的策略。本项不统一所有清理函数的其他语义：例如原生表达式对块结束标签产生单换行，兼容清理有双换行，这些差异不借本次修复一起改写。

当前正文顺序应公开为：阶段返回值/选择器 → 分页拼接 → content.replace → comments 行号及标记 → 宿主正文规范化。counts 是源提供的最终正文行下标，不会自动跟随替换重新映射。

验收：CRLF/CR/LF、连续 br、p/div、实体和空白段均覆盖；改变只限行尾与其空行压缩结果。纯 LF 存量样例、链接文字、图片标记和动作标记保持兼容。另验证最终阅读文本，避免把函数输出修正误称为所有站点的真机排版已修复。

产出：一组独立的内核修复及回归，不等待评论页真机根因确认。

## 4. 第二阶段：评论页诊断与显示可靠性

### T3. 将生成与显示分开记录

主要位置：

- [NativeCommentPageView](../entry/src/main/ets/components/NativeCommentPageView.ets:32)。
- [BookSourceDebug.previewInlineAction](../entry/src/main/ets/pages/BookSourceDebug.ets:590)。
- [ReadBook](../entry/src/main/ets/pages/ReadBook.ets:3590) 的内联面板接线。
- 应用公共的显示诊断模型/缓冲器，建议放在 `entry/src/main/ets/core/book/`；不放进书源 JSON。

组件提供可选的显示结果回调，由调试页在打开预览前建立记录，再接收 ready/failed/cancelled。生成成功只结束“页面生成”步骤；“页面显示”另有状态，重试各自形成独立 attempt。页面关闭、切换章节或页面销毁记为取消，不把取消伪装成失败或成功。

建议的诊断字段：

| 类别 | 字段或约定 |
|---|---|
| 身份 | 本地 attemptId、generation、入口类型、应用/内核版本 |
| 生成 | generationMs、请求数、HTML/data 字节数、生成错误类别 |
| 显示 | attachMs、loadSubmittedMs、outerBootMs、frameLoadedMs、frameReadyMs、首绘事件耗时、elapsedMs |
| 探测 | pollCount、JS 失败次数、最后一次错误码/脱敏摘要、最后一次结构化状态 |
| 终态 | ready/failed/cancelled；失败阶段区分 attach、outer、frame、probe、render-exit、deadline |

指标未观测到时为未知，不填 0 冒充成功。attachMs 等使用单次尝试内一致的时间基准；页面 performance.now 与宿主时钟不直接相减。JS 异常保留首次和末次摘要，成功时汇总，不每 100 ms 打一条日志。每次尝试建议最多 64 条事件、16 KiB 摘要，超出保留计数和终态。

只收集状态、大小、时间及脱敏错误，不默认保存正文、评论全文、Cookie、令牌或源脚本的任意 console 文本。CSP/控制台信息先做长度限制及脱敏，再纳入摘要。复用已有调试会话与导出功能，阅读页只显示可理解的失败信息和重试入口。

### T4. 保留沙箱，增强就绪协议与生命周期

主要位置：内核 `NativeCommentPage.ts` 的生成文档，应用 `NativeCommentPageView.ets`，以及现有组件/浏览器回归。

推荐方案：

1. 外层引导脚本安装监听器，再挂载沙箱 iframe，明确记录外层引导、frame load 和子文档就绪三个信号；不只依赖 HTML 属性 onload。
2. 内核在子文档注入小型引导代码，在 DOM 已解析后通过 DOM `postMessage` 通知外层；可在可用时等待绘制时机以改善显示体验，但不承诺证明所有业务异步脚本已完成。
3. 外层只接受本次 `iframe.contentWindow` 发出的固定形状消息，检查 generation、尝试标识及预期 sandbox origin。origin 为 null 不能独自识别发送者。该消息只设就绪状态，不携带宿主方法或任意 URL。
4. ArkTS 继续用 runJavaScript 读取外层固定结构的状态；onPageEnd、frame load、首绘仅作为触发探测/诊断，不能独立将错误页判为内容成功。请求层的 waitStage 不复用成显示层的就绪状态。
5. 单次只允许一个探测在途。控制器未挂载也有显示期限；每个计时器、Promise 完成和结果回调均关联 attempt/generation。重试更换控制器时丢弃旧实例信号，终态只提交一次，销毁清理全部 timer。
6. 捕获渲染进程退出，直接形成可定位的失败。不要默认延长预算、循环重建或“到 5 秒强制宣布成功”。保留有界失败和显式重试。

接口依据：本机 SDK 声明 `loadData(...): void`、`runJavaScript(...): Promise<string>`；onControllerAttached 和首绘自 API 10 可用，onConsole 自 API 8、onRenderExited 自 API 9 可用，均低于项目最低 API 20。onPageEnd 文档明确只针对主 frame，不代表 iframe 内容就绪。具体 SDK 类型在实施时按本机头文件核对，不照搬旧示例中的消息桥 API。

DOM 协议依据：[MDN iframe](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/iframe) 说明 load 事件不能证明内容加载成功；[MDN postMessage](https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage) 说明跨窗口消息需检查发送者。这里采用消息协议是设计建议，尚未在目标 ArkWeb 实现及验收。

### T5. 在真机上区分原因，再落地最小修复

先用官方 [离线示例](../harmony-book-source-engine/docs/examples/native-inline-comments.json)，再用随附页面配固定模拟数据。两个样本均零 HTTP、无第三方依赖，不把书源账号或站点当前状态引入显示验证。

| 观察结果 | 下一步 |
|---|---|
| controller 一直未挂载、尺寸为 0 | 修组件/弹层创建与布局时序，记录创建期限；不改网络规则 |
| 已 loadData，外层引导状态不存在或 generation 不符 | 核对初始 about:blank 覆盖、loadData 提交时序、控制器是否已更换 |
| 外层正常、子文档无就绪、存在 CSP/导航拦截 | 对照捕获到的实际 URL、策略和 console，限定修复加载方式；不得通过放开网络或同源权限试错 |
| 外层和子文档均就绪，组件仍转圈 | 修 JS 返回值解析、代次匹配或 ArkUI 状态接线 |
| 渲染进程退出 | 给出明确错误和显式重试，保留退出证据，按对应系统问题处理 |
| 官方示例正常，附件固定数据页面失败 | 缩减具体 HTML/脚本，归为页面样本问题，不泛化为所有内联评论不可用 |

如果 srcdoc 在目标版本确有兼容问题，可比较动态 srcdoc 与沙箱内其他离线文档承载方式。任何候选方案仍需通过同源隔离、无外部请求及 WebRTC 绕过回归。删除 iframe、无痕 Web 单独承载不受信任页面并非已证明等价的默认回退，不在证据出现前选定。

真机最小验收：记录设备型号、系统/API、应用和内核提交及样本 SHA-256；调试预览和阅读页各完成首次打开、5 次重复打开、关闭后重开、重试与换章。每次在期限内得到正确内容或准确错误，不能只看到原生标题就算通过。重复轮数用于暴露生命周期问题，不作为性能统计或全设备覆盖承诺。

## 5. 第三阶段：文档和低侵入的作者体验

### T6. 补齐契约和示例

修改内核 `docs/book-source-development.md` 与 `docs/examples/`，应用文档只说明接入和宿主行为：

- 明确 replace、HTML 清理、comments 行下标和空行的先后关系；提供 lib 从列表生成 counts 的现有写法。
- 列出内联规则求值作用域，区分正文 data、page.fetch 绑定名和注入 HTML 的 page.data；不把 page.data 兄弟键改为隐式依赖顺序。
- 提供箭头返回对象、动态键、fields 的当前 item、keep 非详情阶段报错、temp 生命周期、发现触底分页与停止条件示例。
- 由 builtinNames 生成或校对完整保留名索引；明确 image.hash/hmac 返回 Uint8Array、图片脚本可用接口和源自行 catch 的后果。
- 说明当前脚本 HTTP trace 已有的字段，诊断新增项只填真实可观测数据。
- 为零请求评论样本单独给出可导入 JSON 和版本信息，避免文字声称的开关与实际附件不符。

### T7. 表达式化 max/height（第一批可选功能）

涉及 NativeSourceSpec、NativeSourceRunner、导入校验与打包回归。数字写法保持原行为，新增字符串仅接受明确的表达式或模板，避免把错误字面量悄悄当作配置。

- max 在评论统计作用域求值一次，支持 vars、正文 data、stats；不提供尚不存在的当前 para。表达式结果必须可转有限数字，取整并限制在 1–300；现有数字 0 的默认 60 行为保持兼容。
- height 在点击后的页面作用域求值，允许读取 para/total 和页面 fetch 结果；有限数字限制在 0.2–1。现有数字越界继续按原校验拒绝，新表达式越界行为在规范中统一为运行期字段错误，避免与导入校验矛盾。
- 错误指向具体字段。max 失败只取消评论附加信息，不影响正文；height 求值失败沿用页面生成失败与已有备用 URL 的契约。
- 不新增关闭气泡的 max=0 语义；关闭仍使用 comments.when，避免破坏旧源。

### T8. 工具链和图片诊断（第二批可选功能）

先提供面向作者的定义校验与版本信息；清楚区分 schema/表达式校验、JS 运行、HTML 选择器能力和真机端到端验证。不能将 JSONPath-only 的测试宿主包装成支持全部 HTML 的验收工具，也不能通过放松校验把过时镜像变成成功。

图片诊断先做统一调试预览，输入受控图片与当前 imageDecode 配置，显示前后尺寸、脚本是否执行、类型、耗时及失败原因。若增加 image.log，必须经现有有界图片宿主契约接入，设置数量/长度上限；不向动作脚本开放图片、Cookie、文件等整套环境作为捷径。

## 6. 后续能力的进入条件

| 能力 | 进入开发前必须明确的契约 | 本轮安排 |
|---|---|---|
| 评论加载更多 | 页码/游标、追加去重、无更多、失败重试、关闭取消、连续操作总预算、凭据变化与结果过期；当前 8 请求/15 秒是一次生成预算，不能无限复用 | 显示稳定后单独设计；优先服务于声明式/原生列表，不给任意 HTML 一个通用网络桥 |
| 原生评论列表 | 评论字段、回复层级、纯文本/富文本、空态、时间、头像来源及取消；原 HTML 页继续可用 | 独立扩展能力；原 HTML 能力不在本轮替换 |
| 非空段序号/textMode | 明确标题段、空行、混合图片、替换前后及分页拼接；新模式必须显式开启 | 先文档及诊断，再根据多个样本制定扩展 |
| 图片逐图 when | ctx.url/index/params 作用域、何时判断、普通图跳过、缓存标识和脚本会话成本 | 有测量收益后实施，不因估计的会话次数直接加字段 |
| 源 notice/结构化试读状态 | 展示位置、频率、用户关闭、动态更新及平台付费信号来源 | 产品需求单列；不通过 HTTP 200 或字数推断是否付费 |
| 域名自动回落/分页别名去重 | 稳定书源身份、Cookie/请求头、旧绝对链接、失败重放条件；站点别名须有源声明 | 保留现有变量选 host 和规则过滤，不添加全局路径猜测 |

跨站段评由源作者优先收紧书名+作者和章名唯一匹配；没有目标站段落文本时不能声称完成语义对齐。章节拆分、合并或匹配歧义时应放弃段落级匹配或明确降级为章级评论，不能以 counts 下标全落在范围内作为对齐验收。

## 7. 实施顺序与完成门槛

| 批次 | 任务 | 前置依赖 | 完成门槛 |
|---|---|---|---|
| A，确定性修复 | T1 变量快照 + T2 CRLF | 当前复现样本 | 新行为回归通过，真实状态变化仍失效，文本旧样例兼容 |
| B，显示诊断 | T3 诊断结果接线 | 已明确生成/显示契约 | 调试导出能同时看到两阶段真实结果，错误/取消不误报通过 |
| C，显示可靠性 | T4 就绪与生命周期 + T5 真机定位修复 | T3 可观测 | 双入口零请求样本在目标真机通过；具体根因有证据；隔离回归通过 |
| D，作者体验 | T6 文档 + T7 表达式配置 | 文档可随 A–C 交付；T7 在基础行为稳定后 | 新旧配置均有校验，示例与代码一致 |
| E，独立扩展 | T8 及后续能力 | 各自契约和收益依据 | 独立方案、独立验收，不夹进前述缺陷修复 |

允许分别提交内核变量修复、文本修复和应用显示改进，便于定位回归及按项回退。应用引用内核变更时须同步子模块提交。没有服务端接口、数据库或第三方依赖变更；不改全局代理和用户其他设置。

每一批实现完成后更新根 CHANGELOG.md；README 不追加逐版本更新。发布记录准确区分“加入诊断”“修复已复现的变量问题”和“真机显示已验收”，不提前使用后者。

## 8. 验证矩阵

| 层次 | 必须覆盖的验证 |
|---|---|
| 内核 | 上表变量 5 组、默认/空/数字/对象/数组、真实变化、暖/冷/过期上下文、取消、生成失败与备用 URL、正文不受评论失败影响 |
| 文本 | CRLF/CR/LF、br/p/div、标签文本、实体、图片和动作标记、原生与兼容最终正文对照 |
| 组件方法 | 无 page-end 仍探测、控制器一直未挂载、JS 拒绝/不返回、旧代结果、旧超时回调、重复通知、退出、关闭、重试、换章、终态后零活动计时器 |
| 桌面浏览器 | 实际生成文档：子文档消息、伪造来源/旧代消息、CSP 拒绝、脚本错误、注入文本、按钮交互、Cookie/存储隔离、无外部请求及 WebRTC 绕过 |
| 目标真机 | 官方离线与固定评论样本；调试/阅读两个入口；冷/热打开、关闭/重试、切章与后台；记录准确版本和屏幕结果 |
| 兼容版本 | 最低 API 20 和目标 API 26 均需覆盖。只有 API 26 通过时，只标该版本已验收；其他设备作为明确待验项 |
| 构建 | 相关 ArkTS 检查、完整 assembleHap；内核与应用 diff 检查。保留项目既有警告的准确记录 |

实施时按改动选择现有检查：

```powershell
node harmony-book-source-engine/scripts/native-source-check.mjs
node harmony-book-source-engine/scripts/native-js-check.mjs
node harmony-book-source-engine/scripts/native-script-check.mjs
node harmony-book-source-engine/scripts/native-comment-page-check.mjs
node harmony-book-source-engine/scripts/analyze-rule-check.mjs
node harmony-book-source-engine/scripts/neutral-source-engine-check.mjs
node scripts/reader-comment-panel-check.mjs
node scripts/native-comment-page-service-check.mjs
node scripts/native-comment-page-browser-check.mjs
```

检查通过表示相应层次通过，不替代真机显示。只做方案期间不构建、不安装替换用户正在使用的应用。

## 9. 本轮复核证据与交付状态

已执行：

- `node .codex_tmp/native-feedback-recheck-20261101.mjs`：上述 5 组变量基线、挂载前无计时器、失效回调注入检查均符合当前源码行为。
- `native-comment-page-check.mjs`：通过。
- `reader-comment-panel-check.mjs`：通过。
- `analyze-rule-check.mjs`：464 项通过。这也说明现有成功回归没有覆盖本轮新增的缺陷样例，需要在实际修复时补充。
- 本机 ArkWeb SDK 声明与最低 API 范围已核对。

尚未执行：任何优化实现、目标真机评论页验收、新就绪协议的浏览器验证、完整 HAP 构建。本轮完成的是问题复核与实施方案，不能把待实施任务标为已修复。

新增复核程序及结果分别在 `../.codex_tmp/native-feedback-recheck-20261101.mjs`、`../.codex_tmp/native-feedback-recheck-20261101.json`，不依赖第三方站点，也没有改变原附件。工程原有的其他工作区改动保持原状。
