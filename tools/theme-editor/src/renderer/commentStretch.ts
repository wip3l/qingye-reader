// 段评气泡图：预览里的气泡（CSS 近似应用的 ReaderCommentBubblePainter）和“文字区与拉伸线”对话框。规则同应用：
// 文字区的高度对齐气泡高（段评字号 × 1.32），整张图按比例缩放；左右拉伸线之间随文字变长拉伸或平铺，竖直方向不拉伸；
// 气泡折到两行时前一段默认裁到文字区底边（不画尾巴）。
import {
  BUBBLE_FRAME_SLICE_MAX, COMMENT_IMAGE_OVERHANG_BOTTOM, COMMENT_IMAGE_OVERHANG_TOP, commentImageOverhang,
  commentImageSliceOrDefault, commentImageTextOrDefault, defaultCommentImageSlice, defaultCommentImageText,
  normalizeBubbleFrameSlice
} from '../../../../entry/src/main/ets/theme/share/ThemePackageFormat.ts';
import { assetUrl, h, project } from './state.ts';
import { cssArgb, frameAspect, loadImage, setFrameReadyListener, getFrameReadyListener, tintedUrl } from './frameStretch.ts';

export interface CommentBox { left: number; right: number; top: number; bottom: number }
export interface CommentImageSettings {
  slice: { left: number; right: number };
  text: CommentBox;
  round: boolean;
  full: boolean;
  tint: boolean;
  touched: boolean;
}

export function commentImageSettingsOf(comment: any, aspect: number): CommentImageSettings {
  const c = comment || {};
  const slice = commentImageSliceOrDefault(c, aspect || 3);
  return {
    slice: { left: slice.left, right: slice.right },
    text: { ...commentImageTextOrDefault(c, aspect || 3) },
    round: c.imageRepeat === 'round',
    full: c.imageBreak === 'full',
    tint: c.imageTint === true,
    touched: !!normalizeBubbleFrameSlice(c.imageSlice) || !!normalizeBubbleFrameSlice(c.imageText)
  };
}

/** 写回 commentBubble：确定后两组位置总是写；缺省的拉伸、裁掉尾巴、原色不写。 */
export function writeCommentImageSettings(comment: any, settings: CommentImageSettings): void {
  const round3 = (v: number): number => Math.round(v * 1000) / 1000;
  comment.imageSlice = { left: round3(settings.slice.left), right: round3(settings.slice.right) };
  comment.imageText = {
    left: round3(settings.text.left), right: round3(settings.text.right),
    top: round3(settings.text.top), bottom: round3(settings.text.bottom)
  };
  if (settings.round) comment.imageRepeat = 'round'; else delete comment.imageRepeat;
  if (settings.full) comment.imageBreak = 'full'; else delete comment.imageBreak;
  if (settings.tint) comment.imageTint = true; else delete comment.imageTint;
}

export function clearCommentImageSettings(comment: any): void {
  for (const key of ['imageSlice', 'imageText', 'imageRepeat', 'imageBreak', 'imageTint']) delete comment[key];
}

/** 上方、下方超出文字区的比例超过建议值时的提示；没有问题返回空串。 */
export function commentOverhangWarning(text: CommentBox): string {
  const [up, down] = commentImageOverhang(text);
  const parts: string[] = [];
  if (up > COMMENT_IMAGE_OVERHANG_TOP) parts.push(`上方超出气泡高 ${Math.round(up * 100)}%（建议 ≤ ${Math.round(COMMENT_IMAGE_OVERHANG_TOP * 100)}%）`);
  if (down > COMMENT_IMAGE_OVERHANG_BOTTOM) parts.push(`下方超出 ${Math.round(down * 100)}%（建议 ≤ ${Math.round(COMMENT_IMAGE_OVERHANG_BOTTOM * 100)}%）`);
  return parts.length ? `文字区${parts.join('，')}，正文行距小时可能压到上下行` : '';
}

export interface CommentOrnamentImage { ref: string; corner: string; size: number; tint: string }

/**
 * 一个图片段评气泡。fontPx 是气泡文字的字号（数字按 0.8 倍显示）；tail 为 false 是折行时的前一段。
 * 图片还没读到宽高比时先按 3:1 画，读完会通知重画。
 */
export function imageBubble(ref: string, settings: CommentImageSettings, label: string, fontPx: number,
  textColor: string, fillColor: string, tail = true, ornament: CommentOrnamentImage | null = null): HTMLElement {
  const raw = assetUrl(ref);
  const aspect = frameAspect(ref) || 3;
  const count = /^\d+\+?$/.test(label);
  const height = fontPx * 1.32;
  const t = settings.text;
  const full = height / Math.max(0.02, 1 - t.top - t.bottom);
  const fullWidth = full * aspect;
  const insL = t.left * fullWidth;
  const insR = t.right * fullWidth;
  const insT = t.top * full;
  const insB = t.bottom * full;
  const lead = settings.slice.left * fullWidth;
  const trail = settings.slice.right * fullWidth;
  const px = (v: number): string => `${+v.toFixed(2)}px`;
  const pct = (v: number): string => `${+(v * 100).toFixed(3)}%`;
  const url = raw ? (settings.tint ? tintedUrl(raw, fillColor) : raw) : '';
  const cut = !tail && !settings.full;
  const skin = h('span', {
    class: 'cmt-skin',
    style: [
      `left:${px(-insL)}`, `right:${px(-insR)}`, `top:${px(-insT)}`, `height:${px(full)}`,
      `border-width:0 ${px(trail)} 0 ${px(lead)}`,
      url ? `border-image-source:url("${url}")` : 'background:rgba(127,127,127,.25)',
      `border-image-slice:0 ${pct(settings.slice.right)} 0 ${pct(settings.slice.left)} fill`,
      `border-image-width:0 ${px(trail)} 0 ${px(lead)}`,
      `border-image-repeat:${settings.round ? 'round' : 'stretch'} stretch`,
      cut ? `clip-path:inset(0 0 ${px(insB)} 0)` : ''
    ].filter(Boolean).join(';')
  });
  const text = h('span', {
    class: 'cmt-text',
    style: `height:${px(height)};font-size:${px(fontPx * (count ? 0.8 : 1))};color:${cssArgb(textColor)};` +
      (count ? `width:${px(fontPx * 2.4)}` : `padding:0 ${px(fontPx * 0.42)}`)
  }, label);
  // 整张图（含尾巴）竖直居中在这一行上，左右超出的部分留出位置不压前后文字（同应用排版里的字距）。
  const shift = (insB - insT) / 2;
  const el = h('span', {
    class: 'cmt-img', 'data-sec': 'emphasis', title: '段评气泡（包里的气泡图）',
    style: `margin:0 ${px(insR + 2)} 0 ${px(insL + 2)};top:${px(-shift)}`
  }, skin, text);
  if (ornament && assetUrl(ornament.ref)) {
    const size = height * 0.62 * (ornament.size > 0 ? ornament.size : 1);
    const inset = size * 0.12;
    const left = ornament.corner === 'topLeft';
    const bottom = ornament.corner === 'bottomRight';
    const src = ornament.tint ? tintedUrl(assetUrl(ornament.ref), ornament.tint) : assetUrl(ornament.ref);
    el.append(h('img', {
      class: 'cmt-orn-img', src, alt: '',
      style: [`width:${px(size)}`, `height:${px(size)}`,
        left ? `left:${px(-insL + inset - size / 2)}` : `right:${px(-insR + inset - size / 2)}`,
        bottom ? `top:${px(height - inset - size / 2)}` : `top:${px(-insT + inset - size / 2)}`].join(';')
    }));
  }
  return el;
}

/**
 * 文字区与拉伸线对话框：左边大图、两条红线（左右两端）和橙色文字区（拖两个圆点或填数字，按原图像素），
 * 右边选项和小样。确定时交回设置；取消什么都不改。
 */
export function openCommentStretch(ref: string, comment: any,
  colors: { paper: string; ink: string; text: string; fill: string; label: string },
  modal: (title: string, body: HTMLElement, buttons: [string, () => void, boolean?][]) => () => void,
  onDone: (settings: CommentImageSettings) => void): void {
  const asset = project().assets.get(ref);
  const url = assetUrl(ref);
  if (!asset || !url) return;
  loadImage(url).then((img) => {
    const iw = img.naturalWidth || asset.width || 300;
    const ih = img.naturalHeight || asset.height || 100;
    const aspect = iw / ih;
    const settings = commentImageSettingsOf(comment, aspect);
    const s = settings.slice;
    const t = settings.text;

    const box = h('div', { class: 'fs-box' }, h('img', { src: url, alt: '段评气泡图', draggable: 'false' }));
    const textBox = h('div', { class: 'cs-text' });
    box.append(textBox);
    const guides: Record<string, HTMLElement> = {};
    for (const key of ['left', 'right'] as const) {
      const g = h('div', { class: 'fs-g v', tabindex: '0', role: 'slider', 'aria-label': `${key === 'left' ? '左' : '右'}拉伸线` },
        h('span', {}, key === 'left' ? '左' : '右'));
      guides[key] = g;
      box.append(g);
      drag(g, (fx) => setSlice(key, key === 'left' ? fx : 1 - fx));
      g.addEventListener('keydown', (event: KeyboardEvent) => {
        const dir = ({ ArrowLeft: -1, ArrowRight: 1 } as Record<string, number>)[event.key];
        if (!dir) return;
        event.preventDefault();
        const step = (event.shiftKey ? 0.05 : 0.01) * (key === 'left' ? dir : -dir);
        setSlice(key, s[key] + step);
      });
    }
    const handles: Record<string, HTMLElement> = {};
    for (const corner of ['tl', 'br'] as const) {
      const handle = h('div', { class: 'cs-h', tabindex: '0', 'aria-label': corner === 'tl' ? '文字区左上角' : '文字区右下角' });
      handles[corner] = handle;
      box.append(handle);
      drag(handle, (fx, fy) => {
        if (corner === 'tl') { setText('left', fx); setText('top', fy); } else { setText('right', 1 - fx); setText('bottom', 1 - fy); }
      });
    }
    function drag(el: HTMLElement, onMove: (fx: number, fy: number) => void): void {
      el.addEventListener('pointerdown', (event: PointerEvent) => {
        event.preventDefault();
        el.setPointerCapture(event.pointerId);
        const move = (ev: PointerEvent): void => {
          const r = box.getBoundingClientRect();
          onMove((ev.clientX - r.left) / r.width, (ev.clientY - r.top) / r.height);
        };
        const up = (): void => { el.removeEventListener('pointermove', move); el.removeEventListener('pointerup', up); };
        el.addEventListener('pointermove', move);
        el.addEventListener('pointerup', up);
      });
    }
    const clamp = (value: number, other: number): number => Math.max(0, Math.min(BUBBLE_FRAME_SLICE_MAX, 0.98 - other, value));
    const setSlice = (key: 'left' | 'right', value: number): void => {
      s[key] = clamp(value, s[key === 'left' ? 'right' : 'left']);
      settings.touched = true;
      refresh();
    };
    const opposite = { left: 'right', right: 'left', top: 'bottom', bottom: 'top' } as const;
    const setText = (key: keyof CommentBox, value: number): void => {
      t[key] = clamp(value, t[opposite[key]]);
      settings.touched = true;
      refresh();
    };

    const numbers: Record<string, HTMLInputElement> = {};
    const numberRow = (items: [string, string, () => number, (v: number) => void][]): HTMLElement => {
      const row = h('div', { class: 'fs-nums' });
      for (const [key, label, , apply] of items) {
        const input = h('input', { type: 'number', min: 0, id: `cs-${key}` }) as HTMLInputElement;
        input.addEventListener('change', () => apply(+input.value || 0));
        numbers[key] = input;
        row.append(h('label', { for: `cs-${key}` }, `${label} px`, input));
      }
      return row;
    };
    const sliceRow = numberRow([
      ['sl', '左端宽', () => s.left * iw, (v) => setSlice('left', v / iw)],
      ['sr', '右端宽', () => s.right * iw, (v) => setSlice('right', v / iw)]
    ]);
    const textRow = numberRow([
      ['tl', '文字区左', () => t.left * iw, (v) => setText('left', v / iw)],
      ['tr', '文字区右', () => t.right * iw, (v) => setText('right', v / iw)],
      ['tt', '文字区上', () => t.top * ih, (v) => setText('top', v / ih)],
      ['tb', '文字区下', () => t.bottom * ih, (v) => setText('bottom', v / ih)]
    ]);

    const select = (id: string, options: [string, string][], value: string, change: (v: string) => void): HTMLElement =>
      h('select', { id, onchange: (event: Event) => { change((event.target as HTMLSelectElement).value); refresh(); } },
        ...options.map(([v, label]) => h('option', { value: v, selected: v === value }, label)));
    const opaque = h('div', { class: 'fs-warn' }, '不透明位图：正文里会露出方形底色。建议换透明底的 PNG 或 SVG。');
    opaque.hidden = asset.ext !== 'jpg';
    const reach = h('div', { class: 'fs-warn' });
    const sample = h('p', { class: 'cs-sample', style: `background:${cssArgb(colors.paper)};color:${cssArgb(colors.ink)}` });
    const wrapped = h('p', { class: 'cs-sample small', style: `background:${cssArgb(colors.paper)};color:${cssArgb(colors.ink)}` });
    const side = h('div', { class: 'fs-side' }, opaque, reach,
      h('div', { class: 'f' }, h('label', { for: 'cs-repeat' }, '中段'),
        select('cs-repeat', [['stretch', '拉伸'], ['round', '平铺花纹']], settings.round ? 'round' : 'stretch', (v) => { settings.round = v === 'round'; })),
      h('div', { class: 'f' }, h('label', { for: 'cs-break' }, '换行处'),
        select('cs-break', [['cut', '前一段裁掉尾巴'], ['full', '每段画整图']], settings.full ? 'full' : 'cut', (v) => { settings.full = v === 'full'; })),
      h('div', { class: 'f' }, h('label', { for: 'cs-tint' }, '颜色'),
        select('cs-tint', [['0', '保留原色'], ['1', '染成段评底色']], settings.tint ? '1' : '0', (v) => { settings.tint = v === '1'; })),
      h('h5', {}, `${colors.label}小样`), sample, wrapped);
    const body = h('div', { class: 'fs-cols' },
      h('div', { class: 'fs-main' }, h('div', { class: 'fs-stage' }, box), sliceRow, textRow,
        h('p', { class: 'fs-hint' }, '红线之间是会被拉长的中段；橙色框是文字区，它的高度对齐正文里的气泡高，框外的尾巴、花边照样画出。拖圆点或填数字（按原图像素），方向键微调红线。')),
      side);

    const refresh = (): void => {
      guides.left.style.left = `${s.left * 100}%`;
      guides.right.style.left = `${(1 - s.right) * 100}%`;
      Object.assign(textBox.style, { left: `${t.left * 100}%`, right: `${t.right * 100}%`, top: `${t.top * 100}%`, bottom: `${t.bottom * 100}%` });
      Object.assign(handles.tl.style, { left: `${t.left * 100}%`, top: `${t.top * 100}%` });
      Object.assign(handles.br.style, { left: `${(1 - t.right) * 100}%`, top: `${(1 - t.bottom) * 100}%` });
      const values: Record<string, number> = { sl: s.left * iw, sr: s.right * iw, tl: t.left * iw, tr: t.right * iw, tt: t.top * ih, tb: t.bottom * ih };
      for (const [key, value] of Object.entries(values)) {
        if (document.activeElement !== numbers[key]) numbers[key].value = String(Math.round(value));
      }
      const warning = commentOverhangWarning(t);
      reach.textContent = warning;
      reach.hidden = !warning;
      const bubble = (label: string, tail = true): HTMLElement =>
        imageBubble(ref, settings, label, 12, colors.text, colors.fill, tail);
      sample.replaceChildren('“走吧。”他推开门', bubble('3'), '，风一下灌了进来。', bubble('99+'), '雨还没有停。', bubble('本章说'));
      wrapped.replaceChildren('折行时前一段：', bubble('段评', false));
    };
    const previous = getFrameReadyListener();
    const listener = (): void => {
      previous();
      if (body.isConnected) refresh();
      else if (getFrameReadyListener() === listener) setFrameReadyListener(previous);
    };
    setFrameReadyListener(listener);

    const close = modal(`段评气泡图 · 文字区与拉伸线 · ${ref.substring(7)}`, body, [
      ['恢复默认位置', () => {
        Object.assign(s, { left: defaultCommentImageSlice(aspect).left, right: defaultCommentImageSlice(aspect).right });
        Object.assign(t, defaultCommentImageText(aspect));
        settings.touched = false;
        refresh();
      }],
      ['取消', () => close()],
      ['确定', () => { close(); onDone({ ...settings, touched: true }); }, true]
    ]);
    refresh();
  }).catch(() => undefined);
}
