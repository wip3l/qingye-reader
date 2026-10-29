// Execute the folder lifecycle, including dismissal races and scoped book data.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/components/home/BookshelfPage.ets', import.meta.url), 'utf8');
const methods = ['openTileFolder', 'presentTileFolder', 'animateTileFolderOpen', 'closeTileFolder', 'resetTileFolder',
  'captureSharedElementBounds', 'alignTileFolderOrigin', 'tileFolderWidth', 'tileFolderHeight', 'tileFolderColumns', 'tileFolderDataSource', 'getTileGroupBooks'];
const timers = new Map(), finishes = [];
let timerId = 0;
const context = vm.createContext({
  Scroller: class {}, Curve: { Friction: 'friction', EaseInOut: 'ease', EaseOut: 'out' },
  DialogAlignment: { Center: 'center' }, Color: { Transparent: 'transparent' },
  BlurStyle: { NONE: 'none' }, TransitionEffect: { IDENTITY: 'identity' },
  setTimeout(fn) { timers.set(++timerId, fn); return timerId; },
  clearTimeout(id) { timers.delete(id); },
  animateTo(options, update) { update(); if (options.onFinish) finishes.push(options.onFinish); }
});
vm.runInContext(stripTypeScriptTypes(fs.readFileSync(new URL('../entry/src/main/ets/utils/SharedElementBounds.ts', import.meta.url), 'utf8').replace('export class', 'class')), context);
const host = vm.runInContext(stripTypeScriptTypes(`({${methods.map(name => {
  const start = source.indexOf(`  ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}).join(',')}})`), context);
const presentTileFolder = host.presentTileFolder;
const visible = [{ bookUrl: 'visible-audio', group: 7 }, { bookUrl: 'other-group', group: 8 }];
Object.assign(host, {
  contextViewportOriginX: 0, contextViewportOriginY: 0,
  folderBounds: new Map(), showTileFolder: false, activeShelfGroupId: 0, contextViewportWidth: 400, contextViewportHeight: 800,
  statusBarHeight: 24, navBarHeight: 24, tileFolderAnimationGeneration: 0, tileFolderOpenTimer: -1,
  tileFolderDialogId: -1, tileFolderDialogRequest: 0, presentTileFolder() {},
  consumeShelfSwipeClick: () => false,
  allBooks: [...visible, { bookUrl: 'hidden-private', group: 7 }],
  shelfBooksForPage(key) { assert.equal(key, 'audio'); return visible; },
  tileFolderBooksSource: { books: [], replace(books) { this.books = books; } }
});
const tap = [80, 180];
host.openTileFolder(7, 'audio', ...tap);
assert.equal(host.showTileFolder, true);
assert.equal(host.activeShelfGroupId, 0, 'opening a folder must not navigate or persist a group selection');
assert.equal(host.tileFolderBounds.x, 48);
const sourceY = host.tileFolderBounds.y;
host.alignTileFolderOrigin({ globalPosition: { x: 0, y: 36 } });
assert.equal(host.tileFolderBounds.y, sourceY - 36, 'dialog decoration offset must not move the source down');
host.alignTileFolderOrigin({ globalPosition: { x: 0, y: 36 } });
assert.equal(host.tileFolderBounds.y, sourceY - 36, 'repeat layout does not accumulate coordinate offsets');
assert.equal(host.tileFolderExpanded, false);
assert.deepEqual(Array.from(host.tileFolderDataSource().books, b => b.bookUrl), ['visible-audio'],
  'folder contents must use the filtered category, excluding unrelated and private books');
host.openTileFolder(8, 'audio', ...tap);
assert.equal(host.tileFolderGroupId, 7, 'repeated taps cannot replace an open folder');

host.animateTileFolderOpen();
let actions = 0;
host.closeTileFolder(() => actions++);
host.closeTileFolder(() => actions++);
assert.equal(timers.size, 0, 'closing before the first frame cancels the entrance');
assert.equal(actions, 0, 'book navigation waits for dismissal');
assert.equal(finishes.length, 1, 'dismissal is single-flight');
finishes.shift()();
assert.equal(host.showTileFolder, false);
assert.equal(actions, 1);
host.resetTileFolder();
assert.equal(host.tileFolderBooksSource.books.length, 0);

host.openTileFolder(7, 'audio', ...tap);
host.animateTileFolderOpen();
for (const [id, callback] of timers) { timers.delete(id); callback(); }
assert.equal(host.tileFolderExpanded, true);
assert.equal(host.tileFolderContentVisible, false, 'covers stay absent while the native surface is expanding');
finishes.shift()();
assert.equal(host.tileFolderContentVisible, true, 'native completion starts the content reveal');
host.closeTileFolder(() => actions++);
host.resetTileFolder();
finishes.shift()();
assert.equal(actions, 1, 'leaving the shelf cancels pending book navigation');
// A stale opening callback cannot reveal covers after the folder has begun closing.
host.openTileFolder(7, 'audio', ...tap);
host.animateTileFolderOpen();
for (const [id, callback] of timers) { timers.delete(id); callback(); }
const openingFinish = finishes.shift();
host.closeTileFolder();
openingFinish();
assert.equal(host.tileFolderContentVisible, false);
finishes.shift()();
host.resetTileFolder();
host.consumeShelfSwipeClick = () => true;
host.openTileFolder(7, 'audio', ...tap);
assert.equal(host.showTileFolder, false, 'a category swipe must not open the folder under the finger');

for (const [width, height] of [[320, 640], [720, 360], [1200, 900]]) {
  host.tileFolderViewportWidth = width;
  host.tileFolderViewportHeight = height;
  assert.ok(host.tileFolderWidth() < width && host.tileFolderWidth() <= 560);
  assert.ok(host.tileFolderHeight() < height && host.tileFolderHeight() <= 660);
}

// Dialog creation can complete after disposal or after another folder is opened.
// A stale result must close only its own dialog, never the new one.
const pending = [], closed = [];
const prompt = {
  openCustomDialog(options) { return new Promise(resolve => pending.push({ options, resolve })); },
  closeCustomDialog(id) { closed.push(id); }
};
Object.assign(host, { presentTileFolder, getUIContext: () => ({ getPromptAction: () => prompt }),
  consumeShelfSwipeClick: () => false });
host.openTileFolder(7, 'audio', ...tap);
const stale = pending.shift();
host.resetTileFolder();
host.openTileFolder(8, 'audio', ...tap);
const current = pending.shift();
stale.resolve(41);
await Promise.resolve();
assert.deepEqual(closed, [41]);
stale.options.onDidDisappear();
assert.equal(host.showTileFolder, true);
assert.equal(host.tileFolderGroupId, 8);
current.resolve(42);
await Promise.resolve();
assert.equal(host.tileFolderDialogId, 42);
current.options.onWillDismiss();
assert.equal(host.showTileFolder, true, 'system Back waits for the closing animation');
finishes.shift()();
assert.equal(host.showTileFolder, false);
assert.deepEqual(closed, [41, 42]);
current.options.onDidDisappear();
assert.equal(host.tileFolderGroupId, 0);
assert.deepEqual(closed, [41, 42], 'dialog cleanup must not close an already closed handle');
console.log('Bookshelf folder checks passed: scoped books, no navigation, dialog races, system Back and responsive bounds.');
