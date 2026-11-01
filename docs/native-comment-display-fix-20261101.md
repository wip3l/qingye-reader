# 原生内联评论页真机显示修复

日期：2026-11-01。基线 `4ce596f0`（4.4.945），书源内核 `ace8929`（规则实现包含 `8709b3f`，其后为文档提交）。设备 HOP-AL10，API 26。本文记录升版前的工作区修复和本地 debug 安装验证；修复纳入 4.4.946，不表示商店已发布，也不代表 release 包新增设备验收。

## 根因证据

使用用户提供的原始评论 HTML（5,263 UTF-8 字节），配虚构评论数据，生成零 HTTP 请求的临时源，在调试页点击预览：

1. 原实现于 onControllerAttached 中立即调用 loadData。ArkWeb 将其转换为 `data:text/html...` 主框架导航；onLoadIntercept 仅允许 about:blank/srcdoc，日志显示 `result:1`，随后 `ERR_ABORTED(-3)`。轮询只能读到空白页面，最后显示 15 秒超时。
2. 放行确切的宿主生成文档后，日志变为 `result:0`，但仍发生 ERR_ABORTED，紧接着初始声明式 `src: about:blank` 完成导航。即使数据文档未被拦截，过早提交也会被初始空白页取消并覆盖。
3. 改为等待初始 about:blank 的主页面结束，再提交生成文档后，同一份原始 HTML 在设备上显示昵称、正文与点赞信息，加载遮罩消失。关闭弹层并重新预览也可显示。

这不是站点取数或 iframe 内部布局导致的本次故障。只有源文件改动无法解除宿主拦截和初始导航竞态，需安装包含本修复的应用。

## 修复范围

- `NativeCommentPageView.ets`：等初始空页完成后加载；采用 UTF-8→Base64 传输，避免 #、%、Unicode 和 srcdoc 转义文本受到 data URL 解释影响；旧代超时回调不能结束新页面。
- `NativeCommentDocumentPolicy.ts`：三个导航/资源入口共用策略。只允许当前生成 Base64 文档的主框架导航，以及既有 about:blank/srcdoc 和 data:image 资源；其他 HTML data URL、子框架 data 文档、网络和文件地址继续拒绝。销毁/失败后清除文档授权。
- 保留无痕 Web、sandbox=allow-scripts、不授予同源、禁用网络/文件/存储、无 javaScriptProxy。未移除 iframe，未加入 HTML 页面调用宿主的网络桥。
- 用户书源修订另存 Downloads，不进入仓库或订阅。简化页面对正文 data 的引用，增加列表请求开关、接口业务错误及空态、纯文本 DOM 渲染与秒/毫秒时间兼容；正文请求和解码函数保持原样。

## 验证

已通过：

- `reader-comment-panel-check.mjs`：精确数据文档放行、任意/子框架数据文档拒绝、特殊字符往返、初始空页时序、旧超时、关闭和生成/显示结果回调。
- `native-comment-page-browser-check.mjs`：真实 data: Base64 导航的 iframe 就绪、数据注入、按钮、本地隔离与零外部请求；保留已有恶意文本和 WebRTC 绕过检查。
- `native-comment-page-service-check.mjs`、`neutral-source-engine-check.mjs`。
- 书源离线检查：当前格式校验；真实 Runner 执行模拟正文、段评、章评；业务错误和关闭列表请求；修订页面三种浏览器场景；9 个搜索/目录/正文与算法函数的代码保持相同。
- 完整 debug assembleHap：57 个任务构建成功；最后修改后增量构建成功（53 executed、4 up-to-date）。存在工程既有警告。
- API 26 真机：原始 HTML 配虚构数据，预览可见；关闭弹层并重开已重复确认。截图 `.codex_tmp/shuqi-repair/device-pass.jpeg`，布局 `device-pass-layout.json`；两阶段日志分别见 `preview-hilog.txt`、`fixed-hilog.txt`。原始导航失败也在真机复现。

未声称完成：API 20 真机矩阵、第三方站点当前可用性、付费内容或账号验证。没有修改第三方接口签名/正文解码、用户原文件、书架数据或账号设置。

## 使用与清理

设备已覆盖安装本地修复构建。旧缓存中的入口仍可能来自更新前的变量摘要或章节状态，需刷新当前章节后再点击。重导源文件不能替代刷新正文。

临时验证源命名为“Codex段评离线对照”，禁用搜索发现参与，测试后删除。仅清理本次创建的本地服务和两条 HDC 反向映射，保留其他开发任务状态。

官方接口说明参考：[OpenHarmony WebviewController.loadData](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebviewController.md#loaddata)。真实故障判断以本次设备导航日志和修复前后同样本对照为依据，不以桌面浏览器结果替代真机。

## 后续复核：实际阅读入口立即失效

用户安装 4.4.946 后，实际阅读页仍显示“评论显示失败，请重试”。在同一设备复现并抓取完整 UI 树，Toast 的原始错误为“评论入口已失效，请刷新本章”；此时没有生成 HTML，尚未进入上文的 Web 渲染环节。旧实现只把具体原因显示为短暂 Toast，而“重试”反复提交同一个失效入口。

根因是 `NativeSourceRunner.inlineKey` 将整个 `book.vars` 纳入指纹。阅读页正文加载完成后调用 `saveReadingProgress`，写入 `lastReadTime`、分页进度和当前页文本等字段；翻页、朗读也会更新它们。因此，即使刚刷新章节，生成入口与点击入口时的书籍变量也不同。此前离线调试使用固定书籍变量，没有覆盖阅读器保存进度的过程，不能据此宣称实际阅读链路已修复。

修复只从评论指纹中排除明确的阅读与朗读进度字段，并对剩余书籍变量递归排序；规则收到的 `book.vars` 原值保持不变。书源配置、书源变量、登录凭据、书籍业务变量、书籍和章节身份、段落 hash 的校验继续保留。阅读页持久显示生成错误，遇到三类必须重建正文的错误时提供“刷新本章”，收起评论面板并保留页码刷新；刷新完成后用户重新点击段评。

验证结果：

- 内核回归覆盖保存进度、更新朗读位置、对象键重排之后的热／冷上下文打开，以及业务变量、书名变化仍被拒绝。
- 阅读页回归覆盖具体错误保留、普通错误重试、失效／缺失上下文／段落变化三类错误转为刷新章节，且不再次调用旧入口。
- debug `assembleHap` 成功：57 tasks，30 executed，27 up-to-date，存在既有警告。已保留数据覆盖安装到 API 26 设备。
- 使用设备上既有书源，从搜索进入用户截图对应的书与章节。旧缓存首次报失效并显示“刷新本章”；点击该按钮后返回原第 3/9 页。重新点击第 14 段显示共 51 条评论，关闭后第 12 段显示共 29 条评论；再从第 3 页翻到第 4 页并返回，第 14 段仍可显示，加载和失败遮罩均已消失。此项为实际阅读入口与实际数据验证。

本地证据位于 `.codex_tmp/shuqi-repair/`：`error2.json`（修复前具体错误）、`new-error.json`（修复后刷新入口）、`refresh2.json`（刷新完成）、`comment2.json`（第二段评论）、`page4.json`（翻页）、`final-real.json` 与 `progress-fixed.jpeg`（翻页后再次显示）。这些含设备内容的临时文件不提交。

## 后续优化：内联评论跟随深浅色

用户报告深色阅读模式下段评仍为白底。当前设备使用的修订书源已经包含 `prefers-color-scheme: dark` 规则；问题在宿主：`NativeCommentPageView` 没有设置 Web 的 `darkMode`（SDK 明确默认 Off），且原生标题区、加载和错误层使用硬编码白底。此前白底截图中，原生标题也因默认深色文字颜色而不可见。

阅读页和调试预览现在显式向组件传递 `appDarkMode`，Web 使用 On／Off 开启书源的媒体查询，关闭强制反色。原生标题文字、Web 默认背景、加载与错误层、弹层拖动区同步配色。外层离线文档和 opaque iframe 均声明 `color-scheme: light dark` 并提供默认背景与文字色。保留 sandbox、CSP、无宿主桥与网络禁用；不重载源页面来切换主题。阅读器主题刷新只对远程评论运行原有就绪轮询，防止离线评论被远程 Web 的加载遮罩覆盖。

验证：实际 Chromium data: 主文档中的 opaque iframe 在 light→dark→light 时背景、正文、昵称、引用、回复均切换，按钮交互状态保留，仍为零外部请求；阅读页回归覆盖阅读／调试入口主题传值、弹层颜色及离线／远程主题刷新分流。内核评论回归通过。API 26 设备上现有书源同一段的 51 条真实评论，深色下标题、正文、引用和回复区域均正确，切回日间后恢复白底，随后恢复夜间。证据为本地 `dark-result.jpeg` 与 `light-result.jpeg`。无须重新导入或改动当前修订书源。

最终 debug `assembleHap` 构建成功：57 tasks，26 executed、31 up-to-date；保留既有编译警告。最终测试包已覆盖安装并导出至 Downloads，版本仍为 4.4.946，未作正式发布。
