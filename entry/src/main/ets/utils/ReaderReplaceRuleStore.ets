import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { Book, JavaRegexCompat, ImportedReplaceRule } from '@legado/sourceengine';
import { CloudSyncChangeTracker } from '../account/CloudSyncChangeTracker';

export class ReaderReplaceRule {
  id: number = 0;
  name: string = '';
  group: string = '默认';
  pattern: string = '';
  replacement: string = '';
  applyToTitle: boolean = true;
  applyToContent: boolean = true;
  isRegex: boolean = true;
  scope: string = '';
  excludeScope: string = '';
  timeoutMs: number = 3000;
  enabled: boolean = true;
  /** 内置规则类型；空串是用户自己的规则。内置规则没有匹配内容，由阅读页按类型处理。 */
  builtin: string = '';
}

export class ReaderReplaceRuleCheck {
  state: string = 'noMatch';
  label: string = '当前章节未匹配';
  valid: boolean = true;
  scopeMatched: boolean = true;
  titleMatched: boolean = false;
  contentMatched: boolean = false;
  changed: boolean = false;
  compatibilityNotes: string[] = [];
}

export class ReaderReplaceRuleStore {
  static readonly UPDATE_TIME_KEY: string = 'readerReplaceRulesUpdateTime';
  private static readonly STORE_NAME: string = 'reader_replace_rules';
  private static readonly RULES_KEY: string = 'rulesV1';
  private static cachedRules: ReaderReplaceRule[] | null = null;
  /** 内置“移除标题”：开启后正文顶部不排版章节名，顶栏、目录等处照常显示。 */
  static readonly BUILTIN_REMOVE_TITLE: string = 'removeChapterTitle';
  // 固定编号让多设备同步时是同一条；取远大于时间戳的值，避开导入规则自带的小编号。旧版客户端回传会丢掉
  // builtin 字段，所以也按编号认。
  private static readonly BUILTIN_REMOVE_TITLE_ID: number = 8888000000001;
  /** 内置“移除重复标题”：正文开头重复章节名时去掉那一行（或那一截），默认开启。 */
  static readonly BUILTIN_REMOVE_DUPLICATE_TITLE: string = 'removeDuplicateTitle';
  private static readonly BUILTIN_REMOVE_DUPLICATE_TITLE_ID: number = 8888000000002;

  static async load(context: Context, force: boolean = false): Promise<ReaderReplaceRule[]> {
    if (!force && ReaderReplaceRuleStore.cachedRules) {
      return ReaderReplaceRuleStore.cloneRules(ReaderReplaceRuleStore.cachedRules);
    }
    const store = await preferences.getPreferences(context, ReaderReplaceRuleStore.STORE_NAME);
    const value = await store.get(ReaderReplaceRuleStore.RULES_KEY, '');
    const raw = typeof value === 'string' ? value : '';
    const rules = ReaderReplaceRuleStore.decode(raw);
    ReaderReplaceRuleStore.cachedRules = ReaderReplaceRuleStore.cloneRules(rules);
    return rules;
  }

  static async save(context: Context, rules: ReaderReplaceRule[]): Promise<void> {
    const normalized = ReaderReplaceRuleStore.withBuiltins(
      rules.map((rule: ReaderReplaceRule) => ReaderReplaceRuleStore.normalize(rule)));
    ReaderReplaceRuleStore.cachedRules = ReaderReplaceRuleStore.cloneRules(normalized);
    const store = await preferences.getPreferences(context, ReaderReplaceRuleStore.STORE_NAME);
    await store.put(ReaderReplaceRuleStore.RULES_KEY, JSON.stringify(normalized));
    await store.flush();
    AppStorage.setOrCreate(ReaderReplaceRuleStore.UPDATE_TIME_KEY, Date.now());
    CloudSyncChangeTracker.markPreferenceChanged();
  }

  static newRule(): ReaderReplaceRule {
    const rule = new ReaderReplaceRule();
    rule.id = Date.now();
    return rule;
  }

  static isBuiltin(rule: ReaderReplaceRule): boolean {
    return !!rule.builtin;
  }

  /** 本书是否启用了内置“移除标题”（同样受特定范围、排除范围限制）。 */
  static removesChapterTitle(rules: ReaderReplaceRule[], book: Book | null): boolean {
    return rules.some((rule: ReaderReplaceRule): boolean =>
      rule.builtin === ReaderReplaceRuleStore.BUILTIN_REMOVE_TITLE && rule.enabled !== false &&
        ReaderReplaceRuleStore.matchesBookScope(rule, book));
  }

  /** 本书是否启用了内置“移除重复标题”（同样受特定范围、排除范围限制）。 */
  static removesDuplicateTitle(rules: ReaderReplaceRule[], book: Book | null): boolean {
    return rules.some((rule: ReaderReplaceRule): boolean =>
      rule.builtin === ReaderReplaceRuleStore.BUILTIN_REMOVE_DUPLICATE_TITLE && rule.enabled !== false &&
        ReaderReplaceRuleStore.matchesBookScope(rule, book));
  }

  static builtinDescription(rule: ReaderReplaceRule): string {
    if (rule.builtin === ReaderReplaceRuleStore.BUILTIN_REMOVE_TITLE) {
      return '正文顶部不显示章节名，顶栏和目录照常显示';
    }
    return rule.builtin === ReaderReplaceRuleStore.BUILTIN_REMOVE_DUPLICATE_TITLE ?
      '正文开头又写了一遍章节名时去掉，只保留排版的章节名' : '';
  }

  static applyTitle(text: string, rules: ReaderReplaceRule[], book: Book | null): string {
    return ReaderReplaceRuleStore.apply(text, rules, book, true);
  }

  static applyContent(text: string, rules: ReaderReplaceRule[], book: Book | null): string {
    return ReaderReplaceRuleStore.apply(text, rules, book, false);
  }

  static checkRule(sourceRule: ReaderReplaceRule, book: Book | null,
    title: string, content: string): ReaderReplaceRuleCheck {
    const result = new ReaderReplaceRuleCheck();
    const rule = ReaderReplaceRuleStore.normalize(sourceRule);
    if (!rule.enabled) {
      result.state = 'disabled';
      result.label = '已禁用';
      return result;
    }
    if (rule.builtin) {
      result.scopeMatched = ReaderReplaceRuleStore.matchesBookScope(rule, book);
      result.state = result.scopeMatched ? 'builtin' : 'outOfScope';
      result.label = result.scopeMatched ? '当前书籍已生效' : '不适用于当前书籍';
      return result;
    }
    if (!rule.pattern) {
      result.state = 'invalid';
      result.label = '规则无效：匹配内容为空';
      result.valid = false;
      return result;
    }
    result.scopeMatched = ReaderReplaceRuleStore.matchesBookScope(rule, book);
    if (!result.scopeMatched) {
      result.state = 'outOfScope';
      result.label = '不适用于当前书籍';
      return result;
    }
    try {
      if (rule.isRegex) {
        // 规则多数来自 Android 阅读，按 Java 正则方言编译后再校验。
        const replacement = JavaRegexCompat.convertReplacement(rule.replacement);
        const titleRegex = JavaRegexCompat.compile(rule.pattern, 'g');
        const contentRegex = JavaRegexCompat.compile(rule.pattern, 'g');
        result.titleMatched = rule.applyToTitle && !!title && titleRegex.test(title);
        result.contentMatched = rule.applyToContent && !!content && contentRegex.test(content);
        if (result.titleMatched) {
          result.changed = title.replace(JavaRegexCompat.compile(rule.pattern, 'g'), replacement) !== title;
        }
        if (result.contentMatched) {
          result.changed = result.changed ||
            content.replace(JavaRegexCompat.compile(rule.pattern, 'g'), replacement) !== content;
        }
        result.compatibilityNotes = JavaRegexCompat.notes(rule.pattern);
      } else {
        result.titleMatched = rule.applyToTitle && !!title && title.includes(rule.pattern);
        result.contentMatched = rule.applyToContent && !!content && content.includes(rule.pattern);
        if (result.titleMatched) {
          result.changed = title.split(rule.pattern).join(rule.replacement) !== title;
        }
        if (result.contentMatched) {
          result.changed = result.changed || content.split(rule.pattern).join(rule.replacement) !== content;
        }
      }
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      const hint = JavaRegexCompat.unsupportedHint(rule.pattern);
      result.state = 'invalid';
      result.label = hint ? `规则无效：${reason}（${hint}）` : `规则无效：${reason}`;
      result.valid = false;
      return result;
    }
    if (result.titleMatched || result.contentMatched) {
      result.state = result.changed ? 'effective' : 'matched';
      result.label = result.changed ? '当前章节已生效' : '已匹配，替换结果未变化';
    }
    return result;
  }

  private static apply(
    text: string,
    rules: ReaderReplaceRule[],
    book: Book | null,
    title: boolean
  ): string {
    if (!text || rules.length === 0) {
      return text;
    }
    let result = text;
    for (const sourceRule of rules) {
      const rule = ReaderReplaceRuleStore.normalize(sourceRule);
      if (!rule.enabled || !rule.pattern || (title ? !rule.applyToTitle : !rule.applyToContent) ||
        !ReaderReplaceRuleStore.matchesBookScope(rule, book)) {
        continue;
      }
      const startedAt = Date.now();
      try {
        if (rule.isRegex) {
          result = result.replace(JavaRegexCompat.compile(rule.pattern, 'g'),
            JavaRegexCompat.convertReplacement(rule.replacement));
        } else {
          result = result.split(rule.pattern).join(rule.replacement);
        }
      } catch (error) {
        console.warn(`替换净化规则无效: ${rule.name || rule.pattern}`, error);
      }
      if (Date.now() - startedAt > rule.timeoutMs) {
        console.warn(`替换净化规则执行超时: ${rule.name || rule.pattern}`);
      }
    }
    return result;
  }

  private static matchesBookScope(rule: ReaderReplaceRule, book: Book | null): boolean {
    const target = ReaderReplaceRuleStore.bookScopeText(book);
    const includes = ReaderReplaceRuleStore.scopeTokens(rule.scope);
    if (includes.length > 0 && !includes.some((token: string) =>
      ReaderReplaceRuleStore.scopeTokenMatches(token, target))) {
      return false;
    }
    const excludes = ReaderReplaceRuleStore.scopeTokens(rule.excludeScope);
    return !excludes.some((token: string) => ReaderReplaceRuleStore.scopeTokenMatches(token, target));
  }

  private static bookScopeText(book: Book | null): string {
    if (!book) {
      return '';
    }
    return `${book.name || ''}\n${book.author || ''}\n${book.originName || ''}\n` +
      `${book.origin || ''}\n${book.bookUrl || ''}`.toLowerCase();
  }

  private static scopeTokens(value: string): string[] {
    return (value || '').split(/[\n,，;；]+/)
      .map((item: string) => item.trim().toLowerCase())
      .filter((item: string) => !!item);
  }

  private static scopeTokenMatches(token: string, target: string): boolean {
    if (!token) {
      return false;
    }
    if (token.startsWith('/') && token.lastIndexOf('/') > 0) {
      const end = token.lastIndexOf('/');
      try {
        return new RegExp(token.substring(1, end), token.substring(end + 1)).test(target);
      } catch (_) {
        return target.includes(token);
      }
    }
    if (token.includes('*')) {
      const escaped = token.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
      try {
        return new RegExp(escaped, 'i').test(target);
      } catch (_) {
        return false;
      }
    }
    return target.includes(token);
  }

  private static decode(raw: string): ReaderReplaceRule[] {
    if (!raw) {
      return ReaderReplaceRuleStore.withBuiltins([]);
    }
    try {
      const values = JSON.parse(raw) as ReaderReplaceRule[];
      if (!Array.isArray(values)) {
        return ReaderReplaceRuleStore.withBuiltins([]);
      }
      return ReaderReplaceRuleStore.withBuiltins(
        values.map((rule: ReaderReplaceRule) => ReaderReplaceRuleStore.normalize(rule)));
    } catch (error) {
      console.warn('读取替换净化规则失败:', error);
      return ReaderReplaceRuleStore.withBuiltins([]);
    }
  }

  /** 内置规则不能删除：缺了就按固定顺序补回列表最前面；重复的只留第一条。 */
  private static withBuiltins(rules: ReaderReplaceRule[]): ReaderReplaceRule[] {
    const seen: string[] = [];
    const result = rules.filter((rule: ReaderReplaceRule): boolean => {
      if (!rule.builtin) return true;
      if (seen.includes(rule.builtin)) return false;
      seen.push(rule.builtin);
      return true;
    });
    // 倒序 unshift，补回后的顺序与这里列出的一致。
    const defaults: ReaderReplaceRule[] = [
      ReaderReplaceRuleStore.builtinRule(ReaderReplaceRuleStore.BUILTIN_REMOVE_TITLE_ID, false),
      ReaderReplaceRuleStore.builtinRule(ReaderReplaceRuleStore.BUILTIN_REMOVE_DUPLICATE_TITLE_ID, true)
    ];
    for (let index = defaults.length - 1; index >= 0; index--) {
      if (!seen.includes(defaults[index].builtin)) result.unshift(defaults[index]);
    }
    return result;
  }

  private static builtinRule(id: number, enabled: boolean): ReaderReplaceRule {
    const rule = new ReaderReplaceRule();
    rule.id = id;
    rule.enabled = enabled;
    return ReaderReplaceRuleStore.normalize(rule);
  }

  private static normalize(source: ReaderReplaceRule): ReaderReplaceRule {
    const rule = new ReaderReplaceRule();
    rule.id = Number(source?.id) > 0 ? Number(source.id) : Date.now();
    rule.name = `${source?.name || ''}`.trim();
    rule.group = `${source?.group || '默认'}`.trim() || '默认';
    rule.pattern = `${source?.pattern || ''}`;
    rule.replacement = `${source?.replacement || ''}`;
    rule.applyToTitle = source?.applyToTitle !== false;
    rule.applyToContent = source?.applyToContent !== false;
    rule.isRegex = source?.isRegex !== false;
    rule.scope = `${source?.scope || ''}`;
    rule.excludeScope = `${source?.excludeScope || ''}`;
    const timeout = Math.round(Number(source?.timeoutMs));
    rule.timeoutMs = Number.isNaN(timeout) ? 3000 : Math.max(100, Math.min(timeout, 10000));
    rule.enabled = source?.enabled !== false;
    // 内置规则只有开关和书籍范围可改，其余字段固定；匹配内容留空，替换流程自然跳过它。
    if (source?.builtin === ReaderReplaceRuleStore.BUILTIN_REMOVE_TITLE ||
      rule.id === ReaderReplaceRuleStore.BUILTIN_REMOVE_TITLE_ID) {
      ReaderReplaceRuleStore.fixBuiltin(rule, ReaderReplaceRuleStore.BUILTIN_REMOVE_TITLE_ID,
        ReaderReplaceRuleStore.BUILTIN_REMOVE_TITLE, '移除标题', true, false);
    } else if (source?.builtin === ReaderReplaceRuleStore.BUILTIN_REMOVE_DUPLICATE_TITLE ||
      rule.id === ReaderReplaceRuleStore.BUILTIN_REMOVE_DUPLICATE_TITLE_ID) {
      ReaderReplaceRuleStore.fixBuiltin(rule, ReaderReplaceRuleStore.BUILTIN_REMOVE_DUPLICATE_TITLE_ID,
        ReaderReplaceRuleStore.BUILTIN_REMOVE_DUPLICATE_TITLE, '移除重复标题', false, true);
    }
    return rule;
  }

  private static fixBuiltin(rule: ReaderReplaceRule, id: number, builtin: string, name: string,
    applyToTitle: boolean, applyToContent: boolean): void {
    rule.id = id;
    rule.builtin = builtin;
    rule.name = name;
    rule.group = '内置';
    rule.pattern = '';
    rule.replacement = '';
    rule.applyToTitle = applyToTitle;
    rule.applyToContent = applyToContent;
    rule.isRegex = false;
  }

  static cloneRule(source: ReaderReplaceRule): ReaderReplaceRule {
    return ReaderReplaceRuleStore.normalize(source);
  }

  /** 把导入适配器的条目（已按别名统一字段）转成本应用的规则对象。 */
  static fromImportEntry(entry: ImportedReplaceRule): ReaderReplaceRule {
    const rule = new ReaderReplaceRule();
    rule.id = Number.isFinite(entry.id) && entry.id > 0 ? Math.round(entry.id) : 0;
    rule.name = entry.name;
    rule.group = entry.group;
    rule.pattern = entry.pattern;
    rule.replacement = entry.replacement;
    rule.isRegex = entry.isRegex;
    rule.enabled = entry.enabled;
    rule.applyToTitle = entry.applyToTitle;
    rule.applyToContent = entry.applyToContent;
    rule.scope = entry.scope;
    rule.excludeScope = entry.excludeScope;
    rule.timeoutMs = entry.timeoutMs;
    return ReaderReplaceRuleStore.normalize(rule);
  }

  private static cloneRules(rules: ReaderReplaceRule[]): ReaderReplaceRule[] {
    return rules.map((rule: ReaderReplaceRule) => ReaderReplaceRuleStore.cloneRule(rule));
  }
}
