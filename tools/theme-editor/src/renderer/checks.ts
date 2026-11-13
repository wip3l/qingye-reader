// 编辑中的问题：先做编辑器自己的检查（能精确指到字段），没有错误时再把整包交给应用格式层严格校验。
import { buildFiles, formatSize, usedAssetPaths, verifyFiles } from '../core/packageIo.ts';
import { getPath, mp, project, type Mode } from './state.ts';
import { assetFields, SECTIONS, sectionOfPath, type Field } from './sections.ts';
import { contrast, isColor } from './colors.ts';
import { BASE_EXCLUDED, effective, themeName, THEMES, ttsComplete } from './tokens.ts';

export interface Issue {
  level: 'error' | 'warn';
  section: string;
  text: string;
  /** 跳转并聚焦的字段路径（已展开浅深）。 */
  focus: string | null;
}

const MODES: Mode[] = ['light', 'dark'];
const LABEL: Record<Mode, string> = { light: '浅色', dark: '深色' };
const PACKAGE_ID = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/;

/** 位图或 SVG 尺寸与部件规格不符时的提示；没有问题返回空串。 */
export function sizeWarning(field: Field, asset: { kind: string; width: number; height: number }): string {
  if (!asset.width || !asset.height) return '';
  if (asset.kind === 'vector') {
    if (field.viewBox && (asset.width !== field.viewBox[0] || asset.height !== field.viewBox[1])) {
      if (field.icon || field.square) return `viewBox 应为 0 0 ${field.viewBox[0]} ${field.viewBox[1]}`;
      if (Math.abs(asset.width / asset.height - field.viewBox[0] / field.viewBox[1]) > 0.02) return `比例应为 ${field.viewBox[0]}:${field.viewBox[1]}`;
    }
    return '';
  }
  if (field.square && Math.abs(asset.width - asset.height) > 2) return '应为正方形';
  if (field.icon && field.target && asset.width < field.target[0] * 0.75) {
    return `小于 ${field.target[0]} × ${field.target[1]}，高分屏上会发虚`;
  }
  if (field.target && Math.abs(asset.width / asset.height - field.target[0] / field.target[1]) > 0.02) {
    return `比例不是 ${field.target[0]}:${field.target[1]}，会被裁切`;
  }
  return '';
}

export function editorIssues(): Issue[] {
  const p = project();
  const out: Issue[] = [];
  const add = (level: Issue['level'], focus: string | null, text: string, section?: string): void => {
    out.push({ level, section: section || (focus ? sectionOfPath(focus) : 'assets'), text, focus });
  };
  const m = p.manifest;
  if (!m.name.trim()) add('error', 'm.name', '还没有主题名称');
  if (!PACKAGE_ID.test(m.packageId) || m.packageId.includes('..')) add('error', 'm.packageId', 'packageId 只能用字母、数字、点、连字符和下划线，且以字母或数字开头');
  if (!THEMES.some((t) => t.id === m.baseTheme)) add('warn', 'm.baseTheme', `基底主题 ${m.baseTheme} 不是内置主题，预览按默认主题显示`);
  else if (BASE_EXCLUDED.includes(m.baseTheme)) add('warn', 'm.baseTheme', `「${themeName(m.baseTheme)}」不能作基底，没拥有它的人导入时会换成默认主题，请改选别的基底`);

  for (const s of SECTIONS) {
    for (const f of s.fields) {
      if (f.type !== 'color' || !f.k) continue;
      const modes: (Mode | null)[] = f.k.includes('{m}') ? MODES : [null];
      for (const mode of modes) {
        const path = mode ? mp(f.k, mode) : f.k;
        const value = getPath(path);
        if (value && !isColor(value, !!f.alpha)) {
          add('error', path, `${mode ? LABEL[mode] : ''}${s.name}·${f.label}：“${value}” 不是合法颜色（${f.alpha ? '#RRGGBB 或 #AARRGGBB' : '#RRGGBB'}）`);
        }
      }
    }
  }

  for (const mode of MODES) {
    const L = LABEL[mode];
    const reader = (p.parts[mode] && p.parts[mode].reader) || {};
    if (reader.backgroundMode === 'ornaments' && (!reader.leading || !reader.trailing)) {
      add('error', `${mode}.reader.${reader.leading ? 'trailing' : 'leading'}`, `${L}阅读页：角饰模式要左上和右下两张图`);
    }
    if (reader.backgroundMode === 'image' && !reader.image) add('error', `${mode}.reader.image`, `${L}阅读页：整图模式需要一张图`);
    const e = effective(mode);
    if (isColor(e.reader.textColor, false) && isColor(e.reader.backgroundColor, false)) {
      const ratio = contrast(e.reader.textColor, e.reader.backgroundColor);
      if (ratio < 4.5) add('warn', `${mode}.reader.textColor`, `${L}正文与阅读底色对比度 ${ratio.toFixed(1)}，低于 4.5`);
    }
    if (isColor(e.c.primaryTextColor, false) && isColor(e.c.pageColor, false)) {
      const ratio = contrast(e.c.primaryTextColor, e.c.pageColor);
      if (ratio < 4.5) add('warn', `${mode}.colors.primaryTextColor`, `${L}主文字与页面对比度 ${ratio.toFixed(1)}，低于 4.5`);
    }
    if (isColor(e.c.subTextColor, false) && isColor(e.c.pageColor, false) && contrast(e.c.subTextColor, e.c.pageColor) < 3) {
      add('warn', `${mode}.colors.subTextColor`, `${L}副文字与页面对比度低于 3`);
    }
    const tts = (p.parts.ttsPanel && p.parts.ttsPanel[mode]) || {};
    const ttsKeys = ['artwork', 'skyColor', 'surfaceColor', 'glowColor'];
    const ttsFilled = ttsKeys.filter((k) => tts[k]).length;
    if (ttsFilled > 0 && !ttsComplete(tts)) {
      add('error', `ttsPanel.${mode}.${ttsKeys.find((k) => !tts[k])}`, `${L}朗读面板：插画和三种颜色要填齐`);
    }
    // 朗读面板的文字用阅读配色的文字色；只做了一种模式的面板时，另一种模式的文字落在它上面可能看不清。
    if (e.tts && isColor(e.tts.surfaceColor, false) && isColor(e.reader.textColor, false)) {
      const ratio = contrast(e.reader.textColor, e.tts.surfaceColor);
      if (ratio < 4.5) {
        const borrowed = !ttsComplete(tts);
        add('warn', `ttsPanel.${mode}.surfaceColor`, borrowed
          ? `${L}沿用了另一种模式的朗读面板，${L}正文色在面板底色上对比度只有 ${ratio.toFixed(1)}，建议补一套${L}面板`
          : `${L}朗读面板底色与${L}正文色对比度 ${ratio.toFixed(1)}，低于 4.5`);
      }
    }
    const startup = (p.parts.startup && p.parts.startup[mode]) || {};
    if ((startup.title || startup.subtitle) && !startup.image) add('error', `startup.${mode}.image`, `${L}启动封面写了文案但没有图`);
  }

  const nav = p.parts.navigation || {};
  const navKeys = ['bookshelf', 'explore', 'mine'];
  const navCount = navKeys.filter((k) => nav[k]).length;
  if (navCount > 0 && navCount < 3) add('error', `navigation.${navKeys.find((k) => !nav[k])}`, `导航图标要三个都有（现在 ${navCount} 个）`);
  const selectedKey = [...navKeys, 'listen', 'footprint'].find((k) => nav[`${k}Selected`]);
  if (navCount === 0 && (selectedKey || nav.labels || nav.listen || nav.footprint)) {
    add('error', 'navigation.bookshelf', '给了“听”“足迹”、选中态图标或底栏文字设置，还需要书架、发现、我的三个普通图标');
  }
  for (const extra of ['listen', 'footprint']) {
    if (nav[`${extra}Selected`] && !nav[extra]) {
      add('warn', `navigation.${extra}`, `给了“${extra === 'listen' ? '听' : '足迹'}”的选中态，普通态会用基底主题的图标，两张可能对不上`);
    }
  }
  if (p.parts.bubble && p.parts.bubble.frame && !p.parts.bubble.cap) add('error', 'bubble.cap', '包内气泡有边框时还需要端饰');
  const bookCovers = ((p.parts.book && p.parts.book.covers) || []).length;
  const bookCoversDark = ((p.parts.book && p.parts.book.coversDark) || []).length;
  if (bookCovers > 0 && bookCoversDark > 0 && bookCovers !== bookCoversDark) {
    add('warn', 'book.coversDark', `深色封面 ${bookCoversDark} 张、默认封面 ${bookCovers} 张：张数不同时，同一本书切换深浅色会换成另一幅画`);
  }

  for (const { field } of assetFields()) {
    if (!field.k) continue;
    const modes: (Mode | '')[] = field.k.includes('{m}') ? MODES : [''];
    for (const mode of modes) {
      const path = mode ? mp(field.k, mode) : field.k;
      const value = getPath(path);
      const refs: string[] = Array.isArray(value) ? value : (value ? [value] : []);
      for (const ref of refs) {
        const asset = p.assets.get(ref);
        if (!asset) {
          add('error', path, `${ref.substring(7)} 不在素材库里，重新上传或移除这个引用`);
          continue;
        }
        if (field.kinds && !field.kinds.includes(asset.kind) && field.type !== 'covers') add('error', path, `${ref.substring(7)} 的类型不能用在这里`);
        const warn = sizeWarning(field, asset);
        if (warn) add('warn', path, `${ref.substring(7)}：${warn}`);
      }
    }
  }

  const used = usedAssetPaths(p);
  let total = 0;
  for (const ref of used) total += p.assets.get(ref)?.bytes.length || 0;
  if (used.length > 48) add('error', null, `素材超过 48 个（现在 ${used.length} 个）`, 'assets');
  if (total > 78 * 1024 * 1024) add('error', null, `素材合计 ${formatSize(total)}，整包会超过 80 MB`, 'assets');
  return out;
}

/** 格式层报错里的字段路径 → 部件。 */
function sectionOfMessage(message: string): string {
  const rules: [RegExp, string][] = [
    [/parts\.(light|dark)\.colors/, 'colors'], [/parts\.(light|dark)\.reader/, 'reader'], [/parts\.(light|dark)\.emphasis|parts\.bubble/, 'emphasis'],
    [/ttsPanel/, 'tts'], [/homeBackdrop/, 'homeBackdrop'], [/navigation/, 'nav'], [/parts\.book/, 'book'], [/startup/, 'startup'], [/radius|typography/, 'shape'],
    [/logo|preview/, 'brand'], [/packageId|名称|清单/, 'meta']
  ];
  for (const [pattern, id] of rules) if (pattern.test(message)) return id;
  return 'assets';
}

/** 用应用格式层把整包走一遍；通过返回 null。 */
export async function strictIssue(): Promise<Issue | null> {
  const p = project();
  try {
    const files = await buildFiles(p);
    const theme = JSON.parse(new TextDecoder().decode(files.get('theme.json')));
    if (!theme.parts && !theme.settings) return { level: 'error', section: 'colors', text: '主题还是空的：至少设置一个部件', focus: null };
    await verifyFiles(files);
    return null;
  } catch (error) {
    const text = error instanceof Error ? error.message : String(error);
    return { level: 'error', section: sectionOfMessage(text), text, focus: null };
  }
}
