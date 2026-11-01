# PDF 支持实施与验证记录

日期：2026-11-01。依据：用户已确认的 `docs/prd/pdf-support-investigation.md`。

## 已实现

- PDF 原文件导入、元数据、受限尺寸封面、内嵌目录、物理页索引、解析版本及缺失索引重建。
- 独立原版式阅读页，缩放、宽度/整页适配、连续/逐页浏览、宽屏双页、目录、页码输入、滑杆和文字搜索。
- 书架、详情和本地管理中的 PDF 格式/页码显示；稳定页码保存、后台/锁屏保存入口、最近阅读和阅读时长。
- 系统文件关联、WebDAV、OPDS、云文件选择/下载/占位书、已有文件和阅读进度同步协议，以及备份恢复和原文件导出。
- 原文件与派生文件先写入独立版本目录，再通过 RDB 事务切换记录和索引；提交失败保留旧版本，成功后清理旧版本。
- PDF 不进入文字分页、正文缓存、漫画处理和 TTS；局域网阅读将 PDF 标为暂不支持，并拒绝浏览器写入 PDF 进度。
- 使用说明及应用内帮助已同步；变更记录放在根目录 CHANGELOG.md 的“未发布”，未调整应用版本号。

## 关键实施校准

1. 视图搜索在测试设备上出现原生 N-API 崩溃。正式代码改用独立后台文档搜索与矩形高亮，保持相同阅读内核及用户功能；详见 `memory/crashes.md`。
2. API 21+ 使用 PdfDocument.searchKey；API 20 使用既有文本对象及字符矩形接口。页索引、原生显示和核心导航只依赖 API 20 已有能力。
3. 原生文档只在创建它的线程使用，后台任务仅返回序列化元数据、目录或命中坐标。视图在原生组件挂载后加载，销毁时等待在途加载结束再释放，避免主动释放与加载并发。
4. 稳定翻页节流保存到本地；离开/隐藏后复用 CloudSyncCoordinator 的自动进度同步，避免每次翻页触发全书架文件同步。
5. 事务批量写入既可能抛错，也可能返回 -1。现有原子提交封装增加实际写入数量校验，失败进入回滚；新增可选的缺失书籍插入参数，原有换源调用保持默认行为。

## 已执行验证

| 项目 | 结果与证据 |
| --- | --- |
| 工程同步 | 通过，使用 DevEco MCP project_sync，跳过已安装依赖的重复安装 |
| 静态检查 | 检查 28 个变更源码文件，PDF 新增源码无错误。旧 ReadBook 的桌面选择分支有一处已有 Blank/Stack 布局诊断，已通过 git show HEAD 核对该块未改动；构建可通过 |
| 默认应用 HAP | 最终 `entry@default` debug 构建成功，日志 `.hvigor/pdf-release-candidate-build.log` |
| 测试 HAP | `entry@ohosTest` 构建成功，日志 `.hvigor/pdf-final-device-build.log` |
| 核心真机验证 | Pura X Max / HarmonyOS 7.0.0.111，测试结果 `PDF_NATIVE_PROBE_AND_VIEW_PASS` |
| 文字与扫描 PDF | 后台读取页数、生成封面；文字样本正确提取书名、作者及两个目录项 |
| 单页与千页 PDF | 1 页和 1000 页样本的后台解析、封面生成通过；无目录样本能返回空目录 |
| 真实数据库与文件 | 分别用 3 页、1000 页样本验证导入、页索引数量、原文件保留、分组及页码保留、无正文缓存；密码以外的损坏文件重导入失败不破坏旧版本 |
| 真实事务回滚 | 在独立测试数据库建立临时拒写触发器，验证失败后书籍及原索引不变；测试完成移除触发器 |
| 资源生命周期 | 同一控制器重复挂载、加载、缩放、单双页切换、跳页、搜索高亮及销毁两轮通过；未再次触发视图搜索崩溃 |
| 回归脚本 | 8 个脚本以 node --test 执行，汇总 26 项通过、0 失败；其中包含 PDF、备份、云传输、阅读进度、OPDS、EPUB、MOBI，以及关闭入口后的过期异步分流保护 |
| API 20 搜索分支 | 运行生产搜索代码，验证跨文本对象匹配、字符矩形、扫描页跳过和文档释放；该分支未在 API 20 真机执行 |
| 文档与样本一致性 | build-help-data.mjs --check、generate-pdf-test-fixtures.mjs --check 通过 |
| 安装启动 | 最终默认应用的已签名 HAP 已安装到连接设备，并成功启动 EntryAbility |

测试仅使用自行生成的文档。数据库实测显式指定 `pdf_support_probe.db`，不使用用户的 legado.db；测试书籍和受管文件在结束后清理。

## 尚未覆盖的验收场景

- 当前只有一台可连接设备；API 20 系统、独立平板/2in1、实体折叠动作与窗口缩放矩阵仍需补测。
- 尚未使用真实账号在两台设备间做 PDF 云文件上传下载和进度同步往返，也未连接真实 WebDAV/OPDS 服务器做端到端 PDF 下载；入口实现、格式识别和相关既有脚本已覆盖。
- 样本覆盖 1000 页，但文件约 321 KB，不代表已经验证数百 MB 的实际扫描书、复杂字体或超大页面的内存峰值；当前未记录 RSS/首帧性能基准。
- 需要密码的 PDF 明确提示暂不支持；密码样本的实际设备返回码、长时间后台恢复、锁屏恢复，以及异常终止后的恢复，仍需更多真实样本验证。

上述项是验证覆盖边界，不应在发布说明中描述为已完成实测。

## 复现命令

```powershell
node scripts/generate-pdf-test-fixtures.mjs --check
node scripts/build-help-data.mjs --check
node --experimental-strip-types --test scripts/pdf-support-check.mjs scripts/app-data-backup-check.mjs scripts/cloud-transfer-check.mjs scripts/reading-progress-check.mjs scripts/opds-parser-check.mjs scripts/epub-converter-check.mjs scripts/epub-mixed-layout-check.mjs scripts/mobi-parser-check.mjs

# 构建并安装 entry@ohosTest 后：
hdc shell aa test -b io.legado.read -m entry_test -s unittest /ets/testrunner/PdfSupportTestRunner -s timeout 60000
```

默认应用安装包：`entry/build/default/outputs/default/entry-default-signed.hap`。

## 自查结论

- 解析与搜索不阻塞 UI；目录/页列表使用 LazyForEach；应用层不生成整书位图或持久化整书文字。
- 默认页、异步取消、查询过期、写入归属及首次页码恢复均有门控；后台搜索不共享视图原生对象。
- 版本目录和原子提交保留失败前的数据；清理路径受限于应用的 local_books。
- 未新增第三方 PDF 依赖或服务端格式协议。阅读浮层复用既有材质、按钮、进度条和设置行。
- 未发现需要阻塞本次代码交付的新 P0/P1；多设备、长时间生命周期和真实云端流程仍以上述待测项为准，本记录不替代完整发布验收。

## 阅读页视觉统一

- PDF 正文改为沉浸式显示，点按正文唤出／收起菜单；工具栏不再挤占正文高度。
- 新增 PdfReaderControls，直接复用小说页的 ReaderMaterialPanel、ImmersiveBackButton、ReaderQuickJumpContent、ReaderSettingSwitchRow。顶部标题胶囊、底部合并进度面板、目录／设置／搜索／跳页面板沿用相同圆角与间距；宽窗口中的面板靠右，手机窗口保留两侧 18vp 留白。
- 目录仍使用 LazyForEach；搜索、跳转、布局偏好与进度保存继续由阅读页处理，正文轻点通过容器观察触点及位移接入，不抢占 PDF 原生手势。
- 静态检查：新增控件、原生视图、阅读页与 UI 预览页面无诊断；测试 runner 只有已有类型的弃用／异常处理提醒，无错误。
- 最终默认包与测试包构建通过：`.hvigor/pdf-ui-redesign-final-build.log`、`.hvigor/pdf-ui-redesign-final-test-build.log`。
- PDF 与阅读进度脚本共 8 个 Node 测试通过；最终测试包真机回归返回 `PDF_NATIVE_PROBE_AND_VIEW_PASS`。
- Pura X Max 真机查看了菜单、设置、跳页和搜索面板；验证正文轻点后四个操作按钮从 UI 树中消失，再次轻点可恢复；通过跳页浮层从第 2 页定位到第 3 页，标题读数更新为 `3 / 3 页 · 100.0%`；输入时面板随键盘避让。
- 截图记录位于 `.hvigor/pdf-ui-menu.png`、`.hvigor/pdf-ui-settings.png`、`.hvigor/pdf-ui-jump.png`、`.hvigor/pdf-ui-search.png`。这些来自独立测试页面，挂载生产控件与原生 PDF 视图，使用自行生成的三页样本；最终版本进一步收紧了跳页／搜索面板的留白。
- 预览复现：安装测试 HAP 后运行 `hdc shell aa test -b io.legado.read -m entry_test -s unittest /ets/testrunner/PdfSupportTestRunner -s pdfViewOnly true -s pdfControlsPreview true -s timeout 400000`，可交互查看约六分钟。测试继续使用独立数据库和缓存，不读取用户书架。
- 当前视觉检查覆盖连接设备的竖屏；深色模式、实体折叠及独立平板窗口仍未执行本轮视觉矩阵实测。

## PDF AI 超分接入验证

### 实现边界

- PDF 超分默认关闭，分类设置可配置默认值；阅读页单独调整后以 `pdfSuperResolution` 按书保存，独立于漫画设置。权限复用 ReaderComicSuperResolution.access 和 AiAccessPolicy，会员／试用及设备能力变化会重新判断，退出和后台暂停新任务。
- PdfRasterTask 在 TaskPool 生成受限光栅：宽不超过 1024、总像素不超过 1 Mi；当前优先支持无文字／矢量对象、图片覆盖主要区域且原点／旋转可安全对齐的扫描页。高分辨率页、文字页、混合页、旋转或复杂裁切页保持原生显示。
- PdfSuperResolutionSession 复用漫画超分引擎与全局计算队列，最多保留当前及相邻三页引用；源图与结果进入既有漫画图片缓存预算，原文件不改写。光栅任务跨会话串行，避免快速开关时重复写入同一缓存。
- PdfSuperResolutionOverlay 通过 API 26 的 pdfRectToViewRect 贴合原页，整棵图片子树不参与命中。原生 PdfView 保留连续滚动、缩放和单双页能力；滚动／缩放时移除覆盖，停稳后恢复。搜索显示原页，避免覆盖原生匹配高亮。
- 菜单增加“查看原页／查看超分”，可即时比较；设置中说明 AI 可能改变细小文字与数字。失败、取消或权限失效时继续显示原页。

### 已执行验证

- `scripts/pdf-super-resolution-check.mjs`：7 项通过，覆盖输入限制、页边界、缓存命中、三页引用上限、翻页／销毁取消、失败回退、源文件保持不变、空 CropBox 回退、光栅矩阵、原子写盘与原生资源释放；串行队列取消后可继续处理新任务。
- 与 PDF 支持及阅读进度脚本一起运行：15 项 Node 测试通过，0 失败，日志 `.hvigor/pdf-sr-regression.log`。
- ArkTS 静态检查无错误；构建通过。最终测试包日志 `.hvigor/pdf-sr-touch-final-build.log`，最终默认应用日志 `.hvigor/pdf-sr-final-build.log`。
- Pura X Max / HarmonyOS 7.0.0.111：真实系统模型把 PDF 光栅从 128×192 增强至 512×768；测试返回 `PDF_SUPER_RESOLUTION_AND_NATIVE_VIEW_PASS`。测试还验证文字页跳过、扫描页分类、光栅绿色／蓝色象限位置、原页对比、原生缩放和跳页，以及关闭时资源释放。
- 真机 UI 操作验证：正文向上滑动后，第 2 页增强图位置由初始页顶移动至 `y=-585px`，第 3 页位于 `y=1283px`，两页增强覆盖正确贴合原生滚动；记录 `.hvigor/pdf-sr-gesture-pass.png` 和对应 UI 树。
- 点击“查看原页”后 UI 树中的 `pdf_sr_page_*` 全部消失，按钮变为“查看超分”；打开搜索面板时同样没有增强层；关闭搜索恢复增强层；设置中关闭超分后增强层全部移除。相关 UI 树为 `.hvigor/pdf-sr-original-toggle.json`、`.hvigor/pdf-sr-search-paused.json`、`.hvigor/pdf-sr-settings-final.json`、`.hvigor/pdf-sr-disabled.json`。
- 本轮修正了缺失 CropBox 的原生返回差异、光栅矩阵裁切和图片命中导致的原生拖动阻断；原因和回归点见 `memory/bugs.md`。

真实模型测试使用仅在 ohosTest 中安装的 AiHost 和自行生成的样本，测试缓存／数据库隔离；结束恢复 AppAiHost，不修改真实账号、会员或书籍开关。

### 复现与未覆盖项

```powershell
node --experimental-strip-types --test scripts/pdf-super-resolution-check.mjs scripts/pdf-support-check.mjs scripts/reading-progress-check.mjs
hdc shell aa test -b io.legado.read -m entry_test -s unittest /ets/testrunner/PdfSupportTestRunner -s pdfSuperResolution true -s timeout 150000
# 加 -s pdfControlsPreview true -s pdfViewOnly true，并改为 -s timeout 400000，可交互查看增强样本。
```

小样本证明渲染、推理、叠加和回退链路可用，不代表所有扫描书都能改善。尚未实测超大扫描文件的内存峰值、长时间阅读耗电、API 20 真机的禁用路径、复杂扫描页面质量与实体折叠／独立平板的视觉矩阵。上述限制不影响普通原生 PDF 阅读。

## 分类设置及会员权益补齐

- “阅读设置 › 分类设置”在“漫画”下方增加“PDF”，独立页面沿用既有 PageScaffold 和 SettingRow 卡片，包含连续滚动、宽屏双页、适配整页及 AI 超分。
- 统一默认值存于既有 `reader_settings` 偏好文件的 `readerPdfSettings`，默认连续滚动开启，其余关闭；应用备份会包含此偏好文件。现有阅读设置云同步使用字段清单，本次未扩展云端协议。
- 打开 PDF 时合并全局默认和单本变量，单本已保存的值优先；后续只有在阅读页实际修改的选项才写为单本覆盖，普通翻页／退出保存进度不会将所有默认值固化。之前版本已经保存的单本偏好保留。
- 会员权益页的 AI 超分说明及账号页权益对比表同步增加 PDF 扫描页；会员档位和试用规则沿用现有策略。
- `pdf-settings-check.mjs` 覆盖类型校验、默认值／单本覆盖优先级、读取时等待快速连续保存、备份恢复后的重新读取、失败队列恢复，以及生产 saveProgress 的合并行为；与 PDF、超分、阅读进度一起执行，20 项通过、0 失败，日志 `.hvigor/pdf-settings-regression.log`。
- 本轮 ArkTS 静态检查无错误、最终默认应用构建通过，日志 `.hvigor/pdf-settings-final-build.log`。设备在验收时已断开，尝试重新连接原调试地址失败；本轮未完成新分类页的真机 UI 验证与安装，不能沿用上一轮超分真机结果作为此页面的实测结论。
