import { SharedElementMotion } from '../../utils/SharedElementMotion';
import { ShelfCoverLocator } from '../../utils/ShelfCoverLocator';
import { PdfPagePosition } from '../../core/book/pdf/PdfModels';
import {
  SHELF_COVER_OPEN_DURATION, SHELF_COVER_OPEN_START_CAP, SHELF_BOOK_MOTION_UNTIL_KEY, SHELF_BOOK_MOTION_SETTLE,
  SHELF_OPENING_BACKDROP_KEY, SHELF_OPENING_COVER_KEY, SHELF_OPENING_PAGE_SNAPSHOT_KEY, ShelfOpeningCover,
  ShelfOpeningIdleStarter
} from '../reader/ReaderShelfCoverOpening';
import { ReaderOpenSnapshot, ReaderOpenSnapshotStore } from '../../core/reader/ReaderOpenSnapshotStore';
import { SharedElementBounds } from '../../utils/SharedElementBounds';
import { BookshelfCoverBadges } from '../BookshelfCoverBadges';
import { BookshelfCoverBadgeSettings } from '../../utils/BookshelfCoverBadgeSettings';
import { componentUtils, curves, FrameCallback, router, window } from '@kit.ArkUI';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import deviceInfo from '@ohos.deviceInfo';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { Book, BookChapter, BookGroup, SearchBook, BookTypeSupport, sleepMs } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { SearchCoordinator, SearchProgress } from '../../core/book/SearchCoordinator';
import { ReadBookEngine } from '../../core/book/ReadBookEngine';
import { AudioOfflineStore } from '../../core/book/AudioOfflineStore';
import { ReaderCacheBudgetPolicy } from '../../core/book/ReaderCacheBudgetPolicy';
import { AudioOfflineDownloadPrompt } from '../../utils/AudioOfflineDownloadPrompt';
import { ImmersiveBackButton } from '../../components/ImmersiveBackButton';
import { ImmersiveMaterialSurface } from '../../components/ImmersiveMaterialSurface';
import { ImmersiveHeaderAction } from '../../components/ImmersiveHeaderAction';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { CollapsingHeader } from '../../utils/CollapsingHeader';
import { HeaderBackdrop } from '../common/HeaderBackdrop';
import { HomeThemeBackdrop } from './HomeThemeBackdrop';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { BookDisplayHelper } from '../../utils/BookDisplayHelper';
import { BookTileLayout } from '../../utils/BookTileLayout';
import { BookCoverCache } from '../../utils/BookCoverCache';
import { CoverGallerySettings } from '../../utils/CoverGallerySettings';
import { BookshelfDisplaySettingsStore } from '../../utils/BookshelfDisplaySettingsStore';
import { BookshelfStateStore } from '../../utils/BookshelfStateStore';
import { SearchExplorePendingBook } from '../../utils/SearchExplorePendingBook';
import { BookshelfSortHelper } from '../../utils/BookshelfSortHelper';
import { RecentReadCarousel } from './RecentReadCarousel';
import { ShelfReadingNoteCard } from './ShelfReadingNoteCard';
import { CategorySwipePager } from './CategorySwipePager';
import { ShelfCategoryMaterial } from './ShelfCategoryMaterial';
import { SearchExploreSettingsStore } from '../../utils/SearchExploreSettingsStore';
import { AppThemeSettingsStore } from '../../utils/AppThemeSettingsStore';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { ThemeBookCoverSettings } from '../../utils/ThemeBookCoverSettings';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { LocalBookService } from '../../core/book/LocalBookService';
import { BookChangeSourceDialog } from '../../components/BookChangeSourceDialog';
import { SystemDialogSession } from '../../utils/SystemDialogSession';
import { ReaderOpenTrace } from '../../utils/ReaderOpenTrace';
import { FullTextCacheCancelCoordinator, FullTextCacheCancelSignal } from '../../utils/FullTextCacheCancelCoordinator';
import { ShelfCategoryPage, ShelfTileSortEntry, ShelfBookDataSource, ShelfTileEntryDataSource } from '../../core/book/ShelfDataSources';
import { PrivateShelfStore } from '../../utils/PrivateShelfStore';
import { BiometricAuth, BiometricAuthOutcome } from '../../utils/BiometricAuth';
import { RecentReadCardUpdater } from '../../utils/RecentReadCardUpdater';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { CloudAutoSync } from '../../account/CloudAutoSync';
import { CloudDownloadQueue } from '../../account/CloudDownloadQueue';
import { PopupMenuAction } from '../common/PopupMenuAction';

const SHELF_FULL_TEXT_CACHE_NOTIFICATION_INTERVAL_MS: number = 5000;
/** 有声书同时下载的章数。 */
const SHELF_AUDIO_DOWNLOAD_CONCURRENCY: number = 2;
const SHELF_COVER_INITIAL_PREFETCH_COUNT: number = 16;
const SHELF_COVER_UPDATE_BATCH_MS: number = 48;
const SHELF_UPDATE_BADGE_VARIABLE: string = 'shelfHasUpdate';
const SHELF_SEARCH_INPUT_KEY: string = 'bookshelf_search_input';
/** 分组页从卡片处展开、收回卡片的时长。 */
const SHELF_GROUP_MOTION_DURATION: number = 420;
/** 分组页建好、主线程空下来再开始动；一直忙也最多等这么久。 */
const SHELF_GROUP_MOTION_START_CAP: number = 220;
/**
 * 打开时先让卡片截图独自长大的引导段：时长盖住换页那一帧（真机约两百毫秒），走完全程的这么多；
 * 之后的展开段时长另计。两段曲线在接缝处速度大致接上。
 */
const SHELF_GROUP_LEAD_DURATION: number = 220;
const SHELF_GROUP_LEAD_PROGRESS: number = 0.3;
const SHELF_GROUP_EXPAND_DURATION: number = 300;
/** 动画回调丢失（切到后台等）时的兜底收尾。 */
const SHELF_GROUP_MOTION_WATCHDOG: number = 1600;
/** 卡片在书架上的圆角，展开前后要对得上。 */
const SHELF_GROUP_CARD_RADIUS: number = 7;
/** 整页缩放时请系统按高刷跑，不然返回时会先掉到 60Hz。 */
const SHELF_GROUP_FRAME_RATE: ExpectedFrameRateRange = { min: 60, max: 120, expected: 120 };
/** 截图先挂上、等这么多帧真正画出来再切页面：截图和建新页面挤在同一帧时，截图的纹理可能赶不上，整屏闪一下。 */
const SHELF_GROUP_PREMOUNT_FRAMES: number = 2;

/** 分组卡片四宫格里的一本书：点开时它在书架上的位置，返回时落回这里。 */
class TileGroupPreviewSource {
  book: Book;
  bounds: SharedElementBounds;

  constructor(book: Book, bounds: SharedElementBounds) {
    this.book = book;
    this.bounds = bounds;
  }
}

/**
 * 展开/收回时单独飞的一枚封面：按较大那头的尺寸排版，只用缩放平移从 from 走到 to，
 * 由 tileGroupFlyProgress 和页面同一段动画驱动。
 */
class TileGroupFlyer {
  key: string = '';
  cover: ResourceStr = '';
  /** 主题封面在书架上是拉伸铺满的，飞行时一样。 */
  fill: boolean = false;
  color: string = '';
  initial: string = '';
  width: number = 0;
  height: number = 0;
  fromX: number = 0;
  fromY: number = 0;
  fromScaleX: number = 1;
  fromScaleY: number = 1;
  toX: number = 0;
  toY: number = 0;
  toScaleX: number = 1;
  toScaleY: number = 1;
}

/** 下一帧开始渲染时回调。 */
class ShelfGroupNextFrame extends FrameCallback {
  private next: () => void;

  constructor(next: () => void) {
    super();
    this.next = next;
  }

  onFrame(_frameTimeInNano: number): void {
    this.next();
  }
}
/** 下拉偏移回退超过这个距离（vp）才算往回推，避免手指抖动时提示闪烁。 */
const SHELF_REFRESH_PULL_DIRECTION_SLOP: number = 2;
/** 输入停顿这么久才按新关键词重新筛选，连续打字时不必每个字都重建列表。 */
const SHELF_SEARCH_APPLY_DELAY_MS: number = 200;
/** 标签、书源筛选键的前缀，后面跟 encodeURIComponent 过的名字，避免名字里的逗号打乱键列表。 */
const SHELF_FILTER_TAG_PREFIX: string = 'tag:';
const SHELF_FILTER_ORIGIN_PREFIX: string = 'src:';
const SHELF_DAY_MS: number = 24 * 60 * 60 * 1000;
let bookshelfColdStartRefreshStarted: boolean = false;

/** 标签、书源筛选子页里的一项：筛选键、显示名与当前书架里的本数。 */
class ShelfFilterOption {
  key: string = '';
  label: string = '';
  count: number = 0;
}

interface ShelfFullTextCacheTask {
  taskId: number;
  bookUrl: string;
  bookName: string;
  taskKey: string;
  createdAt: number;
  cancelRequested: boolean;
  cancelSeenNonce: number;
  notificationLastAt: number;
  cancelAgent: WantAgent | null;
  done: number;
  total: number;
  status: string;
  coverPixelMap: image.PixelMap | null;
  notificationFailureHintShown: boolean;
  engine: ReadBookEngine | null;
  stoppingNotificationTask: Promise<void> | null;
  /** Chapter indexes to cache, in order. Empty means the whole book. */
  chapterIndexes: number[];
  /** Shown in the notification title: 全文 or 章节. */
  scopeLabel: string;
  /** 有声书下载：用户同意过用移动网络；为 false 时离开 Wi-Fi 就暂停等待。 */
  allowCellular: boolean;
}

/** 首页"书架"页签：书架展示、分组与排序、封面加载、更新检查、全文缓存与书籍操作。 */
@Component
export struct BookshelfPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  /** 标题下方“全部 / 网络 / 本地”胶囊的高度。 */
  static readonly SCOPE_TABS_HEIGHT: number = 44;
  static readonly SCOPE_TABS_PADDING: number = 6;
  static readonly SCOPE_TAB_INDICATOR_WIDTH: number = 18;
  /** 分类栏按书籍类型切换，没有书的类型不显示；隐私书架不在栏里，从最后一项继续左滑进入。 */
  static readonly TYPE_TAB_IDS: string[] = ['all', 'text', 'image', 'audio', 'video'];
  /**
   * 弹窗里直接列出的筛选组：来源、状态、阅读进度、最近阅读与更新。
   * 标签和书源的选项随书架内容变化，键带前缀，放在弹窗的二级页里。
   */
  static readonly FILTER_SOURCE_KEYS: string[] = ['network', 'local'];
  static readonly FILTER_STATUS_KEYS: string[] = ['finished', 'ongoing'];
  static readonly FILTER_PROGRESS_KEYS: string[] = ['unread', 'reading', 'readDone'];
  static readonly FILTER_READ_TIME_KEYS: string[] = ['read7d', 'read30d', 'stale90d'];
  static readonly FILTER_UPDATE_KEYS: string[] = ['updated'];
  static readonly FILTER_GROUPS: string[][] = [BookshelfPage.FILTER_SOURCE_KEYS, BookshelfPage.FILTER_STATUS_KEYS,
    BookshelfPage.FILTER_PROGRESS_KEYS, BookshelfPage.FILTER_READ_TIME_KEYS, BookshelfPage.FILTER_UPDATE_KEYS];
  static readonly FILTER_GROUP_LABELS: string[] = ['来源', '状态', '进度', '最近阅读', '更新'];
  /** 标签、书源二级页里选项区域的最大高度，超出后在区域内滚动。 */
  static readonly FILTER_SUBPAGE_MAX_HEIGHT: number = 360;
  /** 标题行下方书架搜索栏的高度。 */
  static readonly SEARCH_BAR_HEIGHT: number = 40;
  /** 顶部筛选和更多操作圆形按钮的高度。 */
  static readonly HEADER_CONTROL_SIZE: number = 40;
  /** 顶部下拉菜单（沉浸光感弹出层）的圆角、内边距和菜单项高度。 */
  static readonly MENU_RADIUS: number = ImmersiveMaterialRuntime.POPUP_MENU_RADIUS;
  static readonly MENU_PADDING: number = ImmersiveMaterialRuntime.POPUP_MENU_PADDING;
  static readonly MENU_ITEM_HEIGHT: number = 44;
  // 加密的书源封面解密完成后递增，读取它的封面会重新取到本地文件地址。
  @StorageProp('sourceCoverRevision') sourceCoverRevision: number = 0;
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Link isBookMultiSelect: boolean;
  @Link @Watch('onActiveShelfGroupChanged') activeShelfGroupId: number;
  @StorageLink('appThemeBookCoverEnabled') themeBookCoverEnabled: boolean = false;
  @StorageLink('appThemeId') appThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appCustomBaseThemeId') appCustomBaseThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @State books: Book[] = [];
  @StorageLink('cloudDownloadQueueRaw') cloudDownloadQueueRaw: string = '[]';
  @StorageLink('cloudDownloadStatus') cloudDownloadStatus: string = '';
  private cloudBookOpenRequest: number = 0;
  @State allBooks: Book[] = [];
  private shelfListBooksSource: ShelfBookDataSource = new ShelfBookDataSource();
  private shelfTileBooksSource: ShelfBookDataSource = new ShelfBookDataSource();
  private shelfTileEntriesSource: ShelfTileEntryDataSource = new ShelfTileEntryDataSource();
  private shelfTileEntriesCacheKey: string = '';
  private shelfTileEntriesCache: ShelfTileSortEntry[] = [];
  @State shelfCategoryRevision: number = 0;
  @State privateShelfRevealed: boolean = false;
  private shelfCategoryPages: Map<string, ShelfCategoryPage> = new Map();
  /** 'all' 为普通书架，'private' 为隐私书架。 */
  @State shelfScope: string = 'all';
  /** 当前有书的类型，决定分类栏显示哪几项；“全部”总在第一位。 */
  @State shelfTypeTabIds: string[] = ['all'];
  /** 分类栏的实际宽度：沉浸材质底板需要具体数值。 */
  @State shelfScopeTabsWidth: number = 0;
  /** 分类栏上的触点，转给下层材质底板画跟手光晕。 */
  @State shelfScopeTabsTouching: boolean = false;
  @State shelfScopeTabsTouchX: number = 0;
  @State shelfScopeTabsTouchY: number = 0;
  @StorageLink('bookshelfCategoryExpanded') shelfCategoryExpanded: boolean = true;
  @State shelfCategoryAnimating: boolean = false;
  private shelfCategoryAnimationSerial: number = 0;
  private shelfCategoryAnimationWatchdog: number = -1;
  @StorageLink('privateShelfEnabled') @Watch('onPrivateShelfEnabledChanged') privateShelfEnabled: boolean = false;
  @StorageLink('privateShelfHasPassword') privateShelfHasPassword: boolean = false;
  @StorageLink('privateShelfHeaderDoubleTap') privateShelfHeaderDoubleTap: boolean = false;
  @StorageLink('privateShelfBiometric') privateShelfBiometric: boolean = false;
  @State privateShelfBiometricUsable: boolean = false;
  private privateShelfBiometricPending: boolean = false;
  /** 横滑到隐私书架时手指还在屏幕上，这时拉起系统认证框会被立即取消，等抬手再拉起。 */
  private privateShelfBiometricQueued: boolean = false;
  private shelfContentTouching: boolean = false;
  @State privateShelfPasswordInput: string = '';
  @State privateShelfPasswordError: string = '';
  private privateShelfUnlockDialogSession: SystemDialogSession = new SystemDialogSession();
  private changeSourceDialogSession: SystemDialogSession = new SystemDialogSession();
  @State showShelfMoreMenu: boolean = false;
  /** 更多菜单内的二级页：空串、layout 或 sort。 */
  @State shelfMoreMenuPage: string = '';
  @State showShelfFilterMenu: boolean = false;
  /** 筛选弹窗当前页：空串为主页，'tag' / 'origin' 为标签、书源二级页。 */
  @State shelfFilterMenuPage: string = '';
  /** 分类栏选中的书籍类型，只在本次运行内保留（切换页签不丢，重启后回到“全部”）。 */
  @StorageLink('bookshelfTypeTab') shelfTypeTab: string = 'all';
  /** 筛选条件（FILTER_GROUPS 里的键）逗号分隔，同样只在本次运行内保留。 */
  @StorageLink('bookshelfFilterKeys') shelfFilterKeys: string = '';
  /** 书架搜索栏是否展开、框里的原始输入；同样只在本次运行内保留，主页返回键会先收起它。 */
  @StorageLink('bookshelfSearchActive') shelfSearchActive: boolean = false;
  @StorageLink('bookshelfSearchKeyword') @Watch('onShelfSearchKeywordChanged') shelfSearchKeyword: string = '';
  /** 实际参与筛选的关键词（转小写、空白归一），输入停顿后才从 shelfSearchKeyword 同步过来。 */
  @State shelfAppliedSearchKeyword: string = '';
  private shelfSearchApplyTimer: number = -1;
  /** 标题下拉的分组菜单。 */
  @State showShelfGroupMenu: boolean = false;
  @State shelfGroups: BookGroup[] = [];
  @State shelfScopeTransitionX: number = 0;
  @State shelfScopeTransitionScale: number = 1;
  @State shelfScopeTransitionOpacity: number = 1;
  @StorageLink('bookshelfGroupBackRequest') @Watch('onTileGroupBackRequested') tileGroupBackRequest: number = 0;
  @StorageLink('bookshelfGroupTransitionActive') tileGroupAnimating: boolean = false;
  /** 是从书架上的分组卡片进来的：返回时收回这张卡片，否则只淡出。 */
  @State tileGroupHasOrigin: boolean = false;
  private tileGroupOriginBounds: SharedElementBounds = new SharedElementBounds();
  private tileGroupOriginGroupId: number = 0;
  /** 打开时垫在下面的书架截图：分组页从卡片处长大，周围露出的仍是原来的书架。 */
  @State tileGroupBackdrop: image.PixelMap | undefined = undefined;
  /** 返回时盖在上面的分组页截图：下面先换回书架，截图再缩回卡片。 */
  @State tileGroupCurtain: image.PixelMap | undefined = undefined;
  /** 分组卡片自己的截图：打开时盖在长大的页面上很快淡出，返回时在缩小的截图上淡入，首尾和卡片一模一样。 */
  @State tileGroupCardShot: image.PixelMap | undefined = undefined;
  /**
   * 打开时的书架截图在分组页期间留着：返回时活的分组页直接缩回卡片、周围露出它，不必先截分组页、
   * 再在动画前重建书架（重建要占三四帧、三百多毫秒）。尺寸或深浅色变了就不再可用。
   */
  private tileGroupShelfShot: image.PixelMap | undefined = undefined;
  private tileGroupShelfShotKey: string = '';
  /** 缩回卡片后盖在最上面的同一张书架截图：下面换回书架、恢复滚动，画好后揭开。 */
  @State tileGroupCover: image.PixelMap | undefined = undefined;
  /**
   * 卡片是四宫格、分组页是一行四本，整页缩放时封面会从一种排法跳到另一种。四宫格里的书在展开/收回期间各自
   * 从格子飞到分组页里的位置（或飞回来），分组页里这几本自己的封面先藏起来。
   */
  @State tileGroupFlyers: TileGroupFlyer[] = [];
  @State tileGroupFlyProgress: number = 0;
  @State tileGroupHiddenCovers: string[] = [];
  @State shelfReorderCurtain: image.PixelMap | undefined = undefined;
  @State shelfReorderCurtainOpacity: number = 1;
  /** 关书回到书架到挪位动画结束；期间不在 loadBooks 里放掉按住的阅读时间。 */
  private shelfReturnMotionActive: boolean = false;
  private tileGroupPreviewSources: TileGroupPreviewSource[] = [];
  private tileGroupLeadBounds: SharedElementBounds = new SharedElementBounds();
  /** 展开或收回中的页面：以左上角为原点非等比缩放再平移到卡片处，只改绘制不改排版。 */
  @State tileGroupMotionScaleX: number = 1;
  @State tileGroupMotionScaleY: number = 1;
  @State tileGroupMotionTranslateX: number = 0;
  @State tileGroupMotionTranslateY: number = 0;
  @State tileGroupMotionRadius: number = 0;
  @State tileGroupCardOpacity: number = 0;
  @State tileGroupScrimOpacity: number = 0;
  @State tileGroupPageOpacity: number = 1;
  private tileGroupPendingBack: boolean = false;
  /** 已开始但还没切过去的目标分组（-1 表示没有）；兜底收尾时直接切过去，不让点击落空。 */
  private tileGroupPendingTarget: number = -1;
  private tileGroupMotionGeneration: number = 0;
  private tileGroupStartTimer: number = -1;
  private tileGroupMotionWatchdog: number = -1;
  private tileGroupRootPages: Map<string, ShelfCategoryPage> | null = null;
  private tileGroupRootHeaderCollapse: number = 0;
  @State selectedBookUrls: string[] = [];
  @State showMultiSelectMoreMenu: boolean = false;
  private batchExportDialogSession: SystemDialogSession = new SystemDialogSession();
  @State showBookGroupPicker: boolean = false;
  @State groupPickerSingleBookUrl: string = '';
  private addBookGroupDialogSession: SystemDialogSession = new SystemDialogSession();
  private renameBookGroupDialogSession: SystemDialogSession = new SystemDialogSession();
  private deleteBookGroupDialogSession: SystemDialogSession = new SystemDialogSession();
  private batchDeleteDialogSession: SystemDialogSession = new SystemDialogSession();
  private deleteBookDialogSession: SystemDialogSession = new SystemDialogSession();
  private editBookInfoDialogSession: SystemDialogSession = new SystemDialogSession();
  private tagDialogSession: SystemDialogSession = new SystemDialogSession();
  private customCoverDialogSession: SystemDialogSession = new SystemDialogSession();
  @State showAddBookGroupDialog: boolean = false;
  @State newBookGroupName: string = '';
  @State showBookGroupActionMenu: boolean = false;
  @State showRenameBookGroupDialog: boolean = false;
  @State renameBookGroupName: string = '';
  @State pendingBookGroup: BookGroup | null = null;
  @State showDeleteBookGroupDialog: boolean = false;
  @State pendingDeleteBookGroup: BookGroup | null = null;
  @State showBatchDeleteDialog: boolean = false;
  @State isLoading: boolean = false;
  @State showDeleteDialog: boolean = false;
  @State showActionDialog: boolean = false;
  @State showEditBookInfoDialog: boolean = false;
  @State editingBookName: string = '';
  @State editingBookAuthor: string = '';
  @State showTagDialog: boolean = false;
  private cacheDialogSession: SystemDialogSession = new SystemDialogSession();
  private chapterCacheDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onBookshelfSystemDialogFlagChanged') showCacheDialog: boolean = false;
  @State @Watch('onBookshelfSystemDialogFlagChanged') showChapterCacheDialog: boolean = false;
  @State showNetworkCoverDialog: boolean = false;
  @State networkCoverTargetBook: Book | null = null;
  @State networkCoverCandidates: SearchBook[] = [];
  @State networkCoverSearching: boolean = false;
  @State networkCoverStatus: string = '';
  @State showCustomNetworkCoverDialog: boolean = false;
  @State customNetworkCoverUrl: string = '';
  @State pendingDeleteBook: Book | null = null;
  @State pendingActionBook: Book | null = null;
  @State @Watch('syncChangeSourceDialog') showShelfChangeSourceDialog: boolean = false;
  private shelfChangeSourceTarget: Book | null = null;
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State shelfTileViewportWidth: number = 360;
  @State cacheTargetBook: Book | null = null;
  @State cacheChapters: BookChapter[] = [];
  @State cacheStatus: string = '';
  @State cacheRangeDraft: string = '';
  @State isCaching: boolean = false;
  @State activeFullTextCacheBookUrls: string[] = [];
  @State isCacheTocLoading: boolean = false;
  @State isShelfRefreshing: boolean = false;
  @State shelfRefreshStatus: RefreshStatus = RefreshStatus.Inactive;
  @State shelfRefreshPrompt: string = '下拉刷新书架';
  /** 下拉途中手指往回推时收起提示，再往下拉才重新显示。 */
  @State shelfRefreshPullRetracting: boolean = false;
  private shelfRefreshPullPeak: number = 0;
  private shelfRefreshPullTrough: number = 0;
  @State editingTags: string[] = [];
  @State tagInput: string = '';
  @State shelfCoverMap: Map<string, string> = new Map();
  @State shelfCoverRenderVersions: Map<string, number> = new Map();
  private shelfCoverRawUrls: Map<string, string> = new Map();
  private shelfCoverCacheRevision: number = 0;
  private shelfCoverBookTasks: Set<string> = new Set();
  private pendingShelfCoverUpdates: Map<string, string> = new Map();
  private shelfCoverUpdateTimer: number = -1;
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('bookshelfSortMode') sortMode: string = 'recentRead';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('bookshelfShowTags') bookshelfShowTags: boolean = true;
  @StorageLink('bookshelfCoverBadges') @Watch('refreshOfflineBookUrls') bookshelfCoverBadges: string = BookshelfCoverBadgeSettings.DEFAULT;
  /** 边听边下完成一章、删除离线音频后更新，封面"离线"标识据此刷新。 */
  @StorageLink('audioOfflineRevision') @Watch('refreshOfflineBookUrls') audioOfflineRevision: number = 0;
  /** 封面"离线"标识变化时加一；集合本身不是状态变量。 */
  @State offlineBookRevision: number = 0;
  private offlineBookUrls: Set<string> = new Set<string>();
  @StorageLink('bookshelfShowIntro') bookshelfShowIntro: boolean = true;
  @StorageLink('bookshelfShowFullIntro') bookshelfShowFullIntro: boolean = false;
  @StorageLink('bookshelfShowProgressBar') bookshelfShowProgressBar: boolean = false;
  @StorageLink('bookshelfShowLastReadTime') bookshelfShowLastReadTime: boolean = true;
  @StorageLink('bookshelfShowLastReadChapter') bookshelfShowLastReadChapter: boolean = false;
  @StorageLink('bookshelfLayoutMode') bookshelfLayoutMode: string = 'companion';
  @StorageLink('bookshelfLastReadLeafMode') bookshelfLastReadLeafMode: string = 'adaptive';
  @StorageLink('bookshelfLastReadPinMode') @Watch('onLastReadPinModeChanged') bookshelfLastReadPinMode: string = 'large';
  @StorageLink('bookshelfLastReadPinCount') @Watch('onLastReadPinModeChanged') bookshelfLastReadPinCount: number = 1;
  @StorageLink('bookshelfBookOpenAnimation') bookshelfBookOpenAnimation: boolean = true;
  /** 书架设置“书籍分类”：关闭后没有分类栏和展开按钮，所有书按“全部”平铺。 */
  @StorageLink('bookshelfTypeCategoryEnabled') @Watch('onShelfTypeCategorySettingChanged')
  bookshelfTypeCategoryEnabled: boolean = true;
  /** 书架设置“显示全部分类”：关闭后分类栏只列有书的类型。 */
  @StorageLink('bookshelfShowAllTypeTab') @Watch('onShelfTypeCategorySettingChanged')
  bookshelfShowAllTypeTab: boolean = true;
  @StorageLink('bookshelfCoverAlbums') @Watch('onShelfCoverSettingsChanged') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') @Watch('onShelfCoverSettingsChanged') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') @Watch('onShelfCoverSettingsChanged') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverApplyScope') @Watch('onShelfCoverSettingsChanged') bookshelfCoverApplyScope: string = 'all';
  @StorageLink('bookshelfCoverTargetBooks') @Watch('onShelfCoverSettingsChanged') bookshelfCoverTargetBooks: string = '';
  @StorageLink('bookshelfIgnoreSourceCover') @Watch('onShelfCoverSettingsChanged') bookshelfIgnoreSourceCover: boolean = false;
  @StorageLink('bookshelfCoverMode') @Watch('onShelfCoverSettingsChanged') bookshelfCoverMode: string = 'sequence';
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageLink('fullTextCacheCancelNonce') @Watch('onFullTextCacheCancelNonceChanged') fullTextCacheCancelNonce: number = 0;
  @StorageLink('fullTextCacheCancelSignal') @Watch('onFullTextCacheCancelSignalChanged') fullTextCacheCancelSignal: string = '';
  @StorageLink('audioOfflineDownloadRequest') @Watch('onAudioOfflineDownloadRequest') audioOfflineDownloadRequest: string = '';
  @StorageLink('shelfBookCloseAnimationNonce') @Watch('onShelfBookCloseAnimationRequested')
  shelfBookCloseAnimationNonce: number = 0;
  @StorageLink('shelfBookCloseAnimationUrl') shelfBookCloseAnimationUrl: string = '';
  private loadTimer: number = -1;
  private cacheTocLoadToken: number = 0;
  private cacheTocLoadBookUrl: string = '';
  private cacheTocLoadPromise: Promise<boolean> | null = null;
  private cacheDialogOpenedAt: number = 0;
  private fullTextCacheTasks: Map<string, ShelfFullTextCacheTask> = new Map();
  private shelfRefreshRunning: boolean = false;
  private fullTextCacheTaskId: number = 0;
  private fullTextCacheCancelRequested: boolean = false;
  private fullTextCacheCancelSeenNonce: number = 0;
  private fullTextCacheNotificationLastAt: number = 0;
  private fullTextCacheBackgroundRunning: boolean = false;
  private fullTextCacheCancelAgent: WantAgent | null = null;
  private fullTextCacheDone: number = 0;
  private fullTextCacheTotal: number = 0;
  private fullTextCacheStatus: string = '';
  private fullTextCacheBookName: string = '';
  private fullTextCacheNotificationSlotReady: boolean = false;
  private fullTextCacheNotificationFailureHintShown: boolean = false;
  private shelfBookRoutePending: boolean = false;
  private shelfBookReturnRefreshTimer: number = -1;
  private shelfScopeSwapTimer: number = -1;
  private shelfScopeFinishTimer: number = -1;
  private shelfScopeSwitchAnimating: boolean = false;
  private suppressShelfBookClickUntil: number = 0;
  private pendingShelfSortTimer: number = -1;
  private pendingShelfSortMode: string = '';
  private networkCoverCoordinator: SearchCoordinator | null = null;
  private networkCoverSearchToken: number = 0;
  private shelfLoadSerial: number = 0;
  /** 分组与分类栏类型已从偏好恢复；恢复前的变化不写回，避免覆盖上次的选择。 */
  private shelfStateRestored: boolean = false;
  private shelfCategoryExpandedRestored: boolean = false;
  private localBookIntroMigrationQueue: Book[] = [];
  private localBookIntroMigrationRunning: boolean = false;
  private localBookIntroMigrationGeneration: number = 0;
  private shelfComponentActive: boolean = false;
  private shelfUpdateAcknowledgedAt: Map<string, number> = new Map();

  private readonly shelfCoverLocate = (bookUrl: string): ShelfOpeningCover | null => this.locateShelfCover(bookUrl);
  /** 首页根节点整张截图（含标签栏），阅读页放大、缩回时垫在后面；被盖住的页面照样能离屏截图。 */
  private readonly shelfBackdropSnapshot = (): Promise<image.PixelMap> =>
    this.getUIContext().getComponentSnapshot().get('home_root', { scale: 1, waitUntilRenderFinished: true });
  /**
   * 手指按下时提前截的首页图：点开书时多半已经截好，推阅读页前不必再等一次截图。
   * 没点开的（滚动、长按）在松手后不久释放；按下超过 SHELF_OPENING_BACKDROP_FRESH 的也不再用，避免画面已变。
   */
  private shelfOpeningBackdropPending: Promise<image.PixelMap | null> | null = null;
  private shelfOpeningBackdropRequestedAt: number = 0;
  private shelfOpeningBackdropDiscardTimer: number = -1;
  private static readonly SHELF_OPENING_BACKDROP_FRESH: number = 400;
  /** 点开时截图还没回来，最多再等这么久；超时就不垫背景（和以前一样纯色），不让截图拖慢打开。 */
  private static readonly SHELF_OPENING_BACKDROP_WAIT: number = 100;
  /** 阅读页自己缩回后多久刷新书架（首页盖图挡着）。 */
  private static readonly SHELF_RETURN_QUICK_REFRESH: number = 120;
  /** 刷新通知发出后首页 120ms 揭开盖图，再稍等一点开始挪位。 */
  private static readonly SHELF_REORDER_START_DELAY: number = 150;
  private static readonly SHELF_REORDER_DURATION: number = 450;
  private static readonly SHELF_REORDER_CURTAIN_FADE: number = 220;

  aboutToAppear() {
    this.shelfComponentActive = true;
    ShelfCoverLocator.register(this.shelfCoverLocate, this.shelfBackdropSnapshot);
    ReaderOpenSnapshotStore.prepare(getContext(this)).catch((): void => {});
    this.shelfAppliedSearchKeyword = BookshelfPage.normalizeShelfSearchText(this.shelfSearchKeyword);
    this.reloadDisplaySettings();
    this.restoreShelfCategoryExpanded();
    this.restoreSortModeAndLoad();
  }

  aboutToDisappear(): void {
    this.shelfComponentActive = false;
    ShelfCoverLocator.unregister(this.shelfCoverLocate);
    this.discardShelfOpeningBackdrop();
    this.cancelTileGroupMotion();
    this.stopShelfCategoryAnimation();
    this.cloudBookOpenRequest++;
    this.cancelShelfBookOpening();
    this.cancelNetworkCoverSearch();
    this.clearShelfScopeTransition();
    this.shelfCoverCacheRevision++;
    this.localBookIntroMigrationGeneration++;
    this.localBookIntroMigrationQueue = [];
    this.shelfCoverBookTasks.clear();
    this.pendingShelfCoverUpdates.clear();
    if (this.shelfCoverUpdateTimer >= 0) {
      clearTimeout(this.shelfCoverUpdateTimer);
      this.shelfCoverUpdateTimer = -1;
    }
    if (this.pendingShelfSortTimer >= 0) {
      clearTimeout(this.pendingShelfSortTimer);
      this.pendingShelfSortTimer = -1;
    }
    this.pendingShelfSortMode = '';
    if (this.shelfSearchApplyTimer >= 0) {
      clearTimeout(this.shelfSearchApplyTimer);
      this.shelfSearchApplyTimer = -1;
    }
  }

  onActiveShelfGroupChanged(): void {
    this.applyShelfScope();
    // A group switch changes the visible snapshot while the shelf's LazyForEach data sources
    // are retained.  Replacing them here (and forcing a reload) prevents a retained list/grid
    // from continuing to render the books from the previous group, especially on the tile group
    // page where the source is shared across group transitions.
    this.reloadShelfDataSources(true);
    if (this.shelfStateRestored) {
      BookshelfStateStore.saveActiveGroupId(getContext(this), this.activeShelfGroupId).catch((e: Error) => {
        console.warn('保存书架分组状态失败:', e);
      });
    }
  }

  onShelfBookCloseAnimationRequested(): void {
    if (!this.shelfBookCloseAnimationUrl) {
      return;
    }
    this.closeShelfBook(this.shelfBookCloseAnimationUrl);
  }

  async reloadDisplaySettings(): Promise<void> {
    try {
      const settings = await BookshelfDisplaySettingsStore.load(getContext(this));
      this.bookshelfShowTags = settings.showTags;
      this.bookshelfCoverBadges = settings.coverBadges;
      this.bookshelfShowIntro = settings.showIntro;
      this.bookshelfShowFullIntro = settings.showFullIntro;
      this.bookshelfShowProgressBar = settings.showProgressBar;
      this.bookshelfShowLastReadTime = settings.showLastReadTime;
      this.bookshelfShowLastReadChapter = settings.showLastReadChapter;
      this.bookshelfLayoutMode = settings.layoutMode;
      this.bookshelfLastReadLeafMode = settings.lastReadLeafMode;
      this.bookshelfLastReadPinMode = settings.lastReadPinMode;
      this.bookshelfLastReadPinCount = settings.lastReadPinCount;
      this.bookshelfBookOpenAnimation = settings.bookOpenAnimation;
      this.bookshelfTypeCategoryEnabled = settings.typeCategoryEnabled;
      this.bookshelfShowAllTypeTab = settings.showAllTypeTab;
    } catch (e) {
      console.warn('恢复书架显示设置失败:', e);
    }
  }

  onShelfChanged(): void {
    this.scheduleLoadBooks();
  }

  /** 有离线内容的书：下载过音频，或有手动缓存的正文、漫画。只有封面标识里放了"离线"才查。 */
  refreshOfflineBookUrls(): void {
    if (BookshelfCoverBadgeSettings.location(this.bookshelfCoverBadges, 'offline') < 0) {
      if (this.offlineBookUrls.size > 0) {
        this.offlineBookUrls = new Set<string>();
        this.offlineBookRevision++;
      }
      return;
    }
    AppDatabase.getInstance().getOfflineBookUrls().then((urls: string[]): void => {
      this.offlineBookUrls = new Set<string>(urls);
      this.offlineBookRevision++;
    }).catch((error: Error) => console.warn('读取离线书籍失败:', error));
  }

  hasOfflineContent(book: Book): boolean {
    return this.offlineBookRevision >= 0 && !!book.bookUrl && this.offlineBookUrls.has(book.bookUrl);
  }

  // 置顶开关决定平铺数据源里是否剔除上次阅读的书，切换后立即重建，避免同一本书出现两次或消失。
  onLastReadPinModeChanged(): void {
    this.reloadShelfDataSources(true);
  }

  onShelfTypeCategorySettingChanged(): void {
    this.applyShelfScope();
    this.reloadShelfDataSources(true);
  }

  onPrivateShelfEnabledChanged(): void {
    if (!this.privateShelfEnabled) this.privateShelfRevealed = false;
    if (!this.privateShelfEnabled && this.shelfScope === 'private') {
      this.setShelfPage(this.shelfTypeTab);
    }
  }

  onShelfCoverSettingsChanged(): void {
    this.shelfCoverMap = new Map();
    this.shelfCoverRawUrls.clear();
    this.refreshShelfCoverCache(this.books);
  }

  async loadBooks(forceDataSourceReload: boolean = false): Promise<void> {
    const loadSerial = ++this.shelfLoadSerial;
    // 没经过关书动画回到书架（打开失败、阅读页被换成别的页再返回）时，按住的阅读时间在这里放掉。
    if (!this.shelfReturnMotionActive && Number(router.getLength()) <= 1) BookshelfSortHelper.releaseReadTimes();
    // Returning from the reader refreshes shelf metadata. Do not cover an already-rendered shelf
    // with the initial loading placeholder; that one-frame replacement is perceived as a flash.
    const needsInitialPlaceholder = this.allBooks.length === 0;
    if (needsInitialPlaceholder) this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await PrivateShelfStore.load(getContext(this));
      const loadedBooks = SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks());
      const loadedGroups = await db.getCustomBookGroups();
      if (loadSerial !== this.shelfLoadSerial) return;
      if (!this.shelfStateRestored) {
        try {
          this.activeShelfGroupId = await BookshelfStateStore.loadActiveGroupId(getContext(this));
        } catch (e) {
          console.warn('恢复书架分组状态失败:', e);
        }
        try {
          // 在首帧书架出现前恢复，分类页直接停在上次的类型；该类型暂时没书时由 activeShelfTypeTab 回退显示。
          const typeTab = await BookshelfStateStore.loadTypeTab(getContext(this));
          if (BookshelfPage.TYPE_TAB_IDS.indexOf(typeTab) >= 0) this.shelfTypeTab = typeTab;
        } catch (e) {
          console.warn('恢复书架分类状态失败:', e);
        }
        if (loadSerial !== this.shelfLoadSerial) return;
        this.shelfStateRestored = true;
      }
      // A query started before the click can finish during the flight. Keep the shared cover's node stable.
      if (this.shelfBookMotionDelay() > 0) {
        this.scheduleLoadBooks();
        return;
      }
      // Commit the complete snapshot together. In particular, never expose a new expanded card while the retained
      // LazyForEach data source still contains entries from the previous shelf generation.
      this.allBooks = loadedBooks;
      this.shelfGroups = loadedGroups;
      if (this.activeShelfGroupId > 0 && !this.shelfGroups.some((group: BookGroup) => group.groupId === this.activeShelfGroupId)) {
        this.activeShelfGroupId = 0;
      }
      this.applyShelfScope();
      this.reloadShelfDataSources(forceDataSourceReload);
      this.refreshOfflineBookUrls();
      this.refreshShelfCoverCache(this.books);
      this.scheduleLocalBookIntroMigration(loadedBooks);
      this.scheduleColdStartBookshelfRefresh(loadedBooks);
    } catch (e) {
      if (loadSerial === this.shelfLoadSerial) console.error('加载书籍失败:', e);
    } finally {
      if (needsInitialPlaceholder && loadSerial === this.shelfLoadSerial) this.isLoading = false;
    }
  }

  reloadShelfDataSources(force: boolean = false): void {
    this.shelfCategoryRevision++;
    this.shelfTileEntriesCacheKey = '';
    this.shelfTileEntriesCache = [];
    this.shelfListBooksSource.replace(this.books, force);
    this.shelfTileBooksSource.replace(this.getTileBooksWithoutLatest(this.books), force);
    this.shelfTileEntriesSource.replace(this.getSortedTileRootEntries(this.books), force);
  }

  shelfBookMotionDelay(): number {
    return Math.max(0, (AppStorage.get<number>(SHELF_BOOK_MOTION_UNTIL_KEY) || 0) - Date.now());
  }

  scheduleLoadBooks(): void {
    if (this.loadTimer >= 0) {
      clearTimeout(this.loadTimer);
      this.loadTimer = -1;
    }
    // The return timer already reloads the latest database snapshot, including saves made during the flight.
    if (this.shelfBookReturnRefreshTimer >= 0) return;
    this.loadTimer = setTimeout(() => {
      this.loadTimer = -1;
      if (this.shelfBookMotionDelay() > 0 || this.shelfBookReturnRefreshTimer >= 0) {
        if (this.shelfBookReturnRefreshTimer < 0) this.scheduleLoadBooks();
        return;
      }
      this.loadBooks();
    }, Math.max(80, this.shelfBookMotionDelay()));
  }

  scheduleColdStartBookshelfRefresh(loadedBooks: Book[]): void {
    if (bookshelfColdStartRefreshStarted || loadedBooks.length === 0) {
      return;
    }
    bookshelfColdStartRefreshStarted = true;
    // Run once per process after the first local shelf snapshot is visible. The refresh deliberately
    // has no spinner or toast so cold startup remains responsive.
    setTimeout(() => {
      console.info('[ShelfRefresh] cold-start silent refresh started');
      this.refreshBookshelfToc(true).then(() => {
        console.info('[ShelfRefresh] cold-start silent refresh finished');
      }).catch((e: Error) => {
        console.error('[ShelfRefresh] cold-start silent refresh failed:', e);
      });
    }, 600);
  }

  async deleteBook(book: Book) {
    try {
      const db = AppDatabase.getInstance();
      this.deleteBookCoverCache(book);
      CloudAutoSync.onBookRemoved(getContext(this), book).catch(() => undefined);
      LocalBookService.deleteLocalBookFiles(getContext(this), book);
      await db.deleteBook(book.bookUrl, 'bookshelf_user_delete');
      HdsFeedback.showToast(`已删除《${book.name}》`);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      await this.loadBooks();
    } catch (e) {
      console.error('删除书籍失败:', e);
      HdsFeedback.showToast('删除失败');
    }
  }

  showDeleteConfirm(book: Book) {
    this.pendingDeleteBook = book;
    this.openDeleteBookDialog();
  }

  showBookActions(book: Book, event?: GestureEvent): void {
    this.captureContextMenuAnchor(event);
    this.pendingActionBook = book;
    this.showActionDialog = true;
  }

  async saveLocalBookSource(book: Book): Promise<void> {
    try {
      const savedUri = await LocalBookService.exportSourceFile(getContext(this), book);
      if (savedUri) {
        HdsFeedback.showToast(`已保存《${book.name}》源文件`);
      }
    } catch (e) {
      console.error('保存本地书籍源文件失败:', e);
      HdsFeedback.showToast(`保存失败：${e instanceof Error ? e.message : String(e)}`);
    }
  }

  async toggleBookPinned(book: Book): Promise<void> {
    const nextPinned = !book.isPinned;
    const modifiedTime = Date.now();
    try {
      await AppDatabase.getInstance().setBookPinned(book.bookUrl, nextPinned, modifiedTime);
      book.isPinned = nextPinned;
      book.shelfModifiedTime = modifiedTime;
      this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
      this.applyShelfScope();
      this.reloadShelfDataSources(true);
      HdsFeedback.showToast(nextPinned ? `已置顶《${book.name}》` : `已取消置顶《${book.name}》`);
    } catch (e) {
      console.error('更新书籍置顶状态失败:', e);
      HdsFeedback.showToast(nextPinned ? '置顶失败' : '取消置顶失败');
    }
  }

  async toggleBookPrivate(book: Book): Promise<void> {
    const nextPrivate = !book.isPrivate;
    try {
      await AppDatabase.getInstance().setBookPrivate(book.bookUrl, nextPrivate);
      book.isPrivate = nextPrivate;
      this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
      this.applyShelfScope();
      this.reloadShelfDataSources(true);
      // 桌面“最近阅读”卡片不应再展示刚移入隐私书架的书。
      RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext).catch((e: Error) => {
        console.warn('刷新最近阅读卡片失败:', e);
      });
      HdsFeedback.showToast(nextPrivate ? `已将《${book.name}》移入隐私书架` : `已将《${book.name}》移出隐私书架`);
    } catch (e) {
      console.error('更新书籍隐私状态失败:', e);
      HdsFeedback.showToast(nextPrivate ? '标记为隐私失败' : '取消隐私失败');
    }
  }

  private async restoreShelfCategoryExpanded(): Promise<void> {
    try {
      // 当前值来自旧版 PersistentStorage，偏好里还没有时沿用它。
      const expanded = await BookshelfStateStore.loadCategoryExpanded(getContext(this), this.shelfCategoryExpanded);
      // 读偏好期间用户已经手动展开/收起过时，以手动操作为准。
      if (this.shelfComponentActive && !this.shelfCategoryExpandedRestored) this.shelfCategoryExpanded = expanded;
    } catch (e) {
      console.warn('恢复书架分类栏展开状态失败:', e);
    } finally {
      this.shelfCategoryExpandedRestored = true;
    }
  }

  private async restoreSortModeAndLoad(): Promise<void> {
    try {
      // Use the current AppStorage value as a migration fallback for installations that
      // previously relied only on PersistentStorage before the explicit Preferences key existed.
      const storageMode = AppStorage.get<string>('bookshelfSortMode');
      const fallbackMode = BookshelfStateStore.normalizeSortMode(storageMode || this.sortMode);
      const mode = await BookshelfStateStore.loadSortMode(getContext(this), fallbackMode);
      if (this.shelfComponentActive) {
        this.sortMode = mode;
      }
    } catch (e) {
      console.warn('恢复书架排序设置失败:', e);
    } finally {
      if (this.shelfComponentActive) {
        this.scheduleLoadBooks();
      }
    }
  }

  scheduleLocalBookIntroMigration(books: Book[]): void {
    this.localBookIntroMigrationQueue = books.filter((book: Book) =>
      LocalBookService.isLocalBook(book) &&
      (book.getVariable('localContentIntroVersion') !== '6' || !book.intro.trim()));
    if (!this.shelfComponentActive || this.localBookIntroMigrationQueue.length === 0 ||
      this.localBookIntroMigrationRunning) return;
    const generation = ++this.localBookIntroMigrationGeneration;
    this.localBookIntroMigrationRunning = true;
    setTimeout(() => this.runLocalBookIntroMigration(generation), 120);
  }

  async runLocalBookIntroMigration(generation: number): Promise<void> {
    try {
      while (generation === this.localBookIntroMigrationGeneration &&
        this.localBookIntroMigrationQueue.length > 0) {
        const book = this.localBookIntroMigrationQueue.shift();
        if (!book) break;
        try {
          const changed = await LocalBookService.ensureContentIntro(book);
          if (changed && generation === this.localBookIntroMigrationGeneration) {
            this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
            this.applyShelfScope();
          }
        } catch (e) {
          console.warn('后台生成本地书籍简介失败:', book.name, e);
        }
        // Keep migrations behind user input and list animation work.
        await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 16));
      }
    } finally {
      this.localBookIntroMigrationRunning = false;
      if (this.shelfComponentActive && this.localBookIntroMigrationQueue.length > 0) {
        this.scheduleLocalBookIntroMigration(this.localBookIntroMigrationQueue);
      }
    }
  }

  closeBookActions(): void {
    this.showActionDialog = false;
    this.pendingActionBook = null;
  }

  openShelfBookDetail(book: Book): void {
    router.pushUrl({
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
        coverUrl: book.customCoverUrl || book.coverUrl,
        intro: book.customIntro || book.intro,
        latestChapterTitle: book.latestChapterTitle,
        updateTime: book.updateTime,
        wordCount: book.wordCount,
        type: `${book.type}`,
        variable: book.variable,
        promptAddToShelfOnBack: 'false'
      }
    });
  }

  openShelfChangeSource(book: Book): void {
    if (!book.name.trim() || LocalBookService.isLocalBook(book)) {
      HdsFeedback.showToast('当前书籍不支持换源');
      return;
    }
    this.shelfChangeSourceTarget = book;
    this.showShelfChangeSourceDialog = true;
  }

  async openNetworkCoverPicker(book: Book): Promise<void> {
    const keyword = (book.name || '').trim();
    if (!keyword) {
      HdsFeedback.showToast('书名为空，无法搜索封面');
      return;
    }
    this.cancelNetworkCoverSearch();
    this.networkCoverTargetBook = book;
    this.networkCoverCandidates = [];
    this.networkCoverSearching = true;
    this.networkCoverStatus = '正在从启用的书源中搜索...';
    this.showNetworkCoverDialog = true;
    const token = this.networkCoverSearchToken;
    const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
    this.networkCoverCoordinator = coordinator;
    try {
      await AppDatabase.getInstance().initWithContext(getContext(this));
      const results = await coordinator.search(keyword, (progress: SearchProgress) => {
        if (token !== this.networkCoverSearchToken || this.networkCoverCoordinator !== coordinator) return;
        const incoming = progress.finished ? progress.results : (progress.deltaResults || []);
        if (incoming.length > 0) {
          this.appendNetworkCoverCandidates(incoming);
        }
        this.networkCoverStatus = progress.finished ?
          `搜索完成，找到 ${this.networkCoverCandidates.length} 个可选封面` :
          `${progress.status}，可选封面 ${this.networkCoverCandidates.length} 个`;
        if (progress.finished) this.networkCoverSearching = false;
      }, {
        exactMatch: true,
        exactMatchAuthor: false
      });
      if (token !== this.networkCoverSearchToken || this.networkCoverCoordinator !== coordinator) return;
      this.appendNetworkCoverCandidates(results);
      this.networkCoverSearching = false;
      this.networkCoverStatus = this.networkCoverCandidates.length > 0 ?
        `搜索完成，找到 ${this.networkCoverCandidates.length} 个可选封面` : '搜索完成，未找到带封面的书籍';
    } catch (e) {
      if (token !== this.networkCoverSearchToken) return;
      console.error('搜索网络封面失败:', e);
      this.networkCoverSearching = false;
      this.networkCoverStatus = '搜索网络封面失败，请稍后重试';
    } finally {
      if (token === this.networkCoverSearchToken && this.networkCoverCoordinator === coordinator) {
        this.networkCoverCoordinator = null;
      }
    }
  }

  appendNetworkCoverCandidates(results: SearchBook[]): void {
    const merged = this.networkCoverCandidates.slice();
    const coverUrls = new Set<string>(merged.map((item: SearchBook) => item.coverUrl));
    for (const result of results) {
      const coverUrl = (result.coverUrl || '').trim();
      if (!/^https?:\/\//i.test(coverUrl) || coverUrls.has(coverUrl)) continue;
      result.coverUrl = coverUrl;
      merged.push(result);
      coverUrls.add(coverUrl);
      if (merged.length >= 90) break;
    }
    this.networkCoverCandidates = merged;
  }

  async applyNetworkCover(candidate: SearchBook): Promise<void> {
    const target = this.networkCoverTargetBook;
    const coverUrl = (candidate.coverUrl || '').trim();
    if (!target || !coverUrl) return;
    try {
      const db = AppDatabase.getInstance();
      const current = await db.getBook(target.bookUrl);
      if (!current) {
        HdsFeedback.showToast('书籍已不在书架中');
        this.closeNetworkCoverPicker();
        return;
      }
      current.customCoverUrl = coverUrl;
      await db.updateBook(current);
      this.applyShelfBookCoverState(current);
      this.closeNetworkCoverPicker();
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('网络封面已启用');
    } catch (e) {
      console.error('应用网络封面失败:', e);
      HdsFeedback.showToast('应用网络封面失败');
    }
  }

  async restoreDefaultBookCover(book: Book): Promise<void> {
    if (!book.customCoverUrl) return;
    try {
      const db = AppDatabase.getInstance();
      const current = await db.getBook(book.bookUrl);
      if (!current) {
        HdsFeedback.showToast('书籍已不在书架中');
        return;
      }
      current.customCoverUrl = '';
      await db.updateBook(current);
      this.applyShelfBookCoverState(current);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('已恢复默认封面');
    } catch (e) {
      console.error('恢复默认封面失败:', e);
      HdsFeedback.showToast('恢复默认封面失败');
    }
  }

  applyShelfBookCoverState(current: Book): void {
    this.allBooks = this.allBooks.map((book: Book) => book.bookUrl === current.bookUrl ? current : book);
    this.applyShelfScope();
    this.bumpShelfBookCoverRenderVersion(current.bookUrl);
    this.shelfCoverMap = new Map();
    this.shelfCoverRawUrls.clear();
    this.refreshShelfCoverCache(this.books);
  }

  bumpShelfBookCoverRenderVersion(bookUrl: string): void {
    const versions = new Map<string, number>(this.shelfCoverRenderVersions);
    versions.set(bookUrl, (versions.get(bookUrl) || 0) + 1);
    this.shelfCoverRenderVersions = versions;
  }

  shelfBookRenderKey(book: Book, prefix: string): string {
    // LazyForEach keeps an item node when its key is unchanged. Reading progress is persisted into a fresh Book
    // snapshot while the URL/pin/cover identity remains stable, so include the progress checkpoint in the key or
    // the retained card keeps rendering the old percentage until the whole bookshelf is recreated.
    const progressChapterIndex = book.getVariable('readProgressChapterIndex');
    const progressPageCount = book.getVariable('readProgressPageCount');
    return `${prefix}_${book.bookUrl}_pin_${book.isPinned ? '1' : '0'}_` +
      `read_${book.durChapterTime}_${book.durChapterIndex}_${book.durChapterPos}_` +
      `${book.totalChapterNum}_${book.getVariable('readStarted')}_` +
      `badges_${book.getVariable('shelfHasUpdate')}_${book.origin}_${book.originName}_` +
      `${progressChapterIndex}_${progressPageCount}_cover_${this.shelfCoverRenderVersions.get(book.bookUrl) || 0}`;
  }

  openCustomNetworkCoverDialog(): void {
    if (!this.networkCoverTargetBook) return;
    this.customNetworkCoverUrl = this.networkCoverTargetBook.customCoverUrl || '';
    this.showNetworkCoverDialog = false;
    this.openCustomCoverDialog();
  }

  async applyCustomNetworkCover(): Promise<void> {
    const target = this.networkCoverTargetBook;
    const coverUrl = (this.customNetworkCoverUrl || '').trim();
    if (!target) return;
    if (!/^https?:\/\/[^\s]+$/i.test(coverUrl)) {
      HdsFeedback.showToast('请输入有效的 http 或 https 图片链接');
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      const current = await db.getBook(target.bookUrl);
      if (!current) {
        HdsFeedback.showToast('书籍已不在书架中');
        this.closeNetworkCoverPicker();
        return;
      }
      current.customCoverUrl = coverUrl;
      await db.updateBook(current);
      this.applyShelfBookCoverState(current);
      this.closeNetworkCoverPicker();
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('自定义封面已启用');
    } catch (e) {
      console.error('应用自定义封面失败:', e);
      HdsFeedback.showToast('应用自定义封面失败');
    }
  }

  closeNetworkCoverPicker(): void {
    this.cancelNetworkCoverSearch();
    this.showNetworkCoverDialog = false;
    this.closeCustomCoverDialog();
    this.networkCoverTargetBook = null;
    this.networkCoverCandidates = [];
    this.networkCoverStatus = '';
    this.networkCoverSearching = false;
    this.customNetworkCoverUrl = '';
  }

  cancelNetworkCoverSearch(): void {
    this.networkCoverSearchToken++;
    this.networkCoverCoordinator?.cancel();
    this.networkCoverCoordinator = null;
    this.networkCoverSearching = false;
  }

  networkCoverColumnCount(): number {
    const horizontalPadding = 32;
    const targetCardWidth = 108;
    const preferredColumnGap = 8;
    const contentWidth = Math.max(1, this.contextViewportWidth - horizontalPadding);
    const fittedCount = Math.round(
      (contentWidth + preferredColumnGap) / (targetCardWidth + preferredColumnGap)
    );
    return Math.max(3, Math.min(24, fittedCount));
  }

  networkCoverColumnsTemplate(): string {
    const columnCount = this.networkCoverColumnCount();
    let template = '1fr';
    for (let index = 1; index < columnCount; index++) {
      template += ' 1fr';
    }
    return template;
  }

  networkCoverColumnGap(): number {
    const horizontalPadding = 32;
    const targetCardWidth = 108;
    const columnCount = this.networkCoverColumnCount();
    const contentWidth = Math.max(1, this.contextViewportWidth - horizontalPadding);
    const fittedGap = columnCount > 1 ?
      (contentWidth - targetCardWidth * columnCount) / (columnCount - 1) : 8;
    return Math.max(8, Math.min(12, fittedGap));
  }

  networkCoverRowGap(): number {
    return this.networkCoverColumnGap() + 2;
  }

  captureContextMenuAnchor(event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
  }

  updateContextViewport(area: Area): void {
    const width = this.areaDimension(area.width);
    const height = this.areaDimension(area.height);
    if ((width > 0 && Math.abs(width - this.contextViewportWidth) > 1) ||
      (height > 0 && Math.abs(height - this.contextViewportHeight) > 1)) {
      // 旋转或窗口缩放后原卡片坐标失效，安全退回整页淡出，不收向旧位置。
      this.tileGroupHasOrigin = false;
    }
    if (width > 0) {
      this.contextViewportWidth = width;
      this.shelfTileViewportWidth = width;
    }
    if (height > 0) this.contextViewportHeight = height;
  }

  areaDimension(value: Length): number {
    if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  deleteBookCoverCache(book: Book): void {
    const context = getContext(this);
    const covers = [
      ...BookDisplayHelper.decodeCoverList(book.customCoverUrl),
      ...BookDisplayHelper.decodeCoverList(book.coverUrl)
    ];
    for (const cover of covers) {
      BookCoverCache.deleteCachedCover(context, cover);
    }
    const nextMap: Map<string, string> = new Map(this.shelfCoverMap);
    const coverCount = Math.max(1, BookDisplayHelper.getCoverList(book).length);
    for (let i = 0; i < coverCount; i++) {
      const key = this.shelfCoverKey(book, i);
      nextMap.delete(key);
      this.shelfCoverRawUrls.delete(key);
    }
    this.shelfCoverMap = nextMap;
  }

  async refreshShelfCoverCache(books: Book[]): Promise<void> {
    const revision = ++this.shelfCoverCacheRevision;
    this.shelfCoverBookTasks.clear();
    this.pendingShelfCoverUpdates.clear();
    if (this.shelfCoverUpdateTimer >= 0) {
      clearTimeout(this.shelfCoverUpdateTimer);
      this.shelfCoverUpdateTimer = -1;
    }
    // Only warm the initial viewport. Remaining covers are scheduled from coverView.onAppear.
    const initialBooks = books.slice(0, SHELF_COVER_INITIAL_PREFETCH_COUNT);
    const tasks: Promise<void>[] = initialBooks.map(async (book: Book): Promise<void> => {
      const taskKey = `${revision}:${book.bookUrl}`;
      this.shelfCoverBookTasks.add(taskKey);
      try {
        const updates = await this.resolveShelfBookCoverUpdates(book, revision);
        this.queueShelfCoverUpdates(updates, revision);
      } finally {
        this.shelfCoverBookTasks.delete(taskKey);
      }
    });
    try {
      await Promise.all(tasks);
    } catch (e) {
      console.warn('预缓存首屏书架封面失败:', e);
    }
  }

  ensureShelfBookCoverCache(book: Book): void {
    const revision = this.shelfCoverCacheRevision;
    const taskKey = `${revision}:${book.bookUrl}`;
    if (this.shelfCoverBookTasks.has(taskKey)) return;
    this.shelfCoverBookTasks.add(taskKey);
    this.resolveShelfBookCoverUpdates(book, revision)
      .then((updates: Map<string, string>) => this.queueShelfCoverUpdates(updates, revision))
      .catch((e: Error) => console.warn('缓存可见书籍封面失败:', e))
      .finally(() => this.shelfCoverBookTasks.delete(taskKey));
  }

  async resolveShelfBookCoverUpdates(book: Book, revision: number): Promise<Map<string, string>> {
    const updates: Map<string, string> = new Map();
    if (revision !== this.shelfCoverCacheRevision) return updates;
    const covers = CoverGallerySettings.getDisplayCoverList(
      book,
      this.appDarkMode,
      this.bookshelfCoverAlbums,
      this.bookshelfLightCoverAlbumId,
      this.bookshelfDarkCoverAlbumId,
      this.bookshelfCoverApplyScope,
      this.bookshelfCoverTargetBooks,
      this.bookshelfIgnoreSourceCover,
      this.bookshelfCoverMode
    );
    const context = getContext(this);
    for (let i = 0; i < covers.length; i++) {
      if (revision !== this.shelfCoverCacheRevision) return new Map();
      const raw = covers[i];
      if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) continue;
      const key = this.shelfCoverKey(book, i);
      if (this.shelfCoverMap.get(key) && this.shelfCoverRawUrls.get(key) === raw) continue;
      try {
        const local = await BookCoverCache.resolveCachedCoverAsync(context, raw) ||
          await BookCoverCache.resolveCover(context, raw);
        if (revision !== this.shelfCoverCacheRevision) return new Map();
        if (local && local !== raw) {
          this.shelfCoverRawUrls.set(key, raw);
          updates.set(key, local);
        }
      } catch (e) {
        console.warn('缓存书架封面失败:', e);
      }
    }
    return updates;
  }

  queueShelfCoverUpdates(updates: Map<string, string>, revision: number): void {
    if (revision !== this.shelfCoverCacheRevision || updates.size === 0) return;
    updates.forEach((value: string, key: string) => this.pendingShelfCoverUpdates.set(key, value));
    if (this.shelfCoverUpdateTimer >= 0) return;
    this.shelfCoverUpdateTimer = setTimeout(() => {
      this.shelfCoverUpdateTimer = -1;
      if (revision !== this.shelfCoverCacheRevision || this.pendingShelfCoverUpdates.size === 0) return;
      const nextMap = new Map(this.shelfCoverMap);
      this.pendingShelfCoverUpdates.forEach((value: string, key: string) => nextMap.set(key, value));
      this.pendingShelfCoverUpdates.clear();
      this.shelfCoverMap = nextMap;
    }, SHELF_COVER_UPDATE_BATCH_MS);
  }

  /** 标题行收起量，0 为完整显示，CollapsingHeader.DISTANCE 为完全收起；类型页签不收起。 */
  @State shelfHeaderCollapse: number = 0;
  // 顶栏毛玻璃按列表实际滚动距离显现，见 CollapsingHeader.backdropReveal。
  @State shelfHeaderBackdropReveal: number = 0;
  onHeaderCollapseChange: (progress: number) => void = () => {};
  private shelfListScroller: ListScroller = new ListScroller();
  private shelfTileScroller: Scroller = new Scroller();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.tileGroupBackdrop) {
        this.tileGroupBackdropLayer()
      }
      // 分组页和书架各自重建：两页的滚动器与懒加载数据源不共用，返回时才能对准进入前的位置。
      if (this.isTileGroupPage()) {
        Stack() {
          this.shelfPageBody()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.pageColor())
        .scale({ x: this.tileGroupMotionScaleX, y: this.tileGroupMotionScaleY, centerX: 0, centerY: 0 })
        .translate({ x: this.tileGroupMotionTranslateX, y: this.tileGroupMotionTranslateY })
        .borderRadius(this.tileGroupMotionRadius)
        .clip(this.tileGroupBackdrop !== undefined)
        .opacity(this.tileGroupPageOpacity)
      } else {
        this.shelfPageBody()
      }
      if (this.tileGroupBackdrop && this.tileGroupCardShot) {
        this.tileGroupCardLayer()
      }
      if (this.shelfReorderCurtain) {
        // 关书回来挪位时盖着的旧书架截图，在飞行封面下面淡出。
        Image(this.shelfReorderCurtain)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .opacity(this.shelfReorderCurtainOpacity)
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no-hide-descendants')
      }
      if (this.tileGroupFlyers.length > 0) {
        this.tileGroupFlyerLayer()
      }
      if (this.tileGroupCurtain) {
        this.tileGroupCurtainLayer()
      }
      if (this.tileGroupCover) {
        Image(this.tileGroupCover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no-hide-descendants')
      }

      if (this.books.length > 0 && this.shouldShowShelfRefreshStatus()) {
        this.shelfRefreshStatusOverlay()
      }

      // 长按菜单的锚点：放在手指位置的 1×1 节点，弹出层贴着它弹出。
      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showActionDialog, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.bookActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          if (this.showActionDialog) this.closeBookActions();
        }))

      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showBookGroupActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.bookGroupActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          if (this.showBookGroupActionMenu) this.closeBookGroupActionMenu();
        }))

      if (this.isBookMultiSelect) {
        this.bookMultiSelectBar()
      }
      if (this.tileGroupAnimating) {
        // 拦住动画中重复点书或长按，系统返回仍由请求回调排队处理。
        Column().width('100%').height('100%').hitTestBehavior(HitTestMode.Block)
      }
    }
    .width('100%')
    .height('100%')
    .id('bookshelf_motion_root')
    .onAreaChange((_oldValue: Area, newValue: Area) => this.updateContextViewport(newValue))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.showNetworkCoverDialog, this.networkCoverSheet(), this.networkCoverSheetOptions())
  }

  @Builder
  shelfPageBody() {
    Column() {
      // 主题背景图垫在最底层，不占布局、不随列表滚动；下面的列表和网格要用 shelfSurfaceColor 透出它。
      HomeThemeBackdrop()
        .position({ x: 0, y: 0 })

      Column() {
      // 列表上滑时标题行收起：外层按收起量变矮并裁剪，标题行贴底上移并淡出。
      Stack({ alignContent: Alignment.Bottom }) {
        Row() {
          if (this.isTileGroupPage() && !this.isBookMultiSelect) {
            ImmersiveBackButton({
              iconColor: this.primaryTextColor(),
              darkMode: this.appDarkMode,
              buttonSize: 40,
              containerWidth: 56,
              materialScale: 0.83,
              compactLayout: true,
              onBack: () => this.exitTileGroupPage()
            })
            Text(this.activeShelfGroupName())
              .fontSize(AppFontSize.TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Blank()
            Text(this.books.length > 0 ? `${this.books.length}本` : '')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .margin({ right: AppSpacing.MD })
            this.shelfMoreButton()
          } else {
            if (this.isBookMultiSelect) {
              Text('书架')
                .fontSize(AppFontSize.DISPLAY)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
            } else if (!this.isCompanionLayout()) {
              this.shelfGroupSwitcher()
            } else if (this.activeShelfGroupId === -1) {
              // 陪伴布局左上角不放标题，分组改由右侧图标切换；只有“未分组”没有单独的分组页，留个名字说明当前在看什么。
              Text(this.shelfGroupTitle())
                .fontSize(AppFontSize.TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .maxLines(1)
            }

            if (this.isBookMultiSelect) {
              Blank()
              ImmersiveHeaderAction({
                label: '取消',
                accessibilityLabel: '退出多选',
                onTap: () => this.exitBookMultiSelect()
              })
            } else {
              Blank()

              if (this.isCompanionLayout()) {
                this.shelfGroupButton()
              }
              if (this.bookshelfTypeCategoryEnabled) {
                this.shelfCategoryButton()
              }
              this.shelfFilterButton()
              this.shelfMoreButton()
            }
          }
        }
        .width('100%')
        .height(56 + this.statusBarHeight)
        .padding({
          left: this.isTileGroupPage() && !this.isBookMultiSelect ? 0 : AppSpacing.XL,
          right: AppSpacing.XL,
          top: this.statusBarHeight
        })
        .alignItems(VerticalAlign.Center)
        .opacity(CollapsingHeader.contentOpacity(this.shelfHeaderCollapseValue()))
        .hitTestBehavior(CollapsingHeader.acceptsTouch(this.shelfHeaderCollapseValue()) ? HitTestMode.Default : HitTestMode.None)
        // 标题栏里的按钮各自响应单击，双击只在空白处和标题文字上生效。
        .gesture(TapGesture({ count: 2 }).onAction(() => this.toggleShelfPrivateByHeaderDoubleTap()))
      }
      .width('100%')
      .height(56 + this.statusBarHeight - this.shelfHeaderCollapseValue())
      .clip(!this.shelfCategoryAnimating)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.onHeaderCollapseChange((56 + this.statusBarHeight - Number(newArea.height)) /
          CollapsingHeader.DISTANCE);
      })

      if (this.shelfSearchActive) {
        this.shelfSearchBar()
      }

      if (this.showsShelfScopeTabs() && this.shelfCategoryExpanded) {
        this.shelfScopeTabs()
      }

      if (this.isBookMultiSelect) {
        this.bookSelectionStatusBar()
      }

      }
      .width('100%')
      .position({ x: 0, y: 0 })
      .zIndex(5)

      if (this.showsShelfScopeTabs()) {
        ShelfCategoryMaterial({
          expanded: this.shelfCategoryExpanded,
          viewportWidth: this.contextViewportWidth,
          side: AppSpacing.XL,
          top: this.statusBarHeight + 56 +
            (this.shelfSearchActive ? BookshelfPage.SEARCH_BAR_HEIGHT + AppSpacing.MD : 0),
          buttonTop: this.statusBarHeight + 8,
          darkMode: this.appDarkMode, surfaceColor: this.cardColor(), accentColor: this.accentGlowColor(),
          touching: this.shelfScopeTabsTouching && this.shelfCategoryExpanded,
          touchX: this.shelfScopeTabsTouchX, touchY: this.shelfScopeTabsTouchY
        }).position({ x: 0, y: 0 })
          .translate({ y: -this.shelfHeaderCollapseValue() })
          .opacity(this.shelfCategoryExpanded ? 1 : CollapsingHeader.contentOpacity(this.shelfHeaderCollapseValue()))
          .zIndex(4)
      }

      HeaderBackdrop({ backdropHeight: this.shelfHeaderBackdropHeight(),
        statusBarHeight: this.statusBarHeight,
        backdropColor: ThemeRuntime.topBarColor(this.appDarkMode),
        reveal: ThemeRuntime.homeBackdrop(this.appDarkMode) ? this.shelfHeaderBackdropReveal : 1 })
        .width('100%')
        .position({ x: 0, y: 0 })
        .zIndex(3)

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
          Text('加载中...')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .margin({ top: AppSpacing.MD })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.bookshelfTopOverlayHeight() })
        .justifyContent(FlexAlign.Center)

      } else {
        CategorySwipePager({
          pageKeys: this.shelfPageOrder(),
          selectedIndex: Math.max(0, this.shelfPageOrder().indexOf(this.shelfPageKey())),
          swipeEnabled: !this.isBookMultiSelect && !this.isTileGroupPage(),
          swipeExcludedGestureTag: 'recentReadCarouselPan',
          canSelect: (key: string): boolean => this.canSelectShelfPage(key),
          onSelect: (key: string): void => this.setShelfPage(key),
          onSettled: (): void => {
            if (this.shelfScope !== 'private') this.privateShelfRevealed = false;
          },
          onSwipe: (): void => this.markShelfScopePanGesture(240),
          pageContent: (key: string) => { this.shelfCategoryContent(key); }
        })
        .translate({ x: this.shelfScopeTransitionX })
        .scale({ x: this.shelfScopeTransitionScale, y: this.shelfScopeTransitionScale })
        .opacity(this.shelfScopeTransitionOpacity)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.shelfContentTouching = true;
        this.prewarmShelfOpeningBackdrop();
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.shelfContentTouching = false;
        if (this.privateShelfBiometricQueued) {
          this.privateShelfBiometricQueued = false;
          this.startPrivateShelfBiometricUnlock(false);
        }
      }
    })
    .bindSheet(this.showBookGroupPicker, this.bookGroupPickerDialog(), this.bookGroupPickerSheetOptions())
    // 不要给整页加消失转场：切到分组页时旧书架会多留一两帧，而且已经换成了分组的书，整屏闪一下。
    // 展开/收回期间的背景由截图负责。
  }

  @Builder
  tileGroupBackdropLayer() {
    Stack() {
      // 截图必须和页面切换同一帧画出来，异步加载会晚一两帧，露出下面正在重建、封面还空着的页面。
      Image(this.tileGroupBackdrop)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)
        .syncLoad(true)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(this.tileGroupScrimOpacity)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  /** 打开时的卡片截图：和分组页同一套缩放平移，切页前就挂在原卡片上（看上去没变化），之后随页面长大并淡出。 */
  @Builder
  tileGroupCardLayer() {
    Image(this.tileGroupCardShot)
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Fill)
      .syncLoad(true)
      // 卡片是半透明玻璃底，单独截下来也是半透明的；垫上书架底色才和书架上看到的一样，不然一盖上去就透出下面的内容。
      .backgroundColor(this.pageColor())
      .scale({ x: this.tileGroupMotionScaleX, y: this.tileGroupMotionScaleY, centerX: 0, centerY: 0 })
      .translate({ x: this.tileGroupMotionTranslateX, y: this.tileGroupMotionTranslateY })
      .borderRadius(this.tileGroupMotionRadius)
      .clip(true)
      .opacity(this.tileGroupCardOpacity)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  tileGroupFlyerLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.tileGroupFlyers, (flyer: TileGroupFlyer) => {
        Stack() {
          if (flyer.cover) {
            Image(flyer.cover)
              .width('100%')
              .height('100%')
              .objectFit(flyer.fill ? ImageFit.Fill : ImageFit.Cover)
              .syncLoad(true)
              .draggable(false)
          } else {
            Text(flyer.initial)
              .fontSize(28)
              .fontColor('#FFFFFF')
          }
        }
        .width(flyer.width)
        .height(flyer.height)
        .backgroundColor(flyer.color)
        .borderRadius(8)
        .clip(true)
        .position({ x: 0, y: 0 })
        .scale({ x: this.tileGroupFlyValue(flyer.fromScaleX, flyer.toScaleX),
          y: this.tileGroupFlyValue(flyer.fromScaleY, flyer.toScaleY), centerX: 0, centerY: 0 })
        .translate({ x: this.tileGroupFlyValue(flyer.fromX, flyer.toX), y: this.tileGroupFlyValue(flyer.fromY, flyer.toY) })
      }, (flyer: TileGroupFlyer): string => flyer.key)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  tileGroupCurtainLayer() {
    Stack() {
      Image(this.tileGroupCurtain)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)
        .syncLoad(true)
      if (this.tileGroupCardShot) {
        Image(this.tileGroupCardShot)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .backgroundColor(this.pageColor())
          .opacity(this.tileGroupCardOpacity)
      }
    }
    .width('100%')
    .height('100%')
    .scale({ x: this.tileGroupMotionScaleX, y: this.tileGroupMotionScaleY, centerX: 0, centerY: 0 })
    .translate({ x: this.tileGroupMotionTranslateX, y: this.tileGroupMotionTranslateY })
    .borderRadius(this.tileGroupMotionRadius)
    .clip(true)
    .opacity(this.tileGroupPageOpacity)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  /** 换源：系统对话框，API 26+ 是沉浸光感表面。 */
  @Builder
  changeSourceDialogContent() {
    BookChangeSourceDialog({
      targetBook: this.shelfChangeSourceTarget,
      onSwitched: (switched: Book): void => {
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        this.loadBooks();
      },
      onClosed: (): void => {
        this.showShelfChangeSourceDialog = false;
        this.shelfChangeSourceTarget = null;
      }
    })
  }

  syncChangeSourceDialog(): void {
    this.changeSourceDialogSession.sync(this.getUIContext(), this.showShelfChangeSourceDialog, (): void => {
      this.changeSourceDialogContent();
    }, {
      autoCancel: true,
      onDismiss: (): void => { this.showShelfChangeSourceDialog = false; },
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示换源弹窗失败:'
    });
  }

  /** 标题即分组切换：显示当前分组名，点开下拉选分组，旁边是当前视图的本数。 */
  @Builder
  shelfCategoryContent(pageKey: string) {
    if (this.shelfBooksForPage(pageKey).length === 0) {
          Column() {
            SymbolGlyph($r('sys.symbol.bookshelf'))
              .fontSize(56)
              .fontColor([this.subTextColor()])
              .opacity(0.5)
              .margin({ bottom: AppSpacing.XL })
            Text('暂无书籍')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.subTextColor())
            Text(this.shelfScopeEmptyHint(pageKey))
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .margin({ top: AppSpacing.MD })
          }
          .width('100%')
          .height('100%')
          .padding({ top: this.bookshelfTopOverlayHeight() })
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.isShelfRefreshing, builder: this.shelfRefreshBuilder }) {
            if (this.isTileLayout()) {
              this.shelfTileGrid(pageKey)
            } else {
              List({ scroller: this.shelfListScrollerForPage(pageKey), space: AppSpacing.MD }) {
              ListItem() {
                Row()
                  .height(this.bookshelfTopOverlayHeight())
              }

              LazyForEach(this.shelfListBookDataSource(pageKey), (book: Book) => {
                ListItem() {
                  Row() {
                    if (this.isBookMultiSelect) {
                      Toggle({ type: ToggleType.Checkbox, isOn: this.isBookSelected(book.bookUrl) })
                        .selectedColor(this.buttonColor())
                        .margin({ right: AppSpacing.LG })
                        .onChange((isOn: boolean) => {
                          this.setBookSelected(book.bookUrl, isOn);
                        })
                    }
                    Column() {
                      if (this.isCompactLayout()) {
                        this.compactBookContent(book, pageKey)
                      } else {
                        this.looseBookContent(book, pageKey)
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .backgroundColor(this.glassCardColor())
                    .borderRadius(ThemeRuntime.mediumRadius())
                    .clip(true)
                    .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
                    .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
                    .gesture(
                      LongPressGesture({ repeat: false })
                        .onAction((event: GestureEvent) => {
                          if (!this.isBookMultiSelect) {
                            this.showBookActions(book, event);
                          }
                        })
                    )
                    .onClick((event: ClickEvent) => {
                      if (this.consumeShelfSwipeClick()) {
                        return;
                      }
                      if (this.isBookMultiSelect) {
                        this.toggleSelectedBook(book.bookUrl);
                        return;
                      }
                      this.openShelfBook(book, event.windowX, event.windowY);
                    })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
              }, (book: Book) => this.shelfBookRenderKey(book, `list_${pageKey}`))

              ListItem() {
                Column()
                  .height(this.bookshelfListBottomInset())
              }
            }
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .width('100%')
            .height('100%')
            .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
            .backgroundColor(this.shelfSurfaceColor())
            .onAppear(() => this.restoreShelfPageScroll(pageKey, false))
            .onDidScroll((delta: number) => {
              if (pageKey === this.shelfPageKey()) {
                const page = this.shelfCategoryPage(pageKey);
                page.listOffset = page.listScroller.currentOffset().yOffset;
                this.onShelfListScroll(delta, page.listOffset);
              }
            })
            .onScrollStop(() => {
              if (pageKey === this.shelfPageKey()) this.onShelfListScrollStop(this.shelfListScrollerForPage(pageKey).currentOffset().yOffset);
            })
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
            }
          }
          .layoutWeight(1)
          .backgroundColor(this.shelfSurfaceColor())
          .refreshOffset(64)
          .onStateChange((state: RefreshStatus) => {
            if (pageKey === this.shelfPageKey()) this.updateShelfRefreshPrompt(state);
          })
          .onOffsetChange((offset: number) => {
            if (pageKey === this.shelfPageKey()) this.trackShelfRefreshPullOffset(offset);
          })
          .onRefreshing(() => {
            if (pageKey === this.shelfPageKey()) this.refreshBookshelfToc();
          })
        }
  }

  @Builder
  shelfGroupSwitcher() {
    Row({ space: AppSpacing.XS }) {
      Text(this.shelfGroupTitle())
        .fontSize(AppFontSize.DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
      SymbolGlyph(this.showShelfGroupMenu ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.showShelfGroupMenu ? this.accentColor() : this.secondaryTextColor()])
      Text(this.shelfHeaderCountText())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
        .maxLines(1)
        .margin({ left: AppSpacing.XS })
    }
    // 窄屏上右侧按钮放不下时，标题这一段先收缩（分组名省略）。
    .flexShrink(1)
    .height(44)
    .alignItems(VerticalAlign.Center)
    .bindPopup(this.showShelfGroupMenu, this.shelfMenuPopupOptions((): void => {
      this.shelfGroupDropdown()
    }, Placement.BottomLeft, () => {
      this.showShelfGroupMenu = false;
    }))
    .accessibilityText(`${this.shelfGroupTitle()}，切换分组`)
    .onClick(() => {
      this.showShelfGroupMenu = !this.showShelfGroupMenu;
      this.showShelfMoreMenu = false;
      this.showShelfFilterMenu = false;
    })
  }

  /** 陪伴布局右侧的分组图标，弹出与标题下拉相同的分组菜单。 */
  @Builder
  shelfGroupButton() {
    Row() {
      this.shelfHeaderCircleButton($r('sys.symbol.folder'), this.showShelfGroupMenu || this.activeShelfGroupId !== 0,
        `切换分组，当前${this.shelfGroupTitle()}`, () => {
          this.showShelfGroupMenu = !this.showShelfGroupMenu;
          this.showShelfMoreMenu = false;
          this.showShelfFilterMenu = false;
        })
    }
    .margin({ right: 10 })
    .bindPopup(this.showShelfGroupMenu, this.shelfMenuPopupOptions((): void => {
      this.shelfGroupDropdown()
    }, Placement.BottomRight, () => {
      this.showShelfGroupMenu = false;
    }))
  }

  shelfGroupTitle(): string {
    if (this.activeShelfGroupId === 0) {
      return '书架';
    }
    if (this.activeShelfGroupId === -1) {
      return '未分组';
    }
    return this.activeShelfGroupName();
  }

  @Builder
  shelfGroupDropdown() {
    Column() {
      Scroll() {
        Column({ space: AppSpacing.XXS }) {
          this.shelfGroupMenuItem('全部书籍', 0)
          ForEach(this.shelfGroups, (group: BookGroup) => {
            this.shelfGroupMenuItem(group.groupName, group.groupId, group)
          }, (group: BookGroup) => `${group.groupId}_${group.groupName}`)
          this.shelfGroupMenuItem('未分组', -1)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.appDarkMode))
        .margin({ top: AppSpacing.XS, bottom: AppSpacing.XS, left: 12, right: 12 })

      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([this.accentColor()])
        Text('新建分组')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.accentColor())
      }
      .width('100%')
      .height(BookshelfPage.MENU_ITEM_HEIGHT)
      .padding({ left: 12, right: 12 })
      .borderRadius(this.shelfMenuItemRadius())
      .onClick(() => {
        this.showShelfGroupMenu = false;
        this.openAddBookGroupDialog();
      })

      if (this.shelfGroups.length > 0) {
        Text('长按分组可重命名或删除')
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .padding({ left: 12, top: AppSpacing.XXS, bottom: AppSpacing.XS })
      }
    }
    .width(220)
    .padding(BookshelfPage.MENU_PADDING)
  }

  @Builder
  shelfGroupMenuItem(label: string, groupId: number, group?: BookGroup) {
    Row({ space: AppSpacing.SM }) {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.activeShelfGroupId === groupId ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.activeShelfGroupId === groupId ? this.accentColor() : this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`${this.shelfGroupBookCount(groupId)}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
      if (this.activeShelfGroupId === groupId) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(BookshelfPage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.shelfMenuItemRadius())
    .backgroundColor(this.activeShelfGroupId === groupId ? this.selectedSoftBackgroundColor() : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.showShelfGroupMenu = false;
      this.selectShelfGroup(groupId);
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (!group) {
            return;
          }
          this.captureContextMenuAnchor(event);
          this.showShelfGroupMenu = false;
          this.pendingBookGroup = group;
          this.showBookGroupActionMenu = true;
        })
    )
  }

  /** 菜单里每个分组的本数：只看当前是普通还是隐私书架，不受类型和筛选影响。 */
  shelfGroupBookCount(groupId: number): number {
    const privateScope = this.shelfScope === 'private';
    let count = 0;
    for (const book of this.allBooks) {
      if (book.isPrivate !== privateScope) continue;
      if (groupId === 0 || (groupId === -1 ? book.group <= 0 : book.group === groupId)) {
        count++;
      }
    }
    return count;
  }

  @Builder
  bookSelectionStatusBar() {
    Row() {
      Text(this.areAllBooksSelected() ? '☑' : '☐')
        .fontSize(AppFontSize.TITLE)
        .fontColor(this.accentColor())
        .width(28)
        .textAlign(TextAlign.Center)
        .onClick(() => this.toggleAllBooks())

      Text(`已选择 ${this.selectedBookUrls.length}/${this.books.length}`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .margin({ left: AppSpacing.MD })
        .layoutWeight(1)

      Text(this.areAllBooksSelected() ? '取消全选' : '全选')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .padding({ left: AppSpacing.LG, right: AppSpacing.XS, top: AppSpacing.MD, bottom: AppSpacing.MD })
        .onClick(() => this.toggleAllBooks())
    }
    .width('100%')
    .height(42)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  bookMultiSelectBar() {
    Row({ space: 10 }) {
      Button('删除', { type: ButtonType.Normal })
        .layoutWeight(1)
        .height(42)
        .fontSize(AppFontSize.BODY)
        .borderRadius(ThemeRuntime.buttonRadius())
        .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .fontColor(ThemeRuntime.onAccentColor())
        .enabled(this.selectedBookUrls.length > 0)
        .onClick(() => {
          if (this.selectedBookUrls.length > 0) this.openBatchDeleteDialog();
        })
      Button('分组', { type: ButtonType.Normal })
        .layoutWeight(1)
        .height(42)
        .fontSize(AppFontSize.BODY)
        .borderRadius(ThemeRuntime.buttonRadius())
        .backgroundColor(this.buttonColor())
        .fontColor(ThemeRuntime.onAccentColor())
        .enabled(this.selectedBookUrls.length > 0)
        .onClick(() => {
          if (this.selectedBookUrls.length > 0) {
            this.groupPickerSingleBookUrl = '';
            this.showBookGroupPicker = true;
          }
        })
      Button('更多', { type: ButtonType.Normal })
        .layoutWeight(1)
        .height(42)
        .fontSize(AppFontSize.BODY)
        .borderRadius(ThemeRuntime.buttonRadius())
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .enabled(this.selectedBookUrls.length > 0)
        .onClick(() => {
          if (this.selectedBookUrls.length > 0) this.showMultiSelectMoreMenu = true;
        })
        .bindPopup(this.isBookMultiSelect && this.showMultiSelectMoreMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.multiSelectMoreMenu()
        }, Placement.TopRight, this.appDarkMode, this.accentColor(), () => {
          this.showMultiSelectMoreMenu = false;
        }))
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: 10, bottom: this.multiSelectBottomPadding() })
    .backgroundColor(this.glassCardColor())
    .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
    .alignSelf(ItemAlign.End)
  }

  /** 多选底栏“更多”菜单：系统菜单贴着按钮向上弹出。 */
  @Builder
  multiSelectMoreMenu() {
    Scroll() {
      Column() {
        if (this.privateShelfEnabled) {
          this.contextActionItem(this.shelfScope === 'private' ? $r('sys.symbol.lock_open') : $r('sys.symbol.lock'),
            this.shelfScope === 'private' ? '取消隐私' : '标记为隐私', this.primaryTextColor(), () => {
              this.showMultiSelectMoreMenu = false;
              this.setSelectedBooksPrivate(this.shelfScope !== 'private');
            })
        }
        // 选中的书里没有本地书籍时置灰且不可点。
        this.contextActionItem($r('sys.symbol.arrow_right_up_and_square'), '保存源文件',
          this.selectedLocalBooks().length > 0 ? this.primaryTextColor() : this.subTextColor(), () => {
            if (this.selectedLocalBooks().length === 0) return;
            this.showMultiSelectMoreMenu = false;
            this.openBatchExportDialog();
          })

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  /** 书籍长按菜单：系统菜单，API 26+ 挂沉浸光感材质。 */
  @Builder
  bookActionMenu() {
    Scroll() {
      Column() {
        if (this.pendingActionBook) {
          this.contextActionItem($r('sys.symbol.info_circle'), '查看书籍详情', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              const book = this.pendingActionBook;
              this.closeBookActions();
              this.openShelfBookDetail(book);
            }
          })
          this.contextActionItem($r('sys.symbol.pin'), this.pendingActionBook.isPinned ? '取消置顶' : '置顶',
            this.primaryTextColor(), () => {
              if (this.pendingActionBook) {
                const book = this.pendingActionBook;
                this.closeBookActions();
                this.toggleBookPinned(book);
              }
            })
          if (!LocalBookService.isLocalBook(this.pendingActionBook)) {
            this.contextActionItem($r('sys.symbol.arrow_left_arrow_right'), '换源', this.primaryTextColor(), () => {
              if (this.pendingActionBook) {
                const book = this.pendingActionBook;
                this.closeBookActions();
                this.openShelfChangeSource(book);
              }
            })
          }
          if (!LocalBookService.isLocalBook(this.pendingActionBook)) {
            this.contextActionItem($r('sys.symbol.download'), '缓存', this.primaryTextColor(), () => {
              if (this.pendingActionBook) {
                const book = this.pendingActionBook;
                this.showActionDialog = false;
                setTimeout(() => {
                  this.openCacheDialog(book);
                }, 0);
              }
            })
          }
          this.contextActionItem($r('sys.symbol.picture_badge_arrow_down'), '获取网络封面', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              const book = this.pendingActionBook;
              this.showActionDialog = false;
              this.pendingActionBook = null;
              this.openNetworkCoverPicker(book);
            }
          })
          if (this.pendingActionBook.customCoverUrl) {
            this.contextActionItem($r('sys.symbol.minus_circle'), '恢复默认封面',
              this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  const book = this.pendingActionBook;
                  this.closeBookActions();
                  this.restoreDefaultBookCover(book);
                }
              })
          }
          if (LocalBookService.isLocalBook(this.pendingActionBook)) {
            this.contextActionItem($r('sys.symbol.square_and_pencil'), '编辑书籍信息',
              this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  this.editingBookName = this.pendingActionBook.name;
                  this.editingBookAuthor = this.pendingActionBook.author;
                  this.showActionDialog = false;
                  this.openEditBookInfoDialog();
                }
              })
          }
          if (LocalBookService.isLocalBook(this.pendingActionBook)) {
            this.contextActionItem($r('sys.symbol.arrow_right_up_and_square'), '保存源文件',
              this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  const book = this.pendingActionBook;
                  this.showActionDialog = false;
                  setTimeout(() => {
                    this.saveLocalBookSource(book);
                  }, 0);
                }
              })
          }
          this.contextActionItem($r('sys.symbol.folder'), '移动分组', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              const bookUrl = this.pendingActionBook.bookUrl;
              this.showActionDialog = false;
              this.pendingActionBook = null;
              this.groupPickerSingleBookUrl = bookUrl;
              this.showBookGroupPicker = true;
            }
          })
          if (this.privateShelfEnabled) {
            this.contextActionItem(this.pendingActionBook.isPrivate ? $r('sys.symbol.lock_open') : $r('sys.symbol.lock'),
              this.pendingActionBook.isPrivate ? '取消隐私' : '标记为隐私', this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  const book = this.pendingActionBook;
                  this.closeBookActions();
                  this.toggleBookPrivate(book);
                }
              })
          }
          this.contextActionItem($r('sys.symbol.bookmark'), '自定义标签', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              this.editingTags = BookDisplayHelper.getBookTags(this.pendingActionBook);
              this.tagInput = '';
            }
            this.showActionDialog = false;
            this.openTagDialog();
          })
          this.contextActionItem($r('sys.symbol.checkmark_circle'), '多选', this.primaryTextColor(), () => {
            if (this.pendingActionBook) {
              const bookUrl = this.pendingActionBook.bookUrl;
              this.closeBookActions();
              this.enterBookMultiSelect(bookUrl);
            }
          })
          this.contextActionItem($r('sys.symbol.trash'), '移出书架', ThemeRuntime.dangerColor(this.appDarkMode), () => {
            if (this.pendingActionBook) {
              const book = this.pendingActionBook;
              this.closeBookActions();
              this.showDeleteConfirm(book);
            }
          })
        }

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  /** 获取网络封面：半模态弹层，API 26+ 挂沉浸光感材质。 */
  @Builder
  networkCoverSheet() {
    Column() {
      Row() {
        Column() {
          Text('获取网络封面')
            .fontSize(AppFontSize.SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(`《${this.networkCoverTargetBook?.name || ''}》`)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: AppSpacing.MD }) {
          Button('自定义链接')
            .height(36)
            .fontSize(AppFontSize.CAPTION)
            .backgroundColor(this.buttonColor())
            .fontColor(ThemeRuntime.onAccentColor())
            .onClick(() => this.openCustomNetworkCoverDialog())
          Button('取消')
            .height(36)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeNetworkCoverPicker())
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: AppSpacing.MD }) {
        if (this.networkCoverSearching) {
          LoadingProgress()
            .width(18)
            .height(18)
        }
        Text(this.networkCoverStatus || '正在准备搜索...')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(2)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: AppSpacing.LG, bottom: 10 })

      if (this.networkCoverCandidates.length === 0 && !this.networkCoverSearching) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(42)
            .fontColor([this.subTextColor()])
          Text('未找到可用的网络封面')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.secondaryTextColor())
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.networkCoverCandidates, (candidate: SearchBook) => {
            GridItem() {
              Column() {
                Stack() {
                  Column() {
                    Text((candidate.name || '书').substring(0, 1))
                      .fontSize(28)
                      .fontColor('#FFFFFF')
                  }
                  .width('100%')
                  .aspectRatio(0.72)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(this.accentColor())

                  Image(this.imageCover(candidate.coverUrl))
                    .width('100%')
                    .height('100%')
                    .objectFit(ImageFit.Cover)
                }
                .width('100%')
                .aspectRatio(0.72)
                .borderRadius(7)
                .clip(true)
                .backgroundColor(this.inputColor())

                Text(candidate.name || '未知书名')
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(this.primaryTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: AppSpacing.SM })
                Text(candidate.originName || candidate.author || '启用书源')
                  .fontSize(AppFontSize.MICRO)
                  .fontColor(this.subTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: AppSpacing.XXS })
              }
              .width('100%')
              .padding(5)
              .borderRadius(ThemeRuntime.mediumRadius())
              .backgroundColor(this.glassCardColor())
              .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
              .onClick(() => this.applyNetworkCover(candidate))
            }
          }, (candidate: SearchBook) => candidate.coverUrl)
          GridItem() {
            Column()
              .height(68)
          }
          .columnStart(0)
          .columnEnd(this.networkCoverColumnCount() - 1)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .columnsTemplate(this.networkCoverColumnsTemplate())
        .columnsGap(this.networkCoverColumnGap())
        .rowsGap(this.networkCoverRowGap())
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: Math.max(this.navBarHeight, 12) + 12 })
  }

  networkCoverSheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      detents: ['72%', SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      // 只有下滑、点遮罩或返回才走这里；切到自定义链接弹窗是页面主动收起，不清空目标书籍。
      onWillDismiss: (): void => this.closeNetworkCoverPicker(),
      onWillSpringBackWhenDismiss: (): void => {}
    }, this.appDarkMode, this.accentColor());
  }

  /** 移动到分组：内容高度的半模态弹层。 */
  bookGroupPickerSheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      onWillDismiss: (): void => this.closeBookGroupPicker(),
      onWillSpringBackWhenDismiss: (): void => {}
    }, this.appDarkMode, this.accentColor());
  }

  @Builder
  batchExportDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('保存源文件').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      Text(`只能保存本地书籍的源文件，缓存书籍无法保存。将导出选中的 ${this.selectedLocalBooks().length} 本本地书籍。`)
        .fontSize(AppFontSize.BODY).fontColor(this.secondaryTextColor()).textAlign(TextAlign.Center)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeBatchExportDialog())
        Button('确认', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.buttonColor()).fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.closeBatchExportDialog();
            this.exportSelectedLocalBooks();
          })
      }.width('100%')
    }
    .padding(22)
  }

  openBatchExportDialog(): void {
    this.batchExportDialogSession.open(this.getUIContext(), (): void => {
      this.batchExportDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示保存源文件弹窗失败:'
    });
  }

  closeBatchExportDialog(): void {
    this.batchExportDialogSession.close(this.getUIContext());
  }

  @Builder
  bookGroupPickerDialog() {
    Column({ space: AppSpacing.SM }) {
      Text('移动到分组')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .height(32)
        .textAlign(TextAlign.Center)
      Scroll() {
        Column({ space: AppSpacing.XS }) {
          this.bookGroupPickerItem('未分组', 0)
          ForEach(this.shelfGroups, (group: BookGroup) => {
            this.bookGroupPickerItem(group.groupName, group.groupId)
          }, (group: BookGroup) => `picker_${group.groupId}`)
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
  bookGroupPickerItem(label: string, groupId: number) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.primaryTextColor())
      .width('100%')
      .height(38)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(this.glassCardColor())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .onClick(() => this.assignSelectedBooksToGroup(groupId))
  }

  @Builder
  addBookGroupDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('新增书籍分组').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      TextInput({ placeholder: '输入分组名称', text: this.newBookGroupName })
        .width('100%').height(42).backgroundColor(this.inputColor()).fontColor(this.primaryTextColor())
        .borderRadius(ThemeRuntime.mediumRadius()).onChange((value: string) => this.newBookGroupName = value)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeAddBookGroupDialog())
        Button('新增', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.buttonColor()).fontColor(ThemeRuntime.onAccentColor()).enabled(!!this.newBookGroupName.trim())
          .onClick(() => this.addShelfBookGroup())
      }.width('100%')
    }    .padding(22)
  }

  openAddBookGroupDialog(): void {
    this.newBookGroupName = '';
    this.showAddBookGroupDialog = true;
    this.addBookGroupDialogSession.open(this.getUIContext(), (): void => {
      this.addBookGroupDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示新增分组弹窗失败:'
    });
  }

  closeAddBookGroupDialog(): void {
    this.showAddBookGroupDialog = false;
    this.addBookGroupDialogSession.close(this.getUIContext());
  }


  @Builder
  bookGroupActionMenu() {
    Scroll() {
      Column() {
        this.contextActionItem($r('sys.symbol.square_and_pencil'), '重命名', this.primaryTextColor(), () => {
          this.renameBookGroupName = this.pendingBookGroup?.groupName || '';
          this.showBookGroupActionMenu = false;
          this.openRenameBookGroupDialog();
        })
        this.contextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
          this.pendingDeleteBookGroup = this.pendingBookGroup;
          this.showBookGroupActionMenu = false;
          this.openDeleteBookGroupDialog();
        })

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  renameBookGroupDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('重命名分组').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      TextInput({ placeholder: '输入分组名称', text: this.renameBookGroupName })
        .width('100%').height(42).backgroundColor(this.inputColor()).fontColor(this.primaryTextColor())
        .borderRadius(ThemeRuntime.mediumRadius()).onChange((value: string) => this.renameBookGroupName = value)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeRenameBookGroupDialog())
        Button('保存', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.buttonColor()).fontColor(ThemeRuntime.onAccentColor()).enabled(!!this.renameBookGroupName.trim())
          .onClick(() => this.renameShelfBookGroup())
      }.width('100%')
    }    .padding(22)
  }

  openRenameBookGroupDialog(): void {
    this.showRenameBookGroupDialog = true;
    this.renameBookGroupDialogSession.open(this.getUIContext(), (): void => {
      this.renameBookGroupDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示重命名分组弹窗失败:'
    });
  }


  @Builder
  deleteBookGroupDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('删除分组').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      Text(`删除“${this.pendingDeleteBookGroup?.groupName || ''}”后，分组内书籍将移到未分组。`)
        .fontSize(AppFontSize.BODY).fontColor(this.secondaryTextColor()).textAlign(TextAlign.Center)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeDeleteBookGroupDialog())
        Button('删除', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode)).fontColor(ThemeRuntime.onAccentColor()).onClick(() => this.deleteShelfBookGroup())
      }.width('100%')
    }    .padding(22)
  }

  openDeleteBookGroupDialog(): void {
    this.showDeleteBookGroupDialog = true;
    this.deleteBookGroupDialogSession.open(this.getUIContext(), (): void => {
      this.deleteBookGroupDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示删除分组弹窗失败:'
    });
  }


  @Builder
  batchDeleteBooksDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('批量删除').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      Text(`确定从书架移除选中的 ${this.selectedBookUrls.length} 本书吗？`)
        .fontSize(AppFontSize.BODY).fontColor(this.secondaryTextColor()).textAlign(TextAlign.Center)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeBatchDeleteDialog())
        Button('删除', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode)).fontColor(ThemeRuntime.onAccentColor()).onClick(() => this.deleteSelectedBooks())
      }.width('100%')
    }    .padding(22)
  }

  openBatchDeleteDialog(): void {
    this.showBatchDeleteDialog = true;
    this.batchDeleteDialogSession.open(this.getUIContext(), (): void => {
      this.batchDeleteBooksDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示批量删除弹窗失败:'
    });
  }

  closeBatchDeleteDialog(): void {
    this.showBatchDeleteDialog = false;
    this.batchDeleteDialogSession.close(this.getUIContext());
  }

  @Builder
  deleteBookDialogContent() {
    Column() {
      Text('确认删除')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.LG })

      Text(`确定要将《${this.pendingDeleteBook?.name || ''}》从书架移除吗？`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.XXL })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeDeleteBookDialog())

        Button('删除')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            if (this.pendingDeleteBook) {
              const book = this.pendingDeleteBook;
              this.closeDeleteBookDialog();
              this.pendingDeleteBook = null;
              this.deleteBook(book);
            }
          })
      }
      .width('100%')
    }
    .padding(AppSpacing.XXXL)
  }

  openDeleteBookDialog(): void {
    this.showDeleteDialog = true;
    this.deleteBookDialogSession.open(this.getUIContext(), (): void => {
      this.deleteBookDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示删除确认弹窗失败:'
    });
  }

  closeDeleteBookDialog(): void {
    this.showDeleteDialog = false;
    this.deleteBookDialogSession.close(this.getUIContext());
  }

  @Builder
  editBookInfoDialogContent() {
    Column() {
      Text('编辑书籍信息')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 18 })

      Text('书名')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .margin({ bottom: AppSpacing.SM })

      TextInput({ placeholder: '请输入书名', text: this.editingBookName })
        .width('100%')
        .height(44)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.editingBookName = value;
        })

      Text('作者')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .margin({ top: 14, bottom: AppSpacing.SM })

      TextInput({ placeholder: '请输入作者（可留空）', text: this.editingBookAuthor })
        .width('100%')
        .height(44)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.editingBookAuthor = value;
        })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeEditBookInfoDialog())

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(!!this.editingBookName.trim())
          .opacity(this.editingBookName.trim() ? 1 : 0.45)
          .onClick(() => this.saveLocalBookInfo())
      }
      .width('100%')
      .margin({ top: 22 })
    }
    .padding(AppSpacing.XXL)
  }

  openEditBookInfoDialog(): void {
    this.showEditBookInfoDialog = true;
    this.editBookInfoDialogSession.open(this.getUIContext(), (): void => {
      this.editBookInfoDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示编辑书籍信息弹窗失败:'
    });
  }

  @Builder
  tagDialogContent() {
    Column() {
      Text('自定义标签')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 14 })

      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.editingTags, (tag: string, index: number) => {
            Row() {
              Text(tag)
                .fontSize(AppFontSize.BODY)
                .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
              Text('×')
                .fontSize(AppFontSize.BODY)
                .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
                .margin({ left: AppSpacing.SM })
            }
            .padding({ left: 10, right: AppSpacing.MD, top: 5, bottom: 5 })
            .attributeModifier(BookDisplayHelper.getTagModifier(index, this.appDarkMode))
            .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
            .onClick(() => {
              this.removeEditingTag(tag);
            })
          })
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .width('100%')
      .constraintSize({ minHeight: 40, maxHeight: 220 })
      .margin({ bottom: AppSpacing.LG })

      Row() {
        TextInput({ placeholder: '输入标签', text: this.tagInput })
          .height(40)
          .layoutWeight(1)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.tagInput = value;
          })

        Button('添加')
          .height(40)
          .margin({ left: AppSpacing.MD })
          .onClick(() => {
            this.addEditingTag();
          })
      }
      .width('100%')
      .margin({ bottom: 18 })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.closeTagDialog();
          })

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.saveCustomTags();
          })
      }
      .width('100%')
    }
    .padding(18)
  }

  openTagDialog(): void {
    this.showTagDialog = true;
    this.tagDialogSession.open(this.getUIContext(), (): void => {
      this.tagDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示自定义标签弹窗失败:'
    });
  }

  closeTagDialog(): void {
    this.showTagDialog = false;
    this.pendingActionBook = null;
    this.tagDialogSession.close(this.getUIContext());
  }

  @Builder
  customCoverDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('使用自定义链接')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text(`《${this.networkCoverTargetBook?.name || ''}》`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      TextInput({ placeholder: '请输入图片 URL', text: this.customNetworkCoverUrl })
        .type(InputType.Normal)
        .width('100%')
        .height(44)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.customNetworkCoverUrl = value;
        })
      Text('仅支持 http 或 https 图片链接，图片是否可用由网络资源决定。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.closeCustomCoverDialog();
            this.showNetworkCoverDialog = true;
          })
        Button('设为封面', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(/^https?:\/\/[^\s]+$/i.test(this.customNetworkCoverUrl.trim()))
          .onClick(() => this.applyCustomNetworkCover())
      }
      .width('100%')
    }
    .padding(AppSpacing.XXL)
  }

  openCustomCoverDialog(): void {
    this.showCustomNetworkCoverDialog = true;
    // 取消按钮需回退到封面选择面板，蒙层关闭无对应流程，禁用 autoCancel。
    this.customCoverDialogSession.open(this.getUIContext(), (): void => {
      this.customCoverDialogContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示自定义封面弹窗失败:'
    });
  }

  closeCustomCoverDialog(): void {
    this.showCustomNetworkCoverDialog = false;
    this.customCoverDialogSession.close(this.getUIContext());
  }


  selectShelfGroup(groupId: number): void {
    if (this.activeShelfGroupId === groupId) {
      this.applyShelfScope();
      return;
    }
    if (this.shelfScopeSwitchAnimating) {
      return;
    }
    if (this.isTileLayout()) {
      if (!this.tileGroupAnimating) this.changeTileGroup(groupId);
      return;
    }
    const currentIndex = this.shelfGroupOrderIndex(this.activeShelfGroupId);
    const nextIndex = this.shelfGroupOrderIndex(groupId);
    const outgoingX = nextIndex >= currentIndex ? -36 : 36;
    this.animateShelfContentUpdate(() => {
      this.activeShelfGroupId = groupId;
    }, outgoingX);
  }

  shelfGroupOrderIndex(groupId: number): number {
    if (groupId === 0) {
      return 0;
    }
    if (groupId === -1) {
      return this.shelfGroups.length + 1;
    }
    const index = this.shelfGroups.findIndex((group: BookGroup) => group.groupId === groupId);
    return index >= 0 ? index + 1 : 0;
  }

  isTileGroupPage(): boolean {
    return this.isTileLayout() && this.activeShelfGroupId > 0;
  }

  activeShelfGroupName(): string {
    const group = this.shelfGroups.find((item: BookGroup) => item.groupId === this.activeShelfGroupId);
    return group ? group.groupName : '书籍分组';
  }

  captureSharedElementBounds(id: string, fallback: SharedElementBounds | undefined,
    touchX: number, touchY: number, rootId: string = 'bookshelf_motion_root'): SharedElementBounds {
    let measured = fallback;
    try {
      // 滚动不一定触发 onAreaChange；点击时读取真实窗口坐标，避免从旧位置飞出。
      const ui = this.getUIContext();
      const rect = ui.getComponentUtils().getRectangleById(id);
      if (rect.size.width > 0 && rect.size.height > 0) {
        const root = ui.getComponentUtils().getRectangleById(rootId);
        const originX = root.size.width > 0 ? root.windowOffset.x : 0;
        const originY = root.size.height > 0 ? root.windowOffset.y : 0;
        measured = new SharedElementBounds(ui.px2vp(rect.windowOffset.x - originX),
          ui.px2vp(rect.windowOffset.y - originY), ui.px2vp(rect.size.width), ui.px2vp(rect.size.height));
      }
    } catch (error) {
      // LazyForEach 已回收源节点时使用最后有效位置。
    }
    return SharedElementBounds.resolve(measured, touchX, touchY, this.contextViewportWidth, this.contextViewportHeight);
  }

  /**
   * 点分组卡片：先截下卡片和整个书架（截图期间书架不动）。卡片截图马上开始长大（见 leadTileGroupIn），
   * 分组页在它下面建好后一起展开到满屏，卡片截图很快淡出，周围露出书架截图并慢慢压暗。
   * 页面矩形从卡片展开到满屏，始终罩住原卡片，书架截图里那张卡片不会露出来。
   */
  openTileGroupPage(groupId: number, pageKey: string, touchX: number, touchY: number): void {
    if (this.tileGroupAnimating || this.consumeShelfSwipeClick()) return;
    this.showShelfGroupMenu = false;
    this.showShelfMoreMenu = false;
    this.showShelfFilterMenu = false;
    const generation = this.beginTileGroupMotion(groupId);
    const cardId = this.tileGroupElementId(groupId, pageKey);
    this.tileGroupOriginBounds = this.captureSharedElementBounds(cardId, undefined, touchX, touchY);
    this.tileGroupPreviewSources = this.captureTileGroupPreviewSources(groupId, pageKey, cardId);
    this.tileGroupOriginGroupId = groupId;
    this.tileGroupHasOrigin = true;
    Promise.all([this.snapshotTileGroupElement(cardId), this.snapshotTileGroupElement('bookshelf_motion_root')])
      .then((shots: (image.PixelMap | undefined)[]): void => {
        if (generation !== this.tileGroupMotionGeneration) {
          shots.forEach((shot: image.PixelMap | undefined): void => this.releaseTileGroupShot(shot));
          return;
        }
        this.enterTileGroup(groupId, generation, shots[1], shots[0]);
      });
  }

  tileGroupElementId(groupId: number, pageKey: string): string {
    return `shelf_group_${pageKey}_${groupId}`;
  }

  tileGroupPreviewCoverId(cardId: string, book: Book): string {
    return `${cardId}_cover_${encodeURIComponent(book.bookUrl)}`;
  }

  tileGroupFlyValue(from: number, to: number): number {
    return from + (to - from) * this.tileGroupFlyProgress;
  }

  /** 相对书架根节点的位置（vp）；量不到时为空，不像 captureSharedElementBounds 那样回退到手指位置。 */
  measureTileGroupRect(id: string): SharedElementBounds | undefined {
    try {
      const ui = this.getUIContext();
      const rect = ui.getComponentUtils().getRectangleById(id);
      if (rect.size.width <= 0 || rect.size.height <= 0) return undefined;
      const root = ui.getComponentUtils().getRectangleById('bookshelf_motion_root');
      const originX = root.size.width > 0 ? root.windowOffset.x : 0;
      const originY = root.size.height > 0 ? root.windowOffset.y : 0;
      return new SharedElementBounds(ui.px2vp(rect.windowOffset.x - originX), ui.px2vp(rect.windowOffset.y - originY),
        ui.px2vp(rect.size.width), ui.px2vp(rect.size.height));
    } catch (error) {
      return undefined;
    }
  }

  /** 四宫格里每本书在书架上的位置；主题文件夹图不显示四宫格，没有可飞的封面。 */
  captureTileGroupPreviewSources(groupId: number, pageKey: string, cardId: string): TileGroupPreviewSource[] {
    if (this.shouldUseThemeBookCover()) return [];
    const sources: TileGroupPreviewSource[] = [];
    for (const book of this.getTileGroupPreviewBooks(groupId, this.shelfBooksForPage(pageKey))) {
      const bounds = this.measureTileGroupRect(this.tileGroupPreviewCoverId(cardId, book));
      if (bounds) sources.push(new TileGroupPreviewSource(book, bounds));
    }
    return sources;
  }

  /**
   * 分组页里这本书的封面在页面满屏时的位置。getRectangleById 给的是排版位置、不含页面的缩放平移，
   * 所以页面还缩在卡片附近时量到的也就是满屏时的位置。在屏幕外的不飞。
   */
  measureTileGroupPageCover(book: Book): SharedElementBounds | undefined {
    const rect = this.measureTileGroupRect(this.shelfCoverElementId(book, this.shelfCoverScope(this.shelfPageKey(), false)));
    if (!rect || rect.y + rect.height <= 0 || rect.y >= this.contextViewportHeight ||
      rect.x + rect.width <= 0 || rect.x >= this.contextViewportWidth) {
      return undefined;
    }
    return rect;
  }

  makeTileGroupFlyer(book: Book, from: SharedElementBounds, to: SharedElementBounds): TileGroupFlyer {
    const flyer = new TileGroupFlyer();
    const base = from.width >= to.width ? from : to;
    flyer.key = book.bookUrl;
    flyer.cover = this.getShelfCoverList(book).length > 0 ? this.imageCover(this.getShelfCover(book, true)) : '';
    flyer.color = this.getBookColor(book.name);
    flyer.initial = book.name ? book.name.substring(0, 1) : '书';
    flyer.width = base.width;
    flyer.height = base.height;
    flyer.fromX = from.x;
    flyer.fromY = from.y;
    flyer.fromScaleX = from.width / base.width;
    flyer.fromScaleY = from.height / base.height;
    flyer.toX = to.x;
    flyer.toY = to.y;
    flyer.toScaleX = to.width / base.width;
    flyer.toScaleY = to.height / base.height;
    return flyer;
  }

  /** 挂上飞行封面（停在起点）并藏起分组页里对应的封面；返回是否有可飞的。 */
  mountTileGroupFlyers(flyers: TileGroupFlyer[]): boolean {
    this.tileGroupFlyProgress = 0;
    this.tileGroupFlyers = flyers;
    this.tileGroupHiddenCovers = flyers.map((flyer: TileGroupFlyer): string => flyer.key);
    return flyers.length > 0;
  }

  /** 展开：从引导段终点处四宫格里的格子，飞到分组页满屏时的位置。 */
  openTileGroupFlyers(): TileGroupFlyer[] {
    const card = this.tileGroupOriginBounds;
    const lead = this.tileGroupLeadBounds;
    if (card.width <= 0 || card.height <= 0 || lead.width <= 0) return [];
    const kx = lead.width / card.width;
    const ky = lead.height / card.height;
    const flyers: TileGroupFlyer[] = [];
    for (const source of this.tileGroupPreviewSources) {
      const target = this.measureTileGroupPageCover(source.book);
      if (!target) continue;
      const from = new SharedElementBounds(lead.x + (source.bounds.x - card.x) * kx,
        lead.y + (source.bounds.y - card.y) * ky, source.bounds.width * kx, source.bounds.height * ky);
      flyers.push(this.makeTileGroupFlyer(source.book, from, target));
    }
    return flyers;
  }

  /** 收回：从分组页当前（满屏）的位置飞回书架上四宫格里的格子。 */
  closeTileGroupFlyers(): TileGroupFlyer[] {
    const flyers: TileGroupFlyer[] = [];
    for (const source of this.tileGroupPreviewSources) {
      const from = this.measureTileGroupPageCover(source.book);
      if (from) flyers.push(this.makeTileGroupFlyer(source.book, from, source.bounds));
    }
    return flyers;
  }

  /** 从分组菜单等处切换分组：没有卡片可展开，换页后淡入；切回书架走返回动画。 */
  changeTileGroup(groupId: number): void {
    if (groupId === 0) {
      this.leaveTileGroupPage();
      return;
    }
    this.tileGroupHasOrigin = false;
    this.enterTileGroup(groupId, this.beginTileGroupMotion(groupId), undefined, undefined);
  }

  beginTileGroupMotion(targetGroupId: number): number {
    const generation = ++this.tileGroupMotionGeneration;
    this.tileGroupAnimating = true;
    this.tileGroupPendingTarget = targetGroupId;
    if (this.tileGroupMotionWatchdog >= 0) clearTimeout(this.tileGroupMotionWatchdog);
    this.tileGroupMotionWatchdog = setTimeout((): void => this.finishTileGroupMotion(generation),
      SHELF_GROUP_MOTION_WATCHDOG);
    return generation;
  }

  enterTileGroup(groupId: number, generation: number, backdrop: image.PixelMap | undefined,
    cardShot: image.PixelMap | undefined): void {
    const bounds = this.tileGroupOriginBounds;
    const fromCard = this.tileGroupHasOrigin && backdrop !== undefined && cardShot !== undefined &&
      bounds.width > 0 && bounds.height > 0 &&
      bounds.width < this.contextViewportWidth && bounds.height < this.contextViewportHeight;
    if (fromCard) {
      this.releaseTileGroupShot(this.tileGroupCardShot);
      this.tileGroupBackdrop = backdrop;
      this.tileGroupCardShot = cardShot;
      this.placeTileGroupMotion(bounds);
      this.tileGroupCardOpacity = 1;
      this.tileGroupScrimOpacity = 0;
    } else {
      this.releaseTileGroupShot(backdrop);
      this.releaseTileGroupShot(cardShot);
      this.tileGroupHasOrigin = false;
      this.tileGroupPageOpacity = 0;
    }
    // 书架截图垫在活书架下面、卡片截图正好盖在原卡片上，这一帧看不出变化；画出来之后再切到分组页。
    this.afterTileGroupFrames(generation, fromCard ? SHELF_GROUP_PREMOUNT_FRAMES : 0, (): void => {
      if (!fromCard) {
        this.applyTileGroupTarget(groupId);
        this.animateTileGroupIn(generation, false);
        return;
      }
      this.leadTileGroupIn(groupId, generation, bounds);
    });
  }

  /**
   * 拆掉书架、建分组页要占住主线程一帧近两百毫秒。先让卡片截图在渲染线程上开始长大（不受主线程阻塞），
   * 同时把分组页按这段的终点位置建在截图下面；两边都到了再一起展开到满屏，点下去马上就有反馈。
   */
  leadTileGroupIn(groupId: number, generation: number, bounds: SharedElementBounds): void {
    let leadDone = false;
    let pageReady = false;
    const proceed = (): void => {
      if (!leadDone || !pageReady || generation !== this.tileGroupMotionGeneration) return;
      // 飞行封面先停在引导段终点处卡片截图里四宫格的位置挂上一帧（和截图重合、看不出来），再一起动。
      if (this.mountTileGroupFlyers(this.openTileGroupFlyers())) {
        this.afterTileGroupFrames(generation, 1, (): void => this.animateTileGroupIn(generation, true));
      } else {
        this.animateTileGroupIn(generation, true);
      }
    };
    const lead = this.interpolateTileGroupBounds(bounds, SHELF_GROUP_LEAD_PROGRESS);
    this.tileGroupLeadBounds = lead;
    this.getUIContext().animateTo({ duration: SHELF_GROUP_LEAD_DURATION, curve: curves.cubicBezierCurve(0.5, 0, 1, 1),
      expectedFrameRateRange: SHELF_GROUP_FRAME_RATE, onFinish: (): void => {
        leadDone = true;
        proceed();
      } }, (): void => {
      this.placeTileGroupMotion(lead);
      this.tileGroupScrimOpacity = 0.05;
    });
    // 动画先在这一帧提交给渲染线程，下一帧再换页面。
    this.afterTileGroupFrames(generation, 1, (): void => {
      this.applyTileGroupTarget(groupId);
      this.scheduleTileGroupStart(generation, 1, (): void => {
        pageReady = true;
        proceed();
      });
    });
  }

  interpolateTileGroupBounds(bounds: SharedElementBounds, progress: number): SharedElementBounds {
    const width = Math.max(1, this.contextViewportWidth);
    const height = Math.max(1, this.contextViewportHeight);
    return new SharedElementBounds(bounds.x * (1 - progress), bounds.y * (1 - progress),
      bounds.width + (width - bounds.width) * progress, bounds.height + (height - bounds.height) * progress);
  }

  /** fromCard 时由 leadTileGroupIn 在页面建好后直接调用；否则等新页面首帧画好再淡入。 */
  animateTileGroupIn(generation: number, fromCard: boolean): void {
    if (fromCard) {
      const duration = SHELF_GROUP_EXPAND_DURATION;
      // 接着引导段末尾的速度往下走，末段减速。
      this.getUIContext().animateTo({ duration, curve: curves.cubicBezierCurve(0.2, 0.4, 0.2, 1),
        expectedFrameRateRange: SHELF_GROUP_FRAME_RATE,
        onFinish: (): void => this.finishTileGroupMotion(generation) }, (): void => {
        this.resetTileGroupMotionTransform();
        this.tileGroupScrimOpacity = 0.18;
        this.tileGroupFlyProgress = 1;
      });
      // 卡片截图拉大后会糊，很快淡掉，之后看到的都是真实的分组页。
      this.getUIContext().animateTo({ duration: Math.round(duration * 0.3), curve: Curve.EaseOut }, (): void => {
        this.tileGroupCardOpacity = 0;
      });
      return;
    }
    this.scheduleTileGroupStart(generation, 1, (): void => {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut,
        onFinish: (): void => this.finishTileGroupMotion(generation) }, (): void => {
        this.tileGroupPageOpacity = 1;
      });
    });
  }

  /**
   * 返回：留着的书架截图还能用时，活的分组页直接缩回卡片（collapseTileGroupToCard）。否则截下当前分组页
   * 盖在最上面，下面换回书架并恢复进入前的滚动位置，再把截图缩回分组卡片，末段淡入卡片截图，结束时和书架上的
   * 卡片重合。没有卡片可回（菜单进入、窗口尺寸变了、分组被删）时只淡出。
   */
  leaveTileGroupPage(): void {
    const generation = this.beginTileGroupMotion(0);
    const toCard = this.tileGroupHasOrigin && this.tileGroupCardShot !== undefined &&
      this.activeShelfGroupId === this.tileGroupOriginGroupId &&
      this.shelfGroups.some((group: BookGroup): boolean => group.groupId === this.tileGroupOriginGroupId);
    const shelfShot = this.tileGroupShelfShot;
    if (toCard && shelfShot !== undefined && this.tileGroupShelfShotKey === this.tileGroupShelfShotKeyNow()) {
      this.collapseTileGroupToCard(generation, shelfShot);
      return;
    }
    this.snapshotTileGroupElement('bookshelf_motion_root').then((curtain: image.PixelMap | undefined): void => {
      if (generation !== this.tileGroupMotionGeneration) {
        this.releaseTileGroupShot(curtain);
        return;
      }
      this.resetTileGroupMotionTransform();
      this.tileGroupCardOpacity = 0;
      this.tileGroupPageOpacity = 1;
      if (!curtain) {
        this.applyTileGroupTarget(0);
        this.finishTileGroupMotion(generation);
        return;
      }
      // 截图和当前画面一模一样，先盖上并画出来，再在它下面换回书架。
      this.tileGroupCurtain = curtain;
      this.afterTileGroupFrames(generation, SHELF_GROUP_PREMOUNT_FRAMES, (): void => {
        this.applyTileGroupTarget(0);
        this.animateTileGroupOut(generation, toCard);
      });
    });
  }

  /**
   * 打开的镜像：书架截图垫回下面，活的分组页从满屏缩回卡片原处，周围压暗退掉，末段淡入卡片截图。
   * 动画期间不碰书架，落地后用同一张截图盖住，再在下面换回书架。
   */
  collapseTileGroupToCard(generation: number, shelfShot: image.PixelMap): void {
    this.resetTileGroupMotionTransform();
    this.tileGroupPageOpacity = 1;
    this.tileGroupCardOpacity = 0;
    this.tileGroupScrimOpacity = 0.18;
    this.tileGroupBackdrop = shelfShot;
    // 页面此刻满屏，飞行封面就停在分组页里那几本的位置上，挂上看不出变化。
    const flying = this.mountTileGroupFlyers(this.closeTileGroupFlyers());
    // 截图在满屏的分组页下面，挂上这一帧看不出变化；画出来后再缩。
    this.afterTileGroupFrames(generation, 1, (): void => {
      const duration = SHELF_GROUP_MOTION_DURATION;
      this.getUIContext().animateTo({ duration, curve: curves.cubicBezierCurve(0.2, 0, 0, 1),
        expectedFrameRateRange: SHELF_GROUP_FRAME_RATE,
        onFinish: (): void => this.landTileGroupOnCard(generation) }, (): void => {
        this.placeTileGroupMotion(this.tileGroupOriginBounds);
        this.tileGroupScrimOpacity = 0;
        this.tileGroupFlyProgress = 1;
      });
      // 卡片截图里也有四宫格；有飞行封面时晚一点淡入，免得封面还在半路就和截图里的叠出两份。
      this.getUIContext().animateTo({ duration: Math.round(duration * (flying ? 0.4 : 0.35)),
        delay: Math.round(duration * (flying ? 0.5 : 0.3)), curve: Curve.EaseOut }, (): void => {
        this.tileGroupCardOpacity = 1;
      });
    });
  }

  /** 落在卡片上的画面就是书架截图本身：盖上它，下面换回书架、等滚动恢复后揭开。 */
  landTileGroupOnCard(generation: number): void {
    if (generation !== this.tileGroupMotionGeneration) return;
    this.tileGroupCover = this.tileGroupBackdrop;
    this.afterTileGroupFrames(generation, SHELF_GROUP_PREMOUNT_FRAMES, (): void => {
      this.applyTileGroupTarget(0);
      this.scheduleTileGroupStart(generation, 2, (): void => this.finishTileGroupMotion(generation));
    });
  }

  tileGroupShelfShotKeyNow(): string {
    return `${Math.round(this.contextViewportWidth)}x${Math.round(this.contextViewportHeight)}|${this.appDarkMode}`;
  }

  dropTileGroupShelfShot(): void {
    if (this.tileGroupBackdrop === this.tileGroupShelfShot) this.tileGroupBackdrop = undefined;
    if (this.tileGroupCover === this.tileGroupShelfShot) this.tileGroupCover = undefined;
    this.releaseTileGroupShot(this.tileGroupShelfShot);
    this.tileGroupShelfShot = undefined;
    this.tileGroupShelfShotKey = '';
  }

  animateTileGroupOut(generation: number, toCard: boolean): void {
    // 书架要先建好、滚到进入前的位置（滚动在挂载后的下一帧才恢复），再量卡片的真实位置。
    this.scheduleTileGroupStart(generation, 2, (): void => {
      const origin = this.tileGroupOriginBounds;
      const bounds = toCard ? this.captureSharedElementBounds(
        this.tileGroupElementId(this.tileGroupOriginGroupId, this.shelfPageKey()), origin,
        origin.x + origin.width / 2, origin.y + origin.height / 2) : origin;
      const duration = SHELF_GROUP_MOTION_DURATION;
      if (toCard && bounds.width > 0 && bounds.height > 0) {
        this.getUIContext().animateTo({ duration, curve: curves.cubicBezierCurve(0.2, 0, 0, 1),
          expectedFrameRateRange: SHELF_GROUP_FRAME_RATE,
          onFinish: (): void => this.finishTileGroupMotion(generation) }, (): void => {
          this.placeTileGroupMotion(bounds);
        });
        this.getUIContext().animateTo({ duration: Math.round(duration * 0.35), delay: Math.round(duration * 0.3),
          curve: Curve.EaseOut }, (): void => {
          this.tileGroupCardOpacity = 1;
        });
      } else {
        this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut,
          onFinish: (): void => this.finishTileGroupMotion(generation) }, (): void => {
          this.tileGroupPageOpacity = 0;
        });
      }
    });
  }

  /** 把整页（根节点大小）缩放平移到 bounds 处；圆角按缩放比例换算，看上去和卡片一样圆。 */
  placeTileGroupMotion(bounds: SharedElementBounds): void {
    const width = Math.max(1, this.contextViewportWidth);
    const height = Math.max(1, this.contextViewportHeight);
    const scaleX = bounds.width / width;
    const scaleY = bounds.height / height;
    this.tileGroupMotionScaleX = scaleX;
    this.tileGroupMotionScaleY = scaleY;
    this.tileGroupMotionTranslateX = bounds.x;
    this.tileGroupMotionTranslateY = bounds.y;
    this.tileGroupMotionRadius = SHELF_GROUP_CARD_RADIUS * 2 / Math.max(0.01, scaleX + scaleY);
  }

  resetTileGroupMotionTransform(): void {
    this.tileGroupMotionScaleX = 1;
    this.tileGroupMotionScaleY = 1;
    this.tileGroupMotionTranslateX = 0;
    this.tileGroupMotionTranslateY = 0;
    this.tileGroupMotionRadius = 0;
  }

  /** 切换页面状态；进入时存下书架的分类页和标题收起量，返回时原样换回。 */
  applyTileGroupTarget(groupId: number): void {
    this.tileGroupPendingTarget = -1;
    if (groupId === 0) {
      if (this.tileGroupRootPages) {
        this.shelfCategoryPages = this.tileGroupRootPages;
        this.tileGroupRootPages = null;
        this.shelfHeaderCollapse = this.tileGroupRootHeaderCollapse;
      }
    } else {
      if (this.activeShelfGroupId === 0) {
        this.tileGroupRootPages = this.shelfCategoryPages;
        this.tileGroupRootHeaderCollapse = this.shelfHeaderCollapse;
      }
      this.shelfCategoryPages = new Map();
      this.shelfHeaderCollapse = 0;
    }
    this.activeShelfGroupId = groupId;
  }

  /** 等 frames 帧（0 则立即）后执行；被新一轮动画取代时作废。帧回调拿不到时最多等 80ms。 */
  afterTileGroupFrames(generation: number, frames: number, run: () => void): void {
    if (frames <= 0) {
      run();
      return;
    }
    let done = false;
    let remaining = frames;
    const fire = (): void => {
      if (done || generation !== this.tileGroupMotionGeneration) return;
      done = true;
      run();
    };
    const tick = (): void => {
      remaining--;
      if (remaining > 0) post();
      else fire();
    };
    const post = (): void => {
      try {
        this.getUIContext().postFrameCallback(new ShelfGroupNextFrame(tick));
      } catch (error) {
        fire();
      }
    };
    setTimeout(fire, 80);
    post();
  }

  /** 新页面首帧建好、主线程空闲 idleFrames 帧后再开始动，最多等 SHELF_GROUP_MOTION_START_CAP。 */
  scheduleTileGroupStart(generation: number, idleFrames: number, start: () => void): void {
    let started = false;
    let remaining = idleFrames;
    const run = (): void => {
      if (started || generation !== this.tileGroupMotionGeneration) return;
      started = true;
      if (this.tileGroupStartTimer >= 0) clearTimeout(this.tileGroupStartTimer);
      this.tileGroupStartTimer = -1;
      start();
    };
    const idle = (): void => {
      remaining--;
      if (remaining > 0) post();
      else run();
    };
    const post = (): void => {
      try {
        this.getUIContext().postFrameCallback(new ShelfOpeningIdleStarter(idle));
      } catch (error) {
        run();
      }
    };
    if (this.tileGroupStartTimer >= 0) clearTimeout(this.tileGroupStartTimer);
    this.tileGroupStartTimer = setTimeout(run, SHELF_GROUP_MOTION_START_CAP);
    post();
  }

  async snapshotTileGroupElement(id: string): Promise<image.PixelMap | undefined> {
    try {
      return await this.getUIContext().getComponentSnapshot().get(id);
    } catch (error) {
      return undefined;
    }
  }

  /** 截图从界面上撤下后过一会儿再释放，免得当前帧还在画它。 */
  releaseTileGroupShot(shot: image.PixelMap | undefined): void {
    if (!shot) return;
    setTimeout((): void => {
      shot.release().catch((): void => {});
    }, 300);
  }

  finishTileGroupMotion(generation: number): void {
    if (generation !== this.tileGroupMotionGeneration) return;
    // 收尾后这一轮的迟到回调（截图、首帧、动画结束）一律作废。
    this.tileGroupMotionGeneration++;
    if (this.tileGroupMotionWatchdog >= 0) clearTimeout(this.tileGroupMotionWatchdog);
    this.tileGroupMotionWatchdog = -1;
    if (this.tileGroupStartTimer >= 0) clearTimeout(this.tileGroupStartTimer);
    this.tileGroupStartTimer = -1;
    // 截图或首帧回调卡住时也要切到用户选的页面，不能一直锁住书架。
    if (this.tileGroupPendingTarget >= 0) this.applyTileGroupTarget(this.tileGroupPendingTarget);
    if (this.activeShelfGroupId > 0 && this.tileGroupHasOrigin && this.tileGroupBackdrop &&
      this.tileGroupBackdrop !== this.tileGroupShelfShot) {
      this.dropTileGroupShelfShot();
      this.tileGroupShelfShot = this.tileGroupBackdrop;
      this.tileGroupShelfShotKey = this.tileGroupShelfShotKeyNow();
    }
    this.clearTileGroupMotionLayers();
    if (this.activeShelfGroupId === 0) {
      this.releaseTileGroupShot(this.tileGroupCardShot);
      this.tileGroupCardShot = undefined;
      this.tileGroupHasOrigin = false;
      this.tileGroupPreviewSources = [];
      this.dropTileGroupShelfShot();
    }
    this.tileGroupAnimating = false;
    if (this.tileGroupPendingBack) {
      this.tileGroupPendingBack = false;
      this.exitTileGroupPage();
    }
  }

  clearTileGroupMotionLayers(): void {
    // 留作返回用的书架截图只在 dropTileGroupShelfShot 里释放。
    if (this.tileGroupBackdrop !== this.tileGroupShelfShot) this.releaseTileGroupShot(this.tileGroupBackdrop);
    this.releaseTileGroupShot(this.tileGroupCurtain);
    this.tileGroupBackdrop = undefined;
    this.tileGroupCurtain = undefined;
    this.tileGroupCover = undefined;
    this.tileGroupFlyers = [];
    this.tileGroupFlyProgress = 0;
    this.tileGroupHiddenCovers = [];
    this.resetTileGroupMotionTransform();
    this.tileGroupCardOpacity = 0;
    this.tileGroupScrimOpacity = 0;
    this.tileGroupPageOpacity = 1;
  }

  cancelTileGroupMotion(): void {
    this.tileGroupMotionGeneration++;
    if (this.tileGroupStartTimer >= 0) clearTimeout(this.tileGroupStartTimer);
    if (this.tileGroupMotionWatchdog >= 0) clearTimeout(this.tileGroupMotionWatchdog);
    this.tileGroupStartTimer = -1;
    this.tileGroupMotionWatchdog = -1;
    this.tileGroupPendingTarget = -1;
    this.tileGroupPendingBack = false;
    this.clearTileGroupMotionLayers();
    this.releaseTileGroupShot(this.tileGroupCardShot);
    this.tileGroupCardShot = undefined;
    this.tileGroupPreviewSources = [];
    this.dropTileGroupShelfShot();
    this.tileGroupAnimating = false;
  }

  onTileGroupBackRequested(): void {
    if (this.activeShelfGroupId > 0 || this.tileGroupPendingTarget > 0) this.exitTileGroupPage();
  }

  exitTileGroupPage(): void {
    if (this.tileGroupAnimating) {
      this.tileGroupPendingBack = true;
      return;
    }
    this.showShelfGroupMenu = false;
    this.showShelfMoreMenu = false;
    this.selectShelfGroup(0);
  }

  enterBookMultiSelect(initialBookUrl: string): void {
    this.isBookMultiSelect = true;
    this.selectedBookUrls = initialBookUrl ? [initialBookUrl] : [];
    this.showShelfMoreMenu = false;
    this.showShelfFilterMenu = false;
    this.showShelfGroupMenu = false;
  }

  exitBookMultiSelect(): void {
    this.isBookMultiSelect = false;
    this.selectedBookUrls = [];
    this.showBookGroupPicker = false;
    this.groupPickerSingleBookUrl = '';
    this.showMultiSelectMoreMenu = false;
    this.closeBatchDeleteDialog();
    this.closeBatchExportDialog();
  }

  selectedLocalBooks(): Book[] {
    return this.allBooks.filter((book: Book) =>
      this.selectedBookUrls.includes(book.bookUrl) && LocalBookService.isLocalBook(book));
  }

  async setSelectedBooksPrivate(nextPrivate: boolean): Promise<void> {
    const urls = [...this.selectedBookUrls];
    const targets = this.allBooks.filter((book: Book) =>
      urls.includes(book.bookUrl) && book.isPrivate !== nextPrivate);
    const db = AppDatabase.getInstance();
    let changed = 0;
    for (const book of targets) {
      try {
        await db.setBookPrivate(book.bookUrl, nextPrivate);
        book.isPrivate = nextPrivate;
        changed++;
      } catch (e) {
        console.error('批量更新书籍隐私状态失败:', book.name, e);
      }
    }
    this.exitBookMultiSelect();
    await this.loadBooks(true);
    RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext).catch((e: Error) => {
      console.warn('刷新最近阅读卡片失败:', e);
    });
    const failed = targets.length - changed;
    const summary = nextPrivate ? `已将 ${changed} 本书移入隐私书架` : `已将 ${changed} 本书移出隐私书架`;
    HdsFeedback.showToast(failed > 0 ? `${summary}，${failed} 本失败` : summary);
  }

  async exportSelectedLocalBooks(): Promise<void> {
    const targets = this.selectedLocalBooks();
    if (targets.length === 0) return;
    try {
      const result = await LocalBookService.exportSourceFiles(getContext(this), targets);
      if (!result) return;
      this.exitBookMultiSelect();
      const failed = result.failedNames.length;
      if (result.savedCount === 0) {
        HdsFeedback.showToast('保存失败：源文件不存在或已被清理');
      } else {
        HdsFeedback.showToast(failed > 0 ?
          `已保存 ${result.savedCount} 本书的源文件，${failed} 本失败` :
          `已保存 ${result.savedCount} 本书的源文件`);
      }
    } catch (e) {
      console.error('批量保存本地书籍源文件失败:', e);
      HdsFeedback.showToast(`保存失败：${e instanceof Error ? e.message : String(e)}`);
    }
  }

  closeBookGroupPicker(): void {
    this.showBookGroupPicker = false;
    this.groupPickerSingleBookUrl = '';
  }

  toggleSelectedBook(bookUrl: string): void {
    this.setBookSelected(bookUrl, !this.isBookSelected(bookUrl));
  }

  isBookSelected(bookUrl: string): boolean {
    return this.selectedBookUrls.includes(bookUrl);
  }

  setBookSelected(bookUrl: string, selected: boolean): void {
    if (selected) {
      if (!this.isBookSelected(bookUrl)) {
        this.selectedBookUrls = this.selectedBookUrls.concat([bookUrl]);
      }
      return;
    }
    this.selectedBookUrls = this.selectedBookUrls.filter((url: string) => url !== bookUrl);
  }

  areAllBooksSelected(): boolean {
    return this.books.length > 0 && this.books.every((book: Book) => this.isBookSelected(book.bookUrl));
  }

  toggleAllBooks(): void {
    if (this.areAllBooksSelected()) {
      const visibleUrls = this.books.map((book: Book) => book.bookUrl);
      this.selectedBookUrls = this.selectedBookUrls.filter((url: string) => !visibleUrls.includes(url));
      return;
    }
    this.selectedBookUrls = this.books.map((book: Book) => book.bookUrl);
  }

  async addShelfBookGroup(): Promise<void> {
    const name = this.newBookGroupName.trim();
    if (!name) return;
    const db = AppDatabase.getInstance();
    const group = await db.addBookGroup(name);
    if (!group) {
      HdsFeedback.showToast('分组名称已存在');
      return;
    }
    this.closeAddBookGroupDialog();
    this.newBookGroupName = '';
    this.shelfGroups = await db.getCustomBookGroups();
    this.selectShelfGroup(group.groupId);
  }

  closeBookGroupActionMenu(): void {
    this.showBookGroupActionMenu = false;
    this.pendingBookGroup = null;
  }

  closeRenameBookGroupDialog(): void {
    this.showRenameBookGroupDialog = false;
    this.renameBookGroupDialogSession.close(this.getUIContext());
    this.renameBookGroupName = '';
    this.pendingBookGroup = null;
  }

  async renameShelfBookGroup(): Promise<void> {
    const group = this.pendingBookGroup;
    const name = this.renameBookGroupName.trim();
    if (!group || !name) return;
    const renamed = await AppDatabase.getInstance().renameBookGroup(group.groupId, name);
    if (!renamed) {
      HdsFeedback.showToast('分组名称已存在');
      return;
    }
    this.closeRenameBookGroupDialog();
    await this.loadBooks();
    HdsFeedback.showToast('分组已重命名');
  }

  closeDeleteBookGroupDialog(): void {
    this.showDeleteBookGroupDialog = false;
    this.deleteBookGroupDialogSession.close(this.getUIContext());
    this.pendingDeleteBookGroup = null;
    this.pendingBookGroup = null;
  }

  async deleteShelfBookGroup(): Promise<void> {
    const group = this.pendingDeleteBookGroup;
    if (!group) return;
    const db = AppDatabase.getInstance();
    await db.deleteBookGroup(group.groupId);
    if (this.activeShelfGroupId === group.groupId) this.activeShelfGroupId = -1;
    this.closeDeleteBookGroupDialog();
    await this.loadBooks();
    HdsFeedback.showToast('分组已删除，书籍已移到未分组');
  }

  async assignSelectedBooksToGroup(groupId: number): Promise<void> {
    const singleBookUrl = this.groupPickerSingleBookUrl;
    const targetUrls = singleBookUrl ? [singleBookUrl] : [...this.selectedBookUrls];
    if (targetUrls.length === 0) return;
    const count = targetUrls.length;
    const db = AppDatabase.getInstance();
    await db.updateBooksGroup(targetUrls, groupId);
    if (this.isBookMultiSelect) {
      this.exitBookMultiSelect();
    } else {
      this.closeBookGroupPicker();
    }
    await this.loadBooks();
    const groupName = groupId === 0 ? '未分组' :
      (this.shelfGroups.find((group: BookGroup) => group.groupId === groupId)?.groupName || '指定分组');
    HdsFeedback.showToast(count === 1 ? `已移动到“${groupName}”` : `已将 ${count} 本书移动到“${groupName}”`);
  }

  async deleteSelectedBooks(): Promise<void> {
    const urls = [...this.selectedBookUrls];
    const targets = this.allBooks.filter((book: Book) => urls.includes(book.bookUrl));
    const db = AppDatabase.getInstance();
    for (const book of targets) {
      this.deleteBookCoverCache(book);
      await CloudAutoSync.onBookRemoved(getContext(this), book).catch(() => undefined);
      LocalBookService.deleteLocalBookFiles(getContext(this), book);
      await db.deleteBook(book.bookUrl, 'bookshelf_batch_delete');
    }
    this.exitBookMultiSelect();
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    await this.loadBooks();
    HdsFeedback.showToast(`已删除 ${targets.length} 本书`);
  }


  /** 实际生效的标题行收起量：没有可滚动的列表时标题行始终完整显示。 */
  shelfHeaderCollapseValue(): number {
    return !this.isLoading && this.books.length > 0 && !this.isBookMultiSelect && !this.isTileGroupPage() ? this.shelfHeaderCollapse : 0;
  }

  onShelfListScroll(delta: number, offset: number): void {
    const reveal = CollapsingHeader.backdropReveal(offset);
    if (reveal !== this.shelfHeaderBackdropReveal) this.shelfHeaderBackdropReveal = reveal;
    if (this.shelfCategoryAnimating) return;
    const next = CollapsingHeader.next(this.shelfHeaderCollapse, delta, offset);
    if (next !== this.shelfHeaderCollapse) {
      this.shelfHeaderCollapse = next;
    }
  }

  onShelfListScrollStop(offset: number): void {
    if (this.shelfCategoryAnimating) return;
    const target = CollapsingHeader.settle(this.shelfHeaderCollapse, offset);
    if (target !== this.shelfHeaderCollapse) {
      animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
        this.shelfHeaderCollapse = target;
      });
    }
  }

  /** 列表顶部留白按标题行完整显示时的高度预留，不随收起变化，避免滚动中列表跳动。 */
  bookshelfTopOverlayHeight(): number {
    let height = this.statusBarHeight + 56;
    if (this.shelfSearchActive) {
      height += BookshelfPage.SEARCH_BAR_HEIGHT + AppSpacing.MD;
    }
    if (this.showsShelfScopeTabs()) {
      height += (BookshelfPage.SCOPE_TABS_HEIGHT + AppSpacing.MD) * (this.shelfCategoryExpanded ? 1 : 0);
    }
    if (this.isBookMultiSelect) {
      height += 42;
    }
    return height;
  }

  shelfHeaderBackdropHeight(): number {
    // 搜索框的底边不包含下面的间距和沉浸光感分类栏。
    return this.statusBarHeight + 56 - this.shelfHeaderCollapseValue() +
      (this.shelfSearchActive ? BookshelfPage.SEARCH_BAR_HEIGHT : 0);
  }

  bookshelfTileTopSpacerHeight(books: Book[] = this.books): number {
    const gridTopPadding = 10;
    const comfortableGap = 12;
    // Grid 会在顶部占位项与首行之间继续添加 rowsGap，需要从占位高度中抵消。
    return Math.max(0, this.bookshelfTopOverlayHeight() + comfortableGap -
      gridTopPadding - this.shelfTileGridRowGap(books));
  }

  bookshelfListBottomInset(): number {
    const comfortableGap = 20;
    const multiSelectBarHeight = this.isBookMultiSelect ? 104 : 0;
    if (deviceInfo.sdkApiVersion < 23) {
      return comfortableGap + multiSelectBarHeight;
    }
    if (this.isBookMultiSelect) {
      return Math.max(this.navBarHeight, 8) + comfortableGap + multiSelectBarHeight;
    }
    const floatingTabHeight = 56;
    return floatingTabHeight + Math.max(this.navBarHeight, 8) + comfortableGap;
  }

  getBookColor(name: string): string {
    if (!name) return '#007DFF';
    const colors = ['#007DFF', '#E53935', '#43A047', '#EF6C00', '#8E24AA', '#00ACC1', '#D81B60', '#5E35B1'];
    let hash = 0;
    for (let i = 0; i < name.length; i++) {
      hash = name.charCodeAt(i) + ((hash << 5) - hash);
    }
    return colors[Math.abs(hash) % colors.length];
  }

  getDisplayTags(book: Book): string[] {
    const tags = BookDisplayHelper.getBookTags(book);
    return tags;
  }

  getShelfAuthorText(book: Book): string {
    return book.author || '作者未知';
  }

  /**
   * Second info line of the compact/loose shelf row: "<x小时前> · <最新章节名>".
   * The old "作者 · 最后更新 xxx" single line is split so the update time gets its own row and
   * can carry the latest chapter title. It shares the author line's font and colour.
   */
  getShelfUpdateLineText(book: Book): string {
    const timeText = BookDisplayHelper.getLastUpdateRelativeText(book);
    const chapterText = (book.latestChapterTitle || '').trim();
    if (timeText && chapterText) {
      return `${timeText} · ${chapterText}`;
    }
    return timeText || chapterText;
  }

  // --- 书架行排版尺寸 ---------------------------------------------------------
  // 封面需要「顶部对齐书名、底部对齐最后一行文字」，所以下面这些行高必须是确定值：
  // 先用它们算出信息块总高度，再把封面高度设成同一个值，两端自然像素对齐。
  // 信息块内部恒有一个 Blank()，所以某本书没有更新行时，尾部仍会被顶到底部。

  shelfRowSpace(): number {
    return 4;
  }

  shelfTitleLineHeight(): number {
    return 20;
  }

  /** 作者名、更新时间行、宽松布局的阅读进度：字号 14。 */
  shelfTextLineHeight(): number {
    return 19;
  }

  /** 紧凑布局在关闭进度条时显示的阅读进度：字号 12。 */
  shelfSmallTextLineHeight(): number {
    return 16;
  }

  shelfProgressPanelHeight(): number {
    return this.shelfSmallTextLineHeight() + 4 + 3;
  }

  /** 信息块最后一行的高度——封面底部与它对齐。 */
  shelfInfoTailHeight(): number {
    return this.bookshelfShowProgressBar ? this.shelfProgressPanelHeight() : this.shelfSmallTextLineHeight();
  }

  /** 紧凑布局信息块高度 = 标题行 + 作者行 + 更新行 + 尾部行 + 4 个行间距。 */
  shelfCompactInfoHeight(): number {
    return this.shelfTitleLineHeight() + this.shelfTextLineHeight() + this.shelfTextLineHeight() +
      this.shelfInfoTailHeight() + this.shelfRowSpace() * 4;
  }

  /** 宽松布局信息块高度，尾部是阅读进度行。 */
  shelfLooseInfoHeight(): number {
    return this.shelfTitleLineHeight() + this.shelfTextLineHeight() + this.shelfTextLineHeight() +
      this.shelfTextLineHeight() + this.shelfRowSpace() * 4;
  }

  /** 封面沿用 7:9 的书籍比例，高度跟随信息块，宽度按比例推导。 */
  shelfCoverWidth(infoHeight: number): number {
    return Math.round(infoHeight * 7 / 9);
  }

  isCompactLayout(): boolean {
    return this.bookshelfLayoutMode !== 'loose';
  }

  isTileLayout(): boolean {
    return this.bookshelfLayoutMode === 'tile' || this.isCompanionLayout();
  }

  /** 陪伴布局沿用平铺的网格与分组文件夹，只在根视图顶部换成问候、继续阅读轮播与阅读小记。 */
  isCompanionLayout(): boolean {
    return this.bookshelfLayoutMode === 'companion';
  }

  /** 搜索时把分组文件夹摊开，命中的书直接排出来，不会被折进文件夹里。 */
  shouldUseTileGroupFolders(): boolean {
    return this.isTileLayout() && this.activeShelfGroupId === 0 && !this.isBookMultiSelect &&
      !this.shelfAppliedSearchKeyword;
  }

  getUngroupedTileBooks(): Book[] {
    return this.books.filter((book: Book) => book.group <= 0 ||
      !this.shelfGroups.some((group: BookGroup) => group.groupId === book.group));
  }

  getLatestReadTileBook(books: Book[] = this.books): Book | null {
    return BookshelfSortHelper.getPinnedRecentReadBooks(books, 1)[0] ?? null;
  }

  getLatestReadTileBooks(books: Book[] = this.books): Book[] {
    const count = this.isLatestTileCardLarge() ?
      BookshelfDisplaySettingsStore.normalizeLastReadPinCount(this.bookshelfLastReadPinCount) : 1;
    return BookshelfSortHelper.getPinnedRecentReadBooks(books, count);
  }

  shouldShowLatestExpandedTileBook(): boolean {
    return this.isTileLayout() && (this.isCompanionLayout() || this.bookshelfLastReadPinMode !== 'off') &&
      this.activeShelfGroupId === 0 &&
      !this.isBookMultiSelect && !this.shelfAppliedSearchKeyword;
  }

  isLatestTileCardLarge(): boolean {
    return this.isCompanionLayout() || this.bookshelfLastReadPinMode === 'large';
  }

  getTileBooksWithoutLatest(books: Book[], latest: Book[] = this.getLatestReadTileBooks(books)): Book[] {
    const uniqueBooks: Book[] = [];
    const seenBookUrls = new Set<string>();
    books.forEach((book: Book) => {
      const bookUrl = (book.bookUrl || '').trim();
      if (bookUrl && seenBookUrls.has(bookUrl)) return;
      if (bookUrl) seenBookUrls.add(bookUrl);
      uniqueBooks.push(book);
    });
    if (!this.shouldShowLatestExpandedTileBook()) {
      return uniqueBooks;
    }
    const latestUrls = new Set<string>(latest.map((book: Book): string => book.bookUrl.trim()));
    return uniqueBooks.filter((book: Book) => !latestUrls.has((book.bookUrl || '').trim()));
  }

  getTileFolderGroups(books: Book[] = this.books): BookGroup[] {
    const visibleGroupIds = new Set<number>();
    books.forEach((book: Book) => {
      if (book.group > 0) {
        visibleGroupIds.add(book.group);
      }
    });
    return this.shelfGroups.filter((group: BookGroup) => visibleGroupIds.has(group.groupId));
  }

  getSortedTileRootEntries(books: Book[] = this.books, mode: string = this.sortMode,
    viewKey: string = this.shelfViewKey()): ShelfTileSortEntry[] {
    // The expanded recent-read card and the ordinary grid must be derived from the same snapshot.
    // Reading-page return updates allBooks/books in separate reactive assignments; consulting allBooks here used
    // to let the new expanded card coexist with the old ordinary entry for one retained data-source generation.
    const latestBooks = this.getLatestReadTileBooks(books);
    const latestBookUrls = latestBooks.map((book: Book): string => book.bookUrl).join('|');
    const cacheKey = `${mode}_${viewKey}_${this.activeShelfGroupId}_${this.isBookMultiSelect ? '1' : '0'}_` +
      `${this.shouldShowLatestExpandedTileBook() ? latestBookUrls : ''}_` +
      `${books.map((book: Book) => `${book.bookUrl}:${book.name}:${this.getBookReadTime(book)}:${this.getBookAddTime(book)}:` +
        `${BookshelfSortHelper.getBookUpdateTime(book)}:${book.group}:${book.isPinned ? '1' : '0'}`).join('|')}_` +
      `${this.shelfGroups.map((group: BookGroup) => `${group.groupId}:${group.groupName}`).join('|')}`;
    if (cacheKey === this.shelfTileEntriesCacheKey) {
      return this.shelfTileEntriesCache;
    }
    const entries: ShelfTileSortEntry[] = [];
    // 置顶书籍在“全部”平铺页作为根级快捷项展示；它仍保留原分组归属，进入分组后也可找到。
    const ungroupedBooks = this.getTileBooksWithoutLatest(books.filter((book: Book) => book.isPinned ||
      book.group <= 0 || !this.shelfGroups.some((group: BookGroup) => group.groupId === book.group)), latestBooks);
    ungroupedBooks.forEach((book: Book, index: number) => {
      const entry = new ShelfTileSortEntry();
      entry.kind = 'book';
      entry.key = `book_${viewKey}_${book.bookUrl}`;
      entry.book = book;
      entry.readTime = this.getBookReadTime(book);
      entry.addTime = this.getBookAddTime(book);
      entry.updateTime = BookshelfSortHelper.getBookUpdateTime(book);
      entry.name = this.normalizeBookName(book.name);
      entry.pinned = book.isPinned;
      entry.originalOrder = index;
      entries.push(entry);
    });

    const bookOffset = ungroupedBooks.length;
    this.getTileFolderGroups(books).forEach((group: BookGroup, index: number) => {
      const groupBooks = books.filter((book: Book) => book.group === group.groupId);
      const entry = new ShelfTileSortEntry();
      entry.kind = 'group';
      entry.key = `group_${viewKey}_${group.groupId}`;
      entry.group = group;
      entry.readTime = this.latestTileGroupReadTime(groupBooks);
      entry.addTime = this.latestTileGroupAddTime(groupBooks);
      entry.updateTime = groupBooks.reduce((latest: number, book: Book): number =>
        Math.max(latest, BookshelfSortHelper.getBookUpdateTime(book)), 0);
      entry.name = this.normalizeBookName(group.groupName);
      entry.originalOrder = bookOffset + index;
      entries.push(entry);
    });

    entries.sort((a: ShelfTileSortEntry, b: ShelfTileSortEntry) => this.compareTileRootEntry(a, b, mode));
    this.shelfTileEntriesCacheKey = cacheKey;
    this.shelfTileEntriesCache = entries;
    return entries;
  }

  shelfListBookDataSource(pageKey: string = this.shelfPageKey()): ShelfBookDataSource {
    return this.shelfCategoryPage(pageKey).listSource;
  }

  shelfTileBookDataSource(pageKey: string = this.shelfPageKey()): ShelfBookDataSource {
    return this.shelfCategoryPage(pageKey).tileSource;
  }

  shelfTileEntryDataSource(pageKey: string = this.shelfPageKey()): ShelfTileEntryDataSource {
    return this.shelfCategoryPage(pageKey).entrySource;
  }

  latestTileGroupReadTime(books: Book[]): number {
    let latest = 0;
    books.forEach((book: Book) => {
      latest = Math.max(latest, this.getBookReadTime(book));
    });
    return latest;
  }

  latestTileGroupAddTime(books: Book[]): number {
    let latest = 0;
    books.forEach((book: Book) => {
      latest = Math.max(latest, this.getBookAddTime(book));
    });
    return latest;
  }

  compareTileRootEntry(a: ShelfTileSortEntry, b: ShelfTileSortEntry, mode: string = this.sortMode): number {
    if (a.pinned !== b.pinned) {
      return a.pinned ? -1 : 1;
    }
    if (mode === 'name') {
      const nameDiff = a.name.localeCompare(b.name, 'zh-Hans-CN-u-co-pinyin');
      return nameDiff !== 0 ? nameDiff : a.originalOrder - b.originalOrder;
    }
    const timeDiff = mode === 'recentUpdate' ? b.updateTime - a.updateTime :
      (mode === 'recentAdd' ? b.addTime - a.addTime : b.readTime - a.readTime);
    if (timeDiff !== 0) {
      return timeDiff;
    }
    const nameDiff = a.name.localeCompare(b.name, 'zh-Hans-CN-u-co-pinyin');
    return nameDiff !== 0 ? nameDiff : a.originalOrder - b.originalOrder;
  }

  getTileGroupBooks(groupId: number, books: Book[] = this.books): Book[] {
    return books.filter((book: Book) => book.group === groupId);
  }

  getTileGroupPreviewBooks(groupId: number, books: Book[] = this.books): Book[] {
    return this.getTileGroupBooks(groupId, books).slice(0, 4);
  }

  shelfTileColumnCount(): number {
    return BookTileLayout.columnCount(this.shelfTileViewportWidth);
  }

  shelfTileColumnsTemplate(): string {
    const columnCount = this.shelfTileColumnCount();
    let template = '1fr';
    for (let index = 1; index < columnCount; index++) {
      template += ' 1fr';
    }
    return template;
  }

  shelfTileColumnGap(): number {
    return BookTileLayout.columnGap(this.shelfTileViewportWidth);
  }

  shelfTileRowGap(): number {
    return Math.max(24, Math.min(30, this.shelfTileColumnGap() + 8));
  }

  shelfTileGridRowGap(books: Book[] = this.books): number {
    // 轮播卡片在 deck 内上下各留 10vp；圆点行上下对称，下方也只需 10vp。
    // 普通书籍项补回剩余行距，不改变后续书籍行之间的距离。陪伴布局顶部有多块整行内容，统一用小行距。
    if (this.shouldShowLatestExpandedTileBook() && this.isCompanionLayout()) return 10;
    return this.shouldShowLatestExpandedTileBook() && this.isLatestTileCardLarge() &&
      this.getLatestReadTileBooks(books).length > 1 ? 10 : this.shelfTileRowGap();
  }

  shelfTileExpandedCoverAspectRatio(): number {
    const columnCount = this.shelfTileColumnCount();
    const columnGap = this.shelfTileColumnGap();
    const contentWidth = BookTileLayout.contentWidth(this.shelfTileViewportWidth);
    const columnWidth = Math.max(1, (contentWidth - columnGap * (columnCount - 1)) / columnCount);
    const expandedWidth = columnWidth * 2 + columnGap;
    // 普通封面的宽高比为 0.735；跨两列后根据实际列宽换算，确保上下边缘完全对齐。
    return expandedWidth * 0.735 / columnWidth;
  }

  @Builder
  shelfTileGrid(pageKey: string) {
    Grid(this.shelfTileScrollerForPage(pageKey)) {
      GridItem() {
        Row()
          .height(this.bookshelfTileTopSpacerHeight(this.shelfBooksForPage(pageKey)))
      }
      .columnStart(0)
      .columnEnd(this.shelfTileColumnCount() - 1)

      if (this.shouldShowLatestExpandedTileBook()) {
        if (this.isCompanionLayout()) {
          GridItem() {
            this.shelfCompanionGreeting()
          }
          .columnStart(0)
          .columnEnd(this.shelfTileColumnCount() - 1)

          if (this.getLatestReadTileBooks(this.shelfBooksForPage(pageKey)).length > 0) {
          GridItem() {
            RecentReadCarousel({
              books: this.getLatestReadTileBooks(this.shelfBooksForPage(pageKey)),
              cardHeight: this.shelfCompanionHeroHeight(),
              accentColor: this.accentColor(),
              secondaryColor: this.subTextColor(),
              itemWidthRatio: 1,
              renderKey: (book: Book): string => this.shelfBookRenderKey(book, `companion_card_${pageKey}`),
              cardContent: (book: Book) => {
                this.shelfCompanionHeroCard(book, pageKey)
              },
              onOpen: (book: Book, event: GestureEvent): void => this.openRecentCarouselBook(book, event),
              onLongPress: (book: Book, event: GestureEvent): void => this.showBookActions(book, event)
            })
          }
          .columnStart(0)
          .columnEnd(this.shelfTileColumnCount() - 1)
          }

          GridItem() {
            ShelfReadingNoteCard({
              refreshKey: this.shelfCompanionNoteRefreshKey(this.shelfBooksForPage(pageKey)),
              appDarkMode: this.appDarkMode
            })
          }
          .columnStart(0)
          .columnEnd(this.shelfTileColumnCount() - 1)

          if (this.shelfBooksForPage(pageKey).length > this.getLatestReadTileBooks(this.shelfBooksForPage(pageKey)).length) {
          GridItem() {
            this.shelfCompanionSectionHeader(pageKey)
          }
          .columnStart(0)
          .columnEnd(this.shelfTileColumnCount() - 1)
          }
        } else if (this.isLatestTileCardLarge()) {
          if (this.getLatestReadTileBooks(this.shelfBooksForPage(pageKey)).length > 0) {
          GridItem() {
            RecentReadCarousel({
              books: this.getLatestReadTileBooks(this.shelfBooksForPage(pageKey)),
              cardHeight: Math.max(146, this.shelfTileLatestCardHeight()),
              accentColor: this.accentColor(),
              secondaryColor: this.subTextColor(),
              renderKey: (book: Book): string => this.shelfBookRenderKey(book, `latest_card_${pageKey}`),
              cardContent: (book: Book) => {
                this.shelfTileLatestCard(book, pageKey)
              },
              onOpen: (book: Book, event: GestureEvent): void => this.openRecentCarouselBook(book, event),
              onLongPress: (book: Book, event: GestureEvent): void => this.showBookActions(book, event)
            })
          }
          // 占满整行：宽屏列数多于三列时，旁边若再排一本书，卡片与封面高度对不齐。
          .columnStart(0)
          .columnEnd(this.shelfTileColumnCount() - 1)
          }
        } else {
          ForEach(this.getLatestReadTileBooks(this.shelfBooksForPage(pageKey)), (book: Book) => {
          GridItem() {
            this.shelfTileExpandedBook(book, pageKey)
          }
          .columnStart(0)
          .columnEnd(1)
          }, (book: Book) => this.shelfBookRenderKey(book, `expanded_${pageKey}`))
        }
      }

      if (this.shouldUseTileGroupFolders()) {
        LazyForEach(this.shelfTileEntryDataSource(pageKey), (entry: ShelfTileSortEntry) => {
          GridItem() {
            if (entry.kind === 'group' && entry.group) {
              this.shelfTileGroupFolder(entry.group, pageKey)
            } else if (entry.book) {
              this.shelfTileBook(entry.book, pageKey)
            }
          }
          .padding({ bottom: this.shelfTileRowGap() - this.shelfTileGridRowGap(this.shelfBooksForPage(pageKey)) })
        }, (entry: ShelfTileSortEntry) => entry.book ?
          this.shelfBookRenderKey(entry.book, entry.key) : entry.key)
      } else {
        LazyForEach(this.shelfTileBookDataSource(pageKey), (book: Book) => {
          GridItem() {
            this.shelfTileBook(book, pageKey)
          }
          .padding({ bottom: this.shelfTileRowGap() - this.shelfTileGridRowGap(this.shelfBooksForPage(pageKey)) })
        }, (book: Book) => this.shelfBookRenderKey(book, `tile_${pageKey}`))
      }

      GridItem() {
        Column()
          .height(this.bookshelfListBottomInset())
      }
      .columnStart(0)
      .columnEnd(this.shelfTileColumnCount() - 1)
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height('100%')
    .columnsTemplate(this.shelfTileColumnsTemplate())
    .columnsGap(this.shelfTileColumnGap())
    .rowsGap(this.shelfTileGridRowGap(this.shelfBooksForPage(pageKey)))
    .padding({ left: BookTileLayout.SIDE_PADDING, right: BookTileLayout.SIDE_PADDING, top: 10 })
    .backgroundColor(this.shelfSurfaceColor())
    .scrollBar(BarState.Off)
    .cachedCount(4)
    .onAppear(() => this.restoreShelfPageScroll(pageKey, true))
    .onDidScroll((delta: number) => {
      if (!this.tileGroupAnimating && pageKey === this.shelfPageKey()) {
        const page = this.shelfCategoryPage(pageKey);
        page.tileOffset = page.tileScroller.currentOffset().yOffset;
        this.onShelfListScroll(delta, page.tileOffset);
      }
    })
    .onScrollStop(() => {
      if (!this.tileGroupAnimating && pageKey === this.shelfPageKey()) {
        this.onShelfListScrollStop(this.shelfTileScrollerForPage(pageKey).currentOffset().yOffset);
      }
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = this.areaDimension(newValue.width);
      if (width > 0 && Math.abs(width - this.shelfTileViewportWidth) >= 1) {
        this.shelfTileViewportWidth = width;
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  shelfTileExpandedBook(book: Book, pageKey: string) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row({ space: AppSpacing.XXS }) {
          Stack({ alignContent: Alignment.TopStart }) {
            this.coverView(book, '100%', '100%', ImageFit.Fill, true, true, this.shelfCoverScope(pageKey, false))
          }
          .layoutWeight(1)
          .height('100%')
          .borderRadius({ topLeft: 7, bottomLeft: 7 })
          .clip(true)

          Column() {
            this.shelfLastReadLeaf(book)
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ left: 7, right: 7, top: 7, bottom: AppSpacing.SM })
          .backgroundColor(this.shelfTilePageColor())
          .borderRadius({ topRight: 7, bottomRight: 7 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
        .borderRadius(7)
        .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
        .clip(true)

        if (this.isBookMultiSelect) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.isBookSelected(book.bookUrl)) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(12)
                .fontColor(['#FFFFFF'])
            }
          }
          .width(22)
          .height(22)
          .backgroundColor(this.isBookSelected(book.bookUrl) ? this.buttonColor() :
            ThemeRuntime.glassPanelColor(this.appDarkMode))
          .border({ width: 1, color: this.isBookSelected(book.bookUrl) ? this.buttonColor() : this.glassBorderColor() })
          .borderRadius(11)
          .margin({ left: AppSpacing.SM, top: AppSpacing.SM })
        }
      }
      .width('100%')
      .aspectRatio(this.shelfTileExpandedCoverAspectRatio())
      .border({ width: this.isBookSelected(book.bookUrl) ? 2 : 0, color: this.accentColor() })
      .borderRadius(7)

      Row({ space: AppSpacing.XS }) {
        Text(this.shelfTileBookDisplayName(book))
          .fontSize(AppFontSize.CAPTION)
          .lineHeight(18)
          .height(36)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_WORD)
          .layoutWeight(1)
      }
      .width('100%')
      .height(36)
      .alignItems(VerticalAlign.Center)

      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(13)
          .fontColor([this.subTextColor()])
        Text(this.bookshelfShowProgressBar ? this.getReadProgressPercentText(book) : this.getShelfProgressText(book))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(18)
      .alignItems(VerticalAlign.Bottom)

      if (this.bookshelfShowProgressBar) {
        Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(3)
          .color(this.accentColor())
          .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false })
          .onAction((event: GestureEvent) => {
            if (!this.isBookMultiSelect) {
              this.showBookActions(book, event);
            }
          }),
        TapGesture()
          .onAction((event: GestureEvent) => {
            if (this.consumeShelfSwipeClick()) {
              return;
            }
            if (this.isBookMultiSelect) {
              this.toggleSelectedBook(book.bookUrl);
              return;
            }
            const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
            this.openShelfBook(book, finger ? finger.globalX : this.contextViewportWidth / 2,
              finger ? finger.globalY : this.contextViewportHeight / 2);
          })
      ),
      GestureMask.IgnoreInternal
    )
  }

  // “大”样式的中央卡片；外层轮播统一处理横滑、点击和长按。
  @Builder
  shelfTileLatestCard(book: Book, pageKey: string) {
    Row({ space: AppSpacing.LG }) {
      Column() {
        Text('继续阅读')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
          .maxLines(1)

        Text(this.shelfTileBookDisplayName(book))
          .width('100%')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_WORD)
          .margin({ top: AppSpacing.SM })

        Text(this.getReadChapterText(book) || this.getLastReadChapterText(book))
          .width('100%')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: AppSpacing.SM })

        Blank()
          .layoutWeight(1)

        Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(this.accentColor())
          .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
      .alignItems(HorizontalAlign.Start)

      Stack({ alignContent: Alignment.TopStart }) {
        this.coverView(book, '100%', '100%', ImageFit.Cover, false, true, this.shelfCoverScope(pageKey, true))
      }
      .height('100%')
      .aspectRatio(0.735)
      .borderRadius(6)
      .clip(true)
      .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
    }
    .width('100%')
    .height('100%')
    .padding(AppSpacing.XL)
    .backgroundColor(this.glassCardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
    .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(),
      offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
  }

  shelfTileColumnWidth(): number {
    const columnCount = this.shelfTileColumnCount();
    const columnGap = this.shelfTileColumnGap();
    const contentWidth = BookTileLayout.contentWidth(this.shelfTileViewportWidth);
    return Math.max(1, (contentWidth - columnGap * (columnCount - 1)) / columnCount);
  }

  shelfTileLatestCardHeight(): number {
    // 封面约占一列宽度的七成，卡片高度随之换算，宽屏多列时也不会被拉得过高。
    return Math.round(this.shelfTileColumnWidth() * 0.7 / 0.735) + AppSpacing.XL * 2;
  }

  openRecentCarouselBook(book: Book, event: GestureEvent): void {
    if (this.consumeShelfSwipeClick()) return;
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    this.openShelfBook(book, finger ? finger.globalX : this.contextViewportWidth / 2,
      finger ? finger.globalY : this.contextViewportHeight / 2);
  }

  shelfCompanionGreetingLines(): string[] {
    const hour = new Date().getHours();
    if (hour < 5) return ['夜深了，慢慢读。', '读完这一章，就早点休息吧。'];
    if (hour < 11) return ['早上好，慢慢读。', '翻开一本，日子就慢下来了。'];
    if (hour < 13) return ['中午好，慢慢读。', '歇一会儿，读上几页。'];
    if (hour < 18) return ['下午好，慢慢读。', '泡杯茶，故事还在原处等你。'];
    return ['晚上好，慢慢读。', '夜里读书，最是安静。'];
  }

  @Builder
  shelfCompanionGreeting() {
    Column({ space: AppSpacing.XS }) {
      Text(this.shelfCompanionGreetingLines()[0])
        .fontSize(AppFontSize.HEADLINE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
        .maxLines(1)
      Text(this.shelfCompanionGreetingLines()[1])
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .maxLines(1)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpacing.XS, bottom: AppSpacing.SM })
  }

  shelfCompanionHeroHeight(): number {
    return 228;
  }

  /** 卡片底部多留出底板与投影的位置，轮播槽位按圆角裁切，投影不能贴边。 */
  shelfCompanionCoverHeight(): number {
    return this.shelfCompanionHeroHeight() - AppSpacing.XS - AppSpacing.XXL * 2 + AppSpacing.XS;
  }

  shelfCompanionCoverWidth(): number {
    return Math.round(this.shelfCompanionCoverHeight() * 0.735);
  }

  shelfCompanionReadTimeText(book: Book): string {
    const readTime = this.getBookReadTime(book);
    if (readTime <= 0) return '';
    const date = new Date(readTime);
    const now = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const clock = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
    if (date.toDateString() === now.toDateString()) return `今天 ${clock}`;
    const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    if (date.toDateString() === yesterday.toDateString()) return `昨天 ${clock}`;
    return `${date.getMonth() + 1}月${date.getDate()}日 ${clock}`;
  }

  shelfCompanionNoteRefreshKey(books: Book[]): string {
    return this.getLatestReadTileBooks(books)
      .map((book: Book): string => `${book.bookUrl}:${this.getBookReadTime(book)}`).join('|');
  }

  /** 书页厚度约为封面宽度的十分之一，宽屏放大封面时一起变厚。 */
  shelfHardcoverThickness(coverWidth: number): number {
    return Math.max(6, Math.round(coverWidth * 0.1));
  }

  /** 书页条纹按像素宽度换算成渐变比例，三种纸色交替，重复铺满整个书页侧面。 */
  shelfHardcoverPageStripes(width: number): Array<[ResourceColor, number]> {
    const unit = 1 / Math.max(1, width);
    const colors = this.appDarkMode ? ['#D2C9B9', '#A99D88', '#C3B8A5'] : ['#F6EFE2', '#D9CDB7', '#EFE6D5'];
    return [[colors[0], 0], [colors[0], unit], [colors[1], unit], [colors[1], unit * 1.6],
      [colors[2], unit * 1.6], [colors[2], unit * 2.4]];
  }

  /** 底板左缘缩进、书脊阴影宽度与压槽宽度都按封面宽度缩放，网格里的小书与继续阅读的大书比例一致。 */
  shelfHardcoverBoardInset(coverWidth: number): number {
    return Math.max(3, Math.round(coverWidth * 0.043));
  }

  shelfHardcoverSpineWidth(coverWidth: number): number {
    return Math.max(6, Math.round(coverWidth * 0.11));
  }

  shelfHardcoverHingeWidth(coverWidth: number): number {
    return Math.max(2, Math.round(coverWidth * 0.03));
  }

  shelfHardcoverBoardWidth(coverWidth: number): number {
    return coverWidth + this.shelfHardcoverThickness(coverWidth) + 3 - this.shelfHardcoverBoardInset(coverWidth);
  }

  /** 精装书封面以外的部分：两层底板投影、书页侧面与封面压在书页上的窄投影，封面面板叠在它上面。 */
  @Builder
  shelfHardcoverBack(coverWidth: number, coverHeight: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      // 底板投影分两层：大而淡的落地投影、紧贴书底的接触投影。
      Column()
        .width(this.shelfHardcoverBoardWidth(coverWidth))
        .height(coverHeight + 2)
        .position({ x: this.shelfHardcoverBoardInset(coverWidth), y: 2 })
        .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 5, bottomRight: 5 })
        .backgroundColor(this.shelfHardcoverBoardColor())
        .shadow({ radius: Math.round(coverWidth * 0.19), color: this.appDarkMode ? '#99000000' : '#5250341A',
          offsetX: Math.round(coverWidth * 0.085), offsetY: Math.round(coverWidth * 0.115) })
      Column()
        .width(this.shelfHardcoverBoardWidth(coverWidth))
        .height(coverHeight + 2)
        .position({ x: this.shelfHardcoverBoardInset(coverWidth), y: 2 })
        .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 5, bottomRight: 5 })
        .backgroundColor(this.shelfHardcoverBoardColor())
        .border({ width: { right: 1 }, color: '#1FFFFFFF' })
        .shadow({ radius: 6, color: '#47000000', offsetX: 3, offsetY: 4 })

      // 书页侧面：一层纸纹，再叠左右与上下两层明暗。左端藏在封面下面，只露出靠外的一截。
      Column()
        .width(18 + this.shelfHardcoverThickness(coverWidth))
        .height(coverHeight - 4)
        .position({ x: coverWidth - 18, y: 5 })
        .borderRadius({ topRight: 2, bottomRight: 2 })
        .linearGradient({
          direction: GradientDirection.Right,
          repeating: true,
          colors: this.shelfHardcoverPageStripes(18 + this.shelfHardcoverThickness(coverWidth))
        })
      Column()
        .width(18 + this.shelfHardcoverThickness(coverWidth))
        .height(coverHeight - 4)
        .position({ x: coverWidth - 18, y: 5 })
        .borderRadius({ topRight: 2, bottomRight: 2 })
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [['#6B000000', 0], ['#14000000', 0.45], ['#4DFFFFFF', 0.82], ['#1F000000', 1]]
        })
      Column()
        .width(18 + this.shelfHardcoverThickness(coverWidth))
        .height(coverHeight - 4)
        .position({ x: coverWidth - 18, y: 5 })
        .borderRadius({ topRight: 2, bottomRight: 2 })
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#38FFFFFF', 0], ['#00FFFFFF', 0.3], ['#00000000', 0.75], ['#38000000', 1]]
        })

      // 封面压在书页上的一道窄投影。四边各缩进 1vp 藏在封面面板下面，圆角处的抗锯齿不会透出深色细边。
      Column()
        .width(coverWidth - 2)
        .height(coverHeight - 2)
        .position({ x: 1, y: 1 })
        .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 4, bottomRight: 4 })
        .backgroundColor(this.shelfHardcoverBoardColor())
        .shadow({ radius: 3, color: '#59000000', offsetX: 2, offsetY: 0 })
    }
    .width(coverWidth + this.shelfHardcoverThickness(coverWidth) + 3)
    .height(coverHeight + 4)
  }

  /** 封面面板上的打光：斜向明暗、高光带、书脊阴影、压槽与顶边亮线，盖在封面图或分组拼图上面。 */
  @Builder
  shelfHardcoverCoverLight(coverWidth: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 118,
          colors: [['#3DFFFFFF', 0], ['#00FFFFFF', 0.34], ['#00000000', 0.6], ['#42000000', 1]]
        })
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 104,
          colors: [['#00FFFFFF', 0.4], ['#1FFFFFFF', 0.47], ['#00FFFFFF', 0.54]]
        })
      Column()
        .width(this.shelfHardcoverSpineWidth(coverWidth))
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [['#80000000', 0], ['#2E000000', 0.35], ['#29FFFFFF', 0.7], ['#00000000', 1]]
        })
      Column()
        .width(this.shelfHardcoverHingeWidth(coverWidth))
        .height('100%')
        .position({ x: this.shelfHardcoverSpineWidth(coverWidth), y: 0 })
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [['#61000000', 0], ['#33FFFFFF', 0.6], ['#00000000', 1]]
        })
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('#38FFFFFF')
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  /**
   * 立着的精装书：底板比封面略宽略长、右侧露出带明暗的书页、封面上叠书脊阴影、压槽、斜向打光与高光。
   * 每层只能挂一个渐变，所以拆成多个叠放的块；封面仍走 coverView，开书动画按原作用域定位。
   */
  @Builder
  shelfHardcoverBook(book: Book, idScope: string, coverWidth: number, coverHeight: number,
    animateCovers: boolean = false, selected: boolean = false) {
    Stack({ alignContent: Alignment.TopStart }) {
      this.shelfHardcoverBack(coverWidth, coverHeight)

      Stack({ alignContent: Alignment.TopStart }) {
        // 圆角交给外面的封面面板裁，封面图自己不再裁 8vp，否则四角会露出下面的深色底板。
        this.coverView(book, '100%', '100%', ImageFit.Cover, animateCovers, true, idScope, 0,
          this.shelfHardcoverSpineWidth(coverWidth) + this.shelfHardcoverHingeWidth(coverWidth))
        this.shelfHardcoverCoverLight(coverWidth)
      }
      .width(coverWidth)
      .height(coverHeight)
      .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 4, bottomRight: 4 })
      .border({ width: selected ? 2 : 0, color: this.accentColor() })
      .clip(true)
    }
    .width(coverWidth + this.shelfHardcoverThickness(coverWidth) + 3)
    .height(coverHeight + 4)
  }

  /** 分组里扇形张开的书比单本书小一圈，张开后两侧只略微探进列间距。 */
  shelfFolderBookWidth(): number {
    return Math.max(32, Math.round(this.shelfTileHardcoverWidth() * 0.76));
  }

  shelfFolderBookHeight(): number {
    return Math.round(this.shelfFolderBookWidth() / 0.735);
  }

  /** 槽位 0 是正中立着的那本，1 向左倒、2 向右倒；先画后面两本，正中那本盖在最上面。 */
  shelfFolderFanSlots(previewBooks: Book[]): number[] {
    const count = Math.min(3, previewBooks.length);
    return count >= 3 ? [2, 1, 0] : (count === 2 ? [1, 0] : (count === 1 ? [0] : []));
  }

  shelfFolderFanAngle(slot: number): number {
    return slot === 1 ? -7 : (slot === 2 ? 7 : 0);
  }

  shelfFolderFanShift(slot: number): number {
    return slot === 1 ? -5 : (slot === 2 ? 5 : 0);
  }

  @Builder
  shelfFolderFanBook(book: Book, elementId: string, slot: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      this.shelfHardcoverBack(this.shelfFolderBookWidth(), this.shelfFolderBookHeight())

      Stack({ alignContent: Alignment.TopStart }) {
        this.coverView(book, '100%', '100%', ImageFit.Cover, true, false, '', 0,
          this.shelfHardcoverSpineWidth(this.shelfFolderBookWidth()) + this.shelfHardcoverHingeWidth(this.shelfFolderBookWidth()))
        this.shelfHardcoverCoverLight(this.shelfFolderBookWidth())
        if (slot > 0) {
          // 后面两本压暗一点，叠出前后层次。
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(slot === 2 ? '#33000000' : '#1F000000')
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .id(this.tileGroupPreviewCoverId(elementId, book))
      .width(this.shelfFolderBookWidth())
      .height(this.shelfFolderBookHeight())
      .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 4, bottomRight: 4 })
      .clip(true)
    }
    .position({
      x: Math.round((this.shelfTileColumnWidth() - this.shelfFolderBookWidth() -
        this.shelfHardcoverThickness(this.shelfFolderBookWidth()) - 3) / 2) + this.shelfFolderFanShift(slot),
      y: this.shelfTileHardcoverHeight() - this.shelfFolderBookHeight()
    })
    // 以书底中点为轴张开，三本书的书底仍落在同一条线上。
    .rotate({ angle: this.shelfFolderFanAngle(slot), centerX: '50%', centerY: '100%' })
  }

  /**
   * 陪伴布局的分组：最多三本精装书以书底为轴扇形张开。分组展开动画按 elementId 量整叠书的位置并截图、
   * 按各本封面的 id 起飞；倾斜的两本按未旋转的位置起飞，起步时会摆正。
   */
  @Builder
  shelfHardcoverFolder(previewBooks: Book[], elementId: string) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.shouldUseThemeBookCover() || previewBooks.length === 0) {
        // 主题文件夹图没有单本封面可张开，做成一本以文件夹图为封面的精装书。
        Stack({ alignContent: Alignment.TopStart }) {
          this.shelfHardcoverBack(this.shelfTileHardcoverWidth(), this.shelfTileHardcoverHeight())
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.shouldUseThemeBookCover()) {
              Image(this.activeThemeShelfFolder())
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Fill)
            } else {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor(this.shelfHardcoverBoardColor())
            }
            this.shelfHardcoverCoverLight(this.shelfTileHardcoverWidth())
          }
          .width(this.shelfTileHardcoverWidth())
          .height(this.shelfTileHardcoverHeight())
          .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 4, bottomRight: 4 })
          .clip(true)
        }
      } else {
        ForEach(this.shelfFolderFanSlots(previewBooks), (slot: number) => {
          this.shelfFolderFanBook(previewBooks[slot], elementId, slot)
        }, (slot: number) => this.shelfBookRenderKey(previewBooks[slot], `group_fan_${elementId}_${slot}`))
      }
    }
    .id(elementId)
    .width('100%')
    .height(this.shelfTileHardcoverHeight() + 4)
  }

  /** 陪伴布局的网格书：整本书（封面加书页与底板）正好占满一列宽度。 */
  shelfTileHardcoverWidth(): number {
    return Math.max(40, Math.floor((this.shelfTileColumnWidth() - 3) / 1.1));
  }

  shelfTileHardcoverHeight(): number {
    return Math.round(this.shelfTileHardcoverWidth() / 0.735);
  }

  /** 按书的地址取一个固定的数，同一本书每次都是同样的高矮和倾斜，刷新书架时不会跳。 */
  shelfBookJitterSeed(book: Book): number {
    const key = book.bookUrl || book.name || '';
    let hash = 0;
    for (let index = 0; index < key.length; index++) {
      hash = (hash * 31 + key.charCodeAt(index)) | 0;
    }
    return Math.abs(hash);
  }

  /** 书架上的书不一样高：在单本最大尺寸的 88%–100% 之间取几档。 */
  shelfTileBookScale(book: Book): number {
    const scales = [1, 0.94, 0.9, 0.97, 0.88, 1, 0.92];
    return scales[this.shelfBookJitterSeed(book) % scales.length];
  }

  /** 大多数书立正，少数几本以书底为轴微微斜靠。 */
  shelfTileBookLean(book: Book): number {
    const angles = [0, 0, -2, 0, 2.5, 0, -1.5, 0, 3, 0, 0];
    return angles[Math.floor(this.shelfBookJitterSeed(book) / 7) % angles.length];
  }

  shelfTileBookCoverWidth(book: Book): number {
    return Math.round(this.shelfTileHardcoverWidth() * this.shelfTileBookScale(book));
  }

  shelfTileBookCoverHeight(book: Book): number {
    return Math.round(this.shelfTileBookCoverWidth(book) / 0.735);
  }

  shelfHardcoverBoardColor(): string {
    return this.appDarkMode ? '#17120F' : '#3B332B';
  }

  @Builder
  shelfCompanionHeroCard(book: Book, pageKey: string) {
    Row({ space: AppSpacing.XXL }) {
      this.shelfHardcoverBook(book, this.shelfCoverScope(pageKey, true), this.shelfCompanionCoverWidth(),
        this.shelfCompanionCoverHeight())

      Column() {
        Text(this.shelfTileBookDisplayName(book))
          .width('100%')
          .fontSize(AppFontSize.HEADLINE)
          .lineHeight(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accentColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_WORD)

        Text(`${(book.author || '').trim() || '作者未知'} 著`)
          .width('100%')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: AppSpacing.XS })

        Blank()
          .layoutWeight(1)

        Text(this.shelfCompanionReadTimeText(book) ? `上次读到 · ${this.shelfCompanionReadTimeText(book)}` : '上次读到')
          .width('100%')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)

        Text(this.getLastReadChapterText(book))
          .width('100%')
          .fontSize(AppFontSize.BODY_LARGE)
          .lineHeight(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_WORD)
          .margin({ top: AppSpacing.XS })

        Row({ space: AppSpacing.XS }) {
          Text('继续阅读')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(14)
            .fontColor([this.accentColor()])
        }
        .height(34)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(17)
        .backgroundColor(this.selectedSoftBackgroundColor())
        .margin({ top: AppSpacing.MD })
      }
      .layoutWeight(1)
      .height(this.shelfCompanionCoverHeight())
      .alignItems(HorizontalAlign.Start)
      .padding({ top: AppSpacing.XXS })
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.XS, bottom: AppSpacing.XXL * 2 - AppSpacing.XS })
  }

  @Builder
  shelfCompanionSectionHeader(pageKey: string) {
    Row() {
      Text('书架里，还有故事')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Blank()
      Text(`共 ${this.shelfBooksForPage(pageKey).length} 本`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
    }
    .width('100%')
    .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.MD, bottom: AppSpacing.XS })
  }

  @Builder
  shelfFolderPreview(previewBooks: Book[], elementId: string) {
      Stack() {
        if (this.shouldUseThemeBookCover()) {
          Image(this.activeThemeShelfFolder())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
        } else {
          Grid() {
            ForEach(previewBooks, (book: Book) => {
              GridItem() {
                this.coverView(book, '100%', '100%', ImageFit.Cover, true, false)
              }
              .id(this.tileGroupPreviewCoverId(elementId, book))
            }, (book: Book) => this.shelfBookRenderKey(book, `group_${elementId}`))
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%')
          .height('100%')
          .columnsTemplate('1fr 1fr')
          .rowsTemplate('1fr 1fr')
          .columnsGap(AppSpacing.SM)
          .rowsGap(AppSpacing.SM)
          .padding(AppSpacing.MD)
          .backgroundColor(this.glassCardColor())
          .scrollBar(BarState.Off)
        }
      }
      .id(elementId)
      .width('100%')
      .aspectRatio(0.735)
      .borderRadius(7)
      .clip(true)
      .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
      .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(),
        offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })

  }

  @Builder
  shelfTileGroupFolder(group: BookGroup, pageKey: string) {
    Column({ space: AppSpacing.XS }) {
      if (this.isCompanionLayout()) {
        Column() {
          this.shelfHardcoverFolder(this.getTileGroupPreviewBooks(group.groupId, this.shelfBooksForPage(pageKey)),
            this.tileGroupElementId(group.groupId, pageKey))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        // 与单本书一样，书底下留出底板与落地投影。
        .margin({ bottom: AppSpacing.SM })
      } else {
      // Use one outer surface for both the themed folder artwork and the
      // four-cover preview so folders carry the same radius, border and shadow
      // weight as ordinary shelf cards.
      this.shelfFolderPreview(this.getTileGroupPreviewBooks(group.groupId, this.shelfBooksForPage(pageKey)),
        this.tileGroupElementId(group.groupId, pageKey))
      }

      Text(group.groupName)
        .width('100%')
        .height(36)
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(13)
          .fontColor([this.subTextColor()])
        Text(`共 ${this.getTileGroupBooks(group.groupId, this.shelfBooksForPage(pageKey)).length} 本`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      .height(18)
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          this.captureContextMenuAnchor(event);
          this.pendingBookGroup = group;
          this.showBookGroupActionMenu = true;
        })
    )
    .onClick((event: ClickEvent) => this.openTileGroupPage(group.groupId, pageKey, event.windowX, event.windowY))
  }

  @Builder
  shelfTileSelectMark(book: Book) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isBookSelected(book.bookUrl)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(12)
          .fontColor(['#FFFFFF'])
      }
    }
      .width(22)
      .height(22)
      .backgroundColor(this.isBookSelected(book.bookUrl) ? this.buttonColor() :
        ThemeRuntime.glassPanelColor(this.appDarkMode))
      .border({ width: 1, color: this.isBookSelected(book.bookUrl) ? this.buttonColor() : this.glassBorderColor() })
      .borderRadius(11)
      .margin({ left: AppSpacing.SM, top: AppSpacing.SM })
  }

  @Builder
  shelfTileBook(book: Book, pageKey: string) {
    Column({ space: AppSpacing.XS }) {
      if (this.isCompanionLayout()) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 书底对齐在同一条线上，高矮与斜靠各不相同，排出来错落一些。
          Stack() {
            this.shelfHardcoverBook(book, this.shelfCoverScope(pageKey, false), this.shelfTileBookCoverWidth(book),
              this.shelfTileBookCoverHeight(book), true, this.isBookSelected(book.bookUrl))
          }
          .position({
            x: Math.round((this.shelfTileColumnWidth() - this.shelfTileBookCoverWidth(book) -
              this.shelfHardcoverThickness(this.shelfTileBookCoverWidth(book)) - 3) / 2),
            y: this.shelfTileHardcoverHeight() - this.shelfTileBookCoverHeight(book)
          })
          .rotate({ angle: this.shelfTileBookLean(book), centerX: '50%', centerY: '100%' })
          if (this.isBookMultiSelect) {
            this.shelfTileSelectMark(book)
          }
        }
        .width('100%')
        .height(this.shelfTileHardcoverHeight() + 4)
        // 书底下要留出底板与落地投影，书名不能压在投影上。
        .margin({ bottom: AppSpacing.SM })
      } else {
      Stack({ alignContent: Alignment.TopStart }) {
        this.coverView(book, '100%', '100%', ImageFit.Cover, true, true, this.shelfCoverScope(pageKey, false))

        if (this.isBookMultiSelect) {
          this.shelfTileSelectMark(book)
        }

      }
      .width('100%')
      .aspectRatio(0.735)
      .border({
        width: this.isBookSelected(book.bookUrl) ? 2 : ThemeRuntime.glassBorderWidth(),
        color: this.isBookSelected(book.bookUrl) ? this.accentColor() : this.glassBorderColor()
      })
      .borderRadius(8)
      .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(),
        offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
      }

      Row({ space: AppSpacing.XS }) {
        Text(this.shelfTileBookDisplayName(book))
          .fontSize(AppFontSize.CAPTION)
          .lineHeight(18)
          .height(36)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_WORD)
          .layoutWeight(1)
      }
      .width('100%')
      .height(36)
      .alignItems(VerticalAlign.Center)

      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(13)
          .fontColor([this.subTextColor()])
        Text(this.bookshelfShowProgressBar ? this.getReadProgressPercentText(book) : this.getShelfProgressText(book))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(18)
      .alignItems(VerticalAlign.Bottom)

      if (this.bookshelfShowProgressBar) {
        Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(3)
          .color(this.accentColor())
          .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false })
          .onAction((event: GestureEvent) => {
            if (!this.isBookMultiSelect) {
              this.showBookActions(book, event);
            }
          }),
        TapGesture()
          .onAction((event: GestureEvent) => {
            if (this.consumeShelfSwipeClick()) {
              return;
            }
            if (this.isBookMultiSelect) {
              this.toggleSelectedBook(book.bookUrl);
              return;
            }
            const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
            this.openShelfBook(book, finger ? finger.globalX : this.contextViewportWidth / 2,
              finger ? finger.globalY : this.contextViewportHeight / 2);
          })
      ),
      GestureMask.IgnoreInternal
    )
  }

  cloudBookStatus(book: Book): string {
    const position = CloudDownloadQueue.position(this.cloudDownloadQueueRaw, `book:${book.bookUrl}`);
    if (position === 0) return this.cloudDownloadStatus || '等待下载';
    if (position > 0) return `排队 ${position}`;
    return '点击下载';
  }

  /** 单本下载后打开；连续点选多本时只下载，避免完成时抢占阅读页。 */
  async openCloudPlaceholder(book: Book, touchX: number, touchY: number): Promise<void> {
    const key = `book:${book.bookUrl}`;
    if (CloudDownloadQueue.position(this.cloudDownloadQueueRaw, key) >= 0) {
      HdsFeedback.showToast(this.cloudBookStatus(book));
      return;
    }
    const request = ++this.cloudBookOpenRequest;
    const openWhenReady = this.cloudDownloadQueueRaw === '[]';
    const context = getContext(this);
    const route = router.getState();
    try {
      const download = CloudDownloadQueue.enqueue<Book>(key, async (): Promise<Book> => {
        return await CloudAutoSync.ensureBookDownloaded(context, book,
          (done: number, total: number): void => {
            CloudDownloadQueue.status(key, total > 0 ?
              `下载 ${Math.min(100, Math.floor(done * 100 / total))}%` : '下载中');
          },
          (seconds: number): void => { CloudDownloadQueue.status(key, `${seconds}秒后继续`); });
      });
      if (!openWhenReady) HdsFeedback.showToast(`《${book.name}》已加入下载队列`);
      const ready = await download;
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      if (this.shelfComponentActive) await this.loadBooks();
      if (openWhenReady && request === this.cloudBookOpenRequest && this.shelfComponentActive &&
        router.getState().index === route.index && router.getState().path === route.path) {
        this.openShelfBook(ready, touchX, touchY);
      } else {
        HdsFeedback.showToast(`《${book.name}》下载完成`);
      }
    } catch (e) {
      const message = e instanceof Error ? e.message : '';
      HdsFeedback.showToast(message || '云端书籍下载失败，请稍后重试');
    }
  }

  openShelfBook(book: Book, touchX: number, touchY: number): void {
    if (this.shelfBookRoutePending) {
      return;
    }
    if (CloudAutoSync.isPlaceholder(book)) {
      this.openCloudPlaceholder(book, touchX, touchY);
      return;
    }
    this.cloudBookOpenRequest++;
    if (this.bookshelfBookOpenAnimation) {
      AppStorage.setOrCreate<number>(SHELF_BOOK_MOTION_UNTIL_KEY,
        Date.now() + SHELF_COVER_OPEN_START_CAP + SHELF_COVER_OPEN_DURATION + SHELF_BOOK_MOTION_SETTLE);
      // 读完回来才挪位（playShelfReorder），阅读期间书架怎么刷新这本书都留在点开的那一格。
      BookshelfSortHelper.holdReadTime(book);
    }
    this.acknowledgeShelfBookUpdate(book, true);
    // PDFs go straight to their own page (the text reader would first spend a database lookup on the format),
    // with the same cover-open animation parameters as other books.
    const pdf = LocalBookService.isPdfBook(book);
    ReaderOpenTrace.begin(book.bookUrl);
    this.shelfBookRoutePending = true;
    AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', true);
    let backdropWanted = false;
    let windowWidthPx = 0;
    let windowHeightPx = 0;
    if (this.bookshelfBookOpenAnimation) {
      // 位置要在点击的这一刻量，截图可以慢一步。
      const opening = this.shelfOpeningCover(book, touchX, touchY);
      AppStorage.setOrCreate<ShelfOpeningCover>(SHELF_OPENING_COVER_KEY, opening);
      backdropWanted = ShelfCoverLocator.usable(opening);
      windowWidthPx = Math.round(this.getUIContext().vp2px(opening.windowWidth));
      windowHeightPx = Math.round(this.getUIContext().vp2px(opening.windowHeight));
    }
    const url = pdf ? 'pages/PdfReadBook' :
      (LocalBookService.usesEpubOriginalLayout(book) ? 'pages/EpubOriginalReadBook' : 'pages/ReadBook');
    const push = (backdrop: image.PixelMap | null, pageShot: ReaderOpenSnapshot | null): void => {
      // 阅读页放大期间把这张首页图垫在整页后面，书架看起来是被翻开的书慢慢盖住，而不是一点就变成纯色。
      AppStorage.setOrCreate<image.PixelMap | null>(SHELF_OPENING_BACKDROP_KEY, backdrop);
      // 上次关书那一页的图：阅读页第一帧就盖在正文位置，不等正文排好就开始翻开。
      AppStorage.setOrCreate<image.PixelMap | null>(SHELF_OPENING_PAGE_SNAPSHOT_KEY, pageShot ? pageShot.pixelMap : null);
      AppStorage.setOrCreate<string>(`${SHELF_OPENING_PAGE_SNAPSHOT_KEY}Meta`,
        pageShot ? `${pageShot.meta.bookUrl}\n${pageShot.meta.identity}` : '');
      ReaderOpenTrace.mark(book.bookUrl, 'route-requested',
        `${backdrop ? 'backdrop' : 'no-backdrop'} ${pageShot ? 'page-snapshot' : 'no-page-snapshot'}`);
      // Router owns the entire shared transition, including its reverse. No intermediate overlay or timer.
      router.pushUrl({
        url: url,
        params: {
          bookUrl: book.bookUrl,
          formatChecked: 'true',
          shelfBookOpening: this.bookshelfBookOpenAnimation ? 'true' : 'false',
          shelfSharedCoverId: this.bookshelfBookOpenAnimation ? SharedElementMotion.coverId('shelf', book.origin, book.bookUrl) : ''
        }
      }).then(() => {
        this.shelfBookRoutePending = false;
      }).catch((error: Error) => {
        AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
        const stale = AppStorage.get<image.PixelMap | null>(SHELF_OPENING_BACKDROP_KEY) || null;
        AppStorage.setOrCreate<image.PixelMap | null>(SHELF_OPENING_BACKDROP_KEY, null);
        if (stale) stale.release().catch((): void => {});
        AppStorage.setOrCreate<image.PixelMap | null>(SHELF_OPENING_PAGE_SNAPSHOT_KEY, null);
        console.error('打开阅读页失败:', error);
        ReaderOpenTrace.cancel(book.bookUrl, 'route-failed');
        this.cancelShelfBookOpening();
      });
    };
    if (!backdropWanted) {
      this.discardShelfOpeningBackdrop();
      push(null, null);
      return;
    }
    // 两张图并行取：首页截图多半按下时已截好；上一页的图同一进程再开直接在内存里，否则解码一张 JPEG。
    const pageShot = ReaderOpenSnapshotStore.open(getContext(this), book.bookUrl, book.durChapterIndex,
      windowWidthPx, windowHeightPx, this.appDarkMode, this.themeRevision, BookshelfPage.SHELF_OPENING_BACKDROP_WAIT);
    this.takeShelfOpeningBackdrop().then((backdrop: image.PixelMap | null): void => {
      pageShot.then((shot: ReaderOpenSnapshot | null): void => push(backdrop, shot));
    }).catch((): void => push(null, null));
  }

  /** 手指按下时先截一张首页；正在截或刚截过的沿用。 */
  prewarmShelfOpeningBackdrop(): void {
    if (!this.bookshelfBookOpenAnimation || this.shelfBookRoutePending || this.isBookMultiSelect) return;
    if (this.shelfOpeningBackdropPending &&
      Date.now() - this.shelfOpeningBackdropRequestedAt < BookshelfPage.SHELF_OPENING_BACKDROP_FRESH) {
      return;
    }
    this.discardShelfOpeningBackdrop();
    this.shelfOpeningBackdropRequestedAt = Date.now();
    this.shelfOpeningBackdropPending = this.shelfBackdropSnapshot().catch((error: Error): image.PixelMap | null => {
      console.warn('书架背景截图失败:', error);
      return null;
    });
    this.shelfOpeningBackdropDiscardTimer = setTimeout((): void => {
      this.shelfOpeningBackdropDiscardTimer = -1;
      this.discardShelfOpeningBackdrop();
    }, BookshelfPage.SHELF_OPENING_BACKDROP_FRESH + 600);
  }

  /** 丢掉提前截的图（还在截的等它回来再释放）。 */
  discardShelfOpeningBackdrop(): void {
    if (this.shelfOpeningBackdropDiscardTimer >= 0) {
      clearTimeout(this.shelfOpeningBackdropDiscardTimer);
      this.shelfOpeningBackdropDiscardTimer = -1;
    }
    const pending = this.shelfOpeningBackdropPending;
    this.shelfOpeningBackdropPending = null;
    if (pending) {
      pending.then((shot: image.PixelMap | null): void => {
        if (shot) shot.release().catch((): void => {});
      });
    }
  }

  /**
   * 点开书时拿首页截图：按下时截的还新鲜就用它，否则现截；最多等 SHELF_OPENING_BACKDROP_WAIT，
   * 超时返回 null 先推阅读页，迟到的截图直接释放。
   */
  takeShelfOpeningBackdrop(): Promise<image.PixelMap | null> {
    if (!this.shelfOpeningBackdropPending ||
      Date.now() - this.shelfOpeningBackdropRequestedAt >= BookshelfPage.SHELF_OPENING_BACKDROP_FRESH) {
      this.discardShelfOpeningBackdrop();
      this.shelfOpeningBackdropRequestedAt = Date.now();
      this.shelfOpeningBackdropPending = this.shelfBackdropSnapshot().catch((): image.PixelMap | null => null);
    }
    if (this.shelfOpeningBackdropDiscardTimer >= 0) {
      clearTimeout(this.shelfOpeningBackdropDiscardTimer);
      this.shelfOpeningBackdropDiscardTimer = -1;
    }
    const pending = this.shelfOpeningBackdropPending;
    this.shelfOpeningBackdropPending = null;
    if (!pending) return Promise.resolve(null);
    return new Promise<image.PixelMap | null>((resolve: (value: image.PixelMap | null) => void): void => {
      let settled = false;
      const timer = setTimeout((): void => {
        if (settled) return;
        settled = true;
        resolve(null);
        pending.then((shot: image.PixelMap | null): void => {
          if (shot) shot.release().catch((): void => {});
        });
      }, BookshelfPage.SHELF_OPENING_BACKDROP_WAIT);
      pending.then((shot: image.PixelMap | null): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(shot);
      });
    });
  }

  /**
   * 阅读页返回前问书架：这本书的封面现在在哪（读过的书会从格子移进继续阅读卡片）。量不到或不在屏幕内返回空，
   * 阅读页就退回“合上再由共享转场缩回”的老路。
   */
  locateShelfCover(bookUrl: string): ShelfOpeningCover | null {
    if (!this.shelfComponentActive || !bookUrl) return null;
    const book = this.allBooks.find((item: Book): boolean => item.bookUrl === bookUrl);
    if (!book) return null;
    const cover = this.shelfOpeningCover(book, -1, -1);
    return cover.boundsWidth > 0 && cover.boundsHeight > 0 ? cover : null;
  }

  /** 阅读页翻开的封面与书架上看到的一致：主题封面带书框，多图取第一张，没有封面时用首字色块。 */
  shelfOpeningCover(book: Book, touchX: number = -1, touchY: number = -1): ShelfOpeningCover {
    const opening: ShelfOpeningCover = {
      bookUrl: book.bookUrl, cover: '', frame: '', color: this.getBookColor(book.name),
      initial: book.name ? book.name.substring(0, 1) : '书',
      boundsX: 0, boundsY: 0, boundsWidth: 0, boundsHeight: 0, windowWidth: 0, windowHeight: 0, cropImage: false
    };
    this.measureShelfOpeningBounds(book, opening, touchX, touchY);
    if (this.shouldUseThemeBookCover()) {
      const covers = this.activeThemeBookCovers(book);
      opening.cover = covers.length > 0 ? covers[0] : '';
      opening.frame = this.activeThemeShelfFrame();
      opening.color = this.inputColor();
    } else {
      const covers = this.getShelfCoverList(book);
      opening.cover = covers.length > 0 ? this.imageCover(covers[0]) : '';
    }
    return opening;
  }

  /**
   * 量出书架封面在窗口里的位置与窗口尺寸（vp），阅读页据此从封面处放大。
   * 同一本书可能同时出现在书架格子和继续阅读卡片里，取包含点击位置的那一枚；
   * 封面被滚出窗口或量不到时保持 0，阅读页退回到由共享转场飞封面的方式。
   */
  measureShelfOpeningBounds(book: Book, opening: ShelfOpeningCover, touchX: number, touchY: number): void {
    try {
      const ui = this.getUIContext();
      const windowRect = window.findWindow(ui.getWindowName() || '').getWindowProperties().windowRect;
      if (windowRect.width <= 0 || windowRect.height <= 0) return;
      const touchPxX = touchX >= 0 ? ui.vp2px(touchX) : -1;
      const touchPxY = touchY >= 0 ? ui.vp2px(touchY) : -1;
      let picked: componentUtils.ComponentInfo | undefined = undefined;
      let pickedLatest = false;
      const pageKey = this.shelfPageKey();
      for (const latest of [false, true]) {
        const rect = this.shelfCoverRect(ui, book, this.shelfCoverScope(pageKey, latest));
        if (!rect) continue;
        const x = rect.windowOffset.x;
        const y = rect.windowOffset.y;
        const width = rect.size.width;
        const height = rect.size.height;
        if (width <= 0 || height <= 0 || x < 0 || y < 0 || width >= windowRect.width || height >= windowRect.height ||
          x + width > windowRect.width + 1 || y + height > windowRect.height + 1) {
          continue;
        }
        const touched = touchPxX >= x && touchPxX <= x + width && touchPxY >= y && touchPxY <= y + height;
        if (touched || !picked) {
          picked = rect;
          pickedLatest = latest;
        }
        if (touched) break;
      }
      if (!picked) return;
      opening.cropImage = this.shelfCoverCropsImage(book, pageKey, pickedLatest);
      opening.boundsX = ui.px2vp(picked.windowOffset.x);
      opening.boundsY = ui.px2vp(picked.windowOffset.y);
      opening.boundsWidth = ui.px2vp(picked.size.width);
      opening.boundsHeight = ui.px2vp(picked.size.height);
      opening.windowWidth = ui.px2vp(windowRect.width);
      opening.windowHeight = ui.px2vp(windowRect.height);
    } catch (error) {
      // LazyForEach 已回收源节点等情况：没有位置就由共享转场飞封面。
    }
  }

  /**
   * 量位置用的元素 id 按分类页和位置区分：分类页是 Swiper 且缓存相邻页，同一本书会在“全部”和“小说”等页各有一份，
   * 继续阅读卡片里也有一份；只查当前页的格子和卡片，避免查到相邻页那份而退回旧动画。
   * 共享转场 id 各处相同：读过的书回到书架时会移进继续阅读卡片、离开格子，返回转场靠卡片那一枚接住。
   */
  shelfCoverScope(pageKey: string, latest: boolean): string {
    return `${latest ? 'latest_' : ''}${pageKey}_`;
  }

  /**
   * 这枚封面在书架上是否按 ImageFit.Cover 裁切显示，与 coverView 各调用处一致：继续阅读大卡片不轮播、按 Cover；
   * 小号继续阅读格（shelfTileExpandedBook）拉伸铺满；其余格子与列表里主题封面拉伸、普通封面按 Cover。
   */
  shelfCoverCropsImage(book: Book, pageKey: string, latest: boolean): boolean {
    if (latest) return true;
    if (this.shouldUseThemeBookCover()) return false;
    if (this.shouldShowLatestExpandedTileBook() && !this.isLatestTileCardLarge() &&
      this.getLatestReadTileBooks(this.shelfBooksForPage(pageKey))
        .some((item: Book): boolean => item.bookUrl === book.bookUrl)) {
      return false;
    }
    return true;
  }

  /** 读过的书只在继续阅读卡片里、不在格子里，按 id 查不到时可能直接抛错；每处单独兜住，不影响另一处。 */
  shelfCoverRect(ui: UIContext, book: Book, scope: string): componentUtils.ComponentInfo | undefined {
    try {
      return ui.getComponentUtils().getRectangleById(this.shelfCoverElementId(book, scope));
    } catch (error) {
      return undefined;
    }
  }

  shelfCoverElementId(book: Book, scope: string): string {
    return `shelf_book_cover_${scope}${encodeURIComponent(book.bookUrl)}`;
  }

  hasShelfBookUpdate(book: Book): boolean {
    return book.getVariable(SHELF_UPDATE_BADGE_VARIABLE) === '1';
  }

  acknowledgeShelfBookUpdate(book: Book, deferVisual: boolean = false): void {
    if (!book.bookUrl) {
      return;
    }
    // Remember the click while a background refresh may still be in flight, so that refresh cannot
    // write the badge back after the user has already entered this book.
    this.shelfUpdateAcknowledgedAt.set(book.bookUrl, Date.now());
    if (!this.hasShelfBookUpdate(book)) {
      return;
    }
    this.persistShelfBookUpdateAcknowledgement(book.bookUrl).catch((e: Error) => {
      console.error('清除书架更新标记失败:', book.name, e);
    });
    if (!deferVisual) {
      this.applyShelfBookUpdateAcknowledgement(book.bookUrl);
      return;
    }
    // 点开书时立刻改内存里的书列表，路由会在建阅读页之前先把整个书架同步重建、重排（点击事件里约 20ms）。
    // 封面马上就被阅读页盖住，角标晚些去掉看不出来；若动作窗口内已从库里重载过（角标已清），这里什么都不做。
    setTimeout((): void => {
      if (!this.shelfComponentActive) return;
      this.applyShelfBookUpdateAcknowledgement(book.bookUrl);
    }, this.shelfBookMotionDelay() + 120);
  }

  private applyShelfBookUpdateAcknowledgement(bookUrl: string): void {
    const book = this.allBooks.find((item: Book): boolean => item.bookUrl === bookUrl);
    if (!book || !this.hasShelfBookUpdate(book)) return;
    book.putVariable(SHELF_UPDATE_BADGE_VARIABLE, '');
    this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === bookUrl ? book : item);
    this.applyShelfScope();
    this.reloadShelfDataSources(true);
  }

  async persistShelfBookUpdateAcknowledgement(bookUrl: string): Promise<void> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    const current = await db.getBook(bookUrl);
    if (!current || !this.hasShelfBookUpdate(current)) {
      return;
    }
    current.putVariable(SHELF_UPDATE_BADGE_VARIABLE, '');
    await db.updateBook(current, false, 'shelf_update_badge_acknowledged');
  }

  closeShelfBook(bookUrl: string): void {
    this.cancelShelfBookOpening();
    if (this.loadTimer >= 0) {
      clearTimeout(this.loadTimer);
      this.loadTimer = -1;
    }
    AppStorage.setOrCreate<number>(SHELF_BOOK_MOTION_UNTIL_KEY,
      Date.now() + SHELF_COVER_OPEN_DURATION + SHELF_BOOK_MOTION_SETTLE);
    this.shelfReturnMotionActive = true;
    const refresh = (): void => {
      this.shelfBookReturnRefreshTimer = -1;
      this.playShelfReorder(bookUrl)
        .catch((error: Error) => {
          console.warn('返回书架时刷新进度失败:', error);
          this.clearShelfReorderLayers();
        })
        .finally((): void => {
          // 首页盖着阅读页留下的书架截图，等这次重建画出来再揭开；挪位中途出错也照样报（已报过的再报一次无妨）。
          AppStorage.setOrCreate<number>('shelfReturnRefreshNonce', Date.now());
          BookshelfSortHelper.releaseReadTimes();
          this.shelfReturnMotionActive = false;
        });
    };
    // This notification arrives after the cover has closed, immediately before router.back().
    // 阅读页自己缩回时（随后交来首页盖图）返回转场是 0 时长，很快就能刷新；否则等共享转场飞完，保持源节点不动。
    // 盖图在同一轮里紧接着交来，下一轮才看得到；期限仍从此刻算。
    const closedAt = Date.now();
    this.shelfBookReturnRefreshTimer = setTimeout((): void => {
      const selfClosed = !!AppStorage.get<image.PixelMap | null>('shelfReturnBackdrop');
      const refreshAt = closedAt + (selfClosed ? BookshelfPage.SHELF_RETURN_QUICK_REFRESH :
        SHELF_COVER_OPEN_DURATION + SHELF_BOOK_MOTION_SETTLE);
      AppStorage.setOrCreate<number>(SHELF_BOOK_MOTION_UNTIL_KEY, refreshAt);
      this.shelfBookReturnRefreshTimer = setTimeout(refresh, Math.max(0, refreshAt - Date.now()));
    }, 0);
  }

  /**
   * 关书落地后把读过的书挪到新位置：先用当前书架的截图盖住，在它下面放开按住的阅读时间、按新顺序重建
   * （新位置在屏幕外就先滚回顶部），再让一枚封面从原来那一格飞到新位置，截图同时淡出。
   * 位置没变、量不到、截不到图时直接刷新。首页的盖图在这之后才揭开，下面的重排与滚动都看不见。
   */
  async playShelfReorder(bookUrl: string): Promise<void> {
    const held = BookshelfSortHelper.heldReadTime(bookUrl);
    const book = this.allBooks.find((item: Book): boolean => item.bookUrl === bookUrl);
    const from = held !== undefined && book ? this.measureShelfReorderCover(book, false) : undefined;
    let fresh: Book | undefined = undefined;
    if (from && book) {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      fresh = await db.getBook(bookUrl) || undefined;
    }
    BookshelfSortHelper.releaseReadTimes();
    const moved = !!fresh && held !== undefined && BookshelfSortHelper.getBookReadTime(fresh) > held;
    const curtain = moved ? await this.snapshotTileGroupElement('bookshelf_motion_root') : undefined;
    if (!moved || !curtain || !book || !from || !this.shelfComponentActive) {
      this.releaseTileGroupShot(curtain);
      await this.loadBooks(true);
      // 首页盖着阅读页留下的书架截图，等这次重建画出来再揭开。
      AppStorage.setOrCreate<number>('shelfReturnRefreshNonce', Date.now());
      return;
    }
    this.shelfReorderCurtain = curtain;
    this.shelfReorderCurtainOpacity = 1;
    this.tileGroupHiddenCovers = [bookUrl];
    await this.waitShelfFrames(1);
    await this.loadBooks(true);
    await this.waitShelfFrames(2);
    let to = this.measureShelfReorderCover(book, true);
    if (!to) {
      // 新位置滚出了屏幕（多半是列表往下翻过，书挪到了最前面）：截图挡着时滚回顶部再量。
      try {
        if (this.isTileLayout()) this.shelfTileScroller.scrollEdge(Edge.Top);
        else this.shelfListScroller.scrollEdge(Edge.Top);
      } catch (_) {
      }
      await this.waitShelfFrames(2);
      to = this.measureShelfReorderCover(book, true);
    }
    const current = this.allBooks.find((item: Book): boolean => item.bookUrl === bookUrl) || book;
    const travels = !!to && (Math.abs(to.x - from.x) > 1 || Math.abs(to.y - from.y) > 1);
    if (to && travels) {
      this.tileGroupFlyProgress = 0;
      this.tileGroupFlyers = [this.makeShelfReorderFlyer(current, from, to)];
    }
    AppStorage.setOrCreate<number>('shelfReturnRefreshNonce', Date.now());
    // 首页盖图在刷新通知后 120ms 揭开，揭开时下面就是这张一模一样的截图，再开始飞。
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, BookshelfPage.SHELF_REORDER_START_DELAY);
    });
    if (travels) {
      // 截图比封面早一点淡完：飞到一半时下面已经是新顺序的书架，只有这一本还在路上。
      this.getUIContext().animateTo({ duration: BookshelfPage.SHELF_REORDER_CURTAIN_FADE, curve: Curve.EaseOut },
        (): void => {
          this.shelfReorderCurtainOpacity = 0;
        });
      await new Promise<void>((resolve: () => void): void => {
        this.getUIContext().animateTo({ duration: BookshelfPage.SHELF_REORDER_DURATION,
          curve: curves.cubicBezierCurve(0.2, 0, 0, 1), expectedFrameRateRange: SHELF_GROUP_FRAME_RATE,
          onFinish: (): void => resolve() }, (): void => {
          this.tileGroupFlyProgress = 1;
        });
      });
    } else {
      await new Promise<void>((resolve: () => void): void => {
        this.getUIContext().animateTo({ duration: BookshelfPage.SHELF_REORDER_CURTAIN_FADE, curve: Curve.EaseOut,
          onFinish: (): void => resolve() }, (): void => {
          this.shelfReorderCurtainOpacity = 0;
        });
      });
    }
    // 封面先在新位置露出来，下一帧再撤飞行封面，中间不空一帧。
    this.tileGroupHiddenCovers = [];
    await this.waitShelfFrames(1);
    this.clearShelfReorderLayers();
  }

  clearShelfReorderLayers(): void {
    this.tileGroupHiddenCovers = [];
    this.tileGroupFlyers = [];
    this.tileGroupFlyProgress = 0;
    const shot = this.shelfReorderCurtain;
    this.shelfReorderCurtain = undefined;
    setTimeout((): void => this.releaseTileGroupShot(shot), 200);
  }

  /**
   * 这本书在当前分类页上看得见的那枚封面（相对书架根节点，vp）。同一本书可能同时在格子和继续阅读卡片里：
   * 挪位前优先取格子（点开的那一格），挪位后优先取卡片（新位置）。
   */
  measureShelfReorderCover(book: Book, preferLatest: boolean): SharedElementBounds | undefined {
    const pageKey = this.shelfPageKey();
    const order: boolean[] = preferLatest ? [true, false] : [false, true];
    for (const latest of order) {
      const rect = this.measureTileGroupRect(this.shelfCoverElementId(book, this.shelfCoverScope(pageKey, latest)));
      if (rect && rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= this.contextViewportWidth + 1 &&
        rect.y + rect.height <= this.contextViewportHeight + 1) {
        return rect;
      }
    }
    return undefined;
  }

  makeShelfReorderFlyer(book: Book, from: SharedElementBounds, to: SharedElementBounds): TileGroupFlyer {
    const flyer = this.makeTileGroupFlyer(book, from, to);
    if (this.shouldUseThemeBookCover()) {
      const covers = this.activeThemeBookCovers(book);
      if (covers.length > 0) {
        flyer.cover = covers[0];
        flyer.fill = true;
      }
    }
    return flyer;
  }

  waitShelfFrames(frames: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      let remaining = Math.max(1, frames);
      let done = false;
      const finish = (): void => {
        if (done) return;
        done = true;
        resolve();
      };
      const tick = (): void => {
        remaining--;
        if (remaining > 0) post();
        else finish();
      };
      const post = (): void => {
        try {
          this.getUIContext().postFrameCallback(new ShelfGroupNextFrame(tick));
        } catch (error) {
          finish();
        }
      };
      // 页面不在前台时帧回调不来，兜底不卡住。
      setTimeout(finish, 60 * Math.max(1, frames));
      post();
    });
  }

  cancelShelfBookOpening(): void {
    if (this.shelfBookReturnRefreshTimer >= 0) {
      clearTimeout(this.shelfBookReturnRefreshTimer);
      this.shelfBookReturnRefreshTimer = -1;
    }
    this.shelfBookRoutePending = false;
  }

  @Builder
  compactBookContent(book: Book, pageKey: string) {
    Column({ space: AppSpacing.MD }) {
      Row() {
        // 封面高度 = 信息块高度，顶部对齐书名行、底部对齐进度条底部。
        this.coverView(book, this.shelfCoverWidth(this.shelfCompactInfoHeight()),
          this.shelfCompactInfoHeight(), ImageFit.Cover, true, true, this.shelfCoverScope(pageKey, false))

        Column({ space: this.shelfRowSpace() }) {
          Row({ space: AppSpacing.SM }) {
            Text(this.shelfTileBookDisplayName(book))
              .fontSize(AppFontSize.BODY_LARGE)
              .lineHeight(this.shelfTitleLineHeight())
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.getShelfAuthorText(book))
            .fontSize(AppFontSize.BODY)
            .lineHeight(this.shelfTextLineHeight())
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.getShelfUpdateLineText(book)) {
            Text(this.getShelfUpdateLineText(book))
              .fontSize(AppFontSize.BODY)
              .lineHeight(this.shelfTextLineHeight())
              .fontColor(this.secondaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          // 恒定的 Blank：某本书没有更新行时由它吸收多余空间，尾部仍被顶到底部。
          Blank()

          if (this.bookshelfShowProgressBar) {
            this.readProgressPanel(book)
          } else {
            Row() {
              Text(this.getShelfProgressText(book))
                .fontSize(AppFontSize.CAPTION)
                .lineHeight(this.shelfSmallTextLineHeight())
                .fontColor(this.subTextColor())
            }
          }
        }
        .layoutWeight(1)
        .height(this.shelfCompactInfoHeight())
        .margin({ left: AppSpacing.LG })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.bookExtraContent(book)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.LG)
  }

  @Builder
  looseBookContent(book: Book, pageKey: string) {
    Column({ space: AppSpacing.MD }) {
      Row() {
        // 封面高度 = 信息块高度，顶部对齐书名行、底部对齐阅读进度行。
        this.coverView(book, this.shelfCoverWidth(this.shelfLooseInfoHeight()),
          this.shelfLooseInfoHeight(), ImageFit.Cover, true, true, this.shelfCoverScope(pageKey, false))

        Column({ space: this.shelfRowSpace() }) {
          Row({ space: AppSpacing.SM }) {
            Text(this.shelfTileBookDisplayName(book))
              .fontSize(AppFontSize.BODY_LARGE)
              .lineHeight(this.shelfTitleLineHeight())
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.getShelfAuthorText(book))
            .fontSize(AppFontSize.BODY)
            .lineHeight(this.shelfTextLineHeight())
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.getShelfUpdateLineText(book)) {
            Text(this.getShelfUpdateLineText(book))
              .fontSize(AppFontSize.BODY)
              .lineHeight(this.shelfTextLineHeight())
              .fontColor(this.secondaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          // 恒定的 Blank：某本书没有更新行时由它吸收多余空间，尾部仍被顶到底部。
          Blank()

          Row() {

            // 与作者名保持一致的格式（字号 14 + 次级文字色）。
            Text(this.getShelfProgressText(book))
              .fontSize(AppFontSize.BODY)
              .lineHeight(this.shelfTextLineHeight())
              .fontColor(this.secondaryTextColor())
          }
        }
        .layoutWeight(1)
        .height(this.shelfLooseInfoHeight())
        .margin({ left: AppSpacing.LG })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.bookExtraContent(book)

      if (this.bookshelfShowProgressBar) {
        this.looseReadProgressPanel(book)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.LG)
  }

  @Builder
  bookExtraContent(book: Book) {
    if (this.bookshelfShowIntro && this.getBookIntroText(book)) {
      Text(this.getBookIntroText(book))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .lineHeight(18)
        .maxLines(LocalBookService.isLocalBook(book) ? 2 : (this.bookshelfShowFullIntro ? 999 : 2))
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxHeight: LocalBookService.isLocalBook(book) ? 36 : 10000 })
        .clip(true)
        .width('100%')
    }

    if (this.bookshelfShowTags && this.getDisplayTags(book).length > 0) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.getDisplayTags(book), (tag: string, index: number) => {
          this.tagChip(tag, index, 11)
        })
      }
      .width('100%')
    }
  }

  getBookIntroText(book: Book): string {
    const rawIntro = LocalBookService.isLocalBook(book) ? book.intro : book.getDisplayIntro();
    const intro = (rawIntro || '')
      .replace(/\s+/g, ' ')
      .trim();
    if (LocalBookService.isLocalBook(book) && intro.length > 52) {
      return `${intro.substring(0, 52).trim()}…`;
    }
    return intro;
  }

  @Builder
  coverView(book: Book, width: Length, height: Length, imageFit: ImageFit, animateCovers: boolean = true, measure: boolean = true,
    idScope: string = '', radius: number = 8, spineInset: number = -1) {
    Stack() {
      if (this.shouldUseThemeBookCover()) {
        if (this.activeThemeBookCovers(book).length === 1 || !animateCovers) {
          Image(this.activeThemeBookCovers(book)[0])
            .width(width)
            .height(height)
            .objectFit(animateCovers ? ImageFit.Fill : imageFit)
            // 返回书架后进度变了的卡片会整体重建，封面异步加载会先空一帧；本地封面同步解码，让关书动画落地后无缝。
            .syncLoad(true)
        } else {
          Swiper() {
            ForEach(this.activeThemeBookCovers(book), (cover: ResourceStr, index: number) => {
              Image(cover)
                .width(width)
                .height(height)
                .objectFit(ImageFit.Fill)
                // 返回书架后进度变了的卡片会整体重建，封面异步加载会先空一帧；本地封面同步解码，让关书动画落地后无缝。
                .syncLoad(true)
            }, (_cover: ResourceStr, index: number) => `${book.bookUrl}_theme_${index}`)
          }
          .width(width)
          .height(height)
          .autoPlay(true)
          .interval(this.themeBookCoverInterval(book))
          .indicator(false)
          .loop(true)
        }
        Image(this.activeThemeShelfFrame())
          .width(width)
          .height(height)
          .objectFit(ImageFit.Fill)
      } else if (this.getShelfCoverList(book).length === 0) {
        Column() {
          Text(book.name ? book.name.substring(0, 1) : '书')
            .fontSize(28)
            .fontColor('#FFFFFF')
        }
        .width(width)
        .height(height)
        .backgroundColor(this.getBookColor(book.name))
        .justifyContent(FlexAlign.Center)
      } else if (this.getShelfCoverList(book).length === 1 || !animateCovers) {
        Image(this.imageCover(this.getShelfCover(book, animateCovers)))
          .width(width)
          .height(height)
          .objectFit(imageFit)
      } else {
        Swiper() {
          ForEach(this.getShelfCoverList(book), (cover: string) => {
            Image(this.imageCover(cover))
              .width(width)
              .height(height)
              .objectFit(imageFit)
              // 返回书架后进度变了的卡片会整体重建，封面异步加载会先空一帧；本地封面同步解码，让关书动画落地后无缝。
              .syncLoad(true)
          }, (cover: string) => cover)
        }
        .width(width)
        .height(height)
        .autoPlay(true)
        .interval(3500)
        .indicator(false)
        .loop(true)
      }
      if (CloudAutoSync.isPlaceholder(book)) {
        // 云端占位书显示当前进度或排队位置，其他书仍可继续点选下载。
        Stack({ alignContent: Alignment.Center }) {
          if (CloudDownloadQueue.position(this.cloudDownloadQueueRaw, `book:${book.bookUrl}`) >= 0) {
            Text(this.cloudBookStatus(book))
              .fontSize(AppFontSize.MICRO)
              .fontColor('#FFFFFF')
              .maxLines(2)
              .textAlign(TextAlign.Center)
          } else {
            SymbolGlyph($r('sys.symbol.download'))
              .fontSize(16)
              .fontColor(['#FFFFFF'])
          }
        }
        .width(CloudDownloadQueue.position(this.cloudDownloadQueueRaw, `book:${book.bookUrl}`) >= 0 ?
          (typeof width === 'number' ? Math.min(width, 64) : 64) : 32)
        .height(32)
        .borderRadius(16)
        .backgroundColor('#73000000')
        .accessibilityText(`${book.name}在云端，${this.cloudBookStatus(book)}`)
      }
      BookshelfCoverBadges({
        configuration: this.bookshelfCoverBadges,
        typeLabel: this.bookTypeBadgeText(book), typeColor: this.bookTypeBadgeColor(book),
        sourceText: LocalBookService.isLocalBook(book) ? '本地' : (book.originName || book.origin || '').trim(),
        unreadCount: book.totalChapterNum > 0 ? book.getUnreadChapterNum() : 0,
        updated: this.hasShelfBookUpdate(book), pinned: book.isPinned, offline: this.hasOfflineContent(book),
        selecting: this.isBookMultiSelect, spineInset: spineInset
      })
    }
    .id(measure ? this.shelfCoverElementId(book, idScope) : '')
    .sharedTransition(measure && this.bookshelfBookOpenAnimation ? SharedElementMotion.coverId('shelf', book.origin, book.bookUrl) : '', {
      duration: SHELF_COVER_OPEN_DURATION, curve: Curve.EaseInOut, type: SharedTransitionEffectType.Exchange
    })
    .width(width)
    .height(height)
    .borderRadius(radius)
    .clip(true)
    .backgroundColor(this.inputColor())
    .grayscale(CloudAutoSync.isPlaceholder(book) ? 1 : 0)
    .opacity(measure && this.tileGroupHiddenCovers.length > 0 && this.tileGroupHiddenCovers.includes(book.bookUrl) ? 0 :
      (CloudAutoSync.isPlaceholder(book) ? 0.6 : 1))
    .onAppear(() => this.ensureShelfBookCoverCache(book))
  }

  bookTypeBadgeText(book: Book): string {
    if (BookTypeSupport.isVideo(book)) return '视';
    if (BookTypeSupport.isAudio(book)) return '声';
    if (BookTypeSupport.isImage(book)) return '漫';
    return '书';
  }

  bookTypeBadgeColor(book: Book): string {
    if (BookTypeSupport.isVideo(book)) return '#D64560';
    if (BookTypeSupport.isAudio(book)) return '#D9822B';
    if (BookTypeSupport.isImage(book)) return '#8B5CF6';
    return '#3978C5';
  }

  activeThemeBookCovers(book: Book): ResourceStr[] {
    return ThemeBookCoverSettings.covers(book, this.appDarkMode);
  }

  shouldUseThemeBookCover(): boolean {
    return ThemeBookCoverSettings.enabled(this.appDarkMode, this.themeBookCoverEnabled);
  }

  themeBookCoverInterval(book: Book): number {
    return ThemeBookCoverSettings.interval(book);
  }

  activeThemeShelfFrame(): ResourceStr {
    return ThemeBookCoverSettings.frame(this.appDarkMode);
  }

  activeThemeShelfFolder(): ResourceStr {
    return ThemeAssetRegistry.themeShelfFolder(ThemeRuntime.bookTokens(this.appDarkMode).shelfFolderAssetId);
  }

  /** Image 能直接加载的封面地址；加密的书源封面在解密完成前为空。 */
  imageCover(raw: string): string {
    return this.sourceCoverRevision >= 0 ? BookCoverCache.displayCover(getContext(this), raw) : raw;
  }

  getShelfCover(book: Book, animateCovers: boolean = true): string {
    const covers = this.getShelfCoverList(book);
    return covers.length > 0 ? (animateCovers ? BookDisplayHelper.pickCover(covers) : covers[0]) : '';
  }

  getShelfCoverList(book: Book): string[] {
    const covers = CoverGallerySettings.getDisplayCoverList(
      book,
      this.appDarkMode,
      this.bookshelfCoverAlbums,
      this.bookshelfLightCoverAlbumId,
      this.bookshelfDarkCoverAlbumId,
      this.bookshelfCoverApplyScope,
      this.bookshelfCoverTargetBooks,
      this.bookshelfIgnoreSourceCover,
      this.bookshelfCoverMode
    );
    const displayCovers: string[] = [];
    for (let i = 0; i < covers.length; i++) {
      const raw = covers[i];
      const key = this.shelfCoverKey(book, i);
      const cached = this.shelfCoverRawUrls.get(key) === raw ? (this.shelfCoverMap.get(key) || '') : '';
      displayCovers.push(cached || raw);
    }
    return displayCovers;
  }

  shelfCoverKey(book: Book, index: number): string {
    return `${book.bookUrl}#${index}`;
  }

  @Builder
  tagChip(tag: string, index: number, fontSize: number) {
    Text(tag)
      .fontSize(fontSize)
      .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 3, bottom: 3 })
      .attributeModifier(BookDisplayHelper.getTagModifier(index, this.appDarkMode))
      .margin({ left: AppSpacing.XS, bottom: AppSpacing.SM })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  actionItem(label: string, color: string, action: () => void) {
    Button(label)
      .width('100%')
      .height(44)
      .margin({ top: AppSpacing.SM })
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      .fontColor(color)
      .onClick(action)
  }


  onBookshelfSystemDialogFlagChanged(): void {
    if (!this.showCacheDialog) this.cacheDialogSession.close(this.getUIContext());
    if (!this.showChapterCacheDialog) this.chapterCacheDialogSession.close(this.getUIContext());
  }

  @Builder
  cacheDialogContent() {
    Column() {
      Text(`${this.cacheTargetIsAudio() ? '下载' : '缓存'}《${this.cacheTargetBook?.name || '当前书籍'}》`)
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.MD })

      if (this.cacheStatus) {
        Text(this.cacheStatus)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: AppSpacing.MD })
      }

      this.actionItem(this.isCacheTargetBookCaching() ? (this.cacheTargetIsAudio() ? '正在下载...' : '正在缓存...') :
        (this.cacheTargetIsAudio() ? '下载全部音频' : '缓存全文'), this.primaryTextColor(), () => {
        this.cacheWholeBook();
      })
      this.actionItem(this.cacheTargetIsAudio() ? '下载指定章节' : '缓存指定章节', this.primaryTextColor(), () => {
        this.showCacheDialog = false;
        this.showChapterCacheDialog = true;
        if (this.cacheTargetBook) {
          this.loadCacheChapters(this.cacheTargetBook);
        }
        this.chapterCacheDialogSession.open(this.getUIContext(), (): void => {
          this.chapterCacheDialogContent();
        }, {
          autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
          warnTag: '显示章节缓存弹窗失败:'
        });
      })
      this.actionItem(this.cacheTargetIsAudio() ? '删除已下载音频' : '清除已缓存章节', ThemeRuntime.dangerColor(this.appDarkMode), () => {
        this.clearCachedChapters();
      })

      Button('取消')
        .width('100%')
        .height(44)
        .margin({ top: 10 })
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .fontColor(this.primaryTextColor())
        .onClick(() => {
          this.closeCacheDialog();
        })
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
  }

  @Builder
  chapterCacheDialogContent() {
    Column() {
      Row() {
        Text(this.cacheTargetIsAudio() ? '选择章节下载' : '选择章节缓存')
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.primaryTextColor(),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          materialScale: 0.83,
          compactLayout: true,
          accessibilityLabel: '关闭',
          onBack: () => this.closeCacheDialog()
        })
      }
      .width('100%')
      .height(46)
      .alignItems(VerticalAlign.Center)

      if (this.cacheStatus) {
        Text(this.cacheStatus)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .margin({ bottom: AppSpacing.MD })
      }

      Row({ space: AppSpacing.MD }) {
        TextInput({ placeholder: '章节范围，如 1-10、1,3,5-8', text: this.cacheRangeDraft })
          .type(InputType.Normal)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .layoutWeight(1)
          .height(42)
          .padding({ left: 10, right: 10 })
          .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .enabled(!this.isCacheTocLoading)
          .onChange((value: string) => {
            this.cacheRangeDraft = value;
          })
        Button(this.cacheTargetIsAudio() ? '下载' : '缓存')
          .width(96)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(this.buttonColor())
          .enabled(this.cacheChapters.length > 0)
          .onClick(() => this.cacheChapterRange())
      }
      .width('100%')
      .margin({ bottom: AppSpacing.MD })

      List({ space: AppSpacing.XXS }) {
        ForEach(this.cacheChapters, (chapter: BookChapter, index: number) => {
          ListItem() {
            Row({ space: AppSpacing.MD }) {
              Text(chapter.title)
                .fontSize(AppFontSize.BODY_LARGE)
                .fontColor(chapter.cacheDate > 0 ? this.cachedChapterTextColor() : this.primaryTextColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (chapter.cacheDate > 0) {
                Text(this.cacheTargetIsAudio() ? '已下载' : '已缓存')
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(ThemeRuntime.successColor(this.appDarkMode))
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
                  .backgroundColor(ThemeRuntime.successSurfaceColor(this.appDarkMode))
                  .borderRadius(ThemeRuntime.smallRadius())
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.XXS, right: AppSpacing.XXS, top: AppSpacing.LG, bottom: AppSpacing.LG })
            .onClick(() => {
              this.cacheSingleChapter(index);
            })
          }
        })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height(380)
    }
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
  }

  @Builder
  contextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    PopupMenuAction(icon, label, color, action)
  }

  multiSelectBottomPadding(): number {
    return Math.max(this.navBarHeight, 8) + 6;
  }

  addEditingTag(): void {
    const tag = this.tagInput.trim();
    if (!tag || this.editingTags.includes(tag)) {
      this.tagInput = '';
      return;
    }
    this.editingTags = [...this.editingTags, tag];
    this.tagInput = '';
  }

  removeEditingTag(tag: string): void {
    this.editingTags = this.editingTags.filter(item => item !== tag);
  }

  async saveCustomTags(): Promise<void> {
    if (!this.pendingActionBook) return;
    this.addEditingTag();
    const book = this.pendingActionBook;
    const sourceTags = BookDisplayHelper.splitTags(book.kind, '');
    const customTags = this.editingTags.filter(tag => !sourceTags.includes(tag));
    const hiddenTags = sourceTags
      .filter(tag => !this.editingTags.includes(tag))
      .map(tag => `!${tag}`);
    book.customTag = BookDisplayHelper.joinTags([...customTags, ...hiddenTags]);
    await this.updateShelfBook(book);
    this.closeTagDialog();
    HdsFeedback.showToast('标签已保存');
  }

  closeEditBookInfoDialog(): void {
    this.showEditBookInfoDialog = false;
    this.editBookInfoDialogSession.close(this.getUIContext());
    this.editingBookName = '';
    this.editingBookAuthor = '';
    this.pendingActionBook = null;
  }

  async saveLocalBookInfo(): Promise<void> {
    const target = this.pendingActionBook;
    const name = this.editingBookName.trim();
    const author = this.editingBookAuthor.trim();
    if (!target || !LocalBookService.isLocalBook(target)) {
      this.closeEditBookInfoDialog();
      return;
    }
    if (!name) {
      HdsFeedback.showToast('书名不能为空');
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const book = await db.getBook(target.bookUrl);
      if (!book || !LocalBookService.isLocalBook(book)) {
        HdsFeedback.showToast('书籍已不在书架中');
        this.closeEditBookInfoDialog();
        return;
      }
      book.name = name;
      book.author = author;
      book.putVariable('localMetadataCustomized', '1');
      book.putVariable('localCustomName', name);
      book.putVariable('localCustomAuthor', author);
      await db.updateBook(book);
      await db.updateBookBookmarkMetadata(book.bookUrl, name, author);
      this.allBooks = this.allBooks.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
      this.applyShelfScope();
      this.closeEditBookInfoDialog();
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('书籍信息已保存');
    } catch (e) {
      console.error('保存本地书籍信息失败:', e);
      HdsFeedback.showToast('保存失败');
    }
  }

  /** 有声书的"缓存"是把音频下载到本地，界面文字跟着改成"下载"。 */
  cacheTargetIsAudio(): boolean {
    return !!this.cacheTargetBook && BookTypeSupport.isAudio(this.cacheTargetBook);
  }

  /** "N章已缓存 M章待缓存"；有声书说已下载。 */
  cacheSummaryText(chapters: BookChapter[]): string {
    const cachedCount = this.countCachedChapters(chapters);
    const word = this.cacheTargetIsAudio() ? '下载' : '缓存';
    return `${cachedCount}章已${word} ${chapters.length - cachedCount}章待${word}`;
  }

  private showCacheFeedback(message: string): void {
    HdsFeedback.showToast(message);
  }

  async openCacheDialog(book: Book): Promise<void> {
    this.cacheTargetBook = book;
    this.cacheChapters = [];
    this.cacheStatus = this.isBookCaching(book) ? this.currentFullTextCacheDialogStatus(book) : '正在加载目录...';
    this.cacheRangeDraft = '';
    this.cacheDialogOpenedAt = Date.now();
    this.showCacheDialog = true;
    this.cacheDialogSession.open(this.getUIContext(), (): void => {
      this.cacheDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示缓存弹窗失败:'
    });
    // The catalog is loaded even while a background task runs so the panel can show which chapters
    // are already cached; the task uses its own engine, so this cannot disturb it.
    this.loadCacheChapters(book);
  }

  applyShelfScope(invalidatePages: boolean = true): void {
    if (invalidatePages) this.shelfCategoryRevision++;
    this.refreshShelfTypeTabs();
    this.books = this.sortBooks(this.booksForShelfScope(this.shelfScope));
    if (this.books.length === 0) {
      this.showShelfMoreMenu = false;
    }
  }

  /**
   * 按普通书架（当前分组）里实际有的类型重建分类栏。当前类型没书时只在显示上回到第一项
   * （见 activeShelfTypeTab），不改写用户选的类型：书架数据一时不全也不会把选择丢掉。
   * 关闭“书籍分类”时只有“全部”一页；关闭“显示全部分类”时去掉“全部”，一本书都没有时仍留着它当空页。
   */
  refreshShelfTypeTabs(): void {
    let ids: string[] = ['all'];
    if (this.bookshelfTypeCategoryEnabled) {
      const present: boolean[] = BookshelfPage.TYPE_TAB_IDS.map((): boolean => false);
      for (const book of this.allBooks) {
        if (!book.isPrivate && this.matchesShelfGroup(book)) {
          present[BookshelfPage.TYPE_TAB_IDS.indexOf(this.shelfBookType(book))] = true;
        }
      }
      const typeIds: string[] = BookshelfPage.TYPE_TAB_IDS.filter((_id: string, index: number) =>
        index === 0 ? this.bookshelfShowAllTypeTab : present[index]);
      if (typeIds.length > 0) ids = typeIds;
    }
    if (ids.join(',') !== this.shelfTypeTabIds.join(',')) {
      this.shelfTypeTabIds = ids;
    }
  }

  /** 实际显示的分类：选中的类型不在分类栏里时按第一项（通常是“全部”）显示。 */
  activeShelfTypeTab(): string {
    return this.shelfTypeTabIds.indexOf(this.shelfTypeTab) >= 0 ? this.shelfTypeTab : (this.shelfTypeTabIds[0] || 'all');
  }

  /** 标题旁的书本数；隐私书架不在分类栏里，在这里标出当前位置。 */
  shelfHeaderCountText(): string {
    const count = this.books.length > 0 ? `${this.books.length}本` : '分组';
    return this.shelfScope === 'private' ? `隐私 · ${count}` : count;
  }

  shelfScopeEmptyHint(pageKey: string = this.shelfPageKey()): string {
    if (this.shelfAppliedSearchKeyword) {
      const hint = `没有找到与“${this.shelfSearchKeyword.trim()}”相关的书籍`;
      return this.shelfFilterKeyList().length > 0 ? `${hint}，也可以清除筛选条件再试` : hint;
    }
    if (pageKey === 'private') {
      return '长按书籍并选择“标记为隐私”，即可移入隐私书架';
    }
    if (this.shelfFilterKeyList().length > 0) {
      return '没有符合筛选条件的书籍，可在右上角筛选里调整';
    }
    return '搜索书籍或添加本地书籍吧';
  }

  booksForShelfScope(scope: string): Book[] {
    return this.allBooks.filter((book: Book) => this.isInShelfView(book, scope) &&
      this.matchesShelfFilters(book) && this.matchesShelfSearch(book));
  }

  /** 当前书架页（普通/隐私、分组、分类栏类型）里的书，不看筛选和关键词。 */
  isInShelfView(book: Book, scope: string): boolean {
    const privateScope = scope === 'private';
    // 隐私书籍只出现在隐私书架里；隐私书架关闭后它们继续隐藏。
    if (book.isPrivate !== privateScope || !this.matchesShelfGroup(book)) return false;
    const typeTab = this.activeShelfTypeTab();
    return privateScope || typeTab === 'all' || this.shelfBookType(book) === typeTab;
  }

  matchesShelfGroup(book: Book): boolean {
    return this.activeShelfGroupId === 0 ||
      (this.activeShelfGroupId === -1 ? book.group <= 0 : book.group === this.activeShelfGroupId);
  }

  /** 与书籍角标同一优先级：视频 > 有声 > 漫画 > 小说。 */
  shelfBookType(book: Book): string {
    if (BookTypeSupport.isVideo(book)) return 'video';
    if (BookTypeSupport.isAudio(book)) return 'audio';
    if (BookTypeSupport.isImage(book)) return 'image';
    return 'text';
  }

  shelfTypeTabLabel(type: string): string {
    if (type === 'text') return '小说';
    if (type === 'image') return '漫画';
    if (type === 'audio') return '有声书';
    if (type === 'video') return '视频';
    return '全部';
  }

  shelfFilterKeyList(): string[] {
    if (!this.shelfFilterKeys) {
      return [];
    }
    return BookshelfPage.canonicalShelfFilterKeys(this.shelfFilterKeys.split(','));
  }

  /** 固定键按 FILTER_GROUPS 的顺序排在前，标签、书源键按选中先后排在后，去重并丢掉不认识的键。 */
  static canonicalShelfFilterKeys(keys: string[]): string[] {
    const result: string[] = [];
    BookshelfPage.FILTER_GROUPS.forEach((group: string[]) => {
      group.forEach((key: string) => {
        if (keys.indexOf(key) >= 0) result.push(key);
      });
    });
    keys.forEach((key: string) => {
      if (BookshelfPage.isDynamicShelfFilterKey(key) && result.indexOf(key) < 0) result.push(key);
    });
    return result;
  }

  static isDynamicShelfFilterKey(key: string): boolean {
    return (key.startsWith(SHELF_FILTER_TAG_PREFIX) && key.length > SHELF_FILTER_TAG_PREFIX.length) ||
      (key.startsWith(SHELF_FILTER_ORIGIN_PREFIX) && key.length > SHELF_FILTER_ORIGIN_PREFIX.length);
  }

  static shelfFilterKeyFor(prefix: string, value: string): string {
    return `${prefix}${encodeURIComponent(value)}`;
  }

  /** 标签、书源键里的名字；固定键原样返回。 */
  static shelfFilterKeyValue(key: string): string {
    const prefix = key.startsWith(SHELF_FILTER_TAG_PREFIX) ? SHELF_FILTER_TAG_PREFIX :
      (key.startsWith(SHELF_FILTER_ORIGIN_PREFIX) ? SHELF_FILTER_ORIGIN_PREFIX : '');
    if (!prefix) return key;
    try {
      return decodeURIComponent(key.substring(prefix.length));
    } catch (e) {
      return key.substring(prefix.length);
    }
  }

  /** 键所属的组：固定组用下标，标签为 'tag'，书源为 'origin'。 */
  static shelfFilterGroupOf(key: string): string {
    if (key.startsWith(SHELF_FILTER_TAG_PREFIX)) return 'tag';
    if (key.startsWith(SHELF_FILTER_ORIGIN_PREFIX)) return 'origin';
    const index = BookshelfPage.FILTER_GROUPS.findIndex((group: string[]) => group.indexOf(key) >= 0);
    return `${index}`;
  }

  /**
   * 同一组里选的多项取并集，各组之间取交集；某组一项都没选就不按这组限制。
   * 例：网络 + 已完结 = 网络书里已完结的；网络 + 本地 = 不限来源；标签选“玄幻”“都市”= 带其中任一个标签。
   */
  matchesShelfFilters(book: Book): boolean {
    const keys = this.shelfFilterKeyList();
    if (keys.length === 0) {
      return true;
    }
    const groups: string[] = [];
    keys.forEach((key: string) => {
      const group = BookshelfPage.shelfFilterGroupOf(key);
      if (groups.indexOf(group) < 0) groups.push(group);
    });
    const now = Date.now();
    return groups.every((group: string) => keys.some((key: string) =>
      BookshelfPage.shelfFilterGroupOf(key) === group && this.matchesShelfFilterKey(key, book, now)));
  }

  matchesShelfFilterKey(key: string, book: Book, now: number): boolean {
    if (key.startsWith(SHELF_FILTER_TAG_PREFIX)) {
      return BookDisplayHelper.getBookTags(book).indexOf(BookshelfPage.shelfFilterKeyValue(key)) >= 0;
    }
    if (key.startsWith(SHELF_FILTER_ORIGIN_PREFIX)) {
      return this.shelfBookOriginName(book) === BookshelfPage.shelfFilterKeyValue(key);
    }
    if (key === 'network' || key === 'local') return (LocalBookService.isLocalBook(book) ? 'local' : 'network') === key;
    if (key === 'finished' || key === 'ongoing') return (this.isShelfBookFinished(book) ? 'finished' : 'ongoing') === key;
    if (BookshelfPage.FILTER_PROGRESS_KEYS.indexOf(key) >= 0) return this.shelfReadProgressKey(book) === key;
    if (key === 'updated') return this.hasShelfBookUpdate(book);
    const readTime = this.getBookReadTime(book);
    if (key === 'read7d') return readTime > 0 && now - readTime <= 7 * SHELF_DAY_MS;
    if (key === 'read30d') return readTime > 0 && now - readTime <= 30 * SHELF_DAY_MS;
    if (key === 'stale90d') {
      // 从没打开过的书按加入书架的时间算，方便一起清理放了很久没看的书。
      const lastTouched = readTime > 0 ? readTime : this.getBookAddTime(book);
      return lastTouched <= 0 || now - lastTouched > 90 * SHELF_DAY_MS;
    }
    return false;
  }

  /** 书源筛选只看网络书，按书源名归并；本地书的书源名是文件来源，不参与。 */
  shelfBookOriginName(book: Book): string {
    if (LocalBookService.isLocalBook(book)) return '';
    return (book.originName || book.origin || '').trim();
  }

  /** 当前书架页里出现过的标签，按本数从多到少；已选但当前页没有的标签也留着，方便取消。 */
  shelfTagFilterOptions(): ShelfFilterOption[] {
    return this.buildShelfFilterOptions(SHELF_FILTER_TAG_PREFIX, (book: Book) => BookDisplayHelper.getBookTags(book));
  }

  shelfOriginFilterOptions(): ShelfFilterOption[] {
    return this.buildShelfFilterOptions(SHELF_FILTER_ORIGIN_PREFIX, (book: Book) => {
      const name = this.shelfBookOriginName(book);
      return name ? [name] : [];
    });
  }

  buildShelfFilterOptions(prefix: string, valuesOf: (book: Book) => string[]): ShelfFilterOption[] {
    const counts: Map<string, number> = new Map();
    this.allBooks.forEach((book: Book) => {
      if (!this.isInShelfView(book, this.shelfScope)) return;
      const seen: string[] = [];
      valuesOf(book).forEach((raw: string) => {
        const value = raw.trim();
        if (!value || seen.indexOf(value) >= 0) return;
        seen.push(value);
        counts.set(value, (counts.get(value) || 0) + 1);
      });
    });
    this.shelfFilterKeyList().forEach((key: string) => {
      if (key.startsWith(prefix)) {
        const value = BookshelfPage.shelfFilterKeyValue(key);
        if (!counts.has(value)) counts.set(value, 0);
      }
    });
    const options: ShelfFilterOption[] = [];
    counts.forEach((count: number, value: string) => {
      const option = new ShelfFilterOption();
      option.key = BookshelfPage.shelfFilterKeyFor(prefix, value);
      option.label = value;
      option.count = count;
      options.push(option);
    });
    options.sort((a: ShelfFilterOption, b: ShelfFilterOption) => b.count !== a.count ? b.count - a.count :
      a.label.localeCompare(b.label, 'zh-Hans-CN-u-co-pinyin'));
    return options;
  }

  /** 与书籍卡片上的“未读 / N章未读 / 已读完”一致。 */
  shelfReadProgressKey(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return 'unread';
    }
    return this.getReadProgressValue(book) >= 100 ? 'readDone' : 'reading';
  }

  /** 转小写、去掉首尾空白、中间连续空白并成一个空格；空格分开的每个词都要命中。 */
  static normalizeShelfSearchText(text: string): string {
    return (text || '').trim().toLowerCase().split(/\s+/).filter((term: string) => term.length > 0).join(' ');
  }

  /** 关键词按书名、作者、书源名和标签（含自定义标签）匹配，不区分大小写，忽略字段里的空白。 */
  matchesShelfSearch(book: Book): boolean {
    const keyword = this.shelfAppliedSearchKeyword;
    if (!keyword) {
      return true;
    }
    const fields: string[] = [book.name || '', book.author || '', book.originName || '',
      ...BookDisplayHelper.getBookTags(book)];
    const text = fields.join('|').toLowerCase().replace(/\s+/g, '');
    return keyword.split(' ').every((term: string) => text.indexOf(term) >= 0);
  }

  onShelfSearchKeywordChanged(): void {
    if (this.shelfSearchApplyTimer >= 0) {
      clearTimeout(this.shelfSearchApplyTimer);
      this.shelfSearchApplyTimer = -1;
    }
    // 清空时立即恢复全部书籍；打字时等输入停顿再筛。
    if (!this.shelfSearchKeyword.trim()) {
      this.applyShelfSearchKeyword();
      return;
    }
    this.shelfSearchApplyTimer = setTimeout(() => {
      this.shelfSearchApplyTimer = -1;
      this.applyShelfSearchKeyword();
    }, SHELF_SEARCH_APPLY_DELAY_MS);
  }

  applyShelfSearchKeyword(): void {
    const next = BookshelfPage.normalizeShelfSearchText(this.shelfSearchKeyword);
    if (next === this.shelfAppliedSearchKeyword) {
      return;
    }
    this.shelfAppliedSearchKeyword = next;
    this.applyShelfScope();
    this.reloadShelfDataSources(true);
    this.refreshShelfCoverCache(this.books);
    this.scrollShelfToTop();
  }

  scrollShelfToTop(): void {
    try {
      if (this.isTileLayout()) {
        this.shelfTileScroller.scrollEdge(Edge.Top);
      } else {
        this.shelfListScroller.scrollEdge(Edge.Top);
      }
    } catch (e) {
      // 筛完没有书时列表不在，滚动控制器没挂上，不需要滚。
    }
  }

  openShelfSearch(): void {
    this.showShelfFilterMenu = false;
    if (this.shelfSearchActive) {
      this.getUIContext().getFocusController().requestFocus(SHELF_SEARCH_INPUT_KEY);
      return;
    }
    this.getUIContext().animateTo({
      duration: 240,
      curve: Curve.EaseOut,
      onFinish: (): void => {
        // 等搜索栏展开后再唤起键盘，避免键盘挤压布局打断入场动画。
        if (this.shelfComponentActive && this.shelfSearchActive) {
          this.getUIContext().getFocusController().requestFocus(SHELF_SEARCH_INPUT_KEY);
        }
      }
    }, (): void => {
      this.shelfSearchActive = true;
    });
  }

  closeShelfSearch(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.shelfSearchKeyword = '';
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, (): void => {
      this.shelfSearchActive = false;
    });
  }

  /** 来源只筛了本地时，下拉刷新改为重新扫描本地书。 */
  shelfShowsLocalOnly(): boolean {
    const keys = this.shelfFilterKeyList();
    return this.shelfScope !== 'private' && keys.indexOf('local') >= 0 && keys.indexOf('network') < 0;
  }

  /** 书架结果缓存按完整筛选条件区分；单本书的节点身份不跟着分类改变。 */
  shelfViewKey(): string {
    return `${this.shelfScope}-${this.activeShelfTypeTab()}-${this.shelfFilterKeys}-${this.shelfAppliedSearchKeyword}`;
  }

  shelfBookViewPrefix(layout: string): string {
    // 同一本书跨分类、筛选保留已解码封面；普通/隐私书架和不同布局仍隔离。
    return `${layout}_${this.shelfScope}`;
  }

  shelfCategoryPage(key: string): ShelfCategoryPage {
    let page = this.shelfCategoryPages.get(key);
    if (!page) {
      page = new ShelfCategoryPage();
      this.shelfCategoryPages.set(key, page);
    }
    const privateAllowed = this.privateShelfEnabled &&
      (!this.privateShelfHasPassword || this.privateShelfRevealed || this.shelfScope === 'private');
    const signature = `${this.shelfCategoryRevision}:${this.activeShelfGroupId}:${this.sortMode}:` +
      `${this.bookshelfLayoutMode}:${this.bookshelfLastReadPinMode}:${this.bookshelfLastReadPinCount}:` +
      `${this.isBookMultiSelect}:${this.shelfFilterKeys}:${this.shelfAppliedSearchKeyword}:${privateAllowed}`;
    if (signature !== page.signature) {
      page.signature = signature;
      page.books = key === 'private' && !privateAllowed ? [] : this.sortBooks(this.allBooks.filter((book: Book): boolean =>
        book.isPrivate === (key === 'private') && this.matchesShelfGroup(book) &&
        (key === 'all' || key === 'private' || this.shelfBookType(book) === key) &&
        this.matchesShelfFilters(book) && this.matchesShelfSearch(book)));
      if (!this.isTileLayout()) page.listSource.replace(page.books, true);
      else if (this.shouldUseTileGroupFolders()) {
        page.entrySource.replace(this.getSortedTileRootEntries(page.books, this.sortMode, key), true);
      } else page.tileSource.replace(this.getTileBooksWithoutLatest(page.books), true);
    }
    if (key === this.shelfPageKey()) {
      this.shelfListScroller = page.listScroller;
      this.shelfTileScroller = page.tileScroller;
    }
    return page;
  }

  shelfBooksForPage(key: string): Book[] { return this.shelfCategoryPage(key).books; }

  shelfListScrollerForPage(key: string): ListScroller { return this.shelfCategoryPage(key).listScroller; }

  shelfTileScrollerForPage(key: string): Scroller { return this.shelfCategoryPage(key).tileScroller; }

  restoreShelfPageScroll(key: string, tile: boolean): void {
    const page = this.shelfCategoryPage(key);
    const offset = tile ? page.tileOffset : page.listOffset;
    if (offset <= 0) return;
    setTimeout((): void => {
      if (!this.shelfComponentActive) return;
      try {
        if (tile) page.tileScroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
        else page.listScroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
      } catch (_) {
        // 页已被原生懒加载回收时保留记录，下一次挂载再恢复。
      }
    }, 0);
  }

  canSelectShelfPage(key: string): boolean {
    if (this.isBookMultiSelect || this.isTileGroupPage() || !this.shelfPageOrder().includes(key)) return false;
    if (key === 'private' && this.privateShelfHasPassword && !this.privateShelfRevealed && this.shelfScope !== 'private') {
      if (this.privateShelfUnlockDialogSession.isOpen() || this.privateShelfBiometricPending ||
        this.privateShelfBiometricQueued) return false;
      if (!this.privateShelfBiometric || !BiometricAuth.isAvailable()) this.openPrivateShelfUnlockDialog();
      else if (this.shelfContentTouching) this.privateShelfBiometricQueued = true;
      else this.startPrivateShelfBiometricUnlock(false);
      return false;
    }
    return true;
  }

  /** 当前所在页：分类栏里的类型，或隐私书架 'private'。 */
  shelfPageKey(): string {
    return this.shelfScope === 'private' ? 'private' : this.activeShelfTypeTab();
  }

  /** 左右滑动的页序：分类栏里显示的类型，隐私书架开启时接在最后。 */
  shelfPageOrder(): string[] {
    const pages: string[] = [...this.shelfTypeTabIds];
    if (this.privateShelfEnabled) {
      pages.push('private');
    }
    return pages;
  }

  setShelfPage(page: string): void {
    const toPrivate = page === 'private' && this.privateShelfEnabled;
    const nextScope = toPrivate ? 'private' : 'all';
    const nextType = toPrivate ? this.shelfTypeTab : (this.shelfTypeTabIds.indexOf(page) >= 0 ? page : 'all');
    if (this.shelfScope === nextScope && this.shelfTypeTab === nextType) return;
    const typeChanged = this.shelfTypeTab !== nextType;
    this.shelfScope = nextScope;
    this.shelfTypeTab = nextType;
    // 只记类型；隐私书架不记，下次打开回到普通书架。
    if (typeChanged && this.shelfStateRestored) {
      BookshelfStateStore.saveTypeTab(getContext(this), nextType).catch((e: Error) => {
        console.warn('保存书架分类状态失败:', e);
      });
    }
    this.showShelfMoreMenu = false;
    this.showShelfFilterMenu = false;
    this.applyShelfScope(false);
    this.shelfCategoryPage(this.shelfPageKey());
    // 保留仍在进行的封面任务，避免连续切分类反复失效并重新发起相同请求。
    this.books.slice(0, SHELF_COVER_INITIAL_PREFETCH_COUNT)
      .forEach((book: Book): void => this.ensureShelfBookCoverCache(book));
  }



  markShelfScopePanGesture(durationMs: number): void {
    this.suppressShelfBookClickUntil = Date.now() + durationMs;
  }

  consumeShelfSwipeClick(): boolean {
    if (Date.now() > this.suppressShelfBookClickUntil) {
      this.suppressShelfBookClickUntil = 0;
      return false;
    }
    this.suppressShelfBookClickUntil = 0;
    return true;
  }

  /** 设置里打开后，双击顶部标题栏进入隐私书架（有密码先验证），在隐私书架里双击回到原来的分类。 */
  toggleShelfPrivateByHeaderDoubleTap(): void {
    if (!this.privateShelfEnabled || !this.privateShelfHeaderDoubleTap) return;
    this.switchShelfScopeBySelection(this.shelfScope === 'private' ? this.activeShelfTypeTab() : 'private');
  }

  switchShelfScopeBySelection(page: string): void {
    if (this.shelfScopeSwapTimer >= 0 || this.shelfScopeFinishTimer >= 0) {
      return;
    }
    const pages: string[] = this.shelfPageOrder();
    const currentIndex = pages.indexOf(this.shelfPageKey());
    const nextIndex = pages.indexOf(page);
    if (currentIndex < 0 || nextIndex < 0 || currentIndex === nextIndex) {
      return;
    }
    if (this.canSelectShelfPage(page)) this.setShelfPage(page);
  }

  @Builder
  privateShelfUnlockDialogContent() {
    Column() {
      Text('隐私书架')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 18 })

      TextInput({ placeholder: '请输入隐私书架密码', text: this.privateShelfPasswordInput })
        .type(InputType.Password)
        .width('100%')
        .height(44)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.privateShelfPasswordInput = value;
          this.privateShelfPasswordError = '';
        })
        .onSubmit(() => this.submitPrivateShelfUnlock())

      if (this.privateShelfPasswordError) {
        Text(this.privateShelfPasswordError)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .width('100%')
          .margin({ top: AppSpacing.MD })
      }

      if (this.privateShelfBiometricUsable) {
        Text('使用指纹或人脸')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.buttonColor())
          .padding({ top: AppSpacing.MD, bottom: AppSpacing.SM })
          .margin({ top: AppSpacing.SM })
          .onClick(() => this.startPrivateShelfBiometricUnlock(true))
      }

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closePrivateShelfUnlockDialog())

        Button('确定')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(this.privateShelfPasswordInput.length > 0)
          .opacity(this.privateShelfPasswordInput.length > 0 ? 1 : 0.45)
          .onClick(() => this.submitPrivateShelfUnlock())
      }
      .width('100%')
      .margin({ top: 22 })
    }
    .padding(AppSpacing.XXL)
  }

  openPrivateShelfUnlockDialog(error: string = ''): void {
    this.privateShelfPasswordInput = '';
    this.privateShelfPasswordError = error;
    this.privateShelfBiometricUsable = this.privateShelfBiometric && BiometricAuth.isAvailable();
    this.privateShelfUnlockDialogSession.open(this.getUIContext(), (): void => {
      this.privateShelfUnlockDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示隐私书架密码弹窗失败:'
    });
  }

  closePrivateShelfUnlockDialog(): void {
    this.privateShelfUnlockDialogSession.close(this.getUIContext());
    this.privateShelfPasswordInput = '';
    this.privateShelfPasswordError = '';
  }

  async submitPrivateShelfUnlock(): Promise<void> {
    const input = this.privateShelfPasswordInput;
    if (!input) return;
    let passed = false;
    try {
      passed = await PrivateShelfStore.verifyPassword(getContext(this), input);
    } catch (e) {
      console.warn('校验隐私书架密码失败:', e);
    }
    if (!passed) {
      this.privateShelfPasswordError = '密码不正确';
      return;
    }
    this.closePrivateShelfUnlockDialog();
    this.revealPrivateShelfAfterUnlock();
  }

  /** 系统认证框盖在最上层；从密码框里发起时密码框保留，没通过还能接着输密码。 */
  async startPrivateShelfBiometricUnlock(fromPasswordDialog: boolean): Promise<void> {
    if (this.privateShelfBiometricPending) return;
    this.privateShelfBiometricPending = true;
    let outcome = BiometricAuthOutcome.FAILED;
    try {
      outcome = await BiometricAuth.authenticate('进入隐私书架', fromPasswordDialog ? undefined : '使用密码');
    } finally {
      this.privateShelfBiometricPending = false;
    }
    if (outcome === BiometricAuthOutcome.SUCCESS) {
      this.closePrivateShelfUnlockDialog();
      this.revealPrivateShelfAfterUnlock();
      return;
    }
    if (fromPasswordDialog) {
      if (outcome === BiometricAuthOutcome.FAILED) this.privateShelfPasswordError = '未通过验证，请输入密码';
      return;
    }
    // 关掉认证框也给密码框：带锁屏密码的认证框没有“使用密码”按钮，关掉就是改用密码的唯一途径。
    this.openPrivateShelfUnlockDialog(outcome === BiometricAuthOutcome.FAILED ? '未通过验证，请输入密码' : '');
  }

  revealPrivateShelfAfterUnlock(): void {
    if (this.privateShelfEnabled && this.shelfScope !== 'private' && !this.shelfScopeSwitchAnimating) {
      this.privateShelfRevealed = true;
      this.setShelfPage('private');
    }
  }



  animateShelfContentUpdate(update: () => void, outgoingX: number): void {
    this.clearShelfScopeTransition(false);
    this.shelfScopeSwitchAnimating = true;
    animateTo({ duration: 110, curve: Curve.EaseIn }, () => {
      this.shelfScopeTransitionX = outgoingX;
      this.shelfScopeTransitionScale = 0.988;
      this.shelfScopeTransitionOpacity = 0.16;
    });
    this.shelfScopeSwapTimer = setTimeout(() => {
      this.shelfScopeSwapTimer = -1;
      update();
      this.shelfScopeTransitionX = -outgoingX;
      this.shelfScopeTransitionScale = 0.988;
      this.shelfScopeTransitionOpacity = 0.16;
      animateTo({ duration: 210, curve: Curve.Friction }, () => {
        this.shelfScopeTransitionX = 0;
        this.shelfScopeTransitionScale = 1;
        this.shelfScopeTransitionOpacity = 1;
      });
      this.shelfScopeFinishTimer = setTimeout(() => {
        this.shelfScopeFinishTimer = -1;
        this.shelfScopeSwitchAnimating = false;
      }, 230);
    }, 115);
  }

  clearShelfScopeTransition(resetVisuals: boolean = true): void {
    if (this.shelfScopeSwapTimer >= 0) {
      clearTimeout(this.shelfScopeSwapTimer);
      this.shelfScopeSwapTimer = -1;
    }
    if (this.shelfScopeFinishTimer >= 0) {
      clearTimeout(this.shelfScopeFinishTimer);
      this.shelfScopeFinishTimer = -1;
    }
    this.shelfScopeSwitchAnimating = false;
    if (resetVisuals) {
      this.shelfScopeTransitionX = 0;
      this.shelfScopeTransitionScale = 1;
      this.shelfScopeTransitionOpacity = 1;
    }
  }

  /**
   * Closing the panel never stops a running cache task. Range and single-chapter caching now run as
   * background tasks, so the panel is only a launcher and can always be dismissed.
   */
  closeCacheDialog(): void {
    this.showCacheDialog = false;
    this.showChapterCacheDialog = false;
    this.cacheTargetBook = null;
    this.cacheChapters = [];
    this.cacheStatus = '';
    this.cacheRangeDraft = '';
    this.isCacheTocLoading = false;
    this.cacheTocLoadToken++;
    this.cacheTocLoadBookUrl = '';
    this.cacheTocLoadPromise = null;
    this.pendingActionBook = null;
  }

  isCacheTargetBookCaching(): boolean {
    return this.isBookCaching(this.cacheTargetBook);
  }

  isBookCaching(book: Book | null): boolean {
    const bookUrl = book?.bookUrl || '';
    return !!bookUrl && this.fullTextCacheTasks.has(bookUrl);
  }

  currentFullTextCacheDialogStatus(book: Book): string {
    const task = this.getShelfFullTextCacheTask(book.bookUrl);
    if (task) {
      return task.status || this.shelfFullTextCacheProgressText(task);
    }
    return '正在加载目录...';
  }

  setFullTextCacheStatus(task: ShelfFullTextCacheTask, status: string): void {
    task.status = status;
    if (this.cacheTargetBook?.bookUrl && this.cacheTargetBook.bookUrl === task.bookUrl) {
      this.cacheStatus = status;
    }
  }

  onFullTextCacheCancelNonceChanged(): void {
    const nonce = this.fullTextCacheCancelNonce || 0;
    if (!this.isCaching || nonce <= 0) {
      return;
    }
    const signal = this.parseFullTextCacheCancelSignal();
    if (signal) {
      const task = this.findShelfFullTextCacheTaskBySignal(signal);
      if (!task || task.cancelSeenNonce === signal.nonce) {
        return;
      }
      this.beginStoppingShelfFullTextCache(task, signal.nonce, true);
      return;
    }
    let stopped = false;
    this.fullTextCacheTasks.forEach((task: ShelfFullTextCacheTask) => {
      if (task.cancelSeenNonce !== nonce) {
        this.beginStoppingShelfFullTextCache(task, nonce, false);
        stopped = true;
      }
    });
    if (stopped) {
      HdsFeedback.showToast('正在停止缓存…');
    }
  }

  onFullTextCacheCancelSignalChanged(): void {
    const signal = this.parseFullTextCacheCancelSignal();
    if (!signal || !this.isCaching) {
      return;
    }
    const task = this.findShelfFullTextCacheTaskBySignal(signal);
    if (!task || task.cancelSeenNonce === signal.nonce) {
      return;
    }
    this.beginStoppingShelfFullTextCache(task, signal.nonce, true);
  }

  async loadCacheChapters(book: Book, forceRefresh: boolean = false): Promise<boolean> {
    if (!book.bookUrl) {
      this.cacheStatus = '书籍地址为空';
      return false;
    }
    if (!forceRefresh && this.cacheTocLoadPromise && this.cacheTocLoadBookUrl === book.bookUrl) {
      return await this.cacheTocLoadPromise;
    }
    if (!forceRefresh && this.cacheTargetBook?.bookUrl === book.bookUrl && this.cacheChapters.length > 0) {
      return true;
    }
    const token = ++this.cacheTocLoadToken;
    this.cacheTocLoadBookUrl = book.bookUrl;
    this.isCacheTocLoading = true;
    if (this.cacheChapters.length === 0) {
      this.cacheStatus = '正在加载目录...';
    }
    const task = this.loadCacheChaptersInternal(book, token);
    this.cacheTocLoadPromise = task;
    try {
      return await task;
    } finally {
      if (token === this.cacheTocLoadToken) {
        this.isCacheTocLoading = false;
        this.cacheTocLoadPromise = null;
      }
    }
  }

  async loadCacheChaptersInternal(book: Book, token: number): Promise<boolean> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const engine = ReadBookEngine.createBackgroundWorker();
      await engine.openBook(book);
      await engine.syncChapterCacheDates();
      if (token !== this.cacheTocLoadToken || this.cacheTargetBook?.bookUrl !== book.bookUrl ||
        engine.book?.bookUrl !== book.bookUrl) {
        return false;
      }
      const chapters = [...engine.chapters];
      this.cacheChapters = chapters;
      // A running background task owns the status line; its per-chapter progress is more useful
      // than the catalog summary, and the list already marks every cached chapter.
      if (this.isBookCaching(book)) {
        return chapters.length > 0;
      }
      if (chapters.length > 0) {
        this.cacheStatus = this.cacheSummaryText(chapters);
      } else {
        this.cacheStatus = '暂未获取到目录';
      }
      return chapters.length > 0;
    } catch (e) {
      console.error('加载缓存目录失败:', e);
      if (token === this.cacheTocLoadToken && this.cacheTargetBook?.bookUrl === book.bookUrl &&
        !this.isBookCaching(book)) {
        this.cacheStatus = '目录加载失败，请稍后重试';
        HdsFeedback.showToast('目录加载失败');
      }
      return false;
    }
  }

  async cacheWholeBook(): Promise<void> {
    if (!this.cacheTargetBook || this.isCacheTargetBookCaching()) {
      return;
    }
    if (Date.now() - this.cacheDialogOpenedAt < 300) {
      return;
    }
    const book = this.cacheTargetBook;
    if (!book.origin || book.origin === 'local') {
      HdsFeedback.showToast('本地书籍无需缓存');
      return;
    }
    if (BookTypeSupport.isAudio(book)) {
      const network = await AudioOfflineDownloadPrompt.prepare(this.getUIContext(), this.appDarkMode);
      if (network === AudioOfflineDownloadPrompt.CANCEL) return;
      this.closeCacheDialog();
      this.showCacheFeedback('已转入后台下载，可在通知栏取消');
      this.startShelfCacheTask(book, [], '音频', network === AudioOfflineDownloadPrompt.CELLULAR);
      return;
    }
    this.closeCacheDialog();
    this.showCacheFeedback('已转入后台缓存，可在通知栏取消');
    const task = this.createShelfFullTextCacheTask(book, ++this.fullTextCacheTaskId);
    this.runShelfFullTextCache(book, task).catch((error: Error) => {
      console.error('书架全文缓存任务失败:', error);
      this.setFullTextCacheStatus(task, '全文缓存失败');
      this.showCacheFeedback('全文缓存失败');
      this.publishShelfFullTextCacheNotification(task, '全文缓存失败', this.shelfFullTextCacheProgressText(task), false)
        .catch((e: Error) => {
          console.warn('更新书架缓存失败通知失败:', e);
        });
      this.finishShelfFullTextCacheTask(task);
      this.stopShelfFullTextCacheBackgroundRunning().catch((e: Error) => {
        console.warn('停止书架全文缓存后台任务失败:', e);
      });
    });
  }

  async runShelfFullTextCache(book: Book, task: ShelfFullTextCacheTask): Promise<void> {
    this.registerShelfFullTextCacheTask(task);
    this.setFullTextCacheStatus(task, `${task.scopeLabel}缓存后台进行中`);
    try {
      await this.startShelfFullTextCacheBackgroundRunning(book);
      await this.refreshFullTextCacheCover(book, task);
      if (await this.prepareShelfFullTextCacheNotification()) {
        await this.publishShelfFullTextCacheNotification(task, '准备缓存章节',
          this.shelfFullTextCacheProgressText(task), true);
      }
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const freshBook = await db.getBook(book.bookUrl) || book;
      const engine = ReadBookEngine.createBackgroundWorker();
      task.engine = engine;
      if (this.shouldCancelShelfFullTextCache(task)) {
        this.setFullTextCacheStatus(task, '缓存已取消');
        if (task.stoppingNotificationTask) await task.stoppingNotificationTask;
        await this.publishShelfFullTextCacheNotification(task, '缓存已停止',
          this.shelfFullTextCacheProgressText(task), false);
        return;
      }
      await engine.openBook(freshBook);
      await engine.syncChapterCacheDates();
      if (!this.isShelfFullTextCacheTaskActive(task)) {
        return;
      }
      if (this.shouldCancelShelfFullTextCache(task)) {
        this.setFullTextCacheStatus(task, '缓存已取消');
        if (task.stoppingNotificationTask) await task.stoppingNotificationTask;
        await this.publishShelfFullTextCacheNotification(task, '缓存已停止',
          this.shelfFullTextCacheProgressText(task), false);
        return;
      }
      const total = engine.chapters.length;
      if (total === 0) {
        task.total = 0;
        task.done = 0;
        this.setFullTextCacheStatus(task, '暂无可缓存章节');
        await this.publishShelfFullTextCacheNotification(task, '暂无可缓存章节',
          this.shelfFullTextCacheProgressText(task), false);
        return;
      }
      // A scoped task caches only the requested chapters but still reports progress against that
      // subset, so the notification percentage matches what the user asked for.
      const targets = this.shelfFullTextCacheTargetIndexes(task, total);
      task.total = targets.length;
      task.done = 0;
      if (targets.length === 0) {
        this.setFullTextCacheStatus(task, '所选章节均已缓存');
        await this.publishShelfFullTextCacheNotification(task, '所选章节均已缓存',
          this.shelfFullTextCacheProgressText(task), false);
        return;
      }

      await this.publishShelfFullTextCacheProgress(task, true);

      const audio = BookTypeSupport.isAudio(freshBook);
      engine.audioAllowCellular = task.allowCellular;
      // 有声书同时下两章：地址在引擎里排队取，下载本身并行。大文件一章要下很久，
      // 所以每秒刷新状态（通知栏仍按间隔节流），显示已收到的数据量或正在等 Wi-Fi。
      const concurrency = audio ? SHELF_AUDIO_DOWNLOAD_CONCURRENCY : 1;
      const progressTimer = audio ? setInterval((): void => {
        this.setFullTextCacheStatus(task, this.shelfAudioDownloadStatus(task, engine));
        this.publishShelfFullTextCacheProgress(task, false).catch(() => {});
      }, 1000) : -1;
      try {
        for (let position = 0; position < targets.length; position += concurrency) {
          if (!this.isShelfFullTextCacheTaskActive(task) || this.shouldCancelShelfFullTextCache(task)) {
            break;
          }
          const batch = targets.slice(position, position + concurrency)
            .filter((index: number): boolean => !!engine.chapters[index]);
          if (batch.length === 0) {
            continue;
          }
          this.setFullTextCacheStatus(task, audio ? this.shelfAudioDownloadStatus(task, engine) :
            `正在缓存 ${position + 1}/${targets.length}`);
          const results = await Promise.all(batch.map(async (i: number): Promise<boolean> => {
            try {
              return await engine.cacheChapter(i, (): boolean => this.shouldCancelShelfFullTextCache(task));
            } catch (e) {
              if (!this.shouldCancelShelfFullTextCache(task)) console.error('缓存章节失败:', i, e);
              return false;
            }
          }));
          for (const ok of results) {
            if (ok) task.done++;
          }
          if (engine.lastCacheError) throw new Error(engine.lastCacheError);
          this.syncCacheDialogChapterState(task, engine.chapters);
          if (this.shouldCancelShelfFullTextCache(task)) break;
          await this.publishShelfFullTextCacheProgress(task, false);
          await sleepMs(0);
        }
      } finally {
        if (progressTimer >= 0) clearInterval(progressTimer);
      }

      if (!this.isShelfFullTextCacheTaskActive(task)) {
        return;
      }
      const canceled = this.shouldCancelShelfFullTextCache(task);
      await engine.syncChapterCacheDates();
      // 受保护或直播流的章节不可能下载成功，单独说明，免得用户以为是网络问题反复重试。
      const unsupportedNote = engine.audioUnsupportedCount > 0 ?
        `，其中 ${engine.audioUnsupportedCount} 章为受保护音频或直播流，无法离线` : '';
      this.setFullTextCacheStatus(task, canceled ? '缓存已取消' : (task.done === task.total ? `缓存完成：${task.done}/${task.total}` : `缓存结束，${task.total - task.done} 章未完成${unsupportedNote}`));
      this.syncCacheDialogChapterState(task, engine.chapters);
      this.finishCacheDialogSummary(task);
      if (canceled && task.stoppingNotificationTask) await task.stoppingNotificationTask;
      await this.publishShelfFullTextCacheNotification(
        task,
        canceled ? '缓存已停止' : (task.done === task.total ? `${task.scopeLabel}缓存完成` : '部分章节未完成'),
        this.shelfFullTextCacheProgressText(task),
        false
      );
      this.showCacheFeedback(canceled ? '缓存已停止' : `缓存完成 ${task.done}/${task.total}`);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (error) {
      if (!task.cancelRequested) {
        const message = error instanceof Error ? error.message : '缓存任务执行失败';
        throw new Error(message);
      }
      if (task.stoppingNotificationTask) await task.stoppingNotificationTask;
      this.setFullTextCacheStatus(task, '缓存已取消');
      await this.publishShelfFullTextCacheNotification(task, '缓存已停止',
        this.shelfFullTextCacheProgressText(task), false);
      HdsFeedback.showToast('缓存已停止');
    } finally {
      this.finishShelfFullTextCacheTask(task);
      await this.stopShelfFullTextCacheBackgroundRunning();
    }
  }

  /**
   * Whole-book tasks cache every chapter; scoped tasks cache only the requested indexes and skip
   * out-of-range entries that no longer exist after a catalog refresh.
   */
  shelfFullTextCacheTargetIndexes(task: ShelfFullTextCacheTask, total: number): number[] {
    if (task.chapterIndexes.length === 0) {
      const all: number[] = [];
      for (let i = 0; i < total; i++) all.push(i);
      return all;
    }
    const result: number[] = [];
    for (const index of task.chapterIndexes) {
      if (index >= 0 && index < total) result.push(index);
    }
    return result;
  }

  countCachedChaptersIn(chapters: BookChapter[], indexes: number[]): number {
    let count = 0;
    for (const index of indexes) {
      const chapter = chapters[index];
      if (chapter && chapter.cacheDate > 0) {
        count++;
      }
    }
    return count;
  }

  /**
   * Mirrors the background task's progress into an open chapter panel. The task owns a separate
   * engine, so its chapter objects are not the ones the panel renders.
   */
  syncCacheDialogChapterState(task: ShelfFullTextCacheTask, taskChapters: BookChapter[]): void {
    if (!this.showChapterCacheDialog || this.cacheTargetBook?.bookUrl !== task.bookUrl ||
      this.cacheChapters.length === 0) {
      return;
    }
    let changed = false;
    for (const chapter of this.cacheChapters) {
      const taskChapter = taskChapters[chapter.index];
      if (!taskChapter || taskChapter.cacheDate <= 0 || chapter.cacheDate > 0) continue;
      chapter.cacheDate = taskChapter.cacheDate;
      changed = true;
    }
    if (changed) {
      this.cacheChapters = [...this.cacheChapters];
    }
  }

  /** Hands the status line back to the catalog summary once the background task has finished. */
  finishCacheDialogSummary(task: ShelfFullTextCacheTask): void {
    if (!this.showChapterCacheDialog || this.cacheTargetBook?.bookUrl !== task.bookUrl ||
      this.cacheChapters.length === 0) {
      return;
    }
    this.cacheStatus = this.cacheSummaryText(this.cacheChapters);
  }

  createShelfFullTextCacheTask(book: Book, taskId: number, chapterIndexes: number[] = [],
    scopeLabel: string = '全文', allowCellular: boolean = false): ShelfFullTextCacheTask {
    const bookUrl = book.bookUrl || '';
    return {
      taskId: taskId,
      bookUrl: bookUrl,
      bookName: book.name || '书籍',
      taskKey: this.buildFullTextCacheTaskKey(book, taskId),
      createdAt: Date.now(),
      cancelRequested: false,
      cancelSeenNonce: AppStorage.get<number>('fullTextCacheCancelNonce') || 0,
      notificationLastAt: 0,
      cancelAgent: null,
      done: 0,
      total: 0,
      status: '',
      coverPixelMap: null,
      notificationFailureHintShown: false,
      engine: null,
      stoppingNotificationTask: null,
      chapterIndexes: chapterIndexes,
      scopeLabel: scopeLabel,
      allowCellular: allowCellular
    };
  }

  registerShelfFullTextCacheTask(task: ShelfFullTextCacheTask): void {
    this.fullTextCacheTasks.set(task.bookUrl, task);
    FullTextCacheCancelCoordinator.register(task.taskKey, task.bookUrl,
      (signal: FullTextCacheCancelSignal): void => {
        if (FullTextCacheCancelCoordinator.matches(signal, task.taskKey, task.bookUrl)) {
          this.beginStoppingShelfFullTextCache(task, signal.nonce, true);
        }
      });
    this.syncShelfFullTextCacheTaskState();
  }

  finishShelfFullTextCacheTask(task: ShelfFullTextCacheTask): void {
    FullTextCacheCancelCoordinator.unregister(task.taskKey);
    const current = this.fullTextCacheTasks.get(task.bookUrl);
    if (current && current.taskKey === task.taskKey) {
      this.fullTextCacheTasks.delete(task.bookUrl);
    }
    task.engine = null;
    task.stoppingNotificationTask = null;
    this.releaseFullTextCacheCover(task);
    this.syncShelfFullTextCacheTaskState();
  }

  syncShelfFullTextCacheTaskState(): void {
    this.activeFullTextCacheBookUrls = Array.from(this.fullTextCacheTasks.keys());
    this.isCaching = this.activeFullTextCacheBookUrls.length > 0;
  }

  getShelfFullTextCacheTask(bookUrl: string): ShelfFullTextCacheTask | null {
    return bookUrl ? this.fullTextCacheTasks.get(bookUrl) || null : null;
  }

  isShelfFullTextCacheTaskActive(task: ShelfFullTextCacheTask): boolean {
    const current = this.fullTextCacheTasks.get(task.bookUrl);
    return !!current && current.taskKey === task.taskKey;
  }

  findShelfFullTextCacheTaskBySignal(signal: FullTextCacheCancelSignal): ShelfFullTextCacheTask | null {
    if (signal.taskKey) {
      for (const task of this.fullTextCacheTasks.values()) {
        if (task.taskKey === signal.taskKey) {
          return task;
        }
      }
    }
    return signal.bookUrl ? this.getShelfFullTextCacheTask(signal.bookUrl) : null;
  }

  beginStoppingShelfFullTextCache(task: ShelfFullTextCacheTask, nonce: number, showHint: boolean): void {
    if (!this.isShelfFullTextCacheTaskActive(task) || task.cancelRequested) return;
    task.cancelRequested = true;
    task.cancelSeenNonce = nonce;
    this.setFullTextCacheStatus(task, '正在停止缓存…');
    task.engine?.cancelPendingRequests();
    task.stoppingNotificationTask = this.publishShelfFullTextCacheNotification(task, '正在停止缓存…',
      this.shelfFullTextCacheProgressText(task), true).catch((error: Error) => {
      console.warn('更新正在停止缓存通知失败:', error);
    });
    if (showHint) HdsFeedback.showToast('正在停止缓存…');
  }

  shouldCancelShelfFullTextCache(task: ShelfFullTextCacheTask): boolean {
    if (task.cancelRequested) {
      return true;
    }
    const nonce = AppStorage.get<number>('fullTextCacheCancelNonce') || 0;
    if (nonce > 0 && nonce !== task.cancelSeenNonce) {
      const signal = this.parseFullTextCacheCancelSignal();
      if (signal && !this.isCurrentFullTextCacheSignal(task, signal)) {
        task.cancelSeenNonce = signal.nonce;
        return false;
      }
      if (!signal || this.isCurrentFullTextCacheSignal(task, signal)) {
        this.beginStoppingShelfFullTextCache(task, signal ? signal.nonce : nonce, false);
        return true;
      }
    }
    return false;
  }

  parseFullTextCacheCancelSignal(): FullTextCacheCancelSignal | null {
    const raw = this.fullTextCacheCancelSignal || AppStorage.get<string>('fullTextCacheCancelSignal') || '';
    if (!raw.trim()) {
      return null;
    }
    return FullTextCacheCancelCoordinator.parse(raw);
  }

  isCurrentFullTextCacheSignal(task: ShelfFullTextCacheTask, signal: FullTextCacheCancelSignal): boolean {
    if (signal.taskKey && task.taskKey && signal.taskKey === task.taskKey) {
      return true;
    }
    return !!signal.bookUrl && signal.bookUrl === task.bookUrl;
  }

  countCachedChapters(chapters: BookChapter[]): number {
    let count = 0;
    for (const chapter of chapters) {
      if (chapter.cacheDate > 0) {
        count++;
      }
    }
    return count;
  }

  shelfFullTextCacheProgressText(task: ShelfFullTextCacheTask): string {
    const total = Math.max(task.total, 0);
    if (total === 0) {
      return '正在准备缓存章节（0%）';
    }
    const done = Math.max(0, Math.min(task.done, total));
    const percent = Math.floor((done / total) * 100);
    return `已缓存 ${done}/${total} 章（${percent}%）`;
  }

  shelfFullTextCacheNotificationTitle(task: ShelfFullTextCacheTask): string {
    return `缓存${task.scopeLabel}：${task.bookName || '书籍'}`;
  }

  shelfFullTextCacheDisplayText(text: string, additionalText: string, ongoing: boolean): string {
    if (!ongoing || !additionalText || text.includes(additionalText)) {
      return text;
    }
    return `${text} · ${additionalText}`;
  }

  shelfFullTextCacheNormalContent(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): notificationManager.NotificationBasicContent {
    const normalContent: notificationManager.NotificationBasicContent = {
      title: this.shelfFullTextCacheNotificationTitle(task),
      text: this.shelfFullTextCacheDisplayText(text, additionalText, ongoing),
      additionalText: additionalText
    };
    if (task.coverPixelMap) {
      normalContent.lockscreenPicture = task.coverPixelMap;
    }
    return normalContent;
  }

  applyShelfFullTextCacheCoverToRequest(task: ShelfFullTextCacheTask,
    request: notificationManager.NotificationRequest): void {
    if (!task.coverPixelMap) {
      return;
    }
    request.smallIcon = task.coverPixelMap;
    request.largeIcon = task.coverPixelMap;
  }

  async publishShelfFullTextCacheProgress(task: ShelfFullTextCacheTask, force: boolean): Promise<void> {
    const now = Date.now();
    if (!force && now - task.notificationLastAt < SHELF_FULL_TEXT_CACHE_NOTIFICATION_INTERVAL_MS) {
      return;
    }
    task.notificationLastAt = now;
    // 有声书的状态里有已下载数据量、是否在等 Wi-Fi，比固定文字有用。
    await this.publishShelfFullTextCacheNotification(task,
      task.scopeLabel.startsWith('音频') && task.status ? task.status : '全文缓存后台进行中',
      this.shelfFullTextCacheProgressText(task), true);
  }

  /** 有声书下载中的状态：等网络时说明在等什么，否则显示正在下第几章、本批已收到多少数据。 */
  shelfAudioDownloadStatus(task: ShelfFullTextCacheTask, engine: ReadBookEngine): string {
    if (engine.audioWaitingNetwork) {
      return task.allowCellular ? '已暂停：等待网络恢复' : '已暂停：等待连接 Wi-Fi';
    }
    let received = 0;
    engine.audioProgress.forEach((bytes: number): void => {
      received += bytes;
    });
    const position = Math.min(task.total, task.done + 1);
    return received > 0 ? `正在下载 ${position}/${task.total} · ${ReaderCacheBudgetPolicy.formatBytes(received)}` :
      `正在下载 ${position}/${task.total}`;
  }

  async publishShelfFullTextCacheNotification(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: this.fullTextCacheNotificationId(task.bookUrl),
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: ongoing,
        tapDismissed: false,
        isAlertOnce: true,
        deliveryTime: task.createdAt,
        showDeliveryTime: false,
        wantAgent: await this.getShelfFullTextCacheOpenWantAgent(task),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: this.shelfFullTextCacheNormalContent(task, text, additionalText, ongoing)
        }
      };
      if (!ongoing) {
        request.autoDeletedTime = Date.now() + 5000;
      }
      request.label = this.fullTextCacheNotificationLabel(task.bookUrl);
      this.applyShelfFullTextCacheCoverToRequest(task, request);
      if (ongoing) {
        request.actionButtons = [{
          title: '停止缓存',
          wantAgent: await this.getShelfFullTextCacheCancelWantAgent(task)
        }];
      }
      await notificationManager.publish(request);
    } catch (error) {
      console.warn('发布书架全文缓存通知失败:', error);
      try {
        await this.publishBasicShelfFullTextCacheNotification(task, text, additionalText, ongoing);
      } catch (fallbackError) {
        console.warn('发布书架全文缓存基础通知失败:', fallbackError);
        try {
          await this.publishMinimalShelfFullTextCacheNotification(task, text, additionalText, ongoing);
        } catch (minimalError) {
          console.warn('发布书架全文缓存最小通知失败:', minimalError);
          this.showShelfFullTextCacheNotificationFailureHint(task, minimalError);
        }
      }
    }
  }

  async publishBasicShelfFullTextCacheNotification(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: this.fullTextCacheNotificationId(task.bookUrl),
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: ongoing,
      tapDismissed: false,
      isAlertOnce: true,
      deliveryTime: task.createdAt,
      showDeliveryTime: false,
      wantAgent: await this.getShelfFullTextCacheOpenWantAgent(task),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: this.shelfFullTextCacheNormalContent(task, text, additionalText, ongoing)
      }
    };
    if (!ongoing) {
      request.autoDeletedTime = Date.now() + 5000;
    }
    request.label = this.fullTextCacheNotificationLabel(task.bookUrl);
    if (ongoing) {
      request.actionButtons = [{
        title: '停止缓存',
        wantAgent: await this.getShelfFullTextCacheCancelWantAgent(task)
      }];
    }
    this.applyShelfFullTextCacheCoverToRequest(task, request);
    await notificationManager.publish(request);
  }

  async publishMinimalShelfFullTextCacheNotification(task: ShelfFullTextCacheTask, text: string, additionalText: string,
    ongoing: boolean): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: this.fullTextCacheNotificationId(task.bookUrl),
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: ongoing,
      tapDismissed: false,
      isAlertOnce: true,
      deliveryTime: task.createdAt,
      showDeliveryTime: false,
      wantAgent: await this.getShelfFullTextCacheOpenWantAgent(task),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: this.shelfFullTextCacheNormalContent(task, text, additionalText, ongoing)
      }
    };
    if (!ongoing) {
      request.autoDeletedTime = Date.now() + 5000;
    }
    request.label = this.fullTextCacheNotificationLabel(task.bookUrl);
    this.applyShelfFullTextCacheCoverToRequest(task, request);
    await notificationManager.publish(request);
  }

  async refreshFullTextCacheCover(book: Book, task: ShelfFullTextCacheTask): Promise<void> {
    this.releaseFullTextCacheCover(task);
    const raw = this.getShelfCover(book);
    if (!raw) {
      return;
    }
    try {
      const coverPath = await BookCoverCache.prepareCoverFile(getContext(this), raw);
      if (!coverPath) {
        return;
      }
      task.coverPixelMap = await this.createFullTextCacheCoverPixelMap(coverPath);
    } catch (error) {
      console.warn('解析缓存通知封面失败:', error);
    }
  }

  async createFullTextCacheCoverPixelMap(path: string): Promise<image.PixelMap | null> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      return await source.createPixelMap({
        desiredSize: {
          width: 128,
          height: 128
        }
      });
    } catch (error) {
      console.warn('创建缓存通知封面 PixelMap 失败:', error);
      return null;
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (e) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (e) {
        }
      }
    }
  }

  releaseFullTextCacheCover(task: ShelfFullTextCacheTask): void {
    if (!task.coverPixelMap) {
      return;
    }
    try {
      task.coverPixelMap.release().catch((e: Error) => {
        console.warn('释放缓存通知封面失败:', e);
      });
    } catch (e) {
      console.warn('释放缓存通知封面失败:', e);
    }
    task.coverPixelMap = null;
  }

  async prepareShelfFullTextCacheNotification(): Promise<boolean> {
    try {
      if (!await notificationManager.isNotificationEnabled()) {
        try {
          await notificationManager.requestEnableNotification(getContext(this) as common.UIAbilityContext);
        } catch (error) {
          console.warn('请求通知权限失败:', error);
          HdsFeedback.showToast('通知权限未开启，缓存仍会继续');
          return false;
        }
      }
      if (!await notificationManager.isNotificationEnabled()) {
        HdsFeedback.showToast('通知权限未开启，缓存仍会继续');
        return false;
      }
      if (!this.fullTextCacheNotificationSlotReady) {
        await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
        this.fullTextCacheNotificationSlotReady = true;
      }
      return true;
    } catch (error) {
      console.warn('准备书架缓存通知失败:', error);
      this.showShelfFullTextCacheNotificationFailureHint(null, error);
      return false;
    }
  }

  showShelfFullTextCacheNotificationFailureHint(task: ShelfFullTextCacheTask | null, error: Object): void {
    if (task) {
      if (task.notificationFailureHintShown) {
        return;
      }
      task.notificationFailureHintShown = true;
    } else if (this.fullTextCacheNotificationFailureHintShown) {
      return;
    } else {
      this.fullTextCacheNotificationFailureHintShown = true;
    }
    console.warn('书架缓存通知不可用:', error);
    HdsFeedback.showToast(this.shelfFullTextCacheNotificationFailureMessage(error));
  }

  shelfFullTextCacheNotificationFailureMessage(error: Object): string {
    const code = this.notificationErrorCode(error);
    if (code === 1600004 || code === 1600020) {
      return '通知权限未开启，缓存仍会继续';
    }
    if (code === 1600005) {
      return '通知类别已关闭，请检查应用通知设置';
    }
    if (code === 1600009) {
      return '通知发送过快，缓存仍会继续';
    }
    return code > 0 ? `通知发布失败(${code})` : '通知发布失败，请检查应用通知权限';
  }

  notificationErrorCode(error: Object): number {
    const record = error as Record<string, Object>;
    const code = record['code'];
    return typeof code === 'number' ? code as number : 0;
  }

  async getShelfFullTextCacheCancelWantAgent(task: ShelfFullTextCacheTask): Promise<WantAgent> {
    if (task.cancelAgent) {
      return task.cancelAgent;
    }
    const context = getContext(this) as common.UIAbilityContext;
    task.cancelAgent = await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          cacheAction: 'cancelFullTextCache',
          cacheTaskId: task.taskId,
          cacheTaskKey: task.taskKey,
          bookUrl: task.bookUrl
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.fullTextCacheCancelRequestCode(task.bookUrl),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    return task.cancelAgent;
  }

  async getShelfFullTextCacheOpenWantAgent(task: ShelfFullTextCacheTask): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          bookUrl: task.bookUrl
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.fullTextCacheOpenRequestCode(task.bookUrl),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  async startShelfFullTextCacheBackgroundRunning(book: Book): Promise<void> {
    if (this.fullTextCacheBackgroundRunning) {
      return;
    }
    try {
      const agent = await this.createShelfFullTextCacheOpenWantAgent(book);
      await backgroundTaskManager.startBackgroundRunning(getContext(this), ['dataTransfer'], agent);
      this.fullTextCacheBackgroundRunning = true;
    } catch (error) {
      console.warn('启动书架全文缓存后台任务失败:', error);
    }
  }

  async stopShelfFullTextCacheBackgroundRunning(): Promise<void> {
    if (!this.fullTextCacheBackgroundRunning || this.fullTextCacheTasks.size > 0) {
      return;
    }
    this.fullTextCacheBackgroundRunning = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(getContext(this));
    } catch (error) {
      console.warn('停止书架全文缓存后台任务失败:', error);
    }
  }

  async createShelfFullTextCacheOpenWantAgent(book: Book): Promise<WantAgent> {
    const context = getContext(this) as common.UIAbilityContext;
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          bookUrl: book.bookUrl || ''
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.fullTextCacheOpenRequestCode(book.bookUrl || ''),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  buildFullTextCacheTaskKey(book: Book, taskId: number): string {
    return `${this.fullTextCacheHash(book.bookUrl || book.name || 'book')}_${taskId}`;
  }

  fullTextCacheNotificationId(bookUrl: string): number {
    return 260100 + (this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book') % 100000);
  }

  fullTextCacheCancelRequestCode(bookUrl: string): number {
    return 360100 + (this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book') % 100000);
  }

  fullTextCacheOpenRequestCode(bookUrl: string): number {
    return 460100 + (this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book') % 100000);
  }

  fullTextCacheNotificationLabel(bookUrl: string): string {
    return `full_text_cache_${this.fullTextCacheHash(bookUrl || this.fullTextCacheBookName || 'book')}`;
  }

  fullTextCacheHash(value: string): number {
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(i);
      hash |= 0;
    }
    return Math.abs(hash);
  }

  parseChapterRange(raw: string, total: number): number[] {
    const value = (raw || '').trim();
    if (!value || total <= 0) return [];
    const normalized = value.replace(/[，、；;]/g, ',').replace(/[～至]/g, '-');
    const result = new Set<number>();
    for (const part of normalized.split(/[\s,]+/)) {
      if (!part) continue;
      const range = part.match(/^(\d+)\s*-\s*(\d+)$/);
      if (range) {
        const start = Number.parseInt(range[1], 10);
        const end = Number.parseInt(range[2], 10);
        if (start < 1 || end < 1 || start > total || end > total) return [];
        const low = Math.min(start, end);
        const high = Math.max(start, end);
        for (let chapterNumber = low; chapterNumber <= high; chapterNumber++) {
          result.add(chapterNumber - 1);
        }
        continue;
      }
      if (!/^\d+$/.test(part)) return [];
      const chapterNumber = Number.parseInt(part, 10);
      if (chapterNumber < 1 || chapterNumber > total) return [];
      result.add(chapterNumber - 1);
    }
    return Array.from(result).sort((left: number, right: number) => left - right);
  }

  /**
   * Range and single-chapter caching both run as background tasks. They used to await every chapter
   * on the UI thread, which blocked the panel and made it unclosable for the whole download.
   */
  async cacheChapterRange(): Promise<void> {
    const total = this.cacheChapters.length;
    const indexes = this.parseChapterRange(this.cacheRangeDraft, total);
    if (indexes.length === 0) {
      HdsFeedback.showToast(`请输入有效章节范围（1-${total}）`);
      return;
    }
    await this.startScopedShelfCache(indexes, '章节');
  }

  async cacheSingleChapter(index: number): Promise<void> {
    await this.startScopedShelfCache([index], '章节');
  }

  async startScopedShelfCache(indexes: number[], scopeLabel: string): Promise<void> {
    const book = this.cacheTargetBook;
    if (!book || indexes.length === 0) {
      return;
    }
    if (this.isBookCaching(book)) {
      this.showCacheFeedback('该书正在后台缓存，请稍候');
      return;
    }
    if (!book.origin || book.origin === 'local') {
      HdsFeedback.showToast('本地书籍无需缓存');
      return;
    }
    const audio = BookTypeSupport.isAudio(book);
    const network = audio ? await AudioOfflineDownloadPrompt.prepare(this.getUIContext(), this.appDarkMode, indexes.length) :
      AudioOfflineDownloadPrompt.WIFI;
    if (network === AudioOfflineDownloadPrompt.CANCEL) return;
    // The panel stays open so progress and the "已缓存" marks stay visible; closing it is the
    // user's choice and never interrupts the task.
    this.showCacheFeedback(`已转入后台${audio ? '下载' : '缓存'} ${indexes.length} 章，可在通知栏取消`);
    this.startShelfCacheTask(book, indexes, audio ? '音频章节' : scopeLabel, network === AudioOfflineDownloadPrompt.CELLULAR);
  }

  /** 听书页的"下载"把请求交给这里，与书架菜单里的下载走同一个后台任务。 */
  onAudioOfflineDownloadRequest(): void {
    const request = AudioOfflineDownloadPrompt.parse(this.audioOfflineDownloadRequest);
    if (!request) return;
    AppStorage.setOrCreate(AudioOfflineDownloadPrompt.ACK_KEY, request.nonce);
    this.startRequestedAudioDownload(request.bookUrl, request.chapterIndexes, request.allowCellular).catch((error: Error) => {
      console.error('启动听书页下载任务失败:', error);
      this.showCacheFeedback('下载失败');
    });
  }

  async startRequestedAudioDownload(bookUrl: string, indexes: number[], allowCellular: boolean): Promise<void> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    const book = await db.getBook(bookUrl);
    if (!book || !book.origin || book.origin === 'local') {
      this.showCacheFeedback('书架里没有这本书，加入书架后再下载');
      return;
    }
    if (this.isBookCaching(book)) {
      this.showCacheFeedback('该书正在后台下载，请稍候');
      return;
    }
    this.showCacheFeedback(indexes.length > 0 ? `已转入后台下载 ${indexes.length} 章，可在通知栏取消` :
      '已转入后台下载，可在通知栏取消');
    this.startShelfCacheTask(book, indexes, indexes.length > 0 ? '音频章节' : '音频', allowCellular);
  }

  startShelfCacheTask(book: Book, indexes: number[], scopeLabel: string, allowCellular: boolean = false): void {
    const task = this.createShelfFullTextCacheTask(book, ++this.fullTextCacheTaskId, indexes, scopeLabel, allowCellular);
    this.runShelfFullTextCache(book, task).catch((error: Error) => {
      console.error('书架指定章节缓存任务失败:', error);
      // 空间不足、达到离线音频上限要让用户知道原因，其他失败统一提示。
      const reason = error?.message === AudioOfflineStore.STORAGE_FAILURE || error?.message === AudioOfflineStore.CAP_REACHED ?
        error.message : '缓存失败';
      this.setFullTextCacheStatus(task, reason);
      this.showCacheFeedback(reason);
      this.publishShelfFullTextCacheNotification(task, reason,
        this.shelfFullTextCacheProgressText(task), false).catch((e: Error) => {
        console.warn('更新书架缓存失败通知失败:', e);
      });
      this.finishShelfFullTextCacheTask(task);
      this.stopShelfFullTextCacheBackgroundRunning().catch((e: Error) => {
        console.warn('停止书架缓存后台任务失败:', e);
      });
    });
  }

  async clearCachedChapters(): Promise<void> {
    if (!this.cacheTargetBook) {
      return;
    }
    if (this.isCacheTargetBookCaching()) {
      HdsFeedback.showToast('缓存进行中，稍后再清除');
      return;
    }
    const book = this.cacheTargetBook;
    if (!book.bookUrl) {
      HdsFeedback.showToast('书籍地址为空');
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBookCachedContent(book.bookUrl);
      const audio = BookTypeSupport.isAudio(book);
      if (audio) await AudioOfflineStore.clearBook(book.bookUrl);
      const engine = ReadBookEngine.get();
      if (engine.book?.bookUrl === book.bookUrl) {
        engine.clearCurrentBookMemoryCache();
        await engine.syncChapterCacheDates();
        this.cacheChapters = [...engine.chapters];
      } else {
        for (const chapter of this.cacheChapters) {
          chapter.cacheDate = 0;
        }
        this.cacheChapters = [...this.cacheChapters];
      }
      this.cacheStatus = audio ? '已删除已下载音频' : '已清除缓存章节';
      this.showCacheFeedback(this.cacheStatus);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('清除缓存章节失败:', e);
      this.cacheStatus = '清除缓存失败';
      this.showCacheFeedback('清除缓存失败');
    }
  }

  async refreshBookshelfToc(silent: boolean = false): Promise<void> {
    if (this.shelfRefreshRunning) {
      if (!silent) {
        this.shelfRefreshPrompt = '书架刷新中';
        this.isShelfRefreshing = true;
      }
      return;
    }
    if (!silent && this.shelfShowsLocalOnly()) {
      await this.refreshLocalBooks();
      return;
    }
    const shelfBooks = silent ? [...this.allBooks] : [...this.books];
    if (shelfBooks.length === 0) {
      if (!silent) this.isShelfRefreshing = false;
      return;
    }
    this.shelfRefreshRunning = true;
    const refreshStartedAt = Date.now();
    if (!silent) {
      this.isShelfRefreshing = true;
      HdsFeedback.showToast('正在刷新书架...');
    }
    let attempted = 0;
    let skippedFinished = 0;
    let updated = 0;
    let failed = 0;
    let taskFailed = false;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const engine = ReadBookEngine.createBackgroundWorker();
      engine.chapterUpdateBatchTime = refreshStartedAt;
      for (const shelfBook of shelfBooks) {
        if (!shelfBook.bookUrl || LocalBookService.isLocalBook(shelfBook) || !shelfBook.canUpdate) {
          continue;
        }
        if (this.isFinishedBook(shelfBook)) {
          skippedFinished++;
          continue;
        }
        attempted++;
        try {
          const freshBook = await db.getBook(shelfBook.bookUrl) || shelfBook;
          const beforeUpdateTime = BookshelfSortHelper.getBookUpdateTime(freshBook);
          const hadPendingUpdate = this.hasShelfBookUpdate(freshBook);
          await engine.openBook(freshBook);
          await engine.refreshToc();
          const refreshedBook = await db.getBook(shelfBook.bookUrl);
          if (refreshedBook) {
            refreshedBook.lastCheckTime = Date.now();
            refreshedBook.lastCheckCount = engine.chapters.length;
            if (engine.chapters.length > 0) {
              refreshedBook.totalChapterNum = engine.chapters.length;
              refreshedBook.latestChapterTitle = engine.chapters[engine.chapters.length - 1].title;
            }
            const hasNewUpdate = BookshelfSortHelper.getBookUpdateTime(refreshedBook) > beforeUpdateTime;
            const acknowledgedAt = this.shelfUpdateAcknowledgedAt.get(refreshedBook.bookUrl) || 0;
            const keepPendingUpdate = hadPendingUpdate && acknowledgedAt === 0;
            const keepNewUpdate = hasNewUpdate && acknowledgedAt < refreshStartedAt;
            refreshedBook.putVariable(SHELF_UPDATE_BADGE_VARIABLE,
              keepPendingUpdate || keepNewUpdate ? '1' : '');
            await db.updateBook(refreshedBook);
            if (hasNewUpdate) {
              updated++;
            }
          }
        } catch (e) {
          failed++;
          console.error('刷新书架目录失败:', shelfBook.name, e);
        }
      }
      if (attempted > 0) {
        await this.loadBooks();
        if (!silent) {
          const skippedText = skippedFinished > 0 ? `，跳过${skippedFinished}本完结` : '';
          const message = failed > 0 ?
            `书架刷新完成：${updated}本有更新，${failed}本失败${skippedText}` :
            `书架刷新完成：${updated}本有更新${skippedText}`;
          HdsFeedback.showToast(message);
        }
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }
    } catch (e) {
      taskFailed = true;
      console.error('刷新书架失败:', e);
      if (!silent) HdsFeedback.showToast('书架刷新失败');
    } finally {
      this.shelfRefreshRunning = false;
      this.isShelfRefreshing = false;
      this.shelfRefreshStatus = RefreshStatus.Inactive;
      this.shelfRefreshPrompt = '下拉刷新书架';
      if (!silent && !taskFailed && attempted === 0) {
        const message = skippedFinished > 0 ? `没有可刷新的连载书籍，已跳过${skippedFinished}本完结` : '没有可刷新的网络书籍';
        HdsFeedback.showToast(message);
      }
    }
  }

  async refreshLocalBooks(): Promise<void> {
    this.shelfRefreshRunning = true;
    this.isShelfRefreshing = true;
    this.shelfRefreshPrompt = '正在刷新本地书籍...';
    try {
      await this.loadBooks();
      HdsFeedback.showToast('本地书架已刷新');
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('刷新本地书籍失败:', e);
      HdsFeedback.showToast('本地书架刷新失败');
    } finally {
      this.shelfRefreshRunning = false;
      this.isShelfRefreshing = false;
      this.shelfRefreshStatus = RefreshStatus.Inactive;
      this.shelfRefreshPrompt = '下拉刷新书架';
    }
  }

  isFinishedBook(book: Book): boolean {
    return this.shelfBookStatusMarker(book) === 'finished';
  }

  /** 从分类、书源状态和自定义标签里读出的完结标记：'finished'、'ongoing'，读不出时为空串。 */
  shelfBookStatusMarker(book: Book): string {
    const text = `${book.kind || ''},${book.status || ''},${book.customTag || ''}`.replace(/\s+/g, '');
    if (!text.replace(/,/g, '')) {
      return '';
    }
    if (/(连载中|連載中|连载|連載|未完结|未完結|更新中|ongoing|serializing)/i.test(text)) {
      return 'ongoing';
    }
    return /(已完结|已完結|完结|完結|完本|全本|完$|completed|complete|finished)/i.test(text) ? 'finished' : '';
  }

  /** 书源标了完结算已完结；本地书是完整文件，除非标了连载也算已完结；其余都算连载中。 */
  isShelfBookFinished(book: Book): boolean {
    const marker = this.shelfBookStatusMarker(book);
    if (marker) {
      return marker === 'finished';
    }
    return LocalBookService.isLocalBook(book);
  }

  trackShelfRefreshPullOffset(offset: number): void {
    if (this.shelfRefreshRunning || this.isShelfRefreshing) {
      return;
    }
    if (this.shelfRefreshStatus !== RefreshStatus.Drag && this.shelfRefreshStatus !== RefreshStatus.OverDrag) {
      return;
    }
    if (this.shelfRefreshPullRetracting) {
      if (offset > this.shelfRefreshPullTrough + SHELF_REFRESH_PULL_DIRECTION_SLOP) {
        this.shelfRefreshPullRetracting = false;
        this.shelfRefreshPullPeak = offset;
      } else {
        this.shelfRefreshPullTrough = Math.min(this.shelfRefreshPullTrough, offset);
      }
    } else if (this.shelfRefreshStatus === RefreshStatus.Drag &&
      offset < this.shelfRefreshPullPeak - SHELF_REFRESH_PULL_DIRECTION_SLOP) {
      // 只收起“下拉刷新书架”；“松手刷新书架”阶段往回推仍会刷新，提示要留着。
      this.shelfRefreshPullRetracting = true;
      this.shelfRefreshPullTrough = offset;
    } else {
      this.shelfRefreshPullPeak = Math.max(this.shelfRefreshPullPeak, offset);
    }
  }

  resetShelfRefreshPullTracking(): void {
    this.shelfRefreshPullPeak = 0;
    this.shelfRefreshPullTrough = 0;
    this.shelfRefreshPullRetracting = false;
  }

  updateShelfRefreshPrompt(state: RefreshStatus): void {
    if (state === RefreshStatus.Inactive || state === RefreshStatus.Done || state === RefreshStatus.Refresh) {
      this.resetShelfRefreshPullTracking();
    }
    this.shelfRefreshStatus = state;
    if (this.shelfRefreshRunning) {
      this.shelfRefreshPrompt = '书架刷新中';
      return;
    }
    if (state === RefreshStatus.OverDrag) {
      this.shelfRefreshPrompt = '松手刷新书架';
    } else if (state === RefreshStatus.Refresh) {
      this.shelfRefreshPrompt = '正在刷新书架...';
    } else if (state === RefreshStatus.Done) {
      // Done is the native rebound/settled phase. Keeping a fixed sibling visible here makes
      // the prompt overlap the first shelf item after the books have already returned to place.
      this.shelfRefreshPrompt = '下拉刷新书架';
    } else {
      this.shelfRefreshPrompt = '下拉刷新书架';
    }
  }

  shouldShowShelfRefreshStatus(): boolean {
    if (this.isShelfRefreshing) return true;
    if (this.shelfRefreshPullRetracting) return false;
    return this.shelfRefreshStatus === RefreshStatus.Drag ||
      this.shelfRefreshStatus === RefreshStatus.OverDrag ||
      this.shelfRefreshStatus === RefreshStatus.Refresh;
  }

  async updateShelfBook(book: Book): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.updateBook(book);
      this.books = this.books.map((item: Book) => item.bookUrl === book.bookUrl ? book : item);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('更新书籍失败:', e);
      HdsFeedback.showToast('保存失败');
    }
  }

  cachedChapterTextColor(): string {
    return this.appDarkMode ? '#DDEFE5' : '#244B35';
  }

  @Builder
  shelfRefreshBuilder() {
    // Refresh translates its builder back to y=0 during Done. The bookshelf header is an
    // immersive glass overlay, so a visible builder would travel through that overlay. Keep the
    // layout placeholder here and render the status in a fixed sibling below the full header.
    Row()
      .height(48)
      .width('100%')
      .opacity(0)
  }

  @Builder
  shelfRefreshStatusOverlay() {
    Row({ space: AppSpacing.MD }) {
      if (this.isShelfRefreshing) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.accentColor())
      }
      Text(this.shelfRefreshPrompt)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
    }
    .height(48)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .position({ x: 0, y: this.bookshelfTopOverlayHeight() + 4 })
    .zIndex(3)
    .hitTestBehavior(HitTestMode.None)
  }

  /** 从筛选菜单的“搜索书架”展开，边输入边筛当前书架；“取消”清空关键词并收起。 */
  @Builder
  shelfSearchBar() {
    Row({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
        TextInput({ text: this.shelfSearchKeyword, placeholder: '书名、作者、书源或标签' })
          .key(SHELF_SEARCH_INPUT_KEY)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .caretColor(this.accentColor())
          .layoutWeight(1)
          .height(BookshelfPage.SEARCH_BAR_HEIGHT)
          .padding({ left: 0, right: 0 })
          .backgroundColor(Color.Transparent)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string): void => {
            this.shelfSearchKeyword = value;
          })
          .onSubmit((): void => {
            this.getUIContext().getFocusController().clearFocus();
          })
        if (this.shelfSearchKeyword) {
          Text('×')
            .fontSize(AppFontSize.TITLE)
            .fontColor(this.subTextColor())
            .width(32)
            .height(BookshelfPage.SEARCH_BAR_HEIGHT)
            .textAlign(TextAlign.Center)
            .accessibilityText('清空关键词')
            .onClick((): void => {
              this.shelfSearchKeyword = '';
              focusControl.requestFocus(SHELF_SEARCH_INPUT_KEY);
            })
        }
      }
      .layoutWeight(1)
      .height(BookshelfPage.SEARCH_BAR_HEIGHT)
      .padding({ left: AppSpacing.LG, right: AppSpacing.SM })
      .borderRadius(BookshelfPage.SEARCH_BAR_HEIGHT / 2)
      .backgroundColor(this.cardColor())

      Text('取消')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .height(BookshelfPage.SEARCH_BAR_HEIGHT)
        .accessibilityText('取消搜索书架')
        .onClick(() => this.closeShelfSearch())
    }
    .width('100%')
    .height(BookshelfPage.SEARCH_BAR_HEIGHT)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .margin({ bottom: AppSpacing.MD })
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -12 }))
      .combine(TransitionEffect.scale({ x: 0.96, y: 0.96, centerX: '50%', centerY: '0%' })))
  }

  stopShelfCategoryAnimation(): void {
    this.shelfCategoryAnimationSerial++;
    if (this.shelfCategoryAnimationWatchdog >= 0) {
      clearTimeout(this.shelfCategoryAnimationWatchdog);
      this.shelfCategoryAnimationWatchdog = -1;
    }
    this.shelfCategoryAnimating = false;
  }

  toggleShelfCategory(): void {
    this.stopShelfCategoryAnimation();
    const serial = this.shelfCategoryAnimationSerial;
    const expanded = !this.shelfCategoryExpanded;
    this.shelfCategoryExpandedRestored = true;
    BookshelfStateStore.saveCategoryExpanded(getContext(this), expanded).catch((e: Error) => {
      console.warn('保存书架分类栏展开状态失败:', e);
    });
    // 冷启动为收起状态时，首次展开前也有确定的材质宽度。
    this.shelfScopeTabsWidth = Math.max(1, this.contextViewportWidth - AppSpacing.XL * 2);
    this.shelfCategoryAnimating = true;
    const finish = (): void => {
      if (serial === this.shelfCategoryAnimationSerial) this.stopShelfCategoryAnimation();
    };
    this.shelfCategoryAnimationWatchdog = setTimeout(finish, 700);
    try {
      this.getUIContext().animateTo({ duration: 420, curve: Curve.Friction, onFinish: finish }, () => {
        // 原生共享元素同时接管两个材质节点的位置/尺寸和书架顶部留白。
        this.shelfCategoryExpanded = expanded;
      });
    } catch (error) {
      this.shelfCategoryExpanded = expanded;
      finish();
    }
  }

  @Builder
  shelfCategoryButtonMaterial() {
    ImmersiveMaterialSurface({
      surfaceWidth: BookshelfPage.HEADER_CONTROL_SIZE,
      surfaceHeight: BookshelfPage.HEADER_CONTROL_SIZE,
      darkMode: this.appDarkMode,
      fallbackColor: this.cardColor(),
      glowColor: this.accentGlowColor()
    }) {
      Row().width('100%').height('100%')
    }
  }

  @Builder
  shelfCategoryButton() {
    Stack() {
      Row() {
        this.shelfCategoryButtonMaterial()
      }
      .opacity(this.shelfCategoryExpanded ? 1 : 0)
      .animation({ duration: 140, curve: Curve.EaseOut })
      SymbolGlyph($r('sys.symbol.square_stack_3d'))
        .fontSize(20)
        .fontColor([this.primaryTextColor()])
        .hitTestBehavior(HitTestMode.None)
    }
    .width(BookshelfPage.HEADER_CONTROL_SIZE)
    .height(BookshelfPage.HEADER_CONTROL_SIZE)
    .margin({ right: 10 })
    .accessibilityText(this.shelfCategoryExpanded ? '收起分类' : '展开分类')
    .onClick(() => this.toggleShelfCategory())
  }

  showsShelfScopeTabs(): boolean {
    return this.bookshelfTypeCategoryEnabled && !this.isBookMultiSelect && !this.isTileGroupPage();
  }

  @Builder
  shelfScopeTabs() {
    Row() {
      if (this.shelfScopeTabsWidth > 0) {
          Stack({ alignContent: Alignment.BottomStart }) {
            Row() {
              ForEach(this.shelfTypeTabIds, (id: string) => {
                Text(this.shelfTypeTabLabel(id))
                  .fontSize(AppFontSize.BODY_LARGE)
                  .fontWeight(this.isShelfTypeTabSelected(id) ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.isShelfTypeTabSelected(id) ? this.accentColor() : this.secondaryTextColor())
                  .animation({ duration: 180, curve: Curve.Friction })
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height('100%')
                  .accessibilityText(this.shelfTypeTabLabel(id))
                  .accessibilitySelected(this.isShelfTypeTabSelected(id))
                  .onClick(() => this.switchShelfScopeBySelection(id))
              }, (id: string) => id)
            }
            .width('100%')
            .height('100%')
            .padding({ left: BookshelfPage.SCOPE_TABS_PADDING, right: BookshelfPage.SCOPE_TABS_PADDING })

            // 选中指示条：在选中项文字下方滑动，停在隐私书架时隐藏。
            Row()
              .width(BookshelfPage.SCOPE_TAB_INDICATOR_WIDTH)
              .height(3)
              .borderRadius(1.5)
              .backgroundColor(this.accentColor())
              .opacity(this.shelfScopeTabHighlighted() ? 1 : 0)
              .translate({ x: this.shelfScopeTabIndicatorX(), y: -5 })
              .animation({ curve: curves.springMotion(0.3, 1) })
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .height('100%')
      }
    }
    .width(`calc(100% - ${AppSpacing.XL * 2}vp)`)
    .height(BookshelfPage.SCOPE_TABS_HEIGHT)
    .borderRadius(BookshelfPage.SCOPE_TABS_HEIGHT / 2)
    .transition(TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseOut }))
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .hitTestBehavior(this.shelfCategoryExpanded && !this.shelfCategoryAnimating ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.shelfCategoryExpanded && !this.shelfCategoryAnimating ? 'auto' : 'no-hide-descendants')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.shelfScopeTabsTouching = false;
      } else if (event.touches.length > 0) {
        this.shelfScopeTabsTouchX = event.touches[0].x;
        this.shelfScopeTabsTouchY = event.touches[0].y;
        this.shelfScopeTabsTouching = true;
      }
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Math.floor(Number(newValue.width));
      if (Number.isFinite(width) && width > 0 && width !== this.shelfScopeTabsWidth) {
        this.shelfScopeTabsWidth = width;
      }
    })
  }

  /** 分类栏与结果同步切换，指示条由原生弹簧动画衔接。 */
  shelfScopeTabIndex(): number {
    const index = this.shelfTypeTabIds.indexOf(this.shelfPageKey());
    return index >= 0 ? index : 0;
  }

  shelfScopeTabHighlighted(): boolean {
    return this.shelfTypeTabIds.indexOf(this.shelfPageKey()) >= 0;
  }

  isShelfTypeTabSelected(id: string): boolean {
    return this.shelfScopeTabHighlighted() && this.shelfTypeTabIds[this.shelfScopeTabIndex()] === id;
  }

  /** 指示条居中在选中项下方；各项等宽平分分类栏去掉两侧留白后的宽度。 */
  shelfScopeTabIndicatorX(): number {
    const count = Math.max(1, this.shelfTypeTabIds.length);
    const itemWidth = (this.shelfScopeTabsWidth - BookshelfPage.SCOPE_TABS_PADDING * 2) / count;
    return BookshelfPage.SCOPE_TABS_PADDING + itemWidth * this.shelfScopeTabIndex() +
      (itemWidth - BookshelfPage.SCOPE_TAB_INDICATOR_WIDTH) / 2;
  }

  /** 顶部沉浸控件的触摸光晕。 */
  accentGlowColor(): string {
    return `#40${this.accentColor().substring(1)}`;
  }

  @Builder
  shelfHeaderCircleButton(icon: Resource, active: boolean, label: string, onTap: () => void) {
    ImmersiveMaterialSurface({
      surfaceWidth: BookshelfPage.HEADER_CONTROL_SIZE,
      surfaceHeight: BookshelfPage.HEADER_CONTROL_SIZE,
      darkMode: this.appDarkMode,
      fallbackColor: this.cardColor(),
      glowColor: this.accentGlowColor()
    }) {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([active ? this.accentColor() : this.primaryTextColor()])
      }
      .width('100%')
      .height('100%')
      .accessibilityText(label)
      .onClick(() => onTap())
    }
  }

  @Builder
  shelfFilterButton() {
    Row() {
      this.shelfHeaderCircleButton($r('sys.symbol.funnel'),
        this.showShelfFilterMenu || this.shelfFilterKeyList().length > 0, this.shelfFilterAccessibilityText(), () => {
          this.showShelfFilterMenu = !this.showShelfFilterMenu;
          this.shelfFilterMenuPage = '';
          this.showShelfMoreMenu = false;
          this.showShelfGroupMenu = false;
        })
    }
    .margin({ right: 10 })
    .bindPopup(this.showShelfFilterMenu, this.shelfMenuPopupOptions((): void => {
      this.shelfFilterDropdown()
    }, Placement.BottomRight, () => {
      this.showShelfFilterMenu = false;
      this.shelfFilterMenuPage = '';
    }))
  }

  shelfFilterAccessibilityText(): string {
    const keys = this.shelfFilterKeyList();
    return keys.length === 0 ? '筛选' :
      `筛选，当前${keys.map((key: string) => this.shelfFilterLabel(key)).join('、')}`;
  }

  @Builder
  shelfFilterDropdown() {
    if (this.shelfFilterMenuPage === 'tag') {
      this.shelfFilterSubpage('标签', SHELF_FILTER_TAG_PREFIX, this.shelfTagFilterOptions(), '当前书架的书没有标签')
    } else if (this.shelfFilterMenuPage === 'origin') {
      this.shelfFilterSubpage('书源', SHELF_FILTER_ORIGIN_PREFIX, this.shelfOriginFilterOptions(), '当前书架没有网络书籍')
    } else {
      this.shelfFilterMainPage()
    }
  }

  @Builder
  shelfFilterMainPage() {
    Column({ space: AppSpacing.XXS }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17)
          .fontColor([this.shelfSearchActive ? this.accentColor() : this.secondaryTextColor()])
        Text('搜索书架')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.shelfSearchActive ? this.accentColor() : this.primaryTextColor())
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([this.secondaryTextColor()])
      }
      .width('100%')
      .height(BookshelfPage.MENU_ITEM_HEIGHT)
      .padding({ left: 12, right: 12 })
      .borderRadius(this.shelfMenuItemRadius())
      .alignItems(VerticalAlign.Center)
      .accessibilityText('搜索书架')
      .onClick(() => this.openShelfSearch())

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.appDarkMode))
        .margin({ top: AppSpacing.XXS, left: 12, right: 12 })

      ForEach(BookshelfPage.FILTER_GROUP_LABELS, (label: string, index: number) => {
        this.filterSectionLabel(label)
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(BookshelfPage.FILTER_GROUPS[index], (key: string) => {
            this.filterChip(key)
          }, (key: string) => key)
        }
        .width('100%')
        .padding({ left: 12, right: 4 })
      }, (label: string) => label)

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.appDarkMode))
        .margin({ left: 12, right: 12 })
      this.filterSubpageEntry('标签', 'tag', SHELF_FILTER_TAG_PREFIX)
      this.filterSubpageEntry('书源', 'origin', SHELF_FILTER_ORIGIN_PREFIX)

      if (this.shelfFilterKeyList().length > 0) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.hairlineColor(this.appDarkMode))
          .margin({ top: AppSpacing.XS, bottom: AppSpacing.XS, left: 12, right: 12 })
        Text('清除筛选')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .height(BookshelfPage.MENU_ITEM_HEIGHT)
          .textAlign(TextAlign.Center)
          .borderRadius(this.shelfMenuItemRadius())
          .onClick(() => this.setShelfFilterKeys([]))
      }
    }
    .width(248)
    .padding(BookshelfPage.MENU_PADDING)
  }

  /** 主页上的“标签 ›”“书源 ›”：右侧显示已选的名字，点进二级页。 */
  @Builder
  filterSubpageEntry(title: string, page: string, prefix: string) {
    Row({ space: AppSpacing.SM }) {
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
      Text(this.shelfFilterSelectedSummary(prefix))
        .fontSize(AppFontSize.BODY)
        .fontColor(this.shelfFilterSelectedSummary(prefix) === '不限' ? this.secondaryTextColor() : this.accentColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([this.secondaryTextColor()])
    }
    .width('100%')
    .height(BookshelfPage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.shelfMenuItemRadius())
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`${title}筛选，${this.shelfFilterSelectedSummary(prefix)}`)
    .onClick(() => {
      this.shelfFilterMenuPage = page;
    })
  }

  @Builder
  shelfFilterSubpage(title: string, prefix: string, options: ShelfFilterOption[], emptyText: string) {
    Column({ space: AppSpacing.XXS }) {
      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(16)
          .fontColor([this.primaryTextColor()])
        Text(title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .height(BookshelfPage.MENU_ITEM_HEIGHT)
      .padding({ left: 12, right: 12 })
      .borderRadius(this.shelfMenuItemRadius())
      .alignItems(VerticalAlign.Center)
      .accessibilityText(`返回筛选，当前为${title}`)
      .onClick(() => {
        this.shelfFilterMenuPage = '';
      })

      if (options.length === 0) {
        Text(emptyText)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: AppSpacing.LG, bottom: AppSpacing.LG })
      } else {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(options, (option: ShelfFilterOption) => {
              this.filterCountChip(option)
            }, (option: ShelfFilterOption) => option.key)
          }
          .width('100%')
          .padding({ left: 12, right: 4, top: AppSpacing.XS })
        }
        .width('100%')
        .constraintSize({ maxHeight: BookshelfPage.FILTER_SUBPAGE_MAX_HEIGHT })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
      }

      if (this.shelfFilterKeysWithPrefix(prefix).length > 0) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.hairlineColor(this.appDarkMode))
          .margin({ top: AppSpacing.XS, bottom: AppSpacing.XS, left: 12, right: 12 })
        Text(`清除${title}筛选`)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .height(BookshelfPage.MENU_ITEM_HEIGHT)
          .textAlign(TextAlign.Center)
          .borderRadius(this.shelfMenuItemRadius())
          .onClick(() => this.setShelfFilterKeys(this.shelfFilterKeyList()
            .filter((key: string) => !key.startsWith(prefix))))
      }
    }
    .width(248)
    .padding(BookshelfPage.MENU_PADDING)
  }

  /** 标签、书源小块：名字后跟本数。 */
  @Builder
  filterCountChip(option: ShelfFilterOption) {
    Text() {
      Span(option.label)
      Span(` ${option.count}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
        .fontWeight(FontWeight.Regular)
    }
    .fontSize(AppFontSize.BODY)
    .fontWeight(this.isShelfFilterSelected(option.key) ? FontWeight.Medium : FontWeight.Regular)
    .fontColor(this.isShelfFilterSelected(option.key) ? this.accentColor() : this.primaryTextColor())
    .maxLines(1)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .constraintSize({ maxWidth: 216 })
    .height(32)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(16)
    .backgroundColor(this.isShelfFilterSelected(option.key) ? ThemeRuntime.selectedFillColor(this.appDarkMode) :
      ThemeRuntime.softFillColor(this.appDarkMode))
    .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
    .accessibilityText(`${option.label}，${option.count}本`)
    .accessibilitySelected(this.isShelfFilterSelected(option.key))
    .onClick(() => this.toggleShelfFilter(option.key))
  }

  shelfFilterKeysWithPrefix(prefix: string): string[] {
    return this.shelfFilterKeyList().filter((key: string) => key.startsWith(prefix));
  }

  shelfFilterSelectedSummary(prefix: string): string {
    const keys = this.shelfFilterKeysWithPrefix(prefix);
    return keys.length === 0 ? '不限' : keys.map((key: string) => BookshelfPage.shelfFilterKeyValue(key)).join('、');
  }

  @Builder
  filterSectionLabel(label: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.secondaryTextColor())
      .width('100%')
      .padding({ left: 12, top: AppSpacing.SM, bottom: AppSpacing.XXS })
  }

  /** 多选：点一项切换选中，菜单保持打开。 */
  @Builder
  filterChip(key: string) {
    Text(this.shelfFilterLabel(key))
      .fontSize(AppFontSize.BODY)
      .fontWeight(this.isShelfFilterSelected(key) ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.isShelfFilterSelected(key) ? this.accentColor() : this.primaryTextColor())
      .maxLines(1)
      .height(32)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(16)
      .backgroundColor(this.isShelfFilterSelected(key) ? ThemeRuntime.selectedFillColor(this.appDarkMode) :
        ThemeRuntime.softFillColor(this.appDarkMode))
      .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
      .accessibilityText(this.shelfFilterLabel(key))
      .accessibilitySelected(this.isShelfFilterSelected(key))
      .onClick(() => this.toggleShelfFilter(key))
  }

  shelfFilterLabel(key: string): string {
    if (key === 'network') return '网络';
    if (key === 'local') return '本地';
    if (key === 'finished') return '已完结';
    if (key === 'ongoing') return '连载中';
    if (key === 'unread') return '未读';
    if (key === 'reading') return '在读';
    if (key === 'readDone') return '已读完';
    if (key === 'updated') return '有更新';
    if (key === 'read7d') return '一周内';
    if (key === 'read30d') return '一月内';
    if (key === 'stale90d') return '三个月没读';
    return BookshelfPage.shelfFilterKeyValue(key);
  }

  isShelfFilterSelected(key: string): boolean {
    return this.shelfFilterKeyList().indexOf(key) >= 0;
  }

  toggleShelfFilter(key: string): void {
    const keys = this.shelfFilterKeyList();
    const index = keys.indexOf(key);
    if (index >= 0) {
      keys.splice(index, 1);
    } else {
      keys.push(key);
    }
    this.setShelfFilterKeys(keys);
  }

  setShelfFilterKeys(keys: string[]): void {
    const next = BookshelfPage.canonicalShelfFilterKeys(keys).join(',');
    if (next === this.shelfFilterKeys) {
      return;
    }
    this.shelfFilterKeys = next;
    this.applyShelfScope();
    this.reloadShelfDataSources(true);
    this.refreshShelfCoverCache(this.books);
  }

  @Builder
  shelfMoreButton() {
    Row() {
      this.shelfHeaderCircleButton($r('sys.symbol.more'), this.showShelfMoreMenu, '更多操作', () => {
        this.shelfMoreMenuPage = '';
        this.showShelfMoreMenu = !this.showShelfMoreMenu;
        this.showShelfFilterMenu = false;
        this.showShelfGroupMenu = false;
      })
    }
    .bindPopup(this.showShelfMoreMenu, this.shelfMenuPopupOptions((): void => {
      this.shelfMoreDropdown()
    }, Placement.BottomRight, () => {
      this.showShelfMoreMenu = false;
    }))
  }

  @Builder
  shelfMoreDropdown() {
    Column({ space: AppSpacing.XXS }) {
      if (this.shelfMoreMenuPage !== '') {
        Row({ space: AppSpacing.SM }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(14)
            .fontColor([this.primaryTextColor()])
          Text(this.shelfMoreMenuPage === 'layout' ? '布局' : '排序')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
        }
        .width('100%')
        .height(BookshelfPage.MENU_ITEM_HEIGHT)
        .padding({ left: 12, right: 12 })
        .accessibilityText('返回更多操作')
        .onClick(() => { this.shelfMoreMenuPage = ''; })
        Divider().color(ThemeRuntime.hairlineColor(this.appDarkMode))
      }
      if (this.shelfMoreMenuPage === 'layout') {
        this.layoutDropdownItem('紧凑', 'compact', $r('sys.symbol.list_bullet'))
        this.layoutDropdownItem('宽松', 'loose', $r('sys.symbol.bookshelf'))
        this.layoutDropdownItem('平铺', 'tile', $r('sys.symbol.square_grid_2x2'))
        this.layoutDropdownItem('陪伴', 'companion', $r('sys.symbol.book_pages'))
      } else if (this.shelfMoreMenuPage === 'sort') {
        this.sortDropdownItem('新阅读', 'recentRead')
        this.sortDropdownItem('新加入', 'recentAdd')
        this.sortDropdownItem('最近更新', 'recentUpdate')
        this.sortDropdownItem('名称', 'name')
      } else {
        this.shelfMoreMenuItem('布局', this.isCompanionLayout() ? '陪伴' : (this.bookshelfLayoutMode === 'tile' ? '平铺' :
          (this.bookshelfLayoutMode === 'loose' ? '宽松' : '紧凑')), $r('sys.symbol.square_grid_2x2'), 'layout')
        this.shelfMoreMenuItem('排序', this.sortModeLabel(), $r('sys.symbol.text_arrow_up_and_down'), 'sort')
      }
    }
    .width(224)
    .padding(BookshelfPage.MENU_PADDING)
  }

  @Builder
  shelfMoreMenuItem(label: string, value: string, icon: Resource, page: string) {
    Row({ space: AppSpacing.SM }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.primaryTextColor()])
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Text(value)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(BookshelfPage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.shelfMenuItemRadius())
    .accessibilityText(`${label}：${value}`)
    .onClick(() => { this.shelfMoreMenuPage = page; })
  }

  shelfMenuPopupOptions(builder: CustomBuilder, placement: Placement, onHidden: () => void): CustomPopupOptions {
    return ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, builder, placement, this.appDarkMode, this.accentColor(), onHidden);
  }

  shelfMenuItemRadius(): number {
    return BookshelfPage.MENU_RADIUS - BookshelfPage.MENU_PADDING;
  }

  @Builder
  layoutDropdownItem(label: string, mode: string, icon: Resource) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([this.bookshelfLayoutMode === mode ? this.accentColor() : this.secondaryTextColor()])
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.bookshelfLayoutMode === mode ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.bookshelfLayoutMode === mode ? this.accentColor() : this.primaryTextColor())
        .layoutWeight(1)

      if (this.bookshelfLayoutMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(BookshelfPage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.shelfMenuItemRadius())
    .backgroundColor(this.bookshelfLayoutMode === mode ? this.selectedSoftBackgroundColor() : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.applyBookshelfLayoutMode(mode))
  }

  applyBookshelfLayoutMode(mode: string): void {
    const next = mode === 'loose' || mode === 'tile' || mode === 'companion' ? mode : 'compact';
    this.bookshelfLayoutMode = next;
    // The tile data source excludes the expanded recent-read book only in tile mode.
    // Rebuild it immediately when switching layouts so a compact-mode cache entry
    // cannot be rendered alongside the expanded tile card.
    this.reloadShelfDataSources(true);
    this.showShelfMoreMenu = false;
    this.showShelfFilterMenu = false;
    const settings = BookshelfDisplaySettingsStore.fromStorage();
    settings.layoutMode = next;
    BookshelfDisplaySettingsStore.applyToStorage(settings);
    BookshelfDisplaySettingsStore.save(getContext(this), settings).catch((e: Error) => {
      console.warn('保存书架布局失败:', e);
      HdsFeedback.showToast('布局保存失败');
    });
  }

  @Builder
  sortDropdownItem(label: string, mode: string) {
    Row() {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(this.sortMode === mode ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.sortMode === mode ? this.accentColor() : this.primaryTextColor())
        .layoutWeight(1)

      if (this.sortMode === mode) {
        Text('✓')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.accentColor())
      }
    }
    .width('100%')
    .height(BookshelfPage.MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .borderRadius(this.shelfMenuItemRadius())
    .backgroundColor(this.sortMode === mode ? this.selectedSoftBackgroundColor() : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.applyShelfSortMode(mode);
    })
  }

  sortModeLabel(): string {
    if (this.sortMode === 'recentUpdate') return '最近更新';
    if (this.sortMode === 'recentAdd') {
      return '新加入';
    }
    if (this.sortMode === 'name') {
      return '名称';
    }
    return '新阅读';
  }

  selectedSoftBackgroundColor(): string {
    const color = this.accentColor();
    return `#1A${color.substring(1)}`;
  }

  applyShelfSortMode(mode: string): void {
    const next = BookshelfStateStore.normalizeSortMode(mode);
    this.showShelfMoreMenu = false;
    if (this.sortMode === next) {
      // Migrate installations that previously kept this value only in AppStorage.
      this.persistShelfSortMode(next);
      if (this.pendingShelfSortTimer >= 0) {
        clearTimeout(this.pendingShelfSortTimer);
        this.pendingShelfSortTimer = -1;
      }
      this.pendingShelfSortMode = '';
      // 'recentRead' is the default and therefore the mode the user re-taps most often. Re-selecting
      // the already-active mode must still visibly re-sort: a silent return made "点了排序没反应" look
      // like the sort itself was broken whenever the retained snapshot was stale for any reason.
      this.reorderShelfForSortMode(next);
      this.scheduleLoadBooks();
      return;
    }
    if (this.shelfScopeSwitchAnimating) {
      this.pendingShelfSortMode = next;
      if (this.pendingShelfSortTimer >= 0) {
        clearTimeout(this.pendingShelfSortTimer);
      }
      this.pendingShelfSortTimer = setTimeout(() => {
        this.pendingShelfSortTimer = -1;
        const pending = this.pendingShelfSortMode;
        this.pendingShelfSortMode = '';
        if (pending) {
          this.applyShelfSortMode(pending);
        }
      }, 280);
      return;
    }
    if (this.pendingShelfSortTimer >= 0) {
      clearTimeout(this.pendingShelfSortTimer);
      this.pendingShelfSortTimer = -1;
    }
    this.pendingShelfSortMode = '';
    this.persistShelfSortMode(next);
    this.reorderShelfForSortMode(next);
    // The synchronous reorder only re-sorts the snapshot the shelf already holds. Follow it with a
    // DB-backed reload so a snapshot that went stale (e.g. a missed progress notification while the
    // shelf was covered by the reader) cannot keep rendering yesterday's order.
    this.scheduleLoadBooks();
  }

  /**
   * Re-derive the visible shelf order for the newly selected sort mode.
   *
   * This deliberately does not go through animateShelfContentUpdate(): that helper drives the
   * scope-switch slide transition, so reusing it for sorting routed a plain reorder through a
   * 115ms delay plus a second animation frame, and re-entrant selections landed in the
   * shelfScopeSwitchAnimating branch instead of applying. A sort is a one-shot content swap,
   * it must be applied synchronously to both rendered layouts (compact/loose list + tile grid).
   */
  private reorderShelfForSortMode(mode: string): void {
    this.shelfCategoryRevision++;
    this.sortMode = mode;
    const source = this.booksForShelfScope(this.shelfScope);
    const sorted = this.sortBooks(source, mode);
    this.books = sorted;
    // Both layouts read from their own LazyForEach source, and the tile grid additionally caches
    // its root entries. Invalidate the cache before rebuilding so the tile layout cannot render a
    // stale entry order produced by the previous sort mode.
    this.shelfTileEntriesCacheKey = '';
    this.shelfTileEntriesCache = [];
    this.shelfListBooksSource.replace(sorted, true);
    this.shelfTileBooksSource.replace(this.getTileBooksWithoutLatest(sorted), true);
    this.shelfTileEntriesSource.replace(this.getSortedTileRootEntries(sorted, mode), true);
  }

  private persistShelfSortMode(mode: string): void {
    BookshelfStateStore.saveSortMode(getContext(this), mode).catch((e: Error) => {
      console.warn('保存书架排序设置失败:', e);
    });
  }

  sortBooks(books: Book[], mode: string = this.sortMode): Book[] {
    const sorted = [...books];
    sorted.sort((a: Book, b: Book) => {
      if (a.isPinned !== b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      if (mode === 'recentRead') {
        return BookshelfSortHelper.compareRecentRead(a, b);
      }
      if (mode === 'name') {
        return this.compareBookName(a, b);
      }
      if (mode === 'recentUpdate') {
        return BookshelfSortHelper.getBookUpdateTime(b) - BookshelfSortHelper.getBookUpdateTime(a) ||
          this.compareBookName(a, b);
      }
      return this.getBookAddTime(b) - this.getBookAddTime(a);
    });
    return sorted;
  }

  compareBookName(a: Book, b: Book): number {
    const nameA = this.normalizeBookName(a.name);
    const nameB = this.normalizeBookName(b.name);
    const nameDiff = nameA.localeCompare(nameB, 'zh-Hans-CN-u-co-pinyin');
    if (nameDiff !== 0) {
      return nameDiff;
    }
    return this.getBookAddTime(b) - this.getBookAddTime(a);
  }

  normalizeBookName(name?: string): string {
    if (!name) {
      return '';
    }
    return name
      .trim()
      .replace(/^[《〈「『“"'(\[【\s]+/g, '')
      .replace(/[》〉」』”"')\]】\s]+$/g, '');
  }

  shelfTileBookDisplayName(book: Book): string {
    const title = (book?.name || '').trim();
    if (title) {
      return title;
    }
    const bookUrl = (book?.bookUrl || '').trim();
    if (!bookUrl) {
      return '未知书名';
    }
    const candidate = bookUrl.split(/[/?#]/).filter((part: string) => part).pop() || '';
    if (!candidate) {
      return '未知书名';
    }
    const rawTitle = (() => {
      try {
        return decodeURIComponent(candidate);
      } catch (_error) {
        return candidate;
      }
    })();
    return rawTitle.replace(/\.[^./\\]*$/, '').trim() || '未知书名';
  }

  getBookAddTime(book: Book): number {
    return BookshelfSortHelper.getBookAddTime(book);
  }

  getBookReadTime(book: Book): number {
    return BookshelfSortHelper.getBookReadTime(book);
  }

  parseBookTime(value: string): number {
    return BookshelfSortHelper.parseBookTime(value);
  }

  getShelfProgressText(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return '未读';
    }
    if (!this.hasKnownReadProgressTotal(book)) return '进度未知';
    return book.getUnreadChapterNum() > 0 ? this.getReadProgressPercentText(book) :
      (this.getReadProgressValue(book) >= 100 ? '已读完' : '阅读中');
  }

  hasKnownReadProgressTotal(book: Book): boolean {
    return Number.isFinite(book.totalChapterNum) && book.totalChapterNum > 0 &&
      Number.isFinite(book.durChapterIndex) && book.durChapterIndex >= 0 &&
      book.durChapterIndex < book.totalChapterNum;
  }

  getReadProgressValue(book: Book): number {
    if (LocalBookService.isPdfBook(book)) {
      return Math.floor(PdfPagePosition.percent(book.durChapterIndex, book.totalChapterNum, book.hasStartedReading()) * 10) / 10;
    }
    if (!this.hasKnownReadProgressTotal(book)) {
      return 0;
    }
    if (!Book.hasStartedReading(book)) {
      return 0;
    }
    const chapterIndex = Math.min(Math.max(book.durChapterIndex, 0), book.totalChapterNum - 1);
    const progressChapterIndex = Number.parseInt(book.getVariable('readProgressChapterIndex'));
    const currentChapterPageCount = Number.parseInt(book.getVariable('readProgressPageCount'));
    // Unknown/mismatched pagination only proves that earlier chapters were passed.
    let currentChapterProgress = 0;
    if (progressChapterIndex === chapterIndex && Number.isFinite(currentChapterPageCount) &&
      currentChapterPageCount > 0 && Number.isFinite(book.durChapterPos)) {
      const currentPageNumber = Math.min(Math.max(book.durChapterPos + 1, 1), currentChapterPageCount);
      currentChapterProgress = currentPageNumber / currentChapterPageCount;
    }
    const readChapterCount = Math.min(chapterIndex + currentChapterProgress, book.totalChapterNum);
    return Math.floor(readChapterCount * 1000 / book.totalChapterNum) / 10;
  }

  getReadProgressPercentText(book: Book): string {
    if (!this.hasKnownReadProgressTotal(book)) return '进度未知';
    const progress = this.getReadProgressValue(book);
    if (progress <= 0) {
      return '已读0%';
    }
    if (progress >= 100) {
      return '已读100%';
    }
    return progress % 1 === 0 ? `已读${progress.toFixed(0)}%` : `已读${progress.toFixed(1)}%`;
  }

  getLastReadTimeText(book: Book): string {
    const readTime = this.getBookReadTime(book);
    if (readTime <= 0) {
      return '未读';
    }
    return this.formatShelfTime(readTime);
  }

  formatShelfTime(time: number): string {
    const date = new Date(time);
    if (Number.isNaN(date.getTime())) {
      return '未知';
    }
    const now = new Date();
    const dateStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const nowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const dayDiff = Math.floor((nowStart - dateStart) / 86400000);
    const timeText = `${this.padTime(date.getHours())}:${this.padTime(date.getMinutes())}`;
    if (dayDiff === 0) {
      return `今天 ${timeText}`;
    }
    if (dayDiff === 1) {
      return `昨天 ${timeText}`;
    }
    if (date.getFullYear() === now.getFullYear()) {
      return `${date.getMonth() + 1}-${this.padTime(date.getDate())} ${timeText}`;
    }
    return `${date.getFullYear()}-${this.padTime(date.getMonth() + 1)}-${this.padTime(date.getDate())} ${timeText}`;
  }

  padTime(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  @Builder
  readProgressPanel(book: Book) {
    Column({ space: AppSpacing.XS }) {
      Text(this.getReadProgressInfoText(book))
        .fontSize(AppFontSize.CAPTION)
        // 行高固定，shelfProgressPanelHeight() 才能算出与封面一致的高度。
        .lineHeight(this.shelfSmallTextLineHeight())
        .fontColor(this.subTextColor())
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
        .visibility(this.hasKnownReadProgressTotal(book) ? Visibility.Visible : Visibility.Hidden)
        .width('100%')
        .height(3)
        .color(this.accentColor())
        .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')
    }
    .width('100%')
  }

  @Builder
  looseReadProgressPanel(book: Book) {
    Column({ space: AppSpacing.XS }) {
      Progress({ value: this.getReadProgressValue(book), total: 100, type: ProgressType.Linear })
        .visibility(this.hasKnownReadProgressTotal(book) ? Visibility.Visible : Visibility.Hidden)
        .width('100%')
        .height(3)
        .color(this.accentColor())
        .backgroundColor(this.appDarkMode ? '#2D3138' : '#E8EAED')

      Text(this.getReadProgressInfoText(book))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  getReadProgressInfoText(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return '未读';
    }
    const parts: string[] = [this.getReadProgressPercentText(book)];
    if (this.bookshelfShowLastReadTime) {
      parts.push(this.getLastReadTimeText(book));
    }
    if (this.bookshelfShowLastReadChapter) {
      const chapterText = this.getReadChapterText(book);
      if (chapterText) {
        parts.push(chapterText);
      }
    }
    return parts.join(' · ');
  }

  getReadChapterText(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return '';
    }
    return (book.durChapterTitle || '').trim();
  }

  getLastReadChapterText(book: Book): string {
    if (LocalBookService.isPdfBook(book)) return book.hasStartedReading() ? `第 ${book.durChapterIndex + 1} 页` : '尚未阅读';
    if (!Book.hasStartedReading(book)) {
      return '尚未阅读';
    }
    const chapterNumber = book.durChapterIndex >= 0 ? book.durChapterIndex + 1 : -1;
    const chapterTitle = this.getReadChapterText(book);
    if (chapterNumber > 0 && chapterTitle) {
      return `第${chapterNumber}章 · ${chapterTitle}`;
    }
    if (chapterNumber > 0) {
      return `第${chapterNumber}章`;
    }
    return chapterTitle || '尚未记录章节';
  }

  getLastReadChapterNumberText(book: Book): string {
    if (LocalBookService.isPdfBook(book)) return book.hasStartedReading() ? `第 ${book.durChapterIndex + 1} 页` : '尚未阅读';
    if (!Book.hasStartedReading(book)) {
      return '尚未阅读';
    }
    return book.durChapterIndex >= 0 ? `第${book.durChapterIndex + 1}章` : '章节号未知';
  }

  getLastReadChapterNameText(book: Book): string {
    if (!Book.hasStartedReading(book)) {
      return '尚未记录章节';
    }
    const originalTitle = this.getReadChapterText(book).replace(/\s+/g, ' ').trim();
    if (!originalTitle) {
      return '章节名未知';
    }
    let title = originalTitle;
    const chineseChapterPrefix =
      /^第\s*[0-9０-９零〇○一二三四五六七八九十百千万亿两壹贰叁肆伍陆柒捌玖拾佰仟]+\s*(?:章|回|节|話|话|集|篇|幕)\s*(?:[·•:：、.．\-—]+\s*)?/;
    const englishChapterPrefix =
      /^(?:chapter|chap\.?|ch\.?)\s*[0-9０-９]+\s*(?:[·•:：、.．\-—]+\s*)?/i;
    // Some sources return duplicated prefixes such as “第233章 第233章 寒山奇石”.
    // Strip at most a few leading ordinals while preserving the stored chapter title itself.
    for (let index = 0; index < 3; index++) {
      const stripped = title.replace(chineseChapterPrefix, '').replace(englishChapterPrefix, '').trim();
      if (stripped === title) break;
      title = stripped;
      if (!title) break;
    }
    return title || '章节名未知';
  }

  getLastReadPagePreviewText(book: Book): string {
    const text = book.getVariable('lastReadPageText').trim();
    return text || '再次阅读后，将在这里显示上次阅读页的正文内容。';
  }

  getLastReadPageNumberText(book: Book): string {
    if (LocalBookService.isPdfBook(book)) return `${book.durChapterIndex + 1}/${book.totalChapterNum}`;
    const pageCount = Number.parseInt(book.getVariable('readProgressPageCount'));
    const pageNumber = Math.max(1, book.durChapterPos + 1);
    return pageCount > 0 ? `${Math.min(pageNumber, pageCount)}/${pageCount}` : `${pageNumber}`;
  }

  getLastReadLeafContentMode(book: Book): string {
    if (this.bookshelfLastReadLeafMode === 'bookInfo' || this.bookshelfLastReadLeafMode === 'contentPreview') {
      return this.bookshelfLastReadLeafMode;
    }
    // 有声与视频没有可预览的正文。
    if (BookTypeSupport.isAudio(book) || BookTypeSupport.isVideo(book) || LocalBookService.isPdfBook(book)) {
      return 'bookInfo';
    }
    if (this.isShelfComicBook(book) && this.getLastReadPageImage(book)) {
      return 'comicPreview';
    }
    return 'contentPreview';
  }

  isShelfComicBook(book: Book): boolean {
    if (book.origin === 'local') {
      return BookTypeSupport.isImage(book);
    }
    return BookTypeSupport.isImage(book) || book.getVariable('readerComicManualMode') === 'comic' ||
      book.getVariable('readerComicAutoDetected') === '1' || book.getVariable('readerComicMode') === '1';
  }

  getLastReadPageImage(book: Book): string {
    const source = book.getVariable('lastReadPageImage').trim();
    if (!source || /^(?:https?:|data:|file:)/i.test(source)) {
      return source;
    }
    try {
      return fileUri.getUriFromPath(source);
    } catch (_) {
      return source;
    }
  }

  @Builder
  shelfLastReadLeaf(book: Book) {
    if (this.getLastReadLeafContentMode(book) === 'bookInfo') {
      this.shelfLastReadBookInfo(book)
    } else if (this.getLastReadLeafContentMode(book) === 'comicPreview') {
      Image(this.getLastReadPageImage(book))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .draggable(false)
    } else {
      Text(this.getLastReadPagePreviewText(book))
        .width('100%')
        .layoutWeight(1)
        .fontSize(4.8)
        .lineHeight(7.5)
        .fontColor(this.shelfTilePageTextColor())
        .textAlign(TextAlign.JUSTIFY)
        .wordBreak(WordBreak.BREAK_WORD)
        .maxLines(16)
        .textOverflow({ overflow: TextOverflow.Clip })
        .margin({ top: AppSpacing.XS })

      Text(this.getLastReadPageNumberText(book))
        .width('100%')
        .fontSize(5)
        .fontColor(this.shelfTilePageSubTextColor())
        .textAlign(TextAlign.End)
    }
  }

  @Builder
  shelfLastReadBookInfo(book: Book) {
    Column() {
      Text(this.shelfTileBookDisplayName(book))
        .width('100%')
        .fontSize(AppFontSize.MICRO)
        .lineHeight(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.shelfTilePageTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text((book.author || '').trim() || '作者未知')
        .width('100%')
        .fontSize(7)
        .lineHeight(10)
        .fontColor(this.shelfTilePageSubTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 5 })

      Blank()
        .layoutWeight(1)

      Text(this.getLastReadChapterNumberText(book))
        .width('100%')
        .fontSize(8)
        .lineHeight(11)
        .fontColor(this.shelfTilePageTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.getLastReadChapterNameText(book))
        .width('100%')
        .fontSize(8)
        .lineHeight(11)
        .fontColor(this.shelfTilePageTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 1 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  shelfTilePageColor(): string {
    return this.appDarkMode ? '#242321' : '#F8F4E9';
  }

  shelfTilePageTextColor(): string {
    return this.appDarkMode ? '#D8D3C8' : '#3E3A33';
  }

  shelfTilePageSubTextColor(): string {
    return this.appDarkMode ? '#8F8A82' : '#8A8378';
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  shelfSurfaceColor(): string {
    return ThemeRuntime.homeSurfaceColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  glassCardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  glassShadowColor(): string {
    return '#00000000';
  }

  sourceTagBackgroundColor(): string {
    return this.selectedSoftBackgroundColor();
  }

  sourceTagTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : this.accentColor();
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

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }
}
