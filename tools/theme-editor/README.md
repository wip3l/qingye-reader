# 轻页主题编辑器

制作开源轻页 `.qytheme` 主题包（格式 2）的工具，有 Windows 桌面版和可在手机、平板上用的网页版。上传素材、调配色，首页三个页签（书架、发现、我的）、阅读页、朗读面板、启动封面和主题卡片在浅色与深色下并排实时预览，导出能直接在手机上导入的主题包；也能打开已有的主题包或主题文件夹继续编辑。

主题包的字段与素材规范见 [主题包开发指南](../../docs/theme-package-format.md)，编辑器只产出那里列出的内容。

## 使用

- **新建**：选一个内置主题作基底。没改的部件沿用基底主题，只有改过的部件进包。选付费主题作基底时，导入的人没有那套主题，应用会把基底换成默认主题；曜金藏书不能作基底。
- **打开**：`.qytheme` / `.zip`（应用导出的格式 1、格式 2 和手写包都行），或含 `manifest.json`、`theme.json`、`assets/` 的文件夹，也可以把包直接拖进窗口。没通过校验的包也会尽量打开，问题列在底部，改好后再导出。
- **预览**：书架画面可切换应用的四种书架布局（陪伴、平铺、宽松、紧凑），看封面、文件夹插画和首页背景在不同布局下的效果；首页画面的底栏按当前页签显示选中态图标，可切换第四个页签（三页签 / 听 / 足迹）看可选的“听”“足迹”图标。
- **编辑**：左侧选部件，右侧改字段。分浅深的部件跟着检查器顶上的“编辑浅色 / 编辑深色”，提供“从另一模式复制”和“按浅色生成深色初稿”。留空的颜色显示基底主题的值。点预览里的元素会跳到对应部件。
- **书架背景**：“首页背景”里除了通用那张，还有“按书架布局（可选）”四个槽位（陪伴、平铺、宽松、紧凑）。填了的布局在书架预览切到它时显示专属图，其余布局和发现、我的画面显示通用那张。
- **封面与文件夹**：“书籍素材”里除了默认那套封面和文件夹插画，还有可选的“深色封面”和“分组文件夹 · 深色”，填了以后深色模式换成它们，预览的深色一侧随之变化；空着时两种模式用同一套。
- **素材**：拖到槽位上或点“上传”。按文件头识别格式，SVG 做自包含检查，文件名自动改成 `assets/` 允许的字符，同一个文件只存一份。尺寸或比例不合规格时给出提示，位图可以一键居中裁成规格尺寸。
- **问题条**：错误会阻止导出，提示不会。点一条就跳到对应字段。没有编辑器能指出的错误时，会把整包交给应用的格式层（`entry/src/main/ets/theme/share/ThemePackageFormat.ts`）完整校验一遍，应用导入时会报的错这里先报。
- **保存与导出**：Ctrl+S 写回打开的格式 2 主题包；应用导出的旧格式包和文件夹第一次保存时走另存为，原文件不动。“导出为文件夹”在所选位置新建一个主题文件夹。
- **导出截图**：标题栏“导出截图”（手机宽度在“⋯”菜单里）把所有画面——书架四种布局、发现、我的、阅读、朗读、启动、主题卡片——的浅色、深色预览各画一台手机，拼成一张带主题名的 PNG，方便发给别人看效果。底栏第四个页签按当前选择画。桌面版是 2 倍图（约 8500 × 4100），触屏浏览器按画布上限自动缩小。
- **方案内容**：应用导出的方案包里的方案设置、阅读排版、强调规则和字体绑定，在“包信息”里只读展示，导出时原样写回，也可以整节移除。
- **草稿**：有未保存的更改时每 15 秒存一份草稿，下次启动可以恢复。

## 网页版

地址：<https://wip3l.github.io/qingye-reader/theme-editor/>（使用说明书在同一站点的根目录）。和桌面版用同一份界面代码，文件只在本机浏览器里处理，不上传。

- **布局**：宽屏三栏；平板宽度下部件列表收进左上“部件”按钮的抽屉；手机宽度下单栏，底部“部件 / 预览 / 设置”三个页签切换，预览只显示一台手机，顶上可切浅色、深色。选了部件会自动跳到“设置”，问题条点一下展开。
- **打开与导出**：用系统文件选择框打开 `.qytheme` / `.zip`；导出时下载，手机浏览器支持时可以“分享…”交给系统分享面板。没有打开/导出文件夹和写回原文件。
- **草稿**：存在浏览器的 IndexedDB，切到后台时也会存一份；清除网站数据会一并清掉。
- **离线**：打开过一次后可以断网使用，也可以添加到桌面。

`main` 上 `docs/manual/`、`tools/theme-editor/` 或主题源码有改动时，`.github/workflows/pages.yml` 重新构建并发布整个站点（仓库 Settings › Pages 的 Source 需为 GitHub Actions）。

快捷键：Ctrl+N 新建、Ctrl+O 打开（Ctrl+Shift+O 打开文件夹）、Ctrl+S 保存（Ctrl+Shift+S 另存为）、Ctrl+E 导出、Ctrl+Z / Ctrl+Y 撤销重做、F12 开发者工具。

预览只用内置主题的配色、阅读色、强调色和圆角（由 `scripts/extract-builtin-themes.mjs` 从 `BuiltinThemeRegistry.ets` 抽取）。内置主题的封面、角饰和插画是应用内的付费素材，编辑器不带，沿用它们的位置画成占位。

## 开发

```text
tools/theme-editor/
├── electron/          # 主进程（窗口、文件对话框、最近打开、草稿、关闭确认）与 preload
├── scripts/           # extract-builtin-themes.mjs：生成 src/core/builtinThemes.json
├── src/core/          # packageIo.ts：读写主题包、走应用的导入校验流程；不依赖 Electron 与 DOM
├── src/renderer/      # 编辑界面：部件定义、检查、实时预览；browserApi.ts 是网页版替代 Electron 的文件与草稿接口
│   └── public/        # 网页版的 manifest、Service Worker 与图标
└── test/              # Node 回归：手写包、应用导出的方案包、出错的包与导出往返
```

```bash
npm install
```

```bash
npm run dev
```

```bash
npm test
```

```bash
npm run dist
```

`npm run dist` 在 `release/` 下生成单文件便携版 `QingyeThemeEditor-<版本>.exe`。`.npmrc` 把 Electron 与 electron-builder 的二进制下载指向 npmmirror。

主题包格式改动时，编辑器跟着同一次提交更新：`src/core/packageIo.ts` 的导入流程要与 `ThemePackageService` 的导入保持一致，`src/renderer/sections.ts` 的字段要与 `ThemePackageParts` 一致，然后运行 `npm test`。

打包时若报 `Cannot create symbolic link`（electron-builder 的 winCodeSign 压缩包里带 macOS 符号链接，普通权限的 Windows 解不开），在 `%LOCALAPPDATA%\electron-builder\Cache\winCodeSign` 下把那个 `.7z` 解压到 `winCodeSign-2.6.0` 目录并跳过 `darwin`，再重新打包：

```bash
7za x <文件名>.7z -owinCodeSign-2.6.0 -x!darwin
```

冒烟检查：设置环境变量 `QY_EDITOR_SMOKE_SHOT=<png 路径>`（可选 `QY_EDITOR_SMOKE_SCRIPT=<页面脚本>`）启动程序，加载完成后会截图、打印渲染进程报错并退出。
