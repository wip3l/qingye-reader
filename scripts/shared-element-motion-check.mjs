import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const read = path => fs.readFileSync(new URL(path, root), 'utf8');
const context = vm.createContext({});
vm.runInContext(stripTypeScriptTypes(
  read('utils/SharedElementBounds.ts').replace('export class', 'class') +
  read('utils/SharedElementMotion.ts').replace('export class', 'class') +
  '\nglobalThis.api = { SharedElementBounds, SharedElementMotion };'), context);
const { SharedElementBounds: Bounds, SharedElementMotion: Motion } = context.api;
assert.notEqual(Motion.coverId('search', 'a', 'same'), Motion.coverId('explore', 'a', 'same'));
assert.notEqual(Motion.coverId('search', 'a:b', 'c'), Motion.coverId('search', 'a', 'b:c'));
assert.equal(Motion.coverId('search', 'a', ''), '');
const original = new Bounds(20, 90, 100, 140);
const saved = Bounds.resolve(original, 50, 100, 400, 800);
assert.notEqual(saved, original, 'transition keeps a stable snapshot while the shelf relayouts');
original.x = 200;
assert.equal(saved.x, 20);
for (const input of [undefined, new Bounds(-200, 1, 100, 140), new Bounds(10, 900, 100, 140), new Bounds(0, 0, 0, 0)]) {
  const fallback = Bounds.resolve(input, 399, 799, 400, 800);
  assert.ok(fallback.x >= 0 && fallback.x + fallback.width <= 400);
  assert.ok(fallback.y >= 0 && fallback.y + fallback.height <= 800);
}

const source = read('components/home/BookshelfPage.ets');
const name = 'captureSharedElementBounds';
const start = source.indexOf(`  ${name}(`);
const method = source.slice(start, source.indexOf('\n  }', start) + 4);
const host = vm.runInContext(stripTypeScriptTypes(`({ ${method} })`), context);
Object.assign(host, {
  contextViewportWidth: 400, contextViewportHeight: 800,
  getUIContext: () => ({
    px2vp: x => x / 2,
    getComponentUtils: () => ({ getRectangleById: id => id === 'bookshelf_motion_root' ? ({ windowOffset: { x: 20, y: 40 }, size: { width: 800, height: 1600 } }) : ({
      windowOffset: { x: 140, y: 200 }, size: { width: 180, height: 240 }
    }) })
  })
});
const live = host.captureSharedElementBounds('cover', saved, 120, 190);
assert.equal(live.x, 60, 'live window coordinates override stale pre-scroll bounds');
assert.equal(live.y, 80, 'window decoration and root offset are subtracted');
assert.equal(live.width, 90, 'physical pixels convert to vp');
host.getUIContext = () => { throw new Error('source recycled'); };
assert.equal(host.captureSharedElementBounds('cover', saved, 120, 190).x, 20);
console.log('PASS shared elements: route identity isolation, stable bounds, recycled sources and live scroll coordinates');
