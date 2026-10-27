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
    ...syncModels,
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
  db.deleteBookChapters = db.deleteBookCachedContent = db.deleteBookBookmarks = async () => {};
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
