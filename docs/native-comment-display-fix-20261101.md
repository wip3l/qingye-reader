# 原生内联评论页真机显示修复

日期：2026-11-01。基线 `4ce596f0`（4.4.945），书源内核 `3a026e9`。设备 HOP-AL10，API 26。本文记录工作区修复和本地安装验证，不表示商店已发布。

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
