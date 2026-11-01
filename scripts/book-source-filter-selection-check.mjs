// Exercise production filtering, reset and select-all against the displayed counter.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/pages/BookSource.ets', import.meta.url), 'utf8');
function method(name) {
  const match = new RegExp(`^  (?:private )?${name}\\(`, 'm').exec(source);
  assert(match, name);
  return source.slice(match.index, source.indexOf('\n  }', match.index) + 4);
}
const counter = source.match(/Text\((`已选择 \$\{this\.selectedSourceUrls\.length\}\/[^`]+`)\)/)?.[1];
assert(counter, 'selection counter must be present');
const context = vm.createContext({});
const page = vm.runInContext(stripTypeScriptTypes(`new (class {
  ${['applySourceFilters', 'sortFilteredSources', 'activeSourceSortMode', 'sourceNeedsLogin',
    'sourceHasExplorePage', 'setSourceFilterValue', 'resetSourceFilters', 'activeSourceFilterCount',
    'hasActiveSourceFilters', 'enterSelectionMode', 'exitSelectionMode', 'getSelectedSourceUrlLookup',
    'isAllSelected', 'selectAllSources', 'toggleAllSources', 'pruneSelectedSources'].map(method).join('\n')}
  counter() { return ${counter}; }
})()`, { mode: 'strip' }), context);

const rows = Array.from({ length: 158 }, (_, index) => ({
  bookSourceUrl: `source-${index}`, bookSourceName: `书源 ${index}`,
  bookSourceGroup: index === 0 ? '目标分组' : '其他分组',
  sourceFormat: index < 3 ? 'native' : 'legado',
  customOrder: index, enabled: index === 0, enabledExplore: index === 0,
  exploreUrl: index === 0 ? '/explore' : '', loginUrl: index === 0 ? '/login' : ''
}));
function reset() {
  Object.assign(page, {
    allSources: rows, sources: rows, visibleSources: rows,
    searchText: '', activeSourceGroup: '__all__', sourceFormatFilter: 'all', sourceSortMode: 'custom',
    sourceEnabledFilter: 'all', sourceExplorePageFilter: 'all', sourceExploreEnabledFilter: 'all',
    sourceLoginFilter: 'all', sourceValidationFilter: 'all', selectedSourceUrls: [],
    sourceListDataSource: { replace() {} }, isSourceAtBottom: () => false,
    stopSourceSelectionAutoScroll() {}
  });
}

for (const scenario of [
  { sourceEnabledFilter: 'yes' },
  { activeSourceGroup: '目标分组' },
  { sourceFormatFilter: 'native', activeSourceGroup: '目标分组' },
  { sourceFormatFilter: 'native', sourceEnabledFilter: 'yes', activeSourceGroup: '目标分组' },
  { searchText: 'source-0' },
  { sourceExplorePageFilter: 'yes' },
  { sourceExploreEnabledFilter: 'yes' },
  { sourceLoginFilter: 'yes' }
]) {
  reset();
  Object.assign(page, scenario);
  page.applySourceFilters();
  page.enterSelectionMode();
  assert.equal(page.counter(), '已选择 0/1', JSON.stringify(scenario));
  page.toggleAllSources();
  assert.equal(page.counter(), '已选择 1/1');
  assert.deepEqual(Array.from(page.selectedSourceUrls), ['source-0']);
  assert(page.isAllSelected());
  page.toggleAllSources();
  assert.equal(page.counter(), '已选择 0/1');
  assert(!page.isAllSelected());
}

for (const [format, expected] of [['all', 158], ['native', 3], ['legado', 155]]) {
  reset();
  page.sourceFormatFilter = format;
  page.applySourceFilters();
  page.enterSelectionMode();
  assert.equal(page.counter(), `已选择 0/${expected}`);
  page.toggleAllSources();
  assert.equal(page.counter(), `已选择 ${expected}/${expected}`);
}

reset();
page.searchText = 'no match';
page.applySourceFilters();
page.enterSelectionMode();
page.toggleAllSources();
assert.equal(page.counter(), '已选择 0/0');
assert(!page.isAllSelected());

reset();
for (const key of ['enabled', 'explorePage', 'exploreEnabled', 'login']) page.setSourceFilterValue(key, 'yes');
assert.equal(page.activeSourceFilterCount(), 4);
assert.equal(page.sources.length, 1);
page.resetSourceFilters();
assert.equal(page.activeSourceFilterCount(), 0);
assert(!page.hasActiveSourceFilters());
assert.equal(page.sources.length, 158);
page.setSourceFilterValue('enabled', 'yes');
assert.equal(page.activeSourceFilterCount(), 1);
page.setSourceFilterValue('enabled', 'all');
assert.equal(page.activeSourceFilterCount(), 0);
assert.equal(page.sources.length, 158);

console.log('Book source filter/selection checks passed: 158 sources, group/format/search/status filters, counters, select-all, empty list and filter reset.');
