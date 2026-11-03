import { Book, SearchBook, BookTypeSupport } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { BookSourceSwitchTask } from '../core/book/BookSourceSwitchTask';
import { ChangeSourceResultCache } from '../utils/ChangeSourceResultCache';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

/**
 * 换源面板（书架长按"换源"与书籍详情页"换源"共用）。
 * 优先复用候选历史；首次打开或主动刷新时搜索。加载可取消，事务由独立任务完成。
 * 结果只保留与原书同类型的（小说换小说、漫画换漫画、有声换有声、视频换视频）。
 * 目标书在书库中已存在时提交换源并保留阅读进度与临时书标记；
 * 仅存在于搜索结果（未入库）时只把结果交给宿主页面，不落库。
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
    this.status = '正在读取历史换源结果...';
    this.searching = true;
    this.switching = false;
    const sessionId = ++this.sessionId;
    this.loadHistoryThenSearch(sessionId);
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
      this.results = this.filterResults(cached.results.filter((_item: SearchBook, index: number): boolean => available[index]), book.bookUrl, book.origin);
      if (this.results.length > 0 || cached.searched) {
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
      const results = await coordinator.search(target.name, (progress: SearchProgress) => {
        if (!this.isSessionActive(sessionId)) return;
        const found = progress.finished ? progress.results : (progress.deltaResults || []);
        if (found.length > 0 || progress.finished) ChangeSourceResultCache.merge(context, this.cacheKey, found);
        if (progress.finished) {
          this.results = this.filterResults(progress.results.concat(this.results), target.bookUrl, target.origin);
        } else if (progress.deltaResults && progress.deltaResults.length > 0) {
          this.results = this.filterResults(
            progress.deltaResults.concat(this.results), target.bookUrl, target.origin);
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
        maxCandidatesPerSource: 32
      });
      if (!this.isSessionActive(sessionId)) return;
      this.results = this.filterResults(results.concat(this.results), target.bookUrl, target.origin);
      this.status = this.results.length > 0 ?
        `搜索完成，找到 ${this.results.length} 个可切换书源` : '搜索完成，未找到可切换书源';
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
    ChangeSourceResultCache.merge(context, this.cacheKey, this.results, false);
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
    if (this.activeCoordinator) {
      this.activeCoordinator.cancel();
      this.activeCoordinator = null;
    }
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
          Text('换源')
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(`《${this.targetBook?.name || ''}》`)
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

      Text(this.status || '将使用当前书名进行全词匹配搜索')
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
                  Text(book.originName || book.origin)
                    .fontSize(AppFontSize.BODY_LARGE)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.primaryTextColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
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
