// node scripts/result-cover-stability-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const context = vm.createContext({ SearchBook: class {}, SearchBookShelfHelper: {
  keyOf: book => `${book.origin}:${book.bookUrl}`, isInShelf: (book, keys) => keys.includes(`${book.origin}:${book.bookUrl}`)
}, SEARCH_CATEGORY_ALL: 'all', PreparedResultCover: class {},
  ResultCoverPreparation: { options: () => ({ showCover: false }), signature: book => JSON.stringify(book) } });
function methods(source, names) {
  const bodies = names.map(name => {
    const start = source.indexOf(`  ${name}(`);
    assert.ok(start >= 0, name);
    return source.slice(start, source.indexOf('\n  }', start) + 4);
  });
  return vm.runInContext(stripTypeScriptTypes(`({${bodies.join(',')}})`), context);
}
const source = read('components/book/SearchBookResultList.ets');
const dataSourceCode = source.slice(source.indexOf('class SearchBookResultDataSource'), source.indexOf('@Component'));
const dataSource = vm.runInContext(stripTypeScriptTypes(`${dataSourceCode}\nnew SearchBookResultDataSource()`), context);
let reloads = 0;
dataSource.registerDataChangeListener({ onDataReloaded() { reloads++; } });
const list = methods(source, ['onBooksChanged', 'onShelfBookKeysChanged', 'resultBook', 'itemKey', 'listItemKey', 'safeText',
  'requestResultCovers', 'publishReadyResults', 'drainCoverQueue']);
Object.assign(list, { dataSource, layoutMode: 'grid', books: [], shelfBookKeys: [],
  coverMounted: false, pendingCovers: new Map(), preparedCovers: new Map(), preparedSignatures: new Map(),
  resultBooks: new Map(), tagCache: new Map(), readyCoverUrls: new Map() });
const first = { origin: 'source-a', bookUrl: '/book', name: '同名书', author: '',
  aggregationKey: 'title:novel:同名书', aggregationCount: 1 };
list.books = [first]; list.onBooksChanged();
const identity = dataSource.getData(0);
list.readyCoverUrls.set(identity, 'decoded-cover');
for (const count of [2, 3, 12]) {
  list.books = [{ ...first, author: '补全作者', aggregationCount: count }]; list.onBooksChanged();
  assert.equal(dataSource.getData(0), identity, 'aggregation count is content, not node identity');
  assert.equal(reloads, 1, 'metadata/count changes do not reload the lazy tree');
  assert.equal(list.resultBook(identity).aggregationCount, count, 'retained node reads the latest count');
  assert.equal(list.resultBook(identity).author, '补全作者');
  assert.equal(list.readyCoverUrls.get(identity), 'decoded-cover');
}
const second = { origin: 'source-b', bookUrl: '/second', name: '另一本', aggregationCount: 1 };
list.books = [second, { ...first, aggregationCount: 13 }]; list.onBooksChanged();
assert.equal(dataSource.getData(1), identity, 'sorting/appending retains the existing identity');
assert.equal(list.readyCoverUrls.get(identity), 'decoded-cover');
const rawKey = list.itemKey(second);
assert.equal(list.itemKey({ ...second, name: '元数据改名', originName: '改名书源' }), rawKey);
list.books = [second]; list.onBooksChanged();
assert.equal(list.readyCoverUrls.has(identity), false, 'removed results release retained cover entries');
assert.equal(list.resultBooks.size, 1, 'snapshot stays bounded to current results');
list.layoutMode = 'list';
list.books = [first]; list.onBooksChanged();
const beforeActions = reloads;
list.books = [{ ...first, aggregationCount: 2 }]; list.onBooksChanged();
assert.equal(reloads, beforeActions + 1, 'single -> group updates cached HDS swipe actions in list mode');
list.books = [{ ...first, aggregationCount: 3 }]; list.onBooksChanged();
assert.equal(reloads, beforeActions + 1, 'already grouped rows keep their identity as the count grows');

const search = methods(read('components/home/SearchPage.ets'), ['usesSearchCategoryPager', 'searchCategoryPageKeys']);
search.searchResultLayout = 'grid';
let chips = [];
search.searchCategoryChips = () => chips;
assert.equal(search.usesSearchCategoryPager(), true, 'mount the pager before any category arrives');
assert.deepEqual(Array.from(search.searchCategoryPageKeys()), ['all']);
chips = [{ key: 'all' }, { key: 'novel' }, { key: 'comic' }];
assert.equal(search.usesSearchCategoryPager(), true, 'category bar must not replace the whole results subtree');
assert.equal(search.searchCategoryPageKeys()[0], 'all', 'the first page identity survives category discovery');

const tileCode = read('utils/BookTileLayout.ets').replace('export class', 'class');
vm.runInContext(stripTypeScriptTypes(tileCode), context);
const layout = vm.runInContext('BookTileLayout', context);
assert.ok(!read('components/book/SearchResultLoading.ets').includes('ForEach'), 'waiting state has no per-book placeholder cards');
assert.equal(layout.columnCount(360), 3);
assert.equal(layout.columnCount(460), 4, 'regression: a wider phone must not paint three provisional columns');
for (const [page, width] of [['SearchPage', 'searchViewportWidth'], ['ExplorePage', 'exploreViewportWidth']]) {
  assert.ok(read(`components/home/${page}.ets`).includes(`gridViewportWidth: this.${width}`));
}
assert.ok(source.includes('@Prop gridViewportWidth'), 'result grid starts with parent measurement');
console.log('PASS result covers: stable identity, live metadata, retained covers, bounded state, list actions, category growth and measured grid columns');
