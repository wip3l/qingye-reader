// 生效令牌：包里填了的用包里的，没填的回退到基底主题（规则与 ThemePackRegistry 拼装主题时一致）。
import data from '../core/builtinThemes.json';
import { S, project, type Mode } from './state.ts';

export interface BaseVariant {
  colors: Record<string, string>;
  reader: { backgroundColor: string; hasArtwork: boolean; textColor: string; subTextColor: string; contentTone: string };
  emphasis: { mode: string; bubbleStyle: string; color: string; textColor: string };
}

export interface BaseTheme {
  id: string;
  name: string;
  fontFamily: string;
  iconPack: string;
  light: BaseVariant;
  dark: BaseVariant;
  radius: Record<string, number>;
}

export const THEMES: BaseTheme[] = (data as any).themes;
export const BUBBLES: { id: string; label: string }[] = (data as any).bubbles;
export const GENERIC_BUBBLES = ['qq-soft', 'qq-solid', 'capsule', 'paper', 'neon'];

export function baseTheme(): BaseTheme {
  const id = S.project ? S.project.manifest.baseTheme : '';
  return THEMES.find((t) => t.id === id) || THEMES[0];
}

export function themeName(id: string): string {
  const theme = THEMES.find((t) => t.id === id);
  return theme ? theme.name : id;
}

export function bubbleLabel(id: string): string {
  const bubble = BUBBLES.find((b) => b.id === id);
  return bubble ? bubble.label : id;
}

const filled = (record: any): Record<string, any> => {
  const out: Record<string, any> = {};
  for (const [key, value] of Object.entries(record || {})) if (value !== '' && value !== null && value !== undefined) out[key] = value;
  return out;
};

export const ttsComplete = (t: any): boolean => !!(t && t.artwork && t.skyColor && t.surfaceColor && t.glowColor);

export interface Effective {
  c: Record<string, string>;
  reader: {
    backgroundColor: string; textColor: string; subTextColor: string; contentTone: string;
    /** pack：包里的角饰/整图；base-art：沿用基底主题的背景素材（编辑器里画占位）；none：只有底色。 */
    source: 'pack' | 'base-art' | 'none';
    mode: string; leading: string; trailing: string; image: string; imageFit: string;
  };
  e: { mode: string; bubble: 'pack' | string; color: string; textColor: string };
  radius: Record<string, number>;
  tts: any | null;
  startup: any | null;
}

export function effective(mode: Mode): Effective {
  const p = project().parts;
  const base = baseTheme();
  const bv = base[mode];
  const v = p[mode] || {};
  const c = { ...bv.colors, ...filled(v.colors) };
  const r = filled(v.reader);
  let bgMode = r.backgroundMode || (r.image ? 'image' : (r.leading || r.trailing ? 'ornaments' : ''));
  let source: Effective['reader']['source'];
  if (bgMode === 'ornaments' || bgMode === 'image') source = 'pack';
  else if (bgMode === 'none') source = 'none';
  else source = bv.reader.hasArtwork ? 'base-art' : 'none';
  if (!bgMode) bgMode = source === 'base-art' ? 'ornaments' : 'none';
  const reader = {
    backgroundColor: r.backgroundColor || bv.reader.backgroundColor,
    textColor: r.textColor || bv.reader.textColor,
    subTextColor: r.subTextColor || bv.reader.subTextColor,
    contentTone: r.contentTone || bv.reader.contentTone,
    source, mode: bgMode, leading: r.leading || '', trailing: r.trailing || '', image: r.image || '', imageFit: r.imageFit || 'cover'
  };
  const em = filled(v.emphasis);
  const packBubble = !!(p.bubble && p.bubble.cap);
  const e = {
    mode: em.mode || bv.emphasis.mode,
    bubble: packBubble ? 'pack' : (em.bubbleStyle || bv.emphasis.bubbleStyle),
    color: em.color || bv.emphasis.color,
    textColor: em.textColor || bv.emphasis.textColor
  };
  const radius = { ...base.radius };
  for (const [key, value] of Object.entries(p.radius || {})) if (typeof value === 'number') radius[key] = value;
  const other: Mode = mode === 'light' ? 'dark' : 'light';
  const tts = ttsComplete(p.ttsPanel && p.ttsPanel[mode]) ? p.ttsPanel[mode]
    : (ttsComplete(p.ttsPanel && p.ttsPanel[other]) ? p.ttsPanel[other] : null);
  const startup = p.startup && p.startup[mode] && p.startup[mode].image ? p.startup[mode]
    : (p.startup && p.startup[other] && p.startup[other].image ? p.startup[other] : null);
  return { c, reader, e, radius, tts, startup };
}

/** 字段的基底值，用作输入框里“沿用 …”的提示。 */
export function baseValue(path: string): any {
  const keys = path.split('.');
  const base = baseTheme();
  if ((keys[0] === 'light' || keys[0] === 'dark') && keys.length === 3) {
    const variant = base[keys[0] as Mode];
    if (keys[1] === 'colors') return variant.colors[keys[2]];
    if (keys[1] === 'reader') return (variant.reader as any)[keys[2]];
    if (keys[1] === 'emphasis') {
      if (keys[2] === 'color' || keys[2] === 'textColor') return (variant.emphasis as any)[keys[2]];
    }
  }
  if (keys[0] === 'radius') return base.radius[keys[1]];
  return '';
}
