import { ReaderDialogueMatcher, ReaderDialogueOptions } from './ReaderDialogueMatcher';

/** 一条强调规则里和找命中有关的部分，由 ReaderRegexFontCodec.matchSpecs 从规则拷出来。 */
export class ReaderRuleMatchSpec {
  pattern: string = '';
  /** 空：正则表达式；dialogue：智能对话（ReaderDialogueMatcher）。 */
  matcher: string = '';
  scope: string = 'all';
  /** 命中范围里允许其他规则再上色（对话里的人名）。 */
  nestOthers: boolean = false;
  dialogue: ReaderDialogueOptions = new ReaderDialogueOptions();
}

/** 一处命中。overlay 为 true 时它落在一条 nestOthers 规则的命中里，只换文字颜色和粗细。 */
export class ReaderRuleHit {
  start: number = 0;
  end: number = 0;
  ruleIndex: number = -1;
  overlay: boolean = false;

  constructor(start: number, end: number, ruleIndex: number, overlay: boolean) {
    this.start = start;
    this.end = end;
    this.ruleIndex = ruleIndex;
    this.overlay = overlay;
  }
}

/**
 * 阅读页和各处预览共用的命中判定。按规则顺序认领：
 * - 和已认领的命中都不重叠的，直接认领。
 * - 规则开了 nestOthers、已认领的重叠命中全落在它里面（且它们自己没开 nestOthers）：它照样认领，
 *   里面那些改成叠加层。所以人名规则排在对话前面时，对话也不会整句丢掉。
 * - 整个落在一条 nestOthers 命中里的：成为叠加层（和别的叠加层重叠的放弃）。
 * - 其余重叠的整段放弃，不拿剩下的半截。
 */
export class ReaderRegexRuleHits {
  static readonly DIALOGUE: string = 'dialogue';

  static isDialogue(matcher: string): boolean {
    return matcher === ReaderRegexRuleHits.DIALOGUE;
  }

  /** titles 是各标题块在显示文本里的 [起, 止) 区间。仅标题要求命中整个落在一个标题里，仅正文要求不碰标题。 */
  static scopeAccepts(scope: string, start: number, end: number, titles: number[][]): boolean {
    if (scope !== 'title' && scope !== 'body') return true;
    let inside = false;
    let touches = false;
    for (const title of titles) {
      if (start < title[1] && end > title[0]) {
        touches = true;
        if (start >= title[0] && end <= title[1]) inside = true;
      }
    }
    return scope === 'title' ? inside : !touches;
  }

  /** 一条规则在 text 里的全部命中（不管范围和重叠）；正则写错时为空。 */
  static ranges(spec: ReaderRuleMatchSpec, text: string): number[][] {
    if (ReaderRegexRuleHits.isDialogue(spec.matcher)) return ReaderDialogueMatcher.ranges(text, spec.dialogue);
    const pattern = (spec.pattern || '').trim();
    if (!pattern) return [];
    let regex: RegExp;
    try {
      regex = new RegExp(spec.pattern, 'g');
    } catch (_) {
      return [];
    }
    const result: number[][] = [];
    let match = regex.exec(text);
    while (match) {
      const start = match.index;
      const end = start + match[0].length;
      if (end > start) {
        result.push([start, end]);
      } else {
        if (start >= text.length) break;
        regex.lastIndex = Math.max(regex.lastIndex + 1, start + 1);
      }
      match = regex.exec(text);
    }
    return result;
  }

  static collect(specs: ReaderRuleMatchSpec[], text: string, titles: number[][]): ReaderRuleHit[] {
    const primaries: ReaderRuleHit[] = [];
    const overlays: ReaderRuleHit[] = [];
    for (let ruleIndex = 0; ruleIndex < specs.length; ruleIndex++) {
      const spec = specs[ruleIndex];
      for (const range of ReaderRegexRuleHits.ranges(spec, text)) {
        const start = range[0];
        const end = range[1];
        if (!ReaderRegexRuleHits.scopeAccepts(spec.scope, start, end, titles)) continue;
        const first = ReaderRegexRuleHits.firstOverlap(primaries, start);
        let last = first;
        while (last < primaries.length && primaries[last].start < end) last++;
        if (last === first) {
          primaries.splice(first, 0, new ReaderRuleHit(start, end, ruleIndex, false));
          continue;
        }
        if (spec.nestOthers && ReaderRegexRuleHits.canWrap(primaries, first, last, start, end, specs)) {
          const inner = primaries.splice(first, last - first, new ReaderRuleHit(start, end, ruleIndex, false));
          for (const hit of inner) ReaderRegexRuleHits.addOverlay(overlays, hit.start, hit.end, hit.ruleIndex);
          continue;
        }
        const host = primaries[first];
        if (last === first + 1 && specs[host.ruleIndex].nestOthers && start >= host.start && end <= host.end) {
          ReaderRegexRuleHits.addOverlay(overlays, start, end, ruleIndex);
        }
      }
    }
    const result = primaries.concat(overlays);
    result.sort((left: ReaderRuleHit, right: ReaderRuleHit): number =>
      left.start - right.start || (left.overlay ? 1 : 0) - (right.overlay ? 1 : 0));
    return result;
  }

  private static canWrap(primaries: ReaderRuleHit[], first: number, last: number, start: number, end: number,
    specs: ReaderRuleMatchSpec[]): boolean {
    for (let index = first; index < last; index++) {
      const hit = primaries[index];
      if (hit.start < start || hit.end > end || specs[hit.ruleIndex].nestOthers) return false;
    }
    return true;
  }

  private static addOverlay(overlays: ReaderRuleHit[], start: number, end: number, ruleIndex: number): void {
    const first = ReaderRegexRuleHits.firstOverlap(overlays, start);
    if (first < overlays.length && overlays[first].start < end) return;
    overlays.splice(first, 0, new ReaderRuleHit(start, end, ruleIndex, true));
  }

  /** hits 按起点排好且互不重叠（终点也就排好了）：第一个终点在 start 之后的位置。 */
  private static firstOverlap(hits: ReaderRuleHit[], start: number): number {
    let low = 0;
    let high = hits.length;
    while (low < high) {
      const middle = (low + high) >> 1;
      if (hits[middle].end <= start) low = middle + 1;
      else high = middle;
    }
    return low;
  }
}
