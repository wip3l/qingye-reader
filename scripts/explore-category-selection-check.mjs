// node scripts/explore-category-selection-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/components/home/${file}.ets`, 'utf8');
const source = read('ExplorePage');
const history = new Map();
const toasts = [];
const context = vm.createContext({
  console, getContext: () => ({}),
  AppDatabase: { getInstance: () => ({ async initWithContext() {} }) },
  AppStorage: { setOrCreate() {} },
  HdsFeedback: { showToast: text => toasts.push(text) },
  ExploreCategoryHistoryStore: {
    async load() {}, last: source => history.get(source) || '',
    entryKey: (title, url) => `${title}\n${url}`,
    record: (_context, source, key) => history.set(source, key)
  },
  ExplorePage: { ENTRY_GROUP_PREFIX: /ENTRY_GROUP_PREFIX: string = '([^']+)'/.exec(source)[1] }
});
function methods(code, names) {
  const bodies = names.map(name => {
    const start = new RegExp(`^  (?:async )?${name}\\(`, 'm').exec(code)?.index;
    assert.notEqual(start, undefined, name);
    return code.slice(start, code.indexOf('\n  }', start) + 4);
  });
  return vm.runInContext(stripTypeScriptTypes(`({${bodies.join(',')}})`), context);
}
const names = ['loadEntries', 'getActiveEntries', 'exploreCategoryEntries', 'getEntryGroupNames',
  'entryGroupKey', 'explorePlatformLabel', 'normalizeSelectedPlatform', 'restoreExploreCategory',
  'selectExploreCategory', 'getSelectedSourcePlatforms', 'getSelectedSourceUrl', 'getSelectedSourceOption',
  'currentExploreEntryKey', 'switchExplorePlatform'];
const entry = (title, groupTitle = '') => ({ title, groupTitle, url: `/${title}`, sourceUrl: 'lrts' });
const entries = [entry('热播周榜'), entry('新书热播'), entry('历史幻想', '男频'),
  entry('古代言情', '女频'), entry('现代言情', '女频')];
const key = item => `${item.title}\n${item.url}`;
function makePage({ menu = entries, platforms = [], selected = '女频', filters = [] } = {}) {
  const page = methods(source, names);
  Object.assign(page, {
    entries: [], sourceOptions: [], platformNames: [], selectedSourceUrl: 'lrts',
    selectedSourceName: 'LRTS', selectedPlatform: selected, selectedIndex: 0,
    entryGroupMode: false, hasRestoredExploreSelection: true,
    activeExploreSourceGroup: '__all__', exploreSwipePreviews: new Map(),
    loads: [], requests: [], saves: [],
    beginExploreLoad() { return 1; }, isCurrentExploreLoad: () => true, finishExploreLoad() {},
    rebuildExploreSourceDisplayNames() {}, buildExploreSourceGroups: () => [], refreshExploreSourceDataSource() {},
    scrollExploreChannelToSelected() {},
    saveExploreSelection() { this.saves.push(this.selectedPlatform); },
    async loadBooks() { this.loads.push(this.getActiveEntries()[this.selectedIndex]?.title); },
    selectExploreEntry(index) {
      this.selectedIndex = index;
      history.set(this.selectedSourceUrl, this.currentExploreEntryKey());
      this.loadBooks();
    },
    coordinator: {
      async getExploreSources() {
        return [{ sourceUrl: 'lrts', sourceName: 'LRTS', platforms: [...platforms] }];
      },
      async getEntries(platform) { page.requests.push(platform); return menu; },
      getDiscoveredPlatforms: () => [], getDiscoveredFilters: () => filters
    }
  });
  return page;
}

const page = makePage();
await page.loadEntries();
assert.equal(page.loads.at(-1), '古代言情', 'legacy female group selection survives migration');
assert.equal(page.explorePlatformLabel(page.selectedPlatform), '女频');
assert.deepEqual(Array.from(page.platformNames, name => page.explorePlatformLabel(name)), ['其他', '男频', '女频']);

for (const [item, expectedGroup] of [[entries[0], '其他'], [entries[2], '男频'], [entries[4], '女频']]) {
  page.showExploreCategorySheet = true;
  page.selectExploreCategory(key(item));
  assert.equal(page.loads.at(-1), item.title, 'category click loads the chosen category across groups');
  assert.equal(page.showExploreCategorySheet, false);
  assert.equal(page.explorePlatformLabel(page.selectedPlatform), expectedGroup);
  assert.equal(page.currentExploreEntryKey(), key(item));
}

page.selectExploreCategory(key(entries[1]));
await page.loadEntries('', true);
assert.equal(page.loads.at(-1), '新书热播', 'refresh preserves the exact ungrouped category');
assert.deepEqual(page.requests, ['', ''], 'local group keys never become source script platform parameters');

const reopened = makePage({ selected: '男频' });
await reopened.loadEntries();
assert.equal(reopened.loads.at(-1), '新书热播', 'per-source history restores a category outside the saved group');
assert.equal(reopened.explorePlatformLabel(reopened.selectedPlatform), '其他');
const femaleGroup = reopened.entryGroupKey('女频');
const loadEntries = reopened.loadEntries.bind(reopened);
reopened.loadEntries = (...args) => (reopened.pendingLoad = loadEntries(...args));
reopened.switchExplorePlatform(femaleGroup);
await reopened.pendingLoad;
assert.equal(reopened.loads.at(-1), '古代言情', 'explicit group switch overrides old category history');
assert.equal(reopened.requests.at(-1), '');

const previousLoads = reopened.loads.length;
const previousSelection = reopened.currentExploreEntryKey();
reopened.showExploreCategorySheet = true;
reopened.selectExploreCategory('removed\n/missing');
assert.equal(reopened.loads.length, previousLoads);
assert.equal(reopened.currentExploreEntryKey(), previousSelection);
assert.equal(reopened.showExploreCategorySheet, true, 'invalid selection leaves the picker open');
assert.equal(toasts.at(-1), '分类已更新，请刷新后重试');

history.clear();
const remote = makePage({ menu: [entry('平台榜单')], platforms: ['平台甲', '平台乙'], selected: '平台乙' });
await remote.loadEntries();
assert.equal(remote.entryGroupMode, false);
assert.equal(remote.explorePlatformLabel(remote.selectedPlatform), '平台乙');
assert.deepEqual(remote.requests, ['平台乙'], 'real source selector still receives its original parameter');
const flat = makePage({ menu: [entry('榜单一'), entry('榜单二')] });
await flat.loadEntries();
assert.equal(flat.entryGroupMode, false);
assert.equal(flat.getActiveEntries().length, 2, 'flat menus need no artificial group selector');
const mixed = makePage({ menu: [entry('榜单'), entry('分类', '女频')] });
await mixed.loadEntries();
assert.equal(mixed.platformNames.length, 2, 'one named group plus ungrouped entries is still a grouped menu');

const collision = makePage({ menu: [entry('无分组榜'), entry('书源其他榜', '其他')] });
await collision.loadEntries();
assert.equal(new Set(collision.platformNames).size, 2);
collision.selectExploreCategory(key(collision.entries[0]));
assert.equal(collision.explorePlatformLabel(collision.selectedPlatform), '其他（未分组）');
collision.selectExploreCategory(key(collision.entries[1]));
assert.equal(collision.explorePlatformLabel(collision.selectedPlatform), '其他');
assert.equal(collision.loads.at(-1), '书源其他榜');

const sheet = methods(read('ExploreCategorySheet'), ['sections']);
Object.assign(sheet, { keyword: '', recentVisible: () => false, items: collision.entries });
const sections = sheet.sections();
assert.equal(new Set(sections.map(section => section.key)).size, 2, 'sheet sections have distinct keys even with similar titles');
assert.deepEqual(Array.from(sections, section => section.title), ['其他（未分组）', '其他']);
console.log('Explore category selection checks passed (cross-group clicks, refresh, history, platform selectors and group collisions).');
