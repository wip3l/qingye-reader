// 一键导出预览截图：每个画面（书架四种布局、发现、我的、阅读、朗读、启动、主题卡片）浅色、深色各画一台手机，
// 栅格化后拼成一张带标题的 PNG。桌面版和网页版走同一条路：克隆预览 DOM 放进 SVG foreignObject，带上页面样式表，
// 素材的 blob 地址换成 data 地址（SVG 图片里取不到外部资源），包内字体写成 @font-face，再画到画布上。
import { assetFontFamily, assetUrl, project, S, type Mode } from './state.ts';
import { renderScreen, PHONE_H, PHONE_W } from './preview.ts';
import { EXTRA_TAB_CHOICES, SCREENS, SHELF_LAYOUTS } from './sections.ts';
import { baseTheme } from './tokens.ts';
import { mimeForExtension } from '../core/packageIo.ts';

/** 手机连边框的尺寸（.phone 的 7px 边框，content-box）。 */
const FRAME = 7;
const DEVICE_W = PHONE_W + FRAME * 2;
const DEVICE_H = PHONE_H + FRAME * 2;

// 大图版式（未乘倍率的 CSS 像素）。
const COLS = 5;
const PAD = 56;
const GAP = 28;
const HEADER_H = 118;
const CARD_PAD = 22;
const LABEL_H = 40;
const CAPTION_H = 28;
const PHONE_GAP = 18;
const CELL_W = CARD_PAD * 2 + DEVICE_W * 2 + PHONE_GAP;
const CELL_H = CARD_PAD * 2 + LABEL_H + CAPTION_H + DEVICE_H;

const MODE_LABEL: Record<Mode, string> = { light: '浅色', dark: '深色' };

interface Entry { screen: string; shelfLayout?: string; label: string }

function entries(): Entry[] {
  const list: Entry[] = SHELF_LAYOUTS.map(([id, label]) => ({ screen: 'shelf', shelfLayout: id, label: `书架 · ${label}` }));
  for (const [id, label] of SCREENS) if (id !== 'shelf') list.push({ screen: id, label });
  return list;
}

/** 页面里的样式规则；@media 只管编辑器自己的响应式布局，放进 SVG 会按图片尺寸误中窄屏规则，去掉。 */
function pageCss(): string {
  const out: string[] = [];
  for (const sheet of Array.from(document.styleSheets)) {
    let rules: CSSRuleList;
    try {
      rules = sheet.cssRules;
    } catch (_) {
      continue;
    }
    for (const rule of Array.from(rules)) if (!(rule instanceof CSSMediaRule)) out.push(rule.cssText);
  }
  return out.join('\n');
}

function base64(bytes: Uint8Array): string {
  let text = '';
  for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(text);
}

/** 一次导出内复用：blob 地址 → data 地址，以及包内字体的 @font-face。 */
class AssetInliner {
  private readonly byUrl = new Map<string, string>();
  private readonly dataUrls = new Map<string, string>();
  private readonly fonts: [string, string][] = [];

  constructor() {
    for (const [ref, asset] of project().assets) {
      const url = assetUrl(ref);
      if (url) this.byUrl.set(url, ref);
      if (asset.kind === 'font') {
        const family = assetFontFamily(ref);
        if (family) this.fonts.push([family, ref]);
      }
    }
  }

  private dataUrl(ref: string): string {
    let url = this.dataUrls.get(ref);
    if (!url) {
      const asset = project().assets.get(ref)!;
      url = `data:${mimeForExtension(asset.ext)};base64,${base64(asset.bytes)}`;
      this.dataUrls.set(ref, url);
    }
    return url;
  }

  markup(text: string): string {
    return text.replace(/blob:[^"'()\s&<>]+/g, (url) => {
      const ref = this.byUrl.get(url);
      return ref ? this.dataUrl(ref) : url;
    });
  }

  fontFaces(markup: string): string {
    return this.fonts.filter(([family]) => markup.includes(family))
      .map(([family, ref]) => `@font-face{font-family:"${family}";src:url(${this.dataUrl(ref)});}`).join('\n');
  }
}

function loadImage(url: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('画面栅格化失败'));
    img.src = url;
  });
}

/** 一台手机画成 SVG 图片；SVG 的固有尺寸按倍率放大，矢量内容按目标分辨率栅格化。 */
async function rasterize(phone: HTMLElement, css: string, inliner: AssetInliner, scale: number): Promise<HTMLImageElement> {
  phone.style.transform = 'none';
  phone.style.boxShadow = 'none';
  // 预览手机的外层继承了 body 的字号、行高和字体，SVG 里没有 body，写在外层上。
  const body = getComputedStyle(document.body);
  const root = document.createElement('div');
  root.style.cssText = `position:relative;width:${DEVICE_W}px;height:${DEVICE_H}px;margin:0;` +
    `font-family:${body.fontFamily};font-size:${body.fontSize};line-height:${body.lineHeight};` +
    `--f-ui:${getComputedStyle(document.documentElement).getPropertyValue('--f-ui')}`;
  const style = document.createElement('style');
  root.append(style, phone);
  const html = inliner.markup(new XMLSerializer().serializeToString(phone));
  style.textContent = `${inliner.fontFaces(html)}\n${css}`;
  root.removeChild(phone);
  const shell = new XMLSerializer().serializeToString(root).replace('</div>', `${html}</div>`);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${DEVICE_W * scale}" height="${DEVICE_H * scale}" ` +
    `viewBox="0 0 ${DEVICE_W} ${DEVICE_H}"><foreignObject x="0" y="0" width="${DEVICE_W}" height="${DEVICE_H}">${shell}</foreignObject></svg>`;
  // 必须用 data 地址：Chromium 把 blob 地址的 foreignObject SVG 画上画布会污染画布，之后导不出图。
  const img = await loadImage(`data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`);
  await img.decode().catch(() => undefined);
  return img;
}

/** 按某个画面、布局、模式画一台手机，画完恢复界面选择；不带当前部件的虚线框。 */
function phoneFor(entry: Entry, mode: Mode): HTMLElement {
  const ui = S.ui;
  const saved = { screen: ui.screen, shelfLayout: ui.shelfLayout, section: ui.section };
  try {
    ui.screen = entry.screen;
    if (entry.shelfLayout) ui.shelfLayout = entry.shelfLayout as typeof ui.shelfLayout;
    ui.section = '';
    return renderScreen(mode);
  } finally {
    Object.assign(ui, saved);
  }
}

/**
 * 先把所有画面渲染一遍并等图片解码：边框比例、染色图这类缓存要等图片读完才有值（没读完时画的是近似样子）。
 */
async function warmUp(list: Entry[]): Promise<void> {
  const imgs: HTMLImageElement[] = [];
  for (const entry of list) {
    for (const mode of ['light', 'dark'] as Mode[]) imgs.push(...Array.from(phoneFor(entry, mode).querySelectorAll('img')));
  }
  await Promise.all(imgs.map((img) => img.decode().catch(() => undefined)));
  await new Promise((resolve) => setTimeout(resolve, 120));
}

function uiFont(): string {
  return getComputedStyle(document.documentElement).getPropertyValue('--f-ui').trim() || 'system-ui, sans-serif';
}

function ellipsize(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string {
  if (ctx.measureText(text).width <= maxWidth) return text;
  let out = text;
  while (out.length > 1 && ctx.measureText(`${out}…`).width > maxWidth) out = out.slice(0, -1);
  return `${out}…`;
}

export interface BoardResult { bytes: Uint8Array; width: number; height: number }

/** 生成拼好的大图（PNG 字节）。onProgress(已画, 总数)。 */
export async function exportScreenshotBoard(onProgress: (done: number, total: number) => void): Promise<BoardResult> {
  const list = entries();
  const rows = Math.ceil(list.length / COLS);
  const cols = Math.min(COLS, list.length);
  const width = PAD * 2 + cols * CELL_W + (cols - 1) * GAP;
  const height = PAD * 2 + HEADER_H + rows * CELL_H + (rows - 1) * GAP;
  // 桌面 2 倍（手机约 720 × 1560）；触屏浏览器的画布上限低，按面积压到约 1600 万像素以内。
  const maxArea = window.matchMedia('(pointer: coarse)').matches ? 16e6 : 64e6;
  const scale = Math.max(0.5, Math.min(2, Math.sqrt(maxArea / (width * height))));

  const total = list.length * 2;
  onProgress(0, total);
  await warmUp(list);
  const css = pageCss();
  const inliner = new AssetInliner();

  const canvas = document.createElement('canvas');
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('浏览器无法创建这么大的画布');
  ctx.scale(scale, scale);
  const font = uiFont();

  ctx.fillStyle = '#ECEFED';
  ctx.fillRect(0, 0, width, height);

  // 标题：主题名、作者、基底、底栏页签、日期。
  const p = project();
  const name = p.manifest.name || '未命名主题';
  ctx.fillStyle = '#1D2320';
  ctx.textBaseline = 'alphabetic';
  ctx.font = `700 44px ${font}`;
  ctx.fillText(ellipsize(ctx, name, width - PAD * 2), PAD, PAD + 50);
  const extra = EXTRA_TAB_CHOICES.find(([id]) => id === S.ui.extraTab);
  const now = new Date();
  const date = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  const meta = [p.manifest.author ? `作者 ${p.manifest.author}` : '', `基底「${baseTheme().name}」`,
    S.ui.extraTab !== 'none' && extra ? `底栏第四页签：${extra[1]}` : '', date, '轻页主题编辑器预览'].filter(Boolean).join('  ·  ');
  ctx.fillStyle = '#66706B';
  ctx.font = `400 20px ${font}`;
  ctx.fillText(ellipsize(ctx, meta, width - PAD * 2), PAD, PAD + 90);

  let done = 0;
  for (let i = 0; i < list.length; i++) {
    const entry = list[i];
    const x = PAD + (i % COLS) * (CELL_W + GAP);
    const y = PAD + HEADER_H + Math.floor(i / COLS) * (CELL_H + GAP);
    ctx.save();
    ctx.shadowColor = 'rgba(0, 0, 0, 0.08)';
    ctx.shadowBlur = 18;
    ctx.shadowOffsetY = 4;
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    ctx.roundRect(x, y, CELL_W, CELL_H, 22);
    ctx.fill();
    ctx.restore();
    ctx.fillStyle = '#1D2320';
    ctx.font = `700 24px ${font}`;
    ctx.fillText(entry.label, x + CARD_PAD, y + CARD_PAD + 28);

    for (const [k, mode] of (['light', 'dark'] as Mode[]).entries()) {
      const px = x + CARD_PAD + k * (DEVICE_W + PHONE_GAP);
      const py = y + CARD_PAD + LABEL_H + CAPTION_H;
      ctx.fillStyle = '#66706B';
      ctx.font = `500 16px ${font}`;
      ctx.fillText(MODE_LABEL[mode], px + 4, py - 9);
      const img = await rasterize(phoneFor(entry, mode), css, inliner, scale);
      ctx.save();
      ctx.shadowColor = 'rgba(0, 0, 0, 0.18)';
      ctx.shadowBlur = 20;
      ctx.shadowOffsetY = 6;
      ctx.drawImage(img, px, py, DEVICE_W, DEVICE_H);
      ctx.restore();
      onProgress(++done, total);
    }
  }

  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'));
  if (!blob) throw new Error('图片编码失败（画布可能过大）');
  return { bytes: new Uint8Array(await blob.arrayBuffer()), width: canvas.width, height: canvas.height };
}
