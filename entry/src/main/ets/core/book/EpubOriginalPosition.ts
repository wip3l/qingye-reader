import { ReaderActionMarker } from '@legado/sourceengine';
import { ReaderImageMarker } from './ReaderImageMarker';

/** 原版排版里的一个阅读位置：章内一小段文字，加上它在章内文字里的比例（找不到文字时退回比例）。 */
export class EpubOriginalSpot {
  snippet: string = '';
  fraction: number = 0;
}

class EpubCompactText {
  text: string = '';
  /** text 第 i 个字符在原正文里的偏移。 */
  offsets: number[] = [];
}

/**
 * 普通阅读器与原版排版之间换算阅读位置。两边的文字不完全相同（原版保留了脚注块、注音，
 * 普通阅读器把上标数字换成了 ¹²³），所以比较前都压成“去掉空白、统一上下标数字”的紧凑文字，
 * 用一小段紧凑文字定位，找不到时退回章内比例。网页里的脚本按同样的规则压缩（见 EpubOriginalScript）。
 */
export class EpubOriginalPosition {
  static readonly SNIPPET_LENGTH: number = 32;
  private static readonly SUPERSCRIPTS: string = '⁰¹²³⁴⁵⁶⁷⁸⁹';
  private static readonly SUBSCRIPTS: string = '₀₁₂₃₄₅₆₇₈₉';

  /** 普通阅读器正文 offset 处的位置。 */
  static spotAt(content: string, offset: number): EpubOriginalSpot {
    const compact = EpubOriginalPosition.compact(content);
    const spot = new EpubOriginalSpot();
    if (compact.text.length === 0) return spot;
    let index = EpubOriginalPosition.lowerBound(compact.offsets, Math.max(0, offset));
    index = Math.min(index, compact.text.length - 1);
    spot.snippet = compact.text.substring(index, index + EpubOriginalPosition.SNIPPET_LENGTH);
    spot.fraction = index / compact.text.length;
    return spot;
  }

  /** 原版排版的位置换回普通阅读器正文里的偏移。 */
  static offsetFor(content: string, spot: EpubOriginalSpot): number {
    const compact = EpubOriginalPosition.compact(content);
    if (compact.text.length === 0) return 0;
    const fraction = Math.max(0, Math.min(1, spot.fraction || 0));
    const index = EpubOriginalPosition.find(compact.text, EpubOriginalPosition.normalize(spot.snippet || ''), fraction);
    const position = index >= 0 ? index : Math.min(compact.text.length - 1, Math.round(fraction * compact.text.length));
    return compact.offsets[position];
  }

  /**
   * 网页里选中的一段（紧凑文字 quote，及其前后各一小段 prefix / suffix）在普通阅读器正文里的范围 [start, end)。
   * 有多处时取前后文吻合多的、离 fraction 近的；找不到返回 null。划线用它把文件排版的选区换成应用排版的位置。
   */
  static locate(content: string, quote: string, prefix: string, suffix: string, fraction: number): number[] | null {
    const target = EpubOriginalPosition.normalize(quote);
    if (!target) return null;
    const compact = EpubOriginalPosition.compact(content);
    const text = compact.text;
    const expected = Math.max(0, Math.min(1, fraction || 0)) * text.length;
    const before = EpubOriginalPosition.normalize(prefix);
    const after = EpubOriginalPosition.normalize(suffix);
    let best = -1;
    let bestScore = -1;
    let index = text.indexOf(target);
    for (let guard = 0; index >= 0 && guard < 256; guard++) {
      let score = 0;
      while (score < before.length && index - score - 1 >= 0 &&
        text.charAt(index - score - 1) === before.charAt(before.length - score - 1)) score++;
      let tail = 0;
      while (tail < after.length && index + target.length + tail < text.length &&
        text.charAt(index + target.length + tail) === after.charAt(tail)) tail++;
      score += tail;
      if (score > bestScore || (score === bestScore && Math.abs(index - expected) < Math.abs(best - expected))) {
        best = index;
        bestScore = score;
      }
      index = text.indexOf(target, index + 1);
    }
    if (best < 0) return null;
    return [compact.offsets[best], compact.offsets[best + target.length - 1] + 1];
  }

  /** 紧凑文字里找 snippet，找不到就逐步缩短；有多处时取离 fraction 最近的一处。 */
  static find(text: string, snippet: string, fraction: number): number {
    const expected = fraction * text.length;
    for (let length = snippet.length; length >= 6; length = Math.floor(length / 2)) {
      const probe = snippet.substring(0, length);
      let best = -1;
      let index = text.indexOf(probe);
      while (index >= 0) {
        if (best < 0 || Math.abs(index - expected) < Math.abs(best - expected)) best = index;
        index = text.indexOf(probe, index + 1);
      }
      if (best >= 0) return best;
    }
    return -1;
  }

  /** 一段正文的紧凑文字（动作标记换成显示文字、去掉图片标记），与网页脚本 compact() 得到的文字可直接比较。 */
  static compactOf(content: string): string {
    return EpubOriginalPosition.compact(content).text;
  }

  /** 统一上下标数字并去掉空白，网页脚本里有同样的实现。 */
  static normalize(value: string): string {
    let result = '';
    for (const char of value || '') {
      if (/\s/.test(char) || char === '​' || char === '﻿') continue;
      const superscript = EpubOriginalPosition.SUPERSCRIPTS.indexOf(char);
      const subscript = EpubOriginalPosition.SUBSCRIPTS.indexOf(char);
      result += superscript >= 0 ? `${superscript}` : (subscript >= 0 ? `${subscript}` : char);
    }
    return result;
  }

  /** 正文压成紧凑文字：动作标记换回显示文字，图片标记去掉。 */
  private static compact(content: string): EpubCompactText {
    const source = content || '';
    const result = new EpubCompactText();
    const chars: string[] = [];
    let cursor = 0;
    const push = (start: number, end: number, offsetOverride: number = -1): void => {
      for (let index = start; index < end; index++) {
        const piece = EpubOriginalPosition.normalize(source.charAt(index));
        if (!piece) continue;
        chars.push(piece);
        result.offsets.push(offsetOverride >= 0 ? offsetOverride : index);
      }
    };
    while (cursor < source.length) {
      const action = ReaderActionMarker.findFirstRawRange(source, cursor);
      const imageStart = source.indexOf(ReaderImageMarker.PREFIX, cursor);
      const imageEnd = imageStart >= 0 ? source.indexOf(ReaderImageMarker.SUFFIX, imageStart) : -1;
      const nextAction = action.length >= 2 ? action[0] : source.length;
      const nextImage = imageStart >= 0 && imageEnd >= 0 ? imageStart : source.length;
      const next = Math.min(nextAction, nextImage);
      push(cursor, next);
      if (next >= source.length) break;
      if (next === nextAction) {
        const data = ReaderActionMarker.parse(source.substring(action[0], action[1]));
        const label = EpubOriginalPosition.normalize(data ? data.label : '');
        for (const char of label) {
          chars.push(char);
          result.offsets.push(action[0]);
        }
        cursor = action[1];
      } else {
        cursor = imageEnd + ReaderImageMarker.SUFFIX.length;
      }
    }
    result.text = chars.join('');
    return result;
  }

  private static lowerBound(values: number[], target: number): number {
    let low = 0;
    let high = values.length;
    while (low < high) {
      const middle = (low + high) >>> 1;
      if (values[middle] < target) low = middle + 1;
      else high = middle;
    }
    return low;
  }
}
