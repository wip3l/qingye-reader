// 正文人名上色：自动分色（主角优先、手动选的不被占用、不上色）、名字拼正则（去重、去单字、长的在前、转义）。
// 运行：node --experimental-strip-types scripts/reader-name-style-check.mjs
import assert from 'node:assert/strict';
import { loadReaderModules } from './lib/load-reader-modules.mjs';

const modules = await loadReaderModules();
const { ReaderNamePatterns: P, ReaderNameRoleInput: Input } = modules;

function role(id, lead = false, color = undefined) {
  const value = new Input();
  value.id = id;
  value.name = id;
  value.lead = lead;
  value.color = color;
  return value;
}

try {
  // 主角先拿色板前面的颜色，其余按原顺序。
  assert.deepEqual(P.assignColors([role('a'), role('b', true), role('c'), role('d', true)]), [2, 0, 3, 1]);
  // 手动选过的保留，自动分配跳过已被手动占用的颜色；-1 不上色。
  assert.deepEqual(P.assignColors([role('a', false, 0), role('b'), role('c', false, -1), role('d')]), [0, 1, -1, 2]);
  // 超出色板下标的手动值夹到范围内；人多于色板时循环。
  assert.deepEqual(P.assignColors([role('a', false, 99)]), [P.PALETTE.length - 1]);
  const many = Array.from({ length: P.PALETTE.length + 2 }, (_v, i) => role(`r${i}`));
  const colors = P.assignColors(many);
  assert.equal(colors[P.PALETTE.length], 0);
  assert.equal(colors[P.PALETTE.length + 1], 1);
  // 每一对都是白天、夜间两色。
  for (const pair of P.PALETTE) assert.match(pair.join(','), /^#[0-9A-F]{6},#[0-9A-F]{6}$/);

  // 名字：去重、去掉单字、长的在前、正则特殊字符转义。
  assert.equal(P.pattern(['林舟', '舟', '林先生', '林舟', ' ']), '林先生|林舟');
  // 一样长的保持原顺序。
  assert.equal(P.pattern(['A.B', '(甲)']), 'A\\.B|\\(甲\\)');
  assert.equal(P.pattern(['舟']), '');
  const regex = new RegExp(P.pattern(['林舟', '林先生']), 'g');
  assert.deepEqual('林先生说林舟来了'.match(regex), ['林先生', '林舟']);
  assert.equal(P.longestName(['林舟', '林先生']), 3);

  console.log('reader-name-style-check: ok');
} finally {
  modules.cleanup();
}
