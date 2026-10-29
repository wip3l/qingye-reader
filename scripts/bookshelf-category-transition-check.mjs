import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const source = readEtsModule('components/home/BookshelfPage.ets');
const methods = ['toggleShelfCategory', 'stopShelfCategoryAnimation', 'bookshelfTopOverlayHeight'].map(name => {
  const start = source.indexOf(`  ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}).join('\n');
let nextTimer = 0;
const timers = new Map();
const context = vm.createContext({
  AppSpacing: { XL: 24, MD: 12 }, Curve: { Friction: 'friction' },
  setTimeout: finish => { timers.set(++nextTimer, finish); return nextTimer; },
  clearTimeout: id => timers.delete(id)
});
vm.runInContext(stripTypeScriptTypes(`class Shelf {
  static SCOPE_TABS_HEIGHT = 44;
  static SEARCH_BAR_HEIGHT = 40;
  ${methods.replaceAll('BookshelfPage.', 'Shelf.')}
}
globalThis.Shelf = Shelf;`), context);

const completions = [];
const shelf = new context.Shelf();
Object.assign(shelf, {
  shelfCategoryExpanded: false, shelfCategoryAnimating: false,
  shelfCategoryAnimationSerial: 0, shelfCategoryAnimationWatchdog: -1,
  shelfScopeTabsWidth: 0, contextViewportWidth: 360,
  statusBarHeight: 24, shelfSearchActive: false, isBookMultiSelect: false,
  shelfTypeTab: 'audio', showsShelfScopeTabs: () => true,
  getUIContext: () => ({ animateTo: (options, update) => { update(); completions.push(options.onFinish); } })
});
assert.equal(shelf.bookshelfTopOverlayHeight(), 80, 'cold start collapsed reserves no category space');
shelf.toggleShelfCategory();
assert.equal(shelf.shelfScopeTabsWidth, 312, 'first expansion has material width before layout');
assert.equal(shelf.bookshelfTopOverlayHeight(), 136);
const firstFinish = completions.at(-1);
shelf.toggleShelfCategory();
firstFinish();
assert.equal(shelf.shelfCategoryAnimating, true, 'old native completion cannot finish a reversed transition');
assert.equal(shelf.shelfCategoryExpanded, false);
completions.at(-1)();
assert.equal(shelf.shelfCategoryAnimating, false);
assert.equal(timers.size, 0);
assert.equal(shelf.shelfTypeTab, 'audio');
shelf.toggleShelfCategory();
const leavingFinish = completions.at(-1);
shelf.stopShelfCategoryAnimation();
leavingFinish();
assert.equal(timers.size, 0, 'disposal releases fallback timer');
assert.equal(shelf.shelfCategoryExpanded, true, 'disposal preserves the requested end state');
shelf.toggleShelfCategory();
[...timers.values()][0]();
assert.equal(shelf.shelfCategoryAnimating, false, 'fallback releases scroll guard');
shelf.getUIContext = () => { throw new Error('UI unavailable'); };
shelf.toggleShelfCategory();
assert.equal(shelf.shelfCategoryExpanded, true);
assert.equal(timers.size, 0);
assert.equal(shelf.shelfCategoryAnimating, false);
console.log('PASS native category transition: cold start, rapid reversal, stale completion, disposal and fallback');
