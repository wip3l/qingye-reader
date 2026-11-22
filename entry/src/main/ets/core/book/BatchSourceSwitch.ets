import { Context } from '@kit.AbilityKit';
import { Book, BookSource, SearchBook, BookTypeSupport } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { ChangeSourceCacheSnapshot, ChangeSourceResultCache } from '../../utils/ChangeSourceResultCache';
import { SearchExploreSettingsStore } from '../../utils/SearchExploreSettingsStore';
import { SourcePickerKit } from '../../components/home/SourcePickerKit';
import { AuthorFold } from './ChangeSourceAuthorMatch';
import { BatchSourceSwitchPolicy } from './BatchSourceSwitchPolicy';
import { BookSourceSwitchTask, PreparedSourceSwitch } from './BookSourceSwitchTask';
import { ChangeSourceCandidates } from './ChangeSourceCandidates';
import { SearchChineseScriptRuntime } from './SearchChineseScriptRuntime';
import { SearchCoordinator, SearchProgress } from './SearchCoordinator';
import { SourceFormProfile } from './SourceFormProfile';

/** 批量换源里的一本书和它当前的状态。 */
export class BatchSwitchItem {
  static readonly QUEUED: number = 0;
  static readonly WORKING: number = 1;
  static readonly SWITCHED: number = 2;
  static readonly MISSING: number = 3;

  book: Book;
  state: number = BatchSwitchItem.QUEUED;
  /** 进行中是进度，换好后是“旧源 → 新源 · N 章”，没找到时是原因。 */
  detail: string = '';
  startedAt: number = 0;
  /** 换好后的书（新地址、新书源）。 */
  switched: Book | null = null;

  constructor(book: Book) {
    this.book = book;
  }
}

class CandidateSearch {
  eligible: SearchBook[] = [];
  /** 同名同类型的候选总数（含作者对不上的），用来区分“没搜到”和“作者对不上”。 */
  sameName: number = 0;
}

/**
 * 批量自动换源：给一批刷新失败或书源不在本机的书各找一个新书源并换过去。
 * 每本书先搜同名书，按 BatchSourceSwitchPolicy 留下认得准的候选，逐个取目录验证后提交最合适的一个；
 * 提交与手动换源是同一条路，分组、置顶、封面和阅读进度照样保留。
 * 页面只读 items 并在 onChanged 时重绘；停止后已换的保留，没轮到的回到排队状态。
 */
export class BatchSourceSwitch {
  readonly items: BatchSwitchItem[];
  private context: Context;
  private onChanged: () => void;
  private onSwitched: (previousUrl: string, book: Book) => void;
  private stopped: boolean = false;
  private coordinators: Set<SearchCoordinator> = new Set();
  private tasks: Set<BookSourceSwitchTask> = new Set();
  private fold: AuthorFold = null;
  private enabledSources: Set<string> = new Set();
  private scopeGroups: string[] = [];
  private scopeSourceCount: number = 0;
  /** 范围内的启用书源，按形态挑书源时用。 */
  private scopeSources: BookSource[] = [];

  constructor(context: Context, books: Book[], onChanged: () => void,
    onSwitched: (previousUrl: string, book: Book) => void) {
    this.context = context;
    this.items = books.map((book: Book): BatchSwitchItem => new BatchSwitchItem(book));
    this.onChanged = onChanged;
    this.onSwitched = onSwitched;
  }

  isStopped(): boolean { return this.stopped; }

  /** 停掉还没换的：在搜、在取目录的立刻中断；已经开始保存的那一本会保存完。 */
  stop(): void {
    if (this.stopped) return;
    this.stopped = true;
    this.coordinators.forEach((coordinator: SearchCoordinator): void => coordinator.cancel());
    this.tasks.forEach((task: BookSourceSwitchTask): void => task.cancel());
  }

  count(state: number): number {
    return this.items.filter((item: BatchSwitchItem): boolean => item.state === state).length;
  }

  async run(): Promise<void> {
    try {
      await this.loadScope();
      await SourceFormProfile.load();
      const script = await SearchChineseScriptRuntime.forSearch(this.context);
      this.fold = script ? (text: string): string => script.fold(text) : null;
      const queue = this.items.slice();
      const worker = async (): Promise<void> => {
        while (!this.stopped) {
          const item = queue.shift();
          if (!item) return;
          await this.process(item);
        }
      };
      const workers: Promise<void>[] = [];
      for (let i = 0; i < Math.min(BatchSourceSwitchPolicy.CONCURRENCY, this.items.length); i++) workers.push(worker());
      await Promise.all(workers);
    } finally {
      SearchChineseScriptRuntime.saveHints(this.context);
      ChangeSourceResultCache.flush(this.context).catch((e: Error): void => console.warn('保存换源记录失败:', e));
    }
  }

  /** 沿用换源面板记住的范围；记住的分组都不在了就搜全部。 */
  private async loadScope(): Promise<void> {
    const sources = await AppDatabase.getInstance().getEnabledBookSourcesForSearch();
    const scope = await SearchExploreSettingsStore.loadChangeSourceScope(this.context);
    const groups = scope.mode === SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_GROUP ? scope.groups : [];
    let inScope = 0;
    for (const source of sources) {
      if (!source.bookSourceUrl) continue;
      this.enabledSources.add(source.bookSourceUrl);
      if (groups.includes(SourcePickerKit.groupLabel(source.bookSourceGroup))) inScope++;
    }
    this.scopeGroups = inScope > 0 ? groups.slice() : [];
    this.scopeSourceCount = inScope > 0 ? inScope : this.enabledSources.size;
    this.scopeSources = sources.filter((source: BookSource): boolean => !!source.bookSourceUrl &&
      (this.scopeGroups.length === 0 || this.scopeGroups.includes(SourcePickerKit.groupLabel(source.bookSourceGroup))));
  }

  /** 只搜可能出这本书形态的书源；一个都挑不出来时照旧搜全部。 */
  private sourcesFor(book: Book): BookSource[] | undefined {
    const kept = SourceFormProfile.split(this.scopeSources, [BookTypeSupport.mediaCategoryOf(book)]).kept;
    return kept.length > 0 && kept.length < this.scopeSources.length ? kept : undefined;
  }

  private update(item: BatchSwitchItem, state: number, detail: string): void {
    item.state = state;
    item.detail = detail;
    this.onChanged();
  }

  private async process(item: BatchSwitchItem): Promise<void> {
    item.startedAt = Date.now();
    this.update(item, BatchSwitchItem.WORKING, '正在搜索可用书源…');
    try {
      const db = AppDatabase.getInstance();
      const book = await db.getBook(item.book.bookUrl);
      if (!book) {
        this.update(item, BatchSwitchItem.MISSING, '这本书已不在书架');
        return;
      }
      if (!book.name.trim()) {
        this.update(item, BatchSwitchItem.MISSING, '没有书名，无法搜索');
        return;
      }
      const revision = BookSourceSwitchTask.revisionOf(book);
      const cached = await ChangeSourceResultCache.load(this.context, book);
      const found = await this.findCandidates(item, book, cached);
      if (this.stopped) {
        this.update(item, BatchSwitchItem.QUEUED, '');
        return;
      }
      if (found.eligible.length === 0) {
        this.update(item, BatchSwitchItem.MISSING, found.sameName > 0 ? '找到同名的书，但作者对不上' :
          `${this.scopeSourceCount} 个书源里没有找到这本书`);
        return;
      }
      const prepared = await this.verify(item, book, cached.key, found.eligible);
      if (this.stopped) {
        this.update(item, BatchSwitchItem.QUEUED, '');
        return;
      }
      if (prepared.length === 0) {
        this.update(item, BatchSwitchItem.MISSING, '找到的书源都取不到目录');
        return;
      }
      const best = BatchSourceSwitchPolicy.pick(
        prepared.map((entry: PreparedSourceSwitch): number => entry.chapters.length), book.durChapterIndex);
      if (best < 0) {
        this.update(item, BatchSwitchItem.MISSING, '找到的书源章节都少于已读位置');
        return;
      }
      const committer = new BookSourceSwitchTask(false);
      const switched = await committer.commit(this.context, prepared[best], (): void => {},
        (_book: Book, _previousUrl: string): void => {}, revision);
      item.switched = switched;
      const from = (book.originName || book.origin || '').trim();
      const to = (switched.originName || switched.origin || '').trim();
      this.update(item, BatchSwitchItem.SWITCHED, `${from ? `${from} → ` : ''}${to} · ${prepared[best].chapters.length} 章`);
      try { this.onSwitched(book.bookUrl, switched); } catch (e) {
        console.error('批量换源已提交，页面更新失败:', e);
      }
    } catch (e) {
      if (this.stopped) {
        this.update(item, BatchSwitchItem.QUEUED, '');
        return;
      }
      console.error('批量换源失败:', item.book.name, e);
      const message = ((e as Error)?.message || '换源失败').replace(/\s+/g, ' ').trim();
      this.update(item, BatchSwitchItem.MISSING, message.length > 24 ? `${message.substring(0, 24)}…` : message);
    }
  }

  private eligibleOf(book: Book, candidates: SearchBook[]): SearchBook[] {
    return BatchSourceSwitchPolicy.eligible(book.author,
      candidates.map((candidate: SearchBook): string => candidate.author || ''), this.fold)
      .map((index: number): SearchBook => candidates[index]);
  }

  /** 先用以前搜到过的候选；不够再搜，凑够要验证的个数或到时限就停。 */
  private async findCandidates(item: BatchSwitchItem, book: Book, cached: ChangeSourceCacheSnapshot):
    Promise<CandidateSearch> {
    const aliases = ChangeSourceResultCache.sameBookUrls(cached, book.origin, book.bookUrl);
    let all = ChangeSourceCandidates.filter(
      cached.results.filter((candidate: SearchBook): boolean => this.enabledSources.has(candidate.origin)), book, aliases);
    const result = new CandidateSearch();
    result.eligible = this.eligibleOf(book, all);
    result.sameName = all.length;
    if (result.eligible.length >= BatchSourceSwitchPolicy.MAX_VERIFIED) return result;
    const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
    this.coordinators.add(coordinator);
    let timer = -1;
    let finish: () => void = (): void => {};
    const cutoff = new Promise<void>((resolve: () => void): void => {
      finish = resolve;
      timer = setTimeout(resolve, BatchSourceSwitchPolicy.SEARCH_TIMEOUT_MS);
    });
    const search = coordinator.search(book.name, (progress: SearchProgress): void => {
      if (this.stopped) return;
      const delta = progress.finished ? progress.results : (progress.deltaResults || []);
      if (delta.length > 0) {
        ChangeSourceResultCache.merge(this.context, cached.key, delta);
        all = ChangeSourceCandidates.filter(all.concat(delta), book, aliases);
        result.eligible = this.eligibleOf(book, all);
        result.sameName = all.length;
      }
      item.detail = `已搜 ${progress.done}/${progress.total} 个书源 · 候选 ${result.eligible.length}`;
      this.onChanged();
      if (result.eligible.length >= BatchSourceSwitchPolicy.MAX_VERIFIED) finish();
    }, {
      exactMatch: true,
      leanResult: true,
      mediaCategory: BookTypeSupport.mediaCategoryOf(book),
      maxResultsPerSource: 5,
      maxTotalResults: 40,
      stopAfterResults: 16,
      maxCandidatesPerSource: 32,
      sourceGroups: this.scopeGroups.slice(),
      targetSources: this.sourcesFor(book),
      chineseScript: SearchChineseScriptRuntime.ready() || undefined
    }).then((): void => {}).catch((e: Error): void => console.warn('批量换源搜索失败:', book.name, e));
    try {
      await Promise.race([search, cutoff]);
    } finally {
      clearTimeout(timer);
      coordinator.cancel();
      this.coordinators.delete(coordinator);
    }
    return result;
  }

  /** 逐个取详情与目录；取到不比原目录短的就不再往下试。 */
  private async verify(item: BatchSwitchItem, book: Book, key: string, candidates: SearchBook[]):
    Promise<PreparedSourceSwitch[]> {
    const prepared: PreparedSourceSwitch[] = [];
    let attempts = 0;
    for (const candidate of candidates) {
      if (this.stopped || attempts >= BatchSourceSwitchPolicy.MAX_ATTEMPTS ||
        prepared.length >= BatchSourceSwitchPolicy.MAX_VERIFIED) break;
      attempts++;
      const name = (candidate.originName || candidate.origin || '').trim();
      item.detail = `正在读 ${name} 的目录`;
      this.onChanged();
      const task = new BookSourceSwitchTask(false, BatchSourceSwitchPolicy.CANDIDATE_TIMEOUT_MS);
      this.tasks.add(task);
      try {
        const entry = await task.prepare(this.context, key, book, candidate, null, (label: string): void => {
          const pages = label.split('：');
          if (pages.length < 2 || this.stopped) return;
          item.detail = `${name} · 目录${pages[1]}`;
          this.onChanged();
        });
        prepared.push(entry);
        if (BatchSourceSwitchPolicy.enough(entry.chapters.length, book.totalChapterNum, book.durChapterIndex)) break;
      } catch (e) {
        console.warn('批量换源候选不可用:', book.name, name, (e as Error)?.message || e);
      } finally {
        task.release();
        this.tasks.delete(task);
      }
    }
    return prepared;
  }
}
