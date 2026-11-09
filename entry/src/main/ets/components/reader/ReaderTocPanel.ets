import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { Book, BookChapter, Bookmark } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { ListDissolve, ListDissolveParticles } from '../../utils/ListDissolve';
import { DeleteParticleBurst, DeleteParticleLayer } from '../common/DeleteParticles';
import { BookCover } from '../book/BookCover';
import { VirtualListScrollbar } from '../../utils/VirtualListScrollbar';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { BookAnnotation, BookAnnotationStyles } from '../../model/reader/BookAnnotation';

const TOC_WINDOW_PAGE_SIZE = 72;
const TOC_SCROLLBAR_DRAG_UPDATE_INTERVAL_MS = 90;
const TOC_SEARCH_INPUT_KEY = 'tocChapterSearchInput';
const TOC_QUICK_JUMP_INPUT_KEY = 'tocQuickJumpChapterInput';

/**
 * 页面操作面板内部状态的入口。书签的长按菜单画在整页上，由页面持有，它通过这里回到面板里执行动作。
 */
export class ReaderTocPanelController {
  showTocTab: () => void = (): void => {
  };
  cancelBookmarkMultiSelect: () => void = (): void => {
  };
  enterBookmarkMultiSelect: (bookmarkId: number) => void = (_bookmarkId: number): void => {
  };
  deleteBookmark: (bookmark: Bookmark) => Promise<void> = (_bookmark: Bookmark): Promise<void> => Promise.resolve();
}

/**
 * 阅读页的目录 / 书签面板（画在阅读页上的浮层，配色用阅读主题，由页面传入；
 * 在页面里的位置和进出场动画由页面加在组件上）。
 *
 * 目录只挂载一个 72 章的窗口，滚动到两端时再续上相邻的一段，长篇目录因此不会一次创建上千个列表项；
 * 右侧的滚动条按全书章节数换算，可以直接拖到任意位置。搜索、倒序、章节序号跳转、
 * 书签多选这些状态都属于面板自己，面板每次打开重新创建，从当前章节开始。
 */
@Component
export struct ReaderTocPanel {
  @Link chapters: BookChapter[];
  @Link bookmarks: Bookmark[];
  /** 目录倒序在阅读页一次会话内保持。 */
  @Link reverseOrder: boolean;
  @Prop currentChapterIndex: number = 0;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#80868B';
  @Prop accentColor: string = '#0A59F7';
  @Prop swipeButtonColor: string = '#0A59F7';
  @Prop panelColor: string = '#F2FFFFFF';
  @Prop solidPanelColor: string = '#FFFFFF';
  @Prop panelBorderColor: string = '#1F000000';
  @Prop panelShadowColor: string = '#33000000';
  @Prop selectedColor: string = '#11007DFF';
  @Prop panelWidth: number = 360;
  @Prop panelHeight: number = 480;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;

  book: Book | null = null;
  controller: ReaderTocPanelController | null = null;
  /** 章节列表不是书里的章节表时关掉（PDF 传的是目录条目，数据库里存的是页），滚动条只按传入的条目算。 */
  @Prop useDatabaseCount: boolean = true;
  /** 目录里显示的章节标题（页面负责清洗标题）。 */
  chapterTitle: (chapterIndex: number) => string = (_chapterIndex: number): string => '';
  onClose: () => void = (): void => {
  };
  onOpenBookDetail: () => void = (): void => {
  };
  onJumpToChapter: (chapterIndex: number) => void = (_chapterIndex: number): void => {
  };
  onJumpToBookmark: (bookmark: Bookmark) => void = (_bookmark: Bookmark): void => {
  };
  /** 重新抓取目录；完成后面板自己恢复定位或重做搜索。 */
  onRefreshToc: () => Promise<void> = (): Promise<void> => Promise.resolve();
  onLoadBookmarks: () => void = (): void => {
  };
  /** 本地 TXT 显示"目录规则"按钮。 */
  showTocRuleButton: boolean = false;
  /** 目录可能切错时的提示，空串不显示。 */
  @Prop tocRuleHint: string = '';
  onOpenTocRules: () => void = (): void => {
  };
  onDismissTocRuleHint: () => void = (): void => {
  };
  onShowBookmarkActions: (bookmark: Bookmark, globalX: number, globalY: number) => void =
    (_bookmark: Bookmark, _globalX: number, _globalY: number): void => {
    };
  /** 本书的划线（阅读页内存里的那份）；每次切到“笔记”页签时重新取。 */
  annotationsProvider: () => BookAnnotation[] = (): BookAnnotation[] => [];
  /** 这条划线在已载入的章节文本里找不到原文时返回 true；章节没载入时不判断。 */
  annotationMissing: (annotation: BookAnnotation) => boolean = (_annotation: BookAnnotation): boolean => false;
  onJumpToAnnotation: (annotation: BookAnnotation) => void = (_annotation: BookAnnotation): void => {
  };
  onDeleteAnnotation: (annotation: BookAnnotation) => Promise<boolean> =
    (_annotation: BookAnnotation): Promise<boolean> => Promise.resolve(false);

  @State private tab: number = 0;
  @State private visibleChapters: BookChapter[] = [];
  @State private windowStart: number = 0;
  @State private quickJumpArmed: boolean = false;
  @State private quickJumpInputVisible: boolean = false;
  @State private quickJumpDraft: string = '';
  @State private searchVisible: boolean = false;
  @State private searchQuery: string = '';
  @State private searchChapterIndexes: number[] = [];
  @State private searchLoading: boolean = false;
  @State private searchResultActive: boolean = false;
  @State private orderRevision: number = 0;
  @State private databaseChapterCount: number = 0;
  @State private listViewportHeight: number = 0;
  @State private firstVisibleGlobalIndex: number = 0;
  @State private visibleItemCount: number = 1;
  @State private scrollbarDragging: boolean = false;
  @State private scrollbarDragOffset: number = 0;
  @State private bookmarkMultiSelectMode: boolean = false;
  @State private selectedBookmarkIds: number[] = [];
  /** 正在消散的书签 id（字符串），见 ListDissolve。 */
  @State private dissolvingBookmarkKeys: string[] = [];
  @State private deleteParticleBursts: DeleteParticleBurst[] = [];
  @State private noteItems: BookAnnotation[] = [];
  @State private dissolvingNoteKeys: string[] = [];
  private noteScroller: ListScroller = new ListScroller();
  private searchRequestSerial: number = 0;
  private scrollbarPointerAnchor: number = 0;
  private scrollbarPendingIndex: number = -1;
  private scrollbarUpdateTimer: number = -1;
  private tocScroller: Scroller = new Scroller();
  private bookmarkScroller: ListScroller = new ListScroller();
  private loadingPreviousPage: boolean = false;
  private loadingNextPage: boolean = false;
  private positioning: boolean = false;
  private positionRequestSerial: number = 0;

  aboutToAppear(): void {
    const controller = this.controller;
    if (controller) {
      controller.showTocTab = (): void => this.selectTocTab();
      controller.cancelBookmarkMultiSelect = (): void => this.cancelBookmarkMultiSelect();
      controller.enterBookmarkMultiSelect = (bookmarkId: number): void => this.enterBookmarkMultiSelect(bookmarkId);
      // 从长按菜单删除时，等菜单收起再开始消散。
      controller.deleteBookmark = (bookmark: Bookmark): Promise<void> =>
        this.deleteBookmark(bookmark, ListDissolve.AFTER_DIALOG_MS);
    }
    this.databaseChapterCount = this.chapters.length;
    this.firstVisibleGlobalIndex = this.currentChapterIndex;
    this.setWindowAround(this.currentChapterIndex, ScrollAlign.CENTER);
    this.scrollToCurrentChapter(false);
    this.onLoadBookmarks();
    if (this.useDatabaseCount) this.loadDatabaseChapterCount();
  }

  aboutToDisappear(): void {
    this.searchRequestSerial++;
    this.positionRequestSerial++;
    if (this.scrollbarUpdateTimer >= 0) {
      clearTimeout(this.scrollbarUpdateTimer);
      this.scrollbarUpdateTimer = -1;
    }
    const controller = this.controller;
    if (controller) {
      controller.showTocTab = (): void => {
      };
      controller.cancelBookmarkMultiSelect = (): void => {
      };
      controller.enterBookmarkMultiSelect = (_bookmarkId: number): void => {
      };
      controller.deleteBookmark = (_bookmark: Bookmark): Promise<void> => Promise.resolve();
    }
  }

  // ---------------------------------------------------------------- 目录窗口

  private isSearchActive(): boolean {
    return this.searchVisible && this.searchResultActive;
  }

  private globalIndex(localIndex: number): number {
    if (this.isSearchActive()) {
      return this.searchChapterIndexes[localIndex] ?? 0;
    }
    const displayIndex = this.windowStart + localIndex;
    return this.reverseOrder ? this.chapters.length - 1 - displayIndex : displayIndex;
  }

  private chapterAtDisplayIndex(displayIndex: number): BookChapter {
    const canonicalIndex = this.reverseOrder ? this.chapters.length - 1 - displayIndex : displayIndex;
    return this.chapters[canonicalIndex];
  }

  private setWindowAround(index: number, align: ScrollAlign): number {
    this.loadingPreviousPage = false;
    this.loadingNextPage = false;
    if (this.chapters.length === 0) {
      this.windowStart = 0;
      this.visibleChapters = [];
      return 0;
    }
    const canonicalTarget = Math.max(0, Math.min(index, this.chapters.length - 1));
    const target = this.reverseOrder ? this.chapters.length - 1 - canonicalTarget : canonicalTarget;
    let start = target - Math.floor(TOC_WINDOW_PAGE_SIZE / 2);
    if (align === ScrollAlign.START) {
      start = target;
    } else if (align === ScrollAlign.END) {
      start = target - TOC_WINDOW_PAGE_SIZE + 1;
    }
    start = Math.max(0, Math.min(start, Math.max(0, this.chapters.length - TOC_WINDOW_PAGE_SIZE)));
    const end = Math.min(this.chapters.length, start + TOC_WINDOW_PAGE_SIZE);
    const visibleChapters: BookChapter[] = [];
    for (let displayIndex = start; displayIndex < end; displayIndex++) {
      visibleChapters.push(this.chapterAtDisplayIndex(displayIndex));
    }
    this.windowStart = start;
    this.visibleChapters = visibleChapters;
    return target - start;
  }

  private loadNextPage(): void {
    if (this.isSearchActive() || this.positioning || this.loadingNextPage) return;
    const loadedEnd = this.windowStart + this.visibleChapters.length;
    if (loadedEnd >= this.chapters.length) return;
    this.loadingNextPage = true;
    const nextEnd = Math.min(this.chapters.length, loadedEnd + TOC_WINDOW_PAGE_SIZE);
    const nextChapters: BookChapter[] = [];
    for (let displayIndex = loadedEnd; displayIndex < nextEnd; displayIndex++) {
      nextChapters.push(this.chapterAtDisplayIndex(displayIndex));
    }
    this.visibleChapters = this.visibleChapters.concat(nextChapters);
    setTimeout(() => {
      this.loadingNextPage = false;
    }, 0);
  }

  private loadPreviousPage(): void {
    if (this.isSearchActive() || this.positioning || this.loadingPreviousPage || this.windowStart <= 0) return;
    this.loadingPreviousPage = true;
    const oldStart = this.windowStart;
    const nextStart = Math.max(0, oldStart - TOC_WINDOW_PAGE_SIZE);
    const added = oldStart - nextStart;
    const previousChapters: BookChapter[] = [];
    for (let displayIndex = nextStart; displayIndex < oldStart; displayIndex++) {
      previousChapters.push(this.chapterAtDisplayIndex(displayIndex));
    }
    this.windowStart = nextStart;
    this.visibleChapters = previousChapters.concat(this.visibleChapters);
    setTimeout(() => {
      try {
        this.tocScroller.scrollToIndex(added, false, ScrollAlign.START);
      } catch (e) {
        console.warn('向前加载目录失败:', e);
      } finally {
        this.loadingPreviousPage = false;
      }
    }, 0);
  }

  private scrollToCurrentChapter(smooth: boolean = true): void {
    if (this.chapters.length === 0) return;
    const index = Math.max(0, Math.min(this.currentChapterIndex, this.chapters.length - 1));
    this.scrollToChapter(index, ScrollAlign.CENTER, smooth);
  }

  private scrollToChapter(index: number, align: ScrollAlign, smooth: boolean = true): void {
    if (this.chapters.length === 0) return;
    const targetIndex = Math.max(0, Math.min(index, this.chapters.length - 1));
    const requestSerial = ++this.positionRequestSerial;
    this.positioning = true;
    const localIndex = this.setWindowAround(targetIndex, align);
    setTimeout(() => {
      if (requestSerial !== this.positionRequestSerial) return;
      try {
        this.tocScroller.scrollToIndex(localIndex, smooth, align);
      } catch (e) {
        console.warn('定位目录章节失败:', e);
      } finally {
        setTimeout(() => {
          if (requestSerial === this.positionRequestSerial) this.positioning = false;
        }, 0);
      }
    }, 50);
  }

  private toggleOrder(): void {
    this.reverseOrder = !this.reverseOrder;
    this.orderRevision++;
    this.searchRequestSerial++;
    this.searchQuery = '';
    this.searchChapterIndexes = [];
    this.searchLoading = false;
    this.searchResultActive = false;
    this.scrollToCurrentChapter(false);
  }

  private async loadDatabaseChapterCount(): Promise<void> {
    const bookUrl = this.book?.bookUrl || '';
    if (!bookUrl) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.databaseChapterCount = Math.max(await db.getBookChapterCount(bookUrl), this.chapters.length);
    } catch (e) {
      console.warn('读取数据库章节总数失败:', e);
    }
  }

  private async refreshToc(): Promise<void> {
    const searchQuery = this.searchQuery;
    await this.onRefreshToc();
    this.databaseChapterCount = this.chapters.length;
    if (this.searchVisible && this.searchResultActive && searchQuery.trim()) {
      await this.submitSearch();
    } else {
      this.setWindowAround(this.currentChapterIndex, ScrollAlign.CENTER);
      this.scrollToCurrentChapter(false);
    }
    HdsFeedback.showToast('目录已刷新');
  }

  private titleColor(chapter: BookChapter, index: number): string {
    // 主题强调色可能是浅金色；选中行靠底色、字重和标记识别，标题仍保持可读。
    if (index === this.currentChapterIndex) return this.textColor;
    if (chapter.cacheDate > 0) return this.dark ? '#DDEFE5' : '#244B35';
    return this.dark ? '#B8BDC7' : '#333333';
  }

  // ---------------------------------------------------------------- 搜索与序号跳转

  private toggleSearch(): void {
    if (this.searchVisible) {
      this.searchVisible = false;
      this.searchQuery = '';
      this.searchChapterIndexes = [];
      this.searchLoading = false;
      this.searchResultActive = false;
      this.searchRequestSerial++;
      this.setWindowAround(this.currentChapterIndex, ScrollAlign.CENTER);
      this.scrollToCurrentChapter(false);
      return;
    }
    this.searchVisible = true;
    this.quickJumpArmed = false;
    this.quickJumpInputVisible = false;
    this.quickJumpDraft = '';
    setTimeout(() => {
      focusControl.requestFocus(TOC_SEARCH_INPUT_KEY);
    }, 50);
  }

  private async submitSearch(): Promise<void> {
    const keyword = this.searchQuery.trim();
    if (!keyword) {
      this.clearSearchResult();
      return;
    }
    const requestSerial = ++this.searchRequestSerial;
    const bookUrl = this.book?.bookUrl || '';
    this.searchLoading = true;
    try {
      let matches: BookChapter[] = [];
      let totalCount = this.chapters.length;
      let searchSource = '内存';
      if (this.chapters.length > 0) {
        const normalizedKeyword = keyword.toLowerCase();
        matches = this.chapters.filter((chapter: BookChapter) =>
          (chapter.title || '').toLowerCase().includes(normalizedKeyword));
      } else {
        searchSource = '数据库';
        const db = AppDatabase.getInstance();
        await db.initWithContext(getContext(this));
        matches = await db.searchBookChapters(bookUrl, keyword);
        totalCount = await db.getBookChapterCount(bookUrl);
      }
      if (requestSerial !== this.searchRequestSerial || !this.searchVisible) return;
      if (this.reverseOrder) {
        matches = matches.slice().reverse();
      }
      const indexes: number[] = [];
      for (const chapter of matches) {
        indexes.push(chapter.index);
      }
      this.databaseChapterCount = totalCount;
      this.searchChapterIndexes = indexes;
      this.visibleChapters = matches;
      this.windowStart = 0;
      this.searchResultActive = true;
      this.firstVisibleGlobalIndex = indexes.length > 0 ? indexes[0] : 0;
      this.visibleItemCount = 1;
      console.info(`[TOC] ${searchSource}目录搜索: keyword=${keyword}, total=${totalCount}, matches=${matches.length}`);
      setTimeout(() => {
        if (matches.length > 0) {
          this.tocScroller.scrollToIndex(0, false, ScrollAlign.START);
        }
      }, 0);
    } catch (e) {
      console.warn('目录搜索失败:', e);
      if (requestSerial === this.searchRequestSerial) {
        HdsFeedback.showToast('目录搜索失败');
      }
    } finally {
      if (requestSerial === this.searchRequestSerial) {
        this.searchLoading = false;
      }
    }
  }

  private clearSearchResult(): void {
    this.searchRequestSerial++;
    this.searchQuery = '';
    this.searchLoading = false;
    this.searchResultActive = false;
    this.searchChapterIndexes = [];
    const localIndex = this.setWindowAround(this.currentChapterIndex, ScrollAlign.CENTER);
    setTimeout(() => {
      try {
        this.tocScroller.scrollToIndex(localIndex, false, ScrollAlign.CENTER);
      } catch (e) {
        console.warn('清空目录搜索后恢复定位失败:', e);
      }
    }, 0);
  }

  // 第一次点"共 N 章"回到当前章节，紧接着再点一次才出现序号输入框。
  private handleCurrentPositionClick(): void {
    if (this.quickJumpArmed) {
      this.quickJumpDraft = '';
      this.quickJumpInputVisible = true;
      this.quickJumpArmed = false;
      setTimeout(() => {
        focusControl.requestFocus(TOC_QUICK_JUMP_INPUT_KEY);
      }, 50);
      return;
    }
    this.scrollToCurrentChapter();
    this.quickJumpArmed = true;
  }

  private submitQuickJump(): void {
    if (this.chapters.length === 0) {
      HdsFeedback.showToast('暂无可定位的章节');
      return;
    }
    const chapterNumber = Number.parseInt(this.quickJumpDraft, 10);
    if (!Number.isFinite(chapterNumber) || chapterNumber < 1 || chapterNumber > this.chapters.length) {
      HdsFeedback.showToast(`章节序号范围为 1～${this.chapters.length}，请重新输入`);
      setTimeout(() => {
        focusControl.requestFocus(TOC_QUICK_JUMP_INPUT_KEY);
      }, 50);
      return;
    }
    this.quickJumpInputVisible = false;
    this.quickJumpDraft = '';
    this.quickJumpArmed = false;
    this.scrollToChapter(chapterNumber - 1, ScrollAlign.CENTER);
  }

  // ---------------------------------------------------------------- 滚动条

  private updateScrollbarPosition(start: number, end: number): void {
    const localStart = Math.max(0, start);
    this.firstVisibleGlobalIndex = this.globalIndex(localStart);
    this.visibleItemCount = Math.max(1, end - start + 1);
  }

  private shouldShowScrollbar(): boolean {
    return this.listViewportHeight > 0 && this.databaseChapterCount > this.visibleItemCount;
  }

  private scrollbarThumbLength(): number {
    return VirtualListScrollbar.thumbLength(this.listViewportHeight, this.databaseChapterCount,
      this.visibleItemCount);
  }

  private scrollbarThumbOffset(): number {
    const thumbLength = this.scrollbarThumbLength();
    const firstVisibleIndex = this.reverseOrder ?
      this.databaseChapterCount - 1 - this.firstVisibleGlobalIndex : this.firstVisibleGlobalIndex;
    return VirtualListScrollbar.thumbOffset(this.listViewportHeight, thumbLength,
      this.databaseChapterCount, firstVisibleIndex, this.visibleItemCount);
  }

  private displayedScrollbarThumbOffset(): number {
    return this.scrollbarDragging ? this.scrollbarDragOffset : this.scrollbarThumbOffset();
  }

  private scrollbarPointerY(event: GestureEvent): number {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    return finger ? finger.localY : 0;
  }

  private beginScrollbarDrag(event: GestureEvent): void {
    const thumbLength = this.scrollbarThumbLength();
    const currentOffset = this.scrollbarThumbOffset();
    const pointerY = this.scrollbarPointerY(event);
    this.scrollbarDragging = true;
    this.scrollbarDragOffset = currentOffset;
    if (pointerY >= currentOffset && pointerY <= currentOffset + thumbLength) {
      this.scrollbarPointerAnchor = pointerY - currentOffset;
    } else {
      this.scrollbarPointerAnchor = thumbLength / 2;
      this.updateScrollbarFromPointer(pointerY);
    }
  }

  private updateScrollbarDrag(event: GestureEvent): void {
    if (!this.scrollbarDragging) return;
    this.updateScrollbarFromPointer(this.scrollbarPointerY(event));
  }

  private endScrollbarDrag(event: GestureEvent): void {
    if (!this.scrollbarDragging) return;
    this.updateScrollbarFromPointer(this.scrollbarPointerY(event));
    this.scrollbarDragging = false;
    this.flushScrollbarTarget();
  }

  private cancelScrollbarDrag(): void {
    this.scrollbarDragging = false;
    this.scrollbarPendingIndex = -1;
    if (this.scrollbarUpdateTimer >= 0) {
      clearTimeout(this.scrollbarUpdateTimer);
      this.scrollbarUpdateTimer = -1;
    }
  }

  private jumpScrollbarToPointer(event: GestureEvent): void {
    this.scrollbarPointerAnchor = this.scrollbarThumbLength() / 2;
    this.updateScrollbarFromPointer(this.scrollbarPointerY(event));
  }

  private updateScrollbarFromPointer(pointerY: number): void {
    const thumbLength = this.scrollbarThumbLength();
    const offset = VirtualListScrollbar.clampThumbOffset(this.listViewportHeight, thumbLength,
      pointerY - this.scrollbarPointerAnchor);
    this.scrollbarDragOffset = offset;
    const targetIndex = VirtualListScrollbar.firstVisibleIndex(this.listViewportHeight, thumbLength,
      this.databaseChapterCount, this.visibleItemCount, offset);
    const targetChapterIndex = this.reverseOrder ? this.databaseChapterCount - 1 - targetIndex : targetIndex;
    this.firstVisibleGlobalIndex = targetChapterIndex;
    if (this.scrollbarDragging) {
      this.queueScrollbarTarget(targetChapterIndex, TOC_SCROLLBAR_DRAG_UPDATE_INTERVAL_MS);
      return;
    }
    this.queueScrollbarTarget(targetChapterIndex);
  }

  private flushScrollbarTarget(): void {
    if (this.scrollbarUpdateTimer >= 0) {
      clearTimeout(this.scrollbarUpdateTimer);
      this.scrollbarUpdateTimer = -1;
    }
    const pending = this.scrollbarPendingIndex;
    this.scrollbarPendingIndex = -1;
    this.applyScrollbarTarget(pending);
  }

  private queueScrollbarTarget(targetIndex: number, delayMs: number = 16): void {
    this.scrollbarPendingIndex = targetIndex;
    if (this.scrollbarUpdateTimer >= 0) return;
    this.scrollbarUpdateTimer = setTimeout(() => {
      this.scrollbarUpdateTimer = -1;
      const pending = this.scrollbarPendingIndex;
      this.scrollbarPendingIndex = -1;
      this.applyScrollbarTarget(pending);
    }, delayMs);
  }

  private applyScrollbarTarget(targetIndex: number): void {
    if (targetIndex < 0) return;
    if (this.isSearchActive()) {
      const localIndex = this.nearestSearchResultIndex(targetIndex);
      if (localIndex < 0) return;
      this.firstVisibleGlobalIndex = this.searchChapterIndexes[localIndex] ?? targetIndex;
      try {
        this.tocScroller.scrollToIndex(localIndex, false, ScrollAlign.START);
      } catch (e) {
        console.warn('拖动目录滚动条定位搜索结果失败:', e);
      }
      return;
    }
    if (this.chapters.length === 0) return;
    const target = Math.max(0, Math.min(targetIndex, this.chapters.length - 1));
    const requestSerial = ++this.positionRequestSerial;
    this.positioning = true;
    const localIndex = this.setWindowAround(target, ScrollAlign.START);
    setTimeout(() => {
      if (requestSerial !== this.positionRequestSerial) return;
      try {
        this.tocScroller.scrollToIndex(localIndex, false, ScrollAlign.START);
      } catch (e) {
        console.warn('拖动目录滚动条定位章节失败:', e);
      } finally {
        if (requestSerial === this.positionRequestSerial) this.positioning = false;
      }
    }, 0);
  }

  private nearestSearchResultIndex(targetIndex: number): number {
    const indexes = this.searchChapterIndexes;
    if (indexes.length === 0) return -1;
    let low = 0;
    let high = indexes.length - 1;
    while (low < high) {
      const mid = Math.floor((low + high) / 2);
      if (this.reverseOrder ? indexes[mid] > targetIndex : indexes[mid] < targetIndex) low = mid + 1;
      else high = mid;
    }
    if (low > 0 && Math.abs(indexes[low - 1] - targetIndex) <= Math.abs(indexes[low] - targetIndex)) {
      return low - 1;
    }
    return low;
  }

  // ---------------------------------------------------------------- 书签

  private selectTocTab(): void {
    this.tab = 0;
    this.cancelBookmarkMultiSelect();
    this.scrollToCurrentChapter(false);
  }

  private async deleteBookmark(bookmark: Bookmark, delayMs: number = 0): Promise<void> {
    const keys = [`${bookmark.id}`];
    const fade = ListDissolve.fadeOut(this.getUIContext(), keys, (key: string) => {
      this.dissolvingBookmarkKeys = [...this.dissolvingBookmarkKeys, key];
    }, this.bookmarkDeleteParticles(), delayMs);
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBookmark(bookmark.id);
      await fade;
      ListDissolve.commit(this.getUIContext(), () => {
        this.bookmarks = this.bookmarks.filter((item: Bookmark) => item.id !== bookmark.id);
        this.selectedBookmarkIds = this.selectedBookmarkIds.filter((id: number) => id !== bookmark.id);
      }, () => {
        this.dissolvingBookmarkKeys = ListDissolve.without(this.dissolvingBookmarkKeys, keys);
      });
      if (this.bookmarkMultiSelectMode && this.bookmarks.length === 0) {
        this.cancelBookmarkMultiSelect();
      }
      HdsFeedback.showToast('书签已删除');
    } catch (e) {
      console.error('删除书签失败:', e);
      this.dissolvingBookmarkKeys = ListDissolve.without(this.dissolvingBookmarkKeys, keys);
      HdsFeedback.showToast('删除书签失败');
    }
  }

  private async deleteSelectedBookmarks(): Promise<void> {
    const ids = [...this.selectedBookmarkIds];
    if (ids.length === 0) return;
    const keys = ids.map((id: number) => `${id}`);
    const fade = ListDissolve.fadeOut(this.getUIContext(), keys, (key: string) => {
      this.dissolvingBookmarkKeys = [...this.dissolvingBookmarkKeys, key];
    }, this.bookmarkDeleteParticles());
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBookmarks(ids);
      await fade;
      ListDissolve.commit(this.getUIContext(), () => {
        this.bookmarks = this.bookmarks.filter((bookmark: Bookmark) => !ids.includes(bookmark.id));
      }, () => {
        this.dissolvingBookmarkKeys = ListDissolve.without(this.dissolvingBookmarkKeys, keys);
      });
      this.cancelBookmarkMultiSelect();
      HdsFeedback.showToast(`已删除 ${ids.length} 条书签`);
    } catch (e) {
      console.error('批量删除书签失败:', e);
      this.dissolvingBookmarkKeys = ListDissolve.without(this.dissolvingBookmarkKeys, keys);
      HdsFeedback.showToast('批量删除书签失败');
    }
  }

  private bookmarkCardElementId(key: string): string {
    return `reader_bookmark_card_${key}`;
  }

  private bookmarkDeleteParticles(): ListDissolveParticles {
    const particles = new ListDissolveParticles();
    particles.rootId = 'reader_bookmark_list_root';
    particles.colors = [this.accentColor, this.textColor, this.subTextColor];
    particles.elementIdOf = (key: string): string => this.bookmarkCardElementId(key);
    particles.show = (bursts: DeleteParticleBurst[]): void => {
      this.deleteParticleBursts = [...this.deleteParticleBursts, ...bursts];
    };
    particles.hide = (ids: number[]): void => {
      this.deleteParticleBursts = this.deleteParticleBursts.filter((burst: DeleteParticleBurst) => ids.indexOf(burst.id) < 0);
    };
    return particles;
  }

  private isBookmarkDissolving(bookmark: Bookmark): boolean {
    return this.dissolvingBookmarkKeys.length > 0 && this.dissolvingBookmarkKeys.indexOf(`${bookmark.id}`) >= 0;
  }

  private enterBookmarkMultiSelect(bookmarkId: number): void {
    this.bookmarkMultiSelectMode = true;
    if (!this.selectedBookmarkIds.includes(bookmarkId)) {
      this.selectedBookmarkIds = [...this.selectedBookmarkIds, bookmarkId];
    }
    setTimeout(() => {
      try {
        this.bookmarkScroller.closeAllSwipeActions();
      } catch (error) {
        console.warn('关闭书签滑动操作失败:', error);
      }
    }, 0);
  }

  private toggleBookmarkSelection(bookmarkId: number): void {
    if (this.selectedBookmarkIds.includes(bookmarkId)) {
      this.selectedBookmarkIds = this.selectedBookmarkIds.filter((id: number) => id !== bookmarkId);
    } else {
      this.selectedBookmarkIds = [...this.selectedBookmarkIds, bookmarkId];
    }
  }

  private toggleSelectAllBookmarks(): void {
    if (this.selectedBookmarkIds.length === this.bookmarks.length) {
      this.selectedBookmarkIds = [];
    } else {
      this.selectedBookmarkIds = this.bookmarks.map((bookmark: Bookmark) => bookmark.id);
    }
  }

  private cancelBookmarkMultiSelect(): void {
    this.bookmarkMultiSelectMode = false;
    this.selectedBookmarkIds = [];
  }

  private formatBookmarkTime(timestamp: number): string {
    if (timestamp <= 0) return '';
    const date = new Date(timestamp);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${month}-${day} ${hour}:${minute}`;
  }

  private bookmarkSwipeActions(bookmark: Bookmark): HdsSwipeActionOptions {
    return {
      icons: [
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
          backgroundColor: this.swipeButtonColor,
          iconOptions: { accessibilityText: '多选' },
          onAction: () => this.enterBookmarkMultiSelect(bookmark.id)
        },
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
          backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode),
          iconOptions: { accessibilityText: '删除书签' },
          onAction: () => this.deleteBookmark(bookmark)
        }
      ]
    };
  }

  // ---------------------------------------------------------------- 笔记（划线）

  private selectNoteTab(): void {
    this.cancelBookmarkMultiSelect();
    this.tab = 2;
    this.reloadNoteItems();
  }

  private reloadNoteItems(): void {
    this.noteItems = this.annotationsProvider().slice().sort((left: BookAnnotation, right: BookAnnotation): number =>
      left.chapterIndex - right.chapterIndex || left.start - right.start || left.createTime - right.createTime);
  }

  private noteKey(annotation: BookAnnotation): string {
    return `n${annotation.id}`;
  }

  private isNoteDissolving(annotation: BookAnnotation): boolean {
    return this.dissolvingNoteKeys.length > 0 && this.dissolvingNoteKeys.indexOf(this.noteKey(annotation)) >= 0;
  }

  private noteDeleteParticles(): ListDissolveParticles {
    const particles = new ListDissolveParticles();
    particles.rootId = 'reader_note_list_root';
    particles.colors = [this.accentColor, this.textColor, this.subTextColor];
    particles.elementIdOf = (key: string): string => `reader_note_card_${key}`;
    particles.show = (bursts: DeleteParticleBurst[]): void => {
      this.deleteParticleBursts = [...this.deleteParticleBursts, ...bursts];
    };
    particles.hide = (ids: number[]): void => {
      this.deleteParticleBursts = this.deleteParticleBursts.filter((burst: DeleteParticleBurst) => ids.indexOf(burst.id) < 0);
    };
    return particles;
  }

  private async deleteNote(annotation: BookAnnotation): Promise<void> {
    const keys = [this.noteKey(annotation)];
    const fade = ListDissolve.fadeOut(this.getUIContext(), keys, (key: string) => {
      this.dissolvingNoteKeys = [...this.dissolvingNoteKeys, key];
    }, this.noteDeleteParticles());
    const deleted = await this.onDeleteAnnotation(annotation);
    if (!deleted) {
      this.dissolvingNoteKeys = ListDissolve.without(this.dissolvingNoteKeys, keys);
      HdsFeedback.showToast('删除划线失败');
      return;
    }
    await fade;
    ListDissolve.commit(this.getUIContext(), () => {
      this.noteItems = this.noteItems.filter((item: BookAnnotation) => item.id !== annotation.id);
    }, () => {
      this.dissolvingNoteKeys = ListDissolve.without(this.dissolvingNoteKeys, keys);
    });
    HdsFeedback.showToast('划线已删除');
  }

  private noteSwipeActions(annotation: BookAnnotation): HdsSwipeActionOptions {
    return {
      icons: [
        {
          icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
          backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode),
          iconOptions: { accessibilityText: '删除划线' },
          onAction: () => {
            this.deleteNote(annotation);
          }
        }
      ]
    };
  }

  private withAlpha(color: string, alphaHex: string): string {
    return `#${alphaHex}${BookAnnotationStyles.normalizeColor(color).substring(1)}`;
  }

  // ---------------------------------------------------------------- 界面

  build() {
    ReaderMaterialPanel({
      panelWidth: this.panelWidth,
      panelHeight: this.panelHeight,
      cornerRadius: 28,
      darkMode: this.dark,
      fallbackColor: this.panelColor
    }) {
      this.panelBody()
    }
  }

  @Builder
  panelBody() {
    Column() {
      Row({ space: AppSpacing.LG }) {
        BookCover({
          bookUrl: this.book?.bookUrl || '', origin: this.book?.origin || '',
          name: this.book?.name || '', author: this.book?.author || '',
          coverUrl: this.book?.coverUrl || '', customCoverUrl: this.book?.customCoverUrl || '',
          placeholderColor: this.accentColor, cornerRadius: 8
        })
          .width(52)
          .height(68)
          .accessibilityText('查看书籍详情')
          .onClick(() => this.onOpenBookDetail())

        Column({ space: AppSpacing.XS }) {
          Text(this.book?.name || '目录')
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .accessibilityText(`${this.book?.name || '书籍'}，查看详情`)
            .onClick(() => this.onOpenBookDetail())
          Text(this.book?.author || '未知作者')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
          darkMode: this.dark,
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          materialScale: 0.83,
          compactLayout: true,
          accessibilityLabel: '关闭目录',
          onBack: () => this.onClose()
        })
          .alignSelf(ItemAlign.Start)
          .margin({ top: AppSpacing.XS })
      }
      .width('100%')
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.MD })
      .alignItems(VerticalAlign.Center)

      Row() {
        this.tabButton('目录', 0, () => this.selectTocTab())
        this.tabButton('书签', 1, () => {
          this.tab = 1;
          this.onLoadBookmarks();
        })
        this.tabButton('笔记', 2, () => this.selectNoteTab())
      }
      .width('calc(100% - 40vp)')
      .height(44)
      .padding(AppSpacing.XXS)
      .borderRadius(22)
      .backgroundColor(ThemeRuntime.softFillColor(this.dark))
      .margin({ left: AppSpacing.XXL, right: AppSpacing.XXL })

      if (this.tab === 0) {
        this.tocSummary()
        this.chapterList()
      } else if (this.tab === 1) {
        this.bookmarkSummary()
        this.bookmarkList()
      } else {
        this.noteSummary()
        this.noteList()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  tabButton(label: string, index: number, action: () => void) {
    Text(label)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.tab === index ? this.textColor : this.subTextColor)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.tab === index ? this.solidPanelColor : Color.Transparent)
      .shadow({
        radius: this.tab === index ? 6 : 0,
        color: this.tab === index ? this.panelShadowColor : Color.Transparent,
        offsetX: 0,
        offsetY: 2
      })
      .onClick(action)
  }

  @Builder
  tocSummary() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        if (this.quickJumpInputVisible && !this.isSearchActive()) {
          TextInput({ text: this.quickJumpDraft, placeholder: `1-${this.chapters.length}` })
            .type(InputType.Normal)
            .enterKeyType(EnterKeyType.Go)
            .key(TOC_QUICK_JUMP_INPUT_KEY)
            .defaultFocus(true)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.textColor)
            .textAlign(TextAlign.Center)
            .width(92)
            .height(34)
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
            .borderRadius(17)
            .backgroundColor(ThemeRuntime.hairlineColor(this.dark))
            .accessibilityText('输入目标章节序号，按回车定位')
            .onChange((value: string) => {
              this.quickJumpDraft = value.replace(/[^0-9]/g, '').substring(0, 6);
            })
            .onSubmit(() => this.submitQuickJump())
        } else if (this.isSearchActive()) {
          Text(`找到 ${this.searchChapterIndexes.length} 章`)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor)
            .margin({ left: AppSpacing.SM })
        } else {
          Text(`共 ${this.chapters.length} 章`)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor)
            .margin({ left: AppSpacing.SM })
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
            .height(34)
            .textAlign(TextAlign.Center)
            .accessibilityText(this.quickJumpArmed ? '再次点击输入目标章节' : '点击回到当前章节')
            .onClick(() => this.handleCurrentPositionClick())
        }
        ImmersiveBackButton({
          icon: $r('sys.symbol.text_arrow_up_and_down'),
          iconOffsetX: 0,
          iconColor: this.reverseOrder ? this.accentColor : this.textColor,
          darkMode: this.dark,
          buttonSize: 34,
          containerWidth: 34,
          containerHeight: 34,
          startInset: 0,
          materialScale: 0.7,
          compactLayout: true,
          accessibilityLabel: this.reverseOrder ? '切换为正序目录' : '切换为倒序目录',
          onBack: () => this.toggleOrder()
        })
          .margin({ left: AppSpacing.XS })
        Blank()
          .layoutWeight(1)
        if (this.isSearchActive()) {
          Text(`匹配 ${this.searchChapterIndexes.length}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.textColor)
            .height(34)
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
            .textAlign(TextAlign.Center)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(ThemeRuntime.softFillColor(this.dark))
        }
        if (this.showTocRuleButton) {
          ImmersiveBackButton({
            icon: $r('sys.symbol.ruler'),
            iconOffsetX: 0,
            iconColor: this.tocRuleHint ? this.accentColor : this.textColor,
            darkMode: this.dark,
            buttonSize: 34,
            containerWidth: 34,
            containerHeight: 34,
            startInset: 0,
            materialScale: 0.7,
            compactLayout: true,
            accessibilityLabel: '目录规则',
            onBack: () => this.onOpenTocRules()
          })
            .margin({ left: AppSpacing.MD })
        }
        ImmersiveBackButton({
          icon: $r('sys.symbol.arrow_clockwise'),
          iconOffsetX: 0,
          iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
          darkMode: this.dark,
          buttonSize: 34,
          containerWidth: 34,
          containerHeight: 34,
          startInset: 0,
          materialScale: 0.7,
          compactLayout: true,
          accessibilityLabel: '刷新目录',
          onBack: () => {
            this.refreshToc();
          }
        })
          .margin({ left: AppSpacing.MD })
        ImmersiveBackButton({
          icon: $r('sys.symbol.magnifyingglass'),
          iconOffsetX: 0,
          iconColor: this.searchVisible ? this.accentColor : this.textColor,
          darkMode: this.dark,
          buttonSize: 34,
          containerWidth: 34,
          containerHeight: 34,
          startInset: 0,
          materialScale: 0.7,
          compactLayout: true,
          accessibilityLabel: '搜索目录',
          onBack: () => this.toggleSearch()
        })
          .margin({ left: AppSpacing.MD })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.tocRuleHint && !this.isSearchActive()) {
        Row({ space: AppSpacing.SM }) {
          Text(this.tocRuleHint)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.dark ? '#F2B766' : '#8A4500')
            .layoutWeight(1)
          Text('换个规则')
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor)
            .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
            .onClick(() => this.onOpenTocRules())
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([this.dark ? '#F2B766' : '#8A4500'])
            .padding(AppSpacing.XS)
            .accessibilityText('不再提示')
            .onClick(() => this.onDismissTocRuleHint())
        }
        .width('100%')
        .padding({ left: AppSpacing.MD, right: AppSpacing.SM, top: AppSpacing.SM, bottom: AppSpacing.SM })
        .borderRadius(12)
        .backgroundColor(this.dark ? '#3A2C1A' : '#FFF3E6')
      }

      if (this.searchVisible) {
        Row({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([this.subTextColor])
          TextInput({
            text: this.searchQuery,
            placeholder: this.searchLoading ? '正在载入完整目录…' : '搜索章节名称'
          })
            .key(TOC_SEARCH_INPUT_KEY)
            .defaultFocus(true)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.textColor)
            .layoutWeight(1)
            .height(38)
            .padding({ left: 0, right: 0 })
            .backgroundColor(Color.Transparent)
            .enterKeyType(EnterKeyType.Search)
            .onChange((value: string) => {
              this.searchQuery = value;
            })
            .onSubmit(() => {
              this.submitSearch();
            })
          if (this.searchQuery) {
            Text('×')
              .fontSize(AppFontSize.TITLE)
              .fontColor(this.subTextColor)
              .width(32)
              .height(38)
              .textAlign(TextAlign.Center)
              .accessibilityText('清空目录搜索')
              .onClick(() => {
                this.clearSearchResult();
                setTimeout(() => focusControl.requestFocus(TOC_SEARCH_INPUT_KEY), 30);
              })
          }
        }
        .width('100%')
        .height(40)
        .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
        .borderRadius(20)
        .backgroundColor(ThemeRuntime.hairlineColor(this.dark))
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.MD })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  chapterList() {
    Stack({ alignContent: Alignment.TopEnd }) {
      List({ space: 0, scroller: this.tocScroller }) {
        if (this.isSearchActive() && this.visibleChapters.length === 0) {
          ListItem() {
            Column({ space: AppSpacing.MD }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(28)
                .fontColor([this.subTextColor])
              Text('未找到匹配章节')
                .fontSize(AppFontSize.BODY)
                .fontColor(this.subTextColor)
            }
            .width('100%')
            .padding({ top: 44, bottom: 44 })
          }
        }
        // ForEach 会复用同一章节的节点；筛选后旧回调里的 localIndex 不再对应新列表。
        // 行内容、选中态和跳转始终使用章节自身的索引。
        ForEach(this.visibleChapters, (chapter: BookChapter) => {
          ListItem() {
            Column() {
            if (BookChapter.volumeTitleOf(chapter)) {
              Text(BookChapter.volumeTitleOf(chapter))
                .fontSize(AppFontSize.BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.subTextColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.SM })
            }
            Row({ space: AppSpacing.MD }) {
              Text(chapter.index === this.currentChapterIndex ? '•' : '·')
                .fontSize(chapter.index === this.currentChapterIndex ? 22 : 18)
                .fontColor(chapter.index === this.currentChapterIndex ?
                  this.accentColor : this.subTextColor)
                .width(18)
                .textAlign(TextAlign.Center)

              Text(this.chapterTitle(chapter.index))
                .fontSize(AppFontSize.BODY_LARGE)
                .fontWeight(chapter.index === this.currentChapterIndex ?
                  FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.titleColor(chapter, chapter.index))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (this.book?.origin !== 'local' && chapter.cacheDate > 0) {
                Text('已缓存')
                  .fontSize(AppFontSize.MICRO)
                  .fontColor(ThemeRuntime.successColor(this.dark))
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
                  .backgroundColor(ThemeRuntime.successSurfaceColor(this.dark))
                  .borderRadius(ThemeRuntime.mediumRadius())
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.LG, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
            .backgroundColor(chapter.index === this.currentChapterIndex ?
              this.selectedColor : Color.Transparent)
            .border({ width: { bottom: 0.5 }, color: ThemeRuntime.softFillColor(this.dark) })
            .onClick(() => this.onJumpToChapter(chapter.index))
            }
          }
        }, (chapter: BookChapter) =>
          `${this.orderRevision}_${chapter.index}_${chapter.url || chapter.title}`)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .onScrollIndex((start: number, end: number) => this.updateScrollbarPosition(start, end))
      .onReachStart(() => this.loadPreviousPage())
      .onReachEnd(() => this.loadNextPage())

      this.virtualScrollbar()
    }
    .layoutWeight(1)
    .width('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.listViewportHeight = Number(newValue.height);
    })
  }

  @Builder
  virtualScrollbar() {
    if (this.shouldShowScrollbar()) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column()
          .width(3)
          .height(this.listViewportHeight)
          .borderRadius(2)
          .backgroundColor(ThemeRuntime.hairlineColor(this.dark))
          .margin({ right: AppSpacing.XXS })
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(this.scrollbarDragging ? 6 : 4)
          .height(this.scrollbarThumbLength())
          .borderRadius(3)
          .backgroundColor(this.dark ? '#BFD5D8DE' : '#A87A6F63')
          .margin({ right: AppSpacing.XXS })
          .translate({ y: this.displayedScrollbarThumbOffset() })
          .hitTestBehavior(HitTestMode.None)
      }
      .width(24)
      .height(this.listViewportHeight)
      .zIndex(10)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.Vertical, distance: 1 })
            .onActionStart((event: GestureEvent) => this.beginScrollbarDrag(event))
            .onActionUpdate((event: GestureEvent) => this.updateScrollbarDrag(event))
            .onActionEnd((event: GestureEvent) => this.endScrollbarDrag(event))
            .onActionCancel(() => this.cancelScrollbarDrag()),
          TapGesture().onAction((event: GestureEvent) => this.jumpScrollbarToPointer(event))
        )
      )
    }
  }

  @Builder
  bookmarkSummary() {
    if (this.bookmarkMultiSelectMode) {
      Row({ space: AppSpacing.XL }) {
        Text(`已选 ${this.selectedBookmarkIds.length} 项`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.textColor)
          .layoutWeight(1)
        Text(this.selectedBookmarkIds.length === this.bookmarks.length ? '取消全选' : '全选')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.accentColor)
          .onClick(() => this.toggleSelectAllBookmarks())
        Text('删除')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.selectedBookmarkIds.length > 0 ? ThemeRuntime.dangerColor(this.appDarkMode) : this.subTextColor)
          .enabled(this.selectedBookmarkIds.length > 0)
          .onClick(() => {
            this.deleteSelectedBookmarks();
          })
        Text('取消')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor)
          .onClick(() => this.cancelBookmarkMultiSelect())
      }
      .width('100%')
      .height(52)
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL })
      .alignItems(VerticalAlign.Center)
    } else {
      Row() {
        Text(`${this.bookmarks.length} 条书签`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: AppSpacing.XL, bottom: AppSpacing.MD })
    }
  }

  @Builder
  bookmarkList() {
    // 粒子层与空状态、列表放在同一层：删掉最后一条书签切到空状态时，颗粒还要飘完。
    Stack() {
    if (this.bookmarks.length === 0) {
      Column({ space: AppSpacing.LG }) {
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(34)
          .fontColor([this.subTextColor])
        Text('暂无书签')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.subTextColor)
        Text('可使用底栏最右侧按钮添加当前阅读位置')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      List({ space: 0, scroller: this.bookmarkScroller }) {
        ForEach(this.bookmarks, (bookmark: Bookmark) => {
          if (deviceInfo.sdkApiVersion >= 26) {
            // API 26+ uses one left-swipe action panel. Keep multi-select and
            // delete together instead of exposing multi-select on right swipe.
            HdsListItem({
              customItemBuilder: () => {
                this.bookmarkCard(bookmark)
              },
              swipeActionOptions: this.bookmarkSwipeActions(bookmark)
            })
          } else {
            // Older systems use the native ListItem fallback with the same
            // two-button left-swipe action panel.
            ListItem() {
              this.bookmarkCard(bookmark)
            }
            .width('100%')
            .clip(true)
            .swipeAction({
              end: {
                builder: () => {
                  this.bookmarkFallbackSwipeActions(bookmark)
                },
                actionAreaDistance: 128,
                onAction: () => {
                  this.deleteBookmark(bookmark);
                }
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }
        }, (bookmark: Bookmark) => `${bookmark.id}`)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .clip(true)
      .scrollBar(BarState.Auto)
      .scrollBarColor(this.dark ? '#668A8F98' : '#667A6F63')
    }

    if (this.deleteParticleBursts.length > 0) {
      DeleteParticleLayer({ bursts: this.deleteParticleBursts })
    }
    }
    .id('reader_bookmark_list_root')
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  bookmarkCard(bookmark: Bookmark) {
    Column({ space: AppSpacing.XS }) {
      Row() {
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(18)
          .fontColor([this.accentColor])
          .width(26)
        Text(bookmark.chapterName || `第 ${bookmark.chapterIndex + 1} 章`)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`第 ${bookmark.pageIndex + 1} 页`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
      }
      Text(bookmark.content || '已保存阅读位置')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.formatBookmarkTime(bookmark.createTime))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor)
        .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(this.selectedBookmarkIds.includes(bookmark.id) ? this.selectedColor : Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: ThemeRuntime.softFillColor(this.dark) })
    .opacity(ListDissolve.opacity(this.isBookmarkDissolving(bookmark)))
    .scale(ListDissolve.scale(this.isBookmarkDissolving(bookmark)))
    .blur(ListDissolve.blur(this.isBookmarkDissolving(bookmark)))
    .hitTestBehavior(this.isBookmarkDissolving(bookmark) ? HitTestMode.None : HitTestMode.Default)
    .id(this.bookmarkCardElementId(`${bookmark.id}`))
    .onClick(() => {
      if (this.bookmarkMultiSelectMode) this.toggleBookmarkSelection(bookmark.id)
      else this.onJumpToBookmark(bookmark)
    })
    .gesture(LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => {
      if (this.bookmarkMultiSelectMode) return;
      const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
      this.onShowBookmarkActions(bookmark, finger ? finger.globalX : 16, finger ? finger.globalY : 96);
    }))
  }

  @Builder
  bookmarkFallbackSwipeActions(bookmark: Bookmark) {
    Row() {
      this.swipeActionButton($r('sys.symbol.checkmark_circle'), '多选', this.accentColor,
        () => this.enterBookmarkMultiSelect(bookmark.id))
      this.swipeActionButton($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
        this.deleteBookmark(bookmark);
      })
    }
    .height('100%')
  }

  @Builder
  swipeActionButton(icon: Resource, label: string, color: string, action: () => void) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(color)
    .onClick(action)
  }

  @Builder
  noteSummary() {
    Row() {
      Text(`${this.noteItems.length} 条划线`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: AppSpacing.XL, bottom: AppSpacing.MD })
  }

  @Builder
  noteList() {
    // 粒子层与空状态、列表放在同一层：删掉最后一条划线切到空状态时，颗粒还要飘完。
    Stack() {
      if (this.noteItems.length === 0) {
        Column({ space: AppSpacing.LG }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(34)
            .fontColor([this.subTextColor])
          Text('暂无划线')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.subTextColor)
          Text('长按正文选中文字，点“划线”或“笔记”')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 0, scroller: this.noteScroller }) {
          ForEach(this.noteItems, (annotation: BookAnnotation) => {
            if (deviceInfo.sdkApiVersion >= 26) {
              HdsListItem({
                customItemBuilder: () => {
                  this.noteCard(annotation)
                },
                swipeActionOptions: this.noteSwipeActions(annotation)
              })
            } else {
              ListItem() {
                this.noteCard(annotation)
              }
              .width('100%')
              .clip(true)
              .swipeAction({
                end: {
                  builder: () => {
                    this.noteFallbackSwipeActions(annotation)
                  },
                  actionAreaDistance: 64,
                  onAction: () => {
                    this.deleteNote(annotation);
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
            }
          }, (annotation: BookAnnotation) => `${annotation.id}_${annotation.updateTime}`)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .height('100%')
        .clip(true)
        .scrollBar(BarState.Auto)
        .scrollBarColor(this.dark ? '#668A8F98' : '#667A6F63')
      }

      if (this.deleteParticleBursts.length > 0) {
        DeleteParticleLayer({ bursts: this.deleteParticleBursts })
      }
    }
    .id('reader_note_list_root')
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  noteCard(annotation: BookAnnotation) {
    Column({ space: AppSpacing.XS }) {
      Text(annotation.quote)
        .fontSize(AppFontSize.BODY)
        .lineHeight(24)
        .fontColor(annotation.style === BookAnnotationStyles.TEXT ? annotation.color : this.textColor)
        .backgroundColor(annotation.style === BookAnnotationStyles.BACKGROUND ?
          this.withAlpha(annotation.color, '40') : Color.Transparent)
        .decoration({
          type: annotation.style === BookAnnotationStyles.SOLID || annotation.style === BookAnnotationStyles.WAVY ||
            annotation.style === BookAnnotationStyles.DASHED ? TextDecorationType.Underline : TextDecorationType.None,
          color: annotation.color,
          style: annotation.style === BookAnnotationStyles.WAVY ? TextDecorationStyle.WAVY :
            (annotation.style === BookAnnotationStyles.DASHED ? TextDecorationStyle.DASHED : TextDecorationStyle.SOLID)
        })
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (annotation.note.trim()) {
        Text(annotation.note.trim())
          .fontSize(AppFontSize.CAPTION)
          .lineHeight(20)
          .fontColor(this.subTextColor)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: AppSpacing.MD })
          .border({ width: { left: 2 }, color: annotation.color })
          .margin({ top: AppSpacing.XS })
      }
      Row({ space: AppSpacing.MD }) {
        Text(annotation.chapterName || `第 ${annotation.chapterIndex + 1} 章`)
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.subTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.annotationMissing(annotation)) {
          Text('原文已变化')
            .fontSize(AppFontSize.MICRO)
            .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
        }
        Text(this.formatBookmarkTime(annotation.updateTime || annotation.createTime))
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.subTextColor)
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .border({ width: { bottom: 0.5 }, color: ThemeRuntime.softFillColor(this.dark) })
    .opacity(ListDissolve.opacity(this.isNoteDissolving(annotation)))
    .scale(ListDissolve.scale(this.isNoteDissolving(annotation)))
    .blur(ListDissolve.blur(this.isNoteDissolving(annotation)))
    .hitTestBehavior(this.isNoteDissolving(annotation) ? HitTestMode.None : HitTestMode.Default)
    .id(`reader_note_card_${this.noteKey(annotation)}`)
    .onClick(() => this.onJumpToAnnotation(annotation))
  }

  @Builder
  noteFallbackSwipeActions(annotation: BookAnnotation) {
    Row() {
      this.swipeActionButton($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
        this.deleteNote(annotation);
      })
    }
    .height('100%')
  }
}
