// 单本书阅读统计的纯逻辑回归：汇总、按月分组、时间线并段、日历格子与文字格式。
// 卡片与面板需要真机验证。
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';

process.env.TZ = 'Asia/Shanghai';
const source = fs.readFileSync(new URL('../entry/src/main/ets/core/stats/BookReadStats.ts', import.meta.url), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
const context = vm.createContext({});
vm.runInContext(stripTypeScriptTypes(source, { mode: 'strip' }) + '\nglobalThis.BookReadStats = BookReadStats;', context);
const Stats = context.BookReadStats;

const at = (y, m, d, h = 0, minute = 0) => new Date(y, m - 1, d, h, minute).getTime();
const pad = n => (n < 10 ? `0${n}` : `${n}`);
const record = (y, m, d, h, minute, minutes) => ({
  dayKey: `${y}-${pad(m)}-${pad(d)}`, durationMs: minutes * 60000, startedAt: at(y, m, d, h, minute)
});

test('empty input yields an empty summary', () => {
  const stats = Stats.calculate([]);
  assert.equal(stats.activeDays, 0);
  assert.equal(stats.totalMs, 0);
  assert.equal(stats.months.length, 0);
  assert.equal(stats.timeline.length, 0);
});

test('totals, first/last day and best day', () => {
  const stats = Stats.calculate([
    record(2026, 10, 27, 20, 0, 30), record(2026, 10, 27, 22, 0, 28),
    record(2026, 11, 9, 12, 40, 7), record(2026, 11, 9, 22, 5, 26),
    record(2026, 11, 10, 21, 42, 1),
    { dayKey: 'bad', durationMs: 60000, startedAt: 0 }, record(2026, 11, 8, 8, 0, 0)
  ]);
  assert.equal(stats.totalMs, 92 * 60000);
  assert.equal(stats.activeDays, 3);
  assert.equal(stats.firstDayKey, '2026-10-27');
  assert.equal(stats.lastDayKey, '2026-11-10');
  assert.equal(stats.bestDayKey, '2026-10-27');
  assert.equal(stats.bestDayMs, 58 * 60000);
});

test('months are newest first with days newest first', () => {
  const stats = Stats.calculate([record(2026, 10, 27, 20, 0, 30), record(2026, 11, 9, 12, 0, 33),
    record(2026, 11, 10, 21, 0, 1)]);
  assert.deepEqual(Array.from(stats.months, month => month.key), ['2026-11', '2026-10']);
  assert.deepEqual(Array.from(stats.months[0].days, day => day.day), [10, 9]);
  assert.equal(stats.months[0].totalMs, 34 * 60000);
  assert.equal(stats.months[0].maxMs, 33 * 60000);
});

test('records within five minutes merge into one session', () => {
  const stats = Stats.calculate([
    record(2026, 11, 9, 22, 0, 1), record(2026, 11, 9, 22, 1, 1), record(2026, 11, 9, 22, 6, 2),
    record(2026, 11, 9, 23, 0, 5)
  ]);
  const sessions = stats.timeline[0].sessions;
  assert.equal(sessions.length, 2);
  assert.equal(sessions[0].startTs, at(2026, 11, 9, 23, 0));
  assert.equal(sessions[1].startTs, at(2026, 11, 9, 22, 0));
  assert.equal(sessions[1].endTs, at(2026, 11, 9, 22, 8));
  assert.equal(sessions[1].durationMs, 4 * 60000);
  assert.equal(Stats.sessionText(sessions[1]), '22:00 – 22:08 · 4 分钟');
});

test('records without a start time are one untimed entry per day', () => {
  const stats = Stats.calculate([
    { dayKey: '2026-11-01', durationMs: 600000, startedAt: 0 },
    { dayKey: '2026-11-01', durationMs: 300000, startedAt: 0 },
    record(2026, 11, 1, 9, 0, 3)
  ]);
  const sessions = stats.timeline[0].sessions;
  assert.equal(sessions.length, 2);
  assert.equal(sessions[1].startTs, 0);
  assert.equal(Stats.sessionText(sessions[1]), '当天累计 · 15 分钟');
});

test('timeline keeps only the most recent reading days', () => {
  const records = [];
  for (let i = 0; i < Stats.TIMELINE_DAY_LIMIT + 5; i++) {
    const date = new Date(2026, 0, 1 + i);
    records.push(record(date.getFullYear(), date.getMonth() + 1, date.getDate(), 8, 0, 1));
  }
  const stats = Stats.calculate(records);
  assert.equal(stats.timeline.length, Stats.TIMELINE_DAY_LIMIT);
  assert.equal(stats.timelineTruncated, true);
  assert.equal(stats.timeline[0].dayKey, stats.lastDayKey);
  assert.equal(stats.activeDays, Stats.TIMELINE_DAY_LIMIT + 5);
});

test('calendar pads to full weeks starting on Monday and scales levels', () => {
  const stats = Stats.calculate([record(2026, 11, 9, 12, 0, 40), record(2026, 11, 10, 21, 0, 1),
    record(2026, 11, 8, 21, 0, 20)]);
  const cells = Stats.calendar(2026, 11, stats.months[0]);
  // 2026-11-01 是周日，前面补六个空位。
  assert.equal(cells.length, 42);
  assert.equal(cells[5].day, 0);
  assert.equal(cells[6].day, 1);
  const byDay = day => cells.find(cell => cell.day === day);
  assert.equal(byDay(9).level, 4);
  assert.equal(byDay(8).level, 2);
  assert.equal(byDay(10).level, 1);
  assert.equal(byDay(11).level, 0);
  assert.equal(byDay(9).dayKey, '2026-11-09');
  assert.equal(Stats.calendar(2026, 2, null).filter(cell => cell.day > 0).length, 28);
});

test('duration and date formatting', () => {
  assert.deepEqual(Array.from(Stats.durationParts(0)), ['0', '分钟']);
  assert.deepEqual(Array.from(Stats.durationParts(30000)), ['<1', '分钟']);
  assert.deepEqual(Array.from(Stats.durationParts(58 * 60000)), ['58', '分钟']);
  assert.deepEqual(Array.from(Stats.durationParts(377 * 60000)), ['6', '小时', '17', '分钟']);
  assert.deepEqual(Array.from(Stats.durationParts(120 * 60000)), ['2', '小时']);
  assert.equal(Stats.durationText(30000), '不足 1 分钟');
  assert.equal(Stats.durationText(377 * 60000), '6 小时 17 分钟');
  assert.equal(Stats.shortDate('2026-10-27'), '26/10/27');
  assert.equal(Stats.monthDay('2026-10-27'), '10/27');
});
