#!/usr/bin/env node
// 浏览器看书下发正文前拆出书源操作标记的回归检查：正文不能残留内部标记，
// 操作的插入位置要落在原段落末尾，浏览器打不开的操作只删不列。
// Usage: node --experimental-strip-types scripts/lan-reader-actions-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { LanReaderActions, ReaderActionMarker: M, cleanup } = await loadReaderModules();

let failures = 0;
function equal(actual, expected, label) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) return;
  failures++;
  console.error(`FAIL ${label}\n  expected ${e}\n  actual   ${a}`);
}

try {
  const para = M.create('128', 'https://example.org/c?p=1', '段评');
  const hot = M.create('99+', 'https://example.org/c?p=2', '段评', '写得好', '1.2k');
  const chapter = M.create('本章说', 'https://example.org/c', '本章说');
  const script = M.createSourceScript('段评', 'java.showBrowser("x")', '段评');
  const provider = M.createProviderComment('fq', '12', 'b', 'c', 'p');

  equal(LanReaderActions.split('第一段。\n第二段。'), { text: '第一段。\n第二段。', actions: [] }, '没有标记时原样返回');

  const inline = LanReaderActions.split(`第一段。${para}\n第二段。${hot}\n第三段。`);
  equal(inline.text, '第一段。\n第二段。\n第三段。', '段尾标记去掉后正文不变');
  equal(inline.actions.map((a) => [a.pos, a.block, a.label]), [[4, false, '128'], [9, false, '99+']], '段尾标记的位置在段落末尾');
  equal([inline.actions[1].preview, inline.actions[1].likes], ['写得好', '1.2k'], '热评原文与点赞数保留');
  equal(inline.actions[0].url, 'https://example.org/c?p=1', '地址原样保留');

  const block = LanReaderActions.split(`第一段。${para}\n末段。\n\n${chapter}\n`);
  equal(block.text, '第一段。\n末段。', '独占一行的标记整行去掉');
  equal(block.actions.map((a) => [a.pos, a.block, a.label]), [[4, false, '128'], [8, true, '本章说']], '独占一行的标记标成按钮行');

  const middle = LanReaderActions.split(`第一段。\n  ${chapter}  \n第二段。`);
  equal(middle.text, '第一段。\n第二段。', '正文中间独占一行的标记不留空行');
  equal(middle.actions.map((a) => [a.pos, a.block]), [[5, true]], '中间的按钮行位置在下一段之前');

  const hidden = LanReaderActions.split(`第一段。${script}\n第二段。${provider}\n${script}\n第三段。${para}`);
  equal(hidden.text, '第一段。\n第二段。\n第三段。', '浏览器打不开的标记也从正文里去掉');
  equal(hidden.actions.map((a) => [a.pos, a.label]), [[14, '128']], '浏览器打不开的操作不下发');

  const damaged = LanReaderActions.split('第一段。[[LEGADO_READER_ACTION_V3:%7Bbroken\n第二段。');
  equal(damaged, { text: '第一段。\n第二段。', actions: [] }, '损坏的标记不露出原文');

  equal(M.has(LanReaderActions.split(`${para}${hot}${chapter}${script}${provider}`).text), false, '结果里不残留任何标记');
} finally {
  cleanup();
}

if (failures > 0) {
  console.error(`\n${failures} 项检查未通过`);
  process.exit(1);
}
console.log('lan-reader-actions-check: 全部通过');
