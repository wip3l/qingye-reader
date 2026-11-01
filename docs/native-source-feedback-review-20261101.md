# 2026-11-01 外部书源反馈核查

核查结论：这些材料有参考价值，适合作为问题线索和需求收集；不宜整份作为已确认缺陷清单或直接按其优先级实施。最值得保留的是内联评论页的静态对照实验、变量指纹问题、CRLF 清理差异和调试能力建议。材料混用了旧镜像、不同版本书源和宿主推测，存在明确错误。

补充复核：应用提交 `97095afd`、内核 `06f6491`。已新增数字写入转文本、变量键顺序变化两组入口失效复现；调试页“生成通过”未回写显示结果的问题也已核对。具体优化范围、任务和验收门槛见 [优化方案](native-source-feedback-optimization-plan-20261101.md)。原表中的真机限制仍然适用。

后续进展：变量指纹及 CRLF 已由后续内核修改处理；评论页已在 API 26 真机定位到主文档误拦截和初始空白页覆盖，修复与验证见 [评论页显示修复记录](native-comment-display-fix-20261101.md)。下文保留初次核查时的基线与证据边界。

## 核查范围与证据边界

- 读取了 Downloads 中用户列出的 5 份 Markdown 和 1 份 JSON；其中的修复建议仅作为待评估内容，没有据此修改应用或引擎。
- 对照当前工作区：应用提交 `f6f6d4e6`，内核提交 `06f6491`。这不是报告标注的内核 `43804e1`，当前行为不能直接证明旧安装包行为。
- 检查了当前源码和开发文档，执行已有回归，并用实际引擎构造离线对照。没有执行所附书源的站点访问、账号操作或付费链路，没有进行鸿蒙真机验收。
- 原报告提及的 `_tools/mirror`、`native-source-debug.mjs`、`source-check.mjs` 及作者自建站点探测程序未随附件提供，当前仓库未检出这些工具文件；对它们只能核对描述是否合理，不能确认其实际版本及执行结果。
- 本次复核程序与结构化结果：`../.codex_tmp/native-feedback-audit-20261101.mjs`、`../.codex_tmp/native-feedback-audit-20261101.json`。临时程序不属于产品改动。

## 各文件的参考价值

| 文件 | 判断 | 推荐用途 |
|---|---|---|
| `2026-11-01.md` | 有价值，但 20 条中混有真实限制、错误解释和过时文档结论 | 保留原始反馈，按下表重新分类 |
| `轻页原生能力缺口与优化建议-20261101-本轮.md` | CRLF 与处理顺序值得保留；选择器、工具链及站点结论需区分版本和证据范围 | 整理正文清理规范、工具能力边界与分页示例 |
| `2026-11-01-内联评论页真机渲染超时.md` | 对照实验设计有较高排障价值；“任意真机必现”“根因确定”没有足够证据 | 作为真机复现线索 |
| `2026-11-01-提交稿-内联评论页渲染超时.md` | 上一份的精简重复，不是另一组独立证据 | 与上一份合并成一个问题，纠正根因及修复承诺 |
| `书旗-轻页原生-段评版.json` | 当前格式校验及 JS 语法检查通过，可作离线页面样本；跨站段落匹配并不稳健 | 保留附件和版本摘要，不能当作完整线上验收结果 |
| `轻页能力缺口_v6_提交稿.md` | 发现分页文档、提示位等需求有用；若干核心判断过时或自相矛盾 | 提取需求，不直接沿用其 P0/P1 排序 |

## 最重要的三项发现

### 1. 评论页超时值得优先复核，但现有材料没有证明具体根因

报告描述的“关闭请求后仍超时”“调试预览也超时”若在同一安装包、同一规则上成立，确实能大幅缩小到共享离线 Web 组件及其显示、加载和就绪信号链路。仓库的 [验证记录](source-capability-validation.md:3) 也明确没有完成该能力的鸿蒙真机验收，这一引用属实。

实际实现不是轮询 `document.readyState`：

1. [NativeCommentPage](../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeCommentPage.ts:49) 生成外层页面和 `sandbox="allow-scripts"` 的 `srcdoc` iframe；iframe 的 `onload` 设置外层 `window.__NATIVE_PAGE_READY__=true`。
2. [NativeCommentPageView.scheduleReady](../entry/src/main/ets/components/NativeCommentPageView.ets:32) 每 100 ms 执行 JS，检查该布尔值及当前 generation；异常被捕获后继续轮询，没有保留异常细节。
3. 外层 `onPageEnd` 也仅触发上述轮询；并不直接判定就绪。15 秒超时会停止并卸载 Web。
4. 标题由 [ArkUI Text](../entry/src/main/ets/components/NativeCommentPageView.ets:85) 绘制。标题出现不证明 iframe 已显示，也不证明书号、章号和令牌均正确；标题模板只依赖 `para.index`。
5. 页面生成与显示是两个独立的 15 秒预算。`page.fetch` 及限流等待发生在生成阶段，不能解释成占用了显示阶段的同一个 15 秒计时器。

最有用的改进方向是记录控制器挂载、`loadData`、页面结束、JS 返回值及异常、generation、iframe 加载和 CSP/控制台信息，再用官方离线示例在目标设备复现。`waitStage/hostWaitMs/queueMs/renderMs` 来自网页请求执行链，并非现成的内联组件显示指标；可借用度量方式，不能直接当作已有数据接线。

不能直接采纳“去 iframe 一处改动必定解决、隔离等价”的承诺。当前 iframe 的不透明 origin 是实际隔离机制，断网、关闭存储和不注册桥不能单独证明与它等价。[HTML 标准的 sandbox 说明](https://html.spec.whatwg.org/dev/iframe-embed-object.html) 明确区分了该 origin 限制。另外 iframe 的 load 事件本身也不是内容成功绘制的充分证明，见 [MDN iframe 事件说明](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/iframe)。改用其他加载方式应作为待验证方案。

“无论如何 5 秒就显示”只能隐藏等待提示，不能证明文档成功加载。原生评论列表是可讨论的新产品能力，并非本次根因确认或最小修复的前提。

### 2. `vars.set` 确实能造成入口失效，但不是每次写入都必然失效

用当前真实 Runner 和脚本宿主复现：声明变量 `mode`，默认值 `on`，正文脚本写 `chapterState='42'`。

| 初始已保存变量 | 保存后的变量 | 点击本次生成的入口 |
|---|---|---|
| `{}` | `{chapterState:'42', mode:'on'}` | `评论入口已失效，请刷新本章` |
| `{mode:'on'}` | `{mode:'on', chapterState:'42'}` | 正常打开 |

原因在 [setVar](../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeSourceRunner.ts:1456)：当前 Runner 的 `storedVars` 只加入脚本写入键，而保存给宿主的是 `storedVars + varValues`，其中会补齐声明的默认变量。[inlineKey](../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeSourceRunner.ts:1102) 使用当前 `storedVars` 直接 JSON 序列化计算指纹。下一次点击新建 Runner 读到完整持久化变量，指纹可能与刚生成的入口不同。

因此应保留“保存与指纹使用的状态不一致”这一已复现问题，而不是将“正文写 vars 必然失效”写成永久规则。其他章节、设置或账号在入口生成后发生真正变化，也可能按设计使旧入口失效，需要分别判断。本次没有复现原报告“每次刷新都必然失效”的全部条件。

补充对照：声明变量 `limit`，初始保存 `{limit:'1000'}`，正文调用 `vars.set('limit',2000)`，持久化得到 `{limit:'2000'}`，当前入口仍会失效；改为写字符串 `'2000'` 则正常。另将保存变量从 `{a:'1',b:'2'}` 仅改为键顺序相反，也会使入口失效。这表明修复必须统一默认值、声明变量的文本类型和变量对象序列化顺序，不能仅补齐默认变量。新增复核结果在 `../.codex_tmp/native-feedback-recheck-20261101.json`。

### 3. CRLF 清理差异属实，但需限定到具体函数

实际取出并执行 [AnalyzeRule.stripHtml](../harmony-book-source-engine/sourceengine/src/main/ets/core/rule/AnalyzeRule.ts:2926)，输入：

```text
<div>甲\r\n<br/>\r\n<br/>乙</div>
```

输出仍含 `甲\r\n\n\r\n\n乙`。它确实只压缩连续 LF，未先归一化 CRLF。

但原生表达式的 [NativeExpr.stripHtml](../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeExpr.ts:683) 已有 `\r\n? → \n`，同一输入得到 `甲\n\n乙\n`；应用正文规范化也有行尾归一化。因此“所有 CRLF 站点在阅读器必然异常”超出了此证据。建议统一相关清理函数的约定，并验证最终阅读文本，不直接将所有正文强制改成一段一行。

## `2026-11-01.md` 逐项核对

| 编号 | 核查结论 | 依据与处理建议 |
|---|---|---|
| 01 replace 与 counts 顺序 | 顺序属实；缺陷定性过重，部分建议与现状矛盾 | Runner 952 行之后先 replace，再 collectComments。作者预先生成的 counts 不会自动随替换重算。应说明“以最终正文行号为准”。建议再加 afterReplace 把 counts 移到 replace 后，重复了现有顺序。 |
| 02 空行计入下标 | 属实，属于已定义语义和便利性需求 | `text.split('\n')`；非空段序号可作为新增能力，但不是现有索引算错。 |
| 03 无加载更多桥 | 属实 | 当前仅生成时执行 fetch，无页面交互追加请求桥。起点固定 12 条的服务端事实本次未访问验证；不能据此认定引擎只能发一个分页请求。 |
| 04 max 不能表达式 | 属实 | `Number(spec.max)`，默认 60，上限 300。height 也仅接受数字；batch 同样是数字配置，不是已经表达式化的对照字段。 |
| 05 page.data 兄弟键不能互相引用 | 已复现 | `{items:'= [1,2]',shown:'= len(items)'}` 报未定义 items。renderDeep 不把输出键写回作用域。可以先在阶段 let 计算，或在页面 JS 用 items.length；顺序求值是需求选择。 |
| 06 动态对象只能 JS | 不成立；缺少专用聚合函数的建议可保留 | 已验证 `{[xs[0].id]:xs[0].n}` 可用；lib 可 `o[x.id]=x.n`，能无 JS 生成 counts。确实没有专用 toMap/reduce 内置，但不能据此说动态键不支持、被迫使用阶段脚本。 |
| 07 Cookie 自动保存未写 | 行为属实，“当前文档没写”不成立 | 当前脚本 HTTP 接口表已写 Cookie 继续自动保存；HttpClient 也保存 Set-Cookie，cookie.get 读同一书源 Cookie 存储。旧稿是否缺失需核对当时原件。 |
| 08 页面拿不到 data / JS 函数 | 对当前实现不成立 | 正文 scope.snapshot 存入上下文，点击时恢复，包含 data；已实测页面 data.original 读到正文 data.bid。表达式调用仍走同一套 lib/内置/JS 机制，没有页面专门禁用 JS 函数的分支。应把宿主求值作用域与 HTML 页面只能接收显式注入 data 区分开。 |
| 09 箭头函数不能返回对象 | 不成立 | 实际引擎 `map(xs,x => {key:x.id,value:x.n})` 正常。该规则语言不是直接执行 JS 的箭头语法；不能套用 JS 语句块解释。补示例和规则路径错误仍有价值。 |
| 10 任意 vars 写入都失效 | 部分成立，已找到更精确条件 | 见上文变量指纹对照，不能推广为无条件限制。 |
| 11 离线校验器不认 script | 作者工具可能陈旧，不能归为当前内核能力缺失 | 当前 fromObject/validate 接受随附五阶段 script 源。外部镜像未提供，所谓“官方唯一工具”身份及快照时间均未独立核实。版本匹配提示有价值。 |
| 12 图片脚本接口和静默降级 | 文档可改善；“引擎静默降级”证据不足 | 当前文档有 ctx 表、隔离说明、NoPadding 和失败行为。附件自己描述异常被源脚本 try/catch 吞掉，这不等于引擎自动吞错。可增加能力对照表。 |
| 13 章节只有 title | 表述不准确，拆字段需求可讨论 | 已有 url/isVip/isPay/isVolume/tag 等；拼标题可用表达式和条件，不必写 JS。是否新增 no/subtitle 应按多站需求判断。 |
| 14 换域完全不能自救 | 不成立；自动候选域回落确实缺少专用字段 | 顶层 url 作为稳定标识，不妨碍请求 URL 使用 `{{vars.server}}` 或脚本选绝对地址。当前文档已有服务器变量示例。不要为了换请求域直接改变书源身份；旧书籍的绝对 URL 和跨域 Cookie 仍需具体处理。 |
| 15 内置名单完全未公开、clean 冲突 | 部分错误 | get 确实是保留内置名，当前开发文档已有多张内置函数表；clean 不在当前 builtinNames 中，page 也不在该内置名单。把文档表自动生成成完整保留名索引仍有价值。 |
| 16 不同尺寸导致叠页 | 现象待复现，所给根因不成立 | 560×420、1200×900、1280×960 都是 4:3；420/960 不能作为缩放后的可见比例。当前 ReaderComicView 会逐图记尺寸并在 onComplete 更新比例，并非一直按首图排版。源端尺寸元数据可作为优化需求，但不能承诺加字段就解决叠页。 |
| 17 图片脚本没有 log | 属实，有诊断改进价值 | 独立图片会话未提供 log；未捕获异常会形成单图失败，源自行 catch 后引擎无法恢复被吞的原因。 |
| 18 image.hash 返回类型未写 | 不成立，而且按十六进制文本使用会错 | 当前文档在助手前明确“同步返回 Uint8Array”；NativeImageScriptRunner 的 invoke 也统一包装 Uint8Array。hash/hmac 返回字节，不能误补成十六进制字符串。 |
| 19 动作按钮没有 image | 属实，是当前隔离与上下文边界 | 书源级动作并不天然对应某本书某章。独立图片调试预览有价值，不必通过放宽动作环境才能实现。 |
| 20 图片处理开关不能逐图声明 | 配置限制属实，性能收益未测 | processPlainImages 是布尔值，params 在正文阶段求值；但脚本已有 ctx.url/index/params，可逐图原样返回。逐图 when 可评估；不能把“章节 ID 决定是否处理”的案例直接当作同章混图证据。 |

动态 counts 的现有无 JS 写法已实际运行：

```text
fn buildCounts(xs) {
  let o = {};
  for x in xs { o[x.id] = x.n; }
  return o;
}
```

这段只是演示动态对象构造，不自动解决跨站段落身份、净化后行号或重复条目累加。

## “本轮汇总”中的其他主张

| 主张 | 结论 |
|---|---|
| content.text 直接取 @html，replace 看到 HTML，后续宿主再规范化 | 基本属实。应明确处理顺序；HTML 中的匹配并非完全无法可靠实现，不应默认改变所有 @html 和 replace 的兼容语义。textMode 可作为显式新增模式评估。 |
| lib 不隐式读取页面上下文 | 属实，NativeExpr.callFunction 新建只含参数的 scope，是纯计算设计。传入 body/选择结果属于现有正常用法；不是实现失误。 |
| nextUrl 把上一页别名当新页 | 精确 URL 去重不足以识别任意站点别名，风险合理。nextUrl 的语义本来是下一页或剩余页，选中全部导航链接是规则层错误。不能通用认定 xxx_1.html 与 xxx.html 相同，也不能假设站点页码随路径数字单调增长。 |
| source-check 扁平化导入失败、JSONPath-only、GBK POST | 所述机制可能成立，但附件没有这些实际工具代码。仓库的 createTestHost 确实明确是 JSONPath 专用测试宿主，不代表产品 HTML 选择器不支持。修工具应保持相对目录与依赖完整，不能承诺多复制一个 CooperativeScheduler 就补齐当前依赖。 |
| 纯 CSS 列表必然被文本化，必须用 @ 链 | 对当前版本不成立。实际运行 `#main ul li`、`ul.chapter li a` 均返回元素外层 HTML。当前 AnalyzeRule.executeElementValues 已针对 ELEMENTS 保留节点上下文。旧镜像可能有此问题，不能发布成当前通用写法禁令。 |
| tag. 不支持、基础 XPath 都不能用 | tag.ul/tag.li 的样例已通过。XPath 支持取决于具体表达式及版本；不能从某个 following-sibling 例子推出“基础 XPath 全不支持”。 |
| fields 内 sel 默认取整页首个 | 对当前原生规则不成立。NativeExpr 的 sel 默认取当前 scope.item，列表字段的 item 是当前条目；开发文档也明确此约定。 |
| 两轮超时或 ECONNRESET 就判域名失效、书源层无解 | 证据不足。这些只能证明当时特定网络/客户端请求失败，不能排除协议、证书链、地区、限流、验证及临时故障。建议停用应写明样本、时间和网络，不可视为已核验永久站点事实。本次未重新访问这些站点。 |
| 取消 rate、提高 batch 就能普遍提速 | 只是特定测试条件下的结果。限流与并发是不同控制，批量请求还可能受队列、协议及站点承受能力约束，不能采用报告中的通用倍数或约 10/20/30 行实现成本估计。 |

## v6 提交稿逐项核对

| 编号 | 结论 |
|---|---|
| A 发现分页文档 | 有参考价值：宿主触底调用 loadMoreExploreBooks，传 explorePage+1；对原生阶段同样传实际页码。下一页空结果或没有新增书籍会停止，网络/验证提示另保留重试。应补充触发和停止机制；“发现本来只取第一页”不符合当前代码。见 ExplorePage.ets 391 行及 ExploreCoordinator.ts 628 行。 |
| B script 离线完全验不了 | 不成立。现有 native-script-check、native-js-check、native-comment-page-check 都可离线执行真实 Runner，附加测试也验证了脚本变量。作者自己的请求重放归一化失误不能归为产品不支持。面向书源作者的完整通用 CLI、HTML 宿主及版本一致性仍有建设价值。 |
| C keep/temp 矛盾 | 不是矛盾：keep 面向详情书籍变量，temp 面向 Runner 生命周期；目录和正文也可通过章节 URL 携带必要标识。更关键的是“其他阶段 keep 被忽略”错误：NativeScriptHost.ts 149 行明确抛出“keep 只能在详情阶段使用”。补充实际行为有用，不能照原建议写成忽略。 |
| D 脚本 HTTP 没有 trace | 对当前实现不成立。NativeScriptHost.fetch 325 行自动记录脱敏 URL、请求号、状态、长度、耗时、错误；NativeHost 将其送入 debugContext，HTTP 获取也传递该上下文。若旧版 UI 没显示需单独复现，不能直接写成当前未实现。 |
| E 独立请求不能并发 | 主张与正文自相矛盾：同一节已承认 http.all 可并发，当前支持 1–8 并发且逐项计数。声明式 toc.fetch 尚无对应字段，可作为独立需求；“script 只能串行”应删除。 |
| F 源级 notice/hint | 专用展示字段未见，需求合理。已有 comment 和 ui.toast 等不同形式的提示；不能说用户没有任何获知渠道。是否在阅读/详情页持续展示、何时展示需产品设计。 |
| G 密钥流截断最佳实践 | 仅限作者特定算法和已覆盖的输入长度，不是可普遍套用的规则；样本最大请求长度不证明未来请求也不超出。体积提示可以做，不能推荐所有密钥流固定截到 2 KB。 |
| H 付费/试读结果标记 | 正文结构化状态可评估；目录已有 isVip/isPay，不能笼统说没有任何付费元数据。HTTP 200 或短文本本身无法通用识别试读。示例表把 uid=1 列为 isFreeRead=false、payStatus=3，但所给 `isPaid = (... && payStatus !== '3')` 对该行求值为 false，表格与声称分支不一致；付费链路全通未独立核验。 |

v6 附带的旧问题中，负缓存、cache 按书籍建键、声明式目录排序/按 URL 去重、额外 fetch 覆盖阶段等，可以继续当作需求。列表 `unique` 不等于目录对象按 URL 去重；cache 声明名称约束也不等于脚本 cache 不能使用动态键。未知总页数且依赖上一页返回时，不能无条件并发，需先明确可发现或可预测的 URL。

## 随附 JSON 的独立检查

- JSON 可解析；当前 NativeSourceSpec.fromObject/validate 返回零错误；主 JS 可编译，没有发现具名 function 与当前内置函数的同名项。这个检查不等同于真机 QuickJS 完整导入检查或所有业务分支运行。
- 取附件原始评论 HTML 加模拟评论数据，用当前 NativeCommentPage.document 包装后，在本机 Playwright 桌面浏览器中就绪、评论渲染成功，出站请求为 0。它验证生成文档的桌面行为，不能证明目标 ArkWeb 正常，也不能推翻用户的真机超时现象。
- 附件 page HTML 为 5,263 UTF-8 字节，其中 script 为 3,206 字符；只有 dpMode、dpOffset 两个声明变量，page.fetch 没有 when。材料所说“评论列表直连开关关闭后的零请求版本、200 字符脚本”没有作为对应 JSON 一并提交，不能把该对照实验当作已由本附件重现。
- 当前附件自身在页面 URL 中继续读取 data.qdBid/qdCid/qdToken，并在 content.let 保留同值。这与早期“data 不能用，只能 vars”的结论也不一致。
- 段落对应只使用 `line = paragraphId - 1 - offset`；书名匹配失败后会放宽作者条件，章节名也有前缀匹配。没有对两个站点的实际段落文本逐段比对。“39/39 命中”最多说明计数落在有效下标范围，不足以证明语义对齐。异站存在删改、拆章、合章或多一个标题段时，固定偏移不能保证正确；这部分应优先视为书源自身的数据对齐风险。

## 建议采纳顺序

1. **优先核实评论页真机显示**：使用官方零网络示例和可固定版本的最小样本，保留 iframe/CSP/JS 异常和 generation 证据，再决定修复方案。
2. **处理已复现的变量状态与指纹不一致**：统一默认变量归一化和用于生成、校验的快照；保持真正的配置或账号变化会使旧入口失效的语义。
3. **统一文本清理与行号约定**：优先处理 AnalyzeRule 的 CRLF 差异，补充 replace、HTML 清理和 comments 行号的先后顺序；改变默认行为前评估兼容性。
4. **改进作者工具与文档可发现性**：标注 CLI/镜像版本、宿主能力边界，给出 keep/temp、内置保留名、图片 Uint8Array、发现分页和脚本 trace 的清晰示例。
5. **单独评估新增能力**：原生评论列表、加载更多、只显示计数、图片调试预览、逐图 when、源提示位、表达式化 max/height。它们是产品需求，不能因报告统一标了 P0/P1 就视为现有功能阻断。

## 本次验证结果

以下检查均通过：

```text
node harmony-book-source-engine/scripts/native-source-check.mjs        277 assertions
node harmony-book-source-engine/scripts/native-script-check.mjs        125 assertions
node harmony-book-source-engine/scripts/native-comment-page-check.mjs
node scripts/reader-comment-panel-check.mjs
node scripts/native-comment-page-service-check.mjs
node scripts/native-comment-page-browser-check.mjs
node .codex_tmp/native-feedback-audit-20261101.mjs
```

另用真实 AnalyzeRule 加载器验证了纯 CSS 列表保留元素及 tag. 链样例。浏览器检查清除进程代理变量并显式禁用浏览器代理；没有访问报告中的站点。没有修改应用、引擎、随附原件或 CHANGELOG，也没有声称完成真机修复。
