// Run after assembleHap: exercise the compiler's retained @Builder closures,
// which a state-machine-only test cannot cover.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compiledPath = process.argv[2] || new URL('../entry/build/default/cache/default/' +
  'default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/reader/ReaderComicPagedView.ts', import.meta.url);
const strip = source => stripTypeScriptTypes(source.replace(/^import [^;]*;\r?\n/gm, '').replace(/^export /gm, ''));
class Property {
  constructor(value) { this.value = value; }
  get() { return this.value; }
  set(value) { this.value = value; }
  reset(value) { this.value = value; }
}
class ViewPU {
  declareWatch() {}
  finalizeConstruction() {}
}
let drawing;
const Stack = { create() {}, pop() {}, width() {}, height() {}, scale() {}, translate() {},
  position(value) { drawing.x = value.x; }, opacity(value) { drawing.opacity = value; },
  zIndex(value) { drawing.zIndex = value; } };
const ForEach = { create() {}, pop() {} };
const noopComponent = { pop() {} };
const scope = vm.createContext({ console, setTimeout, clearTimeout, ViewPU, Stack, ForEach,
  Row: noopComponent, Canvas: noopComponent, If: noopComponent, __Common__: noopComponent,
  ObservedPropertySimplePU: Property, SynchedPropertySimpleOneWayPU: Property,
  SynchedPropertyObjectOneWayPU: Property,
  CanvasRenderingContext2D: class {}, RenderingContextSettings: class {},
  ReaderPageCurlPainter: class {}, ReaderEmulationFlipPainter: class { clearCorner() {} },
  ReaderEmulationFlipRegion: { BOTTOM: 2 }, ReaderComicRetryRegistry: class {},
});
vm.runInContext(strip(readEtsModule('core/reader/ReaderPageTurnAnimation.ts')), scope);
vm.runInContext(strip(readEtsModule('core/reader/ReaderComicProcessing.ts')), scope);
vm.runInContext(strip(fs.readFileSync(compiledPath, 'utf8')) + '\nglobalThis.View = ReaderComicPagedView;', scope);
const A = vm.runInContext('ReaderPageTurnAnimation', scope);
const markerPages = (chapter, count) => Array.from({ length: count }, (_, i) => `${chapter}:${i}`);

for (const type of A.types()) for (const rtl of [false, true]) for (const dual of [false, true]) {
  for (const direction of [-1, 1]) {
    const oldPages = markerPages('current', 15);
    const targetPages = markerPages('target', 11);
    const view = new scope.View(undefined, {
      pages: oldPages, chapterIndex: 3, pageIndex: direction < 0 ? 0 : 14,
      viewWidth: 400, viewHeight: 800, dualPage: dual, rightToLeft: rtl, animationType: type,
      prevChapterTitle: 'prev', nextChapterTitle: 'next',
      prevChapterPages: direction < 0 ? targetPages : markerPages('prev', 7),
      nextChapterPages: direction > 0 ? targetPages : markerPages('next', 9),
    });
    view.onLayoutChanged();
    const retained = new Map();
    let buildingKey;
    // Keep the actual call arguments emitted by initialRender. ForEach does not
    // rerun itemGenerator for an existing key after the parent changes chapters.
    const compiledSlot = view.slot;
    const stopAfterRoot = {};
    view.slot = (...args) => {
      const observe = view.observeComponentCreation2;
      view.observeComponentCreation2 = callback => {
        const root = {};
        const update = () => { drawing = root; callback(0, false); };
        retained.set(buildingKey, { root, update });
        update();
        throw stopAfterRoot;
      };
      try { compiledSlot.apply(view, args); }
      catch (error) { if (error !== stopAfterRoot) throw error; }
      finally { view.observeComponentCreation2 = observe; }
    };
    let visitedSpreads;
    view.observeComponentCreation2 = (callback, component) => {
      if (component === ForEach && !visitedSpreads) {
        visitedSpreads = true;
        callback(0, false);
      }
    };
    view.forEachUpdateFunction = (_id, values, generate, keyOf) => {
      for (const value of values) {
        buildingKey = keyOf(value);
        if (!retained.has(buildingKey)) generate(value);
      }
    };
    const render = () => { visitedSpreads = false; view.initialRender(); };
    render();
    const targetSpread = view.spreadIndex + direction;
    const targetKey = view.slotKey(targetSpread);
    const target = retained.get(targetKey);
    assert.ok(target, 'the adjacent chapter is mounted before handoff');
    view.dragOffset = view.turnOffset(direction);
    target.update();
    assert.equal(target.root.x, 0, 'target reaches the viewport before handoff');
    assert.equal(target.root.opacity, 1);

    view.chapterIndex += direction;
    view.pages = targetPages;
    view.pageIndex = direction > 0 ? 0 : targetPages.length - 1;
    view.prevChapterPages = direction > 0 ? oldPages : markerPages('earlier', 5);
    view.nextChapterPages = direction < 0 ? oldPages : markerPages('later', 13);
    view.onLayoutChanged();
    render();
    assert.equal(retained.get(view.slotKey(view.spreadIndex)), target,
      'handoff keeps the same mounted target instead of reloading its image');
    target.update();
    const label = `type=${type}, rtl=${rtl}, dual=${dual}, direction=${direction}`;
    assert.equal(target.root.x, 0, `retained page must stay onscreen after handoff (${label})`);
    assert.equal(target.root.opacity, 1, `retained page must stay visible after handoff (${label})`);
    const centerKey = view.slotKey(view.spreadIndex);
    for (const [key, slot] of retained) {
      if (key === centerKey) continue;
      slot.update();
      assert.ok(slot.root.opacity === 0 || Math.abs(slot.root.x) >= view.viewWidth,
        `an old slot must not cover the current page (${label})`);
    }
  }
}
console.log('Comic compiled handoff: retained builders, both chapter directions, six animations, LTR/RTL and single/dual passed.');
