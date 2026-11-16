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
| `requires` | 是 | 至少包含 `custom-scheme-v1`；带 `parts` 时必须包含 `theme-parts-v1`；带字体文件时包含 `fonts-v1`；带 `layout` 时包含 `reader-layout-v1`；带 `emphasis` 时包含 `emphasis-rules-v3`；阅读页角饰只有左上或右下一张时包含 `reader-single-corner-v1`；`covers` 超过 8 张时包含 `book-covers-16-v1`；气泡边框是位图或只有边框没有端饰时包含 `bubble-frame-v1`；气泡端饰或书架边框是位图时（深色那张也算）包含 `bitmap-cap-shelf-frame-v1`。 |
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
| | `reader` | 阅读页：`backgroundColor`（必须是铺满任意尺寸的底色）、`textColor`、`subTextColor`、`contentTone`（`light` / `dark`，决定系统栏图标明暗）、`backgroundMode`（`ornaments` 角饰 / `image` 整图 / `none` 只有底色）。角饰模式填 `leading`（左上）与 `trailing`（右下）图片（SVG 或透明底位图），可以只填一张，另一角空着（此时 `requires` 要加 `reader-single-corner-v1`）；两项填同一个素材时右下角旋转 180° 显示；`leadingScale`、`trailingScale` 分别是左上、右下角饰的显示大小，相对默认尺寸（屏幕短边 × 0.36，夹在 112–260vp）的倍数，0.5–2，默认 1，最大不超过短边的 0.8，旧版本应用忽略这两项按 1 显示。整图模式填 `image` 和 `imageFit`（`cover` / `contain` / `fill`），还可以同时填 `leading` / `trailing`（及两个大小），角饰叠在整图上面；旧版本应用只显示整图。 |
| | `emphasis` | 正文强调：`mode`（`none` / `text` / `highlight` / `bubble`）、`bubbleStyle`（内置气泡 ID，见主题开发指南；包里带了 `bubble` 节时自动用包内气泡）、`color`、`textColor`（可带透明度）。 |
| | `commentBubble` | 可选：段评气泡（含本章说）的外观，见下文“段评气泡”。旧版本应用会忽略。 |
| | `titleEmphasis` | 可选：章节标题的强调，见下文“标题强调”。不写表示主题不设置，标题保持原样。旧版本应用会忽略。 |
| | `chapterHead` | 可选：章首装饰（标题旁的饰图、序号行颜色），见下文“章首装饰”。旧版本应用会忽略。 |
| `ttsPanel` | `light` / `dark` | 朗读与有声书面板：`artwork`（720 × 520 的 SVG 或位图，贴顶等比缩放）、`skyColor`（插画背后的天空色）、`surfaceColor`（不透明的面板底色）、`glowColor`（带透明度的强调光）。四项都要写；只写一种模式时另一种模式沿用它。 |
| `navigation` | `bookshelf`、`explore`、`mine` | 首页底栏的三个图标，缺一不可。SVG 按主题色着色，位图保持原色。 |
| | `bookshelfSelected`、`exploreSelected`、`mineSelected` | 选中态图标，可选；没写的页签选中时仍用普通图标。旧版本应用会忽略这几项。 |
| | `listen`、`footprint`（及 `listenSelected`、`footprintSelected`） | 可选第四个页签“听”“足迹”的图标（其他设置 › 底栏里开启），可以不写；没写时这个页签用基底主题的图标。旧版本应用会忽略。 |
| | `search`、`searchSelected` | 旧版本应用底栏“搜索”页签的图标。本应用读包时照收但不显示；旧版本应用要求有 `search` 才肯导入，应用和桌面编辑器导出时缺了就用 `explore`（与 `exploreSelected`）的图标补上。 |
| | `labels` | 写 `hidden` 时底栏只显示图标，不显示“书架”等文字。 |
| `navigationDark` | 同 `navigation` 的图标字段 | 可选：深色模式单独的图标，每一项都可以不写，没写的沿用 `navigation`；给了深色普通图标却没给深色选中态时，选中也用深色普通图标。没有 `navigation` 时整节不读，`labels` 只看 `navigation`。SVG 图标本来就按主题色着色，一般只有彩色位图才需要另给。旧版本应用会忽略。 |
| `book` | `covers`、`shelfFrame`、`shelfFolder` | 书籍封面数组（最多 16 张，书架按书轮播；超过 8 张时 `requires` 要包含 `book-covers-16-v1`，旧版本应用最多只收 8 张）、书架边框（SVG 或透明底位图；用位图时 `requires` 要包含 `bitmap-cap-shelf-frame-v1`，旧版本应用会提示先更新）、分组文件夹插画。 |
| | `coversDark` | 可选：深色模式单独的一套封面（最多 16 张）。不写时深色模式也用 `covers`。和 `covers` 张数相同、顺序对应时，同一本书切换深浅色落在同一序号上，适合放同一幅画的两个版本。旧版本应用会忽略，两种模式都显示 `covers`，所以 `covers` 要始终写。 |
| | `shelfFrameDark` | 可选：深色模式单独的书架边框，格式要求同 `shelfFrame`（这张是位图也要声明 `bitmap-cap-shelf-frame-v1`）。边框按原色显示，深色描边在深色书架上看不清时再给。不写时深色模式也用 `shelfFrame`。旧版本应用会忽略，两种模式都显示 `shelfFrame`。 |
| | `shelfFolderDark` | 可选：深色模式单独的文件夹插画。不写时深色模式也用 `shelfFolder`。旧版本应用会忽略，两种模式都显示 `shelfFolder`。 |
| | `coverCrops`、`coverCropsDark`、`shelfFolderCrop`、`shelfFolderCropDark` | 可选的显示区域（见下文“显示区域”）：`coverCrops` 是数组，按 `image` 对应到 `covers` 里的某张封面；`coverCropsDark` 同理，对应 `coversDark`；`shelfFolderCrop`、`shelfFolderCropDark` 分别对应两张文件夹插画。 |
| `startup` | `light` / `dark` | 启动封面：`image`（竖屏位图）、`title`、`subtitle`（各最多 40 个字符；省略 `title` 时启动页不显示标题）。 |
| `bubble` | `frame`、`cap`、`frameSlice`、`frameRepeat`、`frameBreak`、`frameTint` | 强调气泡的端饰与边框（都是 SVG 或透明底位图），至少给一样；边框是位图或没有端饰时 `requires` 要包含 `bubble-frame-v1`，端饰是位图时（`bubbleDark` 里的也算）要包含 `bitmap-cap-shelf-frame-v1`，旧版本应用会提示先更新。写了这一节，`emphasis.bubbleStyle` 自动指向包内气泡。边框的拉伸设置见下文“气泡边框”，旧版本应用忽略这些字段、也不画边框。 |
| `titleBubble` / `titleBubbleDark` | 同 `bubble` | 可选：只给标题强调用的端饰与边框（标题气泡），深色那套按项沿用浅色，规则同 `bubbleDark`。素材 SVG、位图都收，不用声明 `requires`；旧版本应用会忽略。 |
| `bubbleDark` | 同 `bubble` | 可选：深色模式单独的端饰与边框。端饰、边框各自沿用：深色没写的那一项用 `bubble` 的（边框连同它的拉伸设置）；某一项只在一种模式里有时，两种模式都用它。端饰按原色显示、边框不开 `frameTint` 时也是原色，浅色那套放在深色纸面上看不清时再给。位图边框不用另外声明 `bubble-frame-v1`。旧版本应用会忽略，两种模式都用 `bubble`。 |
| `homeBackdrop` | `light` / `dark` | 书架、发现和我的页顶部的背景图（位图）。只写一种模式时，另一种模式不显示背景。旧版本应用会忽略这一节。 |
| `shelfBackdrop` | `companion` / `tile` / `loose` / `compact` | 可选：按书架布局（陪伴、平铺、宽松、紧凑）分别给的背景，每种布局下写 `light` / `dark`（及可选的 `lightCrop` / `darkCrop`）。只在书架页、用这种布局时显示，没写的布局或模式用 `homeBackdrop` 那张；发现、我的等页签始终用 `homeBackdrop`。浅色、深色互不借用。旧版本应用会忽略这一节。 |
| | `lightCrop` / `darkCrop` | 可选的显示区域，对应同一模式的背景图。 |
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
      "bookshelf": "assets/nav_bookshelf.svg", "explore": "assets/nav_explore.svg", "mine": "assets/nav_mine.svg",
      "listen": "assets/nav_listen.svg", "footprint": "assets/nav_footprint.svg"
    },
    "book": { "covers": ["assets/cover_01.jpg", "assets/cover_02.jpg"], "shelfFrame": "assets/frame.svg", "shelfFolder": "assets/folder.jpg" },
    "startup": { "light": { "image": "assets/startup.jpg", "title": "夜花园", "subtitle": "月下翻页" } },
    "bubble": { "cap": "assets/bubble_cap.svg" },
    "homeBackdrop": { "light": "assets/home_light.jpg", "dark": "assets/home_dark.jpg" },
    "shelfBackdrop": { "companion": { "light": "assets/home_companion_light.jpg", "dark": "assets/home_companion_dark.jpg" } },
    "logo": "assets/logo.svg",
    "radius": { "card": 14, "button": 22 }
  }
}
```

### 显示区域

封面、文件夹插画和首页背景可以只显示图里的一块，图片文件不改。应用内编辑器给 GIF / 动态 WebP 取景时就这样记录，重新裁剪编码会只剩第一帧。

```json
{ "image": "assets/cover_03.gif", "x": 120, "y": 0, "width": 450, "height": 660, "imageWidth": 800, "imageHeight": 900 }
```

- `image` 是它所属的素材，必须和素材位当前的图一致；对不上的区域（换了图、删了封面后留下的）读包和导出时都会丢掉。
- `x`、`y`、`width`、`height` 是相对 `imageWidth` × `imageHeight` 的像素，只看比例，可以按缩小后的图来量；区域要落在图内、宽高为正，否则整个包导入失败。
- 显示时区域等比放大到盖满素材位、居中，区域比例和素材位不同时裁掉区域两边多出的部分。
- 旧版本应用不认这些字段，显示整张图。

### 气泡边框

正文里每一行强调文字各画一段边框：边框图按比例缩放到文字行的高度，两端花纹保持原样，中间按这段文字的长度拉长或平铺。

- 文字带高度是强调文字字号的 1.36 倍，以文字中线为准。
- `frameSlice`：四条拉伸线，都是占原图宽或高的比例（0–0.49）。`left` / `right` 是左右两端不拉伸的宽度；`top` / `bottom` 是文字带上下留在外面的高度，线外的部分照样画出来（阴影、出头的花纹）。省略时上下贴图边，左右各留“图高 × 0.6”，最多占图宽的 30%。
- `frameRepeat`：`stretch`（默认）中段拉伸；`round` 中段整块重复，略微压缩或拉宽，花纹不会停在半块上。
- `frameBreak`：`full`（默认）换行处每一行都画两端，换行处的端头画进页边距、不会让文字重新换行；`cut` 换行处不画端头，边框在断开处平切。
- `frameTint`：`true` 时把边框染成强调设置里的气泡底色（浅深色各用各的），适合单色线稿；默认保留原色。
- 整段强调文字的首尾会按端头宽度把前后文字推开；有端饰时端饰画在边框外侧。
- 用边框时不再画强调底色的圆角背景。不透明的图（JPG、不带透明通道的 PNG）会在正文里露出底色。

```json
"bubble": {
  "frame": "assets/bubble_frame.png",
  "frameSlice": { "left": 0.17, "right": 0.17, "top": 0.08, "bottom": 0.08 },
  "frameRepeat": "round"
},
"bubbleDark": {
  "frame": "assets/bubble_frame_night.png",
  "frameSlice": { "left": 0.18, "right": 0.18, "top": 0.08, "bottom": 0.08 }
}
```

### 标题强调

`light.titleEmphasis`、`dark.titleEmphasis` 决定章节标题的强调，两种模式各写各的：

- `mode`：`none`（明确不强调）、`text`（仅文字色）、`highlight`（高亮底色）、`bubble`（气泡）。整节不写表示主题不设置。
- `bubbleStyle`：只对 `bubble` 有效。内置气泡样式 ID；`emphasis` 表示和正文强调用同一套样式与素材（含 `bubble` 节的端饰边框）；不写时，包里有 `titleBubble` 就用它，否则同 `emphasis`。
- `color`、`textColor`：强调底色、文字色，可带透明度；不写时用正文强调的颜色。

读者在阅读设置里把“标题强调”选为“跟随主题”（新装默认，旧的“无强调”也迁到这一项）时用主题的标题强调；主题不设置时标题沿用正则规则的效果。“同正文强调”始终和对话用同一套，不看这一节。标题分主副两行时每行各画一个气泡，单行太长折行时按边框的“换行处”设置。

```json
"light": { "titleEmphasis": { "mode": "bubble", "color": "#E9D3A8", "textColor": "#5A3A1C" } },
"dark":  { "titleEmphasis": { "mode": "bubble", "color": "#3A3226", "textColor": "#F2DEAE" } },
"titleBubble": {
  "cap": "assets/title_cap.svg",
  "frame": "assets/title_frame.png",
  "frameSlice": { "left": 0.16, "right": 0.16, "top": 0.12, "bottom": 0.12 }
}
```

应用导出的方案里，方案对标题强调的覆盖写在 `customLightEmphasis.title` / `customDarkEmphasis.title`（字段同上，`mode` 还可以是 `off`：来源主题设了标题强调、方案要改回不设置），方案自己的标题气泡写成 `pack:self:title`。

### 章首装饰

`light.chapterHead`、`dark.chapterHead` 给每章的标题加一张饰图，并可以单独给序号行上色。字段都可以不写：

- `image`：饰图，SVG 或透明底位图。只写了一种模式时另一种模式沿用它（连同 `placement`、`scale`）。
- `placement`：`side`（缺省，标题左侧）、`top`（标题上方）、`bottom`（标题下方）。左侧时饰图贴版心左边、上下居中于整组标题，标题在剩下的宽度里按读者设的对齐方式排；上方、下方时饰图单独占一行，左右跟着标题的对齐方式。
- `scale`：大小倍数 0.5–2，缺省 1。左侧时 1 表示和整组标题一样高（按每段标题一行估算，宽度最多占版心的 30%）；上方、下方时 1 表示约 0.9 个标题字高。
- `numberColor`：分段标题第一段（“第十二章”那一行）的颜色，可带透明度；不写时和标题同色。读者在阅读设置里开了标题分段才生效，各模式写各的。

竖长的图适合放左侧，横长的花纹适合放上方或下方。饰图在标题单独成页、滚动阅读和仿真翻页里都会画。读者可以在阅读设置的标题一栏关掉“章首装饰”。

```json
"light": { "chapterHead": { "image": "assets/title_staff.png", "numberColor": "#8D8478" } },
"dark":  { "chapterHead": { "image": "assets/title_staff_dark.png", "numberColor": "#857D70" } }
```

应用导出的方案里，方案对章首装饰的选择写在 `customLightEmphasis.chapterHead` / `customDarkEmphasis.chapterHead`：不写表示跟随强调气泡的来源主题，`none` 表示不显示，`pack:self` 表示用这个包自己的。

### 段评气泡

`light.commentBubble`、`dark.commentBubble` 决定正文段评与本章说气泡的样子，两种模式各写各的。每个字段都可以不写，不写的沿用强调气泡样式推出来的样子：内置气泡样式有各自的段评配色；包内气泡（`bubble` 节）的段评用强调底色、文字色推导，和强调气泡对得上。书源设置了段评颜色时以书源为准。

- `shape`：`outline` 透明底描边，颜色跟正文墨色；`pill` 胶囊；`rounded` 圆角；`cut` 切角。不认得的值按不写处理。
- `radius`：圆角占气泡高的比例，0–0.5，只对 `rounded` 有效，默认 0.2。
- `fill`、`stroke`、`text`：底色、描边、文字色，可带透明度。`outline` 不用 `fill`。
- `ornament`：角上的小图形，取值 `none`（不画）、`star`、`sparkle`、`dot`、`moon`、`leaf`、`sprig`、`rose`、`paw`、`seal`、`diamond`、`pendant`、`scroll`、`cord`、`signal`、`frame`、`sketch`、`postcard`、`folio`，或 `custom`（用 `ornamentImage`）；`ornamentColor` 是它的颜色，不写时用描边色。

```json
"light": { "commentBubble": { "shape": "rounded", "radius": 0.2, "fill": "#B98546", "text": "#FFF6E6", "ornament": "star" } },
"dark":  { "commentBubble": { "fill": "#EBD3AE", "text": "#4A3423" } }
```

#### 气泡图与角标图

想让段评气泡长成自己画的样子，可以给一张整只气泡的图（尾巴、花边都画在图里），再给一张角标图代替内置小图形：

- `image`：气泡图，SVG 或位图，透明底。写了它，`shape`、`radius`、`stroke` 不再生效；`fill` 只在 `imageTint` 时用来染色。写 `"none"` 表示这个模式不用图片（不沿用另一模式的图）。
- `imageText`：文字区离图片四边的比例 `{ left, right, top, bottom }`。文字区的高度对齐正文里气泡的高度（段评字号 × 1.32），整张图按这个比例缩放。不写时左右各“图高 × 0.35”（最多 25%）、上 12%、下 20%。
- `imageSlice`：左右两条拉伸线 `{ left, right }`，比例 0–0.49。文字变长时只拉伸两线之间的部分，两端不变形；竖直方向不拉伸。不写时左右各“图高 × 0.6”，最多 30%。
- `imageRepeat`：中间部分 `stretch` 拉伸（默认）或 `round` 平铺。
- `imageBreak`：气泡被折到两行时，前一行那段 `cut` 裁到文字区底边、不画尾巴（默认），或 `full` 画整图。
- `imageTint`：`true` 时整张图染成 `fill`（适合单色剪影图）。书源自带段评颜色时，图片气泡只在染色时吃书源底色，文字色以书源为准。
- `ornamentImage`：`ornament` 为 `custom` 时的角标图，SVG 或位图；写了 `ornamentColor` 时整张染成该色，否则按原色。`ornamentCorner` 取 `topLeft`、`topRight`（默认）、`bottomRight`；`ornamentSize` 是大小倍数 0.5–1.5，默认 1（约为气泡高的 0.62）。

图片在文字区左右多出的部分，排版时会用字距留出来，不压前后文字；上方多出超过气泡高的 38%、下方超过 60% 时可能压到上下行，编辑器会提示。只有一种模式写了 `image` 或 `ornamentImage` 时，另一种模式也用它。旧版本应用不认这些字段，照旧按 `shape` 等字段画，所以建议同时写一组形状和颜色作为回退，不需要声明 `requires`。

```json
"light": {
  "commentBubble": {
    "shape": "rounded", "fill": "#B98546", "text": "#4A3423",
    "image": "assets/comment_bubble.png",
    "imageText":  { "left": 0.1, "right": 0.1, "top": 0.14, "bottom": 0.3 },
    "imageSlice": { "left": 0.28, "right": 0.22 },
    "ornament": "custom", "ornamentImage": "assets/comment_mark.svg", "ornamentCorner": "topRight"
  }
},
"dark": { "commentBubble": { "image": "assets/comment_bubble_night.png", "text": "#F2DEAE" } }
```

## 素材规范

| 素材 | 格式 | 规格 |
| --- | --- | --- |
| 阅读角饰 `leading` / `trailing` | SVG 或位图 | SVG 用 `viewBox="0 0 480 480"`，位图取正方形，都要透明底；左上角与右下角是同一场景的两幅图，正文区域不要放密集细节。 |
| 阅读整图 `image` | 位图 | 竖屏位图，按 `imageFit` 铺满或包含；浅色与深色各一张。 |
| 朗读面板 `artwork` | SVG 或位图 | 720 × 520，透明底或完整插画；下半部分会渐隐到 `surfaceColor`。 |
| 导航图标 | SVG 或位图 | SVG 用 `viewBox="0 0 24 24"`、单色纯黑填充，应用按主题色着色（选中为强调色）；位图取 96 × 96 透明底，按原色显示在 24 × 24 vp 的位置，选中与否要靠选中态图标区分。旧版本应用只接受 SVG，带位图图标的包在旧版本上无法导入。 |
| 封面 `covers`、`coversDark` | 位图 | 450 × 660，完整插画，不叠加书名或作者。深色那套的亮部要克制。 |
| 书架边框 `shelfFrame`、`shelfFrameDark` | SVG 或位图 | SVG 用 `viewBox="0 0 450 660"`，位图取 450 × 660 透明底；与封面同比例，中心透明，只画外框和角花；按原色显示。 |
| 文件夹插画 `shelfFolder` | 位图 | 450 × 660。 |
| 启动封面 `image` | 位图 | 841 × 1870 竖屏，底部约 1/5 会叠加文案，不放主体。 |
| 首页背景 `homeBackdrop`、书架背景 `shelfBackdrop` | 位图 | 1080 × 1350（4:5），贴顶铺满宽度，比例不同时居中裁成 4:5。画面放在上部约四成，应用会叠渐变向下淡成页面底色；不要放文字，深色图的亮部要克制。 |
| 段评气泡图 `commentBubble.image` | SVG 或位图 | 整只气泡（含尾巴）的透明底横图，位图高 96–160 px 为宜；尾巴画在下方，文字区和拉伸线见上文“气泡图与角标图”。 |
| 段评角标图 `commentBubble.ornamentImage` | SVG 或位图 | 正方形透明底小图，显示约为气泡高的 0.62 倍。 |
| 标题气泡 `titleBubble.frame` / `cap` | SVG 或位图 | 同强调气泡的端饰与边框，按标题字号缩放；边框文字带对齐标题行。 |
| 气泡边框 `frame` / 端饰 `cap` | SVG 或位图 | 端饰为正方形小图（位图要透明底，按原色显示），按字号缩放，右端自动旋转 180°。边框是横向长条，两端是花纹、中间可拉伸，见下文“气泡边框”。 |
| 主题标识 `logo` | SVG 或位图 | SVG 用 `viewBox="0 0 64 64"`，位图取正方形透明底。 |
| 字体 `appFont` | TTF / OTF / TTC | 请确认字体允许再分发。 |

格式一栏只有三类：“位图”指 PNG / JPG / WebP / GIF / BMP，“SVG 或位图”两类都收，字体单列。每个素材位只规定收哪一类，不再细分后缀；应用内和桌面编辑器的选择器按同一规则列后缀。动图（GIF、动态 WebP）在封面、首页与书架背景上会播放，端饰、角饰这类先解码成位图再绘制的位置只取第一帧。

限制：

- SVG 必须自包含：不得出现 `<script>`、`<image>`、`<use>`、`<filter>`、`<foreignObject>`、`href=`、`url(`，单个不超过 5 MB。
- 位图单个不超过 25 MB，字体单个不超过 40 MB，素材总数不超过 64 个，整包不超过 80 MB，解压后不超过 160 MB。
- 文件扩展名必须与实际格式一致（按文件头识别），`jpeg` 按 `jpg` 处理。
- 素材只能放在 `assets/` 一层，文件名 `[A-Za-z0-9][A-Za-z0-9_-]*`。

导入失败时应用会提示具体原因（哪个字段、哪个素材），按提示修改即可。

## 兼容与回退

- 比当前应用新的 `formatVersion`，或 `requires` 里有应用不认识的能力，导入时提示更新应用。
- 没写的部件按 `baseTheme` 显示，所以只带配色的小包也能完整使用。
- 没有 `shelfBackdrop` 的主题包（此前制作的都是这样）四种书架布局都用 `homeBackdrop`。只写 `shelfBackdrop`、不写 `homeBackdrop` 也可以，但旧版本应用上就没有背景，所以通用那张建议始终保留。
- 只有 `covers`、`shelfFrame`、`shelfFolder` 的主题包（此前制作的都是这样）照常使用，浅色、深色显示同一套封面、同一张书架边框和文件夹插画。只写了 `coversDark`、`shelfFrameDark` 或 `shelfFolderDark` 时浅色模式也用它；应用和桌面编辑器导出这种包时会把它写成 `covers`、`shelfFrame`、`shelfFolder`。
- 没有 `bubbleDark` 的主题包两种模式用同一套端饰和边框。只写了 `bubbleDark` 时浅色也用它，导出时写成 `bubble`；`bubbleDark` 里和 `bubble` 相同的项导出时不重复写。
- 没有 `commentBubble` 的主题包，段评气泡跟着强调气泡样式走；带包内气泡的主题包，段评按强调底色推导（此前是中性灰）。
- 带标题强调和标题气泡的包在旧版本应用上照常导入，标题保持原样。
- 带段评气泡图的包在旧版本应用上照常导入，段评按同一节里的 `shape`、颜色画；`ornament: "custom"` 在旧版本上按不写处理。
- 用户在编辑器里把包内部件换成内置主题的部件是允许的；再导出时，包内素材会随新包一起打出去，并在 `credits` 里保留原作者信息。
- 同一个 `packageId` 再次导入时原位更新：用户的阅读排版和强调规则保留并合并，素材和配色换成新版本。
- 方案设置会随云同步到用户的其他设备，素材不会；另一台设备上会提示“主题包素材不在这台设备上”，重新导入同一个包即可恢复。
- 桌面图标由应用编译期声明，主题包提供不了；应用这套方案时沿用“自定义主题”图标。

## 测试

1. 把文件夹压成 ZIP，改名为 `.qytheme`，用文件管理或聊天软件发到手机，用开源轻页打开，或在主题页点“导入”。
2. 导入前的预览会列出包里有哪些部件；确认后在主题详情点“应用主题”。
3. 浅色、深色、跟随系统各检查一次：首页导航图标与首页背景、书架封面、书架边框与分组文件夹、阅读页背景、强调气泡与段评气泡、朗读面板、启动封面。
4. 改动素材后保持 `packageId` 不变再次导入，确认走的是更新。

仓库里 `node --experimental-strip-types scripts/theme-package-check.mjs` 覆盖格式校验的纯逻辑，可以在提交格式改动前运行。
