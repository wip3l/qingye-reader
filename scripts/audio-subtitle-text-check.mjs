// 听书 AI 字幕的文字整理回归：字节级 BPE token 还原逐字时间、标点对位、切行、合并与当前行查找。
// 识别本身（sherpa-onnx、音频解码）依赖系统接口，只能真机验证。

import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const modulePath = path.join(root, 'entry/src/main/ets/core/subtitle/SubtitleText.ts');
const { SubtitleText, SubtitleChar, SubtitleCue } = await import(pathToFileURL(modulePath).href);

let assertions = 0;
function assert(condition, message) {
  assertions++;
  if (!condition) throw new Error(message);
}
function equal(actual, expected, message) {
  assert(JSON.stringify(actual) === JSON.stringify(expected),
    `${message}\n  actual:   ${JSON.stringify(actual)}\n  expected: ${JSON.stringify(expected)}`);
}

// 与 sherpa-onnx csrc/bbpe.cc 一致的字节 → 字符表，用来把文字编码成模型会输出的 token。
const byteToSymbol = new Map();
for (let b = 0; b < 32; b++) byteToSymbol.set(b, String.fromCodePoint(0x100 + b));
for (let b = 32; b < 127; b++) byteToSymbol.set(b, String.fromCodePoint(b));
{
  const skipped = new Set([0x132, 0x133, 0x13f, 0x140, 0x149, 0x17f]);
  let value = 127;
  for (let code = 0x120; code <= 0x1a6; code++) {
    if (skipped.has(code)) continue;
    byteToSymbol.set(value++, String.fromCodePoint(code));
  }
  assert(value === 256, '字节表应覆盖 127–255');
}
function encode(text) {
  return Array.from(new TextEncoder().encode(text)).map((b) => byteToSymbol.get(b)).join('');
}
function texts(chars) {
  return chars.map((char) => char.text).join('');
}

// 1. 与真实 tokens.txt 对得上：表里的几个 token 都能解成完整汉字。
{
  const sample = ['▁ƎĽĥ', '▁ƍĻŕ', '▁ƋŞġ', '▁Əťļ'];
  const chars = SubtitleText.decodeTokens(sample, [0, 0.1, 0.2, 0.3], 0);
  equal(chars.length, 4, '每个 3 字节 token 解出一个字');
  assert(chars.every((char) => /\p{Script=Han}/u.test(char.text)), `应全是汉字：${texts(chars)}`);
}

// 2. 一个字的字节分在两个 token 里：时间取第一个字节所在的 token。
{
  const bytes = encode('雨夜');
  const tokens = ['▁' + bytes.slice(0, 2), bytes.slice(2, 4), bytes.slice(4)];
  const chars = SubtitleText.decodeTokens(tokens, [0.5, 0.62, 0.8], 10000);
  equal(texts(chars), '雨夜', '跨 token 的字节拼回原字');
  equal(chars.map((char) => char.ms), [10500, 10620], '时间取首字节所在 token，并加上段起点');
}

// 3. 空格：英文单词之间保留一个，中文旁边去掉；解不出来的字节丢掉。
{
  const tokens = ['▁' + encode('他说'), '▁' + encode('hello'), '▁' + encode('world'), '▁' + encode('。'),
    String.fromCodePoint(0x1a6)];
  const chars = SubtitleText.decodeTokens(tokens, [0, 0.4, 0.8, 1.2, 1.3], 0);
  equal(texts(chars), '他说hello world。', '中文旁不留空格，英文词间留一个');
}

// 4. 标点对位：插入的标点用前一个字的时间并标记为标点；原字被改动时放弃标点。
{
  const chars = [...'掌柜的还开着吗'].map((text, i) => new SubtitleChar(text, 1000 + i * 200));
  const withPunct = SubtitleText.applyPunctuation(chars, '掌柜的，还开着吗？');
  equal(texts(withPunct), '掌柜的，还开着吗？', '标点插回原位');
  const comma = withPunct[3];
  assert(comma.punct && comma.ms === 1400, '逗号用前一个字的时间');
  equal(texts(SubtitleText.applyPunctuation(chars, '掌柜地，还开着吗？')), '掌柜的还开着吗', '改了字就不用标点结果');
  const latin = SubtitleText.decodeTokens(['▁' + encode('ok'), '▁' + encode('go')], [0, 0.3], 0);
  equal(texts(SubtitleText.applyPunctuation(latin, 'OK, go.')), 'ok, go.', '大小写不同仍算同一个字母');
}

// 5. 切行：句末必换；逗号处至少 6 字才换；停顿超过 0.7 秒换；超长硬换。
{
  const make = (text, start, step = 200, gaps = {}) => {
    let ms = start;
    return [...text].map((char, i) => {
      if (gaps[i]) ms += gaps[i];
      const value = new SubtitleChar(char, ms, /[，。？！、]/.test(char));
      ms += step;
      return value;
    });
  };
  const cues = SubtitleText.buildCues(make('进来吧，雨这么大，喝碗热汤再走。年轻人道了谢', 0));
  equal(cues.map((cue) => cue.text), ['进来吧，雨这么大，', '喝碗热汤再走。', '年轻人道了谢'], '逗号短行并入下一句');
  equal(cues[0].startMs, 0, '行起点是第一个字');
  assert(cues[1].endMs > cues[1].startMs, '行有正的时长');
  const paused = SubtitleText.buildCues(make('老周愣了一下还是卸下门板', 0, 150, { 6: 900 }));
  equal(paused.map((cue) => cue.text), ['老周愣了一下', '还是卸下门板'], '长停顿处换行');
  const long = SubtitleText.buildCues(make('一'.repeat(60), 0, 100));
  assert(long.every((cue) => cue.text.length <= 26), '没有停顿也不超过 26 字');
  equal(long.map((cue) => cue.text).join(''), '一'.repeat(60), '硬换行不丢字');
}

// 6. clip 去掉段首标点；merge 排序、去重并让结束时间不晚于下一行开始；indexAt 找当前行。
{
  const chars = [new SubtitleChar('，', 900, true), new SubtitleChar('好', 1000), new SubtitleChar('的', 1200),
    new SubtitleChar('呀', 16500)];
  equal(texts(SubtitleText.clip(chars, 0, 16000)), '好的', '只留本段的字，段首标点去掉');
  const cue = (startMs, endMs, text) => Object.assign(new SubtitleCue(), { startMs, endMs, text });
  const merged = SubtitleText.merge([[cue(17000, 18000, '第二段')], [cue(1000, 17500, '第一段'), cue(1000, 17500, '第一段')]]);
  equal(merged.map((item) => item.text), ['第一段', '第二段'], '按时间排好并去掉重复');
  equal(merged[0].endMs, 17000, '结束时间不晚于下一行开始');
  equal([SubtitleText.indexAt(merged, 500), SubtitleText.indexAt(merged, 1000), SubtitleText.indexAt(merged, 20000)],
    [-1, 0, 1], '第一行之前为 -1，之后取最近开始的一行');
}

// 7. 段交界处被切开的半句接回一行；上一行以标点结束或中间停顿太久时不接。
{
  const cue = (startMs, endMs, text) => Object.assign(new SubtitleCue(), { startMs, endMs, text });
  const joined = SubtitleText.merge([[cue(110000, 111950, '是我告')], [cue(112100, 113200, '诉你的')]]);
  equal(joined.map((item) => item.text), ['是我告诉你的'], '跨段半句接回');
  equal([joined[0].startMs, joined[0].endMs], [110000, 113200], '接起来的行覆盖两段时间');
  const ended = SubtitleText.merge([[cue(110000, 111950, '好了。')], [cue(112100, 113200, '走吧')]]);
  equal(ended.length, 2, '上一行以标点结束不接');
  const paused = SubtitleText.merge([[cue(100000, 101000, '他说')], [cue(112100, 113200, '走吧')]]);
  equal(paused.length, 2, '中间停顿太久不接');
  const sameChunk = SubtitleText.merge([[cue(0, 1950, '老周愣了一下'), cue(2000, 3000, '还是卸下门板')]]);
  equal(sameChunk.length, 2, '同一段里的换行不动');
}

console.log(`audio subtitle text check passed (${assertions} assertions)`);
