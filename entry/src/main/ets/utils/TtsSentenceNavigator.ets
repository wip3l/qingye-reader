/**
 * 朗读面板的上一句/下一句、上一段/下一段：在本章原文里找目标句子的起点，朗读从那里重新开始。
 * 只认中英文句末标点和换行，句末后面紧跟的引号、括号算在这一句里；空白不算句子内容。
 * 找不到（已是本章第一句或最后一句）时返回 -1，由调用方换章。
 */
export class TtsSentenceNavigator {
  private static readonly TERMINATORS: string = '。！？!?；;…\n';
  private static readonly CLOSERS: string = '”’」』）)】》"\'';

  private static isTerminator(ch: string): boolean {
    return TtsSentenceNavigator.TERMINATORS.indexOf(ch) >= 0;
  }

  private static isCloser(ch: string): boolean {
    return TtsSentenceNavigator.CLOSERS.indexOf(ch) >= 0;
  }

  private static isSpace(ch: string): boolean {
    return ch === ' ' || ch === '\t' || ch === '\r' || ch === '\n' || ch === '　' || ch === ' ';
  }

  /** 从 index 起跳过空白，返回第一个非空白字符的位置；到末尾返回 -1。 */
  private static skipSpaces(text: string, index: number): number {
    let i = Math.max(0, index);
    while (i < text.length && TtsSentenceNavigator.isSpace(text.charAt(i))) i++;
    return i < text.length ? i : -1;
  }

  /** index 所在句子的起点（跳过开头空白）。 */
  static sentenceStartAt(text: string, index: number): number {
    if (!text) return -1;
    let i = Math.max(0, Math.min(index, text.length - 1));
    // 落在句间空白里时归到下一句。
    if (TtsSentenceNavigator.isSpace(text.charAt(i))) {
      const next = TtsSentenceNavigator.skipSpaces(text, i);
      if (next >= 0) return next;
    }
    while (i > 0) {
      const ch = text.charAt(i - 1);
      if (TtsSentenceNavigator.isTerminator(ch)) break;
      // 句末后的引号、括号属于上一句：往前看能连到句末标点就停在这里。
      if (TtsSentenceNavigator.isCloser(ch)) {
        let j = i - 1;
        while (j > 0 && TtsSentenceNavigator.isCloser(text.charAt(j - 1))) j--;
        if (j > 0 && TtsSentenceNavigator.isTerminator(text.charAt(j - 1))) break;
      }
      i--;
    }
    const start = TtsSentenceNavigator.skipSpaces(text, i);
    return start >= 0 ? start : i;
  }

  /** index 所在句子的结尾（含句末标点和紧跟的引号、括号），返回结尾之后的位置。 */
  private static sentenceEndAfter(text: string, index: number): number {
    let i = Math.max(0, index);
    while (i < text.length && !TtsSentenceNavigator.isTerminator(text.charAt(i))) i++;
    while (i < text.length && TtsSentenceNavigator.isTerminator(text.charAt(i))) i++;
    while (i < text.length && TtsSentenceNavigator.isCloser(text.charAt(i))) i++;
    return i;
  }

  static nextSentenceStart(text: string, index: number): number {
    if (!text) return -1;
    const start = TtsSentenceNavigator.sentenceStartAt(text, index);
    return TtsSentenceNavigator.skipSpaces(text, TtsSentenceNavigator.sentenceEndAfter(text, Math.max(start, index)));
  }

  /**
   * 上一句：正读到一句中间（朗读块从句子中间开始）时先回到这一句开头；已在句首再退到上一句。
   */
  static previousSentenceStart(text: string, index: number): number {
    if (!text) return -1;
    const start = TtsSentenceNavigator.sentenceStartAt(text, index);
    if (start >= 0 && start < index) return start;
    let i = start - 1;
    while (i >= 0 && TtsSentenceNavigator.isSpace(text.charAt(i))) i--;
    if (i < 0) return -1;
    return TtsSentenceNavigator.sentenceStartAt(text, i);
  }

  private static paragraphStartAt(text: string, index: number): number {
    let i = Math.max(0, Math.min(index, text.length));
    while (i > 0 && text.charAt(i - 1) !== '\n') i--;
    const start = TtsSentenceNavigator.skipSpaces(text, i);
    return start >= 0 ? start : i;
  }

  static nextParagraphStart(text: string, index: number): number {
    if (!text) return -1;
    const lineEnd = text.indexOf('\n', Math.max(0, index));
    return lineEnd < 0 ? -1 : TtsSentenceNavigator.skipSpaces(text, lineEnd + 1);
  }

  /** 上一段：读到段落中间时先回到本段开头；已在段首再退到上一段开头。 */
  static previousParagraphStart(text: string, index: number): number {
    if (!text) return -1;
    const start = TtsSentenceNavigator.paragraphStartAt(text, index);
    if (start < index) return start;
    let i = start - 1;
    while (i >= 0 && TtsSentenceNavigator.isSpace(text.charAt(i))) i--;
    if (i < 0) return -1;
    return TtsSentenceNavigator.paragraphStartAt(text, i);
  }

  /** 本章最后一句的起点，从上一章开头退回时用。 */
  static lastSentenceStart(text: string): number {
    if (!text) return -1;
    let i = text.length - 1;
    while (i >= 0 && (TtsSentenceNavigator.isSpace(text.charAt(i)) || TtsSentenceNavigator.isCloser(text.charAt(i)) ||
      TtsSentenceNavigator.isTerminator(text.charAt(i)))) i--;
    return i < 0 ? -1 : TtsSentenceNavigator.sentenceStartAt(text, i);
  }

  /**
   * 面板上的文字压缩过空白（连续空格合一、换行两侧空白去掉），点按位置要换回原文位置。
   * clean 对前缀的结果长度随前缀变长不减，二分找到第一个压缩后长度达到 cleanedOffset 的原文位置。
   */
  static sourceOffsetForCleaned(slice: string, cleanedOffset: number, clean: (text: string) => string): number {
    let low = 0;
    let high = slice.length;
    while (low < high) {
      const mid = Math.floor((low + high) / 2);
      if (clean(slice.substring(0, mid)).length < cleanedOffset + 1) low = mid + 1;
      else high = mid;
    }
    return Math.max(0, Math.min(slice.length, low - 1));
  }
}
