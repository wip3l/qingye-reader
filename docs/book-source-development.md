# 书源规则开发入口

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

## 书源分组与显示顺序

书源的分组名称来自导入定义和用户手动管理；分组的展示顺序由应用在本机保存，可在书源管理中拖动调整。发现和搜索范围读取同一顺序，重新打开应用继续沿用。拖动排序不修改书源规则，不需要为书源 JSON 添加排序字段，也不改变站内发现分类的 `dynamicMenus` 顺序。

宿主若只持有部分书源（例如发现或搜索筛选结果），应只读取全局分组顺序，不能用局部列表清理未出现的分组。全量书源管理负责合并现有顺序、新分组与用户手动创建的分组。

## 换源与章节更新

换源候选列表可由宿主缓存并跨入口复用；实际切换前需获取并校验完整目录，用户取消、请求超时或目录失败时保留原书及阅读位置。书源应正确返回目录分页与章节身份，不能用局部目录替代完整结果。

书籍“最近更新”按确认发现新章节的时间排序，加入书架、首次加载或没有新章节的刷新不视为更新；该时间由宿主持久化，书源无需新增时间字段。

## 图片处理与显示标识

AI 处理位于图片下载、解密和重排之后。含透明或半透明像素的插图保留原图，避免转为 JPEG 时出现黑框；不透明的 RGBA 图片仍可参与超分。阅读设置的“AI处理标识”只控制处理提示和完成标识，不关闭处理或原页对照，书源无需针对该开关修改规则。

## 开发要点

阅读器的分页、滚动位置和 MiMo 小说朗读属于宿主能力，不要求书源新增字段。正文保持原有内容与段落语义；`readProgressScrollAnchorV1` 是宿主保存的滚动位置，不是业务变量，不能用于评论上下文失效判断。它与阅读时间、分页及朗读位置一样不参与评论入口指纹，详情 `keep` 等业务变量仍参与校验。

宿主版本以 `AppScope/app.json5` 为准，准确的子模块版本用 `git submodule status harmony-book-source-engine` 查看；逐版本变化见[更新日志](../CHANGELOG.md)。

- 逐字遍历使用 `for ch in chars(text)`；`chars` 按 Unicode 码点拆分，在 JS 函数体内调用时写 `native.chars(text)`。导入时会检查声明式规则中未定义的函数名，JS 函数体仍需实际执行验证。
- 声明式 `cache` 取值失败时继续返回 `null`，在调试记录中检查 `cache.名称.url` 或 `cache.名称.value`，并为依赖它的规则准备空值处理。
- 顶层 `headers` 在每个请求上按当前作用域求值，与本次请求的请求头合并，同名以本次请求为准。
- 发现页 `dynamicMenus` 可写 `script`：返回分类数组，或按行（或 `&&`）分隔的“名称::地址”文本，没有 `::` 的行是分组标题。
- 原生书源误用 `book.url` 时调试页会提示改用 `book.bookUrl`；`http.*` 结果的 `finalUrl` 拿不到时为空，不要假定它一定存在。
- 兼容书源的 HTML 文本提取先统一 CRLF 换行；正文空行问题请同时检查原始响应、选择器输出和净化规则。

### 漫画与正文图片

- 漫画阅读先返回完整图片清单，再逐张下载、解密和显示。`content.script` 只需返回原始地址列表，不要在生成清单时处理整章图片；请求头、解密参数、索引与尺寸会保留到后续加载。
- 图片解密分别验证标准算法、`ivPrefixBytes:16` 和 `imageDecode.script`；内容条带乱序而文件可正常解码时，设置 `content.imageDecode.processPlainImages: true` 并用 `image.reorderStrips(bytes, options)`。
- 单张图片失败只影响这一张，原位显示原因；含失败图片的章节不写入正文缓存。`data:` 内嵌图片也按 `imageDecode` 处理。
- 漫画 OCR、繁→简、着色与超分都在原图下载、解密与重排之后由本机处理，书源不需要新增字段。

### 内联评论页

- `content.comments.page/chapterPage`：点击气泡后才执行页面的附加请求，再在隔离的离线网页中显示 HTML 和数据。可导入[离线示例](../harmony-book-source-engine/docs/examples/native-inline-comments.json)验证交互。
- 评论入口按保存后的变量计算指纹；补齐默认值、数字转文本及变量排列变化不使入口失效，最近阅读时间、分页进度和朗读位置也不参与。业务变量（含详情 `keep`）、账号、规则或段落内容变化后应刷新本章再验证。过期入口在错误面板提供“刷新本章”，普通失败可重试。
- 评论页跟随应用深浅色，可用 `@media (prefers-color-scheme: dark)` 适配；写死的白色背景需提供深色覆盖。应用不显示原生标题，标题和条数由 HTML 提供。
- HTML 由宿主以 UTF-8 / Base64 加载，书源填写普通 `html` 即可；页面保持离线，外部资源需在页面生成阶段取回并注入 `data`。调试页的“页面生成”与“页面显示”分别记录结果，只生成 HTML 不算界面验收。

### 网页验证

规则接口、错误码表及可复制函数片段见公共文档的[网页验证与会话诊断](../harmony-book-source-engine/docs/book-source-development.md#网页验证与会话诊断)。书源设置里有独立的网页验证入口，无需为显示入口添加假的 `login`；API 26 上原生请求与 `cookie.get` 会带上第一方分区 Cookie，显式 Cookie 头优先。不要把“完成”或存在 Cookie 当作已经通过人机验证。

开发时按以下顺序检查：

1. **先验证普通请求**：检查 `ok`、`statusCodeAvailable`、业务内容与请求编号；明确挑战特征后再调用 `browser.verify`，不要对所有 403 无条件打开网页。
2. **区分阶段**：搜索/发现会结束当前阶段，用户完成验证后手动重试；允许交互的设置页动作可在点“完成”后继续。`browser.open` 不等待结果。
3. **核对同一次操作的 UA 和 Cookie**：优先复用 `device.ua`；检查是否存在显式旧 Cookie 头。不要将 clearance 复制到其他域名。
4. **检查等待条件与预算**：`waitFor` 选择业务元素；网页超时单位为秒，请求总预算为毫秒；队列和宿主迁移共享预算。`WEB_HOST_CHANGED` 下不要自动重放 POST。
5. **对照实际展示**：搜索脚本条数、有效条数、去重/精确匹配/上限、相关性过滤、展示条数逐层检查；不能仅凭调试返回列表断言搜索 UI 丢数据。

受控诊断样本见 [web-verification-device-fixture.cjs](../scripts/web-verification-device-fixture.cjs)（不是真实站点书源，默认禁用）。

## 视频播放接入

视频书源使用 `type: "video"`，`content.video` 返回媒体直链，可选字段 `content.videoPage` 返回当前集的原站播放网页。字段规则和示例统一维护在公共文档的[视频网页回退](../harmony-book-source-engine/docs/book-source-development.md#视频网页回退)章节。

从「剧集详情 → 开始观看」或书架进入播放页后，优先原生播放；明确不支持视频规格且有网页地址时自动回退。网络或未知播放错误重新获取直链一次，仍失败时可手动选择「网页播放」。只提供网页地址时，也通过播放页按钮手动进入。未配置有效 `videoPage` 的书源不会自动打开章节接口。

网页模式支持应用选集、上一集、下一集、刷新网页、重试原生和全屏返回。网站自己的进度、倍速、清晰度与连播由网站控制；应用仅保留进入网页前的原生进度，不把网页中的选集和播放秒数同步到书架。后台暂停网页媒体，回到前台后手动继续播放。

开发时注意：

- `videoPage` 是字段规则；固定地址写为 `"= 'https://example.com/watch/1'"`，接口字段可以写 `"$.webUrl"`。不能直接把不含模板的固定 URL 当选择器规则填写。
- 媒体请求头不会注入回退网页，当前原生 `Video` 组件仍不发送 `mediaHeaders`；网页使用对应域的 ArkWeb Cookie。网页回退不保证解决编码、鉴权或站点限制。
- 通用正文调试不启用视频专用回退，空直链仍可能报错；仅网页的视频源需要进入实际播放页验证。

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

## 宿主实现差异

网络选项位于“其他设置 → 兼容与诊断”：HTTP/1.1 兼容模式与图片下载并发（4/8/12，默认 4）只在本机保存，不写入书源。图片并发与脚本 `http.all` 的并发是两套独立限制。脚本请求的 `timeout`、`http.all` 选项及 `finalUrl` 语义见公共文档的“脚本阶段”接口表。

| 能力 | 当前应用现状 |
| --- | --- |
| 原生书源 | 支持编辑、书源设置（变量、音色、账号登录、动作按钮）、搜索、发现、详情、目录、正文、听书、视频播放与漫画图片解密；书源管理和发现页的长按菜单可进入书源设置 |
| 原生 JS | `js` 函数库与 `script` 阶段已接入；`http`、变量、Cookie、缓存、凭据和详情书籍变量通过内核宿主接口处理，与兼容书源迁移开关独立 |
| 原生 HTTP 与诊断 | 支持响应头/可用性标记/请求编号、严格批量失败与对象式条件重试；复制/导出包含前置性能摘要，目录调试可选最多 3000 章 |
| 漫画媒体自定义头 | 允许合法自定义头；API 22+ 且拦截可用时逐跳下载，同 origin 保留、跨 origin 移除；音频播放器内部的跳转不走这套逐跳策略 |
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
