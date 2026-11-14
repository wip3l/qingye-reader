import { WebParseSettingsStore } from '../../utils/WebParseSettingsStore';
import { SharedElementMotion } from '../../utils/SharedElementMotion';
import { ShelfCoverLocator } from '../../utils/ShelfCoverLocator';
import { ShelfBookPerspective, ShelfBookShape } from '../../utils/ShelfBookPerspective';
import { PdfPagePosition } from '../../core/book/pdf/PdfModels';
import {
  SHELF_COVER_OPEN_DURATION, SHELF_COVER_OPEN_START_CAP, SHELF_BOOK_MOTION_UNTIL_KEY, SHELF_BOOK_MOTION_SETTLE,
  SHELF_OPENING_BACKDROP_KEY, SHELF_OPENING_COVER_KEY, SHELF_OPENING_PAGE_SNAPSHOT_KEY, ShelfOpeningCover
} from '../reader/ReaderShelfCoverOpening';
import { ReaderOpenSnapshot, ReaderOpenSnapshotStore } from '../../core/reader/ReaderOpenSnapshotStore';
import { SharedElementBounds } from '../../utils/SharedElementBounds';
import { DeleteParticles, DeleteParticleLayer, DeleteParticleBurst } from '../common/DeleteParticles';
import { BookshelfCoverBadges } from '../BookshelfCoverBadges';
import { BookshelfCoverBadgeSettings } from '../../utils/BookshelfCoverBadgeSettings';
import { componentUtils, curves, FrameCallback, router, window } from '@kit.ArkUI';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { BackgroundPermit } from '../../utils/BackgroundPermit';
import { notificationManager } from '@kit.NotificationKit';
import deviceInfo from '@ohos.deviceInfo';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
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
import { AnimatedImagePolicy } from '../../utils/AnimatedImagePolicy';
import { BookCoverCache } from '../../utils/BookCoverCache';
import { CoverGallerySettings } from '../../utils/CoverGallerySettings';
import { BookshelfDisplaySettingsStore } from '../../utils/BookshelfDisplaySettingsStore';
import { BookshelfStateStore } from '../../utils/BookshelfStateStore';
import { SearchExplorePendingBook } from '../../utils/SearchExplorePendingBook';
import { BookshelfSortHelper } from '../../utils/BookshelfSortHelper';
import { RecentReadCarousel } from './RecentReadCarousel';
import { ShelfReadingNoteCard } from './ShelfReadingNoteCard';
import { ShelfGreetingEditor } from './ShelfGreetingEditor';
import { ShelfSectionTitleEditor } from './ShelfSectionTitleEditor';
import { ShelfGreetingTemplate, ShelfGreetingValues } from '../../utils/ShelfGreetingTemplate';
import { CategorySwipePager } from './CategorySwipePager';
import { ShelfCategoryMaterial } from './ShelfCategoryMaterial';
import { SearchExploreSettingsStore } from '../../utils/SearchExploreSettingsStore';
import { AppThemeSettingsStore } from '../../utils/AppThemeSettingsStore';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { ThemeImageSlots } from '../../theme/ThemePackRegistry';
import { ThemeImageCrop } from '../../theme/share/ThemePackageFormat';
import { ThemeCroppedImage } from '../theme/ThemeCroppedImage';
import { ThemeBookCoverSettings } from '../../utils/ThemeBookCoverSettings';
import { CoverDimSettings } from '../../utils/CoverDimSettings';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { HexColor } from '../../utils/HexColor';
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
import { ReaderHaptics } from '../../utils/ReaderHaptics';

const SHELF_FULL_TEXT_CACHE_NOTIFICATION_INTERVAL_MS: number = 5000;
/** 有声书同时下载的章数。 */
const SHELF_AUDIO_DOWNLOAD_CONCURRENCY: number = 2;
/**
 * 书架检查更新同时刷新的书数，每路各用一个后台引擎。耗时主要在等网络，并发能把总时长压到接近最慢的几本。
 * 同一书源最多同时刷 SHELF_REFRESH_PER_SOURCE 本，没填 concurrentRate 的书源也不至于被一下子打满。
 */
const SHELF_REFRESH_CONCURRENCY: number = 6;
const SHELF_REFRESH_PER_SOURCE: number = 2;
/**
 * 单本检查更新的时长上限。网络请求有自己的超时，但网页解析、书源脚本卡住时不会结束，那一路会一直占着、进度停住；
 * 超时就算这本失败，这一路丢掉旧引擎（它可能还卡在这本书上）换个新的接着查。
 */
const SHELF_REFRESH_BOOK_TIMEOUT_MS: number = 60000;
/** 单本查了这么久，封面圆钮显示秒数、清单里给出“跳过”。 */
const SHELF_REFRESH_STUCK_MS: number = 15000;
/** 最近一次检查更新失败的原因，封面显示红色“!”；下次检查成功或点开这本书时清除。 */
const SHELF_REFRESH_ERROR_VARIABLE: string = 'shelfRefreshError';
const SHELF_REFRESH_STUCK_COLOR: string = '#E6E08A00';
const SHELF_REFRESH_ERROR_COLOR: string = '#E5484D';
const SHELF_COVER_INITIAL_PREFETCH_COUNT: number = 16;
const SHELF_COVER_UPDATE_BATCH_MS: number = 48;
const SHELF_UPDATE_BADGE_VARIABLE: string = 'shelfHasUpdate';
const SHELF_SEARCH_INPUT_KEY: string = 'bookshelf_search_input';
/**
 * 分组开合：和隐私书架进出一样整页缩放、交叉淡入淡出。分组页是盖在书架上的独立一层，书架不拆；打开时书架放大到
 * ZOOM_LARGE 淡出，分组页从 ZOOM_SMALL 浮起；返回反过来。曲线与隐私书架相同。
 */
const SHELF_GROUP_ZOOM_IN_DURATION: number = 420;
const SHELF_GROUP_ZOOM_OUT_DURATION: number = 340;
const SHELF_GROUP_ZOOM_LARGE: number = 1.06;
const SHELF_GROUP_ZOOM_SMALL: number = 0.94;
/** 要浮起的那一层等待期间的透明度：不是 0，渲染服务在等待时就把它画好，开动第一帧不卡（0 时整层被跳过，第一帧要画 40ms）。 */
const SHELF_GROUP_PAGE_PREPARE_OPACITY: number = 0.01;
/**
 * 打开分组时等分组页这一屏封面解码完再浮起，最多等这么久（主题的大封面图后台解码要一两百毫秒）；
 * 分组页开头几十毫秒几乎透明，晚一点解码完的封面看不出来。
 */
const SHELF_GROUP_COVER_WAIT: number = 150;
/** 动画回调丢失（切到后台等）时的兜底收尾。 */
const SHELF_GROUP_MOTION_WATCHDOG: number = 2400;
/** 请系统按高刷跑，不然会先掉到 60Hz。 */
const SHELF_GROUP_FRAME_RATE: ExpectedFrameRateRange = { min: 60, max: 120, expected: 120 };
/** 隐私书架进出的时长；进入前先等一帧让隐私书架层建好。 */
const PRIVATE_SHELF_ENTER_DURATION: number = 420;
const PRIVATE_SHELF_EXIT_DURATION: number = 340;
const PRIVATE_SHELF_PREMOUNT_DELAY: number = 16;

/** 关书挪位时单独飞的平面封面：按 width/height 排版，只用缩放平移从 from 走到 to，由 tileGroupFlyProgress 驱动。 */
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
/** 与 Refresh.refreshOffset 一致：下拉超过这个距离松手才刷新。 */
const SHELF_REFRESH_TRIGGER_OFFSET: number = 64;
/** 翻书指示（书本 30 + 间距 4 + 一行说明）的高度，用于在露出的空隙里居中。 */
const SHELF_REFRESH_INDICATOR_HEIGHT: number = 50;
const SHELF_REFRESH_CAPSULE_HEIGHT: number = 32;
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

/** 检查更新时正在查的一本书，封面圆钮与胶囊清单按 startedAt 算已用时。 */
class ShelfRefreshActiveBook {
  book: Book;
  startedAt: number;

  constructor(book: Book, startedAt: number) {
    this.book = book;
    this.startedAt = startedAt;
  }
}

/** 本轮检查更新失败的一本书，胶囊清单里列出，点一行去换源。 */
class ShelfRefreshFailure {
  book: Book;
  reason: string;

  constructor(book: Book, reason: string) {
    this.book = book;
    this.reason = reason;
  }
}

/** 一本书的检查结果；abandoned 表示超时或被跳过，引擎可能还卡在这本书上。 */
class ShelfRefreshResult {
  updated: boolean;
  error: string;
  abandoned: boolean;

  constructor(updated: boolean, error: string, abandoned: boolean) {
    this.updated = updated;
    this.error = error;
    this.abandoned = abandoned;
  }
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
  /** 立体书舞台比封面高出的一截，留给书底的底板。斜靠以舞台底边中点为轴，算封面四角时要用同一个数。 */
  static readonly SHELF_HARDCOVER_STAGE_PAD: number = 4;
  static readonly SCOPE_TABS_HEIGHT: number = 44;
  static readonly SCOPE_TABS_PADDING: number = 6;
  static readonly SCOPE_TAB_INDICATOR_WIDTH: number = 18;
  /** 分类栏按书籍类型切换，没有书的类型不显示；隐私书架不在栏里，双击书架顶部进出。 */
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
  /** 动图开关切换或第一帧静图生成后递增，封面地址重新经过 AnimatedImagePolicy。 */
  @StorageProp('animatedImageRevision') animatedImageRevision: number = 0;
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
  /** 隐私书架单独一层盖在分类页上；进出时挂上/卸下，0 为普通书架，1 为隐私书架完全展开。 */
  @State privateShelfLayerMounted: boolean = false;
  @State privateShelfLayerProgress: number = 0;
  /** 进入动画走完后隐藏底下的分类页，退出动画开始前再显示。 */
  @State privateShelfLayerCovering: boolean = false;
  @StorageLink('bookshelfGroupBackRequest') @Watch('onTileGroupBackRequested') tileGroupBackRequest: number = 0;
  @StorageLink('bookshelfGroupTransitionActive') tileGroupAnimating: boolean = false;
  /** 是从书架上的分组文件夹点进来的：返回时缩回那个文件夹（tileGroupOriginX/Y），否则以屏幕中心缩放。 */
  @State tileGroupHasOrigin: boolean = false;
  private tileGroupOriginGroupId: number = 0;
  private tileGroupOriginViewportKey: string = '';
  private tileGroupOriginX: number = 0;
  private tileGroupOriginY: number = 0;
  /** 关书挪位时盖着的旧书架截图里那本书的封面先藏起来（只藏封面图）。 */
  @State tileGroupHiddenCovers: string[] = [];
  /** 关书挪位时单独飞的封面。 */
  @State tileGroupFlyers: TileGroupFlyer[] = [];
  @State tileGroupFlyProgress: number = 0;
  /**
   * 分组页那一层显示的分组（0 为没有这一层）。平铺布局的分组页盖在书架上，书架底层不拆、停在进入前的分组上：
   * 打开不用销毁书架，返回不用重建、滚回。返回动画结束后才卸下这一层。
   */
  @State tileGroupLayerGroupId: number = 0;
  /** 分组页那一层的分类页（键见 tileGroupPageKey），换分组或这一层卸下时清空。 */
  private tileGroupPages: Map<string, ShelfCategoryPage> = new Map();
  /** 书架底层显示的分组：进入分组页前所在的分组（0 或 -1）。 */
  private tileGroupBaseGroupId: number = 0;
  /** 分组页那一层的标题栏毛玻璃按它自己的滚动显现。 */
  @State tileGroupBackdropReveal: number = 0;
  /** 两层的缩放：分组页从 ZOOM_SMALL 浮起，书架从 ZOOM_LARGE 落回。 */
  @State tileGroupShelfScale: number = 1;
  @State tileGroupPageScale: number = 1;
  /** 缩放中心（相对书架根节点，vp）。 */
  @State tileGroupZoomX: number = 0;
  @State tileGroupZoomY: number = 0;
  /** 开合期间两层都不画底色和主题背景图（由 tileGroupBackgroundLayer 垫着）：缩放的只有内容，背景不动。 */
  @State tileGroupBareBody: boolean = false;
  /** 开合期间垫在最底下的页面背景（底色与主题背景图），书架或分组页淡出时露出的仍是同样的背景。 */
  @State tileGroupMotionBackground: boolean = false;
  /** 打开分组时为真：分组页挂上的本地封面登记进 tileGroupPendingCovers，后台解码完移出，都解码完分组页才浮起。 */
  private tileGroupAwaitCovers: boolean = false;
  private tileGroupPendingCovers: Set<string> = new Set();
  @State tileGroupShelfOpacity: number = 1;
  @State tileGroupPageOpacity: number = 1;
  @State shelfReorderCurtain: image.PixelMap | undefined = undefined;
  @State shelfReorderCurtainOpacity: number = 1;
  /** 关书回到书架到挪位动画结束；期间不在 loadBooks 里放掉按住的阅读时间。 */
  private shelfReturnMotionActive: boolean = false;
  private tileGroupPendingBack: boolean = false;
  /** 已开始但还没切过去的目标分组（-1 表示没有）；兜底收尾时直接切过去，不让点击落空。 */
  private tileGroupPendingTarget: number = -1;
  private tileGroupMotionGeneration: number = 0;
  private tileGroupMotionWatchdog: number = -1;
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
  private greetingEditorDialogSession: SystemDialogSession = new SystemDialogSession();
  private sectionTitleEditorDialogSession: SystemDialogSession = new SystemDialogSession();
  private tagDialogSession: SystemDialogSession = new SystemDialogSession();
  private customCoverDialogSession: SystemDialogSession = new SystemDialogSession();
  @State showAddBookGroupDialog: boolean = false;
  /** 新建分组弹窗是从“移动到分组”打开的：建好后把待移动的书移进去，不切换当前分组。 */
  private addBookGroupThenAssign: boolean = false;
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
  /** 长按菜单里“单独设置封面”是否展开了二级选项。 */
  @State bookActionCoverExpanded: boolean = false;
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
  @State shelfRefreshPrompt: string = '下拉检查更新';
  /** 下拉途中手指往回推时收起提示，再往下拉才重新显示。 */
  @State shelfRefreshPullRetracting: boolean = false;
  private shelfRefreshPullPeak: number = 0;
  private shelfRefreshPullTrough: number = 0;
  /** Refresh 当前下拉距离，驱动翻书指示的翻开程度。 */
  @State shelfRefreshPullOffset: number = 0;
  /**
   * 进度胶囊：松手后书架立刻弹回，检查在后台进行，进度显示在顶栏下方的胶囊里。
   * 胶囊跟标题行一起收起/展开；收起期间检查完成时结果先留着（summaryPending），等标题行完整展开再显示。
   */
  @State shelfRefreshCapsuleVisible: boolean = false;
  @State shelfRefreshCapsuleDone: boolean = false;
  /** 本轮要检查的书数与已检查数；总数为 0 表示只刷本地书，胶囊显示转圈。 */
  @State shelfRefreshTotal: number = 0;
  @State shelfRefreshChecked: number = 0;
  /** 完成或本地刷新时的胶囊文字；检查中由 total/checked 拼出。 */
  @State shelfRefreshCapsuleText: string = '';
  @State shelfRefreshCapsuleSubText: string = '';
  @State shelfRefreshCapsuleScale: number = 1;
  /** 胶囊内容实测宽度，沉浸材质底板只接受具体宽度。 */
  @State shelfRefreshCapsuleWidth: number = 0;
  private shelfRefreshSummaryPending: boolean = false;
  private shelfRefreshCapsuleTimer: number = -1;
  /** 正在查的书（最多 SHELF_REFRESH_CONCURRENCY 本），封面圆钮与胶囊清单都读它。 */
  @State shelfRefreshActive: ShelfRefreshActiveBook[] = [];
  /** 本轮失败的书，胶囊清单里列出。 */
  @State shelfRefreshFailures: ShelfRefreshFailure[] = [];
  /** 本轮失败、还没落库重载的书；封面“!”在检查进行中就能显示。 */
  @State shelfRefreshFailedUrls: string[] = [];
  /** 检查进行中每秒更新一次，只有封面圆钮和清单里的已用秒数读它。 */
  @State shelfRefreshNow: number = 0;
  @State shelfRefreshSheetVisible: boolean = false;
  private shelfRefreshTicker: number = -1;
  /** 正在查的书各自的放弃入口：超时与清单里的“跳过”都走这里。 */
  private shelfRefreshCancels: Map<string, (reason: string) => void> = new Map();
  @State editingTags: string[] = [];
  @State tagInput: string = '';
  @State shelfCoverMap: Map<string, string> = new Map();
  @State shelfCoverRenderVersions: Map<string, number> = new Map();
  private shelfCoverRawUrls: Map<string, string> = new Map();
  private shelfCoverCacheRevision: number = 0;
  private shelfCoverBookTasks: Set<string> = new Set();
  private pendingShelfCoverUpdates: Map<string, string> = new Map();
  private shelfCoverUpdateTimer: number = -1;
  /** 正在消散的书：卡片淡出、缩小、模糊，动画结束后才真正从列表里拿掉。 */
  @State shelfDissolvingUrls: string[] = [];
  @State shelfDissolveBursts: DeleteParticleBurst[] = [];
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
  /** 书架设置“错落摆放”：关闭后陪伴网格里的书一样大、全部立正。 */
  @StorageLink('bookshelfCompanionStagger') @Watch('onCompanionStaggerChanged')
  bookshelfCompanionStagger: boolean = true;
  /** 书架设置“阅读小记”：关闭后陪伴布局不显示阅读小记卡片。 */
  @StorageLink('bookshelfCompanionReadingNote') bookshelfCompanionReadingNote: boolean = true;
  /** 陪伴布局左上角问候语：time 内置按时段，custom 用户自写两行（可含占位符），off 不显示。 */
  @StorageLink('bookshelfGreetingMode') bookshelfGreetingMode: string = 'time';
  @StorageLink('bookshelfGreetingTitle') bookshelfGreetingTitle: string = '';
  @StorageLink('bookshelfGreetingSubtitle') bookshelfGreetingSubtitle: string = '';
  @StorageLink('bookshelfCompanionSectionTitle') bookshelfCompanionSectionTitle: string = '';
  @StorageProp('accountDisplayName') accountDisplayName: string = '';
  /** 阅读小记读出的今日时长，问候语 {今日阅读} 直接用。 */
  @StorageProp('shelfTodayReadMs') shelfTodayReadMs: number = 0;
  @StorageLink('bookshelfCoverAlbums') @Watch('onShelfCoverSettingsChanged') bookshelfCoverAlbums: string = '';
  @StorageLink('bookshelfLightCoverAlbumId') @Watch('onShelfCoverSettingsChanged') bookshelfLightCoverAlbumId: string = '';
  @StorageLink('bookshelfDarkCoverAlbumId') @Watch('onShelfCoverSettingsChanged') bookshelfDarkCoverAlbumId: string = '';
  @StorageLink('bookshelfCoverApplyScope') @Watch('onShelfCoverSettingsChanged') bookshelfCoverApplyScope: string = 'all';
  @StorageLink('bookshelfCoverTargetBooks') @Watch('onShelfCoverSettingsChanged') bookshelfCoverTargetBooks: string = '';
  @StorageLink('bookshelfIgnoreSourceCover') @Watch('onShelfCoverSettingsChanged') bookshelfIgnoreSourceCover: boolean = false;
  @StorageLink('bookshelfIgnoreEmptyCoverOnly') @Watch('onShelfCoverSettingsChanged') bookshelfIgnoreEmptyCoverOnly: boolean = false;
  @StorageLink('bookshelfCoverMode') @Watch('onShelfCoverSettingsChanged') bookshelfCoverMode: string = 'sequence';
  @StorageProp('bookshelfDarkCoverDim') bookshelfDarkCoverDim: boolean = false;
  @StorageProp('bookshelfDarkCoverDimLevel') bookshelfDarkCoverDimLevel: number = 20;
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
  private privateShelfLayerTimer: number = -1;
  private privateShelfLayerGeneration: number = 0;
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
    this.stopShelfRefreshTicker();
    ShelfCoverLocator.unregister(this.shelfCoverLocate);
    this.discardShelfOpeningBackdrop();
    this.cancelTileGroupMotion();
    this.stopShelfCategoryAnimation();
    this.cloudBookOpenRequest++;
    this.cancelShelfBookOpening();
    this.cancelNetworkCoverSearch();
    this.clearShelfScopeTransition();
    this.clearPrivateShelfLayerTimer();
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
    // 平铺布局进出分组页时书架底层的分组不变：不作废书架的分类页，不然书架整屏重建，正是开合要省掉的。
    const tileGroupMove = this.isTileLayout() && (this.activeShelfGroupId > 0 || this.tileGroupLayerGroupId > 0);
    this.syncTileGroupLayer();
    this.applyShelfScope(!tileGroupMove);
    // A group switch changes the visible snapshot while the shelf's LazyForEach data sources
    // are retained.  Replacing them here (and forcing a reload) prevents a retained list/grid
    // from continuing to render the books from the previous group.
    this.reloadShelfDataSources(true, !tileGroupMove);
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
      this.bookshelfCompanionStagger = settings.companionStagger;
      this.bookshelfCompanionReadingNote = settings.companionReadingNote;
      this.bookshelfGreetingMode = settings.greetingMode;
      this.bookshelfGreetingTitle = settings.greetingTitle;
      this.bookshelfGreetingSubtitle = settings.greetingSubtitle;
      this.bookshelfCompanionSectionTitle = settings.companionSectionTitle;
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

  // 书的高矮、斜靠和分组叠法都跟着开关变；渲染键带上开关值，重建数据源让已有的书和分组按新样式重画。
  onCompanionStaggerChanged(): void {
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

  reloadShelfDataSources(force: boolean = false, invalidatePages: boolean = true): void {
    if (invalidatePages) this.shelfCategoryRevision++;
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
    // 书架设置“自动获取更新”关闭时跳过（只在网页解析开启时显示，关闭网页解析时在线书本就不在书架上）。
    setTimeout(async () => {
      try {
        const settings = await BookshelfDisplaySettingsStore.load(getContext(this));
        if (!settings.autoRefresh) {
          console.info('[ShelfRefresh] cold-start silent refresh skipped: auto refresh off');
          return;
        }
      } catch (e) {
        console.warn('[ShelfRefresh] read auto refresh setting failed:', e);
      }
      console.info('[ShelfRefresh] cold-start silent refresh started');
      this.refreshBookshelfToc(true).then(() => {
        console.info('[ShelfRefresh] cold-start silent refresh finished');
      }).catch((e: Error) => {
        console.error('[ShelfRefresh] cold-start silent refresh failed:', e);
      });
    }, 600);
  }

  async deleteBook(book: Book) {
    // 消散动画与删库同时进行；封面缓存等动画播完再清，否则封面会先变回占位图。
    const dissolve = this.dissolveShelfBooks([book]);
    try {
      const db = AppDatabase.getInstance();
      CloudAutoSync.onBookRemoved(getContext(this), book).catch(() => undefined);
      LocalBookService.deleteLocalBookFiles(getContext(this), book);
      await db.deleteBook(book.bookUrl, 'bookshelf_user_delete');
      await dissolve;
      this.commitShelfBookRemoval([book.bookUrl]);
      this.deleteBookCoverCache(book);
      HdsFeedback.showToast(`已删除《${book.name}》`);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      await this.loadBooks();
    } catch (e) {
      console.error('删除书籍失败:', e);
      this.shelfDissolvingUrls = this.shelfDissolvingUrls.filter((url: string) => url !== book.bookUrl);
      HdsFeedback.showToast('删除失败');
    }
  }

  isShelfBookDissolving(bookUrl: string): boolean {
    return this.shelfDissolvingUrls.length > 0 && this.shelfDissolvingUrls.indexOf(bookUrl) >= 0;
  }

  shelfDissolveScale(bookUrl: string): number {
    return this.isShelfBookDissolving(bookUrl) ? 0.9 : 1;
  }

  shelfCardElementId(book: Book, scope: string): string {
    return `shelf_book_card_${scope}${encodeURIComponent(book.bookUrl)}`;
  }

  /**
   * 当前分类页上这本书看得见的那张卡片（相对书架根节点，vp）。先找继续阅读卡片里的封面，再找格子或列表行；
   * 滚出屏幕、只在相邻分类页里的不算，这些书不播粒子，直接随列表一起删掉。
   */
  locateShelfDissolveTarget(book: Book, pageKey: string): DeleteParticleBurst | undefined {
    const viewportWidth = this.contextViewportWidth;
    const viewportHeight = this.contextViewportHeight;
    for (const latest of [true, false]) {
      const scope = this.shelfCoverScope(pageKey, latest);
      const coverId = this.shelfCoverElementId(book, scope);
      const bounds = (latest ? undefined : this.measureTileGroupRect(this.shelfCardElementId(book, scope))) ||
        this.measureTileGroupRect(coverId);
      if (!bounds || bounds.width < 4 || bounds.height < 4) continue;
      if (viewportWidth > 0 && (bounds.x + bounds.width <= 0 || bounds.x >= viewportWidth)) continue;
      if (viewportHeight > 0 && (bounds.y + bounds.height <= 0 || bounds.y >= viewportHeight)) continue;
      const burst = new DeleteParticleBurst();
      burst.x = bounds.x;
      burst.y = bounds.y;
      burst.width = bounds.width;
      burst.height = bounds.height;
      burst.coverId = coverId;
      return burst;
    }
    return undefined;
  }

  /** 让这些书的卡片散成颗粒，等卡片淡出完再返回；看不见的书不等。 */
  async dissolveShelfBooks(books: Book[]): Promise<void> {
    if (books.length === 0) return;
    const pageKey = this.shelfPageKey();
    const targets: DeleteParticleBurst[] = [];
    for (const book of books) {
      if (targets.length >= 16) break;
      const target = this.locateShelfDissolveTarget(book, pageKey);
      if (target) targets.push(target);
    }
    const urls = books.map((book: Book) => book.bookUrl);
    if (targets.length === 0) {
      this.shelfDissolvingUrls = [...this.shelfDissolvingUrls, ...urls];
      return;
    }
    const ui = this.getUIContext();
    const fallback = this.appDarkMode ? ['#C8CCD2', '#8A9099', '#5F6670'] : ['#5F6670', '#9AA0A6', '#C4C8CE'];
    const colors = await Promise.all(targets.map((target: DeleteParticleBurst) =>
      DeleteParticles.pickColors(ui, target.coverId, fallback)));
    const ids: number[] = [];
    targets.forEach((target: DeleteParticleBurst, index: number) => {
      target.id = DeleteParticles.newId();
      target.colors = colors[index];
      target.count = DeleteParticles.particleCount(target.width, target.height, targets.length);
      ids.push(target.id);
    });
    this.shelfDissolveBursts = [...this.shelfDissolveBursts, ...targets];
    this.getUIContext().animateTo({ duration: DeleteParticles.FADE_MS, curve: Curve.EaseIn }, () => {
      this.shelfDissolvingUrls = [...this.shelfDissolvingUrls, ...urls];
    });
    setTimeout(() => {
      this.shelfDissolveBursts = this.shelfDissolveBursts.filter((burst: DeleteParticleBurst) => ids.indexOf(burst.id) < 0);
    }, DeleteParticles.LAYER_MS);
    await sleepMs(DeleteParticles.FADE_MS);
  }

  /** 消散完的书先从内存里拿掉并让其余卡片补位，库里的最新数据随后由 loadBooks 补齐。 */
  commitShelfBookRemoval(urls: string[]): void {
    this.getUIContext().animateTo({ duration: 320, curve: Curve.FastOutSlowIn }, () => {
      this.allBooks = this.allBooks.filter((book: Book) => urls.indexOf(book.bookUrl) < 0);
      this.applyShelfScope();
      this.reloadShelfDataSources();
    });
    // 被拿掉的格子在补位动画里还会播一段系统默认的消失转场，期间节点仍在画；消散状态要等这段结束再清，
    // 否则透明度先回到 1，已经散掉的封面会重新露出来再淡出。
    setTimeout(() => {
      this.shelfDissolvingUrls = this.shelfDissolvingUrls.filter((url: string) => urls.indexOf(url) < 0);
    }, 600);
  }

  showDeleteConfirm(book: Book) {
    this.pendingDeleteBook = book;
    this.openDeleteBookDialog();
  }

  showBookActions(book: Book, event?: GestureEvent): void {
    this.captureContextMenuAnchor(event);
    this.pendingActionBook = book;
    this.bookActionCoverExpanded = false;
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
    this.bookActionCoverExpanded = false;
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
      HdsFeedback.showToast('当前书籍不支持换规则');
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
    this.networkCoverStatus = '正在从启用的规则中搜索...';
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
      const previousCover = current.customCoverUrl;
      current.customCoverUrl = coverUrl;
      await db.updateBook(current);
      this.removeLocalBookCoverFile(previousCover, coverUrl);
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
      const previousCover = current.customCoverUrl;
      current.customCoverUrl = '';
      await db.updateBook(current);
      this.removeLocalBookCoverFile(previousCover, '');
      this.applyShelfBookCoverState(current);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('已恢复默认封面');
    } catch (e) {
      console.error('恢复默认封面失败:', e);
      HdsFeedback.showToast('恢复默认封面失败');
    }
  }

  /** 上传本地图片作封面：复制进沙箱后写入 customCoverUrl，与网络封面同一优先级。 */
  async pickLocalBookCover(book: Book): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['图片|.jpg,.jpeg,.png,.webp,.gif,.bmp,.heic,.heif'];
      const result = await new picker.DocumentViewPicker(getContext(this)).select(options);
      if (!result || result.length === 0 || !result[0]) return;
      const source = result[0];
      // 动图原样复制、书架上照常播放；太大的拒收，免得一屏解码拖慢书架。
      const oversize = await AnimatedImagePolicy.oversizeAnimatedMessage(source);
      if (oversize) {
        HdsFeedback.showToast(oversize);
        return;
      }
      const db = AppDatabase.getInstance();
      const current = await db.getBook(book.bookUrl);
      if (!current) {
        HdsFeedback.showToast('书籍已不在书架中');
        return;
      }
      const dir = this.localBookCoverDir();
      if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
      const match = /\.(jpe?g|png|webp|gif|bmp|heic|heif)$/i.exec(decodeURIComponent(source));
      const ext = match ? `.${match[1].toLowerCase()}` : '.jpg';
      const destUri = fileUri.getUriFromPath(`${dir}/${Date.now()}${ext}`);
      await fs.copy(source, destUri);
      const previousCover = current.customCoverUrl;
      current.customCoverUrl = destUri;
      await db.updateBook(current);
      this.removeLocalBookCoverFile(previousCover, destUri);
      this.applyShelfBookCoverState(current);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('本地封面已启用');
    } catch (e) {
      console.error('设置本地封面失败:', e);
      HdsFeedback.showToast('设置本地封面失败');
    }
  }

  localBookCoverDir(): string {
    return `${getContext(this).filesDir}/book_covers`;
  }

  /** 换掉或恢复封面后，删掉不再使用的本地上传封面文件。 */
  removeLocalBookCoverFile(previous: string, next: string): void {
    const prefix = `${fileUri.getUriFromPath(this.localBookCoverDir())}/`;
    if (!previous || previous === next || !previous.startsWith(prefix)) return;
    try {
      fs.unlinkSync(new fileUri.FileUri(previous).path);
    } catch (e) {
      console.warn('删除旧本地封面失败:', e);
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
    // the retained card keeps rendering the old percentage until the whole bookshelf is recreated. Name and author
    // are part of the key for the same reason: editing a local book's info would otherwise leave the old card.
    const progressChapterIndex = book.getVariable('readProgressChapterIndex');
    const progressPageCount = book.getVariable('readProgressPageCount');
    return `${prefix}_${book.bookUrl}_pin_${book.isPinned ? '1' : '0'}_name_${book.name}_${book.author}_` +
      `read_${book.durChapterTime}_${book.durChapterIndex}_${book.durChapterPos}_` +
      `${book.totalChapterNum}_${book.getVariable('readStarted')}_` +
      `badges_${book.getVariable('shelfHasUpdate')}_${book.origin}_${book.originName}_` +
      `${progressChapterIndex}_${progressPageCount}_cover_${this.shelfCoverRenderVersions.get(book.bookUrl) || 0}_` +
      `stagger_${this.bookshelfCompanionStagger ? '1' : '0'}`;
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
      const previousCover = current.customCoverUrl;
      current.customCoverUrl = coverUrl;
      await db.updateBook(current);
      this.removeLocalBookCoverFile(previousCover, coverUrl);
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
      this.bookshelfCoverMode,
      this.bookshelfIgnoreEmptyCoverOnly
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
  @State @Watch('onShelfHeaderCollapseChanged') shelfHeaderCollapse: number = 0;
  // 顶栏毛玻璃按列表实际滚动距离显现，见 CollapsingHeader.backdropReveal。
  @State shelfHeaderBackdropReveal: number = 0;
  onHeaderCollapseChange: (progress: number) => void = () => {};
  private shelfListScroller: ListScroller = new ListScroller();
  private shelfTileScroller: Scroller = new Scroller();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.tileGroupMotionBackground) {
        this.tileGroupBackgroundLayer()
      }
      // 书架一直在底下，分组页打开后藏起来（不排版、不拆）；分组页另成一层盖在上面。
      Stack() {
        this.shelfPageBody()
      }
      .width('100%')
      .height('100%')
      .scale({ x: this.tileGroupShelfScale, y: this.tileGroupShelfScale,
        centerX: this.tileGroupZoomX, centerY: this.tileGroupZoomY })
      .opacity(this.tileGroupShelfOpacity)
      // 开合时整层画成一张再缩放淡出：两整层带阴影的书一起半透明缩放，渲染服务每帧重画两层要 25–50ms。
      .renderGroup(this.tileGroupAnimating)
      .visibility(this.isTileGroupPage() && !this.tileGroupAnimating ? Visibility.None : Visibility.Visible)
      .hitTestBehavior(this.isTileGroupPage() ? HitTestMode.None : HitTestMode.Default)
      // 在分组页里切到列表布局时分组变成书架的筛选，这一层不再显示。
      if (this.tileGroupLayerGroupId > 0 && this.isTileLayout()) {
        Stack() {
          this.tileGroupPageBody()
        }
        .width('100%')
        .height('100%')
        .scale({ x: this.tileGroupPageScale, y: this.tileGroupPageScale,
          centerX: this.tileGroupZoomX, centerY: this.tileGroupZoomY })
        .opacity(this.tileGroupPageOpacity)
        .renderGroup(this.tileGroupAnimating)
        .hitTestBehavior(this.isTileGroupPage() ? HitTestMode.Default : HitTestMode.None)
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
      if (this.shelfDissolveBursts.length > 0) {
        DeleteParticleLayer({ bursts: this.shelfDissolveBursts })
      }

      if (this.books.length > 0 && this.shouldShowShelfRefreshStatus()) {
        this.shelfRefreshPullIndicator()
      }
      if (this.shelfRefreshCapsuleVisible) {
        this.shelfRefreshCapsule()
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

      Column()
        .width(1)
        .height(1)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
        .bindSheet(this.showBookGroupPicker, this.bookGroupPickerDialog(), this.bookGroupPickerSheetOptions())

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
      // 分组开合期间由 tileGroupBackgroundLayer 垫着，这里不画。
      if (!this.tileGroupBareBody) {
        HomeThemeBackdrop()
          .position({ x: 0, y: 0 })
      }

      Column() {
      // 列表上滑时标题行收起：外层按收起量变矮并裁剪，标题行贴底上移并淡出。
      Stack({ alignContent: Alignment.Bottom }) {
        Row() {
          if (this.isBookMultiSelect) {
            Text('书架')
              .fontSize(AppFontSize.DISPLAY)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
          } else if (!this.isCompanionLayout()) {
            this.shelfGroupSwitcher()
          } else if (this.shelfBaseGroupId() === -1) {
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
            this.shelfMoreButton(false)
          }
        }
        .width('100%')
        .height(56 + this.statusBarHeight)
        .padding({
          left: AppSpacing.XL,
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
        // 隐私书架期间分类页停在原来的类型上，退出时直接露出来。
        CategorySwipePager({
          pageKeys: this.shelfPageOrder(),
          selectedIndex: Math.max(0, this.shelfPageOrder().indexOf(this.activeShelfTypeTab())),
          swipeEnabled: !this.isBookMultiSelect && this.shelfScope !== 'private',
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
        .scale({
          x: this.shelfScopeTransitionScale * this.privateShelfOuterScale(),
          y: this.shelfScopeTransitionScale * this.privateShelfOuterScale()
        })
        .opacity(this.shelfScopeTransitionOpacity * (1 - this.privateShelfLayerProgress))
        .visibility(this.privateShelfLayerCovering ? Visibility.Hidden : Visibility.Visible)
        .hitTestBehavior(this.shelfScope === 'private' ? HitTestMode.None : HitTestMode.Default)

        if (this.privateShelfLayerMounted) {
          // 外层是 Column：不脱离排版的话会排在分类页下面、整层落在屏幕外。
          Column() {
            this.shelfCategoryContent('private')
          }
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .clip(true)
          .scale({ x: this.privateShelfInnerScale(), y: this.privateShelfInnerScale() })
          .opacity(this.privateShelfLayerProgress)
          .hitTestBehavior(this.shelfScope === 'private' ? HitTestMode.Default : HitTestMode.None)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tileGroupBareBody ? Color.Transparent : this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onTouch((event: TouchEvent) => this.onShelfBodyTouch(event))
    // 开合期间的背景由 tileGroupBackgroundLayer 负责。
  }

  onShelfBodyTouch(event: TouchEvent): void {
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
  }

  /** 分组页那一层：返回键、分组名、本数和更多按钮，下面是这个分组的书（标题栏不随滚动收起）。 */
  @Builder
  tileGroupPageBody() {
    Column() {
      if (!this.tileGroupBareBody) {
        HomeThemeBackdrop()
          .position({ x: 0, y: 0 })
      }

      Column() {
        Row() {
          if (this.isBookMultiSelect) {
            Text('书架')
              .fontSize(AppFontSize.DISPLAY)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
            Blank()
            ImmersiveHeaderAction({
              label: '取消',
              accessibilityLabel: '退出多选',
              onTap: () => this.exitBookMultiSelect()
            })
          } else {
            ImmersiveBackButton({
              iconColor: this.primaryTextColor(),
              darkMode: this.appDarkMode,
              buttonSize: 40,
              containerWidth: 56,
              materialScale: 0.83,
              compactLayout: true,
              onBack: () => this.exitTileGroupPage()
            })
            Text(this.tileGroupLayerName())
              .fontSize(AppFontSize.TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Blank()
            // 按这一层自己的书数：返回时当前分组已切回书架，this.books 不再是这个分组的书。
            Text(this.shelfBooksForPage(this.tileGroupLayerKey()).length > 0 ?
              `${this.shelfBooksForPage(this.tileGroupLayerKey()).length}本` : '')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .margin({ right: AppSpacing.MD })
            this.shelfMoreButton(true)
          }
        }
        .width('100%')
        .height(56 + this.statusBarHeight)
        .padding({ left: this.isBookMultiSelect ? AppSpacing.XL : 0, right: AppSpacing.XL, top: this.statusBarHeight })
        .alignItems(VerticalAlign.Center)

        if (this.isBookMultiSelect) {
          this.bookSelectionStatusBar()
        }
      }
      .width('100%')
      .position({ x: 0, y: 0 })
      .zIndex(5)

      HeaderBackdrop({ backdropHeight: this.statusBarHeight + 56,
        statusBarHeight: this.statusBarHeight,
        backdropColor: ThemeRuntime.topBarColor(this.appDarkMode),
        reveal: ThemeRuntime.homeBackdrop(this.appDarkMode) ? this.tileGroupBackdropReveal : 1 })
        .width('100%')
        .position({ x: 0, y: 0 })
        .zIndex(3)

      Column() {
        this.shelfCategoryContent(this.tileGroupLayerKey())
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tileGroupBareBody ? Color.Transparent : this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onTouch((event: TouchEvent) => this.onShelfBodyTouch(event))
  }

  /** 和分组页一样的底色与主题背景图：书架或分组页整页淡出时，背景留在原处不跟着淡。 */
  @Builder
  tileGroupBackgroundLayer() {
    Column() {
      HomeThemeBackdrop()
        .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  tileGroupFlyerLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.tileGroupFlyers, (flyer: TileGroupFlyer) => {
        Stack() {
          if (flyer.cover && flyer.fill && this.themeImageCrop(ThemeImageSlots.COVER, flyer.cover)) {
            ThemeCroppedImage({ src: flyer.cover,
              crop: this.themeImageCrop(ThemeImageSlots.COVER, flyer.cover) as ThemeImageCrop,
              syncLoad: this.coverSyncLoadable(flyer.cover) })
              .width('100%')
              .height('100%')
          } else if (flyer.cover) {
            Image(flyer.cover)
              .width('100%')
              .height('100%')
              .objectFit(flyer.fill ? ImageFit.Fill : ImageFit.Cover)
              .syncLoad(this.coverSyncLoadable(flyer.cover))
              .draggable(false)
          } else {
            Text(flyer.initial)
              .fontSize(28)
              .fontColor('#FFFFFF')
          }
          if (!flyer.fill && this.shelfCoverDimOpacity() > 0) {
            this.shelfCoverDimLayer()
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
      warnTag: '显示换规则弹窗失败:'
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
          .padding({ top: this.bookshelfTopOverlayHeight(pageKey) })
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.isShelfRefreshing, builder: this.shelfRefreshBuilder }) {
            if (this.isTileLayout()) {
              this.shelfTileGrid(pageKey)
            } else {
              List({ scroller: this.shelfListScrollerForPage(pageKey), space: AppSpacing.MD }) {
              ListItem() {
                Row()
                  .height(this.bookshelfTopOverlayHeight(pageKey))
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
                  .id(this.shelfCardElementId(book, this.shelfCoverScope(pageKey, false)))
                  .opacity(this.isShelfBookDissolving(book.bookUrl) ? 0 : 1)
                  .scale({ x: this.isShelfBookDissolving(book.bookUrl) ? 0.96 : 1,
                    y: this.isShelfBookDissolving(book.bookUrl) ? 0.96 : 1 })
                  .blur(this.isShelfBookDissolving(book.bookUrl) ? 16 : 0)
                  .hitTestBehavior(this.isShelfBookDissolving(book.bookUrl) ? HitTestMode.None : HitTestMode.Default)
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
          .refreshOffset(SHELF_REFRESH_TRIGGER_OFFSET)
          .onStateChange((state: RefreshStatus) => {
            if (pageKey === this.shelfPageKey()) this.updateShelfRefreshPrompt(state);
          })
          .onOffsetChange((offset: number) => {
            if (pageKey !== this.shelfPageKey()) return;
            this.shelfRefreshPullOffset = offset;
            this.trackShelfRefreshPullOffset(offset);
          })
          .onRefreshing(() => {
            if (pageKey === this.shelfPageKey()) this.onShelfPullRefresh();
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
      this.shelfHeaderCircleButton($r('sys.symbol.folder'), this.showShelfGroupMenu || this.shelfBaseGroupId() !== 0,
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

  /** 分组下拉菜单里置顶分组排在前面，其余保持原有顺序。 */
  shelfGroupsPinnedFirst(): BookGroup[] {
    const pinned = this.shelfGroups.filter((group: BookGroup): boolean => group.pinned === true);
    if (pinned.length === 0) return this.shelfGroups;
    return pinned.concat(this.shelfGroups.filter((group: BookGroup): boolean => group.pinned !== true));
  }

  /** 书架标题栏上的分组名（书架底层那一层所在的分组）。 */
  shelfGroupTitle(): string {
    const groupId = this.shelfBaseGroupId();
    if (groupId === 0) {
      return '书架';
    }
    if (groupId === -1) {
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
          ForEach(this.shelfGroupsPinnedFirst(), (group: BookGroup) => {
            this.shelfGroupMenuItem(group.groupName, group.groupId, group)
          }, (group: BookGroup) => `${group.groupId}_${group.groupName}_${group.pinned ? '1' : '0'}`)
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
        Text('长按分组可置顶、重命名或删除')
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
      if (group?.pinned) {
        SymbolGlyph($r('sys.symbol.pin'))
          .fontSize(13)
          .fontColor([this.secondaryTextColor()])
          .accessibilityText('已置顶')
      }
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
          if (this.hasShelfRefreshError(this.pendingActionBook) && !LocalBookService.isLocalBook(this.pendingActionBook)) {
            this.contextActionItem($r('sys.symbol.exclamationmark_circle'),
              `检查失败：${this.shelfRefreshErrorReason(this.pendingActionBook)}，去换规则`, SHELF_REFRESH_ERROR_COLOR, () => {
                if (this.pendingActionBook) {
                  const book = this.pendingActionBook;
                  this.closeBookActions();
                  this.openShelfChangeSource(book);
                }
              })
          }
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
            this.contextActionItem($r('sys.symbol.arrow_left_arrow_right'), '换规则', this.primaryTextColor(), () => {
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
          PopupMenuAction($r('sys.symbol.picture'), '单独设置封面', this.primaryTextColor(), () => {
            this.bookActionCoverExpanded = !this.bookActionCoverExpanded;
          }, true, this.bookActionCoverExpanded ? '▾' : '▸', this.subTextColor())
          if (this.bookActionCoverExpanded) {
            Column() {
              this.contextActionItem($r('sys.symbol.picture_badge_arrow_down'), '获取网络封面', this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  const book = this.pendingActionBook;
                  this.closeBookActions();
                  this.openNetworkCoverPicker(book);
                }
              })
              this.contextActionItem($r('sys.symbol.picture_badge_arrowshape_turn_right_up'), '上传本地图片', this.primaryTextColor(), () => {
                if (this.pendingActionBook) {
                  const book = this.pendingActionBook;
                  this.closeBookActions();
                  setTimeout(() => {
                    this.pickLocalBookCover(book);
                  }, 0);
                }
              })
            }
            .width('100%')
            .padding({ left: 16 })
          }
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
                Text(candidate.originName || candidate.author || '启用规则')
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
          .backgroundColor(this.glassCardColor())
          .accessibilityText('新建分组并移入')
          .onClick(() => {
            // 只收起弹层、不走 closeBookGroupPicker，单本移动的目标书还要留给新分组用。
            this.showBookGroupPicker = false;
            this.openAddBookGroupDialog(true);
          })
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
      Text(this.addBookGroupThenAssign ? '新建分组并移入' : '新增书籍分组').fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      TextInput({ placeholder: '输入分组名称', text: this.newBookGroupName })
        .width('100%').height(42).backgroundColor(this.inputColor()).fontColor(this.primaryTextColor())
        .borderRadius(ThemeRuntime.mediumRadius()).onChange((value: string) => this.newBookGroupName = value)
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.glassCardColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.closeAddBookGroupDialog())
        Button(this.addBookGroupThenAssign ? '新建并移入' : '新增', { type: ButtonType.Normal }).layoutWeight(1).height(42).borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.buttonColor()).fontColor(ThemeRuntime.onAccentColor()).enabled(!!this.newBookGroupName.trim())
          .onClick(() => this.addShelfBookGroup())
      }.width('100%')
    }    .padding(22)
  }

  openAddBookGroupDialog(thenAssign: boolean = false): void {
    this.addBookGroupThenAssign = thenAssign;
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
    if (this.addBookGroupThenAssign) {
      this.addBookGroupThenAssign = false;
      this.groupPickerSingleBookUrl = '';
    }
    this.showAddBookGroupDialog = false;
    this.addBookGroupDialogSession.close(this.getUIContext());
  }


  @Builder
  bookGroupActionMenu() {
    Scroll() {
      Column() {
        this.contextActionItem($r('sys.symbol.pin'), this.pendingBookGroup?.pinned ? '取消置顶' : '置顶',
          this.primaryTextColor(), () => {
            const group = this.pendingBookGroup;
            this.showBookGroupActionMenu = false;
            if (group) this.toggleBookGroupPinned(group);
          })
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
   * 点分组卡片打开分组页：和隐私书架进出一样整页缩放、交叉淡入淡出，缩放中心是点的这个文件夹。
   */
  openTileGroupPage(groupId: number, pageKey: string, touchX: number, touchY: number): void {
    if (this.tileGroupAnimating || this.consumeShelfSwipeClick()) return;
    this.showShelfGroupMenu = false;
    this.showShelfMoreMenu = false;
    this.showShelfFilterMenu = false;
    const generation = this.beginTileGroupMotion(groupId);
    const folder = this.measureTileGroupRect(this.tileGroupElementId(groupId, pageKey));
    this.tileGroupHasOrigin = folder !== undefined;
    this.tileGroupOriginGroupId = groupId;
    this.tileGroupOriginViewportKey = this.tileGroupViewportKey();
    if (folder) {
      this.tileGroupOriginX = folder.x + folder.width / 2;
      this.tileGroupOriginY = folder.y + folder.height / 2;
    }
    this.zoomTileGroup(groupId, generation, folder !== undefined);
  }

  /** 返回书架：缩回进来时那个文件夹；窗口变了、分组没了或是从菜单进来的，以屏幕中心缩放。 */
  leaveTileGroupPage(): void {
    const target = this.tileGroupBaseGroupId;
    const generation = this.beginTileGroupMotion(target);
    const toFolder = this.tileGroupHasOrigin && this.activeShelfGroupId === this.tileGroupOriginGroupId &&
      this.tileGroupOriginViewportKey === this.tileGroupViewportKey() &&
      this.shelfGroups.some((group: BookGroup): boolean => group.groupId === this.tileGroupOriginGroupId);
    this.zoomTileGroup(target, generation, toFolder);
  }

  /**
   * 从分组菜单等处切换分组：书架打开某个分组时以屏幕中心缩放；分组页里回到书架时若有来处就缩回那个文件夹；
   * 书架底层换个分组（全部 / 未分组）或分组页换个分组时不用开合，直接换。
   */
  changeTileGroup(groupId: number): void {
    if (groupId > 0 && !this.isTileGroupPage()) {
      this.tileGroupHasOrigin = false;
      this.zoomTileGroup(groupId, this.beginTileGroupMotion(groupId), false);
    } else if (groupId <= 0 && this.isTileGroupPage()) {
      this.leaveTileGroupPage();
    } else {
      this.applyTileGroupTarget(groupId);
    }
  }

  /**
   * 开合：两层都撤掉底色和主题背景图（由 tileGroupBackgroundLayer 垫着），缩放的只有内容。打开时在书架上面建分组页
   * （透明、停在起点），等这一屏封面解码完；返回时把藏着的书架显出来（只排版、不重建），等它画出来。然后两层一口气走完。
   * 建页时主线程堵着、动画也画不出帧（真机实测整段冻住），所以动画不提前开始。
   */
  zoomTileGroup(groupId: number, generation: number, fromFolder: boolean): void {
    const entering = groupId > 0;
    this.tileGroupZoomX = fromFolder ? this.tileGroupOriginX : this.contextViewportWidth / 2;
    this.tileGroupZoomY = fromFolder ? this.tileGroupOriginY : this.contextViewportHeight / 2;
    this.tileGroupMotionBackground = true;
    this.tileGroupBareBody = true;
    const run = (): void => {
      this.getUIContext().animateTo({
        duration: entering ? SHELF_GROUP_ZOOM_IN_DURATION : SHELF_GROUP_ZOOM_OUT_DURATION,
        curve: curves.cubicBezierCurve(0.2, 0, 0, 1), expectedFrameRateRange: SHELF_GROUP_FRAME_RATE,
        onFinish: (): void => this.finishTileGroupMotion(generation)
      }, (): void => {
        this.tileGroupShelfScale = entering ? SHELF_GROUP_ZOOM_LARGE : 1;
        this.tileGroupShelfOpacity = entering ? 0 : 1;
        this.tileGroupPageScale = entering ? 1 : SHELF_GROUP_ZOOM_SMALL;
        this.tileGroupPageOpacity = entering ? 1 : 0;
      });
    };
    if (entering) {
      this.tileGroupPageScale = SHELF_GROUP_ZOOM_SMALL;
      this.tileGroupPageOpacity = SHELF_GROUP_PAGE_PREPARE_OPACITY;
      this.beginTileGroupCoverWait(groupId);
      this.applyTileGroupTarget(groupId);
      this.afterTileGroupCoversReady(generation, run);
    } else {
      this.tileGroupShelfScale = SHELF_GROUP_ZOOM_LARGE;
      this.tileGroupShelfOpacity = SHELF_GROUP_PAGE_PREPARE_OPACITY;
      this.applyTileGroupTarget(groupId);
      this.afterTileGroupFrames(generation, 2, run);
    }
  }

  /**
   * 打开分组：封面换成磁盘缓存后在后台解码，分组页建好后等这一屏都解码完再开始动画。同步解码一屏要在主线程上
   * 堵几百毫秒。
   */
  beginTileGroupCoverWait(groupId: number): void {
    this.warmTileGroupCovers(groupId);
    this.tileGroupPendingCovers.clear();
    this.tileGroupAwaitCovers = true;
  }

  /** 分组页挂上的封面（见 coverView）都解码完、再等一帧画出来后执行；没缓存的网络封面不等，最多等 SHELF_GROUP_COVER_WAIT。 */
  afterTileGroupCoversReady(generation: number, run: () => void, maxWait: number = SHELF_GROUP_COVER_WAIT): void {
    const deadline = Date.now() + maxWait;
    const check = (): void => {
      if (this.tileGroupPendingCovers.size === 0 || Date.now() >= deadline) {
        this.tileGroupAwaitCovers = false;
        this.tileGroupPendingCovers.clear();
        this.afterTileGroupFrames(generation, 1, run);
        return;
      }
      this.afterTileGroupFrames(generation, 1, check);
    };
    // 建页这一帧里封面才挂上、登记成待解码。
    this.afterTileGroupFrames(generation, 2, check);
  }

  /** 只登记后台解码的本地封面：同步解码的挂上就画好了，网络封面不等。 */
  noteTileGroupCoverMounted(book: Book, src: string, sync: boolean): void {
    if (this.tileGroupAwaitCovers && !sync && this.coverSyncLoadable(src)) this.tileGroupPendingCovers.add(book.bookUrl);
  }

  tileGroupElementId(groupId: number, pageKey: string): string {
    return `shelf_group_${pageKey}_${groupId}`;
  }

  tileGroupFlyValue(from: number, to: number): number {
    return from + (to - from) * this.tileGroupFlyProgress;
  }

  /** 尺寸、布局或状态栏变了，书架上量到的位置和缓存的落点都作废。 */
  tileGroupViewportKey(): string {
    return `${Math.round(this.contextViewportWidth)}x${Math.round(this.contextViewportHeight)}|` +
      `${this.bookshelfLayoutMode}|${Math.round(this.statusBarHeight)}`;
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

  /** 关书挪位用的平面封面：按较大那头的尺寸排版，只用缩放平移从 from 走到 to。 */
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

  beginTileGroupMotion(targetGroupId: number): number {
    const generation = ++this.tileGroupMotionGeneration;
    this.tileGroupAnimating = true;
    this.tileGroupPendingTarget = targetGroupId;
    if (this.tileGroupMotionWatchdog >= 0) clearTimeout(this.tileGroupMotionWatchdog);
    this.tileGroupMotionWatchdog = setTimeout((): void => this.finishTileGroupMotion(generation),
      SHELF_GROUP_MOTION_WATCHDOG);
    return generation;
  }

  /** 切换当前分组。进入分组页时挂上分组页那一层（换了分组就换一套分类页），书架底层记住进来前的分组。 */
  applyTileGroupTarget(groupId: number): void {
    this.tileGroupPendingTarget = -1;
    if (groupId > 0 && this.isTileLayout()) {
      if (this.activeShelfGroupId <= 0) this.tileGroupBaseGroupId = this.activeShelfGroupId;
      this.mountTileGroupLayer(groupId);
    }
    this.activeShelfGroupId = groupId;
  }

  mountTileGroupLayer(groupId: number): void {
    if (this.tileGroupLayerGroupId === groupId) return;
    this.tileGroupPages = new Map();
    this.tileGroupBackdropReveal = 0;
    this.tileGroupLayerGroupId = groupId;
  }

  /** 没在开合时，分组页那一层跟着当前分组：启动时恢复到分组页、分组被删等都走这里。 */
  syncTileGroupLayer(): void {
    if (this.tileGroupAnimating) return;
    if (this.isTileGroupPage()) {
      this.mountTileGroupLayer(this.activeShelfGroupId);
    } else if (this.tileGroupLayerGroupId > 0) {
      this.tileGroupLayerGroupId = 0;
      this.tileGroupPages = new Map();
    }
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
    // 收尾后这一轮的迟到回调（首帧、动画结束）一律作废。
    this.tileGroupMotionGeneration++;
    if (this.tileGroupMotionWatchdog >= 0) clearTimeout(this.tileGroupMotionWatchdog);
    this.tileGroupMotionWatchdog = -1;
    // 首帧回调卡住时也要切到用户选的页面，不能一直锁住书架。
    if (this.tileGroupPendingTarget >= 0) this.applyTileGroupTarget(this.tileGroupPendingTarget);
    this.clearTileGroupMotionLayers();
    if (!this.isTileGroupPage()) this.tileGroupHasOrigin = false;
    this.tileGroupAnimating = false;
    // 返回动画走完、画面静止后才卸下分组页那一层，销毁它的那一帧看不出来。
    this.syncTileGroupLayer();
    if (this.tileGroupPendingBack) {
      this.tileGroupPendingBack = false;
      this.exitTileGroupPage();
    }
  }

  /** 背景放回两层里，两层都回到原大、不透明（书架在分组页下面时是藏着的）。 */
  clearTileGroupMotionLayers(): void {
    this.tileGroupShelfScale = 1;
    this.tileGroupPageScale = 1;
    this.tileGroupBareBody = false;
    this.tileGroupMotionBackground = false;
    this.tileGroupAwaitCovers = false;
    this.tileGroupPendingCovers.clear();
    this.tileGroupShelfOpacity = 1;
    this.tileGroupPageOpacity = 1;
  }

  cancelTileGroupMotion(): void {
    this.tileGroupMotionGeneration++;
    if (this.tileGroupMotionWatchdog >= 0) clearTimeout(this.tileGroupMotionWatchdog);
    this.tileGroupMotionWatchdog = -1;
    this.tileGroupPendingTarget = -1;
    this.tileGroupPendingBack = false;
    this.clearTileGroupMotionLayers();
    this.tileGroupAnimating = false;
    this.syncTileGroupLayer();
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
    const thenAssign = this.addBookGroupThenAssign;
    // 先清标记再关弹窗，关弹窗时不清掉单本移动的目标书。
    this.addBookGroupThenAssign = false;
    this.closeAddBookGroupDialog();
    this.newBookGroupName = '';
    this.shelfGroups = await db.getCustomBookGroups();
    if (thenAssign) {
      await this.assignSelectedBooksToGroup(group.groupId);
      return;
    }
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

  async toggleBookGroupPinned(group: BookGroup): Promise<void> {
    const nextPinned = !group.pinned;
    try {
      await AppDatabase.getInstance().setBookGroupPinned(group.groupId, nextPinned);
      await this.loadBooks();
      HdsFeedback.showToast(nextPinned ? `已置顶分组《${group.groupName}》` : `已取消置顶分组《${group.groupName}》`);
    } catch (e) {
      console.error('更新分组置顶状态失败:', e);
      HdsFeedback.showToast(nextPinned ? '置顶失败' : '取消置顶失败');
    }
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
    // 先关掉确认框露出书架，选中的书在多选状态下原地消散，播完再退出多选、补位。
    this.closeBatchDeleteDialog();
    const dissolve = this.dissolveShelfBooks(targets);
    try {
      for (const book of targets) {
        await CloudAutoSync.onBookRemoved(getContext(this), book).catch(() => undefined);
        LocalBookService.deleteLocalBookFiles(getContext(this), book);
        await db.deleteBook(book.bookUrl, 'bookshelf_batch_delete');
      }
    } finally {
      await dissolve;
      this.exitBookMultiSelect();
      this.commitShelfBookRemoval(urls);
      for (const book of targets) this.deleteBookCoverCache(book);
    }
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    await this.loadBooks();
    HdsFeedback.showToast(`已删除 ${targets.length} 本书`);
  }


  /** 书架标题行实际生效的收起量：没有可滚动的列表时标题行始终完整显示（分组页的标题栏不收起）。 */
  shelfHeaderCollapseValue(): number {
    return !this.isLoading && this.books.length > 0 && !this.isBookMultiSelect ? this.shelfHeaderCollapse : 0;
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

  /** 列表顶部留白按标题行完整显示时的高度预留，不随收起变化，避免滚动中列表跳动。分组页那一层只有标题栏。 */
  bookshelfTopOverlayHeight(pageKey: string = ''): number {
    let height = this.statusBarHeight + 56;
    if (this.isTileGroupPageKey(pageKey)) {
      return height + (this.isBookMultiSelect ? 42 : 0);
    }
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

  bookshelfTileTopSpacerHeight(books: Book[] = this.books, pageKey: string = ''): number {
    const gridTopPadding = 10;
    const comfortableGap = 12;
    // Grid 会在顶部占位项与首行之间继续添加 rowsGap，需要从占位高度中抵消。
    return Math.max(0, this.bookshelfTopOverlayHeight(pageKey) + comfortableGap -
      gridTopPadding - this.shelfTileGridRowGap(books, pageKey));
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
   * 没有更新时间时补“最新”前缀：书源章节名常常只有“第N章”，单独显示会被误读成“共N章”。
   */
  getShelfUpdateLineText(book: Book): string {
    const timeText = BookDisplayHelper.getLastUpdateRelativeText(book);
    const chapterText = (book.latestChapterTitle || '').trim();
    if (timeText && chapterText) {
      return `${timeText} · ${chapterText}`;
    }
    if (chapterText) {
      return `最新 · ${chapterText}`;
    }
    return timeText;
  }

  getShelfLatestChapterTitle(book: Book): string {
    return (book.latestChapterTitle || '').trim();
  }

  /** 宽松布局的作者信息行：作者 · 书源 · 字数。书源已在封面角标上显示时不重复。 */
  getLooseShelfMetaText(book: Book): string {
    const parts: string[] = [this.getShelfAuthorText(book)];
    const origin = this.shelfBookOriginName(book);
    if (origin && BookshelfCoverBadgeSettings.location(this.bookshelfCoverBadges, 'source') < 0) {
      parts.push(origin);
    }
    const words = this.formatShelfWordCount(book.wordCount);
    if (words) {
      parts.push(words);
    }
    return parts.join(' · ');
  }

  /** 书源给的字数可能是纯数字，也可能已带“万字”等单位；纯数字才换算。 */
  formatShelfWordCount(raw: string): string {
    const text = (raw || '').trim();
    if (!/^\d+$/.test(text)) {
      return text;
    }
    const count = Number.parseInt(text);
    if (!Number.isFinite(count) || count <= 0) {
      return '';
    }
    if (count < 10000) {
      return `${count}字`;
    }
    const wan = count / 10000;
    return wan >= 100 ? `${Math.round(wan)}万字` : `${Math.round(wan * 10) / 10}万字`;
  }

  /** 封面角标没放“书籍更新标识”时，在宽松/紧凑卡片右上角补一个“新”。 */
  shouldShowShelfCardUpdateCorner(book: Book): boolean {
    return this.hasShelfBookUpdate(book) &&
      BookshelfCoverBadgeSettings.location(this.bookshelfCoverBadges, 'update') < 0;
  }

  @Builder
  looseLatestChapterRow(book: Book) {
    Row({ space: 6 }) {
      if (this.getShelfLatestChapterTitle(book) || BookDisplayHelper.getLastUpdateRelativeText(book)) {
        Row({ space: 6 }) {
          Text(BookDisplayHelper.getLastUpdateRelativeText(book) || '最新')
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
            .maxLines(1)
            .flexShrink(0)
          if (this.getShelfLatestChapterTitle(book)) {
            Text(this.getShelfLatestChapterTitle(book))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.secondaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
          }
        }
        .height(24)
        .padding({ left: 9, right: 9 })
        .borderRadius(12)
        .backgroundColor(HexColor.withOpacity(this.accentColor(), 0.1))
        .alignItems(VerticalAlign.Center)
        .flexShrink(1)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 列表卡片右上角的“新”：贴住卡片角，外侧圆角跟卡片一致，只在内侧左下留圆角。 */
  @Builder
  shelfCardUpdateCorner() {
    Text('新')
      .fontSize(AppFontSize.MICRO)
      .fontWeight(FontWeight.Medium)
      .fontColor(ThemeRuntime.onAccentColor())
      .height(this.shelfCardUpdateCornerHeight())
      .padding({ left: 8, right: 8 })
      .borderRadius({ topRight: ThemeRuntime.mediumRadius(), bottomLeft: 10 })
      .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
  }

  shelfCardUpdateCornerHeight(): number {
    return 20;
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

  /** 宽松布局信息块（= 封面）高度。进度条开着时没有进度行，这份高度留给书名第二行，见 looseBookContent。 */
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
  shouldUseTileGroupFolders(pageKey: string = ''): boolean {
    return this.isTileLayout() && this.pageGroupId(pageKey) === 0 && !this.isBookMultiSelect &&
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

  shouldShowLatestExpandedTileBook(pageKey: string = ''): boolean {
    return this.isTileLayout() && (this.isCompanionLayout() || this.bookshelfLastReadPinMode !== 'off') &&
      this.pageGroupId(pageKey) === 0 &&
      !this.isBookMultiSelect && !this.shelfAppliedSearchKeyword;
  }

  isLatestTileCardLarge(): boolean {
    return this.isCompanionLayout() || this.bookshelfLastReadPinMode === 'large';
  }

  getTileBooksWithoutLatest(books: Book[], latest: Book[] = this.getLatestReadTileBooks(books), pageKey: string = ''): Book[] {
    const uniqueBooks: Book[] = [];
    const seenBookUrls = new Set<string>();
    books.forEach((book: Book) => {
      const bookUrl = (book.bookUrl || '').trim();
      if (bookUrl && seenBookUrls.has(bookUrl)) return;
      if (bookUrl) seenBookUrls.add(bookUrl);
      uniqueBooks.push(book);
    });
    if (!this.shouldShowLatestExpandedTileBook(pageKey)) {
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
    const cacheKey = `${mode}_${viewKey}_${this.shelfBaseGroupId()}_${this.isBookMultiSelect ? '1' : '0'}_` +
      `${this.shouldShowLatestExpandedTileBook() ? latestBookUrls : ''}_` +
      `${books.map((book: Book) => `${book.bookUrl}:${book.name}:${book.author}:${this.getBookReadTime(book)}:${this.getBookAddTime(book)}:` +
        `${BookshelfSortHelper.getBookUpdateTime(book)}:${book.group}:${book.isPinned ? '1' : '0'}`).join('|')}_` +
      `${this.shelfGroups.map((group: BookGroup) => `${group.groupId}:${group.groupName}:${group.pinned ? '1' : '0'}`).join('|')}`;
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
      // 置顶分组和置顶书籍同属最前一档，档内按当前排序方式排。
      entry.pinned = group.pinned === true;
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

  shelfTileGridRowGap(books: Book[] = this.books, pageKey: string = ''): number {
    // 轮播卡片在 deck 内上下各留 10vp；圆点行上下对称，下方也只需 10vp。
    // 普通书籍项补回剩余行距，不改变后续书籍行之间的距离。陪伴布局顶部有多块整行内容，统一用小行距。
    if (this.shouldShowLatestExpandedTileBook(pageKey) && this.isCompanionLayout()) return 10;
    return this.shouldShowLatestExpandedTileBook(pageKey) && this.isLatestTileCardLarge() &&
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
          .height(this.bookshelfTileTopSpacerHeight(this.shelfBooksForPage(pageKey), pageKey))
      }
      .columnStart(0)
      .columnEnd(this.shelfTileColumnCount() - 1)

      if (this.shouldShowLatestExpandedTileBook(pageKey)) {
        if (this.isCompanionLayout()) {
          if (this.bookshelfGreetingMode !== 'off') {
          GridItem() {
            Column() {
              this.shelfCompanionGreeting(pageKey)
              if (!this.bookshelfCompanionReadingNote) {
                // 小记卡片关闭时仍挂一个不占位的实例，问候语的 {今日阅读} 继续有数可用。
                ShelfReadingNoteCard({
                  refreshKey: this.shelfCompanionNoteRefreshKey(this.shelfBooksForPage(pageKey)),
                  appDarkMode: this.appDarkMode,
                  collapsed: true
                })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .columnStart(0)
          .columnEnd(this.shelfTileColumnCount() - 1)
          }

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

          if (this.bookshelfCompanionReadingNote) {
          GridItem() {
            ShelfReadingNoteCard({
              refreshKey: this.shelfCompanionNoteRefreshKey(this.shelfBooksForPage(pageKey)),
              appDarkMode: this.appDarkMode
            })
          }
          .columnStart(0)
          .columnEnd(this.shelfTileColumnCount() - 1)
          }

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

      if (this.shouldUseTileGroupFolders(pageKey)) {
        LazyForEach(this.shelfTileEntryDataSource(pageKey), (entry: ShelfTileSortEntry) => {
          GridItem() {
            if (entry.kind === 'group' && entry.group) {
              this.shelfTileGroupFolder(entry.group, pageKey)
            } else if (entry.book) {
              this.shelfTileBook(entry.book, pageKey)
            }
          }
          .padding({ bottom: this.shelfTileRowGap() - this.shelfTileGridRowGap(this.shelfBooksForPage(pageKey), pageKey) })
        }, (entry: ShelfTileSortEntry) => entry.book ?
          this.shelfBookRenderKey(entry.book, entry.key) :
          `${entry.key}_stagger_${this.bookshelfCompanionStagger ? '1' : '0'}_pin_${entry.pinned ? '1' : '0'}`)
      } else {
        LazyForEach(this.shelfTileBookDataSource(pageKey), (book: Book) => {
          GridItem() {
            this.shelfTileBook(book, pageKey)
          }
          .padding({ bottom: this.shelfTileRowGap() - this.shelfTileGridRowGap(this.shelfBooksForPage(pageKey), pageKey) })
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
    .rowsGap(this.shelfTileGridRowGap(this.shelfBooksForPage(pageKey), pageKey))
    .padding({ left: BookTileLayout.SIDE_PADDING, right: BookTileLayout.SIDE_PADDING, top: 10 })
    .backgroundColor(this.shelfSurfaceColor())
    .scrollBar(BarState.Off)
    .cachedCount(4)
    .onAppear(() => this.restoreShelfPageScroll(pageKey, true))
    .onDidScroll((delta: number) => {
      if (!this.tileGroupAnimating && pageKey === this.shelfPageKey()) {
        const page = this.shelfCategoryPage(pageKey);
        page.tileOffset = page.tileScroller.currentOffset().yOffset;
        if (this.isTileGroupPageKey(pageKey)) {
          // 分组页的标题栏不收起，只让毛玻璃按滚动显现。
          const reveal = CollapsingHeader.backdropReveal(page.tileOffset);
          if (reveal !== this.tileGroupBackdropReveal) this.tileGroupBackdropReveal = reveal;
        } else {
          this.onShelfListScroll(delta, page.tileOffset);
        }
      }
    })
    .onScrollStop(() => {
      if (!this.tileGroupAnimating && pageKey === this.shelfPageKey() && !this.isTileGroupPageKey(pageKey)) {
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
    .opacity(this.isShelfBookDissolving(book.bookUrl) ? 0 : 1)
    .scale({ x: this.shelfDissolveScale(book.bookUrl), y: this.shelfDissolveScale(book.bookUrl) })
    .blur(this.isShelfBookDissolving(book.bookUrl) ? 16 : 0)
    .hitTestBehavior(this.isShelfBookDissolving(book.bookUrl) ? HitTestMode.None : HitTestMode.Default)
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
        Text(this.shelfContinueActionText(book))
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
    .opacity(this.isShelfBookDissolving(book.bookUrl) ? 0 : 1)
    .scale({ x: this.shelfDissolveScale(book.bookUrl), y: this.shelfDissolveScale(book.bookUrl) })
    .blur(this.isShelfBookDissolving(book.bookUrl) ? 16 : 0)
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

  shelfCompanionReadingBookName(pageKey: string): string {
    const latest = this.getLatestReadTileBooks(this.shelfBooksForPage(pageKey));
    return latest.length > 0 ? latest[0].name : '';
  }

  shelfCompanionGreetingLines(pageKey: string): string[] {
    const now = new Date();
    if (this.bookshelfGreetingMode !== 'custom') return ShelfGreetingTemplate.defaultLines(now.getHours());
    const values = new ShelfGreetingValues();
    values.hour = now.getHours();
    values.date = now;
    values.nickname = this.accountDisplayName;
    values.todayReadMs = this.shelfTodayReadMs;
    values.readingBookName = this.shelfCompanionReadingBookName(pageKey);
    return ShelfGreetingTemplate.customLines(this.bookshelfGreetingTitle, this.bookshelfGreetingSubtitle, values);
  }

  /** 长按问候语直接改文案，不用进书架设置。 */
  @Builder
  shelfCompanionGreeting(pageKey: string) {
    Column({ space: AppSpacing.XS }) {
      Text(this.shelfCompanionGreetingLines(pageKey)[0])
        .fontSize(AppFontSize.HEADLINE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.shelfCompanionGreetingLines(pageKey)[1]) {
        Text(this.shelfCompanionGreetingLines(pageKey)[1])
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpacing.XS, bottom: AppSpacing.SM })
    .gesture(LongPressGesture().onAction(() => this.openGreetingEditor(pageKey)))
  }

  openGreetingEditor(pageKey: string): void {
    if (this.isBookMultiSelect) return;
    const custom = this.bookshelfGreetingMode === 'custom';
    const draft = ShelfGreetingTemplate.defaultDraft(new Date().getHours());
    const title = custom ? this.bookshelfGreetingTitle : draft[0];
    const subtitle = custom ? this.bookshelfGreetingSubtitle : draft[1];
    const readingBookName = this.shelfCompanionReadingBookName(pageKey);
    this.greetingEditorDialogSession.open(this.getUIContext(), (): void => {
      this.greetingEditorDialogContent(title, subtitle, readingBookName);
    }, {
      // 写到一半误触蒙层或返回键不能丢稿，只能点取消或保存关闭。
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示问候语编辑弹窗失败:'
    });
  }

  @Builder
  greetingEditorDialogContent(title: string, subtitle: string, readingBookName: string) {
    ShelfGreetingEditor({
      appDarkMode: this.appDarkMode,
      initialTitle: title,
      initialSubtitle: subtitle,
      nickname: this.accountDisplayName,
      todayReadMs: this.shelfTodayReadMs,
      readingBookName: readingBookName,
      onSave: (nextTitle: string, nextSubtitle: string): void => this.saveGreeting('custom', nextTitle, nextSubtitle),
      onSaveDefault: (): void => this.saveGreeting('time', '', ''),
      onCancel: (): void => this.greetingEditorDialogSession.close(this.getUIContext())
    })
  }

  saveGreeting(mode: string, title: string, subtitle: string): void {
    this.greetingEditorDialogSession.close(this.getUIContext());
    BookshelfDisplaySettingsStore.saveGreeting(getContext(this), mode, title, subtitle).catch((e: Error) => {
      console.warn('保存问候语失败:', e);
      HdsFeedback.showToast('问候语保存失败');
    });
  }

  openSectionTitleEditor(): void {
    if (this.isBookMultiSelect) return;
    const title = this.bookshelfCompanionSectionTitle;
    this.sectionTitleEditorDialogSession.open(this.getUIContext(), (): void => {
      this.sectionTitleEditorDialogContent(title);
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示书架标题编辑弹窗失败:'
    });
  }

  @Builder
  sectionTitleEditorDialogContent(title: string) {
    ShelfSectionTitleEditor({
      appDarkMode: this.appDarkMode,
      initialTitle: title,
      onSave: (nextTitle: string): void => {
        this.sectionTitleEditorDialogSession.close(this.getUIContext());
        BookshelfDisplaySettingsStore.saveCompanionSectionTitle(getContext(this), nextTitle).catch((e: Error) => {
          console.warn('保存书架标题失败:', e);
          HdsFeedback.showToast('书架标题保存失败');
        });
      },
      onCancel: (): void => this.sectionTitleEditorDialogSession.close(this.getUIContext())
    })
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

  /**
   * “当前章/总章数 · 章节名”，如“11/1234 · 第11章 夜雨”。章节名多半自带“第N章”，序号只用分数形式给出；
   * 总章数未知时只放章节名，PDF 与未开始读的书沿用原来的说法。
   */
  shelfCompanionChapterText(book: Book): string {
    const title = this.getReadChapterText(book);
    if (LocalBookService.isPdfBook(book) || !title) return this.getLastReadChapterText(book);
    if (!this.hasKnownReadProgressTotal(book)) return title;
    return `${book.durChapterIndex + 1}/${book.totalChapterNum} · ${title}`;
  }

  shelfCompanionNoteRefreshKey(books: Book[]): string {
    return this.getLatestReadTileBooks(books)
      .map((book: Book): string => `${book.bookUrl}:${this.getBookReadTime(book)}`).join('|');
  }

  /**
   * 书页条纹按像素宽度换算成渐变比例，三种纸色交替，重复铺满整个书页侧面。
   * 平放的书正对着书口，等宽的条纹太像栅格，换成一组疏密不匀的。
   */
  shelfHardcoverPageStripes(width: number, uneven: boolean = false): Array<[ResourceColor, number]> {
    const unit = 1 / Math.max(1, width);
    const colors = this.appDarkMode ? ['#D2C9B9', '#A99D88', '#C3B8A5'] : ['#F6EFE2', '#D9CDB7', '#EFE6D5'];
    if (uneven) {
      return [[colors[0], 0], [colors[0], unit * 1.2], [colors[1], unit * 1.2], [colors[1], unit * 1.6],
        [colors[2], unit * 1.6], [colors[2], unit * 3], [colors[1], unit * 3], [colors[1], unit * 3.3],
        [colors[0], unit * 3.3], [colors[0], unit * 4.3], [colors[2], unit * 4.3], [colors[2], unit * 5.2],
        [colors[1], unit * 5.2], [colors[1], unit * 5.5]];
    }
    return [[colors[0], 0], [colors[0], unit], [colors[1], unit], [colors[1], unit * 1.6],
      [colors[2], unit * 1.6], [colors[2], unit * 2.4]];
  }

  /** 书脊阴影宽度与压槽宽度按封面宽度缩放，网格里的小书与继续阅读的大书比例一致。 */
  shelfHardcoverSpineWidth(coverWidth: number): number {
    return Math.max(6, Math.round(coverWidth * 0.11));
  }

  shelfHardcoverHingeWidth(coverWidth: number): number {
    return Math.max(2, Math.round(coverWidth * 0.03));
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
   * angle 是侧转角度，depthRatio 是厚度占封面宽度的比例。继续阅读的大书 36°/0.24，网格与分组里的小书默认 24°/0.2。
   * 关闭错落摆放时所有书都平放：封面正对，右边露出封面宽度 6% 的书页。
   */
  shelfBookShape(coverWidth: number, coverHeight: number, angle: number, depthRatio: number): ShelfBookShape {
    if (!this.bookshelfCompanionStagger) return ShelfBookPerspective.flat(coverWidth, coverHeight, 0.06);
    return ShelfBookPerspective.shape(coverWidth, coverHeight, angle, depthRatio, this.getUIContext().vp2px(1));
  }

  /** 书口上的书页：一层纸纹，再叠前后与上下两层明暗。靠封面的一头暗，往外渐亮。 */
  @Builder
  shelfHardcoverPagesFace(width: number, uneven: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Right,
          repeating: true,
          colors: this.shelfHardcoverPageStripes(width, uneven)
        })
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [['#6B000000', 0], ['#14000000', 0.45], ['#4DFFFFFF', 0.82], ['#1F000000', 1]]
        })
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#38FFFFFF', 0], ['#00FFFFFF', 0.3], ['#00000000', 0.75], ['#38000000', 1]]
        })
    }
    .width('100%')
    .height('100%')
  }

  /** 书口：整面先铺硬壳色，书页缩进一圈盖在上面；贴着书底的接触投影挂在这一层。侧转与平放共用，位置都取自 shelfBookShape。 */
  @Builder
  shelfHardcoverSide(coverWidth: number, coverHeight: number, angle: number, depthRatio: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() {
        this.shelfHardcoverPagesFace(this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).pagesWidth,
          this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).flat)
      }
      .width(this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).pagesWidth)
      .height(coverHeight - this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).pageInset * 2)
      .position({
        x: this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).pagesX,
        y: this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).pageInset
      })
    }
    .width(this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).depth)
    .height(coverHeight)
    .position({ x: this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).sideX, y: 0 })
    .backgroundColor(this.shelfHardcoverBoardColor())
    .shadow({ radius: 6, color: '#47000000', offsetX: 3, offsetY: 4 })
    .scale({ x: 1, y: 1, centerX: 0, centerY: 0 })
    .transform(this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).sideMatrix)
  }

  /**
   * 立着的精装书，绕竖轴侧转：封面近大远小，右侧书口是一个往里收的面，两头露出硬壳的厚度，中间是带明暗的书页。
   * 封面和书口各是一个矩形，套上 ShelfBookPerspective 算好的矩阵变成投影后的四边形；矩阵以左上角为原点，
   * 所以先用 scale 把变换中心挪到左上角。封面仍走 coverView，开书动画按原作用域定位。
   */
  @Builder
  shelfHardcoverBook(book: Book, idScope: string, coverWidth: number, coverHeight: number,
    animateCovers: boolean = false, selected: boolean = false, angle: number = 24, depthRatio: number = 0.2) {
    Stack({ alignContent: Alignment.TopStart }) {
      this.shelfHardcoverSide(coverWidth, coverHeight, angle, depthRatio)

      // 封面：大而淡的落地投影挂在这一层。
      Stack({ alignContent: Alignment.TopStart }) {
        // 圆角交给外面的封面面板裁，封面图自己不再裁 8vp，否则四角会露出下面的深色底板。
        this.coverView(book, '100%', '100%', ImageFit.Cover, animateCovers, true, idScope, 0,
          this.shelfHardcoverSpineWidth(coverWidth) + this.shelfHardcoverHingeWidth(coverWidth))
        this.shelfHardcoverCoverLight(coverWidth)
      }
      .width(coverWidth)
      .height(coverHeight)
      .position({ x: this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).coverX, y: 0 })
      .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 3, bottomRight: 3 })
      .border({ width: selected ? 2 : 0, color: this.accentColor() })
      .backgroundColor(this.shelfHardcoverBoardColor())
      .clip(true)
      .shadow({ radius: Math.round(coverWidth * 0.19), color: this.appDarkMode ? '#99000000' : '#5250341A',
        offsetX: Math.round(coverWidth * 0.085), offsetY: Math.round(coverWidth * 0.115) })
      .scale({ x: 1, y: 1, centerX: 0, centerY: 0 })
      .transform(this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).coverMatrix)
    }
    // 整本书的舞台自己没有变换，继续阅读卡片里的书按它量位置再算封面四角（见 shelfOpeningCoverQuad）。
    .id(`${this.shelfCoverElementId(book, idScope)}_stage`)
    .width(this.shelfBookShape(coverWidth, coverHeight, angle, depthRatio).stageWidth)
    .height(coverHeight + BookshelfPage.SHELF_HARDCOVER_STAGE_PAD)
  }

  /**
   * 分组里扇形张开的书比单本书小一圈，张开后两侧只略微探进列间距。
   * 关闭错落摆放时三本书向右上阶梯错开，每本缩小一点，整叠约等于一本书的占位。
   * 错开只有几 vp 时后两本只露出一条细缝，看着像描边错位而不像摞在一起的书。
   */
  shelfFolderBookWidth(): number {
    if (!this.bookshelfCompanionStagger) {
      return Math.max(32, this.shelfTileHardcoverWidth() - Math.round(this.shelfFolderStackStep() * 1.2));
    }
    return Math.max(32, Math.round(this.shelfTileHardcoverWidth() * 0.76));
  }

  /** 关闭错落摆放时每本书向右上错开的距离，按单本书宽度缩放。 */
  shelfFolderStackStep(): number {
    return Math.max(5, Math.round(this.shelfTileHardcoverWidth() * 0.075));
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
    if (!this.bookshelfCompanionStagger) return 0;
    return slot === 1 ? -7 : (slot === 2 ? 7 : 0);
  }

  /** 关闭错落摆放时不张开：三本立正，后面的依次向右上错开一个台阶，露出书头和书页侧面。 */
  shelfFolderFanShift(slot: number): number {
    if (!this.bookshelfCompanionStagger) return (slot - 1) * this.shelfFolderStackStep();
    return slot === 1 ? -5 : (slot === 2 ? 5 : 0);
  }

  shelfFolderFanRise(slot: number): number {
    if (!this.bookshelfCompanionStagger) return slot * this.shelfFolderStackStep();
    return 0;
  }

  /** 后面的书压暗，叠出前后层次；阶梯叠放露出的部分少，压得比扇形更重一些才分得清。 */
  shelfFolderBackShade(slot: number): string {
    if (!this.bookshelfCompanionStagger) return slot === 2 ? '#4D000000' : '#29000000';
    return slot === 2 ? '#33000000' : '#1F000000';
  }

  @Builder
  shelfFolderFanBook(book: Book, elementId: string, slot: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      this.shelfHardcoverSide(this.shelfFolderBookWidth(), this.shelfFolderBookHeight(), 24, 0.2)

      Stack({ alignContent: Alignment.TopStart }) {
        this.coverView(book, '100%', '100%', ImageFit.Cover, true, false, '', 0,
          this.shelfHardcoverSpineWidth(this.shelfFolderBookWidth()) + this.shelfHardcoverHingeWidth(this.shelfFolderBookWidth()))
        this.shelfHardcoverCoverLight(this.shelfFolderBookWidth())
        if (slot > 0) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.shelfFolderBackShade(slot))
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(this.shelfFolderBookWidth())
      .height(this.shelfFolderBookHeight())
      .position({ x: this.shelfBookShape(this.shelfFolderBookWidth(), this.shelfFolderBookHeight(), 24, 0.2).coverX, y: 0 })
      .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 3, bottomRight: 3 })
      .backgroundColor(this.shelfHardcoverBoardColor())
      .clip(true)
      .shadow({ radius: Math.round(this.shelfFolderBookWidth() * 0.19), color: this.appDarkMode ? '#99000000' : '#5250341A',
        offsetX: Math.round(this.shelfFolderBookWidth() * 0.085), offsetY: Math.round(this.shelfFolderBookWidth() * 0.115) })
      .scale({ x: 1, y: 1, centerX: 0, centerY: 0 })
      .transform(this.shelfBookShape(this.shelfFolderBookWidth(), this.shelfFolderBookHeight(), 24, 0.2).coverMatrix)
    }
    .width(this.shelfBookShape(this.shelfFolderBookWidth(), this.shelfFolderBookHeight(), 24, 0.2).stageWidth)
    .height(this.shelfFolderBookHeight() + 4)
    .position({
      x: Math.round((this.shelfTileColumnWidth() -
        this.shelfBookShape(this.shelfFolderBookWidth(), this.shelfFolderBookHeight(), 24, 0.2).stageWidth) / 2) +
        this.shelfFolderFanShift(slot),
      y: this.shelfTileHardcoverHeight() - this.shelfFolderBookHeight() - this.shelfFolderFanRise(slot)
    })
    // 以书底中点为轴张开，三本书的书底仍落在同一条线上。
    .rotate({ angle: this.shelfFolderFanAngle(slot), centerX: '50%', centerY: '100%' })
  }

  /**
   * 陪伴布局的分组：最多三本精装书以书底为轴扇形张开。打开分组时按 elementId 量这叠书的中心，作为整页缩放的中心。
   */
  @Builder
  shelfHardcoverFolder(previewBooks: Book[], elementId: string) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.shouldUseThemeBookCover() || previewBooks.length === 0) {
        // 主题文件夹图没有单本封面可张开，做成一本以文件夹图为封面的精装书。
        Stack({ alignContent: Alignment.TopStart }) {
          this.shelfHardcoverSide(this.shelfTileHardcoverWidth(), this.shelfTileHardcoverHeight(), 24, 0.2)
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.shouldUseThemeBookCover() && this.themeImageCrop(ThemeImageSlots.FOLDER, this.activeThemeShelfFolder())) {
              ThemeCroppedImage({ src: this.activeThemeShelfFolder(),
                crop: this.themeImageCrop(ThemeImageSlots.FOLDER, this.activeThemeShelfFolder()) as ThemeImageCrop })
                .width('100%')
                .height('100%')
            } else if (this.shouldUseThemeBookCover()) {
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
          .position({ x: this.shelfBookShape(this.shelfTileHardcoverWidth(), this.shelfTileHardcoverHeight(), 24, 0.2).coverX, y: 0 })
          .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 3, bottomRight: 3 })
          .backgroundColor(this.shelfHardcoverBoardColor())
          .clip(true)
          .shadow({ radius: Math.round(this.shelfTileHardcoverWidth() * 0.19), color: this.appDarkMode ? '#99000000' : '#5250341A',
            offsetX: Math.round(this.shelfTileHardcoverWidth() * 0.085), offsetY: Math.round(this.shelfTileHardcoverWidth() * 0.115) })
          .scale({ x: 1, y: 1, centerX: 0, centerY: 0 })
          .transform(this.shelfBookShape(this.shelfTileHardcoverWidth(), this.shelfTileHardcoverHeight(), 24, 0.2).coverMatrix)
        }
        .width(this.shelfBookShape(this.shelfTileHardcoverWidth(), this.shelfTileHardcoverHeight(), 24, 0.2).stageWidth)
        .height(this.shelfTileHardcoverHeight() + 4)
        .position({
          x: Math.round((this.shelfTileColumnWidth() -
            this.shelfBookShape(this.shelfTileHardcoverWidth(), this.shelfTileHardcoverHeight(), 24, 0.2).stageWidth) / 2),
          y: 0
        })
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

  /** 书架上的书不一样高：在单本最大尺寸的 82%–100% 之间取几档。 */
  shelfTileBookScale(book: Book): number {
    if (!this.bookshelfCompanionStagger) return 1;
    const scales = [1, 0.92, 0.86, 0.96, 0.82, 1, 0.89];
    return scales[this.shelfBookJitterSeed(book) % scales.length];
  }

  /** 一半的书立正，另一半以书底为轴斜靠，最多 5°。 */
  shelfTileBookLean(book: Book): number {
    if (!this.bookshelfCompanionStagger) return 0;
    const angles = [0, -3, 0, 4, 0, -2, 0, 5, -4, 0, 2.5];
    return angles[Math.floor(this.shelfBookJitterSeed(book) / 7) % angles.length];
  }

  /** 错落摆放时每本书侧转的角度不同：有的几乎正对着，有的转得能看见一大截书口。 */
  shelfTileBookTurn(book: Book): number {
    if (!this.bookshelfCompanionStagger) return 24;
    const turns = [24, 14, 32, 20, 36, 10, 28];
    return turns[Math.floor(this.shelfBookJitterSeed(book) / 77) % turns.length];
  }

  /** 错落摆放时书有厚有薄，厚度占封面宽度的 12%–30%。侧转角度与厚度取同一套档位，投影后都不超出一列的宽度。 */
  shelfTileBookDepth(book: Book): number {
    if (!this.bookshelfCompanionStagger) return 0.2;
    const depths = [0.2, 0.14, 0.26, 0.3, 0.12, 0.22, 0.17];
    return depths[Math.floor(this.shelfBookJitterSeed(book) / 539) % depths.length];
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
        this.shelfCompanionCoverHeight(), false, false, 36, 0.24)

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

        Text(this.shelfCompanionChapterText(book))
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
          Text(this.shelfContinueActionText(book))
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
    .opacity(this.isShelfBookDissolving(book.bookUrl) ? 0 : 1)
    .scale({ x: this.shelfDissolveScale(book.bookUrl), y: this.shelfDissolveScale(book.bookUrl) })
    .blur(this.isShelfBookDissolving(book.bookUrl) ? 16 : 0)
  }

  /** 长按标题直接改文案，不用进书架设置。 */
  @Builder
  shelfCompanionSectionHeader(pageKey: string) {
    Row() {
      Text(BookshelfDisplaySettingsStore.companionSectionTitleText(this.bookshelfCompanionSectionTitle))
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
        .gesture(LongPressGesture().onAction(() => this.openSectionTitleEditor()))
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
        if (this.shouldUseThemeBookCover() && this.themeImageCrop(ThemeImageSlots.FOLDER, this.activeThemeShelfFolder())) {
          ThemeCroppedImage({ src: this.activeThemeShelfFolder(),
            crop: this.themeImageCrop(ThemeImageSlots.FOLDER, this.activeThemeShelfFolder()) as ThemeImageCrop })
            .width('100%')
            .height('100%')
        } else if (this.shouldUseThemeBookCover()) {
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
        if (this.shelfRefreshActiveInGroup(group.groupId, pageKey) > 0) {
          LoadingProgress()
            .width(13)
            .height(13)
            .color(this.accentColor())
          Text(`${this.shelfRefreshActiveInGroup(group.groupId, pageKey)} 本检查中`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.accentColor())
        } else {
          if (group.pinned) {
            SymbolGlyph($r('sys.symbol.pin'))
              .fontSize(12)
              .fontColor([this.accentColor()])
              .accessibilityText('已置顶')
          }
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(13)
            .fontColor([this.subTextColor()])
          Text(`共 ${this.getTileGroupBooks(group.groupId, this.shelfBooksForPage(pageKey)).length} 本`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
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

  shelfRefreshActiveInGroup(groupId: number, pageKey: string): number {
    if (this.shelfRefreshActive.length === 0) return 0;
    const urls = new Set<string>(this.getTileGroupBooks(groupId, this.shelfBooksForPage(pageKey))
      .map((book: Book): string => book.bookUrl));
    return this.shelfRefreshActive.filter((item: ShelfRefreshActiveBook): boolean => urls.has(item.book.bookUrl)).length;
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
              this.shelfTileBookCoverHeight(book), true, this.isBookSelected(book.bookUrl),
              this.shelfTileBookTurn(book), this.shelfTileBookDepth(book))
          }
          .position({
            x: Math.round((this.shelfTileColumnWidth() - this.shelfBookShape(this.shelfTileBookCoverWidth(book),
              this.shelfTileBookCoverHeight(book), this.shelfTileBookTurn(book), this.shelfTileBookDepth(book)).stageWidth) / 2),
            y: this.shelfTileHardcoverHeight() - this.shelfTileBookCoverHeight(book)
          })
          .rotate({ angle: this.shelfTileBookLean(book), centerX: '50%', centerY: '100%' })
          if (this.isBookMultiSelect) {
            this.shelfTileSelectMark(book)
          }
        }
        // 格子没有变换：斜靠的书按它量位置，再按上面的排版参数算封面四角（见 shelfOpeningCoverQuad）。
        .id(`${this.shelfCoverElementId(book, this.shelfCoverScope(pageKey, false))}_slot`)
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
    .id(this.shelfCardElementId(book, this.shelfCoverScope(pageKey, false)))
    .opacity(this.isShelfBookDissolving(book.bookUrl) ? 0 : 1)
    .scale({ x: this.shelfDissolveScale(book.bookUrl), y: this.shelfDissolveScale(book.bookUrl) })
    .blur(this.isShelfBookDissolving(book.bookUrl) ? 16 : 0)
    .hitTestBehavior(this.isShelfBookDissolving(book.bookUrl) ? HitTestMode.None : HitTestMode.Default)
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
    if (BookTypeSupport.isAudio(book)) {
      this.openShelfAudioBook(book);
      return;
    }
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

  /**
   * 有声书直接进听书页：听书页按播放器从底部滑上来、收下去，不做封面翻开，也就不要首页截图和整页 0 时长转场。
   * 还判断不出类型的（书源没声明、第一次打开）仍走阅读页，由它查到是有声书后转过去。
   * shelfBookOpening 让听书页关闭时通知书架放开按住的阅读时间、按新进度挪位。
   */
  private openShelfAudioBook(book: Book): void {
    this.shelfBookRoutePending = true;
    AppStorage.setOrCreate<boolean>('shelfReaderDirectTransition', false);
    this.discardShelfOpeningBackdrop();
    router.pushUrl({
      url: 'pages/AudioBook',
      params: { bookUrl: book.bookUrl, shelfBookOpening: this.bookshelfBookOpenAnimation ? 'true' : 'false' }
    }).then((): void => {
      this.shelfBookRoutePending = false;
    }).catch((error: Error): void => {
      console.error('打开听书页失败:', error);
      this.cancelShelfBookOpening();
    });
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
      boundsX: 0, boundsY: 0, boundsWidth: 0, boundsHeight: 0, windowWidth: 0, windowHeight: 0, cropImage: false,
      themeCover: false
    };
    this.measureShelfOpeningBounds(book, opening, touchX, touchY);
    if (this.shouldUseThemeBookCover()) {
      const covers = this.activeThemeBookCovers(book);
      opening.cover = covers.length > 0 ? covers[0] : '';
      opening.frame = this.activeThemeShelfFrame();
      opening.color = this.inputColor();
      opening.themeCover = true;
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
      this.applyShelfOpeningCoverLanding(ui, book, opening, pageKey, pickedLatest);
    } catch (error) {
      // LazyForEach 已回收源节点等情况：没有位置就由共享转场飞封面。
    }
  }

  /**
   * 错落摆放的立体书：封面在窗口里是个侧转（网格里还斜靠）的四边形，按排版参数算出它的四个角（vp，左上起顺时针）。
   * 按 id 量封面节点得到的是它变换前的那块，比侧转后的封面宽、位置也偏，关书落在那上面再换成书架上的书会跳一下。
   * 锚点量的是自己没有变换的节点（网格里是书所在的格子，继续阅读卡片里是整本书的舞台），不依赖系统对变换后节点的
   * 测量口径。平放的书和其他布局返回 undefined，沿用量到的矩形。
   */
  shelfOpeningCoverQuad(ui: UIContext, book: Book, pageKey: string, latest: boolean): number[] | undefined {
    if (!this.isCompanionLayout() || !this.bookshelfCompanionStagger) return undefined;
    const coverWidth = latest ? this.shelfCompanionCoverWidth() : this.shelfTileBookCoverWidth(book);
    const coverHeight = latest ? this.shelfCompanionCoverHeight() : this.shelfTileBookCoverHeight(book);
    const shape = latest ? this.shelfBookShape(coverWidth, coverHeight, 36, 0.24) :
      this.shelfBookShape(coverWidth, coverHeight, this.shelfTileBookTurn(book), this.shelfTileBookDepth(book));
    if (shape.flat || shape.coverQuad.length !== 8) return undefined;
    const coverId = this.shelfCoverElementId(book, this.shelfCoverScope(pageKey, latest));
    let anchor: componentUtils.ComponentInfo | undefined = undefined;
    try {
      anchor = ui.getComponentUtils().getRectangleById(`${coverId}${latest ? '_stage' : '_slot'}`);
    } catch (error) {
      return undefined;
    }
    if (!anchor || anchor.size.width <= 0 || anchor.size.height <= 0) return undefined;
    let originX = ui.px2vp(anchor.windowOffset.x);
    let originY = ui.px2vp(anchor.windowOffset.y);
    let lean = 0;
    if (!latest) {
      // 与 shelfTileBook 里这本书在格子中的位置、斜靠一致。
      originX += Math.round((this.shelfTileColumnWidth() - shape.stageWidth) / 2);
      originY += this.shelfTileHardcoverHeight() - coverHeight;
      lean = this.shelfTileBookLean(book);
    }
    return ShelfBookPerspective.coverQuadInWindow(shape, coverHeight + BookshelfPage.SHELF_HARDCOVER_STAGE_PAD,
      originX, originY, lean);
  }

  /**
   * 算得出四角、且四角都在窗口里、与量到的封面是同一处时，把 bounds 换成封面实际占的那块（斜靠的书带上角度），
   * 并记下封面侧转前的宽高比，封面图的裁切才和书架上一致。
   */
  applyShelfOpeningCoverLanding(ui: UIContext, book: Book, opening: ShelfOpeningCover, pageKey: string,
    latest: boolean): void {
    const quad = this.shelfOpeningCoverQuad(ui, book, pageKey, latest);
    if (!quad) return;
    let minX = quad[0];
    let maxX = quad[0];
    let minY = quad[1];
    let maxY = quad[1];
    for (let index = 2; index < quad.length; index += 2) {
      minX = Math.min(minX, quad[index]);
      maxX = Math.max(maxX, quad[index]);
      minY = Math.min(minY, quad[index + 1]);
      maxY = Math.max(maxY, quad[index + 1]);
    }
    if (!(minX >= -1 && minY >= -1 && maxX <= opening.windowWidth + 1 && maxY <= opening.windowHeight + 1)) return;
    // 锚点量错（比如节点还没排好）时四角会落到别处，这时宁可按量到的矩形缩放。
    const centerX = (minX + maxX) / 2;
    const centerY = (minY + maxY) / 2;
    if (centerX < opening.boundsX - opening.boundsWidth || centerX > opening.boundsX + opening.boundsWidth * 2 ||
      centerY < opening.boundsY - opening.boundsHeight || centerY > opening.boundsY + opening.boundsHeight * 2) {
      return;
    }
    const lean = latest ? 0 : this.shelfTileBookLean(book);
    const landing = ShelfBookPerspective.coverLanding(quad, lean);
    if (landing[2] <= 0 || landing[3] <= 0) return;
    opening.boundsX = landing[0];
    opening.boundsY = landing[1];
    opening.boundsWidth = landing[2];
    opening.boundsHeight = landing[3];
    opening.lean = lean;
    const coverWidth = latest ? this.shelfCompanionCoverWidth() : this.shelfTileBookCoverWidth(book);
    const coverHeight = latest ? this.shelfCompanionCoverHeight() : this.shelfTileBookCoverHeight(book);
    opening.coverAspect = coverWidth / coverHeight;
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
    if (this.shouldShowLatestExpandedTileBook(pageKey) && !this.isLatestTileCardLarge() &&
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
    if (this.hasShelfRefreshError(book)) {
      const bookUrl = book.bookUrl;
      if (deferVisual) {
        // 与更新角标一样等开书动作过去再改状态，免得点开时整个书架重建。
        setTimeout((): void => this.clearShelfRefreshError(bookUrl), this.shelfBookMotionDelay() + 120);
      } else {
        this.clearShelfRefreshError(bookUrl);
      }
    }
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
    Stack({ alignContent: Alignment.TopEnd }) {
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
                // 右上角“新”标识会压到书名末尾，有标识时让出位置。
                .margin({ right: this.shouldShowShelfCardUpdateCorner(book) ? 18 : 0 })

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

      if (this.shouldShowShelfCardUpdateCorner(book)) {
        this.shelfCardUpdateCorner()
      }
    }
    .width('100%')
  }

  @Builder
  looseBookContent(book: Book, pageKey: string) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: AppSpacing.MD }) {
        Row() {
          // 封面高度 = 信息块高度，顶部对齐书名行、底部对齐阅读进度行。
          this.coverView(book, this.shelfCoverWidth(this.shelfLooseInfoHeight()),
            this.shelfLooseInfoHeight(), ImageFit.Cover, true, true, this.shelfCoverScope(pageKey, false))

          // 分层排：书名和作者信息贴顶，最新章节标签（进度条关着时再加进度行）贴封面底边，空白只留在中间。
          // 高度预算（封面 93）：进度条开着 = 书名两行 40 + 6 + 信息行 16 + 标签 24 = 86；
          // 关着 = 书名一行 20 + 6 + 16 + 标签 24 + 4 + 进度 19 = 89。
          Column() {
            Text(this.shelfTileBookDisplayName(book))
              .fontSize(AppFontSize.BODY_LARGE)
              .lineHeight(this.shelfTitleLineHeight())
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .maxLines(this.bookshelfShowProgressBar ? 2 : 1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              // 右上角“新”标识会压到书名第一行末尾，有标识时书名右侧让出位置。
              .padding({ right: this.shouldShowShelfCardUpdateCorner(book) ? 18 : 0 })

            Text(this.getLooseShelfMetaText(book))
              .fontSize(AppFontSize.CAPTION)
              .lineHeight(this.shelfSmallTextLineHeight())
              .fontColor(this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 6 })

            Blank()

            if (this.getShelfLatestChapterTitle(book) || BookDisplayHelper.getLastUpdateRelativeText(book)) {
              this.looseLatestChapterRow(book)
            }

            // 进度条开着时下方面板已带百分比，这里不再重复。
            if (!this.bookshelfShowProgressBar) {
              Text(this.getShelfProgressText(book))
                .fontSize(AppFontSize.BODY)
                .lineHeight(this.shelfTextLineHeight())
                .fontColor(this.secondaryTextColor())
                .maxLines(1)
                .margin({ top: this.shelfRowSpace() })
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

      if (this.shouldShowShelfCardUpdateCorner(book)) {
        this.shelfCardUpdateCorner()
      }
    }
    .width('100%')
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
    idScope: string = '', radius: number = 8, spineInset: number = -1, syncDecode: boolean = false) {
    Stack() {
      if (this.shouldUseThemeBookCover()) {
        if ((this.activeThemeBookCovers(book).length === 1 || !animateCovers) &&
          this.themeImageCrop(ThemeImageSlots.COVER, this.activeThemeBookCovers(book)[0])) {
          // 主题包动图封面取景时只记了显示区域，按区域画。
          ThemeCroppedImage({ src: this.activeThemeBookCovers(book)[0],
            crop: this.themeImageCrop(ThemeImageSlots.COVER, this.activeThemeBookCovers(book)[0]) as ThemeImageCrop,
            syncLoad: syncDecode || !this.tileGroupAwaitCovers,
            onLoaded: () => this.tileGroupPendingCovers.delete(book.bookUrl),
            onFailed: () => this.tileGroupPendingCovers.delete(book.bookUrl) })
            .width(width)
            .height(height)
            .onAppear(() => {
              if (this.tileGroupAwaitCovers && !syncDecode) this.tileGroupPendingCovers.add(book.bookUrl);
            })
        } else if (this.activeThemeBookCovers(book).length === 1 || !animateCovers) {
          Image(this.activeThemeBookCovers(book)[0])
            .width(width)
            .height(height)
            .objectFit(animateCovers ? ImageFit.Fill : imageFit)
            // 返回书架后进度变了的卡片会整体重建，封面异步加载会先空一帧；本地封面同步解码，让关书动画落地后无缝。
            // 打开分组时例外：分组页一屏的主题封面在后台解码，解码完分组页才浮起（见 afterTileGroupCoversReady）。
            .syncLoad(syncDecode || !this.tileGroupAwaitCovers)
            .onAppear(() => {
              if (this.tileGroupAwaitCovers && !syncDecode) this.tileGroupPendingCovers.add(book.bookUrl);
            })
            .onComplete(() => this.tileGroupPendingCovers.delete(book.bookUrl))
            .onError(() => this.tileGroupPendingCovers.delete(book.bookUrl))
        } else {
          Swiper() {
            ForEach(this.activeThemeBookCovers(book), (cover: ResourceStr, index: number) => {
              if (this.themeImageCrop(ThemeImageSlots.COVER, cover)) {
                ThemeCroppedImage({ src: cover, crop: this.themeImageCrop(ThemeImageSlots.COVER, cover) as ThemeImageCrop,
                  syncLoad: !this.tileGroupAwaitCovers,
                  onLoaded: () => {
                    if (index === 0) this.tileGroupPendingCovers.delete(`${book.bookUrl}#theme`);
                  },
                  onFailed: () => {
                    if (index === 0) this.tileGroupPendingCovers.delete(`${book.bookUrl}#theme`);
                  } })
                  .width(width)
                  .height(height)
                  .onAppear(() => {
                    if (this.tileGroupAwaitCovers && index === 0) this.tileGroupPendingCovers.add(`${book.bookUrl}#theme`);
                  })
              } else {
                Image(cover)
                  .width(width)
                  .height(height)
                  .objectFit(ImageFit.Fill)
                  // 返回书架后进度变了的卡片会整体重建，封面异步加载会先空一帧；本地封面同步解码，让关书动画落地后无缝。
                  // 打开分组时改后台解码，分组页等开头显示的第一张解码完再浮起。
                  .syncLoad(!this.tileGroupAwaitCovers)
                  .onAppear(() => {
                    if (this.tileGroupAwaitCovers && index === 0) this.tileGroupPendingCovers.add(`${book.bookUrl}#theme`);
                  })
                  .onComplete(() => {
                    if (index === 0) this.tileGroupPendingCovers.delete(`${book.bookUrl}#theme`);
                  })
                  .onError(() => {
                    if (index === 0) this.tileGroupPendingCovers.delete(`${book.bookUrl}#theme`);
                  })
              }
            }, (cover: ResourceStr, index: number) => `${book.bookUrl}_theme_${index}_${this.themeCoverKey(cover)}`)
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
          // 分组开合时新建的封面同步解码：陪伴布局的书底板和书页先画出来，封面晚一两帧就是一本空书一闪。
          .syncLoad(this.shelfCoverSyncLoad(this.imageCover(this.getShelfCover(book, animateCovers)), syncDecode))
          // 打开分组时分组页的封面在后台解码，解码完才淡入（见 afterTileGroupCoversReady）。
          .onAppear(() => this.noteTileGroupCoverMounted(book, this.imageCover(this.getShelfCover(book, animateCovers)),
            this.shelfCoverSyncLoad(this.imageCover(this.getShelfCover(book, animateCovers)), syncDecode)))
          .onComplete(() => this.tileGroupPendingCovers.delete(book.bookUrl))
          .onError(() => this.tileGroupPendingCovers.delete(book.bookUrl))
      } else {
        Swiper() {
          ForEach(this.getShelfCoverList(book), (cover: string) => {
            Image(this.imageCover(cover))
              .width(width)
              .height(height)
              .objectFit(imageFit)
              // 返回书架后进度变了的卡片会整体重建，封面异步加载会先空一帧；本地封面同步解码，让关书动画落地后无缝。
              .syncLoad(this.coverSyncLoadable(this.imageCover(cover)))
          }, (cover: string) => cover)
        }
        .width(width)
        .height(height)
        .autoPlay(true)
        .interval(3500)
        .indicator(false)
        .loop(true)
      }
      // 深色模式调暗封面：盖在图片上、角标和标记之下；主题封面不调暗。
      if (!this.shouldUseThemeBookCover() && this.shelfCoverDimOpacity() > 0) {
        this.shelfCoverDimLayer()
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
      // 分组卡片里的小封面（measure 为 false）不标，分组卡片的本数行另显示“N 本检查中”。
      if (measure && this.shelfRefreshActiveStart(book.bookUrl) > 0) {
        this.shelfRefreshCoverChip(book.bookUrl)
      } else if (measure && this.hasShelfRefreshError(book)) {
        this.shelfRefreshCoverError()
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
    const covers = ThemeBookCoverSettings.covers(book, this.appDarkMode, this.bookshelfCoverMode);
    if (this.animatedImageRevision < 0) return covers;
    const context = getContext(this);
    return covers.map((cover: ResourceStr): ResourceStr =>
      typeof cover === 'string' ? AnimatedImagePolicy.display(context, cover) : cover);
  }

  /** 深色模式调暗封面的遮罩不透明度，0 表示不调暗。 */
  shelfCoverDimOpacity(): number {
    return CoverDimSettings.opacity(this.appDarkMode, this.bookshelfDarkCoverDim, this.bookshelfDarkCoverDimLevel);
  }

  @Builder
  shelfCoverDimLayer() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .opacity(this.shelfCoverDimOpacity())
      .hitTestBehavior(HitTestMode.None)
  }

  shouldUseThemeBookCover(): boolean {
    return ThemeBookCoverSettings.enabled(this.appDarkMode, this.themeBookCoverEnabled);
  }

  /** 轮播项 key 里代表封面图本身的那段：深浅色各有一套封面的主题切换模式时，靠它让轮播换图。 */
  themeCoverKey(cover: ResourceStr): string {
    return typeof cover === 'string' ? cover : `${(cover as Resource).id}`;
  }

  themeBookCoverInterval(book: Book): number {
    return ThemeBookCoverSettings.interval(book);
  }

  activeThemeShelfFrame(): ResourceStr {
    return ThemeBookCoverSettings.frame(this.appDarkMode);
  }

  /** 主题包动图封面、文件夹插画取景时记下的显示区域；没有时按原来的方式整张显示。 */
  themeImageCrop(slot: string, src: ResourceStr): ThemeImageCrop | null {
    return ThemeAssetRegistry.imageCrop(slot, src, this.appDarkMode);
  }

  activeThemeShelfFolder(): ResourceStr {
    return ThemeAssetRegistry.themeShelfFolder(ThemeRuntime.bookTokens(this.appDarkMode).shelfFolderAssetId);
  }

  /** Image 能直接加载的封面地址；加密的书源封面在解密完成前为空。 */
  imageCover(raw: string): string {
    if (this.sourceCoverRevision < 0 || this.animatedImageRevision < 0) return raw;
    const context = getContext(this);
    return AnimatedImagePolicy.display(context, BookCoverCache.displayCover(context, raw));
  }

  /** 只有本地文件和资源能同步解码：网络地址同步加载会在主线程上下载，一屏没缓存的封面就能把界面卡死。 */
  coverSyncLoadable(src: ResourceStr): boolean {
    if (typeof src !== 'string') return true;
    return !!src && !src.startsWith('http://') && !src.startsWith('https://');
  }

  shelfCoverSyncLoad(src: string, syncDecode: boolean): boolean {
    return syncDecode && this.coverSyncLoadable(src);
  }

  /**
   * 分组页建起来之前，把头几屏书的封面换成磁盘上已有的缓存。文件夹里只露三四本，其余的书架上没显示过，
   * 封面还是网络地址：建好后才换成缓存文件、一本本重新加载闪一下。只查磁盘、不下载。
   */
  warmTileGroupCovers(groupId: number): void {
    const privateScope = this.shelfScope === 'private';
    const columns = Math.max(1, this.shelfTileColumnCount());
    const rows = Math.ceil(Math.max(1, this.contextViewportHeight) / Math.max(1, this.shelfTileColumnWidth())) + 1;
    const books = this.sortBooks(this.allBooks.filter((book: Book): boolean =>
      book.group === groupId && book.isPrivate === privateScope)).slice(0, columns * rows);
    const context = getContext(this);
    let nextMap: Map<string, string> | null = null;
    for (const book of books) {
      const covers = this.rawShelfCoverList(book);
      for (let i = 0; i < covers.length; i++) {
        const raw = covers[i];
        if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) continue;
        const key = this.shelfCoverKey(book, i);
        if (this.shelfCoverMap.get(key) && this.shelfCoverRawUrls.get(key) === raw) continue;
        const local = BookCoverCache.resolveCachedCover(context, raw);
        if (!local || local === raw) continue;
        if (!nextMap) nextMap = new Map(this.shelfCoverMap);
        this.shelfCoverRawUrls.set(key, raw);
        nextMap.set(key, local);
      }
    }
    if (nextMap) this.shelfCoverMap = nextMap;
  }

  rawShelfCoverList(book: Book): string[] {
    return CoverGallerySettings.getDisplayCoverList(
      book,
      this.appDarkMode,
      this.bookshelfCoverAlbums,
      this.bookshelfLightCoverAlbumId,
      this.bookshelfDarkCoverAlbumId,
      this.bookshelfCoverApplyScope,
      this.bookshelfCoverTargetBooks,
      this.bookshelfIgnoreSourceCover,
      this.bookshelfCoverMode,
      this.bookshelfIgnoreEmptyCoverOnly
    );
  }

  getShelfCover(book: Book, animateCovers: boolean = true): string {
    const covers = this.getShelfCoverList(book);
    return covers.length > 0 ? (animateCovers ? BookDisplayHelper.pickCover(covers) : covers[0]) : '';
  }

  getShelfCoverList(book: Book): string[] {
    const covers = this.rawShelfCoverList(book);
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
        if (!book.isPrivate && this.matchesShelfGroup(book, this.shelfBaseGroupId())) {
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
    return WebParseSettingsStore.enabled() ? '搜索书籍或添加本地书籍吧' : '添加本地书籍吧';
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

  matchesShelfGroup(book: Book, groupId: number = this.activeShelfGroupId): boolean {
    return groupId === 0 || (groupId === -1 ? book.group <= 0 : book.group === groupId);
  }

  /** 书架底层显示的分组：平铺布局打开分组页时停在进入前的分组上，分组页另成一层。 */
  shelfBaseGroupId(): number {
    return this.isTileGroupPage() ? this.tileGroupBaseGroupId : this.activeShelfGroupId;
  }

  /** 分组页那一层的分类页键 `g<分组>:<类型>`；书架底层直接用类型（或 'private'）作键。 */
  tileGroupPageKey(groupId: number): string {
    return `g${groupId}:${this.shelfScope === 'private' ? 'private' : this.activeShelfTypeTab()}`;
  }

  tileGroupLayerKey(): string {
    return this.tileGroupPageKey(this.tileGroupLayerGroupId);
  }

  tileGroupLayerName(): string {
    const group = this.shelfGroups.find((item: BookGroup) => item.groupId === this.tileGroupLayerGroupId);
    return group ? group.groupName : '书籍分组';
  }

  isTileGroupPageKey(key: string): boolean {
    return /^g\d+:/.test(key);
  }

  /** 这个分类页显示的分组：分组页的键里带着分组，其余是书架底层的分组。 */
  pageGroupId(key: string): number {
    return this.isTileGroupPageKey(key) ? Number(key.substring(1, key.indexOf(':'))) : this.shelfBaseGroupId();
  }

  pageTypeKey(key: string): string {
    return this.isTileGroupPageKey(key) ? key.substring(key.indexOf(':') + 1) : key;
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
    const pages = this.isTileGroupPageKey(key) ? this.tileGroupPages : this.shelfCategoryPages;
    let page = pages.get(key);
    if (!page) {
      page = new ShelfCategoryPage();
      pages.set(key, page);
    }
    const groupId = this.pageGroupId(key);
    const type = this.pageTypeKey(key);
    const privateAllowed = this.privateShelfEnabled &&
      (!this.privateShelfHasPassword || this.privateShelfRevealed || this.shelfScope === 'private');
    const signature = `${this.shelfCategoryRevision}:${groupId}:${this.sortMode}:` +
      `${this.bookshelfLayoutMode}:${this.bookshelfLastReadPinMode}:${this.bookshelfLastReadPinCount}:` +
      `${this.isBookMultiSelect}:${this.shelfFilterKeys}:${this.shelfAppliedSearchKeyword}:${privateAllowed}`;
    if (signature !== page.signature) {
      page.signature = signature;
      page.books = type === 'private' && !privateAllowed ? [] : this.sortBooks(this.allBooks.filter((book: Book): boolean =>
        book.isPrivate === (type === 'private') && this.matchesShelfGroup(book, groupId) &&
        (type === 'all' || type === 'private' || this.shelfBookType(book) === type) &&
        this.matchesShelfFilters(book) && this.matchesShelfSearch(book)));
      if (!this.isTileLayout()) page.listSource.replace(page.books, true);
      else if (this.shouldUseTileGroupFolders(key)) {
        page.entrySource.replace(this.getSortedTileRootEntries(page.books, this.sortMode, key), true);
      } else page.tileSource.replace(this.getTileBooksWithoutLatest(page.books,
        this.getLatestReadTileBooks(page.books), key), true);
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
    return !this.isBookMultiSelect && !this.isTileGroupPage() && this.shelfPageOrder().includes(key);
  }

  /** 当前所在页：分组页、分类栏里的类型，或隐私书架 'private'。 */
  shelfPageKey(): string {
    if (this.isTileGroupPage()) return this.tileGroupPageKey(this.activeShelfGroupId);
    return this.shelfScope === 'private' ? 'private' : this.activeShelfTypeTab();
  }

  /** 左右滑动的页序：分类栏里显示的类型。隐私书架不在页序里，只能双击顶部进出。 */
  shelfPageOrder(): string[] {
    return [...this.shelfTypeTabIds];
  }

  setShelfPage(page: string): void {
    const toPrivate = page === 'private' && this.privateShelfEnabled;
    const nextScope = toPrivate ? 'private' : 'all';
    const nextType = toPrivate ? this.shelfTypeTab : (this.shelfTypeTabIds.indexOf(page) >= 0 ? page : 'all');
    if (this.shelfScope === nextScope && this.shelfTypeTab === nextType) return;
    const typeChanged = this.shelfTypeTab !== nextType;
    const scopeChanged = this.shelfScope !== nextScope;
    this.shelfScope = nextScope;
    this.shelfTypeTab = nextType;
    if (scopeChanged) {
      if (!toPrivate) this.privateShelfRevealed = false;
      this.animatePrivateShelfLayer(toPrivate);
    }
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

  /** 隐私书架唯一的入口：双击顶部标题栏进入（有密码先验证），在隐私书架里双击回到原来的分类。 */
  toggleShelfPrivateByHeaderDoubleTap(): void {
    if (!this.privateShelfEnabled || this.shelfScopeSwapTimer >= 0 || this.shelfScopeFinishTimer >= 0) return;
    if (this.shelfScope === 'private') {
      this.setShelfPage(this.activeShelfTypeTab());
      return;
    }
    if (this.isBookMultiSelect || this.isTileGroupPage()) return;
    if (this.privateShelfHasPassword && !this.privateShelfRevealed) {
      if (this.privateShelfUnlockDialogSession.isOpen() || this.privateShelfBiometricPending ||
        this.privateShelfBiometricQueued) return;
      if (!this.privateShelfBiometric || !BiometricAuth.isAvailable()) this.openPrivateShelfUnlockDialog();
      else if (this.shelfContentTouching) this.privateShelfBiometricQueued = true;
      else this.startPrivateShelfBiometricUnlock(false);
      return;
    }
    this.setShelfPage('private');
  }

  /** 分类栏点选类型；在隐私书架里点任一类型都回到普通书架的该类型。 */
  switchShelfScopeBySelection(page: string): void {
    if (this.shelfScopeSwapTimer >= 0 || this.shelfScopeFinishTimer >= 0) {
      return;
    }
    if (this.shelfScope !== 'private' && page === this.activeShelfTypeTab()) {
      return;
    }
    if (this.canSelectShelfPage(page)) this.setShelfPage(page);
  }

  /**
   * 隐私书架进出：进入时普通书架向外放大淡出，隐私书架从稍小处浮起；退出反过来。
   * 进入先挂上隐私书架层按起点画一帧再动，免得建列表那一帧吃掉动画开头。
   */
  animatePrivateShelfLayer(enter: boolean): void {
    this.clearPrivateShelfLayerTimer();
    const generation = ++this.privateShelfLayerGeneration;
    if (enter) {
      this.privateShelfLayerMounted = true;
      this.privateShelfLayerTimer = setTimeout(() => {
        this.privateShelfLayerTimer = -1;
        if (generation !== this.privateShelfLayerGeneration) return;
        this.getUIContext().animateTo({
          duration: PRIVATE_SHELF_ENTER_DURATION, curve: curves.cubicBezierCurve(0.2, 0, 0, 1),
          expectedFrameRateRange: SHELF_GROUP_FRAME_RATE
        }, () => {
          this.privateShelfLayerProgress = 1;
        });
        this.privateShelfLayerTimer = setTimeout(() => {
          this.privateShelfLayerTimer = -1;
          if (generation === this.privateShelfLayerGeneration) this.privateShelfLayerCovering = true;
        }, PRIVATE_SHELF_ENTER_DURATION);
      }, PRIVATE_SHELF_PREMOUNT_DELAY);
      return;
    }
    this.privateShelfLayerCovering = false;
    this.getUIContext().animateTo({
      duration: PRIVATE_SHELF_EXIT_DURATION, curve: curves.cubicBezierCurve(0.2, 0, 0, 1),
      expectedFrameRateRange: SHELF_GROUP_FRAME_RATE
    }, () => {
      this.privateShelfLayerProgress = 0;
    });
    // 不靠 onFinish 卸下：切到后台时回调可能丢，隐私书架层会一直挂着。
    this.privateShelfLayerTimer = setTimeout(() => {
      this.privateShelfLayerTimer = -1;
      if (generation === this.privateShelfLayerGeneration) this.privateShelfLayerMounted = false;
    }, PRIVATE_SHELF_EXIT_DURATION);
  }

  clearPrivateShelfLayerTimer(): void {
    if (this.privateShelfLayerTimer >= 0) {
      clearTimeout(this.privateShelfLayerTimer);
      this.privateShelfLayerTimer = -1;
    }
  }

  /** 普通书架：隐私书架展开时向外放大。 */
  privateShelfOuterScale(): number {
    return 1 + 0.06 * this.privateShelfLayerProgress;
  }

  /** 隐私书架：从 0.94 浮到原大。 */
  privateShelfInnerScale(): number {
    return 0.94 + 0.06 * this.privateShelfLayerProgress;
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
      // 没申请到时登记仍然保留，许可那边会自己重试。
      this.fullTextCacheBackgroundRunning = true;
      await BackgroundPermit.acquire(getContext(this) as common.UIAbilityContext, 'shelf-cache', 'dataTransfer', agent);
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
      await BackgroundPermit.release('shelf-cache');
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

  /** 下拉松手：书架立刻弹回，检查放到后台；已在检查（含冷启动静默刷新）时只亮出胶囊并弹一下。 */
  onShelfPullRefresh(): void {
    // 等 Refresh 把 refreshing 双向写成 true 之后再收回，否则可能被它覆盖、列表停在下拉位置。
    setTimeout(() => {
      this.isShelfRefreshing = false;
    }, 0);
    if (this.shelfRefreshRunning) {
      this.showShelfRefreshCapsule();
      this.bumpShelfRefreshCapsule();
      return;
    }
    this.refreshBookshelfToc();
  }

  async refreshBookshelfToc(silent: boolean = false): Promise<void> {
    if (this.shelfRefreshRunning) {
      if (!silent) {
        this.showShelfRefreshCapsule();
        this.bumpShelfRefreshCapsule();
      }
      return;
    }
    if (!silent && this.shelfShowsLocalOnly()) {
      await this.refreshLocalBooks();
      return;
    }
    const shelfBooks = silent ? [...this.allBooks] : [...this.books];
    let skippedFinished = 0;
    const targets = shelfBooks.filter((book: Book) => {
      if (!book.bookUrl || LocalBookService.isLocalBook(book) || !book.canUpdate) return false;
      if (this.isFinishedBook(book)) {
        skippedFinished++;
        return false;
      }
      return true;
    });
    if (targets.length === 0) {
      if (!silent && shelfBooks.length > 0) {
        HdsFeedback.showToast(skippedFinished > 0 ? `没有可刷新的连载书籍，已跳过${skippedFinished}本完结` :
          '没有可刷新的网络书籍');
      }
      return;
    }
    this.shelfRefreshRunning = true;
    this.shelfRefreshTotal = targets.length;
    this.shelfRefreshChecked = 0;
    this.shelfRefreshActive = [];
    this.shelfRefreshFailures = [];
    this.shelfRefreshFailedUrls = [];
    this.startShelfRefreshTicker();
    if (!silent) {
      this.showShelfRefreshCapsule();
    }
    const refreshStartedAt = Date.now();
    let updated = 0;
    let failed = 0;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const pending: Book[] = [...targets];
      const sourceActive: Map<string, number> = new Map();
      let waiters: (() => void)[] = [];
      const takeNext = (): Book | null => {
        const index = pending.findIndex((book: Book): boolean =>
          (sourceActive.get(book.origin) || 0) < SHELF_REFRESH_PER_SOURCE);
        if (index < 0) return null;
        const book = pending.splice(index, 1)[0];
        sourceActive.set(book.origin, (sourceActive.get(book.origin) || 0) + 1);
        return book;
      };
      const release = (origin: string): void => {
        sourceActive.set(origin, Math.max(0, (sourceActive.get(origin) || 0) - 1));
        const woken = waiters;
        waiters = [];
        woken.forEach((wake: () => void) => wake());
      };
      const runWorker = async (): Promise<void> => {
        // 每路一个引擎：引擎持有当前书的目录与会话，不能在两本书之间共用。
        let engine = ReadBookEngine.createBackgroundWorker();
        engine.chapterUpdateBatchTime = refreshStartedAt;
        while (pending.length > 0) {
          const shelfBook = takeNext();
          if (!shelfBook) {
            // 剩下的书所属书源都已满额，等任意一本刷完再挑。
            await new Promise<void>((resolve: () => void) => {
              waiters.push(resolve);
            });
            continue;
          }
          this.beginShelfRefreshBook(shelfBook);
          try {
            const result = await this.runShelfRefreshBook(engine, db, shelfBook, refreshStartedAt);
            if (result.abandoned) {
              // 旧引擎可能还卡在这本书上，丢给它自己跑完，这一路换新的。
              engine = ReadBookEngine.createBackgroundWorker();
              engine.chapterUpdateBatchTime = refreshStartedAt;
            }
            if (result.error) {
              failed++;
              console.error('刷新书架目录失败:', shelfBook.name, result.error);
              await this.recordShelfRefreshFailure(db, shelfBook, result.error);
            } else if (result.updated) {
              updated++;
            }
          } finally {
            this.shelfRefreshChecked++;
            this.endShelfRefreshBook(shelfBook.bookUrl);
            release(shelfBook.origin);
          }
        }
      };
      const workers: Promise<void>[] = [];
      const workerCount = Math.min(SHELF_REFRESH_CONCURRENCY, targets.length);
      for (let i = 0; i < workerCount; i++) {
        workers.push(runWorker());
      }
      await Promise.all(workers);
      await this.loadBooks();
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      this.finishShelfRefreshCapsule(updated > 0 ? `${updated} 本有更新` : '没有新章节',
        failed > 0 ? ` · ${failed} 本失败` : '');
    } catch (e) {
      console.error('刷新书架失败:', e);
      if (this.shelfRefreshCapsuleVisible) {
        this.hideShelfRefreshCapsule();
        HdsFeedback.showToast('书架刷新失败');
      }
    } finally {
      this.shelfRefreshRunning = false;
      this.shelfRefreshStatus = RefreshStatus.Inactive;
      this.shelfRefreshActive = [];
      this.shelfRefreshCancels.clear();
      this.stopShelfRefreshTicker();
    }
  }

  /** 刷一本书，带超时与手动跳过；被放弃时 refreshShelfBookToc 仍在后台跑，晚到的结果照常落库。 */
  async runShelfRefreshBook(engine: ReadBookEngine, db: AppDatabase, shelfBook: Book,
    refreshStartedAt: number): Promise<ShelfRefreshResult> {
    let timer: number = -1;
    const cancelled = new Promise<ShelfRefreshResult>((resolve: (result: ShelfRefreshResult) => void) => {
      const cancel = (reason: string): void => resolve(new ShelfRefreshResult(false, reason, true));
      this.shelfRefreshCancels.set(shelfBook.bookUrl, cancel);
      timer = setTimeout(() => cancel(`${Math.round(SHELF_REFRESH_BOOK_TIMEOUT_MS / 1000)} 秒未返回`),
        SHELF_REFRESH_BOOK_TIMEOUT_MS);
    });
    const work = this.refreshShelfBookToc(engine, db, shelfBook, refreshStartedAt)
      .then((updated: boolean): ShelfRefreshResult => new ShelfRefreshResult(updated, '', false))
      .catch((e: Error): ShelfRefreshResult => new ShelfRefreshResult(false, this.shelfRefreshErrorText(e), false));
    try {
      return await Promise.race([work, cancelled]);
    } finally {
      clearTimeout(timer);
      this.shelfRefreshCancels.delete(shelfBook.bookUrl);
    }
  }

  shelfRefreshErrorText(e: Error): string {
    const message = (e && e.message ? e.message : `${e}`).replace(/\s+/g, ' ').trim();
    if (!message || message === 'undefined' || message === '[object Object]') return '规则出错';
    return message.length > 24 ? `${message.substring(0, 24)}…` : message;
  }

  /** 记下失败原因：落库给下次打开书架用，同时立刻在封面上标出。 */
  async recordShelfRefreshFailure(db: AppDatabase, shelfBook: Book, reason: string): Promise<void> {
    this.shelfRefreshFailures = [...this.shelfRefreshFailures, new ShelfRefreshFailure(shelfBook, reason)];
    if (!this.shelfRefreshFailedUrls.includes(shelfBook.bookUrl)) {
      this.shelfRefreshFailedUrls = [...this.shelfRefreshFailedUrls, shelfBook.bookUrl];
    }
    try {
      const current = await db.getBook(shelfBook.bookUrl);
      if (!current) return;
      current.putVariable(SHELF_REFRESH_ERROR_VARIABLE, reason);
      await db.updateBook(current, false, 'shelf_refresh_failed');
    } catch (e) {
      console.error('记录书架检查失败原因失败:', shelfBook.name, e);
    }
  }

  beginShelfRefreshBook(book: Book): void {
    this.shelfRefreshActive = [...this.shelfRefreshActive, new ShelfRefreshActiveBook(book, Date.now())];
  }

  endShelfRefreshBook(bookUrl: string): void {
    this.shelfRefreshActive = this.shelfRefreshActive.filter((item: ShelfRefreshActiveBook): boolean =>
      item.book.bookUrl !== bookUrl);
  }

  /** 清单里的“跳过”：这本算失败，这一路马上去查下一本。 */
  skipShelfRefreshBook(bookUrl: string): void {
    const cancel = this.shelfRefreshCancels.get(bookUrl);
    if (cancel) cancel('已跳过');
  }

  startShelfRefreshTicker(): void {
    this.stopShelfRefreshTicker();
    this.shelfRefreshNow = Date.now();
    this.shelfRefreshTicker = setInterval(() => {
      this.shelfRefreshNow = Date.now();
    }, 1000);
  }

  stopShelfRefreshTicker(): void {
    if (this.shelfRefreshTicker >= 0) {
      clearInterval(this.shelfRefreshTicker);
      this.shelfRefreshTicker = -1;
    }
  }

  /** 正在查时返回开始时间，否则 0。 */
  shelfRefreshActiveStart(bookUrl: string): number {
    const item = this.shelfRefreshActive.find((entry: ShelfRefreshActiveBook): boolean => entry.book.bookUrl === bookUrl);
    return item ? item.startedAt : 0;
  }

  shelfRefreshElapsed(startedAt: number): number {
    return startedAt > 0 ? Math.max(0, this.shelfRefreshNow - startedAt) : 0;
  }

  shelfRefreshElapsedText(startedAt: number): string {
    return `${Math.floor(this.shelfRefreshElapsed(startedAt) / 1000)}秒`;
  }

  shelfRefreshErrorReason(book: Book): string {
    const failure = this.shelfRefreshFailures.find((item: ShelfRefreshFailure): boolean =>
      item.book.bookUrl === book.bookUrl);
    if (failure && this.shelfRefreshFailedUrls.includes(book.bookUrl)) return failure.reason;
    return book.getVariable(SHELF_REFRESH_ERROR_VARIABLE) || '';
  }

  hasShelfRefreshError(book: Book): boolean {
    return this.shelfRefreshFailedUrls.includes(book.bookUrl) || !!book.getVariable(SHELF_REFRESH_ERROR_VARIABLE);
  }

  /** 点开书或换源后清掉失败标记。 */
  clearShelfRefreshError(bookUrl: string): void {
    this.shelfRefreshFailedUrls = this.shelfRefreshFailedUrls.filter((url: string): boolean => url !== bookUrl);
    const book = this.allBooks.find((item: Book): boolean => item.bookUrl === bookUrl);
    if (book && book.getVariable(SHELF_REFRESH_ERROR_VARIABLE)) {
      book.putVariable(SHELF_REFRESH_ERROR_VARIABLE, '');
    }
    const persist = async (): Promise<void> => {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const current = await db.getBook(bookUrl);
      if (!current || !current.getVariable(SHELF_REFRESH_ERROR_VARIABLE)) return;
      current.putVariable(SHELF_REFRESH_ERROR_VARIABLE, '');
      await db.updateBook(current, false, 'shelf_refresh_error_cleared');
    };
    persist().catch((e: Error) => console.error('清除书架检查失败标记失败:', bookUrl, e));
  }

  /** 刷新一本书的目录并记下检查结果与更新角标；返回这次是否发现新章节。 */
  async refreshShelfBookToc(engine: ReadBookEngine, db: AppDatabase, shelfBook: Book,
    refreshStartedAt: number): Promise<boolean> {
    const freshBook = await db.getBook(shelfBook.bookUrl) || shelfBook;
    const beforeUpdateTime = BookshelfSortHelper.getBookUpdateTime(freshBook);
    const hadPendingUpdate = this.hasShelfBookUpdate(freshBook);
    await engine.openBook(freshBook);
    await engine.refreshToc();
    const refreshedBook = await db.getBook(shelfBook.bookUrl);
    if (!refreshedBook) return false;
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
    refreshedBook.putVariable(SHELF_REFRESH_ERROR_VARIABLE, '');
    await db.updateBook(refreshedBook);
    return hasNewUpdate;
  }

  async refreshLocalBooks(): Promise<void> {
    this.shelfRefreshRunning = true;
    this.shelfRefreshTotal = 0;
    this.shelfRefreshChecked = 0;
    this.shelfRefreshCapsuleText = '正在刷新本地书籍';
    this.showShelfRefreshCapsule();
    try {
      await this.loadBooks();
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      this.finishShelfRefreshCapsule('本地书架已刷新', '');
    } catch (e) {
      console.error('刷新本地书籍失败:', e);
      this.hideShelfRefreshCapsule();
      HdsFeedback.showToast('本地书架刷新失败');
    } finally {
      this.shelfRefreshRunning = false;
      this.shelfRefreshStatus = RefreshStatus.Inactive;
    }
  }

  /** 胶囊跟随的标题行收起量；分组页标题栏不收起。 */
  shelfRefreshCapsuleCollapse(): number {
    return this.isTileGroupPage() ? 0 : this.shelfHeaderCollapseValue();
  }

  showShelfRefreshCapsule(): void {
    this.clearShelfRefreshCapsuleTimer();
    this.shelfRefreshSummaryPending = false;
    this.shelfRefreshCapsuleDone = false;
    if (this.shelfRefreshCapsuleVisible) return;
    animateTo({ curve: curves.springMotion(0.42, 0.82) }, () => {
      this.shelfRefreshCapsuleVisible = true;
    });
  }

  /** 显示完成结果；标题行收着（胶囊随之隐藏）时先挂起，等标题行完整展开再显示。 */
  finishShelfRefreshCapsule(text: string, subText: string): void {
    if (!this.shelfRefreshCapsuleVisible) return;
    this.shelfRefreshCapsuleText = text;
    this.shelfRefreshCapsuleSubText = subText;
    this.shelfRefreshCapsuleDone = true;
    if (this.shelfRefreshCapsuleCollapse() >= CollapsingHeader.DISTANCE / 2) {
      this.shelfRefreshSummaryPending = true;
      return;
    }
    this.revealShelfRefreshSummary();
  }

  revealShelfRefreshSummary(): void {
    this.shelfRefreshSummaryPending = false;
    this.bumpShelfRefreshCapsule();
    this.clearShelfRefreshCapsuleTimer();
    // 清单开着时等它关掉再收（见 closeShelfRefreshSheet）；有失败的书多留一会儿，方便点开看是哪几本。
    if (this.shelfRefreshSheetVisible) return;
    this.shelfRefreshCapsuleTimer = setTimeout(() => {
      this.shelfRefreshCapsuleTimer = -1;
      this.hideShelfRefreshCapsule();
    }, this.shelfRefreshFailures.length > 0 ? 4000 : 2400);
  }

  hideShelfRefreshCapsule(): void {
    this.clearShelfRefreshCapsuleTimer();
    this.shelfRefreshSummaryPending = false;
    if (!this.shelfRefreshCapsuleVisible) return;
    animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, () => {
      this.shelfRefreshCapsuleVisible = false;
    });
  }

  clearShelfRefreshCapsuleTimer(): void {
    if (this.shelfRefreshCapsuleTimer >= 0) {
      clearTimeout(this.shelfRefreshCapsuleTimer);
      this.shelfRefreshCapsuleTimer = -1;
    }
  }

  bumpShelfRefreshCapsule(): void {
    if (!this.shelfRefreshCapsuleVisible) return;
    animateTo({
      duration: 140, curve: Curve.FastOutSlowIn, onFinish: () => {
        animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
          this.shelfRefreshCapsuleScale = 1;
        });
      }
    }, () => {
      this.shelfRefreshCapsuleScale = 1.08;
    });
  }

  onShelfHeaderCollapseChanged(): void {
    if (this.shelfRefreshSummaryPending && this.shelfRefreshCapsuleCollapse() === 0) {
      this.revealShelfRefreshSummary();
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
    if (this.isShelfRefreshing) {
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
      // 只收起“下拉检查更新”；“松手检查更新”阶段往回推仍会刷新，提示要留着。
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
    if (state === RefreshStatus.Inactive) {
      this.shelfRefreshPullOffset = 0;
    }
    if (state === RefreshStatus.OverDrag && this.shelfRefreshStatus === RefreshStatus.Drag) {
      ReaderHaptics.uiTick();
    }
    this.shelfRefreshStatus = state;
    if (this.shelfRefreshRunning) {
      this.shelfRefreshPrompt = '正在检查';
      return;
    }
    if (state === RefreshStatus.Refresh || state === RefreshStatus.Done) {
      // 松手后书架立刻弹回，提示停在“松手”那一句跟着淡出。
      return;
    }
    const localOnly = this.shelfShowsLocalOnly();
    if (state === RefreshStatus.OverDrag) {
      this.shelfRefreshPrompt = localOnly ? '松手刷新' : '松手检查更新';
    } else {
      this.shelfRefreshPrompt = localOnly ? '下拉刷新' : '下拉检查更新';
    }
  }

  shouldShowShelfRefreshStatus(): boolean {
    if (this.shelfRefreshPullRetracting) return false;
    if (this.shelfRefreshStatus === RefreshStatus.Drag || this.shelfRefreshStatus === RefreshStatus.OverDrag) {
      return true;
    }
    // 弹回途中按下拉距离淡出，回到原位即消失。
    return (this.shelfRefreshStatus === RefreshStatus.Refresh || this.shelfRefreshStatus === RefreshStatus.Done) &&
      this.shelfRefreshPullOffset > 1;
  }

  /** 翻书指示：0 合拢，1 到达松手线完全翻开。 */
  shelfRefreshPullProgress(): number {
    return Math.max(0, Math.min(1, this.shelfRefreshPullOffset / SHELF_REFRESH_TRIGGER_OFFSET));
  }

  shelfRefreshPullOver(): boolean {
    return this.shelfRefreshStatus === RefreshStatus.OverDrag ||
      this.shelfRefreshPullOffset >= SHELF_REFRESH_TRIGGER_OFFSET;
  }

  shelfRefreshIndicatorColor(): ResourceColor {
    return this.shelfRefreshPullOver() ? this.accentColor() : this.secondaryTextColor();
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

  /** 翻书指示的一页：从书脊处按下拉进度展开到 angle 度。angle 只传常量，进度在这里读状态。 */
  @Builder
  shelfRefreshFanPage(angle: number) {
    Column()
      .width(2)
      .height(16)
      .borderRadius(1)
      .backgroundColor(this.shelfRefreshIndicatorColor())
      .rotate({ angle: angle * this.shelfRefreshPullProgress(), centerX: '50%', centerY: '100%' })
      .margin({ bottom: 3 })
  }

  @Builder
  shelfRefreshPullIndicator() {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        this.shelfRefreshFanPage(-62)
        this.shelfRefreshFanPage(-31)
        this.shelfRefreshFanPage(0)
        this.shelfRefreshFanPage(31)
        this.shelfRefreshFanPage(62)
        Row()
          .width(26)
          .height(2.4)
          .borderRadius(1.2)
          .backgroundColor(this.shelfRefreshIndicatorColor())
      }
      .width(36)
      .height(30)
      Text(this.shelfRefreshPrompt)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
        .maxLines(1)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    // 指示放在顶栏下方露出的空隙里居中，不随 Refresh 的 builder 穿过毛玻璃顶栏。
    .position({
      x: 0,
      y: this.bookshelfTopOverlayHeight(this.shelfPageKey()) +
        Math.max(0, (this.shelfRefreshPullOffset - SHELF_REFRESH_INDICATOR_HEIGHT) / 2)
    })
    .opacity(Math.min(1, this.shelfRefreshPullProgress() * 1.4))
    .zIndex(3)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }

  /** 进度胶囊文字：检查中显示进度，完成或只刷本地书时显示 shelfRefreshCapsuleText。 */
  shelfRefreshCapsuleLabel(): string {
    if (this.shelfRefreshCapsuleDone || this.shelfRefreshTotal <= 0) return this.shelfRefreshCapsuleText;
    return `检查更新 ${this.shelfRefreshChecked}/${this.shelfRefreshTotal}`;
  }

  @Builder
  shelfRefreshCapsule() {
    Row() {
      Stack() {
        ImmersiveMaterialSurface({
          surfaceWidth: Math.max(SHELF_REFRESH_CAPSULE_HEIGHT, this.shelfRefreshCapsuleWidth),
          surfaceHeight: SHELF_REFRESH_CAPSULE_HEIGHT,
          darkMode: this.appDarkMode,
          fallbackColor: this.cardColor(),
          glowColor: this.accentGlowColor()
        }) {
          Row().width('100%').height('100%')
        }
        Row({ space: AppSpacing.SM }) {
          if (this.shelfRefreshCapsuleDone) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor([this.accentColor()])
          } else if (this.shelfRefreshTotal > 0) {
            Progress({ value: this.shelfRefreshChecked, total: this.shelfRefreshTotal, type: ProgressType.Ring })
              .width(16)
              .height(16)
              .color(this.accentColor())
              .style({ strokeWidth: 2.4 })
          } else {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(this.accentColor())
          }
          Text(this.shelfRefreshCapsuleLabel())
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
          if (this.shelfRefreshCapsuleDone && this.shelfRefreshCapsuleSubText) {
            Text(this.shelfRefreshCapsuleSubText)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.secondaryTextColor())
              .maxLines(1)
          }
          if (this.shelfRefreshTotal > 0) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([this.secondaryTextColor()])
              .rotate({ angle: this.shelfRefreshSheetVisible ? 180 : 0 })
              .animation({ duration: 200, curve: Curve.FastOutSlowIn })
          }
        }
        .height(SHELF_REFRESH_CAPSULE_HEIGHT)
        .padding({ left: 10, right: this.shelfRefreshTotal > 0 ? 10 : 14 })
        .alignItems(VerticalAlign.Center)
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          const width = this.areaDimension(newValue.width);
          if (width > 0 && Math.abs(width - this.shelfRefreshCapsuleWidth) >= 0.5) {
            this.shelfRefreshCapsuleWidth = width;
          }
        })
      }
      .scale({ x: this.shelfRefreshCapsuleScale, y: this.shelfRefreshCapsuleScale })
      // 只有胶囊本身可点（展开清单）；标题行收着、胶囊淡没时不挡住下面的书。
      .hitTestBehavior(this.shelfRefreshTotal > 0 &&
        this.shelfRefreshCapsuleCollapse() < CollapsingHeader.DISTANCE / 2 ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => this.toggleShelfRefreshSheet())
      .bindPopup(this.shelfRefreshSheetVisible, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
        (): void => {
          this.shelfRefreshSheet()
        }, Placement.Bottom, this.appDarkMode, this.accentColor(), () => {
          if (this.shelfRefreshSheetVisible) this.closeShelfRefreshSheet();
        }))
      .accessibilityText(this.shelfRefreshCapsuleLabel() +
        (this.shelfRefreshCapsuleDone ? this.shelfRefreshCapsuleSubText : ''))
      .accessibilityDescription(this.shelfRefreshTotal > 0 ? '点按查看正在检查和失败的书' : '')
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    // 跟标题行一起收起：同步上移收起量，并用标题文字同一条淡出曲线，不会滑进状态栏。
    .position({ x: 0, y: this.bookshelfTopOverlayHeight(this.shelfPageKey()) + AppSpacing.SM })
    .translate({ y: -this.shelfRefreshCapsuleCollapse() })
    .opacity(CollapsingHeader.contentOpacity(this.shelfRefreshCapsuleCollapse()))
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -10 }))
      .combine(TransitionEffect.scale({ x: 0.88, y: 0.88, centerX: '50%', centerY: '0%' })))
    .zIndex(3)
    // 整行自身不接触摸，只有胶囊接（见上）。
    .hitTestBehavior(HitTestMode.None)
  }

  toggleShelfRefreshSheet(): void {
    if (this.shelfRefreshSheetVisible) {
      this.closeShelfRefreshSheet();
      return;
    }
    if (this.shelfRefreshTotal <= 0) return;
    // 清单开着时结果胶囊不自动收起，关掉清单后再收。
    this.clearShelfRefreshCapsuleTimer();
    this.shelfRefreshSheetVisible = true;
  }

  closeShelfRefreshSheet(): void {
    this.shelfRefreshSheetVisible = false;
    if (this.shelfRefreshCapsuleDone && !this.shelfRefreshRunning && this.shelfRefreshCapsuleVisible &&
      !this.shelfRefreshSummaryPending && this.shelfRefreshCapsuleTimer < 0) {
      this.shelfRefreshCapsuleTimer = setTimeout(() => {
        this.shelfRefreshCapsuleTimer = -1;
        this.hideShelfRefreshCapsule();
      }, 1200);
    }
  }

  /** 正在查的书按开始时间排，最久的在上面。 */
  shelfRefreshActiveSorted(): ShelfRefreshActiveBook[] {
    return [...this.shelfRefreshActive].sort((a: ShelfRefreshActiveBook, b: ShelfRefreshActiveBook): number =>
      a.startedAt - b.startedAt);
  }

  shelfRefreshQueuedCount(): number {
    return Math.max(0, this.shelfRefreshTotal - this.shelfRefreshChecked - this.shelfRefreshActive.length);
  }

  shelfRefreshStuckColor(): string {
    return this.appDarkMode ? '#F0A63A' : '#C77700';
  }

  /** 封面正中的检查圆钮：转圈，查得久了变橙并显示秒数。bookUrl 只作查找键，状态在这里现读。 */
  @Builder
  shelfRefreshCoverChip(bookUrl: string) {
    Row({ space: 4 }) {
      LoadingProgress()
        .width(16)
        .height(16)
        .color('#FFFFFF')
      if (this.shelfRefreshElapsed(this.shelfRefreshActiveStart(bookUrl)) >= SHELF_REFRESH_STUCK_MS) {
        Text(this.shelfRefreshElapsedText(this.shelfRefreshActiveStart(bookUrl)))
          .fontSize(AppFontSize.MICRO)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .fontFeature('"tnum" on')
          .maxLines(1)
      }
    }
    .height(28)
    .constraintSize({ minWidth: 28 })
    .padding({ left: 6, right: 6 })
    .borderRadius(14)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.shelfRefreshElapsed(this.shelfRefreshActiveStart(bookUrl)) >= SHELF_REFRESH_STUCK_MS ?
      SHELF_REFRESH_STUCK_COLOR : '#73000000')
    .hitTestBehavior(HitTestMode.None)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
      .animation({ duration: 200, curve: Curve.FastOutSlowIn }))
    .accessibilityText(`正在检查更新，已用${this.shelfRefreshElapsedText(this.shelfRefreshActiveStart(bookUrl))}`)
  }

  @Builder
  shelfRefreshCoverError() {
    Text('!')
      .width(22)
      .height(22)
      .borderRadius(11)
      .textAlign(TextAlign.Center)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .backgroundColor(SHELF_REFRESH_ERROR_COLOR)
      .hitTestBehavior(HitTestMode.None)
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
        .animation({ duration: 240, curve: curves.springMotion(0.36, 0.7) }))
      .accessibilityText('上次检查更新失败，长按可换规则')
  }

  @Builder
  shelfRefreshThumb(book: Book) {
    Stack() {
      if (this.getShelfCoverList(book).length === 0) {
        Text(book.name ? book.name.substring(0, 1) : '书')
          .fontSize(12)
          .fontColor('#FFFFFF')
      } else {
        Image(this.imageCover(this.getShelfCover(book, false)))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
        if (this.shelfCoverDimOpacity() > 0) {
          this.shelfCoverDimLayer()
        }
      }
    }
    .width(24)
    .height(32)
    .borderRadius(3)
    .clip(true)
    .backgroundColor(this.getShelfCoverList(book).length === 0 ? this.getBookColor(book.name) : this.inputColor())
  }

  @Builder
  shelfRefreshSheetHeader(left: string, right: string) {
    Row() {
      Text(left)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
      Blank()
      Text(right)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  /** 点胶囊展开的清单：正在查的书（查久了可跳过）与本轮失败的书（点一行去换源）。 */
  @Builder
  shelfRefreshSheet() {
    Scroll() {
      Column() {
        this.shelfRefreshSheetHeader(`正在检查 ${this.shelfRefreshActive.length}`,
          this.shelfRefreshRunning ? `排队 ${this.shelfRefreshQueuedCount()}` : '')
        if (this.shelfRefreshActive.length === 0) {
          Text(this.shelfRefreshRunning ? '正在准备…' : '全部查完')
            .width('100%')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.secondaryTextColor())
            .padding({ top: 4, bottom: 6 })
        }
        ForEach(this.shelfRefreshActiveSorted(), (item: ShelfRefreshActiveBook) => {
          Row({ space: AppSpacing.SM }) {
            this.shelfRefreshThumb(item.book)
            Column() {
              Text(item.book.name)
                .fontSize(AppFontSize.BODY)
                .fontColor(this.primaryTextColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text((item.book.originName || item.book.origin || '').trim())
                .fontSize(AppFontSize.MICRO)
                .fontColor(this.secondaryTextColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.shelfRefreshElapsedText(item.startedAt))
              .fontSize(AppFontSize.CAPTION)
              .fontWeight(this.shelfRefreshElapsed(item.startedAt) >= SHELF_REFRESH_STUCK_MS ? FontWeight.Medium :
                FontWeight.Regular)
              .fontColor(this.shelfRefreshElapsed(item.startedAt) >= SHELF_REFRESH_STUCK_MS ?
                this.shelfRefreshStuckColor() : this.secondaryTextColor())
              .fontFeature('"tnum" on')
            if (this.shelfRefreshElapsed(item.startedAt) >= SHELF_REFRESH_STUCK_MS) {
              Text('跳过')
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.accentColor())
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .borderRadius(12)
                .border({ width: 1, color: this.glassBorderColor() })
                .onClick(() => this.skipShelfRefreshBook(item.book.bookUrl))
                .accessibilityText(`跳过${item.book.name}`)
            }
          }
          .width('100%')
          .height(44)
        }, (item: ShelfRefreshActiveBook) => `active_${item.book.bookUrl}`)
        if (this.shelfRefreshFailures.length > 0) {
          this.shelfRefreshSheetHeader(`失败 ${this.shelfRefreshFailures.length}`, '点一行去换规则')
          ForEach(this.shelfRefreshFailures, (item: ShelfRefreshFailure) => {
            Row({ space: AppSpacing.SM }) {
              this.shelfRefreshThumb(item.book)
              Column() {
                Text(item.book.name)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(this.primaryTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${(item.book.originName || item.book.origin || '').trim()} · ${item.reason}`)
                  .fontSize(AppFontSize.MICRO)
                  .fontColor(SHELF_REFRESH_ERROR_COLOR)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
                .fontSize(14)
                .fontColor([this.secondaryTextColor()])
            }
            .width('100%')
            .height(44)
            .onClick(() => {
              const book = item.book;
              this.closeShelfRefreshSheet();
              setTimeout(() => this.openShelfChangeSource(book), 0);
            })
          }, (item: ShelfRefreshFailure) => `failed_${item.book.bookUrl}`)
        }
      }
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
    }
    .width(Math.min(340, this.contextViewportWidth - 32))
    .constraintSize({ maxHeight: 420 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
  }

  /** 从筛选菜单的“搜索书架”展开，边输入边筛当前书架；“取消”清空关键词并收起。 */
  @Builder
  shelfSearchBar() {
    Row({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
        TextInput({ text: this.shelfSearchKeyword, placeholder: '书名、作者、规则或标签' })
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

  /** 书架底层的分类栏（分组页那一层没有分类栏）。 */
  showsShelfScopeTabs(): boolean {
    return this.bookshelfTypeCategoryEnabled && !this.isBookMultiSelect;
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
      this.shelfFilterSubpage('规则', SHELF_FILTER_ORIGIN_PREFIX, this.shelfOriginFilterOptions(), '当前书架没有网络书籍')
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
      this.filterSubpageEntry('规则', 'origin', SHELF_FILTER_ORIGIN_PREFIX)

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

  /**
   * 书架和分组页的标题栏各有一个；只有当前那一层的按钮挂菜单，免得两处同时弹出。
   * @Builder 按值传参不随状态刷新，所以只传固定的“属于哪一层”，当前在哪一层在这里现读。
   */
  @Builder
  shelfMoreButton(onGroupLayer: boolean) {
    Row() {
      this.shelfHeaderCircleButton($r('sys.symbol.more'), this.showShelfMoreMenu, '更多操作', () => {
        this.shelfMoreMenuPage = '';
        this.showShelfMoreMenu = !this.showShelfMoreMenu;
        this.showShelfFilterMenu = false;
        this.showShelfGroupMenu = false;
      })
    }
    .bindPopup(this.showShelfMoreMenu && onGroupLayer === this.isTileGroupPage(),this.shelfMenuPopupOptions((): void => {
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

  /** 继续卡片上的动作文案按书的类型区分：有声书是听、视频是观看、漫画是翻看、其余是读。 */
  shelfContinueActionText(book: Book): string {
    if (BookTypeSupport.isAudio(book)) return '继续收听';
    if (BookTypeSupport.isVideo(book)) return '继续观看';
    if (this.isShelfComicBook(book)) return '继续翻看';
    return '继续阅读';
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
