# 主题包开发指南

本文面向为开源轻页制作主题包（`.qytheme`，格式 2）的作者：把配色、素材和令牌按下面的结构放进一个文件夹，压缩后改名为 `.qytheme`，会员用户在主题页导入即可使用。主题包导入后成为一套自定义方案（占用方案额度），包里的素材在本机注册为主题 `pack:<packageId>`，方案的各个部件都指向它；用户也可以在自定义编辑器里把包内部件和内置主题混搭。

不想手写 JSON 的话，可以用 Windows 上的 [轻页主题编辑器](../tools/theme-editor/README.md)：上传素材、调配色，浅色和深色并排实时预览，导出前用应用同一份格式校验走一遍；也能打开已有的主题包继续改。

应用内部的主题模型、内置主题的新增方式见 [主题开发指南](theme-development.md)。用户在编辑器里直接上传素材得到的方案，导出后也是本格式的包（`packageId` 形如 `custom-xxxxxxxx`）。

## 目录结构

```text
my-theme/
├── manifest.json        # 包信息
├── theme.json           # parts（包内部件），可选的 settings / layout / emphasis / fonts
└── assets/              # 素材，只允许一层，文件名用字母、数字、下划线、连字符
    ├── nav_bookshelf.svg
    ├── cover_01.jpg
    └── ...
```

压缩时可以把 `my-theme/` 整个压进去，也可以只压目录里的内容；ZIP 不能加密，不能用 ZIP64。打包完成后把扩展名改成 `.qytheme`。

## manifest.json

```json
{
  "format": "qytheme",
  "formatVersion": 2,
  "packageId": "night-garden",
  "name": "夜花园",
  "author": "小明",
  "version": "1.0",
  "description": "深蓝夜色里的花园",
  "baseTheme": "plain-default",
  "requires": ["custom-scheme-v1", "reader-layout-v1", "theme-parts-v1"]
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `format` | 是 | 固定 `qytheme`。 |
| `formatVersion` | 是 | 固定 `2`。比应用支持的版本新时提示用户更新应用。 |
| `packageId` | 是 | 主题包的稳定标识，字母、数字、`.`、`-`、`_`，不超过 64 个字符。同一个 `packageId` 再次导入视为更新，原位替换那套方案；换 ID 就是另一个主题。 |
| `name` | 是 | 显示名，最多 24 个字符。 |
| `author` | 否 | 署名，最多 24 个字符，只做展示。 |
| `version` | 否 | 作者自定的版本号，最多 32 个字符。 |
| `description` | 否 | 一句话说明，最多 120 个字符，显示在主题详情。 |
| `baseTheme` | 否 | 包里没写的部件回退到哪个内置主题，默认 `plain-default`。内置主题 ID 见主题开发指南。选付费主题时，导入的人没有那套主题，基底会换成 `plain-default`（导入预览里会列出）；要所有人看到一样的效果，就用 `plain-default` 或把部件都写进包里。`obsidian-archive`、`celestial-vault` 这类专属主题不要作基底。 |
| `requires` | 是 | 至少包含 `custom-scheme-v1`；带 `parts` 时必须包含 `theme-parts-v1`；带字体文件时包含 `fonts-v1`；带 `layout` 时包含 `reader-layout-v1`；带 `emphasis` 时包含 `emphasis-rules-v3`。 |
| `assets` | 否 | 可以不写：应用导入时枚举 `assets/` 目录。写了就按 `[{ "path": "assets/x.png", "sha256": "...", "size": 123 }]` 登记，`sha256` 和 `size` 可省略，写了会核对。 |
| `credits` | 否 | 再导出的混搭方案记录原主题包：`{ "packageId", "name", "author" }`。手写包不用填。 |

## theme.json

```json
{
  "parts": { ... },
  "settings": { ... },
  "layout": { ... },
  "emphasis": { "enabled": true, "rules": [ ... ] },
  "fonts": [ ... ]
}
```

手写主题包只需要 `parts`。`settings` 里的 `customLightPalette`、`customDarkPalette`、`customLightEmphasis`、`customDarkEmphasis`、`customRadius`、`customLightStartupText`、`customDarkStartupText`、`customAppFontFamily` 是方案级的逐项覆盖（见主题开发指南“方案级覆盖”），写了它们时清单 `requires` 要加 `scheme-overrides-v1`；手写包一般不需要它们，颜色、圆角、启动文案和界面字体都直接写在 `parts` 里。`settings`、`layout`、`emphasis`、`fonts` 是应用导出自定义方案时写入的内容（方案的部件选择、阅读排版、强调规则、字体绑定），格式与应用导出的一致，手写时可以省略。省略 `settings` 时，导入得到的方案所有部件都指向这个包，颜色、阅读背景和启动文案取自 `parts`。

`settings` 里引用这个包自己时写 `pack:self`，例如 `"paletteThemeId": "pack:self"`、`"customLightReaderBackgroundAssetId": "pack:self:light"`；导入时换成安装后的 ID。

### parts

每一节都可选；没写的部件沿用 `baseTheme`。素材字段写 `assets/` 下的相对路径。颜色写 `#RRGGBB`，注明可带透明度的写 `#AARRGGBB`。

| 节 | 字段 | 说明 |
| --- | --- | --- |
| `light` / `dark` | `colors` | 界面配色：`pageColor`、`cardColor`、`inputColor`、`primaryTextColor`、`subTextColor`、`dividerColor`、`accentColor`、`buttonColor`、`dangerColor`。可以只写一部分。 |
| | `reader` | 阅读页：`backgroundColor`（必须是铺满任意尺寸的底色）、`textColor`、`subTextColor`、`contentTone`（`light` / `dark`，决定系统栏图标明暗）、`backgroundMode`（`ornaments` 角饰 / `image` 整图 / `none` 只有底色）。角饰模式填 `leading`（左上）与 `trailing`（右下）两张图（SVG 或透明底位图）；整图模式填 `image` 和 `imageFit`（`cover` / `contain` / `fill`）。 |
| | `emphasis` | 正文强调：`mode`（`none` / `text` / `highlight` / `bubble`）、`bubbleStyle`（内置气泡 ID，见主题开发指南；包里带了 `bubble` 节时自动用包内气泡）、`color`、`textColor`（可带透明度）。 |
| `ttsPanel` | `light` / `dark` | 朗读与有声书面板：`artwork`（720 × 520 的 SVG 或位图，贴顶等比缩放）、`skyColor`（插画背后的天空色）、`surfaceColor`（不透明的面板底色）、`glowColor`（带透明度的强调光）。四项都要写；只写一种模式时另一种模式沿用它。 |
| `navigation` | `bookshelf`、`explore`、`mine` | 首页底栏的三个图标，缺一不可。SVG 按主题色着色，位图保持原色。 |
| | `bookshelfSelected`、`exploreSelected`、`mineSelected` | 选中态图标，可选；没写的页签选中时仍用普通图标。旧版本应用会忽略这几项。 |
| | `search`、`searchSelected` | 旧版本应用底栏“搜索”页签的图标。本应用读包时照收但不显示；旧版本应用要求有 `search` 才肯导入，应用和桌面编辑器导出时缺了就用 `explore`（与 `exploreSelected`）的图标补上。 |
| | `labels` | 写 `hidden` 时底栏只显示图标，不显示“书架”等文字。 |
| `book` | `covers`、`shelfFrame`、`shelfFolder` | 书籍封面数组（最多 8 张，书架按书轮播）、书架边框 SVG、分组文件夹插画。 |
| `startup` | `light` / `dark` | 启动封面：`image`（竖屏位图）、`title`、`subtitle`（各最多 40 个字符；省略 `title` 时启动页不显示标题）。 |
| `bubble` | `frame`、`cap` | 强调气泡的边框 SVG（可选）与端饰 SVG（必填）。写了这一节，`emphasis.bubbleStyle` 自动指向包内气泡。 |
| `homeBackdrop` | `light` / `dark` | 书架、发现和我的页顶部的背景图（位图）。只写一种模式时，另一种模式不显示背景。旧版本应用会忽略这一节。 |
| `logo` | | 主题标识，SVG 或位图，显示在方案卡片的角标处。 |
| `preview` | | 预览图位图，显示在主题页的方案卡片上；省略时卡片显示启动封面。 |
| `radius` | `small`、`medium`、`large`、`card`、`button`、`bubble` | 圆角，0 到 48。 |
| `typography` | `appFont`、`appFontFamily` | 界面字体：`appFont` 指向包内字体文件（需要 `fonts-v1`），导入后加入用户字体库并作为这套方案的界面字体；没有字体文件时可只写 `appFontFamily` 指定系统字体族名。 |

示例：

```json
{
  "parts": {
    "light": {
      "colors": { "pageColor": "#F6F3EC", "cardColor": "#FFFFFF", "accentColor": "#2F6B5F", "buttonColor": "#2F6B5F" },
      "reader": {
        "backgroundColor": "#FBF7EE", "textColor": "#2F2A22", "subTextColor": "#7A7064", "contentTone": "light",
        "backgroundMode": "ornaments", "leading": "assets/reader_light_tl.svg", "trailing": "assets/reader_light_br.svg"
      },
      "emphasis": { "mode": "bubble", "color": "#DDEFE8", "textColor": "#1F4A40" }
    },
    "dark": {
      "colors": { "pageColor": "#121614", "cardColor": "#1B211E", "accentColor": "#8FD3C2", "buttonColor": "#6FB8A6" },
      "reader": {
        "backgroundColor": "#141917", "textColor": "#D7DBD6", "subTextColor": "#97A09B", "contentTone": "dark",
        "backgroundMode": "image", "image": "assets/reader_dark.jpg", "imageFit": "cover"
      }
    },
    "ttsPanel": {
      "light": { "artwork": "assets/tts_light.svg", "skyColor": "#D9EDE5", "surfaceColor": "#F4F7F5", "glowColor": "#2E2F6B5F" },
      "dark": { "artwork": "assets/tts_dark.svg", "skyColor": "#15302A", "surfaceColor": "#10171A", "glowColor": "#338FD3C2" }
    },
    "navigation": {
      "bookshelf": "assets/nav_bookshelf.svg", "explore": "assets/nav_explore.svg", "mine": "assets/nav_mine.svg"
    },
    "book": { "covers": ["assets/cover_01.jpg", "assets/cover_02.jpg"], "shelfFrame": "assets/frame.svg", "shelfFolder": "assets/folder.jpg" },
    "startup": { "light": { "image": "assets/startup.jpg", "title": "夜花园", "subtitle": "月下翻页" } },
    "bubble": { "cap": "assets/bubble_cap.svg" },
    "homeBackdrop": { "light": "assets/home_light.jpg", "dark": "assets/home_dark.jpg" },
    "logo": "assets/logo.svg",
    "radius": { "card": 14, "button": 22 }
  }
}
```

## 素材规范

| 素材 | 格式 | 规格 |
| --- | --- | --- |
| 阅读角饰 `leading` / `trailing` | SVG 或 PNG / WebP | SVG 用 `viewBox="0 0 480 480"`，位图取正方形，都要透明底；左上角与右下角是同一场景的两幅图，正文区域不要放密集细节。 |
| 阅读整图 `image` | PNG / JPG / WebP | 竖屏位图，按 `imageFit` 铺满或包含；浅色与深色各一张。 |
| 朗读面板 `artwork` | SVG 或位图 | 720 × 520，透明底或完整插画；下半部分会渐隐到 `surfaceColor`。 |
| 导航图标 | SVG 或 PNG / WebP | SVG 用 `viewBox="0 0 24 24"`、单色纯黑填充，应用按主题色着色（选中为强调色）；位图取 96 × 96 透明底，按原色显示在 24 × 24 vp 的位置，选中与否要靠选中态图标区分。旧版本应用只接受 SVG，带位图图标的包在旧版本上无法导入。 |
| 封面 `covers` | JPG / PNG | 450 × 660，完整插画，不叠加书名或作者。 |
| 书架边框 `shelfFrame` | SVG | 与封面同比例，中心透明，只画外框和角花。 |
| 文件夹插画 `shelfFolder` | JPG / PNG | 450 × 660。 |
| 启动封面 `image` | JPG / PNG | 841 × 1870 竖屏，底部约 1/5 会叠加文案，不放主体。 |
| 首页背景 `homeBackdrop` | JPG / PNG / WebP | 1080 × 1350（4:5），贴顶铺满宽度，比例不同时居中裁成 4:5。画面放在上部约四成，应用会叠渐变向下淡成页面底色；不要放文字，深色图的亮部要克制。 |
| 气泡边框 `frame` / 端饰 `cap` | SVG | 端饰为正方形小图，按字号缩放，右端自动旋转 180°。 |
| 主题标识 `logo` | SVG | `viewBox="0 0 64 64"`。 |
| 字体 `appFont` | TTF / OTF / TTC | 请确认字体允许再分发。 |

限制：

- SVG 必须自包含：不得出现 `<script>`、`<image>`、`<use>`、`<filter>`、`<foreignObject>`、`href=`、`url(`，单个不超过 1 MB。
- 位图单个不超过 20 MB，字体单个不超过 40 MB，素材总数不超过 48 个，整包不超过 80 MB，解压后不超过 160 MB。
- 文件扩展名必须与实际格式一致（按文件头识别），`jpeg` 按 `jpg` 处理。
- 素材只能放在 `assets/` 一层，文件名 `[A-Za-z0-9][A-Za-z0-9_-]*`。

导入失败时应用会提示具体原因（哪个字段、哪个素材），按提示修改即可。

## 兼容与回退

- 比当前应用新的 `formatVersion`，或 `requires` 里有应用不认识的能力，导入时提示更新应用。
- 没写的部件按 `baseTheme` 显示，所以只带配色的小包也能完整使用。
- 用户在编辑器里把包内部件换成内置主题的部件是允许的；再导出时，包内素材会随新包一起打出去，并在 `credits` 里保留原作者信息。
- 同一个 `packageId` 再次导入时原位更新：用户的阅读排版和强调规则保留并合并，素材和配色换成新版本。
- 方案设置会随云同步到用户的其他设备，素材不会；另一台设备上会提示“主题包素材不在这台设备上”，重新导入同一个包即可恢复。
- 桌面图标由应用编译期声明，主题包提供不了；应用这套方案时沿用“自定义主题”图标。

## 测试

1. 把文件夹压成 ZIP，改名为 `.qytheme`，用文件管理或聊天软件发到手机，用开源轻页打开，或在主题页点“导入”。
2. 导入前的预览会列出包里有哪些部件；确认后在主题详情点“应用主题”。
3. 浅色、深色、跟随系统各检查一次：首页导航图标与首页背景、书架封面与分组文件夹、阅读页背景与强调气泡、朗读面板、启动封面。
4. 改动素材后保持 `packageId` 不变再次导入，确认走的是更新。

仓库里 `node --experimental-strip-types scripts/theme-package-check.mjs` 覆盖格式校验的纯逻辑，可以在提交格式改动前运行。
