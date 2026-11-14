// 编辑器窗口：部件树、检查器、实时预览、问题条，以及打开/保存/导出/草稿。
import './styles.css';
import {
  exportFiles, exportZip, formatSize, loadProject, makeAsset, newProject, readZip, safeAssetPath, serializeDraft,
  deserializeDraft, usedAssetPaths, type EditorAsset, type EditorProject, type FileMap
} from '../core/packageIo.ts';
import { $, assetUrl, getPath, h, mp, project, S, setPath, toast, type Mode } from './state.ts';
import { SECTIONS, SCREENS, SHELF_LAYOUTS, EXTRA_TAB_CHOICES, section, assetFields, type Field } from './sections.ts';
import { renderScreen, PHONE_H, PHONE_W } from './preview.ts';
import { editorIssues, sizeWarning, strictIssue, type Issue } from './checks.ts';
import { alphaOf, contrast, darkDraft, isColor, withAlpha } from './colors.ts';
import { baseThemeOptions, baseValue, effective, themeName } from './tokens.ts';
import { browserApi } from './browserApi.ts';

interface Result<T> { ok: boolean; value?: T; error?: string }
interface OpenedTarget { path: string; name: string; kind: 'zip' | 'folder'; bytes?: Uint8Array; files?: [string, Uint8Array][] }
interface RecentItem { path: string; name: string; kind: string; time: number; exists: boolean }
interface EditorApi {
  openDialog(folder: boolean): Promise<Result<OpenedTarget | null>>;
  openPath(target: string): Promise<Result<OpenedTarget>>;
  saveFile(target: string | null, defaultName: string, bytes: Uint8Array): Promise<Result<string | null>>;
  exportFolder(name: string, files: [string, Uint8Array][]): Promise<Result<string | null>>;
  recent(): Promise<Result<RecentItem[]>>;
  forgetRecent(target: string): Promise<Result<void>>;
  saveDraft(bytes: Uint8Array): Promise<Result<void>>;
  loadDraft(): Promise<Result<Uint8Array | null>>;
  clearDraft(): Promise<Result<void>>;
  launchFile(): Promise<Result<string | null>>;
  reveal(target: string): Promise<Result<void>>;
  setDirty(value: boolean): void;
  setTitle(title: string): void;
}
declare global { interface Window { editorApi?: EditorApi } }
const api: EditorApi = window.editorApi || browserApi();

async function call<T>(promise: Promise<Result<T>>): Promise<T> {
  const result = await promise;
  if (!result.ok) throw new Error(result.error || '操作失败');
  return result.value as T;
}

const MODE_LABEL: Record<Mode, string> = { light: '浅色', dark: '深色' };
const KIND_LABEL: Record<string, string> = { image: '位图', vector: 'SVG', font: '字体' };

// ---- 撤销与提交 ----

interface Snapshot { project: EditorProject }
const undoStack: Snapshot[] = [];
const redoStack: Snapshot[] = [];

function snapshot(): Snapshot {
  const p = project();
  return {
    project: {
      ...p,
      manifest: structuredClone(p.manifest),
      parts: structuredClone(p.parts),
      settings: p.settings ? structuredClone(p.settings) : null,
      layout: p.layout ? structuredClone(p.layout) : null,
      emphasis: p.emphasis ? structuredClone(p.emphasis) : null,
      fonts: structuredClone(p.fonts),
      assets: new Map(p.assets)
    }
  };
}

function markDirty(): void {
  if (!S.doc.dirty) {
    S.doc.dirty = true;
    api.setDirty(true);
  }
}

function commit(change: () => void): void {
  undoStack.push(snapshot());
  if (undoStack.length > 100) undoStack.shift();
  redoStack.length = 0;
  change();
  markDirty();
  render();
}

let liveBase: Snapshot | null = null;
/** 拖取色器、滑块时实时刷新预览，松手才记一次撤销。 */
function liveSet(path: string, value: any): void {
  if (!liveBase) liveBase = snapshot();
  setPath(path, value);
  markDirty();
  renderPreview();
  renderTitle();
}
function finishLive(): void {
  if (liveBase) {
    undoStack.push(liveBase);
    redoStack.length = 0;
    liveBase = null;
  }
  render();
}

function undo(from: Snapshot[], to: Snapshot[]): void {
  const s = from.pop();
  if (!s || !S.project) return;
  to.push(snapshot());
  S.project = s.project;
  markDirty();
  render();
}

// ---- 渲染 ----

let issues: Issue[] = [];
let strict: Issue | null = null;
let strictTimer = 0;
let strictSeq = 0;

function scheduleStrict(): void {
  window.clearTimeout(strictTimer);
  strictTimer = window.setTimeout(async () => {
    if (!S.project) return;
    const seq = ++strictSeq;
    const result = issues.some((i) => i.level === 'error') ? null : await strictIssue();
    if (seq !== strictSeq) return;
    strict = result;
    renderNav();
    renderIssues();
  }, 350);
}

function allIssues(): Issue[] {
  return strict ? [...issues, strict] : issues;
}

function render(): void {
  if (!S.project) return;
  issues = editorIssues();
  if (issues.some((i) => i.level === 'error')) strict = null;
  renderNav();
  renderInspector();
  renderPreview();
  renderIssues();
  renderTitle();
  scheduleStrict();
}

function sectionState(id: string): string {
  const list = allIssues();
  if (list.some((i) => i.section === id && i.level === 'error')) return 'err';
  if (list.some((i) => i.section === id && i.level === 'warn')) return 'warn';
  const s = section(id);
  if (id === 'meta') return 'set';
  if (id === 'assets') return project().assets.size ? 'set' : '';
  const any = s.fields.some((f) => {
    if (!f.k || f.k.startsWith('m.')) return false;
    return (['light', 'dark'] as Mode[]).some((m) => {
      const v = getPath(mp(f.k as string, m));
      return Array.isArray(v) ? v.length > 0 : v !== '' && v !== null && v !== undefined;
    });
  });
  return any ? 'set' : '';
}

function renderNav(): void {
  const nav = $('#nav');
  nav.replaceChildren();
  let group = '';
  for (const s of SECTIONS) {
    if (s.group !== group) {
      group = s.group;
      nav.append(h('h4', {}, group));
    }
    const count = s.id === 'assets' ? String(project().assets.size) : '';
    nav.append(h('button', { 'aria-current': S.ui.section === s.id ? 'true' : 'false', onclick: () => selectSection(s.id) },
      h('i', { class: `dot ${sectionState(s.id)}` }), s.name, count ? h('span', { class: 'count' }, count) : null));
  }
  nav.append(h('div', { class: 'legend' },
    h('span', {}, h('i', { class: 'dot set' }), '已设置'), h('span', {}, h('i', { class: 'dot' }), '沿用基底主题'),
    h('span', {}, h('i', { class: 'dot warn' }), '有提示'), h('span', {}, h('i', { class: 'dot err' }), '有错误，不能导出')));
}

function selectSection(id: string, focus?: string | null): void {
  S.ui.section = id;
  const s = section(id);
  if (s.screen) S.ui.screen = s.screen;
  if (focus) {
    const m = /^(light|dark)\./.exec(focus) || /\.(light|dark)\./.exec(focus);
    if (m) S.ui.mode = m[1] as Mode;
  }
  render();
  if (focus) {
    const el = document.querySelector(`[data-key="${CSS.escape(focus)}"]`) as HTMLElement | null;
    if (el) {
      el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      el.classList.add('flash');
      const input = el.querySelector('input,select,textarea,button') as HTMLElement | null;
      if (input) input.focus({ preventScroll: true });
    }
  }
}

function renderTitle(): void {
  const name = S.doc.fileName || project().manifest.name || '未命名主题';
  $('#file-label').replaceChildren(name + (S.doc.dirty ? ' •' : ''), h('span', {}, `pack:${project().manifest.packageId}`));
  api.setTitle(`${name}${S.doc.dirty ? ' •' : ''} — 轻页主题编辑器`);
  ($('#btn-undo') as HTMLButtonElement).disabled = !undoStack.length;
  ($('#btn-redo') as HTMLButtonElement).disabled = !redoStack.length;
}

function renderIssues(): void {
  const box = $('#issues');
  box.replaceChildren();
  const list = allIssues();
  const errors = list.filter((i) => i.level === 'error').length;
  const warns = list.length - errors;
  ($('#btn-export') as HTMLButtonElement).disabled = errors > 0;
  ($('#btn-folder') as HTMLButtonElement).disabled = errors > 0;
  ($('#btn-save') as HTMLButtonElement).disabled = errors > 0;
  if (S.doc.problems.length) {
    box.append(h('div', { class: 'loadnote' }, `打开时没通过应用的校验：${S.doc.problems[0]}。改好后即可导出。`));
  }
  if (!list.length) {
    box.append(h('div', { class: 'sum okmsg' }, '✓ 可以导出：已用应用的格式校验走过一遍'));
    return;
  }
  box.append(h('div', { class: 'sum' },
    errors ? h('span', { class: 'e' }, `${errors} 个错误`) : null, warns ? h('span', { class: 'w' }, `${warns} 个提示`) : null));
  box.append(h('ul', {}, ...list.map((i) => h('li', { class: i.level },
    h('button', { onclick: () => selectSection(i.section, i.focus) }, i.text)))));
}

// ---- 预览 ----

function renderPreview(): void {
  const box = $('#phones');
  box.replaceChildren();
  const both = S.ui.layout === 'both';
  const modes: Mode[] = both ? ['light', 'dark'] : [S.ui.mode];
  for (const mode of modes) {
    const phone = renderScreen(mode);
    phone.addEventListener('click', (event) => {
      if (S.ui.mode !== mode) {
        S.ui.mode = mode;
        render();
        return;
      }
      const target = (event.target as HTMLElement).closest('[data-sec]') as HTMLElement | null;
      if (target && target.dataset.sec && target.dataset.sec !== S.ui.section) selectSection(target.dataset.sec);
    });
    const label = h('div', { class: 'cap' }, MODE_LABEL[mode], mode === S.ui.mode ? ' · 正在编辑' : ' · 点击切换编辑');
    box.append(h('div', { class: `phonecol${mode === S.ui.mode ? ' active' : ''}` }, label, h('div', { class: 'phonebox' }, phone)));
  }
  fitPhones();
  $('#screens').replaceChildren(...SCREENS.map(([id, label]) => h('button', {
    'aria-pressed': S.ui.screen === id ? 'true' : 'false', onclick: () => { S.ui.screen = id; renderPreview(); }
  }, label)));
  // 书架画面才有布局切换；应用里四种布局对主题素材的用法不同（陪伴用精装书，紧凑和宽松是列表）。
  const layouts = $('#shelf-layouts');
  layouts.hidden = S.ui.screen !== 'shelf';
  layouts.replaceChildren(...SHELF_LAYOUTS.map(([id, label]) => h('button', {
    'aria-pressed': S.ui.shelfLayout === id ? 'true' : 'false', title: `书架布局：${label}`,
    onclick: () => { S.ui.shelfLayout = id as typeof S.ui.shelfLayout; renderPreview(); }
  }, label)));
  // 首页三个画面（书架、发现、我的）有底栏，可以切换第四个页签看“听”“足迹”的图标。
  const extraTab = $('#extra-tab');
  extraTab.hidden = !['shelf', 'explore', 'mine'].includes(S.ui.screen);
  extraTab.replaceChildren(...EXTRA_TAB_CHOICES.map(([id, label]) => h('button', {
    'aria-pressed': S.ui.extraTab === id ? 'true' : 'false', title: id === 'none' ? '底栏只有三个页签' : `底栏第四个页签：${label}`,
    onclick: () => { S.ui.extraTab = id as typeof S.ui.extraTab; renderPreview(); }
  }, label)));
  document.querySelectorAll('#layout-seg button').forEach((b) => b.setAttribute('aria-pressed', (b as HTMLElement).dataset.l === S.ui.layout ? 'true' : 'false'));
}

function fitPhones(): void {
  const box = $('#phones');
  const cols = box.querySelectorAll('.phonebox');
  if (!cols.length) return;
  const gap = 28;
  const availW = (box.clientWidth - 32 - (cols.length - 1) * gap) / cols.length;
  // 去掉上下内边距与手机上方的“浅色 · 正在编辑”一行。
  const availH = box.clientHeight - 32 - 34;
  const scale = Math.max(0.35, Math.min(1, availW / (PHONE_W + 14), availH / (PHONE_H + 14)));
  cols.forEach((col) => {
    const phone = col.firstElementChild as HTMLElement;
    phone.style.transform = `scale(${scale})`;
    (col as HTMLElement).style.width = `${(PHONE_W + 14) * scale}px`;
    (col as HTMLElement).style.height = `${(PHONE_H + 14) * scale}px`;
  });
}

// ---- 检查器 ----

function fieldValue(key: string): any {
  if (key.startsWith('m.')) return (project().manifest as any)[key.substring(2)];
  return getPath(mp(key));
}

function setField(key: string, value: any): void {
  commit(() => {
    if (key.startsWith('m.')) (project().manifest as any)[key.substring(2)] = value;
    else setPath(mp(key), value);
  });
}

function renderInspector(): void {
  const s = section(S.ui.section);
  const box = $('#insp');
  const scroll = box.querySelector('.fields')?.scrollTop || 0;
  box.replaceChildren();
  const head = h('header', {}, h('h3', {}, s.name), h('p', {}, s.desc));
  if (s.modal) {
    const other: Mode = S.ui.mode === 'light' ? 'dark' : 'light';
    const bar = h('div', { class: 'modebar' },
      h('div', { class: 'seg' }, ...(['light', 'dark'] as Mode[]).map((m) => h('button', {
        'aria-pressed': S.ui.mode === m ? 'true' : 'false', onclick: () => { S.ui.mode = m; render(); }
      }, `编辑${MODE_LABEL[m]}`))),
      h('button', { class: 'tb small', onclick: () => copyMode(other) }, `从${MODE_LABEL[other]}复制`));
    if (S.ui.mode === 'dark' && ['colors', 'reader', 'emphasis'].includes(s.id)) {
      bar.append(h('button', { class: 'tb small', title: '保留色相，按角色重定明暗，只是初稿', onclick: () => generateDark() }, '按浅色生成深色初稿'));
    }
    head.append(bar);
  }
  box.append(head);
  const fields = h('div', { class: 'fields' });
  box.append(fields);
  if (s.id === 'assets') {
    fields.append(renderAssetLibrary());
  } else {
    let group: HTMLElement | null = null;
    for (const f of s.fields) {
      if (f.g) {
        group = h('div', { class: 'group' }, h('h5', {}, f.g));
        fields.append(group);
        continue;
      }
      if (f.when && !f.when(S.ui.mode)) continue;
      (group || fields).append(f.type === 'preserved' ? renderPreserved() : renderField(f));
    }
  }
  fields.scrollTop = scroll;
}

function renderField(f: Field): HTMLElement {
  const key = f.k as string;
  const path = mp(key);
  const value = fieldValue(key);
  const id = `f-${path.replace(/\W/g, '-')}`;
  const row = h('div', { class: 'f', 'data-key': key.startsWith('m.') ? key : path });
  if (f.type === 'covers') {
    row.classList.add('wide');
    row.append(renderCovers(f));
    return row;
  }
  // 素材槽位放不下左侧标签，标签放到槽位上方。
  if (f.type === 'asset') row.classList.add('wide');
  row.append(h('label', { for: id }, f.label));
  if (f.type === 'text' || f.type === 'textarea') {
    const input = h(f.type === 'text' ? 'input' : 'textarea', {
      id, type: f.type === 'text' ? 'text' : null, maxlength: f.max || null, spellcheck: 'false',
      onchange: (event: Event) => setField(key, (event.target as HTMLInputElement).value.trim())
    }) as HTMLInputElement;
    input.value = value || '';
    row.append(input);
  } else if (f.type === 'select') {
    const options = [...(f.options || [])];
    // 打开的包里是下拉不提供的值（例如不能作基底的主题）时照样显示出来，问题条会说明。
    if (value && !options.some(([v]) => v === value)) options.unshift([value, `${themeName(value)}（不可选）`]);
    row.append(h('select', { id, onchange: (event: Event) => setField(key, (event.target as HTMLSelectElement).value) },
      ...options.map(([v, label]) => h('option', { value: v, selected: (value || '') === v }, label))));
  } else if (f.type === 'color') {
    row.append(renderColor(f, path, value || '', id));
  } else if (f.type === 'range') {
    const base = baseValue(path);
    const current = typeof value === 'number' ? value : (typeof base === 'number' ? base : (f.fallback ?? 0));
    const out = h('output', {}, String(current));
    const range = h('input', {
      id, type: 'range', min: f.min, max: f.max, step: f.step ?? 1, value: current,
      oninput: (event: Event) => { const v = +(event.target as HTMLInputElement).value; out.textContent = String(v); liveSet(path, v); },
      onchange: () => finishLive()
    });
    row.append(h('div', { class: 'range' }, range, out, typeof value === 'number'
      ? h('button', { class: 'inherit', title: f.resetLabel ? `清空，恢复${f.resetLabel}` : '清空，沿用基底主题',
        onclick: () => setField(key, '') }, f.resetLabel || '沿用')
      : h('span', { class: 'inherit muted' }, f.resetLabel || '沿用')));
  } else if (f.type === 'asset') {
    row.append(renderSlot(f, path, value || '', id));
  }
  if (f.hint) row.append(h('div', { class: 'hint' }, f.hint));
  return row;
}

function renderColor(f: Field, path: string, value: string, id: string): HTMLElement {
  const base = baseValue(path);
  const shown = isColor(value, true) ? value : (isColor(base, true) ? base : '#000000');
  const picker = h('input', {
    type: 'color', value: `#${shown.slice(-6)}`, 'aria-label': `${f.label}取色`,
    oninput: (event: Event) => {
      const hex = (event.target as HTMLInputElement).value.toUpperCase();
      liveSet(path, f.alpha && value.length === 9 ? withAlpha(hex, alphaOf(value)) : hex);
    },
    onchange: () => finishLive()
  });
  const text = h('input', {
    id, type: 'text', value, spellcheck: 'false', placeholder: base ? `沿用 ${base}` : (f.alpha ? '#AARRGGBB' : '#RRGGBB'),
    title: f.alpha ? '#RRGGBB 或 #AARRGGBB（透明度在前）' : '#RRGGBB',
    onchange: (event: Event) => setField(path, (event.target as HTMLInputElement).value.trim().toUpperCase())
  });
  const wrap = h('div', { class: 'color' }, picker, text);
  if (f.alpha) {
    const alpha = Math.round(alphaOf(value || base || '#FF000000') / 2.55);
    wrap.append(h('input', {
      type: 'range', class: 'alpha', min: 0, max: 100, value: alpha, title: `不透明度 ${alpha}%`, 'aria-label': `${f.label}不透明度`,
      oninput: (event: Event) => {
        const pct = +(event.target as HTMLInputElement).value;
        liveSet(path, withAlpha(value || base || '#000000', pct * 2.55));
      },
      onchange: () => finishLive()
    }));
  }
  if (f.vs) {
    const fg = value || base;
    const bg = getPath(mp(f.vs)) || baseValue(mp(f.vs));
    if (isColor(fg, false) && isColor(bg, false)) {
      const ratio = contrast(fg, bg);
      wrap.append(h('span', { class: `ratio ${ratio >= 4.5 ? 'good' : 'bad'}`, title: '与底色的对比度，正文建议不低于 4.5' }, ratio.toFixed(1)));
    }
  }
  if (value) wrap.append(h('button', { class: 'inherit', title: '清空，沿用基底主题', onclick: () => setField(path, '') }, '沿用'));
  return wrap;
}

function assetThumb(asset: EditorAsset | undefined, ref: string, icon = false): HTMLElement {
  const thumb = h('div', { class: 'thumb' });
  if (!asset) return thumb;
  if (asset.kind === 'font') thumb.append(h('b', { class: 'font-thumb' }, 'Aa'));
  // 只有 SVG 图标会被应用着色；位图图标按原色显示。
  else if (icon && asset.kind === 'vector') thumb.append(h('i', { class: 'ico', style: `--m:url("${assetUrl(ref)}")` }));
  else thumb.append(h('img', { src: assetUrl(ref), alt: '' }));
  return thumb;
}

function renderSlot(f: Field, path: string, ref: string, id: string): HTMLElement {
  const p = project();
  const asset = ref ? p.assets.get(ref) : undefined;
  const warning = asset ? sizeWarning(f, asset) : '';
  const meta = h('div', { class: 'meta' },
    h('b', {}, asset ? ref.substring(7) : (ref ? `${ref.substring(7)}（缺失）` : '拖入文件，或点“上传”')),
    asset ? `${asset.width ? `${asset.width}×${asset.height} · ` : ''}${KIND_LABEL[asset.kind]} · ${formatSize(asset.bytes.length)}` : (f.spec || ''));
  if (warning) meta.append(h('span', { class: 'warnline' }, warning));
  const actions = h('div', { class: 'acts' },
    h('button', { id, onclick: () => pickFiles(f.kinds || [], false, (files) => ingest(files[0], f, (newRef) => setField(path, newRef))) }, asset ? '替换' : '上传'));
  const library = [...p.assets.values()].filter((a) => (f.kinds || []).includes(a.kind) && a.path !== ref);
  if (library.length) actions.append(h('button', { onclick: () => pickFromLibrary(library, (picked) => setField(path, picked)) }, '素材库'));
  if (asset && asset.kind === 'image' && f.target && warning) {
    actions.append(h('button', { title: `居中裁成 ${f.target[0]}×${f.target[1]}`, onclick: () => cropAsset(ref, f.target as [number, number]) }, '裁剪'));
  }
  if (ref) actions.append(h('button', { onclick: () => setField(path, '') }, '移除'));
  const slot = h('div', { class: `slot${warning ? ' warned' : ''}` }, assetThumb(asset, ref, f.icon), meta, actions);
  acceptDrop(slot, (files) => ingest(files[0], f, (newRef) => setField(path, newRef)));
  return slot;
}

function renderCovers(f: Field): HTMLElement {
  // 浅色（默认）那套 book.covers 和深色那套 book.coversDark 共用这一个格子列表。
  const listPath = f.k as string;
  const covers: string[] = (getPath(listPath) || []) as string[];
  const grid = h('div', { class: 'covers' });
  covers.forEach((ref, i) => {
    const asset = project().assets.get(ref);
    const warning = asset ? sizeWarning(f, asset) : '缺失';
    const move = (delta: number): void => commit(() => {
      const list = getPath(listPath) as string[];
      const [item] = list.splice(i, 1);
      list.splice(i + delta, 0, item);
    });
    grid.append(h('div', { class: `c${warning ? ' warned' : ''}`, title: `${ref.substring(7)}${warning ? `：${warning}` : ''}` },
      asset ? h('img', { src: assetUrl(ref), alt: `封面 ${i + 1}` }) : null,
      h('div', { class: 'c-acts' },
        i > 0 ? h('button', { onclick: () => move(-1), 'aria-label': '前移' }, '‹') : null,
        i < covers.length - 1 ? h('button', { onclick: () => move(1), 'aria-label': '后移' }, '›') : null,
        asset && warning ? h('button', { onclick: () => cropAsset(ref, f.target as [number, number]), title: '裁成 450×660' }, '裁') : null,
        h('button', { onclick: () => commit(() => (getPath(listPath) as string[]).splice(i, 1)), 'aria-label': '移除' }, '×'))));
  });
  const addCovers = (files: File[]): void => {
    const room = 8 - ((getPath(listPath) || []) as string[]).length;
    ingestMany(files.slice(0, room), { kinds: ['image'], target: f.target }, (refs) => commit(() => {
      if (!Array.isArray(getPath(listPath))) setPath(listPath, []);
      (getPath(listPath) as string[]).push(...refs);
    }));
  };
  if (covers.length < 8) {
    const add = h('button', { class: 'c add', title: '添加封面（可多选）', onclick: () => pickFiles(['image'], true, addCovers) }, '+');
    grid.append(add);
  }
  acceptDrop(grid, addCovers);
  return h('div', { class: 'covers-wrap' }, grid,
    h('div', { class: 'hint' }, `${covers.length}/8 张 · 可以一次拖入多张 · ‹ › 调整顺序`),
    f.hint ? h('div', { class: 'hint' }, f.hint) : null);
}

/** 应用导出的方案包里保留的 settings / layout / emphasis / fonts：只读展示，可以整节移除。 */
function renderPreserved(): HTMLElement {
  const p = project();
  const box = h('div', { class: 'preserved' });
  const rows: [string, string, () => void][] = [];
  if (p.settings) {
    const sources = ['customLightSources', 'customDarkSources'].map((k) => p.settings[k]).filter(Boolean);
    const from = new Set<string>();
    for (const src of sources) for (const v of Object.values(src)) if (typeof v === 'string' && v) from.add(v === 'pack:self' ? '本包' : themeName(v));
    rows.push(['方案设置', `部件来源：${from.size ? [...from].join('、') : '默认'}`, () => { p.settings = null; }]);
  }
  if (p.layout) rows.push(['阅读排版', `${Object.keys(p.layout).length} 项（字号 ${p.layout.fontSize ?? '默认'}）`, () => { p.layout = null; }]);
  if (p.emphasis) rows.push(['强调规则', `${p.emphasis.rules.length} 条，${p.emphasis.enabled ? '开启' : '关闭'}`, () => { p.emphasis = null; }]);
  if (p.fonts.length) rows.push(['字体绑定', p.fonts.map((f) => f.name || f.family).join('、'), () => { p.fonts = []; }]);
  if (!rows.length) {
    box.append(h('div', { class: 'note' }, '没有。打开应用导出的方案包时，这里会列出它的方案设置、阅读排版、强调规则和字体，导出时原样写回。'));
    return box;
  }
  for (const [title, detail, remove] of rows) {
    box.append(h('div', { class: 'prow' }, h('div', {}, h('b', {}, title), h('span', {}, detail)),
      h('button', { class: 'tb small', onclick: () => commit(remove) }, '移除')));
  }
  if (p.manifest.credits) {
    box.append(h('div', { class: 'note' }, `混搭自「${p.manifest.credits.name}」${p.manifest.credits.author ? `（${p.manifest.credits.author}）` : ''}，导出时保留署名。`));
  }
  return box;
}

function renderAssetLibrary(): HTMLElement {
  const p = project();
  const used = new Set(usedAssetPaths(p));
  const users = new Map<string, string[]>();
  for (const { field, section: s } of assetFields()) {
    if (!field.k) continue;
    for (const m of (field.k.includes('{m}') ? ['light', 'dark'] : ['']) as (Mode | '')[]) {
      const v = getPath(m ? mp(field.k, m) : field.k);
      for (const ref of (Array.isArray(v) ? v : [v]) as string[]) {
        if (!ref) continue;
        const label = `${s.name}${field.label ? `·${field.label}` : ''}${m ? `（${MODE_LABEL[m]}）` : ''}`;
        users.set(ref, [...(users.get(ref) || []), label]);
      }
    }
  }
  let total = 0;
  for (const ref of used) total += p.assets.get(ref)?.bytes.length || 0;
  const list = h('div', { class: 'group' });
  list.append(h('div', { class: 'note' }, `${p.assets.size} 个素材，导出 ${used.size} 个，约 ${formatSize(total)}（上限 48 个、80 MB）。`));
  for (const asset of [...p.assets.values()].sort((a, b) => a.path.localeCompare(b.path))) {
    const who = users.get(asset.path);
    list.append(h('div', { class: 'slot' }, assetThumb(asset, asset.path),
      h('div', { class: 'meta' }, h('b', {}, asset.path.substring(7)),
        `${KIND_LABEL[asset.kind]} · ${asset.width ? `${asset.width}×${asset.height} · ` : ''}${formatSize(asset.bytes.length)}`,
        h('span', { class: who ? 'uses' : 'warnline' }, who ? who.join('、') : (used.has(asset.path) ? '方案设置引用' : '没被引用，导出时不会打进包'))),
      h('div', { class: 'acts' }, h('button', { onclick: () => commit(() => { p.assets.delete(asset.path); }) }, '删除'))));
  }
  const add = h('button', { class: 'tb', onclick: () => pickFiles(['image', 'vector', 'font'], true, (files) => ingestMany(files, { kinds: ['image', 'vector', 'font'] }, () => render())) }, '添加素材…');
  list.append(add);
  acceptDrop(list, (files) => ingestMany(files, { kinds: ['image', 'vector', 'font'] }, () => render()));
  return list;
}

function copyMode(from: Mode): void {
  const s = section(S.ui.section);
  commit(() => {
    for (const f of s.fields) {
      if (!f.k || !f.k.includes('{m}')) continue;
      const v = getPath(mp(f.k, from));
      if (v !== undefined && v !== '') setPath(mp(f.k), structuredClone(v));
    }
  });
  toast(`已把${MODE_LABEL[from]}的${s.name}复制过来`);
}

function generateDark(): void {
  const light = effective('light');
  const draft = darkDraft({
    colors: light.c,
    reader: { backgroundColor: light.reader.backgroundColor, textColor: light.reader.textColor, subTextColor: light.reader.subTextColor, contentTone: 'light' },
    emphasis: { color: light.e.color, textColor: light.e.textColor }
  });
  commit(() => {
    for (const group of ['colors', 'reader', 'emphasis']) {
      for (const [key, value] of Object.entries(draft[group])) setPath(`dark.${group}.${key}`, value);
    }
  });
  toast('已生成深色初稿：界面配色、阅读颜色与强调色');
}

// ---- 上传素材 ----

function pickFiles(kinds: string[], multiple: boolean, done: (files: File[]) => void): void {
  const input = h('input', { type: 'file', multiple: multiple || null }) as HTMLInputElement;
  const accept: Record<string, string> = { image: '.png,.jpg,.jpeg,.webp,.gif,.bmp', vector: '.svg', font: '.ttf,.otf,.ttc' };
  input.accept = kinds.map((k) => accept[k]).join(',');
  input.onchange = () => { if (input.files && input.files.length) done([...input.files]); };
  input.click();
}

function acceptDrop(el: HTMLElement, done: (files: File[]) => void): void {
  el.addEventListener('dragover', (event) => { event.preventDefault(); event.stopPropagation(); el.classList.add('drag'); });
  el.addEventListener('dragleave', () => el.classList.remove('drag'));
  el.addEventListener('drop', (event) => {
    event.preventDefault();
    event.stopPropagation();
    el.classList.remove('drag');
    const files = event.dataTransfer ? [...event.dataTransfer.files] : [];
    if (files.length) done(files);
  });
}

/** 读文件、认格式、查 SVG、规整文件名后放进素材库；同内容的文件只存一份。 */
async function addAsset(file: File, kinds: string[]): Promise<string | null> {
  const p = project();
  const bytes = new Uint8Array(await file.arrayBuffer());
  for (const existing of p.assets.values()) {
    if (existing.bytes.length === bytes.length && existing.bytes.every((b, i) => b === bytes[i])) return existing.path;
  }
  const probe = makeAsset('assets/probe', bytes);
  if (typeof probe === 'string') {
    toast(`${file.name}：${probe}`, 'error');
    return null;
  }
  if (!kinds.includes(probe.kind)) {
    toast(`${file.name} 是${KIND_LABEL[probe.kind]}，这里需要${kinds.map((k) => KIND_LABEL[k]).join('或')}`, 'error');
    return null;
  }
  const path = safeAssetPath(file.name, probe.ext, (candidate) => p.assets.has(candidate));
  probe.path = path;
  p.assets.set(path, probe);
  return path;
}

async function ingest(file: File, f: { kinds?: string[]; target?: [number, number] }, done: (ref: string) => void): Promise<void> {
  const ref = await addAsset(file, f.kinds || []);
  if (!ref) return;
  done(ref);
  toast(`已添加 ${ref.substring(7)}`);
}

async function ingestMany(files: File[], f: { kinds?: string[]; target?: [number, number] }, done: (refs: string[]) => void): Promise<void> {
  const refs: string[] = [];
  for (const file of files) {
    const ref = await addAsset(file, f.kinds || []);
    if (ref) refs.push(ref);
  }
  if (refs.length) {
    done(refs);
    toast(`已添加 ${refs.length} 个素材`);
  }
}

/** 居中裁到目标比例并缩放到规格尺寸，原样式编码（GIF、BMP 转 PNG）。引用路径不变或随扩展名改名。 */
async function cropAsset(ref: string, target: [number, number]): Promise<void> {
  const p = project();
  const asset = p.assets.get(ref);
  if (!asset) return;
  try {
    const bitmap = await createImageBitmap(new Blob([asset.bytes as BlobPart]));
    const ratio = target[0] / target[1];
    let sw = bitmap.width;
    let sh = bitmap.height;
    if (sw / sh > ratio) sw = Math.round(sh * ratio); else sh = Math.round(sw / ratio);
    const canvas = document.createElement('canvas');
    canvas.width = target[0];
    canvas.height = target[1];
    const ctx = canvas.getContext('2d') as CanvasRenderingContext2D;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(bitmap, (bitmap.width - sw) / 2, (bitmap.height - sh) / 2, sw, sh, 0, 0, target[0], target[1]);
    const ext = asset.ext === 'jpg' || asset.ext === 'webp' ? asset.ext : 'png';
    const mime = ext === 'jpg' ? 'image/jpeg' : `image/${ext}`;
    const blob: Blob = await new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('编码失败'))), mime, 0.92));
    const bytes = new Uint8Array(await blob.arrayBuffer());
    const newPath = ext === asset.ext ? ref : safeAssetPath(ref.substring(7), ext, (c) => p.assets.has(c));
    const made = makeAsset(newPath, bytes);
    if (typeof made === 'string') throw new Error(made);
    commit(() => {
      p.assets.delete(ref);
      p.assets.set(newPath, made);
      if (newPath !== ref) {
        const swap = (v: any): any => (v === ref ? newPath : Array.isArray(v) ? v.map(swap) : v && typeof v === 'object' ? (Object.keys(v).forEach((k) => { v[k] = swap(v[k]); }), v) : v);
        swap(p.parts);
      }
    });
    toast(`已裁成 ${target[0]}×${target[1]}`);
  } catch (error) {
    toast(`裁剪失败：${(error as Error).message}`, 'error');
  }
}

function pickFromLibrary(list: EditorAsset[], done: (ref: string) => void): void {
  const close = modal('从素材库选择', h('div', { class: 'choice lib' }, ...list.map((asset) => h('button', {
    onclick: () => { close(); done(asset.path); }
  }, asset.kind === 'font' ? h('b', { class: 'font-thumb' }, 'Aa') : h('img', { src: assetUrl(asset.path), alt: '' }), h('span', {}, asset.path.substring(7))))),
  [['取消', () => close()]]);
}

// ---- 对话框 ----

function modal(title: string, body: HTMLElement, buttons: [string, () => void, boolean?][]): () => void {
  const dialog = h('dialog', { class: 'dlg' }) as HTMLDialogElement;
  const close = (): void => { dialog.close(); dialog.remove(); };
  dialog.append(h('header', {}, h('h3', {}, title)), h('div', { class: 'content' }, body),
    h('footer', {}, ...buttons.map(([label, action, primary]) => h('button', { class: `tb${primary ? ' primary' : ''}`, onclick: action }, label))));
  dialog.addEventListener('cancel', (event) => { event.preventDefault(); close(); });
  document.body.append(dialog);
  dialog.showModal();
  return close;
}

function confirmDiscard(): Promise<boolean> {
  if (!S.project || !S.doc.dirty) return Promise.resolve(true);
  return new Promise((resolve) => {
    const close = modal('有未保存的更改', h('p', {}, '当前主题还没保存，继续会丢掉这些更改。'), [
      ['取消', () => { close(); resolve(false); }],
      ['不保存，继续', () => { close(); resolve(true); }, true]
    ]);
  });
}

// ---- 打开、保存、导出 ----

function setProject(p: EditorProject, doc: Partial<typeof S.doc>): void {
  S.project = p;
  S.doc = { filePath: null, fileName: '', dirty: false, problems: [], ...doc };
  undoStack.length = 0;
  redoStack.length = 0;
  strict = null;
  S.ui.section = 'meta';
  S.ui.screen = 'card';
  api.setDirty(S.doc.dirty);
  showEditor();
  render();
}

async function openTarget(target: OpenedTarget): Promise<void> {
  let files: FileMap;
  if (target.kind === 'folder') files = new Map(target.files || []);
  else files = readZip(target.bytes as Uint8Array);
  const { project: p, problems } = await loadProject(files);
  // 只有严格通过的格式 2 包才允许 Ctrl+S 直接覆盖；应用导出的格式 1 包和文件夹走另存为，原文件不动。
  const overwrite = target.kind === 'zip' && !problems.length && p.sourceFormatVersion >= 2;
  setProject(p, { filePath: overwrite ? target.path : null, fileName: target.name, problems });
  if (problems.length) toast(`已打开，但有问题要修：${problems[0]}`, 'error');
  else if (p.sourceFormatVersion < 2) toast('这是应用导出的旧格式方案包，保存时会另存为格式 2');
  else toast(`已打开 ${target.name}`);
}

async function openFromDialog(folder: boolean): Promise<void> {
  if (!(await confirmDiscard())) return;
  try {
    const target = await call(api.openDialog(folder));
    if (target) await openTarget(target);
  } catch (error) {
    toast(`打不开：${(error as Error).message}`, 'error');
  }
}

async function openPath(path: string): Promise<void> {
  if (!(await confirmDiscard())) return;
  try {
    await openTarget(await call(api.openPath(path)));
  } catch (error) {
    toast(`打不开：${(error as Error).message}`, 'error');
  }
}

async function openDroppedFile(file: File): Promise<void> {
  if (!(await confirmDiscard())) return;
  try {
    await openTarget({ path: '', name: file.name, kind: 'zip', bytes: new Uint8Array(await file.arrayBuffer()) });
  } catch (error) {
    toast(`打不开：${(error as Error).message}`, 'error');
  }
}

function packageFileName(): string {
  const name = (project().manifest.name || '主题').replace(/[\\/:*?"<>|]/g, '_').trim() || '主题';
  return `${name}.qytheme`;
}

async function save(saveAs: boolean): Promise<void> {
  if (!S.project) return;
  if (allIssues().some((i) => i.level === 'error')) {
    toast('还有错误没改完，先看底部的问题条', 'error');
    return;
  }
  try {
    const zip = await exportZip(project());
    const path = await call(api.saveFile(saveAs ? null : S.doc.filePath, packageFileName(), zip));
    if (!path) return;
    S.doc.filePath = path;
    S.doc.fileName = path.split(/[\\/]/).pop() || path;
    S.doc.dirty = false;
    S.doc.problems = [];
    project().sourceFormatVersion = 2;
    api.setDirty(false);
    await call(api.clearDraft());
    render();
    toast(`已保存 ${S.doc.fileName}（${formatSize(zip.length)}）`);
  } catch (error) {
    toast(`保存失败：${(error as Error).message}`, 'error');
  }
}

async function showExport(): Promise<void> {
  let files: FileMap;
  try {
    files = await exportFiles(project());
  } catch (error) {
    toast(`不能导出：${(error as Error).message}`, 'error');
    return;
  }
  const names = [...files.keys()].filter((n) => n.startsWith('assets/')).sort();
  const total = [...files.values()].reduce((sum, b) => sum + b.length, 0);
  const tree = [`${packageFileName()}`, '├── manifest.json', '├── theme.json', `└── assets/${names.length ? '' : '（空）'}`,
    ...names.map((n, i) => `    ${i === names.length - 1 ? '└──' : '├──'} ${n.substring(7).padEnd(26)} ${formatSize(files.get(n)!.length).padStart(8)}`)].join('\n');
  const manifest = new TextDecoder().decode(files.get('manifest.json'));
  const theme = new TextDecoder().decode(files.get('theme.json'));
  const pre = h('pre', { class: 'json' });
  const tabs = h('div', { class: 'seg' });
  const show = (which: 'm' | 't'): void => {
    pre.textContent = which === 'm' ? manifest : theme;
    tabs.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', (b as HTMLElement).dataset.w === which ? 'true' : 'false'));
  };
  tabs.append(h('button', { 'data-w': 'm', onclick: () => show('m') }, 'manifest.json'), h('button', { 'data-w': 't', onclick: () => show('t') }, 'theme.json'));
  show('t');
  const requires = JSON.parse(manifest).requires.join('、');
  const body = h('div', { class: 'cols' },
    h('div', { class: 'side' }, h('div', { class: 'tree' }, tree),
      h('div', { class: 'note' }, `${names.length} 个素材 · 解压后约 ${formatSize(total)}`, h('br'), `requires：${requires}`, h('br'), '已用应用的格式层解码一遍：通过')),
    h('div', { class: 'main' }, tabs, pre));
  const close = modal('导出主题包', body, [
    ['取消', () => close()],
    ['导出为文件夹…', async () => { close(); await exportFolder(files); }],
    ['另存为 .qytheme…', async () => { close(); await save(true); }, true]
  ]);
}

async function exportFolder(prepared?: FileMap): Promise<void> {
  try {
    const files = prepared || await exportFiles(project());
    const name = packageFileName().replace(/\.qytheme$/, '');
    const dir = await call(api.exportFolder(name, [...files.entries()]));
    if (dir) toast(`已导出到 ${dir}`);
  } catch (error) {
    toast(`导出失败：${(error as Error).message}`, 'error');
  }
}

async function newDocument(): Promise<void> {
  if (!(await confirmDiscard())) return;
  const select = h('select', { id: 'new-base' }, ...baseThemeOptions().map(([id, label]) => h('option', { value: id }, label))) as HTMLSelectElement;
  const name = h('input', { id: 'new-name', type: 'text', maxlength: 24, placeholder: '例如：夜花园' }) as HTMLInputElement;
  const create = (): void => {
    close();
    const p = newProject(select.value);
    p.manifest.name = name.value.trim();
    setProject(p, { fileName: '' });
  };
  const close = modal('新建主题', h('div', { class: 'form' },
    h('div', { class: 'f' }, h('label', { for: 'new-name' }, '名称'), name),
    h('div', { class: 'f' }, h('label', { for: 'new-base' }, '基底主题'), select),
    h('div', { class: 'note' }, '所有部件先沿用基底主题，你改哪个部件就只有哪个部件进包。预览只显示基底主题的配色，它的图片在应用里才看得到。')),
  [['取消', () => close()], ['创建', create, true]]);
  name.focus();
}

// ---- 草稿 ----

async function saveDraft(): Promise<void> {
  if (!S.project || !S.doc.dirty) return;
  try {
    await call(api.saveDraft(serializeDraft(project(), { fileName: S.doc.fileName, filePath: S.doc.filePath, time: Date.now() })));
  } catch (_) {
    // 草稿只是兜底，写不进去不打扰编辑。
  }
}

// ---- 欢迎页 ----

function showEditor(): void {
  $('#welcome').hidden = true;
  $('#editor').hidden = false;
}

async function showWelcome(): Promise<void> {
  $('#editor').hidden = true;
  const box = $('#welcome');
  box.hidden = false;
  const actions = h('div', { class: 'choice' },
    h('button', { onclick: () => newDocument() }, h('b', {}, '新建主题'), h('span', {}, '选一个内置主题作基底，从配色开始改')),
    h('button', { onclick: () => openFromDialog(false) }, h('b', {}, '打开主题包…'), h('span', {}, '.qytheme 或 .zip，应用导出的和手写的都行')),
    h('button', { onclick: () => openFromDialog(true) }, h('b', {}, '打开主题文件夹…'), h('span', {}, '含 manifest.json、theme.json 和 assets/ 的文件夹')));
  const body = h('div', { class: 'welcome-inner' },
    h('h1', {}, '轻页主题编辑器'),
    h('p', { class: 'lead' }, '为开源轻页制作 .qytheme 主题包：上传素材、调配色，浅色和深色同时预览，导出后在手机上导入即可使用。'),
    actions);
  try {
    const draft = await call(api.loadDraft());
    if (draft) {
      const { project: p, meta } = deserializeDraft(draft);
      const when = meta && meta.time ? new Date(meta.time).toLocaleString() : '';
      body.append(h('div', { class: 'draft' }, h('div', {}, h('b', {}, '有一份没保存的编辑'), h('span', {}, `${p.manifest.name || meta.fileName || '未命名主题'}${when ? ` · ${when}` : ''}`)),
        h('button', { class: 'tb primary', onclick: () => setProject(p, { fileName: meta.fileName || '', filePath: meta.filePath || null, dirty: true }) }, '恢复'),
        h('button', { class: 'tb', onclick: async () => { await call(api.clearDraft()); showWelcome(); } }, '丢弃')));
    }
  } catch (_) {
    // 草稿损坏时当作没有。
  }
  try {
    const recent = (await call(api.recent())).filter((r) => r.exists);
    if (recent.length) {
      body.append(h('h4', {}, '最近打开'), h('ul', { class: 'recent-list' }, ...recent.map((r) => h('li', {},
        h('button', { onclick: () => openPath(r.path) }, h('b', {}, r.name), h('span', {}, r.path))))));
    }
  } catch (_) {
    // 没有最近记录。
  }
  box.replaceChildren(body);
}

// ---- 启动 ----

function bindChrome(): void {
  $('#btn-new').onclick = () => newDocument();
  $('#btn-open').onclick = () => openFromDialog(false);
  $('#btn-open-folder').onclick = () => openFromDialog(true);
  $('#btn-undo').onclick = () => undo(undoStack, redoStack);
  $('#btn-redo').onclick = () => undo(redoStack, undoStack);
  $('#btn-save').onclick = () => save(false);
  $('#btn-folder').onclick = () => exportFolder();
  $('#btn-export').onclick = () => showExport();
  $('#layout-seg').addEventListener('click', (event) => {
    const b = (event.target as HTMLElement).closest('button') as HTMLElement | null;
    if (b && b.dataset.l) {
      S.ui.layout = b.dataset.l as 'both' | 'one';
      renderPreview();
    }
  });
  document.addEventListener('keydown', (event) => {
    if (!(event.ctrlKey || event.metaKey) || document.querySelector('dialog[open]')) return;
    const key = event.key.toLowerCase();
    const target = event.target;
    const inText = target instanceof Element && target.matches('input[type=text],textarea');
    if (key === 'n') { event.preventDefault(); newDocument(); }
    else if (key === 'o') { event.preventDefault(); openFromDialog(event.shiftKey); }
    if (!S.project || $('#editor').hidden) return;
    if (key === 's') { event.preventDefault(); save(event.shiftKey); }
    else if (key === 'e') { event.preventDefault(); showExport(); }
    else if (key === 'z' && !event.shiftKey && !inText) { event.preventDefault(); undo(undoStack, redoStack); }
    else if ((key === 'y' || (key === 'z' && event.shiftKey)) && !inText) { event.preventDefault(); undo(redoStack, undoStack); }
  });
  // 把主题包拖进窗口任意位置即打开；拖到素材槽位的由槽位自己处理。
  document.addEventListener('dragover', (event) => event.preventDefault());
  document.addEventListener('drop', (event) => {
    event.preventDefault();
    const file = event.dataTransfer && event.dataTransfer.files[0];
    if (!file) return;
    if (/\.(qytheme|zip)$/i.test(file.name)) openDroppedFile(file);
    else if (S.project && !$('#editor').hidden) toast('把素材拖到右侧对应的槽位上，或拖进素材库');
  });
  window.addEventListener('resize', () => { if (S.project) fitPhones(); });
  window.setInterval(saveDraft, 15000);
  window.addEventListener('beforeunload', () => { void saveDraft(); });
}

async function start(): Promise<void> {
  bindChrome();
  try {
    const launch = await call(api.launchFile());
    if (launch) {
      await openTarget(await call(api.openPath(launch)));
      return;
    }
  } catch (error) {
    toast(`打不开：${(error as Error).message}`, 'error');
  }
  await showWelcome();
}

start();
