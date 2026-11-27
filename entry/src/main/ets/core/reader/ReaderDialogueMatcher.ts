/**
 * 智能对话：逐字配对引号，找出正文里的对话，代替“对话”正则。
 *
 * - 一段之内按引号配对。“”、「」、『』、＂＂、"" 都算对话；「」里的『』、“”里的‘’只是对话内容。
 * - 跨段（crossParagraph）：中文排版里一人连说几段时，前几段只有前引号，最后一段才收引号。段末没收的引号，
 *   只有下一段也以同一种前引号开头时，才从前引号算到段末；否则不上色，漏掉一个后引号不会把整段旁白染掉。
 * - 纠正写反的引号（fixQuotes）：书源常见“你好“、”快走！”。对话里又遇到 “ 时，后面先出现 ”、且后面 ” 比 “ 多，
 *   按嵌套的引号算（“他说“走”就走了”）；否则把它当后引号。对话外遇到 ”、同段下一个弯引号也是 ” 时，把它当前引号。
 *   关掉时和原来的正则一样：对话里的 “ 只是内容，对话外的 ” 不管。
 * - 短引号不算对话（skipShort）：引号里不超过 SHORT_MAX 个字、没有句读标点，又不在段首、前面不是冒号或“说道问”
 *   一类字时，当作强调（招式名、称号），不算对话。偶尔会漏掉很短的对话，所以默认关。
 *
 * 结果是按起点排好的 [起, 止) 区间，含两侧引号；跨段的那一段止于段末（不含换行和段末空白）。
 */
export class ReaderDialogueOptions {
  crossParagraph: boolean = true;
  fixQuotes: boolean = true;
  skipShort: boolean = false;
}

const CURLY = 0;
const CORNER = 1;
const WHITE_CORNER = 2;
const ASCII = 3;
const FULL_WIDTH = 4;

const SHORT_MAX = 8;
const SENTENCE_MARKS = '，。！？…；：、,.!?;:～~—';
const SPEECH_LEAD = '：:说道问喊叫答笑骂吼嚷叹曰';

export class ReaderDialogueMatcher {
  /**
   * 旧版本应用读不懂智能对话，规则里仍存这条正则给它们用，效果接近：顺带处理跨段和写反的引号，不判断短引号。
   * 用户把匹配方式切回正则表达式时，输入框里显示的也是它。
   */
  static readonly FALLBACK_PATTERN: string =
    '“[^“”\\n]*(?:[”“]|(?=\\n[\\s\\u3000]*“))|”[^“”\\n]*”|「[^」\\n]*(?:」|(?=\\n[\\s\\u3000]*「))|' +
    '『[^』\\n]*』|"[^"\\n]*"|＂[^＂\\n]*＂';

  /** 以对话开头的段落：给“段首缩进”用，粘连匹配只试段首。 */
  static readonly LEADING_PATTERN: string = '[“”「『"＂]';

  static ranges(text: string, options: ReaderDialogueOptions): number[][] {
    const result: number[][] = [];
    const length = text.length;
    let lineStart = 0;
    while (lineStart <= length) {
      let lineEnd = text.indexOf('\n', lineStart);
      if (lineEnd < 0) lineEnd = length;
      ReaderDialogueMatcher.scanLine(text, lineStart, lineEnd, options, result);
      if (lineEnd >= length) break;
      lineStart = lineEnd + 1;
    }
    return result;
  }

  private static scanLine(text: string, start: number, end: number, options: ReaderDialogueOptions,
    out: number[][]): void {
    let kind = -1;
    let openAt = -1;
    let depth = 0;
    for (let index = start; index < end; index++) {
      const ch = text.charAt(index);
      if (kind < 0) {
        const opened = ReaderDialogueMatcher.openerKind(text, ch, index, end, options.fixQuotes);
        if (opened >= 0) {
          kind = opened;
          openAt = index;
          depth = 1;
        }
        continue;
      }
      const step = ReaderDialogueMatcher.innerStep(text, kind, ch, index, end, options.fixQuotes);
      if (step > 0) {
        depth++;
      } else if (step < 0) {
        depth--;
        if (depth === 0) {
          if (!options.skipShort || !ReaderDialogueMatcher.looksLikeEmphasis(text, start, openAt, index)) {
            out.push([openAt, index + 1]);
          }
          kind = -1;
        }
      }
    }
    if (kind >= 0 && options.crossParagraph && ReaderDialogueMatcher.nextLineOpens(text, end, kind,
      options.fixQuotes)) {
      let stop = end;
      while (stop > openAt + 1 && ReaderDialogueMatcher.isBlank(text.charAt(stop - 1))) stop--;
      out.push([openAt, stop]);
    }
  }

  private static openerKind(text: string, ch: string, index: number, end: number, fix: boolean): number {
    if (ch === '“') return CURLY;
    if (ch === '「') return CORNER;
    if (ch === '『') return WHITE_CORNER;
    if (ch === '"') return ASCII;
    if (ch === '＂') return FULL_WIDTH;
    if (ch === '”' && fix && ReaderDialogueMatcher.nextCurly(text, index + 1, end) === '”') return CURLY;
    return -1;
  }

  /** 对话里遇到的字：1 再套一层，-1 收一层，0 只是内容。 */
  private static innerStep(text: string, kind: number, ch: string, index: number, end: number, fix: boolean): number {
    switch (kind) {
      case CURLY:
        if (ch === '”') return -1;
        if (ch !== '“' || !fix) return 0;
        return ReaderDialogueMatcher.nestsAhead(text, index + 1, end) ? 1 : -1;
      case CORNER:
        return ch === '「' ? 1 : (ch === '」' ? -1 : 0);
      case WHITE_CORNER:
        return ch === '『' ? 1 : (ch === '』' ? -1 : 0);
      case ASCII:
        return ch === '"' ? -1 : 0;
      case FULL_WIDTH:
        return ch === '＂' ? -1 : 0;
      default:
        return 0;
    }
  }

  /** 对话里又遇到 “：后面先来的是 ”、且后面 ” 比 “ 多，才是嵌套的一层。 */
  private static nestsAhead(text: string, from: number, end: number): boolean {
    let opens = 0;
    let closes = 0;
    let first = '';
    for (let index = from; index < end; index++) {
      const ch = text.charAt(index);
      if (ch !== '“' && ch !== '”') continue;
      if (!first) first = ch;
      if (ch === '“') opens++;
      else closes++;
    }
    return first === '”' && closes > opens;
  }

  private static nextCurly(text: string, from: number, end: number): string {
    for (let index = from; index < end; index++) {
      const ch = text.charAt(index);
      if (ch === '“' || ch === '”') return ch;
    }
    return '';
  }

  private static nextLineOpens(text: string, end: number, kind: number, fix: boolean): boolean {
    let index = end + 1;
    while (index < text.length && ReaderDialogueMatcher.isBlank(text.charAt(index))) index++;
    if (index >= text.length) return false;
    const ch = text.charAt(index);
    switch (kind) {
      case CURLY:
        return ch === '“' || (fix && ch === '”');
      case CORNER:
        return ch === '「';
      case WHITE_CORNER:
        return ch === '『';
      case ASCII:
        return ch === '"';
      case FULL_WIDTH:
        return ch === '＂';
      default:
        return false;
    }
  }

  /** 引号里字少、没有句读，又不在段首、前面也不是冒号或说话的字：多半是招式名、称号这类强调。 */
  private static looksLikeEmphasis(text: string, lineStart: number, openAt: number, closeAt: number): boolean {
    const inner = closeAt - openAt - 1;
    if (inner < 1 || inner > SHORT_MAX) return false;
    for (let index = openAt + 1; index < closeAt; index++) {
      if (SENTENCE_MARKS.indexOf(text.charAt(index)) >= 0) return false;
    }
    let before = openAt - 1;
    while (before >= lineStart && ReaderDialogueMatcher.isBlank(text.charAt(before))) before--;
    if (before < lineStart) return false;
    return SPEECH_LEAD.indexOf(text.charAt(before)) < 0;
  }

  private static isBlank(ch: string): boolean {
    return ch === ' ' || ch === '\t' || ch === '\r' || ch === '　' || ch === ' ';
  }
}
