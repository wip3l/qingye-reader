/**
 * 应用排版用到的 EPUB 背景图：书里常把卷首页、人物卡的整页插图写成 CSS 背景（background-image），
 * 文字压在图上。应用排版只排文字和图片，这里从书的样式表、<style> 和 style 属性里找出这些背景图，
 * 交给 EpubHtmlConverter 当插图放进正文。本模块不依赖系统 API，Node 回归脚本可以直接加载。
 *
 * 只做够用的近似：选择器只看最后一段（标签、#id、.class 的组合），忽略祖先与伪类，
 * 多条规则命中时按特异度、再按先后取一条；style 属性优先于样式表。
 */
export class EpubCssBackgroundRule {
  tag: string = '';
  id: string = '';
  classes: string[] = [];
  specificity: number = 0;
  order: number = 0;
  /** 背景图地址；空串表示这条规则把背景去掉了（background: none）。 */
  url: string = '';
  /** 明确写了平铺（repeat、repeat-x 等）：多半是纸纹、花边，不当插图。 */
  repeat: boolean = false;
}

export class EpubCssBackgroundValue {
  url: string = '';
  repeat: boolean = false;
}

/** 一个 XHTML 文件的样式上下文：命中背景图的规则，以及 <html>、<body> 的起始标签（它们不在 body 片段里）。 */
export class EpubPageStyle {
  rules: EpubCssBackgroundRule[] = [];
  rootTags: string[] = [];
}

export type EpubCssUrlRebase = (url: string) => string;

export class EpubCssBackground {
  private static readonly COMPOUND: RegExp = /^([a-zA-Z][\w-]*|\*)?((?:[#.][\w -￿-]+)*)$/;

  /** <link rel="stylesheet"> 的 href，按出现顺序。 */
  static stylesheetHrefs(html: string): string[] {
    const hrefs: string[] = [];
    const pattern = /<link\b[^>]*>/gi;
    let match = pattern.exec(html || '');
    while (match) {
      const tag = match[0];
      const rel = EpubCssBackground.attribute(tag, 'rel').toLowerCase();
      const href = EpubCssBackground.attribute(tag, 'href');
      if (href && rel.split(/\s+/).includes('stylesheet') && !/^(?:data:|https?:)/i.test(href)) hrefs.push(href);
      match = pattern.exec(html || '');
    }
    return hrefs;
  }

  /** 文件里 <style> 块的内容，按出现顺序拼在一起。 */
  static styleBlocks(html: string): string {
    const blocks: string[] = [];
    const pattern = /<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi;
    let match = pattern.exec(html || '');
    while (match) {
      blocks.push(match[1]);
      match = pattern.exec(html || '');
    }
    return blocks.join('\n');
  }

  static rootTags(html: string): string[] {
    const tags: string[] = [];
    const root = /<html\b[^>]*>/i.exec(html || '');
    if (root) tags.push(root[0]);
    const body = /<body\b[^>]*>/i.exec(html || '');
    if (body) tags.push(body[0]);
    return tags;
  }

  /**
   * 解析样式表，只留下设置了背景图（或把背景去掉）的规则。rebase 把 url() 里的地址换成
   * 相对 XHTML 文件能解析的形式（外部样式表里的地址相对样式表本身），返回空串表示丢弃。
   */
  static parseRules(css: string, rebase: EpubCssUrlRebase | null = null, orderBase: number = 0): EpubCssBackgroundRule[] {
    const rules: EpubCssBackgroundRule[] = [];
    const source = (css || '').replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--|-->/g, '');
    EpubCssBackground.collectRules(source, rebase, orderBase, rules);
    return rules;
  }

  private static collectRules(source: string, rebase: EpubCssUrlRebase | null, orderBase: number,
    rules: EpubCssBackgroundRule[]): void {
    let cursor = 0;
    while (cursor < source.length) {
      const open = source.indexOf('{', cursor);
      if (open < 0) return;
      const prelude = source.substring(cursor, open).replace(/@(?:import|charset|namespace)\b[^;]*;/gi, '').trim();
      const close = EpubCssBackground.matchingBrace(source, open);
      const inner = source.substring(open + 1, close < 0 ? source.length : close);
      cursor = close < 0 ? source.length : close + 1;
      if (prelude.startsWith('@')) {
        // @media、@supports 里的规则照常生效；@font-face、@page、@keyframes 等与背景插图无关。
        if (/^@(?:media|supports)\b/i.test(prelude)) EpubCssBackground.collectRules(inner, rebase, orderBase, rules);
        continue;
      }
      const value = EpubCssBackground.declarationBackground(inner);
      if (!value) continue;
      let url = value.url;
      if (url && rebase) url = rebase(url);
      if (value.url && !url) continue;
      for (const selector of prelude.split(',')) {
        const rule = EpubCssBackground.ruleFor(selector);
        if (!rule) continue;
        rule.url = url;
        rule.repeat = value.repeat;
        rule.order = orderBase + rules.length;
        rules.push(rule);
      }
    }
  }

  private static matchingBrace(source: string, open: number): number {
    let depth = 0;
    for (let index = open; index < source.length; index++) {
      const char = source.charAt(index);
      if (char === '{') depth++;
      else if (char === '}') {
        depth--;
        if (depth === 0) return index;
      }
    }
    return -1;
  }

  private static ruleFor(selector: string): EpubCssBackgroundRule | null {
    const parts = selector.trim().split(/\s*[\s>+~]\s*/).filter((part: string): boolean => !!part);
    if (parts.length === 0) return null;
    const last = parts[parts.length - 1];
    const match = EpubCssBackground.COMPOUND.exec(last);
    if (!match || (!match[1] && !match[2])) return null;
    const rule = new EpubCssBackgroundRule();
    rule.tag = match[1] && match[1] !== '*' ? match[1].toLowerCase() : '';
    const pieces = (match[2] || '').match(/[#.][^#.]+/g) || [];
    for (const piece of pieces) {
      if (piece.charAt(0) === '#') rule.id = piece.substring(1);
      else rule.classes.push(piece.substring(1));
    }
    if (!rule.tag && !rule.id && rule.classes.length === 0) return null;
    rule.specificity = (rule.id ? 100 : 0) + rule.classes.length * 10 + (rule.tag ? 1 : 0);
    // 祖先选择器也算进特异度，结果才与浏览器的取舍大致一致。
    for (let index = 0; index < parts.length - 1; index++) {
      const ancestor = parts[index];
      rule.specificity += (ancestor.match(/#/g) || []).length * 100 + (ancestor.match(/\./g) || []).length * 10;
    }
    return rule;
  }

  /** 一组声明里的背景图；没有写背景时返回 null，写了 none 时 url 为空。 */
  static declarationBackground(declarations: string): EpubCssBackgroundValue | null {
    let found: EpubCssBackgroundValue | null = null;
    let repeatText = '';
    for (const raw of (declarations || '').split(';')) {
      const colon = raw.indexOf(':');
      if (colon < 0) continue;
      const name = raw.substring(0, colon).trim().toLowerCase();
      const value = raw.substring(colon + 1).replace(/!important/i, '').trim();
      if (name === 'background' || name === 'background-image') {
        const url = /url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]*))\s*\)/i.exec(value);
        if (url) {
          found = new EpubCssBackgroundValue();
          found.url = (url[1] !== undefined ? url[1] : (url[2] !== undefined ? url[2] : url[3] || '')).trim();
          if (name === 'background') repeatText = value;
        } else if (name === 'background-image' || /(?:^|\s)none(?:\s|$)/i.test(value) || !/\burl\(/i.test(value)) {
          // background: #fff 之类的简写同样会把前面的背景图清掉。
          found = new EpubCssBackgroundValue();
          repeatText = '';
        }
      } else if (name === 'background-repeat') {
        repeatText = value;
      }
    }
    if (found && found.url && /^(?:data:|https?:)/i.test(found.url)) found.url = '';
    if (found) found.repeat = /\b(?:repeat|repeat-x|repeat-y|round|space)\b/i.test(repeatText.replace(/no-repeat/gi, ''));
    return found;
  }

  /** 起始标签的背景图：style 属性优先，其次按特异度和先后取样式表规则。没有背景时返回 null。 */
  static backgroundOf(tag: string, style: EpubPageStyle | null): EpubCssBackgroundValue | null {
    const inline = EpubCssBackground.attribute(tag, 'style');
    if (inline) {
      const value = EpubCssBackground.declarationBackground(EpubCssBackground.decodeBasicEntities(inline));
      if (value) return value.url ? value : null;
    }
    if (!style || style.rules.length === 0) return null;
    const name = /^<\s*([a-zA-Z][\w:-]*)/.exec(tag);
    const tagName = name ? name[1].toLowerCase().replace(/^.*:/, '') : '';
    const id = EpubCssBackground.attribute(tag, 'id');
    const classes = EpubCssBackground.attribute(tag, 'class').split(/\s+/).filter((item: string): boolean => !!item);
    let best: EpubCssBackgroundRule | null = null;
    for (const rule of style.rules) {
      if (rule.tag && rule.tag !== tagName) continue;
      if (rule.id && rule.id !== id) continue;
      if (rule.classes.some((item: string): boolean => !classes.includes(item))) continue;
      if (!best || rule.specificity > best.specificity ||
        (rule.specificity === best.specificity && rule.order > best.order)) {
        best = rule;
      }
    }
    if (!best || !best.url) return null;
    const value = new EpubCssBackgroundValue();
    value.url = best.url;
    value.repeat = best.repeat;
    return value;
  }

  private static attribute(tag: string, name: string): string {
    const match = new RegExp(`(?:^|[\\s"'])${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'>]+))`, 'i').exec(tag || '');
    if (!match) return '';
    return match[1] !== undefined ? match[1] : (match[2] !== undefined ? match[2] : (match[3] || ''));
  }

  private static decodeBasicEntities(value: string): string {
    return value.replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, '\'').replace(/&amp;/g, '&');
  }
}
