// Production cache services + production SQL, with isolated SQLite/files/clock. No user data or network.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import { readEtsModule } from './ets-module-staging.mjs';

export function harness() {
  const sql = new DatabaseSync(':memory:');
  const dbSource = readEtsModule('model/data/AppDatabase.ts');
  sql.exec(dbSource.match(/CREATE TABLE IF NOT EXISTS book_contents \([\s\S]*?\n      \)/)[0]);
  sql.exec(`ALTER TABLE book_contents ADD COLUMN cacheRevision INTEGER DEFAULT 0;
    ALTER TABLE book_contents ADD COLUMN imagesIndexed INTEGER DEFAULT 0;
    CREATE TABLE books(bookUrl TEXT PRIMARY KEY,origin TEXT);
    CREATE TABLE reader_pagination_cache(bookUrl TEXT,chapterIndex INTEGER);
    CREATE TABLE reader_image_refs(bookUrl TEXT,chapterIndex INTEGER,path TEXT,PRIMARY KEY(bookUrl,chapterIndex,path));
    CREATE TABLE reader_image_resources(path TEXT PRIMARY KEY,sourceUrl TEXT,raw TEXT,imageIndex INTEGER,bytes INTEGER,usedAt INTEGER,state TEXT);`);
  let now = 1800000000000;
  const metrics = { scans: 0 };
  let onStat = null;
  let seq = 0;
  let failWrites = false;
  let failCopy = false;
  let failSql = '';
  const timers = new Map();
  const files = new Map();
  const handles = new Map();
  const directories = new Set(['/cache/comic_images', '/files/reader_images']);
  const stamp = () => now / 1000;
  const io = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4, READ_ONLY: 8 },
    accessSync: p => files.has(p) || directories.has(p),
    statSync(p) { const f = files.get(p); if (!f) throw Error('ENOENT'); return { size: f.size, mtime: f.mtime, isFile: () => true }; },
    async stat(p) { const result = io.statSync(p); if (onStat) await onStat(p); return result; },
    async listFile(dir) { metrics.scans++; return [...files.keys()].filter(p => p.startsWith(dir + '/')).map(p => p.slice(dir.length + 1)); },
    mkdirSync: p => directories.add(p),
    openSync(p) { const fd = ++seq; handles.set(fd, p); files.set(p, { size: 0, mtime: stamp(), data: new Uint8Array() }); return { fd }; },
    writeSync(fd, bytes) {
      if (failWrites) throw Error('ENOSPC');
      const f = files.get(handles.get(fd)); const input = new Uint8Array(bytes);
      const next = new Uint8Array(f.data.length + input.length); next.set(f.data); next.set(input, f.data.length);
      f.data = next; f.size = next.length; f.mtime = stamp(); return input.length;
    },
    fsyncSync() {}, closeSync() {},
    unlinkSync(p) { if (!files.delete(p)) throw Error('ENOENT'); },
    renameSync(a, b) { if (!files.has(a)) throw Error('ENOENT'); files.set(b, files.get(a)); files.delete(a); },
    async copyFile(a, b) { if (failCopy) throw Error('ENOSPC'); const f = files.get(a); if (!f) throw Error('ENOENT'); files.set(b, { ...f, mtime: stamp(), data: f.data.slice() }); }
  };
  const rs = (query, params = []) => {
    const statement = sql.prepare(query), keys = statement.columns().map(c => c.name), rows = statement.all(...params);
    let at = -1;
    return { rowCount: rows.length, goToFirstRow: () => { at = 0; return !!rows[at]; }, goToNextRow: () => !!rows[++at],
      getColumnIndex: n => keys.indexOf(n), getLong: i => Number(rows[at][keys[i]] || 0), getString: i => String(rows[at][keys[i]] || ''), close() {} };
  };
  class Predicates {
    constructor(table) { this.table = table; this.conditions = []; this.params = []; }
    equalTo(k, v) { this.conditions.push(`${k}=?`); this.params.push(v); return this; }
    where() { return this.conditions.length ? ' WHERE ' + this.conditions.join(' AND ') : ''; }
  }
  const store = {
    async executeSql(query, params = []) {
      if (failSql && query.includes(failSql)) throw Error('injected SQL failure');
      sql.prepare(query).run(...params);
    },
    async querySql(query, params = []) { return rs(query, params); },
    async query(p, columns) { return rs(`SELECT ${columns.length ? columns.join(',') : '*'} FROM ${p.table}${p.where()}`, p.params); },
    async update(values, p) { return Number(sql.prepare(`UPDATE ${p.table} SET ${Object.keys(values).map(k => k + '=?').join(',')}${p.where()}`).run(...Object.values(values), ...p.params).changes); },
    async delete(p) { return Number(sql.prepare(`DELETE FROM ${p.table}${p.where()}`).run(...p.params).changes); },
    async createTransaction() {
      sql.exec('BEGIN');
      return { ...store, execute: store.executeSql, async commit() { sql.exec('COMMIT'); }, async rollback() { sql.exec('ROLLBACK'); } };
    }
  };
  const context = vm.createContext({ fs: io, console: { info() {}, warn() {}, error() {}, log() {} },
    Date: class extends Date { static now() { return now; } },
    setTimeout(fn, delay) { const id = ++seq; if (!delay) queueMicrotask(fn); else timers.set(id, { fn, due: now + delay }); return id; },
    clearTimeout: id => timers.delete(id), setInterval() { return 0; }, clearInterval() {},
    AppStorage: { get: key => key === 'appFilesDir' ? '/files' : '/cache' },
    relationalStore: { RdbPredicates: Predicates },
    ReaderOpenTrace: { mark() {} }, ReaderActionMarker: { hasLegacy: () => false },
    HttpClient: class { static CANCELLED_ERROR = 'cancelled'; },
    BookSource: class {},
  });
  const load = relative => vm.runInContext(stripTypeScriptTypes(readEtsModule(relative)
    .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, '')), context, { filename: relative });
  for (const name of ['ReaderCacheCoordinator', 'ReaderImageMarker', 'ReaderImageReferences', 'ReaderCacheBudgetPolicy']) load(`core/book/${name}.ts`);
  load('model/data/AppDatabase.ts');
  for (const name of ['ReaderImageCache', 'ReaderCacheBudget', 'ReaderImageScheduler', 'ReaderImageResults', 'WebBookService', 'ReadBookEngine', 'ReaderImageRecovery']) load(`core/book/${name}.ts`);
  const api = vm.runInContext('({ db: appDb, Budget: ReaderCacheBudget, Cache: ReaderImageCache, Coordinator: ReaderCacheCoordinator, Marker: ReaderImageMarker, Engine: ReadBookEngine, Recovery: ReaderImageRecovery, Resource: ReaderImageResource })', context);
  api.db.store = store;
  api.db.getBookSource = async () => ({ bookSourceUrl: 'source' });
  const chapter = index => ({ index, url: 'chapter-' + index, title: 'Chapter ' + index, cacheDate: 0 });
  const put = (path, size = 100, age = 3600000) => files.set(path, { size, mtime: (now - age) / 1000, data: new Uint8Array(Math.min(size, 1000)) });
  return { ...api, sql, store, context, files, timers, chapter, put, metrics, onStat: callback => { onStat = callback; }, load, now: () => now, age: ms => { now += ms; },
    failWrites: v => { failWrites = v; }, failCopy: v => { failCopy = v; }, failSql: v => { failSql = v; },
    async advance(ms) {
      now += ms;
      for (const [id, timer] of [...timers]) if (timer.due <= now) { timers.delete(id); timer.fn(); }
      await api.Budget.chain;
      await api.Coordinator.chain;
    },
    close() { sql.close(); }
  };
}
