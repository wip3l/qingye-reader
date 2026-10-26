// Run with: node scripts/reader-tts-boundary-check.mjs
// Execute the production ArkTS methods without loading device speech/audio APIs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/utils/SystemTtsReader.ets', import.meta.url), 'utf8');
const names = [
  'splitText', 'splitCustomText', 'appendCustomTextRange', 'splitSystemText',
  'splitSystemChunksAtPageBreaks', 'appendAbsoluteTextChunk', 'splitCloudText',
  'findLastCloudBreak', 'findFirstCloudBreak', 'isCloudBreak', 'extendTtsBreak',
  'isClosingPunctuationAt', 'isClosingPunctuation', 'findSentenceBreak',
  'isStrongSentenceEnd', 'isWeakSentenceEnd', 'isSentenceEnd', 'isNumericDecimalPoint',
  'isTrimChar', 'isHighSurrogate', 'safeHardCutIndex', 'snapPageBreakOffset',
  'splitCloudFocusChunks', 'appendFocusChunk', 'cloudFocusChunkForSpeechRange',
  'buildProsodyCloudCues', 'normalizeChunkForSpeechWithMap', 'normalizeChunkForSpeech',
  'normalizeMathNotationForSpeech', 'replaceUnsafeSpeechCharacters'
];
const methods = names.map(name => {
  const start = source.indexOf(`  private ${name}(`);
  assert.ok(start >= 0, `production method ${name}`);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
});
const constants = source.split('\n').filter(line => line.includes('private static readonly '));
const Reader = vm.runInNewContext(stripTypeScriptTypes(
  `class SystemTtsReader { ${constants.join('\n')} ${methods.join('\n')} }; SystemTtsReader`),
  { console: { info() {} } });
const reader = new Reader();
reader.optionFocusBreakOffsets = [];
reader.getTtsLanguage = () => 'zh-CN';

function checkRanges(text, chunks, origin = 0) {
  let previousEnd = origin;
  for (const chunk of chunks) {
    assert.ok(chunk.start >= previousEnd && chunk.end > chunk.start, 'ordered, nonempty ranges');
    assert.equal(text.slice(previousEnd - origin, chunk.start - origin).trim(), '', 'no missing text');
    assert.equal(chunk.text, text.slice(chunk.start - origin, chunk.end - origin), 'original UTF-16 offsets');
    assert.doesNotMatch(chunk.text, /^[”’）)】\]》〉」』。！？；;!?…]/u, 'no stranded sentence tail');
    previousEnd = chunk.end;
  }
  assert.equal(text.slice(previousEnd - origin).trim(), '', 'include the chapter tail');
}

const first = '王婆子哎呦一声，“什么零花钱啊，给这么多，我可不要，你拿回去，我不要。”';
const second = '云果儿也没睡呢，坐在自己床上玩七巧板呢，见她阿姐来了也趿拉着鞋子跑了过来，“阿姐，阿姐，有我没？”';
const third = '云桃捏了下云果儿的鼻子，“有，那是留给你的。”';
const screenshot = `${first}\n　　${second}\n　　${third}`;
assert.deepEqual(Array.from(reader.splitText(screenshot, 64), item => item.text), [first, second, third]);

const paths = [
  ['custom', text => reader.splitCustomText(text, 64)],
  ['system', text => reader.splitSystemText(text, [])],
  ['cloud request', text => reader.splitCloudText(text)],
  ['cloud fallback', text => reader.splitCloudFocusChunks({ text, start: 0, end: text.length })]
];
let cases = 0;
for (const [name, split] of paths) {
  for (const tier of ['STANDARD', 'PREMIUM']) {
    reader.optionCloudVoiceTier = tier;
    checkRanges(screenshot, split(screenshot));
    // Put punctuation on either side of every relevant soft length limit.
    for (const length of [30, 31, 32, 41, 42, 49, 50, 59, 60, 63, 64, 99, 100, 159, 160, 199, 200, 449, 450]) {
      for (const tail of ['。”', '？！”', '……」', '......』', '？！）】', '。”』）', '！”“']) {
        const text = '前'.repeat(length) + tail + '后'.repeat(80) + '。';
        try { checkRanges(text, split(text)); }
        catch (error) { throw new Error(`${name}/${tier}/${length}/${tail}: ${error.message}`); }
        cases++;
      }
    }
  }
}

// Paired ASCII quotes must close the current range, never steal the next opening quote.
for (const [text, boundary, expected] of [
  ['他说：“好？！”然后走了。', 6, 8],
  ['结束。\n“下一段。”', 3, 3],
  ['结束。 “下一段。”', 3, 3],
  ['结束。“下一句。”', 3, 3],
  ['Done."Next."', 5, 5],
  ['"Done."Next.', 6, 7],
  ["'Don\'t stop!'Next.", 12, 13],
  ['数值为3.5米。', 4, 4],
  ['数值为3.5米。', 8, 8]
]) {
  assert.equal(reader.extendTtsBreak(text, boundary, text.length), expected, text);
}
assert.equal(reader.extendTtsBreak('结束。”后文', 3, 3), 3, 'respect the owning source range');

// Page splits inside punctuation must also move both adjacent ranges to one boundary.
const pageText = '前'.repeat(24) + '？！。”』）' + '后'.repeat(24) + '。';
for (let offset = 24; offset < 30; offset++) {
  checkRanges(pageText, reader.splitSystemText(pageText, [offset]));
  reader.optionFocusBreakOffsets = [100 + offset, 100 + offset + 1];
  checkRanges(pageText, reader.splitCloudFocusChunks({ text: pageText, start: 100, end: 100 + pageText.length }), 100);
}
reader.optionFocusBreakOffsets = [];

// Old server timings may end anywhere inside a punctuation run. Adjacent mappings
// must still be contiguous; punctuation-only timing ranges may disappear.
for (const text of [screenshot, '他说：“完成50%了？！。”\n　　接着还有😀和3.5米。']) {
  const normalized = reader.normalizeChunkForSpeechWithMap(text);
  const variants = [
    { text, sourceToSpeechOffsets: Array.from({ length: text.length + 1 }, (_, index) => index) },
    normalized
  ];
  for (const speech of variants) {
    const job = { ...speech, chunk: { text, start: 100, end: 100 + text.length } };
    for (let boundary = 1; boundary < job.text.length; boundary++) {
      const left = reader.cloudFocusChunkForSpeechRange(job, 0, boundary);
      const right = reader.cloudFocusChunkForSpeechRange(job, boundary, job.text.length);
      if (left && right) assert.equal(left.end, right.start, 'no duplicated/missing punctuation');
      const ranges = [left, right].filter(Boolean);
      assert.equal(ranges.map(range => range.text).join(''), text, 'lossless source mapping');
    }
  }
}

// Moving a punctuation boundary must not move the next sentence's playback cue.
const timedText = '他说：“结束了。”然后继续。';
const quote = timedText.indexOf('”');
const job = { text: timedText, chunk: { text: timedText, start: 0, end: timedText.length }, index: 0,
  sourceToSpeechOffsets: Array.from({ length: timedText.length + 1 }, (_, index) => index) };
const audio = { sampleRate: 1000, pcm: new ArrayBuffer(6000), timings: [
  { startOffset: 0, endOffset: quote, startTime: 0 },
  { startOffset: quote, endOffset: quote + 1, startTime: 1000 },
  { startOffset: quote + 1, endOffset: timedText.length, startTime: 1500 }
] };
const cues = reader.buildProsodyCloudCues(1, job, audio);
assert.deepEqual(Array.from(cues, cue => cue.frameOffset), [0, 1500]);
reader.readGeneration = 1;
reader.active = true;
reader.notifyAudioStarted = () => {};
const spoken = [];
reader.onChunkStart = chunk => spoken.push(chunk.text);
cues.forEach(cue => cue.callback());
assert.deepEqual(spoken, ['他说：“结束了。”', '然后继续。']);

console.log(`TTS boundary checks passed: ${cases} length/tail cases, screenshot, pages, source maps and playback cues.`);
