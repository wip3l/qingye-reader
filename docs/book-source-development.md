# 书源规则开发文档

本项目使用公共书源解析内核 [harmony-book-source-engine](https://github.com/wip3l/harmony-book-source-engine)。规则格式、字段、表达式、选择器及示例在内核仓库统一维护；本文说明当前应用的接入情况、开发入口和操作流程。

- [当前内核的公共书源规则开发文档](../harmony-book-source-engine/docs/book-source-development.md)：第一部分原生书源（推荐），第二部分兼容书源（已过时）
- [开发流程](../harmony-book-source-engine/docs/book-source-development.md#开发流程)、[网页书站示例](../harmony-book-source-engine/docs/book-source-development.md#网页书站示例)、[综合示例](../harmony-book-source-engine/docs/book-source-development.md#综合示例)：从零写一个原生书源
- [字段速查](../harmony-book-source-engine/docs/book-source-development.md#字段速查)、[导入校验与常见报错](../harmony-book-source-engine/docs/book-source-development.md#导入校验与常见报错)、[从兼容书源改写](../harmony-book-source-engine/docs/book-source-development.md#从兼容书源改写)
- [JS 函数库 `js`](../harmony-book-source-engine/docs/book-source-development.md#js-函数库-js)：表达式调用、内置函数、参数与返回值、限制
- [后台脚本阶段 `script`](../harmony-book-source-engine/docs/book-source-development.md#脚本阶段-script)：请求、状态、登录、网页交互、完整示例与排错
- [网页验证与会话诊断](../harmony-book-source-engine/docs/book-source-development.md#网页验证与会话诊断)：阶段差异、UA 传递、分区 Cookie、验证后继续、错误码及验收边界
- [封面解密 coverDecode](https://github.com/wip3l/harmony-book-source-engine/blob/main/docs/book-source-development.md#加密封面-coverdecode)：含封面请求头 `coverHeaders`
- [自定义图片字节脚本](../harmony-book-source-engine/docs/book-source-development.md#自定义图片字节脚本)：`content.imageDecode.script`，以及标准算法的 `ivPrefixBytes`、`keyEncoding`
- [视频网页回退](../harmony-book-source-engine/docs/book-source-development.md#视频网页回退)：`content.videoPage`、声明式与脚本示例、错误处理及播放限制
- [宿主图片加载接入](https://github.com/wip3l/harmony-book-source-engine/blob/main/docs/cover-decoding.md)
- [内核 HAR 接入说明](https://github.com/wip3l/harmony-book-source-engine/blob/main/sourceengine/README.md)

本仓库以子模块 `harmony-book-source-engine/` 引用内核，克隆后先执行 `git submodule update --init`。应用使用子模块固定的内核提交，内核新增的规则能力要等子模块升级后才在应用里生效；[在线主分支文档](https://github.com/wip3l/harmony-book-source-engine/blob/main/docs/book-source-development.md)可能领先于当前应用。

## 网页验证更新与开发检查（2026-10-29）

以下对应包含本轮引擎与应用修复的 **4.4.938 本地开发构建**，已编译、签名并安装到 HPR-W72（API 26），启动与进程检查通过。不代表此前发布的所有同版本安装包都具备这些改动。

| 更新内容 | 对书源开发者的影响 |
| --- | --- |
| 设置页网页宿主 | 动作、动态选项等可直接发起显式网页抓取；修复首次加载时序，退出页面后取消所属任务；打开验证页等待用户操作不会被误当成取消 |
| 独立网页验证入口 | 在书源设置中可主动打开验证页，无需为了显示入口添加假的 `login` 配置；搜索/发现仍需点“去验证”并重新发起 |
| UA 对齐 | 原生请求、隐藏网页抓取、可见验证页使用相应 UA；请求单独覆盖 UA 时，调用 `browser.verify(url, hint, { userAgent: ua })` 传入同一值 |
| 分区 Cookie 复用 | API 26 原生请求与脚本 `cookie.get` 纳入第一方分区 Cookie；无需新增 JSON 字段；显式 Cookie 头仍优先，避免旧手工头覆盖新会话 |
| 真实状态与结构化错误 | HTTP 脚本结果增加 `statusCodeAvailable`、`errorCode`、`errorStage`；网页抓取的兼容 200 不代表原站返回 200 |
| 会话状态与搜索诊断 | 设置页区分已保存会话与登录状态；搜索日志区分返回、过滤和展示条数；调试页展示宿主等待、排队、渲染耗时 |

规则接口、错误码表及可复制函数片段统一维护在公共文档的[网页验证与会话诊断](../harmony-book-source-engine/docs/book-source-development.md#网页验证与会话诊断)。新增示例分别覆盖搜索提示用户验证，以及设置页 `browser.verify` 后继续抓取业务元素。不要把“完成”或存在 Cookie 当作已经通过人机验证。

开发时按以下顺序检查：

1. **先验证普通请求**：检查 `ok`、`statusCodeAvailable`、业务内容与请求编号；明确挑战特征后再调用 `browser.verify`，不要对所有 403 无条件打开网页。
2. **区分阶段**：搜索/发现会结束当前阶段，用户完成验证后手动重试；允许交互的设置页动作可在点“完成”后继续。`browser.open` 不等待结果。
3. **核对同一次操作的 UA 和 Cookie**：优先复用 `device.ua`；检查是否存在显式旧 Cookie 头。不要将 clearance 复制到其他域名。
4. **检查等待条件与预算**：`waitFor` 选择业务元素；网页超时单位为秒，请求总预算为毫秒；队列和宿主迁移共享预算。`WEB_HOST_CHANGED` 下不要自动重放 POST。
5. **对照实际展示**：搜索脚本条数、有效条数、去重/精确匹配/上限、相关性过滤、展示条数逐层检查；不能仅凭调试返回列表断言搜索 UI 丢数据。

### 本地样本与回归入口

完整受控样本由 [web-verification-device-fixture.cjs](../scripts/web-verification-device-fixture.cjs) 提供，包含 UA 校验页面、设置页“网页抓取诊断”“验证后继续抓取”动作、搜索和发现入口。它是诊断样本，不是真实站点书源，默认禁用。开发机启动服务并建立设备映射后，在设备导入 `http://127.0.0.1:18393/source.json`；搜索关键词为“网页验证验收”。启动、设备测试与清理步骤见[实施与验收记录](cf-challenge-repair-validation.md#可重复执行)。

```powershell
node scripts/web-verification-check.mjs
node scripts/network-compatibility-check.mjs
node harmony-book-source-engine/scripts/native-script-check.mjs
```

这些 Node 回归检查业务契约；设备运行时测试另行执行。已有 API 26 证据覆盖冷启动抓取、宿主恢复、取消、UA 比对、原始状态可用性，以及 SDK 分区 Cookie 读取与根路径清理。真实 CF 案例、可信 HTTPS Cookie 收发、重启持久化、不同 Domain/Path、完整页面交互矩阵及旧系统真机尚未全部验收。详见[完整实施与验收记录](cf-challenge-repair-validation.md)。

## 视频播放接入

视频书源使用 `type: "video"`，`content.video` 返回媒体直链，新增的可选字段 `content.videoPage` 返回当前集的原站播放网页。字段规则和示例统一维护在公共文档的[视频网页回退](../harmony-book-source-engine/docs/book-source-development.md#视频网页回退)章节。

在包含该功能的应用开发构建中，从「剧集详情 → 开始观看」或书架进入播放页后，优先原生播放；明确不支持视频规格且有网页地址时自动回退。网络或未知播放错误重新获取直链一次，仍失败时可手动选择「网页播放」。只提供网页地址时，也通过播放页按钮手动进入。未配置有效 `videoPage` 的书源不会自动打开章节接口。

网页模式支持应用选集、上一集、下一集、刷新网页、重试原生和全屏返回。网站自己的进度、倍速、清晰度与连播由网站控制；应用仅保留进入网页前的原生进度，不把网页中的选集和播放秒数同步到书架。后台暂停网页媒体，回到前台后手动继续播放。

开发时注意：

- `videoPage` 是字段规则；固定地址写为 `"= 'https://example.com/watch/1'"`，接口字段可以写 `"$.webUrl"`。不能直接把不含模板的固定 URL 当选择器规则填写。
- 媒体请求头不会注入回退网页，当前原生 `Video` 组件仍不发送 `mediaHeaders`；网页使用对应域的 ArkWeb Cookie。网页回退不保证解决编码、鉴权或站点限制。
- 通用正文调试不启用视频专用回退，空直链仍可能报错；仅网页的视频源需要进入实际播放页验证。
- 该能力已通过自动化检查和构建，MateBook Fold 已安装启动；真实不支持格式的视频、网站登录及网页全屏仍需实际书源验收，不代表此前发布的所有同版本安装包已支持。

## 本轮新增与变更（2026-10-26）

以下内容对应本工作区包含本轮改动的 4.4.934 开发构建，已经编译并安装到 API 26 设备验收；不表示此前发布的所有 4.4.934 安装包都包含这些功能。规则接口在公共文档维护，本页记录应用接入及操作变化。

| 内容 | 增加或变更 | 开发文档入口 |
| --- | --- | --- |
| 响应头与请求编号 | 脚本 HTTP 结果新增 `headers`、`headersAvailable`、`requestId`，失败状态也保留可观测响应头；WebView DOM 不伪造头 | [响应头读取](../harmony-book-source-engine/docs/book-source-development.md#读取响应头与关联请求) |
| 严格批量请求 | `http.all(..., { failOnPartial: true })` 整批完成后汇总失败数量、索引与请求信息；默认逐项返回保持不变 | [脚本阶段接口](../harmony-book-source-engine/docs/book-source-development.md#脚本阶段-script) |
| 条件重试 | `retry` 增加状态码、固定/指数退避及 Retry-After 对象策略，重试受取消和总预算约束；数字形式兼容 | [条件重试](../harmony-book-source-engine/docs/book-source-development.md#条件重试) |
| 数字变量 | 静态 `vars[].options/default` 接受字符串和有限数字，运行时按文本使用；已实测设置页选择、保存和后续请求取值 | [变量与书源设置](../harmony-book-source-engine/docs/book-source-development.md#书源变量-vars) |
| 漫画自定义请求头 | 允许合法自定义头，缓存按头隔离；同 origin 跳转保留、跨 origin 移除自定义头及凭据。修复 SDK 自动跳转继续携带头，以及空 302 响应体报错 | [媒体头与重定向](../harmony-book-source-engine/docs/book-source-development.md#媒体请求头与重定向) |
| 网络与脚本诊断 | 增加请求编号、传输/尝试信息、请求/响应头和脚本计算/总耗时；正文字符数与未测量的线路字节数分开显示 | [单书源调试](../harmony-book-source-engine/docs/book-source-development.md#单书源调试) |
| 报告与大目录检查 | 复制/导出报告前置 `summary`；新增“目录检查：最多 3000 章”开关，报告同时显示实际章节数和检查上限 | 见下方操作说明与真机基准 |

WebView、`browser.render`、默认 User-Agent、按钮上下文和详情 `keep` 原本已支持，本轮完善说明及验证。脚本计算预算仍为 **2 秒**；没有增加到 5 秒，也没有新增通用挑战页自动回退。漫画的逐跳策略不代表音频播放器内部重定向也已采用同样处理。

## 原生 JS 开发路线

当前原生书源已经支持 JavaScript，无需打开“脚本引擎迁移”的灰度开关。按任务选择写法：

| 需求 | 写法 | 运行位置 |
| --- | --- | --- |
| 拼接地址、字段转换、选择器提取 | 声明式规则、表达式、`lib` | 原生规则解析器 |
| 签名、解密、复用纯 JS 算法 | 顶层 `js` 定义函数，在表达式或模板中按名调用 | 主线程同步 QuickJS；单次最多 300 ms，不能请求网络或写状态 |
| 先取令牌再请求、批量取详情、自行分页 | `search/explore/detail/toc/content.script` 指定 `js` 中的函数名 | 后台 QuickJS；同步写法调用 `http` 等宿主接口 |
| 多步登录、发送验证码 | `login.script`、`login.sendCode.script` | 后台脚本，表单值从 `ctx.form` 读取 |
| 设置页按钮、动态下拉选项 | `actions[].script`、`vars[].optionsScript` | 后台脚本；按钮返回提示，选项返回字符串数组 |

`js` 是 JSON 中的一段字符串，换行需要写成 `\n`，也可以先在编辑器里编写 JS 再用 `JSON.stringify` 转成 JSON 字符串。原生规则不使用兼容书源的 `@js:`、`<js>`、`jsLib` 或 `java.*` 写法。

JS 中调用内置函数时使用 `native.split(text, ',')` 等写法。若报未定义错误，按提示核对 `native.` 前缀；导入校验通过并不保证未执行的函数体没有错误。详见公共文档的 [JS 函数库说明](../harmony-book-source-engine/docs/book-source-development.md#js-函数库-js)。

脚本阶段返回的是供规则解析的页面或 JSON，不必手动构造应用的数据库对象。返回后仍可使用 `let`、`fail`、`list`、`fields` 和正文提取规则；返回数组且省略 `list` 时逐项解析。目录与正文的脚本要自行完成分页，`nextUrl` 不再生效。完整接口、状态作用域和可复制示例见公共文档，不在此维护第二套规范。

## 在应用中开发与验证

1. 在「我的 → 书源管理 → 新建原生书源」编辑完整 JSON，先“校验”再“保存”。校验检查定义和函数等约束，不代表网站链路已经可用。
2. 打开“调试”，输入能匹配样本书名的关键词并开始。书源管理入口默认运行全链路，没有阶段切换按钮；脚本请求、`log(...)` 与结果摘要出现在执行明细中，报错会带阶段和函数名。若单源搜索无结果，先排除关键词相关性过滤。
3. 打开“书源设置”，分别验证变量保存、动态选项、登录、验证码和动作按钮。先保存手动修改的变量，再执行依赖这些变量的按钮；按钮执行时显示忙碌状态，结束后刷新登录状态和动作列表。
4. 实测需要验证的流程：搜索和发现提示“去验证”后，完成网页操作并重新发起请求；详情、目录、正文或设置页脚本调用 `browser.verify` 时，点网页右上角“完成”才会继续，返回或取消会报“网页操作已取消”。
5. 从仓库根目录运行下面的规则回归；在真机上通过「其他设置 → 兼容与诊断 → 脚本引擎迁移 → 后台脚本线程验证」检查原生运行时，再验收真实页面交互。

```powershell
node --experimental-strip-types harmony-book-source-engine/scripts/native-source-check.mjs
node --experimental-strip-types harmony-book-source-engine/scripts/native-js-check.mjs
node --experimental-strip-types harmony-book-source-engine/scripts/native-script-check.mjs
```

Node 检查使用替身，不会验证真机 QuickJS、系统网页控件或实际站点登录。遇到“表达式里不能发请求或读写状态”时，将流程移到阶段 `script`；遇到请求次数或运行时间超限时，减少请求、使用缓存或拆分流程。更多原因见公共文档的原生脚本排错表。

### 大目录检查与报告读取

调试页默认只检查前 **32 章**。需要验证 600、1000、3000 章时，打开开关，确认文字为“目录检查：最多 3000 章”，再运行调试；重新进入页面时需再次确认。该开关只改变调试取样数量，不是书源字段，不改变正常阅读的目录上限。

“复制调试内容”和“导出报告”都在完整 `session` 前放置 `summary`，优先展示会话编号、阶段状态、阶段耗时、实际 `chapterCount`、检查上限及脚本 timing。长报告在聊天输入框被截断时，仍可先读到这些关键指标；需要完整网络轨迹时导出 JSON 文件。

- **脚本计算**：QuickJS 实际计算耗时，用于核对默认 2 秒预算。
- **脚本总耗时**：包括脚本调用宿主接口时的等待。
- **目录阶段耗时**：还包含脚本结果返回后的字段解析和章节处理。
- **实际章节数**：必须与样本规模一致；脚本读了 3000 条而 `chapterCount=32` 时，仅完成了取样，不能当作完整目录结果。

网络明细中的头是传给传输层的参数，需通过服务端回显确认到达情况；`responseChars` 是字符数，`responseBytes=-1` 是未测量网络字节数。敏感头会脱敏，但分享报告前仍需检查规则和正文预览里的业务数据。

### 本轮真机基准

设备为 HPR-W72、API 26，测试使用 USB 反向映射的本地受控服务和简化 JSON。网络回显、响应头、503 重试、严格批量失败及 WebView 抓取已通过；漫画同 origin / 跨 origin 的 302 跳转由图片显示和服务端收到的头共同核验通过。

| 完整目录样本 | 脚本计算 | 脚本总耗时 | 目录阶段 | 全链路 |
| --- | ---: | ---: | ---: | ---: |
| 600 章 | 5.99 ms | 101 ms | 202 ms | 214 ms |
| 1000 章 | 9.01 ms | 37 ms | 186 ms | 198 ms |
| 3000 章，重启后首轮 | 18.22 ms | 117 ms | 587 ms | 604 ms |
| 3000 章，连续热运行 | 21.93 ms | 69 ms | 574 ms | 593 ms |

各轮实际章节数均匹配配置，支持继续保留当前计算预算。完整阶段只有上表 4 次样本，不能用来推断 P95、冷/热性能差异、复杂 HTML 或公网表现，也不代表目录滚动帧率。交互式验证、取消/超时真机操作、旧系统与音频重定向仍需对应验收。

完整证据、脚本与复现步骤见[本轮验证记录](native-source-capability-followup-validation.md)和[实施清单](native-source-capability-followup-plan.md)。临时测试服务及端口映射已停止；复测时按记录重新启动。

## 宿主实现差异

网络选项位于“其他设置 → 兼容与诊断”：HTTP/1.1 兼容模式与图片下载并发（4/8/12，默认 4）均在本机保存。图片并发与脚本 `http.all` 的并发是两套独立限制；提高图片并发不会取消前台保留名额。详见[图片并发真机验证方法](image-concurrency-validation.md)。脚本请求的 `timeout`、`http.all` 选项及 `finalUrl` 语义见公共文档的“脚本阶段”接口表。

本次新增的原生内联评论页使用 `content.comments.page/chapterPage`：点击气泡后才执行页面的附加请求，再在隔离的离线 Web 中显示 HTML 和数据。阅读器支持标题、高度、取消和备用 URL；调试页支持按入口生成并预览。字段、预算、旧宿主兼容与示例见[公共文档的内联评论页](../harmony-book-source-engine/docs/book-source-development.md#内联评论页点击后取数和生成-html)。这些能力以包含相应改动的构建为准，不代表先前同版本安装包已经具备。

可导入[离线示例](../harmony-book-source-engine/docs/examples/native-inline-comments.json)验证交互；该示例无需网络，且仅面向支持 page/chapterPage 的宿主。完整验证命令和平台边界见[实施验证记录](source-capability-validation.md)。

| 能力 | 当前应用现状（4.4.940） |
| --- | --- |
| 原生书源 | 支持编辑、书源设置（变量、音色、账号登录、动作按钮）、搜索、发现、详情、目录、正文、听书、视频播放与漫画图片解密；书源管理和发现页的长按菜单可进入书源设置 |
| 原生 JS | `js` 函数库与 `script` 阶段已接入；`http`、变量、Cookie、缓存、凭据和详情书籍变量通过内核宿主接口处理，与兼容书源迁移开关独立 |
| 原生 HTTP 与诊断 | 本轮开发构建支持响应头/可用性标记/请求编号、严格批量失败与对象式条件重试；复制/导出包含前置性能摘要，目录调试可选最多 3000 章 |
| 漫画媒体自定义头 | 本轮开发构建允许合法自定义头；API 22+ 且拦截可用时逐跳下载，同 origin 保留、跨 origin 移除。已在 API 26 设备验证 HTTP 302；音频播放器内部跳转另验 |
| 原生脚本界面交互 | 启动时通过 `NativeSourceInteraction.setHandler(new AppSourceInteraction(...))` 安装提示、发现缓存失效和网页处理器；`ui.toast` 显示书源名称与消息，`ui.refreshExplore` 清除该源发现缓存 |
| 原生网页交互 | `browser.verify` 沿用内置验证页，点“完成”返回 HTML 并保存 Cookie；搜索和发现只提示“去验证”。`browser.open` 打开网页但不等待结果；`browser.render` 使用内核网页抓取宿主 |
| 设置页脚本 | 动作按钮运行中显示状态并防止重复执行；动态选项获取失败时保留静态选项并显示原因；成功加载后若原值不在新列表中，会选中第一项并标记待保存 |
| 封面解密 `coverDecode` | 已接入：封面下载时识别 `SourceCoverUrl` 标记，从数据库取该书源后调用 `SourceCoverLoader` 解密并缓存到本地；书架、搜索与发现结果、详情页、听书页、目录面板、阅读统计、桌面卡片和朗读媒体卡片都显示解密后的封面，解密完成前显示占位。局域网阅读的封面接口同样转发解密后的图片。解密结果按封面地址缓存，书源改了 `coverDecode` 参数后，已缓存的封面不会自动重新解密 |
| 正文图片解密 | 漫画图片与正文插图下载后按 `content.imageDecode` 解密：支持标准算法、`ivPrefixBytes:16`、`keyEncoding`，以及在后台 QuickJS 里运行的 `imageDecode.script` 字节脚本；脚本结果按书源、脚本代码、配置和图片地址缓存，翻章或退出阅读时会取消未完成的解密 |
| 封面请求头 `coverHeaders` | 带请求头的封面经应用下载并缓存，请求头参与缓存标识 |
| 兼容脚本提示 `java.toast` | 详情、目录、正文阶段的提示显示为应用内提示，同一书源的同一条提示 15 秒内只显示一次；原生脚本使用 `ui.toast` |
| 网络错误 | 域名解析失败、超时、连接被拒等直接显示真实原因，不会误报“需要登录或网页验证” |
| 书源导入 | URL、剪贴板、本地文件（可一次多选，合并后统一勾选）和系统“打开方式” |
| 书籍类型 | 以详情阶段的结果为准：搜索或发现列表里标为有声、漫画、视频的书，如果详情接口返回的是小说信息，进入详情后按小说处理；书源的有声版与小说版不要共用同一个书籍 ID。有声书在详情页点“开始听书”直接进入听书页 |
| 书源排序与加入时间 | 新增或导入的书源排在置顶书源之后的最前面；加入时间只保存在应用自己的数据库，随本地备份恢复，不写入书源 JSON、不进入引擎，也不参与云同步 |
| 有声书离线 | 播放与离线下载共用同一套音频地址解析；离线文件按章节地址或标题和音色对应，目录刷新后自动对回新序号。书源无需为离线下载增加字段 |
| 可选宿主端口 `SourceEngineHost` | 不安装，按内核默认行为运行；这不影响独立安装的 `NativeSourceInteraction` 界面处理器与 `BookSourceRuntimeStore` 持久化 |

修改规则格式与开发说明请到内核仓库提交。应用只维护自己的页面、导入与调试操作和宿主接入说明。

## 此前 4.4.934 的 AI 阅读体验验收

- 此前这轮 AI 阅读体验改动没有新增书源字段或改变规则语义；本轮原生接口扩展见本文开头。漫画超分的核对与合成改在原生库完成、相邻页提前处理，处理中提示与条漫翻屏动画均为应用侧改动；4.4.931 起的书源均可直接使用。图片仍在下载、解密与重排之后才交给本机 AI 处理，书源不需要为 AI 处理做调整。

## 4.4.933 验收补充

- 本版没有新增书源字段或改变规则语义，主要是阅读体验与 AI 着色的应用侧改动；4.4.931 的书源均可直接使用。

## 4.4.931 验收补充

- 原生内联评论页 `content.comments.page` / `chapterPage` 已接入：点击气泡后才执行页面的附加请求，HTML 在隔离的离线网页中显示。可先导入内核仓库的[离线示例](../harmony-book-source-engine/docs/examples/native-inline-comments.json)验证。
- 网络选项（HTTP/1.1 兼容模式、图片下载并发 4/8/12）只在本机生效，不写入书源；`http.*` 结果的 `finalUrl` 拿不到时为空，书源不要假定它一定存在。

## 4.4.930 验收补充

- 原生书源在后台线程做纯解析时只送纯选择器规则；超出限额或出错的规则回到当前线程按原方式执行，结果不变。书源字段与脚本接口没有变化。
- 漫画着色、超分和翻译在原图下载、解密与重排之后由本机处理，不新增书源 JSON 字段，书源不需要为此做任何改动。

## 4.3.929 验收补充

- 原生图片字节脚本支持 `image.reorderStrips(bytes, options)` 横条重排。文件可正常解码但内容条带乱序时，设置 `content.imageDecode.processPlainImages: true`，避免明文图片直接跳过脚本。参数、尺寸和预算以[公共规则文档](../harmony-book-source-engine/docs/book-source-development.md#自定义图片字节脚本)为准。
- 漫画阅读先返回完整的图片清单，再逐张下载、解密和显示。书源的 `content.script` 只需返回原始地址列表，不要在生成清单时处理整章图片；请求头、解密参数、图片索引与尺寸会保留到后续加载。手动缓存与全文缓存仍等待图片处理完成，有失败图片的章节不写入正文缓存。
- 应用的 `ReaderImageScheduler` 为当前章、相邻章预加载及全文缓存分配全局最多 4 个图片处理名额；可见图片优先，其次附近图片。前台繁忙时后台最多 1 个名额，空闲时最多 2 个。图片脚本另受内核执行器的会话预算约束，调度上限不是书源字段。
- 漫画 OCR 与繁→简属于阅读器本地显示功能，在原图片下载、解密或重排后处理，不新增书源 JSON 字段，也不要求书源上传图片或接入翻译服务。日／英／韩→中尚未实现。
- 验收分别覆盖普通图片、带请求头图片、加密图片、条带重排、单图失败与重试，以及快速翻章后的取消；关闭繁→简应恢复原图显示。

## 4.3.928 验收补充

- 发现页 `dynamicMenus` 可写 `script`：函数返回分类数组，或按行（或 `&&`）分隔的“名称::地址”文本，没有 `::` 的行是分组标题。
- 顶层 `headers` 在每个请求上按当前作用域求值（各阶段、分类、附加请求、动作按钮、登录和脚本里的 `http.*`），与本次请求的请求头合并，同名以本次请求为准；动态请求头可以直接写成表达式或模板。
- 写了 `optionsScript` 的变量，保存的值不再因不在静态 `options` 里而回退到默认值。
- 一章里单张图片下载或解密失败只影响这一张，原位显示原因；`data:` 内嵌图片也按 `imageDecode` 处理。含失败图片的章节不写入正文缓存。
- 正文缓存有 256 MiB 上限，自动清理只针对阅读和预缓存顺带写入的章节，“缓存全文”“缓存指定章节”写入的不会被清掉。

## 4.3.927 验收补充

- 验证漫画图片解密时分别检查标准算法、`ivPrefixBytes:16` 和 `imageDecode.script` 三种写法；脚本报错会带上 `content.imageDecode.script (函数名)`。
- 原生书源误用 `book.url` 时调试页会提示改用 `book.bookUrl`；分类菜单可单独设置 `list`、`fields`。
- 书源规则与脚本接口之外，本版主要是应用侧改动（会员与云同步、书架与阅读体验），不改变公共书源字段。

## 4.2.925 验收补充

- 原生书源的 JS 函数库与后台脚本阶段均已接入。验证登录、验证码、动态变量选项和动作按钮时，同时检查执行状态、失败提示及发现缓存刷新。
- 验证正文插图时，应确认下载缓存后的图片能够显示；多行 HTML 属性（例如 og:description）应完整提取。
- 书架关键词、标签和书源筛选属于应用侧功能，不改变公共书源字段或脚本接口。

## 4.4.935 发布核对

本版本纳入上文记录的 4.4.934 开发构建能力，包括响应头与请求编号、严格批量请求、条件重试、数字变量、漫画自定义请求头及调试报告。此前的设备验收记录保留原日期；本次发布打包不代表重新执行了全部真机用例。

书列表 JS 字段批处理已修复对象返回表达式，编写搜索与发现规则时应检查批处理结果与单字段求值一致，尤其注意对象字段、空值和数组结果。阅读统计同步、键盘翻页、持握手、分享海报和精细字重属于宿主功能，不新增书源格式字段。

## 4.4.936 发布核对

本版本纳入 `content.videoPage` 视频网页回退及原生 JS 错误提示改进。视频回退需明确声明当前集的 HTTP/HTTPS 原站网页，不从媒体直链或章节接口推测；实际播放页与通用正文调试的处理范围不同，详见上文。

原生 JS 内调用规则内置函数应使用 `native.函数名(...)`；不可把规则表达式的内置名称直接当作 JS 全局函数。相关错误会提示 native 调用方式。朗读音色管理和统计页界面属于宿主功能，不新增书源字段。
