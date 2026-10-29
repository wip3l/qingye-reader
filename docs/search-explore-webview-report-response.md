# 对《轻页-搜索发现阶段WebView宿主缺失报告》的回复

日期：2026-10-29

回复对象：报告中描述的 4.4.938 真机搜索／发现取页失败

本次修复版本：轻页 4.4.940 本地开发构建（含本轮应用与书源引擎修改）

## 一、结论

报告记录的“普通 HTTP 遇到挑战、设置页能取页、发现页两次返回空”具有排查价值。本次没有取得报告对应的完整安装包、完整书源和原始请求轨迹，因此不否定这些现场记录，也不将其表述为已独立复现。

但“空正文就说明没有 WebView 宿主”“三个阶段的能力未实现”“Cookie 读不到就证明 HttpOnly／分区读取缺失”不能直接成立。源码核查和受控测试证明：搜索、发现、设置动作已有共用网页抓取通道；即使宿主已挂载，等待加载回调或整页稳定也能导致超时、空正文。

本次已经围绕代码确认的问题实施改进：显式等待条件提前检查、失败快照保留、原生发现任务取消、诊断信息贯通。真实 Cloudflare 站点是否恢复，仍需使用修复构建对原书源进行同条件复验，不能由通用回归替代。

## 二、逐项回应原报告

| 原报告判断或建议 | 当前确认结果 |
| --- | --- |
| 搜索／发现没有 WebView 宿主 | 主页已有 WebBookFetchRuntimeHost；两个阶段的 http.get(webView) 与 browser.render 未被非交互权限限制。实际挂载或生命周期故障仍可能发生，但不能从 len=0 定案 |
| 设置页有宿主，所以只有设置页能用 | 设置页另行挂载同一组件；运行时支持多个控制器以及退出后恢复旧控制器。入口不同不等于另有一套请求能力 |
| HttpOnly／分区 Cookie 未进入请求层 | 原生读取并非仅依靠 document.cookie；API 26 已调用包含第一方分区 Cookie 的读取，cookie.get 和原生 HTTP 接入该读取。低版本使用旧接口回退；这不代表低版本拥有 API 26 的分区能力 |
| errorCode／errorStage／statusCodeAvailable 缺失 | 当前标准脚本通道始终返回这些字段。需核对现场构建及探测方式，不能以 false／空字符串判断字段不存在。本次另补充耗时、等待阶段和失败快照标记 |
| 搜索／发现可显式 webView 的文档与实现冲突 | 接口已存在，描述该能力本身没有冲突；“可调用”并不保证具体站点已通过挑战或完整验收 |
| 再挂载宿主或新增声明式 webView 可解锁问题 | 两项基础能力均已存在。本次改善已有抓取链路，不重复添加另一套宿主 |
| 点击“完成验证”就代表已经过盾 | 当前完成动作主要保存网页会话。必须重新访问业务页确认内容，不能仅据按钮提示或 Cookie 存在判断 |
| ok=1、len>1000 说明能力已到位 | 不足。挑战页也可能被成功抓取；WebView status=200 是兼容抓取状态，statusCodeAvailable=false。需验证业务元素与实际解析结果 |
| 解析测试证明完整书源没问题 | 能证明测试样本的解析正确；无法单独证明请求、超时预算、变量、会话和阶段分支都正确 |
| 一次宿主改动能支持全部 CF 站点 | 无法保证。只对明确测试过的行为和站点条件作结论 |

版本追溯也确认：主仓库 dc10311 对应 4.4.938，其引擎 b1389e1 已包含上述宿主、Cookie 和诊断字段修复；相关核心文件到本轮核查前的引擎 536a6fd 没有变化。报告中的版本号不足以确定实际安装包是否包含这些提交。

## 三、本次实际改动

### 1. 显式 waitFor 不再必须等待整页完成和稳定

之前，选择器检查要经过 onPageEnd、readyState=complete、页面签名稳定等前置条件。慢图片、持续变化的页面、缺失页面结束回调，都可能导致业务元素已经存在却迟迟不检查。

现在，声明式 webView、脚本 http.get(webView) 和 browser.render 中的显式 waitFor 会在确认新文档、DOM 到达 interactive／complete 后开始检查。无显式条件的普通抓取仍采用原有整页完成和稳定策略。

为防止同 URL 刷新时误读旧文档，导航前标记旧文档，检查页面地址与导航代次，并忽略旧导航或旧控制器的迟到结果。无法安全标记旧文档时回退到页面结束后的检查。该改动不保证在所有导航事件都缺失时仍能成功。

### 2. 失败时保留有上限的页面快照

在已取得当前文档内容的前提下，加载、选择器、网页脚本或总预算失败可返回最近快照；最大保留 65536 个 UTF-16 单元，并提供截断标志。导航变化时清除上一文档快照。

返回仍保持 ok=false，不把挑战页或残缺内容伪装成业务成功。取消、排队、宿主不可用或尚无有效快照时，body 仍可能为空。

外层 HTTP 截止时间通过请求编号结束对应网页任务，保留该任务的快照及阶段信息，避免先返回一个没有上下文的空超时结果。

### 3. 原生发现列表和动态分类贯通取消

切分类、刷新、切离发现或组件销毁时，取消本发现操作的旧任务。取消信号传入 NativeSourceService、运行器、脚本宿主与请求层，已取消任务不再占用网页队列继续执行。

迟到的旧错误不会覆盖新操作提示，旧动态分类不会重新写入缓存；其他页面／其他 coordinator 的任务不受该取消影响。此验收重点为原生书源列表和动态分类，不扩大为所有兼容源内部脚本路径的完整取消保证。

### 4. 脚本和调试界面得到更完整的诊断

| 字段 | 含义 |
| --- | --- |
| errorCode／errorStage | 导致失败的原因和阶段；未细分失败使用兜底分类，不再依赖裸 ok/len |
| waitStage | 结束时正在等待什么：例如宿主、队列、加载、整页稳定、选择器或脚本；总预算超时也能保留该信息 |
| hostWaitMs／queueMs／renderMs | 宿主等待、运行时排队、加载执行耗时（毫秒）；不是完整请求耗时的严格拆分 |
| bodyIsSnapshot | 失败响应的 body 是否为诊断快照 |
| snapshotTruncated | 快照是否因保留上限被截断 |
| requestId | 用于关联同次请求的诊断编号 |
| statusCodeAvailable | 是否取得原站 HTTP 状态，网页 DOM 抓取为 false |

browser.render 成功继续返回字符串；失败继续抛出 Error。脚本 catch 到的异常包含上述分类、耗时及快照标记，e.response 保存完整失败响应。未捕获时，错误文案也包含分类。调试页显示等待阶段和快照标记。

本次未重新实现 Cookie 分区读取、修改用户 Cookie、增加无页面常驻宿主或无人值守挑战求解；这些不能作为本次新增能力宣称。

## 四、验证记录

Node 回归已通过：

- 原生脚本阶段：125 项断言。
- 新增网页抓取回归：DOM 提前检查、普通抓取仍等稳定、同 URL 旧文档拒绝、快照上限与截断、选择器失败、HTTP 外层截止时间保留快照、导航清除旧快照。
- 新增脚本桥接回归：搜索、发现、设置动作的 HTTP 诊断与 browser.render 结构化异常。
- 新增发现取消回归：列表、动态菜单、缓存、迟到错误、独立 coordinator、服务转发与页面生命周期。
- 既有宿主恢复、POST 不重放、取消与截止时间检查。
- 既有网络兼容、分区请求 Cookie、显式 Cookie 头优先、UA 大小写合并、延迟图片等待、发现分类选择和诊断脱敏检查。

HPR-W72（API 26，目标 127.0.0.1:33761）受控设备测试通过，返回：

```text
PASS WebVerification: hosts/restoration/cancel/status/interactive-DOM/deadline-snapshot;
Cookie API: httpOnly=true, partitionDefault=false, partitionIncluded=true
TestFinished-ResultCode: 0
```

新增测试页面包含一个延迟 15 秒的图片响应，以及每 30 毫秒修改的 DOM 文本。实际设备在 6 秒请求预算内通过业务元素提取；同一页面使用不存在的选择器时，在 3 秒总预算结束后返回 REQUEST_DEADLINE、waitStage=selector，并保留含 fixture-ready 的失败快照。

测试采用开发机回环 HTTP 服务，经 HDC 映射到设备；没有访问或代替真实 CF 挑战。Cookie 探针只在保留测试域写入短期虚构 Cookie、比较存在性并清理，没有读取或输出真实站点 Cookie 值。临时服务及端口映射已清理。

主应用和独立测试 HAP 均已完成编译、调试签名与验签，测试 HAP 安装与测试运行成功。最终主应用安装包记录见下文构建标识。

### 构建标识

最终主应用产物：`output/entry-4.4.940-arm64-debug-signed.hap`。收尾再次执行主应用编译、调试签名、验签、HPR-W72 覆盖安装、启动及进程存活检查，全部通过；最终设备运行的是主应用构建。

本轮主仓库基线为 `cea9289`、引擎基线为 `536a6fd`，包含本轮未提交修改；同版本旧包不代表具有相同能力。最终主应用 HAP 的 SHA-256：

```text
8FC132AF62A623E6DAD2C7549C0C38B8813971BFAE3163EC1D72C06EF7825F20
```

## 五、原书源的复验方式

1. 使用明确包含本轮改动的安装包，不只核对 4.4.940 版本号。
2. 设置动作、search.script、explore.script 分别调用同一个取页函数，保持同一完整 URL、UA、等待条件和超时参数；不要设置页测搜索地址、发现页测分类地址后直接归因于入口。
3. 先单请求对照，再测冷启动、设置页返回、快速切分类及并发排队。
4. 失败记录 requestId、字段存在性、errorCode、errorStage、waitStage、耗时、最终地址、body 长度及快照标记。不要记录完整 Cookie、认证头或用户页面内容。
5. 成功必须同时检查业务元素和解析出的合理数据；ok=true 或正文长度达标不构成过盾证明。

可在原诊断函数中增加以下记录（r 为 http.get 返回值）：

```js
var diagnostics = {
  ok: r.ok,
  status: r.status,
  hasStatusCodeAvailable: Object.prototype.hasOwnProperty.call(r, 'statusCodeAvailable'),
  statusCodeAvailable: r.statusCodeAvailable,
  error: r.error,
  errorCode: r.errorCode,
  errorStage: r.errorStage,
  waitStage: r.waitStage,
  requestId: r.requestId,
  hostWaitMs: r.hostWaitMs,
  queueMs: r.queueMs,
  renderMs: r.renderMs,
  finalUrl: r.finalUrl,
  bodyLength: String(r.body || '').length,
  bodyIsSnapshot: r.bodyIsSnapshot,
  snapshotTruncated: r.snapshotTruncated
};
```

## 六、仍待验收的边界

- 未使用报告中的完整霹雳书屋书源复现三个实际 UI 入口，也未执行真实 Cloudflare 人工验证。
- 未证明报告里的那次 cf_clearance 已成功取得、持久化并随对应请求发送；可信 HTTPS、Cookie Domain／Path／分区及重启后的会话仍需专项验证。
- API 20–25 仅有兼容分支和编译检查，未在这些系统版本的设备上执行本轮用例。
- Node 控制器替身和本地 HTTP 页面分别证明代码契约与受控 ArkWeb 行为，不能推广为所有复杂站点、多窗口和路由组合均已通过。

建议将原报告的核心结论调整为：“该构建下发现阶段 WebView 抓取失败，具体等待阶段和会话状态需进一步核实。”保留原始现象，同时移除“空正文等于宿主缺失”及“补宿主即可解锁全部 CF 站点”的确定性表述。
