/**
 * 书内链接跳转的落点。阅读页排版用的源文本可能多出标题行、缩进，被替换规则改过，不能直接按转换结果的
 * 字符偏移跳。所以转换时记下锚点后面的一小段文字（needle）和锚点前面正文的长度（estimate），
 * 跳转时在目标章的源文本里找这段文字，有几处时取离 estimate 最近的那一处。
 */
export class EpubLinkLocation {
  chapterIndex: number = -1;
  needle: string = '';
  estimate: number = 0;
}

export class EpubLinkTarget {
  static readonly NEEDLE_LENGTH: number = 20;
  private static readonly SHORT_NEEDLE_LENGTH: number = 8;
  /** 落点后面浅色闪一下的范围：到这一段结束，最多这么多字。 */
  private static readonly FLASH_MAX_LENGTH: number = 120;

  /** 锚点后面第一段有字的正文开头（去掉段首空白，\s 含全角空格）。content 里的标记应已去掉。 */
  static needle(content: string): string {
    for (const line of (content || '').split('\n')) {
      const text = line.replace(/^\s+/, '').replace(/\s+$/, '');
      if (text.length >= 2) return text.substring(0, EpubLinkTarget.NEEDLE_LENGTH);
    }
    return '';
  }

  /**
   * 在 plain（与阅读页源文本等长、标记换成空格的文本）里找 needle，返回 [起点, 闪动范围终点]；
   * 整段找不到时用前 8 个字再找，仍找不到返回 [-1, -1]。
   */
  static locate(plain: string, needle: string, estimate: number): number[] {
    const text = plain || '';
    for (const probe of [needle, (needle || '').substring(0, EpubLinkTarget.SHORT_NEEDLE_LENGTH)]) {
      if (probe.length < 2) continue;
      let best = -1;
      let index = text.indexOf(probe);
      while (index >= 0) {
        if (best < 0 || Math.abs(index - estimate) < Math.abs(best - estimate)) best = index;
        if (index > estimate) break;
        index = text.indexOf(probe, index + 1);
      }
      if (best >= 0) return [best, EpubLinkTarget.flashEnd(text, best)];
    }
    return [-1, -1];
  }

  private static flashEnd(text: string, start: number): number {
    const limit = Math.min(text.length, start + EpubLinkTarget.FLASH_MAX_LENGTH);
    const lineEnd = text.indexOf('\n', start);
    return lineEnd >= 0 && lineEnd < limit ? lineEnd : limit;
  }
}
