# 网页验证修复：实施与验收记录

日期：2026-10-29。对应 [修复方案](cf-challenge-repair-plan.md) 与 [问题核查](cf-challenge-gap-review.md)。

## 已实施

| 项目 | 实际改动 |
| --- | --- |
| 设置页网页抓取 | 设置页挂载现有 WebBookFetchRuntimeHost；动作、动态选项、登录检查等贯通取消信号，销毁后停止本页网络并忽略迟到的 UI 更新；新增独立“网页验证”入口 |
| 宿主往返 | 注册多个仍存活的控制器；新页面退出时恢复先前宿主；可见回调重新选定宿主；旧控制器的异步回调不影响迁移后的请求；已发出的 POST 不随宿主切换重放 |
| 首次加载 | 真机复测发现首次关联控制器后立即请求可能超时；组件改为优先等待初始页面 onPageEnd 后注册，遗漏回调时保留有界初始化兜底 |
| 取消与预算 | 活动任务和排队任务检查取消；队列和迁移共享截止时间，没有显式截止时间的旧调用也有总预算；完成后清理定时器 |
| 错误与状态 | 内部/脚本响应保留 errorCode、errorStage、statusCodeAvailable；WebView 原始 HTTP 状态未知，兼容保留抓取 status；调试页展示宿主、排队、渲染耗时，不再把所有网页超时写成连接失败 |
| 分区 Cookie | API 26 请求专用读取采用 fetchCookieSync(url,false,true)，低版本保留旧调用；原生 cookie.get、文本和二进制 HTTP 复用同一匹配结果；显式 Cookie 头优先，跨 origin 禁止注入规则保留 |
| 复制与清理 | Cookie 复制仍使用不含分区 Cookie 的读取；clearance 不跨地址复制；删除增加分区属性写入及短期墓碑兼容路径，避免把分区值转成非分区值；不清空用户全局 Cookie |
| UA | 请求头合并按名称大小写去重；主请求、脚本验证、设置页验证传递求值后的 UA；验证上下文用独立 token 绑定 URL、书源和 UA；新增可选 browser.verify(url,hint,{userAgent}) |
| 会话状态 | 没有明确登录凭据/指定 Cookie 判定时显示“已保存网页会话（登录状态未确认）”；“完成”表示保存会话，不冒充已过盾；会话未确认时使用中性色 |
| 搜索诊断 | 增加有效记录、去重/精确匹配/上限、相关性过滤及纳入展示数量日志，配合已有脚本返回条数定位差异 |
| 开发材料 | 更新主应用与引擎文档；新增完整本地测试源、Node 回归和独立设备测试 Ability/Runner |

未增加搜索/发现自动弹窗、通用 403 回退或无人值守挑战求解。没有修改书源脚本请求 primary:false 的既有契约。

## Node 检查

- 原生书源规则：264 项断言通过。
- 原生 JS 函数库：89 项断言通过。
- 原生脚本阶段：125 项断言通过，包含 UA 传递、动态 UA 求值和拒绝换行参数。
- network-compatibility-check：通过；增加分区请求 Cookie、同名 Cookie 保留、显式头优先、UA 大小写合并检查；原有跨域重定向去凭据等检查继续通过。
- web-verification-check：通过；覆盖宿主恢复、POST 不重放、活动/队列取消、截止时间、API 版本分支、复制边界、验证上下文隔离及 fixture 格式。
- web-request-deadline-check：通过；保留队列过期、迁移、活动停止和过期请求不发出的检查。
- source-followup-diagnostics-check：通过；诊断脱敏与序列化检查。
- web-book-fetch-wait-check：通过；迟到图片、未满足选择器、非法正则与硬截止时间。此旧脚本需设置 DEVECO_HOME 为本机 command-line-tools 根目录，已复用本机 SDK 执行。

Node 替身用于验证业务契约，不视为 ArkWeb 或真实站点的运行证据。

## HPR-W72 API 26 设备证据

设备目标：127.0.0.1:33761；应用版本：4.4.938 本地调试构建。测试 HAP 使用独立 entry_test 模块，不导入书源到用户数据库、不修改阅读设置。

Cookie 探针向 `https://cf-cookie-probe.invalid/` 写入随机命名、60 秒有效期的虚构 Cookie，然后对比两种 SDK 读取：

```text
httpOnly=true
partitionDefault=false
partitionIncluded=true
```

这证明本设备的 HttpOnly 并非一概不可读，分区 Cookie 默认确实不被原接口返回。修复后 `CookieStore.getRequestCookie` 能读到测试分区 Cookie，`removeCookie` 后请求读取不再返回它，普通测试 Cookie也清除。没有读取/打印用户站点 Cookie 值。

本地受控服务监听开发机 127.0.0.1:18393，经 HDC rport 映射。测试覆盖隐藏宿主请求、新宿主加入、退出后恢复旧宿主、活动请求取消、HTTP 状态可用性；原生 HTTP 和网页请求的 UA 由服务端比对。

首次测试失败暴露出冷启动问题。增加预热后曾通过，但没有采用该轮作为冷启动验收。修复初始导航后，移除首请求前的原生 HTTP 请求与固定等待，连续两次设备测试返回：

```text
PASS WebVerification: hosts/restoration/cancel/status;
Cookie API: httpOnly=true, partitionDefault=false, partitionIncluded=true
TestFinished-ResultCode: 0
```

服务端日志位于 `.codex_tmp/web-verification-device.jsonl`，只记录时间、方法、路径和 UA 是否匹配，不记录 Cookie 或认证头。

上述 Cookie 实验直接操作 SDK CookieManager，**不是可信 HTTPS 站点下发分区 Cookie 后再由原生网络发送的完整测试**；本地服务是 HTTP。两类证据分别记录，不能合并宣称 HTTPS/CF 全链路通过。

## 最终应用构建与安装

包含最后的设置动作与 browser.open UA 修复后，重新执行 `node scripts/local-device-build.cjs --install`，编译、调试签名、验签、覆盖安装、启动及进程存活检查全部通过。4.4.938 已安装到 HPR-W72（127.0.0.1:33761），产物为 `output/entry-4.4.938-arm64-debug-signed.hap`。最后一轮原生脚本 125 项断言、网页验证回归和网络兼容性检查均通过。

## 可重复执行

```powershell
node scripts/web-verification-device-fixture.cjs
# 另一终端：
hdc -t 127.0.0.1:33761 rport tcp:18393 tcp:18393
node scripts/local-device-build.cjs --test --install
hdc -t 127.0.0.1:33761 shell aa test -b io.legado.read -m entry_test -s unittest /ets/testrunner/WebVerificationTestRunner -s timeout 70000
```

手动设置页流程可导入 `http://127.0.0.1:18393/source.json`。样本默认禁用，提供“网页抓取诊断”和“验证后继续抓取”动作，搜索关键词用“网页验证验收”；发现入口明确提示主动验证。服务端 `/report` 只说明相应脚本运行到报告步骤，不能代替用户实际点完验证页的验收。

本次测试结束后已停止测试服务并移除本任务的 tcp:18393 映射；测试 Cookie 仅存活一分钟。正式安装使用不带 --test 的本地构建脚本，始终显式设置 LEGADO_DEVICE_TARGET 并按项目规定直连。

## 验收边界

- 尚未完成霹雳/刺猬原书源在相同关键词下的 UI 与调试对照，也未操作真实 CF 人工验证。本次通用修复不宣称两个案例已全部恢复。
- 尚未完成实际设置页的每个动作、可见验证页返回继续脚本、并发书源验证选择的人工 UI 矩阵；代码与受控运行时/上下文回归已覆盖对应机制。
- 尚未完成可信 HTTPS 服务端发送/接收分区 Cookie、应用重启后的持久化以及不同 Domain/Path 组合的完整设备矩阵。当前清理验证限定测试域根路径，不能推广到所有 Cookie 作用域。
- API 20–25 只验证了版本分支及最低 API 编译兼容，未在这些版本真机运行。
- 未新增常驻后台宿主；无页面宿主时返回明确错误。注册/恢复策略仍需在其他设备、多窗口和复杂路由下扩展验收。
- 工作区存在其他并行任务产生的阅读相关修改，均保留。整包编译时发现新增阅读跳转代码通过基础 Context 读取 config 导致类型错误，仅将该处转换为 UIAbilityContext 以通过编译；这些阅读相关改动不纳入本次网页验证修复提交。
