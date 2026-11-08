/**
 * 简繁同搜：按书源自己的用字（简体站/繁体站）发对应写法的关键词，比对和合并时统一折成简体。
 *
 * 每个书源只在不知道用字时才可能多发一次：先发用户输入的原词，没有相关结果再换另一种写法补搜。
 * 搜完按返回书名的简繁字比例判断站点用字记下来（判断不出时，记下“搜出相关结果的那种写法”），下次只发一次。
 * 字典由宿主注入（AI 引擎里的 OpenCC 字典），这里只依赖两个转换方法，方便 Node 回归直接跑。
 */
export interface ChineseScriptConverter {
  /** 繁→简，结果与原文等长逐位对齐。 */
  toSimplified(text: string): string;
  /** 简→繁（台湾用字）。 */
  toTraditional(text: string): string;
}

/** 只取判断用字需要的书源字段，BookSource 直接满足。 */
export interface SearchScriptSource {
  bookSourceUrl: string;
  bookSourceName?: string;
  bookSourceGroup?: string;
}

/** 结果里判断站点用字需要的字段，SearchBook 直接满足。 */
export interface SearchScriptBook {
  name?: string;
  author?: string;
}

export class SearchKeywordVariants {
  original: string = '';
  simplified: string = '';
  traditional: string = '';
  /** 's' 输入是简体写法；'t' 输入里有繁体字；'' 没有简繁差异（英文、数字、简繁同形），搜索照旧。 */
  inputScript: string = '';

  hasVariant(): boolean {
    return this.inputScript !== '';
  }

  /** 进度行显示的“另一种写法”。 */
  other(): string {
    if (this.inputScript === SearchChineseScript.TRADITIONAL) return this.simplified;
    if (this.inputScript === SearchChineseScript.SIMPLIFIED) return this.traditional;
    return '';
  }

  forScript(script: string): string {
    return script === SearchChineseScript.TRADITIONAL ? this.traditional : this.simplified;
  }
}

/** 一个书源要发的关键词：second 非空表示 first 没有相关结果时补搜。 */
export class SearchSourcePlan {
  first: string = '';
  firstScript: string = '';
  second: string = '';
  secondScript: string = '';
}

export class SearchChineseScript {
  static readonly SIMPLIFIED: string = 's';
  static readonly TRADITIONAL: string = 't';
  /** 书源名或分组明说是繁体/台港站的，第一次就按繁体站发。 */
  private static readonly TRADITIONAL_SOURCE_NAME: RegExp =
    /繁體|繁体|正體|正体|台灣|台湾|香港|[（(【\[]繁[）)】\]]|(^|[^a-z])(tw|hk)([^a-z]|$)/i;
  /** 判断站点用字至少要这么多个“只有一种写法才有”的字，避免一两个异体字误判。 */
  private static readonly MIN_SIGNAL: number = 2;
  private static readonly CLASSIFY_BOOKS: number = 20;
  private static readonly FOLD_CACHE_LIMIT: number = 4000;

  private readonly converter: ChineseScriptConverter;
  /** 书源地址 → 's' / 't'，由宿主持久化；这里改动后 changed 置位。 */
  private readonly hints: Map<string, string>;
  private readonly foldCache: Map<string, string> = new Map();
  private changed: boolean = false;

  constructor(converter: ChineseScriptConverter, hints: Map<string, string>) {
    this.converter = converter;
    this.hints = hints;
  }

  variants(keyword: string): SearchKeywordVariants {
    const result = new SearchKeywordVariants();
    const original = keyword || '';
    result.original = original;
    result.simplified = original;
    result.traditional = original;
    if (!original) return result;
    const simplified = this.converter.toSimplified(original);
    if (simplified !== original) {
      // 用户输入的繁体照原样发给繁体站，不再按台湾用字改写。
      result.inputScript = SearchChineseScript.TRADITIONAL;
      result.simplified = simplified;
      return result;
    }
    const traditional = this.converter.toTraditional(original);
    if (traditional !== original) {
      result.inputScript = SearchChineseScript.SIMPLIFIED;
      result.traditional = traditional;
    }
    return result;
  }

  plan(source: SearchScriptSource, variants: SearchKeywordVariants): SearchSourcePlan {
    const plan = new SearchSourcePlan();
    plan.first = variants.original;
    if (!variants.hasVariant()) return plan;
    const known = this.scriptOf(source);
    if (known) {
      plan.first = variants.forScript(known);
      plan.firstScript = known;
      return plan;
    }
    const other = variants.inputScript === SearchChineseScript.TRADITIONAL ?
      SearchChineseScript.SIMPLIFIED : SearchChineseScript.TRADITIONAL;
    plan.firstScript = variants.inputScript;
    plan.second = variants.forScript(other);
    plan.secondScript = other;
    return plan;
  }

  /** 已记住的用字，没有记住时看书源名；都没有返回 ''。 */
  scriptOf(source: SearchScriptSource): string {
    const known = this.hints.get(source.bookSourceUrl || '') || '';
    if (known === SearchChineseScript.SIMPLIFIED || known === SearchChineseScript.TRADITIONAL) return known;
    return SearchChineseScript.nameHint(source.bookSourceName || '', source.bookSourceGroup || '');
  }

  /**
   * 搜完一个书源后调用。books 是它返回的全部结果（不只相关的，书名用字同样说明站点用字）；
   * workedScript 是搜出相关结果的那种写法，没有相关结果时传 ''。
   */
  learn(source: SearchScriptSource, books: SearchScriptBook[], workedScript: string): void {
    const url = source.bookSourceUrl || '';
    if (!url) return;
    const texts: string[] = [];
    for (let index = 0; index < books.length && index < SearchChineseScript.CLASSIFY_BOOKS; index++) {
      texts.push(books[index].name || '', books[index].author || '');
    }
    const script = this.classify(texts) || workedScript;
    if (!script || this.hints.get(url) === script) return;
    // 先删再放：Map 按插入顺序，宿主超出上限时从最旧的删起。
    this.hints.delete(url);
    this.hints.set(url, script);
    this.changed = true;
  }

  /** 上次取过之后记住的用字有没有变；取完清零，宿主据此决定要不要写回。 */
  takeChanged(): boolean {
    const changed = this.changed;
    this.changed = false;
    return changed;
  }

  /** 按简繁特有字的数量判断用字；两边差不多（混合站）或太少时返回 ''。 */
  classify(texts: string[]): string {
    let traditional = 0;
    let simplified = 0;
    for (const text of texts) {
      if (!text) continue;
      const toSimplified = this.converter.toSimplified(text);
      traditional += SearchChineseScript.diffCount(text, toSimplified);
      const toTraditional = this.converter.toTraditional(text);
      if (toTraditional.length === text.length) simplified += SearchChineseScript.diffCount(text, toTraditional);
    }
    const min = SearchChineseScript.MIN_SIGNAL;
    if (traditional >= min && traditional >= simplified * 2) return SearchChineseScript.TRADITIONAL;
    if (simplified >= min && simplified >= traditional * 2) return SearchChineseScript.SIMPLIFIED;
    return '';
  }

  /** 比对用：折成简体。结果与原文等长，同一批结果反复排序时走缓存。 */
  fold(text: string): string {
    if (!text) return text;
    const cached = this.foldCache.get(text);
    if (cached !== undefined) return cached;
    const folded = this.converter.toSimplified(text);
    if (this.foldCache.size >= SearchChineseScript.FOLD_CACHE_LIMIT) this.foldCache.clear();
    this.foldCache.set(text, folded);
    return folded;
  }

  /** 书名里有繁体字（折简体后会变）。结果卡片的“繁”角标用。 */
  isTraditional(text: string): boolean {
    return !!text && this.fold(text) !== text;
  }

  static nameHint(name: string, group: string): string {
    return SearchChineseScript.TRADITIONAL_SOURCE_NAME.test(`${name} ${group}`) ? SearchChineseScript.TRADITIONAL : '';
  }

  private static diffCount(source: string, target: string): number {
    if (source.length !== target.length) return 0;
    let count = 0;
    for (let index = 0; index < source.length; index++) {
      if (source.charCodeAt(index) !== target.charCodeAt(index)) count++;
    }
    return count;
  }
}
