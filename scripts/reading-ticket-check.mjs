// 票夹的纯逻辑回归：哪些标记出票、读完编号、按作品归并时长、开始/结束日、月份分组与排序、
// 合计与筛选、票面文字、背面日历，以及足迹页“最近的票”默认不显示。票面绘制、存图和出票动画需要真机验证。
import assert from 'node:assert/strict';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compile = source => stripTypeScriptTypes(source.replace(/^import [\s\S]*?;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

const context = vm.createContext({
  FootprintSettingsStore: { saveLayout: async () => {} }
});
vm.runInContext(compile(readEtsModule('model/book/BookMark.ts')) + '\n' +
  compile(readEtsModule('core/ticket/ReadingTicket.ts')) + '\n' +
  compile(readEtsModule('utils/FootprintLayout.ets')) +
  '\nglobalThis.api = { BookMark, BookMarkStatus, ReadingTicketRules, TicketStatsRow, TicketMedia, FootprintLayout };',
  context);
const { BookMark, BookMarkStatus, ReadingTicketRules, TicketStatsRow, TicketMedia, FootprintLayout } = context.api;

// vm 里造的数组和这里的数组原型不同，比较前转成普通值。
const plain = value => JSON.parse(JSON.stringify(value));
const deepEqual = (actual, expected) => assert.deepEqual(plain(actual), plain(expected));
const notDeepEqual = (actual, expected) => assert.notDeepEqual(plain(actual), plain(expected));

const at = (y, m, d, h = 12) => new Date(y, m - 1, d, h).getTime();

function mark(fields) {
  const item = new BookMark();
  Object.assign(item, { createTime: at(2026, 1, 1), updateTime: at(2026, 1, 1) }, fields);
  return item;
}

function row(bookUrl, name, author, dayKey, minutes) {
  const item = new TicketStatsRow();
  Object.assign(item, { bookUrl, name, author, dayKey, durationMs: minutes * 60000 });
  return item;
}

test('only read, reading and dropped marks get tickets', () => {
  const marks = [
    mark({ workKey: 'a', bookName: 'A', status: BookMarkStatus.READ, finishTime: at(2026, 3, 1) }),
    mark({ workKey: 'b', bookName: 'B', status: BookMarkStatus.WANT }),
    mark({ workKey: 'c', bookName: 'C', status: BookMarkStatus.NONE, rating: 8 }),
    mark({ workKey: 'd', bookName: 'D', status: BookMarkStatus.READING }),
    mark({ workKey: 'e', bookName: 'E', status: BookMarkStatus.DROPPED })
  ];
  const keys = ReadingTicketRules.build(marks, []).map(ticket => ticket.workKey).sort();
  deepEqual(keys, ['a', 'd', 'e']);
});

test('numbers follow finish order; only read tickets carry one', () => {
  const marks = [
    mark({ workKey: 'late', status: BookMarkStatus.READ, finishTime: at(2026, 5, 2) }),
    mark({ workKey: 'early', status: BookMarkStatus.READ, finishTime: at(2026, 2, 2) }),
    mark({ workKey: 'tie-b', status: BookMarkStatus.READ, finishTime: at(2026, 3, 3), createTime: at(2026, 1, 9) }),
    mark({ workKey: 'tie-a', status: BookMarkStatus.READ, finishTime: at(2026, 3, 3), createTime: at(2026, 1, 3) }),
    mark({ workKey: 'reading', status: BookMarkStatus.READING })
  ];
  const numbers = ReadingTicketRules.numbers(marks);
  deepEqual([...numbers.entries()], [['early', 1], ['tie-a', 2], ['tie-b', 3], ['late', 4]]);
  const tickets = ReadingTicketRules.build(marks, []);
  assert.equal(tickets.find(t => t.workKey === 'reading').number, 0);
  assert.equal(ReadingTicketRules.numberText(tickets.find(t => t.workKey === 'late')), 'No.0004');
});

test('stats merge by address and by name+author without counting a day twice', () => {
  const marks = [mark({
    workKey: 'w', bookName: '三体', author: '刘慈欣', bookUrl: 'src1/book', status: BookMarkStatus.READ,
    finishTime: at(2026, 10, 4)
  })];
  const rows = [
    row('src1/book', '三体', '刘慈欣', '2026-09-20', 30),
    row('src1/book', '三体', '刘慈欣', '2026-09-21', 60),
    // 换源后的另一本，同名同作者。
    row('src2/book', '三体', '刘慈欣', '2026-09-21', 30),
    row('src2/book', '三体', '刘慈欣', '2026-10-03', 90),
    // 同名不同作者、无效记录都不算。
    row('src3/book', '三体', '别人', '2026-09-25', 600),
    row('src1/book', '三体', '刘慈欣', 'bad', 600),
    row('src1/book', '三体', '刘慈欣', '2026-09-22', 0)
  ];
  const [ticket] = ReadingTicketRules.build(marks, rows);
  assert.equal(ticket.totalMs, 210 * 60000);
  assert.equal(ticket.activeDays, 3);
  assert.equal(ticket.startDayKey, '2026-09-20');
  assert.equal(ticket.endDayKey, '2026-10-04');
  assert.equal(ticket.monthKey, '2026-10');
});

test('start and end days for each status and missing records', () => {
  const read = ReadingTicketRules.compose(mark({
    workKey: 'r', status: BookMarkStatus.READ, finishTime: at(2026, 4, 1), createTime: at(2026, 3, 1)
  }), new Map([['2026-04-10', 60000]]), 1);
  // 先标读过、之后又读了几分钟：开始日不晚于读完日。
  assert.equal(read.startDayKey, '2026-04-01');
  assert.equal(read.endDayKey, '2026-04-01');

  const reading = ReadingTicketRules.compose(mark({
    workKey: 'g', status: BookMarkStatus.READING, updateTime: at(2026, 6, 9)
  }), new Map([['2026-05-01', 60000], ['2026-05-20', 60000]]), 0);
  assert.equal(reading.endDayKey, '');
  assert.equal(reading.monthKey, '2026-05');

  const dropped = ReadingTicketRules.compose(mark({
    workKey: 'd', status: BookMarkStatus.DROPPED, createTime: at(2026, 7, 3), updateTime: at(2026, 8, 2)
  }), new Map(), 0);
  assert.equal(dropped.startDayKey, '2026-07-03');
  assert.equal(dropped.endDayKey, '2026-08-02');
  assert.equal(dropped.totalMs, 0);
  assert.equal(dropped.monthKey, '2026-08');
});

test('tickets sort by month, newest first within the month', () => {
  const marks = [
    mark({ workKey: 'oct', status: BookMarkStatus.READ, finishTime: at(2026, 10, 30) }),
    mark({ workKey: 'nov-early', status: BookMarkStatus.READ, finishTime: at(2026, 11, 2) }),
    mark({ workKey: 'nov-late', status: BookMarkStatus.READ, finishTime: at(2026, 11, 20) }),
    mark({ workKey: 'nov-reading', status: BookMarkStatus.READING, updateTime: at(2026, 11, 10) })
  ];
  const rows = [row('', '', '', '2026-11-12', 10)];
  deepEqual(ReadingTicketRules.build(marks, rows).map(t => t.workKey),
    ['nov-late', 'nov-reading', 'nov-early', 'oct']);
});

test('summary, years and filters', () => {
  const marks = [
    mark({ workKey: 'a', bookUrl: 'a', status: BookMarkStatus.READ, finishTime: at(2026, 3, 1), rating: 10 }),
    mark({ workKey: 'b', bookUrl: 'b', status: BookMarkStatus.READ, finishTime: at(2025, 12, 1), rating: 7 }),
    mark({ workKey: 'c', bookUrl: 'c', status: BookMarkStatus.DROPPED, updateTime: at(2026, 2, 1) })
  ];
  const tickets = ReadingTicketRules.build(marks, [row('a', '', '', '2026-02-27', 90), row('b', '', '', '2025-11-30', 45)]);
  deepEqual(ReadingTicketRules.summary(tickets), [3, 2, 2.3, 4.25]);
  deepEqual(ReadingTicketRules.years(tickets), [2026, 2025]);
  deepEqual(ReadingTicketRules.filter(tickets, BookMarkStatus.READ, 2026).map(t => t.workKey), ['a']);
  assert.equal(ReadingTicketRules.filter(tickets, 0, 0).length, 3);
});

test('ticket text helpers', () => {
  deepEqual(ReadingTicketRules.durationValue(0), ['—', '']);
  deepEqual(ReadingTicketRules.durationValue(20000), ['1', '分钟']);
  deepEqual(ReadingTicketRules.durationValue(40 * 60000), ['40', '分钟']);
  deepEqual(ReadingTicketRules.durationValue(12.5 * 3600000), ['12.5', '小时']);
  deepEqual(ReadingTicketRules.durationValue(123.4 * 3600000), ['123', '小时']);
  assert.equal(ReadingTicketRules.ratingText(0), '未评分');
  assert.equal(ReadingTicketRules.ratingText(9), '★ 4.5');
  assert.equal(ReadingTicketRules.ratingText(10), '★ 5');
  const base = { startDayKey: '2026-11-03', endDayKey: '2026-11-08' };
  assert.equal(ReadingTicketRules.rangeText(base), '2026.11.03 至 11.08');
  assert.equal(ReadingTicketRules.rangeText({ startDayKey: '2025-12-30', endDayKey: '2026-01-02' }),
    '2025.12.30 至 2026.01.02');
  assert.equal(ReadingTicketRules.rangeText({ startDayKey: '2026-11-03', endDayKey: '' }), '2026.11.03 起');
  assert.equal(ReadingTicketRules.rangeText({ startDayKey: '2026-11-03', endDayKey: '2026-11-03' }), '2026.11.03');
  assert.equal(ReadingTicketRules.stampText(BookMarkStatus.READ), '已读');
  assert.equal(ReadingTicketRules.checkText(BookMarkStatus.DROPPED), '中途离场');
  assert.equal(TicketMedia.durationLabel(32), '总收听时长');
  assert.equal(TicketMedia.durationLabel(64), '总观看时长');
  assert.equal(TicketMedia.durationLabel(8), '总阅读时长');
});

test('back calendar covers 28 days ending on the end day', () => {
  const days = new Map([['2026-11-08', 60 * 60000], ['2026-11-07', 15 * 60000], ['2026-10-12', 60000],
    ['2026-10-11', 600 * 60000]]);
  const levels = ReadingTicketRules.calendarLevels(days, '2026-11-08');
  assert.equal(levels.length, 28);
  assert.equal(levels[27], 4);
  assert.equal(levels[26], 1);
  assert.equal(levels[0], 1); // 10-12 是第一格，10-11 不在范围里，所以最久的一天是 11-08
  assert.equal(levels.filter(level => level > 0).length, 3);
  deepEqual(ReadingTicketRules.calendarLevels(days, ''), new Array(28).fill(0));
});

test('barcode is stable per book', () => {
  const a = ReadingTicketRules.barcode('novel\u0001三体\u0001刘慈欣');
  deepEqual(a, ReadingTicketRules.barcode('novel\u0001三体\u0001刘慈欣'));
  notDeepEqual(a, ReadingTicketRules.barcode('novel\u0001活着\u0001余华'));
  assert.ok(a.every(width => width >= 1 && width <= 3));
});

test('footprint “recent tickets” is hidden by default and for layouts saved before it existed', () => {
  const fresh = FootprintLayout.parse('');
  assert.equal(fresh.isVisible('ticket'), false);
  assert.equal(fresh.isDefault(), true);
  const old = FootprintLayout.parse(JSON.stringify({
    order: ['week', 'month', 'rank', 'excerpt', 'bookmark', 'mark'], hidden: ['rank'], limits: {}
  }));
  assert.equal(old.isVisible('ticket'), false);
  assert.equal(old.isVisible('rank'), false);
  assert.equal(old.order[old.order.length - 1], 'ticket');
  // 用户打开过之后照常显示。
  const shown = FootprintLayout.parse(JSON.stringify({ order: old.order, hidden: [], limits: {} }));
  assert.equal(shown.isVisible('ticket'), true);
  assert.equal(shown.isDefault(), false);
});
