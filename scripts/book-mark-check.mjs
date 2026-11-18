// 书籍标记的纯逻辑回归：评分/分类/短评规整、星星填充、空标记判定、普通对象读回、分类汇总与作品键。
// 页面与数据库读写需要真机验证。
import assert from 'node:assert/strict';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

const context = vm.createContext({
  BookTypeSupport: { mediaCategoryOf: book => book.category || 'novel' },
  Book: class {},
  SearchBook: class {},
  EncodedSourceUrl: { decode: value => value }
});
vm.runInContext(compile(readEtsModule('model/book/BookMark.ts')) + '\n' +
  compile(readEtsModule('utils/BookIdentity.ts')) +
  '\nglobalThis.api = { BookMark, BookMarkRules, BookMarkStatus, BookMarkTags, BookIdentity };', context);
const { BookMark, BookMarkRules, BookMarkStatus, BookMarkTags, BookIdentity } = context.api;

test('rating is clamped to 0–10 half-star steps', () => {
  assert.equal(BookMarkRules.normalizeRating(-3), 0);
  assert.equal(BookMarkRules.normalizeRating(11), 10);
  assert.equal(BookMarkRules.normalizeRating('7'), 7);
  assert.equal(BookMarkRules.normalizeRating(6.6), 7);
  assert.equal(BookMarkRules.normalizeRating(undefined), 0);
  assert.equal(BookMarkRules.ratingText(9), '4.5');
});

test('star fill gives full, half and empty stars', () => {
  assert.deepEqual([0, 1, 2, 3, 4].map(i => BookMarkRules.starFill(7, i)), [1, 1, 1, 0.5, 0]);
  assert.deepEqual([0, 1, 2, 3, 4].map(i => BookMarkRules.starFill(10, i)), [1, 1, 1, 1, 1]);
  assert.deepEqual([0, 1, 2, 3, 4].map(i => BookMarkRules.starFill(1, i)), [0.5, 0, 0, 0, 0]);
  assert.deepEqual([0, 1, 2, 3, 4].map(i => BookMarkRules.starFill(0, i)), [0, 0, 0, 0, 0]);
});

test('rating labels follow the five bands', () => {
  assert.deepEqual([0, 1, 2, 3, 5, 7, 8, 9, 10].map(v => BookMarkRules.ratingLabel(v)),
    ['', '很差', '很差', '较差', '还行', '推荐', '推荐', '力荐', '力荐']);
});

test('journal sections: star bands put half stars in the lower band, months drop the current year', () => {
  assert.deepEqual([0, 1, 2, 3, 8, 9, 10].map(v => BookMarkRules.ratingBand(v)),
    ['未打分', '半星', '1 星', '1 星', '4 星', '4 星', '5 星']);
  const now = new Date(2026, 10, 17).getTime();
  assert.equal(BookMarkRules.monthLabel(new Date(2026, 10, 2).getTime(), now), '11月');
  assert.equal(BookMarkRules.monthLabel(new Date(2025, 11, 20).getTime(), now), '2025年12月');
});

test('tags are cleaned, deduplicated, length- and count-limited', () => {
  const many = Array.from({ length: 14 }, (_, i) => `标签${i}`);
  assert.equal(BookMarkRules.normalizeCategories(many).length, 10);
  assert.deepEqual([...BookMarkRules.normalizeCategories(['  科幻 ', '科幻', '', null, '一二三四五六七八九十一二三四五六七八'])],
    ['科幻', '一二三四五六七八九十一二三四五六']);
  // 书架按这些字符拆分 customTag，写进书架前去掉，免得一个标签被拆成几个；开头的“!”是书架的隐藏标记。
  assert.equal(BookMarkRules.normalizeCategory('通勤 读'), '通勤读');
  assert.equal(BookMarkRules.normalizeCategory('科幻/悬疑、推理'), '科幻悬疑推理');
  assert.equal(BookMarkRules.normalizeCategory('!!隐藏'), '隐藏');
  assert.deepEqual([...BookMarkRules.normalizeCategories('科幻')], []);
  assert.deepEqual([...BookMarkRules.parseCategories('["a","a","b"]')], ['a', 'b']);
  assert.deepEqual([...BookMarkRules.parseCategories('not json')], []);
});

test('review is trimmed and capped at 500 characters', () => {
  assert.equal(BookMarkRules.normalizeReview('  好看  '), '好看');
  assert.equal(BookMarkRules.normalizeReview('字'.repeat(600)).length, 500);
});

test('a mark with nothing filled in counts as empty', () => {
  const mark = new BookMark();
  assert.equal(BookMarkRules.isEmpty(mark), true);
  mark.review = '   ';
  assert.equal(BookMarkRules.isEmpty(mark), true);
  mark.status = BookMarkStatus.WANT;
  assert.equal(BookMarkRules.isEmpty(mark), false);
});

test('plain objects from backup or sync are normalised', () => {
  assert.equal(BookMarkRules.fromPlain(null), null);
  assert.equal(BookMarkRules.fromPlain({ workKey: '', bookName: '书' }), null);
  assert.equal(BookMarkRules.fromPlain({ workKey: 'k', bookName: '  ' }), null);
  const mark = BookMarkRules.fromPlain({ workKey: 'k', bookName: '书', rating: 30, status: 9, categories: ['a', 'a'],
    review: ' 评 ', createTime: 50, updateTime: 10, finishTime: 99 });
  assert.equal(mark.rating, 10);
  assert.equal(mark.status, BookMarkStatus.NONE);
  assert.deepEqual([...mark.categories], ['a']);
  assert.equal(mark.review, '评');
  assert.equal(mark.updateTime, 50, 'update time never earlier than create time');
  assert.equal(mark.finishTime, 0, 'finish time only kept for 读过');
  const read = BookMarkRules.fromPlain({ workKey: 'k', bookName: '书', status: 3, finishTime: 99 });
  assert.equal(read.finishTime, 99);
  assert.equal(BookMarkStatus.label(read.status), '读过');
  const dropped = BookMarkRules.fromPlain({ workKey: 'k', bookName: '书', status: 4, finishTime: 99 });
  assert.equal(dropped.status, BookMarkStatus.DROPPED);
  assert.equal(BookMarkStatus.label(dropped.status), '弃读');
  assert.equal(dropped.finishTime, 0, 'dropped books keep no finish time');
});

test('average rating follows the status filter and leaves dropped books out of all', () => {
  const make = (status, rating) => Object.assign(new BookMark(), { status, rating });
  const marks = [make(BookMarkStatus.READ, 10), make(BookMarkStatus.READ, 8), make(BookMarkStatus.WANT, 0),
    make(BookMarkStatus.DROPPED, 2), make(BookMarkStatus.NONE, 6)];
  assert.equal(BookMarkRules.averageRatingText(marks, 0), '4.0');
  assert.equal(BookMarkRules.averageRatingText(marks, BookMarkStatus.READ), '4.5');
  assert.equal(BookMarkRules.averageRatingText(marks, BookMarkStatus.DROPPED), '1.0');
  assert.equal(BookMarkRules.averageRatingText(marks, BookMarkStatus.WANT), '');
  assert.equal(BookMarkRules.averageRatingText([make(BookMarkStatus.DROPPED, 4)], 0), '');
});

test('known categories are ordered by use, then by name', () => {
  const make = categories => Object.assign(new BookMark(), { categories });
  assert.deepEqual([...BookMarkRules.collectCategories([make(['b', 'a']), make(['a']), make(['c'])])], ['a', 'b', 'c']);
});

test('mark key keeps local books and missing authors, ignores device paths', () => {
  const book = (name, author, origin, bookUrl, category) => ({ name, author, origin, bookUrl, category });
  const online = BookIdentity.markKeyOf(book('《三体》', '刘慈欣 著', 'https://a.test', 'https://a.test/1'));
  const otherSource = BookIdentity.markKeyOf(book('三体', '刘慈欣', 'https://b.test', 'https://b.test/9'));
  assert.equal(online, otherSource, 'same work across sources');
  assert.notEqual(BookIdentity.markKeyOf(book('三体', '刘慈欣', '', '', 'audio')), online, 'media category separates works');
  const local = BookIdentity.markKeyOf(book('本地书', '', 'local', 'file:///data/storage/1.txt'));
  assert.equal(local, BookIdentity.markKeyOf(book('本地书', '未知', 'local', 'file:///other/device.txt')));
  assert.ok(local, 'local books without author still get a key');
  assert.equal(BookIdentity.markKeyOf(book('  ', '作者', 'x', 'y')), '');
  assert.equal(BookIdentity.workKeyOf(book('本地书', '', 'local', 'file:///1.txt')), '', 'workKeyOf unchanged');
});

test('mark tags replace shelf custom tags but keep hidden source tags', () => {
  assert.deepEqual([...BookMarkTags.customOf(['a', '!玄幻', 'b'])], ['a', 'b']);
  assert.deepEqual([...BookMarkTags.composeShelfTokens(['旧', '!玄幻', '!连载'], ['新', '连载'])], ['新', '连载', '!玄幻'],
    'adding a hidden source tag back unhides it');
  assert.deepEqual([...BookMarkTags.composeShelfTokens(['旧', '!玄幻'], [])], ['!玄幻']);
});

test('shelf edits flow back into the mark, keeping source-named tags still shown', () => {
  // 标记里有“玄幻”（和书源标签同名，书架保存时不写进 customTag）和“通勤读”；书架上删了“通勤读”、加了“重读”。
  assert.deepEqual([...BookMarkTags.fromShelf(['玄幻', '通勤读'], ['重读'], ['玄幻', '连载'])], ['玄幻', '重读']);
  // 书架上把书源标签“玄幻”也隐藏了：标记里的“玄幻”跟着去掉。
  assert.deepEqual([...BookMarkTags.fromShelf(['玄幻', '通勤读'], ['通勤读'], ['连载'])], ['通勤读']);
  assert.equal(BookMarkTags.same(['a', 'b'], ['a', 'b']), true);
  assert.equal(BookMarkTags.same(['a', 'b'], ['b', 'a']), false);
});
