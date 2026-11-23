import { Book, BookSource, SearchBook, BookTypeSupport } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { BookSourceSwitchTask } from '../core/book/BookSourceSwitchTask';
import { ChangeSourceResultCache } from '../utils/ChangeSourceResultCache';
import { ChangeSourceScope, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { BookSourceGroupStore } from '../utils/BookSourceGroupStore';
import { SourcePickerKit } from './home/SourcePickerKit';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { SearchChineseScriptRuntime } from '../core/book/SearchChineseScriptRuntime';
import { ChangeSourceCandidates } from '../core/book/ChangeSourceCandidates';
import { AuthorFold, ChangeSourceAuthorMatch } from '../core/book/ChangeSourceAuthorMatch';
import { SkippedSource, SourceFormProfile } from '../core/book/SourceFormProfile';
import { SourceFormJudge } from '../core/book/SourceFormJudge';

class ChangeSourceGroupOption {
  name: string = '';
  /** 组内可搜的启用书源数（含当前书源：聚合书源里别的子站也能换）。 */
  count: number = 0;
}

/**
 * 每个书源最多给几条候选。聚合书源一次搜索会返回多个子站的同名书，各占一条；
 * 普通书源同名不同作者的书也不会挤掉要找的那本。
 */
const MAX_RESULTS_PER_SOURCE: number = 5;

const SCOPE_ALL: string = SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_ALL;
const SCOPE_GROUP: string = SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_GROUP;
const SCOPE_SEARCH_DELAY_MS: number = 600;
/** 勾了其他形态时每种形态各取这么多条，免得小说站先把名额占满、漫画和短剧还没轮到。 */
const RESULTS_PER_FORM: number = 20;

/** 其他形态分段里的一行：段标题或一条结果。 */
class OtherFormRow {
  key: string = '';
  form: string = '';
  count: number = 0;
  first: boolean = false;
  book: SearchBook | null = null;
}

/**
 * 换源面板（书架长按"换源"与书籍详情页"换源"共用）。
 * 优先复用候选历史；首次打开或主动刷新时搜索。加载可取消，事务由独立任务完成。
 * 结果只保留与原书同类型的（小说换小说、漫画换漫画、有声换有声、视频换视频）。
 * 目标书在书库中已存在时提交换源并保留阅读进度与临时书标记；
 * 仅存在于搜索结果（未入库）时只把结果交给宿主页面，不落库。
 * 范围条：全部 / 组内（可多选分组），全局记住一份；改范围先按已有结果筛选，停手后再按新范围搜。
 * 组内搜不到可临时搜全部（不改记住的设置）；记住的分组都不在了自动退回全部并提示。
 * 作者校验：作者与原书不同的候选（同名的另一本书）默认收起，状态行给出个数，点“显示”后排在列表最后并标出；
 * 候选没给作者的照样显示，排在作者一致的后面。
 * 形态条：本书的形态总会搜，漫画、有声书、短剧等可多选“一起找”（全局记住）。搜之前按 SourceFormProfile 跳过
 * 不出这些形态的书源，状态行给出个数，可查看原因并设为“以后照搜”；挑出的书源里没找到本书形态时再搜一遍跳过的。
 * 其他形态的结果按形态分段列在后面，点“打开”进详情页另开一本，不替换正在读的这本。
 */
@Component
export struct BookChangeSourceDialog {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  targetBook: Book | null = null;
  onSwitched: (book: Book, previousUrl: string) => void = (_book: Book): void => {
  };
  onClosed: () => void = (): void => {
  };
  /** 切换提交前回调（宿主可先落盘阅读进度），完成后再开始切换。 */
  onBeforeSwitch: (() => Promise<void>) | null = null;
  /** 阅读器换源时标记阅读状态变量，避免章节 0/页 0 的切换被书架视为未读。 */
  markReadOnSwitch: boolean = false;

  @State results: SearchBook[] = [];
  @State status: string = '';
  @State searching: boolean = false;
  @State switching: boolean = false;
  @State selectedResultKey: string = '';
  @State scopeMode: string = SCOPE_ALL;
  @State scopeGroups: string[] = [];
  @State groupOptions: ChangeSourceGroupOption[] = [];
  /** 组内搜不到后点了“在全部书源中搜索”：只影响这次打开，记住的范围不变。 */
  @State tempAll: boolean = false;
  /** 组内时临时显示其他分组的结果（历史候选里会有）。 */
  @State showHidden: boolean = false;
  @State hiddenCount: number = 0;
  /** 这次打开里点了“显示”作者不同的候选。 */
  @State showAuthorMismatch: boolean = false;
  @State authorHiddenCount: number = 0;
  @State scopeNotice: string = '';
  /** 除本书形态外一起找的形态。 */
  @State extraForms: string[] = [];
  /** 其他形态的显示行（段标题 + 结果），按范围筛过。 */
  @State otherRows: OtherFormRow[] = [];
  @State otherCount: number = 0;
  /** 本次范围与形态下跳过的书源。 */
  @State skippedSources: SkippedSource[] = [];
  /** 跳过的书源这次已经补搜过（挑出的书源里没找到本书形态时）。 */
  @State skippedSearched: boolean = false;
  @State showSkipped: boolean = false;
  @State alwaysRevision: number = 0;
  private alwaysChanged: boolean = false;
  private enabledSources: BookSource[] = [];
  private keptSources: BookSource[] = [];
  /** 过滤掉当前这本与其他类型后的全部候选；results 是按范围筛过的显示列表。 */
  private allResults: SearchBook[] = [];
  private sourceGroupOf: Map<string, string> = new Map<string, string>();
  /** 候选（origin|bookUrl|author）与原书作者的比对结果，按当前作者算一次缓存起来。 */
  private authorRelationOf: Map<string, number> = new Map<string, number>();
  /** authorRelationOf 是否按简繁折叠后算的。 */
  private authorFoldUsed: boolean = false;
  private scopeSearchTimer: number = -1;
  private cacheKey: string = '';
  /** 同书源下指向当前这本的其他地址（换源时被详情改写前的搜索地址）。 */
  private currentBookAliases: string[] = [];
  private bookRevision: number = 0;
  private cacheContext: Context | null = null;
  private activeSwitch: BookSourceSwitchTask | null = null;
  private closed: boolean = false;
  private sessionId: number = 0;
  private activeCoordinator: SearchCoordinator | null = null;

  aboutToAppear(): void {
    if (!this.targetBook) {
      this.onClosed();
      return;
    }
    this.startSession();
  }

  aboutToDisappear(): void {
    this.closeWork();
  }

  startSession(): void {
    if (!this.targetBook) return;
    this.cancelActiveSearch();
    this.closed = false;
    this.cacheContext = getContext(this);
    this.bookRevision = BookSourceSwitchTask.revisionOf(this.targetBook);
    this.results = [];
    this.allResults = [];
    this.currentBookAliases = [];
    this.hiddenCount = 0;
    this.showHidden = false;
    this.authorHiddenCount = 0;
    this.showAuthorMismatch = false;
    this.authorRelationOf = new Map<string, number>();
    this.otherRows = [];
    this.otherCount = 0;
    this.skippedSources = [];
    this.skippedSearched = false;
    this.showSkipped = false;
    this.alwaysChanged = false;
    this.tempAll = false;
    this.status = '正在读取历史换源结果...';
    this.searching = true;
    this.switching = false;
    const sessionId = ++this.sessionId;
    this.loadScopeThenHistory(sessionId);
  }

  async loadScopeThenHistory(sessionId: number): Promise<void> {
    await this.loadScope();
    if (!this.isSessionActive(sessionId)) return;
    await this.loadHistoryThenSearch(sessionId);
  }

  /** 读取可选分组与记住的范围；记住的分组都已不存在（删除、改名或组内书源全停用）时退回全部。 */
  async loadScope(): Promise<void> {
    const context = this.cacheContext || getContext(this);
    try {
      await BookSourceGroupStore.loadOrder(context);
      const sources = await AppDatabase.getInstance().getEnabledBookSourcesForSearch();
      this.enabledSources = sources;
      const counts = new Map<string, number>();
      const groupOf = new Map<string, string>();
      for (const source of sources) {
        const url = source.bookSourceUrl || '';
        const group = SourcePickerKit.groupLabel(source.bookSourceGroup);
        if (url) groupOf.set(url, group);
        counts.set(group, (counts.get(group) || 0) + 1);
      }
      this.sourceGroupOf = groupOf;
      this.groupOptions = SourcePickerKit.sortGroups(Array.from(counts.keys())).map((name: string) => {
        const option = new ChangeSourceGroupOption();
        option.name = name;
        option.count = counts.get(name) || 0;
        return option;
      });
      const scope = await SearchExploreSettingsStore.loadChangeSourceScope(context);
      this.extraForms = scope.forms.filter((form: string): boolean => form !== this.ownForm());
      const available = scope.groups.filter((group: string): boolean => counts.has(group));
      this.scopeGroups = available;
      this.scopeMode = scope.mode === SCOPE_GROUP && available.length > 0 ? SCOPE_GROUP : SCOPE_ALL;
      if (scope.mode === SCOPE_GROUP && available.length === 0) {
        const name = scope.groups.length === 1 ? `“${scope.groups[0]}”` : '';
        this.scopeNotice = `上次选的分组${name}已不存在，已改为在全部书源中换源`;
      }
      if (available.length !== scope.groups.length || this.scopeMode !== scope.mode) this.persistScope();
    } catch (e) {
      console.warn('读取换源范围失败:', e);
      this.scopeMode = SCOPE_ALL;
    }
    try {
      await SourceFormProfile.load();
    } catch (e) {
      console.warn('读取书源形态失败:', e);
    }
    this.splitSourcesByForm();
  }

  ownForm(): string {
    return BookTypeSupport.mediaCategoryOf(this.targetBook);
  }

  searchForms(): string[] {
    return [this.ownForm()].concat(this.extraForms);
  }

  /**
   * 按当前范围和形态挑书源。一个都挑不出来时不跳过（照旧全搜）；
   * 没读到启用书源时 keptSources 为空，搜索层自己去读。
   */
  splitSourcesByForm(): void {
    const scoped = this.isScoped();
    const inScope = this.enabledSources.filter((source: BookSource): boolean =>
      !scoped || this.scopeGroups.includes(this.sourceGroupOf.get(source.bookSourceUrl || '') || ''));
    const split = SourceFormProfile.split(inScope, this.searchForms());
    if (split.kept.length === 0 || split.skipped.length === 0) {
      this.keptSources = [];
      this.skippedSources = [];
    } else {
      this.keptSources = split.kept;
      this.skippedSources = split.skipped;
    }
    this.skippedSearched = false;
  }

  async loadHistoryThenSearch(sessionId: number): Promise<void> {
    const book = this.targetBook;
    if (!book) return;
    try {
      const cached = await ChangeSourceResultCache.load(getContext(this), book);
      if (!this.isSessionActive(sessionId)) return;
      this.cacheKey = cached.key;
      this.currentBookAliases = ChangeSourceResultCache.sameBookUrls(cached, book.origin, book.bookUrl);
      const db = AppDatabase.getInstance();
      const available = await Promise.all(cached.results.map(async (item: SearchBook): Promise<boolean> => {
        const source = await db.getBookSource(item.origin);
        return !!source && source.enabled;
      }));
      if (!this.isSessionActive(sessionId)) return;
      await this.prepareAuthorFold(cached.results);
      if (!this.isSessionActive(sessionId)) return;
      this.allResults = this.filterResults(
        cached.results.filter((_item: SearchBook, index: number): boolean => available[index]), book.bookUrl, book.origin);
      this.applyScope();
      // 组内看不到历史候选时按组内重新搜；全部范围沿用原来的“搜过就不自动搜”。
      if (this.results.length > 0 || (cached.searched && !this.isScoped())) {
        this.searching = false;
        const age = cached.updatedAt > 0 ? new Date(cached.updatedAt).toLocaleString() : '此前';
        this.status = `历史结果 ${this.results.length} 个 · ${age}；点击刷新可重新搜索`;
        return;
      }
    } catch (e) {
      console.warn('读取换源历史结果失败:', e);
    }
    if (this.isSessionActive(sessionId)) {
      this.search(sessionId);
    }
  }

  refreshResults(): void {
    if (!this.targetBook || this.switching) return;
    this.cancelActiveSearch();
    const sessionId = ++this.sessionId;
    this.searching = true;
    this.status = '正在刷新可用书源...';
    this.search(sessionId);
  }

  private closeWork(): void {
    if (this.closed) return;
    this.closed = true;
    this.sessionId++;
    this.clearScopeSearchTimer();
    this.cancelActiveSearch();
    this.activeSwitch?.cancel();
    if (this.cacheContext) ChangeSourceResultCache.flush(this.cacheContext);
  }

  requestClose(): void {
    this.closeWork();
    this.onClosed();
  }

  /** skippedOnly：挑出的书源里没找到本书形态，再搜一遍跳过的书源。 */
  async search(sessionId: number, skippedOnly: boolean = false): Promise<void> {
    const target = this.targetBook;
    if (!target) return;
    const context = this.cacheContext || getContext(this);
    if (!skippedOnly) this.splitSourcesByForm();
    const targetSources = skippedOnly ?
      this.skippedSources.map((item: SkippedSource): BookSource => item.source) : this.keptSources.slice();
    const multiForm = this.extraForms.length > 0;
    const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
    this.activeCoordinator = coordinator;
    this.searching = true;
    this.status = skippedOnly ? `挑出的书源里没找到，正在搜跳过的 ${targetSources.length} 个书源...` : '正在搜索可用书源...';
    let fallback = false;
    try {
      // 简繁同搜：繁体站的同名书也能出现在换源列表里（书名折成简体比对）。
      const chineseScript = await SearchChineseScriptRuntime.forSearch(context);
      if (!this.isSessionActive(sessionId)) return;
      const results = await coordinator.search(target.name, (progress: SearchProgress) => {
        if (!this.isSessionActive(sessionId)) return;
        const found = progress.finished ? progress.results : (progress.deltaResults || []);
        if (found.length > 0 || progress.finished) ChangeSourceResultCache.merge(context, this.cacheKey, found);
        if (progress.finished) {
          this.allResults = this.filterResults(progress.results.concat(this.allResults), target.bookUrl, target.origin);
          this.applyScope();
        } else if (progress.deltaResults && progress.deltaResults.length > 0) {
          this.allResults = this.filterResults(
            progress.deltaResults.concat(this.allResults), target.bookUrl, target.origin);
          this.applyScope();
        }
        this.status = progress.status;
      }, {
        exactMatch: true,
        leanResult: true,
        mediaCategories: this.searchForms(),
        maxResultsPerSource: MAX_RESULTS_PER_SOURCE,
        maxTotalResults: multiForm ? 100 : 60,
        stopAfterResults: 20,
        maxResultsPerCategory: multiForm ? RESULTS_PER_FORM : undefined,
        maxCandidatesPerSource: 32,
        sourceGroups: this.isScoped() ? this.scopeGroups.slice() : [],
        targetSources: targetSources.length > 0 ? targetSources : undefined,
        chineseScript: chineseScript || undefined
      });
      SearchChineseScriptRuntime.saveHints(context);
      if (!this.isSessionActive(sessionId)) return;
      this.allResults = this.filterResults(results.concat(this.allResults), target.bookUrl, target.origin);
      this.applyScope();
      ChangeSourceResultCache.merge(context, this.cacheKey, results);
      ChangeSourceResultCache.flush(context);
      if (skippedOnly) this.skippedSearched = true;
      if (!skippedOnly && this.results.length === 0 && this.skippedSources.length > 0) {
        fallback = true;
      } else {
        this.status = this.finishedStatus();
      }
    } catch (e) {
      if (!this.isSessionActive(sessionId)) return;
      console.error('搜索换源失败:', e);
      this.status = '搜索换源失败';
    } finally {
      if (this.activeCoordinator === coordinator) {
        this.activeCoordinator = null;
      }
      if (this.isSessionActive(sessionId) && !fallback) {
        this.searching = false;
      }
    }
    if (fallback && this.isSessionActive(sessionId)) await this.search(sessionId, true);
  }

  finishedStatus(): string {
    if (this.results.length > 0) {
      return this.otherCount > 0 ? `搜索完成，找到 ${this.results.length} 个可切换书源，另有 ${this.otherCount} 个其他形态` :
        `搜索完成，找到 ${this.results.length} 个可切换书源`;
    }
    if (this.otherCount > 0) {
      return `搜索完成，没有同为${SourceFormJudge.label(this.ownForm())}的书源，找到 ${this.otherCount} 个其他形态`;
    }
    return this.isScoped() ? '搜索完成，所选分组内未找到' : '搜索完成，未找到可切换书源';
  }

  async switchSource(searchBook: SearchBook): Promise<void> {
    const target = this.targetBook;
    if (!target || this.switching || this.closed) return;
    this.cancelActiveSearch();
    this.searching = false;
    const sessionId = ++this.sessionId;
    this.switching = true;
    this.selectedResultKey = searchBook.origin + '|' + searchBook.bookUrl;
    const context = this.cacheContext || getContext(this);
    ChangeSourceResultCache.merge(context, this.cacheKey, this.allResults, false);
    ChangeSourceResultCache.flush(context);
    const task = new BookSourceSwitchTask(this.markReadOnSwitch);
    this.activeSwitch = task;
    const deliver = this.onSwitched;
    try {
      const fullBook = await task.run(context, this.cacheKey, target, searchBook, this.onBeforeSwitch,
        (label: string): void => { if (this.isSessionActive(sessionId)) this.status = label; }, deliver, this.bookRevision);
      HdsFeedback.showToast('已切换至 ' + (fullBook.originName || searchBook.originName));
      if (this.isSessionActive(sessionId)) this.requestClose();
    } catch (error) {
      if (!this.isSessionActive(sessionId)) {
        if (task.isCommitting()) HdsFeedback.showToast('换源保存失败，已保留原书源');
        return;
      }
      this.status = (error as Error).message || '切换书源失败，已保留原书源';
      HdsFeedback.showToast(this.status);
    } finally {
      if (this.activeSwitch === task) this.activeSwitch = null;
      if (this.isSessionActive(sessionId)) {
        this.switching = false;
        this.selectedResultKey = '';
      }
    }
  }

  isSessionActive(sessionId: number): boolean {
    return sessionId === this.sessionId;
  }

  cancelActiveSearch(): void {
    this.clearScopeSearchTimer();
    if (this.activeCoordinator) {
      this.activeCoordinator.cancel();
      this.activeCoordinator = null;
    }
  }

  isScoped(): boolean {
    return this.scopeMode === SCOPE_GROUP && !this.tempAll && this.scopeGroups.length > 0;
  }

  /**
   * 按当前范围和作者校验从 allResults 筛出显示列表，并记下两类被藏起来的个数。
   * 显示顺序：作者一致 → 作者未知 → 作者不同（点了“显示”才有）。
   */
  applyScope(): void {
    const scoped = this.isScoped() && !this.showHidden;
    const groups = this.scopeGroups;
    const same: SearchBook[] = [];
    const unknown: SearchBook[] = [];
    const different: SearchBook[] = [];
    const others: SearchBook[] = [];
    const ownForm = this.ownForm();
    let otherGroups = 0;
    let authorHidden = 0;
    for (const book of this.allResults) {
      if (BookTypeSupport.mediaCategoryOf(book) !== ownForm) {
        if (this.extraForms.includes(BookTypeSupport.mediaCategoryOf(book)) &&
          (!scoped || groups.includes(this.sourceGroupOf.get(book.origin) || ''))) {
          others.push(book);
        }
        continue;
      }
      const relation = this.authorRelation(book);
      const authorShown = relation !== ChangeSourceAuthorMatch.DIFFERENT || this.showAuthorMismatch;
      if (scoped && !groups.includes(this.sourceGroupOf.get(book.origin) || '')) {
        if (authorShown) otherGroups++;
        continue;
      }
      if (!authorShown) {
        authorHidden++;
      } else if (relation === ChangeSourceAuthorMatch.SAME) {
        same.push(book);
      } else if (relation === ChangeSourceAuthorMatch.UNKNOWN) {
        unknown.push(book);
      } else {
        different.push(book);
      }
    }
    this.results = same.concat(unknown, different);
    this.hiddenCount = otherGroups;
    this.authorHiddenCount = authorHidden;
    this.buildOtherRows(others);
  }

  /** 其他形态按形态条的顺序分段；改编作品作者常写法不同，不收起，只把作者一致的排前面。 */
  buildOtherRows(others: SearchBook[]): void {
    const rows: OtherFormRow[] = [];
    let first = true;
    for (const form of SearchExploreSettingsStore.CHANGE_SOURCE_FORMS) {
      if (!this.extraForms.includes(form)) continue;
      const books = others.filter((book: SearchBook): boolean => BookTypeSupport.mediaCategoryOf(book) === form);
      if (books.length === 0) continue;
      const header = new OtherFormRow();
      header.key = `form|${form}|${books.length}`;
      header.form = form;
      header.count = books.length;
      header.first = first;
      first = false;
      rows.push(header);
      const sameAuthor = books.filter((book: SearchBook): boolean =>
        this.authorRelation(book) === ChangeSourceAuthorMatch.SAME);
      const rest = books.filter((book: SearchBook): boolean =>
        this.authorRelation(book) !== ChangeSourceAuthorMatch.SAME);
      for (const book of sameAuthor.concat(rest)) {
        const row = new OtherFormRow();
        row.key = `book|${book.origin}|${book.bookUrl}`;
        row.form = form;
        row.book = book;
        rows.push(row);
      }
    }
    this.otherRows = rows;
    this.otherCount = others.length;
  }

  private authorFold(): AuthorFold {
    const script = SearchChineseScriptRuntime.ready();
    return script ? (text: string): string => script.fold(text) : null;
  }

  authorRelation(book: SearchBook): number {
    const fold = this.authorFold();
    // 简繁字典后加载好时，之前按原字算的结果作废重算。
    if (!!fold !== this.authorFoldUsed) {
      this.authorRelationOf.clear();
      this.authorFoldUsed = !!fold;
    }
    const key = `${book.origin || ''}|${book.bookUrl}|${book.author || ''}`;
    const cached = this.authorRelationOf.get(key);
    if (cached !== undefined) return cached;
    const relation = ChangeSourceAuthorMatch.compare(this.targetBook?.author || '', book.author || '', fold);
    this.authorRelationOf.set(key, relation);
    return relation;
  }

  /** 历史结果里有作者对不上的，先把简繁字典读进来，免得繁体站的同一作者被当成不同。 */
  async prepareAuthorFold(results: SearchBook[]): Promise<void> {
    if (!SearchChineseScriptRuntime.enabled() || SearchChineseScriptRuntime.ready()) return;
    const author = this.targetBook?.author || '';
    const mismatch = results.some((book: SearchBook): boolean =>
      ChangeSourceAuthorMatch.compare(author, book.author || '') === ChangeSourceAuthorMatch.DIFFERENT);
    if (mismatch) await SearchChineseScriptRuntime.forSearch(this.cacheContext || getContext(this));
  }

  revealAuthorMismatch(): void {
    this.showAuthorMismatch = true;
    this.applyScope();
  }

  authorTip(): string {
    return this.authorHiddenCount > 0 && !this.showAuthorMismatch ? `；${this.authorHiddenCount} 个作者不同，` : '';
  }

  authorLink(): string {
    return this.authorHiddenCount > 0 && !this.showAuthorMismatch ? '显示' : '';
  }

  isAuthorMismatch(book: SearchBook): boolean {
    return this.authorRelation(book) === ChangeSourceAuthorMatch.DIFFERENT;
  }

  selectScopeMode(mode: string): void {
    if (this.switching) return;
    if (mode === SCOPE_ALL) {
      if (this.scopeMode === SCOPE_ALL) return;
      this.scopeMode = SCOPE_ALL;
    } else {
      if (this.scopeMode === SCOPE_GROUP && !this.tempAll) return;
      if (this.scopeGroups.length === 0) {
        const fallback = this.defaultScopeGroup();
        if (!fallback) {
          HdsFeedback.showToast('没有可选的书源分组');
          return;
        }
        this.scopeGroups = [fallback];
      }
      this.scopeMode = SCOPE_GROUP;
    }
    this.tempAll = false;
    this.onScopeChanged();
  }

  toggleScopeGroup(name: string): void {
    if (this.switching) return;
    const selected = this.scopeGroups.includes(name);
    if (this.tempAll) {
      // 临时搜全部时点分组，先回到组内；点的是唯一选中的那个就只回到组内。
      this.tempAll = false;
      if (!selected) {
        this.scopeGroups = this.scopeGroups.concat([name]);
      } else if (this.scopeGroups.length > 1) {
        this.scopeGroups = this.scopeGroups.filter((group: string): boolean => group !== name);
      }
    } else if (selected) {
      if (this.scopeGroups.length <= 1) {
        HdsFeedback.showToast('至少保留一个分组');
        return;
      }
      this.scopeGroups = this.scopeGroups.filter((group: string): boolean => group !== name);
    } else {
      this.scopeGroups = this.scopeGroups.concat([name]);
    }
    this.onScopeChanged();
  }

  /** 首次切到组内：优先当前书源所在分组，其次第一个有书源可搜的分组。 */
  defaultScopeGroup(): string {
    const current = this.sourceGroupOf.get(this.targetBook?.origin || '') || '';
    const currentOption = this.groupOptions.find((option: ChangeSourceGroupOption): boolean => option.name === current);
    if (currentOption && currentOption.count > 0) return current;
    const first = this.groupOptions.find((option: ChangeSourceGroupOption): boolean => option.count > 0);
    return first ? first.name : (this.groupOptions.length > 0 ? this.groupOptions[0].name : '');
  }

  /** 范围变了：立即保存并按新范围筛已有结果，停手一会儿再搜，连点几个分组只搜一次。 */
  onScopeChanged(): void {
    if (!this.targetBook) return;
    this.scopeNotice = '';
    this.showHidden = false;
    this.showSkipped = false;
    this.persistScope();
    this.splitSourcesByForm();
    this.cancelActiveSearch();
    const sessionId = ++this.sessionId;
    this.applyScope();
    this.searching = true;
    this.status = '正在按新范围搜索...';
    this.scopeSearchTimer = setTimeout((): void => {
      this.scopeSearchTimer = -1;
      if (this.isSessionActive(sessionId)) this.search(sessionId);
    }, SCOPE_SEARCH_DELAY_MS);
  }

  /** 组内没找到时只这一次搜全部。 */
  expandToAllSources(): void {
    if (!this.targetBook || this.switching) return;
    this.tempAll = true;
    this.showHidden = false;
    this.applyScope();
    this.refreshResults();
  }

  makeAllScopeDefault(): void {
    this.scopeMode = SCOPE_ALL;
    this.tempAll = false;
    this.persistScope();
    this.applyScope();
  }

  revealHiddenResults(): void {
    this.showHidden = true;
    this.applyScope();
  }

  persistScope(): void {
    const scope = new ChangeSourceScope();
    scope.mode = this.scopeMode;
    scope.groups = this.scopeGroups.slice();
    scope.forms = this.extraForms.slice();
    SearchExploreSettingsStore.saveChangeSourceScope(this.cacheContext || getContext(this), scope)
      .catch((e: Error): void => { console.warn('保存换源范围失败:', e); });
  }

  clearScopeSearchTimer(): void {
    if (this.scopeSearchTimer !== -1) {
      clearTimeout(this.scopeSearchTimer);
      this.scopeSearchTimer = -1;
    }
  }

  scopeSourceCount(): number {
    let total = 0;
    for (const option of this.groupOptions) {
      if (!this.isScoped() || this.scopeGroups.includes(option.name)) total += option.count;
    }
    return total;
  }

  scopeSummary(): string {
    return this.isScoped() ? `${this.scopeSourceCount()} 个书源` : `全部 ${this.scopeSourceCount()} 个书源`;
  }

  hiddenTip(): string {
    return this.hiddenCount > 0 && !this.showHidden ? `；另有 ${this.hiddenCount} 个在其他分组，` : '';
  }

  hiddenLink(): string {
    return this.hiddenCount > 0 && !this.showHidden ? '显示全部' : '';
  }

  resultGroupLabel(book: SearchBook): string {
    return this.sourceGroupOf.get(book.origin) || '';
  }

  filterResults(results: SearchBook[], currentBookUrl: string, currentOrigin: string): SearchBook[] {
    const target = this.targetBook;
    if (!target || target.bookUrl !== currentBookUrl || target.origin !== currentOrigin) return [];
    return ChangeSourceCandidates.filter(results, target, this.currentBookAliases, this.extraForms);
  }

  /** 勾选或取消一起找的形态：记住，按已有结果先筛，停手后再搜（与改范围一样）。 */
  toggleForm(form: string): void {
    if (this.switching) return;
    if (form === this.ownForm()) {
      HdsFeedback.showToast(`本书是${SourceFormJudge.label(form)}，总会搜`);
      return;
    }
    this.extraForms = this.extraForms.includes(form) ?
      this.extraForms.filter((item: string): boolean => item !== form) :
      SearchExploreSettingsStore.CHANGE_SOURCE_FORMS.filter((item: string): boolean =>
        item === form || this.extraForms.includes(item));
    // 取消勾选后历史候选里那些形态的结果也不再要；勾选的形态等搜索补上。
    this.allResults = this.allResults.filter((book: SearchBook): boolean =>
      BookTypeSupport.mediaCategoryOf(book) === this.ownForm() ||
        this.extraForms.includes(BookTypeSupport.mediaCategoryOf(book)));
    this.onScopeChanged();
  }

  isFormSelected(form: string): boolean {
    return form === this.ownForm() || this.extraForms.includes(form);
  }

  formChipLabel(form: string): string {
    return form === this.ownForm() ? `${SourceFormJudge.label(form)} · 本书` : SourceFormJudge.label(form);
  }

  skipTip(): string {
    if (this.skippedSources.length === 0) return '';
    return this.skippedSearched ? `；跳过的 ${this.skippedSources.length} 个书源也搜过了，` :
      `；按形态跳过 ${this.skippedSources.length} 个书源，`;
  }

  skipLink(): string {
    return this.skipTip() ? '查看' : '';
  }

  openSkipped(): void {
    if (this.skippedSources.length === 0) return;
    this.alwaysChanged = false;
    this.showSkipped = true;
  }

  /** 从跳过列表回到结果；改过“照搜”就按新判断重搜。 */
  closeSkipped(): void {
    this.showSkipped = false;
    if (this.alwaysChanged) {
      this.alwaysChanged = false;
      this.refreshResults();
    }
  }

  toggleAlways(item: SkippedSource): void {
    const url = item.source.bookSourceUrl || '';
    SourceFormProfile.setAlways(url, !SourceFormProfile.isAlways(url));
    this.alwaysChanged = true;
    this.alwaysRevision++;
  }

  clearAlways(): void {
    SourceFormProfile.clearAlways();
    this.alwaysChanged = true;
    this.alwaysRevision++;
  }

  isAlways(item: SkippedSource, _revision: number): boolean {
    return SourceFormProfile.isAlways(item.source.bookSourceUrl || '');
  }

  /** 列表外另有设为照搜的书源个数（换别的书时设的）。 */
  otherAlwaysCount(_revision: number): number {
    let inList = 0;
    for (const item of this.skippedSources) {
      if (SourceFormProfile.isAlways(item.source.bookSourceUrl || '')) inList++;
    }
    return SourceFormProfile.alwaysCount() - inList;
  }

  /** 其他形态的结果进详情页另开一本；先关掉换源面板。 */
  openOtherForm(book: SearchBook): void {
    if (this.switching) return;
    const uiContext = this.getUIContext();
    this.requestClose();
    uiContext.getRouter().pushUrl({
      url: 'pages/SearchBookDetail',
      params: {
        bookUrl: book.bookUrl,
        tocUrl: book.tocUrl,
        origin: book.origin,
        originName: book.originName,
        name: book.name,
        author: book.author,
        kind: book.kind,
        status: book.status,
        coverUrl: book.coverUrl,
        intro: book.intro,
        latestChapterTitle: book.latestChapterTitle,
        updateTime: book.updateTime,
        wordCount: book.wordCount,
        type: String(book.type || 0),
        variable: book.variable || ''
      }
    }).catch((e: Error): void => { console.warn('打开其他形态失败:', e); });
  }

  build() {
    Column() {
      Row() {
        Column({ space: AppSpacing.XXS }) {
          Row({ space: AppSpacing.LG }) {
            Text('换源')
              .fontSize(AppFontSize.TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
            if (this.groupOptions.length > 0) {
              this.scopeSwitch()
            }
          }
          .alignItems(VerticalAlign.Center)
          Text(this.subtitleText())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (!this.searching) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(21)
            .fontColor([this.primaryTextColor()])
            .width(40)
            .height(40)
            .margin({ right: AppSpacing.XS })
            .onClick(() => this.refreshResults())
        }
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([this.primaryTextColor()])
          .width(40)
          .height(40)
          .onClick(() => {
            this.requestClose();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.groupOptions.length > 0 && this.scopeMode === SCOPE_GROUP) {
        this.scopeGroupChips()
      }
      this.formChips()

      if (this.scopeNotice) {
        Text(this.scopeNotice)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.warningColor(this.appDarkMode))
          .width('100%')
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
          .borderRadius(ThemeRuntime.smallRadius())
          .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
          .margin({ top: AppSpacing.MD })
      }

      if (this.tempAll && this.scopeMode === SCOPE_GROUP) {
        Row({ space: AppSpacing.MD }) {
          Text('本次临时搜全部，默认仍是组内')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.accentColor())
            .layoutWeight(1)
          Text('改为默认')
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
            .onClick(() => this.makeAllScopeDefault())
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
        .borderRadius(ThemeRuntime.smallRadius())
        .backgroundColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .margin({ top: AppSpacing.MD })
      }

      Text() {
        Span(this.status || '将使用当前书名进行全词匹配搜索')
        Span(this.hiddenTip())
        Span(this.hiddenLink())
          .fontColor(this.accentColor())
          .onClick(() => this.revealHiddenResults())
        Span(this.authorTip())
        Span(this.authorLink())
          .fontColor(this.accentColor())
          .onClick(() => this.revealAuthorMismatch())
        Span(this.skipTip())
        Span(this.skipLink())
          .fontColor(this.accentColor())
          .onClick(() => this.openSkipped())
      }
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ top: AppSpacing.MD, bottom: AppSpacing.MD })

      if (this.showSkipped) {
        this.skippedList()
      } else if (this.searching && this.results.length === 0 && this.otherCount === 0) {
        Column({ space: AppSpacing.MD }) {
          LoadingProgress().width(36).height(36)
          Text('正在搜索可用书源...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .height(260)
        .justifyContent(FlexAlign.Center)
      } else if (this.results.length === 0 && this.otherCount === 0 && this.isScoped()) {
        Column({ space: AppSpacing.LG }) {
          Text('所选分组里没有找到这本书')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
          Button('在全部书源中搜索')
            .height(36)
            .fontSize(AppFontSize.BODY)
            .borderRadius(18)
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
            .backgroundColor(this.buttonColor())
            .fontColor(ThemeRuntime.onAccentColor())
            .enabled(!this.switching)
            .onClick(() => this.expandToAllSources())
        }
        .width('100%')
        .height(260)
        .justifyContent(FlexAlign.Center)
      } else if (this.results.length === 0 && this.otherCount === 0) {
        Text('暂无可切换书源')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.subTextColor())
          .width('100%')
          .height(260)
          .textAlign(TextAlign.Center)
      } else {
        List({ space: AppSpacing.MD }) {
          if (this.results.length === 0) {
            ListItem() {
              Text(`没有找到同为${SourceFormJudge.label(this.ownForm())}的书源`)
                .fontSize(AppFontSize.BODY)
                .fontColor(this.subTextColor())
                .width('100%')
                .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
            }
          }
          ForEach(this.results, (book: SearchBook) => {
            ListItem() {
              Row() {
                Column({ space: AppSpacing.XS }) {
                  Row({ space: AppSpacing.SM }) {
                    Text(book.originName || book.origin)
                      .fontSize(AppFontSize.BODY_LARGE)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.primaryTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .flexShrink(1)
                    if (this.resultGroupLabel(book)) {
                      Text(this.resultGroupLabel(book))
                        .fontSize(AppFontSize.MICRO + 1)
                        .fontColor(this.subTextColor())
                        .maxLines(1)
                        .height(18)
                        .padding({ left: AppSpacing.SM, right: AppSpacing.SM })
                        .borderRadius(9)
                        .border({ width: 1, color: ThemeRuntime.dividerColor(this.appDarkMode) })
                        .flexShrink(0)
                    }
                  }
                  .width('100%')
                  if (this.isAuthorMismatch(book)) {
                    Row({ space: AppSpacing.XS }) {
                      Text(`作者：${book.author}`)
                        .fontSize(AppFontSize.CAPTION)
                        .fontColor(ThemeRuntime.warningColor(this.appDarkMode))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .flexShrink(1)
                      Text('作者不同')
                        .fontSize(AppFontSize.MICRO)
                        .fontColor(ThemeRuntime.warningColor(this.appDarkMode))
                        .height(16)
                        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
                        .borderRadius(4)
                        .border({ width: 1, color: ThemeRuntime.warningColor(this.appDarkMode) })
                        .flexShrink(0)
                    }
                    .width('100%')
                  } else {
                    Text(`作者：${book.author || '未知'}`)
                      .fontSize(AppFontSize.CAPTION)
                      .fontColor(this.subTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  Text(`最新：${book.latestChapterTitle || '书源未提供'}`)
                    .fontSize(AppFontSize.CAPTION)
                    .fontColor(this.subTextColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button(this.selectedResultKey === (book.origin + '|' + book.bookUrl) ? '切换中' : '切换')
                  .width(68)
                  .height(32)
                  .fontSize(AppFontSize.BODY)
                  .borderRadius(16)
                  .backgroundColor(this.buttonColor())
                  .fontColor(ThemeRuntime.onAccentColor())
                  .enabled(!this.switching)
                  .onClick(() => this.switchSource(book))
              }
              .width('100%')
              .padding(AppSpacing.LG)
              .backgroundColor(this.inputColor())
              .borderRadius(ThemeRuntime.mediumRadius())
            }
          }, (book: SearchBook) => `${book.origin}|${book.bookUrl}`)

          ForEach(this.otherRows, (row: OtherFormRow) => {
            ListItem() {
              if (row.book) {
                this.otherFormCard(row.book, row.form)
              } else {
                Column({ space: AppSpacing.XXS }) {
                  Text(`${SourceFormJudge.label(row.form)} · ${row.count}`)
                    .fontSize(AppFontSize.CAPTION)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.subTextColor())
                  if (row.first) {
                    Text('点“打开”另开一本，不会替换正在读的这本')
                      .fontSize(AppFontSize.CAPTION)
                      .fontColor(this.subTextColor())
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ top: AppSpacing.MD })
              }
            }
          }, (row: OtherFormRow): string => row.key)

          if (this.searching) {
            ListItem() {
              Row({ space: AppSpacing.MD }) {
                LoadingProgress().width(20).height(20)
                Text('继续加载中...').fontSize(AppFontSize.BODY).fontColor(this.subTextColor())
              }
              .width('100%')
              .height(42)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .height(340)
      }
    }
    .width('100%')
    .padding(AppSpacing.XXL)
    .clip(true)
  }

  @Builder
  scopeSwitch() {
    Row() {
      this.scopeSegment('全部', SCOPE_ALL)
      this.scopeSegment('组内', SCOPE_GROUP)
    }
    .padding(2)
    .borderRadius(15)
    .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
  }

  /** 书名后接本次会搜的书源数。 */
  subtitleText(): string {
    const name = `《${this.targetBook?.name || ''}》`;
    return this.groupOptions.length > 0 ? `${name} · ${this.scopeSummary()}` : name;
  }

  @Builder
  scopeGroupChips() {
    Scroll() {
      Row({ space: AppSpacing.MD }) {
        ForEach(this.groupOptions, (option: ChangeSourceGroupOption) => {
          Row({ space: AppSpacing.XS }) {
            Text(option.name)
              .fontSize(AppFontSize.BODY - 1)
              .fontColor(this.isGroupChipSelected(option.name) ? this.accentColor() : this.primaryTextColor())
            Text(`${option.count}`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.isGroupChipSelected(option.name) ? this.accentColor() : this.subTextColor())
          }
          .height(30)
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
          .borderRadius(15)
          .border({
            width: 1,
            color: this.isGroupChipSelected(option.name) ? this.accentColor() :
              ThemeRuntime.dividerColor(this.appDarkMode)
          })
          .backgroundColor(this.isGroupChipSelected(option.name) ?
            ThemeRuntime.selectedFillColor(this.appDarkMode) : Color.Transparent)
          .accessibilityText(`${option.name}，${option.count} 个书源`)
          .accessibilitySelected(this.isGroupChipSelected(option.name))
          .onClick(() => this.toggleScopeGroup(option.name))
        }, (option: ChangeSourceGroupOption): string => `${option.name}|${option.count}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .margin({ top: AppSpacing.LG })
  }

  /** 形态条：本书形态常亮，其他形态可多选一起找。 */
  @Builder
  formChips() {
    Row({ space: AppSpacing.MD }) {
      Text('形态')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .flexShrink(0)
      Scroll() {
        Row({ space: AppSpacing.MD }) {
          ForEach(SearchExploreSettingsStore.CHANGE_SOURCE_FORMS, (form: string) => {
            Text(this.formChipLabel(form))
              .fontSize(AppFontSize.BODY - 1)
              .fontColor(this.isFormSelected(form) ? this.accentColor() : this.primaryTextColor())
              .height(30)
              .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
              .borderRadius(15)
              .border({
                width: 1,
                color: this.isFormSelected(form) ? this.accentColor() : ThemeRuntime.dividerColor(this.appDarkMode)
              })
              .backgroundColor(this.isFormSelected(form) ? ThemeRuntime.selectedFillColor(this.appDarkMode) :
                Color.Transparent)
              .accessibilityText(form === this.ownForm() ? `${SourceFormJudge.label(form)}，本书形态，总会搜` :
                `一起找${SourceFormJudge.label(form)}`)
              .accessibilitySelected(this.isFormSelected(form))
              .onClick(() => this.toggleForm(form))
          }, (form: string): string => `${form}|${this.isFormSelected(form)}|${form === this.ownForm()}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: AppSpacing.LG })
  }

  @Builder
  otherFormCard(book: SearchBook, form: string) {
    Row() {
      Column({ space: AppSpacing.XS }) {
        Row({ space: AppSpacing.SM }) {
          Text(book.originName || book.origin)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          Text(SourceFormJudge.label(form))
            .fontSize(AppFontSize.MICRO + 1)
            .fontColor(this.accentColor())
            .maxLines(1)
            .height(18)
            .padding({ left: AppSpacing.SM, right: AppSpacing.SM })
            .borderRadius(9)
            .border({ width: 1, color: this.accentColor() })
            .flexShrink(0)
        }
        .width('100%')
        Text(`作者：${book.author || '未知'}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`最新：${book.latestChapterTitle || '书源未提供'}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('打开')
        .width(68)
        .height(32)
        .fontSize(AppFontSize.BODY)
        .borderRadius(16)
        .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
        .fontColor(this.accentColor())
        .enabled(!this.switching)
        .onClick(() => this.openOtherForm(book))
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .backgroundColor(this.inputColor())
    .borderRadius(ThemeRuntime.mediumRadius())
  }

  /** 按形态跳过的书源与原因；可逐个设为“以后照搜”，回到结果时按新判断重搜。 */
  @Builder
  skippedList() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        Text(`按形态跳过的 ${this.skippedSources.length} 个书源`)
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text('返回结果')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.accentColor())
          .onClick(() => this.closeSkipped())
      }
      .width('100%')
      Text(`判断它们不出${this.searchForms().map((form: string): string => SourceFormJudge.label(form)).join('、')}。` +
        '设为“以后照搜”后，换别的书时也照搜。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      List({ space: AppSpacing.SM }) {
        ForEach(this.skippedSources, (item: SkippedSource) => {
          ListItem() {
            Row({ space: AppSpacing.MD }) {
              Column({ space: AppSpacing.XXS }) {
                Text(item.source.bookSourceName || item.source.bookSourceUrl)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(this.primaryTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.reason)
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(this.subTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Button(this.isAlways(item, this.alwaysRevision) ? '撤销' : '以后照搜')
                .height(30)
                .fontSize(AppFontSize.CAPTION)
                .borderRadius(15)
                .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
                .backgroundColor(this.isAlways(item, this.alwaysRevision) ? this.buttonColor() :
                  ThemeRuntime.softFillColor(this.appDarkMode))
                .fontColor(this.isAlways(item, this.alwaysRevision) ? ThemeRuntime.onAccentColor() :
                  this.accentColor())
                .onClick(() => this.toggleAlways(item))
            }
            .width('100%')
            .padding({ left: AppSpacing.LG, right: AppSpacing.MD, top: AppSpacing.MD, bottom: AppSpacing.MD })
            .backgroundColor(this.inputColor())
            .borderRadius(ThemeRuntime.mediumRadius())
          }
        }, (item: SkippedSource): string => `${item.source.bookSourceUrl}|${this.alwaysRevision}`)
        if (this.otherAlwaysCount(this.alwaysRevision) > 0) {
          ListItem() {
            Text() {
              Span(`另有 ${this.otherAlwaysCount(this.alwaysRevision)} 个书源设为照搜，`)
              Span('全部恢复自动判断')
                .fontColor(this.accentColor())
                .onClick(() => this.clearAlways())
            }
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .width('100%')
            .padding({ top: AppSpacing.SM })
          }
        }
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(340)
  }

  @Builder
  scopeSegment(label: string, mode: string) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontWeight(this.scopeMode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.scopeMode === mode ? this.accentColor() : this.subTextColor())
      .height(26)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(13)
      .backgroundColor(this.scopeMode === mode ? ThemeRuntime.selectedFillColor(this.appDarkMode) : Color.Transparent)
      .accessibilitySelected(this.scopeMode === mode)
      .onClick(() => this.selectScopeMode(mode))
  }

  /** 临时搜全部时分组标签仍按记住的选择高亮，便于看出点回去会搜哪些。 */
  isGroupChipSelected(name: string): boolean {
    return this.scopeGroups.includes(name);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }
}
