/**
 * 标点挤压：相邻两个全角标点之间的空白收掉一部分，例如“。”后接“」”、“，”后接“「”。
 *
 * 全角标点的字面只占字框的一半，另一半是空白；两个连在一起时会出现一个字宽左右的空隙，读起来松散。
 * 排版时给前一个标点设负字距（字距加在字符之后），把它右侧的空白和后一个标点左侧的空白一起收窄。
 * 收多少按当前字体里两个字形实际的空白量算，不按字形风格假定：标点居中的字体（如繁体习惯）空白少，
 * 收得少或不收；引号在字体里是窄字形时空白很小，自然不收。这样换字体也不会把字压到一起。
 *
 * 只处理相邻的成对标点；行首开引号的压缩会改变断行，不做。问号、叹号连用（“？！”“！！”）保持原样。
 */

/** 一个标点字形在字框里的空白，单位为字号（em）。 */
export interface ReaderGlyphSpace {
  /** 字面左侧到字框左边的空白。 */
  left: number;
  /** 字面右侧到字框右边的空白。 */
  right: number;
  /** 字框宽度。 */
  advance: number;
}

export class ReaderPunctuationSqueeze {
  /** 句读与闭合标点：字面通常在左半边。 */
  static readonly CLOSING: string = '、。，．：；！？）」』】》〉〕］｝”’';
  /** 开启标点：字面通常在右半边。 */
  static readonly OPENING: string = '（「『【《〈〔［｛“‘';
  /** 一次最多收掉的量。 */
  static readonly MAX_EM: number = 0.5;
  /** 两个字面之间至少留下的空白。 */
  static readonly MIN_GAP_EM: number = 0.2;
  /** 能收的量小于这个值时不收，避免为一点点差别切碎排版。 */
  static readonly MIN_SQUEEZE_EM: number = 0.12;
  /** 前一个标点的字框窄于这个宽度时不是全角字形，不收。 */
  static readonly FULL_WIDTH_EM: number = 0.8;

  static isPunctuation(char: string): boolean {
    return char.length === 1 && (ReaderPunctuationSqueeze.CLOSING.indexOf(char) >= 0 ||
      ReaderPunctuationSqueeze.OPENING.indexOf(char) >= 0);
  }

  private static readonly PAIR: RegExp = new RegExp(`[${ReaderPunctuationSqueeze.CLOSING}${ReaderPunctuationSqueeze.OPENING}]{2}`);

  /** [start, end) 内所有挤压对的前一个字的下标（两个字都要在范围内）。大多数段落没有成对标点，先整体判一次。 */
  static pairOwners(text: string, start: number, end: number): number[] {
    const owners: number[] = [];
    const from = Math.max(0, start);
    const to = Math.min(text.length, end);
    if (to - from < 2 || !ReaderPunctuationSqueeze.PAIR.test(text.substring(from, to))) return owners;
    for (let index = from; index + 1 < to; index++) {
      if (ReaderPunctuationSqueeze.ownsPair(text, index)) owners.push(index);
    }
    return owners;
  }

  /** text[index] 与下一个字是否构成可挤压的一对；是的话负字距加在 text[index] 上。 */
  static ownsPair(text: string, index: number): boolean {
    if (index < 0 || index + 1 >= text.length) return false;
    const prev = text[index];
    const next = text[index + 1];
    if (!ReaderPunctuationSqueeze.isPunctuation(prev) || !ReaderPunctuationSqueeze.isPunctuation(next)) return false;
    return !(ReaderPunctuationSqueeze.isMark(prev) && ReaderPunctuationSqueeze.isMark(next));
  }

  /** 按两个字形的实际空白算出要收掉的量（em），0 表示不收。 */
  static squeezeEm(prev: ReaderGlyphSpace | null, next: ReaderGlyphSpace | null): number {
    if (!prev || !next || prev.advance < ReaderPunctuationSqueeze.FULL_WIDTH_EM) return 0;
    // 不超过前一个字形自身右侧的空白：前一个标点落在行尾时，字面仍留在版心里。
    const amount = Math.min(ReaderPunctuationSqueeze.MAX_EM, prev.right,
      prev.right + next.left - ReaderPunctuationSqueeze.MIN_GAP_EM);
    return amount >= ReaderPunctuationSqueeze.MIN_SQUEEZE_EM ? amount : 0;
  }

  private static isMark(char: string): boolean {
    return char === '！' || char === '？';
  }
}
