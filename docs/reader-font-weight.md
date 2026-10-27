# 阅读字体粗细

正文粗细设置沿用 `fontWeight`，默认 400，范围 50–900，加减步长 50，也可以输入整数。阅读字体与正文排版两个入口读写同一个值。

## 字体类型与显示

- 有 `wght` 轴的导入字体：使用原生可变字重，限制到字体声明的轴范围。
- 已识别的单个静态 TTF/OTF：400 表示文件原始字形，低于 400 保持原样；大于 400 使用细描边逐渐加粗。这里的 400 是微调起点，不保证字体文件自身的名义字重也是 400。
- 系统字体、字体集合 TTC 和无法确认能力的文件：保留原生匹配，不猜测它们的能力。
- 章节标题和正文内标题使用独立的 `titleFontWeight`，默认 600。
- 每条正则规则使用独立的 `fontWeight`，默认 400；命中规则时优先于正文或标题粗细。旧规则缺少该字段时补为 400。
- 标题粗细随主题档案和主题包保存；规则粗细随规则编码、同步和主题包保存。

静态字体的排版字重固定为 400，避免系统伪加粗与描边叠加。描边宽度为 `字号像素 × 0.03 × (设置值 - 400) / 500`，在 900 时每侧最多扩张字号的 1.5%。描边不修改字宽、换行、分页或选区坐标。

## 实现细节

`ReaderFontMetadata` 通过有界读取检查 SFNT 表目录、OS/2 和 fvar，不需要将整个字体读入内存。字体注册时缓存能力，卸载时清除。

`ReaderFontStroke` 在具有相同排版参数的透明文字段落上取得原生 `Run`，附加同色画笔后调用 `Run.paint`。透明填充避免重绘正文填充和抗锯齿边缘；阴影、背景、装饰仍由原段落绘制。描边缓存随页面释放，纯系统/可变字体段落不生成描边段落。实际回退到其他字体的缺字和表情不描边。

不能用 `Run.getPositions()` 重建 TextBlob：真机上这些坐标保留塑形阶段的原点，没有包含最终换行、两端对齐的全部偏移。也不能再给 `Run.paint` 添加行偏移，它已包含原段落坐标变换。

正文、标题、主题排版和正则字体预览共用此描边实现。正则预览仍保留背景、阴影、下划线和装饰图片。

## 验证

本地检查：

```powershell
node scripts/reader-font-metadata-check.mjs '本地字体路径.ttf'
node scripts/reader-font-weight-check.mjs
node scripts/reader-settings-persistence-check.mjs
node scripts/theme-typography-check.mjs
node scripts/custom-font-lifecycle-check.mjs
node scripts/theme-framework-check.mjs
```

设备测试 `ReaderFontWeightTestRunner` 使用显式测试素材，不改书架、排版设置或字体选择。将本地静态 TTF 临时复制到 `entry/src/ohosTest/resources/rawfile/reader-font-fixture.ttf`，构建 `entry@ohosTest` 并安装测试 HAP，然后执行：

```text
hdc -t <设备> shell aa test -b io.legado.read -m entry_test -s unittest /ets/testrunner/ReaderFontWeightTestRunner -s timeout 60000
```

测试比较 400、401、450、500、600、900 的整章分页、片段位置和像素覆盖量，并输出 PNG 的分段 Base64 供画面检查。测试素材是本地文件，不提交到仓库，也不加入正式应用资源。

本次使用「乖乖小熊的打工日记.ttf」：文件大小 10,719,676 字节，名义字重 400，无 fvar 表；读取 226 字节即可完成能力检查。真机验证了混合字号、颜色、中文、英文、标点、两端对齐和跨页文本。

## 预览黑底回归修复

原生 TextStyle 的 `backgroundRect: undefined` 会被设备绑定层解析成黑色背景。共享 `ReaderFontTextStyle.resolve` 显式设置透明背景，且不把缺省的行高等可选值写成 undefined。正常片段也重置背景，避免继承前一高亮片段。

真机用同样的蓝色文字与白底测试：旧写法产生 93,073 个纯黑背景像素，新写法为 0。`ReaderFontWeightTestRunner` 使用实际预览样式构造器执行该对照，并导出 `PREVIEW_IMAGE before/after`。

## 正则颜色透明度

阅读字体页的文字色、高亮色块和气泡色取色器启用透明度滑块：0% 不透明、100% 完全透明。保存格式为 ArkUI 的 `#AARRGGBB`，仍兼容六位 `#RRGGBB`。改变色相、明度或预置颜色会保留当前透明度；原有非正则取色器保持 RGB 模式。

正则颜色校验、规则编码与 native style 均保留 alpha。主题气泡的预设透明度与所选颜色的 alpha 相乘。透明黑 `#00000000` 使用显式 colorEnabled 标记，避免被误认为“未设置颜色”。

新增回归：`node scripts/regex-bubble-color-check.mjs`、`node scripts/reader-color-picker-check.mjs`。

真机另验证了同一静态字体、同一字号、同一颜色下的独立粗细：标题 900、正文 400、正则 700，仅标题与命中正则生成描边，未扩散到前后正文。

## 粗细步进按钮交互回归

不要把粗细数值作为普通参数传给 `@Builder` 再由点击回调捕获：这会让数值标签及回调停留在最初的值。`ReaderFontWeightStepper` 使用 `@Prop` 响应父页面更新，点击时先更新自身数值再通知父页面，禁用状态也直接读取当前值。

`ReaderFontWeightStepperTest` 复用正式组件，使用 `entry_test` 的独立偏好存储。构建并安装 `entry@ohosTest` 后执行：

```text
python scripts/reader-font-stepper-device-check.py --hdc <hdc路径> --device <设备ID>
```

真机验证：正文、标题、正则分别连续增加三次并减少一次；父页面状态同步；50/900 上下限的禁用与恢复；清空界面值后从偏好存储恢复三项数值。测试结束关闭专用测试页面，不改正式应用的排版设置。

### 点击数字精确输入

阅读字体页的正文、标题、正则粗细均可点击数值打开数字键盘，输入 50–900 的任意整数；键盘“完成”或失焦时提交。空输入保持原值，越界值限制到上下限。提交后加减仍以 50 为步长，基于精确值继续调整，例如 425 → 475。

验证输入逻辑：`node scripts/reader-font-weight-input-check.mjs`。真机交互测试在上一条设备命令后加 `--precise`，覆盖自动聚焦、三处精确输入、空值、上下限、输入后的步进以及偏好存储恢复。
