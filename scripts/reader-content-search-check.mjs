#!/usr/bin/env node
// 正文查找的匹配、摘录与跳转后找回同一处的回归检查。
// 直接加载 entry 下的纯 TS 模块 ReaderContentSearchMatcher，测到的就是应用实际运行的代码。
// Usage: node --experimental-strip-types scripts/reader-content-search-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { ReaderContentSearchMatcher, cleanup } = await loadReaderModules();

let failures = 0;
const check = (condition, message, detail = '') => {
  if (condition) {
    console.log(`  ok - ${message}`);
  } else {
    failures++;
    console.error(`  FAIL - ${message}${detail ? `\n         ${detail}` : ''}`);
  }
};
const equal = (actual, expected, message) =>
  check(actual === expected, message, `expected ${JSON.stringify(expected)}\n         actual   ${JSON.stringify(actual)}`);

try {
  console.log('匹配');
  {
    const text = '少年握紧长剑。\n\n长剑出鞘，寒光四射。长剑';
    const matches = ReaderContentSearchMatcher.find(text, ' 长剑 ');
    equal(matches.length, 3, '关键字前后空白去掉后逐处命中');
    equal(matches.map((m) => m.ordinal).join(','), '0,1,2', '序号按出现顺序');
    equal(text.substring(matches[1].start, matches[1].end), '长剑', '位置对应原文');
    equal(matches[1].before, '少年握紧长剑。', '摘录前文换行折掉、贴着命中的空白去掉');
    equal(matches[1].after, '出鞘，寒光四射。长剑', '摘录后文');
    equal(ReaderContentSearchMatcher.find(text, '长剑', 2).length, 2, '数量上限');
    equal(ReaderContentSearchMatcher.find(text, '   ').length, 0, '空关键字不查');
  }
  {
    const matches = ReaderContentSearchMatcher.find('Hello hello HELLO', 'hello');
    equal(matches.length, 3, '不区分大小写');
    equal(matches[2].text, 'HELLO', '命中保留原文大小写');
  }
  {
    const matches = ReaderContentSearchMatcher.find('价格(元)是 1.5 * 2，价格(元)', '(元)');
    equal(matches.length, 2, '正则特殊字符按普通文字匹配');
    equal(ReaderContentSearchMatcher.find('a.b axb', 'a.b').length, 1, '点号不当通配');
  }

  console.log('内部标记');
  {
    const marker = '[[LEGADO_EPUB_IMAGE:%2Fdata%2Fbook%2Fbase.png]]';
    const text = `第一段 base 文字\n${marker}\n第二段 base`;
    const matches = ReaderContentSearchMatcher.find(text, 'base');
    equal(matches.length, 2, '标记里的路径不算命中');
    equal(matches[1].ordinal, 1, '跳过标记后序号连续');
    check(!matches[0].after.includes('LEGADO'), '摘录里不出现标记', matches[0].after);
    equal(matches[0].after, '文字 第二段 base', '标记折成空格并入摘录');
  }
  {
    const marker = '[[LEGADO_READER_ACTION_V3:{"title":"段评"}]]';
    const text = `${marker}段评区开头的段评`;
    const matches = ReaderContentSearchMatcher.find(text, '段评');
    equal(matches.length, 2, '段评按钮标记里的标题不算命中');
    equal(matches[0].before, '', '命中紧挨标记时前文为空');
  }
  {
    const longMarker = `[[LEGADO_EPUB_IMAGE:${'x'.repeat(200)}]]`;
    const text = `${longMarker}剑`;
    const matches = ReaderContentSearchMatcher.find(text, '剑');
    equal(matches[0].before, '', '摘录窗口起点落在标记中间时不留下半截标记');
  }

  console.log('跳转后找回同一处');
  {
    const searched = '他说：长剑在此。\n\n她说：长剑不在。\n\n长剑在此。';
    const hits = ReaderContentSearchMatcher.find(searched, '长剑');
    // 排版文本比查找时多了标题行（标题里也有关键字）和段首缩进。
    const paged = '第一章 长剑\n\n　　他说：长剑在此。\n\n　　她说：长剑不在。\n\n　　长剑在此。';
    for (const hit of hits) {
      const located = ReaderContentSearchMatcher.locate(paged, '长剑', hit.ordinal, hit.before, hit.after);
      check(!!located, `第 ${hit.ordinal + 1} 处找得回`);
      if (located) {
        const want = paged.indexOf(`${hit.before.trim().slice(-3)}`) >= 0;
        check(want, `第 ${hit.ordinal + 1} 处上下文存在`);
      }
    }
    const second = ReaderContentSearchMatcher.locate(paged, '长剑', hits[1].ordinal, hits[1].before, hits[1].after);
    equal(paged.substring(second.start - 3, second.end), '她说：长剑', '标题多出一处时仍按上下文落到同一处');
    const third = ReaderContentSearchMatcher.locate(paged, '长剑', hits[2].ordinal, hits[2].before, hits[2].after);
    equal(paged.substring(third.start, third.end + 3), '长剑在此。', '末处按上下文定位');
    check(third.start > second.start, '先后顺序不乱');
  }
  {
    const located = ReaderContentSearchMatcher.locate('完全不同的文字 剑', '剑', 5, '找不到的前文', '找不到');
    equal(located?.start, 8, '上下文都对不上时退回到最后一处');
    equal(ReaderContentSearchMatcher.locate('没有命中', '剑', 0, '', ''), null, '排版文本里没有关键字时返回空');
  }
} finally {
  cleanup();
}

if (failures > 0) {
  console.error(`\n${failures} 项失败`);
  process.exit(1);
}
console.log('\n全部通过');
