import { Book, CooperativeScheduler } from '@legado/sourceengine';
import { ReadBookEngine } from '../book/ReadBookEngine';
import { ReaderContentPreprocessor } from '../concurrency/ReaderContentPreprocessor';
import { ReaderReplaceRule } from '../../utils/ReaderReplaceRuleStore';
import { ReaderContentSearchMatch, ReaderContentSearchMatcher } from './ReaderContentSearchMatcher';

/** 结果列表里的一条：哪一章的第几处，以及给人看的摘录。 */
export class ReaderContentSearchHit {
  /** 在整次查找结果里的序号，从 0 起；底部导航条的“第几处”用它。 */
  index: number = 0;
  chapterIndex: number = 0;
  chapterTitle: string = '';
  ordinal: number = 0;
  before: string = '';
  text: string = '';
  after: string = '';
  key: string = '';
}

/** 一次查找的进度。hits 只带自上次回调以来新找到的结果，由宿主自己累加。 */
export class ReaderContentSearchProgress {
  query: string = '';
  hits: ReaderContentSearchHit[] = [];
  scanned: number = 0;
  total: number = 0;
  found: number = 0;
  running: boolean = false;
  /** 结果达到上限后提前停止。 */
  truncated: boolean = false;
  failed: boolean = false;
}

export interface ReaderContentSearchHost {
  book: () => Book | null;
  chapterCount: () => number;
  chapterTitle: (index: number) => string;
  /** 与正文显示一致的替换净化规则。 */
  replaceRules: () => ReaderReplaceRule[];
  onProgress: (progress: ReaderContentSearchProgress) => void;
}

/**
 * 本地书全文查找：从第一章起逐章取正文、做与显示一致的替换净化后匹配，结果边查边回传。
 * 用阅读页会话的副本（或独立的后台引擎）取正文，不挤占阅读页引擎的章节缓存，也不改变它的当前章。
 * 本地书正文来自章节缓存或书籍文件，不联网。匹配本身只是字符串查找，在主线程分批做并按时让出；
 * 替换净化规则仍在 TaskPool 里执行。
 */
export class ReaderContentSearch {
  static readonly MAX_HITS: number = 1000;
  private static readonly READ_AHEAD: number = 4;
  private static readonly REPORT_INTERVAL_MS: number = 150;

  private readonly host: ReaderContentSearchHost;
  private serial: number = 0;
  private engine: ReadBookEngine | null = null;
  private engineBookUrl: string = '';

  constructor(host: ReaderContentSearchHost) {
    this.host = host;
  }

  cancel(): void {
    this.serial++;
  }

  /** 离开阅读页时调用：停掉查找并放掉取正文用的引擎。 */
  dispose(): void {
    this.cancel();
    this.engine = null;
    this.engineBookUrl = '';
  }

  async start(rawQuery: string): Promise<void> {
    const serial = ++this.serial;
    const query = ReaderContentSearchMatcher.normalizeQuery(rawQuery);
    const book = this.host.book();
    const total = this.host.chapterCount();
    const progress = new ReaderContentSearchProgress();
    progress.query = query;
    progress.total = total;
    progress.running = true;
    if (!book || !query || total <= 0) {
      progress.running = false;
      this.host.onProgress(progress);
      return;
    }
    this.host.onProgress(progress);
    const cancelled = (): boolean => serial !== this.serial;
    const rules = this.host.replaceRules();
    const applyRules = ReaderContentPreprocessor.hasActiveContentRules(rules);
    let pendingHits: ReaderContentSearchHit[] = [];
    let found = 0;
    let lastReportAt = Date.now();
    const report = (running: boolean): void => {
      const next = new ReaderContentSearchProgress();
      next.query = query;
      next.hits = pendingHits;
      next.scanned = progress.scanned;
      next.total = total;
      next.found = found;
      next.running = running;
      next.truncated = progress.truncated;
      next.failed = progress.failed;
      pendingHits = [];
      lastReportAt = Date.now();
      this.host.onProgress(next);
    };
    try {
      const engine = await this.engineFor(book);
      if (cancelled()) return;
      const reads: Map<number, Promise<string>> = new Map<number, Promise<string>>();
      const count = Math.min(total, engine.chapters.length);
      progress.total = count;
      for (let index = 0; index < count; index++) {
        for (let ahead = index; ahead < Math.min(count, index + ReaderContentSearch.READ_AHEAD); ahead++) {
          if (!reads.has(ahead)) reads.set(ahead, this.readChapter(engine, ahead, cancelled));
        }
        let text = await (reads.get(index) as Promise<string>);
        reads.delete(index);
        if (cancelled()) return;
        if (text && applyRules) {
          text = await ReaderContentPreprocessor.apply(text, rules, book);
          if (cancelled()) return;
        }
        const matches = ReaderContentSearchMatcher.find(text, query, ReaderContentSearch.MAX_HITS - found);
        if (matches.length > 0) {
          const title = this.host.chapterTitle(index);
          for (const match of matches) pendingHits.push(this.hitOf(found++, index, title, match));
        }
        progress.scanned = index + 1;
        if (found >= ReaderContentSearch.MAX_HITS) {
          progress.truncated = true;
          break;
        }
        if (Date.now() - lastReportAt >= ReaderContentSearch.REPORT_INTERVAL_MS) {
          report(true);
          await CooperativeScheduler.yieldToEventLoop();
          if (cancelled()) return;
        }
      }
    } catch (error) {
      console.warn('[ReaderContentSearch] 查找失败:', error);
      progress.failed = true;
    }
    if (!cancelled()) report(false);
  }

  private hitOf(index: number, chapterIndex: number, title: string, match: ReaderContentSearchMatch): ReaderContentSearchHit {
    const hit = new ReaderContentSearchHit();
    hit.index = index;
    hit.chapterIndex = chapterIndex;
    hit.chapterTitle = title;
    hit.ordinal = match.ordinal;
    hit.before = match.before;
    hit.text = match.text;
    hit.after = match.after;
    hit.key = `${chapterIndex}_${match.ordinal}_${match.start}`;
    return hit;
  }

  private async readChapter(engine: ReadBookEngine, index: number, cancelled: () => boolean): Promise<string> {
    if (cancelled()) return '';
    try {
      return await engine.peekContent(index);
    } catch (error) {
      console.warn(`[ReaderContentSearch] 读取第 ${index} 章失败:`, error);
      return '';
    }
  }

  private async engineFor(book: Book): Promise<ReadBookEngine> {
    if (this.engine && this.engineBookUrl === book.bookUrl &&
      this.engine.chapters.length === this.host.chapterCount()) {
      return this.engine;
    }
    // 优先复制阅读页的会话：目录现成、内存里已有的章节直接可用；会话不属于这本书时才另开一个后台引擎。
    let engine = ReadBookEngine.forkSession(book.bookUrl);
    if (!engine) {
      engine = ReadBookEngine.createBackgroundWorker();
      await engine.openBook(book);
    }
    this.engine = engine;
    this.engineBookUrl = book.bookUrl;
    return engine;
  }
}
