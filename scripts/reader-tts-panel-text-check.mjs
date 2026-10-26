// Run with: node --experimental-strip-types scripts/reader-tts-panel-text-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const readBook = fs.readFileSync(new URL('../entry/src/main/ets/pages/ReadBook.ets', import.meta.url), 'utf8');
function method(source, name) {
  const start = source.indexOf(`  ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const methods = ['cleanTtsPanelSlice', 'ttsCurrentSentence', 'ttsPanelTextBefore',
  'ttsPanelTextAfter', 'ttsPanelFollowingText'];
const host = vm.runInNewContext(stripTypeScriptTypes(`({${methods.map(name => method(readBook, name)).join(',')}})`));
function slices(text, start, end) {
  Object.assign(host, { ttsDisplayText: text, ttsHighlightStart: start, ttsHighlightEnd: end,
    ttsPanelOffsetSource: () => text });
  return [host.ttsPanelTextBefore(), host.ttsCurrentSentence(), host.ttsPanelTextAfter()];
}

// Legacy incoming ranges must still render losslessly. Boundary correction belongs
// to SystemTtsReader and is exercised by reader-tts-boundary-check.mjs.
const before = '上一段。\n云果儿问：“明心，你猜里面是什么？';
const current = '”\n　　明心摇头，又立马说道：“是吃的！';
const after = '”\n　　云果儿笑了。';
assert.deepEqual(slices(before + current + after, before.length, before.length + current.length),
  [before, current, after]);
assert.equal(host.ttsPanelFollowingText(), before + current + after, 'speech boundaries must not add newlines');

const fixedBefore = before + '”';
const fixedCurrent = current.slice(1) + '”';
const fixedAfter = after.slice(1);
assert.deepEqual(slices(fixedBefore + fixedCurrent + fixedAfter,
  fixedBefore.length, fixedBefore.length + fixedCurrent.length), [fixedBefore, fixedCurrent, fixedAfter]);

// Check every boundary, including spaces, paragraph separators, quotation marks and UTF-16 offsets.
for (const text of ['他说：“好！”她答：“嗯。”', 'Hello, world! Next word.',
  '前段。\n　　当前段。\n后段。', '测试😀，再见！']) {
  for (let start = 0; start < text.length; start++) {
    for (let end = start + 1; end <= text.length; end++) {
      assert.equal(slices(text, start, end).join(''), text);
      assert.equal(host.ttsPanelFollowingText(), text);
    }
  }
}
assert.deepEqual(slices('最后一句。', 0, 5), ['', '最后一句。', '']);
assert.equal(host.cleanTtsPanelSlice(' \n　　下一段\n '), '下一段', 'preview cleanup still trims edges');

// A long paragraph must follow the spoken line, not the center of the entire paragraph.
const panel = fs.readFileSync(new URL('../entry/src/main/ets/components/ReaderTtsPlayerPanel.ets', import.meta.url), 'utf8');
const timers = new Map();
let timerId = 0;
const scrolls = [];
const context = vm.createContext({
  setTimeout(fn) { timers.set(++timerId, fn); return timerId; },
  clearTimeout(id) { timers.delete(id); }, Curve: { EaseOut: 'easeOut' }
});
const follower = vm.runInContext(stripTypeScriptTypes(`({${method(panel, 'scrollToCurrentSentence')}})`), context);
Object.assign(follower, {
  textUpdateTimer: -1, globalTtsTextBefore: '字'.repeat(600), globalTtsCurrentText: '\n　正在读',
  readingViewportHeight: 200, isAudio: () => false,
  getUIContext: () => ({ px2vp: px => px / 2 }),
  readingTextController: { getLayoutManager: () => ({
    getLineCount: () => 40,
    getLineMetrics: i => ({ startIndex: i * 20, endIndex: (i + 1) * 20,
      baseline: i * 56 + 40, ascent: 40, height: 56 })
  }) },
  textScroller: { scrollTo: options => scrolls.push(options) }
});
follower.scrollToCurrentSentence(true);
follower.scrollToCurrentSentence(false);
assert.equal(timers.size, 1, 'separate storage changes must coalesce');
for (const callback of timers.values()) callback();
assert.equal(scrolls.length, 1);
assert.equal(scrolls[0].yOffset, 754, 'line 30 is centered using px-to-vp conversion');
assert.equal(scrolls[0].animation, false);
console.log('TTS panel checks passed: quote boundaries, paragraphs, spaces, Unicode, previews and long-paragraph following.');
