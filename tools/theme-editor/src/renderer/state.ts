// 渲染进程的全局状态与几处通用工具：当前工程、文档信息、界面选择，按路径读写 parts，素材的 blob 地址。
import type { EditorProject } from '../core/packageIo.ts';
import { mimeForExtension } from '../core/packageIo.ts';

export type Mode = 'light' | 'dark';

export interface DocInfo {
  /** Ctrl+S 直接写回的 .qytheme；为空时走“另存为”。 */
  filePath: string | null;
  fileName: string;
  dirty: boolean;
  /** 打开时严格校验没过的原因。 */
  problems: string[];
}

export interface UiState {
  section: string;
  mode: Mode;
  screen: string;
  layout: 'both' | 'one';
  /** 书架画面按哪种布局画，与应用“书架布局”设置的四个值一致。 */
  shelfLayout: 'companion' | 'tile' | 'loose' | 'compact';
}

export const S: { project: EditorProject | null; doc: DocInfo; ui: UiState } = {
  project: null,
  doc: { filePath: null, fileName: '', dirty: false, problems: [] },
  ui: { section: 'meta', mode: 'light', screen: 'card', layout: 'both', shelfLayout: 'companion' }
};

export function project(): EditorProject {
  if (!S.project) throw new Error('没有打开的主题');
  return S.project;
}

export function h(tag: string, attrs: Record<string, any> = {}, ...kids: any[]): HTMLElement {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key === 'style') el.style.cssText = value;
    else if (key === 'html') el.innerHTML = value;
    else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.substring(2), value);
    else if (key === 'value' && 'value' in el) (el as HTMLInputElement).value = String(value);
    else el.setAttribute(key, value === true ? '' : String(value));
  }
  for (const kid of kids.flat(3)) {
    if (kid === null || kid === undefined || kid === false) continue;
    el.append(kid instanceof Node ? kid : String(kid));
  }
  return el;
}

export const $ = <T extends HTMLElement = HTMLElement>(selector: string): T => document.querySelector(selector) as T;

export const mp = (path: string, mode: Mode = S.ui.mode): string => path.replace('{m}', mode);

export function getPath(path: string): any {
  return path.split('.').reduce((o: any, key: string) => (o === null || o === undefined ? undefined : o[key]), project().parts);
}

export function setPath(path: string, value: any): void {
  const keys = path.split('.');
  let o = project().parts;
  for (const key of keys.slice(0, -1)) {
    if (o[key] === null || o[key] === undefined || typeof o[key] !== 'object') o[key] = {};
    o = o[key];
  }
  o[keys[keys.length - 1]] = value;
}

const urlCache: WeakMap<Uint8Array, string> = new WeakMap();

/** 素材的显示地址；引用为空或素材不在库里时返回空串。 */
export function assetUrl(ref: string | undefined): string {
  if (!ref || !S.project) return '';
  const asset = S.project.assets.get(ref);
  if (!asset) return '';
  let url = urlCache.get(asset.bytes);
  if (!url) {
    url = URL.createObjectURL(new Blob([asset.bytes as BlobPart], { type: mimeForExtension(asset.ext) }));
    urlCache.set(asset.bytes, url);
  }
  return url;
}

const fontCache: WeakMap<Uint8Array, string> = new WeakMap();
let fontSeq = 0;

/** 把包内字体注册进页面，返回可用的 font-family 名；失败返回空串。 */
export function assetFontFamily(ref: string | undefined): string {
  if (!ref || !S.project) return '';
  const asset = S.project.assets.get(ref);
  if (!asset || asset.kind !== 'font') return '';
  let family = fontCache.get(asset.bytes);
  if (!family) {
    family = `qy-pack-font-${++fontSeq}`;
    try {
      const face = new FontFace(family, asset.bytes.slice().buffer);
      document.fonts.add(face);
      face.load().catch(() => undefined);
    } catch (_) {
      return '';
    }
    fontCache.set(asset.bytes, family);
  }
  return family;
}

let toastTimer = 0;
export function toast(message: string, kind: 'info' | 'error' = 'info'): void {
  document.querySelectorAll('.toast').forEach((el) => el.remove());
  const el = h('div', { class: `toast ${kind}`, role: 'status' }, message);
  document.body.append(el);
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => el.remove(), kind === 'error' ? 5200 : 2800);
}
