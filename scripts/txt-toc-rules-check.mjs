// 本地 TXT 目录规则：内置规则的标题判定、规则引用的编解码、安卓阅读规则的导入。
// 用法：node --experimental-strip-types scripts/txt-toc-rules-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { projectRoot, readEtsModule } from './lib/ets-module-staging.mjs';

const compatPath = path.join(projectRoot, 'harmony-book-source-engine', 'sourceengine', 'src', 'main', 'ets',
  'core', 'rule', 'JavaRegexCompat.ts');
const stageDir = fs.mkdtempSync(path.join(os.tmpdir(), 'txt-toc-rules-'));
const source = readEtsModule('core/book/TxtTocRules.ets')
  .replace("import { JavaRegexCompat } from '@legado/sourceengine';",
    `import { JavaRegexCompat } from '${pathToFileURL(compatPath).href}';`);
const stagedPath = path.join(stageDir, 'TxtTocRules.ts');
fs.writeFileSync(stagedPath, source);
const { TxtChapterMatcher, TxtTocResolvedRule, TxtTocRules } = await import(pathToFileURL(stagedPath).href);

function matcherFor(id, words = 10000) {
  const rule = TxtTocRules.builtins().find((item) => item.id === id);
  assert.ok(rule, `缺少内置规则 ${id}`);
  const resolved = new TxtTocResolvedRule();
  resolved.rule = rule;
  resolved.wordsPerChapter = words;
  return new TxtChapterMatcher(resolved);
}

function isTitle(matcher, rawLine) {
  const candidate = rawLine.replace(/[\u200B-\u200D\u2060\uFEFF]/g, '').trim();
  return matcher.isTitle(rawLine, candidate);
}

function expectTitles(id, titles, bodies) {
  const matcher = matcherFor(id);
  for (const line of titles) assert.equal(isTitle(matcher, line), true, `${id} 应认作标题：${line}`);
  for (const line of bodies) assert.equal(isTitle(matcher, line), false, `${id} 不应认作标题：${line}`);
}

const BODY = '\u3000\u3000雨是从傍晚开始下的。阿栖把最后一封信塞进邮袋。';

expectTitles('auto', ['第一章 旧城来信', '序章', '第12回', 'Chapter 3', '===潮汐表==='], [BODY, '……', '']);
// 智能识别会把正文列表认成标题，这正是要提供其他规则的原因。
assert.equal(isTitle(matcherFor('auto'), '1、不要相信邮差。'), true);

expectTitles('strict',
  ['第一章 旧城来信', '序章 雨夜', '楔子', '尾声', '第十二回：归航', '第3卷 风起', '第二节 早晨'],
  ['1、不要相信邮差。', BODY, '第一次见面时他就说过', '第三节课上老师点了他的名', '第一集合点在码头', '第二部分是附录']);

expectTitles('number', ['12. 潮汐表', '001 标题', '3、不要回答'], ['3.5亿人看过', '2024年冬天', BODY, '12']);

expectTitles('english', ['Chapter 12 The Tide', 'Part II', 'CHAPTER ONE'.replace('ONE', '1'), 'Prologue'],
  ['Part of the reason was the rain.', 'Book lovers know this.', BODY]);

expectTitles('symbol', ['【潮汐表】', '===潮汐表===', '☆潮汐表☆', '〖第一卷〗'], ['【注】这里补充说明', BODY, '======']);

expectTitles('unindented', ['潮汐表', '第一章 旧城来信'],
  [BODY, '\u3000潮汐表', '    潮汐表', '他说：', '你好。', '这是一句不缩进但是特别特别长超过二十个字的普通正文内容']);

const words = matcherFor('words', 5000);
assert.equal(words.isWordSplit(), true);
assert.equal(words.wordsPerChapter, 5000);
assert.equal(isTitle(words, '第一章 旧城来信'), false);

// 自定义规则按 Java 正则转换（安卓阅读的写法）。
const custom = TxtTocRules.newCustomRule();
custom.pattern = '^[ \u3000\\t]{0,4}第.{1,4}卷\\s*.{0,10}\\s*第.{1,8}章.{0,30}$';
const customResolved = new TxtTocResolvedRule();
customResolved.rule = custom;
const customMatcher = new TxtChapterMatcher(customResolved);
assert.equal(isTitle(customMatcher, '第一卷 风起 第三章 灯塔'), true);
assert.equal(isTitle(customMatcher, '第三章 潮汐表'), false);
assert.equal(TxtTocRules.patternError(custom.pattern), '');
assert.notEqual(TxtTocRules.patternError('^第(.{1,4}章'), '');
assert.notEqual(TxtTocRules.patternError(''), '');

// 标题最长字数。
custom.pattern = '^第.+章.*$';
custom.maxTitleLength = 8;
const shortMatcher = new TxtChapterMatcher(customResolved);
assert.equal(isTitle(shortMatcher, '第一章 灯塔'), true);
assert.equal(isTitle(shortMatcher, '第一章 灯塔守夜人的第二封信'), false);

// 规则引用：智能识别存空串，按字数分章带字数。
assert.equal(TxtTocRules.ref('auto'), '');
assert.equal(TxtTocRules.ref('strict'), 'strict');
assert.equal(TxtTocRules.ref('words', 5000), 'words:5000');
assert.equal(TxtTocRules.ruleIdOf(''), 'auto');
assert.equal(TxtTocRules.ruleIdOf('words:20000'), 'words');
assert.equal(TxtTocRules.wordsOf('words:20000'), 20000);
assert.equal(TxtTocRules.wordsOf('words:abc'), TxtTocRules.DEFAULT_WORDS_PER_CHAPTER);
assert.equal(TxtTocRules.wordsOf('words:99999999'), 30000);
assert.equal(TxtTocRules.wordsLabel(5000), '5 千字');
assert.equal(TxtTocRules.wordsLabel(10000), '1 万字');

// 安卓阅读 txtTocRule.json 的条目。
const imported = TxtTocRules.fromImport({ id: -3, enable: false, name: '目录(古典)', rule: '^第.{1,8}回.*$',
  example: '第一回 灵根育孕源流出', serialNumber: 3 });
assert.equal(imported.name, '目录(古典)');
assert.equal(imported.pattern, '^第.{1,8}回.*$');
assert.equal(imported.enabled, false);
assert.equal(imported.builtin, false);
assert.ok(imported.id.startsWith(TxtTocRules.CUSTOM_PREFIX));
assert.equal(TxtTocRules.fromImport({ name: '空的' }), null);
const exported = TxtTocRules.toExport(imported, 1);
assert.equal(exported.rule, imported.pattern);
assert.equal(exported.enable, false);
const roundTrip = TxtTocRules.fromImport(exported);
assert.equal(roundTrip.pattern, imported.pattern);
assert.equal(roundTrip.maxTitleLength, imported.maxTitleLength);

fs.rmSync(stageDir, { recursive: true, force: true });
console.log('txt-toc-rules-check: ok');
