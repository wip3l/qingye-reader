// 把网页版说明书 docs/manual/index.html 转成应用内帮助页读取的结构化数据。
// 网页版是唯一的正文来源；改完说明书后运行：node scripts/build-help-data.mjs
// 加 --check 只比对、不写文件，生成结果与仓库里的 help.json 不一致时以非零退出。
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SOURCE = resolve(root, 'docs/manual/index.html');
const OUTPUT = resolve(root, 'entry/src/main/resources/rawfile/manual/help.json');

// 首页“按功能查看”的分组：一个专题由说明书里的一个或几个章节（h2 所在 section 的 id）合成。
// action 是专题页顶部的跳转按钮，url 为应用内页面，home: N 表示回首页并切到第 N 个页签。
const GROUPS = [
  [
    { id: 'layout', title: '界面总览', icon: 'square_grid_2x2', summary: '底部页签、“我的”入口、桌面卡片', parts: ['layout'] },
    { id: 'shelf', title: '书架', icon: 'bookshelf', summary: '筛选、分组、多选、隐私书架、封面', parts: ['shelf', 'shelfset'],
      action: { label: '打开书架设置', url: 'pages/BookshelfSettings' } },
    { id: 'search', title: '搜索与发现', icon: 'magnifyingglass', summary: '搜索范围、历史、遇到“去验证”', parts: ['search', 'explore'],
      action: { label: '去搜索', home: 2 } },
    { id: 'detail', title: '书籍详情与换源', icon: 'arrow_left_arrow_right', summary: '完整目录、视频内容、换源', parts: ['detail'] },
  ],
  [
    { id: 'source', title: '书源管理', icon: 'externaldrive', summary: '导入、校验、分组、登录', parts: ['source'],
      action: { label: '打开书源管理', url: 'pages/BookSource' } },
    { id: 'sourceedit', title: '书源编辑与调试', icon: 'square_and_pencil', summary: '原生书源 JS、单书源调试', parts: ['sourceedit'] },
  ],
  [
    { id: 'reader', title: '阅读', icon: 'book', summary: '点击区域、目录、书签、漫画', parts: ['reader'],
      action: { label: '打开阅读设置', url: 'pages/Settings' } },
    { id: 'typo', title: '排版、字体与配色', icon: 'textformat', summary: '排版参数、页眉页脚、背景', parts: ['typo'],
      action: { label: '打开阅读设置', url: 'pages/Settings' } },
    { id: 'tts', title: '朗读与有声书', icon: 'speaker_wave_3', summary: '音色、朗读面板、后台播放', parts: ['tts', 'audio'],
      action: { label: '打开朗读设置', url: 'pages/TtsSettings' } },
    { id: 'clean', title: '缓存与替换净化', icon: 'funnel', summary: '缓存章节、预缓存、净化规则', parts: ['clean'],
      action: { label: '管理替换规则', url: 'pages/ReaderReplaceRules' } },
  ],
  [
    { id: 'import', title: '导入、OPDS 与浏览器看书', icon: 'download', summary: '本地导入、书库、WebDAV', parts: ['import', 'lan'],
      action: { label: '打开书籍导入', url: 'pages/BookImport' } },
    { id: 'backup', title: '备份与云同步', icon: 'arrow_2_circlepath', summary: '导出导入、迁移、多设备同步', parts: ['backup', 'sync'],
      action: { label: '打开数据同步', url: 'pages/DataSync' } },
    { id: 'look', title: '主题与外观', icon: 'paintpalette', summary: '主题、自定义方案、字体与图标', parts: ['look'],
      action: { label: '打开主题', url: 'pages/ThemeSettings' } },
    { id: 'account', title: '账号、点数与统计', icon: 'person', summary: '登录、点数规则、阅读统计', parts: ['account', 'misc'],
      action: { label: '打开账号', url: 'pages/AccountCenter' } },
  ],
];

// 不进分组、从首页其他位置进入的专题。
const EXTRA_TOPICS = [
  { id: 'start', title: '快速上手', icon: 'list_bullet', summary: '', parts: ['start'] },
  { id: 'legal', title: '使用须知', icon: 'checkmark_shield', summary: '', parts: ['legal'] },
];

// 首页“新手上手”卡片：说明书里的步骤偏长，卡片用短句，详细步骤点标题进“快速上手”专题看。
const QUICK_START = [
  { title: '导入书源', desc: 'URL 或文件导入，多个可勾选', action: { label: '去书源管理', url: 'pages/BookSource' } },
  { title: '校验书源', desc: '先看哪些能用，失败的一键禁用', action: { label: '去校验', url: 'pages/BookSource' } },
  { title: '搜书加书架', desc: '搜索或发现，在详情页加入书架', action: { label: '去搜索', home: 2 } },
  { title: '开始阅读', desc: '点屏幕中央呼出菜单，调字号与翻页', action: { label: '去书架', home: 0 } },
];

// 首页直接展示的常见问题（按问题原文匹配），以及个别答案下的跳转按钮。
const FEATURED_FAQ = ['搜索不到任何书', '换了手机，数据怎么搬过去', '正文里有广告或乱七八糟的文字'];
const FAQ_ACTIONS = {
  '搜索不到任何书': { label: '打开书源管理', url: 'pages/BookSource' },
  '换了手机，数据怎么搬过去': { label: '打开数据备份', url: 'pages/DataBackup' },
  '正文里有广告或乱七八糟的文字': { label: '管理替换规则', url: 'pages/ReaderReplaceRules' },
  'OPDS 书库连不上': { label: '打开 OPDS 书库', url: 'pages/OpdsServers' },
  '书源提示证书错误': { label: '打开书源管理', url: 'pages/BookSource' },
};

// ───────────── 极简 HTML 解析：说明书是手写的规整 HTML，够用即可 ─────────────

const VOID = new Set(['img', 'br', 'input', 'meta', 'link', 'hr']);

function decode(text) {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (all, code) => {
    if (code[0] === '#') {
      return String.fromCodePoint(code[1] === 'x' || code[1] === 'X' ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10));
    }
    const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
    return named[code.toLowerCase()] ?? all;
  });
}

function parse(html) {
  const doc = { tag: '#root', attrs: {}, children: [] };
  const stack = [doc];
  const re = /<!--[\s\S]*?-->|<(\/?)([a-zA-Z0-9]+)((?:\s+[^\s=>]+(?:="[^"]*")?)*)\s*\/?>|([^<]+)/g;
  let m;
  while ((m = re.exec(html))) {
    if (m[0].startsWith('<!--')) continue;
    const top = stack[stack.length - 1];
    if (m[4] !== undefined) {
      top.children.push({ tag: '#text', text: decode(m[4]) });
      continue;
    }
    const tag = m[2].toLowerCase();
    if (m[1]) {
      const at = stack.map((n) => n.tag).lastIndexOf(tag);
      if (at > 0) stack.length = at;
      continue;
    }
    const attrs = {};
    for (const a of m[3].matchAll(/([^\s=]+)(?:="([^"]*)")?/g)) attrs[a[1]] = decode(a[2] ?? '');
    const node = { tag, attrs, children: [] };
    top.children.push(node);
    if (tag === 'script' || tag === 'style') {
      const end = html.indexOf(`</${tag}>`, re.lastIndex);
      re.lastIndex = end < 0 ? html.length : end + tag.length + 3;
      continue;
    }
    if (!VOID.has(tag)) stack.push(node);
  }
  return doc;
}

const cls = (node) => (node.attrs?.class || '').split(/\s+/).filter(Boolean);
const elements = (node) => node.children.filter((c) => c.tag !== '#text');
const textOf = (node) => (node.tag === '#text' ? node.text : node.children.map(textOf).join(''));
const clean = (text) => text.replace(/\s+/g, ' ').trim();

function findById(node, id) {
  if (node.attrs?.id === id) return node;
  for (const child of node.children || []) {
    const hit = child.tag === '#text' ? null : findById(child, id);
    if (hit) return hit;
  }
  return null;
}

// ───────────── 行内文字：k 0 普通、1 加粗、2 菜单路径、3 代码、4 链接 ─────────────

function inline(node) {
  const runs = [];
  const push = (t, k, u) => {
    if (!t) return;
    const last = runs[runs.length - 1];
    if (last && last.k === k && !u && !last.u) last.t += t;
    else runs.push(u ? { t, k, u } : { t, k });
  };
  const walk = (n, k) => {
    if (n.tag === '#text') return push(n.text.replace(/\s+/g, ' '), k);
    if (n.tag === 'ul' || n.tag === 'ol') return;
    if (n.tag === 'a') return push(clean(textOf(n)), 4, n.attrs.href || '');
    if (n.tag === 'code') return push(textOf(n), 3);
    if (n.tag === 'span' && cls(n).includes('p')) return push(clean(textOf(n)), 2);
    const next = n.tag === 'b' || n.tag === 'strong' ? 1 : k;
    for (const c of n.children) walk(c, next);
  };
  walk(node, 0);
  if (runs.length) {
    runs[0].t = runs[0].t.replace(/^\s+/, '');
    runs[runs.length - 1].t = runs[runs.length - 1].t.replace(/\s+$/, '');
  }
  return runs.filter((r) => r.t);
}

// ───────────── 块：p 段落、tip 提示、note 注意、h 小标题、ul/ol 列表、rows 表格、zone 点击区域 ─────────────

function listItems(list, level, out) {
  for (const li of elements(list).filter((c) => c.tag === 'li')) {
    out.push({ r: inline(li), lv: level });
    for (const sub of elements(li).filter((c) => c.tag === 'ul' || c.tag === 'ol')) listItems(sub, level + 1, out);
  }
  return out;
}

function tableRows(table) {
  const trs = [];
  const collect = (n) => {
    for (const c of elements(n)) {
      if (c.tag === 'tr') trs.push(c);
      else collect(c);
    }
  };
  collect(table);
  let head = [];
  const rows = [];
  for (const tr of trs) {
    const cells = elements(tr).filter((c) => c.tag === 'td' || c.tag === 'th');
    if (cells.every((c) => c.tag === 'th')) {
      head = cells.map((c) => clean(textOf(c)));
      continue;
    }
    rows.push({ title: clean(textOf(cells[0])), cells: cells.slice(1).map(inline) });
  }
  return { k: 'rows', head, rows };
}

function blocks(nodes) {
  const out = [];
  for (const n of nodes) {
    if (n.tag === '#text') {
      if (n.text.trim()) out.push({ k: 'p', r: [{ t: clean(n.text), k: 0 }] });
      continue;
    }
    const c = cls(n);
    if (n.tag === 'h2' || n.tag === 'h3' || n.tag === 'footer' || n.tag === 'img') continue;
    if (c.includes('shots') || c.includes('meta') || c.includes('steps') || c.includes('sub')) continue;
    if (n.tag === 'p') {
      const kind = c.includes('tip') ? 'tip' : c.includes('note') ? 'note' : 'p';
      out.push({ k: kind, r: inline(n) });
    } else if (n.tag === 'h4') {
      out.push({ k: 'h', r: inline(n) });
    } else if (n.tag === 'ul' || n.tag === 'ol') {
      out.push({ k: n.tag, items: listItems(n, 0, []) });
    } else if (n.tag === 'table') {
      out.push(tableRows(n));
    } else if (c.includes('tw')) {
      out.push(...blocks(n.children));
    } else if (c.includes('tabs')) {
      const rows = elements(n).map((d) => {
        const [b, span] = elements(d);
        return { title: clean(textOf(b)), cells: [inline(span)] };
      });
      out.push({ k: 'rows', head: [], rows });
    } else if (c.includes('zone')) {
      const grid = elements(n).find((d) => cls(d).includes('grid9'));
      const cells = elements(grid).map((i) => ({ t: clean(textOf(i)), m: cls(i).includes('m') ? 1 : cls(i).includes('n') ? 2 : 0 }));
      const para = elements(n).find((d) => d.tag === 'p');
      out.push({ k: 'zone', cells, r: para ? inline(para) : [] });
    } else if (n.tag === 'details') {
      continue;
    } else {
      out.push(...blocks(n.children));
    }
  }
  return out.filter((b) => (b.r ? b.r.length : true));
}

function plain(blockList) {
  const parts = [];
  for (const b of blockList) {
    if (b.r) parts.push(b.r.map((r) => r.t).join(''));
    if (b.items) parts.push(...b.items.map((i) => i.r.map((r) => r.t).join('')));
    if (b.rows) parts.push(...b.rows.map((row) => [row.title, ...row.cells.map((cell) => cell.map((r) => r.t).join(''))].join(' ')));
    if (b.cells && b.k === 'zone') parts.push(b.cells.map((cell) => cell.t).join(' '));
  }
  return parts.join('\n');
}

// ───────────── 组装 ─────────────

function buildPart(section, topicId, counter) {
  const h2 = elements(section).find((c) => c.tag === 'h2');
  const intro = blocks(section.children);
  const sections = [];
  for (const sub of elements(section).filter((c) => cls(c).includes('sub'))) {
    const h3 = elements(sub).find((c) => c.tag === 'h3');
    counter.n += 1;
    const body = blocks(sub.children);
    sections.push({ id: sub.attrs.id || `${topicId}-${counter.n}`, title: clean(textOf(h3)), blocks: body, text: plain(body) });
  }
  return { id: section.attrs.id, title: clean(textOf(h2)), intro, sections };
}

function buildTopic(def, doc) {
  const counter = { n: 0 };
  const parts = def.parts.map((id) => {
    const section = findById(doc, id);
    if (!section) throw new Error(`说明书里没有章节 #${id}`);
    return buildPart(section, def.id, counter);
  });
  const topic = { id: def.id, title: def.title, icon: def.icon, summary: def.summary, parts };
  if (def.action) topic.action = def.action;
  return topic;
}

function build(html) {
  const doc = parse(html);
  const meta = clean(textOf(findById(doc, 'top')));
  const version = (meta.match(/当前版本\s*([\d.]+)/) || [])[1] || '';
  const updated = (meta.match(/文档更新\s*([\d-]+)/) || [])[1] || '';

  const groups = GROUPS.map((group) => group.map((def) => buildTopic(def, doc)));
  const extra = EXTRA_TOPICS.map((def) => buildTopic(def, doc));

  // 快速上手专题：步骤列表在说明书里是 ol.steps，单独转成有序列表放在开头。
  const start = extra.find((t) => t.id === 'start');
  const stepsNode = (function find(n) {
    if (n.tag === 'ol' && cls(n).includes('steps')) return n;
    for (const c of n.children || []) {
      const hit = c.tag === '#text' ? null : find(c);
      if (hit) return hit;
    }
    return null;
  })(findById(doc, 'start'));
  const steps = elements(stepsNode).map((li) => {
    const strong = (function find(n) {
      if (n.tag === 'strong') return n;
      for (const c of n.children || []) {
        const hit = c.tag === '#text' ? null : find(c);
        if (hit) return hit;
      }
      return null;
    })(li);
    const desc = (function find(n) {
      if (n.tag === 'span' && cls(n).includes('d')) return n;
      for (const c of n.children || []) {
        const hit = c.tag === '#text' ? null : find(c);
        if (hit) return hit;
      }
      return null;
    })(li);
    return { r: [{ t: clean(textOf(strong)), k: 1 }, { t: '：', k: 0 }, ...inline(desc)], lv: 0 };
  });
  start.parts[0].intro.splice(1, 0, { k: 'ol', items: steps });

  const faqSection = findById(doc, 'faq');
  const faq = elements(faqSection).filter((c) => c.tag === 'details').map((d) => {
    const q = clean(textOf(elements(d).find((c) => c.tag === 'summary')));
    const body = blocks(elements(d).filter((c) => c.tag !== 'summary'));
    const item = { q, blocks: body, text: plain(body) };
    if (FAQ_ACTIONS[q]) item.action = FAQ_ACTIONS[q];
    return item;
  });
  for (const q of [...FEATURED_FAQ, ...Object.keys(FAQ_ACTIONS)]) {
    if (!faq.some((f) => f.q === q)) throw new Error(`常见问题里没有“${q}”`);
  }
  const featured = FEATURED_FAQ.map((q) => faq.findIndex((f) => f.q === q));

  // 说明书开头“先了解”的提示放进使用须知，首页不再单独展示。
  const legal = extra.find((t) => t.id === 'legal');
  legal.parts[0].intro.unshift(...blocks(elements(findById(doc, 'top')).filter((c) => c.tag === 'p' && cls(c).includes('note'))));
  const footer = clean(textOf(elements(findById(doc, 'legal')).find((c) => c.tag === 'footer') || { tag: '#text', text: '' }));

  return { version, updated, quickStart: QUICK_START, groups, topics: extra, faq, featuredFaq: featured, legalFooter: footer };
}

const html = readFileSync(SOURCE, 'utf8');
const data = build(html);
const json = JSON.stringify(data);
if (process.argv.includes('--check')) {
  let current = '';
  try {
    current = readFileSync(OUTPUT, 'utf8');
  } catch {
    current = '';
  }
  if (current !== json) {
    console.error('help.json 与 docs/manual/index.html 不同步，请运行 node scripts/build-help-data.mjs');
    process.exit(1);
  }
  console.log('help.json 已与说明书同步');
} else {
  writeFileSync(OUTPUT, json);
  const sections = data.groups.flat().reduce((n, t) => n + t.parts.reduce((m, p) => m + p.sections.length, 0), 0);
  console.log(`已生成 ${OUTPUT}：${data.groups.flat().length} 个专题、${sections} 个小节、${data.faq.length} 条常见问题，${(json.length / 1024).toFixed(1)} KB`);
}
