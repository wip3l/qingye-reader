import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const enhanceJobs = [], translateJobs = [];
const context = vm.createContext({ console, getContext: () => ({}), vp2px: x => x,
  ReaderComicSuperResolution: { enhance: () => { const job = deferred(); enhanceJobs.push(job); return job.promise; } },
  ComicChineseConverter: { layer: () => { const job = deferred(); translateJobs.push(job); return job.promise; } }
});
vm.runInContext(stripTypeScriptTypes(readEtsModule('core/reader/ReaderComicProcessing.ts').replace(/^export /gm, '')), context);
// Keep production lifecycle/business methods; omit only ArkUI's declarative build methods.
let item = readEtsModule('components/reader/ReaderComicView.ets').split('export struct ReaderComicImageItem {')[1].split('\n  build() {')[0];
item = item.replace(/@(Prop|State|Watch)(\([^)]*\))?\s*/g, '');
vm.runInContext(stripTypeScriptTypes(`class ComicItem {${item}\n}`), context);
const { Registry, Item } = vm.runInContext('({Registry: ReaderComicProcessing, Item: ComicItem})', context);
const registry = new Registry();
let updates = 0;
const unsubscribe = registry.subscribe(() => updates++);
const fresh = () => {
  const item = new Item();
  Object.assign(item, { processing: registry, mounted: true, visible: true, loaded: true, source: 'page.jpg', ratio: 2, viewWidth: 300,
    superResolution: true, textConvert: true });
  return item;
};
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
const itemA = fresh(), itemB = fresh();
itemA.maybeEnhance(); itemA.maybeConvertText(); itemB.maybeEnhance();
assert.equal(registry.message(true), 'AI 超分 / AI 着色 / AI 翻译处理中…');
enhanceJobs[0].resolve('file://a.jpg'); await flush();
assert.match(registry.message(false), /超分/, 'another visible page keeps the shared indicator');
itemB.visible = false; itemB.syncProcessing();
assert.equal(registry.message(false), 'AI 翻译处理中…', 'offscreen work does not leave progress');
translateJobs[0].reject(new Error('OCR unavailable')); await flush();
assert.equal(registry.message(false), '', 'failure clears progress');
// A late result from an old request must not clear a replacement request.
itemA.resetEnhancement(); itemA.maybeEnhance();
itemA.resetEnhancement(); itemA.maybeEnhance();
enhanceJobs[2].resolve('file://stale.jpg'); await flush();
assert.equal(itemA.enhancedUri, '');
assert.equal(registry.message(false), 'AI 超分处理中…');
enhanceJobs[3].resolve('file://fresh.jpg'); await flush();
assert.equal(registry.message(false), '');
itemA.resetTextLayer(); itemA.maybeConvertText();
itemA.textConvert = false; itemA.onTextConvertChanged();
assert.equal(registry.message(false), '', 'turning translation off clears immediately');
itemB.visible = true; itemB.syncProcessing();
itemB.aboutToDisappear();
assert.equal(registry.message(false), '', 'unmount clears owned tasks');
// Mounted neighbours outside the viewport are enhanced ahead of time without showing progress.
const ahead = fresh(); ahead.visible = false;
const jobsBefore = enhanceJobs.length;
ahead.maybeEnhance();
assert.equal(enhanceJobs.length, jobsBefore + 1, 'offscreen mounted pages are prefetched');
assert.equal(registry.message(false), '', 'prefetch does not show the badge');
ahead.visible = true; ahead.syncProcessing();
assert.equal(registry.message(false), 'AI 超分处理中…', 'scrolling onto a page still being enhanced shows progress');
ahead.aboutToDisappear();
const other = new Registry();
other.update(Registry.owner(), true, false);
assert.equal(registry.message(false), '', 'readers do not share progress state');
const before = updates; unsubscribe(); registry.update(Registry.owner(), true, false);
assert.equal(updates, before, 'unmounted badges no longer receive notifications');
console.log('Comic progress: concurrent pages/features, failures, visibility, stale results, toggles and unmount passed.');
