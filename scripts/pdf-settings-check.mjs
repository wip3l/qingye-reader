import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compile = text => stripTypeScriptTypes(text.replace(/^import[\s\S]*?;\r?$/gm, '').replace(/^export /gm, ''), { mode: 'strip' });
const modelCode = compile(readEtsModule('core/book/pdf/ReaderPdfSettings.ts'));
const model = vm.createContext({});
vm.runInContext(modelCode + '\nglobalThis.Model = ReaderPdfSettings;', model);
const Model = model.Model;

test('PDF defaults are safe, typed and round-trip without enabling AI from malformed values', () => {
  for (const raw of ['', 'invalid', 'null', '[]', '"text"', '{"continuous":"false","superResolution":"true"}']) {
    const settings = Model.parse(raw);
    assert.equal(settings.continuous, true); assert.equal(settings.superResolution, false);
  }
  const settings = new Model(); settings.fitPage = true; settings.doublePage = true;
  const restored = Model.parse(settings.toJson());
  assert.equal(restored.fitPage, true); assert.equal(restored.doublePage, true);
  const copied = restored.copy(); copied.fitPage = false; assert.equal(restored.fitPage, true);
});

test('per-book overrides win individually; reading a book does not freeze global defaults', () => {
  const defaults = new Model(); defaults.continuous = false; defaults.superResolution = true;
  const book = defaults.withOverrides({ pdfSuperResolution: '0', pdfContinuous: '1', pdfDoublePage: 'invalid' });
  assert.equal(book.continuous, true); assert.equal(book.superResolution, false);
  assert.deepEqual(Object.keys(book.bookVariables([])), []);
  const saved = book.bookVariables([Model.CONTINUOUS]);
  assert.deepEqual(Object.keys(saved), ['pdfContinuous']);
  defaults.fitPage = true;
  const reopened = defaults.withOverrides(saved);
  assert.equal(reopened.continuous, true); assert.equal(reopened.fitPage, true); assert.equal(reopened.superResolution, true);
});

function storeHarness() {
  const values = new Map([['readerComicSettings', 'comic settings sentinel']]);
  const writes = []; let rejectFlush = false;
  const sandbox = vm.createContext({ console,
    preferences: { getPreferences: async (_context, name) => {
      assert.equal(name, 'reader_settings');
      return { get: async (key, fallback) => values.get(key) ?? fallback,
        put: async (key, raw) => { writes.push(JSON.parse(raw)); values.set(key, raw); },
        flush: async () => { if (rejectFlush) { rejectFlush = false; throw new Error('flush failed'); } } };
    } }
  });
  vm.runInContext(modelCode + '\n' + compile(readEtsModule('core/book/pdf/ReaderPdfSettingsStore.ets')) +
    '\nglobalThis.api = { Model: ReaderPdfSettings, Store: ReaderPdfSettingsStore };', sandbox);
  return { ...sandbox.api, values, writes, rejectNextFlush: () => { rejectFlush = true; } };
}

test('rapid saves persist immutable snapshots in order, and loading waits for the latest save', async () => {
  const h = storeHarness(); const settings = new h.Model(); settings.continuous = false;
  const first = h.Store.save({}, settings);
  settings.fitPage = true;
  const second = h.Store.save({}, settings);
  const loaded = await h.Store.load({}); await Promise.all([first, second]);
  assert.equal(h.writes[0].fitPage, false); assert.equal(h.writes[1].fitPage, true);
  assert.equal(loaded.continuous, false); assert.equal(loaded.fitPage, true);
  assert.equal(h.values.get('readerComicSettings'), 'comic settings sentinel');
});

test('preference restore is visible without stale cache; a failed save cannot block later saves', async () => {
  const h = storeHarness(); const settings = new h.Model();
  h.rejectNextFlush(); await assert.rejects(h.Store.save({}, settings), /flush failed/);
  settings.doublePage = true; await h.Store.save({}, settings);
  assert.equal((await h.Store.load({})).doublePage, true);
  h.values.set('readerPdfSettings', '{"fitPage":true,"continuous":false}');
  const restored = await h.Store.load({});
  assert.equal(restored.fitPage, true); assert.equal(restored.continuous, false); assert.equal(restored.doublePage, false);
});

test('production progress saves keep defaults inherited and preserve unrelated per-book preferences', async () => {
  const page = readEtsModule('pages/PdfReadBook.ets');
  const start = page.indexOf('  private saveProgress(): Promise<void> {');
  const method = page.slice(start, page.indexOf('\n  }', start) + 4);
  const variables = new Map([['pdfFitPage', '1'], ['unrelated', 'keep']]);
  let writes = 0;
  const sandbox = vm.createContext({ console, clearTimeout,
    ReaderProgressCheckpoint: { canWrite: () => true }, PdfPagePosition: { title: index => `page ${index + 1}` },
    AppStorage: { setOrCreate() {} },
    appDb: { getBook: async () => ({ durChapterTime: 0, hasStartedReading: () => true,
      putVariable: (key, value) => variables.set(key, value), variable: '{}' }),
      updateBookReadingProgress: async () => { writes++; } }
  });
  vm.runInContext(modelCode + '\n' + compile(`class PdfProgressProbe { ${method} }\nglobalThis.Probe = PdfProgressProbe;`), sandbox);
  const reader = new sandbox.Probe();
  Object.assign(reader, { saveTimer: -1, ready: true, book: {}, owner: 'probe', pageIndex: 1,
    continuous: true, doublePage: false, fitPage: true, superResolution: true,
    customizedPreferences: new Set(), bookUrl: 'local://pdf', saveTask: Promise.resolve() });
  await reader.saveProgress();
  assert.equal(variables.has('pdfContinuous'), false); assert.equal(variables.has('pdfSuperResolution'), false);
  reader.customizedPreferences.add('pdfContinuous'); reader.continuous = false;
  await reader.saveProgress();
  assert.equal(variables.get('pdfContinuous'), '0'); assert.equal(variables.get('pdfFitPage'), '1');
  assert.equal(variables.get('unrelated'), 'keep'); assert.equal(writes, 2);
});
