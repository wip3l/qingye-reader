/** 正文段首缩进的字符数；旧设置未保存此项时保持两字符。 */
export class ReaderParagraphIndent {
  static readonly DEFAULT: number = 2;

  static normalize(value: number): number {
    return Number.isFinite(value) ? Math.max(0, Math.min(4, Math.round(value))) : ReaderParagraphIndent.DEFAULT;
  }

  /** 缩进改变了正文字符偏移，按相同行内的正文位置恢复阅读锚点。 */
  static remapOffset(source: string, target: string, offset: number): number {
    if (!source || source === target) return offset;
    const sourceLines = source.split('\n');
    const targetLines = target.split('\n');
    if (sourceLines.length !== targetLines.length) return offset;
    let sourceStart = 0;
    let targetStart = 0;
    for (let index = 0; index < sourceLines.length; index++) {
      const before = sourceLines[index];
      const after = targetLines[index];
      const beforeText = before.replace(/^[\t 　]+/, '');
      const afterText = after.replace(/^[\t 　]+/, '');
      if (beforeText !== afterText) return offset;
      if (offset <= sourceStart + before.length) {
        const contentOffset = offset - sourceStart - (before.length - beforeText.length);
        return targetStart + (contentOffset < 0 ? 0 : after.length - afterText.length + contentOffset);
      }
      sourceStart += before.length + 1;
      targetStart += after.length + 1;
    }
    return target.length;
  }
}

/** 一条“以这个正则命中的文字开头的段落，段首缩进用 indent 个字符”的设定，来自正则字体规则。 */
export class ReaderParagraphIndentOverride {
  pattern: string = '';
  indent: number = 0;
}

/** 按顺序试各条设定，第一条在段落开头命中的生效；都不命中用全局缩进。正则只编译一次。 */
export class ReaderParagraphIndentMatcher {
  private patterns: RegExp[] = [];
  private indents: number[] = [];

  constructor(overrides: ReaderParagraphIndentOverride[]) {
    for (const item of overrides) {
      const source = (item.pattern || '').trim();
      if (!source) continue;
      try {
        // 粘连匹配只在段落开头试一次，不扫整段。
        this.patterns.push(new RegExp(source, 'y'));
        this.indents.push(ReaderParagraphIndent.normalize(item.indent));
      } catch (_) {
      }
    }
  }

  isEmpty(): boolean {
    return this.patterns.length === 0;
  }

  /** content 是去掉行首空白后的段落。 */
  indentFor(content: string, fallback: number): number {
    for (let index = 0; index < this.patterns.length; index++) {
      const pattern = this.patterns[index];
      pattern.lastIndex = 0;
      const match = pattern.exec(content);
      if (match && match[0].length > 0) return this.indents[index];
    }
    return fallback;
  }
}
