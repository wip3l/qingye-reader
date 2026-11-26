// 章末卡片：标题、全书进度、数字写法、末章文字，以及接线（缓存键只看开关、数字跟着划线版本号原地重建）。
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
const sandbox = vm.createContext({});
vm.runInContext(stripTypeScriptTypes(strip('core/reader/ReaderChapterEndText.ts') +
  '\nglobalThis.Text = ReaderChapterEndText;'), sandbox);
const Text = sandbox.Text;

assert.equal(Text.headLabel('第十二章 借书簿'), '第十二章 读完');
assert.equal(Text.headLabel('第 12 章　借书簿'), '第12章 读完');
assert.equal(Text.headLabel('第三百零五回 雨夜'), '第三百零五回 读完');
assert.equal(Text.headLabel('楔子'), '本章读完');
assert.equal(Text.headLabel(''), '本章读完');
assert.equal(Text.bookPercent(11, 312), '全书 4%');
assert.equal(Text.bookPercent(311, 312), '全书 100%');
assert.equal(Text.bookPercent(0, 0), '');
assert.equal(Text.number(3186), '3,186');
assert.equal(Text.number(1234567), '1,234,567');
assert.equal(Text.number(12), '12');
assert.equal(Text.todayMinutes(-1), '', '还没取到写“—”');
assert.equal(Text.todayMinutes(0), '', '今天还没记下时长写“—”');
assert.equal(Text.todayMinutes(20000), '1', '不足一分钟算一分钟');
assert.equal(Text.todayMinutes(38 * 60000 + 20000), '38');
assert.equal(Text.endOfBook(true), '全书完');
assert.equal(Text.endOfBook(false), '已读到最新一章');
assert.equal(Text.nextTitle('  第十三章\n雨夜还书 '), '第十三章 雨夜还书');
console.log('PASS: chapter-end text');

// 接线
assert.match(method('buildReaderPaginationCacheKey'), /readerChapterEndKeyIdentity\(\)/);
assert.match(method('readerChapterEndKeyIdentity'), /'_end2'/, '本章说包进卡片后排法变了，键要换版本');
assert.doesNotMatch(method('readerChapterEndKeyIdentity'), /readerTodayReadMs|readerAnnotations/,
  '会变的数字不进缓存键，否则取分页时键对不上');
assert.match(method('createIncrementalReaderV2Pagination'), /document\.chapterEnd = this\.readerChapterEndSpecFor\(chapterIndex, source\)/);
assert.match(method('runReaderContinuousLayout'), /readerContinuousEndsOf\(request\.chapter\)\.length - 1/);
assert.match(method('readerAnnotationStamp'), /readerChapterEndVersion/);
assert.match(method('decorateReaderV2Page'), /page\.chapterEndMode > 0\) this\.refreshReaderChapterEndCard/);
const paginator = readEtsModule('core/reader/ReaderV2Paginator.ets');
assert.match(paginator, /session\.continuous \? Number\.POSITIVE_INFINITY : column\.bottom - page\.contentBottomPx/,
  '翻页模式只用末页留白');
assert.match(paginator, /ReaderChapterEnd\.wrapInsetX\(session\.snapshot\)/, '本章说包进卡片时往里收');
assert.match(paginator, /columnBottom - reserve/, '本章说先给卡片下半截留位');
assert.match(paginator, /if \(wrapChapter\) page\.chapterEndWrapTop = y \+ gap;/);
console.log('PASS: wiring');
