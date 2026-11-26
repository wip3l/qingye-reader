// 左侧部件与检查器字段的定义，与 theme.json 的 parts 一一对应（见 docs/theme-package-format.md）。
import { BUBBLES, baseThemeOptions } from './tokens.ts';
import {
  COMMENT_BUBBLE_ORNAMENT_NAMES,
  COMMENT_BUBBLE_ORNAMENTS,
  COMMENT_BUBBLE_SHAPE_NAMES,
  COMMENT_BUBBLE_SHAPES
} from '../../../../entry/src/main/ets/theme/share/ThemePackageFormat.ts';
import { getPath, type Mode } from './state.ts';

export interface Field {
  /** 分组标题行。 */
  g?: string;
  /** 字段路径：m. 开头是清单；{m} 换成当前编辑的浅色/深色。 */
  k?: string;
  label?: string;
  type?: 'text' | 'textarea' | 'select' | 'color' | 'range' | 'asset' | 'covers' | 'preserved';
  options?: [string, string][];
  max?: number;
  min?: number;
  /** range：步长（默认 1）、没填时显示的值、清空按钮的字样（默认“沿用”）。 */
  step?: number;
  fallback?: number;
  resetLabel?: string;
  alpha?: boolean;
  hint?: string;
  /** 素材允许的类型：image / vector / font。 */
  kinds?: string[];
  spec?: string;
  /** 位图的目标尺寸：比例不符时提供按它裁剪。 */
  target?: [number, number];
  square?: boolean;
  viewBox?: [number, number];
  /** 对比度参照的底色字段。 */
  /** 对比度参照的颜色路径；可按当前模式的设置换参照。 */
  vs?: string | ((mode: Mode) => string);
  icon?: boolean;
  /** 气泡边框：上传后弹出拉伸区域对话框，格子里多一个“拉伸区域…”按钮和设置概要。 */
  frameStretch?: boolean;
  /** 段评气泡图：上传后弹出文字区与拉伸线对话框，格子里多一个“文字区与拉伸线…”按钮和设置概要。 */
  commentStretch?: boolean;
  when?: (mode: Mode) => boolean;
}

/** 应用“书架布局”的四个选项（键同应用的 bookshelfLayoutMode）；陪伴是新装应用的默认值。预览的布局切换和按布局的书架背景都用它。 */
export const SHELF_LAYOUTS: [string, string][] = [['companion', '陪伴'], ['tile', '平铺'], ['loose', '宽松'], ['compact', '紧凑']];

export interface Section {
  id: string;
  group: string;
  name: string;
  /** 选中时预览切到哪个画面。 */
  screen: string | null;
  /** 字段分浅色、深色。 */
  modal?: boolean;
  desc: string;
  fields: Field[];
}

const mode = (m: Mode, path: string): any => getPath(`${m}.${path}`);
const shelfFull = (): boolean => getPath('shelfBackdropDisplay.mode') === 'full';
// 浅色或深色任一套有端饰或边框，强调就用包内气泡（同应用 bubbleFor）。
const packBubble = (): boolean => !!(getPath('bubble.cap') || getPath('bubble.frame') || getPath('bubbleDark.cap') ||
  getPath('bubbleDark.frame'));
// 角饰模式和整图模式都可以带角饰（整图模式下叠在整图上面）。
const ornamentsAllowed = (m: Mode): boolean => ['ornaments', 'image'].includes(mode(m, 'reader.backgroundMode'));

export const NAV_TABS: [string, string][] = [['bookshelf', '书架'], ['explore', '发现'], ['mine', '我的']];
/** 应用“其他设置 › 底栏”可选的第四个页签，排在“我的”前面；图标可不给，应用用基底主题的。 */
export const EXTRA_NAV_TABS: [string, string][] = [['listen', '听'], ['footprint', '足迹']];
/** 编辑器里列图标格的顺序，和底栏一致。 */
const NAV_ICON_TABS: [string, string][] = [NAV_TABS[0], NAV_TABS[1], ...EXTRA_NAV_TABS, NAV_TABS[2]];

function navIconField(k: string, label: string): Field {
  return { k, label, type: 'asset', kinds: ['vector', 'image'], icon: true, square: true, viewBox: [24, 24], target: [96, 96],
    spec: 'SVG：viewBox 0 0 24 24，单色纯黑；位图：96 × 96 透明底，原色显示' };
}

export const SECTIONS: Section[] = [
  {
    id: 'meta', group: '包', name: '包信息', screen: 'card',
    desc: '写进 manifest.json。requires 由编辑器按内容自动计算。', fields: [
      { g: '基本信息' },
      { k: 'm.name', label: '名称', type: 'text', max: 24, hint: '最多 24 个字符，显示在主题页' },
      { k: 'm.packageId', label: 'packageId', type: 'text', max: 64, hint: '字母、数字与 . - _。同一个 ID 再次导入是原位更新，换 ID 就是另一个主题' },
      { k: 'm.author', label: '作者', type: 'text', max: 24 },
      { k: 'm.version', label: '版本', type: 'text', max: 32 },
      { k: 'm.description', label: '说明', type: 'textarea', max: 120 },
      { g: '回退' },
      { k: 'm.baseTheme', label: '基底主题', type: 'select', options: baseThemeOptions(),
        hint: '包里没写的部件沿用它。选付费主题时，导入的人没有这套主题，这些部件会按默认主题显示。预览只显示基底的配色，它的图片在应用里才看得到' },
      { g: '随包保留的方案内容' },
      { type: 'preserved' }
    ]
  },
  {
    id: 'colors', group: '配色与阅读', name: '界面配色', screen: 'shelf', modal: true,
    desc: '书架、发现、我的等界面的配色。留空沿用基底主题。', fields: [
      { g: '底色' },
      { k: '{m}.colors.pageColor', label: '页面', type: 'color' },
      { k: '{m}.colors.cardColor', label: '卡片', type: 'color' },
      { k: '{m}.colors.inputColor', label: '输入框', type: 'color' },
      { k: '{m}.colors.dividerColor', label: '分割线', type: 'color' },
      { g: '文字' },
      { k: '{m}.colors.primaryTextColor', label: '主文字', type: 'color', vs: '{m}.colors.pageColor' },
      { k: '{m}.colors.subTextColor', label: '副文字', type: 'color', vs: '{m}.colors.pageColor' },
      { g: '强调' },
      { k: '{m}.colors.accentColor', label: '强调色', type: 'color' },
      { k: '{m}.colors.buttonColor', label: '按钮', type: 'color' },
      { k: '{m}.colors.dangerColor', label: '危险', type: 'color' }
    ]
  },
  {
    id: 'reader', group: '配色与阅读', name: '阅读页', screen: 'reader', modal: true,
    desc: '阅读配色选“应用主题”时生效。底色必须能铺满任意尺寸的屏幕。', fields: [
      { g: '颜色' },
      { k: '{m}.reader.backgroundColor', label: '阅读底色', type: 'color' },
      { k: '{m}.reader.textColor', label: '正文', type: 'color', vs: '{m}.reader.backgroundColor' },
      { k: '{m}.reader.subTextColor', label: '页眉页脚', type: 'color', vs: '{m}.reader.backgroundColor' },
      { k: '{m}.reader.contentTone', label: '内容明暗', type: 'select',
        options: [['', '沿用基底'], ['light', '浅（系统栏用深色图标）'], ['dark', '深（系统栏用浅色图标）']] },
      { g: '背景' },
      { k: '{m}.reader.backgroundMode', label: '背景方式', type: 'select',
        options: [['', '沿用基底'], ['ornaments', '角饰'], ['image', '整图'], ['none', '只有底色']] },
      { k: '{m}.reader.leading', label: '左上角饰', type: 'asset', kinds: ['vector', 'image'], square: true, target: [480, 480],
        viewBox: [480, 480], spec: 'SVG（viewBox 0 0 480 480）或正方形透明底位图；可只传左上或右下一角', when: (m) => ornamentsAllowed(m) },
      { k: '{m}.reader.trailing', label: '右下角饰', type: 'asset', kinds: ['vector', 'image'], square: true, target: [480, 480],
        viewBox: [480, 480], spec: '与左上角同一场景的另一幅图；选和左上角同一张素材时旋转 180° 显示', when: (m) => ornamentsAllowed(m) },
      { k: '{m}.reader.leadingScale', label: '左上角饰大小', type: 'range', min: 0.5, max: 2, step: 0.1, fallback: 1, resetLabel: '默认',
        hint: '相对默认尺寸（屏幕短边 × 0.36，夹在 112–260vp）的倍数；最大不超过短边的 0.8',
        when: (m) => ornamentsAllowed(m) },
      { k: '{m}.reader.leadingInset', label: '左上角饰边距', type: 'range', min: 0, max: 3, step: 0.1, fallback: 1, resetLabel: '默认',
        hint: '相对默认边距（屏幕短边 × 0.025，夹在 8–22vp）的倍数；0 是贴着屏幕边缘。旧版本应用忽略，按默认边距显示',
        when: (m) => ornamentsAllowed(m) },
      { k: '{m}.reader.trailingScale', label: '右下角饰大小', type: 'range', min: 0.5, max: 2, step: 0.1, fallback: 1, resetLabel: '默认',
        when: (m) => ornamentsAllowed(m) },
      { k: '{m}.reader.trailingInset', label: '右下角饰边距', type: 'range', min: 0, max: 3, step: 0.1, fallback: 1, resetLabel: '默认',
        when: (m) => ornamentsAllowed(m) },
      { k: '{m}.reader.image', label: '整图', type: 'asset', kinds: ['image'], spec: '竖屏位图 PNG / JPG / WebP',
        when: (m) => mode(m, 'reader.backgroundMode') === 'image' },
      { k: '{m}.reader.imageFit', label: '铺放', type: 'select', options: [['cover', '铺满裁切'], ['contain', '完整包含'], ['fill', '拉伸']],
        when: (m) => mode(m, 'reader.backgroundMode') === 'image' }
    ]
  },
  {
    id: 'emphasis', group: '配色与阅读', name: '正文强调', screen: 'reader', modal: true,
    desc: '强调规则“跟随主题”时用的样式。预览里引号内的对话套用它。', fields: [
      { g: '样式' },
      { k: '{m}.emphasis.mode', label: '强调方式', type: 'select',
        options: [['', '沿用基底'], ['none', '无'], ['text', '仅文字色'], ['highlight', '高亮底色'], ['bubble', '气泡']] },
      { k: '{m}.emphasis.bubbleStyle', label: '气泡样式', type: 'select',
        options: [['', '沿用基底'], ...BUBBLES.map((b) => [b.id, b.label] as [string, string])],
        hint: '主题专属气泡要导入的人拥有那套主题才能用，否则应用换成通用样式',
        when: (m) => !packBubble() },
      { k: '{m}.emphasis.color', label: '底色', type: 'color', alpha: true,
        hint: '底色和文字色可带透明度，写成 #AARRGGBB（透明度在前）。网页和设计软件常用的 #RRGGBBAA 要把末两位挪到最前，例如 #9EC0D9B6 → #B69EC0D9' },
      { k: '{m}.emphasis.textColor', label: '文字色', type: 'color', alpha: true },
      { g: '包内气泡 · 浅色' },
      { k: 'bubble.cap', label: '端饰', type: 'asset', kinds: ['vector', 'image'], square: true, spec: '正方形小图，SVG 或透明底位图，按字号缩放，右端自动旋转 180°',
        hint: '端饰用位图时（深色那张也算），旧版本应用会提示先更新' },
      { k: 'bubble.frame', label: '边框', type: 'asset', kinds: ['vector', 'image'], frameStretch: true,
        spec: '可选，SVG 或透明底 PNG / WebP，按行拉伸；只有边框时不画端饰' },
      { g: '包内气泡 · 深色（可选）' },
      { k: 'bubbleDark.cap', label: '端饰', type: 'asset', kinds: ['vector', 'image'], square: true, spec: '空着时深色沿用浅色那张' },
      { k: 'bubbleDark.frame', label: '边框', type: 'asset', kinds: ['vector', 'image'], frameStretch: true,
        spec: '空着时深色沿用浅色那张（连同拉伸设置）',
        hint: '单色边框打开“染成气泡底色”就会跟着两种模式的底色变，可以不画第二张。只给了深色时两种模式都用它。旧版本应用只认浅色那套' },
      { g: '段评气泡' },
      { k: '{m}.commentBubble.image', label: '气泡图', type: 'asset', kinds: ['vector', 'image'], commentStretch: true,
        spec: '整只气泡（含尾巴）的透明底横图，位图高 96–160 px 为宜；上传后调文字区和拉伸线',
        hint: '写了气泡图时形状、圆角、描边不生效，底色只在染色时用；下面的形状和颜色留给旧版本应用回退。深色空着时沿用浅色那张' },
      { k: '{m}.commentBubble.shape', label: '形状', type: 'select',
        options: [['', '跟随气泡样式'], ...COMMENT_BUBBLE_SHAPES.map((id, i) => [id, COMMENT_BUBBLE_SHAPE_NAMES[i]] as [string, string])],
        hint: '段评与本章说的气泡。描边是透明底、颜色跟正文墨色；书源设置了段评颜色时以书源为准。旧版本应用忽略这一组' },
      { k: '{m}.commentBubble.radius', label: '圆角', type: 'range', min: 0, max: 0.5, step: 0.01, fallback: 0.2, resetLabel: '默认',
        hint: '占气泡高的比例，0.5 是全圆', when: (m) => mode(m, 'commentBubble.shape') === 'rounded' },
      { k: '{m}.commentBubble.fill', label: '底色', type: 'color', alpha: true, when: (m) => mode(m, 'commentBubble.shape') !== 'outline' },
      { k: '{m}.commentBubble.stroke', label: '描边', type: 'color', alpha: true },
      { k: '{m}.commentBubble.text', label: '文字色', type: 'color', alpha: true, vs: '{m}.commentBubble.fill' },
      { k: '{m}.commentBubble.ornament', label: '角标', type: 'select',
        options: [['', '跟随气泡样式'], ...COMMENT_BUBBLE_ORNAMENTS.map((id, i) => [id, COMMENT_BUBBLE_ORNAMENT_NAMES[i]] as [string, string])],
        hint: '应用内置的小图形（预览里用近似的符号示意），或选“自定义图片”传一张。旧版本应用把“自定义图片”当成跟随' },
      { k: '{m}.commentBubble.ornamentImage', label: '角标图', type: 'asset', kinds: ['vector', 'image'], square: true,
        spec: '正方形透明底小图，显示约为气泡高的 0.62 倍；深色空着时沿用浅色那张',
        when: (m) => mode(m, 'commentBubble.ornament') === 'custom' },
      { k: '{m}.commentBubble.ornamentCorner', label: '角标位置', type: 'select',
        options: [['', '右上'], ['topLeft', '左上'], ['bottomRight', '右下']],
        when: (m) => mode(m, 'commentBubble.ornament') === 'custom' },
      { k: '{m}.commentBubble.ornamentSize', label: '角标大小', type: 'range', min: 0.5, max: 1.5, step: 0.05, fallback: 1,
        resetLabel: '默认', when: (m) => mode(m, 'commentBubble.ornament') === 'custom' },
      { k: '{m}.commentBubble.ornamentColor', label: '角标颜色', type: 'color', alpha: true,
        hint: '自定义图片：写了颜色时整张染成这个颜色，不写按原色',
        when: (m) => !!mode(m, 'commentBubble.ornament') && mode(m, 'commentBubble.ornament') !== 'none' }
    ]
  },
  {
    id: 'title', group: '配色与阅读', name: '标题强调', screen: 'reader', modal: true,
    desc: '章节标题的强调。读者在阅读设置里把标题强调选为“跟随主题”（新装默认）时用它；不设置时标题保持原样。旧版本应用忽略这一节。', fields: [
      { g: '样式' },
      { k: '{m}.titleEmphasis.mode', label: '强调方式', type: 'select',
        options: [['', '不设置'], ['none', '无'], ['text', '仅文字色'], ['highlight', '高亮底色'], ['bubble', '气泡']],
        hint: '不设置时主题不管标题；“无”表示主题明确不给标题加强调' },
      { k: '{m}.titleEmphasis.bubbleStyle', label: '气泡样式', type: 'select',
        options: [['', '自动（有标题气泡用它，否则同强调气泡）'], ['emphasis', '同强调气泡'], ...BUBBLES.map((b) => [b.id, b.label] as [string, string])],
        hint: '同强调气泡：和正文强调用同一套样式与素材。主题专属气泡要导入的人拥有那套主题才能用',
        when: (m) => mode(m, 'titleEmphasis.mode') === 'bubble' },
      { k: '{m}.titleEmphasis.color', label: '底色', type: 'color', alpha: true,
        hint: '不写时用正文强调的底色',
        when: (m) => ['highlight', 'bubble'].includes(mode(m, 'titleEmphasis.mode')) },
      { k: '{m}.titleEmphasis.textColor', label: '文字色', type: 'color', alpha: true,
        vs: (m) => mode(m, 'titleEmphasis.mode') === 'text' ? '{m}.reader.backgroundColor' : '{m}.titleEmphasis.color',
        hint: '仅文字色：不写时用正文强调的文字色，它在阅读底上看不清时退回正文强调的底色',
        when: (m) => ['text', 'highlight', 'bubble'].includes(mode(m, 'titleEmphasis.mode')) },
      { g: '标题气泡 · 浅色' },
      { k: 'titleBubble.cap', label: '端饰', type: 'asset', kinds: ['vector', 'image'], square: true,
        spec: '正方形小图，SVG 或透明底位图，按标题字号缩放，右端自动旋转 180°' },
      { k: 'titleBubble.frame', label: '边框', type: 'asset', kinds: ['vector', 'image'], frameStretch: true,
        spec: '可选，SVG 或透明底 PNG / WebP，按行拉伸；只有边框时不画端饰',
        hint: '传了标题气泡、气泡样式选“自动”时标题用它' },
      { g: '标题气泡 · 深色（可选）' },
      { k: 'titleBubbleDark.cap', label: '端饰', type: 'asset', kinds: ['vector', 'image'], square: true, spec: '空着时深色沿用浅色那张' },
      { k: 'titleBubbleDark.frame', label: '边框', type: 'asset', kinds: ['vector', 'image'], frameStretch: true,
        spec: '空着时深色沿用浅色那张（连同拉伸设置）' }
    ]
  },
  {
    id: 'chapterHead', group: '配色与阅读', name: '章首装饰', screen: 'reader', modal: true,
    desc: '画在每章标题旁的饰图、分段标题第一段（“第十二章”那一行）的颜色，和首字装饰。读者可以在阅读设置的标题里关掉。旧版本应用忽略这一节。', fields: [
      { g: '标题饰图' },
      { k: '{m}.chapterHead.image', label: '饰图', type: 'asset', kinds: ['vector', 'image'],
        spec: 'SVG 或透明底位图。放左侧适合竖长的图，放上方、下方适合横长的花纹',
        hint: '深色空着时沿用浅色那张（连同位置和大小）' },
      { k: '{m}.chapterHead.placement', label: '位置', type: 'select',
        options: [['', '标题左侧'], ['top', '标题上方'], ['bottom', '标题下方']],
        hint: '左侧：贴版心左边、上下对齐整组标题，标题在剩下的宽度里按读者的对齐方式排。上方、下方：单独占一行，跟着标题的对齐方式',
        when: (m) => !!mode(m, 'chapterHead.image') },
      { k: '{m}.chapterHead.scale', label: '大小', type: 'range', min: 0.5, max: 10, step: 0.1, fallback: 1, resetLabel: '默认',
        hint: '左侧时 1 表示和整组标题一样高（最宽占版心的 30%）；上方、下方时 1 表示约一个标题字高',
        when: (m) => !!mode(m, 'chapterHead.image') },
      { g: '序号行' },
      { k: '{m}.chapterHead.numberColor', label: '序号行颜色', type: 'color', alpha: true, vs: '{m}.reader.backgroundColor',
        hint: '不写时和标题同色。读者开了标题分段才看得出' },
      { g: '首字装饰' },
      { k: '{m}.chapterHead.dropCapLines', label: '首字', type: 'select',
        options: [['', '不处理'], ['2', '占 2 行'], ['3', '占 3 行'], ['4', '占 4 行']],
        hint: '每章第一段的第一个字放大。开头是引号、数字、字母时这一章不处理。深色不处理时沿用浅色那套' },
      { k: '{m}.chapterHead.dropCapStyle', label: '首字样式', type: 'select',
        options: [['', '下沉'], ['raise', '放大']],
        hint: '下沉：前几行绕开首字。放大：首字一样高，但底边对齐第一行、向上抬出，只有第一行绕排。旧版本应用按下沉显示',
        when: (m) => !!mode(m, 'chapterHead.dropCapLines') },
      { k: '{m}.chapterHead.dropCapImage', label: '印章图', type: 'asset', kinds: ['vector', 'image'], square: true,
        spec: '垫在首字底下，字画在正中：正方形、中间留空的 SVG 或透明底位图。不传就只把字放大',
        when: (m) => !!mode(m, 'chapterHead.dropCapLines') },
      { k: '{m}.chapterHead.dropCapColor', label: '首字颜色', type: 'color', alpha: true, vs: '{m}.reader.backgroundColor',
        hint: '不写时和正文同色', when: (m) => !!mode(m, 'chapterHead.dropCapLines') },
      { k: '{m}.chapterHead.dropCapRatio', label: '字在印章里的大小', type: 'range', min: 0.4, max: 0.9, step: 0.02, fallback: 0.62,
        resetLabel: '默认', hint: '字高占印章边长的比例', when: (m) => !!mode(m, 'chapterHead.dropCapImage') }
    ]
  },
  {
    id: 'nav', group: '素材', name: '导航图标', screen: 'shelf',
    desc: '首页底栏。书架、发现、我的三个普通图标要么都给，要么都不给；“听”“足迹”是可选的第四个页签，可以不给（应用用基底主题的图标），旧版本应用会忽略。SVG 按主题色着色，位图（PNG / WebP）保持原色。选中态可选，没给的页签选中时仍用普通图标。', fields: [
      { g: '普通图标' },
      ...NAV_ICON_TABS.map(([key, label]): Field => navIconField(`navigation.${key}`, label)),
      { g: '选中态（可选）' },
      ...NAV_ICON_TABS.map(([key, label]): Field => navIconField(`navigation.${key}Selected`, label)),
      { g: '底栏' },
      { k: 'navigation.labels', label: '文字', type: 'select', options: [['', '图标下显示文字'], ['hidden', '只显示图标']],
        hint: '只显示图标时，图标本身要能认出是哪个页签' },
      { g: '深色图标（可选）' },
      ...NAV_ICON_TABS.map(([key, label]): Field => ({ ...navIconField(`navigationDark.${key}`, label),
        spec: '空着时深色沿用上面那张。SVG 会按主题色着色，一般不用另给；彩色位图在深色底栏上太亮时再给' })),
      { g: '深色选中态（可选）' },
      ...NAV_ICON_TABS.map(([key, label]): Field => ({ ...navIconField(`navigationDark.${key}Selected`, label),
        spec: '给了深色普通图标却没给这张时，选中也用深色普通图标',
        hint: key === 'mine' ? '旧版本应用只认上面那套' : undefined }))
    ]
  },
  {
    id: 'book', group: '素材', name: '书籍素材', screen: 'shelf',
    desc: '书架按书轮播封面。封面是完整插画，不叠书名和作者。深色模式可以单独给一套封面、书架边框和文件夹插画，不给就两种模式都用默认的。', fields: [
      { g: '封面（最多 16 张，450 × 660）' },
      { k: 'book.covers', type: 'covers', target: [450, 660] },
      { g: '深色封面（可选，最多 16 张）' },
      { k: 'book.coversDark', type: 'covers', target: [450, 660],
        hint: '空着时深色模式沿用上面那套。和上面张数相同、顺序对应时，同一本书切换深浅色还是同一幅画。旧版本应用只认上面那套；上面那套超过 8 张时，旧版本应用会提示先更新' },
      { g: '书架' },
      { k: 'book.shelfFrame', label: '书架边框', type: 'asset', kinds: ['vector', 'image'], viewBox: [450, 660], target: [450, 660], spec: 'SVG 或透明底位图，与封面同比例，中心透明',
        hint: '边框用位图时（深色那张也算），旧版本应用会提示先更新' },
      { k: 'book.shelfFrameDark', label: '书架边框 · 深色（可选）', type: 'asset', kinds: ['vector', 'image'], viewBox: [450, 660], target: [450, 660], spec: 'SVG 或透明底位图，与封面同比例，中心透明',
        hint: '边框按原色显示，深色描边在深色书架上看不见时再给这张；空着时深色沿用上面那张。旧版本应用只认上面那张' },
      { k: 'book.shelfFolder', label: '分组文件夹', type: 'asset', kinds: ['image'], target: [450, 660], spec: '450 × 660 位图' },
      { k: 'book.shelfFolderDark', label: '分组文件夹 · 深色（可选）', type: 'asset', kinds: ['image'], target: [450, 660], spec: '450 × 660 位图',
        hint: '空着时深色模式沿用上面那张。旧版本应用只认上面那张' }
    ]
  },
  {
    id: 'startup', group: '素材', name: '启动封面', screen: 'startup', modal: true,
    desc: '只做一种模式时，另一种模式沿用它。底部约 1/5 会叠文案，别放主体。', fields: [
      { g: '封面' },
      { k: 'startup.{m}.image', label: '竖图', type: 'asset', kinds: ['image'], target: [841, 1870], spec: '841 × 1870 JPG / PNG，也可以用 GIF / 动态 WebP',
        hint: '动图在启动页播完一遍再进首页（最长 8 秒），不超过 25 MB；关掉“播放动图”时只显示第一帧' },
      { k: 'startup.{m}.title', label: '标题', type: 'text', max: 40, hint: '留空时启动页不显示标题' },
      { k: 'startup.{m}.subtitle', label: '副标题', type: 'text', max: 40 }
    ]
  },
  {
    id: 'shelfBackdrop', group: '素材', name: '书架背景', screen: 'shelf', modal: true,
    desc: '只在书架页显示，四种布局和分组页共用；发现、我的页用“页签顶部背景”。没做时书架也用页签顶部那张。浅色、深色各做一张，互不借用。', fields: [
      { g: '背景图' },
      { k: 'shelfBackdrop.all.{m}', label: '书架背景', type: 'asset', kinds: ['image'], target: [1080, 1350],
        spec: '顶部淡出用 1080 × 1350（4:5），画面放在上半部分；全屏用竖图（约 9 : 20）',
        hint: '旧版本应用不认这一张，书架照旧显示页签顶部背景' },
      { g: '显示方式' },
      { k: 'shelfBackdropDisplay.mode', label: '显示方式', type: 'select', options: [['', '顶部淡出'], ['full', '全屏']],
        hint: '全屏时书架页铺满整屏，按布局单独配的图也这样显示；发现、我的页仍只衬顶部。旧版本应用照旧铺在顶部' },
      { k: 'shelfBackdropDisplay.fit', label: '图片显示', type: 'select', when: shelfFull,
        options: [['cover', '裁切铺满'], ['contain', '完整显示'], ['fill', '拉伸铺满'], ['tile', '平铺']] },
      { k: 'shelfBackdropDisplay.position', label: '取景', type: 'range', min: 0, max: 100, fallback: 50, resetLabel: '居中',
        when: () => shelfFull() && !['contain', 'fill', 'tile'].includes(getPath('shelfBackdropDisplay.fit')),
        hint: '沿被裁掉的那条轴取景：图比屏幕瘦是上→下，比屏幕胖是左→右' },
      { k: 'shelfBackdropDisplay.gap', label: '空白处', type: 'select', options: [['blur', '模糊延展'], ['color', '主题底色']],
        when: () => shelfFull() && getPath('shelfBackdropDisplay.fit') === 'contain' },
      { k: 'shelfBackdropDisplay.lightWash', label: '淡化', type: 'range', min: 0, max: 80, fallback: 30, resetLabel: '默认',
        when: (m: Mode) => shelfFull() && m === 'light', hint: '盖一层页面底色（百分比），书名更清楚；浅色、深色分开调' },
      { k: 'shelfBackdropDisplay.darkWash', label: '淡化', type: 'range', min: 0, max: 80, fallback: 45, resetLabel: '默认',
        when: (m: Mode) => shelfFull() && m === 'dark', hint: '盖一层页面底色（百分比），书名更清楚；浅色、深色分开调' },
      { k: 'shelfBackdropDisplay.blur', label: '模糊', type: 'range', min: 0, max: 20, fallback: 0, resetLabel: '不模糊',
        when: shelfFull },
      { g: '按书架布局单独换（可选）' },
      ...SHELF_LAYOUTS.map(([key, label]): Field => ({
        k: `shelfBackdrop.${key}.{m}`, label, type: 'asset', kinds: ['image'], target: [1080, 1350],
        spec: '空着时沿用上面的书架背景',
        hint: key === 'compact' ? '只在书架用这种布局时显示' : undefined
      }))
    ]
  },
  {
    id: 'homeBackdrop', group: '素材', name: '页签顶部背景', screen: 'explore', modal: true,
    desc: '发现和我的页顶部的背景，不随列表滚动，向下自动淡成页面底色；没做书架背景时书架也用这张。浅色、深色各做一张；只做一种时另一种模式不显示背景。', fields: [
      { g: '背景图' },
      { k: 'homeBackdrop.{m}', label: '背景图', type: 'asset', kinds: ['image'], target: [1080, 1350],
        spec: '1080 × 1350（4:5），画面放在上半部分；比例不同时居中裁成 4:5' }
    ]
  },
  {
    id: 'tts', group: '素材', name: '朗读面板', screen: 'tts', modal: true,
    desc: '朗读与有声书面板的背景。四项都要填；只做一种模式时，另一种模式沿用它。', fields: [
      { g: '插画' },
      { k: 'ttsPanel.{m}.artwork', label: '插画', type: 'asset', kinds: ['vector', 'image'], target: [720, 520], viewBox: [720, 520],
        spec: '720 × 520，贴顶等比缩放，下半部分渐隐到面板底色' },
      { g: '颜色' },
      { k: 'ttsPanel.{m}.skyColor', label: '天空色', type: 'color', hint: '插画背后的渐变起点' },
      { k: 'ttsPanel.{m}.surfaceColor', label: '面板底色', type: 'color', hint: '不透明；接近页面色，保证文字对比度' },
      { k: 'ttsPanel.{m}.glowColor', label: '柔光', type: 'color', alpha: true, hint: '播放区的强调光，带透明度：#AARRGGBB，透明度在前（不是网页常用的 #RRGGBBAA）' }
    ]
  },
  {
    id: 'shape', group: '形状与品牌', name: '圆角与字体', screen: 'shelf',
    desc: '圆角 0 到 48，浅深共用。', fields: [
      { g: '圆角' },
      ...(['small', 'medium', 'large', 'card', 'button', 'bubble'] as const).map((key): Field => ({
        k: `radius.${key}`, label: { small: '小', medium: '中', large: '大', card: '卡片', button: '按钮', bubble: '气泡' }[key],
        type: 'range', min: 0, max: 48
      })),
      { g: '界面字体' },
      { k: 'typography.appFont', label: '字体文件', type: 'asset', kinds: ['font'], spec: 'TTF / OTF / TTC，请确认字体允许再分发' },
      { k: 'typography.appFontFamily', label: '系统字体族', type: 'text', max: 120, hint: '没有字体文件时可只填族名，例如 serif' }
    ]
  },
  {
    id: 'brand', group: '形状与品牌', name: '标识与预览图', screen: 'card',
    desc: '主题卡片的角标与预览图。没有预览图时卡片显示启动封面。', fields: [
      { g: '卡片' },
      { k: 'logo', label: '主题标识', type: 'asset', kinds: ['vector', 'image'], square: true, viewBox: [64, 64], spec: 'SVG，viewBox 0 0 64 64' },
      { k: 'preview', label: '预览图', type: 'asset', kinds: ['image'], spec: '位图，竖版 3:4 左右' }
    ]
  },
  {
    id: 'assets', group: '包', name: '素材库', screen: null,
    desc: '工程里的全部素材。没被任何部件引用的素材导出时不会打进包。', fields: []
  }
];

export const SCREENS: [string, string][] = [['shelf', '书架'], ['explore', '发现'], ['mine', '我的'],
  ['reader', '阅读'], ['tts', '朗读'], ['startup', '启动'], ['card', '主题卡片']];
/** 预览底栏的第四个页签，与应用“其他设置 › 底栏”的三个值一致。 */
export const EXTRA_TAB_CHOICES: [string, string][] = [['none', '三页签'], ...EXTRA_NAV_TABS];

export function section(id: string): Section {
  return SECTIONS.find((s) => s.id === id) || SECTIONS[0];
}

/** 从字段路径反查它属于哪个部件。 */
export function sectionOfPath(path: string): string {
  for (const s of SECTIONS) {
    for (const f of s.fields) {
      if (!f.k) continue;
      if (f.k === path || f.k.replace('{m}', 'light') === path || f.k.replace('{m}', 'dark') === path) return s.id;
    }
  }
  return 'assets';
}

/** 各个素材槽位，用于“素材库”里列出谁引用了它。 */
export function assetFields(): { field: Field; section: Section }[] {
  const out: { field: Field; section: Section }[] = [];
  for (const s of SECTIONS) for (const f of s.fields) if (f.type === 'asset' || f.type === 'covers') out.push({ field: f, section: s });
  return out;
}
