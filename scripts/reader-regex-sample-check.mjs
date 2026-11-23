// 正则规则预览的命中样例：拼出的文字放进某种放法后，必须真能被规则命中；拼不出时返回空串。
import { ReaderRegexSample } from '../entry/src/main/ets/core/reader/ReaderRegexSample.ts';

let assertions = 0;

function assert(condition, message) {
  assertions++;
  if (!condition) throw new Error(message);
}

/** 和预览一样：逐种放法、每行加段首全角缩进后用 g 正则核对，返回第一个命中的放法序号。 */
function matchedPlacement(pattern, sample) {
  const regex = new RegExp(pattern, 'g');
  const bodies = ReaderRegexSample.placements(sample);
  for (let i = 0; i < bodies.length; i++) {
    const text = `第三章 重逢\n${bodies[i].split('\n').map((line) => `　　${line}`).join('\n')}`;
    regex.lastIndex = 0;
    let match = regex.exec(text);
    while (match) {
      if (match[0].length > 0 && match.index > '第三章 重逢'.length) return i;
      if (match[0].length === 0) regex.lastIndex++;
      match = regex.exec(text);
    }
  }
  return -1;
}

const cases = [
  // [正则, 期望的样例（null 表示只要求能命中）, 期望的放法序号（null 表示不限）]
  ['(?<=(?:^|\\n)[ \\t\\u3000]*)第[0-9０-９零〇一二两三四五六七八九十百千万]+[章节回卷集部篇](?:[ \\t\\u3000]+[^\\n]{0,30})?(?=\\r?\\n|$)',
    '第一章 重逢', 1],
  ['“[^”\\n]*”|「[^」\\n]*」|『[^』\\n]*』|"[^"\\n]*"', '“重逢”', 0],
  ['【[^】]{1,20}】', '【重逢】', 0],
  ['\\d{4}年\\d{1,2}月', '1234年1月', 0],
  ['关键词', '关键词', 0],
  ['[\\u4e00-\\u9fa5]{2,4}之力', '重逢之力', 0],
  ['(ab|cd)\\1', 'abab', 0],
  ['(?<word>好)\\k<word>', '好好', 0],
  ['\\bhello\\b', 'hello', null],
  ['^ps[:：].*$', null, null],
  ['[^\\s]+', null, 0],
  ['.{3}', '重逢故', 0],
  ['a{2,}', 'aa', 0],
  ['\\(注\\)', '(注)', 0],
  ['[a-z]+@[a-z]+\\.com', 'a@a.com', 0],
  ['\\x41\\u3001', 'A、', 0],
];

for (const [pattern, expected, placement] of cases) {
  const sample = ReaderRegexSample.generate(pattern);
  if (expected !== null) assert(sample === expected, `样例不对：${pattern} → ${JSON.stringify(sample)}，期望 ${expected}`);
  if (sample) {
    const index = matchedPlacement(pattern, sample);
    if (placement !== null) {
      assert(index === placement, `放法不对：${pattern} → ${index}，期望 ${placement}`);
    }
  }
}

// ^ 在 g 正则（不带 m）里只认整段开头，预览正文里命中不了：交给“未命中”兜底即可，但样例本身要拼得出。
assert(ReaderRegexSample.generate('^ps[:：].*$') === 'ps:重逢', '^…$ 也要拼出样例');
assert(matchedPlacement('^ps[:：].*$', 'ps:重逢') === -1, '^ 在正文中段不该命中');

// 拼不出的情况返回空串，不抛异常。
for (const bad of ['', '   ', '(abc', 'a)', '*a', '\\', 'a{100}', '(?=x)', '^$', '\\b']) {
  assert(ReaderRegexSample.generate(bad) === '', `应当拼不出：${JSON.stringify(bad)}`);
}

// 放法都是多行正文，且都含样例本身。
for (const body of ReaderRegexSample.placements('样')) {
  assert(body.includes('样') && body.includes('\n'), '放法要含样例并分行');
}

console.log(`reader-regex-sample-check passed (${assertions} assertions)`);
