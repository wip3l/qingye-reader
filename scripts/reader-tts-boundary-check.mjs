// Run with: node scripts/reader-tts-boundary-check.mjs
// Execute the production ArkTS methods without loading device speech/audio APIs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/utils/SystemTtsReader.ets', import.meta.url), 'utf8');
const names = [
  'splitText', 'splitCustomText', 'appendCustomTextRange', 'splitSystemText', 'splitSystemSentenceText',
  'appendPackedSpeechChunks', 'speechPackLimit', 'speechSentenceLimit', 'splitSpeechSentences',
  'isSpeechSentenceEndAt', 'pushSpeechSentence', 'appendBalancedSpeechPieces', 'resplitRemainingForDirectPlay',
  'coalescePunctuationOnlyChunks', 'isSpeechOnlyPunctuation', 'isSpeechPunctuationCode',
  'buildSystemFocusCues', 'appendSystemFocusCue', 'frameAtSpeechOffset', 'speechWeightAt',
  'findPcmQuietRuns', 'alignAnchorsToQuietRuns', 'stripFootnoteMarkers',
  'splitSystemChunksAtPageBreaks', 'appendAbsoluteTextChunk', 'splitCloudText',
  'findLastCloudBreak', 'findFirstCloudBreak', 'isCloudBreakAt', 'isEllipsisInsideSentence',
  'isCloudBreak', 'extendTtsBreak',
  'isClosingPunctuationAt', 'isClosingPunctuation', 'findSentenceBreak',
  'isStrongSentenceEnd', 'isWeakSentenceEnd', 'isSentenceEnd', 'isNumericDecimalPoint',
  'isTrimChar', 'isHighSurrogate', 'safeHardCutIndex', 'backOffHardCut', 'snapPageBreakOffset',
  'splitCloudFocusChunks', 'appendFocusChunk', 'cloudFocusChunkForSpeechRange',
  'buildProsodyCloudCues', 'normalizeChunkForSpeechWithMap', 'normalizeChunkForSpeech',
  'normalizeMathNotationForSpeech', 'replaceUnsafeSpeechCharacters', 'stripDecorativeSpeechSymbols'
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

// An ellipsis followed by more words is a pause inside the sentence: never end a chunk there.
const hesitation = '以后玉帝陛下偷偷摸去瑶池宫，却见一位位女仙舞刀弄枪、披甲戴盔……\n　　“小神……明白。”\n　　' +
  '李长寿低头应了句，只感觉一阵头疼。';
for (const chunks of [reader.splitSystemText(hesitation), reader.splitSystemSentenceText(hesitation, []), reader.splitCustomText(hesitation, 64),
  reader.splitCloudText(hesitation)]) {
  checkRanges(hesitation, chunks);
  for (const chunk of chunks) assert.doesNotMatch(chunk.text, /小神…+$/u, 'ellipsis inside a quote is not a chunk end');
}
// A long run with nowhere to cut (letters/digits only) must still advance: the hard cut used to
// walk back to the chunk start and the split loop never ended.
for (const run of ['a'.repeat(1200), '7'.repeat(1200), '哈'.repeat(30) + 'x'.repeat(1200) + '。']) {
  const unbroken = `他念出那串编号：${run}\n　　然后合上了本子。`;
  for (const chunks of [reader.splitSystemText(unbroken), reader.splitSystemSentenceText(unbroken, []), reader.splitCustomText(unbroken, 64),
    reader.splitCloudText(unbroken), reader.splitText(unbroken, 64)]) {
    checkRanges(unbroken, chunks);
  }
}
assert.equal(reader.isEllipsisInsideSentence('盔……\n', 1), false, 'paragraph-final ellipsis still ends');
assert.equal(reader.isEllipsisInsideSentence('神……”', 1), false, 'ellipsis before a closing quote still ends');
assert.equal(reader.isEllipsisInsideSentence('Wait...what', 5), true, 'ASCII ellipsis inside a sentence');
assert.equal(reader.isEllipsisInsideSentence('Done.Next', 4), false, 'a single full stop is not an ellipsis');

const paths = [
  ['custom', text => reader.splitCustomText(text, 64)],
  ['system', text => reader.splitSystemText(text)],
  ['system direct play', text => reader.splitSystemSentenceText(text, [])],
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
  checkRanges(pageText, reader.splitSystemSentenceText(pageText, [offset]));
  reader.optionFocusBreakOffsets = [100 + offset, 100 + offset + 1];
  checkRanges(pageText, reader.splitCloudFocusChunks({ text: pageText, start: 100, end: 100 + pageText.length }), 100);
}
reader.optionFocusBreakOffsets = [];

// Marker symbols must not reach custom voices, which read them out as "星号"; math stays spoken.
assert.equal(reader.normalizeChunkForSpeech('*时间不早，该吃晚饭了。'), '时间不早，该吃晚饭了。');
assert.equal(reader.normalizeChunkForSpeech('他**真的**来了，※注：★重点'), '他真的来了，注：重点');
assert.equal(reader.normalizeChunkForSpeech('3*4与5＊6'), '3乘以4与5乘以6');
assert.equal(reader.normalizeChunkForSpeech('3 * 4'), '3乘以4');
const markerMap = reader.normalizeChunkForSpeechWithMap('*时间不早。');
assert.equal(markerMap.text, '时间不早。');
assert.deepEqual(Array.from(markerMap.sourceToSpeechOffsets.slice(0, 3)), [0, 0, 1]);

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

// Sentence first: a short sentence is never glued onto the next one only to be cut at a comma,
// custom voices never merge paragraphs, and an over-long sentence is cut near its middle.
const passage = [
  '他愣住了。眼前这座废弃多年的道观，门楣上的牌匾早已斑驳脱落，只剩下半个模糊的“清”字还勉强能够辨认出来，在风中轻轻摇晃着。',
  '　　“师兄，你说这里真的有人住吗？”小师妹缩着脖子，躲在他身后小声问道，声音里带着几分掩饰不住的害怕。',
  '　　“嗯。”',
  '　　院子里杂草丛生，青石板的缝隙中钻出一簇簇不知名的野花，在午后的阳光下显得格外鲜艳，与周围破败的景象形成了鲜明的对比，仿佛有人一直在悄悄打理这片角落一般。',
  '　　他打开网址www.example.com看了看，版本是v1.2.3。'
].join('\n');
const systemChunks = reader.splitSystemText(passage);
const customChunks = reader.splitCustomText(passage, 64);
checkRanges(passage, systemChunks);
checkRanges(passage, customChunks);
assert.equal(systemChunks[0].text, '他愣住了。', 'system: short opening sentence stands alone');
assert.equal(customChunks[0].text, '他愣住了。', 'custom: short opening sentence stands alone');
for (const chunk of systemChunks) assert.doesNotMatch(chunk.text, /[，,、]$/u, 'system: whole sentences only');
for (const chunk of customChunks) assert.doesNotMatch(chunk.text, /\n/u, 'custom: one paragraph per chunk');
assert.ok(systemChunks.some(chunk => chunk.text.includes('\n')), 'system: short paragraphs are read together');
assert.ok(systemChunks.every(chunk => chunk.text.length <= 240), 'system: chunk stays below the engine limit');
assert.ok(customChunks.some(chunk => chunk.text.includes('www.example.com看了看')), 'a dot inside a URL is not a full stop');
const longSentence = passage.split('\n')[3].trim();
const longPieces = customChunks.filter(chunk => longSentence.includes(chunk.text));
assert.equal(longPieces.length, 2, 'custom: a 76-character sentence becomes two pieces');
assert.ok(Math.min(...longPieces.map(chunk => chunk.text.length)) >= 30, 'custom: pieces are balanced');
assert.ok(longPieces.every(chunk => /[，。]$/u.test(chunk.text)), 'custom: pieces end on punctuation');
for (const run of ['——', '……']) {
  const text = '甲'.repeat(40) + run + '乙'.repeat(40) + '。';
  for (const chunk of reader.splitCustomText(text, 64)) {
    assert.ok(!chunk.text.endsWith(run[0]) || chunk.text.endsWith(run), `${run} is not split in half`);
  }
}

// System voice cues: sentence starts snap to the pauses in the PCM, a page start inside a sentence
// is interpolated between them, and the first cue stays at frame 0.
{
  const rate = 8000;
  const sentencesText = ['第一句话说得比较长一些。', '第二句。', '第三句话又说了很久很久才停下来。'];
  const text = sentencesText.join('');
  const durations = [1.2, 1.6, 1.4];
  const gap = 0.35;
  const frames = Math.round((durations.reduce((a, b) => a + b, 0) + gap * 2) * rate);
  const pcm = new ArrayBuffer(frames * 2);
  const samples = new Int16Array(pcm);
  const gapEnds = [];
  let cursor = 0;
  durations.forEach((seconds, index) => {
    const length = Math.round(seconds * rate);
    for (let i = 0; i < length; i++) samples[cursor + i] = i % 2 === 0 ? 3000 : -3000;
    cursor += length;
    if (index < durations.length - 1) {
      cursor += Math.round(gap * rate);
      gapEnds.push(cursor);
    }
  });
  reader.sourceText = text;
  const pageStart = text.indexOf('又说');
  reader.optionFocusBreakOffsets = [pageStart];
  const focus = reader.buildSystemFocusCues({ text, start: 0, end: text.length }, pcm, rate);
  assert.deepEqual(Array.from(focus, cue => cue.chunk.text),
    ['第一句话说得比较长一些。', '第二句。', '第三句话', '又说了很久很久才停下来。']);
  assert.equal(focus[0].frameOffset, 0);
  for (let index = 0; index < gapEnds.length; index++) {
    const error = Math.abs(focus[index + 1].frameOffset - gapEnds[index]) / rate;
    assert.ok(error < 0.06, `sentence ${index + 2} cue lands on its pause (off by ${error.toFixed(3)}s)`);
  }
  assert.ok(focus[3].frameOffset > focus[2].frameOffset && focus[3].frameOffset < frames, 'page cue inside its sentence');
  // One sentence, no page break: a single cue as before.
  reader.optionFocusBreakOffsets = [];
  reader.sourceText = sentencesText[0];
  assert.equal(reader.buildSystemFocusCues({ text: sentencesText[0], start: 0, end: sentencesText[0].length },
    pcm, rate).length, 1);
}

// Comma pauses inside sentences and an overall tempo far from the estimate: the alignment must
// still pick the longer sentence-end pauses, in order.
{
  const rate = 16000;
  // [text, seconds of speech per clause...]; clauses inside one sentence are split by 0.15s comma pauses.
  const plan = [
    ['院子里杂草丛生，青石板的缝隙中钻出野花，在阳光下显得格外鲜艳。', [0.9, 1.1, 1.0]],
    ['“等等。”', [0.5]],
    ['林默忽然停下脚步，侧耳听了听。', [0.9, 0.7]],
    ['远处传来一阵若有若无的钟声。', [1.4]]
  ];
  const text = plan.map(item => item[0]).join('');
  const pieces = [];
  plan.forEach(([, clauses], sentence) => {
    clauses.forEach((seconds, clause) => {
      pieces.push(['speech', seconds * 0.7]);
      if (clause < clauses.length - 1) pieces.push(['quiet', 0.15]);
    });
    if (sentence < plan.length - 1) pieces.push(['quiet', 0.4]);
  });
  const frames = Math.round(pieces.reduce((sum, [, seconds]) => sum + seconds, 0) * rate);
  const pcm = new ArrayBuffer(frames * 2);
  const samples = new Int16Array(pcm);
  const sentenceStarts = [];
  let cursor = 0;
  let previousQuiet = 0;
  for (const [kind, seconds] of pieces) {
    const length = Math.round(seconds * rate);
    if (kind === 'speech') {
      if (previousQuiet === 0.4) sentenceStarts.push(cursor);
      for (let i = 0; i < length; i++) samples[cursor + i] = Math.round(2500 * Math.sin(i / 3));
    }
    previousQuiet = kind === 'quiet' ? seconds : 0;
    cursor += length;
  }
  reader.sourceText = text;
  reader.optionFocusBreakOffsets = [];
  const focus = reader.buildSystemFocusCues({ text, start: 0, end: text.length }, pcm, rate);
  assert.deepEqual(Array.from(focus, cue => cue.chunk.text), plan.map(item => item[0]));
  sentenceStarts.forEach((start, index) => {
    const error = Math.abs(focus[index + 1].frameOffset - start) / rate;
    assert.ok(error < 0.06, `comma pauses: sentence ${index + 2} cue off by ${error.toFixed(3)}s`);
  });
  reader.sourceText = '';
}

// Direct engine playback cannot place cues: the unread rest falls back to sentence-sized chunks.
{
  reader.sourceText = passage;
  reader.optionFocusBreakOffsets = [];
  reader.chunks = reader.coalescePunctuationOnlyChunks(reader.splitSystemText(passage), passage);
  const before = reader.chunks.length;
  reader.resplitRemainingForDirectPlay(1);
  assert.ok(reader.chunks.length > before, 'remaining chunks are re-split');
  assert.equal(reader.chunks[0].text, '他愣住了。', 'already spoken chunks stay');
  checkRanges(passage, reader.chunks);
  assert.ok(reader.chunks.slice(1).every(chunk => chunk.text.length <= 60), 'sentence-sized again');
  reader.chunks = [];
  reader.sourceText = '';
}

// Footnote numbers are not spoken; bracketed words still are.
assert.equal(reader.normalizeChunkForSpeech('他推开门[12]，走了出去。'), '他推开门，走了出去。');
assert.equal(reader.normalizeChunkForSpeech('这是注释【3】和〔45〕的位置。'), '这是注释和的位置。');
assert.equal(reader.normalizeChunkForSpeech('【公告】第[一]章'), '【公告】第[一]章');
const footnoteMap = reader.normalizeChunkForSpeechWithMap('门[12]开了。');
assert.equal(footnoteMap.text, '门开了。');
for (let index = 1; index < footnoteMap.sourceToSpeechOffsets.length; index++) {
  assert.ok(footnoteMap.sourceToSpeechOffsets[index] >= footnoteMap.sourceToSpeechOffsets[index - 1], 'monotonic map');
}

console.log(`TTS boundary checks passed: ${cases} length/tail cases, screenshot, pages, source maps, playback cues, sentence packing and system cues.`);
