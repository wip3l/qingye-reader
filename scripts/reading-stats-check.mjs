// Executes production aggregation, migration SQL and tracker logic. Native UI is checked by the HAP build.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { randomUUID } from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

process.env.TZ = 'America/Denver';
const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(file, globals, names) {
  const code = fs.readFileSync(new URL(file, root), 'utf8').replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, '');
  const context = vm.createContext({ console, ...globals });
  vm.runInContext(stripTypeScriptTypes(code, { mode: 'strip' }) + `\nthis.exports={${names}};`, context);
  return context.exports;
}
const { ReadStatsSummary: Summary } = load('core/stats/ReadStatsSummary.ts', {}, 'ReadStatsSummary');
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
  const sql = new DatabaseSync(':memory:');
  t.after(() => sql.close());
  sql.exec(`CREATE TABLE books (bookUrl TEXT PRIMARY KEY, name TEXT, author TEXT DEFAULT '', coverUrl TEXT DEFAULT '',
    customCoverUrl TEXT DEFAULT '', origin TEXT DEFAULT 'web', isPrivate INTEGER DEFAULT 0, pendingAddToShelf INTEGER DEFAULT 0);
    CREATE TABLE read_stats (dayKey TEXT, bookUrl TEXT, durationMs INTEGER, lastReadAt INTEGER, PRIMARY KEY(dayKey,bookUrl));`);
  const { appDb: db, ReadStatsEntry: Entry } = load('model/data/AppDatabase.ts', {
    relationalStore: { RdbPredicates: Predicates }, util: { generateRandomUUID: randomUUID },
    BookIdentity: { cloudIdentityValue: book => `identity:${book.bookUrl}` },
    CloudSyncChangeTracker: { markDataChanged() {} }
  }, 'appDb, ReadStatsEntry');
  db.store = {
    executeSql: async (query, args = []) => sql.prepare(query).run(...args),
    querySql: async (query, args = []) => new ResultSet(sql.prepare(query).all(...args)),
    update: async (data, p) => sql.prepare(`UPDATE ${p.table} SET ${Object.keys(data).map(k => `${k}=?`)} WHERE ${p.clauses.join(' AND ')}`).run(...Object.values(data), ...p.args).changes,
    delete: async p => sql.prepare(`DELETE FROM ${p.table} WHERE ${p.clauses.join(' AND ')}`).run(...p.args).changes
  };
  db.getBook = async url => sql.prepare('SELECT * FROM books WHERE bookUrl=?').get(url) || null;
  db.recordBookMutation = async () => {};
  db.deleteBookChapters = db.deleteBookCachedContent = db.deleteBookBookmarks = async () => {};
  const book = (url, name, isPrivate = 0) => sql.prepare('INSERT OR REPLACE INTO books (bookUrl,name,isPrivate) VALUES(?,?,?)').run(url, name, isPrivate);
  const entry = (overrides = {}) => Object.assign(new Entry(), {
    recordId: randomUUID(), bookUrl: 'book', dayKey: '2026-10-26', deviceId: 'phone', deviceName: '手机',
    durationMs: 60000, ownerId: 'alice', startedAt: date(2026,10,26), lastReadAt: date(2026,10,26)+60000
  }, overrides);
  return { sql, db, book, entry, query: (device = '', owner = 'alice') => db.getReadStatsByDayRange('0000-00-00', '9999-99-99', device, owner) };
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
