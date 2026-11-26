/**
 * 长按选词（纯逻辑）：在手指所在的句子里用系统分词结果找出那个词。
 * 分词只看手指附近一句（到句号、问号、叹号、分号、换行为止，最多前后各 MAX_SIDE 个字），够快也够准。
 */
export class ReaderWordSegmentRange {
  static readonly MAX_SIDE: number = 40;
  /** 超过这个长度的“词”（分词器把整串专名、数字连在一起时）不当作词选中，保持只选一个字。 */
  static readonly MAX_WORD: number = 8;
  private static readonly STOP: RegExp = /[。！？!?；;\n…]/;
  private static readonly CJK: RegExp = /[\u3400-\u9FFF\uF900-\uFAFF]/;

  /** 手指所在的这个字是不是要分词的汉字。 */
  static isCjk(char: string): boolean {
    return ReaderWordSegmentRange.CJK.test(char || '');
  }

  /** 取手指附近的一句：[开始, 结束)，结束不含句末标点。 */
  static window(text: string, position: number): number[] {
    const max = ReaderWordSegmentRange.MAX_SIDE;
    let start = position;
    while (start > 0 && position - start < max && !ReaderWordSegmentRange.STOP.test(text.charAt(start - 1))) start--;
    let end = position + 1;
    while (end < text.length && end - position < max && !ReaderWordSegmentRange.STOP.test(text.charAt(end))) end++;
    return [Math.max(0, start), Math.min(text.length, end)];
  }

  /**
   * 按分词结果在 sentence 里依次对位，找出盖住 local（句内下标）的那个词，返回句内 [开始, 结束)。
   * 词要至少两个字、含汉字、不超过 MAX_WORD；对不上或不像词返回 null（调用方保持只选一个字）。
   */
  static rangeAt(sentence: string, words: string[], local: number): number[] | null {
    let cursor = 0;
    for (const raw of words) {
      const word = raw || '';
      if (!word) continue;
      let index = sentence.startsWith(word, cursor) ? cursor : sentence.indexOf(word, cursor);
      if (index < 0) {
        // 分词器有时会去掉或改写空白：跳过对不上的词，后面的仍按顺序找。
        continue;
      }
      const end = index + word.length;
      if (local >= index && local < end) {
        const length = Array.from(word).length;
        if (length < 2 || length > ReaderWordSegmentRange.MAX_WORD || !ReaderWordSegmentRange.CJK.test(word) ||
          /\s/.test(word)) {
          return null;
        }
        return [index, end];
      }
      cursor = end;
      if (cursor > local) break;
    }
    return null;
  }
}
