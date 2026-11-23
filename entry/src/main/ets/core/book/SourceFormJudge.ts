/**
 * 按“形态”（小说、漫画、有声书、短剧）判断某个书源值不值得搜，换源与批量换源共用；纯逻辑，便于 Node 回归。
 *
 * 判断依据按可靠程度依次看，前面的有结论就不再往下：
 * 1. 用户设为“照搜”的书源总是搜；
 * 2. 这个书源以往搜索结果的形态统计（样本够 MIN_SAMPLES 条才算数）：要找的形态占比不到 1/50 就跳过；
 *    聚合书源小说、漫画、短剧混着出，统计里各形态都有，自然照搜；
 * 3. 书源声明：类型标为有声或漫画、正文规则取图片；
 * 4. 书源名或分组里只出现一种形态的字样（“短剧”“漫画”“听书”等），只作辅助。
 * 都没有结论时照搜，宁可多搜不漏搜。
 */
export class SourceFormTally {
  novel: number = 0;
  comic: number = 0;
  audio: number = 0;
  video: number = 0;
}

export class SourceFormFacts {
  name: string = '';
  group: string = '';
  /** 书源声明的形态：'audio' / 'comic'，没声明为空。 */
  declared: string = '';
  /** 声明来自类型字段（'type'）还是从正文规则推出（'rule'）。 */
  declaredBy: string = '';
  tally: SourceFormTally | null = null;
  always: boolean = false;
}

export class SourceFormVerdict {
  search: boolean = true;
  /** 跳过时给用户看的原因；照搜时为空。 */
  reason: string = '';
}

export class SourceFormJudge {
  static readonly NOVEL: string = 'novel';
  static readonly COMIC: string = 'comic';
  static readonly AUDIO: string = 'audio';
  static readonly VIDEO: string = 'video';
  static readonly FORMS: string[] = ['novel', 'comic', 'audio', 'video'];
  static readonly MIN_SAMPLES: number = 20;
  /** 某形态占比低于 1/RARE_RATIO 视为不出这种形态，容得下偶尔一两条分错类的结果。 */
  static readonly RARE_RATIO: number = 50;

  static label(form: string): string {
    if (form === SourceFormJudge.COMIC) return '漫画';
    if (form === SourceFormJudge.AUDIO) return '有声书';
    if (form === SourceFormJudge.VIDEO) return '短剧';
    return '小说';
  }

  static countOf(tally: SourceFormTally, form: string): number {
    if (form === SourceFormJudge.COMIC) return tally.comic;
    if (form === SourceFormJudge.AUDIO) return tally.audio;
    if (form === SourceFormJudge.VIDEO) return tally.video;
    return tally.novel;
  }

  static total(tally: SourceFormTally): number {
    return tally.novel + tally.comic + tally.audio + tally.video;
  }

  static judge(facts: SourceFormFacts, forms: string[]): SourceFormVerdict {
    const verdict = new SourceFormVerdict();
    const wanted = forms.filter((form: string): boolean => SourceFormJudge.FORMS.includes(form));
    if (facts.always || wanted.length === 0) return verdict;
    const wantedLabel = wanted.map((form: string): string => SourceFormJudge.label(form)).join('、');

    const tally = facts.tally;
    const total = tally ? SourceFormJudge.total(tally) : 0;
    if (tally && total >= SourceFormJudge.MIN_SAMPLES) {
      const produces = wanted.some((form: string): boolean =>
        SourceFormJudge.countOf(tally, form) * SourceFormJudge.RARE_RATIO >= total);
      if (produces) return verdict;
      verdict.search = false;
      const dominant = SourceFormJudge.FORMS.find((form: string): boolean =>
        SourceFormJudge.countOf(tally, form) * SourceFormJudge.RARE_RATIO >= total * (SourceFormJudge.RARE_RATIO - 1));
      verdict.reason = dominant ? `近 ${total} 条结果都是${SourceFormJudge.label(dominant)}` :
        `近 ${total} 条结果里没有${wantedLabel}`;
      return verdict;
    }

    if (facts.declared) {
      if (wanted.includes(facts.declared)) return verdict;
      verdict.search = false;
      verdict.reason = facts.declaredBy === 'rule' ? '正文取的是图片，按漫画书源算' :
        `书源类型标为${SourceFormJudge.label(facts.declared)}`;
      return verdict;
    }

    const hint = SourceFormJudge.nameHint(facts.name, facts.group);
    if (hint.form && !wanted.includes(hint.form)) {
      verdict.search = false;
      verdict.reason = `名称或分组含“${hint.word}”`;
    }
    return verdict;
  }

  /** 书源名与分组里只出现一种形态的字样时返回那种形态；同时像小说站或出现多种形态时不下结论。 */
  static nameHint(name: string, group: string): NameHint {
    const text = `${name || ''}\n${group || ''}`;
    const result = new NameHint();
    const found: NameHint[] = [];
    for (const rule of NAME_RULES) {
      const match = text.match(rule.pattern);
      if (match) {
        const hint = new NameHint();
        hint.form = rule.form;
        hint.word = match[0];
        found.push(hint);
      }
    }
    if (found.length !== 1 || found[0].form === SourceFormJudge.NOVEL) return result;
    return found[0];
  }
}

export class NameHint {
  form: string = '';
  word: string = '';
}

class NameRule {
  form: string;
  pattern: RegExp;

  constructor(form: string, pattern: RegExp) {
    this.form = form;
    this.pattern = pattern;
  }
}

const NAME_RULES: NameRule[] = [
  new NameRule('video', /短剧|影视|视频/),
  new NameRule('comic', /漫画|动漫|comic|manga/i),
  new NameRule('audio', /听书|有声|广播剧|audio/i),
  new NameRule('novel', /小说|文学|书屋|书院|书阁|笔趣|阅读/)
];
