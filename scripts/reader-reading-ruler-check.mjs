// 阅读尺：设置取值、行的整理、尺怎么移动（含双页两栏）、尺边落在行缝里。
// 运行：node --experimental-strip-types scripts/reader-reading-ruler-check.mjs
import assert from 'node:assert/strict';
import { loadReaderModules } from './lib/load-reader-modules.mjs';

const modules = await loadReaderModules();
const { ReaderReadingRulerSteps: S, ReaderRulerRow: Row } = modules;

/** 每栏 counts[i] 行，行高 24、行距 30。 */
function page(...counts) {
  const rows = [];
  counts.forEach((count, column) => {
    for (let i = 0; i < count; i++) rows.push(new Row(i * 30, i * 30 + 24, column));
  });
  return rows;
}
const step = (result) => (result.turn ? 'turn' : result.index);

try {
  // 设置取值
  assert.equal(S.normalizeStyle('band'), 'band');
  assert.equal(S.normalizeStyle('other'), 'mask');
  assert.equal(S.normalizeLines(0), 1);
  assert.equal(S.normalizeLines(5), 3);
  assert.equal(S.normalizeLines(Number.NaN), 2);
  assert.equal(S.normalizeStrength(10), 30);
  assert.equal(S.normalizeStrength(100), 95);

  // 单页：往下按行数走，走完本页才翻页；往上到页首再翻。
  const single = page(7);
  assert.equal(step(S.next(single, 0, 2)), 2);
  assert.equal(step(S.next(single, 4, 2)), 6);
  assert.equal(step(S.next(single, 6, 2)), 'turn');
  assert.equal(step(S.previous(single, 4, 2)), 2);
  assert.equal(step(S.previous(single, 1, 2)), 0);
  assert.equal(step(S.previous(single, 0, 2)), 'turn');
  assert.equal(S.lastIndex(single, 2), 5);
  assert.deepEqual(S.span(single, 6, 2), [6, 6]);
  assert.equal(step(S.next([], 0, 2)), 'turn');

  // 双页：先走完左栏再到右栏第一行；往回从右栏首行退到左栏最后几行。
  const spread = page(5, 3);
  assert.deepEqual(S.span(spread, 4, 2), [4, 4]);
  assert.equal(step(S.next(spread, 4, 2)), 5);
  assert.equal(step(S.next(spread, 6, 2)), 'turn');
  assert.equal(step(S.previous(spread, 5, 2)), 3);
  assert.equal(S.lastIndex(spread, 2), 6);
  assert.equal(S.lastIndex(page(5, 1), 2), 5);

  // 整理：按栏、按上边排序；上下重叠过半的并成一行（首字绕排的两截）。
  const merged = S.mergeRows([new Row(30, 54, 0), new Row(0, 24, 0), new Row(2, 22, 0), new Row(0, 24, 1),
    new Row(60, 60, 0)]);
  assert.deepEqual(merged.map((row) => [row.top, row.bottom, row.column]), [[0, 24, 0], [30, 54, 0], [0, 24, 1]]);

  // 尺边：向相邻行各让出一半行距，栏首栏尾外侧让出 0.15 行高。
  assert.deepEqual(S.bandEdges(single, [1, 2]), [27, 87]);
  assert.deepEqual(S.bandEdges(single, [0, 0]).map((value) => Math.round(value * 10) / 10), [-3.6, 27]);
  assert.deepEqual(S.bandEdges(spread, [3, 4]).map((value) => Math.round(value * 10) / 10), [87, 147.6]);

  // 拖把手：取离手指最近的一行，只在当前栏里找。
  assert.equal(S.rowAt(single, 70, -1), 2);
  assert.equal(S.rowAt(single, 500, -1), 6);
  assert.equal(S.rowAt(spread, 10, 1), 5);

  console.log('reader-reading-ruler-check: ok');
} finally {
  modules.cleanup();
}
