// 智能对话与强调规则命中判定：引号配对、跨段、写反的引号、短引号，以及对话里叠加人名、规则顺序。
// 运行：node --experimental-strip-types scripts/reader-dialogue-match-check.mjs
import assert from 'node:assert/strict';
import { loadReaderModules } from './lib/load-reader-modules.mjs';

const modules = await loadReaderModules();
const { ReaderDialogueMatcher, ReaderDialogueOptions, ReaderRegexRuleHits, ReaderRuleMatchSpec } = modules;

function options(cross = true, fix = true, skip = false) {
  const value = new ReaderDialogueOptions();
  value.crossParagraph = cross;
  value.fixQuotes = fix;
  value.skipShort = skip;
  return value;
}

/** 命中的文字，便于读断言。 */
function hits(text, opts = options()) {
  return ReaderDialogueMatcher.ranges(text, opts).map(([start, end]) => text.slice(start, end));
}

try {
  // 基本配对：几种引号；「」里的『』、“”里的‘’只是内容。
  assert.deepEqual(hits('他说：“你好。”她点头：「走吧，『快』点。」又道"ok"，＂嗯＂。'),
    ['“你好。”', '「走吧，『快』点。」', '"ok"', '＂嗯＂']);
  assert.deepEqual(hits('“他说‘走’就走了。”'), ['“他说‘走’就走了。”']);

  // 跨段：下一段也以前引号开头时，本段从前引号算到段末（不含段末空白）。
  const cross = '老人说起旧事。\n　　“那年冬天特别冷。 \n　　“我爹说，鱼都睡着了。”';
  assert.deepEqual(hits(cross), ['“那年冬天特别冷。', '“我爹说，鱼都睡着了。”']);
  assert.deepEqual(hits(cross, options(false)), ['“我爹说，鱼都睡着了。”']);
  // 下一段不是引号开头：没收的引号不上色，不把旁白染掉。
  assert.deepEqual(hits('“你好，他说。\n他转身走了。'), []);
  assert.deepEqual(hits('「第一段\n「第二段」'), ['「第一段', '「第二段」']);

  // 写反的引号：“你好“ 当后引号，”快走！” 当前引号。
  assert.deepEqual(hits('“你别过来“林舟喊道，“我数到三。”'), ['“你别过来“', '“我数到三。”']);
  assert.deepEqual(hits('”快走！”阿芜拉起他就跑。'), ['”快走！”']);
  // 书源转换坏了、整段引号都成了同一个方向。
  assert.deepEqual(hits('“走吧“他说。“好的“她答。'), ['“走吧“', '“好的“']);
  assert.deepEqual(hits('”走吧”他说。”好的”她答。'), ['”走吧”', '”好的”']);
  // 真嵌套：后面先来 ”、且 ” 比 “ 多时按一层嵌套。
  // （“你好“他说，”再见” 这种两种写反混在一段里的，和嵌套分不开，按嵌套整句算。）
  assert.deepEqual(hits('“他说“走”就走了。”旁白。'), ['“他说“走”就走了。”']);
  // 关掉纠正：和原来的正则一样，对话里的 “ 只是内容，对话外的 ” 不管。
  assert.deepEqual(hits('“你别过来“林舟喊道，“我数到三。”', options(true, false)), ['“你别过来“林舟喊道，“我数到三。”']);
  assert.deepEqual(hits('”快走！”阿芜拉起他就跑。', options(true, false)), []);
  // 引号外孤零零的 ” 不开对话。
  assert.deepEqual(hits('他看着她”，又看了看。'), []);

  // 短引号不算对话：字少、无句读、不在段首、前面不是冒号或说话的字。
  const skip = options(true, true, true);
  assert.deepEqual(hits('他一招“回风拂柳”使出，江湖人称“小剑仙”。', skip), []);
  assert.deepEqual(hits('他说“走”，转身就跑。', skip), ['“走”']);
  assert.deepEqual(hits('他道：“好”', skip), ['“好”']);
  assert.deepEqual(hits('“嗯”\n他一招“回风拂柳”。', skip), ['“嗯”']);
  assert.deepEqual(hits('他问“你去哪儿”', skip), ['“你去哪儿”']);
  assert.deepEqual(hits('他喊“快跑，别回头”', skip), ['“快跑，别回头”']);
  assert.deepEqual(hits('他一招“回风拂柳”使出。'), ['“回风拂柳”']);

  // 兜底正则（旧版本用）能处理跨段和写反，且是合法正则。
  const fallback = new RegExp(ReaderDialogueMatcher.FALLBACK_PATTERN, 'g');
  assert.deepEqual('“你别过来“林舟喊道，“我数到三。”'.match(fallback), ['“你别过来“', '“我数到三。”']);
  assert.deepEqual('“那年冬天。\n　　“开春了。”'.match(fallback), ['“那年冬天。', '“开春了。”']);
  assert.deepEqual('”快走！”'.match(fallback), ['”快走！”']);
  assert.ok(new RegExp(ReaderDialogueMatcher.LEADING_PATTERN, 'y').test('“你好”'));

  // ---------- 命中判定 ----------
  function spec(pattern, extra = {}) {
    const value = new ReaderRuleMatchSpec();
    value.pattern = pattern;
    Object.assign(value, extra);
    return value;
  }
  const dialogue = spec('', { matcher: 'dialogue', nestOthers: true });
  const names = spec('林舟|阿芜');
  const text = '林舟问：“阿芜，你读过《山海经》吗？”阿芜摇头。';
  const show = (list) => list.map((hit) => `${hit.overlay ? '+' : ''}${hit.ruleIndex}:${text.slice(hit.start, hit.end)}`);

  // 对话在前：对话里的人名成为叠加层，对话外的人名照常。
  assert.deepEqual(show(ReaderRegexRuleHits.collect([dialogue, names], text, [])),
    ['1:林舟', '0:“阿芜，你读过《山海经》吗？”', '+1:阿芜', '1:阿芜']);
  // 人名在前：对话照样认领，把里面的人名改成叠加层（以前整句对话会丢掉）。
  assert.deepEqual(show(ReaderRegexRuleHits.collect([names, dialogue], text, [])),
    ['0:林舟', '1:“阿芜，你读过《山海经》吗？”', '+0:阿芜', '0:阿芜']);
  // 关掉“命中里显示其他规则”：和以前一样，重叠的后来者整段放弃。
  const flat = spec('', { matcher: 'dialogue', nestOthers: false });
  assert.deepEqual(show(ReaderRegexRuleHits.collect([flat, names], text, [])),
    ['1:林舟', '0:“阿芜，你读过《山海经》吗？”', '1:阿芜']);
  assert.deepEqual(show(ReaderRegexRuleHits.collect([names, flat], text, [])), ['0:林舟', '0:阿芜', '0:阿芜']);
  // 跨出对话边界的命中不叠加、也不打断对话。
  const straddle = spec('吗？”阿芜');
  assert.deepEqual(show(ReaderRegexRuleHits.collect([dialogue, straddle], text, [])),
    ['0:“阿芜，你读过《山海经》吗？”']);
  // 叠加层之间互不重叠，先到先得。
  const book = spec('《[^》]+》');
  const bookTitle = spec('山海');
  assert.deepEqual(show(ReaderRegexRuleHits.collect([dialogue, book, bookTitle], text, [])),
    ['0:“阿芜，你读过《山海经》吗？”', '+1:《山海经》']);
  // 作用范围：仅正文的规则碰到标题不算。
  const titled = '第一章 “重逢”\n他说：“你好。”';
  const bodyOnly = spec('', { matcher: 'dialogue', scope: 'body' });
  assert.deepEqual(ReaderRegexRuleHits.collect([bodyOnly], titled, [[0, 9]]).map((hit) => titled.slice(hit.start, hit.end)),
    ['“你好。”']);
  // 正则写错、零长度命中：不报错。
  assert.deepEqual(ReaderRegexRuleHits.collect([spec('(['), spec('(?=他)')], titled, []), []);
  assert.equal(ReaderRegexRuleHits.scopeAccepts('title', 0, 4, [[0, 9]]), true);
  assert.equal(ReaderRegexRuleHits.scopeAccepts('body', 0, 4, [[0, 9]]), false);

  console.log('reader-dialogue-match-check: ok');
} finally {
  modules.cleanup();
}
