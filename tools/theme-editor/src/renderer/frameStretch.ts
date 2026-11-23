// 强调气泡边框的拉伸：预览里逐行套边框的 CSS、拉伸区域对话框。规则同应用（ReaderV2BubbleFrame）：
// 文字带高度是字号的 1.36 倍，上下拉伸线之间对齐文字带，线外照样画出；左右两端按比例缩放保持原样，中段拉伸或平铺；
// 换行处每行都画两端（box-decoration-break: clone），或在断开处平切（slice）。
import {
  BUBBLE_FRAME_SLICE_MAX, bubbleFrameSliceOrDefault, normalizeBubbleFrameSlice
} from '../../../../entry/src/main/ets/theme/share/ThemePackageFormat.ts';
import { assetUrl, h, project } from './state.ts';

export const BAND_EM = 1.36;

export interface FrameSlice { left: number; right: number; top: number; bottom: number }
export interface FrameSettings { slice: FrameSlice; round: boolean; cut: boolean; tint: boolean; touched: boolean }

// 原图宽高比与染色后的图都要等图片读完：读完后调监听重画预览。
const aspects = new Map<string, number>();
const tinted = new Map<string, string>();
const pending = new Set<string>();
let onReady: () => void = () => {};
export function setFrameReadyListener(listener: () => void): void { onReady = listener; }
export function getFrameReadyListener(): () => void { return onReady; }

export function loadImage(url: string): Promise<HTMLImageElement> {
  return load(url);
}

function load(url: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('图片读不出来'));
    img.src = url;
  });
}

/** 原图宽 / 高；还没读到时先返回 0 并开始读，读完通知重画。 */
export function frameAspect(ref: string): number {
  const url = assetUrl(ref);
  if (!url) return 0;
  const known = aspects.get(url);
  if (known) return known;
  const asset = project().assets.get(ref);
  if (asset && asset.width && asset.height) {
    aspects.set(url, asset.width / asset.height);
    return asset.width / asset.height;
  }
  if (!pending.has(url)) {
    pending.add(url);
    load(url).then((img) => {
      aspects.set(url, (img.naturalWidth || 300) / (img.naturalHeight || 100));
      onReady();
    }).catch(() => aspects.set(url, 3)).finally(() => pending.delete(url));
  }
  return 0;
}

const luminances = new Map<string, number>();

/**
 * 边框不透明像素的平均相对亮度（0–1），用来提示“浅色边框放到深色纸面上看不清”。还没读到时返回 -1 并开始读，
 * 读完通知重画；读不出来时也返回 -1。
 */
export function frameLuminance(ref: string): number {
  const url = assetUrl(ref);
  if (!url) return -1;
  const known = luminances.get(url);
  if (known !== undefined) return known;
  const key = `lum|${url}`;
  if (!pending.has(key)) {
    pending.add(key);
    load(url).then((img) => {
      const w = Math.max(1, Math.min(240, img.naturalWidth || 240));
      const hgt = Math.max(1, Math.round(w / Math.max(0.1, (img.naturalWidth || 300) / (img.naturalHeight || 100))));
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = hgt;
      const ctx = canvas.getContext('2d') as CanvasRenderingContext2D;
      ctx.drawImage(img, 0, 0, w, hgt);
      const data = ctx.getImageData(0, 0, w, hgt).data;
      const lin = (v: number): number => { const c = v / 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
      let sum = 0;
      let weight = 0;
      for (let i = 0; i < data.length; i += 4) {
        const a = data[i + 3] / 255;
        if (a < 0.15) continue;
        sum += a * (0.2126 * lin(data[i]) + 0.7152 * lin(data[i + 1]) + 0.0722 * lin(data[i + 2]));
        weight += a;
      }
      luminances.set(url, weight > 0 ? sum / weight : -1);
      onReady();
    }).catch(() => luminances.set(url, -1)).finally(() => pending.delete(key));
  }
  return -1;
}

/** 染成气泡底色的图（只改不透明像素的颜色，保留透明度）；没读完时先用原图。 */
export function tintedUrl(url: string, color: string): string {
  const key = `${url}|${color}`;
  const done = tinted.get(key);
  if (done) return done;
  if (!pending.has(key)) {
    pending.add(key);
    load(url).then((img) => {
      const w = Math.max(1, img.naturalWidth || 300);
      const hgt = Math.max(1, img.naturalHeight || 100);
      const scale = Math.max(1, Math.min(4, 480 / hgt));
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(w * scale);
      canvas.height = Math.round(hgt * scale);
      const ctx = canvas.getContext('2d') as CanvasRenderingContext2D;
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      ctx.globalCompositeOperation = 'source-in';
      ctx.fillStyle = cssArgb(color);
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      tinted.set(key, canvas.toDataURL('image/png'));
      onReady();
    }).catch(() => tinted.set(key, url)).finally(() => pending.delete(key));
  }
  return url;
}

/** 应用的颜色是 #AARRGGBB（透明度在前）。 */
export function cssArgb(color: string): string {
  const hex = (color || '').replace('#', '');
  if (hex.length === 8) return `#${hex.slice(2)}${hex.slice(0, 2)}`;
  return color || '#000000';
}

export function frameSettingsOf(bubble: any, aspect: number): FrameSettings {
  const b = bubble || {};
  return {
    slice: { ...bubbleFrameSliceOrDefault(b.frameSlice, aspect || 3) },
    round: b.frameRepeat === 'round',
    cut: b.frameBreak === 'cut',
    tint: b.frameTint === true,
    touched: !!normalizeBubbleFrameSlice(b.frameSlice)
  };
}

/** 写回 bubble：拉伸线总是写（调过就写，确定后视为调过）；缺省的拉伸、每行两端、原色不写。 */
export function writeFrameSettings(bubble: any, settings: FrameSettings): void {
  bubble.frameSlice = { ...normalizeBubbleFrameSlice(settings.slice) };
  if (settings.round) bubble.frameRepeat = 'round'; else delete bubble.frameRepeat;
  if (settings.cut) bubble.frameBreak = 'cut'; else delete bubble.frameBreak;
  if (settings.tint) bubble.frameTint = true; else delete bubble.frameTint;
}

export function clearFrameSettings(bubble: any): void {
  delete bubble.frameSlice;
  delete bubble.frameRepeat;
  delete bubble.frameBreak;
  delete bubble.frameTint;
}

/**
 * 给强调文字的 span 套边框的样式。fontPx 是这段文字的字号；返回空串表示图片还没读到。
 */
export function frameSpanStyle(ref: string, settings: FrameSettings, fontPx: number, tintColor: string): string {
  const aspect = frameAspect(ref);
  const raw = assetUrl(ref);
  if (!aspect || !raw) return '';
  const url = settings.tint ? tintedUrl(raw, tintColor) : raw;
  const { left, right, top, bottom } = settings.slice;
  const full = fontPx * BAND_EM / Math.max(0.02, 1 - top - bottom);
  const lead = left * aspect * full;
  const trail = right * aspect * full;
  const pct = (v: number): string => `${+(v * 100).toFixed(3)}%`;
  const px = (v: number): string => `${+v.toFixed(2)}px`;
  const brk = settings.cut ? 'slice' : 'clone';
  return [
    'background:none', 'border-radius:0', 'border-style:solid', 'border-width:0',
    `border-image-source:url("${url}")`,
    `border-image-slice:${pct(top)} ${pct(right)} ${pct(bottom)} ${pct(left)} fill`,
    `border-image-width:${px(top * full)} ${px(trail)} ${px(bottom * full)} ${px(lead)}`,
    `border-image-outset:${px(top * full)} 0 ${px(bottom * full)} 0`,
    `border-image-repeat:${settings.round ? 'round' : 'stretch'} stretch`,
    // 行内盒的内容区约 1.2em，上下各补 0.08em 凑成 1.36em 的文字带。
    `padding:0.08em ${px(trail)} 0.08em ${px(lead)}`,
    `box-decoration-break:${brk}`, `-webkit-box-decoration-break:${brk}`
  ].join(';');
}

/**
 * 边框拉伸区域对话框：左边大图和四条红线（也能填数字，按原图像素），右边选项和小样。
 * 确定时交回设置；取消什么都不改。
 */
export function openFrameStretch(ref: string, bubble: any, colors: { text: string; bubble: string },
  modal: (title: string, body: HTMLElement, buttons: [string, () => void, boolean?][]) => () => void,
  onDone: (settings: FrameSettings) => void): void {
  const asset = project().assets.get(ref);
  const url = assetUrl(ref);
  if (!asset || !url) return;
  load(url).then((img) => {
    const iw = img.naturalWidth || asset.width || 300;
    const ih = img.naturalHeight || asset.height || 100;
    const aspect = iw / ih;
    aspects.set(url, aspect);
    const settings = frameSettingsOf(bubble, aspect);
    const s = settings.slice;

    const imgEl = h('img', { src: url, alt: '边框素材', draggable: 'false' });
    const box = h('div', { class: 'fs-box' }, imgEl);
    const guides: Record<string, HTMLElement> = {};
    for (const key of ['left', 'right', 'top', 'bottom'] as const) {
      const vertical = key === 'left' || key === 'right';
      const label = { left: '左', right: '右', top: '上', bottom: '下' }[key];
      const g = h('div', { class: `fs-g ${vertical ? 'v' : 'h'}`, tabindex: '0', role: 'slider', 'aria-label': `${label}拉伸线` },
        h('span', {}, label));
      guides[key] = g;
      box.append(g);
      g.addEventListener('pointerdown', (event: PointerEvent) => {
        event.preventDefault();
        g.setPointerCapture(event.pointerId);
        const move = (ev: PointerEvent): void => {
          const r = box.getBoundingClientRect();
          const fx = (ev.clientX - r.left) / r.width;
          const fy = (ev.clientY - r.top) / r.height;
          const value = key === 'left' ? fx : key === 'right' ? 1 - fx : key === 'top' ? fy : 1 - fy;
          setSlice(key, value);
        };
        const up = (): void => { g.removeEventListener('pointermove', move); g.removeEventListener('pointerup', up); };
        g.addEventListener('pointermove', move);
        g.addEventListener('pointerup', up);
      });
      g.addEventListener('keydown', (event: KeyboardEvent) => {
        const dir = ({ ArrowLeft: -1, ArrowUp: -1, ArrowRight: 1, ArrowDown: 1 } as Record<string, number>)[event.key];
        if (!dir) return;
        event.preventDefault();
        const step = (event.shiftKey ? 0.05 : 0.01) * (key === 'left' || key === 'top' ? dir : -dir);
        setSlice(key, s[key] + step);
      });
    }
    const opposite = { left: 'right', right: 'left', top: 'bottom', bottom: 'top' } as const;
    const setSlice = (key: keyof FrameSlice, value: number): void => {
      s[key] = Math.max(0, Math.min(BUBBLE_FRAME_SLICE_MAX, 0.98 - s[opposite[key]], value));
      settings.touched = true;
      refresh();
    };

    const numbers: Record<string, HTMLInputElement> = {};
    const numberRow = h('div', { class: 'fs-nums' });
    for (const [key, label] of [['left', '左端宽'], ['right', '右端宽'], ['top', '文字行上方'], ['bottom', '文字行下方']] as const) {
      const input = h('input', { type: 'number', min: 0, id: `fs-${key}` }) as HTMLInputElement;
      input.addEventListener('change', () => {
        const size = key === 'left' || key === 'right' ? iw : ih;
        setSlice(key, (+input.value || 0) / size);
      });
      numbers[key] = input;
      numberRow.append(h('label', { for: `fs-${key}` }, `${label} px`, input));
    }

    const select = (id: string, options: [string, string][], value: string, change: (v: string) => void): HTMLElement => {
      const el = h('select', { id, onchange: (event: Event) => { change((event.target as HTMLSelectElement).value); refresh(); } },
        ...options.map(([v, label]) => h('option', { value: v, selected: v === value }, label)));
      return el;
    };
    const warn = h('div', { class: 'fs-warn' }, '不透明位图：正文里会露出底色。建议换透明底的 PNG 或 SVG。');
    warn.hidden = asset.ext !== 'jpg';
    const sampleSpan = (text: string): HTMLElement => h('span', { class: 'fs-em' }, text);
    const strips = ['短句', '中等长度的一句话', '一句很长很长的强调文字也能拉开'].map(sampleSpan);
    const para = h('p', { class: 'fs-para' }, '他敲敲柜台：', sampleSpan('“这本账簿是谁送来的？”'), '老人答：',
      sampleSpan('“昨夜一个穿灰大衣的年轻人放下就走了，连名字都没留。”'));
    const side = h('div', { class: 'fs-side' }, warn,
      h('div', { class: 'f' }, h('label', { for: 'fs-repeat' }, '中段'),
        select('fs-repeat', [['stretch', '拉伸'], ['round', '平铺花纹']], settings.round ? 'round' : 'stretch', (v) => { settings.round = v === 'round'; })),
      h('div', { class: 'f' }, h('label', { for: 'fs-break' }, '换行处'),
        select('fs-break', [['full', '每行两端'], ['cut', '断开处平切']], settings.cut ? 'cut' : 'full', (v) => { settings.cut = v === 'cut'; })),
      h('div', { class: 'f' }, h('label', { for: 'fs-tint' }, '颜色'),
        select('fs-tint', [['0', '保留原色'], ['1', '染成气泡底色（浅深各用各的）']], settings.tint ? '1' : '0', (v) => { settings.tint = v === '1'; })),
      h('h5', {}, '长短试看'), h('div', { class: 'fs-strips' }, ...strips.map((span) => h('div', {}, span))),
      h('h5', {}, '正文'), para);
    const body = h('div', { class: 'fs-cols' },
      h('div', { class: 'fs-main' }, h('div', { class: 'fs-stage' }, box), numberRow,
        h('p', { class: 'fs-hint' }, '拖红线或填数字（按原图像素）。左右线之间是会被拉长的中段；上下线之间对齐文字行，线外的阴影、出头花纹照样画出。方向键微调，按住 Shift 一次 5%。')),
      side);

    const refresh = (): void => {
      guides.left.style.left = `${s.left * 100}%`;
      guides.right.style.left = `${(1 - s.right) * 100}%`;
      guides.top.style.top = `${s.top * 100}%`;
      guides.bottom.style.top = `${(1 - s.bottom) * 100}%`;
      numbers.left.value = String(Math.round(s.left * iw));
      numbers.right.value = String(Math.round(s.right * iw));
      numbers.top.value = String(Math.round(s.top * ih));
      numbers.bottom.value = String(Math.round(s.bottom * ih));
      const style = frameSpanStyle(ref, settings, 15, colors.bubble);
      for (const span of [...strips, ...para.querySelectorAll<HTMLElement>('.fs-em')]) {
        span.setAttribute('style', `${style};color:${cssArgb(colors.text)}`);
      }
    };
    // 小样等图读完也要重画；对话框关掉后把监听换回去。
    const previous = onReady;
    const listener = (): void => {
      previous();
      if (body.isConnected) refresh();
      else if (onReady === listener) setFrameReadyListener(previous);
    };
    setFrameReadyListener(listener);

    const close = modal(`边框拉伸区域 · ${ref.substring(7)}`, body, [
      ['恢复默认位置', () => {
        Object.assign(s, bubbleFrameSliceOrDefault(null, aspect));
        settings.touched = false;
        refresh();
      }],
      ['取消', () => close()],
      ['确定', () => { close(); onDone({ ...settings, touched: true }); }, true]
    ]);
    refresh();
  }).catch(() => undefined);
}
