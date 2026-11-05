# 轻页主题编辑器

制作开源轻页 `.qytheme` 主题包（格式 2）的 Windows 桌面程序。上传素材、调配色，书架、阅读页、朗读面板、启动封面和主题卡片在浅色与深色下并排实时预览，导出能直接在手机上导入的主题包；也能打开已有的主题包或主题文件夹继续编辑。

主题包的字段与素材规范见 [主题包开发指南](../../docs/theme-package-format.md)，编辑器只产出那里列出的内容。

## 使用

- **新建**：选一个内置主题作基底。没改的部件沿用基底主题，只有改过的部件进包。
- **打开**：`.qytheme` / `.zip`（应用导出的格式 1、格式 2 和手写包都行），或含 `manifest.json`、`theme.json`、`assets/` 的文件夹，也可以把包直接拖进窗口。没通过校验的包也会尽量打开，问题列在底部，改好后再导出。
- **编辑**：左侧选部件，右侧改字段。分浅深的部件跟着检查器顶上的“编辑浅色 / 编辑深色”，提供“从另一模式复制”和“按浅色生成深色初稿”。留空的颜色显示基底主题的值。点预览里的元素会跳到对应部件。
- **素材**：拖到槽位上或点“上传”。按文件头识别格式，SVG 做自包含检查，文件名自动改成 `assets/` 允许的字符，同一个文件只存一份。尺寸或比例不合规格时给出提示，位图可以一键居中裁成规格尺寸。
- **问题条**：错误会阻止导出，提示不会。点一条就跳到对应字段。没有编辑器能指出的错误时，会把整包交给应用的格式层（`entry/src/main/ets/theme/share/ThemePackageFormat.ts`）完整校验一遍，应用导入时会报的错这里先报。
- **保存与导出**：Ctrl+S 写回打开的格式 2 主题包；应用导出的旧格式包和文件夹第一次保存时走另存为，原文件不动。“导出为文件夹”在所选位置新建一个主题文件夹。
- **方案内容**：应用导出的方案包里的方案设置、阅读排版、强调规则和字体绑定，在“包信息”里只读展示，导出时原样写回，也可以整节移除。
- **草稿**：有未保存的更改时每 15 秒存一份草稿，下次启动可以恢复。

快捷键：Ctrl+N 新建、Ctrl+O 打开（Ctrl+Shift+O 打开文件夹）、Ctrl+S 保存（Ctrl+Shift+S 另存为）、Ctrl+E 导出、Ctrl+Z / Ctrl+Y 撤销重做、F12 开发者工具。

预览只用内置主题的配色、阅读色、强调色和圆角（由 `scripts/extract-builtin-themes.mjs` 从 `BuiltinThemeRegistry.ets` 抽取）。内置主题的封面、角饰和插画是应用内的付费素材，编辑器不带，沿用它们的位置画成占位。

## 开发

```text
tools/theme-editor/
├── electron/          # 主进程（窗口、文件对话框、最近打开、草稿、关闭确认）与 preload
├── scripts/           # extract-builtin-themes.mjs：生成 src/core/builtinThemes.json
├── src/core/          # packageIo.ts：读写主题包、走应用的导入校验流程；不依赖 Electron 与 DOM
├── src/renderer/      # 编辑界面：部件定义、检查、实时预览
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
