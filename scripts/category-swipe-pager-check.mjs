// node scripts/category-swipe-pager-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = path => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${path}`, 'utf8');
const context = vm.createContext({
  console, getContext: () => ({}), ScrollAlign: { CENTER: 0 },
  ExploreCategoryHistoryStore: { record() {}, entryKey: (title, url) => `${title}:${url}` },
  SearchBook: class {}, SearchCategoryChip: class {}, SEARCH_CATEGORY_ALL: 'all',
  BookTypeSupport: {
    MEDIA_CATEGORIES: ['novel', 'comic', 'audio', 'video'],
    mediaCategoryOf: book => book.category || 'novel'
  },
  ListScroller: class { scrollToIndex() {} }
});
Object.assign(context, {
  SearchPage: { HEADER_CONTROL_SIZE: 40, TITLE_ROW_HEIGHT: 56, STATUS_ROW_HEIGHT: 32, CATEGORY_BAR_HEIGHT: 44 },
  ExplorePage: { CHANNEL_BAR_HEIGHT: 44 }, AppSpacing: { MD: 8 },
  ScrollState: { Idle: 0, Scroll: 1, Fling: 2 }, Curve: { FastOutSlowIn: 0, EaseOut: 1 },
  animateTo: (_options, update) => update()
});
vm.runInContext(stripTypeScriptTypes(read('utils/CollapsingHeader.ets').replace('export class', 'class')), context);
function methods(file, names, folder = 'home') {
  const source = read(`components/${folder}/${file}.ets`);
  const bodies = names.map(name => {
    const start = new RegExp(`^  (?:async )?${name}\\(`, 'm').exec(source)?.index ?? -1;
    assert.ok(start >= 0, name);
    return source.slice(start, source.indexOf('\n  }', start) + 4);
  });
  return vm.runInContext(stripTypeScriptTypes(`({${bodies.join(',')}})`), context);
}

const dataSourceCode = read('components/home/CategorySwipePager.ets').split('@Component')[0];
context.GestureControl = { GestureType: { PAN_GESTURE: 'pan' } };
context.GestureJudgeResult = { REJECT: 'reject', CONTINUE: 'continue' };
const gesturePager = methods('CategorySwipePager', ['judgeSwipe']);
const recognizer = (tag = '', builtIn = false, type = 'pan') => ({
  getTag: () => tag, isBuiltIn: () => builtIn, getType: () => type
});
const carouselTag = 'recentReadCarouselPan';
gesturePager.swipeExcludedGestureTag = carouselTag;
assert.equal(gesturePager.judgeSwipe(recognizer('', true), [recognizer(carouselTag)]), 'reject',
  'a gesture starting in the carousel cannot switch categories, regardless of recognition threshold or carousel boundary');
assert.equal(gesturePager.judgeSwipe(recognizer('', true), []), 'continue', 'other shelf areas still switch categories');
assert.equal(gesturePager.judgeSwipe(recognizer('', true), [recognizer('other')]), 'continue');
assert.equal(gesturePager.judgeSwipe(recognizer(carouselTag), [recognizer(carouselTag)]), 'continue', 'carousel drag remains enabled');
assert.equal(gesturePager.judgeSwipe(recognizer('', true, 'tap'), [recognizer(carouselTag)]), 'continue', 'non-pan gestures are unaffected');
gesturePager.swipeExcludedGestureTag = '';
assert.equal(gesturePager.judgeSwipe(recognizer('', true), [recognizer(carouselTag)]), 'continue', 'other category gesturePager consumers keep default behavior');
const pages = vm.runInContext(stripTypeScriptTypes(`${dataSourceCode}\nnew CategoryPageDataSource()`), context);
let reloads = 0;
pages.registerDataChangeListener({ onDataReloaded: () => reloads++ });
pages.replace(['all', 'novel', 'audio']);
pages.replace(['all', 'novel', 'audio']);
assert.equal(reloads, 1, 'new results with the same category order must not reload the pager during a drag');
pages.replace(['all', 'novel', 'comic', 'audio']);
assert.equal(reloads, 2);
assert.equal(pages.getData(3), 'audio');

const pager = methods('CategorySwipePager', ['onSelectedIndexChanged', 'selectNativeIndex']);
const nativeChanges = [], selections = [];
Object.assign(pager, { mounted: true, nativeIndex: 0, selectedIndex: 0, pageKeys: ['all', 'novel', 'audio'],
  controller: { changeIndex: (...args) => nativeChanges.push(args) },
  onSelect(key) { selections.push(key); this.selectedIndex = this.pageKeys.indexOf(key); this.onSelectedIndexChanged(); }
});
pager.selectedIndex = 2;
pager.onSelectedIndexChanged();
assert.deepEqual(nativeChanges, [[2, true]], 'tab clicks animate through the native controller');
pager.selectNativeIndex(1);
assert.deepEqual(selections, ['novel']);
assert.equal(nativeChanges.length, 1, 'native drag callbacks must not start a second programmatic animation');
pager.selectNativeIndex(2);
assert.equal(pager.selectedIndex, 2, 'reversed/settled drag reflects the final native page');

const storeSource = read('utils/SearchResultAggregationStore.ets')
  .replace(/^import .*;\r?\n/gm, '').replace(/export class /g, 'class ');
vm.runInContext(stripTypeScriptTypes(storeSource), context);
const search = methods('SearchPage', [
  'applySearchResultsSnapshot', 'searchCategoryCount', 'effectiveSearchCategory',
  'searchCategoryChips', 'searchBooksForCategory', 'searchCategoryScroller'
]);
Object.assign(search, {
  resultArrivalTracker: { record() {} },
  searchCategoryScrollers: new Map(), searchResultCategory: 'audio', isSearching: true,
  searchExploreAggregateResults: true
});
const results = [
  { name: '同一本书', category: 'novel', origin: 'a', bookUrl: 'a/1' },
  { name: '同一本书', category: 'novel', origin: 'b', bookUrl: 'b/1' },
  { name: '同一本书', category: 'audio', origin: 'a', bookUrl: 'a/2' }
];
search.applySearchResultsSnapshot(results);
assert.equal(search.searchBooksForCategory('novel')[0].aggregationCount, 2);
assert.equal(search.searchBooksForCategory('audio')[0].aggregationCount, 1);
assert.equal(search.searchBooksForCategory('all').length, 2);
assert.notEqual(search.searchCategoryScroller('novel'), search.searchCategoryScroller('audio'));
assert.equal(search.searchCategoryScroller('novel'), search.searchCategoryScroller('novel'));
search.applySearchResultsSnapshot([...results, { name: '漫画', category: 'comic', origin: 'c', bookUrl: 'c/1' }]);
assert.equal(search.effectiveSearchCategory(), 'audio', 'new category insertion keeps the selected category identity');
assert.deepEqual(Array.from(search.searchCategoryChips(), chip => chip.key), ['all', 'novel', 'comic', 'audio']);
assert.equal(search.searchBooksForCategory('comic').length, 1, 'neighbor pages read newly arrived results');
assert.equal(search.searchBooksForCategory(''), search.displayedSearchResults, 'list mode reads the current filter dynamically');

context.ResultCoverCache = class { covers = new Map(); signatures = new Map(); };
context.ExploreResultCache = { isFresh: timestamp => timestamp > Date.now() - 3600000 };
vm.runInContext(stripTypeScriptTypes(read('components/home/ExplorePage.ets').match(/class ExplorePageSnapshot[\s\S]*?\n}/)[0]), context);
const explore = methods('ExplorePage', [
  'explorePageKeys', 'isCurrentExplorePage', 'explorePageLoading', 'explorePageBooks', 'selectExploreEntry',
  'explorePageSnapshot', 'retainCurrentExplorePage', 'restoreExplorePage', 'beginExploreLoad', 'isCurrentExploreLoad'
]);
let cancelledExploreLoads = 0;
Object.assign(explore, {
  coordinator: { cancelPending: () => cancelledExploreLoads++ },
  getUIContext: () => ({ animateTo: (_options, update) => update() }),
  selectedPlatform: '频道', selectedSourceUrl: 'source-a', selectedIndex: 0, isLoading: false,
  books: [{ name: '第一类的书' }], explorePages: new Map(), exploreLoadVersion: 0, exploreMetadataQueued: new Set(),
  exploreMetadataUnavailable: new Set(), shelfBookKeys: [], explorePage: 3, hasMoreExploreBooks: false,
  exploreContentLoadedAt: Date.now(), loadCount: 0, syncExploreShelfStatus() {},
  resultArrivalTracker: { discardPending() {} },
  getActiveEntries() {
    return Array.from({ length: 6 }, (_, index) => ({ sourceUrl: this.selectedSourceUrl, title: `分类${index}`, url: `${index}` }));
  },
  loadBooks() { this.loadCount++; this.beginExploreLoad(); this.books = []; },
  exploreChannelScroller: { scrollToIndex() {} }
});
const keys = Array.from(explore.explorePageKeys());
// 列表 Builder 的按值参数在首次挂载后固定；空 key 表示持续跟随当前分类。
// 模拟首次挂载时分类尚未加载，随后分类/书源发生变化但 Builder 不重建。
const listPageKey = '';
explore.isLoading = true;
assert.equal(explore.explorePageLoading(listPageKey), true);
explore.isLoading = false;
assert.equal(explore.explorePageLoading(listPageKey), false, 'list must stop loading when the first request finishes');
assert.equal(explore.explorePageBooks(listPageKey), explore.books, 'list reads the loaded current books');
explore.selectedIndex = 1;
explore.books = [{ name: '第二类的书' }];
assert.equal(explore.explorePageBooks(listPageKey)[0].name, '第二类的书', 'list follows category changes without remounting');
explore.books = [];
assert.equal(explore.explorePageLoading(listPageKey), false, 'empty/error results must leave loading state');
assert.equal(explore.explorePageBooks(listPageKey).length, 0);
explore.selectedSourceUrl = 'source-b';
assert.equal(explore.isCurrentExplorePage(listPageKey), true, 'list actions keep targeting the current source');
explore.selectedSourceUrl = 'source-a';
explore.selectedIndex = 0;
explore.books = [{ name: '第一类的书' }];
explore.exploreBooksPageKey = keys[0];
explore.selectExploreEntry(1);
assert.equal(cancelledExploreLoads, 1, 'a fresh category cancels the previous category request');
assert.equal(explore.explorePageBooks(keys[0])[0].name, '第一类的书', 'outgoing page keeps its content during the animation');
assert.equal(explore.explorePageLoading(keys[1]), true);
explore.isLoading = false;
assert.equal(explore.explorePageBooks(keys[1]).length, 0, 'failed incoming request must not display outgoing books');
explore.selectExploreEntry(0);
assert.equal(cancelledExploreLoads, 2, 'restoring a warm category also cancels outgoing work');
assert.equal(explore.isLoading, false, 'returning to a warm category must not enter loading');
assert.equal(explore.loadCount, 1, 'warm return must not call loadBooks or read the network/disk cache');
assert.equal(explore.explorePage, 3, 'pagination position is retained');
assert.equal(explore.hasMoreExploreBooks, false, 'end-of-results state is retained');
const oldVersion = explore.exploreLoadVersion;
assert.equal(explore.restoreExplorePage('missing'), false);
assert.equal(explore.exploreLoadVersion, oldVersion, 'cache miss does not mutate the active request');
explore.explorePages.get(keys[0]).scrollOffset = 480;
explore.selectExploreEntry(1);
explore.selectExploreEntry(0);
assert.equal(explore.explorePages.get(keys[0]).scrollOffset, 480, 'leaving and restoring retains scroll offset');
assert.equal(explore.explorePageLoading(keys[0]), false);
assert.equal(explore.explorePageBooks(keys[0])[0].name, '第一类的书');
for (let index = 0; index < 5; index++) {
  explore.selectedIndex = index;
  explore.isLoading = false;
  explore.exploreBooksPageKey = keys[index];
  explore.books = [{ name: `书${index}` }];
  explore.selectExploreEntry(index + 1);
}
assert.equal(explore.explorePages.size, 5, 'visited categories retain content beyond adjacent pages');
explore.isLoading = false;
explore.selectedPlatform = '另一个频道';
const newKey = explore.explorePageKeys()[explore.selectedIndex];
explore.selectExploreEntry(0);
assert.equal(explore.explorePages.has(newKey), false, 'changing platform must not relabel old books as new-category previews');
explore.selectedSourceUrl = 'source-b';
assert.notEqual(explore.explorePageKeys()[0], keys[0], 'source identity is part of each page key');

// A late shelf-status lookup during pagination cannot save a new category under the old key.
const saved = [];
context.ExploreResultCache.save = (...args) => saved.push(args);
const pagination = methods('ExplorePage', ['loadMoreExploreBooks', 'mergeExploreBooks', 'isCurrentExploreLoad']);
let finishShelfLookup;
Object.assign(pagination, { isLoading: false, isLoadingMore: false, hasMoreExploreBooks: true,
  books: [{ origin: 'a', bookUrl: '1' }], explorePage: 1, exploreLoadVersion: 1, selectedIndex: 0,
  selectedPlatform: 'group', getActiveEntries: () => [{ title: 'old', sourceUrl: 'a', url: '/old' }],
  coordinator: { explore: async () => [{ origin: 'a', bookUrl: '2' }] }, getSelectedSiteLabel: () => 'site',
  syncExploreShelfStatus: () => new Promise(resolve => { finishShelfLookup = resolve; }),
  retainCurrentExplorePage() { assert.fail('stale pagination cannot save current page'); }
});
const pendingPage = pagination.loadMoreExploreBooks();
await new Promise(resolve => setImmediate(resolve));
assert.equal(typeof finishShelfLookup, 'function');
pagination.exploreLoadVersion++;
pagination.books = [{ origin: 'b', bookUrl: 'new' }];
finishShelfLookup();
await pendingPage;
assert.equal(saved.length, 0, 'late pagination cannot corrupt another category cache');

// 分类各自从纵向位置 0 开始，但共享的顶栏收起量不能因此归零。
for (const [file, prefix] of [['ExplorePage', 'explore'], ['SearchPage', 'search']]) {
  const isSearch = prefix === 'search';
  const page = methods(file, [
    `uses${isSearch ? 'Search' : 'Explore'}CategoryPager`, `${prefix}ResultTopPadding`,
    `${prefix}HeaderCollapseValue`, `${prefix}TopOverlayHeight`,
    `on${isSearch ? 'Search' : 'Explore'}ListScroll`, `on${isSearch ? 'Search' : 'Explore'}ListScrollStop`,
    ...(isSearch ? ['searchCollapsibleHeight', 'searchFieldRowHeight', 'searchStatusRowTop'] : [])
  ]);
  Object.assign(page, {
    statusBarHeight: 24, showResult: true, isLoading: true, statusMessage: '搜索中',
    books: [], displayedSearchResults: [], showSearchCategoryBar: () => true,
    getActiveEntries: () => [{}], showsExploreChannelBar: () => true, shouldShowExploreStatus: () => false,
    searchResultLayout: 'grid', exploreResultLayout: 'grid'
  });
  const distance = isSearch ? page.searchCollapsibleHeight() : 56;
  const collapseKey = `${prefix}HeaderCollapse`;
  const value = () => page[`${prefix}HeaderCollapseValue`]();
  page[collapseKey] = distance;
  assert.equal(value(), distance, `${file}: loading/empty incoming page preserves the collapsed header`);
  const expandedInset = page[`${prefix}TopOverlayHeight`]();
  for (const collapse of [0, distance / 2, distance]) {
    page[collapseKey] = collapse;
    assert.equal(page[`${prefix}ResultTopPadding`](), expandedInset,
      `${file}: header movement must not resize scroll content and feed back into scrolling`);
  }

  const name = isSearch ? 'Search' : 'Explore';
  const list = { userScrollOnly: true, gridUserScrolled: false,
    scroller: { currentOffset: () => ({ yOffset: 0 }) },
    onListScroll: (delta, offset) => page[`on${name}ListScroll`](delta, offset),
    onListScrollStop: offset => page[`on${name}ListScrollStop`](offset)
  };
  const listSource = read('components/book/SearchBookResultList.ets');
  for (const event of ['onDidScroll', 'onScrollStop']) {
    const callback = listSource.match(new RegExp(`\\.${event}\\((\\([^\\n]*\\) => \\{[\\s\\S]*?\\n\\s*\\})\\)`))[1];
    context.list = list;
    vm.runInContext(stripTypeScriptTypes(`list.${event} = function () { return ${callback}; }.call(list);`), context);
  }
  list.onDidScroll(-200, 0);
  list.onScrollStop();
  assert.equal(value(), distance, `${file}: mounting/resetting the new list cannot expand the header`);
  list.onDidScroll(-12, 1);
  assert.equal(value(), distance - 12, `${file}: real downward dragging still reveals the header`);
  page[`on${name}ListScroll`](12, 0);
  assert.equal(value(), distance - 12, `${file}: top spring rebound does not hide it again`);
  page[`on${name}ListScroll`](-distance, -40);
  assert.equal(value(), 0, `${file}: downward dragging can fully expand it`);
  page[`on${name}ListScroll`](distance, distance);
  assert.equal(value(), distance, `${file}: upward scrolling still collapses it`);
  page.isLoading = false;
  page.books = [{}]; page.displayedSearchResults = [{}];
  page.searchResultLayout = 'list'; page.exploreResultLayout = 'list';
  assert.equal(page[`${prefix}ResultTopPadding`](), expandedInset,
    `${file}: ordinary list mode retains its fixed expanded-header spacer`);
  page[`on${name}ListScroll`](0, 0);
  assert.equal(value(), isSearch ? 0 : distance,
    `${file}: discovery list paging also preserves the shared header when an idle page mounts`);
}

// 分类进入时补齐共享顶栏的滚动距离；滚动中只更新收起量，不能反过来调整列表位置或尺寸。
const pending = new Map();
let timerId = 0;
context.setTimeout = callback => { pending.set(++timerId, callback); return timerId; };
context.clearTimeout = id => pending.delete(id);
const grid = methods('SearchBookResultList', [
  'onGridPageActiveChanged', 'alignGridToHeader', 'aboutToDisappear'
], 'book');
let gridOffset = 0;
let scrollCalls = 0;
Object.assign(grid, {
  drainCoverQueue() {}, pendingCovers: new Map(), coverGeneration: 0,
  layoutMode: 'grid', userScrollOnly: true, gridPageActive: true, gridHeaderCollapse: 56,
  gridAlignTimer: -1, gridUserScrolled: false, restoredScroll: false, initialScrollOffset: 0,
  scroller: {
    currentOffset: () => ({ yOffset: gridOffset }),
    scrollTo: options => { gridOffset = options.yOffset; scrollCalls++; assert.equal(options.animation, false); }
  }
});
const flush = () => { const callbacks = [...pending.values()]; pending.clear(); callbacks.forEach(callback => callback()); };
grid.onGridPageActiveChanged();
assert.equal(scrollCalls, 0, 'initial alignment waits for the List to mount');
flush();
assert.equal(gridOffset, 56, 'a new category starts below the collapsed header without a blank gap');
grid.gridHeaderCollapse = 20;
flush();
assert.equal(scrollCalls, 1, 'header scrolling alone never queues another alignment');
gridOffset = 240;
grid.onGridPageActiveChanged(); flush();
assert.equal(gridOffset, 240, 'returning to a category preserves its deeper scroll position');
gridOffset = 0;
grid.onGridPageActiveChanged();
grid.gridPageActive = false;
grid.onGridPageActiveChanged(); flush();
assert.equal(gridOffset, 0, 'leaving a category cancels pending alignment');
grid.gridPageActive = true;
grid.onGridPageActiveChanged(); grid.aboutToDisappear(); flush();
assert.equal(gridOffset, 0, 'unmounting cancels pending scroller work');
grid.restoredScroll = false;
grid.initialScrollOffset = 480;
grid.onGridPageActiveChanged(); flush();
assert.equal(gridOffset, 480, 'a recycled category restores its saved scroll position');

console.log('PASS category pager: page identity, aggregation, previews, bounded cache, shared header, stable scroll layout and category-entry alignment');
