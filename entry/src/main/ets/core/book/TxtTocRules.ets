import { JavaRegexCompat } from '@legado/sourceengine';

/**
 * 本地 TXT 的分章规则。
 * - regex：逐行去掉首尾空白后用正则判断，匹配的行就是章节标题；
 * - unindented：没有缩进、不长、不以标点结尾的行当标题；
 * - words：不找标题，按字数切章，标题取每章开头一句。
 * 每本书只在变量里记规则引用（见 TxtTocRules.ref），规则本身全局保存。
 */
export class TxtTocRule {
  id: string = '';
  name: string = '';
  desc: string = '';
  pattern: string = '';
  example: string = '';
  kind: string = 'regex';
  builtin: boolean = false;
  enabled: boolean = true;
  maxTitleLength: number = 50;
  ignoreCase: boolean = true;
}

/** 一条规则加上按字数分章时的字数，就是一本书实际用来分章的设定。 */
export class TxtTocResolvedRule {
  rule: TxtTocRule = new TxtTocRule();
  wordsPerChapter: number = 10000;
}

export class TxtTocRules {
  static readonly KIND_REGEX: string = 'regex';
  static readonly KIND_UNINDENTED: string = 'unindented';
  static readonly KIND_WORDS: string = 'words';
  static readonly AUTO_ID: string = 'auto';
  static readonly WORDS_ID: string = 'words';
  static readonly CUSTOM_PREFIX: string = 'custom-';
  static readonly DEFAULT_MAX_TITLE_LENGTH: number = 50;
  static readonly DEFAULT_WORDS_PER_CHAPTER: number = 10000;
  static readonly WORD_OPTIONS: number[] = [5000, 10000, 20000];
  /** 不到这么多字的章节算“短章”，短章太多通常说明把正文认成了标题。 */
  static readonly SHORT_CHAPTER_CHARS: number = 300;

  /** 默认规则；也是规则被删掉后的退路。 */
  static readonly AUTO_PATTERN: string =
    '^(?:扉页|正文|目录|[序引前楔][言子]?|(?:内容|文章|书籍|作品|作者)?简介|作品相关|后记|尾声|' +
    '卷[首尾末](?:语|总结|感言)|最?[上中下序引终末][章卷篇幕回节册季话集]|' +
    '第\\s*[\\dO零〇一两二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬]{1,12}\\s*' +
    '[章卷页季回幕册话段篇节集部](?:\\s+|[：:、._—-]\\s*)?.{0,30}|' +
    '[\\dO零〇一两二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬]{1,12}\\s*' +
    '[章卷页季回幕册话段篇节集部](?:(?:\\s+|[：:、._—-]\\s*).{1,30})?|' +
    '[章卷篇节幕回册话段季集部]\\s*[\\dO零〇一两二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬]{1,12}' +
    '(?:\\s+|[：:、._—-]\\s*)?.{0,30}|' +
    '[\\dO零〇一两二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬]{1,12}\\s*[｜、_|：:；;–.·—-]\\s*' +
    '[^\\s].{0,30}|(?:chapter|part|volume|book)\\s+[0-9ivxlcdm]+(?:\\s+|[：:._—-]\\s*)?.{0,30}|' +
    '[-·.–—_*＊~～=]{2,}\\s*.{1,35}\\s*[-·.–—_*＊~～=]{2,})$';

  /** 只有标点和空白的行永远不当标题（分隔线、省略号行）。 */
  static readonly PUNCTUATION_ONLY_PATTERN: string =
    '^[\\s\\u0000-\\u001F\\u007F-\\u009F\\x21-\\x2F\\x3A-\\x40\\x5B-\\x60\\x7B-\\x7E' +
    '\\u2000-\\u206F\\u2100-\\u2BFF\\u2E00-\\u2E7F\\u3000-\\u303F\\uFE10-\\uFE1F' +
    '\\uFE30-\\uFE4F\\uFF01-\\uFF0F\\uFF1A-\\uFF20\\uFF3B-\\uFF40\\uFF5B-\\uFF65]+$';

  private static readonly NUMERALS: string = '\\d零〇一两二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬';

  static builtins(): TxtTocRule[] {
    const n = TxtTocRules.NUMERALS;
    return [
      TxtTocRules.builtin(TxtTocRules.AUTO_ID, '智能识别', '常见的「第X章/卷」、序章尾声、数字序号、符号标题都认',
        TxtTocRules.KIND_REGEX, TxtTocRules.AUTO_PATTERN, '第一章 旧城来信', 50),
      TxtTocRules.builtin('strict', '只认「第…章」', '第X章/回/卷/节，加上序章、楔子、尾声；正文有列表时用它',
        TxtTocRules.KIND_REGEX,
        `^(?:(?:序章|序言|序幕|楔子|引子|尾声|后记|终章|番外)(?:\\s+.{0,30}|[：:、]\\s*.{0,30})?|` +
          `第\\s*[${n}]{1,12}\\s*(?:[章回卷篇幕]|节(?!课)|集(?![合中体团])|部(?![分门队]))` +
          `(?:\\s+|[：:、._—-]\\s*)?.{0,30})$`,
        '第十二章 潮汐表', 50),
      TxtTocRules.builtin('number', '数字序号', '「001 标题」「12. 标题」「3、标题」这类行',
        TxtTocRules.KIND_REGEX, '^[0-9０-９]{1,5}\\s*(?:[、.．:：_—-]\\s*|\\s+)[^\\s0-9０-９].{0,30}$', '12. 潮汐表', 40),
      TxtTocRules.builtin('english', '英文 Chapter', 'Chapter 1、Part II、Volume 3',
        TxtTocRules.KIND_REGEX,
        '^(?:(?:chapter|part|volume|book|section|episode)\\s*(?:[0-9]+|[ivxlcdm]+)\\b|prologue|epilogue)' +
          '(?:\\s+|[：:._—-]\\s*)?.{0,40}$',
        'Chapter 12 The Tide', 60),
      TxtTocRules.builtin('symbol', '符号包裹', '【标题】、===标题===、☆标题☆',
        TxtTocRules.KIND_REGEX,
        '^(?:【[^【】]{1,30}】|〖[^〖〗]{1,30}〗|[☆★◆◇]\\s*[^☆★◆◇]{1,30}?\\s*[☆★◆◇]|' +
          '[=＝\\-—~～*＊#]{2,}\\s*[^=＝\\-—~～*＊#]{1,30}?\\s*[=＝\\-—~～*＊#]{2,})$',
        '【潮汐表】', 40),
      TxtTocRules.builtin('unindented', '顶格短行', '不缩进、20 字以内、不以标点结尾的行；适合排版规整的书',
        TxtTocRules.KIND_UNINDENTED, '', '潮汐表', 20),
      TxtTocRules.builtin(TxtTocRules.WORDS_ID, '按字数分章', '书里没有章节标题时用，每 N 字切一章，标题取章首句',
        TxtTocRules.KIND_WORDS, '', '', 0)
    ];
  }

  private static builtin(id: string, name: string, desc: string, kind: string, pattern: string, example: string,
    maxTitleLength: number): TxtTocRule {
    const rule = new TxtTocRule();
    rule.id = id;
    rule.name = name;
    rule.desc = desc;
    rule.kind = kind;
    rule.pattern = pattern;
    rule.example = example;
    rule.builtin = true;
    rule.maxTitleLength = maxTitleLength;
    rule.ignoreCase = true;
    return rule;
  }

  /** 书里保存的规则引用：按字数分章带上字数（words:10000），其他就是规则 id，空串表示默认。 */
  static ref(ruleId: string, wordsPerChapter: number = TxtTocRules.DEFAULT_WORDS_PER_CHAPTER): string {
    if (ruleId === TxtTocRules.WORDS_ID) return `${TxtTocRules.WORDS_ID}:${TxtTocRules.normalizeWords(wordsPerChapter)}`;
    return ruleId === TxtTocRules.AUTO_ID ? '' : ruleId;
  }

  static ruleIdOf(ref: string): string {
    const value = (ref || '').trim();
    if (!value) return TxtTocRules.AUTO_ID;
    const colon = value.indexOf(':');
    return colon > 0 ? value.substring(0, colon) : value;
  }

  static wordsOf(ref: string): number {
    const value = (ref || '').trim();
    const colon = value.indexOf(':');
    if (colon < 0) return TxtTocRules.DEFAULT_WORDS_PER_CHAPTER;
    return TxtTocRules.normalizeWords(Number(value.substring(colon + 1)));
  }

  static normalizeWords(value: number): number {
    if (!Number.isFinite(value) || value <= 0) return TxtTocRules.DEFAULT_WORDS_PER_CHAPTER;
    return Math.min(30000, Math.max(1000, Math.round(value)));
  }

  static wordsLabel(words: number): string {
    return words >= 10000 && words % 10000 === 0 ? `${words / 10000} 万字` :
      words % 1000 === 0 ? `${words / 1000} 千字` : `${words} 字`;
  }

  /** 菜单和弹窗里显示的规则名；按字数分章带上字数。 */
  static displayName(rule: TxtTocRule, wordsPerChapter: number): string {
    return rule.kind === TxtTocRules.KIND_WORDS ? `${rule.name} · ${TxtTocRules.wordsLabel(wordsPerChapter)}` : rule.name;
  }

  static newCustomRule(): TxtTocRule {
    const rule = new TxtTocRule();
    rule.id = `${TxtTocRules.CUSTOM_PREFIX}${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;
    rule.kind = TxtTocRules.KIND_REGEX;
    rule.maxTitleLength = TxtTocRules.DEFAULT_MAX_TITLE_LENGTH;
    rule.ignoreCase = true;
    return rule;
  }

  static clone(source: TxtTocRule): TxtTocRule {
    const rule = new TxtTocRule();
    rule.id = source.id;
    rule.name = source.name;
    rule.desc = source.desc;
    rule.pattern = source.pattern;
    rule.example = source.example;
    rule.kind = source.kind;
    rule.builtin = source.builtin;
    rule.enabled = source.enabled;
    rule.maxTitleLength = source.maxTitleLength;
    rule.ignoreCase = source.ignoreCase;
    return rule;
  }

  /** 规则正则写错时返回给用户看的原因，正确返回空串。 */
  static patternError(pattern: string): string {
    const value = (pattern || '').trim();
    if (!value) return '请填写标题正则';
    try {
      JavaRegexCompat.compile(value, '');
      return '';
    } catch (e) {
      const message = (e as Error)?.message || '';
      return message ? `正则写法有误：${message}` : '正则写法有误';
    }
  }

  /**
   * 读入导入的规则。兼容安卓阅读的 txtTocRule 格式（name / rule / example / enable），
   * 也认本应用导出时多带的 maxTitleLength、ignoreCase。读不出正则的返回 null。
   */
  static fromImport(raw: Record<string, Object>): TxtTocRule | null {
    if (!raw || typeof raw !== 'object') return null;
    const pattern = TxtTocRules.text(raw['rule'] ?? raw['pattern']).trim();
    if (!pattern) return null;
    const rule = TxtTocRules.newCustomRule();
    rule.name = TxtTocRules.text(raw['name']).trim() || '导入的规则';
    rule.pattern = pattern;
    rule.example = TxtTocRules.text(raw['example']).trim();
    rule.enabled = raw['enable'] !== false && raw['enabled'] !== false;
    const maxLength = Number(raw['maxTitleLength']);
    if (Number.isFinite(maxLength) && maxLength > 0) rule.maxTitleLength = Math.min(200, Math.round(maxLength));
    if (raw['ignoreCase'] === false) rule.ignoreCase = false;
    return rule;
  }

  static toExport(rule: TxtTocRule, serialNumber: number): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['id'] = serialNumber;
    result['name'] = rule.name;
    result['rule'] = rule.pattern;
    result['example'] = rule.example;
    result['serialNumber'] = serialNumber;
    result['enable'] = rule.enabled;
    result['maxTitleLength'] = rule.maxTitleLength;
    result['ignoreCase'] = rule.ignoreCase;
    return result;
  }

  private static text(value: Object | undefined | null): string {
    if (value === undefined || value === null) return '';
    return typeof value === 'string' ? value : `${value}`;
  }
}

/** 按一条规则判断某一行是不是章节标题。 */
export class TxtChapterMatcher {
  readonly kind: string;
  readonly wordsPerChapter: number;
  private readonly regex: RegExp | null;
  private readonly maxTitleLength: number;
  private readonly punctuationOnly: RegExp = new RegExp(TxtTocRules.PUNCTUATION_ONLY_PATTERN);
  private static readonly UNINDENTED_TRAILING_PUNCTUATION: RegExp =
    /[。，、；：！？…”’」』）)\].,;:!?~～—-]$/;
  private static readonly INDENT: RegExp = /^[\s\u3000\u00A0]/;

  constructor(resolved: TxtTocResolvedRule) {
    const rule = resolved.rule;
    this.kind = rule.kind;
    this.wordsPerChapter = TxtTocRules.normalizeWords(resolved.wordsPerChapter);
    this.maxTitleLength = rule.maxTitleLength > 0 ? rule.maxTitleLength : TxtTocRules.DEFAULT_MAX_TITLE_LENGTH;
    if (rule.kind !== TxtTocRules.KIND_REGEX) {
      this.regex = null;
    } else if (rule.builtin) {
      this.regex = new RegExp(rule.pattern, rule.ignoreCase ? 'i' : '');
    } else {
      // 自定义规则多半来自安卓阅读，按 Java 正则语法转换。
      this.regex = JavaRegexCompat.compile(rule.pattern, rule.ignoreCase ? 'i' : '');
    }
  }

  isWordSplit(): boolean {
    return this.kind === TxtTocRules.KIND_WORDS;
  }

  /** rawLine 是原始行（已去掉行尾 \r），candidate 是去掉零宽字符和首尾空白后的行。 */
  isTitle(rawLine: string, candidate: string): boolean {
    if (this.kind === TxtTocRules.KIND_WORDS) return false;
    if (!candidate || candidate.length > this.maxTitleLength || this.punctuationOnly.test(candidate)) return false;
    if (this.kind === TxtTocRules.KIND_UNINDENTED) {
      const line = rawLine.replace(/^[\u200B-\u200D\u2060\uFEFF]+/, '');
      return !TxtChapterMatcher.INDENT.test(line) &&
        !TxtChapterMatcher.UNINDENTED_TRAILING_PUNCTUATION.test(candidate);
    }
    if (!this.regex) return false;
    this.regex.lastIndex = 0;
    return this.regex.test(candidate);
  }
}
