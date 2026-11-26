// 书封扉页：标签与章数字数一行、页码不算扉页、停在扉页时页眉页脚为空、分页缓存键不含封面路径。
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const strip = file => readEtsModule(file).replace(/^import [\s\S]*?;\r?\n/gm, '').replace(/^export /gm, '');
const readBook = readEtsModule('pages/ReadBook.ets');
function method(name) {
  const start = readBook.search(new RegExp(`^  (?:async )?${name}\\(`, 'm'));
  assert(start >= 0, name);
  return readBook.slice(start, readBook.indexOf('\n  }', start) + 4);
}
const sandbox = vm.createContext({
  graphicsText: { FontWeight: Object.fromEntries(Array.from({ length: 9 }, (_, i) => [`W${(i + 1) * 100}`, i])) }
});
vm.runInContext(stripTypeScriptTypes([
  strip('core/reader/ReaderFrontPageText.ts'),
  strip('core/reader/ReaderInfoBarModel.ts'),
  strip('core/reader/ReaderFrontPage.ets'),
  `class Reader { ${method('applyReaderFrontPageToInfoBar')}
    readerFrontPageCount(chapterIndex) { return chapterIndex === 0 ? this.front : 0; } }`,
  'globalThis.api = { ReaderFrontPageText, ReaderInfoBarContext, ReaderInfoBarText, ReaderInfoItem, ReaderFrontPage, ' +
  'ReaderFrontPageSpec, Reader };'
].join('\n')), sandbox);
const { ReaderFrontPageText: Text, ReaderInfoBarContext: Context, ReaderInfoBarText: Bar, ReaderInfoItem: Item,
  ReaderFrontPage: Front, ReaderFrontPageSpec: Spec, Reader } = sandbox.api;

// 标签：拆开、去重，去掉日期、状态、数字和过长的词，最多三个
assert.deepEqual(Array.from(Text.tags('玄幻,东方玄幻 连载 2024-05-01 玄幻')), ['玄幻', '东方玄幻']);
assert.deepEqual(Array.from(Text.tags('悬疑|民国/群像、都市 完结')), ['悬疑', '民国', '群像']);
assert.deepEqual(Array.from(Text.tags('这是一个特别长的分类名 科幻')), ['科幻']);
assert.deepEqual(Array.from(Text.tags('')), []);
// 章数字数
assert.equal(Text.meta(312, '986000'), '共 312 章 · 98.6 万字');
assert.equal(Text.meta(312, '98.6万字'), '共 312 章 · 98.6万字');
assert.equal(Text.meta(12, '3200'), '共 12 章 · 3200 字');
assert.equal(Text.meta(0, '120 万'), '120万字');
assert.equal(Text.meta(5, ''), '共 5 章');
assert.equal(Text.words('1000000'), '100 万字');
console.log('PASS: tags and meta line');

// 页码：扉页和第一章第一页都存成 0，页数不算扉页
assert.equal(Text.contentPageIndex(0, 1), 0);
assert.equal(Text.contentPageIndex(1, 1), 0);
assert.equal(Text.contentPageIndex(5, 1), 4);
assert.equal(Text.contentPageIndex(5, 0), 5);
assert.equal(Text.contentPageCount(10, 1), 9);
assert.equal(Text.contentPageCount(1, 1), 1, '只有扉页时按一页算');
assert.equal(Text.contentPageCount(0, 1), 0, '页数未知时保持未知');
console.log('PASS: content page index and count');

// 页眉页脚：第一章页码不算扉页；停在扉页时文字和电量都不显示
const reader = new Reader();
reader.front = 1;
const onFront = new Context();
onFront.pageIndex = 0;
onFront.pageCount = 10;
onFront.chapterCount = 3;
onFront.timeText = '21:46';
onFront.batteryPercent = 80;
reader.applyReaderFrontPageToInfoBar(onFront, 0, 0);
assert.equal(onFront.frontPage, true);
assert.equal(onFront.pageCount, 9);
for (const item of [Item.PAGE, Item.TIME, Item.TIME_BATTERY, Item.CHAPTER_TITLE]) {
  assert.equal(Bar.leading(item, onFront), '', `${item} 在扉页上不显示`);
}
assert.equal(Bar.battery(Item.BATTERY, onFront), -1);
assert.equal(Bar.chapterPercent(onFront), 0);
const firstText = new Context();
firstText.pageIndex = 1;
firstText.pageCount = 10;
firstText.chapterCount = 3;
reader.applyReaderFrontPageToInfoBar(firstText, 0, 1);
assert.equal(firstText.frontPage, false);
assert.equal(Bar.of(Item.PAGE, firstText), '1/9', '第一章第一页显示为 1/9');
const otherChapter = new Context();
otherChapter.pageIndex = 2;
otherChapter.pageCount = 8;
reader.applyReaderFrontPageToInfoBar(otherChapter, 1, 2);
assert.equal(Bar.of(Item.PAGE, otherChapter), '3/8', '其余章节不受影响');
console.log('PASS: info bar skips the front page');

// 标识：分页缓存键用的标识不含封面路径，页标识含
const spec = new Spec();
spec.title = '长夜书灯';
spec.author = '林间雪';
spec.intro = '镇上的书铺只在夜里开门。';
const before = spec.layoutIdentity();
const identityBefore = spec.identity();
spec.coverPath = '/data/cover.jpg';
assert.equal(spec.layoutIdentity(), before, '封面后到不改分页缓存键');
assert.notEqual(spec.identity(), identityBefore, '封面换了页标识要变');
spec.intro = '另一段简介';
assert.notEqual(spec.layoutIdentity(), before, '简介变了要重排');
assert.equal(Front.cleanIntro('<p>第一段</p><br/>\n　　第二段&nbsp;&amp;  \n\n'), '第一段 第二段 &');
console.log('PASS: identities and intro cleanup');

// 接线：分页缓存键带扉页标识，第一章的翻页文档挂扉页，滚动阅读第一块挂扉页
assert.match(method('buildReaderPaginationCacheKey'), /readerFrontPageKeyIdentity\(chapterIndex\)/);
assert.match(method('createIncrementalReaderV2Pagination'), /document\.frontPage = this\.readerFrontPageCount\(chapterIndex\) > 0/);
assert.match(method('runReaderContinuousLayout'), /if \(request\.index === 0\) document\.frontPage = this\.readerFrontPageSpecFor/);
console.log('PASS: wiring');
