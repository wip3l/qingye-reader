import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/pages/ReadBook.ets', import.meta.url), 'utf8');
const requestSource = fs.readFileSync(new URL('../entry/src/main/ets/core/reader/ReaderContinuousLayoutRequest.ets', import.meta.url), 'utf8');
function method(name) {
  const start = source.search(new RegExp(`^  (?:async )?${name}\\(`, 'm'));
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const timers = new Map(); let timerId = 0, nativeCalls = 0, paused = false, rejectNext = false;
const held = [];
const reportedErrors = [];
const sandbox = vm.createContext({ console: { ...console, error: (...args) => reportedErrors.push(args) }, px2vp: n => n / 2,
  setTimeout: fn => { timers.set(++timerId, fn); return timerId; }, clearTimeout: id => timers.delete(id),
  ReaderTitleStyleCodec: { decode: () => ({}) },
  ReaderV2DocumentParser: { parse: chunk => ({ chunk }) },
  ReaderV2Paginator: { layoutContinuousAsync: (document, snapshot, valid) => {
    // The fourth parameter is the validity callback in the production signature.
    throw new Error('Unexpected call signature');
  } },
});
sandbox.ReaderV2Paginator.layoutContinuousAsync = (document, snapshot, styles, valid) => {
  nativeCalls++;
  const result = { identity: `${document.identity}:${snapshot.identity}`, contentBottomPx: 400, fragments: [] };
  if (rejectNext) { rejectNext = false; return Promise.reject(new Error('native layout failed')); }
  if (paused) return new Promise(resolve => held.push(() => resolve(valid() ? result : null)));
  return Promise.resolve(result);
};
const names = ['readerContinuousV2Request', 'readerContinuousV2State', 'readerContinuousV2Layout',
  'queueReaderContinuousLayout', 'scheduleReaderContinuousLayout', 'runReaderContinuousLayout',
  'pruneReaderContinuousLayouts', 'warmReaderContinuousLayouts', 'cancelReaderContinuousLayouts'];
vm.runInContext(stripTypeScriptTypes(requestSource.replace(/^import .*;\r?\n/gm, '')
  .replace(/^@Observed\r?\n/gm, '').replace(/^export /gm, '') +
  `\nclass Reader { ${names.map(method).join('\n')} }; globalThis.Reader = Reader;`), sandbox);
const snapshot = { identity: 'font-20' };
function fixture() {
  const reader = new sandbox.Reader();
  Object.assign(reader, { pageViewWidth: 600, currentChapterIndex: 0, currentPageIndex: 0,
    readerV2SurfaceGeneration: 0, readerContinuousLayoutGeneration: 0, readerParagraphSpacing: 10, readerTitleStyleRaw: '',
    readerContinuousLastListStart: 0, readerContinuousLastListEnd: 0,
    readerContinuousLayoutSerial: 0, readerContinuousLayoutActiveSerial: -1, readerContinuousLayoutTimer: -1,
    readerContinuousLayoutRequests: new Map(), readerContinuousLayoutQueue: [],
    readerContinuousV2Layouts: new Map(), readerContinuousV2Documents: new Map(),
    readerContinuousV2Sources: new Map(), readerContinuousV2Controllers: new Map(), readerPageVisible: true,
    sourceText: 'chapter', usesReaderContinuousV2: () => true,
    readerContinuousChapterOf: n => n < 0 ? 0 : n, readerContinuousV2ChunkText: (_index, text) => text,
    readerContinuousV2ChunkStart: index => index * 1800, readerContinuousSourceOf() { return this.sourceText; },
    readerContinuousEndsOf: () => new Array(100), hashText: s => s, readerPaginationSourceHash: s => s,
    buildReaderV2Snapshot: () => snapshot, readerV2HeadingHints: () => [], getChapterTitle: () => '',
    buildReaderV2RegexStyles: () => [], toMeasureNonNegativePx: n => n * 2,
    readerComicPageDataSource: { itemAt: n => n === 0 ?
      { chapterIndex: 0, pageIndex: 0, text: 'first', isPage: () => true } : null },
    isReaderImageOnlyPage: () => false,
  });
  return reader;
}
async function tick() {
  const jobs = [...timers.values()]; timers.clear();
  for (const fn of jobs) fn();
  for (let i = 0; i < 8; i++) await Promise.resolve();
}
async function settle() {
  for (let i = 0; i < 8; i++) await Promise.resolve();
  for (let i = 0; timers.size && i < 100; i++) await tick();
  assert.equal(timers.size, 0);
}

const reader = fixture();
assert.equal(reader.readerContinuousV2Layout(0, 'first'), null);
assert.equal(nativeCalls, 0, 'cache-only lookups never shape native text');
const state = reader.readerContinuousV2State(0, 'first');
assert.equal(reader.readerContinuousV2State(0, 'first'), state);
assert.equal(timers.size, 1); assert.equal(nativeCalls, 0, 'List builder only schedules work');
await settle();
assert.equal(nativeCalls, 1); assert.equal(state.ready, true); assert.equal(state.heightVp, 210);
assert(reader.readerContinuousV2Layout(0, 'first'));
reader.readerContinuousV2State(0, 'first'); await settle(); assert.equal(nativeCalls, 1);

paused = true;
const staleState = reader.readerContinuousV2State(1, 'second'); await tick();
assert.equal(staleState.ready, false);
reader.cancelReaderContinuousLayouts(false); reader.readerPageVisible = false;
held.shift()(); await settle(); assert.equal(staleState.ready, false, 'hide rejects a late native result');
reader.readerPageVisible = true;
reader.readerContinuousV2State(1, 'second'); await tick();
held.shift()(); await settle(); assert.equal(staleState.ready, true, 'a retained pending host resumes on foreground');

const beforeFontChange = reader.readerContinuousV2State(2, 'third'); await tick();
reader.cancelReaderContinuousLayouts(true); reader.readerV2SurfaceGeneration++;
const afterFontChange = reader.readerContinuousV2State(2, 'third'); await tick();
held.shift()(); await settle();
assert.equal(beforeFontChange.ready, false); assert.equal(afterFontChange.ready, false);
assert.equal(reader.readerContinuousLayoutActiveSerial, reader.readerContinuousLayoutSerial,
  'an older finally must not release the replacement owner');
held.shift()(); await settle(); assert.equal(afterFontChange.ready, true);
paused = false;

rejectNext = true;
const broken = reader.readerContinuousV2State(3, 'broken'); await settle();
assert.equal(broken.failed, true); assert.equal(reader.readerContinuousLayoutActiveSerial, -1);
assert.equal(reportedErrors.length, 1, 'the rejected native job is reported once');
const recovered = reader.readerContinuousV2State(4, 'healthy'); await settle(); assert.equal(recovered.ready, true);

for (let index = 5; index < 55; index++) { reader.readerContinuousV2State(index, `chunk-${index}`); await settle(); }
assert(reader.readerContinuousLayoutRequests.size <= 24, 'native and lightweight caches remain bounded');
assert(reader.readerContinuousV2Layouts.size <= 24);
assert(reader.readerContinuousV2Documents.size <= 24);
const old = reader.readerContinuousV2State(0, 'same'); await settle();
reader.sourceText = 'replacement chapter';
const fresh = reader.readerContinuousV2State(0, 'same');
assert.notEqual(old, fresh, 'source changes invalidate same-looking chunks and source-offset mappings');
await settle();
assert.equal(fresh.ready, true);
reader.readerContinuousV2State(1, 'same'); await settle();
const repeatedFirst = reader.readerContinuousV2Layout(0, 'same');
const repeatedSecond = reader.readerContinuousV2Layout(1, 'same');
assert.notEqual(repeatedFirst.identity, repeatedSecond.identity, 'identical chunks retain distinct source-offset maps');
assert.equal(reader.readerContinuousV2Sources.get(repeatedFirst.identity), 0);
assert.equal(reader.readerContinuousV2Sources.get(repeatedSecond.identity), 1800);
assert(!method('readerContinuousV2Layout').includes('layoutContinuous('));
console.log('PASS: cache-only builders, async native layout, deduplication, bounded retention, lifecycle/source/typography cancellation and failure recovery');
