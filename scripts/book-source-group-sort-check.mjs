// Run production persistence, picker ordering and drag handlers without a device.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const read = path => fs.readFileSync(new URL(`../entry/src/main/ets/${path}`, import.meta.url), 'utf8');
const compile = code => stripTypeScriptTypes(code, { mode: 'strip' });
const plain = array => Array.from(array);
const stored = new Map();
const appValues = new Map();
let failFlush = false;
const context = vm.createContext({
  AppStorage: {
    get: key => appValues.get(key),
    setOrCreate: (key, value) => appValues.set(key, value)
  },
  preferences: { getPreferences: async () => ({
    get: async (key, fallback) => stored.get(key) ?? fallback,
    put: async (key, value) => stored.set(key, value),
    flush: async () => { if (failFlush) throw new Error('disk failure'); }
  }) }
});
const storeCode = read('utils/BookSourceGroupStore.ets').replace(/^import .*;\r?\n/gm, '').replace('export class', 'class');
vm.runInContext(compile(`${storeCode}\nglobalThis.BookSourceGroupStore = BookSourceGroupStore;`), context);
const store = context.BookSourceGroupStore;
stored.set('groups', JSON.stringify(['漫画', '有声书', '网文', '旧空分组']));
stored.set('user_groups', JSON.stringify(['手动空分组']));
stored.set('user_groups_ready', true);
assert.deepEqual(plain(await store.load({}, ['网文', '漫画', '有声书', '新书源分组'])),
  ['漫画', '有声书', '网文', '手动空分组', '新书源分组']);
let groups = await store.reorder({}, ['网文', '有声书', '漫画', '手动空分组', '新书源分组']);
// Simulate restart: no in-memory order, and sources arrive in a different order.
appValues.clear();
assert.deepEqual(plain(await store.loadOrder({})), plain(groups));
assert.deepEqual(plain(await store.load({}, ['漫画', '新书源分组', '网文', '有声书'])), plain(groups));
groups = await store.rename({}, '有声书', '听书', groups);
assert.deepEqual(plain(groups), ['网文', '听书', '漫画', '手动空分组', '新书源分组']);
groups = await store.add({}, '末尾新增', groups);
assert.equal(groups.at(-1), '末尾新增');
groups = await store.remove({}, '漫画', groups);
assert.deepEqual(plain(groups), ['网文', '听书', '手动空分组', '新书源分组', '末尾新增']);
const beforeRead = JSON.stringify([...stored]);
await store.loadOrder({});
assert.equal(JSON.stringify([...stored]), beforeRead, 'reading a source subset must not clean global groups');
const published = appValues.get('bookSourceGroupOrder');
failFlush = true;
await assert.rejects(store.reorder({}, groups.slice().reverse()), /disk failure/);
assert.equal(appValues.get('bookSourceGroupOrder'), published, 'failed saves must not publish order');
failFlush = false;

const pickerCode = read('components/home/SourcePickerKit.ets');
const pickerClass = pickerCode.slice(pickerCode.indexOf('export class SourcePickerKit'), pickerCode.indexOf('\n/** 书源选择里的搜索框'));
const picker = vm.runInContext(compile(`${pickerClass.replace('export class', 'class')}\nSourcePickerKit;`), context);
assert.deepEqual(plain(picker.sortGroups(['未分组', '听书', '网文'])), ['网文', '听书', '未分组']);
assert.deepEqual(plain(picker.sortGroups(['未知B', '末尾新增', '未知A', '网文'])), ['网文', '末尾新增', '未知A', '未知B']);

function method(code, name) {
  const match = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(code);
  assert(match, name);
  return code.slice(match.index, code.indexOf('\n  }', match.index) + 4);
}
const dragCode = read('components/book/SourceGroupSortList.ets');
const timers = new Map();
let timerId = 0;
const dragContext = vm.createContext({
  AppSpacing: { SM: 8 },
  setInterval: callback => { timers.set(++timerId, callback); return timerId; },
  clearInterval: id => timers.delete(id)
});
const drag = vm.runInContext(compile(`new (class {
  ${['syncGroups', 'beginDrag', 'updateDrag', 'moveDraggedGroup', 'autoScroll', 'stopAutoScroll',
    'cancelDrag', 'finishDrag', 'aboutToDisappear'].map(name => method(dragCode, name)).join('\n')}
})()`), dragContext);
let scrollY = 0;
let saves = 0;
const event = (offsetY, globalY = 100) => ({ offsetY, fingerList: [{ globalY }] });
function resetDrag() {
  scrollY = 0;
  Object.assign(drag, {
    groups: ['A', 'B', 'C', 'D'], orderedGroups: ['A', 'B', 'C', 'D'],
    draggingGroup: '', savingOrder: false, dragTranslation: 0,
    viewportTop: 0, viewportHeight: 192, scrollTimer: -1,
    scroller: {
      currentOffset: () => ({ yOffset: scrollY }),
      scrollBy: (_x, y) => { scrollY = Math.max(0, Math.min(64, scrollY + y)); }
    },
    onReorder: async next => { saves++; drag.groups = plain(next); return true; }
  });
}
resetDrag();
drag.beginDrag('B', event(0));
drag.updateDrag(event(128));
assert.deepEqual(plain(drag.orderedGroups), ['A', 'C', 'D', 'B']);
assert.equal(drag.dragTranslation, 0);
drag.updateDrag(event(-128));
assert.deepEqual(plain(drag.orderedGroups), ['B', 'A', 'C', 'D']);
await drag.finishDrag();
assert.deepEqual(plain(drag.groups), ['B', 'A', 'C', 'D']);
assert.equal(timers.size, 0);
resetDrag();
drag.beginDrag('A', event(0));
drag.updateDrag(event(10000));
assert.deepEqual(plain(drag.orderedGroups), ['B', 'C', 'D', 'A']);
drag.cancelDrag();
assert.deepEqual(plain(drag.orderedGroups), ['A', 'B', 'C', 'D']);
resetDrag();
drag.beginDrag('C', event(0));
drag.updateDrag(event(0, 190));
for (let i = 0; i < 8; i++) drag.autoScroll();
assert.equal(scrollY, 64);
assert.deepEqual(plain(drag.orderedGroups), ['A', 'B', 'D', 'C']);
await drag.finishDrag();
resetDrag();
drag.onReorder = async () => false; // Parent reports a save failure and keeps its original groups.
drag.beginDrag('A', event(0));
drag.updateDrag(event(64));
await drag.finishDrag();
assert.deepEqual(plain(drag.orderedGroups), ['A', 'B', 'C', 'D']);
assert.equal(drag.savingOrder, false);
resetDrag();
drag.beginDrag('A', event(0));
drag.aboutToDisappear();
assert.equal(timers.size, 0, 'closing the dialog must stop auto scroll');
assert.equal(saves, 2);

// Run the page update hooks so existing search/explore instances adopt the new order.
for (const [path, hooks, initial, resultKey] of [
  ['components/home/SearchPage.ets', ['onSourceGroupOrderChanged', 'rebuildSearchSourceIndex'],
    { searchSourceList: [{ bookSourceUrl: 'a', bookSourceGroup: '听书' },
      { bookSourceUrl: 'b', bookSourceGroup: '网文' }], normalizeSourceGroup: source => source.bookSourceGroup }, 'sourceGroups'],
  ['components/home/ExplorePage.ets', ['onSourceGroupOrderChanged', 'buildExploreSourceGroups'],
    { sourceOptions: [{ sourceGroup: '听书' }, { sourceGroup: '网文' }], exploreSourceGroupLabel: group => group }, 'exploreSourceGroups']
]) {
  context.SourcePickerKit = picker;
  const page = vm.runInContext(compile(`new (class { ${hooks.map(name => method(read(path), name)).join('\n')} })()`), context);
  Object.assign(page, initial);
  page.onSourceGroupOrderChanged();
  assert.deepEqual(plain(page[resultKey]), ['网文', '听书']);
}
console.log('Book source group sorting passed: persistence/restart, rename/add/remove, subset readers, picker order, live page refresh, bidirectional drag, boundaries, auto scroll, cancellation and save rollback.');
