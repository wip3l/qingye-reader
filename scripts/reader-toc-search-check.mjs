// Run with: node --experimental-strip-types scripts/reader-toc-search-check.mjs
// Keep keyed row callbacks alive across filtering, as ArkUI ForEach does.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const file = new URL('../entry/src/main/ets/components/reader/ReaderTocPanel.ets', import.meta.url);
const source = fs.readFileSync(file, 'utf8');
const rowSource = source.slice(source.indexOf('ForEach(this.visibleChapters'), source.indexOf('  @Builder\n  virtualScrollbar'));
function method(name) {
  const start = new RegExp(`^  private (?:async )?${name}\\(`, 'm').exec(source)?.index;
  assert.notEqual(start, undefined, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
}
const title = rowSource.match(/Text\((this\.chapterTitle\([^\n]+)\)/)[1];
const jump = rowSource.match(/\.onClick\(\(\) => (this\.onJumpToChapter\([^\n]+)\)/)[1];
const selected = rowSource.match(/\.backgroundColor\(([^\n]+) \?/)[1];
const key = rowSource.match(/\n\s*(`[^\n]+`)\)/)[1];

const foldSource = fs.readFileSync(new URL('../entry/src/main/ets/core/reader/TocVolumeFold.ts', import.meta.url), 'utf8');
const TocVolumeFold = vm.runInNewContext(`${stripTypeScriptTypes(foldSource).replace('export class', 'class')}; TocVolumeFold`,
  { Map, Set });
// 第 1～3 章不属于任何卷，之后三卷从第 4、21、51 章开始。
const VOLUMES = { 3: '第一卷', 20: '第二卷', 50: '第三卷' };

function harness(reverseOrder = false) {
  const timers = [];
  const context = vm.createContext({
    console: { info() {}, warn() {} },
    setTimeout: fn => { timers.push(fn); return timers.length; },
    ScrollAlign: { START: 0, CENTER: 1, END: 2 }, TOC_WINDOW_PAGE_SIZE: 72,
    TocVolumeFold, BookChapter: { volumeTitleOf: chapter => chapter.volume || '' },
    HdsFeedback: { showToast() {} }
  });
  const methods = ['isSearchActive', 'globalIndex', 'chapterAtDisplayIndex', 'setWindowAround',
    'submitSearch', 'clearSearchResult', 'toggleOrder', 'scrollToCurrentChapter', 'scrollToChapter',
    'loadNextPage', 'loadPreviousPage', 'positionOf', 'ensureDisplayOrder', 'displayCount',
    'canonicalAtDisplayIndex', 'displayIndexOf', 'foldMemoryKey', 'expandVolumeOf', 'setCollapsedVolumes',
    'volumeHeadOf', 'isVolumeCollapsed', 'toggleVolume', 'toggleAllVolumes', 'refillWindow'];
  const panel = vm.runInContext(stripTypeScriptTypes(`({${methods.map(method).join(',')}})`), context);
  const chapters = Array.from({ length: 75 }, (_, index) => ({
    index, title: `第${index + 1}章`, url: `chapter-${index}`, cacheDate: 1, volume: VOLUMES[index] || ''
  }));
  Object.assign(panel, {
    chapters, reverseOrder, currentChapterIndex: 0, book: { bookUrl: 'test-book' },
    searchVisible: true, searchResultActive: false, searchChapterIndexes: [], searchQuery: '',
    searchRequestSerial: 0, positionRequestSerial: 0, orderRevision: 0,
    collapsedVolumes: [], volumeStarts: [], displayOrder: null, displayOrderSignature: '', volumeStartsSignature: '',
    visibleChapters: [], windowStart: 0,
    tocScroller: { scrollToIndex() {} },
    chapterTitle: index => chapters[index].title, onJumpToChapter: index => index
  });
  const cache = new Map();
  const makeRow = vm.runInContext(`(function(chapter, localIndex) {
    return { key: ${key}, title: () => ${title}, jump: () => ${jump}, selected: () => ${selected} };
  })`, context);
  return { panel, flush() {
    while (timers.length) timers.shift()();
  }, render() {
    return panel.visibleChapters.map((chapter, localIndex) => {
      const candidate = makeRow.call(panel, chapter, localIndex);
      if (!cache.has(candidate.key)) cache.set(candidate.key, candidate);
      return cache.get(candidate.key);
    });
  } };
}

for (const reversed of [false, true]) {
  const h = harness(reversed);
  const p = h.panel;
  p.setWindowAround(35, 1);
  h.render(); // Existing chapter rows capture their positions in the unfiltered list.
  p.searchQuery = '36';
  await p.submitSearch();
  h.flush();
  let rows = h.render();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].title(), '第36章', 'search 36 must display chapter 36, not chapter 1');
  assert.equal(rows[0].jump(), 35, 'search result opens the matching chapter');
  assert.equal(rows[0].selected(), false, 'chapter 36 is not highlighted while reading chapter 1');
  p.currentChapterIndex = 35;
  assert.equal(rows[0].selected(), true, 'selected state follows the actual chapter');

  p.searchQuery = '3';
  await p.submitSearch();
  h.flush();
  rows = h.render();
  const expected = p.chapters.filter(chapter => chapter.title.includes('3'));
  if (reversed) expected.reverse();
  assert.deepEqual(rows.map(row => row.jump()), expected.map(chapter => chapter.index));
  assert.deepEqual(rows.map(row => row.title()), expected.map(chapter => chapter.title));

  p.searchQuery = 'missing';
  await p.submitSearch();
  assert.equal(h.render().length, 0, 'no matches leaves an empty result');
  p.clearSearchResult();
  h.flush();
  rows = h.render();
  assert.deepEqual(rows.map(row => row.jump()), p.visibleChapters.map(chapter => chapter.index));
  assert.deepEqual(rows.map(row => row.title()), p.visibleChapters.map(chapter => chapter.title));

  p.toggleOrder();
  h.flush();
  rows = h.render();
  assert.deepEqual(rows.map(row => row.jump()), p.visibleChapters.map(chapter => chapter.index));
  p.setWindowAround(74, 0);
  h.render();
  p.loadPreviousPage();
  h.flush();
  p.loadNextPage();
  h.flush();
  rows = h.render();
  assert.deepEqual(rows.map(row => row.title()), p.visibleChapters.map(chapter => chapter.title),
    'extending a catalog window preserves retained row titles');
  assert.deepEqual(rows.map(row => row.jump()), p.visibleChapters.map(chapter => chapter.index));
}

// 分卷收起：收起的卷只留卷头行，卷头上方的窗口不动，被收起的章节定位到卷头行。
for (const reversed of [false, true]) {
  const h = harness(reversed);
  const p = h.panel;
  p.setWindowAround(0, 0);
  const head = reversed ? 49 : 20;
  assert.equal(p.volumeHeadOf(p.chapters[head]), 20, 'volume header sits on the first row the volume shows');
  assert.equal(p.volumeHeadOf(p.chapters[reversed ? 20 : 49]), -1);
  assert.equal(p.volumeHeadOf(p.chapters[1]), -1, 'chapters before the first volume have no header');
  const before = p.visibleChapters.slice(0, p.visibleChapters.indexOf(p.chapters[head]) + 1);
  const startBefore = p.windowStart;
  p.toggleVolume(20);
  assert.equal(p.isVolumeCollapsed(20), true);
  assert.equal(p.windowStart, startBefore, 'collapsing keeps the window start');
  assert.deepEqual(p.visibleChapters.slice(0, before.length), before, 'rows above the header are untouched');
  const shown = p.visibleChapters.map(chapter => chapter.index);
  for (let index = 20; index < 50; index++) {
    assert.equal(shown.includes(index), index === head, `chapter ${index + 1} visibility`);
  }
  assert.equal(p.displayCount(), 75 - 29);
  assert.equal(p.canonicalAtDisplayIndex(p.displayIndexOf(35)), head, 'hidden chapters map to the header row');
  const local = p.setWindowAround(35, 1);
  assert.equal(p.visibleChapters[local].index, head);
  p.loadNextPage();
  h.flush();
  assert.equal(new Set(p.visibleChapters).size, p.visibleChapters.length, 'paging never repeats rows');

  p.toggleOrder();
  h.flush();
  assert.equal(p.isVolumeCollapsed(20), true, 'collapse survives order changes');
  assert.equal(p.chapterAtDisplayIndex(p.displayIndexOf(30)).index, reversed ? 20 : 49);

  p.searchQuery = '3';
  await p.submitSearch();
  assert.ok(p.visibleChapters.some(chapter => chapter.index === 29), 'search ignores collapsed volumes');
  assert.equal(p.isVolumeCollapsed(20), false, 'search results show headers expanded');
  p.clearSearchResult();
  h.flush();

  assert.equal(p.expandVolumeOf(25), true);
  assert.equal(p.displayOrder, null, 'expanding the last collapsed volume drops the display order');
  p.toggleAllVolumes(50);
  h.flush();
  assert.deepEqual([...p.collapsedVolumes], [3, 20, 50]);
  assert.equal(p.displayCount(), 3 + 3);
  p.toggleAllVolumes(50);
  assert.deepEqual([...p.collapsedVolumes], []);
}
const remembered = harness(false).panel;
remembered.toggleVolume(3);
const reopened = harness(false).panel;
reopened.collapsedVolumes = TocVolumeFold.recall(reopened.foldMemoryKey());
assert.deepEqual([...reopened.collapsedVolumes], [3], 'collapsed volumes are remembered per book');
console.log('Reader TOC checks passed: retained rows, search, selection, clearing, reverse order, paging and volume folding.');
