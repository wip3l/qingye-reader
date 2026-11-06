// 小说繁→简：等长转换、标记豁免、分片、繁体检测，以及阅读页的接入点。
// node --experimental-strip-types scripts/reader-text-convert-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const engine = path.join(root, 'harmony-book-ai-engine/aiengine/src/main');
const context = vm.createContext({ Map, Set, Number, Math, Error, Array, RegExp, String });
function load(file) {
  const code = fs.readFileSync(file, 'utf8').replace(/^import [^;]*;\r?\n/gm, '').replace(/^export /gm, '');
  vm.runInContext(stripTypeScriptTypes(code, { mode: 'strip' }), context);
}
load(path.join(engine, 'ets/core/reader/ComicChineseDictionary.ts'));
load(path.join(root, 'entry/src/main/ets/core/reader/ReaderTextConvert.ts'));
const Dictionary = vm.runInContext('ComicChineseDictionary', context);
const Convert = vm.runInContext('ReaderTextConvert', context);
const raw = (name) => fs.readFileSync(path.join(engine, 'resources/rawfile/opencc', name), 'utf8');
const dictionary = new Dictionary(raw('TSCharacters.txt'), raw('TSPhrases.txt'));

// 等长：整份字典的每个词条转换后 UTF-16 长度都不变；会变长的条目（扩展区汉字、二噁英）保留原文。
for (const file of ['TSCharacters.txt', 'TSPhrases.txt']) {
  for (const line of raw(file).split(/\r?\n/)) {
    const tab = line.indexOf('\t');
    if (!line || line.startsWith('#') || tab <= 0) continue;
    const source = line.substring(0, tab);
    assert.equal(dictionary.convertSameLength(source).length, source.length, `${source} 转换后长度变了`);
  }
}
assert.equal(dictionary.convertSameLength('二噁英'), '二恶英', '变长的词组跳过后仍按单字转换');
assert.equal(dictionary.convertSameLength('㑮'), '㑮', '映射到扩展区汉字的生僻字保留原字');
assert.notEqual(dictionary.convert('㑮'), '㑮', '漫画用的完整转换不受影响');

const traditional = '雨後的街道還帶著潮氣，她把傘收進門邊的鐵架，抬頭看見書店的燈仍亮著。' +
  '「今天也來得這麼晚？」老闆從櫃檯後探出頭，手裡捧著一疊剛到的舊書。她笑了笑，沒有回答，徑直走向最裡面那排書架。';
const converted = Convert.convert(dictionary, traditional);
assert.equal(converted.length, traditional.length);
for (const word of ['还', '这么', '书店', '门边', '铁架', '头', '没有', '书架']) assert.ok(converted.includes(word), word);

// 标记原样保留：图片标记里是编码过的路径，交互标记里是应用数据。
const image = '[[LEGADO_EPUB_IMAGE:%E5%9C%96%E6%9B%B8/圖書館.png]]';
const action = '[[LEGADO_READER_ACTION_V3:{"title":"段評 說明"}]]';
const mixed = `第一章 開始\n${image}\n這是正文。${action}還有後文。`;
const mixedOut = Convert.convert(dictionary, mixed);
assert.equal(mixedOut.length, mixed.length);
assert.ok(mixedOut.includes(image) && mixedOut.includes(action), '标记不转换');
assert.ok(mixedOut.startsWith('第一章 开始\n') && mixedOut.includes('这是正文。') && mixedOut.includes('还有后文。'));

// 分片：拼回去就是原文，长段只在换行处切开。
const paragraph = '這是一段很長的正文，用來測試分片。'.repeat(40) + '\n';
const long = paragraph.repeat(60);
const chunks = Convert.chunks(long);
assert.equal(chunks.join(''), long);
assert.ok(chunks.length > 1);
for (const chunk of chunks.slice(0, -1)) {
  assert.ok(chunk.length <= 8000 && chunk.endsWith('\n'), '分片不超过上限且在换行处结束');
}
assert.equal(Convert.convert(dictionary, long), dictionary.convertSameLength(long), '分片转换与整段一致');
assert.deepEqual(Array.from(Convert.chunks('')), []);
assert.deepEqual(Array.from(Convert.chunks(`${image}${action}`)), [image, action]);

// 繁体检测：繁体提示；简体、日文、过短都不提示。
const sampleOf = (text) => Convert.sample(dictionary, text);
assert.ok(Convert.looksTraditional(sampleOf(traditional.repeat(3))));
assert.ok(!Convert.looksTraditional(sampleOf(converted.repeat(3))), '简体书不提示');
assert.ok(!Convert.looksTraditional(sampleOf(traditional)), '字数太少不判断');
const japanese = '雨上がりの通りはまだ湿っていた。彼女は傘を入口の棚に差し込み、顔を上げると本屋の明かりがまだ灯っていた。' +
  '「今日も遅いね」と店主が櫃檯の奥から顔を出した。問題の書類を確認し、開館の時間を調べた。';
assert.ok(!Convert.looksTraditional(sampleOf(japanese.repeat(4))), '日文不提示');
assert.ok(sampleOf(`${image}${traditional}`).cjk === sampleOf(traditional).cjk, '标记不计入样本');

// 书籍变量：只有 t2s 算开启；off 与 t2s 之外都算没选过。
assert.ok(Convert.enabled('t2s') && !Convert.enabled('off') && !Convert.enabled(''));
assert.ok(Convert.undecided('') && !Convert.undecided('off') && !Convert.undecided('t2s'));

// 阅读页接入点。
const readBook = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/ReadBook.ets'), 'utf8');
const method = (name) => {
  const start = readBook.indexOf(`\n  ${name}(`);
  assert.ok(start >= 0, `缺少 ${name}`);
  const next = readBook.indexOf('\n  }\n', start);
  return readBook.substring(start, next);
};
assert.ok(method('readerPreparedContentKey').includes('isReaderTextConvertActive()'), '准备缓存按转换模式区分');
assert.ok(method('readerContentNeedsPreparation').includes('isReaderTextConvertActive()'), '开启后同步路径不能直接分页原文');
const prepare = method('async prepareReaderContentRules');
assert.ok(prepare.indexOf('ReaderContentPreprocessor.apply') < prepare.indexOf('ReaderTextConvertRuntime.convert'),
  '替换净化先于繁→简');
assert.ok(method('getChapterTitle').includes('ReaderTextConvertRuntime.convertNow'), '章节名一起转换');
assert.ok(method('isReaderTextConvertActive').includes('!this.isReaderComicModeActive()'), '漫画模式不转换正文');
assert.ok(method('async reloadReaderTextConvert').includes('findPageIndexByOffset(readingOffset)'), '切换后停在原处');
assert.ok(readBook.includes('transformText: async'), '全文查找与显示一致');
assert.ok(method('startReaderContentSearch').includes('ReaderTextConvertRuntime.convertNow(query)'), '繁体查找词也能查到');
const search = fs.readFileSync(path.join(root, 'entry/src/main/ets/core/reader/ReaderContentSearch.ets'), 'utf8');
assert.ok(search.indexOf('ReaderContentPreprocessor.apply(text') < search.indexOf('this.host.transformText(text)'));

console.log('reader-text-convert-check: ok');
