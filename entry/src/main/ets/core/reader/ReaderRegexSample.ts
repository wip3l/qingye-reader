/**
 * 按正则表达式拼一段会被它命中的文字，给正则规则的预览用：预览里有了命中，强调效果（气泡、文字色等）才看得到。
 *
 * 只认阅读页用的 JS 正则写法（`new RegExp(pattern, 'g')`，不带 u 标志）里的常见部分：字符、字符集、`.`、
 * 常用转义、分组与分支、量词、反向引用；行首行尾、单词边界和前后断言不产出文字。拼法偏向能读的样子：
 * 字符集优先挑中文和常见字，`.`、反选字符集这类“什么都行”的位置用一小段词填，可选部分一律带上。
 * 拼出的文字不保证在任何上下文里都命中（断言、行首条件要看前后文），调用方用 `placements` 给出的几种放法
 * 逐个用真正则核对，取第一个命中的。
 */

/** “什么都行”的位置依次取这些字，例如 `“[^”]*”` 拼成“重逢”。 */
const FILLER = '重逢故人归来';
/** 字符集里优先挑的字：中文数字、常用字，再是字母数字、空格和标点。 */
const PREFERRED = '一十二三章节回卷部篇集第文字的了重逢aA1 0，。';
const FILLER_ASCII = 'text';

/** 最长多少字；超了算拼不出，免得 {100} 之类撑满预览。 */
const MAX_LENGTH = 40;

class CharSet {
  ranges: number[][] = [];
  negated: boolean = false;

  add(lo: number, hi: number): void {
    this.ranges.push([lo, hi]);
  }

  has(code: number): boolean {
    let inside = false;
    for (const range of this.ranges) {
      if (code >= range[0] && code <= range[1]) {
        inside = true;
        break;
      }
    }
    return this.negated ? !inside : inside;
  }
}

/** 一个可重复的单元：pick(i) 给第 i 次重复的文字；wide 表示“什么都行”，重复时多填几个字更像样。 */
class Atom {
  pick: (index: number) => string;
  wide: boolean;
  zeroWidth: boolean;

  constructor(pick: (index: number) => string, wide: boolean = false, zeroWidth: boolean = false) {
    this.pick = pick;
    this.wide = wide;
    this.zeroWidth = zeroWidth;
  }
}

class SampleParser {
  private src: string;
  private pos: number = 0;
  private groups: string[] = [];
  private groupNames: Map<string, number> = new Map<string, number>();
  private groupCount: number = 0;
  failed: boolean = false;

  constructor(src: string) {
    this.src = src;
  }

  run(): string {
    const text = this.alternation();
    if (this.pos < this.src.length) this.failed = true;
    return text;
  }

  private peek(offset: number = 0): string {
    return this.src.charAt(this.pos + offset);
  }

  private alternation(): string {
    let chosen: string | null = null;
    while (true) {
      const text = this.sequence();
      // 选第一个产出文字的分支；全都只产出空串时也认空串。
      if (chosen === null || (chosen === '' && text !== '')) chosen = text;
      if (this.peek() !== '|') break;
      this.pos++;
    }
    return chosen === null ? '' : chosen;
  }

  private sequence(): string {
    let text = '';
    while (this.pos < this.src.length && this.peek() !== '|' && this.peek() !== ')') {
      text += this.term();
      if (this.failed || text.length > MAX_LENGTH) {
        this.failed = true;
        return text;
      }
    }
    return text;
  }

  private term(): string {
    const atom = this.atom();
    if (this.failed) return '';
    const count = this.quantifier(atom);
    if (atom.zeroWidth) return '';
    if (count > MAX_LENGTH) {
      this.failed = true;
      return '';
    }
    let text = '';
    for (let i = 0; i < count; i++) text += atom.pick(i);
    return text;
  }

  /** 读量词并定下重复几次：可选部分带上一次，“什么都行”的位置填两个字，其余取下限。 */
  private quantifier(atom: Atom): number {
    const ch = this.peek();
    let min = 1;
    let max = 1;
    let optional = false;
    if (ch === '*') {
      min = 0; max = Infinity; this.pos++;
    } else if (ch === '+') {
      min = 1; max = Infinity; this.pos++;
    } else if (ch === '?') {
      min = 0; max = 1; optional = true; this.pos++;
    } else if (ch === '{') {
      const match = /^\{(\d+)(,(\d*))?\}/.exec(this.src.substring(this.pos));
      if (!match) return 1; // 不成量词的 { 按普通字符，已在 atom 里处理过
      min = Number(match[1]);
      max = match[2] === undefined ? min : (match[3] ? Number(match[3]) : Infinity);
      this.pos += match[0].length;
    } else {
      return 1;
    }
    if (this.peek() === '?') this.pos++; // 非贪婪
    if (optional) return 1;
    if (atom.wide) return Math.max(min, Math.min(2, max));
    return min;
  }

  private atom(): Atom {
    const ch = this.peek();
    if (ch === '^' || ch === '$') {
      this.pos++;
      return new Atom((): string => '', false, true);
    }
    if (ch === '(') return this.group();
    if (ch === '[') return this.charClassAtom();
    if (ch === '.') {
      this.pos++;
      return SampleParser.fromSet(SampleParser.negatedOf([[0x0A, 0x0A], [0x0D, 0x0D], [0x2028, 0x2029]]));
    }
    if (ch === '\\') return this.escapeAtom();
    if (ch === ')' || ch === '*' || ch === '+' || ch === '?') {
      this.failed = true;
      return new Atom((): string => '');
    }
    this.pos++;
    return new Atom((): string => ch);
  }

  private group(): Atom {
    this.pos++; // (
    let capture = true;
    let lookaround = false;
    let name = '';
    if (this.peek() === '?') {
      const rest = this.src.substring(this.pos, this.pos + 3);
      if (rest.startsWith('?:')) {
        capture = false; this.pos += 2;
      } else if (rest.startsWith('?=') || rest.startsWith('?!')) {
        capture = false; lookaround = true; this.pos += 2;
      } else if (rest === '?<=' || rest === '?<!') {
        capture = false; lookaround = true; this.pos += 3;
      } else {
        const named = /^\?<([A-Za-z_$][\w$]*)>/.exec(this.src.substring(this.pos));
        if (!named) {
          this.failed = true;
          return new Atom((): string => '');
        }
        name = named[1];
        this.pos += named[0].length;
      }
    }
    let index = -1;
    if (capture) {
      index = ++this.groupCount;
      if (name) this.groupNames.set(name, index);
    }
    const text = this.alternation();
    if (this.peek() !== ')') {
      this.failed = true;
      return new Atom((): string => '');
    }
    this.pos++;
    if (lookaround) return new Atom((): string => '', false, true);
    if (index > 0) this.groups[index] = text;
    return new Atom((): string => text);
  }

  private charClassAtom(): Atom {
    this.pos++; // [
    const set = new CharSet();
    if (this.peek() === '^') {
      set.negated = true;
      this.pos++;
    }
    let first = true;
    while (this.pos < this.src.length && (this.peek() !== ']' || first)) {
      first = false;
      const lo = this.classUnit(set);
      if (lo < 0) continue; // \d 之类已整段加入
      if (this.peek() === '-' && this.peek(1) !== ']' && this.peek(1) !== '') {
        this.pos++;
        const hi = this.classUnit(set);
        if (hi < 0) {
          set.add(lo, lo);
          set.add(0x2D, 0x2D);
        } else {
          set.add(Math.min(lo, hi), Math.max(lo, hi));
        }
      } else {
        set.add(lo, lo);
      }
    }
    if (this.peek() !== ']') {
      this.failed = true;
      return new Atom((): string => '');
    }
    this.pos++;
    return SampleParser.fromSet(set);
  }

  /** 字符集里的一个字，返回编码；遇到 \d、\w、\s 这类整类时直接加进 set，返回 -1。 */
  private classUnit(set: CharSet): number {
    const ch = this.peek();
    if (ch !== '\\') {
      this.pos++;
      return ch.charCodeAt(0);
    }
    const next = this.peek(1);
    const classRanges = SampleParser.classEscape(next);
    if (classRanges) {
      this.pos += 2;
      for (const range of classRanges) set.add(range[0], range[1]);
      return -1;
    }
    if (next === 'b') {
      this.pos += 2;
      return 0x08;
    }
    return this.escapedCode();
  }

  private escapeAtom(): Atom {
    const next = this.peek(1);
    if (next === 'b' || next === 'B') {
      this.pos += 2;
      return new Atom((): string => '', false, true);
    }
    if (next === 'd') {
      this.pos += 2;
      return new Atom((i: number): string => '1234567890'.charAt(i % 10));
    }
    if (next === 's') {
      this.pos += 2;
      return new Atom((): string => ' ');
    }
    if (next === 'w') {
      this.pos += 2;
      return new Atom((i: number): string => FILLER_ASCII.charAt(i % FILLER_ASCII.length), true);
    }
    if (next === 'D' || next === 'S' || next === 'W') {
      this.pos += 2;
      return SampleParser.fromSet(SampleParser.negatedOf(SampleParser.classEscape(next.toLowerCase()) || []));
    }
    if (next >= '1' && next <= '9') {
      const digits = /^\d+/.exec(this.src.substring(this.pos + 1));
      const ref = Number(digits ? digits[0] : next);
      if (ref <= this.groupCount) {
        this.pos += 1 + (digits ? digits[0].length : 1);
        const text = this.groups[ref] || '';
        return new Atom((): string => text);
      }
    }
    if (next === 'k') {
      const named = /^k<([A-Za-z_$][\w$]*)>/.exec(this.src.substring(this.pos + 1));
      if (named && this.groupNames.has(named[1])) {
        this.pos += 1 + named[0].length;
        const text = this.groups[this.groupNames.get(named[1]) as number] || '';
        return new Atom((): string => text);
      }
    }
    const code = this.escapedCode();
    const text = String.fromCharCode(code);
    return new Atom((): string => text);
  }

  /** 读一个转义成的单个字符（\n、　、\x41、\. 等），pos 停在它后面。 */
  private escapedCode(): number {
    const next = this.peek(1);
    const rest = this.src.substring(this.pos + 2);
    this.pos += 2;
    switch (next) {
      case 'n': return 0x0A;
      case 'r': return 0x0D;
      case 't': return 0x09;
      case 'v': return 0x0B;
      case 'f': return 0x0C;
      case '0': return 0x00;
      case 'x': {
        const hex = /^[0-9A-Fa-f]{2}/.exec(rest);
        if (hex) {
          this.pos += 2;
          return parseInt(hex[0], 16);
        }
        return 0x78;
      }
      case 'u': {
        const hex = /^[0-9A-Fa-f]{4}/.exec(rest);
        if (hex) {
          this.pos += 4;
          return parseInt(hex[0], 16);
        }
        return 0x75;
      }
      case 'c': {
        const letter = /^[A-Za-z]/.exec(rest);
        if (letter) {
          this.pos += 1;
          return letter[0].toUpperCase().charCodeAt(0) - 64;
        }
        this.pos -= 1; // \c 后面不是字母时按反斜杠本身
        return 0x5C;
      }
      case '':
        this.failed = true;
        return 0x5C;
      default:
        return next.charCodeAt(0);
    }
  }

  private static classEscape(letter: string): number[][] | null {
    if (letter === 'd') return [[0x30, 0x39]];
    if (letter === 'w') return [[0x30, 0x39], [0x41, 0x5A], [0x5F, 0x5F], [0x61, 0x7A]];
    if (letter === 's') {
      return [[0x09, 0x0D], [0x20, 0x20], [0xA0, 0xA0], [0x1680, 0x1680], [0x2000, 0x200A],
        [0x2028, 0x2029], [0x202F, 0x202F], [0x205F, 0x205F], [0x3000, 0x3000], [0xFEFF, 0xFEFF]];
    }
    return null;
  }

  private static negatedOf(ranges: number[][]): CharSet {
    const set = new CharSet();
    set.negated = true;
    for (const range of ranges) set.add(range[0], range[1]);
    return set;
  }

  /** 字符集挑字：先挑填充词里的字（能接受两个以上就算“什么都行”），再挑常用字，最后取第一个能显示的字。 */
  private static fromSet(set: CharSet): Atom {
    const choices: string[] = [];
    let fillerHits = 0;
    for (const ch of FILLER) {
      if (set.has(ch.charCodeAt(0))) {
        choices.push(ch);
        fillerHits++;
      }
    }
    for (const ch of PREFERRED) {
      if (set.has(ch.charCodeAt(0)) && choices.indexOf(ch) < 0) choices.push(ch);
    }
    if (choices.length === 0) {
      const fallback = SampleParser.firstPrintable(set);
      if (fallback >= 0) choices.push(String.fromCharCode(fallback));
    }
    if (choices.length === 0) return new Atom((): string => '\u0000');
    return new Atom((i: number): string => choices[i % choices.length], fillerHits >= 2);
  }

  private static firstPrintable(set: CharSet): number {
    if (!set.negated) {
      for (const range of set.ranges) {
        for (let code = range[0]; code <= range[1] && code <= range[0] + 256; code++) {
          if (SampleParser.printable(code)) return code;
        }
      }
      // 只含不可见字符的集合（如 [\t\n]）也照取第一个，至少能命中。
      return set.ranges.length > 0 ? set.ranges[0][0] : -1;
    }
    for (let code = 0x21; code < 0x3000; code++) {
      if (set.has(code) && SampleParser.printable(code)) return code;
    }
    return -1;
  }

  private static printable(code: number): boolean {
    return code > 0x20 && !(code >= 0x7F && code <= 0xA0) && !(code >= 0xD800 && code <= 0xDFFF);
  }
}

export class ReaderRegexSample {
  static readonly LEAD_LINE: string = '他合上书页，窗外的雨还没停。';
  static readonly TAIL_LINE: string = '门被推开，风卷着潮气涌进来。';

  /** 拼一段会被 pattern 命中的文字；写法不认识、超长或只产出空串时返回 ''。 */
  static generate(pattern: string): string {
    const source = (pattern || '').trim();
    if (!source) return '';
    const parser = new SampleParser(source);
    const text = parser.run();
    if (parser.failed || !text || text.length > MAX_LENGTH || text.indexOf('\u0000') >= 0) return '';
    return text;
  }

  /**
   * 样例放进预览正文的几种放法（每项是多行正文）：嵌在句中、单独一行、段首、段尾。
   * 要求独占一行、紧跟行首的正则只有后几种能命中，调用方逐个核对。
   */
  static placements(sample: string): string[] {
    const lead = ReaderRegexSample.LEAD_LINE;
    const tail = ReaderRegexSample.TAIL_LINE;
    return [
      `${lead}\n门被推开，${sample}，风卷着潮气涌进来。`,
      `${lead}\n${sample}\n${tail}`,
      `${lead}\n${sample}风卷着潮气涌进来。`,
      `他合上书页，${sample}\n${tail}`
    ];
  }
}
