// 标点挤压：成对判定、按字形空白算收进量，以及分页器把负字距只加在前一个标点上。
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import [\s\S]*?;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

// 模拟一款大陆习惯的字体：句读与闭合标点字面在左半边，开启标点在右半边，引号“”是窄字形。
const SPACES = {
  '。': { left: 0.1, right: 0.6, advance: 1 },
  '，': { left: 0.1, right: 0.6, advance: 1 },
  '：': { left: 0.15, right: 0.55, advance: 1 },
  '」': { left: 0.1, right: 0.55, advance: 1 },
  '「': { left: 0.55, right: 0.1, advance: 1 },
  '）': { left: 0.1, right: 0.6, advance: 1 },
  '！': { left: 0.2, right: 0.5, advance: 1 },
  '？': { left: 0.15, right: 0.5, advance: 1 },
  '“': { left: 0.02, right: 0.05, advance: 0.3 },
  '”': { left: 0.05, right: 0.02, advance: 0.3 }
};
const measured = [];
const context = vm.createContext({
  graphicsText: { FontWeight: Object.fromEntries(Array.from({ length: 9 }, (_, i) => [`W${(i + 1) * 100}`, i])) },
  ReaderCommentBubbleStyle: class { identity() { return 'bubble'; } },
  ReaderPunctuationMetrics: {
    spaceOf(style, char) {
      measured.push(char);
      return SPACES[char] ?? null;
    }
  }
});
vm.runInContext([
  'core/reader/ReaderCommentBubbleSize.ts', 'core/reader/ReaderFontWeight.ts', 'core/reader/ReaderPunctuationSqueeze.ts',
  'core/reader/ReaderV2LayoutSnapshot.ets', 'core/reader/ReaderV2PageLayout.ets', 'core/reader/ReaderV2Style.ets',
  'core/reader/ReaderV2Paginator.ets'
].map(file => compile(read(file))).join('\n') + `
  globalThis.api = { ReaderPunctuationSqueeze, ReaderV2LayoutInput, ReaderV2LayoutSnapshot, ReaderV2Paginator,
    ReaderV2SpanStyleRange };
`, context);
const { ReaderPunctuationSqueeze: Squeeze, ReaderV2LayoutInput: Input, ReaderV2LayoutSnapshot: Snapshot,
  ReaderV2Paginator: Paginator, ReaderV2SpanStyleRange: Range } = context.api;

// 成对判定
assert.equal(Squeeze.ownsPair('好。」', 1), true);
assert.equal(Squeeze.ownsPair('说：「', 1), true);
assert.equal(Squeeze.ownsPair('好。他', 1), false, '后面不是标点');
assert.equal(Squeeze.ownsPair('什么？！', 2), false, '问号叹号连用保持原样');
assert.equal(Squeeze.ownsPair('好！」', 1), true, '叹号后接闭合引号照常收');
assert.equal(Squeeze.ownsPair('好……」', 1), false, '省略号不参与');
assert.equal(Squeeze.ownsPair('。', 0), false, '末尾没有下一个字');
assert.deepEqual(Array.from(Squeeze.pairOwners('他说：「好。」然后。', 0, 10)), [2, 5]);
assert.deepEqual(Array.from(Squeeze.pairOwners('他说：「好。」', 0, 3)), [], '一对标点要都在范围内');
assert.deepEqual(Array.from(Squeeze.pairOwners('没有成对标点。', 0, 7)), []);
console.log('PASS: punctuation pair detection');

// 收进量
const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-9, `${actual} != ${expected}`);
near(Squeeze.squeezeEm(SPACES['。'], SPACES['」']), 0.5);
near(Squeeze.squeezeEm(SPACES['」'], SPACES['「']), 0.5);
near(Squeeze.squeezeEm(SPACES['！'], SPACES['」']), 0.4, '至少留 0.2 个字的空白');
near(Squeeze.squeezeEm({ left: 0.3, right: 0.3, advance: 1 }, { left: 0.3, right: 0.3, advance: 1 }), 0.3,
  '居中字形只收到各留一点空白');
near(Squeeze.squeezeEm({ left: 0.1, right: 0.25, advance: 1 }, SPACES['「']), 0.25,
  '不超过前一个字形右侧的空白，落在行尾时字面不出版心');
assert.equal(Squeeze.squeezeEm({ left: 0.35, right: 0.2, advance: 1 }, { left: 0.1, right: 0.4, advance: 1 }), 0,
  '能收的太少就不收');
assert.equal(Squeeze.squeezeEm(SPACES['“'], SPACES['「']), 0, '窄字形引号不收');
assert.equal(Squeeze.squeezeEm(null, SPACES['「']), 0, '量不到字形时不收');
console.log('PASS: squeeze amount follows glyph whitespace');

// 分页器：前一个标点单独成段并带负字距，其余字不变
const input = new Input();
input.viewportWidthPx = 800;
input.viewportHeightPx = 1200;
const snapshot = Snapshot.create(input);
const text = '他说：「好。」然后';
const block = { title: false, headingLevel: 0, text, displayStart: 0, id: 'b0' };
const document = { actions: [] };
const boundaries = Array.from(Paginator.styleBoundaries(document, block, [], 0, text.length, false));
for (const owner of [2, 5]) {
  assert.ok(boundaries.includes(owner) && boundaries.includes(owner + 1), `第 ${owner} 个字单独成段`);
}
const base = snapshot.letterSpacingPx;
const font = Paginator.baseTextStyle(block, snapshot).fontSize;
measured.length = 0;
near(Paginator.styleAt(document, block, 2, snapshot, []).letterSpacing, base - 0.5 * font);
assert.deepEqual(measured, ['：', '「'], '按这一对字的字形量');
near(Paginator.styleAt(document, block, 5, snapshot, []).letterSpacing, base - 0.5 * font);
for (const offset of [0, 1, 3, 4, 6, 7]) {
  assert.equal(Paginator.styleAt(document, block, offset, snapshot, []).letterSpacing, base, `第 ${offset} 个字不收`);
}
// 正则规则改了字号时按改后的字号收
const bigger = new Range(5, 7);
bigger.fontSizePx = 60;
near(Paginator.styleAt(document, block, 5, snapshot, [bigger]).letterSpacing, base - 0.5 * 60);
// 装饰框紧接在后面时，预留的空白不被吃掉
const untouched = { fontSize: font, letterSpacing: base + 12 };
assert.equal(Paginator.squeezePunctuation(block, 2, 12, untouched).letterSpacing, base + 12);
console.log('PASS: paginator applies the squeeze only to the first punctuation of a pair');

assert.ok(read('core/reader/ReaderV2LayoutSnapshot.ets').includes('psqueeze1'), '排版标识要随挤压规则换版本');
console.log('PASS: layout identity version');
