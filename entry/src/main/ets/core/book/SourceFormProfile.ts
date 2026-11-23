import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { BookSource, BookTypeSupport } from '@legado/sourceengine';
import { appDb } from '../../model/data/AppDatabase';
import { SourceFormFacts, SourceFormJudge, SourceFormTally, SourceFormVerdict } from './SourceFormJudge';

/** 按形态挑书源的结果：要搜的书源和跳过的书源（附原因）。 */
export class SourceFormSplit {
  kept: BookSource[] = [];
  skipped: SkippedSource[] = [];
}

export class SkippedSource {
  source: BookSource;
  reason: string;

  constructor(source: BookSource, reason: string) {
    this.source = source;
    this.reason = reason;
  }
}

/**
 * 书源形态画像：每个书源在以往搜索里出过多少条小说、漫画、有声书、短剧，以及用户设为“照搜”的书源。
 * 搜索层每解析出一条结果就记一笔（先记在内存，搜完合并写回独立的偏好文件），换源按它挑书源。
 * 计数超过 DECAY_AT 时整体减半，书源改版换了内容也能慢慢跟上；读入时去掉已删除的书源。
 */
export class SourceFormProfile {
  private static readonly STORE_NAME: string = 'search_source_forms';
  private static readonly KEY_TALLY: string = 'tally';
  private static readonly KEY_ALWAYS: string = 'alwaysSearch';
  private static readonly MAX_SOURCES: number = 3000;
  private static readonly DECAY_AT: number = 400;
  private static readonly SAVE_DELAY_MS: number = 3000;
  private static context: Context | null = null;
  private static tallies: Map<string, SourceFormTally> = new Map();
  private static always: Set<string> = new Set();
  /** 还没读盘时记下的计数，读入后并进去。 */
  private static pending: Map<string, SourceFormTally> = new Map();
  private static loaded: boolean = false;
  private static loading: Promise<void> | null = null;
  private static dirty: boolean = false;
  private static saveTimer: number = -1;

  /** 启动时绑定应用上下文，不读盘；第一次要用时再读。 */
  static bindContext(context: Context): void {
    SourceFormProfile.context = context;
  }

  static async load(): Promise<void> {
    if (SourceFormProfile.loaded) return;
    if (!SourceFormProfile.loading) {
      SourceFormProfile.loading = SourceFormProfile.read().finally((): void => {
        SourceFormProfile.loading = null;
      });
    }
    await SourceFormProfile.loading;
  }

  /** 搜索层调用：某书源解析出一条某形态的结果。 */
  static note(sourceUrl: string, form: string): void {
    if (!sourceUrl || !SourceFormJudge.FORMS.includes(form)) return;
    const target = SourceFormProfile.loaded ? SourceFormProfile.tallies : SourceFormProfile.pending;
    let tally = target.get(sourceUrl);
    if (!tally) {
      tally = new SourceFormTally();
      target.set(sourceUrl, tally);
    } else if (SourceFormProfile.loaded) {
      // 挪到末尾：超过上限时从最久没出过结果的书源删起。
      target.delete(sourceUrl);
      target.set(sourceUrl, tally);
    }
    SourceFormProfile.add(tally, form, 1);
    if (SourceFormProfile.loaded && SourceFormJudge.total(tally) > SourceFormProfile.DECAY_AT) {
      SourceFormProfile.halve(tally);
    }
    SourceFormProfile.dirty = true;
    SourceFormProfile.scheduleSave();
  }

  static isAlways(sourceUrl: string): boolean {
    return SourceFormProfile.always.has(sourceUrl);
  }

  static alwaysCount(): number {
    return SourceFormProfile.always.size;
  }

  static setAlways(sourceUrl: string, value: boolean): void {
    if (!sourceUrl || SourceFormProfile.always.has(sourceUrl) === value) return;
    if (value) {
      SourceFormProfile.always.add(sourceUrl);
    } else {
      SourceFormProfile.always.delete(sourceUrl);
    }
    SourceFormProfile.dirty = true;
    SourceFormProfile.scheduleSave(0);
  }

  static clearAlways(): void {
    if (SourceFormProfile.always.size === 0) return;
    SourceFormProfile.always.clear();
    SourceFormProfile.dirty = true;
    SourceFormProfile.scheduleSave(0);
  }

  static judge(source: BookSource, forms: string[]): SourceFormVerdict {
    const facts = new SourceFormFacts();
    const url = source.bookSourceUrl || '';
    facts.name = source.bookSourceName || '';
    facts.group = source.bookSourceGroup || '';
    facts.always = SourceFormProfile.always.has(url);
    facts.tally = SourceFormProfile.tallies.get(url) || null;
    if (source.bookSourceType === 1) {
      facts.declared = SourceFormJudge.AUDIO;
      facts.declaredBy = 'type';
    } else if (source.bookSourceType === 2) {
      facts.declared = SourceFormJudge.COMIC;
      facts.declaredBy = 'type';
    } else if (BookTypeSupport.typeFromSource(source) === BookTypeSupport.IMAGE) {
      facts.declared = SourceFormJudge.COMIC;
      facts.declaredBy = 'rule';
    }
    return SourceFormJudge.judge(facts, forms);
  }

  /** 按形态把书源分成要搜的和跳过的；调用前先 load()。 */
  static split(sources: BookSource[], forms: string[]): SourceFormSplit {
    const result = new SourceFormSplit();
    for (const source of sources) {
      const verdict = SourceFormProfile.judge(source, forms);
      if (verdict.search) {
        result.kept.push(source);
      } else {
        result.skipped.push(new SkippedSource(source, verdict.reason));
      }
    }
    return result;
  }

  private static add(tally: SourceFormTally, form: string, count: number): void {
    if (form === SourceFormJudge.COMIC) tally.comic += count;
    else if (form === SourceFormJudge.AUDIO) tally.audio += count;
    else if (form === SourceFormJudge.VIDEO) tally.video += count;
    else tally.novel += count;
  }

  private static halve(tally: SourceFormTally): void {
    tally.novel = Math.floor(tally.novel / 2);
    tally.comic = Math.floor(tally.comic / 2);
    tally.audio = Math.floor(tally.audio / 2);
    tally.video = Math.floor(tally.video / 2);
  }

  private static scheduleSave(delay: number = SourceFormProfile.SAVE_DELAY_MS): void {
    if (!SourceFormProfile.context) return;
    if (SourceFormProfile.saveTimer !== -1) {
      if (delay > 0) return;
      clearTimeout(SourceFormProfile.saveTimer);
    }
    SourceFormProfile.saveTimer = setTimeout((): void => {
      SourceFormProfile.saveTimer = -1;
      SourceFormProfile.save().catch((e: Error): void => {
        console.warn('[SourceForm] 保存书源形态失败:', e);
      });
    }, delay);
  }

  private static async save(): Promise<void> {
    const context = SourceFormProfile.context;
    if (!context) return;
    await SourceFormProfile.load();
    if (!SourceFormProfile.dirty) return;
    SourceFormProfile.dirty = false;
    const tallies = SourceFormProfile.tallies;
    while (tallies.size > SourceFormProfile.MAX_SOURCES) {
      const oldest = tallies.keys().next();
      if (oldest.done) break;
      tallies.delete(oldest.value);
    }
    const rows: Array<Array<string | number>> = [];
    tallies.forEach((tally: SourceFormTally, url: string): void => {
      rows.push([url, tally.novel, tally.comic, tally.audio, tally.video]);
    });
    const store = await preferences.getPreferences(context, SourceFormProfile.STORE_NAME);
    await store.put(SourceFormProfile.KEY_TALLY, JSON.stringify(rows));
    await store.put(SourceFormProfile.KEY_ALWAYS, JSON.stringify(Array.from(SourceFormProfile.always)));
    await store.flush();
  }

  private static async read(): Promise<void> {
    const context = SourceFormProfile.context;
    const tallies: Map<string, SourceFormTally> = new Map();
    const always: Set<string> = new Set();
    if (context) {
      try {
        const store = await preferences.getPreferences(context, SourceFormProfile.STORE_NAME);
        // 只取书源地址这一列，比读完整书源轻；书源库还没打开（读不到任何地址）时全部保留，免得误删。
        const existing = await appDb.getBookSourceAddedTimes();
        const rawTally = await store.get(SourceFormProfile.KEY_TALLY, '');
        const rows = typeof rawTally === 'string' && rawTally ? JSON.parse(rawTally) as Array<Array<string | number>> : [];
        if (Array.isArray(rows)) {
          for (const row of rows) {
            if (!Array.isArray(row) || row.length < 5) continue;
            const url = String(row[0] || '');
            if (!url || (existing.size > 0 && !existing.has(url))) continue;
            const tally = new SourceFormTally();
            tally.novel = SourceFormProfile.count(row[1]);
            tally.comic = SourceFormProfile.count(row[2]);
            tally.audio = SourceFormProfile.count(row[3]);
            tally.video = SourceFormProfile.count(row[4]);
            tallies.set(url, tally);
          }
        }
        const rawAlways = await store.get(SourceFormProfile.KEY_ALWAYS, '');
        const urls = typeof rawAlways === 'string' && rawAlways ? JSON.parse(rawAlways) as string[] : [];
        if (Array.isArray(urls)) {
          for (const url of urls) {
            const value = String(url || '');
            if (value && (existing.size === 0 || existing.has(value))) always.add(value);
          }
        }
      } catch (e) {
        console.warn('[SourceForm] 读取书源形态失败:', e);
      }
    }
    // 读盘期间已有的“照搜”改动以内存为准。
    SourceFormProfile.always.forEach((url: string): void => { always.add(url); });
    SourceFormProfile.pending.forEach((extra: SourceFormTally, url: string): void => {
      const tally = tallies.get(url) || new SourceFormTally();
      tallies.delete(url);
      for (const form of SourceFormJudge.FORMS) SourceFormProfile.add(tally, form, SourceFormJudge.countOf(extra, form));
      while (SourceFormJudge.total(tally) > SourceFormProfile.DECAY_AT) SourceFormProfile.halve(tally);
      tallies.set(url, tally);
    });
    SourceFormProfile.pending = new Map();
    SourceFormProfile.tallies = tallies;
    SourceFormProfile.always = always;
    SourceFormProfile.loaded = true;
  }

  private static count(value: string | number): number {
    const n = Math.floor(Number(value));
    return Number.isFinite(n) && n > 0 ? n : 0;
  }
}
