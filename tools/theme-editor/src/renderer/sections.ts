// 左侧部件与检查器字段的定义，与 theme.json 的 parts 一一对应（见 docs/theme-package-format.md）。
import { BUBBLES, baseThemeOptions } from './tokens.ts';
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
  vs?: string;
  icon?: boolean;
  when?: (mode: Mode) => boolean;
}

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
        viewBox: [480, 480], spec: 'SVG（viewBox 0 0 480 480）或正方形透明底位图', when: (m) => mode(m, 'reader.backgroundMode') === 'ornaments' },
      { k: '{m}.reader.trailing', label: '右下角饰', type: 'asset', kinds: ['vector', 'image'], square: true, target: [480, 480],
        viewBox: [480, 480], spec: '与左上角同一场景的另一幅图，别直接镜像', when: (m) => mode(m, 'reader.backgroundMode') === 'ornaments' },
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
        when: (m) => !getPath('bubble.cap') },
      { k: '{m}.emphasis.color', label: '底色', type: 'color', alpha: true },
      { k: '{m}.emphasis.textColor', label: '文字色', type: 'color', alpha: true },
      { g: '包内气泡（浅深共用）' },
      { k: 'bubble.cap', label: '端饰', type: 'asset', kinds: ['vector'], square: true, spec: '正方形小 SVG，按字号缩放，右端自动旋转 180°' },
      { k: 'bubble.frame', label: '边框', type: 'asset', kinds: ['vector'], spec: '可选，SVG' }
    ]
  },
  {
    id: 'nav', group: '素材', name: '导航图标', screen: 'shelf',
    desc: '四个要么都给，要么都不给。单色纯黑填充的 SVG，应用按主题色着色。', fields: [
      { g: 'SVG，viewBox 0 0 24 24' },
      { k: 'navigation.bookshelf', label: '书架', type: 'asset', kinds: ['vector'], icon: true, viewBox: [24, 24], spec: '单色纯黑' },
      { k: 'navigation.explore', label: '发现', type: 'asset', kinds: ['vector'], icon: true, viewBox: [24, 24], spec: '单色纯黑' },
      { k: 'navigation.search', label: '搜索', type: 'asset', kinds: ['vector'], icon: true, viewBox: [24, 24], spec: '单色纯黑' },
      { k: 'navigation.mine', label: '我的', type: 'asset', kinds: ['vector'], icon: true, viewBox: [24, 24], spec: '单色纯黑' }
    ]
  },
  {
    id: 'book', group: '素材', name: '书籍素材', screen: 'shelf',
    desc: '书架按书轮播封面。封面是完整插画，不叠书名和作者。', fields: [
      { g: '封面（最多 8 张，450 × 660）' },
      { k: 'book.covers', type: 'covers', target: [450, 660] },
      { g: '书架' },
      { k: 'book.shelfFrame', label: '书架边框', type: 'asset', kinds: ['vector'], viewBox: [450, 660], spec: 'SVG，与封面同比例，中心透明' },
      { k: 'book.shelfFolder', label: '分组文件夹', type: 'asset', kinds: ['image'], target: [450, 660], spec: '450 × 660 位图' }
    ]
  },
  {
    id: 'startup', group: '素材', name: '启动封面', screen: 'startup', modal: true,
    desc: '只做一种模式时，另一种模式沿用它。底部约 1/5 会叠文案，别放主体。', fields: [
      { g: '封面' },
      { k: 'startup.{m}.image', label: '竖图', type: 'asset', kinds: ['image'], target: [841, 1870], spec: '841 × 1870 JPG / PNG' },
      { k: 'startup.{m}.title', label: '标题', type: 'text', max: 40, hint: '留空时启动页不显示标题' },
      { k: 'startup.{m}.subtitle', label: '副标题', type: 'text', max: 40 }
    ]
  },
  {
    id: 'homeBackdrop', group: '素材', name: '首页背景', screen: 'shelf', modal: true,
    desc: '书架、发现、搜索和我的页顶部的背景，不随列表滚动，向下自动淡成页面底色。浅色、深色各做一张；只做一种时另一种模式不显示背景。', fields: [
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
      { k: 'ttsPanel.{m}.glowColor', label: '柔光', type: 'color', alpha: true, hint: '播放区的强调光，带透明度' }
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

export const SCREENS: [string, string][] = [['shelf', '书架'], ['reader', '阅读'], ['tts', '朗读'], ['startup', '启动'], ['card', '主题卡片']];

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
