// Executes production aggregation, migration SQL and tracker logic. Native UI is checked by the HAP build.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { randomUUID } from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { readEtsModule } from './lib/ets-module-staging.mjs';

process.env.TZ = 'America/Denver';
const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(file, globals, names) {
  const code = fs.readFileSync(new URL(file, root), 'utf8').replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, '');
  // platform/TextCompare 的鸿蒙实现就是 localeCompare。
  const compareText = (a, b, locale, options) => a.localeCompare(b, locale, options);
  const context = vm.createContext({ console, compareText, ...globals });
  vm.runInContext(stripTypeScriptTypes(code, { mode: 'strip' }) + `\nthis.exports={${names}};`, context);
  return context.exports;
}
const { ReadStatsSummary: Summary } = load('core/stats/ReadStatsSummary.ts', {}, 'ReadStatsSummary');
const Book = vm.runInNewContext(stripTypeScriptTypes(readEtsModule('model/data/Book.ts')
  .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' }) + '\nBook;');
const syncModels = load('core/stats/ReadStatsSyncModels.ts', {},
  'ReadStatsPendingUpload,ReadStatsSyncPayload,ReadStatsSyncOperation,ReadStatsSyncRequest,ReadStatsSyncResponse,ReadStatsSyncAck,ReadStatsSyncChange');
const date = (y, m, d, h = 0, minute = 0) => new Date(y, m - 1, d, h, minute).getTime();
const row = (dayKey, durationMs, deviceId = 'phone', bookKey = 'book') => ({
  dayKey, durationMs, deviceId, bookKey, bookUrl: bookKey, name: bookKey, author: '', coverUrl: '', onShelf: true
});

test('all devices sum duration; days and book identities are deduplicated', () => {
  const result = Summary.calculate([row('2026-10-19', 1800000), row('2026-10-19', 1200000, 'tablet'),
    row('2026-10-20', 600000, 'tablet', 'second')], 'week', date(2026, 10, 20), date(2026, 10, 21));
  assert.equal(result.totalMs, 3600000);
  assert.equal(result.activeDays, 2);
  assert.equal(result.items.length, 2);
  assert.equal(result.averageMs, 1200000);
  assert.equal(result.bars.length, 7);
  assert.equal(result.bars[0].durationMs, 3000000);
  assert.equal(result.bars[2].durationMs, 0);
});

test('ranking merges source editions with complete matching metadata and keeps deletion keys', () => {
  const old = { ...row('2026-10-20', 60000, 'phone', 'old-source'),
    name: '公路求生，神级宝箱开局', author: '静舟小妖', onShelf: false, bookUrl: 'old' };
  const current = { ...old, bookKey: 'new-source', bookUrl: 'new', durationMs: 120000,
    name: ' 公路求生，神级宝箱开局 ', author: ' 静舟小妖 ', coverUrl: 'cover', onShelf: true };
  for (const rows of [[old, current], [current, old]]) {
    const result = Summary.calculate(rows, 'all', date(2026, 10, 20), date(2026, 10, 21));
    assert.equal(result.items.length, 1); assert.equal(result.totalMs, 180000);
    const item = result.items[0];
    assert.equal(item.durationMs, 180000); assert.equal(item.percent, 100);
    assert.equal(item.bookUrl, 'new'); assert.equal(item.coverUrl, 'cover'); assert(item.onShelf);
    assert.deepEqual(Array.from(item.recordBookKeys).sort(), ['new-source', 'old-source']);
  }
  const distinct = Summary.calculate([old, { ...current, author: '其他作者' },
    { ...old, bookKey: 'unknown-a', author: '' }, { ...old, bookKey: 'unknown-b', author: '' }],
  'all', date(2026, 10, 20), date(2026, 10, 21));
  assert.equal(distinct.items.length, 4, 'different authors and incomplete metadata stay separate');
  const spaced = Summary.calculate([
    { ...old, name: ' A  B ', bookKey: 'spaced' },
    { ...old, name: 'A B', bookKey: 'same-spaced' },
    { ...old, name: 'AB', bookKey: 'unspaced' },
  ], 'all', date(2026, 10, 20), date(2026, 10, 21));
  assert.equal(spaced.items.length, 2, 'normalization preserves meaningful word boundaries');
});
test('ranking merges simplified/traditional titles and attaches author-less records only when unambiguous', () => {
  const engine = new URL('../harmony-book-ai-engine/aiengine/src/main/', import.meta.url);
  const { ComicChineseDictionary: Dictionary } = load(new URL('ets/core/reader/ComicChineseDictionary.ts', engine),
    {}, 'ComicChineseDictionary');
  const raw = name => fs.readFileSync(new URL(`resources/rawfile/opencc/${name}`, engine), 'utf8');
  const dictionary = new Dictionary(raw('TSCharacters.txt'), raw('TSPhrases.txt'));
  const fold = text => dictionary.convertSameLength(text);
  const at = [date(2026, 11, 18), date(2026, 11, 19)];
  const imported = { ...row('2026-11-17', 9 * 3600000, 'legacy-import', 'android'),
    name: '穿越兽世种田养狼', author: '土豆派豆', onShelf: false, bookUrl: 'android-history://x' };
  const shelf = { ...row('2026-11-18', 35 * 60000, 'phone', 'shelf'),
    name: '穿越獸世種田養狼', author: '土豆派豆', coverUrl: 'cover', bookUrl: 'shelf-url' };
  for (const rows of [[imported, shelf], [shelf, imported]]) {
    const merged = Summary.calculate(rows, 'all', ...at, fold);
    assert.equal(merged.items.length, 1);
    assert.equal(merged.items[0].name, '穿越獸世種田養狼', 'shows the shelf edition');
    assert.equal(merged.items[0].bookUrl, 'shelf-url'); assert.equal(merged.items[0].coverUrl, 'cover');
    assert.equal(merged.items[0].durationMs, 9 * 3600000 + 35 * 60000);
    assert.deepEqual(Array.from(merged.items[0].recordBookKeys).sort(), ['android', 'shelf']);
  }
  assert.equal(Summary.calculate([imported, shelf], 'all', ...at).items.length, 2, 'no dictionary: compared as written');
  assert.equal(Summary.calculate([{ ...imported, name: '北大硕士科举:震惊满朝' },
    { ...shelf, name: '北大硕士科举：震惊满朝' }], 'all', ...at).items.length, 1, 'full-width punctuation folds without a dictionary');
  // 一边没有作者：书架上同名的只有一本时并进去，两个方向都要成立。
  assert.equal(Summary.calculate([{ ...imported, author: '' }, shelf], 'all', ...at, fold).items.length, 1);
  assert.equal(Summary.calculate([imported, { ...shelf, author: '' }], 'all', ...at, fold).items.length, 1);
  assert.equal(Summary.calculate([{ ...imported, author: '' }, { ...shelf, author: '' }], 'all', ...at, fold).items.length, 1);
  // 认不准的保持分开：同名带作者的有两部、书架上同名两本、或没有一本在书架上。
  assert.equal(Summary.calculate([{ ...imported, author: '' }, shelf,
    { ...shelf, bookKey: 'other', author: '另一位作者', onShelf: false }], 'all', ...at, fold).items.length, 3);
  assert.equal(Summary.calculate([{ ...imported, author: '' }, { ...shelf, author: '' },
    { ...shelf, bookKey: 'shelf-2', author: '' }], 'all', ...at, fold).items.length, 3);
  assert.equal(Summary.calculate([{ ...imported, author: '' },
    { ...shelf, author: '', onShelf: false }], 'all', ...at, fold).items.length, 2);
});
test('manual merges fold works into one row without touching records and split restores them', () => {
  const { ReadStatsSummary: S, ReadWorkMerges: Merges, ReadWorkIdentity: Identity } =
    load('core/stats/ReadStatsSummary.ts', {}, 'ReadStatsSummary,ReadWorkMerges,ReadWorkIdentity');
  const at = [date(2026, 11, 18), date(2026, 11, 19)];
  const off = { ...row('2026-11-17', 25 * 3600000, 'legacy-import', 'old'), name: '全职艺术家', author: '我最白',
    onShelf: false, bookUrl: 'old-url' };
  const shelf = { ...row('2026-11-18', 5 * 3600000, 'phone', 'shelf'), name: '全职艺术家', author: '我最白 著',
    coverUrl: 'cover', bookUrl: 'shelf-url' };
  const other = { ...row('2026-11-18', 3600000, 'phone', 'other'), name: '道诡异仙', author: '狐尾的笔' };
  const rows = [off, shelf, other];
  const plain = S.calculate(rows, 'all', ...at);
  assert.equal(plain.items.length, 3);
  assert.deepEqual(Array.from(S.sameTitleItems(plain.items, null, []), item => item.bookKey), ['old', 'shelf']);
  assert.equal(S.sameTitleItems(plain.items, null, ['全职艺术家']).length, 0, 'dismissed titles stay quiet');
  const member = (name, author) => ({ work: Identity.workKey(name, author), name, author });
  const a = member('全职艺术家', '我最白'), b = member('全职艺术家', '我最白 著'), c = member('道诡异仙', '狐尾的笔');
  let groups = Merges.combine([], [a, b], b.work);
  for (const order of [rows, [...rows].reverse()]) {
    const merged = S.calculate(order, 'all', ...at, null, groups);
    assert.equal(merged.items.length, 2);
    assert.equal(merged.totalMs, plain.totalMs);
    const item = merged.items[0];
    assert.equal(item.durationMs, 30 * 3600000); assert.equal(item.mergedWorks, 2);
    assert.equal(item.author, '我最白 著'); assert.equal(item.bookUrl, 'shelf-url'); assert(item.onShelf);
    assert.equal(item.workKey, b.work); assert.equal(item.editions.length, 2);
    assert.deepEqual(Array.from(item.recordBookKeys).sort(), ['old', 'shelf']);
    assert.equal(S.sameTitleItems(merged.items, null, []).length, 0);
  }
  const offMain = S.calculate(rows, 'all', ...at, null, Merges.combine([], [a, b], a.work)).items[0];
  assert.equal(offMain.author, '我最白', 'shows the chosen edition');
  assert.equal(offMain.bookUrl, 'shelf-url', 'still opens the shelf edition');
  const onlyOff = S.calculate([off, other], 'all', ...at, null, groups).items[0];
  assert.equal(onlyOff.author, '我最白'); assert.equal(onlyOff.mergedWorks, 2); assert(!onlyOff.onShelf);
  groups = Merges.combine(groups, [c, a], c.work);
  assert.equal(groups.length, 1, 'merging into an existing group absorbs it');
  assert.equal(groups[0].members.length, 3);
  assert.equal(S.calculate(rows, 'all', ...at, null, groups).items.length, 1);
  const stored = Merges.parse(JSON.stringify(groups));
  assert.equal(stored[0].main, c.work); assert.equal(stored[0].members.length, 3);
  assert.equal(Merges.parse('oops').length, 0);
  assert.equal(Merges.parse(JSON.stringify([{ main: a.work, members: [a] }])).length, 0);
  groups = Merges.remove(stored, c.work, c.work);
  assert.equal(groups[0].members.length, 2); assert.notEqual(groups[0].main, c.work);
  groups = Merges.remove(groups, groups[0].main, a.work);
  assert.equal(groups.length, 0, 'a group of one is dropped');
  assert.equal(Merges.remove(stored, c.work, '').length, 0);
  assert.equal(S.calculate(rows, 'all', ...at, null, groups).items.length, 3);
});

test('ranking sorts by recent reading, read days or title and keeps duration ranks', () => {
  const { ReadStatsSummary: S, ReadWorkMerges: Merges, ReadWorkIdentity: Identity } =
    load('core/stats/ReadStatsSummary.ts', {}, 'ReadStatsSummary,ReadWorkMerges,ReadWorkIdentity');
  const at = (key, h, m) => { const [y, mo, d] = key.split('-').map(Number); return date(y, mo, d, h, m); };
  const read = (key, minutes, book, h = 9, m = 0) => ({ ...row(key, minutes * 60000, 'phone', book),
    name: book, author: '作者', lastReadAt: at(key, h, m) });
  const rows = [read('2026-11-16', 300, '宿命之环'), read('2026-11-17', 60, '宿命之环'), read('2026-11-18', 60, '宿命之环'),
    read('2026-11-22', 30, '道诡异仙', 17, 40), read('2026-11-21', 30, '道诡异仙', 23, 30),
    read('2026-11-22', 90, '赤心巡天', 8, 5), { ...read('2026-11-19', 20, '沧元图'), lastReadAt: 0 }];
  const week = S.calculate(rows, 'week', date(2026, 11, 22), date(2026, 11, 22, 18, 2));
  const names = (sort, mode = 'week', items = week.items) => Array.from(S.sortItems(items, sort, mode), item => item.name);
  assert.deepEqual(names('duration'), ['宿命之环', '赤心巡天', '道诡异仙', '沧元图']);
  assert.deepEqual(names('recent'), ['道诡异仙', '赤心巡天', '沧元图', '宿命之环']);
  assert.deepEqual(names('days'), ['宿命之环', '道诡异仙', '赤心巡天', '沧元图'], 'ties fall back to the duration rank');
  assert.deepEqual(names('title'), ['沧元图', '赤心巡天', '道诡异仙', '宿命之环'], 'titles follow pinyin');
  assert.deepEqual(names('unknown'), names('duration'));
  assert.deepEqual(names('days', 'day'), names('duration', 'day'), 'day view has no read-day ordering');
  assert.equal(S.effectiveSort('days', 'day'), 'duration');
  assert.deepEqual(Array.from(week.items, item => item.rank), [1, 2, 3, 4], 'sorting copies the list');
  const by = name => week.items.find(item => item.name === name);
  assert.equal(by('宿命之环').readDays, 3);
  assert.equal(by('道诡异仙').lastReadAt, at('2026-11-22', 17, 40));
  const now = date(2026, 11, 22, 18, 2);
  assert.equal(S.recentLabel(by('道诡异仙'), 'week', now), '今天 17:40');
  assert.equal(S.recentLabel(by('道诡异仙'), 'day', now), '17:40');
  assert.equal(S.recentLabel({ ...by('道诡异仙'), lastDayKey: '2026-11-21', lastReadAt: at('2026-11-21', 23, 30) }, 'week', now), '昨天 23:30');
  assert.equal(S.recentLabel(by('宿命之环'), 'week', now), '11月18日');
  assert.equal(S.recentLabel(by('沧元图'), 'week', now), '11月19日', 'old records without a time show the date');
  assert.equal(S.recentLabel(by('沧元图'), 'day', now), '', 'day view without a time falls back to the share');
  assert.equal(S.recentLabel(by('宿命之环'), 'year', date(2027, 1, 3)), '2026年11月18日');
  const member = name => ({ work: Identity.workKey(name, '作者'), name, author: '作者' });
  const merged = S.calculate(rows, 'week', date(2026, 11, 22), now, null,
    Merges.combine([], [member('宿命之环'), member('道诡异仙')], member('宿命之环').work));
  const group = merged.items.find(item => item.mergedWorks === 2);
  assert(group, 'merged row exists');
  assert.equal(group.readDays, 5, 'merged rows union their read days');
  assert.equal(group.lastReadAt, at('2026-11-22', 17, 40), 'merged rows keep the latest read');
});

test('calendar periods cover leap days, year crossings, and daylight saving days', () => {
  assert.equal(Summary.range('month', date(2024, 2, 29)).endKey, '2024-02-29');
  assert.equal(Summary.range('week', date(2026, 1, 1)).startKey, '2025-12-29');
  assert.equal(Summary.range('week', date(2026, 3, 8)).endKey, '2026-03-08');
  assert.equal(Summary.range('year', date(2024, 2, 29)).endKey, '2024-12-31');
  const result = Summary.calculate([row('2026-03-02', 7 * 60000)], 'week', date(2026, 3, 8), date(2026, 3, 9));
  assert.equal(result.averageMs, 60000);
  assert.equal(Summary.dayKey(Summary.shift('month', date(2026, 1, 31), 1)), '2026-02-01');
});
test('all-time average starts at earliest visible record; year buckets sum accurately', () => {
  const rows = [row('2025-12-31', 60000), row('2026-01-01', 120000)];
  const all = Summary.calculate(rows, 'all', date(2026, 1, 1), date(2026, 1, 2));
  assert.equal(all.averageMs, 60000);
  assert.deepEqual(Array.from(all.bars, b => b.durationMs), [60000, 120000]);
  const year = Summary.calculate(rows, 'year', date(2026, 1, 1), date(2026, 1, 2));
  assert.equal(year.totalMs, 120000);
  assert.equal(year.bars.length, 12);
  assert.equal(Summary.calculate([], 'all', date(2026, 1, 1), date(2026, 1, 2)).averageMs, 0);
  assert.equal(Summary.duration(1), '不足1分钟');
});

class ResultSet {
  constructor(rows) { this.rows = rows; this.index = -1; this.keys = rows.length ? Object.keys(rows[0]) : []; }
  goToNextRow() { return ++this.index < this.rows.length; }
  goToFirstRow() { this.index = 0; return this.rows.length > 0; }
  getColumnIndex(key) { return this.keys.indexOf(key); }
  getString(index) { return String(this.rows[this.index][this.keys[index]] ?? ''); }
  getLong(index) { return Number(this.rows[this.index][this.keys[index]] ?? 0); }
  isColumnNull(index) { return this.rows[this.index][this.keys[index]] == null; }
  close() {}
}
class Predicates {
  constructor(table) { this.table = table; this.clauses = []; this.args = []; }
  equalTo(key, value) { this.clauses.push(`${key} = ?`); this.args.push(value); return this; }
  between(key, start, end) { this.clauses.push(`${key} BETWEEN ? AND ?`); this.args.push(start, end); return this; }
  and() { return this; }
}
async function database(t) {
  let progressMarks = 0;
  const sql = new DatabaseSync(':memory:');
  t.after(() => sql.close());
  sql.exec(`CREATE TABLE books (bookUrl TEXT PRIMARY KEY, name TEXT, author TEXT DEFAULT '', coverUrl TEXT DEFAULT '',
    customCoverUrl TEXT DEFAULT '', origin TEXT DEFAULT 'web', isPrivate INTEGER DEFAULT 0, pendingAddToShelf INTEGER DEFAULT 0);
    CREATE TABLE read_stats (dayKey TEXT, bookUrl TEXT, durationMs INTEGER, lastReadAt INTEGER, PRIMARY KEY(dayKey,bookUrl));`);
  const { appDb: db, ReadStatsEntry: Entry } = load('model/data/AppDatabase.ts', {
    ...syncModels, Book,
    relationalStore: { RdbPredicates: Predicates }, util: { generateRandomUUID: randomUUID },
    BookIdentity: { cloudIdentityValue: book => `identity:${book.bookUrl}` },
    CloudSyncChangeTracker: { markDataChanged() {}, markReadingProgressChanged() { progressMarks++; } }
  }, 'appDb, ReadStatsEntry');
  db.store = {
    executeSql: async (query, args = []) => sql.prepare(query).run(...args),
    querySql: async (query, args = []) => new ResultSet(sql.prepare(query).all(...args)),
    update: async (data, p) => sql.prepare(`UPDATE ${p.table} SET ${Object.keys(data).map(k => `${k}=?`)} WHERE ${p.clauses.join(' AND ')}`).run(...Object.values(data), ...p.args).changes,
    delete: async p => sql.prepare(`DELETE FROM ${p.table} WHERE ${p.clauses.join(' AND ')}`).run(...p.args).changes
  };
  db.getBook = async url => sql.prepare('SELECT * FROM books WHERE bookUrl=?').get(url) || null;
  db.getAllBooks = async () => sql.prepare('SELECT * FROM books').all();
  const migrate = db.migrateReadStats.bind(db);
  db.migrateReadStats = async () => { await migrate(); await db.migrateReadStatsSync(); };
  db.recordBookMutation = async () => {};
  db.deleteBookChapters = db.deleteBookCachedContent = db.deleteBookBookmarks = db.deleteBookAnnotations = async () => {};
  db.deleteAudioOfflineFiles = async () => [];
  const book = (url, name, isPrivate = 0) => sql.prepare('INSERT OR REPLACE INTO books (bookUrl,name,isPrivate) VALUES(?,?,?)').run(url, name, isPrivate);
  const entry = (overrides = {}) => Object.assign(new Entry(), {
    recordId: randomUUID(), bookUrl: 'book', dayKey: '2026-10-26', deviceId: 'phone', deviceName: '手机',
    durationMs: 60000, ownerId: 'alice', startedAt: date(2026,10,26), lastReadAt: date(2026,10,26)+60000
  }, overrides);
  return { sql, db, book, entry, progressMarks: () => progressMarks,
    query: (device = '', owner = 'alice') => db.getReadStatsByDayRange('0000-00-00', '9999-99-99', device, owner) };
}
test('legacy migration is resumable, preserves totals, snapshots and tombstones', async t => {
  const h = await database(t);
  h.book('book', '保留的书名');
  h.sql.exec("INSERT INTO read_stats VALUES ('2026-10-25','book',90000,0),('2026-10-24','missing',30000,0)");
  await h.db.migrateReadStats();
  await h.db.migrateReadStats();
  assert.equal(h.sql.prepare('SELECT COUNT(*) AS n FROM read_stats_records').get().n, 2);
  assert.equal((await h.query()).reduce((s,r)=>s+r.durationMs,0), 120000);
  assert.equal((await h.query()).find(r=>r.bookUrl==='book').name, '保留的书名');
  await h.db.deleteReadStatsForBook('book','0000-00-00','9999-99-99');
  await h.db.migrateReadStats();
  assert.equal((await h.query()).length, 1);
  assert.equal(h.sql.prepare('SELECT COUNT(*) AS n FROM read_stats_records').get().n, 2);
});
test('day rows carry the latest read time across records of that day', async t => {
  const h = await database(t);
  h.book('book', '书'); await h.db.migrateReadStats();
  await h.db.addReadStats([h.entry({ lastReadAt: date(2026,10,26,9) }), h.entry({ lastReadAt: date(2026,10,26,21,30) }),
    h.entry({ deviceId: 'tablet', lastReadAt: date(2026,10,26,22) })]);
  const rows = await h.query('phone');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].durationMs, 120000);
  assert.equal(rows[0].lastReadAt, date(2026,10,26,21,30));
});
test('record retries are idempotent, account/device scopes isolate and deletion stays scoped', async t => {
  const h = await database(t);h.book('book','原名');await h.db.migrateReadStats();
  const first=h.entry();await h.db.addReadStats([first, first]);
  await h.db.addReadStats([h.entry({deviceId:'tablet'}),h.entry({ownerId:'bob'}),h.entry({ownerId:''})]);
  assert.equal((await h.query()).reduce((s,r)=>s+r.durationMs,0),180000);
  assert.equal((await h.query('phone')).reduce((s,r)=>s+r.durationMs,0),120000);
  assert.equal((await h.query('','')).reduce((s,r)=>s+r.durationMs,0),60000);
  await h.db.deleteReadStatsSelection('identity:book','2026-10-26','2026-10-26','phone','alice');
  await h.db.addReadStats([first]);
  assert.equal((await h.query()).reduce((s,r)=>s+r.durationMs,0),60000);
  assert.equal((await h.query('','bob')).reduce((s,r)=>s+r.durationMs,0),60000);
  assert.equal((await h.db.getReadStatsDevices('alice')).length,1);
});

test('Android history import preserves off-shelf titles, merges larger totals and respects tombstones', async t => {
  const h = await database(t);
  await h.db.migrateReadStats();
  const first = h.entry({ recordId: 'android-read:stable', ownerId: '', deviceId: 'legacy-import',
    deviceName: 'Android 阅读导入', bookUrl: 'android-history://missing', durationMs: 49809 });
  await h.db.restoreAndroidReadStats(first, '离架小说', '作者');
  await h.db.restoreAndroidReadStats(first, '离架小说', '作者');
  let rows = await h.query('', '');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].name, '离架小说');
  assert.equal(rows[0].author, '作者');
  assert.equal(rows[0].onShelf, false);
  assert.equal(rows[0].durationMs, 49809);
  await h.db.restoreAndroidReadStats({ ...first, durationMs: 60000 }, '离架小说', '作者');
  await h.db.restoreAndroidReadStats(first, '离架小说', '作者');
  rows = await h.query('', '');
  assert.equal(rows[0].durationMs, 60000);
  assert.equal(h.sql.prepare('SELECT COUNT(*) AS n FROM books').get().n, 0);
  await h.db.deleteReadStatsForBook(first.bookUrl, '0000-00-00', '9999-99-99');
  await h.db.restoreAndroidReadStats({ ...first, durationMs: 90000 }, '离架小说', '作者');
  assert.equal((await h.query('', '')).length, 0);
  assert.equal(h.sql.prepare('SELECT COUNT(*) AS n FROM read_stats_records').get().n, 1);
});
test('deleted books retain latest title and private books stay hidden after removal', async t => {
  const h = await database(t);h.book('book','旧名');await h.db.migrateReadStats();
  await h.db.addReadStats([h.entry()]);h.book('book','新名');await h.db.deleteBook('book');
  const rows=await h.query();assert.equal(rows[0].name,'新名');assert.equal(rows[0].onShelf,false);
  h.book('secret','隐私书',1);await h.db.addReadStats([h.entry({bookUrl:'secret'})]);
  await h.db.deleteBook('secret');assert.equal((await h.query()).length,1);
  h.book('secret','隐私书',0);assert.equal((await h.query()).length,2);
});

test('privacy toggles persist in snapshots and visible selection cannot delete hidden records', async t => {
  const h = await database(t);h.book('book','普通书');await h.db.migrateReadStats();
  await h.db.addReadStats([h.entry()]);
  await h.db.setBookPrivate('book',true);
  assert.equal((await h.query()).length,0);
  await h.db.deleteReadStatsSelection('identity:book','2026-10-26','2026-10-26','','alice');
  assert.equal(h.sql.prepare('SELECT deletedAt FROM read_stats_records').get().deletedAt,0);
  h.sql.prepare('DELETE FROM books WHERE bookUrl=?').run('book');
  assert.equal((await h.query()).length,0);
  h.book('book','普通书');await h.db.setBookPrivate('book',false);
  assert.equal((await h.query()).length,1);
});

test('tracker splits midnight and account changes, retries preserve original IDs', async () => {
  let now=date(2026,10,25,23,59),fail=false;
  const saved=new Map();
  class Clock extends Date { constructor(...args){super(...(args.length?args:[now]));}static now(){return now;} }
  class Entry { recordId='';ownerId='';deviceId='';deviceName='';startedAt=0;timezoneOffset=0;dayKey='';bookUrl='';durationMs=0;lastReadAt=0; }
  const db={init:async()=>{},addReadStats:async entries=>{for(const e of entries)saved.set(e.recordId,{...e});if(fail)throw new Error('simulated partial write');}};
  const {readStatsTracker: tracker}=load('core/stats/ReadStatsTracker.ts',{
    Date:Clock,ReadStatsEntry:Entry,util:{generateRandomUUID:randomUUID},appDb:db,
    ReadStatsDevice:{id:async()=> 'phone',displayName:()=> '手机'},setInterval:()=>1,clearInterval(){},console:{warn(){}}
  },'readStatsTracker');
  tracker.init({});tracker.setReadingActive('book');now+=120000;await tracker.flushAndWait();
  assert.deepEqual([...saved.values()].map(e=>e.dayKey),['2026-10-25','2026-10-26']);
  assert.equal([...saved.values()].reduce((s,e)=>s+e.durationMs,0),120000);
  tracker.setOwnerId('alice');now+=60000;fail=true;await assert.rejects(tracker.flushAndWait());
  const count=saved.size;fail=false;await tracker.flushAndWait();assert.equal(saved.size,count);
  tracker.setOwnerId('bob');now+=60000;tracker.setTtsActive('book');now+=60000;await tracker.flushAndWait();
  assert.equal([...saved.values()].filter(e=>e.ownerId==='alice').reduce((s,e)=>s+e.durationMs,0),60000);
  assert.equal([...saved.values()].filter(e=>e.ownerId==='bob').reduce((s,e)=>s+e.durationMs,0),120000);
});

test('durable stats outbox excludes guests, private data and unportable local identities', async t => {
  const h = await database(t); h.book('book', '公开书'); h.book('secret', '私密书', 1);
  await h.db.migrateReadStats();
  h.sql.prepare('UPDATE books SET customCoverUrl=? WHERE bookUrl=?').run('/data/private/cover.jpg', 'book');
  await h.db.addReadStats([h.entry(), h.entry({ ownerId: '' }), h.entry({ ownerId: 'bob' }),
    h.entry({ bookUrl: 'secret' }), h.entry({ deviceId: 'another-device' }), h.entry({ bookUrl: 'local:file-path' })]);
  const boundary = await h.db.getReadStatsUploadBoundary();
  const uploads = await h.db.getPendingReadStats('alice', 'phone', boundary);
  assert.equal(uploads.length, 1);
  assert.equal(uploads[0].operation.payload.coverUrl, '');
  assert.equal(uploads[0].operation.payload.name, '公开书');
  assert.equal('bookUrl' in uploads[0].operation.payload, false);
  assert.equal('ownerId' in uploads[0].operation.payload, false);
  // New readings arriving during a long initial sync are left for the next run.
  await h.db.addReadStats([h.entry()]);
  await h.db.acknowledgeReadStats('alice', uploads, uploads.map(u => ({ recordId: u.operation.recordId, deleted: false })));
  assert.equal((await h.db.getPendingReadStats('alice', 'phone', boundary)).length, 0);
  assert.equal((await h.db.getPendingReadStats('alice', 'phone', await h.db.getReadStatsUploadBoundary())).length, 1);
  await h.db.setBookPrivate('secret', false);
  assert.equal((await h.db.getPendingReadStats('alice', 'phone', await h.db.getReadStatsUploadBoundary()))
    .some(u => u.operation.payload?.name === '私密书'), false);
});

test('downloaded records preserve device/title, sum once, remain private and never become upload deltas', async t => {
  const h = await database(t); await h.db.migrateReadStats();
  const payload = Object.assign(new syncModels.ReadStatsSyncPayload(), { deviceId: 'tablet', deviceName: '平板',
    bookKey: 'identity:book', name: '远端已删除的书名', dayKey: '2026-10-26', durationMs: 60000,
    startedAt: date(2026,10,26), lastReadAt: date(2026,10,26)+60000 });
  const change = { recordId: randomUUID(), sequenceId: 1, deleted: false, payload };
  await h.db.applyReadStatsChanges('alice', [change, change]);
  assert.equal((await h.query())[0].name, payload.name);
  assert.equal((await h.query())[0].onShelf, false);
  assert.equal((await h.query()).reduce((sum,r) => sum+r.durationMs,0), 60000);
  assert.equal((await h.query('', 'bob')).length, 0);
  assert.equal((await h.db.getPendingReadStats('alice', 'phone', 99999)).length, 0);
  h.book('book', '本机同一本书');
  await h.db.setBookPrivate('book', true);
  assert.equal((await h.query()).length, 0);
  const redactions = await h.db.getPendingReadStats('alice', 'phone', 99999);
  assert.equal(redactions.length, 1); assert.equal(redactions[0].operation.payload, null);
  // A replay received after making a matching local book private cannot disclose its remote snapshot.
  await h.db.applyReadStatsChanges('alice', [change]);
  assert.equal((await h.query()).length, 0);
  // Deleting the local private book must not let a later page clear the retained privacy flag.
  await h.db.deleteBook('book');
  await h.db.applyReadStatsChanges('alice', [change]);
  assert.equal((await h.query()).length, 0);
});

test('in-flight upsert acknowledgements cannot swallow newer deletion or privacy retraction', async t => {
  const h = await database(t); h.book('book','书'); await h.db.migrateReadStats();
  const entry = h.entry(); await h.db.addReadStats([entry]);
  const sent = await h.db.getPendingReadStats('alice', 'phone', 99999);
  await h.db.deleteReadStatsSelection('identity:book','2026-10-26','2026-10-26','','alice');
  await h.db.applyReadStatsChanges('alice', [{ recordId: entry.recordId, sequenceId: 1, deleted: false,
    payload: sent[0].operation.payload }]);
  await h.db.acknowledgeReadStats('alice', sent, [{ recordId: entry.recordId, deleted: false }]);
  assert.equal((await h.query()).length,0);
  const deletion = await h.db.getPendingReadStats('alice','phone',99999);
  assert.equal(deletion.length,1); assert.equal(deletion[0].operation.deleted,true);
  await h.db.acknowledgeReadStats('alice',deletion,[{recordId:entry.recordId,deleted:true}]);
  assert.equal((await h.db.getPendingReadStats('alice','phone',99999)).length,0);

  const other=h.entry(); await h.db.addReadStats([other]);
  const beforePrivate=await h.db.getPendingReadStats('alice','phone',99999);
  await h.db.setBookPrivate('book',true);
  await h.db.acknowledgeReadStats('alice',beforePrivate,[{recordId:other.recordId,deleted:false}]);
  const privacy=await h.db.getPendingReadStats('alice','phone',99999);
  assert.ok(privacy.every(u=>u.operation.deleted && u.operation.payload===null));
  await h.db.applyReadStatsChanges('alice',[{recordId:other.recordId,sequenceId:2,deleted:true,payload:null}]);
  await h.db.setBookPrivate('book',false);
  assert.equal((await h.query()).reduce((sum,r)=>sum+r.durationMs,0),60000);
  await h.db.applyReadStatsChanges('alice',[{recordId:other.recordId,sequenceId:1,deleted:false,
    payload:beforePrivate[0].operation.payload}]);
  assert.equal((await h.query()).reduce((sum,r)=>sum+r.durationMs,0),60000);
});

test('client coordinator resumes lost responses and partial pages; cursor advances only after successful apply', async t => {
  const h=await database(t);h.book('book','书');await h.db.migrateReadStats();
  const original=h.entry();await h.db.addReadStats([original]);
  const cloud=new Map();let sequence=0, failAfterCommit=true, requested=0, session='alice';
  const {ReadStatsCloudSync:sync}=load('account/ReadStatsCloudSync.ets',{
    ...syncModels, AppStorage:{get(){return 0},setOrCreate(){}},
    readStatsTracker:{flushAndWait:async()=>{}},AccountApiError:class extends Error{},
    AccountSessionStore:{isLoggedIn:()=>true,account:()=>({userId:session}),token:()=>session},
  AccountCommerceApi:{fetchSyncDevices:async()=>({devices:[]}),exchangeReadStats:async req=>{
      requested++;
      for(const op of req.operations){if(!cloud.has(op.recordId)||op.deleted) cloud.set(op.recordId,{...op,sequenceId:++sequence});}
      if(failAfterCommit){failAfterCommit=false;throw new Error('response lost');}
      const changes=[...cloud.values()].filter(c=>c.sequenceId>req.cursor).sort((a,b)=>a.sequenceId-b.sequenceId);
      return {protocolVersion:1,acknowledgements:req.operations.map(op=>({recordId:op.recordId,deleted:cloud.get(op.recordId).deleted})),
        changes,nextCursor:changes.at(-1)?.sequenceId??req.cursor,hasMore:false};
    }}
  },'ReadStatsCloudSync');
  await assert.rejects(sync.run(h.db,'alice','phone','alice'),/response lost/);
  assert.equal(await h.db.getReadStatsSyncCursor('alice'),0);
  assert.equal((await h.db.getPendingReadStats('alice','phone',99999)).length,1);
  const apply=h.db.applyReadStatsChanges.bind(h.db);let failApply=true;
  h.db.applyReadStatsChanges=async(...args)=>{await apply(...args);if(failApply){failApply=false;throw new Error('disk failure');}};
  await assert.rejects(sync.run(h.db,'alice','phone','alice'),/disk failure/);
  assert.equal(await h.db.getReadStatsSyncCursor('alice'),0);
  await sync.run(h.db,'alice','phone','alice');
  assert.equal(cloud.size,1);assert.equal((await h.query()).reduce((sum,r)=>sum+r.durationMs,0),60000);
  assert.equal(await h.db.getReadStatsSyncCursor('alice'),1);
  assert.equal((await h.db.getPendingReadStats('alice','phone',99999)).length,0);
  session='bob';const before=requested;
  await assert.rejects(sync.run(h.db,'alice','phone','alice'),/账号已切换/);
  assert.equal(requested,before);
});

test('malformed protocol pages do not pass validation or advance cursor', () => {
  const {ReadStatsCloudSync:sync}=load('account/ReadStatsCloudSync.ets',{},'ReadStatsCloudSync');
  const request={cursor:5,operations:[]};
  for(const response of [
    {protocolVersion:1,acknowledgements:[],changes:[],nextCursor:6,hasMore:false},
    {protocolVersion:1,acknowledgements:[],changes:[],nextCursor:5,hasMore:true},
    {protocolVersion:2,acknowledgements:[],changes:[],nextCursor:5,hasMore:false}
  ]) assert.throws(()=>sync.validate(response,request));
});

test('switching accounts while a response is in flight stops application and cursor advancement', async () => {
  let session='alice', applied=0;
  const db={getReadStatsUploadBoundary:async()=>0,getReadStatsSyncCursor:async()=>0,
    getPendingReadStats:async()=>[],applyReadStatsChanges:async()=>{applied++},
    acknowledgeReadStats:async()=>{applied++},setReadStatsSyncCursor:async()=>{applied++}};
  const {ReadStatsCloudSync:sync}=load('account/ReadStatsCloudSync.ets',{
    ...syncModels,AccountApiError:class extends Error{},
    AccountSessionStore:{isLoggedIn:()=>true,account:()=>({userId:session}),token:()=>session},
    AccountCommerceApi:{exchangeReadStats:async(req,token)=>{
      assert.equal(token,'alice');session='bob';
      return {protocolVersion:1,acknowledgements:[],changes:[],nextCursor:0,hasMore:false};
    }}
  },'ReadStatsCloudSync');
  await assert.rejects(sync.run(db,'alice','phone','alice'),/账号已切换/);
  assert.equal(applied,0);
});

// Real SQLite outbox + production exchange loop, with only HTTP and native storage substituted.
async function exchangeHarness(t) {
  const h = await database(t); h.book('book', '书'); await h.db.migrateReadStats();
  let now = 10000000, user = 'alice', token = 'alice', fetches = 0, hook = async () => {};
  const requests = [], cloud = [], names = [];
  const { ReadStatsCloudSync: sync } = load('account/ReadStatsCloudSync.ets', {
    ...syncModels, ReadStatsDeviceOption: class {}, Date: class extends Date { static now() { return now; } },
    AppStorage: { get() { return 0; }, setOrCreate() {} }, AccountApiError: class extends Error {},
    AccountSessionStore: { isLoggedIn: () => true, account: () => ({ userId: user }), token: () => token },
    AccountCommerceApi: {
      fetchSyncDevices: async () => { fetches++; return { devices: names }; },
      exchangeReadStats: async req => {
        requests.push(req.operations.length);
        for (const op of req.operations) cloud.push({ ...op, sequenceId: cloud.length + 1 });
        await hook(req);
        const remaining = cloud.filter(c => c.sequenceId > req.cursor);
        const changes = remaining.slice(0, 100);
        return { protocolVersion: 1, acknowledgements: req.operations.map(op => ({ recordId: op.recordId, deleted: op.deleted })),
          changes, nextCursor: changes.at(-1)?.sequenceId ?? req.cursor, hasMore: remaining.length > 100 };
      }
    }
  }, 'ReadStatsCloudSync');
  return { ...h, sync, requests, cloud, names, fetches: () => fetches,
    advance: ms => { now += ms; }, session: (u, tok = u) => { user = u; token = tok; },
    hook: value => { hook = value; }, run: (force = false) => sync.run(h.db, user, 'phone', token, force) };
}

test('60 saved minutes upload in one exchange; no general dirty mark or trailing empty request', async t => {
  const h = await exchangeHarness(t);
  await h.db.addReadStats(Array.from({ length: 60 }, () => h.entry()));
  assert.equal(h.progressMarks(), 0);
  const result = await h.run();
  assert.equal(result.uploaded, 60);
  assert.deepEqual(h.requests, [60]);
  assert.equal(h.fetches(), 1);
  assert.equal((await h.query()).reduce((n, r) => n + r.durationMs, 0), 3600000);
});

test('upload and download pagination drains completely without a final empty exchange', async t => {
  const h = await exchangeHarness(t);
  await h.db.addReadStats(Array.from({ length: 205 }, () => h.entry()));
  assert.equal((await h.run()).uploaded, 205);
  assert.deepEqual(h.requests, [100, 100, 5]);
  h.requests.length = 0;
  const payload = h.cloud[0].payload;
  for (let i = 0; i < 201; i++) h.cloud.push({ recordId: randomUUID(), deleted: false,
    payload: { ...payload, deviceId: 'tablet' }, sequenceId: h.cloud.length + 1 });
  assert.equal((await h.run()).downloaded, 201);
  assert.deepEqual(h.requests, [0, 0, 0]);
  assert.equal(await h.db.getReadStatsSyncCursor('alice'), 406);
});

test('device names cache expires, manual refresh bypasses it, and sessions cannot share it', async t => {
  const h = await exchangeHarness(t);
  await h.db.addReadStats([h.entry()]); await h.run();
  h.names.push({ deviceId: 'phone', deviceName: '新名称' });
  h.advance(60000); await h.run(); assert.equal(h.fetches(), 1);
  await h.run(true); assert.equal(h.fetches(), 2);
  assert.equal(h.sql.prepare('SELECT deviceName FROM read_stats_records LIMIT 1').get().deviceName, '新名称');
  h.advance(30 * 60000); await h.run(); assert.equal(h.fetches(), 3);
  h.session('alice', 'new-token'); await h.run(); assert.equal(h.fetches(), 4);
  h.session('bob'); await h.run(); assert.equal(h.fetches(), 5);
});

test('new records in flight stay queued beyond the captured upload boundary', async t => {
  const h = await exchangeHarness(t);
  await h.db.addReadStats([h.entry()]);
  let added = false;
  h.hook(async () => { if (!added) { added = true; await h.db.addReadStats([h.entry()]); } });
  assert.equal((await h.run()).uploaded, 1);
  assert.deepEqual(h.requests, [1]);
  assert.equal((await h.db.getPendingReadStats('alice', 'phone', 99999)).length, 1);
  assert.equal((await h.run()).uploaded, 1);
  assert.deepEqual(h.requests, [1, 1]);
});

test('a deletion created during upload is sent before ending the same run', async t => {
  const h = await exchangeHarness(t);
  await h.db.addReadStats([h.entry()]); let deleted = false;
  h.hook(async () => {
    if (!deleted) { deleted = true; await h.db.deleteReadStatsForBook('book', '0000-00-00', '9999-99-99'); }
  });
  await h.run();
  assert.deepEqual(h.requests, [1, 1]);
  assert.equal(h.cloud.at(-1).deleted, true);
  assert.equal((await h.db.getPendingReadStats('alice', 'phone', 99999)).length, 0);
  assert.equal((await h.query()).length, 0);
});
