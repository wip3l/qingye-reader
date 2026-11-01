// Runs the production backup service against temporary files and in-memory DB/preferences.
// HarmonyOS ZIP and crypto are substituted here; device integration is covered by the HAP build/manual QA.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';
import { execFileSync } from 'node:child_process';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const plain = value => JSON.parse(JSON.stringify(value));
const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

function harness(t, nestedTarget = false) {
  const prefix = path.join(os.tmpdir(), 'qingye-backup-check-');
  const root = fs.mkdtempSync(prefix);
  t.after(() => {
    assert.ok(path.resolve(root).startsWith(path.resolve(prefix)));
    fs.rmSync(root, { recursive: true, force: true });
  });
  const states = new Map();
  const makeDevice = name => {
    const filesDir = path.join(root, name, 'files').replaceAll('\\', '/');
    const tempDir = path.join(root, name, 'temp').replaceAll('\\', '/');
    fs.mkdirSync(filesDir, { recursive: true });
    fs.mkdirSync(tempDir, { recursive: true });
    const context = { filesDir, tempDir };
    states.set(filesDir, { prefs: new Map(), books: new Map(), sources: [], addedTimes: new Map(), groups: [], bookmarks: [], keywords: [], readRecords: new Map() });
    return context;
  };
  const source = makeDevice('source');
  const target = makeDevice(nestedTarget ? 'source/files/migrated' : 'target');
  let active;
  let failCopy = '';
  const db = {
    initWithContext: async context => { active = states.get(context.filesDir); },
    getAllBookSources: async () => active.sources,
    getAllBooks: async () => [...active.books.values()],
    getCustomBookGroups: async () => active.groups,
    addBookGroup: async name => {
      const group = { groupId: 2 ** active.groups.length, groupName: name, order: 0, show: true, enableRefresh: true };
      active.groups.push(group);
      return group;
    },
    getBookSourceSummaries: async () => active.sources,
    restoreAndroidReadStats: async (record, name, author) => {
      const old = active.readRecords.get(record.recordId);
      if (!old || old.durationMs < record.durationMs) active.readRecords.set(record.recordId, { ...plain(record), name, author });
    },
    getAllBookmarks: async () => active.bookmarks,
    getSearchKeywords: async () => active.keywords,
    getBook: async url => active.books.get(url),
    restoreBook: async book => active.books.set(book.bookUrl, book),
    updateBook: async book => active.books.set(book.bookUrl, book),
    restoreBookSource: async value => active.sources.push(plain(value)),
    getBookSourceAddedTimes: async () => new Map(active.addedTimes),
    restoreBookSourceAddedTimes: async times => {
      for (const [url, time] of Object.entries(times)) active.addedTimes.set(url, time);
    },
    restoreBookGroup: async value => {
      const index = active.groups.findIndex(group => group.groupId === value.groupId);
      if (index < 0) active.groups.push(plain(value)); else active.groups[index] = plain(value);
    },
    restoreBookmark: async value => active.bookmarks.push(plain(value)),
    restoreSearchKeyword: async value => active.keywords.push(plain(value))
  };
  const handles = new Map();
  const platformFs = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 2, CREATE: 64, TRUNC: 512 },
    accessSync: fs.existsSync,
    stat: async file => fs.statSync(file),
    listFile: async file => fs.readdirSync(file),
    mkdir: async file => fs.mkdirSync(file, { recursive: true }),
    rmdir: async file => fs.rmdirSync(file),
    unlink: async file => fs.unlinkSync(file),
    open: async (file, mode) => {
      const fd = fs.openSync(file, mode & 64 ? 'w+' : mode === 0 ? 'r' : 'r+');
      handles.set(fd, file);
      return { fd };
    },
    close: async file => { fs.closeSync(file.fd); handles.delete(file.fd); },
    copyFile: async (src, dest) => {
      if (handles.get(src) === failCopy) throw new Error('simulated copy failure');
      fs.copyFileSync(handles.get(src), handles.get(dest));
    },
    read: async (fd, buffer, options = {}) => fs.readSync(fd, Buffer.from(buffer), 0,
      options.length ?? buffer.byteLength, options.offset ?? null),
    write: async (fd, buffer, options = {}) => fs.writeSync(fd, Buffer.from(buffer), 0,
      options.length ?? buffer.byteLength, options.offset ?? null)
  };
  const snapshot = dir => {
    const result = {};
    const walk = (current, relative = '') => {
      for (const name of fs.readdirSync(current)) {
        const absolute = path.join(current, name);
        const key = relative + name;
        if (fs.statSync(absolute).isDirectory()) walk(absolute, key + '/');
        else result[key] = fs.readFileSync(absolute).toString('base64');
      }
    };
    walk(dir);
    return result;
  };
  const zlib = {
    CompressLevel: { COMPRESS_LEVEL_BEST_SPEED: 1, COMPRESS_LEVEL_NO_COMPRESSION: 0 },
    compressFile: async (dir, archive) => fs.writeFileSync(archive, JSON.stringify(snapshot(dir))),
    decompressFile: async (archive, dir) => {
      for (const [relative, bytes] of Object.entries(JSON.parse(fs.readFileSync(archive, 'utf8')))) {
        const file = path.join(dir, relative);
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, Buffer.from(bytes, 'base64'));
      }
    }
  };
  const sandbox = vm.createContext({
    console, fs: platformFs, zlib, setTimeout,
    util: {
      TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
      TextDecoder: { create: () => {
        const decoder = new TextDecoder();
        return { decodeWithStream: (bytes, options) => decoder.decode(bytes, options) };
      } }
    },
    statfs: { getFreeSize: async () => 1024 ** 4 },
    fileUri: { getUriFromPath: file => `file://${file}` },
    AppStorage: { get: () => 'recentRead', setOrCreate() {} },
    AppDatabase: { getInstance: () => db },
    BookSourceGroupStore: { load: async () => {} },
    ReaderReplaceRuleStore: { load: async () => [], save: async () => {} },
    TtsSettingsStore: { load: async () => ({ customVoices: '' }), save: async () => {} },
    BookshelfStateStore: { normalizeSortMode: value => value, saveSortMode: async () => {} },
    LocalBookService: {
      TYPE_EPUB: 1,
      formatOf: book => book.getVariable('localFormat') || (book.type === 1 ? 'epub' : book.type === 4 ? 'pdf' : 'txt'),
      isLocalBook: book => book.bookUrl.startsWith('local://'),
      isPhysicalLocalBook: book => book.bookUrl.startsWith('local://'),
      ensureLocalParserCurrent: async () => {}
    },
    preferences: { getPreferences: async (context, name) => {
      const prefs = states.get(context.filesDir).prefs;
      if (!prefs.has(name)) prefs.set(name, {});
      return {
        getAll: async () => plain(prefs.get(name)),
        clear: async () => prefs.set(name, {}),
        put: async (key, value) => { prefs.get(name)[key] = value; },
        flush: async () => {}
      };
    } },
    BackupCrypto: {
      encryptFile: async (src, dest) => { fs.copyFileSync(src, dest); return { payloadFile: 'payload.bin' }; },
      parseMetadata: JSON.parse,
      decryptFile: async (src, dest) => fs.copyFileSync(src, dest)
    }
  });
  const statsEntry = readEtsModule('model/data/AppDatabase.ts').match(/export class ReadStatsEntry \{[\s\S]*?\n\}/)[0];
  vm.runInContext(compile(readEtsModule('model/data/Book.ts')) + '\n' + compile(statsEntry) + '\n' +
    compile(readEtsModule('core/stats/AndroidReadRecordImport.ts')) + '\n' +
    compile(readEtsModule('utils/AndroidBackupJsonReader.ts')) + '\n' +
    compile(readEtsModule('utils/ReaderFontHelper.ets')) + '\n' +
    compile(readEtsModule('utils/AppDataBackupService.ets')) +
    '\nglobalThis.api = { AppDataBackupService, AppDataBackupSelection, Book, ReaderFontHelper, AndroidReadRecordImport, AndroidBackupJsonReader };', sandbox);
  const { AppDataBackupService: service, AppDataBackupSelection: Selection, Book, ReaderFontHelper: fonts } = sandbox.api;
  const write = (context, relative, contents) => {
    const file = `${context.filesDir}/${relative}`;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, contents);
    return file;
  };
  const addBook = (url, name, file = '') => {
    const book = new Book();
    book.bookUrl = url;
    book.name = name;
    book.durChapterIndex = 3;
    book.durChapterPos = 120;
    book.putVariable('readStarted', 'true');
    if (file) { book.putVariable('localFilePath', file); book.putVariable('localFormat', 'txt'); }
    states.get(source.filesDir).books.set(url, book);
    return book;
  };
  const selection = (...keys) => Object.assign(new Selection(), {
    sources: false, bookshelf: false, progress: false, bookmarks: false, localBooks: false, settings: false,
    searchHistory: false
  }, Object.fromEntries(keys.map(key => [key, true])));
  return { service, Selection, source, target, fonts, write, addBook, selection, zlib, api: sandbox.api,
    from: states.get(source.filesDir), to: states.get(target.filesDir),
    failCopy: file => { failCopy = file; } };
}

test('full export/import preserves themes, OPDS, fonts, books and reports missing local files', async t => {
  const h = harness(t);
  const fontPath = h.write(h.source, 'reader_fonts/reader_font_1.ttf', 'font bytes');
  const family = h.fonts.stableFontFamily(fontPath);
  const library = JSON.stringify({ fonts: [{ familyName: family, filePath: fontPath, sourceName: '我的字体' }] });
  const profile = { fontMode: 'custom', fontFamily: family, fontFilePath: fontPath, customFontsRaw: library,
    bodyFontFamily: family, titleFontFamily: family, regexFontRulesRaw: JSON.stringify([{ fontFamily: family }]) };
  h.from.prefs.set('reader_settings', {
    readerFontMode: 'custom', readerFontFamily: family, readerFontFilePath: fontPath,
    readerFontSourceName: '我的字体', readerCustomFontsRaw: library,
    readerBodyFontFamily: family, readerTitleFontFamily: family,
    readerRegexFontRulesRaw: profile.regexFontRulesRaw, readerThemeProfileV1_custom_2: JSON.stringify(profile)
  });
  h.from.prefs.set('immersive_light_settings', { immersiveLightLevel: 'balanced' });
  h.from.prefs.set('custom_theme_schemes', { active_scheme_id: 'custom_2', active_scheme_revision: 4,
    schemes: JSON.stringify([{ id: 'custom_1', name: '白天' }, { id: 'custom_2', name: '夜间', revision: 4 }]) });
  h.from.prefs.set('opds_settings', { active_server_id: 'opds-1', servers_v1: JSON.stringify([
    { id: 'opds-1', name: '书库', baseUrl: 'https://books.example/opds/', authType: 'basic',
      username: 'reader', rememberPassword: false, password: 'do-not-export' }
  ]) });
  h.from.prefs.set('opds_secrets', { password: 'secret' });
  h.to.prefs.set('opds_secrets', { password: 'target-secret' });
  h.to.prefs.set('reader_settings', { readerFontMode: 'device', readerCustomFontsRaw: '' });
  h.from.sources = [{ bookSourceUrl: 'https://source.example', loginHeader: 'secret', loginInfo: 'secret' }];
  h.from.addedTimes.set('https://source.example', 1700000000000);
  h.from.groups = [{ groupId: 1, groupName: '收藏' }];
  h.addBook('https://books.example/1', '网络书');
  const localPath = h.write(h.source, 'local_books/1.txt', '本地书正文');
  h.addBook('local://1', '本地书', localPath);
  h.addBook('local://2', '缺失的书', `${h.source.filesDir}/local_books/missing.txt`);
  h.addBook('local://3', '没有路径的书');
  h.from.bookmarks = [{ bookUrl: 'local://1', content: '书签正文' }];
  h.from.keywords = [{ word: '测试', usage: 2 }];
  const selected = new h.Selection();
  selected.searchHistory = true;
  const backup = await h.service.createBackup(h.source, selected, 'password123');
  assert.equal(backup.manifest.localBooks.length, 1);
  assert.deepEqual(plain(backup.manifest.skippedLocalBooks), ['缺失的书', '没有路径的书']);
  assert.deepEqual(Object.keys(backup.manifest.localFiles), ['local://1']);
  assert.match(backup.summary(), /本地图书 1/);
  assert.match(backup.summary(), /网络书籍 1/);
  assert.equal(backup.manifest.preferenceStores.opds_secrets, undefined);
  assert.equal(backup.manifest.sources[0].loginHeader, '');
  const session = await h.service.prepareImport(h.target, backup.archivePath, 'password123');
  assert.equal(session.encrypted, true);
  const result = await h.service.importBackup(h.target, session, selected);
  assert.equal(result.localBooks, 1);
  assert.equal(h.to.addedTimes.get('https://source.example'), 1700000000000);
  assert.equal(result.books, 1);
  assert.equal(result.bookmarks, 1);
  assert.equal(result.progress, 2);
  assert.equal(result.settings, 14);
  assert.equal(h.to.prefs.get('immersive_light_settings').immersiveLightLevel, 'balanced');
  assert.equal(h.to.books.get('local://1').durChapterPos, 120);
  assert.equal(fs.readFileSync(`${h.target.filesDir}/local_books/1.txt`, 'utf8'), '本地书正文');
  assert.deepEqual(h.to.prefs.get('custom_theme_schemes'), h.from.prefs.get('custom_theme_schemes'));
  const opds = JSON.parse(h.to.prefs.get('opds_settings').servers_v1)[0];
  assert.equal(opds.baseUrl, 'https://books.example/opds/');
  assert.equal(opds.password, '');
  assert.equal(opds.rememberPassword, false);
  assert.equal(h.to.prefs.get('opds_secrets').password, 'target-secret');
  const restored = h.to.prefs.get('reader_settings');
  const newPath = `${h.target.filesDir}/reader_fonts/reader_font_1.ttf`;
  const newFamily = h.fonts.stableFontFamily(newPath);
  assert.notEqual(newFamily, family);
  assert.equal(restored.readerFontMode, 'custom');
  assert.equal(restored.readerFontFilePath, newPath);
  assert.equal(restored.readerFontFamily, newFamily);
  assert.equal(restored.readerTitleFontFamily, newFamily);
  assert.equal(restored.readerBodyFontFamily, newFamily);
  assert.equal(JSON.parse(restored.readerCustomFontsRaw).fonts[0].familyName, newFamily);
  const restoredProfile = JSON.parse(restored.readerThemeProfileV1_custom_2);
  assert.equal(restoredProfile.titleFontFamily, newFamily);
  assert.equal(JSON.parse(restoredProfile.regexFontRulesRaw)[0].fontFamily, newFamily);
  assert.equal(fs.readFileSync(newPath, 'utf8'), 'font bytes');
  await h.service.discardImport(session);
  await h.service.discardExport(backup.archivePath);
  assert.equal(fs.existsSync(backup.archivePath), false);
});

test('deselected settings are neither exported nor restored', async t => {
  const h = harness(t);
  h.from.prefs.set('custom_theme_schemes', { active_scheme_id: 'incoming' });
  h.to.prefs.set('custom_theme_schemes', { active_scheme_id: 'local' });
  const backup = await h.service.createBackup(h.source, h.selection('bookshelf'), '');
  assert.deepEqual(plain(backup.manifest.preferenceStores), {});
  const settingsBackup = await h.service.createBackup(h.source, h.selection('settings'), '');
  const session = await h.service.prepareImport(h.target, settingsBackup.archivePath);
  await h.service.importBackup(h.target, session, h.selection('bookshelf'));
  assert.equal(h.to.prefs.get('custom_theme_schemes').active_scheme_id, 'local');
});

for (const version of [1, 2]) {
  test(`legacy v${version} without new optional fields still imports, absent stores stay intact`, async t => {
    const h = harness(t);
    h.to.prefs.set('opds_settings', { active_server_id: 'local' });
    h.from.prefs.set('reader_settings', { readerFontMode: 'device' });
    const backup = await h.service.createBackup(h.source, h.selection('settings'), '');
    const manifest = plain(backup.manifest);
    manifest.version = version;
    delete manifest.skippedLocalBooks;
    delete manifest.preferenceStores.opds_settings;
    delete manifest.preferenceStores.custom_theme_schemes;
    manifest.preferenceStores.account_commerce_session = '{"token":"untrusted"}';
    const archive = JSON.parse(fs.readFileSync(backup.archivePath, 'utf8'));
    archive['manifest.json'] = Buffer.from(JSON.stringify(manifest)).toString('base64');
    fs.writeFileSync(backup.archivePath, JSON.stringify(archive));
    const session = await h.service.prepareImport(h.target, backup.archivePath);
    await h.service.importBackup(h.target, session, h.selection('settings'));
    assert.equal(h.to.prefs.get('reader_settings').readerFontMode, 'device');
    assert.equal(h.to.prefs.get('opds_settings').active_server_id, 'local');
    assert.equal(h.to.prefs.has('account_commerce_session'), false);
  });
}

test('local file copy errors fail export instead of reporting a complete backup', async t => {
  const h = harness(t);
  const file = h.write(h.source, 'local_books/1.txt', 'content');
  h.addBook('local://1', '读取失败的书', file);
  h.failCopy(file);
  await assert.rejects(h.service.createBackup(h.source, h.selection('localBooks'), ''), /simulated copy failure/);
});

test('legacy backups with missing local book payload report skipped imports', async t => {
  const h = harness(t);
  const file = h.write(h.source, 'local_books/1.txt', 'content');
  h.addBook('local://1', '缺失载荷', file);
  const backup = await h.service.createBackup(h.source, h.selection('localBooks'), '');
  const session = await h.service.prepareImport(h.target, backup.archivePath);
  fs.unlinkSync(`${session.rootPath}/local_books/0.txt`);
  const result = await h.service.importBackup(h.target, session, h.selection('localBooks'));
  assert.equal(result.localBooks, 0);
  assert.equal(result.skippedLocalBooks, 1);
  assert.match(result.summary(), /跳过本地书 1/);
});

test('font paths are rebased once even when the target root contains the original root', async t => {
  const h = harness(t, true);
  const file = h.write(h.source, 'reader_fonts/a.ttf', 'font bytes');
  h.from.prefs.set('reader_settings', {
    readerFontMode: 'custom', readerFontFamily: h.fonts.stableFontFamily(file), readerFontFilePath: file,
    readerCustomFontsRaw: JSON.stringify([{ filePath: file, familyName: h.fonts.stableFontFamily(file) }])
  });
  const backup = await h.service.createBackup(h.source, h.selection('settings'), '');
  const session = await h.service.prepareImport(h.target, backup.archivePath);
  await h.service.importBackup(h.target, session, h.selection('settings'));
  const restored = h.to.prefs.get('reader_settings');
  assert.equal(restored.readerFontFilePath, `${h.target.filesDir}/reader_fonts/a.ttf`);
  assert.equal(restored.readerFontFamily, h.fonts.stableFontFamily(restored.readerFontFilePath));
  assert.equal(JSON.parse(restored.readerCustomFontsRaw)[0].filePath, restored.readerFontFilePath);
});

function androidFixture(h, files) {
  const dir = path.join(h.source.tempDir, 'android-fixture');
  fs.mkdirSync(dir, { recursive: true });
  for (const [name, contents] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), JSON.stringify(contents));
  const archive = path.join(h.source.tempDir, 'android.zip');
  return h.zlib.compressFile(dir, archive).then(() => archive);
}
const androidName = { bookName: '测试小说', bookAuthor: '作者', deviceId: '' };
const androidDetail = { ...androidName, date: '2026-11-02', firstReadTime: 1793549788437,
  lastReadTime: 1793549838246, readTime: 49809, readWords: 3 };

test('Android daily/session/total records count once, retain the exported date and restore first-chapter read state', async t => {
  const h = harness(t);
  const archive = await androidFixture(h, {
    'bookshelf.json': [{ bookUrl: 'https://book/1', name: androidName.bookName, author: androidName.bookAuthor,
      origin: 'https://source', type: 8, durChapterIndex: 0, durChapterPos: 0, variable: 'null' }],
    'readRecordDetail.json': [androidDetail],
    'readRecordSession.json': [{ ...androidName, id: 1, startTime: androidDetail.firstReadTime, endTime: androidDetail.lastReadTime }],
    'readRecord.json': [{ ...androidName, readTime: 49809, lastRead: androidDetail.lastReadTime }]
  });
  const session = await h.service.prepareImport(h.target, archive, '');
  const selected = h.selection('bookshelf', 'progress');
  const result = await h.service.importBackup(h.target, session, selected);
  assert.equal(result.books, 1);
  assert.equal(result.readRecords, 1);
  assert.match(result.summary(), /阅读记录 1/);
  const [record] = h.to.readRecords.values();
  assert.equal(record.dayKey, '2026-11-02');
  assert.equal(record.durationMs, 49809);
  assert.equal(record.bookUrl, 'https://book/1');
  assert.equal(record.ownerId, '');
  assert.equal(h.to.books.get('https://book/1').getVariable('readStarted'), 'true');
  assert.equal(h.to.books.get('https://book/1').getVariable('lastReadTime'), String(androidDetail.lastReadTime));
  await h.service.importBackup(h.target, session, selected);
  assert.equal(h.to.readRecords.size, 1);
  assert.equal([...h.to.readRecords.values()].reduce((sum, r) => sum + r.durationMs, 0), 49809);
});

test('history-only backups work without adding shelf placeholders; deselecting progress leaves history untouched', async t => {
  const h = harness(t);
  const archive = await androidFixture(h, { 'readRecordDetail.json': [androidDetail] });
  const session = await h.service.prepareImport(h.target, archive, '');
  assert.equal(h.service.hasCategory(session.manifest, 'progress'), true);
  assert.equal(h.service.hasCategory(session.manifest, 'bookshelf'), false);
  await h.service.importBackup(h.target, session, h.selection('bookshelf'));
  assert.equal(h.to.readRecords.size, 0);
  await h.service.importBackup(h.target, session, h.selection('progress'));
  assert.equal(h.to.books.size, 0);
  assert.equal(h.to.readRecords.size, 1);
  assert.match([...h.to.readRecords.values()][0].bookUrl, /^android-history:/);
});

test('record fallback is per book/device, sessions split at midnight and malformed rows are rejected', t => {
  const h = harness(t);
  const importer = new h.api.AndroidReadRecordImport();
  const start = new Date(2026, 10, 1, 23, 59).getTime();
  const session = { ...androidName, deviceId: 'phone', startTime: start, endTime: start + 120000 };
  importer.addDetail({ ...androidDetail, date: '2026-02-30' });
  importer.addDetail({ ...androidDetail, readTime: 'Infinity' });
  importer.addSession(session);
  importer.addSession(session);
  importer.addTotal({ ...androidName, deviceId: 'phone', readTime: 120000, lastRead: start + 120000 });
  importer.addTotal({ ...androidName, deviceId: 'old', readTime: 20000, lastRead: start });
  const records = plain(importer.records());
  assert.equal(records.length, 3);
  assert.equal(records.reduce((sum, r) => sum + r.durationMs, 0), 140000);
  assert.deepEqual(records.filter(r => r.deviceId === 'android:phone').map(r => r.durationMs), [60000, 60000]);
  assert.equal(new Set(records.map(r => r.recordId)).size, 3);
});

test('Android conversion rejects unsafe numbers and non-object variable containers', t => {
  const h = harness(t);
  for (const variable of ['null', '[]', '42', '{bad', '{"readStarted":{"bad":1},"lastReadTime":123}']) {
    const book = h.service.convertAndroidBook({ bookUrl: 'https://book/1', variable,
      durChapterIndex: -3, durChapterPos: 'Infinity', totalChapterNum: '1e300' }, { legacyIds: [], localIds: new Map() });
    assert.equal(book.durChapterIndex, 0);
    assert.equal(book.durChapterPos, 0);
    assert.equal(book.totalChapterNum, 0);
    assert.equal(book.getVariable('readStarted'), '');
    assert.doesNotThrow(() => book.putVariable('next', 'yes'));
  }
  assert.equal(h.service.numberValue(undefined, 3), 3);
  assert.equal(h.service.numberValue('Infinity', 3), 3);
  assert.equal(h.service.numberValue('', 3), 3);
});

test('streaming reader handles every chunk boundary, escapes, primitive rows and malformed tails', t => {
  const h = harness(t);
  const value = [{ name: '中文😀"', nested: [1, { text: 'a,b]}\\' }] }, null, 1, { b: 2 }];
  const raw = JSON.stringify(value);
  for (let size = 1; size <= raw.length; size++) {
    const reader = new h.api.AndroidBackupJsonReader('fixture.json');
    const rows = [];
    for (let i = 0; i < raw.length; i += size) rows.push(...reader.append(raw.slice(i, i + size)));
    reader.finish();
    assert.deepEqual(plain(rows), [value[0], value[3]]);
  }
  for (const invalid of ['[{},]', '[{}', '[{}]x', '[{},{}] false', '[,{}]', '[{} {}]', 'null']) {
    const reader = new h.api.AndroidBackupJsonReader('invalid.json');
    assert.throws(() => { reader.append(invalid); reader.finish(); });
  }
  const objectReader = new h.api.AndroidBackupJsonReader('object.json');
  assert.deepEqual(plain(objectReader.append(' {"a":1} ')), [{ a: 1 }]);
  objectReader.finish();
  const deepReader = new h.api.AndroidBackupJsonReader('deep.json');
  assert.throws(() => deepReader.append('['.repeat(140)), /嵌套过深/);
});

test('Android text character positions restore through Harmony anchors; audio positions retain their own units', t => {
  const h = harness(t);
  const mapping = { legacyIds: [], localIds: new Map() };
  const text = h.service.convertAndroidBook({ type: 8, durChapterIndex: 3, durChapterPos: 1200 }, mapping);
  assert.equal(text.durChapterPos, 0);
  assert.equal(text.getVariable('readProgressCharOffsetV2'), '1200');
  assert.equal(text.getVariable('readProgressCharOffsetChapterV2'), '3');
  const audio = h.service.convertAndroidBook({ type: 32, durChapterIndex: 3, durChapterPos: 1200 }, mapping);
  assert.equal(audio.durChapterPos, 1200);
  assert.equal(audio.getVariable('readProgressCharOffsetV2'), '');
});

test('provided Android ZIP imports its actual books, sources and exactly 49809ms of reading time', {
  skip: !process.env.ANDROID_BACKUP_ZIP
}, async t => {
  const h = harness(t);
  // Read archive bytes as data only; scripts embedded in source rules are never evaluated.
  const archiveData = execFileSync('python', ['-c',
    'import zipfile,json,base64,sys; z=zipfile.ZipFile(sys.argv[1]); print(json.dumps({n:base64.b64encode(z.read(n)).decode() for n in z.namelist() if not n.endswith("/")}))',
    process.env.ANDROID_BACKUP_ZIP], { maxBuffer: 16 * 1024 * 1024 });
  const archive = path.join(h.source.tempDir, 'real-android.zip');
  fs.writeFileSync(archive, archiveData);
  const session = await h.service.prepareImport(h.target, archive, '');
  const selected = new h.Selection();
  const result = await h.service.importBackup(h.target, session, selected);
  assert.equal(result.books, 1);
  assert.equal(result.sources, 2);
  assert.equal(result.httpTts, 2);
  assert.equal(result.readRecords, 1);
  assert.equal(h.to.readRecords.size, 1);
  assert.equal([...h.to.readRecords.values()][0].durationMs, 49809);
  assert.equal([...h.to.readRecords.values()][0].dayKey, '2026-11-02');
  const [book] = h.to.books.values();
  assert.equal(book.durChapterIndex, 3);
  assert.equal(book.type, 8);
  assert.equal(book.getVariable('readStarted'), 'true');
  assert.equal([...h.to.readRecords.values()][0].bookUrl, book.bookUrl);
  if (process.env.ANDROID_BACKUP_NORMALIZED_OUT) {
    fs.writeFileSync(process.env.ANDROID_BACKUP_NORMALIZED_OUT,
      JSON.stringify({ books: [...h.to.books.values()], sources: h.to.sources }));
  }
  await h.service.importBackup(h.target, session, selected);
  assert.equal(h.to.readRecords.size, 1);
});
