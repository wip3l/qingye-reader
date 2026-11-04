// Execute production PDF raster/session logic with deterministic native boundaries.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createHash } from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compile = text => stripTypeScriptTypes(text.replace(/^import[\s\S]*?;\r?$/gm, '')
  .replace(/^export /gm, '').replace(/^@Concurrent\r?\n/gm, ''), { mode: 'strip' });
const models = compile(readEtsModule('core/book/pdf/PdfRasterModels.ts'));
const policy = vm.createContext({});
vm.runInContext(models + '\nglobalThis.policy = PdfRasterPolicy;', policy);

test('raster bounds, detailed scan bypass and physical neighbor boundaries', () => {
  const p = policy.policy;
  assert.equal(p.inputWidth(400, 600, 4000, 1000), 0);
  assert.equal(p.inputWidth(400, 600, 800, 1000), 800);
  for (const height of [1, 600, 40000]) {
    const width = p.inputWidth(400, height, 1800, 1000);
    assert.ok(width <= 1024 && width * Math.floor(width * height / 400) <= 1024 * 1024);
  }
  assert.equal(p.inputWidth(0, 600, 800, 1000), 0);
  assert.equal(p.inputWidth(400, NaN, 800, 1000), 0);
  assert.deepEqual([...p.candidates(0, 1)], [0]);
  assert.deepEqual([...p.candidates(999, 1000)], [999, 998]);
});

function harness(t, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pdf-sr-')).replaceAll('\\', '/');
  t.after(() => { assert.match(path.basename(root), /^pdf-sr-/); fs.rmSync(root, { recursive: true, force: true }); });
  const original = `${root}/original.pdf`; fs.writeFileSync(original, 'original PDF bytes');
  const pins = new Map(); const writes = []; let calls = 0; let renderCalls = 0;
  const sandbox = vm.createContext({ console,
    fs: { stat: async file => { const s = fs.statSync(file); return { size: s.size, mtime: s.mtimeMs }; },
      accessSync: fs.existsSync, mkdirSync: dir => fs.mkdirSync(dir, { recursive: true }) },
    digestHashHex: (_algorithm, text) => createHash('sha256').update(text).digest('hex'),
    ReaderCacheCoordinator: { retainFile: file => {
      pins.set(file, (pins.get(file) || 0) + 1); let released = false;
      return () => { if (released) return; released = true; const n = pins.get(file) - 1;
        if (n) pins.set(file, n); else pins.delete(file); };
    } },
    ReaderCacheBudget: { noteComicWrite: file => writes.push(file) },
    ReaderComicSuperResolution: { enhance: async (file, _width, active) => {
      calls++; if (options.enhance) return options.enhance(file, active);
      return options.failure ? '' : `file://${file}.enhanced.jpg`;
    } },
    PdfRasterTask: { render: async (_source, index, _width, output) => {
      renderCalls++; if (options.render) await options.render();
      if (options.renderFailure) throw new Error('native render failed');
      fs.writeFileSync(output, 'derived raster');
      return { pageIndex: index, eligible: !options.textPage, imagePath: output, pageWidth: 400, pageHeight: 600 };
    } }
  });
  vm.runInContext(models + '\n' + compile(readEtsModule('core/book/pdf/PdfSuperResolutionSession.ets')) +
    '\nglobalThis.Session = PdfSuperResolutionSession;', sandbox);
  return { root, pins, writes, session: new sandbox.Session(original, root),
    calls: () => calls, renders: () => renderCalls, unchanged: () => assert.equal(fs.readFileSync(original, 'utf8'), 'original PDF bytes') };
}

test('reuse, bounded retained pages, shared budget and original file preservation', async t => {
  const h = harness(t);
  const first = await h.session.prepare(0, 1000, () => true);
  assert.ok(first.enhancedUri); assert.equal(h.pins.size, 2);
  assert.equal(await h.session.prepare(0, 1000, () => true), first);
  assert.equal(h.calls(), 1); assert.equal(h.renders(), 1);
  await Promise.all([1, 2, 3, 4, 5].map(i => h.session.prepare(i, 1000, () => true)));
  assert.equal(h.pins.size, 6); assert.equal(h.session.get(0), undefined);
  assert.equal(h.writes.length, 6);
  h.session.retain([5]); assert.equal(h.pins.size, 2);
  h.session.dispose(); assert.equal(h.pins.size, 0); h.unchanged();
  assert.equal(await h.session.prepare(6, 1000, () => true), undefined);
});

for (const cause of ['navigation', 'dispose']) {
  test(`in-flight ${cause} cannot publish a stale enhanced page or leak cache pins`, async t => {
    let release; let started; const entered = new Promise(resolve => { started = resolve; });
    const h = harness(t, { enhance: async file => { started(); await new Promise(resolve => { release = resolve; }); return `file://${file}.enhanced.jpg`; } });
    let active = true;
    const task = h.session.prepare(0, 1000, () => active);
    await entered;
    if (cause === 'dispose') h.session.dispose(); else active = false;
    release(); assert.equal(await task, undefined);
    assert.equal(h.session.get(0), undefined); assert.equal(h.pins.size, 0); h.unchanged();
  });
}

test('text pages skip inference; failed enhancement keeps original and does not loop', async t => {
  const text = harness(t, { textPage: true });
  assert.equal((await text.session.prepare(0, 1000, () => true)).enhancedUri, '');
  assert.equal(text.calls(), 0); text.session.dispose();
  const failed = harness(t, { failure: true });
  assert.equal((await failed.session.prepare(0, 1000, () => true)).enhancedUri, '');
  await failed.session.prepare(0, 1000, () => true);
  assert.equal(failed.calls(), 1); failed.session.dispose(); assert.equal(failed.pins.size, 0);
});

test('native rendering errors release sources and allow later jobs to run', async t => {
  const h = harness(t, { renderFailure: true });
  await assert.rejects(h.session.prepare(0, 1000, () => true), /native render failed/);
  await assert.rejects(h.session.prepare(1, 1000, () => true), /native render failed/);
  assert.equal(h.pins.size, 0); assert.equal(h.calls(), 0);
});

test('AI indicator preference hides PDF processing and completion text while preserving original-page comparison', () => {
  const controls = readEtsModule('components/reader/PdfReaderControls.ets');
  const method = controls.match(/  private enhancementStatusLabel\(\): string \{[\s\S]*?\n  \}/);
  assert.ok(method);
  const label = vm.runInNewContext(compile(`({${method[0].replace('private ', '')}})`)).enhancementStatusLabel;
  const state = { readerAiProcessingIndicatorEnabled: true, enhancementStatus: '正在增强当前页…', showOriginal: false };
  assert.equal(label.call(state), '正在增强当前页…');
  state.readerAiProcessingIndicatorEnabled = false;
  assert.equal(label.call(state), '');
  state.showOriginal = true;
  assert.equal(label.call(state), '原页');
  state.showOriginal = false;
  for (const status of ['AI 超分', '增强未完成，显示原页', '增强图读取失败，显示原页']) {
    state.enhancementStatus = status;
    assert.equal(label.call(state), '');
    state.readerAiProcessingIndicatorEnabled = true;
    assert.equal(label.call(state), status);
    state.readerAiProcessingIndicatorEnabled = false;
  }
});

test('missing CropBox uses MediaBox; raster writes atomically, reuses cache and releases native resources', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pdf-sr-raster-'));
  t.after(() => { assert.match(path.basename(root), /^pdf-sr-raster-/); fs.rmSync(root, { recursive: true, force: true }); });
  let pageReleased = 0, docReleased = 0, decodedReleased = 0, renderedReleased = 0, packed = 0;
  const box = { left: 0, top: 600, right: 400, bottom: 0 };
  const sandbox = vm.createContext({ console,
    fs: { accessSync: fs.existsSync, statSync: fs.statSync, renameSync: fs.renameSync, unlinkSync: fs.unlinkSync,
      OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
      openSync: file => ({ fd: fs.openSync(file, 'w') }), writeSync: fs.writeSync, closeSync: file => fs.closeSync(file.fd) },
    taskpool: { execute: (fn, ...args) => fn(...args) },
    pdfService: { ParseResult: { PARSE_SUCCESS: 0 }, RotationAngle: { ANGLE_0: 0 },
      BoxType: { BOX_CROP: 1, BOX_MEDIA: 0 }, GraphicsObjectType: { OBJECT_IMAGE: 3 }, PdfMatrix: class {},
      PdfDocument: class {
        loadDocument() { return 0; } releaseDocument() { docReleased++; }
        getPage() { return { getWidth: () => 400, getHeight: () => 600, getRotation: () => 0,
          getTextContent: () => '', getBox: type => type === 1 ? { left: 0, top: 0, right: 0, bottom: 0 } : box,
          getGraphicsObjects: () => [{ type: 3, width: 400, height: 600,
            pixelMap: { getImageInfo: async () => ({ size: { width: 800, height: 1200 } }), release: async () => { decodedReleased++; } } }],
          getAreaPixelMap: (matrix, width, height) => {
            assert.equal(width, 800); assert.equal(height, 1200);
            assert.equal(matrix.width, width); assert.equal(matrix.height, height);
            return { release: async () => { renderedReleased++; } };
          }, release() { pageReleased++; } }; }
      } },
    image: { createImagePacker: () => ({
      packToData: async () => { packed++; return Buffer.from('JPEG bytes'); }, release: async () => {} }) }
  });
  vm.runInContext(models + '\n' + compile(readEtsModule('core/concurrency/PdfRasterTask.ets')) +
    '\nglobalThis.raster = PdfRasterTask;', sandbox);
  const output = path.join(root, 'page.jpg');
  const first = await sandbox.raster.render('fixture.pdf', 0, 1000, output);
  assert.equal(first.eligible, true); assert.equal(first.rectTop, 600);
  assert.equal(fs.existsSync(output), true); assert.equal(fs.existsSync(output + '.part'), false);
  await sandbox.raster.render('fixture.pdf', 0, 1000, output);
  assert.equal(packed, 1); assert.equal(renderedReleased, 1);
  assert.equal(decodedReleased, 2); assert.equal(pageReleased, 2); assert.equal(docReleased, 2);
  await assert.rejects(sandbox.raster.render('fixture.pdf', 0, 1000, output, () => false), /已取消/);
  await sandbox.raster.render('fixture.pdf', 0, 1000, output);
  assert.equal(packed, 1); assert.equal(docReleased, 3);
});
