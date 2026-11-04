import { ReaderActionMarker } from '@legado/sourceengine';

/**
 * 同一章重新转换后，把旧正文里的字符偏移换到新正文里，阅读进度不因正文多了标记而往回跳。
 * 新正文与旧正文的差别只有两类：一段文字换成了显示同样文字的动作标记（注释编号），
 * 或者一段文字被整段去掉（被引用的脚注块）。逐字对齐，遇到不一致就在旧正文里往后找新正文接下来的文字。
 */
export class EpubTextOffsetMap {
  private static readonly PROBE_LENGTH: number = 24;

  static map(oldText: string, newText: string, offset: number): number {
    const before = oldText || '';
    const after = newText || '';
    const target = Math.max(0, Math.min(before.length, Math.round(offset)));
    if (before === after) return target;
    let i = 0;
    let j = 0;
    let markerStart = -1;
    let markerEnd = -1;
    const nextMarker = (from: number): void => {
      const bounds = ReaderActionMarker.findFirstRawRange(after, from);
      markerStart = bounds.length >= 2 ? bounds[0] : after.length;
      markerEnd = bounds.length >= 2 ? bounds[1] : after.length;
    };
    nextMarker(0);
    while (i < target && j < after.length) {
      if (j === markerStart) {
        const data = ReaderActionMarker.parse(after.substring(markerStart, markerEnd));
        const label = data ? data.label : '';
        if (label && before.startsWith(label, i)) {
          if (target < i + label.length) return j;
          i += label.length;
        }
        j = markerEnd;
        nextMarker(j);
        continue;
      }
      if (before.charCodeAt(i) === after.charCodeAt(j)) {
        i++;
        j++;
        continue;
      }
      const probe = after.substring(j, Math.min(markerStart, j + EpubTextOffsetMap.PROBE_LENGTH));
      const resumed = probe.length >= 2 ? before.indexOf(probe, i + 1) : -1;
      if (resumed < 0) break;
      // 旧正文 [i, resumed) 在新正文里被去掉了，落在其中的偏移归到新正文的这个位置。
      if (target < resumed) return j;
      i = resumed;
    }
    return Math.min(after.length, j + Math.max(0, target - i));
  }
}
