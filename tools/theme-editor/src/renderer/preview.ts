// 实时预览：按应用的布局重画书架、阅读页、朗读面板、启动封面和主题卡片。手机按 360 × 780 vp 绘制再整体缩放。
// 阅读角饰尺寸取 ReaderThemeDecorationLayout（短边 × 0.36，夹在 112–260），朗读面板的分层取 TtsPanelThemeBackground。
import { assetFontFamily, assetUrl, h, project, S, type Mode } from './state.ts';
import { baseTheme, bubbleLabel, effective, GENERIC_BUBBLES, type Effective } from './tokens.ts';
import { cssColor, luminance } from './colors.ts';
import { NAV_TABS, EXTRA_NAV_TABS } from './sections.ts';

export const PHONE_W = 360;
export const PHONE_H = 780;
const ORNAMENT = Math.max(112, Math.min(260, PHONE_W * 0.36));
const ORNAMENT_INSET = Math.max(8, Math.min(22, PHONE_W * 0.025));

const svgUrl = (svg: string): string => `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
const DEFAULT_NAV: Record<string, string> = {
  bookshelf: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M4 3h4v18H4zM10 3h4v18h-4zM16.5 4.2l3.8-1 3.2 16.6-3.8 1z"/></svg>',
  explore: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm4.5 5.5-2.8 6.2-6.2 2.8 2.8-6.2z"/></svg>',
  mine: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 3a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9zM3 21c0-4.4 4-7 9-7s9 2.6 9 7z"/></svg>',
  listen: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 3.5A8.5 8.5 0 0 0 3.5 12v2.2h1.6V12a6.9 6.9 0 0 1 13.8 0v2.2h1.6V12A8.5 8.5 0 0 0 12 3.5zM5.5 13h1a2 2 0 0 1 2 2v3.5a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2V15a2 2 0 0 1 2-2zm12 0h1a2 2 0 0 1 2 2v3.5a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2V15a2 2 0 0 1 2-2z"/></svg>',
  footprint: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M4.7 11.5h2.6a1.2 1.2 0 0 1 1.2 1.2v6.6a1.2 1.2 0 0 1-1.2 1.2H4.7a1.2 1.2 0 0 1-1.2-1.2v-6.6a1.2 1.2 0 0 1 1.2-1.2zm6-8h2.6a1.2 1.2 0 0 1 1.2 1.2v14.6a1.2 1.2 0 0 1-1.2 1.2h-2.6a1.2 1.2 0 0 1-1.2-1.2V4.7a1.2 1.2 0 0 1 1.2-1.2zm6 4h2.6a1.2 1.2 0 0 1 1.2 1.2v10.6a1.2 1.2 0 0 1-1.2 1.2h-2.6a1.2 1.2 0 0 1-1.2-1.2V8.7a1.2 1.2 0 0 1 1.2-1.2z"/></svg>'
};

/** 沿用基底主题的图片：编辑器不带内置素材，画成占位并写明来源。 */
function placeholder(label: string, cls = ''): HTMLElement {
  return h('div', { class: `ph ${cls}` }, h('span', {}, label));
}

const usesBaseArt = (): boolean => baseTheme().id !== 'plain-default';

function themeVars(mode: Mode, e: Effective): string {
  const c = e.c;
  const r = e.reader;
  const vars: Record<string, string> = {
    '--p-page': c.pageColor, '--p-card': c.cardColor, '--p-input': c.inputColor, '--p-text': c.primaryTextColor,
    '--p-sub': c.subTextColor, '--p-divider': c.dividerColor, '--p-accent': c.accentColor, '--p-button': c.buttonColor,
    '--p-danger': c.dangerColor, '--p-rbg': r.backgroundColor, '--p-rtext': r.textColor, '--p-rsub': r.subTextColor,
    '--p-em': cssColor(e.e.color), '--p-em-text': cssColor(e.e.textColor)
  };
  for (const [key, value] of Object.entries(e.radius)) vars[`--p-r-${key}`] = `${value}px`;
  if (e.tts) {
    vars['--p-tsky'] = e.tts.skyColor;
    vars['--p-tsurf'] = e.tts.surfaceColor;
    vars['--p-tglow'] = cssColor(e.tts.glowColor);
  } else {
    vars['--p-tsky'] = c.cardColor;
    vars['--p-tsurf'] = c.pageColor;
    vars['--p-tglow'] = 'transparent';
  }
  const p = project().parts;
  const packFont = assetFontFamily(p.typography && p.typography.appFont);
  const family = packFont || (p.typography && p.typography.appFontFamily) || '';
  if (family) vars['--p-font'] = `"${family}", var(--f-ui)`;
  void mode;
  return Object.entries(vars).map(([k, v]) => `${k}:${v}`).join(';');
}

function statusBar(darkContent: boolean): HTMLElement {
  return h('div', { class: 'statusbar', style: `color:${darkContent ? '#FFFFFF' : '#111111'}` },
    h('span', {}, '9:41'), h('span', { class: 'sb-icons' }, h('i'), h('i'), h('b')));
}

/**
 * 动图取景记下的显示区域（book.coverCrops、book.shelfFolderCrop、homeBackdrop.lightCrop / darkCrop）换成 CSS，
 * 效果同应用的 ThemeCroppedImage：区域等比盖满、居中、裁掉多余。区域不属于这张图时返回空串。
 */
function cropStyle(crop: any, ref: string): string {
  if (!crop || !ref || crop.image !== ref) return '';
  const { x, y, width, height, imageWidth, imageHeight } = crop;
  if (!(imageWidth > 0 && imageHeight > 0 && width > 0 && height > 0)) return '';
  const pct = (value: number, total: number): string => `${Math.max(0, value / total * 100).toFixed(4)}%`;
  return `object-fit:cover;object-view-box:inset(${pct(y, imageHeight)} ${pct(imageWidth - x - width, imageWidth)} ` +
    `${pct(imageHeight - y - height, imageHeight)} ${pct(x, imageWidth)});`;
}

function coverCropStyle(book: any, ref: string): string {
  const crops: any[] = Array.isArray(book.coverCrops) ? book.coverCrops : [];
  return cropStyle(crops.find((crop) => crop && crop.image === ref), ref);
}

const BOOKS: [string, string][] = [['山海拾遗', '读到 12%'], ['夜航船', '读到 58%'], ['长安客', '未读'], ['北窗', '读到 3%'], ['雾港来信', '更新 2 章']];

function coverTile(index: number, title: string): HTMLElement {
  const book = project().parts.book || {};
  const covers: string[] = (book.covers || []).filter((ref: string) => assetUrl(ref));
  const frame = assetUrl(book.shelfFrame);
  const tile = h('div', { class: 'bk', 'data-sec': 'book' });
  if (covers.length) {
    const ref = covers[index % covers.length];
    tile.append(h('img', { class: 'cv', src: assetUrl(ref), alt: '', style: coverCropStyle(book, ref) }), h('div', { class: 'ttl' }, title));
  } else if (usesBaseArt()) {
    tile.append(placeholder(`沿用「${baseTheme().name}」封面`, 'fill'));
  } else {
    tile.append(h('div', { class: 'plain' }, h('b', {}, title)));
  }
  if (frame) tile.append(h('img', { class: 'fr', src: frame, alt: '' }));
  return tile;
}

/** 底栏一个页签的图标：SVG 用遮罩按文字色着色，位图原样显示，和应用一致。 */
function navIcon(key: string, selected: boolean): HTMLElement {
  const nav = project().parts.navigation || {};
  const ref = (selected && nav[`${key}Selected`]) || nav[key] || '';
  const url = assetUrl(ref);
  if (url && project().assets.get(ref)?.kind === 'image') return h('img', { class: 'ico', src: url, alt: '' });
  return h('i', { class: 'ico', style: `--m:url("${url || svgUrl(DEFAULT_NAV[key])}")` });
}

/**
 * 首页背景（HomeThemeBackdrop）：贴顶、4:5 铺满宽度，向下淡成页面底色。书架整张显示；发现、我的只衬标题区，
 * 高度和不透明度取各页传给组件的值，渐变停点照搬组件。浅深色不互相借用。
 */
function homeBackdrop(mode: Mode, e: Effective, visibleHeight: number, strength: number): HTMLElement | null {
  const parts = project().parts.homeBackdrop || {};
  const url = assetUrl(parts[mode]);
  if (!url) return null;
  const crop = cropStyle(parts[`${mode}Crop`], parts[mode]);
  const stops = mode === 'dark' ? [[0.25, 0], [0.55, 38], [0.9, 70], [1, 100]] : [[0.1, 0], [0.3, 38], [0.85, 72], [1, 100]];
  const gradient = stops.map(([a, at]) => `color-mix(in srgb, ${e.c.pageColor} ${Math.round(a * 100)}%, transparent) ${at}%`).join(', ');
  return h('div', { class: 'hbg', 'data-sec': 'homeBackdrop', style: visibleHeight ? `height:${visibleHeight}px` : 'aspect-ratio:4 / 5' },
    h('img', { src: url, alt: '', style: `opacity:${strength};${crop}` }), h('i', { style: `background:linear-gradient(${gradient})` }));
}

/** 首页三个页签共用的骨架：背景、状态栏、内容、底栏（当前页签用选中态图标）。 */
function homeScreen(mode: Mode, e: Effective, tab: number, cls: string, backdrop: HTMLElement | null, ...content: HTMLElement[]): HTMLElement {
  const s = h('div', { class: `scr home ${cls}` });
  if (backdrop) s.append(backdrop);
  s.append(statusBar(luminance(e.c.pageColor) < 0.25));
  s.append(h('div', { class: 'home-body' }, ...content));
  const nav = project().parts.navigation || {};
  const iconsOnly = nav.labels === 'hidden' && !!nav.bookshelf;
  const bar = h('div', { class: `navbar${iconsOnly ? ' icons-only' : ''}`, 'data-sec': 'nav' });
  // 第四个页签排在“我的”前面；包里没给它的图标时应用用基底主题的，这里画默认图标。
  const selectedKey = NAV_TABS[tab][0];
  const extra = EXTRA_NAV_TABS.find(([key]) => key === S.ui.extraTab);
  const tabs = extra ? [NAV_TABS[0], NAV_TABS[1], extra, NAV_TABS[2]] : NAV_TABS;
  tabs.forEach(([key, label]) => {
    bar.append(h('div', { class: `it${key === selectedKey ? ' on' : ''}` }, navIcon(key, key === selectedKey), iconsOnly ? null : label));
  });
  s.append(bar);
  return s;
}

function folderArt(): HTMLElement {
  const book = project().parts.book || {};
  const folder = assetUrl(book.shelfFolder);
  if (folder) return h('img', { class: 'cv', src: folder, alt: '', style: cropStyle(book.shelfFolderCrop, book.shelfFolder) });
  return usesBaseArt() ? placeholder(`沿用「${baseTheme().name}」文件夹`, 'fill') : h('div', { class: 'plain folder' }, h('b', {}, '分组'));
}

function shelfHeader(): HTMLElement[] {
  return [
    h('div', { class: 'hd', 'data-sec': 'colors' }, h('b', {}, '书架'), h('span', { class: 'hd-acts' }, '整理', h('i', { class: 'dots' }))),
    h('div', { class: 'search', 'data-sec': 'colors' }, '搜索书架里的书')
  ];
}

/** 平铺：上次阅读卡 + 三列封面网格，分组是一张文件夹插画。 */
function shelfTile(): HTMLElement[] {
  const recentCover = coverTile(1, '夜航船');
  recentCover.classList.add('mini');
  const grid = h('div', { class: 'grid' });
  BOOKS.forEach(([title, sub], i) => grid.append(h('div', { class: 'cell' }, coverTile(i, title), h('div', { class: 'gname' }, title), h('div', { class: 'gsub' }, sub))));
  grid.append(h('div', { class: 'cell' }, h('div', { class: 'bk', 'data-sec': 'book' }, folderArt()), h('div', { class: 'gname' }, '收藏夹'), h('div', { class: 'gsub' }, '8 本')));
  return [...shelfHeader(),
    h('div', { class: 'recent', 'data-sec': 'colors' }, recentCover,
      h('div', { class: 'rc-body' }, h('div', { class: 't' }, '夜航船'), h('div', { class: 's' }, '第十七章 · 灯下'), h('div', { class: 'bar' }, h('i'))),
      h('span', { class: 'go' }, '继续阅读')),
    h('div', { class: 'sec-title', 'data-sec': 'colors' }, '全部书籍', h('span', {}, '6')),
    grid];
}

const LIST_BOOKS: [string, string, string, string][] = [
  ['夜航船', '张岱', '最新：第二百零三章 归舟', '读到 58%'], ['山海拾遗', '佚名', '最新：卷九 大荒北经', '读到 12%'],
  ['长安客', '沈三白', '已完结 · 共 86 章', '未读'], ['北窗', '林间', '更新 2 章：第四十一章 雪夜', '读到 3%'], ['雾港来信', '海生', '最新：番外 灯塔', '读到 91%']
];

/** 紧凑 / 宽松：一本一张卡片，封面按 7:9 跟着信息块高度走；宽松多一行、进度单独成行。 */
function shelfList(loose: boolean): HTMLElement[] {
  const rows = h('div', { class: `list${loose ? ' loose' : ''}` });
  LIST_BOOKS.forEach(([title, author, update, progress], i) => {
    const cover = coverTile(i, title);
    cover.classList.add('lc');
    rows.append(h('div', { class: 'row-card', 'data-sec': 'colors' }, cover,
      h('div', { class: 'row-info' }, h('b', {}, title), h('span', {}, author), h('span', {}, update),
        loose ? h('span', { class: 'prog-line' }, progress) : h('span', { class: 'prog-tag' }, progress))));
  });
  return [...shelfHeader(), rows];
}

/** 精装书：深色底板 + 书页 + 封面压槽，和应用陪伴布局的 shelfHardcoverBook 同一套层次。 */
function hardcover(index: number, title: string, scale = 1, lean = 0, art?: HTMLElement): HTMLElement {
  const book = h('div', { class: 'hc', 'data-sec': 'book', style: `--s:${scale};transform:rotate(${lean}deg)` });
  const cover = art ? h('div', { class: 'bk hc-cover' }, art) : coverTile(index, title);
  cover.classList.add('hc-cover');
  book.append(h('i', { class: 'hc-board' }), h('i', { class: 'hc-pages' }), cover, h('i', { class: 'hc-spine' }));
  return book;
}

/**
 * 陪伴：问候、继续阅读大卡（立体书）、阅读小记，下面是错落的精装书网格；分组是文件夹插画做封面的精装书。
 * 配色跟应用 BookshelfPage 的 shelfCompanionGreeting / shelfCompanionHeroCard 与 ShelfReadingNoteCard 一致：
 * 问候大字、书名、“继续阅读”、小记标题与今日分钟数用强调色，“继续阅读”是强调色 10% 底的胶囊（不用按钮色）。
 */
function shelfCompanion(): HTMLElement[] {
  const hero = h('div', { class: 'cp-hero', 'data-sec': 'colors' }, hardcover(1, '夜航船'),
    h('div', { class: 'cp-info' }, h('b', {}, '夜航船'), h('small', {}, '张岱 著'), h('i', { class: 'gap' }),
      h('small', {}, '上次读到 · 今天 20:50'), h('span', { class: 'ch' }, '68/524 · 第十七章 灯下'),
      h('span', { class: 'go' }, '继续阅读 →')));
  const days = [22, 40, 15, 0, 55, 30, 46];
  const note = h('div', { class: 'cp-note', 'data-sec': 'colors' },
    h('div', { class: 'cp-note-hd' }, h('b', {}, '阅读小记'), h('span', {}, '阅读统计 ›')),
    h('div', { class: 'cp-note-bd' },
      h('div', { class: 'cp-today' }, h('small', {}, '今日阅读'), h('div', {}, h('b', {}, '46'), h('span', {}, '分钟'))),
      h('div', { class: 'cp-trend' },
        h('div', { class: 'cp-bars' }, ...days.map((m, i) => h('i', { class: i === days.length - 1 ? 'today' : '', style: `height:${Math.max(8, m * 1.6)}%` }))),
        h('span', {}, '近 7 天 3小时28分 · 已连续读了 5 天'))));
  const scales = [1, 0.94, 0.9, 0.97, 0.88];
  const leans = [0, -2, 0, 2.5, 0];
  const grid = h('div', { class: 'grid cp-grid' });
  BOOKS.forEach(([title, sub], i) => grid.append(h('div', { class: 'cell' }, hardcover(i, title, scales[i], leans[i]),
    h('div', { class: 'gname' }, title), h('div', { class: 'gsub' }, sub))));
  grid.append(h('div', { class: 'cell' }, hardcover(0, '收藏夹', 1, 0, folderArt()), h('div', { class: 'gname' }, '收藏夹'), h('div', { class: 'gsub' }, '8 本')));
  return [
    h('div', { class: 'hd cp-top' }, h('span'), h('span', { class: 'hd-acts' }, h('i', { class: 'folder-ico' }), h('i', { class: 'dots' }))),
    h('div', { class: 'cp-greet', 'data-sec': 'colors' }, h('b', {}, '晚上好，慢慢读。'), h('span', {}, '泡杯茶，故事还在原处等你。')),
    hero, note,
    h('div', { class: 'sec-title cp-sec', 'data-sec': 'colors' }, '书架里，还有故事', h('span', {}, `共 ${BOOKS.length} 本`)),
    grid];
}

function screenShelf(mode: Mode, e: Effective): HTMLElement {
  const layout = S.ui.shelfLayout;
  const content = layout === 'companion' ? shelfCompanion() : layout === 'tile' ? shelfTile() : shelfList(layout === 'loose');
  return homeScreen(mode, e, 0, `shelf shelf-${layout}`, homeBackdrop(mode, e, 0, 1), ...content);
}

function screenExplore(mode: Mode, e: Effective): HTMLElement {
  const chips = ['推荐', '玄幻', '历史', '悬疑', '言情', '出版'];
  const books: [string, string][] = [['长夜渡', '一叶舟 · 古风'], ['星海归航', '北辰 · 科幻'], ['旧城往事', '林间 · 都市'], ['青灯志异', '佚名 · 悬疑']];
  const list = h('div', { class: 'ex-list' });
  books.forEach(([title, meta], i) => list.append(h('div', { class: 'row-card', 'data-sec': 'colors' }, coverTile(i + 2, title),
    h('div', { class: 'row-info' }, h('b', {}, title), h('span', {}, meta), h('span', {}, '一句话简介：风起于青萍之末。')))));
  return homeScreen(mode, e, 1, 'explore', homeBackdrop(mode, e, 30 + 250, 0.7),
    h('div', { class: 'hd', 'data-sec': 'colors' }, h('b', {}, '发现'), h('span', { class: 'hd-acts' }, '书源')),
    h('div', { class: 'chips', 'data-sec': 'colors' }, ...chips.map((c, i) => h('span', { class: i === 0 ? 'on' : '' }, c))),
    h('div', { class: 'sec-title', 'data-sec': 'colors' }, '本周热读'),
    list);
}

function screenMine(mode: Mode, e: Effective): HTMLElement {
  const group = (rows: string[]): HTMLElement => h('div', { class: 'mine-group', 'data-sec': 'colors' },
    ...rows.map((r) => h('div', {}, r, h('i', { class: 'chev' }))));
  return homeScreen(mode, e, 2, 'mine', homeBackdrop(mode, e, 30 + 330, 0.85),
    h('div', { class: 'profile', 'data-sec': 'colors' }, h('i', { class: 'avatar' }),
      h('div', {}, h('b', {}, '书友 0571'), h('span', {}, '已读 128 本 · 累计 312 小时'))),
    h('div', { class: 'stats', 'data-sec': 'colors' }, ...[['46', '今日分钟'], ['5', '连续天数'], ['12', '本月本数']].map(([v, l]) => h('div', {}, h('b', {}, v), h('span', {}, l)))),
    group(['主题', '阅读设置', '朗读与有声书']),
    group(['书源管理', '同步与备份', '帮助']));
}

function emphasis(text: string, e: Effective): HTMLElement | string {
  if (e.e.mode === 'none') return text;
  if (e.e.mode === 'bubble') {
    const bubble = project().parts.bubble || {};
    const span = h('span', { class: 'em-bubble', 'data-sec': 'emphasis' });
    if (e.e.bubble === 'pack') {
      const cap = assetUrl(bubble.cap);
      const frame = assetUrl(bubble.frame);
      if (frame) span.style.cssText = `background-image:url("${frame}");background-size:100% 100%`;
      if (cap) span.append(h('img', { class: 'bcap', src: cap, alt: '' }));
      span.append(text);
      if (cap) span.append(h('img', { class: 'bcap r', src: cap, alt: '' }));
    } else {
      span.append(text);
      span.title = `气泡样式：${bubbleLabel(e.e.bubble)}${GENERIC_BUBBLES.includes(e.e.bubble) ? '' : '（主题专属，端饰在应用内显示）'}`;
    }
    return span;
  }
  return h('span', { class: e.e.mode === 'highlight' ? 'em-highlight' : 'em-text', 'data-sec': 'emphasis' }, text);
}

function readerBody(e: Effective): HTMLElement {
  const r = e.reader;
  const p = project();
  const s = h('div', { class: 'scr reader', 'data-sec': 'reader' });
  if (r.source === 'pack' && r.mode === 'image') {
    const url = assetUrl(r.image);
    if (url) s.append(h('img', { class: 'bgimg', src: url, style: `object-fit:${r.imageFit === 'fill' ? 'fill' : r.imageFit}`, alt: '' }));
  } else if (r.source === 'pack' && r.mode === 'ornaments') {
    const style = `width:${ORNAMENT}px;height:${ORNAMENT}px`;
    if (assetUrl(r.leading)) s.append(h('img', { class: 'orn l', src: assetUrl(r.leading), style: `${style};left:${ORNAMENT_INSET}px;top:${ORNAMENT_INSET}px`, alt: '' }));
    if (assetUrl(r.trailing)) s.append(h('img', { class: 'orn t', src: assetUrl(r.trailing), style: `${style};right:${ORNAMENT_INSET}px;bottom:${ORNAMENT_INSET}px`, alt: '' }));
  } else if (r.source === 'base-art') {
    const style = `width:${ORNAMENT}px;height:${ORNAMENT}px`;
    s.append(h('div', { class: 'orn-ph', style: `${style};left:${ORNAMENT_INSET}px;top:${ORNAMENT_INSET}px` }, `「${baseTheme().name}」角饰`));
    s.append(h('div', { class: 'orn-ph', style: `${style};right:${ORNAMENT_INSET}px;bottom:${ORNAMENT_INSET}px` }, '应用内显示'));
  }
  s.append(statusBar(r.contentTone === 'dark'));
  s.append(h('div', { class: 'rhead' }, '第十七章 灯下'));
  const layout = p.layout || {};
  const fontSize = typeof layout.fontSize === 'number' && layout.fontSize >= 12 && layout.fontSize <= 40 ? layout.fontSize : 19;
  const margin = typeof layout.marginLeft === 'number' ? Math.max(8, Math.min(48, layout.marginLeft)) : 20;
  const content = h('div', { class: 'content', style: `font-size:${fontSize}px;padding:6px ${margin}px` }, h('h2', {}, '第十七章 灯下'));
  const p1 = h('p', {}, '船过石桥时，舱里的灯忽然暗了一下。老周把书合上，抬头看了看窗外的水色，');
  p1.append(emphasis('“今晚风大，怕是要靠岸了。”', e));
  const p2 = h('p', {}, '阿遥没有应声，只把那页折了个角。她记得母亲说过，');
  p2.append(emphasis('“夜里读书，读到哪儿就算到哪儿。”', e), '水声一阵紧过一阵，像是有人在船底翻书。');
  const p3 = h('p', {}, '岸上的灯笼一盏一盏亮起来，映在河面上，碎成许多小小的金色鳞片。她伸手去碰，只碰到了凉。');
  const p4 = h('p', {}, '老周又把书翻开，从折角的那一页读起。');
  content.append(p1, p2, p3, p4);
  s.append(content);
  s.append(h('div', { class: 'rfoot', style: `left:${margin}px;right:${margin}px` }, h('span', {}, '夜航船 · 3/14'), h('span', {}, '21:40  82%')));
  return s;
}

function screenTts(e: Effective): HTMLElement {
  const s = h('div', { class: 'scr tts' });
  s.append(readerBody(e));
  s.append(h('div', { class: 'dim' }));
  const sheet = h('div', { class: 'sheet', 'data-sec': 'tts' });
  if (e.tts) {
    const art = h('div', { class: 'art' }, h('img', { src: assetUrl(e.tts.artwork), alt: '' }), h('div', { class: 'art-fade' }));
    sheet.append(art, h('div', { class: 'glow' }));
  } else if (usesBaseArt()) {
    sheet.append(h('div', { class: 'art' }, placeholder(`沿用「${baseTheme().name}」面板插画`, 'fill')));
  }
  sheet.append(h('div', { class: 'ctl' },
    h('div', {}, h('div', { class: 't' }, '夜航船'), h('div', { class: 's' }, '第十七章 灯下 · 晓晓')),
    h('div', { class: 'prog' }, h('i')), h('div', { class: 'times' }, h('span', {}, '03:12'), h('span', {}, '07:40')),
    h('div', { class: 'btns' }, h('span'), h('span'), h('span', { class: 'play' }), h('span'), h('span'))));
  s.append(sheet);
  return s;
}

function screenStartup(e: Effective): HTMLElement {
  const s = h('div', { class: 'scr startup', 'data-sec': 'startup' });
  const p = project().parts;
  if (e.startup && assetUrl(e.startup.image)) {
    s.append(h('img', { src: assetUrl(e.startup.image), alt: '' }));
    if (e.startup.title || e.startup.subtitle) {
      s.append(h('div', { class: 'txt' }, e.startup.title ? h('b', {}, e.startup.title) : null, e.startup.subtitle ? h('span', {}, e.startup.subtitle) : null));
    }
  } else {
    s.append(placeholder(`沿用「${baseTheme().name}」的启动页`, 'fill dark'));
  }
  void p;
  s.prepend(statusBar(true));
  return s;
}

function screenCard(e: Effective): HTMLElement {
  const p = project();
  const s = h('div', { class: 'scr cards' });
  s.append(statusBar(luminance(e.c.pageColor) < 0.25));
  s.append(h('div', { class: 'hd' }, h('b', {}, '主题')));
  const previewUrl = assetUrl(p.parts.preview) || (e.startup ? assetUrl(e.startup.image) : '');
  const logo = assetUrl(p.parts.logo);
  const mine = h('div', { class: 'tcard', 'data-sec': 'brand' },
    h('div', { class: 'pv' }, previewUrl ? h('img', { class: 'p', src: previewUrl, alt: '' }) : h('div', { class: 'swatch' }, h('i', { style: 'background:var(--p-page)' }), h('i', { style: 'background:var(--p-card)' }), h('i', { style: 'background:var(--p-accent)' })),
      logo ? h('img', { class: 'logo', src: logo, alt: '' }) : null),
    h('div', { class: 'nm' }, p.manifest.name || '未命名主题', h('small', {}, p.manifest.author ? `${p.manifest.author} · 自定义方案` : '自定义方案')));
  const other = h('div', { class: 'tcard other' }, h('div', { class: 'pv' }), h('div', { class: 'nm' }, baseTheme().name, h('small', {}, '内置')));
  s.append(h('div', { class: 'row' }, mine, other));
  s.append(h('div', { class: 'detail', 'data-sec': 'meta' },
    h('b', {}, p.manifest.name || '未命名主题'),
    h('div', {}, p.manifest.description || '（没有说明）'),
    h('div', { class: 'chips' }, ...describe().map((label) => h('i', {}, label))),
    h('div', { class: 'apply' }, '应用主题')));
  return s;
}

/** 主题详情里列出的部件（对应 describeParts）。 */
export function describe(): string[] {
  const p = project().parts;
  const out: string[] = [];
  const has = (o: any): boolean => !!o && Object.values(o).some((v) => v !== '' && v !== null && v !== undefined);
  if (has(p.light && p.light.colors) || has(p.dark && p.dark.colors)) out.push('界面配色');
  if ((['light', 'dark'] as Mode[]).some((m) => p[m] && p[m].reader && (p[m].reader.backgroundMode || p[m].reader.backgroundColor))) out.push('阅读背景');
  if (has(p.light && p.light.emphasis) || has(p.dark && p.dark.emphasis) || (p.bubble && p.bubble.cap)) out.push('正文强调');
  if (p.ttsPanel && (has(p.ttsPanel.light) || has(p.ttsPanel.dark))) out.push('朗读面板');
  if (p.navigation && has(p.navigation)) out.push('导航图标');
  if (p.book && ((p.book.covers || []).length || p.book.shelfFrame || p.book.shelfFolder)) out.push('书籍素材');
  if (p.startup && ((p.startup.light && p.startup.light.image) || (p.startup.dark && p.startup.dark.image))) out.push('启动封面');
  if (p.homeBackdrop && (p.homeBackdrop.light || p.homeBackdrop.dark)) out.push('首页背景');
  if (p.logo) out.push('主题标识');
  if (p.typography && (p.typography.appFont || p.typography.appFontFamily)) out.push('界面字体');
  if (p.radius && Object.keys(p.radius).some((k) => typeof p.radius[k] === 'number')) out.push('圆角');
  return out;
}

export function renderScreen(mode: Mode): HTMLElement {
  const e = effective(mode);
  const screen = S.ui.screen;
  const content = screen === 'reader' ? readerBody(e) : screen === 'tts' ? screenTts(e)
    : screen === 'startup' ? screenStartup(e) : screen === 'card' ? screenCard(e)
    : screen === 'explore' ? screenExplore(mode, e)
    : screen === 'mine' ? screenMine(mode, e) : screenShelf(mode, e);
  const phone = h('div', { class: `phone ${mode}`, style: `${themeVars(mode, e)};width:${PHONE_W}px;height:${PHONE_H}px` }, content);
  phone.querySelectorAll(`[data-sec="${S.ui.section}"]`).forEach((el) => el.classList.add('focus'));
  return phone;
}
