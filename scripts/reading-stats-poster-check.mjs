import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const base = new URL('../entry/src/main/ets/', import.meta.url);
function load(file, globals, names) {
  const code = fs.readFileSync(new URL(file, base), 'utf8').replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, '');
  const context = vm.createContext({ console, ...globals });
  vm.runInContext(stripTypeScriptTypes(code, { mode: 'strip' }) + `\nthis.result={${names}};`, context);
  return context.result;
}
const summary = load('core/stats/ReadStatsSummary.ts', {}, 'ReadStatsSummary,ReadStatsRank,ReadStatsBar');
const model = load('core/stats/ReadStatsPosterModel.ts', summary,
  'ReadStatsPosterSnapshot,ReadStatsPosterOptions,ReadStatsPosterLayout,ReadStatsPosterSession');
const { ReadStatsPosterSnapshot: Snapshot, ReadStatsPosterOptions: Options, ReadStatsPosterLayout: Layout, ReadStatsPosterSession: Session } = model;
function fixture(count = 5, mode = 'week') {
  const stats = new summary.ReadStatsSummary();
  stats.totalMs = 756 * 60000; stats.activeDays = 6; stats.averageMs = 108 * 60000;
  stats.items = Array.from({ length: count }, (_, i) => Object.assign(new summary.ReadStatsRank(), {
    bookKey: `book-${i}`, name: `已移除书籍 ${i + 1}`, rank: i + 1, durationMs: (count - i) * 60000, onShelf: false
  }));
  stats.bars = [54, 96, 162, 0, 120, 144, 180].map((minutes, index) => Object.assign(new summary.ReadStatsBar(), {
    key: `2026-10-${19 + index}`, label: ['一','二','三','四','五','六','日'][index], durationMs: minutes * 60000
  }));
  return { stats, snapshot: Snapshot.capture(stats, 'account-a', mode, '2026年10月19日 — 10月25日', '全部设备', '私密昵称', '') };
}

test('snapshot freezes filters, metrics, deleted titles, bars and ranking without altering the page', () => {
  const { stats, snapshot } = fixture();
  stats.items[0].name = '新同步名称'; stats.items[0].durationMs = 1; stats.bars[0].durationMs = 0; stats.totalMs = 0;
  assert.equal(snapshot.books[0].name, '已移除书籍 1');
  assert.equal(snapshot.books[0].durationMs, 5 * 60000);
  assert.equal(snapshot.bars[0].durationMs, 54 * 60000);
  assert.equal(snapshot.totalMs, 756 * 60000);
  assert.equal(snapshot.ownerId, 'account-a'); assert.equal(snapshot.device, '全部设备');
  assert.equal(snapshot.books[0].bookUrl, ''); // No local book URI in share payload.
});

test('all books paginate without gaps, duplicates, changed ranks or changing aggregate totals', () => {
  const { snapshot } = fixture(27);
  const opts = new Options(); opts.rankLimit = -1;
  const pages = Layout.pages(snapshot, opts);
  assert.deepEqual(Array.from(pages, p => p.books.length), [10, 10, 7]);
  assert.deepEqual(Array.from(pages).flatMap(p => Array.from(p.books, b => b.rank)), Array.from({ length: 27 }, (_, i) => i + 1));
  assert(pages.every(p => p.height < 2500 && p.count === 3));
  assert.equal(snapshot.totalMs, 756 * 60000);
});

test('limited and hidden rankings never change book count or aggregate statistics', () => {
  const { snapshot } = fixture(17);
  for (const limit of [0, 3, 5, 10]) {
    const opts = new Options(); opts.rankLimit = limit;
    assert.equal(Layout.pages(snapshot, opts)[0].books.length, limit);
    assert.equal(snapshot.books.length, 17);
  }
});

test('profile is opt-in, and missing/disabled footer content collapses', () => {
  const { snapshot } = fixture();
  const opts = new Options();
  assert.equal(Layout.hasProfile(snapshot, opts), false);
  const hiddenHeight = Layout.pages(snapshot, opts)[0].height;
  opts.profile = true;
  assert.equal(Layout.hasProfile(snapshot, opts), true);
  assert(Layout.pages(snapshot, opts)[0].height > hiddenHeight);
  opts.avatar = false; opts.nickname = false; opts.signature = false;
  assert.equal(Layout.hasProfile(snapshot, opts), false);
  assert.equal(Layout.pages(snapshot, opts)[0].height, hiddenHeight);
});

test('preferences reject malformed enums and truncate text by Unicode code point', () => {
  const opts = Options.normalize({ style: 999, rankLimit: -9, profile: 'true', alias: '😀'.repeat(40), quote: '文'.repeat(70) });
  assert.equal(opts.style, 0); assert.equal(opts.rankLimit, 5); assert.equal(opts.profile, false);
  assert.equal(Array.from(opts.alias).length, 24); assert.equal(Array.from(opts.quote).length, 40);
  assert.equal(Options.normalize({ quote: '第一行\n第二行\t' }).quote, '第一行 第二行 ');
});

test('daily layout omits trend, and all period headings are correct', () => {
  const { snapshot } = fixture();
  const opts = new Options();
  const weekHeight = Layout.pages(snapshot, opts)[0].height;
  const modes = ['day', 'week', 'month', 'year', 'all'];
  const titles = ['我的阅读日报', '我的阅读周报', '我的阅读月报', '我的阅读年报', '我的阅读时光'];
  modes.forEach((mode, index) => { snapshot.mode = mode; assert.equal(snapshot.title(), titles[index]); });
  snapshot.mode = 'day'; assert.equal(Layout.pages(snapshot, opts)[0].height, weekHeight - 310);
});

test('handoff is single-use and does not retain a second account snapshot', () => {
  Session.put(fixture().snapshot); assert.equal(Session.take().ownerId, 'account-a'); assert.equal(Session.take(), null);
});

function canvasRecorder() {
  const texts = [];
  const ctx = { fillText: (text, x, y, max) => texts.push({ text, x, y, max }), measureText: text => ({ width: Array.from(text).length * 32 }) };
  for (const method of ['fillRect','beginPath','moveTo','lineTo','quadraticCurveTo','closePath','fill','arc','stroke','save','restore','clip','drawImage']) ctx[method] = () => {};
  return { ctx, texts };
}
const { ReadStatsPosterRenderer: Renderer } = load('core/stats/ReadStatsPosterRenderer.ets', { ...summary, ...model }, 'ReadStatsPosterRenderer');
test('all four real drawing paths keep true totals and obey profile/hidden-rank switches', () => {
  const { snapshot } = fixture();
  for (let style = 0; style < 4; style++) {
    const opts = new Options(); opts.style = style; opts.rankLimit = 0;
    const page = Layout.pages(snapshot, opts)[0];
    const { ctx, texts } = canvasRecorder();
    new Renderer(ctx, style).draw(snapshot, opts, page, new Map(), null);
    assert(texts.some(t => t.text === '12小时36分'));
    assert(texts.some(t => t.text === '阅读书籍  5本'));
    assert(!texts.some(t => t.text.includes('私密昵称') || t.text.includes('已移除书籍')));
    assert(texts.every(t => t.y >= 0 && t.y < page.height));
  }
});
test('long book names and user quotes fit within fixed export page bounds', () => {
  const { snapshot } = fixture(10);
  snapshot.books[0].name = '超长书名'.repeat(200);
  const opts = new Options(); opts.profile = true; opts.quote = '这是一句完整的阅读签名'.repeat(3); opts.rankLimit = 10;
  const page = Layout.pages(snapshot, opts)[0]; const { ctx, texts } = canvasRecorder();
  new Renderer(ctx, 0).draw(snapshot, opts, page, new Map(), null);
  assert(texts.some(t => t.text.includes('…')));
  assert(texts.some(t => t.text === snapshot.nickname));
  assert(texts.every(t => t.y + 32 < page.height));
});

test('native multi-image sharing uses real file URIs; saving cancellation writes nothing', async () => {
  const records = []; let shown = 0, copies = 0;
  const { ImageFileExport } = load('utils/ImageFileExport.ets', {
    fileUri: { getUriFromPath: path => `file://${path}` },
    uniformTypeDescriptor: { UniformDataType: { IMAGE: 'image' }, getUniformDataTypeByFilenameExtension: ext => `image${ext}` },
    systemShare: { SharedData: class { constructor(row) { records.push(row); } addRecord(row) { records.push(row); } },
      ShareController: class { async show() { shown++; } }, SharePreviewMode: { DETAIL: 1 }, SelectionMode: { SINGLE: 0 } },
    photoAccessHelper: { PhotoType: { IMAGE: 1 }, getPhotoAccessHelper: () => ({ showAssetsCreationDialog: async () => [] }) },
    fileIo: { copyFile: async () => { copies++; } }
  }, 'ImageFileExport');
  await ImageFileExport.share({}, ['/cache/a.png', '/cache/b.png']);
  assert.equal(shown, 1); assert.equal(records.length, 2); assert.equal(records[1].uri, 'file:///cache/b.png');
  assert.equal(await ImageFileExport.save({}, ['/cache/a.png']), false); assert.equal(copies, 0);
  await assert.rejects(ImageFileExport.share({}, []));
});
