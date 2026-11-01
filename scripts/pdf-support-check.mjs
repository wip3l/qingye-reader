// Production PDF navigation/import logic against real temporary files. Native parsing is tested by PdfSupportTestRunner.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';
import { createHash } from 'node:crypto';
import { readEtsModule, projectRoot } from './lib/ets-module-staging.mjs';

const compile = source => stripTypeScriptTypes(source.replace(/^import[\s\S]*?;\r?$/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
const context = vm.createContext({ console });
vm.runInContext(compile(readEtsModule('core/book/pdf/PdfModels.ts')) + '\nglobalThis.api = { PdfPagePosition };', context);
const { PdfPagePosition: position } = context.api;

test('physical-page boundaries, percentages and unread state', () => {
  assert.equal(position.clamp(-4, 100), 0);
  assert.equal(position.clamp(100, 100), 99);
  assert.equal(position.clamp(NaN, 100), 0);
  assert.equal(position.clamp(3, 0), 0);
  assert.equal(position.percent(0, 100, false), 0);
  assert.equal(position.percent(0, 100), 1);
  assert.equal(position.percent(99, 100), 100);
  assert.equal(position.fromPercent(0, 100), 0);
  assert.equal(position.fromPercent(100, 100), 99);
  assert.equal(position.fromPercent(50, 100), 49);
  assert.equal(position.title(0), '第 1 页');
  for (const count of [1, 3, 100, 1000]) {
    for (let index = 0; index < count; index++) {
      assert.equal(position.clamp(index, count), index);
      assert.equal(position.fromPercent(position.percent(index, count), count), index);
    }
  }
});

function importHarness(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pdf-support-')).replaceAll('\\', '/');
  t.after(() => { assert.match(path.basename(root), /^pdf-support-/); fs.rmSync(root, { recursive: true, force: true }); });
  const filesDir = `${root}/files`; fs.mkdirSync(filesDir);
  let saved = null, chapters = [], failParsing = false, failCommit = false;
  const handles = new Map();
  const platformFs = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    mkdirSync: file => fs.mkdirSync(file, { recursive: true }),
    copy: async (from, to) => fs.copyFileSync(from.replace(/^file:\/\//, ''), to.replace(/^file:\/\//, '')),
    openSync: file => { const fd = fs.openSync(file, 'w'); handles.set(fd, file); return { fd }; },
    writeSync: (fd, content) => fs.writeSync(fd, content), closeSync: file => fs.closeSync(file.fd),
    accessSync: fs.existsSync, statSync: fs.statSync,
    rmdirSync: file => { assert.ok(file.startsWith(`${filesDir}/local_books/`)); fs.rmSync(file, { recursive: true }); },
    unlinkSync: fs.unlinkSync, readText: async file => fs.readFileSync(file, 'utf8')
  };
  const sandbox = vm.createContext({ console, fs: platformFs, setTimeout,
    fileUri: { getUriFromPath: file => `file://${file}` },
    appDb: { commitBookSourceSwitch: async (_url, book, index, upsert) => {
      assert.equal(upsert, true);
      if (failCommit) throw new Error('injected transaction failure');
      saved = JSON.parse(JSON.stringify(book)); chapters = JSON.parse(JSON.stringify(index));
    } },
    PdfImportTask: { extract: async (_file, assets) => {
      if (failParsing) throw new Error('PDF 损坏或格式不受支持');
      fs.writeFileSync(`${assets}/cover.jpg`, 'cover');
      return { pageCount: 3, title: 'Embedded title', author: 'Embedded author', coverPath: `${assets}/cover.jpg`,
        outline: [{ id: '0', title: 'Opening', pageIndex: 0, depth: 0 }] };
    } }
  });
  vm.runInContext(compile(readEtsModule('model/data/Book.ts')) + '\n' +
    compile(readEtsModule('core/book/pdf/PdfModels.ts')) + '\n' + compile(readEtsModule('core/book/pdf/PdfBookService.ets')) +
    '\nglobalThis.api = { Book, PdfBookService };', sandbox);
  const book = new sandbox.api.Book();
  book.bookUrl = 'local://pdf-probe'; book.type = 4; book.group = 7; book.durChapterIndex = 2;
  book.putVariable('localFormat', 'pdf');
  const source = `${root}/source.pdf`; fs.writeFileSync(source, '%PDF-fixture');
  return { root, book, source, service: sandbox.api.PdfBookService,
    import: candidate => sandbox.api.PdfBookService.import({ filesDir }, candidate || book, source, 'probe', 'Fallback', '',
      async file => createHash('sha256').update(fs.readFileSync(file)).digest('hex')),
    state: () => ({ saved, chapters }), failParsing: () => { failParsing = true; }, failCommit: () => { failCommit = true; } };
}

test('PDF import keeps the original, indexes physical pages without body caches, and preserves custom state', async t => {
  const h = importHarness(t);
  const result = await h.import();
  assert.equal(result.name, 'Embedded title');
  assert.equal(result.author, 'Embedded author');
  assert.equal(result.group, 7); assert.equal(result.durChapterIndex, 2); assert.equal(result.durChapterPos, 0);
  assert.equal(fs.readFileSync(result.getVariable('localFilePath'), 'utf8'), '%PDF-fixture');
  assert.equal(h.state().chapters.length, 3);
  assert.equal(h.state().chapters[2].url, 'local://pdf-probe#page=2');
  assert.equal(h.state().chapters[2].title, '第 3 页');
  assert.equal(result.getVariable('readerComicMode'), '0');
  assert.equal((await h.service.outline(result)).length, 1);
  const oldRoot = result.getVariable('localExtractRoot');
  result.putVariable('localMetadataCustomized', '1'); result.putVariable('localCustomName', 'My title');
  result.putVariable('localCustomAuthor', 'My author');
  const replacement = await h.import(result);
  assert.equal(replacement.name, 'My title'); assert.equal(replacement.author, 'My author');
  assert.equal(fs.existsSync(oldRoot), false);
  assert.equal(fs.existsSync(replacement.getVariable('localFilePath')), true);
});

for (const failure of ['parser', 'transaction']) {
  test(`failed ${failure} leaves the committed file and book intact`, async t => {
    const h = importHarness(t);
    const previous = await h.import();
    const oldFile = previous.getVariable('localFilePath');
    const snapshot = JSON.stringify(h.state().saved);
    const oldRoot = previous.getVariable('localExtractRoot');
    failure === 'parser' ? h.failParsing() : h.failCommit();
    await assert.rejects(() => h.import(previous));
    assert.equal(fs.existsSync(oldFile), true);
    assert.equal(JSON.stringify(h.state().saved), snapshot);
    assert.equal(fs.readdirSync(path.dirname(oldRoot)).length, 1, 'uncommitted revision was cleaned');
  });
}

test('system association, route and remote PDF format support are registered', () => {
  const manifest = fs.readFileSync(path.join(projectRoot, 'entry/src/main/module.json5'), 'utf8');
  assert.match(manifest, /"type": "application\/pdf"/);
  assert.match(manifest, /"type": "com\.adobe\.pdf"/);
  const routes = JSON.parse(fs.readFileSync(path.join(projectRoot, 'entry/src/main/resources/base/profile/main_pages.json'), 'utf8'));
  assert.ok(routes.src.includes('pages/PdfReadBook'));
  const read = readEtsModule('pages/ReadBook.ets');
  assert.ok(read.indexOf("url: 'pages/PdfReadBook'") < read.indexOf('ReaderProgressCheckpoint.attach('));
  const model = vm.createContext({ console });
  vm.runInContext(compile(readEtsModule('webdav/WebDavModels.ets')) + '\nglobalThis.WebDavEntry = WebDavEntry;', model);
  const entry = new model.WebDavEntry(); entry.name = 'document.PDF'; entry.relativePath = 'document.PDF';
  assert.equal(entry.readableBook(), true); assert.equal(entry.format(), 'pdf');
});

test('API 20 search joins text objects, keeps character boxes, and skips scanned pages', async () => {
  let released = 0;
  const textObject = text => ({ type: 1, charUnicodes: [...text].map(c => c.codePointAt(0)),
    charRects: [...text].map((_, i) => ({ left: i, right: i + 1, top: 10, bottom: 0 })) });
  const pages = [[textObject('Hello '), textObject('World HELLO')], [{ type: 3 }]];
  const sandbox = vm.createContext({ console, deviceInfo: { sdkApiVersion: 20 },
    taskpool: { execute: (fn, ...args) => fn(...args) },
    pdfService: { ParseResult: { PARSE_SUCCESS: 0 }, GraphicsObjectType: { OBJECT_TEXT: 1 },
      PdfDocument: class {
        loadDocument() { return 0; }
        getPageCount() { return pages.length; }
        getPage(index) { return { getGraphicsObjects: () => pages[index], release() {} }; }
        releaseDocument() { released++; }
      } }
  });
  vm.runInContext(compile(readEtsModule('core/book/pdf/PdfModels.ts')) + '\n' +
    compile(readEtsModule('core/concurrency/PdfSearchTask.ets').replace(/^@Concurrent\r?\n/gm, '')) +
    '\nglobalThis.api = PdfSearchTask;', sandbox);
  const result = await sandbox.api.search('fixture.pdf', 'hello');
  assert.equal(result.hits.length, 2);
  assert.equal(result.hits[0].pageIndex, 0);
  assert.equal(result.hits[0].rects.length, 5);
  assert.equal((await sandbox.api.search('fixture.pdf', 'o World')).hits.length, 1);
  assert.equal((await sandbox.api.search('fixture.pdf', 'absent')).hits.length, 0);
  assert.equal(released, 3);
});

test('leaving the text entry while PDF lookup is pending cannot redirect a different page', async () => {
  const source = readEtsModule('pages/ReadBook.ets');
  const start = source.indexOf('  async aboutToAppear() {');
  const method = source.slice(start, source.indexOf('\n  }', start) + 4);
  let resolveBook, queries = 0, redirects = 0;
  const lookup = new Promise(resolve => { resolveBook = resolve; });
  const sandbox = vm.createContext({ console, getContext: () => ({}),
    router: { getParams: () => ({ bookUrl: 'local://pdf' }), replaceUrl: async () => { redirects++; } },
    AppDatabase: { getInstance: () => ({ initWithContext: async () => {}, getBook: () => { queries++; return lookup; } }) },
    LocalBookService: { isPdfBook: () => true },
    ReaderProgressCheckpoint: { attach() { throw new Error('Disposed entry acquired progress ownership'); } }
  });
  vm.runInContext(compile(`class EntryProbe { ${method} }\nglobalThis.EntryProbe = EntryProbe;`), sandbox);
  const entry = new sandbox.EntryProbe();
  const opening = entry.aboutToAppear();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(queries, 1);
  entry.readerEntryAlive = false;
  resolveBook({ bookUrl: 'local://pdf' });
  await opening;
  assert.equal(redirects, 0);
});
