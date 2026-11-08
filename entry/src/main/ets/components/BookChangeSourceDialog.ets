import { Book, SearchBook, BookTypeSupport } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { BookSourceSwitchTask } from '../core/book/BookSourceSwitchTask';
import { ChangeSourceResultCache } from '../utils/ChangeSourceResultCache';
import { ChangeSourceScope, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { BookSourceGroupStore } from '../utils/BookSourceGroupStore';
import { SourcePickerKit } from './home/SourcePickerKit';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { SearchChineseScriptRuntime } from '../core/book/SearchChineseScriptRuntime';

class ChangeSourceGroupOption {
  name: string = '';
  /** 组内可搜的启用书源数，不含当前书源。 */
  count: number = 0;
}

const SCOPE_ALL: string = SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_ALL;
const SCOPE_GROUP: string = SearchExploreSettingsStore.CHANGE_SOURCE_SCOPE_GROUP;
const SCOPE_SEARCH_DELAY_MS: number = 600;

/**
 * 换源面板（书架长按"换源"与书籍详情页"换源"共用）。
 * 优先复用候选历史；首次打开或主动刷新时搜索。加载可取消，事务由独立任务完成。
 * 结果只保留与原书同类型的（小说换小说、漫画换漫画、有声换有声、视频换视频）。
 * 目标书在书库中已存在时提交换源并保留阅读进度与临时书标记；
 * 仅存在于搜索结果（未入库）时只把结果交给宿主页面，不落库。
 * 范围条：全部 / 组内（可多选分组），全局记住一份；改范围先按已有结果筛选，停手后再按新范围搜。
 * 组内搜不到可临时搜全部（不改记住的设置）；记住的分组都不在了自动退回全部并提示。
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
  @State scopeNotice: string = '';
  /** 过滤掉当前书源与其他类型后的全部候选；results 是按范围筛过的显示列表。 */
  private allResults: SearchBook[] = [];
  private sourceGroupOf: Map<string, string> = new Map<string, string>();
  private scopeSearchTimer: number = -1;
  private cacheKey: string = '';
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
    this.hiddenCount = 0;
    this.showHidden = false;
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
      const origin = this.targetBook?.origin || '';
      const counts = new Map<string, number>();
      const groupOf = new Map<string, string>();
      for (const source of sources) {
        const url = source.bookSourceUrl || '';
        const group = SourcePickerKit.groupLabel(source.bookSourceGroup);
        if (url) groupOf.set(url, group);
        // 只有当前书源的分组也算存在，记住的范围不能因此被清掉，只是个数为 0。
        counts.set(group, (counts.get(group) || 0) + (url && url === origin ? 0 : 1));
      }
      this.sourceGroupOf = groupOf;
      this.groupOptions = SourcePickerKit.sortGroups(Array.from(counts.keys())).map((name: string) => {
        const option = new ChangeSourceGroupOption();
        option.name = name;
        option.count = counts.get(name) || 0;
        return option;
      });
      const scope = await SearchExploreSettingsStore.loadChangeSourceScope(context);
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
  }

  async loadHistoryThenSearch(sessionId: number): Promise<void> {
    const book = this.targetBook;
    if (!book) return;
    try {
      const cached = await ChangeSourceResultCache.load(getContext(this), book);
      if (!this.isSessionActive(sessionId)) return;
      this.cacheKey = cached.key;
      const db = AppDatabase.getInstance();
      const available = await Promise.all(cached.results.map(async (item: SearchBook): Promise<boolean> => {
        const source = await db.getBookSource(item.origin);
        return !!source && source.enabled;
      }));
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

  async search(sessionId: number): Promise<void> {
    const target = this.targetBook;
    if (!target) return;
    const context = this.cacheContext || getContext(this);
    const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
    this.activeCoordinator = coordinator;
    this.searching = true;
    this.status = '正在搜索可用书源...';
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
        if (progress.finished) this.searching = false;
      }, {
        exactMatch: true,
        leanResult: true,
        excludeSourceUrls: [target.origin],
        mediaCategory: BookTypeSupport.mediaCategoryOf(target),
        maxResultsPerSource: 1,
        maxTotalResults: 60,
        stopAfterResults: 20,
        maxCandidatesPerSource: 32,
        sourceGroups: this.isScoped() ? this.scopeGroups.slice() : [],
        chineseScript: chineseScript || undefined
      });
      SearchChineseScriptRuntime.saveHints(context);
      if (!this.isSessionActive(sessionId)) return;
      this.allResults = this.filterResults(results.concat(this.allResults), target.bookUrl, target.origin);
      this.applyScope();
      this.status = this.results.length > 0 ? `搜索完成，找到 ${this.results.length} 个可切换书源` :
        (this.isScoped() ? '搜索完成，所选分组内未找到' : '搜索完成，未找到可切换书源');
      ChangeSourceResultCache.merge(context, this.cacheKey, results);
      ChangeSourceResultCache.flush(context);
    } catch (e) {
      if (!this.isSessionActive(sessionId)) return;
      console.error('搜索换源失败:', e);
      this.status = '搜索换源失败';
    } finally {
      if (this.activeCoordinator === coordinator) {
        this.activeCoordinator = null;
      }
      if (this.isSessionActive(sessionId)) {
        this.searching = false;
      }
    }
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

  /** 按当前范围从 allResults 筛出显示列表，并记下被藏起来的个数。 */
  applyScope(): void {
    if (!this.isScoped() || this.showHidden) {
      this.results = this.allResults.slice();
      this.hiddenCount = 0;
      return;
    }
    const groups = this.scopeGroups;
    const visible = this.allResults.filter((book: SearchBook): boolean =>
      groups.includes(this.sourceGroupOf.get(book.origin) || ''));
    this.results = visible;
    this.hiddenCount = this.allResults.length - visible.length;
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
    this.persistScope();
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
    const filtered: SearchBook[] = [];
    const seen = new Set<string>();
    // 历史结果可能是旧版本不分类型时存下的，这里同样按原书类型过滤。
    const category = BookTypeSupport.mediaCategoryOf(this.targetBook);
    for (const result of results) {
      if (!result.bookUrl || SearchBookShelfHelper.isNavigationResult(result) ||
        (result.origin === currentOrigin) ||
        BookTypeSupport.mediaCategoryOf(result) !== category) continue;
      const key = `${result.origin || ''}\n${result.bookUrl}`;
      if (seen.has(key)) continue;
      seen.add(key);
      filtered.push(result);
    }
    return filtered;
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
      }
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ top: AppSpacing.MD, bottom: AppSpacing.MD })

      if (this.searching && this.results.length === 0) {
        Column({ space: AppSpacing.MD }) {
          LoadingProgress().width(36).height(36)
          Text('正在搜索可用书源...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .height(260)
        .justifyContent(FlexAlign.Center)
      } else if (this.results.length === 0 && this.isScoped()) {
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
      } else if (this.results.length === 0) {
        Text('暂无可切换书源')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.subTextColor())
          .width('100%')
          .height(260)
          .textAlign(TextAlign.Center)
      } else {
        List({ space: AppSpacing.MD }) {
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
