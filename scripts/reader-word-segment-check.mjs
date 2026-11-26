// 长按选词：取手指附近一句、按分词结果找出盖住手指的那个词，以及接线（只在选中一个汉字时扩、拖过手柄不改）。
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const sandbox = vm.createContext({});
vm.runInContext(stripTypeScriptTypes(readEtsModule('core/reader/ReaderWordSegmentRange.ts')
  .replace(/^export /gm, '') + '\nglobalThis.Range = ReaderWordSegmentRange;'), sandbox);
const Range = sandbox.Range;

// 句子窗口：到句末标点为止，不含它
const text = '他抬头看了一眼。萧炎握紧了拳头，低声说道：“陨落心炎！”然后转身走了';
const pos = text.indexOf('萧炎') + 1;
const [ws, we] = Array.from(Range.window(text, pos));
assert.equal(text.substring(ws, we), '萧炎握紧了拳头，低声说道：“陨落心炎');
const long = '甲'.repeat(100);
const [ls, le] = Array.from(Range.window(long, 50));
assert.equal(50 - ls, Range.MAX_SIDE);
assert.equal(le - 50, Range.MAX_SIDE);
console.log('PASS: sentence window');

// 对位：分词结果按顺序对回句子
const sentence = '萧炎握紧了拳头，低声说道';
const words = ['萧炎', '握紧', '了', '拳头', '，', '低声', '说道'];
assert.deepEqual(Array.from(Range.rangeAt(sentence, words, 0)), [0, 2], '人名');
assert.deepEqual(Array.from(Range.rangeAt(sentence, words, 1)), [0, 2]);
assert.deepEqual(Array.from(Range.rangeAt(sentence, words, 6)), [5, 7], '拳头');
assert.equal(Range.rangeAt(sentence, words, 4), null, '单字词保持只选一个字');
assert.equal(Range.rangeAt(sentence, words, 7), null, '标点不扩');
assert.equal(Range.rangeAt(sentence, ['萧炎握紧了拳头低声说道'], 3), null, '对不上原文的词跳过');
assert.equal(Range.rangeAt('一二三四五六七八九十', ['一二三四五六七八九十'], 2), null, '太长的不当作词');
assert.deepEqual(Array.from(Range.rangeAt('他说 陨落心炎', ['他', '说', '陨落', '心炎'], 4)), [3, 5],
  '分词器去掉空白时后面的词仍能对上');
assert.equal(Range.isCjk('萧'), true);
assert.equal(Range.isCjk('a'), false);
assert.equal(Range.isCjk('，'), false);
console.log('PASS: word range from segments');

// 接线
const readBook = readEtsModule('pages/ReadBook.ets');
function method(name) {
  const start = readBook.search(new RegExp(`^  (?:async )?${name}\\(`, 'm'));
  assert(start >= 0, name);
  return readBook.slice(start, readBook.indexOf('\n  }', start) + 4);
}
const refine = method('refineReaderSelectionToWord');
assert.match(refine, /end - start !== 1/, '只在选中一个字时扩');
assert.match(refine, /canIUse\('SystemCapability\.AI\.NaturalLanguage\.TextProcessing'\)/);
assert.match(refine, /readerV2SelectionDisplayStart !== initial\[0\]/, '拖过手柄就不改');
assert.match(method('beginReaderV2NativeSelection'), /this\.refineReaderSelectionToWord\(page, text, position, start, end, serial\)/);
console.log('PASS: wiring');
