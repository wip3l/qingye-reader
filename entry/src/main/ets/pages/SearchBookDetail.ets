import { router } from '@kit.ArkUI';
import { motion } from '@kit.MultimodalAwarenessKit';
import deviceInfo from '@ohos.deviceInfo';
import { Book, BookGroup, SearchBook, BookChapter, BookFieldSanitizer, BookTypeSupport, BookUrlResolver } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { syncSystemBars } from '../utils/SystemBars';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { HeaderBackdrop } from '../components/common/HeaderBackdrop';
import { GlassTagModifier, ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverUrlNormalizer } from '../utils/CoverUrlNormalizer';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ImmersiveReadButton, IMMERSIVE_READ_BUTTON_WIDTH } from '../components/ImmersiveReadButton';
import { BookCover } from '../components/book/BookCover';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { PendingTrialBookCleanup } from '../utils/PendingTrialBookCleanup';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { ShelfWorkDuplicatePrompt } from '../utils/ShelfWorkDuplicatePrompt';
import { BookSourceStageRuntimeHost } from '../components/BookSourceStageRuntimeHost';
import { BookChangeSourceDialog } from '../components/BookChangeSourceDialog';
import { BookCatalogSheet } from '../components/BookCatalogSheet';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';
import { LocalBookService } from '../core/book/LocalBookService';
import { HdsFeedback } from '../utils/HdsFeedback';
import { VideoBookPlayer } from '../utils/VideoBookPlayer';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { KnockShare } from '../utils/KnockShare';
import { AudioSheetTransition, AUDIO_SHEET_ENTER_DURATION, AUDIO_SHEET_EXIT_DURATION } from '../utils/AudioSheetTransition';
import { BookMark, BookMarkRules, BookMarkStatus } from '../model/book/BookMark';
import { BookMarkService } from '../core/mark/BookMarkService';
import { BookMarkStars, bookMarkStarColor } from '../components/book/BookMarkStars';
import { TicketStubRow } from '../components/ticket/TicketStubRow';
import { TicketIssueOverlay } from '../components/ticket/TicketIssueOverlay';
import { ReadingTicket, ReadingTicketRules } from '../core/ticket/ReadingTicket';
import { ReadingTicketLoader } from '../core/ticket/ReadingTicketLoader';
import { TicketAlbumStore } from '../utils/TicketAlbumStore';
import { BookMarkSheet } from '../components/book/BookMarkSheet';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { BookReadStatsPanel } from '../components/book/BookReadStatsPanel';
import { BookReadStatsLoader, BookReadStatsSnapshot } from '../core/stats/BookReadStatsLoader';
import { NewBookGroup } from '../utils/NewBookGroup';
import { NewBookGroupStore } from '../utils/NewBookGroupStore';

@Entry
@Component
struct SearchBookDetailPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('smartGripEnabled') @Watch('onSmartGripEnabledChanged') smartGripEnabled: boolean = true;
  /** 顶栏底色与书名渐显所需的滚动距离。 */
  static readonly TITLE_FADE_DISTANCE: number = 120;
  /** 封面氛围背景的高度。 */
  static readonly AMBIENT_HEIGHT: number = 460;
  /** 简介收起时显示的行数。 */
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State bookUrl: string = '';
  @State tocUrl: string = '';
  @State origin: string = '';
  @State originName: string = '';
  @State name: string = '';
  @State author: string = '';
  @State kind: string = '';
  @State status: string = '';
  @State coverUrl: string = '';
  @State sharedCoverId: string = '';
  @State intro: string = '';
  @State latestChapterTitle: string = '';
  @State totalChapterNum: number = 0;
  @State wordCount: string = '';
  @State updateTime: string = '';
  @State bookType: number = 0;
  private bookVariable: string = '';
  private autoStartRead: boolean = false;
  private autoStartReadTriggered: boolean = false;
  private readerBookUrl: string = '';
  @State openingReader: boolean = false;
  @State readButtonOnLeft: boolean = false;
  @State readButtonBarWidth: number = 0;
  private holdingHandSubscribed: boolean = false;
  private holdingHandPageVisible: boolean = false;
  private holdingHandCallback: (status: motion.HoldingHandStatus) => void =
    (status: motion.HoldingHandStatus): void => this.onHoldingHandChanged(status);
  @State isInShelf: boolean = false;
  /** 书在书架里的分组（> 0 为自定义分组，0 为未分组）与分组名；分组被删掉时名字为空、按未分组显示。 */
  @State shelfGroupId: number = 0;
  @State shelfGroupName: string = '';
  /** “放进分组”面板与面板里列出的分组。 */
  @State showGroupSheet: boolean = false;
  @State shelfGroupOptions: BookGroup[] = [];
  @State newShelfGroupEditing: boolean = false;
  @State newShelfGroupName: string = '';
  /** 点顶栏书架钮加入后，底部停留几秒的“已加入书架　放进分组”提示条。 */
  @State groupNudgeVisible: boolean = false;
  @State groupNudgeText: string = '';
  private groupNudgeTimer: number = -1;
  private static readonly GROUP_NUDGE_MS: number = 4000;
  /** 库里这本书已有阅读进度（含未入架的临时阅读书），阅读按钮显示“继续…”。 */
  @State hasReadProgress: boolean = false;
  @State isSaving: boolean = false;
  @State isLoadingBookInfo: boolean = false;
  @State bookInfoRenderVersion: number = 0;
  private hasLoadedBookInfo: boolean = false;
  private resolvedBookInfo: Book | null = null;
  private bookInfoPromise: Promise<Book | null> | null = null;
  private bookInfoRetryTimerId: number = -1;
  private bookInfoRetryCount: number = 0;
  private shelfCheckPromise: Promise<void> | null = null;
  private shelfCheckKey: string = '';
  private shelfCheckVersion: number = -1;
  @State promptAddToShelfOnBackFromResult: boolean = false;
  @State promptAddToShelfAfterRead: boolean = false;
  @State pendingAddToShelfBookUrl: string = '';
  @State showAddToShelfOnBackDialog: boolean = false;
  private addToShelfOnBackDialogSession: SystemDialogSession = new SystemDialogSession();
  private changeSourceDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('syncChangeSourceDialog') showChangeSourcePanel: boolean = false;
  @State changeSourceTarget: Book | null = null;
  @State showCatalogSheet: boolean = false;
  /** 这部作品的“我的标记”；没有标记时为 null。 */
  @State bookMark: BookMark | null = null;
  @State showMarkSheet: boolean = false;
  /** 刚标成读过、正在出的那张票；null 时不显示出票层。 */
  @State issueTicket: ReadingTicket | null = null;
  @State issueTicketStyle: string = TicketAlbumStore.STYLE_PAPER;
  /** 标记面板正在专注写短评，面板拉到最高档。 */
  @State markSheetFocused: boolean = false;
  @StorageProp('bookMarkRevision') @Watch('onBookMarkRevisionChanged') bookMarkRevision: number = 0;
  private markDraft: BookMark = new BookMark();
  private markCategories: string[] = [];
  private markLoadVersion: number = 0;
  /** 标记页签里直接点选的常用标签：用过的标记标签和书架标签。 */
  @State markQuickTags: string[] = [];
  /** 打开标记面板后直接聚焦短评框。 */
  private markSheetFocusReview: boolean = false;
  /** 页签里连点星星、状态、标签时按顺序保存，后一次在前一次存好的标记上改。 */
  private markSaveChain: Promise<void> = Promise.resolve();
  /**
   * 操作行下面的页签：简介、统计（有阅读记录才有）、标记。进详情页默认从简介开始；
   * 从我的标记、足迹的标记卡进来（参数 initialTab=mark）时直接显示标记。
   */
  static readonly TAB_INTRO: number = 0;
  static readonly TAB_STATS: number = 1;
  static readonly TAB_MARK: number = 2;
  static readonly TAB_LABELS: string[] = ['简介', '统计', '标记'];
  /** 标记页签里最多直接列出几个标签（已选的不受限）。 */
  static readonly MARK_QUICK_TAG_COUNT: number = 6;
  @State detailTabBarWidth: number = 0;
  private static readonly TAB_BAR_PADDING: number = 8;
  private static readonly TAB_INDICATOR_WIDTH: number = 18;
  private static readonly TAB_SWITCH_DURATION: number = 240;
  /** 新内容从哪边进来：1 从右、-1 从左；0 表示还没手动切过，首次显示不做动画。 */
  private detailTabSlide: number = 0;
  @State detailTab: number = 0;
  @State readStats: BookReadStatsSnapshot = new BookReadStatsSnapshot();
  private readStatsLoadVersion: number = 0;
  /** 正文滚动距离：顶栏底色与书名随之渐显。 */
  @State detailScrollY: number = 0;
  @State headerCollapse: number = 0;
  /** 头部封面已加载完成的地址；氛围背景只对它显示，读系统缓存而不再发第二次网络请求。 */
  @State readyCoverUrl: ResourceStr = '';
  private detailScroller: Scroller = new Scroller();
  private knockShareOwner: string = `book-detail-${Date.now()}-${Math.random()}`;
  private openingCatalogChapter: boolean = false;
  private authorSearchDialogBuilder: CustomBuilder | undefined = undefined;
  private authorSearchDialogId: number = -1;
  private changeSourceDialogBuilder: CustomBuilder | undefined = undefined;
  private changeSourceDialogId: number = -1;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;

  aboutToAppear() {
    this.syncBars();
    this.bookInfoRetryCount = 0;
    const params = router.getParams() as Record<string, string>;
    if (params) {
      // Heal result caches produced by older builds that joined every matching descendant URL.
      // Keeping this at the detail boundary also prevents malformed values from becoming shelf IDs.
      this.bookUrl = BookUrlResolver.scalar(params['bookUrl'] || '');
      this.tocUrl = BookUrlResolver.scalar(params['tocUrl'] || '');
      this.origin = params['origin'] || '';
      this.originName = params['originName'] || '';
      this.name = params['name'] || '';
      this.author = params['author'] || '';
      this.kind = params['kind'] || '';
      this.status = params['status'] || '';
      this.coverUrl = params['coverUrl'] || '';
      this.sharedCoverId = params['sharedCoverId'] || '';
      this.intro = BookFieldSanitizer.clean(params['intro'] || '');
      this.latestChapterTitle = params['latestChapterTitle'] || '';
      this.wordCount = params['wordCount'] || '';
      this.updateTime = params['updateTime'] || '';
      this.bookType = Number(params['type'] || 0) || 0;
      this.bookVariable = params['variable'] || '';
      this.promptAddToShelfOnBackFromResult = params['promptAddToShelfOnBack'] === 'true';
      this.autoStartRead = params['autoStartRead'] === 'true';
      this.readerBookUrl = params['readerBookUrl'] || '';
      if (params['initialTab'] === 'mark') this.detailTab = SearchBookDetailPage.TAB_MARK;
      // Both operations initialize/read the same AppDatabase instance. Starting them at the
      // same time can make getBookSource() observe the store before initialization has completed,
      // leaving the detail page with an empty intro until the reader opens the book again.
      // Serialize the source-detail request behind the shelf check so the first page visit uses
      // the same initialized database path as the reader.
      this.checkShelf().then((): void => {
        this.loadBookInfo();
        this.triggerAutoStartRead();
        this.loadBookMark();
        this.loadReadStats();
      });
    }
  }

  onPageShow(): void {
    this.holdingHandPageVisible = true;
    KnockShare.attachBook(this.knockShareOwner, getContext(this),
      (): Book | null => this.name ? this.buildCurrentBook() : null);
    this.startHoldingHandTracking();
    this.syncBars();
    this.checkShelf().then(() => {
      if (this.shouldPromptAddToShelfOnBack()) {
        this.showAddToShelfOnBackPrompt();
      }
    });
    this.refreshChapterCount();
    this.loadBookMark();
    this.loadReadStats();
    // Some source runtimes need one UI turn after the detail route is mounted (especially when the
    // hidden Web transport is still attaching). Do not keep an empty first response cached forever.
    if (!this.intro && !this.isLoadingBookInfo && this.bookUrl && this.origin) {
      this.scheduleBookInfoRetry();
    }
  }

  aboutToDisappear(): void {
    KnockShare.detach(this.knockShareOwner);
    this.holdingHandPageVisible = false;
    this.stopHoldingHandTracking();
    if (this.bookInfoRetryTimerId >= 0) {
      clearTimeout(this.bookInfoRetryTimerId);
      this.bookInfoRetryTimerId = -1;
    }
    this.clearGroupNudgeTimer();
  }

  onPageHide(): void {
    KnockShare.detach(this.knockShareOwner);
    this.holdingHandPageVisible = false;
    this.stopHoldingHandTracking();
  }

  private onSmartGripEnabledChanged(): void {
    if (!this.smartGripEnabled) {
      this.stopHoldingHandTracking();
      this.readButtonOnLeft = false;
    } else {
      this.startHoldingHandTracking();
    }
  }

  private startHoldingHandTracking(): void {
    if (!this.smartGripEnabled || !this.holdingHandPageVisible ||
      this.holdingHandSubscribed || deviceInfo.sdkApiVersion < 20 ||
      !canIUse('SystemCapability.MultimodalAwareness.Motion')) return;
    try {
      this.holdingHandSubscribed = true;
      motion.on('holdingHandChanged', this.holdingHandCallback);
    } catch (error) {
      this.holdingHandSubscribed = false;
      this.readButtonOnLeft = false;
      // 系统能力存在也可能不支持当前机型；保留右下角的常规阅读入口。
      console.warn('握姿感知不可用，阅读按钮保持右侧:', error);
    }
  }

  private stopHoldingHandTracking(): void {
    if (!this.holdingHandSubscribed) return;
    this.holdingHandSubscribed = false;
    try {
      // 仅移除本页回调，不影响系统底栏或其他页面的握姿订阅。
      motion.off('holdingHandChanged', this.holdingHandCallback);
    } catch (error) {
      console.warn('释放书籍详情握姿监听失败:', error);
    }
  }

  private onHoldingHandChanged(status: motion.HoldingHandStatus): void {
    if (!this.smartGripEnabled || !this.holdingHandPageVisible || !this.holdingHandSubscribed) return;
    // 双手、未握持、未知状态沿用上次位置，不让按钮在放下手机时突然跳回。
    if (status !== motion.HoldingHandStatus.LEFT_HAND_HELD &&
      status !== motion.HoldingHandStatus.RIGHT_HAND_HELD) return;
    const onLeft = status === motion.HoldingHandStatus.LEFT_HAND_HELD;
    if (onLeft === this.readButtonOnLeft) return;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, (): void => {
      this.readButtonOnLeft = onLeft;
    });
  }

  private readButtonOffsetX(): number {
    return this.readButtonOnLeft ?
      -Math.max(0, this.readButtonBarWidth - IMMERSIVE_READ_BUTTON_WIDTH - AppSpacing.XL * 2) : 0;
  }

  pageTransition() {
    if (AudioSheetTransition.active()) {
      // 听书页从底部盖上来、再收下去，详情页垫在下面不动。
      PageTransitionExit({ type: RouteType.Push, duration: AUDIO_SHEET_ENTER_DURATION }).opacity(1)
      PageTransitionEnter({ type: RouteType.Pop, duration: AUDIO_SHEET_EXIT_DURATION }).opacity(1)
    }
  }

  build() {
    Stack() {
      WebBookFetchRuntimeHost()
      this.ambientBackdrop()

      Column() {
        Scroll(this.detailScroller) {
          Column() {
            this.detailHero()

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.getTags(), (tag: string, index: number) => {
                this.tagChip(tag, index)
              })

              if (this.wordCount) {
                Text(this.wordCount)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(this.secondaryTextColor())
                  .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
                  .attributeModifier(this.neutralTagModifier())
                  .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
              }

              if (this.updateTime) {
                Text(`更新：${this.updateTime}`)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(this.secondaryTextColor())
                  .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
                  .attributeModifier(this.neutralTagModifier())
                  .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
              }

              if (this.name) {
                this.markSummaryChip()
              }
            }
            .width('100%')
            .margin({ top: AppSpacing.XL })

            this.detailTabBar()

            // 每个分支各包一层，切换时新内容带着淡入和位移进来。
            if (this.activeDetailTab() === SearchBookDetailPage.TAB_STATS) {
              Column() {
                BookReadStatsPanel({ snapshot: this.readStats, chapterUnit: this.chapterUnit() })
              }
              .width('100%')
              .transition(this.detailTabTransition())
            } else if (this.activeDetailTab() === SearchBookDetailPage.TAB_MARK) {
              Column() {
                this.detailMarkBlock()
              }
              .width('100%')
              .transition(this.detailTabTransition())
            } else {
              Column() {
                this.detailChapterRow()
                this.detailIntro()
              }
              .width('100%')
              .transition(this.detailTabTransition())
            }
          }
          .width('100%')
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: 64 + this.statusBarHeight,
            bottom: 96 + this.navBarHeight })
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        // 内容不足一屏时贴顶，Scroll 默认会把它竖直居中。
        .align(Alignment.Top)
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .onDidScroll((_xOffset: number, yOffset: number) => {
          this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
            this.detailScroller.currentOffset().yOffset);
          // 只在跨过渐显区间时更新，滚动中不逐帧刷新整页。
          const offset = Math.max(0, Math.min(SearchBookDetailPage.TITLE_FADE_DISTANCE, this.detailScroller.currentOffset().yOffset));
          if (Math.abs(offset - this.detailScrollY) >= 4 || offset === 0 || offset === SearchBookDetailPage.TITLE_FADE_DISTANCE) {
            this.detailScrollY = offset;
          }
        })
        .onScrollStop(() => {
          const target = CollapsingHeader.settle(this.headerCollapse, this.detailScroller.currentOffset().yOffset);
          if (target !== this.headerCollapse) {
            animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
              this.headerCollapse = target;
            });
          }
        })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      // 目录面板已绑在外层 Stack 上，一个组件只能绑一个半模态，标记面板挂在这一层。
      .bindSheet($$this.showMarkSheet, this.markSheet(), this.markSheetOptions())

      HeaderBackdrop({ statusBarHeight: this.statusBarHeight, backdropHeight: this.statusBarHeight,
        backdropColor: ThemeRuntime.topBarColor(this.appDarkMode) })
        .width('100%')
        .position({ x: 0, y: 0 })
        .opacity(CollapsingHeader.scrimOpacity(this.headerCollapse))
        .hitTestBehavior(HitTestMode.None)

      this.titleBar()

      Row() {
        ImmersiveReadButton({
          label: this.readButtonLabel(),
          icon: BookTypeSupport.isVideo(this.detailTypeProbe()) || BookTypeSupport.isAudio(this.detailTypeProbe()) ?
            $r('sys.symbol.play_fill') : $r('sys.symbol.book'),
          darkMode: this.appDarkMode,
          accentColor: this.accentColor(),
          busy: this.isSaving || this.openingReader || this.openingCatalogChapter,
          onRead: (): void => {
            this.startRead();
          }
        })
          .translate({ x: this.readButtonOffsetX() })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: AppSpacing.XL, bottom: AppSpacing.XL + this.navBarHeight })
      // 锚定整页底边，再上移自身高度；align 不会改变 Row 在父 Stack 中的默认居中位置。
      .position({ x: 0, y: '100%' })
      .translate({ y: '-100%' })
      .hitTestBehavior(HitTestMode.Transparent)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.readButtonBarWidth = Number(newArea.width);
      })
      // 外层 Stack 和正文 Scroll 已各绑了目录、标记半模态，分组面板挂在常驻的阅读按钮这一行。
      .bindSheet($$this.showGroupSheet, this.shelfGroupSheet(), this.shelfGroupSheetOptions())

      if (this.groupNudgeVisible) {
        Row() {
          this.shelfGroupNudge()
        }
        .width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL,
          bottom: AppSpacing.XL + this.navBarHeight + 56 + AppSpacing.MD })
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
        .hitTestBehavior(HitTestMode.Transparent)
        .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Friction }))
      }

      BookSourceStageRuntimeHost()

      if (this.issueTicket) {
        TicketIssueOverlay({
          ticket: this.issueTicket as ReadingTicket,
          ticketStyle: this.issueTicketStyle,
          onOpen: (): void => {
            const ticket = this.issueTicket;
            if (!ticket) return;
            router.pushUrl({ url: 'pages/TicketDetail', params: { workKey: ticket.workKey, fromDetail: 'true' } });
          },
          onClose: (): void => {
            this.issueTicket = null;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showCatalogSheet, this.catalogSheet(), this.catalogSheetOptions())
  }

  /** 换源：系统对话框，API 26+ 是沉浸光感表面。 */
  @Builder
  changeSourceDialogContent() {
    BookChangeSourceDialog({
      targetBook: this.changeSourceTarget,
      onSwitched: (switched: Book): void => {
        this.applySwitchedSource(switched);
      },
      onClosed: (): void => {
        this.showChangeSourcePanel = false;
        this.changeSourceTarget = null;
      }
    })
  }

  syncChangeSourceDialog(): void {
    this.changeSourceDialogSession.sync(this.getUIContext(), this.showChangeSourcePanel, (): void => {
      this.changeSourceDialogContent();
    }, {
      autoCancel: true,
      onDismiss: (): void => { this.showChangeSourcePanel = false; },
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示换源弹窗失败:'
    });
  }

  /** 半模态直接承载材质和目录内容，避免拖动时反复测量并重排内部的材质 TabBar。 */
  catalogSheetOptions(): SheetOptions {
    const options: SheetOptions = {
      detents: ['67%', SheetSize.LARGE],
      dragBar: false,
      showClose: false,
      backgroundColor: Color.Transparent,
      blurStyle: BlurStyle.NONE,
      borderWidth: 0,
      radius: { topLeft: 28, topRight: 28, bottomLeft: 28, bottomRight: 28 },
      shadow: { radius: 0, color: Color.Transparent },
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onDisappear: () => {
        this.showCatalogSheet = false;
      }
    };
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, options,
      this.appDarkMode, this.accentColor());
  }

  @Builder
  catalogSheet() {
    BookCatalogSheet({
      book: this.buildCurrentBook(),
      onChapterSelected: (chapter: BookChapter): void => {
        this.openChapterFromCatalog(chapter);
      },
      onLoaded: (count: number): void => {
        this.totalChapterNum = count;
      },
      onClose: (): void => {
        this.showCatalogSheet = false;
      }
    })
  }

  @Builder
  titleBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
          buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
          onBack: () => this.handleBack() })

        Text(this.titleBarProgress() > 0.6 ? (this.name || this.detailPageTitle()) : this.detailPageTitle())
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        // 书架与目录在顶栏右侧，和返回按钮同一种沉浸光感圆钮。同作者、换源分别是点作者行、书源行。
        ImmersiveHeaderAction({
          icon: this.isInShelf ? $r('sys.symbol.bookshelf_badge_checkmark_fill') :
            $r('sys.symbol.bookshelf_badge_plus'),
          tint: this.isInShelf ? this.accentColor() : '',
          actionEnabled: !this.isSaving,
          accessibilityLabel: this.isInShelf ? '已在书架，点按移出书架' : '加入书架',
          onTap: (): void => {
            if (this.isInShelf) {
              this.removeFromShelf();
            } else {
              this.addToShelf(true);
            }
          }
        })
          .margin({ left: AppSpacing.MD })
        ImmersiveHeaderAction({
          icon: $r('sys.symbol.list_bullet'),
          accessibilityLabel: BookTypeSupport.isVideo(this.detailTypeProbe()) ? '选集' : '目录',
          onTap: (): void => {
            this.openChapterList();
          }
        })
          .margin({ left: AppSpacing.MD })
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ right: AppSpacing.XL, top: this.statusBarHeight })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56 + this.statusBarHeight - this.headerCollapse)
    .clip(true)
    .opacity(CollapsingHeader.contentOpacity(this.headerCollapse))
    .hitTestBehavior(CollapsingHeader.acceptsTouch(this.headerCollapse) ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(CollapsingHeader.acceptsTouch(this.headerCollapse) ? 'auto' : 'no-hide-descendants')
    .position({ x: 0, y: 0 })
  }

  titleBarProgress(): number {
    return Math.min(1, this.detailScrollY / SearchBookDetailPage.TITLE_FADE_DISTANCE);
  }

  detailPageTitle(): string {
    return BookTypeSupport.isVideo(this.detailTypeProbe()) ? '剧集详情' : '书籍详情';
  }

  /**
   * 封面氛围背景：封面低分辨率模糊铺在顶部，上面盖一层“透明 → 页面底色”的渐变，渐变底部是不透明的页面色、
   * 正好对齐图片底边，所以图片底部自然消失、没有硬边。页面底色层与渐变层始终不透明，滚动时只淡化图片这一层。
   * 封面等头部封面加载完成后再显示，读系统缓存，不再发第二次网络请求。
   */
  @Builder
  ambientBackdrop() {
    Stack({ alignContent: Alignment.Top }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.pageColor())

      if (this.readyCoverUrl) {
        Image(this.readyCoverUrl)
          .width('100%')
          .height(SearchBookDetailPage.AMBIENT_HEIGHT)
          .objectFit(ImageFit.Cover)
          .sourceSize({ width: 96, height: 128 })
          .blur(48)
          .opacity((this.appDarkMode ? 0.5 : 0.62) * (1 - this.titleBarProgress() * 0.4))
      }

      Column()
        .width('100%')
        .height(SearchBookDetailPage.AMBIENT_HEIGHT)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            // 顶部也叠一层淡淡的页面色，保证作者、书源等次要文字在封面色上看得清。
            [`#40${this.pageColor().substring(1)}`, 0],
            [`#33${this.pageColor().substring(1)}`, 0.3],
            [`#A6${this.pageColor().substring(1)}`, 0.68],
            [this.pageColor(), 1]
          ]
        })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 头部：封面、书名、作者与书源直接放在氛围背景上，不再套卡片。 */
  @Builder
  detailHero() {
    Row({ space: AppSpacing.XL }) {
      Stack() {
        this.coverView()
      }
      .width(104)
      .height(140)
      .sharedTransition(this.sharedCoverId, { duration: 360, curve: Curve.Friction, type: SharedTransitionEffectType.Exchange })
      // 投影按外层形状绘制，不给圆角会是直角矩形的影子，在封面四角露出来。
      .borderRadius(8)
      .shadow({ radius: 16, color: this.appDarkMode ? '#66000000' : '#33000000', offsetX: 0, offsetY: 6 })

      Column() {
        Text(this.name || '未知书名')
          .fontSize(AppFontSize.HEADLINE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: AppSpacing.XXS }) {
          Text(this.author || '作者未知')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (this.author) {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([this.subTextColor()])
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: AppSpacing.MD })
        .onClick(() => {
          if (this.author) {
            this.showAuthorSearchPrompt();
          }
        })

        if (this.originName || this.origin) {
          Row({ space: AppSpacing.XS }) {
            SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
              .fontSize(13)
              .fontColor([this.subTextColor()])
            Text(this.originName || this.origin)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(12)
              .fontColor([this.subTextColor()])
          }
          .alignItems(VerticalAlign.Center)
          .margin({ top: AppSpacing.SM })
          .accessibilityText(`书源${this.originName || this.origin}，换源`)
          .onClick(() => {
            this.showChangeSourcePrompt();
          })
        }

        if (this.isInShelf) {
          this.shelfGroupChip()
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: AppSpacing.LG })
    .alignItems(VerticalAlign.Center)
  }

  private hasReadStats(): boolean {
    return this.readStats.stats.activeDays > 0;
  }

  /** 统计页签没有了（记录被删、换了一本书）或书名还没有时落回简介。 */
  private activeDetailTab(): number {
    if (this.detailTab === SearchBookDetailPage.TAB_STATS && !this.hasReadStats()) return SearchBookDetailPage.TAB_INTRO;
    if (this.detailTab === SearchBookDetailPage.TAB_MARK && !this.name) return SearchBookDetailPage.TAB_INTRO;
    return this.detailTab;
  }

  private chapterUnit(): string {
    return BookTypeSupport.isVideo(this.detailTypeProbe()) || BookTypeSupport.isAudio(this.detailTypeProbe()) ? '集' :
      LocalBookService.isPdfBook(this.detailTypeProbe()) ? '页' : '章';
  }

  private async loadReadStats(): Promise<void> {
    const version = ++this.readStatsLoadVersion;
    try {
      const snapshot = await BookReadStatsLoader.load(getContext(this), this.bookUrl, this.name, this.author);
      if (version === this.readStatsLoadVersion) this.readStats = snapshot;
    } catch (error) {
      console.warn('读取本书阅读统计失败:', error);
    }
  }

  /** 分段条上依次有哪些页签：统计要有阅读记录，标记要有书名。 */
  private detailTabs(): number[] {
    const tabs: number[] = [SearchBookDetailPage.TAB_INTRO];
    if (this.hasReadStats()) tabs.push(SearchBookDetailPage.TAB_STATS);
    if (this.name) tabs.push(SearchBookDetailPage.TAB_MARK);
    return tabs;
  }

  private selectDetailTab(tab: number): void {
    const tabs = this.detailTabs();
    const from = tabs.indexOf(this.activeDetailTab());
    const to = tabs.indexOf(tab);
    if (to < 0 || to === from) return;
    this.detailTabSlide = to > from ? 1 : -1;
    this.detailTab = tab;
  }

  /**
   * 页签内容的进场：朝切换方向滑入一小段并淡入。旧内容直接撤掉，不做退场，
   * 否则新旧两块在同一列里上下叠着，页面高度会先撑开再缩回。
   */
  private detailTabTransition(): TransitionEffect {
    if (this.detailTabSlide === 0) return TransitionEffect.IDENTITY;
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: this.detailTabSlide * 28 }))
        .animation({ duration: SearchBookDetailPage.TAB_SWITCH_DURATION, curve: Curve.Friction }),
      TransitionEffect.IDENTITY);
  }

  /** 下划线左边距：在选中那一段里居中。 */
  private detailTabIndicatorX(): number {
    const tabs = this.detailTabs();
    const inner = Math.max(0, this.detailTabBarWidth - SearchBookDetailPage.TAB_BAR_PADDING * 2);
    const segment = inner / Math.max(1, tabs.length);
    const index = Math.max(0, tabs.indexOf(this.activeDetailTab()));
    return SearchBookDetailPage.TAB_BAR_PADDING + segment * index +
      (segment - SearchBookDetailPage.TAB_INDICATOR_WIDTH) / 2;
  }

  /**
   * 整宽的页签条，和书源管理页的格式切换条同一种样式：一块沉浸光感底板，选中项用强调色文字加一小段下划线。
   * 有几个页签就等分成几段；材质底板要具体宽度，量外层这一行得到。下划线是同一条，切换时滑到新位置。
   */
  @Builder
  detailTabBar() {
    Row() {
      if (this.detailTabBarWidth > 0) {
        ImmersiveMaterialSurface({
          surfaceWidth: this.detailTabBarWidth,
          surfaceHeight: 44,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: `#40${this.accentColor().substring(1)}`
        }) {
          Stack({ alignContent: Alignment.BottomStart }) {
            Row() {
              ForEach(this.detailTabs(), (tab: number) => {
                Text(SearchBookDetailPage.TAB_LABELS[tab])
                  .fontSize(AppFontSize.BODY_LARGE)
                  .fontWeight(this.activeDetailTab() === tab ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.activeDetailTab() === tab ? this.accentColor() : this.secondaryTextColor())
                  .animation({ duration: SearchBookDetailPage.TAB_SWITCH_DURATION, curve: Curve.Friction })
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  .height('100%')
                  .layoutWeight(1)
                  .accessibilityText(SearchBookDetailPage.TAB_LABELS[tab])
                  .accessibilitySelected(this.activeDetailTab() === tab)
                  .onClick(() => {
                    this.selectDetailTab(tab);
                  })
              }, (tab: number): string => `${tab}`)
            }
            .width('100%')
            .height('100%')
            .padding({ left: SearchBookDetailPage.TAB_BAR_PADDING, right: SearchBookDetailPage.TAB_BAR_PADDING })

            Row()
              .width(SearchBookDetailPage.TAB_INDICATOR_WIDTH)
              .height(3)
              .borderRadius(1.5)
              .backgroundColor(this.accentColor())
              .margin({ bottom: 6 })
              .translate({ x: this.detailTabIndicatorX() })
              .animation({ duration: SearchBookDetailPage.TAB_SWITCH_DURATION, curve: Curve.Friction })
              .hitTestBehavior(HitTestMode.None)
              .accessibilityLevel('no')
          }
          .width('100%')
          .height('100%')
        }
      }
    }
    .width('100%')
    .height(44)
    .margin({ top: AppSpacing.SM })
    .onSizeChange((_old: SizeOptions, next: SizeOptions) => {
      this.detailTabBarWidth = Math.floor(Number(next.width ?? 0));
    })
  }

  /**
   * 标签行末尾的标记摘要：有评分或状态时显示“★4.0 · 养肥”，标过但只有标签、短评时显示“已标记”，
   * 没标过显示“☆ 标记”。点它切到标记页签，不用先进页签才看得到评分和状态。
   */
  @Builder
  markSummaryChip() {
    Row({ space: 3 }) {
      if (this.bookMark && this.bookMark.rating > 0) {
        Text('★')
          .fontSize(AppFontSize.BODY)
          .fontColor(bookMarkStarColor(this.appDarkMode))
      } else if (!this.bookMark) {
        Text('☆')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
      }
      Text(this.markSummaryText())
        .fontSize(AppFontSize.BODY)
        .fontColor(this.bookMark ? this.primaryTextColor() : this.secondaryTextColor())
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
    .attributeModifier(this.neutralTagModifier())
    .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
    .accessibilityText(this.bookMark ? `我的标记，${this.markSummaryText()}` : '标记这本书')
    .onClick(() => {
      this.selectDetailTab(SearchBookDetailPage.TAB_MARK);
    })
  }

  private markSummaryText(): string {
    const mark = this.bookMark;
    if (!mark) return '标记';
    const parts: string[] = [];
    if (mark.rating > 0) parts.push(BookMarkRules.ratingText(mark.rating));
    if (mark.status !== BookMarkStatus.NONE) parts.push(BookMarkStatus.label(mark.status));
    return parts.length > 0 ? parts.join(' · ') : '已标记';
  }

  /**
   * “标记”页签：评分、阅读状态、常用标签、短评按标记面板的顺序直接摆出来，没标过的书也不留空白。
   * 星星、状态、标签点一下就保存（再点同一项取消）；“＋ 新标签”打开面板，点短评打开面板并聚焦短评框。
   */
  @Builder
  detailMarkBlock() {
    Column({ space: AppSpacing.MD }) {
      this.markFieldLabel('评分', this.bookMark ? this.markDateText() : '点一下就保存')
      Row({ space: AppSpacing.MD }) {
        BookMarkStars({
          rating: this.bookMark ? this.bookMark.rating : 0,
          starSize: 28,
          darkMode: this.appDarkMode,
          emptyColor: ThemeRuntime.softFillColor(this.appDarkMode),
          interactive: true,
          onRate: (rating: number): void => {
            this.rateFromDetail(rating);
          }
        })
        if (this.bookMark && this.bookMark.rating > 0) {
          Text(`${BookMarkRules.ratingText(this.bookMark.rating)} · ${BookMarkRules.ratingLabel(this.bookMark.rating)}`)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.secondaryTextColor())
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      this.markFieldLabel('阅读状态', '')
      Row({ space: 3 }) {
        ForEach(BookMarkStatus.ALL, (value: number) => {
          Text(BookMarkStatus.label(value))
            .fontSize(AppFontSize.BODY)
            .fontWeight(this.detailMarkStatus() === value ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.detailMarkStatus() === value ? this.primaryTextColor() : this.secondaryTextColor())
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .borderRadius(ThemeRuntime.mediumRadius() - 2)
            .backgroundColor(this.detailMarkStatus() === value ? ThemeRuntime.cardColor(this.appDarkMode) :
              Color.Transparent)
            .shadow(this.detailMarkStatus() === value ? { radius: 4, color: '#1A000000', offsetY: 1 } :
              { radius: 0, color: Color.Transparent })
            .accessibilityText(`${BookMarkStatus.label(value)}${this.detailMarkStatus() === value ? '，已选' : ''}`)
            .onClick(() => {
              this.statusFromDetail(value);
            })
        }, (value: number) => `${value}`)
      }
      .width('100%')
      .padding(3)
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))

      this.markFieldLabel(this.markQuickTags.length > 0 ? '常用标签' : '标签', '')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.detailTagChoices(), (name: string) => {
          Text(name)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.detailHasTag(name) ? this.accentColor() : this.secondaryTextColor())
            .height(30)
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
            .borderRadius(15)
            .border({ width: 1, color: this.detailHasTag(name) ? this.accentColor() : Color.Transparent })
            .backgroundColor(this.detailHasTag(name) ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) :
              ThemeRuntime.softFillColor(this.appDarkMode))
            .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
            .accessibilityText(`${name}${this.detailHasTag(name) ? '，已选' : ''}`)
            .onClick(() => {
              this.toggleTagFromDetail(name);
            })
        }, (name: string) => name)
        Text('＋ 新标签')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.accentColor())
          .height(30)
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
          .borderRadius(15)
          .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
          .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
          .onClick(() => {
            this.openMarkSheet();
          })
      }
      .width('100%')
      .margin({ bottom: -AppSpacing.SM })

      this.markFieldLabel('短评', '')
      if (this.bookMark && this.bookMark.review.trim()) {
        Text(this.bookMark.review.trim())
          .fontSize(AppFontSize.BODY_LARGE)
          .lineHeight(24)
          .fontColor(this.primaryTextColor())
          .wordBreak(WordBreak.BREAK_WORD)
          .width('100%')
          .onClick(() => {
            this.openMarkSheet(true);
          })
      } else {
        Text('读完的感受、推荐给谁、记住的一个细节……')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .constraintSize({ minHeight: 72 })
          .align(Alignment.TopStart)
          .padding(AppSpacing.LG)
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
          .accessibilityText('写短评')
          .onClick(() => {
            this.openMarkSheet(true);
          })
      }

      if (this.bookMark && ReadingTicketRules.hasTicket(this.bookMark as BookMark)) {
        TicketStubRow({
          mark: this.bookMark as BookMark,
          markKey: `${(this.bookMark as BookMark).workKey}|${(this.bookMark as BookMark).status}|` +
            `${(this.bookMark as BookMark).updateTime}`
        })
          .margin({ top: AppSpacing.XS })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: AppSpacing.XL })
  }

  @Builder
  markFieldLabel(title: string, hint: string) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
      Blank()
      if (hint) {
        Text(hint)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
      }
    }
    .width('100%')
    .margin({ top: AppSpacing.XS })
  }

  private detailMarkStatus(): number {
    return this.bookMark ? this.bookMark.status : BookMarkStatus.NONE;
  }

  private detailHasTag(name: string): boolean {
    return this.bookMark !== null && this.bookMark.categories.includes(name);
  }

  /** 已选的标签全部列出，再用常用标签补到 6 个。 */
  private detailTagChoices(): string[] {
    const result: string[] = this.bookMark ? this.bookMark.categories.slice() : [];
    for (const name of this.markQuickTags) {
      if (result.length >= SearchBookDetailPage.MARK_QUICK_TAG_COUNT) break;
      if (!result.includes(name)) result.push(name);
    }
    return result;
  }

  private markDateText(): string {
    const mark = this.bookMark;
    if (!mark) return '';
    const finished = mark.status === BookMarkStatus.READ && mark.finishTime > 0;
    const date = new Date(finished ? mark.finishTime : mark.updateTime);
    const label = `${date.getMonth() + 1}月${date.getDate()}日`;
    const day = date.getFullYear() === new Date().getFullYear() ? label : `${date.getFullYear()}年${label}`;
    return finished ? `${day}读完` : `${day}标记`;
  }

  @Builder
  markSheet() {
    BookMarkSheet({
      initial: this.markDraft,
      knownCategories: this.markCategories,
      existing: this.bookMark !== null,
      coverBookUrl: this.bookUrl,
      coverOrigin: this.origin,
      focusReview: this.markSheetFocusReview,
      onSave: (mark: BookMark): void => {
        this.saveMarkFromSheet(mark);
      },
      onDelete: (): void => {
        this.deleteMarkFromSheet();
      },
      onClose: (): void => {
        this.showMarkSheet = false;
      },
      onFocusModeChange: (focused: boolean): void => {
        this.markSheetFocused = focused;
      }
    })
  }

  /**
   * 写短评时拉到最高档、键盘收起回到默认档；RESIZE_ONLY 让面板压缩高度让出键盘，
   * 面板内容据此把短评框撑到键盘顶边。
   */
  markSheetOptions(): SheetOptions {
    const options: SheetOptions = {
      detents: ['78%', SheetSize.LARGE],
      detentSelection: this.markSheetFocused ? SheetSize.LARGE : '78%',
      keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      blurStyle: BlurStyle.NONE,
      borderWidth: 0,
      radius: { topLeft: 28, topRight: 28, bottomLeft: 28, bottomRight: 28 },
      shadow: { radius: 0, color: Color.Transparent },
      onDisappear: () => {
        this.showMarkSheet = false;
        this.markSheetFocused = false;
      }
    };
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, options,
      this.appDarkMode, this.accentColor());
  }

  /** 目录入口：“最新 · 章节名”，右侧总章数；目录是章节列表的唯一入口，没有最新章节名时也保留。 */
  @Builder
  detailChapterRow() {
    Row({ space: AppSpacing.SM }) {
      Text() {
        Span(BookTypeSupport.isVideo(this.detailTypeProbe()) ? '选集' : '最新')
          .fontColor(this.secondaryTextColor())
        Span(' · ')
          .fontColor(this.subTextColor())
        Span(this.latestChapterTitle || '点击查看完整章节列表')
          .fontColor(this.primaryTextColor())
      }
      .fontSize(AppFontSize.BODY_LARGE)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)

      if (this.totalChapterNum > 0) {
        Text(`共 ${this.totalChapterNum} ${BookTypeSupport.isVideo(this.detailTypeProbe()) ||
          BookTypeSupport.isAudio(this.detailTypeProbe()) ? '集' : LocalBookService.isPdfBook(this.detailTypeProbe()) ? '页' : '章'}`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openChapterList();
    })
  }

  @Builder
  detailIntro() {
    Column({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(16)
          .fontColor([this.subTextColor()])
        Text('简介')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
      }
      .alignItems(VerticalAlign.Center)

      Text(this.intro || (this.isLoadingBookInfo ? '简介加载中...' : '暂无简介'))
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.secondaryTextColor())
        .lineHeight(26)
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
        .id(`book_detail_intro_${this.bookInfoRenderVersion}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: AppSpacing.MD })
  }

  private readButtonLabel(): string {
    const verb = this.hasReadProgress ? '继续' : '开始';
    const probe = this.detailTypeProbe();
    if (BookTypeSupport.isVideo(probe)) return `${verb}观看`;
    if (BookTypeSupport.isAudio(probe)) return `${verb}听书`;
    return `${verb}阅读`;
  }

  onBackPress(): boolean {
    if (this.shouldPromptAddToShelfOnBack()) {
      this.showAddToShelfOnBackPrompt();
      return true;
    }
    return false;
  }

  async checkShelf(): Promise<void> {
    const key = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
    const version = AppStorage.get<number>('shelfUpdateTime') || 0;
    if (this.shelfCheckPromise) return this.shelfCheckPromise;
    if (key && key === this.shelfCheckKey && version === this.shelfCheckVersion) return;
    const task = this.performShelfCheck();
    this.shelfCheckPromise = task;
    try {
      await task;
      this.shelfCheckKey = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
      this.shelfCheckVersion = AppStorage.get<number>('shelfUpdateTime') || 0;
    } finally {
      if (this.shelfCheckPromise === task) this.shelfCheckPromise = null;
    }
  }

  private async performShelfCheck(): Promise<void> {
    if (!this.bookUrl || this.bookUrl.trim() === '') {
      this.isInShelf = false;
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const existing = await db.getBook(this.bookUrl) ||
        await this.findShelfBookByKey(BookIdentity.keyOfUrl(this.bookUrl, this.origin));
      if (existing) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
          await db.updateBook(existing, true, 'detail_check_cover_update');
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
      }
      if (existing) {
        this.syncStateFromBook(existing);
      }
      this.hasReadProgress = existing !== null && Book.hasStartedReading(existing);
      this.isInShelf =existing !== null && !SearchExplorePendingBook.isPendingAddToShelf(existing);
    } catch (e) {
      console.error('检查书架失败:', e);
      this.isInShelf = false;
    }
  }

  async removeFromShelf(): Promise<void> {
    if (this.isSaving || !this.isInShelf) return;
    this.isSaving = true;
    try {
      const book = new SearchBook();
      book.bookUrl = this.bookUrl;
      book.origin = this.origin;
      await SearchBookShelfHelper.removeFromShelf(getContext(this), book);
      this.hideGroupNudge();
      this.showGroupSheet = false;
      this.isInShelf = false;
      this.hasReadProgress = false;
      this.promptAddToShelfAfterRead = false;
      this.pendingAddToShelfBookUrl = '';
      this.shelfCheckKey = '';
      this.shelfCheckVersion = -1;
    } catch (e) {
      console.error('移出书架失败:', e);
      HdsFeedback.showToast('移出书架失败');
    } finally {
      this.isSaving = false;
    }
  }

  /** fromHeader：点顶栏书架钮加入，加入后出“放进分组”提示条；其他入口（返回提示、开始阅读）只弹提示。 */
  async addToShelf(fromHeader: boolean = false): Promise<boolean> {
    if (!this.bookUrl) {
      HdsFeedback.showToast('书籍地址为空');
      return false;
    }

    this.isSaving = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const requestKey = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
      const existing = await db.getBook(this.bookUrl) || await this.findShelfBookByKey(requestKey);
      if (existing) {
        const existingWasPending = SearchExplorePendingBook.isPendingAddToShelf(existing);
        if (existingWasPending) {
          const resolved = await this.resolveSameWorkBeforeShelf(existing);
          if (resolved !== null) return resolved;
        }
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
        }
        existing.kind = BookFieldSanitizer.prefer(this.kind, existing.kind);
        existing.status = BookFieldSanitizer.prefer(this.status, existing.status);
        existing.intro = BookFieldSanitizer.prefer(this.intro, existing.intro);
        existing.latestChapterTitle = BookFieldSanitizer.prefer(this.latestChapterTitle, existing.latestChapterTitle);
        existing.wordCount = BookFieldSanitizer.prefer(this.wordCount, existing.wordCount);
        existing.updateTime = BookFieldSanitizer.prefer(this.updateTime, existing.updateTime);
        // 试读过的书这时才真正入架，按新书套默认分组；本来就在书架的书不动分组。
        const existingGroupName = existingWasPending ? await NewBookGroupStore.apply(getContext(this), existing) : '';
        SearchExplorePendingBook.clearPendingAddToShelf(existing);
        await BookMarkService.carryTagsToShelfBook(existing);
        await db.updateBook(existing, true, 'explicit_add_existing');
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        this.syncStateFromBook(existing);
        this.isInShelf = true;
        this.promptAddToShelfAfterRead = false;
        this.pendingAddToShelfBookUrl = '';
        this.announceAddedToShelf(existingGroupName, fromHeader, false);
        return true;
      }

      const book = new Book();
      book.bookUrl = this.bookUrl;
      book.tocUrl = this.tocUrl;
      book.origin = this.origin;
      book.originName = this.originName;
      book.name = this.name;
      book.author = this.author;
      book.kind = BookFieldSanitizer.clean(this.kind);
      book.status = BookFieldSanitizer.clean(this.status);
      book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
      book.intro = BookFieldSanitizer.clean(this.intro);
      book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
      book.wordCount = BookFieldSanitizer.clean(this.wordCount);
      book.updateTime = BookFieldSanitizer.clean(this.updateTime);
      book.group = NewBookGroup.UNGROUPED;
      book.type = this.bookType;
      book.variable = this.bookVariable;
      BookTypeSupport.applyBookType(book);
      book.canUpdate = true;
      book.lastCheckTime = Date.now();
      book.latestChapterTime = Date.now();
      const fallbackCoverUrl = book.coverUrl;
      const fullBook = await this.resolveBookInfo();
      if (fullBook) {
        book.bookUrl = fullBook.bookUrl || book.bookUrl;
        book.tocUrl = fullBook.tocUrl || book.tocUrl;
        book.name = fullBook.name || book.name;
        book.author = fullBook.author || book.author;
        book.kind = BookFieldSanitizer.prefer(fullBook.kind, book.kind);
        book.status = BookFieldSanitizer.prefer(fullBook.status, book.status);
        book.coverUrl = CoverUrlNormalizer.prefer(fallbackCoverUrl, fullBook.coverUrl || book.coverUrl);
        book.intro = BookFieldSanitizer.prefer(fullBook.intro, book.intro);
        book.latestChapterTitle = BookFieldSanitizer.prefer(fullBook.latestChapterTitle, book.latestChapterTitle);
        book.updateTime = BookFieldSanitizer.prefer(fullBook.updateTime, book.updateTime);
        book.wordCount = BookFieldSanitizer.prefer(fullBook.wordCount, book.wordCount);
        book.variable = fullBook.variable || book.variable;
        book.type = fullBook.type || book.type;
      }

      const resolvedExisting = await this.findShelfBookByKey(BookIdentity.keyOfBook(book));
      if (resolvedExisting) {
        const resolvedWasPending = SearchExplorePendingBook.isPendingAddToShelf(resolvedExisting);
        if (resolvedWasPending) {
          const resolved = await this.resolveSameWorkBeforeShelf(resolvedExisting);
          if (resolved !== null) return resolved;
        }
        const nextCoverUrl = CoverUrlNormalizer.prefer(book.coverUrl, resolvedExisting.coverUrl);
        if (nextCoverUrl && resolvedExisting.coverUrl !== nextCoverUrl) {
          resolvedExisting.coverUrl = nextCoverUrl;
        }
        resolvedExisting.kind = BookFieldSanitizer.prefer(book.kind, resolvedExisting.kind);
        resolvedExisting.status = BookFieldSanitizer.prefer(book.status, resolvedExisting.status);
        resolvedExisting.intro = BookFieldSanitizer.prefer(book.intro, resolvedExisting.intro);
        resolvedExisting.latestChapterTitle = BookFieldSanitizer.prefer(book.latestChapterTitle, resolvedExisting.latestChapterTitle);
        resolvedExisting.updateTime = BookFieldSanitizer.prefer(book.updateTime, resolvedExisting.updateTime);
        resolvedExisting.wordCount = BookFieldSanitizer.prefer(book.wordCount, resolvedExisting.wordCount);
        const resolvedGroupName = resolvedWasPending ?
          await NewBookGroupStore.apply(getContext(this), resolvedExisting) : '';
        SearchExplorePendingBook.clearPendingAddToShelf(resolvedExisting);
        await BookMarkService.carryTagsToShelfBook(resolvedExisting);
        await db.updateBook(resolvedExisting, true, 'explicit_add_resolved_existing');
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        this.syncStateFromBook(resolvedExisting);
        this.isInShelf = true;
        this.promptAddToShelfAfterRead = false;
        this.pendingAddToShelfBookUrl = '';
        this.announceAddedToShelf(resolvedGroupName, fromHeader, false);
        return true;
      }

      const resolved = await this.resolveSameWorkBeforeShelf(book);
      if (resolved !== null) return resolved;
      const groupName = await NewBookGroupStore.apply(getContext(this), book);
      SearchExplorePendingBook.clearPendingAddToShelf(book);
      await BookMarkService.carryTagsToShelfBook(book);
      await db.insertBook(book, 'explicit_add_from_detail');
      this.syncStateFromBook(book);

      this.isInShelf = true;
      this.promptAddToShelfAfterRead = false;
      this.pendingAddToShelfBookUrl = '';
      this.isSaving = false;
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      this.announceAddedToShelf(groupName, fromHeader, true);
      return true;
    } catch (e) {
      console.error('加入书架失败:', e);
      HdsFeedback.showToast('加入书架失败');
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async loadBookInfo(): Promise<void> {
    try {
      const fullBook = await this.resolveBookInfo();
      if (fullBook) this.syncStateFromBook(fullBook);
      if (!this.intro) this.scheduleBookInfoRetry();
    } catch (e) {
      console.warn('加载书籍详情失败:', e);
      this.scheduleBookInfoRetry();
    }
  }

  private scheduleBookInfoRetry(): void {
    if (this.intro || !this.bookUrl || !this.origin || this.bookInfoRetryCount >= 4) return;
    if (this.bookInfoRetryTimerId >= 0) return;
    const retry = this.bookInfoRetryCount++;
    const delay = retry === 0 ? 500 : (retry === 1 ? 1200 : (retry === 2 ? 2500 : 5000));
    this.bookInfoRetryTimerId = setTimeout((): void => {
      this.bookInfoRetryTimerId = -1;
      if (this.intro || !this.bookUrl || !this.origin || this.isLoadingBookInfo) return;
      // WebBookService returns the original Book instance when a request or rule yields no fields. Clear
      // that incomplete cache so the next attempt can observe a newly attached runtime/session.
      this.resolvedBookInfo = null;
      this.hasLoadedBookInfo = false;
      this.loadBookInfo();
    }, delay);
  }

  private async resolveBookInfo(): Promise<Book | null> {
    if (this.resolvedBookInfo) return this.resolvedBookInfo;
    if (this.bookInfoPromise) return this.bookInfoPromise;
    if (this.hasLoadedBookInfo || !this.bookUrl || !this.origin) return null;
    this.hasLoadedBookInfo = true;
    this.isLoadingBookInfo = true;
    const task = this.fetchBookInfo();
    this.bookInfoPromise = task;
    try {
      const fullBook = await task;
      if (fullBook) {
        fullBook.lastCheckTime = Date.now();
        this.resolvedBookInfo = fullBook;
        this.syncStateFromBook(fullBook);
      }
      return fullBook;
    } finally {
      if (this.bookInfoPromise === task) this.bookInfoPromise = null;
      this.isLoadingBookInfo = false;
    }
  }

  private async fetchBookInfo(): Promise<Book | null> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    const source = await db.getBookSource(this.origin);
    if (!source) return null;
    const book = this.buildCurrentBook();
    BookTypeSupport.applyBookType(book, source);
    return new WebBookService().getBookInfo(source, book);
  }

  private buildCurrentBook(): Book {
    const book = new Book();
    book.bookUrl = this.bookUrl;
    book.tocUrl = this.tocUrl;
    book.origin = this.origin;
    book.originName = this.originName;
    book.name = this.name;
    book.author = this.author;
    book.kind = BookFieldSanitizer.clean(this.kind);
    book.status = BookFieldSanitizer.clean(this.status);
    book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
    book.intro = BookFieldSanitizer.clean(this.intro);
    book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.clean(this.wordCount);
    book.updateTime = BookFieldSanitizer.clean(this.updateTime);
    book.type = this.bookType;
    book.variable = this.bookVariable;
    return book;
  }

  handleBack(): void {
    if (this.shouldPromptAddToShelfOnBack()) {
      this.showAddToShelfOnBackPrompt();
      return;
    }
    router.back();
  }

  showAuthorSearchPrompt(): void {
    if (!this.author.trim()) return;
    // 与“点数使用说明”相同的系统自定义对话框：表面材质由系统提供，API 26+ 即沉浸光感效果。
    this.authorSearchDialogBuilder = (): void => {
      this.authorSearchDialogContent();
    };
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.authorSearchDialogBuilder,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode)
    }).then((dialogId: number) => {
      this.authorSearchDialogId = dialogId;
    }).catch((error: Error) => {
      console.warn('显示作者检索确认失败:', error);
    });
  }

  closeAuthorSearchDialog(): void {
    if (this.authorSearchDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.authorSearchDialogId);
      this.authorSearchDialogId = -1;
    }
  }

  confirmAuthorSearch(): void {
    this.closeAuthorSearchDialog();
    const author = this.author.trim();
    if (!author) return;
    const nonce = AppStorage.get<number>('globalSearchPendingNonce') || 0;
    AppStorage.setOrCreate('globalSearchPendingKeyword', author);
    AppStorage.setOrCreate('globalSearchPendingNonce', nonce + 1);
    // 详情页可能叠在聚合结果页之上，直接回退到主页再切搜索Tab，保证发起搜索的页面可见。
    router.back({ url: 'pages/Index' });
  }

  showChangeSourcePrompt(): void {
    if (!this.bookUrl || !this.origin) {
      HdsFeedback.showToast('书籍信息不完整，暂时无法换源');
      return;
    }
    if (LocalBookService.isLocalBook(this.detailTargetBook())) {
      HdsFeedback.showToast('本地书籍无需换源');
      return;
    }
    this.changeSourceDialogBuilder = (): void => {
      this.changeSourceConfirmDialogContent();
    };
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.changeSourceDialogBuilder,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode)
    }).then((dialogId: number) => {
      this.changeSourceDialogId = dialogId;
    }).catch((error: Error) => {
      console.warn('显示换源确认失败:', error);
    });
  }

  closeChangeSourceDialog(): void {
    if (this.changeSourceDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.changeSourceDialogId);
      this.changeSourceDialogId = -1;
    }
  }

  detailTargetBook(): Book {
    const resolved = this.resolvedBookInfo;
    if (resolved) return resolved;
    return this.buildCurrentBook();
  }

  confirmChangeSource(): void {
    this.closeChangeSourceDialog();
    // 打开面板前固化目标书籍，避免面板打开期间详情信息加载完成导致目标被替换。
    this.changeSourceTarget = this.detailTargetBook();
    this.showChangeSourcePanel = true;
  }

  applySwitchedSource(switched: Book): void {
    const previousBookUrl = this.bookUrl;
    // 旧书源解析缓存全部作废，后续加入书架/阅读都会按新书源重新拉取。
    this.resolvedBookInfo = null;
    this.bookInfoPromise = null;
    this.hasLoadedBookInfo = false;
    this.syncStateFromBook(switched);
    if (this.pendingAddToShelfBookUrl && this.pendingAddToShelfBookUrl === previousBookUrl) {
      this.pendingAddToShelfBookUrl = switched.bookUrl;
    }
    this.totalChapterNum = switched.totalChapterNum > 0 ? switched.totalChapterNum : 0;
    this.checkShelf();
  }

  shouldPromptAddToShelfOnBack(): boolean {
    return this.promptAddToShelfOnBackFromResult && this.searchExplorePromptAddToShelfOnBack &&
      this.promptAddToShelfAfterRead && !this.isSaving && !this.showAddToShelfOnBackDialog &&
      !!this.bookUrl && this.bookUrl === this.pendingAddToShelfBookUrl;
  }

  showAddToShelfOnBackPrompt(): void {
    if (this.showAddToShelfOnBackDialog) return;
    this.showAddToShelfOnBackDialog = true;
    // 蒙层点击原本走“不加入”清理流程而非普通关闭，因此禁用 autoCancel，仅由按钮触发。
    this.addToShelfOnBackDialogSession.open(this.getUIContext(),
      (): void => {
        this.addToShelfOnBackDialogContent();
      }, {
        autoCancel: false,
        maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
        warnTag: '显示加入书架确认失败:'
      });
  }

  closeAddToShelfOnBackDialog(): void {
    this.showAddToShelfOnBackDialog = false;
    this.addToShelfOnBackDialogSession.close(this.getUIContext());
  }

  dismissAddToShelfOnBackPrompt(): void {
    this.closeAddToShelfOnBackDialog();
    this.removePendingReadBook().finally(() => {
      router.back();
    });
  }

  async removePendingReadBook(): Promise<void> {
    if (!this.pendingAddToShelfBookUrl) {
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const pendingBook = await db.getBook(this.pendingAddToShelfBookUrl);
      if (ReaderTtsFloatingSession.isPlayingBook(this.pendingAddToShelfBookUrl)) {
        // 不加入书架也接着放；临时书等停播后再删，播放面板和系统媒体控件才取得到封面。
        PendingTrialBookCleanup.deleteAfterPlayback(getContext(this), this.pendingAddToShelfBookUrl);
      } else if (SearchExplorePendingBook.isPendingAddToShelf(pendingBook)) {
        await db.deleteBook(this.pendingAddToShelfBookUrl, 'temporary_read_declined');
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }
    } catch (e) {
      console.error('移除临时阅读书籍失败:', e);
    }
    this.promptAddToShelfAfterRead = false;
    this.pendingAddToShelfBookUrl = '';
    this.isInShelf = false;
  }

  async keepPendingReadBookInShelf(): Promise<boolean> {
    if (!this.pendingAddToShelfBookUrl) {
      return await this.addToShelf();
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const pendingBook = await db.getBook(this.pendingAddToShelfBookUrl);
      if (pendingBook) {
        const pendingWasPending = SearchExplorePendingBook.isPendingAddToShelf(pendingBook);
        if (pendingWasPending) {
          const resolved = await this.resolveSameWorkBeforeShelf(pendingBook);
          if (resolved !== null) return resolved;
        }
        const pendingGroupName = pendingWasPending ? await NewBookGroupStore.apply(getContext(this), pendingBook) : '';
        SearchExplorePendingBook.clearPendingAddToShelf(pendingBook);
        await BookMarkService.carryTagsToShelfBook(pendingBook);
        await db.updateBook(pendingBook, true, 'temporary_read_kept');
        this.syncStateFromBook(pendingBook);
        this.isInShelf = true;
        this.promptAddToShelfAfterRead = false;
        this.pendingAddToShelfBookUrl = '';
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        HdsFeedback.showToast(NewBookGroup.addedToast(pendingGroupName));
        return true;
      }
    } catch (e) {
      console.error('加入书架失败:', e);
      HdsFeedback.showToast('加入书架失败');
      return false;
    }
    return await this.addToShelf();
  }

  async confirmAddToShelfOnBack(): Promise<void> {
    this.closeAddToShelfOnBackDialog();
    const ok = await this.keepPendingReadBookInShelf();
    if (ok) {
      router.back();
    }
  }

  async prepareBookForReading(): Promise<boolean> {
    if (!this.bookUrl) {
      HdsFeedback.showToast('书籍地址为空');
      return false;
    }

    this.isSaving = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const requestKey = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
      const existing = await db.getBook(this.bookUrl) || await this.findShelfBookByKey(requestKey, true);
      if (existing) {
        let bookChanged = false;
        const knownCategory = BookTypeSupport.mediaCategoryOf(this.detailTypeProbe());
        const inferredType = this.bookType || BookTypeSupport.typeFromVariable(this.bookVariable);
        if (knownCategory === BookTypeSupport.CATEGORY_NOVEL && inferredType && existing.type !== inferredType) {
          existing.type = inferredType;
          bookChanged = true;
        }
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
          bookChanged = true;
        }
        if (this.mergeResolvedDetailIntoBook(existing)) {
          bookChanged = true;
        }
        const typeBefore = existing.type;
        const variableBefore = existing.variable;
        this.ensureMediaCategory(existing, knownCategory);
        if (existing.type !== typeBefore || existing.variable !== variableBefore) {
          bookChanged = true;
        }
        if (bookChanged) {
          await db.updateBook(existing, true, 'prepare_read_update_existing');
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
        this.syncStateFromBook(existing);
        if (SearchExplorePendingBook.isPendingAddToShelf(existing)) {
          PendingTrialBookCleanup.cancel(existing.bookUrl);
          this.isInShelf = false;
          this.promptAddToShelfAfterRead = this.promptAddToShelfOnBackFromResult;
          this.pendingAddToShelfBookUrl = existing.bookUrl;
        } else {
          this.isInShelf = true;
          this.promptAddToShelfAfterRead = false;
          this.pendingAddToShelfBookUrl = '';
        }
        return true;
      }

      const book = await this.buildBookForShelf();
      const resolvedExisting = await this.findShelfBookByKey(BookIdentity.keyOfBook(book), true);
      if (resolvedExisting) {
        const resolvedTypeBefore = resolvedExisting.type;
        const resolvedVariableBefore = resolvedExisting.variable;
        const resolvedMerged = this.mergeResolvedDetailIntoBook(resolvedExisting);
        this.ensureMediaCategory(resolvedExisting, BookTypeSupport.mediaCategoryOf(book));
        if (resolvedMerged || resolvedExisting.type !== resolvedTypeBefore ||
          resolvedExisting.variable !== resolvedVariableBefore) {
          await db.updateBook(resolvedExisting, true, 'prepare_read_update_resolved');
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
        this.syncStateFromBook(resolvedExisting);
        if (SearchExplorePendingBook.isPendingAddToShelf(resolvedExisting)) {
          PendingTrialBookCleanup.cancel(resolvedExisting.bookUrl);
          this.isInShelf = false;
          this.promptAddToShelfAfterRead = this.promptAddToShelfOnBackFromResult;
          this.pendingAddToShelfBookUrl = resolvedExisting.bookUrl;
        } else {
          this.isInShelf = true;
          this.promptAddToShelfAfterRead = false;
          this.pendingAddToShelfBookUrl = '';
        }
        return true;
      }
      SearchExplorePendingBook.markPendingAddToShelf(book);
      await db.insertBook(book, 'temporary_read_insert');
      this.syncStateFromBook(book);
      this.isInShelf = false;
      this.promptAddToShelfAfterRead = this.promptAddToShelfOnBackFromResult;
      this.pendingAddToShelfBookUrl = book.bookUrl;
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      return true;
    } catch (e) {
      console.error('准备阅读失败:', e);
      HdsFeedback.showToast('打开阅读失败');
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  private mergeResolvedDetailIntoBook(book: Book): boolean {
    let changed = false;
    const kind = BookFieldSanitizer.prefer(this.kind, book.kind);
    const status = BookFieldSanitizer.prefer(this.status, book.status);
    const intro = BookFieldSanitizer.prefer(this.intro, book.intro);
    const latestChapterTitle = BookFieldSanitizer.prefer(this.latestChapterTitle, book.latestChapterTitle);
    const wordCount = BookFieldSanitizer.prefer(this.wordCount, book.wordCount);
    const updateTime = BookFieldSanitizer.prefer(this.updateTime, book.updateTime);
    if (kind !== book.kind) {
      book.kind = kind;
      changed = true;
    }
    if (status !== book.status) {
      book.status = status;
      changed = true;
    }
    if (intro !== book.intro) {
      book.intro = intro;
      changed = true;
    }
    if (latestChapterTitle !== book.latestChapterTitle) {
      book.latestChapterTitle = latestChapterTitle;
      changed = true;
    }
    if (wordCount !== book.wordCount) {
      book.wordCount = wordCount;
      changed = true;
    }
    if (updateTime !== book.updateTime) {
      book.updateTime = updateTime;
      changed = true;
    }
    if (this.tocUrl && this.tocUrl !== book.tocUrl) {
      book.tocUrl = this.tocUrl;
      changed = true;
    }
    if (this.bookVariable && this.bookVariable !== book.variable) {
      book.variable = this.bookVariable;
      changed = true;
    }
    return changed;
  }

  async buildBookForShelf(): Promise<Book> {
    const book = new Book();
    book.bookUrl = this.bookUrl;
    book.tocUrl = this.tocUrl;
    book.origin = this.origin;
    book.originName = this.originName;
    book.name = this.name;
    book.author = this.author;
    book.kind = BookFieldSanitizer.clean(this.kind);
    book.status = BookFieldSanitizer.clean(this.status);
    book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
    book.intro = BookFieldSanitizer.clean(this.intro);
    book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.clean(this.wordCount);
    book.group = NewBookGroup.UNGROUPED;
    book.type = this.bookType;
    book.variable = this.bookVariable;
    BookTypeSupport.applyBookType(book);
    book.canUpdate = true;
    book.lastCheckTime = Date.now();
    book.latestChapterTime = Date.now();
    const fallbackCoverUrl = book.coverUrl;
    const fullBook = await this.resolveBookInfo();
    if (fullBook) {
      book.bookUrl = fullBook.bookUrl || book.bookUrl;
      book.tocUrl = fullBook.tocUrl || book.tocUrl;
      book.name = fullBook.name || book.name;
      book.author = fullBook.author || book.author;
      book.kind = BookFieldSanitizer.prefer(fullBook.kind, book.kind);
      book.status = BookFieldSanitizer.prefer(fullBook.status, book.status);
      book.coverUrl = CoverUrlNormalizer.prefer(fallbackCoverUrl, fullBook.coverUrl || book.coverUrl);
      book.intro = BookFieldSanitizer.prefer(fullBook.intro, book.intro);
      book.latestChapterTitle = BookFieldSanitizer.prefer(fullBook.latestChapterTitle, book.latestChapterTitle);
      book.updateTime = BookFieldSanitizer.prefer(fullBook.updateTime, book.updateTime);
      book.wordCount = BookFieldSanitizer.prefer(fullBook.wordCount, book.wordCount);
      book.variable = fullBook.variable || book.variable;
      book.type = fullBook.type || book.type;
    }
    // 类型以书源详情为准；是有声/漫画/视频时在 variable 里写入 tab，阅读页据此转到听书/漫画/播放页。
    this.ensureMediaCategory(book, BookTypeSupport.mediaCategoryOf(book));
    return book;
  }

  /**
   * 让书籍记录与已知类型一致：有声/漫画补类型标记位，并在 variable 里写入 tab
   * （阅读页按 variable 的 tab 优先定类型）；视频在 variable 里写入 tab=video。小说不做处理。
   */
  private ensureMediaCategory(target: Book, category: string): void {
    let tab = '';
    let bit = 0;
    if (category === BookTypeSupport.CATEGORY_AUDIO) {
      tab = 'audio';
      bit = BookTypeSupport.AUDIO;
    } else if (category === BookTypeSupport.CATEGORY_COMIC) {
      tab = 'comic';
      bit = BookTypeSupport.IMAGE;
    } else if (category === BookTypeSupport.CATEGORY_VIDEO) {
      tab = 'video';
    }
    if (!tab) return;
    if (bit) {
      target.type = (target.type & ~(BookTypeSupport.TEXT | BookTypeSupport.AUDIO | BookTypeSupport.IMAGE)) | bit;
    }
    if (BookTypeSupport.typeFromVariable(target.variable) !== bit || category === BookTypeSupport.CATEGORY_VIDEO) {
      const merged = SearchBookDetailPage.mergeVariableTab(target.variable, tab);
      if (merged) target.variable = merged;
    }
  }

  /** 书已在书架时书源行下面的分组胶囊，点开“放进分组”面板改分组。 */
  @Builder
  shelfGroupChip() {
    Row({ space: AppSpacing.XXS }) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(12)
        .fontColor([this.accentColor()])
      Text(this.shelfGroupName || '未分组')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.accentColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(11)
        .fontColor([this.accentColor()])
    }
    .height(24)
    .padding({ left: AppSpacing.SM, right: AppSpacing.SM })
    .borderRadius(12)
    .backgroundColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
    .alignItems(VerticalAlign.Center)
    .margin({ top: AppSpacing.SM })
    .accessibilityText(`书架分组：${this.shelfGroupName || '未分组'}，点按更改`)
    .onClick(() => {
      this.openShelfGroupSheet();
    })
  }

  /** 提示条宽度：材质底板要具体数值，借阅读按钮那一行量到的整页宽度，左右各让出页边距。 */
  private groupNudgeWidth(): number {
    return Math.max(0, this.readButtonBarWidth - AppSpacing.XL * 2);
  }

  /** 和返回、阅读按钮同一种沉浸光感胶囊底板，内容叠在上面。 */
  @Builder
  shelfGroupNudge() {
    ImmersiveMaterialSurface({
      surfaceWidth: this.groupNudgeWidth(),
      surfaceHeight: 48,
      darkMode: this.appDarkMode,
      fallbackColor: this.cardColor(),
      glowColor: `#40${this.accentColor().substring(1)}`
    }) {
      this.shelfGroupNudgeContent()
    }
  }

  @Builder
  shelfGroupNudgeContent() {
    Row({ space: AppSpacing.MD }) {
      Text(this.groupNudgeText)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(this.shelfGroupName ? '换分组' : '放进分组')
        .fontSize(AppFontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.onAccentColor())
        .height(32)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(16)
        .backgroundColor(this.buttonColor())
        .onClick(() => {
          this.hideGroupNudge();
          this.openShelfGroupSheet();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.SM })
    .alignItems(VerticalAlign.Center)
  }

  /** 和同页的标记、目录面板同一种悬浮沉浸光感面板：四角圆、去掉系统默认底色和投影，由材质自己画。 */
  shelfGroupSheetOptions(): SheetOptions {
    const options: SheetOptions = {
      height: SheetSize.FIT_CONTENT,
      keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      blurStyle: BlurStyle.NONE,
      borderWidth: 0,
      radius: { topLeft: 28, topRight: 28, bottomLeft: 28, bottomRight: 28 },
      shadow: { radius: 0, color: Color.Transparent },
      onDisappear: (): void => {
        this.showGroupSheet = false;
        this.newShelfGroupEditing = false;
      }
    };
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, options,
      this.appDarkMode, this.accentColor());
  }

  /** 和书架“移动到分组”同样的列表；新建分组就地输入，建好直接放进去。 */
  @Builder
  shelfGroupSheet() {
    Column({ space: AppSpacing.SM }) {
      Text('放进分组')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .height(32)
        .textAlign(TextAlign.Center)
      Scroll() {
        Column({ space: AppSpacing.XS }) {
          this.shelfGroupSheetItem('未分组', 0)
          ForEach(this.shelfGroupOptions, (group: BookGroup) => {
            this.shelfGroupSheetItem(group.groupName, group.groupId)
          }, (group: BookGroup) => `detail_group_${group.groupId}`)
          if (this.newShelfGroupEditing) {
            Row({ space: AppSpacing.SM }) {
              TextInput({ placeholder: '输入分组名称', text: this.newShelfGroupName })
                .layoutWeight(1)
                .height(38)
                .backgroundColor(this.inputColor())
                .fontColor(this.primaryTextColor())
                .borderRadius(ThemeRuntime.mediumRadius())
                .defaultFocus(true)
                .onChange((value: string) => {
                  this.newShelfGroupName = value;
                })
                .onSubmit(() => {
                  this.createShelfGroupAndAssign();
                })
              Button('新建并放入', { type: ButtonType.Normal })
                .height(38)
                .fontSize(AppFontSize.BODY)
                .borderRadius(ThemeRuntime.buttonRadius())
                .backgroundColor(this.buttonColor())
                .fontColor(ThemeRuntime.onAccentColor())
                .enabled(!!this.newShelfGroupName.trim())
                .onClick(() => {
                  this.createShelfGroupAndAssign();
                })
            }
            .width('100%')
          } else {
            Row({ space: AppSpacing.SM }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(16)
                .fontColor([this.accentColor()])
              Text('新建分组')
                .fontSize(AppFontSize.BODY)
                .fontColor(this.accentColor())
            }
            .width('100%')
            .height(38)
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
            .borderRadius(ThemeRuntime.mediumRadius())
            .backgroundColor(this.inputColor())
            .accessibilityText('新建分组并放入')
            .onClick(() => {
              this.newShelfGroupName = '';
              this.newShelfGroupEditing = true;
            })
          }
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .constraintSize({ maxHeight: 360 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: Math.max(this.navBarHeight, 12) + 12 })
  }

  @Builder
  shelfGroupSheetItem(label: string, groupId: number) {
    Row({ space: AppSpacing.SM }) {
      Text(label)
        .fontSize(AppFontSize.BODY)
        .fontColor(groupId === this.currentShelfGroupId() ? this.accentColor() : this.primaryTextColor())
        .fontWeight(groupId === this.currentShelfGroupId() ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (groupId === this.currentShelfGroupId()) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(38)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(groupId === this.currentShelfGroupId() ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) :
      this.inputColor())
    .accessibilitySelected(groupId === this.currentShelfGroupId())
    .onClick(() => {
      this.assignShelfGroup(groupId);
    })
  }

  /** 面板里该打勾的分组：分组已被删掉（找不到名字）时按未分组算。 */
  private currentShelfGroupId(): number {
    return this.shelfGroupId > 0 && this.shelfGroupName ? this.shelfGroupId : 0;
  }

  private async loadShelfGroupOptions(): Promise<BookGroup[]> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    const groups = await db.getCustomBookGroups();
    this.shelfGroupOptions = groups;
    return groups;
  }

  private async refreshShelfGroupName(): Promise<void> {
    const groupId = this.shelfGroupId;
    if (groupId <= 0) {
      this.shelfGroupName = '';
      return;
    }
    try {
      const groups = await this.loadShelfGroupOptions();
      if (groupId !== this.shelfGroupId) return;
      this.shelfGroupName = groups.find((group: BookGroup): boolean => group.groupId === groupId)?.groupName ?? '';
    } catch (e) {
      console.warn('读取书架分组失败:', e);
    }
  }

  openShelfGroupSheet(): void {
    if (!this.isInShelf || !this.bookUrl) return;
    this.newShelfGroupEditing = false;
    this.newShelfGroupName = '';
    this.loadShelfGroupOptions().then((): void => {
      this.showGroupSheet = true;
    }).catch((e: Error): void => {
      console.warn('读取书架分组失败:', e);
      HdsFeedback.showToast('读取分组失败');
    });
  }

  async assignShelfGroup(groupId: number): Promise<void> {
    this.showGroupSheet = false;
    if (!this.bookUrl || !this.isInShelf) return;
    const target = groupId > 0 ? groupId : 0;
    // 选了就记成“上次选的分组”，包括选回未分组。
    NewBookGroupStore.saveLastGroupId(getContext(this), target).catch((e: Error): void => {
      console.warn('保存上次选的分组失败:', e);
    });
    if (target === this.currentShelfGroupId()) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.updateBooksGroup([this.bookUrl], target);
      const groupName = target > 0 ?
        (this.shelfGroupOptions.find((group: BookGroup): boolean => group.groupId === target)?.groupName ?? '') : '';
      this.shelfGroupId = target;
      this.shelfGroupName = groupName;
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast(`已放进“${groupName || '未分组'}”`);
    } catch (e) {
      console.error('设置书架分组失败:', e);
      HdsFeedback.showToast('设置分组失败');
    }
  }

  async createShelfGroupAndAssign(): Promise<void> {
    const name = this.newShelfGroupName.trim();
    if (!name) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const group = await db.addBookGroup(name);
      if (!group) {
        HdsFeedback.showToast('已有同名分组');
        return;
      }
      this.shelfGroupOptions = [...this.shelfGroupOptions, group];
      this.newShelfGroupEditing = false;
      this.newShelfGroupName = '';
      await this.assignShelfGroup(group.groupId);
    } catch (e) {
      console.error('新建书架分组失败:', e);
      HdsFeedback.showToast('新建分组失败');
    }
  }

  /** 加入后的反馈：顶栏书架钮出提示条，其余入口按 toastOtherwise 决定是否弹提示。 */
  private announceAddedToShelf(groupName: string, fromHeader: boolean, toastOtherwise: boolean): void {
    if (fromHeader) {
      this.showGroupNudge(groupName);
    } else if (toastOtherwise) {
      HdsFeedback.showToast(NewBookGroup.addedToast(groupName));
    }
  }

  private showGroupNudge(groupName: string): void {
    this.clearGroupNudgeTimer();
    this.groupNudgeText = NewBookGroup.addedToast(groupName);
    this.groupNudgeVisible = true;
    this.groupNudgeTimer = setTimeout((): void => {
      this.groupNudgeTimer = -1;
      this.hideGroupNudge();
    }, SearchBookDetailPage.GROUP_NUDGE_MS);
  }

  private hideGroupNudge(): void {
    this.clearGroupNudgeTimer();
    this.groupNudgeVisible = false;
  }

  private clearGroupNudgeTimer(): void {
    if (this.groupNudgeTimer >= 0) {
      clearTimeout(this.groupNudgeTimer);
      this.groupNudgeTimer = -1;
    }
  }

  @Builder
  addToShelfOnBackDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text('加入书架')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      Text(`是否将《${this.name || '这本书'}》加入书架？`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')

      Row({ space: AppSpacing.MD }) {
        Button('不加入')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.dismissAddToShelfOnBackPrompt();
          })

        Button('加入书架')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.confirmAddToShelfOnBack();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .padding(AppSpacing.XXXL)
  }

  @Builder
  authorSearchDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text('作者检索')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      Text(`是否以作者“${this.author}”为关键词发起搜索？`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.closeAuthorSearchDialog();
          })

        Button('搜索')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.confirmAuthorSearch();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .padding(AppSpacing.XXXL)
  }

  @Builder
  changeSourceConfirmDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text('换源')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      Text(`是否为《${this.name || '这本书'}》搜索可切换的书源？`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.closeChangeSourceDialog();
          })

        Button('换源')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.confirmChangeSource();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .padding(AppSpacing.XXXL)
  }

  async findShelfBookByKey(bookKey: string, includePending: boolean = false): Promise<Book | null> {
    return SearchBookShelfHelper.findShelfBookByKey(bookKey, includePending);
  }

  /**
   * The shelf keeps one online copy per work. When another entry of this work is already there,
   * offer to switch it to this source instead of adding a second copy. Returns null when there is
   * no such book, otherwise whether this book is now on the shelf.
   */
  private async resolveSameWorkBeforeShelf(book: Book): Promise<boolean | null> {
    const sameWork = await SearchBookShelfHelper.findSameWorkShelfBook(book, book.bookUrl);
    if (!sameWork) return null;
    const switched = await ShelfWorkDuplicatePrompt.offerSwitch(getContext(this), this.getUIContext(), sameWork,
      ShelfWorkDuplicatePrompt.candidateOf(book));
    if (!switched) return false;
    this.resolvedBookInfo = null;
    this.bookInfoPromise = null;
    this.hasLoadedBookInfo = false;
    this.syncStateFromBook(switched);
    this.isInShelf = true;
    this.promptAddToShelfAfterRead = false;
    this.pendingAddToShelfBookUrl = '';
    this.shelfCheckKey = '';
    this.shelfCheckVersion = -1;
    return true;
  }

  syncStateFromBook(book: Book): void {
    this.bookUrl = book.bookUrl || this.bookUrl;
    this.tocUrl = book.tocUrl || this.tocUrl;
    this.origin = book.origin || this.origin;
    this.originName = book.originName || this.originName;
    this.name = book.name || this.name;
    this.author = book.author || this.author;
    this.kind = book.kind || this.kind;
    this.status = book.status || this.status;
    this.coverUrl = CoverUrlNormalizer.prefer(book.coverUrl, this.coverUrl);
    this.intro = book.intro || this.intro;
    this.latestChapterTitle = book.latestChapterTitle || this.latestChapterTitle;
    this.wordCount = book.wordCount || this.wordCount;
    this.updateTime = book.updateTime || this.updateTime;
    this.bookType = book.type || this.bookType;
    this.bookVariable = book.variable || this.bookVariable;
    this.shelfGroupId = book.group > 0 ? book.group : 0;
    this.refreshShelfGroupName();
    this.bookInfoRenderVersion++;
    // 书籍信息补齐后作者可能才有，作品键随之变化。
    this.loadBookMark();
    this.loadReadStats();
  }

  private onBookMarkRevisionChanged(): void {
    this.loadBookMark();
  }

  private markKey(): string {
    return this.name ? BookMarkService.keyOf(this.buildCurrentBook()) : '';
  }

  private async loadBookMark(): Promise<void> {
    const version = ++this.markLoadVersion;
    const key = this.markKey();
    if (!key) {
      this.bookMark = null;
      return;
    }
    try {
      await AppDatabase.getInstance().initWithContext(getContext(this));
      const mark = await AppDatabase.getInstance().getBookMark(key);
      if (version === this.markLoadVersion) this.bookMark = mark;
      const tags = await BookMarkService.knownTags();
      if (version === this.markLoadVersion) this.markQuickTags = tags;
      // 书架上这本还没有标签时把标记的标签补过去（打通之前保存的、被旧快照写回空的）。
      if (mark && mark.categories.length > 0) await BookMarkService.fillMissingShelfTags(mark);
    } catch (error) {
      console.warn('读取书籍标记失败:', error);
    }
  }

  private rateFromDetail(rating: number): void {
    this.quickSaveMark((draft: BookMark): string => {
      draft.rating = rating;
      return rating > 0 ? `已标记 · ${BookMarkRules.ratingText(rating)} 星` : '已清除评分';
    });
  }

  /** 再点已选的状态就取消。 */
  private statusFromDetail(status: number): void {
    this.quickSaveMark((draft: BookMark): string => {
      draft.status = draft.status === status ? BookMarkStatus.NONE : status;
      return draft.status === BookMarkStatus.NONE ? '已清除阅读状态' : `已标为${BookMarkStatus.label(draft.status)}`;
    });
  }

  private toggleTagFromDetail(name: string): void {
    this.quickSaveMark((draft: BookMark): string => {
      if (draft.categories.includes(name)) {
        draft.categories = draft.categories.filter((tag: string): boolean => tag !== name);
        return `已移除标签 ${name}`;
      }
      if (draft.categories.length >= BookMarkRules.MAX_CATEGORIES) {
        return `最多 ${BookMarkRules.MAX_CATEGORIES} 个标签`;
      }
      draft.categories = [...draft.categories, name];
      return `已加标签 ${name}`;
    });
  }

  /**
   * 页签里的快捷保存：在最新的标记上改一项再存，全清空就删掉标记。
   * 排队执行，连点几下也不会拿旧标记覆盖刚存的那次；刚标成读过时照常出票。
   */
  private quickSaveMark(edit: (draft: BookMark) => string): void {
    if (!this.markKey()) return;
    this.markSaveChain = this.markSaveChain.then(async (): Promise<void> => {
      try {
        ++this.markLoadVersion;
        const before = this.bookMark;
        const wasRead = before !== null && before.status === BookMarkStatus.READ;
        const draft = await BookMarkService.prepareDraft(this.buildCurrentBook(), before);
        const message = edit(draft);
        const saved = await BookMarkService.save(draft);
        this.bookMark = saved;
        if (saved && !wasRead && saved.status === BookMarkStatus.READ) {
          await this.issueReadTicket(saved);
        } else {
          HdsFeedback.showToast(saved || before === null ? message : '已删除标记');
        }
      } catch (error) {
        console.error('保存书籍标记失败:', error);
        HdsFeedback.showToast('保存失败，请重试');
      }
    });
  }

  private async openMarkSheet(focusReview: boolean = false): Promise<void> {
    if (!this.markKey() || this.showMarkSheet) return;
    this.markSheetFocusReview = focusReview;
    try {
      this.markCategories = await BookMarkService.knownTags();
      this.markDraft = await BookMarkService.prepareDraft(this.buildCurrentBook(), this.bookMark);
    } catch (error) {
      console.warn('准备标记面板失败:', error);
      return;
    }
    this.showMarkSheet = true;
  }

  private async saveMarkFromSheet(draft: BookMark): Promise<void> {
    try {
      ++this.markLoadVersion;
      const existed = this.bookMark !== null;
      const wasRead = this.bookMark !== null && this.bookMark.status === BookMarkStatus.READ;
      const saved = await BookMarkService.save(draft);
      this.bookMark = saved;
      if (saved && !wasRead && saved.status === BookMarkStatus.READ) {
        await this.issueReadTicket(saved);
      } else if (saved) {
        HdsFeedback.showToast('标记已保存');
      } else if (existed) {
        HdsFeedback.showToast('已删除标记');
      }
    } catch (error) {
      console.error('保存书籍标记失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    }
  }

  /** 刚标成读过：出票动画开着就出票，关着只提示收进了票夹。 */
  private async issueReadTicket(mark: BookMark): Promise<void> {
    try {
      const context = getContext(this);
      await TicketAlbumStore.load(context);
      const ticket = await ReadingTicketLoader.loadOne(context, mark);
      if (!ticket) {
        HdsFeedback.showToast('标记已保存');
        return;
      }
      if (TicketAlbumStore.issueAnimation()) {
        this.issueTicketStyle = TicketAlbumStore.currentStyle();
        this.issueTicket = ticket;
      } else {
        HdsFeedback.showToast(ticket.number > 0 ? `标记已保存 · 第 ${ticket.number} 张票已收进票夹` : '标记已保存');
      }
    } catch (error) {
      console.warn('出票失败:', error);
      HdsFeedback.showToast('标记已保存');
    }
  }

  private async deleteMarkFromSheet(): Promise<void> {
    const key = this.markDraft.workKey;
    try {
      ++this.markLoadVersion;
      await BookMarkService.remove(key);
      this.bookMark = null;
      HdsFeedback.showToast('已删除标记');
    } catch (error) {
      console.error('删除书籍标记失败:', error);
      HdsFeedback.showToast('删除失败，请重试');
    }
  }

  /** 在 variable 里补上 tab，保留其余字段（目录等规则可能依赖它们）；不是 JSON 对象时返回空串。 */
  private static mergeVariableTab(variable: string, tab: string): string {
    try {
      const record = (variable ? JSON.parse(variable) : {}) as Record<string, Object>;
      if (record === null || typeof record !== 'object' || Array.isArray(record)) return '';
      record['tab'] = tab;
      return JSON.stringify(record);
    } catch (_) {
      return '';
    }
  }

  detailTypeProbe(): Book {
    const book = new Book();
    book.origin = this.origin;
    book.originName = this.originName;
    book.kind = this.kind;
    book.type = this.bookType;
    book.variable = this.bookVariable;
    return book;
  }

  /**
   * The catalog card shows a chapter count that only exists after the catalog has been fetched at
   * least once. Prefer the stored column and fall back to counting the cached chapter rows.
   */
  private async refreshChapterCount(): Promise<void> {
    if (!this.bookUrl) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const book = await db.getBook(this.bookUrl);
      // 阅读页存进度不一定发 shelfUpdateTime，checkShelf 可能被跳过；每次回到详情页都在这里重读一次。
      if (book) this.hasReadProgress = Book.hasStartedReading(book);
      const stored = book ? book.totalChapterNum : 0;
      this.totalChapterNum = stored > 0 ? stored : await db.getBookChapterCount(this.bookUrl);
    } catch (e) {
      console.warn('读取章节总数失败:', e);
    }
  }

  openChapterList(): void {
    if (!this.bookUrl || !this.origin) {
      HdsFeedback.showToast('书籍信息不完整，暂时无法查看目录');
      return;
    }
    this.showCatalogSheet = true;
  }

  /**
   * 目录面板里点中某一章。先走与"开始阅读"相同的入库流程（未上架时写临时阅读书并保留
   * 返回时的加入书架提示），再把进度指到该章。
   */
  async openChapterFromCatalog(chapter: BookChapter): Promise<void> {
    if (this.openingCatalogChapter || chapter.index < 0) return;
    this.openingCatalogChapter = true;
    try {
      const ok = await this.prepareBookForReading();
      if (!ok) return;
      const db = AppDatabase.getInstance();
      const book = await db.getBook(this.bookUrl);
      if (!book) {
        HdsFeedback.showToast('打开章节失败');
        return;
      }
      // The reader derives its opening chapter from durChapterIndex alone (see
      // ReadBookEngine.openBookFresh / applyLatestReadingProgress). durChapterPos must be reset
      // too: savedReaderProgressOffset only matches on chapter, so a stale page would land
      // somewhere inside the target chapter.
      book.durChapterIndex = chapter.index;
      book.durChapterPos = 0;
      book.durChapterTitle = chapter.title;
      await db.updateBook(book, true, 'open_chapter_from_catalog_sheet');
      this.showCatalogSheet = false;
      if (BookTypeSupport.isVideo(book)) {
        // 视频类书籍没有阅读形态，点哪一集就直接播放哪一集。
        await VideoBookPlayer.open(book.bookUrl, chapter.index);
        return;
      }
      await router.pushUrl({
        url: 'pages/ReadBook',
        params: { bookUrl: book.bookUrl }
      });
    } catch (e) {
      console.error('打开章节失败:', e);
      HdsFeedback.showToast('打开章节失败');
    } finally {
      this.openingCatalogChapter = false;
    }
  }

  async startRead(): Promise<void> {
    if (this.openingReader || this.isSaving || this.openingCatalogChapter) return;
    this.openingReader = true;
    try {
      const ok = await this.prepareBookForReading();
      if (!ok) return;

      if (BookTypeSupport.isVideo(this.detailTypeProbe())) {
        await this.startWatch();
        return;
      }

      // 从目录进入详情后，继续阅读同一本书直接回到原阅读页，保留分页和当前位置。
      if (this.readerBookUrl && this.readerBookUrl === this.bookUrl &&
        !BookTypeSupport.isAudio(this.detailTypeProbe())) {
        router.back();
        return;
      }

      await router.pushUrl({
        url: BookTypeSupport.isAudio(this.detailTypeProbe()) ? 'pages/AudioBook' : 'pages/ReadBook',
        params: { bookUrl: this.bookUrl }
      });
    } catch (error) {
      console.error('打开阅读失败:', error);
      HdsFeedback.showToast('打开阅读失败');
    } finally {
      this.openingReader = false;
    }
  }

  /** 视频类书籍：进入播放页，接着上次看到的那一集；选集由播放页自己加载。 */
  async startWatch(): Promise<void> {
    try {
      await VideoBookPlayer.open(this.bookUrl);
    } catch (e) {
      console.warn('打开播放页失败:', e);
      HdsFeedback.showToast('打开播放页失败');
    }
  }

  triggerAutoStartRead(): void {
    if (!this.autoStartRead || this.autoStartReadTriggered || !this.bookUrl) return;
    this.autoStartReadTriggered = true;
    // Let the detail page mount before preparing the transient reader record and routing to ReadBook.
    setTimeout((): void => {
      this.startRead();
    }, 0);
  }

  getTags(): string[] {
    return BookDisplayHelper.splitTags(this.kind, this.status);
  }

  /** 字数、更新时间这类中性信息标签：同样的沉浸光感胶囊，用输入框底色染色。 */
  neutralTagModifier(): GlassTagModifier {
    return new GlassTagModifier(this.appDarkMode);
  }

  @Builder
  tagChip(tag: string, index: number) {
    Text(tag)
      .fontSize(AppFontSize.BODY)
      .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
      .attributeModifier(BookDisplayHelper.getGlassTagModifier(index, this.appDarkMode))
      .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
  }

  @Builder
  coverView() {
    // 尺寸跟随外层共享元素：返回列表时飞回去的是这一层，写死宽高会以详情页大小飞到列表再突然缩小。
    BookCover({
      bookUrl: this.bookUrl, origin: this.origin, coverUrl: this.coverUrl, name: this.name, author: this.author,
      useBookshelfCover: this.searchExploreUseBookshelfCoverGallery,
      placeholderColor: this.accentColor(), cornerRadius: 8,
      onReadyCover: (url: ResourceStr): void => { this.readyCoverUrl = url; }
    })
      .width('100%')
      .height('100%')
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
