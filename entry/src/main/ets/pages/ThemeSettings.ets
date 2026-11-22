import { MembershipBadge } from '../components/common/MembershipBadge';
import { promptAction, router, SymbolGlyphModifier } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { AppIconManager } from '../utils/AppIconManager';
import { AppIconSettingsStore } from '../utils/AppIconSettingsStore';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderThemeHelper } from '../utils/ReaderThemeHelper';
import { syncSystemBars } from '../utils/SystemBars';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { ThemeTrialManager } from '../utils/ThemeTrialManager';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../utils/CustomThemeSchemeStore';
import { SchemeAssetService } from '../utils/SchemeAssetService';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ThemeModeSwitch } from '../components/theme/ThemeModeSwitch';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRecentStore } from '../utils/ThemeRecentStore';
import { ReaderThemeBackground } from '../components/ReaderThemeBackground';
import { ThemeDetailScene } from '../components/theme/ThemeDetailScene';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import {
  BubbleFrameBreak,
  BubbleFrameRepeat,
  normalizeChapterHead,
  ThemeImageCrop,
  ThemePackageBubble,
  ThemePackageChapterHead
} from '../theme/share/ThemePackageFormat';
import {
  ThemeChapterHeadSampleMetrics,
  ThemeChapterHeadTitle,
  ThemeDropCapParagraph
} from '../components/theme/ThemeChapterHeadSample';
import { ThemeBubbleFramePreview } from '../components/theme/ThemeBubbleFramePreview';
import { BubbleFramePreviewPart } from '../components/theme/BubbleFramePreviewPainter';
import { ThemeCroppedImage } from '../components/theme/ThemeCroppedImage';
import { SuperExclusiveThemes, ThemeIds, ThemePack, ThemeColorTokens, ThemeRegexEmphasisModes, ThemeVariant } from '../theme/ThemeModels';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ResolvedBubbleFrame, ThemeImageSlots, ThemePackRegistry } from '../theme/ThemePackRegistry';
import { AccountCommerceConfig } from '../account/AccountCommerceConfig';
import { AccountApiError, ThemeCatalogItem, ThemeCatalogResponse,
  ThemeEntitlement } from '../account/AccountCommerceModels';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { CustomThemeQuota } from '../account/CustomThemeQuota';
import { MembershipCommerceService } from '../account/MembershipCommerceService';
import { HuaweiAccountService } from '../account/HuaweiAccountService';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderResolvedRegexEmphasis
} from '../model/reader/ReaderRegexFontRule';
import {
  ReaderCommentBubbleImage,
  ReaderCommentBubbleStyles,
  ReaderCommentBubblePainter
} from '../core/reader/ReaderCommentBubble';
import { StartupCoverTextStore } from '../utils/StartupCoverTextStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { CloudThemeSync } from '../account/CloudThemeSync';
import { ListDissolve } from '../utils/ListDissolve';
import { DeleteParticleBurst, DeleteParticleLayer } from '../components/common/DeleteParticles';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { themeAuthorLine, ThemeExportDialog, ThemeImportDialog } from '../components/theme/ThemeShareDialogs';
import {
  ThemeExportOptions,
  ThemeExportPlan,
  ThemeExportResult,
  ThemeImportPreview,
  ThemePackageService
} from '../theme/share/ThemePackageService';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { PopupMenuAction, PopupMenuHeader } from '../components/common/PopupMenuAction';

// “我的”页已拥有区只露这么多套，其余进“全部”列表，免得把方案挤到很下面。
const OWNED_PREVIEW_COUNT = 8;
// “我的”页方案区露出的套数（置顶优先），其余进“我的方案”全部页。
const SCHEME_PREVIEW_COUNT = 4;
// 方案到这么多套才在全部页给搜索框。
const SCHEME_SEARCH_MIN = 8;
const SCHEME_SORTS: string[] = ['recent', 'modified', 'created', 'name', 'manual'];
const SCHEME_FILTERS: string[] = ['all', 'self', 'import'];
// 置顶的侧滑底色和名称旁的图钉：和应用（强调色）、删除（红）分开，各主题下都看得清。
const SCHEME_PIN_COLOR = '#F2A11B';
const OWNED_TILE_WIDTH = 88;
const OWNED_TILE_HEIGHT = 124;
const ROW_THUMB_WIDTH = 44;
const ROW_THUMB_HEIGHT = 62;
const CURRENT_HERO_HEIGHT = 188;
const CURRENT_CARD_HERO_HEIGHT = 132;
const STORE_TILE_WIDTH = 100;
const STORE_TILE_HEIGHT = 168;
const DETAIL_READER_FONT_SIZE = 17;
const DETAIL_READER_LINE_HEIGHT = 31;
// 实景预览卡的宽高比：接近一屏，比真机屏幕略矮，一屏里还能露出上下的小标题。
const DETAIL_SCENE_RATIO = 9 / 15.5;
const DETAIL_READER_BAR_HEIGHT = 28;
const DETAIL_READER_TITLE_SIZE = 24;
const DETAIL_READER_TITLE_HEIGHT = 72;
const DETAIL_FULL_SCENES: string[] = ['shelf', 'reader', 'listen'];
const DETAIL_SHELF_LAYOUTS: string[] = ['compact', 'loose', 'tile', 'companion'];

function detailShelfLayoutLabel(layout: string): string {
  if (layout === 'compact') return '紧凑';
  if (layout === 'loose') return '宽松';
  if (layout === 'tile') return '平铺';
  return '陪伴';
}
const DETAIL_SCRIM = '#59000000';
const DETAIL_MODE_SWITCH_WIDTH: number = 128;

/** 主题库的一个风格分组；没归进任何组的主题（如后加的内置主题包）落到“更多”。 */
class ThemeStoreGroup {
  title: string;
  themeIds: string[];

  constructor(title: string, themeIds: string[]) {
    this.title = title;
    this.themeIds = themeIds;
  }
}

const THEME_STORE_GROUPS: ThemeStoreGroup[] = [
  new ThemeStoreGroup('超级会员专属', [ThemeIds.CELESTIAL_VAULT, ThemeIds.OBSIDIAN_ARCHIVE]),
  new ThemeStoreGroup('国风雅韵', [ThemeIds.QINGLUAN_WATER, ThemeIds.PLUM_TEA, ThemeIds.SWORD_FROST,
    ThemeIds.MOON_CRANE, ThemeIds.INK_WASH]),
  new ThemeStoreGroup('插画角色', [ThemeIds.CAT_PIPI, ThemeIds.STRAWBERRY_CREAM, ThemeIds.STARWISH_MAGIC,
    ThemeIds.AZURE_MECHA, ThemeIds.NEON_HARBOR]),
  new ThemeStoreGroup('纸本质感', [ThemeIds.LETTERPRESS_PAGE, ThemeIds.WARM_PAPER,
    ThemeIds.ROSE_LETTER, ThemeIds.CRIMSON_ARCHIVE]),
  new ThemeStoreGroup('清爽日常', [ThemeIds.PLAIN_DEFAULT, ThemeIds.CLASSIC_BLUE, ThemeIds.FOREST_MIST,
    ThemeIds.NEON_NIGHT])
];

/** 方案详情“方案组成”的一行：部件名和它取自哪套主题。 */
class SchemePartRow {
  label: string;
  source: string;

  constructor(label: string, source: string) {
    this.label = label;
    this.source = source;
  }
}

/**
 * One run of the reader preview's sample page; dialogue runs wear the theme's emphasis style and
 * comment runs are drawn as the theme's paragraph-comment pill.
 */
class ReaderPreviewSegment {
  text: string;
  emphasis: boolean;
  comment: boolean;

  constructor(text: string, emphasis: boolean = false, comment: boolean = false) {
    this.text = text;
    this.emphasis = emphasis;
    this.comment = comment;
  }
}

// Long enough to fill the tallest preview pane; the pane clips it at a whole line.
const READER_PREVIEW_SEGMENTS: ReaderPreviewSegment[] = [
  new ReaderPreviewSegment('\u3000\u3000雨停的时候，檐下还挂着水珠。她把灯芯拨亮了些，翻开那本旧书。'),
  new ReaderPreviewSegment('12', false, true),
  new ReaderPreviewSegment('\n\u3000\u3000纸页泛黄，墨迹却还清楚。窗外起了风，吹得帘子轻轻晃动，她没有抬头。\n\u3000\u3000'),
  new ReaderPreviewSegment('“长夜未尽，且慢慢读。”', true),
  new ReaderPreviewSegment('她轻声念道。\n\u3000\u3000远处传来更鼓，一声，又一声。灯花落了下来，书页翻过去，故事才刚刚开始。'),
  new ReaderPreviewSegment('8', false, true),
  new ReaderPreviewSegment('\n\u3000\u3000门外有人收了伞，在阶前跺了跺脚上的泥。\n\u3000\u3000'),
  new ReaderPreviewSegment('“这么晚了，还不歇息？”', true),
  new ReaderPreviewSegment('\n\u3000\u3000她合上书，指尖还压着方才读到的那一行，笑了笑：'),
  new ReaderPreviewSegment('“就差最后几页。”', true),
  new ReaderPreviewSegment('\n\u3000\u3000来人不再劝，只把一盏新茶搁在案角。茶烟细细地升起来，和灯影叠在一处，在墙上晃成一片淡淡的水纹。' +
    '\n\u3000\u3000夜更深了。巷口卖馄饨的担子早已收走，只剩一两声犬吠，隔着几重院墙传过来，又很快沉下去。\n\u3000\u3000'),
  new ReaderPreviewSegment('“你看这一句。”', true),
  new ReaderPreviewSegment('她忽然把书推过去，指给他看。那是一行极小的批注，墨色比正文浅些，像是很多年前，另一个同样不肯睡的人留下的。' +
    '\n\u3000\u3000他凑近看了许久，低声念出来：'),
  new ReaderPreviewSegment('“愿此夜长，愿此书不尽。”', true),
  new ReaderPreviewSegment('\n\u3000\u3000两人都没有再说话。灯芯爆了一声轻响，窗纸上映出第一线微白，天快要亮了。' +
    '\n\u3000\u3000她把书签夹回原处，将那盏已经凉透的茶端起来，慢慢喝完。新的一天，就从这一页之后开始。' +
    '\n\u3000\u3000很多年以后，她仍记得那个雨夜：一盏灯，一本书，一个不催她的人。' +
    '\n\u3000\u3000而那行小小的批注，她后来也照着写了一遍，留给下一个翻开这本书的人。')
];

// 主题设了首字装饰时，第一段（不带缩进、去掉段末的段评数）单独画成首字段落，样张从第二段接着画。
const READER_PREVIEW_LEAD = '雨停的时候，檐下还挂着水珠。她把灯芯拨亮了些，翻开那本旧书。';
const READER_PREVIEW_REST: ReaderPreviewSegment[] = READER_PREVIEW_SEGMENTS.slice(2).map(
  (segment: ReaderPreviewSegment, index: number): ReaderPreviewSegment => index === 0 ?
    new ReaderPreviewSegment(segment.text.substring(1), segment.emphasis, segment.comment) : segment);

/** User choice from the "apply theme" prompt. */
class ThemeApplyChoice {
  // 只对第一次使用的主题有意义：true 用主题预设排版，false 沿用当前排版。
  usePresetLayout: boolean = false;
  applyCover: boolean = false;
  applyIcon: boolean = false;

  static preserve(): ThemeApplyChoice {
    return new ThemeApplyChoice();
  }
}

/** One theme the user can apply right away; customSchemeId is set for custom schemes. */
class ThemeSettingsRouteParams {
  themeId: string = '';
}

class ThemeListEntry {
  theme: ThemePack;
  customSchemeId: string;

  constructor(theme: ThemePack, customSchemeId: string = '') {
    this.theme = theme;
    this.customSchemeId = customSchemeId;
  }
}

/**
 * 详情 Swiper 的页：只建当前页和相邻页。每页一整套实景预览，用 ForEach 时“已拥有 20 套”会在点开的那一帧
 * 把 20 页全部建出并测量，真机点完要 700ms 才出详情。
 * 每项是“选择键 + 页键”：页键里带方案修订号、深浅和权益修订号，变了才重建那一页（按值传给 @Builder 的条目不会自己刷新）。
 */
class ThemeDetailPageSource implements IDataSource {
  private pages: string[] = [];
  private listeners: DataChangeListener[] = [];

  static selectKey(page: string): string {
    const separator = page.indexOf('|');
    return separator < 0 ? page : page.substring(0, separator);
  }

  totalCount(): number { return this.pages.length; }
  getData(index: number): string { return this.pages[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(pages: string[]): void {
    if (pages.length === this.pages.length && pages.every((page: string, index: number) => page === this.pages[index])) {
      return;
    }
    this.pages = pages.slice();
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

@Entry
@Component
struct ThemeSettingsPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appThemeId') appThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appIconId') appIconId: string = AppIconSettingsStore.DEFAULT_ICON_ID;
  @StorageLink('appThemeBookCoverEnabled') themeBookCoverEnabled: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appCustomBaseThemeId') customBaseThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appCustomLightAccentColor') customLightAccentColor: string = '#007DFF';
  @StorageLink('appCustomDarkAccentColor') customDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appCustomLightButtonColor') customLightButtonColor: string = '#007DFF';
  @StorageLink('appCustomDarkButtonColor') customDarkButtonColor: string = '#3F8CFF';
  @StorageLink('appCustomLightReaderBackgroundColor') customLightReaderBackgroundColor: string = '#F7F1E3';
  @StorageLink('appCustomLightReaderTextColor') customLightReaderTextColor: string = '#2F261D';
  @StorageLink('appCustomLightReaderSubTextColor') customLightReaderSubTextColor: string = '#7A6F63';
  @StorageLink('appCustomLightReaderBackgroundAssetId') customLightReaderBackgroundAssetId: string = '';
  @StorageLink('appCustomLightReaderBackgroundImageFit') customLightReaderBackgroundImageFit: string = 'cover';
  @StorageLink('appCustomLightReaderContentTone') customLightReaderContentTone: string = 'light';
  @StorageLink('appCustomDarkReaderBackgroundColor') customDarkReaderBackgroundColor: string = '#1F2329';
  @StorageLink('appCustomDarkReaderTextColor') customDarkReaderTextColor: string = '#D8D8D8';
  @StorageLink('appCustomDarkReaderSubTextColor') customDarkReaderSubTextColor: string = '#9AA0A6';
  @StorageLink('appCustomDarkReaderBackgroundAssetId') customDarkReaderBackgroundAssetId: string = '';
  @StorageLink('appCustomDarkReaderBackgroundImageFit') customDarkReaderBackgroundImageFit: string = 'cover';
  @StorageLink('appCustomDarkReaderContentTone') customDarkReaderContentTone: string = 'dark';
  @StorageLink('readerLightThemeIndex') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') readerDarkThemeIndex: number = 0;
  @StorageLink('accountLoggedIn') accountLoggedIn: boolean = false;
  @StorageLink('accountPoints') accountPoints: number = 0;
  @StorageLink('accountEntitlementsRevision') @Watch('onEntitlementsChanged')
  accountEntitlementsRevision: number = 0;
  @StorageLink('themeTrialThemeId') trialThemeId: string = '';
  @StorageLink('themeTrialEndsAt') trialEndsAt: number = 0;
  @StorageLink('activeCustomThemeSchemeId') activeCustomSchemeId: string = '';
  @StorageLink('activeCustomThemeSchemeRevision') activeCustomSchemeRevision: number = 0;
  @StorageLink('customThemeSchemesRevision') @Watch('onCustomThemeSchemesRevisionChanged')
  customThemeSchemesRevision: number = 0;
  // 云同步装好主题包、或云端可下载的包变了：方案卡片和详情跟着换。
  @StorageLink('cloudRemoteThemePacksRaw') @Watch('onCloudThemePacksChanged') cloudRemoteThemePacksRaw: string = '[]';
  @StorageLink('installedThemePacksRevision') @Watch('onCloudThemePacksChanged')
  installedThemePacksRevision: number = 0;
  @StorageLink('startupCoverTextsRevision') startupCoverTextsRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State applyingThemeId: string = '';
  @State homeSegment: string = 'mine';
  @State ownedListOpen: boolean = false;
  @State ownedSort: string = 'recent';
  @State recentThemeIds: string[] = [];
  // 主题与方案最近一次应用的时间，键同 ThemeRecentStore；改了就加 recentUseRevision 让列表重排。
  private recentUseTimes: Map<string, number> = new Map<string, number>();
  @State recentUseRevision: number = 0;
  // “我的方案”全部页：排序存本机；筛选、搜索和整理状态关页就清掉。
  @State schemeListOpen: boolean = false;
  @State schemeSort: string = 'recent';
  @State schemeFilter: string = 'all';
  @State schemeQuery: string = '';
  @State schemeSortMenuOpen: boolean = false;
  @State schemeOrganizing: boolean = false;
  @State schemeSelected: string[] = [];
  // 整理模式里两段（置顶 / 其他）的方案 ID：onMove 要求拖动时当场改数据，松手再写回存储。
  @State schemeOrderPinned: string[] = [];
  @State schemeOrderRest: string[] = [];
  // 批量删除时要删的方案；单个删除仍用 actionCustomSchemeId。
  @State deleteSchemeIds: string[] = [];
  // 竖向详情页：detailKeys 是同一列表里可左右滑动的项（theme:<主题 ID> 或 scheme:<方案 ID>）。
  @State detailOpen: boolean = false;
  @State detailKeys: string[] = [];
  @State detailIndex: number = 0;
  @State detailLabel: string = '';
  // 详情页可单独切浅色 / 深色预览，不改应用的深浅色。
  @State @Watch('syncDetailPages') detailDark: boolean = false;
  private detailPageSource: ThemeDetailPageSource = new ThemeDetailPageSource();
  // 相邻页每页建出加测量约 25ms，入场动画（260ms）结束后才预建，免得滑入时掉帧。
  @State detailCachedCount: number = 0;
  private detailCacheTimer: number = -1;
  // 正在看的那一页已经滑过大图：顶栏换成实底，按钮不压在预览卡上。
  @State detailTopSolid: boolean = false;
  // 各页的滚动位置（键同 detailKeys），左右换页后顶栏按新一页的位置取实底或透明。
  private detailOffsets: Map<string, number> = new Map<string, number>();
  // 书架预览正在看的布局：打开详情时取用户当前的书架布局，可在预览上方切换，不改书架设置。
  @State detailShelfLayout: string = 'companion';
  // 放大到全屏看的画面（shelf / reader / listen），空串表示没有放大。
  @State detailFullScene: string = '';
  @State detailPartsOpen: boolean = false;
  @State @Watch('syncDetailPages') customSchemes: CustomThemeScheme[] = [];
  /** 正在消散的自定义方案 id，见 ListDissolve。 */
  @State dissolvingSchemeIds: string[] = [];
  @State deleteParticleBursts: DeleteParticleBurst[] = [];
  // 已经有自己排版的主题：阅读档案 ID → 排版摘要。卡片上显示它，没有的才显示预设排版。
  @State boundLayoutRevision: number = 0;
  private boundLayoutSummaries: Map<string, string> = new Map<string, string>();
  @State typographyFollowsTheme: boolean = true;
  @State customSchemeLimit: number = CustomThemeQuota.current();
  @State addingCustomScheme: boolean = false;
  @State @Watch('syncThemeExportDialog') showThemeExportDialog: boolean = false;
  @State exportPlan: ThemeExportPlan = new ThemeExportPlan();
  @State @Watch('syncThemeImportDialog') showThemeImportDialog: boolean = false;
  @State importPreview: ThemeImportPreview = new ThemeImportPreview();
  @State preparingThemeImport: boolean = false;
  // 外部“用本应用打开”.qytheme 文件时由 EntryAbility 写入。
  @StorageLink('pendingThemeImportNonce') @Watch('onPendingThemeImport') pendingThemeImportNonce: number = 0;
  @State showCustomThemeActionMenu: boolean = false;
  @State @Watch('syncShowRenameCustomThemeDialog') showRenameCustomThemeDialog: boolean = false;
  private renameCustomThemeDialogSession: SystemDialogSession = new SystemDialogSession();
  private themeExportDialogSession: SystemDialogSession = new SystemDialogSession();
  private themeImportDialogSession: SystemDialogSession = new SystemDialogSession();
  private themeApplyDialogSession: SystemDialogSession = new SystemDialogSession();
  private startupTextDialogSession: SystemDialogSession = new SystemDialogSession();
  private deleteCustomThemeDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('syncShowDeleteCustomThemeDialog') showDeleteCustomThemeDialog: boolean = false;
  @State actionCustomSchemeId: string = '';
  // 列表行长按菜单对应的主题（entrySelectKey），以及“查看详情”要带的列表上下文。
  @State actionThemeKey: string = '';
  private actionThemeContext: string = '';
  private actionThemeLabel: string = '';
  @State renameCustomThemeName: string = '';
  @State contextMenuX: number = 24;
  @State contextMenuY: number = 120;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State @Watch('syncShowStartupTextDialog') showStartupTextDialog: boolean = false;
  @State startupTextThemeId: string = '';
  @State startupTextTitle: string = '';
  @State startupTextSubtitle: string = '';
  @State @Watch('syncShowThemeApplyDialog') showThemeApplyDialog: boolean = false;
  @State applyDialogThemeName: string = '';
  // 排版开关打开、关闭时各自会得到的排版，提示随开关切换，数值取自实际要生效的设置。
  @State applyDialogLayoutOnHint: string = '';
  @State applyDialogLayoutOffHint: string = '';
  @State applyDialogFirstUse: boolean = false;
  @State applyDialogHasCover: boolean = false;
  @State applyDialogApplyLayout: boolean = false;
  @State applyDialogApplyCover: boolean = false;
  @State applyDialogApplyIcon: boolean = false;
  private pendingApplyChoice: ((choice: ThemeApplyChoice | null) => void) | null = null;
  @State themeCatalog: ThemeCatalogItem[] = [];
  @State themeCatalogLoaded: boolean = false;
  // The last catalog request failed; prices stay hidden and the acquire buttons offer a retry.
  @State themeCatalogFailed: boolean = false;
  private customSchemeRefreshSerial: number = 0;
  private commentBubbleImages: Map<string, ReaderCommentBubbleImage | null> =
    new Map<string, ReaderCommentBubbleImage | null>();

  aboutToAppear(): void {
    this.loadThemeSettings();
    this.refreshCustomSchemes();
    this.initializeAccount();
    this.refreshThemeCatalog();
    this.loadRecentThemes();
    this.syncBars();
    const params = router.getParams() as ThemeSettingsRouteParams;
    if (params?.themeId && SuperExclusiveThemes.has(params.themeId)) {
      this.openDetail([`theme:${params.themeId}`], 0, '主题库');
    }
    this.onPendingThemeImport();
  }

  aboutToDisappear(): void {
    clearTimeout(this.detailCacheTimer);
    if (this.showThemeImportDialog) {
      ThemePackageService.discardImport(this.importPreview);
    }
  }

  onPageShow(): void {
    this.refreshCustomSchemeLimit();
    ThemeTrialManager.stopIfExpired();
    AppIconManager.syncCurrentIcon(getContext(this)).catch((error: Error) => {
      console.warn('同步桌面图标失败:', error);
    });
    this.refreshCustomSchemes();
    this.syncBars();
  }

  onCustomThemeSchemesRevisionChanged(): void {
    this.refreshCustomSchemes();
  }

  onCloudThemePacksChanged(): void {
    this.refreshCustomSchemes();
    this.syncDetailPages();
  }

  refreshCustomSchemeLimit(): void {
    this.customSchemeLimit = CustomThemeQuota.current();
  }

  onEntitlementsChanged(): void {
    this.refreshCustomSchemeLimit();
    this.syncDetailPages();
  }

  customSchemeAuthor(customSchemeId: string): string {
    if (!customSchemeId) return '';
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    return scheme ? scheme.author : '';
  }

  /** 方案用到的主题包本机没有（换设备同步过来、或目录被清掉）。 */
  customSchemePackMissing(customSchemeId: string): boolean {
    if (!customSchemeId) return false;
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    return !!scheme && CloudThemeSync.schemePackageIds(scheme).some((id: string): boolean =>
      !ThemePackRegistry.getByPackageId(id));
  }

  /** 缺的主题包在云端，应用或打开时会下载。读 cloudRemoteThemePacksRaw 让界面随之刷新。 */
  customSchemeInCloud(customSchemeId: string): boolean {
    if (!customSchemeId || this.cloudRemoteThemePacksRaw === '[]') return false;
    return CloudThemeSync.remotePacksOf(CustomThemeSchemeStore.find(this.customSchemes, customSchemeId)).length > 0;
  }

  /** 打开方案详情时在后台把云端的素材包取回来，装好后详情自动换成真实素材。 */
  prefetchSchemePacks(customSchemeId: string): void {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme || !this.customSchemePackMissing(customSchemeId)) return;
    CloudThemeSync.ensureSchemePacks(getContext(this), scheme).catch((e: Error) => {
      console.warn('下载云端主题素材失败:', e.message);
    });
  }

  /** 主题分享 Beta 导出和导入都只对会员开放。 */
  async ensureThemeShareAccess(): Promise<boolean> {
    // 从外部打开主题包冷启动时，账号可能还没读完。
    await AccountSessionStore.load(getContext(this));
    if (ThemePackageService.isAvailable()) {
      return true;
    }
    const result = await promptAction.showDialog({
      title: '主题分享 Beta · 会员专享',
      message: '开通任一档会员后，可以把自定义主题导出为 .qytheme 主题包分享给好友，也可以导入别人分享的主题包。',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '了解会员', color: this.accentColor() }
      ]
    });
    if (result.index === 1) {
      router.pushUrl({ url: 'pages/AccountCenter' });
    }
    return false;
  }

  async requestThemeExport(schemeId: string): Promise<void> {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    if (!scheme) return;
    const exclusiveName = ThemePackageService.exclusiveThemeBlockingExport(scheme);
    if (exclusiveName) {
      await promptAction.showDialog({
        title: '这套主题不能分享',
        message: `它用到了终身超级会员专属主题「${exclusiveName}」，专属主题的素材只能自己使用，不能导出为主题包分享。`,
        buttons: [{ text: '知道了', color: this.accentColor() }]
      });
      return;
    }
    if (!(await this.ensureThemeShareAccess())) return;
    try {
      this.exportPlan = await ThemePackageService.planExport(getContext(this), scheme);
      this.showThemeExportDialog = true;
    } catch (e) {
      console.error('读取待导出主题失败:', e);
      HdsFeedback.showToast('读取主题失败，请稍后重试');
    }
  }

  async runThemeExport(options: ThemeExportOptions, share: boolean): Promise<void> {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, this.exportPlan.schemeId);
    if (!scheme) return;
    let result: ThemeExportResult | null = null;
    try {
      result = await ThemePackageService.buildPackage(getContext(this), scheme, options);
      if (share) {
        await ThemePackageService.share(getContext(this) as common.UIAbilityContext, result);
        this.showThemeExportDialog = false;
        // 分享面板异步读取文件，临时文件交给系统清理临时目录时一并删除。
        result = null;
      } else if (await ThemePackageService.saveToFile(getContext(this), result)) {
        this.showThemeExportDialog = false;
        HdsFeedback.showToast(`已导出「${result.fileName}」`);
      }
    } catch (e) {
      console.error('导出主题包失败:', e);
      HdsFeedback.showToast((e as Error).message || '导出失败，请稍后重试');
    } finally {
      ThemePackageService.discardExport(result);
    }
  }

  onPendingThemeImport(): void {
    const uri = AppStorage.get<string>('pendingThemeImportUri') || '';
    if (!uri) return;
    AppStorage.setOrCreate('pendingThemeImportUri', '');
    this.requestThemeImport(uri);
  }

  async requestThemeImport(sourceUri: string): Promise<void> {
    if (this.preparingThemeImport || this.showThemeImportDialog) return;
    if (!(await this.ensureThemeShareAccess())) return;
    this.preparingThemeImport = true;
    try {
      const uri = sourceUri || await ThemePackageService.pickPackage(getContext(this));
      if (!uri) return;
      this.importPreview = await ThemePackageService.prepareImport(getContext(this), uri);
      this.refreshCustomSchemeLimit();
      await this.refreshCustomSchemes();
      this.showThemeImportDialog = true;
    } catch (e) {
      console.error('读取主题包失败:', e);
      HdsFeedback.showToast((e as Error).message || '无法读取这个主题包');
    } finally {
      this.preparingThemeImport = false;
    }
  }

  closeThemeImport(): void {
    ThemePackageService.discardImport(this.importPreview);
    this.importPreview = new ThemeImportPreview();
    this.showThemeImportDialog = false;
  }

  async runThemeImport(replaceSchemeId: string): Promise<void> {
    try {
      const result = await ThemePackageService.commitImport(getContext(this), this.getUIContext(),
        this.importPreview, replaceSchemeId);
      this.importPreview = new ThemeImportPreview();
      this.showThemeImportDialog = false;
      await this.refreshCustomSchemes();
      if (result.replacedActive) {
        // 更新了正在使用的主题包方案：重新应用，新素材才会铺到各页面。
        await this.selectTheme(ThemeIds.CUSTOM, result.scheme.id, false);
      }
      let notice = replaceSchemeId && result.scheme.packageId ? `已更新「${result.scheme.name}」` :
        `已导入「${result.scheme.name}」`;
      if (result.addedRules > 0) notice += `，追加 ${result.addedRules} 条强调规则`;
      if (result.missingFonts.length > 0) notice += `，${result.missingFonts.length} 款字体改用全局字体`;
      HdsFeedback.showToast(notice);
      this.openSchemeDetail(result.scheme.id);
    } catch (e) {
      console.error('导入主题包失败:', e);
      HdsFeedback.showToast((e as Error).message || '导入失败，请稍后重试');
      // 写入失败时临时文件已清理，需要重新选择文件。
      this.importPreview = new ThemeImportPreview();
      this.showThemeImportDialog = false;
    }
  }

  onBackPress(): boolean {
    if (this.showThemeExportDialog) {
      this.showThemeExportDialog = false;
      return true;
    }
    if (this.showThemeImportDialog) {
      this.closeThemeImport();
      return true;
    }
    if (this.detailOpen && this.detailFullScene) {
      this.detailFullScene = '';
      return true;
    }
    if (this.detailOpen) {
      this.closeDetail();
      return true;
    }
    if (this.schemeListOpen && this.schemeSortMenuOpen) {
      this.schemeSortMenuOpen = false;
      return true;
    }
    if (this.schemeListOpen && this.schemeOrganizing) {
      this.stopSchemeOrganize();
      return true;
    }
    if (this.schemeListOpen) {
      this.closeSchemeList();
      return true;
    }
    if (this.ownedListOpen) {
      this.ownedListOpen = false;
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '主题', content: () => {
        this.homeContent()
      }, actions: () => {
        this.headerActions()
      } })

      if (this.ownedListOpen) {
        this.ownedListOverlay()
      }

      if (this.schemeListOpen) {
        this.schemeListOverlay()
      }

      if (this.detailOpen) {
        this.detailOverlay()
      }

      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showCustomThemeActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.customThemeActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          this.showCustomThemeActionMenu = false;
        }))

      if (this.deleteParticleBursts.length > 0) {
        DeleteParticleLayer({ bursts: this.deleteParticleBursts })
      }
    }
    .id('theme_settings_root')
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updateContextViewport(newValue);
    })
  }

  /** 主题包导出：系统对话框。 */
  @Builder
  themeExportDialogContent() {
    ThemeExportDialog({
      darkMode: this.appDarkMode,
      plan: this.exportPlan,
      onClose: () => {
        this.showThemeExportDialog = false;
      },
      onExport: (options: ThemeExportOptions, share: boolean): Promise<void> => this.runThemeExport(options, share)
    })
  }

  /** 主题包导入：系统对话框。 */
  @Builder
  themeImportDialogContent() {
    ThemeImportDialog({
      darkMode: this.appDarkMode,
      preview: this.importPreview,
      schemes: this.customSchemes,
      limit: this.customSchemeLimit,
      activeSchemeId: this.appThemeId === ThemeIds.CUSTOM ? this.activeCustomSchemeId : '',
      onClose: () => this.closeThemeImport(),
      onImport: (replaceSchemeId: string): Promise<void> => this.runThemeImport(replaceSchemeId)
    })
  }

  syncThemeExportDialog(): void {
    this.themeExportDialogSession.sync(this.getUIContext(), this.showThemeExportDialog, (): void => {
      this.themeExportDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示主题导出弹窗失败:',
      onDismiss: (): void => {
        this.showThemeExportDialog = false;
      }
    });
  }

  syncThemeImportDialog(): void {
    this.themeImportDialogSession.sync(this.getUIContext(), this.showThemeImportDialog, (): void => {
      this.themeImportDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示主题导入弹窗失败:',
      onDismiss: (): void => {
        this.closeThemeImport();
      }
    });
  }

  @Builder
  headerActions() {
    Row({ space: AppSpacing.SM }) {
      ImmersiveHeaderAction({
        icon: $r('sys.symbol.square_and_arrow_down'),
        tint: this.accentColor(),
        actionEnabled: !this.preparingThemeImport,
        accessibilityLabel: this.preparingThemeImport ? '正在读取主题包' : '导入主题包',
        onTap: () => {
          this.requestThemeImport('');
        }
      })
      if (this.accountLoggedIn) {
        ImmersiveHeaderAction({
          label: `${this.accountPoints} 点`,
          tint: this.accentColor(),
          accessibilityLabel: `当前 ${this.accountPoints} 点，打开账号中心`,
          onTap: () => {
            router.pushUrl({ url: 'pages/AccountCenter' });
          }
        })
      }
    }
    .margin({ right: AppSpacing.XL })
  }

  /** 书架上的一本书：主题带封面套装就轮着用套装和书籍边框，否则用主题色块。 */
  /** 正文样张：对白套这套主题的强调样式，段评数画成主题的段评气泡。 */
  @Builder
  readerSampleText(theme: ThemePack, fontSize: number, lineHeight: number, maxLines: number, rest: boolean) {
    if (this.themeBubbleFrame(theme)) {
      // 包内气泡有边框：文字行内的 Span 画不出逐行拉伸的边框，整张样张改用编辑器小样的画法。
      // partsProvider 不是状态变量，换主题或深浅色时靠键重建组件。
      ForEach([this.frameSampleKey(theme, rest)], (_key: string) => {
        ThemeBubbleFramePreview({
          uri: this.themeBubbleFrame(theme)?.asset ?? '',
          capUri: this.themeBubbleCapUri(theme),
          settings: this.themeBubbleFrameSettings(theme),
          textColor: this.themeRegexPreview(theme).textColor,
          bubbleColor: this.themeRegexPreview(theme).backgroundColor,
          paperColor: '#00000000',
          normalTextColor: this.activeVariant(theme).reader.textColor,
          fontSize: fontSize,
          lineHeight: lineHeight,
          fontFamily: theme.typography.appFontFamily,
          indentChars: 0,
          paddingX: 0,
          paddingY: 0,
          maxLines: maxLines,
          cornerRadius: 0,
          partsProvider: (): BubbleFramePreviewPart[] => this.frameSampleParts(theme, fontSize, rest)
        })
      }, (key: string) => key)
    } else {
      this.readerSampleRichText(theme, fontSize, lineHeight, maxLines, rest)
    }
  }

  /** 这套主题的强调用的是包内气泡且包里有边框时给出边框；只在气泡模式下画。 */
  themeBubbleFrame(theme: ThemePack): ResolvedBubbleFrame | null {
    const style = this.themeRegexPreview(theme);
    if (style.mode === 'none' || !style.bubbleDecorationEnabled) return null;
    return ThemePackRegistry.bubbleFrame(this.activeVariant(theme).regexEmphasis.bubbleStyle, this.variantDark());
  }

  themeBubbleCapUri(theme: ThemePack): string {
    if (!this.themeHasRegexBubbleCap(theme)) return '';
    const cap = ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle,
      this.variantDark());
    return typeof cap === 'string' ? cap : '';
  }

  themeBubbleFrameSettings(theme: ThemePack): ThemePackageBubble {
    const settings = new ThemePackageBubble();
    const frame = this.themeBubbleFrame(theme);
    if (!frame) return settings;
    settings.frameSlice = frame.slice;
    settings.frameRepeat = frame.round ? BubbleFrameRepeat.ROUND : '';
    settings.frameBreak = frame.cut ? BubbleFrameBreak.CUT : '';
    settings.frameTint = frame.tint;
    return settings;
  }

  frameSampleKey(theme: ThemePack, rest: boolean): string {
    return `reader_frame_sample_${theme.id}_${this.activeVariant(theme).reader.contentTone}_` +
      `${this.activeVariant(theme).regexEmphasis.bubbleStyle}_${rest ? 'rest' : 'all'}`;
  }

  /** 样张的分段：rest 为真时从第二段开始（第一段画成了首字段落）。 */
  previewSegments(rest: boolean): ReaderPreviewSegment[] {
    return rest ? READER_PREVIEW_REST : READER_PREVIEW_SEGMENTS;
  }

  /** 样张分段：对白套边框，段评数换成主题的段评气泡图（与文字版样张一样前面空一格）。 */
  frameSampleParts(theme: ThemePack, fontSize: number, rest: boolean): BubbleFramePreviewPart[] {
    const dark = this.activeVariant(theme).reader.contentTone === 'dark';
    const parts: BubbleFramePreviewPart[] = [];
    for (const segment of this.previewSegments(rest)) {
      if (!segment.comment) {
        parts.push(new BubbleFramePreviewPart(segment.text, segment.emphasis));
        continue;
      }
      const image = this.commentBubbleImage(theme, segment.text, fontSize * 0.85, dark);
      if (!image) continue;
      parts.push(new BubbleFramePreviewPart(' ', false));
      parts.push(BubbleFramePreviewPart.inlineImage(image.pixelMap, this.commentBubbleImageWidth(image),
        this.commentBubbleImageHeight(image)));
    }
    return parts;
  }

  @Builder
  readerSampleRichText(theme: ThemePack, fontSize: number, lineHeight: number, maxLines: number, rest: boolean) {
    Text() {
      ForEach(this.previewSegments(rest), (segment: ReaderPreviewSegment) => {
        if (segment.comment) {
          Span(' ')
          this.commentBubbleSpan(theme, segment.text, fontSize * 0.85,
            this.activeVariant(theme).reader.contentTone === 'dark')
        } else if (!segment.emphasis) {
          Span(segment.text)
        } else if (this.themeHasRegexBubbleCap(theme)) {
          ContainerSpan() {
            ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle,
              this.variantDark()))
              .width(fontSize)
              .height(fontSize)
              .objectFit(ImageFit.Contain)
              .verticalAlign(ImageSpanAlignment.CENTER)
            Span(segment.text)
              .fontColor(this.themeRegexPreview(theme).textColor)
              .textShadow(this.themeRegexPreviewShadow(theme))
            ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle,
              this.variantDark()))
              .width(fontSize)
              .height(fontSize)
              .objectFit(ImageFit.Contain)
              .verticalAlign(ImageSpanAlignment.CENTER)
              .rotate({ angle: 180 })
          }
          .textBackgroundStyle(this.themeRegexPreviewBackground(theme))
        } else {
          ContainerSpan() {
            Span(segment.text)
              .fontColor(this.themeRegexPreview(theme).textColor)
              .textShadow(this.themeRegexPreviewShadow(theme))
          }
          .textBackgroundStyle(this.themeRegexPreviewBackground(theme))
        }
      }, (_segment: ReaderPreviewSegment, index: number) =>
        `reader_preview_${theme.id}_${rest ? 'rest' : 'all'}_${index}`)
    }
    .fontSize(fontSize)
    .lineHeight(lineHeight)
    .fontFamily(theme.typography.appFontFamily)
    .fontColor(this.activeVariant(theme).reader.textColor)
    .maxLines(maxLines)
    .textOverflow({ overflow: TextOverflow.Clip })
    .width('100%')
  }

  /** 色块图：方案的预览图或启动图，否则主题启动图；默认主题没有启动插画，画应用图标。 */
  @Builder
  swatchArt(entry: ThemeListEntry) {
    if (this.swatchImage(entry)) {
      Image(this.swatchImage(entry) as ResourceStr)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Stack() {
        Image($r('app.media.icon'))
          .width('46%')
          .aspectRatio(1)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.activeVariant(entry.theme).colors.inputColor)
    }
  }

  @Builder
  sheetPillButton(label: string, action: () => void) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.accentColor())
      .height(30)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
      .borderRadius(15)
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      .accessibilityRole(AccessibilityRoleType.BUTTON)
      .onClick(action)
  }

  /** 首页：顶部“我的 / 主题库”切换，下面是对应的内容。 */
  @Builder
  homeContent() {
    Column({ space: AppSpacing.MD }) {
      this.segmentControl()
      if (this.homeSegment === 'store') {
        this.storeContent()
      } else {
        this.mineContent()
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XS })
  }

  @Builder
  segmentControl() {
    Row() {
      ForEach(['mine', 'store'], (segment: string) => {
        Text(segment === 'store' ? '主题库' : '我的')
          .fontSize(AppFontSize.BODY)
          .fontWeight(this.homeSegment === segment ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.homeSegment === segment ? this.primaryTextColor() : this.subTextColor())
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height('100%')
          .borderRadius(16)
          .backgroundColor(this.homeSegment === segment ? this.cardColor() : Color.Transparent)
          .shadow(this.homeSegment === segment ? { radius: 4, color: '#1F000000', offsetY: 1 } :
            { radius: 0, color: Color.Transparent })
          .accessibilityRole(AccessibilityRoleType.BUTTON)
          .onClick(() => {
            this.homeSegment = segment;
          })
      }, (segment: string) => `segment_${segment}`)
    }
    .width('100%')
    .height(40)
    .padding(4)
    .borderRadius(20)
    .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
  }

  /** 我的：当前主题一张卡（大图、快捷操作、封面开关），已拥有是横向图块（其余进“全部”），方案列表紧跟在后面。 */
  @Builder
  mineContent() {
    Column({ space: AppSpacing.MD }) {
      ForEach(this.currentThemeEntries(), (entry: ThemeListEntry) => {
        this.currentCard(entry)
      }, (entry: ThemeListEntry) => `current_${this.themeEntryKey(entry)}`)

      Row({ space: AppSpacing.SM }) {
        Text('已拥有的主题')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Row() {
          Text(`全部 ${this.ownedThemeEntries().length}`)
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([this.accentColor()])
        }
        .height(32)
        .padding({ left: AppSpacing.MD, right: AppSpacing.SM })
        .borderRadius(16)
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .accessibilityText(`查看全部 ${this.ownedThemeEntries().length} 套已拥有主题`)
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .onClick(() => {
          this.ownedListOpen = true;
        })
      }
      .width('100%')
      .padding({ left: AppSpacing.XXS, top: AppSpacing.SM })
      Scroll() {
        Row({ space: AppSpacing.MD }) {
          ForEach(this.ownedPreviewEntries(), (entry: ThemeListEntry) => {
            this.ownedTile(entry)
          }, (entry: ThemeListEntry) => `owned_preview_${this.themeEntryKey(entry)}_${this.themeRowState(entry)}`)
          this.ownedAllTile()
        }
        .alignItems(VerticalAlign.Top)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .align(Alignment.TopStart)

      Row({ space: AppSpacing.SM }) {
        Text('我的方案')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Text(`${this.customSchemes.length}/${this.customSchemeLimit}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .layoutWeight(1)
        this.sheetPillButton(this.preparingThemeImport ? '读取中' : '导入', () => {
          this.requestThemeImport('');
        })
        this.sheetPillButton(this.addingCustomScheme ? '添加中' : '新建', () => {
          this.addCustomScheme();
        })
      }
      .width('100%')
      .padding({ left: AppSpacing.XXS, top: AppSpacing.SM })
      if (this.customSchemes.length > 0) {
        Column() {
          List() {
            ForEach(this.schemePreviewEntries(), (entry: ThemeListEntry, index: number) => {
              this.swipeThemeItem(entry, 'schemes', '我的方案', index > 0)
            }, (entry: ThemeListEntry) => `scheme_row_${this.themeEntryKey(entry)}_${this.themeRowState(entry)}`)
          }
          .themeCardList(this.cardColor())
          Divider()
            .strokeWidth(0.5)
            .color(ThemeRuntime.dividerColor(this.appDarkMode))
          Row({ space: AppSpacing.XXS }) {
            Text(`查看全部 ${this.customSchemes.length} 套`)
              .fontSize(AppFontSize.BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Text(`按${this.schemeSortLabel(this.schemeSort)}`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([this.subTextColor()])
          }
          .width('100%')
          .height(48)
          .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
          .accessibilityGroup(true)
          .accessibilityText(`查看全部 ${this.customSchemes.length} 套方案，可排序、置顶和整理`)
          .accessibilityRole(AccessibilityRoleType.BUTTON)
          .onClick(() => this.openSchemeList())
        }
        .width('100%')
        .borderRadius(ThemeRuntime.cardRadius())
        .backgroundColor(this.cardColor())
        .clip(true)
        Text(`置顶的排在最前，其余按“${this.schemeSortLabel(this.schemeSort)}”；左滑可置顶、应用或删除`)
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.subTextColor())
          .padding({ left: AppSpacing.XXS })
      }
      this.desktopIconCard()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 当前主题：大图下面一排快捷操作，再跟主题封面开关；和当前主题无关的桌面图标在页面最下面。 */
  @Builder
  currentCard(entry: ThemeListEntry) {
    Column() {
      this.currentHero(entry)
      Row() {
        this.quickAction($r('sys.symbol.info_circle'), '详情', () => {
          this.openDetailFor(entry, entry.customSchemeId ? 'schemes' : 'owned',
            entry.customSchemeId ? '我的方案' : '已拥有');
        })
        if (entry.customSchemeId) {
          this.quickAction($r('sys.symbol.paintpalette'), '编辑方案', () => {
            router.pushUrl({ url: 'pages/ThemeColorSettings', params: { schemeId: entry.customSchemeId } });
          })
          this.quickAction($r('sys.symbol.textformat'), '排版', () => {
            router.pushUrl({ url: 'pages/ThemeTypographySettings', params: { schemeId: entry.customSchemeId } });
          })
        } else {
          if (this.currentCanEditStartupText()) {
            this.quickAction($r('sys.symbol.square_and_pencil'), '启动文案', () => {
              this.openStartupTextDialog(this.appThemeId);
            })
          }
          if (this.canBaseSchemeOn(entry.theme)) {
            this.quickAction($r('sys.symbol.plus_square_on_square'), '以此新建方案', () => {
              this.createSchemeFromTheme(entry.theme);
            })
          }
        }
      }
      .width('100%')
      if (this.currentHasCoverSetting()) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.dividerColor(this.appDarkMode))
          .margin({ left: AppSpacing.LG })
        Row({ space: AppSpacing.MD }) {
          Column({ space: 2 }) {
            Text('主题封面与书籍边框')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.primaryTextColor())
            Text(this.themeBookCoverEnabled ? '书架使用主题封面和配套边框' : '保留每本书原有封面；可在封面设置里只给没有封面的书使用')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          AdaptiveSwitch({
            isOn: this.themeBookCoverEnabled,
            switchEnabled: !this.isTrialTheme(this.appThemeId),
            onChange: (enabled: boolean) => {
              this.setThemeBookCoverEnabled(enabled);
            }
          })
        }
        .width('100%')
        .constraintSize({ minHeight: 62 })
        .padding({ left: AppSpacing.LG, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.dividerColor(this.appDarkMode))
          .margin({ left: AppSpacing.LG })
        Row() {
          Text('更多封面设置')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([this.subTextColor()])
        }
        .width('100%')
        .height(48)
        .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
        .onClick(() => {
          router.pushUrl({ url: 'pages/CoverSettings' });
        })
      }
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .clip(true)
  }

  @Builder
  currentHero(entry: ThemeListEntry) {
    Stack({ alignContent: Alignment.BottomStart }) {
      this.swatchArt(entry)
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ direction: GradientDirection.Right, colors: [['#B3000000', 0], ['#14000000', 0.75]] })
      Column({ space: AppSpacing.XS }) {
        Text(this.isTrialTheme(entry.theme.id) ? '试用中' : '正在使用')
          .fontSize(AppFontSize.MICRO)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
          .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 2, bottom: 2 })
          .borderRadius(10)
          .backgroundColor(this.accentColor())
        Row({ space: AppSpacing.XS }) {
          if (SuperExclusiveThemes.has(entry.theme.id)) {
            MembershipBadge({ sku: 'SUPER_LIFETIME' })
          }
          Text(entry.theme.name)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(entry.theme.typography.appFontFamily)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
        }
        Text(this.themeRowSubtitle(entry))
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#E6FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(AppSpacing.LG)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(CURRENT_CARD_HERO_HEIGHT)
    .accessibilityText(`正在使用「${entry.theme.name}」，查看详情`)
    .onClick(() => this.openDetailFor(entry, entry.customSchemeId ? 'schemes' : 'owned',
      entry.customSchemeId ? '我的方案' : '已拥有'))
  }

  @Builder
  quickAction(icon: Resource, label: string, action: () => void) {
    Column({ space: AppSpacing.XXS }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.primaryTextColor()])
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(label)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(action)
  }

  /** 已拥有主题的图块：点进详情，长按出快捷菜单（应用 / 查看详情）。 */
  @Builder
  ownedTile(entry: ThemeListEntry) {
    Column({ space: AppSpacing.XXS }) {
      Stack() {
        this.swatchArt(entry)
      }
      .width(OWNED_TILE_WIDTH)
      .height(OWNED_TILE_HEIGHT)
      .borderRadius(12)
      .clip(true)
      Row({ space: AppSpacing.XXS }) {
        if (SuperExclusiveThemes.has(entry.theme.id)) {
          MembershipBadge({ sku: 'SUPER_LIFETIME' })
        }
        Text(entry.theme.name)
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
      }
      .margin({ top: AppSpacing.XS })
      Text(this.storeTileTag(entry))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(OWNED_TILE_WIDTH)
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`查看「${entry.theme.name}」详情`)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          this.openThemeRowActions(entry, 'owned', '已拥有', event);
        })
    )
    .onClick(() => this.openDetailFor(entry, 'owned', '已拥有'))
  }

  @Builder
  ownedAllTile() {
    Column({ space: AppSpacing.XXS }) {
      Text(`${this.ownedThemeEntries().length}`)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Text('全部')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
    }
    .width(OWNED_TILE_WIDTH)
    .height(OWNED_TILE_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
    .accessibilityGroup(true)
    .accessibilityText(`查看全部 ${this.ownedThemeEntries().length} 套已拥有主题`)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(() => {
      this.ownedListOpen = true;
    })
  }

  @Builder
  desktopIconCard() {
    Row({ space: AppSpacing.MD }) {
      Image(AppIconManager.optionById(this.appIconId).preview)
        .width(28)
        .height(28)
        .borderRadius(7)
        .objectFit(ImageFit.Cover)
        .draggable(false)
        .accessibilityText('当前桌面图标')
      Text('桌面图标')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(54)
    .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
    .margin({ top: AppSpacing.SM })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(() => {
      router.pushUrl({ url: 'pages/AppIconSettings' });
    })
  }

  /** 一行主题或方案：点进竖向详情，右边只显示使用状态；左滑或长按快速应用。 */
  @Builder
  themeRow(entry: ThemeListEntry, context: string, label: string, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.dividerColor(this.appDarkMode))
          .margin({ left: AppSpacing.MD + ROW_THUMB_WIDTH + AppSpacing.MD })
      }
      Row({ space: AppSpacing.MD }) {
        Row({ space: AppSpacing.MD }) {
          Stack() {
            this.swatchArt(entry)
          }
          .width(ROW_THUMB_WIDTH)
          .height(ROW_THUMB_HEIGHT)
          .borderRadius(6)
          .clip(true)
          Column({ space: 2 }) {
            Row({ space: AppSpacing.XS }) {
              if (SuperExclusiveThemes.has(entry.theme.id)) {
                MembershipBadge({ sku: 'SUPER_LIFETIME' })
              }
              if (context === 'schemes' && this.schemePinned(entry.customSchemeId)) {
                SymbolGlyph($r('sys.symbol.pin'))
                  .fontSize(13)
                  .fontColor([SCHEME_PIN_COLOR])
                  .accessibilityText('已置顶')
              }
              Text(entry.theme.name)
                .fontSize(AppFontSize.BODY_LARGE)
                .fontWeight(FontWeight.Medium)
                .fontFamily(entry.theme.typography.appFontFamily)
                .fontColor(this.primaryTextColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)
              if (this.customSchemeInCloud(entry.customSchemeId)) {
                Text('云端')
                  .fontSize(AppFontSize.MICRO)
                  .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 1, bottom: 1 })
                  .borderRadius(ThemeRuntime.smallRadius())
                  .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
                  .flexShrink(0)
              }
            }
            Text(this.themeRowSubtitle(entry))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.customSchemePackMissing(entry.customSchemeId) &&
                !this.customSchemeInCloud(entry.customSchemeId) ?
                ThemeRuntime.dangerColor(this.appDarkMode) : this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .accessibilityText(`查看「${entry.theme.name}」详情`)
        .gesture(
          LongPressGesture({ repeat: false })
            .onAction((event: GestureEvent) => {
              this.openThemeRowActions(entry, context, label, event);
            })
        )
        .onClick(() => this.openDetailFor(entry, context, label))
        this.themeRowAction(entry)
      }
      .width('100%')
      .padding({ left: AppSpacing.MD, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
    }
    .width('100%')
    .opacity(ListDissolve.opacity(this.isSchemeRowDissolving(entry, context)))
    .scale(ListDissolve.scale(this.isSchemeRowDissolving(entry, context)))
    .blur(ListDissolve.blur(this.isSchemeRowDissolving(entry, context)))
    .id(this.schemeRowIdFor(entry.customSchemeId, context))
  }

  schemeRowElementId(schemeId: string): string {
    return `theme_scheme_row_${encodeURIComponent(schemeId)}`;
  }

  /**
   * 方案行的组件 ID（删除时按它找位置放粒子）。全部页盖在“我的”页上面时两处都有同一套方案，
   * ID 只给看得见的那一处：全部页开着给全部页的行，否则给“我的”页的行。
   */
  schemeRowIdFor(schemeId: string, context: string): string {
    if (!schemeId || !this.isSchemeRowContext(context)) return '';
    return (context === 'schemes') === !this.schemeListOpen ? this.schemeRowElementId(schemeId) : '';
  }

  isSchemeRowContext(context: string): boolean {
    return context === 'schemes' || context === 'scheme-list' || context === 'scheme-organize';
  }

  /** 只有“我的方案”里的那一行消散（“我的”页或全部页），其他列表里同一方案的预览不动。 */
  isSchemeRowDissolving(entry: ThemeListEntry, context: string): boolean {
    return this.isSchemeRowContext(context) && !!entry.customSchemeId && this.dissolvingSchemeIds.length > 0 &&
      this.dissolvingSchemeIds.indexOf(entry.customSchemeId) >= 0;
  }

  @Builder
  themeRowAction(entry: ThemeListEntry) {
    if (this.applyingThemeId === (entry.customSchemeId || entry.theme.id) &&
      !this.isSelected(entry.theme, entry.customSchemeId)) {
      Text('应用中')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.accentColor())
    } else if (!entry.customSchemeId && this.isTrialTheme(entry.theme.id)) {
      Text('试用中')
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor())
    } else if (this.isSelected(entry.theme, entry.customSchemeId)) {
      Text('使用中')
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor())
    }
  }

  /** 卡片里的一行主题：左滑露出“应用”，方案另有“删除”（走二次确认）；没有可做的就不给侧滑。 */
  @Builder
  swipeThemeItem(entry: ThemeListEntry, context: string, label: string, showDivider: boolean) {
    if (!this.themeRowCanApply(entry) && !entry.customSchemeId) {
      ListItem() {
        this.themeRow(entry, context, label, showDivider)
      }
    } else if (deviceInfo.sdkApiVersion >= 26) {
      // HdsListItem 必须直接挂在 List 下，侧滑才不被包装节点阻断。
      HdsListItem({ customItemBuilder: (): void => {
        this.themeRow(entry, context, label, showDivider);
      }, swipeActionOptions: this.themeRowSwipeActions(entry) })
    } else {
      ListItem() {
        this.themeRow(entry, context, label, showDivider)
      }
      .swipeAction({ end: { builder: (): void => {
        this.themeRowFallbackSwipeActions(entry);
      } }, edgeEffect: SwipeEdgeEffect.Spring })
    }
  }

  themeRowSwipeActions(entry: ThemeListEntry): HdsSwipeActionOptions {
    const options: HdsSwipeActionOptions = { icons: [] };
    if (entry.customSchemeId) {
      const pinned = this.schemePinned(entry.customSchemeId);
      options.icons?.push({ icon: new SymbolGlyphModifier($r('sys.symbol.pin')),
        backgroundColor: SCHEME_PIN_COLOR,
        iconOptions: { accessibilityText: `${pinned ? '取消置顶' : '置顶'}「${entry.theme.name}」` },
        onAction: () => {
          this.setSchemesPinned([entry.customSchemeId], !pinned);
        } });
    }
    if (this.themeRowCanApply(entry)) {
      options.icons?.push({ icon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
        backgroundColor: this.accentColor(), iconOptions: { accessibilityText: `应用「${entry.theme.name}」` },
        onAction: () => {
          this.selectTheme(entry.theme.id, entry.customSchemeId);
        } });
    }
    if (entry.customSchemeId) {
      options.icons?.push({ icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode),
        iconOptions: { accessibilityText: `删除「${entry.theme.name}」` },
        onAction: () => {
          this.requestDeleteCustomTheme(entry.customSchemeId);
        } });
    }
    return options;
  }

  @Builder
  themeRowFallbackSwipeActions(entry: ThemeListEntry) {
    Row() {
      if (entry.customSchemeId) {
        this.swipeButton($r('sys.symbol.pin'), this.schemePinned(entry.customSchemeId) ? '取消置顶' : '置顶',
          SCHEME_PIN_COLOR, () => {
            this.setSchemesPinned([entry.customSchemeId], !this.schemePinned(entry.customSchemeId));
          })
      }
      if (this.themeRowCanApply(entry)) {
        this.swipeButton($r('sys.symbol.checkmark'), '应用', this.accentColor(), () => {
          this.selectTheme(entry.theme.id, entry.customSchemeId);
        })
      }
      if (entry.customSchemeId) {
        this.swipeButton($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
          this.requestDeleteCustomTheme(entry.customSchemeId);
        })
      }
    }
    .height('100%')
  }

  @Builder
  swipeButton(icon: Resource, label: string, color: string, action: () => void) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([ThemeRuntime.onAccentColor(color)])
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.onAccentColor(color))
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(color)
    .accessibilityText(label)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(action)
  }

  /** 主题库：推荐横幅加按风格分组的横排货架，点任一主题进竖向详情。 */
  @Builder
  storeContent() {
    Column({ space: AppSpacing.SM }) {
      ForEach(this.storeFeaturedEntries(), (entry: ThemeListEntry) => {
        this.storeBanner(entry)
      }, (entry: ThemeListEntry) => `store_featured_${this.themeEntryKey(entry)}`)
      ForEach(this.storeGroups(), (group: ThemeStoreGroup) => {
        Column({ space: AppSpacing.SM }) {
          Row() {
            Text(group.title)
              .fontSize(AppFontSize.SUBTITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Text(`共 ${group.themeIds.length} 款`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .padding({ left: AppSpacing.XXS, top: AppSpacing.MD })
          Scroll() {
            Row({ space: AppSpacing.MD }) {
              ForEach(this.groupEntries(group), (entry: ThemeListEntry) => {
                this.storeTile(entry, group.title)
              }, (entry: ThemeListEntry) => `store_${group.title}_${this.themeEntryKey(entry)}`)
            }
            .alignItems(VerticalAlign.Top)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .width('100%')
          .align(Alignment.TopStart)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (group: ThemeStoreGroup) => `store_group_${group.title}_${group.themeIds.length}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  storeBanner(entry: ThemeListEntry) {
    Stack({ alignContent: Alignment.BottomStart }) {
      this.swatchArt(entry)
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ direction: GradientDirection.Right, colors: [['#C7000000', 0.3], ['#00000000', 0.85]] })
      Column({ space: AppSpacing.SM }) {
        Text(this.storeBannerTag(entry))
          .fontSize(AppFontSize.MICRO)
          .fontColor('#FFFFFF')
          .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 2, bottom: 2 })
          .borderRadius(10)
          .border({ width: 1, color: '#B3FFFFFF' })
        Text(entry.theme.name)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontFamily(entry.theme.typography.appFontFamily)
          .fontColor('#FFFFFF')
        Text(entry.theme.description)
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#E6FFFFFF')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('62%')
      }
      .padding(AppSpacing.LG)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(CURRENT_HERO_HEIGHT)
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .accessibilityText(`查看「${entry.theme.name}」详情`)
    .onClick(() => this.openDetailFor(entry, 'store', '主题库'))
  }

  @Builder
  storeTile(entry: ThemeListEntry, groupTitle: string) {
    Column({ space: AppSpacing.XXS }) {
      Stack() {
        this.swatchArt(entry)
      }
      .width(STORE_TILE_WIDTH)
      .height(STORE_TILE_HEIGHT)
      .borderRadius(12)
      .clip(true)
      .border({ width: this.isSelected(entry.theme) ? 2 : 0, color: this.accentColor() })
      Text(entry.theme.name)
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: AppSpacing.XS })
      Text(this.storeTileTag(entry))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.isSelected(entry.theme) ? this.accentColor() : this.subTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(STORE_TILE_WIDTH)
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`查看「${entry.theme.name}」详情`)
    .onClick(() => this.openDetailFor(entry, `group:${groupTitle}`, groupTitle))
  }

  @Builder
  ownedListOverlay() {
    Column() {
      Row({ space: AppSpacing.SM }) {
        this.immersiveBack(() => {
          this.ownedListOpen = false;
        })
        Text('已拥有的主题')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.ownedThemeEntries().length} 套`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      .height(56)
      .padding({ right: AppSpacing.XL })
      Row({ space: AppSpacing.SM }) {
        ForEach(['recent', 'name'], (sort: string) => {
          Text(sort === 'name' ? '按名称' : '最近用过')
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.ownedSort === sort ? ThemeRuntime.onAccentColor(this.accentColor()) : this.primaryTextColor())
            .backgroundColor(this.ownedSort === sort ? this.accentColor() : ThemeRuntime.inputColor(this.appDarkMode))
            .height(32)
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
            .borderRadius(16)
            .accessibilityRole(AccessibilityRoleType.BUTTON)
            .onClick(() => {
              this.ownedSort = sort;
            })
        }, (sort: string) => `owned_sort_${sort}`)
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.MD })
      Scroll() {
        Column() {
          List() {
            ForEach(this.sortedOwnedEntries(this.ownedSort), (entry: ThemeListEntry, index: number) => {
              this.swipeThemeItem(entry, 'owned-list', '已拥有', index > 0)
            }, (entry: ThemeListEntry) =>
              `owned_list_${this.ownedSort}_${this.themeEntryKey(entry)}_${this.themeRowState(entry)}`)
          }
          .themeCardList(this.cardColor())
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: Math.max(AppSpacing.XXL, this.navBarHeight + AppSpacing.LG) })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.pageColor())
    .transition(TransitionEffect.translate({ x: 48 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 240, curve: Curve.Friction }))
  }

  /**
   * “我的方案”全部页：顶栏、搜索（方案多时）、排序与筛选，下面分“置顶 / 其他”两段。
   * 平时行可左滑、长按（同“我的”页）；整理模式换成可多选、可长按拖动的列表，底部是批量操作。
   */
  @Builder
  schemeListOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.schemeListTopBar()
        if (this.customSchemes.length >= SCHEME_SEARCH_MIN) {
          this.schemeSearchField()
        }
        this.schemeListControls()
        if (this.schemeOrganizing) {
          this.schemeOrganizeList()
        } else {
          this.schemeBrowseList()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight })
      if (this.schemeOrganizing) {
        this.schemeOrganizeBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .transition(TransitionEffect.translate({ x: 48 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 240, curve: Curve.Friction }))
  }

  @Builder
  schemeListTopBar() {
    Row({ space: AppSpacing.SM }) {
      // 顶栏两侧的按钮都用沉浸光感材质，和返回按钮、详情页“更多”一致。
      if (this.schemeOrganizing) {
        ImmersiveHeaderAction({ label: '完成', onTap: () => this.stopSchemeOrganize() })
        Text(this.schemeSelected.length > 0 ? `已选 ${this.schemeSelected.length} 项` : '选择方案')
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
        ImmersiveHeaderAction({
          label: this.schemeSelected.length > 0 &&
            this.schemeSelected.length === this.schemeOrderPinned.length + this.schemeOrderRest.length ? '全不选' : '全选',
          tint: this.accentColor(),
          onTap: () => this.toggleSelectAllSchemes()
        })
      } else {
        this.immersiveBack(() => this.closeSchemeList())
        Text('我的方案')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.customSchemes.length}/${this.customSchemeLimit}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
        ImmersiveHeaderAction({ label: '整理', onTap: () => this.startSchemeOrganize() })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: this.schemeOrganizing ? AppSpacing.LG : 0, right: AppSpacing.LG })
  }

  @Builder
  schemeSearchField() {
    Row({ space: AppSpacing.SM }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16)
        .fontColor([this.subTextColor()])
      TextInput({ placeholder: '搜索方案名称或作者', text: this.schemeQuery })
        .layoutWeight(1)
        .height(40)
        .padding(0)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string) => {
          this.schemeQuery = value;
          this.syncSchemeOrganizeOrder();
        })
      if (this.schemeQuery) {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(16)
          .fontColor([this.subTextColor()])
          .accessibilityText('清空搜索')
          .onClick(() => {
            this.schemeQuery = '';
            this.syncSchemeOrganizeOrder();
          })
      }
    }
    .height(40)
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.SM })
    .borderRadius(20)
    .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
  }

  @Builder
  schemeListControls() {
    Row({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.XXS }) {
        SymbolGlyph($r('sys.symbol.sort'))
          .fontSize(16)
          .fontColor([this.primaryTextColor()])
        Text(this.schemeSortLabel(this.schemeSort))
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([this.subTextColor()])
      }
      .height(32)
      .padding({ right: AppSpacing.XS })
      .accessibilityGroup(true)
      .accessibilityText(`排序：${this.schemeSortLabel(this.schemeSort)}`)
      .accessibilityRole(AccessibilityRoleType.BUTTON)
      .onClick(() => {
        this.schemeSortMenuOpen = !this.schemeSortMenuOpen;
      })
      .bindPopup(this.schemeSortMenuOpen, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
        (): void => {
          this.schemeSortMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          this.schemeSortMenuOpen = false;
        }))
      Blank()
      ForEach(SCHEME_FILTERS, (filter: string) => {
        Text(`${this.schemeFilterLabel(filter)} ${this.schemeFilterCount(filter)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.schemeFilter === filter ? ThemeRuntime.onAccentColor(this.accentColor()) :
            this.primaryTextColor())
          .backgroundColor(this.schemeFilter === filter ? this.accentColor() :
            ThemeRuntime.inputColor(this.appDarkMode))
          .height(30)
          .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
          .borderRadius(15)
          .accessibilityRole(AccessibilityRoleType.BUTTON)
          .accessibilitySelected(this.schemeFilter === filter)
          .onClick(() => this.setSchemeFilter(filter))
      }, (filter: string) => `scheme_filter_${filter}_${this.schemeFilter === filter}_${this.schemeFilterCount(filter)}`)
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.SM })
  }

  schemeFilterCount(filter: string): number {
    return this.customSchemes.filter((scheme: CustomThemeScheme): boolean =>
      this.schemeMatchesFilter(scheme, filter)).length;
  }

  /** 全部页当前筛选、搜索下置顶段或其他段的套数（只数不建条目，便宜）。 */
  schemeListCount(pinned: boolean): number {
    const query = this.schemeQuery.trim().toLowerCase();
    return this.customSchemes.filter((scheme: CustomThemeScheme): boolean => scheme.pinned === pinned &&
      this.schemeMatchesFilter(scheme, this.schemeFilter) &&
      (!query || scheme.name.toLowerCase().includes(query) || scheme.author.toLowerCase().includes(query))).length;
  }

  @Builder
  schemeSortMenu() {
    Column() {
      PopupMenuHeader('排序方式', this.subTextColor())
      ForEach(SCHEME_SORTS, (sort: string) => {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(18)
            .width(22)
            .fontColor([this.accentColor()])
            .opacity(this.schemeSort === sort ? 1 : 0)
          Text(this.schemeSortLabel(sort))
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.schemeSort === sort ? this.accentColor() : this.primaryTextColor())
            .layoutWeight(1)
          if (sort === 'manual') {
            Text('可拖动')
              .fontSize(AppFontSize.MICRO)
              .fontColor(this.subTextColor())
          }
        }
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })
        .borderRadius(ImmersiveMaterialRuntime.POPUP_MENU_RADIUS - ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
        .stateStyles({
          normal: {
            .backgroundColor(Color.Transparent)
          },
          pressed: {
            .backgroundColor('#1A808080')
          }
        })
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .accessibilitySelected(this.schemeSort === sort)
        .onClick(() => this.setSchemeSort(sort))
      }, (sort: string) => `scheme_sort_${sort}_${this.schemeSort === sort}`)
    }
    .width(176)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  schemeSectionLabel(label: string, count: number, pinned: boolean) {
    Row({ space: AppSpacing.XS }) {
      if (pinned) {
        SymbolGlyph($r('sys.symbol.pin'))
          .fontSize(12)
          .fontColor([SCHEME_PIN_COLOR])
      }
      Text(`${label} · ${count}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
    }
    .width('100%')
    .padding({ left: AppSpacing.XXS, top: AppSpacing.MD, bottom: AppSpacing.SM })
  }

  @Builder
  schemeEmptyHint() {
    Text(this.schemeQuery.trim() ? `没有找到与“${this.schemeQuery.trim()}”相关的方案` : '这一类下还没有方案')
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 64, bottom: 64 })
  }

  @Builder
  schemeBrowseList() {
    Scroll() {
      Column() {
        if (this.schemeListCount(true) + this.schemeListCount(false) === 0) {
          this.schemeEmptyHint()
        }
        if (this.schemeListCount(true) > 0) {
          this.schemeSectionLabel('置顶', this.schemeListCount(true), true)
          List() {
            ForEach(this.schemeListEntries(true), (entry: ThemeListEntry, index: number) => {
              this.swipeThemeItem(entry, 'scheme-list', '我的方案', index > 0)
            }, (entry: ThemeListEntry) => `scheme_list_pin_${this.themeEntryKey(entry)}_${this.themeRowState(entry)}`)
          }
          .themeCardList(this.cardColor())
        }
        if (this.schemeListCount(false) > 0) {
          this.schemeSectionLabel(this.schemeListCount(true) > 0 ? '其他方案' : '全部方案',
            this.schemeListCount(false), false)
          List() {
            ForEach(this.schemeListEntries(false), (entry: ThemeListEntry, index: number) => {
              this.swipeThemeItem(entry, 'scheme-list', '我的方案', index > 0)
            }, (entry: ThemeListEntry) => `scheme_list_rest_${this.themeEntryKey(entry)}_${this.themeRowState(entry)}`)
          }
          .themeCardList(this.cardColor())
        }
        Text('向左滑可置顶、应用或删除；长按还可编辑、复制、重命名或分享')
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.subTextColor())
          .width('100%')
          .padding({ left: AppSpacing.XXS, top: AppSpacing.SM })
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG,
        bottom: Math.max(AppSpacing.XXL, this.navBarHeight + AppSpacing.LG) })
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  schemeEntryById(schemeId: string): ThemeListEntry {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    return scheme ? new ThemeListEntry(this.customTheme(scheme), scheme.id) :
      new ThemeListEntry(BuiltinThemeRegistry.findById(ThemeIds.PLAIN_DEFAULT), schemeId);
  }

  schemeOrganizeKey(prefix: string, schemeId: string): string {
    const entry = this.schemeEntryById(schemeId);
    return `${prefix}_${schemeId}_${this.schemeSelected.indexOf(schemeId) >= 0}_${this.schemeDragEnabled()}_` +
      `${this.themeRowState(entry)}_${entry.theme.name}`;
  }

  /**
   * 整理模式：每套方案一张独立小卡片，点按选中；能拖动时长按卡片抬起，上下拖动换位置（List 挤压让位、
   * 边缘自动滚动），松手写回。置顶与其他两段各自排，不能互相拖过去。
   */
  @Builder
  schemeOrganizeList() {
    List({ space: AppSpacing.SM }) {
      if (this.schemeOrderPinned.length + this.schemeOrderRest.length === 0) {
        ListItem() {
          this.schemeEmptyHint()
        }
      }
      if (this.schemeOrderPinned.length > 0) {
        ListItem() {
          this.schemeSectionLabel('置顶', this.schemeOrderPinned.length, true)
        }
        ForEach(this.schemeOrderPinned, (schemeId: string) => {
          ListItem() {
            this.schemeOrganizeRow(this.schemeEntryById(schemeId))
          }
        }, (schemeId: string) => this.schemeOrganizeKey('scheme_org_pin', schemeId))
          .onMove(this.schemeDragEnabled() ?
            (from: number, to: number) => this.moveSchemeDuringDrag(true, from, to) : undefined, {
            onDrop: (_index: number) => {
              this.commitSchemeOrder();
            }
          })
      }
      if (this.schemeOrderRest.length > 0) {
        ListItem() {
          this.schemeSectionLabel(this.schemeOrderPinned.length > 0 ? '其他方案' : '全部方案',
            this.schemeOrderRest.length, false)
        }
        ForEach(this.schemeOrderRest, (schemeId: string) => {
          ListItem() {
            this.schemeOrganizeRow(this.schemeEntryById(schemeId))
          }
        }, (schemeId: string) => this.schemeOrganizeKey('scheme_org_rest', schemeId))
          .onMove(this.schemeDragEnabled() ?
            (from: number, to: number) => this.moveSchemeDuringDrag(false, from, to) : undefined, {
            onDrop: (_index: number) => {
              this.commitSchemeOrder();
            }
          })
      }
      ListItem() {
        Column() {
          Text(!this.schemeDragEnabled() ? '筛选或搜索时不能拖动排序' : this.schemeSort === 'manual' ?
            '长按方案上下拖动可调整顺序' : '长按方案上下拖动可调整顺序，松手后改为“手动排序”')
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.subTextColor())
            .width('100%')
            .padding({ left: AppSpacing.XXS })
          Row()
            .height(this.navBarHeight + 96)
        }
        .width('100%')
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  schemeOrganizeRow(entry: ThemeListEntry) {
    Row({ space: AppSpacing.MD }) {
      Stack() {
        if (this.schemeSelected.indexOf(entry.customSchemeId) >= 0) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor([ThemeRuntime.onAccentColor(this.accentColor())])
        }
      }
      .width(22)
      .height(22)
      .borderRadius(11)
      .border({ width: this.schemeSelected.indexOf(entry.customSchemeId) >= 0 ? 0 : 1.5, color: this.subTextColor() })
      .backgroundColor(this.schemeSelected.indexOf(entry.customSchemeId) >= 0 ? this.accentColor() : Color.Transparent)
      Stack() {
        this.swatchArt(entry)
      }
      .width(ROW_THUMB_WIDTH)
      .height(ROW_THUMB_HEIGHT)
      .borderRadius(6)
      .clip(true)
      Column({ space: 2 }) {
        Text(entry.theme.name)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontFamily(entry.theme.typography.appFontFamily)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.themeRowSubtitle(entry))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.schemeIsActive(entry.customSchemeId)) {
        Text('使用中')
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor())
      }
      if (this.schemeDragEnabled()) {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(20)
          .fontColor([this.subTextColor()])
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.MD, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .opacity(ListDissolve.opacity(this.isSchemeRowDissolving(entry, 'scheme-organize')))
    .scale(ListDissolve.scale(this.isSchemeRowDissolving(entry, 'scheme-organize')))
    .blur(ListDissolve.blur(this.isSchemeRowDissolving(entry, 'scheme-organize')))
    .id(this.schemeRowIdFor(entry.customSchemeId, 'scheme-organize'))
    .accessibilityGroup(true)
    .accessibilityText(`${entry.theme.name}，${this.schemeSelected.indexOf(entry.customSchemeId) >= 0 ? '已选中' : '未选中'}`)
    .onClick(() => this.toggleSchemeSelected(entry.customSchemeId))
  }

  @Builder
  schemeOrganizeBar() {
    Column() {
      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.dividerColor(this.appDarkMode))
      Row() {
        this.schemeBarAction($r('sys.symbol.pin'), this.selectedSchemesAllPinned() ? '取消置顶' : '置顶',
          this.schemeSelected.length > 0, this.primaryTextColor(), () => {
            this.batchPinSelectedSchemes();
          })
        this.schemeBarAction($r('sys.symbol.share'), '分享', this.schemeSelected.length === 1,
          this.primaryTextColor(), () => {
            this.requestThemeExport(this.schemeSelected[0]);
          })
        this.schemeBarAction($r('sys.symbol.trash'), '删除', this.schemeSelected.length > 0,
          ThemeRuntime.dangerColor(this.appDarkMode), () => {
            this.requestDeleteSelectedSchemes();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
      .padding({ top: AppSpacing.SM, bottom: Math.max(AppSpacing.SM, this.navBarHeight) + AppSpacing.XS })
    }
    .width('100%')
    .backgroundColor(this.cardColor())
    .transition(TransitionEffect.translate({ y: 96 }).animation({ duration: 220, curve: Curve.Friction }))
  }

  @Builder
  schemeBarAction(icon: Resource, label: string, enabled: boolean, color: string, action: () => void) {
    Column({ space: AppSpacing.XXS }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([color])
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(color)
    }
    .width(80)
    .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
    .opacity(enabled ? 1 : 0.35)
    .enabled(enabled)
    .accessibilityGroup(true)
    .accessibilityText(label)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(action)
  }

  /** 竖向详情：同一列表里左右滑动切换，每页整页用这套主题（深浅色可单独切换预览）的配色。 */
  @Builder
  detailOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Swiper() {
          LazyForEach(this.detailPageSource, (page: string) => {
            this.detailPage(this.resolveEntry(ThemeDetailPageSource.selectKey(page)))
          }, (page: string) => `detail_${page}`)
        }
        .index(this.detailIndex)
        .indicator(false)
        .loop(false)
        .duration(280)
        .cachedCount(this.detailCachedCount)
        .disableSwipe(this.detailKeys.length <= 1)
        .onChange((index: number) => {
          this.detailIndex = index;
          this.syncDetailTopSolid();
        })
        .width('100%')
        .layoutWeight(1)
        ForEach(this.currentDetailEntries(), (entry: ThemeListEntry) => {
          this.detailActionBar(entry)
        }, (entry: ThemeListEntry) => `detail_actions_${this.themeEntryKey(entry)}`)
      }
      .width('100%')
      .height('100%')
      this.detailTopBar()
      if (this.detailFullScene) {
        this.detailFullOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.detailPageColor())
    .transition(TransitionEffect.translate({ y: 64 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 260, curve: Curve.Friction }))
  }

  /** 详情顶栏：返回、位置、浅深色开关和方案的“更多”；开关固定在这里，滑到哪一段都能直接切。 */
  @Builder
  detailTopBar() {
    Row({ space: AppSpacing.SM }) {
      ImmersiveBackButton({ iconColor: this.detailTextColor(), darkMode: this.variantDark(),
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        accessibilityLabel: '返回主题', onBack: () => this.closeDetail() })
      Text(this.detailPositionLabel())
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .height(28)
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
        .borderRadius(14)
        .backgroundColor(DETAIL_SCRIM)
        .flexShrink(1)
      Blank()
      this.detailModeToggle()
      if (this.currentDetailSchemeId()) {
        ImmersiveHeaderAction({
          icon: $r('sys.symbol.more'),
          accessibilityLabel: '更多操作',
          onTap: () => {
            this.openDetailSchemeActions();
          }
        })
      }
    }
    .width('100%')
    .height(PageScaffold.BAR_HEIGHT + this.statusBarHeight)
    .padding({ right: AppSpacing.XL, top: this.statusBarHeight })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.detailTopSolid ? this.detailPageColor() : Color.Transparent)
    .animation({ duration: 160, curve: Curve.Friction })
  }

  /** 浅色/深色预览开关：颜色取正在预览的那套主题，叠在预览画面上也协调。 */
  @Builder
  detailModeToggle() {
    ThemeModeSwitch({
      selectedDark: this.detailDark,
      darkMode: this.detailDark,
      accentColor: this.detailColors().accentColor,
      subTextColor: this.detailColors().subTextColor,
      fallbackColor: this.detailColors().cardColor,
      switchWidth: DETAIL_MODE_SWITCH_WIDTH,
      switchHeight: ImmersiveHeaderAction.SIZE,
      onChange: (dark: boolean) => {
        this.detailDark = dark;
      }
    })
  }

  detailColors(): ThemeColorTokens {
    const entries = this.currentDetailEntries();
    if (entries.length > 0) return this.activeVariant(entries[0].theme).colors;
    const colors = new ThemeColorTokens();
    colors.accentColor = ThemeRuntime.accentColor(this.detailDark);
    colors.subTextColor = ThemeRuntime.subTextColor(this.detailDark);
    colors.cardColor = ThemeRuntime.cardColor(this.detailDark);
    return colors;
  }

  @Builder
  immersiveBack(action: () => void) {
    ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
      buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
      accessibilityLabel: '返回主题', onBack: action })
  }

  /** 竖长详情：大图开头，往下依次是状态、方案组成、书架与导航、阅读页、听书面板，整页一条滚动。 */
  @Builder
  detailPage(entry: ThemeListEntry) {
    Scroll() {
      Column({ space: AppSpacing.MD }) {
        this.detailHero(entry)
        Column({ space: AppSpacing.MD }) {
          this.detailInfoCard(entry)
          if (entry.customSchemeId) {
            this.schemePartsCard(entry)
          }
          this.detailShelfTitle(entry.theme)
          this.detailSceneCard(entry, 'shelf')
          this.detailSectionTitle(entry.theme, '阅读页')
          this.detailSceneCard(entry, 'reader')
          this.detailSectionTitle(entry.theme, '听书面板')
          this.detailSceneCard(entry, 'listen')
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.XXL })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor(this.activeVariant(entry.theme).colors.pageColor)
    .onDidScroll(this.detailScrollTracker(this.entrySelectKey(entry)))
  }

  /** 大图：竖图完整铺开，名称和简介压在图的下沿。 */
  @Builder
  detailHero(entry: ThemeListEntry) {
    Stack({ alignContent: Alignment.BottomStart }) {
      this.swatchArt(entry)
      Column()
        .width('100%')
        .height('60%')
        .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00000000', 0], ['#A6000000', 1]] })
      Column({ space: AppSpacing.SM }) {
        if (entry.customSchemeId) {
          Text('我的方案')
            .fontSize(AppFontSize.CAPTION)
            .fontColor('#E6FFFFFF')
        }
        Row({ space: AppSpacing.XS }) {
          if (SuperExclusiveThemes.has(entry.theme.id)) {
            MembershipBadge({ sku: 'SUPER_LIFETIME' })
          }
          Text(entry.theme.name)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontFamily(entry.theme.typography.appFontFamily)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
        }
        Text(this.detailHeroDescription(entry))
          .fontSize(AppFontSize.BODY)
          .fontColor('#E6FFFFFF')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.XL })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(this.detailHeroHeight())
  }

  @Builder
  detailInfoCard(entry: ThemeListEntry) {
    Row({ space: AppSpacing.MD }) {
      Image(this.stageIcon(entry.theme, entry.customSchemeId))
        .width(44)
        .height(44)
        .borderRadius(11)
        .objectFit(ImageFit.Cover)
        .draggable(false)
        .accessibilityText(this.isSelected(entry.theme, entry.customSchemeId) ? '当前桌面图标' :
          `${entry.theme.name}桌面图标预览`)
      Column({ space: 2 }) {
        Text(this.detailCaption(entry))
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.activeVariant(entry.theme).colors.accentColor)
        Text(this.themeLayoutSummary(entry.theme, entry.customSchemeId))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.activeVariant(entry.theme).colors.subTextColor)
          .maxLines(2)
        if (this.customSchemeInCloud(entry.customSchemeId)) {
          Text('这套方案的素材在云端，正在下载；下载完成前按默认样式显示。')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(entry.theme).colors.subTextColor)
        } else if (this.customSchemePackMissing(entry.customSchemeId)) {
          Text('这套方案的主题包素材不在这台设备上，正按默认样式显示；重新导入同一个主题包即可恢复。')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(entry.theme).colors.dangerColor)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.activeVariant(entry.theme).colors.cardColor)
  }

  @Builder
  detailSectionTitle(theme: ThemePack, title: string) {
    Text(title)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.activeVariant(theme).colors.subTextColor)
      .padding({ left: AppSpacing.XXS, top: AppSpacing.SM })
  }

  /** 方案组成：收起时一行摘要，点开是两列小格。 */
  @Builder
  schemePartsCard(entry: ThemeListEntry) {
    Column() {
      Row({ space: AppSpacing.SM }) {
        Text(`方案组成 · ${this.detailDark ? '深色' : '浅色'}`)
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeVariant(entry.theme).colors.primaryTextColor)
        Text(this.schemePartsSummary(entry.customSchemeId))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.activeVariant(entry.theme).colors.subTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([this.activeVariant(entry.theme).colors.subTextColor])
          .rotate({ angle: this.detailPartsOpen ? 90 : 0 })
      }
      .width('100%')
      .height(48)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .accessibilityGroup(true)
      .accessibilityText(`方案组成，${this.detailPartsOpen ? '点按收起' : '点按展开'}`)
      .accessibilityRole(AccessibilityRoleType.BUTTON)
      .onClick(() => {
        this.detailPartsOpen = !this.detailPartsOpen;
      })
      if (this.detailPartsOpen) {
        Divider()
          .strokeWidth(0.5)
          .color(this.activeVariant(entry.theme).colors.dividerColor)
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.schemeParts(entry.customSchemeId), (part: SchemePartRow) => {
            Column({ space: 2 }) {
              Text(part.label)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.activeVariant(entry.theme).colors.primaryTextColor)
              Text(part.source)
                .fontSize(AppFontSize.MICRO)
                .fontColor(this.activeVariant(entry.theme).colors.subTextColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('50%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: AppSpacing.LG, right: AppSpacing.SM, top: AppSpacing.SM, bottom: AppSpacing.SM })
          }, (part: SchemePartRow, index: number) => `scheme_part_${index}_${part.source}`)
        }
        .width('100%')
        .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
      }
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.activeVariant(entry.theme).colors.cardColor)
    .clip(true)
  }

  /** 书架预览的小标题：右边一排布局切换，默认是用户当前的书架布局。 */
  @Builder
  detailShelfTitle(theme: ThemePack) {
    Row() {
      Text('书架与导航')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.activeVariant(theme).colors.subTextColor)
      Blank()
      Row({ space: AppSpacing.XXS }) {
        ForEach(DETAIL_SHELF_LAYOUTS, (layout: string) => {
          Text(detailShelfLayoutLabel(layout))
            .fontSize(AppFontSize.CAPTION)
            .fontWeight(this.detailShelfLayout === layout ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.detailShelfLayout === layout ? this.activeVariant(theme).colors.accentColor :
              this.activeVariant(theme).colors.subTextColor)
            .height(28)
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
            .borderRadius(14)
            .backgroundColor(this.detailShelfLayout === layout ? this.activeVariant(theme).colors.inputColor :
              Color.Transparent)
            .accessibilityText(`预览${detailShelfLayoutLabel(layout)}布局`)
            .accessibilityRole(AccessibilityRoleType.BUTTON)
            .accessibilitySelected(this.detailShelfLayout === layout)
            .onClick(() => {
              this.detailShelfLayout = layout;
            })
        }, (layout: string) => `detail_shelf_layout_${layout}`)
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.XXS, top: AppSpacing.SM })
    .alignItems(VerticalAlign.Center)
  }

  /** 一张实景预览卡：接近一屏大小，点按放大到全屏。 */
  @Builder
  detailSceneCard(entry: ThemeListEntry, scene: string) {
    Stack() {
      this.detailSceneContent(entry, scene, false)
    }
    .width('100%')
    .aspectRatio(DETAIL_SCENE_RATIO)
    .borderRadius(ThemeRuntime.cardRadius())
    .border({ width: 1, color: this.activeVariant(entry.theme).colors.dividerColor })
    .clip(true)
    .accessibilityText(`${scene === 'shelf' ? '书架' : (scene === 'reader' ? '阅读页' : '听书面板')}预览，点按放大`)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(() => {
      this.openDetailFull(scene);
    })
  }

  /** 实景画面本体；full 为全屏预览，让出状态栏和底部小白条。 */
  @Builder
  detailSceneContent(entry: ThemeListEntry, scene: string, full: boolean) {
    if (scene === 'reader') {
      this.detailReaderScene(entry.theme, full)
    } else {
      ThemeDetailScene({
        themePack: entry.theme,
        previewDark: this.variantDark(),
        scene: scene,
        shelfLayout: this.detailShelfLayout,
        ttsThemeId: this.previewTtsPanelThemeId(entry.theme, entry.customSchemeId),
        homeBackdropThemeId: this.detailBackdropThemeId(entry.theme, entry.customSchemeId),
        topInset: full ? this.statusBarHeight : 0,
        bottomInset: full ? this.navBarHeight : 0
      })
    }
  }

  /** 阅读页实景：阅读背景与角饰、页眉、章节标题、正文（强调与段评气泡）、页脚。 */
  @Builder
  detailReaderScene(theme: ThemePack, full: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      ReaderThemeBackground({
        surfaceColor: this.activeVariant(theme).reader.backgroundColor,
        backgroundAssetId: this.activeVariant(theme).reader.backgroundAssetId,
        compact: false
      })
      Column() {
        Row() {
          Text('山野来信')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).reader.subTextColor)
          Blank()
          Text('第十二章 灯下')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).reader.subTextColor)
        }
        .width('100%')
        .height(DETAIL_READER_BAR_HEIGHT)
        // 章首装饰按主题自己的画（相当于读者开着“标题装饰”和“首字装饰”）。
        Column() {
          ThemeChapterHeadTitle({
            head: this.detailChapterHead(theme),
            numberText: '第十二章',
            titleSize: DETAIL_READER_TITLE_SIZE,
            fontFamily: theme.typography.appFontFamily,
            titleWeight: FontWeight.Bold
          }) {
            Text(ThemeChapterHeadSampleMetrics.showsNumber(this.detailChapterHead(theme), '第十二章') ?
              '灯下' : '第十二章 灯下')
              .fontSize(DETAIL_READER_TITLE_SIZE)
              .fontWeight(FontWeight.Bold)
              .fontFamily(theme.typography.appFontFamily)
              .fontColor(this.activeVariant(theme).reader.textColor)
              .width('100%')
          }
        }
        .width('100%')
        .height(this.detailReaderTitleHeight(theme))
        .justifyContent(FlexAlign.Center)
        Column() {
          if (this.detailDropCap(theme)) {
            ThemeDropCapParagraph({
              text: READER_PREVIEW_LEAD,
              head: this.detailChapterHead(theme),
              fontSize: DETAIL_READER_FONT_SIZE,
              lineHeight: DETAIL_READER_LINE_HEIGHT,
              fontFamily: theme.typography.appFontFamily,
              textColor: this.activeVariant(theme).reader.textColor,
              capFontFamily: theme.typography.appFontFamily,
              capFontWeight: FontWeight.Bold
            })
          }
          this.readerSampleText(theme, DETAIL_READER_FONT_SIZE, DETAIL_READER_LINE_HEIGHT,
            this.detailReaderLines(theme, full), this.detailDropCap(theme))
        }
        .width('100%')
        .height(this.detailReaderLines(theme, full) * DETAIL_READER_LINE_HEIGHT)
        .alignItems(HorizontalAlign.Start)
        .clip(true)
        Blank()
        Row() {
          Text('21:07 · 电量 82%')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).reader.subTextColor)
          Blank()
          Text('12 / 38 · 31.5%')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).reader.subTextColor)
        }
        .width('100%')
        .height(DETAIL_READER_BAR_HEIGHT)
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppSpacing.XXXL, right: AppSpacing.XXXL,
        top: (full ? this.statusBarHeight : 0) + AppSpacing.MD,
        bottom: (full ? this.navBarHeight : 0) + AppSpacing.MD })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  /** 全屏预览：书架、阅读页、听书面板左右滑动切换，点按画面退出。 */
  @Builder
  detailFullOverlay() {
    ForEach(this.currentDetailEntries(), (entry: ThemeListEntry) => {
      Swiper() {
        ForEach(DETAIL_FULL_SCENES, (scene: string) => {
          Stack() {
            this.detailSceneContent(entry, scene, true)
          }
          .width('100%')
          .height('100%')
        }, (scene: string) => `detail_full_scene_${scene}`)
      }
      .index(Math.max(0, DETAIL_FULL_SCENES.indexOf(this.detailFullScene)))
      .indicator(false)
      .loop(false)
      .duration(280)
      .onChange((index: number) => {
        this.detailFullScene = DETAIL_FULL_SCENES[index];
      })
      .width('100%')
      .height('100%')
      .backgroundColor(this.activeVariant(entry.theme).colors.pageColor)
      .accessibilityText('全屏预览，点按退出')
      .onClick(() => {
        this.detailFullScene = '';
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
    }, (entry: ThemeListEntry) => `detail_full_${this.themeEntryKey(entry)}`)
  }

  /** 详情底栏：试用中给结束试用与获取，其余按拥有状态给应用、试用与获取或编辑方案。 */
  @Builder
  detailActionBar(entry: ThemeListEntry) {
    Column() {
      if (!entry.customSchemeId && this.isTrialTheme(entry.theme.id)) {
        Row({ space: AppSpacing.MD }) {
          this.storeTrialButton(entry.theme)
          this.storeAcquireButton(entry.theme)
        }
        .width('100%')
      } else {
        this.storeThemeActions(entry.theme, entry.customSchemeId)
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD,
      bottom: Math.max(AppSpacing.LG, this.navBarHeight + AppSpacing.SM) })
    .backgroundColor(this.activeVariant(entry.theme).colors.pageColor)
    .border({ width: { top: 0.5 }, color: this.activeVariant(entry.theme).colors.dividerColor })
  }

  async initializeAccount(): Promise<void> {
    try {
      await HuaweiAccountService.initialize(getContext(this));
      if (AccountSessionStore.isLoggedIn() && AccountCommerceConfig.isServerConfigured()) {
        await HuaweiAccountService.refresh(getContext(this));
      }
    } catch (e) {
      console.warn('同步主题权益失败:', e);
    }
  }

  async refreshThemeCatalog(): Promise<void> {
    if (!AccountCommerceConfig.isServerConfigured()) {
      this.themeCatalogFailed = true;
      return;
    }
    this.themeCatalogFailed = false;
    try {
      const response: ThemeCatalogResponse = await AccountCommerceApi.fetchThemeCatalog();
      this.themeCatalog = response.themes || [];
      this.themeCatalogLoaded = true;
    } catch (e) {
      // Prices differ per theme, so nothing is shown or sold until the catalog
      // arrives; a previously loaded catalog stays in use.
      this.themeCatalogFailed = !this.themeCatalogLoaded;
      console.warn('同步主题目录失败:', e);
    }
  }

  async loadThemeSettings(): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const theme = settings.themeId === ThemeIds.CUSTOM ?
        AppThemeSettingsStore.customTheme(settings, this.appDarkMode) :
        BuiltinThemeRegistry.findById(settings.themeId);
      if (settings.themeBookCoverEnabled && !this.themeHasBookCover(theme)) {
        settings.themeBookCoverEnabled = false;
        await AppThemeSettingsStore.save(getContext(this), settings);
      }
      AppThemeSettingsStore.applyToStorage(settings);
      this.appThemeId = settings.themeId;
      this.themeBookCoverEnabled = settings.themeBookCoverEnabled;
      const readerSettings = await ReaderSettingsStore.load(getContext(this));
      ReaderSettingsStore.applyToStorage(readerSettings);
    } catch (e) {
      console.warn('加载主题设置失败:', e);
    }
  }

  async refreshCustomSchemes(): Promise<void> {
    const serial = ++this.customSchemeRefreshSerial;
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const schemes = await CustomThemeSchemeStore.load(getContext(this), settings);
      if (serial === this.customSchemeRefreshSerial) {
        this.customSchemes = schemes;
        this.syncSchemeOrganizeOrder();
      }
      const follows = await ReaderSettingsStore.typographyFollowsTheme(getContext(this));
      const summaries = new Map<string, string>();
      const profileIds: string[] = schemes.map((scheme: CustomThemeScheme): string =>
        ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id));
      for (const theme of BuiltinThemeRegistry.all()) {
        profileIds.push(ReaderSettingsStore.profileIdFor(theme.id, ''));
      }
      for (const profileId of profileIds) {
        if (!await ReaderSettingsStore.hasThemeTypography(getContext(this), profileId)) continue;
        const profile = await ReaderSettingsStore.loadProfile(getContext(this), profileId);
        summaries.set(profileId, `排版：字号 ${profile.fontSize} · 行距 ${profile.lineHeight} · ` +
          `边距 ${profile.marginLeft}/${profile.marginRight}`);
      }
      if (serial === this.customSchemeRefreshSerial) {
        this.typographyFollowsTheme = follows;
        this.boundLayoutSummaries = summaries;
        this.boundLayoutRevision++;
      }
    } catch (e) {
      console.warn('加载自定义主题方案失败:', e);
    }
  }

  themeLayoutSummary(theme: ThemePack, customSchemeId: string): string {
    if (!this.typographyFollowsTheme) return '排版不跟随主题，所有主题共用当前排版和翻页设置';
    const saved = this.boundLayoutRevision >= 0 ?
      this.boundLayoutSummaries.get(ReaderSettingsStore.profileIdFor(theme.id, customSchemeId)) : undefined;
    return saved ?? `预设排版：字号 ${theme.readerLayout.fontSize} · 行距 ${theme.readerLayout.lineHeight} · ` +
      `边距 ${theme.readerLayout.marginLeft}/${theme.readerLayout.marginRight}`;
  }

  async selectTheme(themeId: string, customSchemeId: string = '',
    askApplyOptions: boolean = true): Promise<void> {
    if (this.applyingThemeId) {
      return;
    }
    const customScheme = themeId === ThemeIds.CUSTOM ?
      CustomThemeSchemeStore.find(this.customSchemes, customSchemeId) : null;
    if (themeId === ThemeIds.CUSTOM && !customScheme) {
      return;
    }
    if (customScheme) {
      const unavailableStartupTheme = this.unavailableCustomStartupTheme(customScheme.settings);
      if (unavailableStartupTheme) {
        HdsFeedback.showToast(`方案使用的主题「${unavailableStartupTheme}」尚未获取或已过期`);
        return;
      }
      if (this.customSchemePackMissing(customScheme.id)) {
        if (this.customSchemeInCloud(customScheme.id)) HdsFeedback.showToast('正在下载云端的主题素材…');
        try {
          await CloudThemeSync.ensureSchemePacks(getContext(this), customScheme);
        } catch (e) {
          HdsFeedback.showToast(`主题素材下载失败：${(e as Error).message}`);
        }
      }
    }
    if (ThemeTrialManager.isActive()) {
      ThemeTrialManager.stop(getContext(this) as common.UIAbilityContext);
      this.appThemeId = AppStorage.get<string>('appThemeId') || AppThemeSettingsStore.DEFAULT_THEME_ID;
      this.themeBookCoverEnabled = AppStorage.get<boolean>('appThemeBookCoverEnabled') || false;
    }
    if (themeId === this.appThemeId && themeId !== ThemeIds.CUSTOM) {
      return;
    }
    const accessible = await this.ensureThemeAccess(themeId);
    if (!accessible) {
      return;
    }
    this.applyingThemeId = customSchemeId || themeId;
    try {
      const theme = customScheme ? this.customThemeFor(customScheme, this.appDarkMode) : BuiltinThemeRegistry.findById(themeId);
      const previous: AppThemeSettings = await AppThemeSettingsStore.load(getContext(this));
      // 排版跟随主题时每套主题记着自己的排版，切换即取回，只有第一次使用的主题要选起点；
      // 不跟随时排版始终沿用当前这套，弹窗里不出现排版选项。
      const targetProfileId = ReaderSettingsStore.profileIdFor(themeId, customScheme ? customScheme.id : '');
      const firstUse = await ReaderSettingsStore.typographyFollowsTheme(getContext(this)) &&
        !await ReaderSettingsStore.hasThemeTypography(getContext(this), targetProfileId);
      const currentReader = await ReaderSettingsStore.load(getContext(this));
      const choice: ThemeApplyChoice | null = askApplyOptions ?
        await this.promptThemeApplyOptions(theme, firstUse, currentReader) : ThemeApplyChoice.preserve();
      if (!choice) {
        return;
      }
      // 应用前记下当前档案：自定义方案之间切换时主题 ID 都是 custom，靠方案 ID 区分各自的排版。
      const previousProfileId = ReaderSettingsStore.activeProfileId();
      let settings: AppThemeSettings = AppThemeSettingsStore.activateTheme(themeId, previous);
      if (customScheme) {
        settings = AppThemeSettingsStore.applyCustomSnapshot(settings, customScheme.settings);
      }
      settings.themeBookCoverEnabled = choice.applyCover;
      AppThemeSettingsStore.applyToStorage(settings);
      await AppThemeSettingsStore.save(getContext(this), settings);
      if (customScheme) {
        await CustomThemeSchemeStore.setActiveScheme(getContext(this), customScheme);
        this.activeCustomSchemeId = customScheme.id;
        this.activeCustomSchemeRevision = customScheme.revision;
      }
      this.appThemeId = settings.themeId;
      this.themeBookCoverEnabled = settings.themeBookCoverEnabled;
      if (themeId !== ThemeIds.CUSTOM) {
        await this.recordRecentUse(themeId);
      } else if (customScheme) {
        await this.recordRecentUse(ThemeRecentStore.schemeKey(customScheme.id));
      }
      const readerSettings = await ReaderSettingsStore.switchThemeProfile(getContext(this), previousProfileId,
        ReaderSettingsStore.profileIdFor(settings.themeId, customScheme ? customScheme.id : ''));
      if (firstUse && choice.usePresetLayout) {
        const layout = theme.readerLayout;
        await ReaderSettingsStore.restoreThemePreset(getContext(this), layout.fontSize, layout.lineHeight,
          layout.paragraphSpacing, layout.marginLeft, layout.marginRight, layout.marginTop, layout.marginBottom,
          layout.letterSpacing);
      }
      await ReaderSettingsStore.saveThemeSettings(getContext(this), ReaderThemeHelper.APP_THEME_INDEX,
        ReaderThemeHelper.APP_THEME_INDEX, readerSettings.lightCustomThemeBackgroundColor,
        readerSettings.lightCustomThemeTextColor, readerSettings.darkCustomThemeBackgroundColor,
        readerSettings.darkCustomThemeTextColor, this.appDarkMode, readerSettings.customThemesRaw);
      this.readerLightThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
      this.readerDarkThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
      await ReaderFontBootstrap.registerThemeFontFromSettings(getContext(this), this.getUIContext());
      ReaderFontBootstrap.applyApplicationFont(getContext(this), 'theme-settings');
      this.refreshRecentReadCard();
      this.syncBars();
      let iconNotice = '';
      if (choice.applyIcon) {
        if (!AppIconManager.isSupported()) {
          iconNotice = `；桌面图标未更换，${AppIconManager.UNSUPPORTED_MESSAGE}`;
        } else {
          try {
            await AppIconManager.applyIcon(getContext(this), AppIconManager.optionForTheme(theme.id));
          } catch (error) {
            console.warn('应用主题桌面图标失败:', error);
            iconNotice = AppIconManager.isSetFailed(error) ?
              '；桌面图标未更换，可能是系统主题替换了本应用图标' : '；桌面图标切换失败，可在图标设置中重试';
          }
        }
      }
      const layoutNotice = !firstUse ? '' : choice.usePresetLayout ? '，使用主题预设排版' : '，沿用当前排版';
      HdsFeedback.showToast(`已应用「${theme.name}」主题${layoutNotice}${iconNotice}`);
      this.refreshCustomSchemes();
    } catch (e) {
      console.error('应用主题失败:', e);
      HdsFeedback.showToast('应用主题失败，请稍后重试');
    } finally {
      this.applyingThemeId = '';
    }
  }

  promptThemeApplyOptions(theme: ThemePack, firstUse: boolean,
    currentReader: ReaderSettings): Promise<ThemeApplyChoice | null> {
    this.applyDialogThemeName = theme.name;
    this.applyDialogHasCover = this.themeHasBookCover(theme);
    this.applyDialogFirstUse = firstUse;
    if (firstUse) {
      const preset = theme.readerLayout;
      this.applyDialogLayoutOnHint = `第一次使用这套主题，排版换成主题预设：${this.layoutSummary(preset.fontSize,
        preset.lineHeight, preset.paragraphSpacing, preset.marginLeft, preset.marginRight)}`;
      this.applyDialogLayoutOffHint = `第一次使用这套主题，沿用当前排版：${this.layoutSummary(
        currentReader.fontSize, currentReader.lineHeight, currentReader.paragraphSpacing, currentReader.marginLeft,
        currentReader.marginRight)}`;
      // 默认沿用当前排版，不让调好的字号和页眉页脚在换主题时意外丢失。
      this.applyDialogApplyLayout = false;
    }
    // 主题带封面时默认勾选“应用主题封面”，不再沿用上次的选择。
    this.applyDialogApplyCover = this.applyDialogHasCover;
    // 桌面图标默认不随主题更换，由用户主动打开。
    this.applyDialogApplyIcon = false;
    this.showThemeApplyDialog = true;
    return new Promise<ThemeApplyChoice | null>(
      (resolve: (choice: ThemeApplyChoice | null) => void) => {
        this.pendingApplyChoice = resolve;
      });
  }

  confirmThemeApply(): void {
    const choice = new ThemeApplyChoice();
    choice.usePresetLayout = this.applyDialogFirstUse && this.applyDialogApplyLayout;
    choice.applyCover = this.applyDialogHasCover && this.applyDialogApplyCover;
    choice.applyIcon = this.applyDialogApplyIcon;
    const resolve = this.pendingApplyChoice;
    this.closeThemeApplyDialog();
    if (resolve) {
      resolve(choice);
    }
  }

  cancelThemeApply(): void {
    const resolve = this.pendingApplyChoice;
    this.closeThemeApplyDialog();
    if (resolve) {
      resolve(null);
    }
  }

  layoutSummary(fontSize: number, lineHeight: number, paragraphSpacing: number, marginLeft: number,
    marginRight: number): string {
    return `字号 ${fontSize} · 行距 ${lineHeight} · 段距 ${paragraphSpacing} · 边距 ${marginLeft}/${marginRight}`;
  }

  closeThemeApplyDialog(): void {
    this.showThemeApplyDialog = false;
    this.pendingApplyChoice = null;
    this.applyDialogThemeName = '';
    this.applyDialogLayoutOnHint = '';
    this.applyDialogLayoutOffHint = '';
    this.applyDialogFirstUse = false;
    this.applyDialogHasCover = false;
  }

  async ensureThemeAccess(themeId: string): Promise<boolean> {
    if (themeId === ThemeIds.CUSTOM || this.hasThemeAccess(themeId)) {
      return true;
    }
    if (SuperExclusiveThemes.has(themeId)) return this.claimExclusiveTheme(themeId);
    const offer = this.themeOffer(themeId);
    if (!offer) {
      if (this.themeCatalogLoaded) {
        HdsFeedback.showToast('该主题暂未上架');
      } else {
        HdsFeedback.showToast('主题价格尚未加载，请稍后重试');
        this.refreshThemeCatalog();
      }
      return false;
    }
    const pricePoints = offer.pricePoints;
    const validDays = offer.validDays;
    if (!this.accountLoggedIn) {
      const loginDialog = await promptAction.showDialog({
        title: '登录后获取主题',
        message: `该主题需要 ${pricePoints} 点，获取后有效 ${validDays} 天。首次登录免费送 300 点。`,
        buttons: [
          { text: '取消', color: this.subTextColor() },
          { text: '去登录', color: this.accentColor() }
        ]
      });
      if (loginDialog.index === 1) {
        router.pushUrl({ url: 'pages/AccountCenter' });
      }
      return false;
    }
    const theme = BuiltinThemeRegistry.findById(themeId);
    const confirm = await promptAction.showDialog({
      title: `获取「${theme.name}」`,
      message: `将扣除 ${pricePoints} 点，主题有效期为 ${validDays} 天。有效期内可在所有已登录终端使用。`,
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: `确认 · ${pricePoints} 点`, color: this.accentColor() }
      ]
    });
    if (confirm.index !== 1) {
      return false;
    }
    try {
      await HuaweiAccountService.redeemTheme(getContext(this), themeId, pricePoints, validDays);
      HdsFeedback.showToast(`已获取「${theme.name}」，有效期 ${validDays} 天`);
      return true;
    } catch (e) {
      const error = e as AccountApiError;
      if (error.errorCode === 'THEME_OFFER_CHANGED') {
        await this.refreshThemeCatalog();
        HdsFeedback.showToast('主题价格或有效期已更新，请重新确认');
      } else if (error.errorCode === 'INSUFFICIENT_POINTS') {
        const recharge = await promptAction.showDialog({
          title: '点数不足',
          message: `当前有 ${this.accountPoints} 点，获取该主题需要 ${pricePoints} 点。`,
          buttons: [
            { text: '取消', color: this.subTextColor() },
            { text: '去充值', color: this.accentColor() }
          ]
        });
        if (recharge.index === 1) {
          router.pushUrl({ url: 'pages/AccountCenter' });
        }
      } else {
        HdsFeedback.showToast(error.message || '获取主题失败，请稍后重试');
      }
      return false;
    }
  }

  themeOffer(themeId: string): ThemeCatalogItem | null {
    for (let index = 0; index < this.themeCatalog.length; index++) {
      const offer = this.themeCatalog[index];
      if (offer && offer.themeId === themeId &&
        (offer.pricePoints > 0 || offer.acquisition === 'SUPER_CLAIM') && offer.validDays > 0) {
        return offer;
      }
    }
    return null;
  }

  async claimExclusiveTheme(themeId: string): Promise<boolean> {
    const name = BuiltinThemeRegistry.findById(themeId).name;
    if (!this.accountLoggedIn) {
      HdsFeedback.showToast('请登录终身超级会员账号后领取');
      router.pushUrl({ url: 'pages/AccountCenter' });
      return false;
    }
    try {
      await HuaweiAccountService.refresh(getContext(this));
      if (AccountSessionStore.activeMembershipSku() !== 'SUPER_LIFETIME') {
        HdsFeedback.showToast(`「${name}」仅供终身超级会员领取，不支持点数购买`);
        router.pushUrl({ url: 'pages/AccountCenter' });
        return false;
      }
      if (AccountSessionStore.hasOwnedEntitlement(themeId)) return true;
      if (!this.themeOffer(themeId)) {
        await this.refreshThemeCatalog();
        if (!this.themeOffer(themeId)) {
          HdsFeedback.showToast('专属主题暂未开放领取，请稍后再试');
          return false;
        }
      }
      const choice = await promptAction.showDialog({
        title: `领取「${name}」`,
        message: '终身超级会员专属，不扣除点数。领取后有效一年，到期后可再次手动领取；有效期内不重复叠加。',
        buttons: [{ text: '取消', color: this.subTextColor() }, { text: '领取一年', color: this.accentColor() }]
      });
      if (choice.index !== 1) return false;
      await MembershipCommerceService.claimSuperTheme(getContext(this), themeId);
      HdsFeedback.showToast(`已领取「${name}」，有效一年`);
      return AccountSessionStore.hasOwnedEntitlement(themeId);
    } catch (e) {
      HdsFeedback.showToast((e as Error).message || '领取失败，请稍后重试');
      return false;
    }
  }

  async setThemeBookCoverEnabled(enabled: boolean): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      settings.themeBookCoverEnabled = enabled;
      AppThemeSettingsStore.applyToStorage(settings);
      await AppThemeSettingsStore.save(getContext(this), settings);
      this.themeBookCoverEnabled = enabled;
      HdsFeedback.showToast(enabled ? '已启用主题封面与书籍边框' : '已恢复图书原封面');
    } catch (e) {
      console.error('保存主题封面设置失败:', e);
      HdsFeedback.showToast('保存主题封面设置失败');
    }
  }

  refreshRecentReadCard(): void {
    const context = getContext(this) as common.UIAbilityContext;
    RecentReadCardUpdater.reload(context).catch((e: Error) => {
      console.warn('主题切换后刷新最近阅读卡片失败:', e);
    });
  }

  customTheme(scheme: CustomThemeScheme): ThemePack {
    return this.customThemeFor(scheme, this.variantDark());
  }

  customThemeFor(scheme: CustomThemeScheme, darkMode: boolean): ThemePack {
    const theme = AppThemeSettingsStore.customTheme(scheme.settings, darkMode);
    theme.name = scheme.name;
    theme.description = '自由组合浅色与深色模式下的主题部件';
    return theme;
  }

  /** 预览用的深浅色：详情页打开时跟详情页里的切换，否则跟应用。 */
  variantDark(): boolean {
    return this.detailOpen ? this.detailDark : this.appDarkMode;
  }

  activeVariant(theme: ThemePack): ThemeVariant {
    return this.variantDark() ? theme.dark : theme.light;
  }

  isSelected(theme: ThemePack, customSchemeId: string = ''): boolean {
    if (theme.id === ThemeIds.CUSTOM) {
      const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
      return this.appThemeId === ThemeIds.CUSTOM && this.activeCustomSchemeId === customSchemeId &&
        !!scheme && scheme.revision === this.activeCustomSchemeRevision;
    }
    return theme.id === this.appThemeId;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  titleBarSurfaceColor(): string {
    return ThemeRuntime.topBarColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  storeThemeActions(theme: ThemePack, customSchemeId: string = '') {
    if (theme.id === ThemeIds.CUSTOM) {
      Row({ space: AppSpacing.MD }) {
        Button('编辑方案', { type: ButtonType.Normal })
          .borderRadius(this.storeButtonRadius(theme))
          .height(44)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.activeVariant(theme).colors.accentColor)
          .backgroundColor(this.activeVariant(theme).colors.inputColor)
          .layoutWeight(1)
          .onClick(() => {
            router.pushUrl({
              url: 'pages/ThemeColorSettings',
              params: { schemeId: customSchemeId }
            });
          })
        Button(this.isSelected(theme, customSchemeId) ? '正在使用' : '应用方案', { type: ButtonType.Normal })
          .borderRadius(this.storeButtonRadius(theme))
          .height(44)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.buttonColor))
          .backgroundColor(this.activeVariant(theme).colors.buttonColor)
          .layoutWeight(1)
          .enabled(!this.isSelected(theme, customSchemeId))
          .onClick(() => {
            this.selectTheme(theme.id, customSchemeId);
          })
      }
      .width('100%')
    } else if (this.isSelected(theme)) {
      Row({ space: AppSpacing.MD }) {
        if (this.canBaseSchemeOn(theme)) {
          this.newSchemeButton(theme)
        }
        Row() {
          Text(this.isTrialTheme(theme.id) ? '试用中 · 5分钟后自动恢复' : '正在使用该主题')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).colors.accentColor)
        }
        .layoutWeight(1)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius(this.storeButtonRadius(theme))
        .backgroundColor(this.activeVariant(theme).colors.inputColor)
      }
      .width('100%')
    } else if (BuiltinThemeRegistry.isFree(theme.id) || AccountSessionStore.hasValidEntitlement(theme.id)) {
      Row({ space: AppSpacing.MD }) {
        if (this.canBaseSchemeOn(theme)) {
          this.newSchemeButton(theme)
        }
        Button('应用主题', { type: ButtonType.Normal })
          .borderRadius(this.storeButtonRadius(theme))
          .layoutWeight(1)
          .height(44)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.buttonColor))
          .backgroundColor(this.activeVariant(theme).colors.buttonColor)
          .onClick(() => {
            this.selectTheme(theme.id);
          })
      }
      .width('100%')
    } else {
      Row({ space: AppSpacing.MD }) {
        if (!SuperExclusiveThemes.has(theme.id)) {
          this.storeTrialButton(theme)
        }
        this.storeAcquireButton(theme)
      }
      .width('100%')
    }
  }

  @Builder
  newSchemeButton(theme: ThemePack) {
    Button(this.addingCustomScheme ? '新建中' : '以此新建方案', { type: ButtonType.Normal })
      .borderRadius(this.storeButtonRadius(theme))
      .height(44)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.activeVariant(theme).colors.accentColor)
      .backgroundColor(this.activeVariant(theme).colors.inputColor)
      .layoutWeight(1)
      .enabled(!this.addingCustomScheme)
      .onClick(() => this.createSchemeFromTheme(theme))
  }

  /** 自己能用的内置主题才能当新方案的底子（试用中的不算）；主题包不在主题库里。 */
  canBaseSchemeOn(theme: ThemePack): boolean {
    if (theme.id === ThemeIds.CUSTOM || this.isTrialTheme(theme.id) || ThemePackRegistry.isPackId(theme.id)) return false;
    if (SuperExclusiveThemes.has(theme.id)) return AccountSessionStore.hasOwnedEntitlement(theme.id);
    return BuiltinThemeRegistry.isFree(theme.id) || AccountSessionStore.hasValidEntitlement(theme.id);
  }

  /** 以某个内置主题为底子新建方案：各部件来源都指向它，直接进编辑器。 */
  async createSchemeFromTheme(theme: ThemePack): Promise<void> {
    if (this.addingCustomScheme) return;
    this.addingCustomScheme = true;
    try {
      const appSettings = await AppThemeSettingsStore.load(getContext(this));
      const settings = AppThemeSettingsStore.activateTheme(ThemeIds.CUSTOM,
        AppThemeSettingsStore.createForTheme(theme.id));
      const added = await CustomThemeSchemeStore.addWith(getContext(this), appSettings, `${theme.name} 改`, settings);
      if (!added) {
        this.refreshCustomSchemeLimit();
        HdsFeedback.showToast(`当前权益最多可创建 ${this.customSchemeLimit} 套自定义主题，已有方案保留`);
        return;
      }
      await this.refreshCustomSchemes();
      HdsFeedback.showToast(`已新建「${added.name}」`);
      router.pushUrl({ url: 'pages/ThemeColorSettings', params: { schemeId: added.id } });
    } catch (e) {
      console.error('以主题新建方案失败:', e);
      HdsFeedback.showToast('新建方案失败，请稍后重试');
    } finally {
      this.addingCustomScheme = false;
    }
  }

  /** 复制方案：设置、自传素材、本机图片和阅读排版各复制一份，之后两套互不影响。 */
  async duplicateCustomScheme(schemeId: string): Promise<void> {
    if (this.addingCustomScheme) return;
    this.addingCustomScheme = true;
    try {
      const added = await SchemeAssetService.duplicateScheme(getContext(this), schemeId);
      if (!added) {
        this.refreshCustomSchemeLimit();
        HdsFeedback.showToast(`当前权益最多可创建 ${this.customSchemeLimit} 套自定义主题，已有方案保留`);
        return;
      }
      await this.refreshCustomSchemes();
      HdsFeedback.showToast(`已复制为「${added.name}」`);
    } catch (e) {
      console.error('复制自定义主题方案失败:', e);
      HdsFeedback.showToast((e as Error).message || '复制方案失败，请稍后重试');
    } finally {
      this.addingCustomScheme = false;
    }
  }

  @Builder
  storeTrialButton(theme: ThemePack) {
    Button(this.isTrialTheme(theme.id) ? '结束试用' : '试用5分钟', { type: ButtonType.Normal })
      .borderRadius(this.storeButtonRadius(theme))
      .height(44)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.activeVariant(theme).colors.accentColor)
      .backgroundColor(this.activeVariant(theme).colors.inputColor)
      .layoutWeight(1)
      .onClick(() => {
        if (this.isTrialTheme(theme.id)) {
          this.stopThemeTrial();
        } else {
          this.startThemeTrial(theme);
        }
      })
  }

  @Builder
  storeAcquireButton(theme: ThemePack) {
    Button(this.acquireButtonLabel(theme.id, '获取'), { type: ButtonType.Normal })
      .borderRadius(this.storeButtonRadius(theme))
      .height(44)
      .fontSize(AppFontSize.BODY)
      .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.buttonColor))
      .backgroundColor(this.activeVariant(theme).colors.buttonColor)
      .layoutWeight(1)
      .enabled(this.acquireButtonEnabled(theme.id))
      .onClick(() => this.onAcquireButtonTap(theme.id))
  }

  /**
   * The theme running right now: the trial theme while a trial is active,
   * otherwise the applied builtin theme or custom scheme. Empty until the
   * active custom scheme has loaded.
   */
  currentThemeEntries(): ThemeListEntry[] {
    if (this.appThemeId === ThemeIds.CUSTOM) {
      const scheme = CustomThemeSchemeStore.find(this.customSchemes, this.activeCustomSchemeId);
      return scheme ? [new ThemeListEntry(this.customTheme(scheme), scheme.id)] : [];
    }
    return [new ThemeListEntry(BuiltinThemeRegistry.findById(this.appThemeId))];
  }

  /** 免费的默认主题加上有有效权益的主题，排在色块条最前面。 */
  ownedThemeEntries(): ThemeListEntry[] {
    const entries: ThemeListEntry[] = [new ThemeListEntry(BuiltinThemeRegistry.findById(ThemeIds.PLAIN_DEFAULT))];
    for (const theme of this.purchasedThemes()) {
      entries.push(new ThemeListEntry(theme));
    }
    return entries;
  }

  /** 全部方案按当前排序（置顶在前），“我的”页、详情左右切换都用这个顺序。 */
  schemeEntries(): ThemeListEntry[] {
    return this.schemeEntriesOf(this.sortedSchemes(false));
  }

  schemePreviewEntries(): ThemeListEntry[] {
    return this.schemeEntries().slice(0, SCHEME_PREVIEW_COUNT);
  }

  entrySelectKey(entry: ThemeListEntry): string {
    return entry.customSchemeId ? `scheme:${entry.customSchemeId}` : `theme:${entry.theme.id}`;
  }

  async loadRecentThemes(): Promise<void> {
    this.recentThemeIds = await ThemeRecentStore.load(getContext(this));
    this.recentUseTimes = await ThemeRecentStore.loadTimes(getContext(this));
    this.recentUseRevision++;
    const sort = await ThemeRecentStore.loadSchemeSort(getContext(this));
    if (SCHEME_SORTS.indexOf(sort) >= 0) this.schemeSort = sort;
  }

  async recordRecentUse(key: string): Promise<void> {
    this.recentThemeIds = await ThemeRecentStore.record(getContext(this), key);
    this.recentUseTimes = await ThemeRecentStore.loadTimes(getContext(this));
    this.recentUseRevision++;
  }

  schemeSortLabel(sort: string): string {
    if (sort === 'modified') return '最近修改';
    if (sort === 'created') return '创建时间';
    if (sort === 'name') return '名称';
    if (sort === 'manual') return '手动排序';
    return '最近使用';
  }

  schemeFilterLabel(filter: string): string {
    if (filter === 'self') return '自建';
    if (filter === 'import') return '导入';
    return '全部';
  }

  schemeMatchesFilter(scheme: CustomThemeScheme, filter: string): boolean {
    if (filter === 'self') return !scheme.imported;
    if (filter === 'import') return scheme.imported;
    return true;
  }

  schemeIsActive(schemeId: string): boolean {
    return this.appThemeId === ThemeIds.CUSTOM && this.activeCustomSchemeId === schemeId;
  }

  schemeUsedAt(schemeId: string): number {
    return this.recentUseRevision >= 0 ? (this.recentUseTimes.get(ThemeRecentStore.schemeKey(schemeId)) || 0) : 0;
  }

  /**
   * 按当前排序排好的方案，置顶的在前。filtered 为 true 时再套上全部页的筛选和搜索。
   * 最近使用：正在用的最前，其余按应用时间，没用过的按创建时间新的在前；手动就是存储里的顺序。
   */
  sortedSchemes(filtered: boolean): CustomThemeScheme[] {
    const query = filtered ? this.schemeQuery.trim().toLowerCase() : '';
    const list = this.customSchemes.filter((scheme: CustomThemeScheme): boolean =>
      (!filtered || this.schemeMatchesFilter(scheme, this.schemeFilter)) &&
        (!query || scheme.name.toLowerCase().includes(query) || scheme.author.toLowerCase().includes(query)));
    const position = new Map<string, number>();
    this.customSchemes.forEach((scheme: CustomThemeScheme, index: number) => position.set(scheme.id, index));
    const sort = this.schemeSort;
    list.sort((a: CustomThemeScheme, b: CustomThemeScheme): number => {
      if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
      if (sort === 'recent') {
        const activeA = this.schemeIsActive(a.id) ? 1 : 0;
        const activeB = this.schemeIsActive(b.id) ? 1 : 0;
        if (activeA !== activeB) return activeB - activeA;
        const used = this.schemeUsedAt(b.id) - this.schemeUsedAt(a.id);
        if (used !== 0) return used;
        return b.createdAt - a.createdAt;
      }
      if (sort === 'modified') return b.updatedAt - a.updatedAt;
      if (sort === 'created') return b.createdAt - a.createdAt;
      if (sort === 'name') return a.name.localeCompare(b.name, 'zh');
      return (position.get(a.id) || 0) - (position.get(b.id) || 0);
    });
    return list;
  }

  schemeEntriesOf(schemes: CustomThemeScheme[]): ThemeListEntry[] {
    return schemes.map((scheme: CustomThemeScheme): ThemeListEntry =>
      new ThemeListEntry(this.customTheme(scheme), scheme.id));
  }

  /** 全部页筛选后的方案，分成置顶和其他两段。 */
  schemeListEntries(pinned: boolean): ThemeListEntry[] {
    return this.schemeEntriesOf(this.sortedSchemes(true)
      .filter((scheme: CustomThemeScheme): boolean => scheme.pinned === pinned));
  }

  schemePinned(schemeId: string): boolean {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    return !!scheme && scheme.pinned;
  }

  /** 行第二行跟着排序带一句时间，看得出为什么排在这；名称和手动排序不带。 */
  schemeSortMeta(schemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    if (!scheme) return '';
    if (this.schemeSort === 'recent') {
      if (this.schemeIsActive(schemeId)) return '';
      const usedAt = this.schemeUsedAt(schemeId);
      return usedAt > 0 ? `${this.relativeTime(usedAt)}用过` : '还没用过';
    }
    if (this.schemeSort === 'modified') {
      return scheme.updatedAt > 0 ? `${this.relativeTime(scheme.updatedAt)}修改` : '';
    }
    if (this.schemeSort === 'created') {
      return scheme.createdAt > 0 ? `${this.calendarDate(scheme.createdAt)}创建` : '';
    }
    return '';
  }

  relativeTime(at: number): string {
    const minutes = Math.floor((Date.now() - at) / 60000);
    if (minutes < 1) return '刚刚';
    if (minutes < 60) return `${minutes} 分钟前`;
    if (minutes < 24 * 60) return `${Math.floor(minutes / 60)} 小时前`;
    const days = Math.floor(minutes / (24 * 60));
    if (days === 1) return '昨天';
    if (days < 7) return `${days} 天前`;
    return this.calendarDate(at);
  }

  calendarDate(at: number): string {
    const date = new Date(at);
    const sameYear = date.getFullYear() === new Date().getFullYear();
    return `${sameYear ? '' : `${date.getFullYear()}年`}${date.getMonth() + 1}月${date.getDate()}日`;
  }

  setSchemeSort(sort: string): void {
    this.schemeSortMenuOpen = false;
    if (this.schemeSort === sort) return;
    this.schemeSort = sort;
    this.syncSchemeOrganizeOrder();
    ThemeRecentStore.saveSchemeSort(getContext(this), sort);
  }

  setSchemeFilter(filter: string): void {
    this.schemeFilter = filter;
    this.syncSchemeOrganizeOrder();
  }

  openSchemeList(): void {
    this.schemeFilter = 'all';
    this.schemeQuery = '';
    this.schemeOrganizing = false;
    this.schemeSelected = [];
    this.schemeListOpen = true;
  }

  closeSchemeList(): void {
    this.schemeListOpen = false;
    this.schemeOrganizing = false;
    this.schemeSortMenuOpen = false;
    this.schemeSelected = [];
  }

  startSchemeOrganize(): void {
    this.schemeSelected = [];
    this.schemeOrganizing = true;
    this.syncSchemeOrganizeOrder();
  }

  stopSchemeOrganize(): void {
    this.schemeOrganizing = false;
    this.schemeSelected = [];
  }

  /** 整理模式里两段的顺序跟着当前排序、筛选和方案列表重建；选中的项里删掉已经不在的。 */
  syncSchemeOrganizeOrder(): void {
    const sorted = this.sortedSchemes(true);
    this.schemeOrderPinned = sorted.filter((item: CustomThemeScheme): boolean => item.pinned)
      .map((item: CustomThemeScheme): string => item.id);
    this.schemeOrderRest = sorted.filter((item: CustomThemeScheme): boolean => !item.pinned)
      .map((item: CustomThemeScheme): string => item.id);
    const visible = [...this.schemeOrderPinned, ...this.schemeOrderRest];
    if (this.schemeSelected.some((id: string): boolean => visible.indexOf(id) < 0)) {
      this.schemeSelected = this.schemeSelected.filter((id: string): boolean => visible.indexOf(id) >= 0);
    }
  }

  /** 筛选或搜索时只看到一部分方案，拖动会把看不到的挤乱，所以只在看全部时允许。 */
  schemeDragEnabled(): boolean {
    return this.schemeOrganizing && this.schemeFilter === 'all' && !this.schemeQuery.trim();
  }

  toggleSchemeSelected(schemeId: string): void {
    if (this.schemeSelected.indexOf(schemeId) >= 0) {
      this.schemeSelected = this.schemeSelected.filter((id: string): boolean => id !== schemeId);
    } else {
      this.schemeSelected = [...this.schemeSelected, schemeId];
    }
  }

  toggleSelectAllSchemes(): void {
    const visible = [...this.schemeOrderPinned, ...this.schemeOrderRest];
    this.schemeSelected = this.schemeSelected.length === visible.length ? [] : visible;
  }

  selectedSchemesAllPinned(): boolean {
    return this.schemeSelected.length > 0 &&
      this.schemeSelected.every((id: string): boolean => this.schemePinned(id));
  }

  moveSchemeDuringDrag(pinned: boolean, from: number, to: number): void {
    const ids = pinned ? [...this.schemeOrderPinned] : [...this.schemeOrderRest];
    if (from < 0 || from >= ids.length || to < 0 || to >= ids.length) return;
    const moved = ids.splice(from, 1);
    ids.splice(to, 0, moved[0]);
    if (pinned) {
      this.schemeOrderPinned = ids;
    } else {
      this.schemeOrderRest = ids;
    }
  }

  /** 松手后写回：拖动时看到的就是全部方案，顺序整个存下，排序换成“手动排序”。 */
  async commitSchemeOrder(): Promise<void> {
    const ordered = [...this.schemeOrderPinned, ...this.schemeOrderRest];
    const before = this.sortedSchemes(true).map((item: CustomThemeScheme): string => item.id);
    if (ordered.join('\n') === before.join('\n')) return;
    const switched = this.schemeSort !== 'manual';
    this.schemeSort = 'manual';
    ThemeRecentStore.saveSchemeSort(getContext(this), 'manual');
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      await CustomThemeSchemeStore.reorder(getContext(this), settings, ordered);
      await this.refreshCustomSchemes();
      if (switched) HdsFeedback.showToast('已改为手动排序');
    } catch (e) {
      console.error('保存方案顺序失败:', e);
      HdsFeedback.showToast('保存顺序失败，请稍后重试');
      this.syncSchemeOrganizeOrder();
    }
  }

  async setSchemesPinned(schemeIds: string[], pinned: boolean): Promise<void> {
    if (schemeIds.length === 0) return;
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      await CustomThemeSchemeStore.setPinned(getContext(this), settings, schemeIds, pinned);
      await this.refreshCustomSchemes();
      const one = schemeIds.length === 1 ? CustomThemeSchemeStore.find(this.customSchemes, schemeIds[0]) : null;
      if (pinned) {
        HdsFeedback.showToast(one ? `已置顶「${one.name}」` : `已置顶 ${schemeIds.length} 套方案`);
      } else {
        HdsFeedback.showToast(one ? `已取消置顶「${one.name}」` : `已取消置顶 ${schemeIds.length} 套方案`);
      }
    } catch (e) {
      console.error('置顶方案失败:', e);
      HdsFeedback.showToast('操作失败，请稍后重试');
    }
  }

  async batchPinSelectedSchemes(): Promise<void> {
    const ids = [...this.schemeSelected];
    const pin = !this.selectedSchemesAllPinned();
    this.schemeSelected = [];
    await this.setSchemesPinned(ids, pin);
  }

  requestDeleteSelectedSchemes(): void {
    const ids = [...this.schemeSelected];
    if (ids.length === 0) return;
    if (ids.length >= this.customSchemes.length) {
      HdsFeedback.showToast('至少需要保留一套自定义主题');
      return;
    }
    this.deleteSchemeIds = ids;
    this.actionCustomSchemeId = '';
    this.showDeleteCustomThemeDialog = true;
  }

  /** 已拥有主题：recent 按最近应用排（当前主题最前，没用过的保持原顺序），name 按名称。 */
  sortedOwnedEntries(sort: string): ThemeListEntry[] {
    const entries = this.ownedThemeEntries();
    if (sort === 'name') {
      entries.sort((a: ThemeListEntry, b: ThemeListEntry): number => a.theme.name.localeCompare(b.theme.name, 'zh'));
      return entries;
    }
    const rank = (entry: ThemeListEntry): number => {
      if (entry.theme.id === this.appThemeId) return -1;
      const index = this.recentThemeIds.indexOf(entry.theme.id);
      return index < 0 ? Number.MAX_SAFE_INTEGER : index;
    };
    entries.sort((a: ThemeListEntry, b: ThemeListEntry): number => rank(a) - rank(b));
    return entries;
  }

  /** “我的”页露出的几套已拥有主题；当前主题已在大图里，不重复。 */
  ownedPreviewEntries(): ThemeListEntry[] {
    return this.sortedOwnedEntries('recent')
      .filter((entry: ThemeListEntry): boolean => entry.theme.id !== this.appThemeId)
      .slice(0, OWNED_PREVIEW_COUNT);
  }

  themeRowSubtitle(entry: ThemeListEntry): string {
    if (entry.customSchemeId) {
      if (this.customSchemeInCloud(entry.customSchemeId)) return '素材在云端 · 应用或打开时下载';
      if (this.customSchemePackMissing(entry.customSchemeId)) return '主题包素材不在这台设备上';
      if (this.isCustomSchemePending(entry.theme, entry.customSchemeId)) return '有改动 · 待应用';
      const meta = this.schemeSortMeta(entry.customSchemeId);
      const sources = this.schemeSourcesSummary(entry.customSchemeId);
      return meta ? `${meta} · ${sources}` : sources;
    }
    return this.themeAccessLabel(entry.theme.id);
  }

  /** 方案概要：浅色和深色各自的主体来自哪套主题。 */
  schemeSourcesSummary(schemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    if (!scheme) return '自定义方案';
    const light = BuiltinThemeRegistry.findById(scheme.settings.customLightSources.paletteThemeId).name;
    const dark = BuiltinThemeRegistry.findById(scheme.settings.customDarkSources.paletteThemeId).name;
    return `浅色 ${light} · 深色 ${dark}`;
  }

  schemeParts(schemeId: string): SchemePartRow[] {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    if (!scheme) return [];
    const sources = this.variantDark() ? scheme.settings.customDarkSources : scheme.settings.customLightSources;
    const name = (themeId: string): string => `来自 ${BuiltinThemeRegistry.findById(themeId).name}`;
    return [
      new SchemePartRow('启动封面', this.customPreviewStartupImage(schemeId) ? '自定义图片' : name(sources.startupThemeId)),
      new SchemePartRow('页面配色', name(sources.paletteThemeId)),
      new SchemePartRow('阅读页', name(sources.readerThemeId)),
      new SchemePartRow('听书面板', name(sources.ttsPanelThemeId || sources.readerThemeId)),
      new SchemePartRow('强调气泡', name(sources.bubbleThemeId)),
      new SchemePartRow('导航图标', name(sources.navigationThemeId)),
      new SchemePartRow('书籍封面', name(sources.bookThemeId)),
      new SchemePartRow('首页背景', name(sources.homeBackdropThemeId || sources.startupThemeId)),
      new SchemePartRow('字体', name(sources.typographyThemeId))
    ];
  }

  currentHasCoverSetting(): boolean {
    return this.appThemeId !== ThemeIds.CUSTOM && this.themeHasBookCover(BuiltinThemeRegistry.findById(this.appThemeId));
  }

  currentCanEditStartupText(): boolean {
    return this.appThemeId !== ThemeIds.CUSTOM && !this.isTrialTheme(this.appThemeId) &&
      this.canEditStartupText(BuiltinThemeRegistry.findById(this.appThemeId));
  }

  /** 主题库分组：只留实际存在的主题，没归组的放进“更多”。 */
  storeGroups(): ThemeStoreGroup[] {
    const grouped: string[] = [];
    const groups: ThemeStoreGroup[] = [];
    for (const group of THEME_STORE_GROUPS) {
      const ids = group.themeIds.filter((id: string): boolean => BuiltinThemeRegistry.has(id));
      grouped.push(...ids);
      if (ids.length > 0) groups.push(new ThemeStoreGroup(group.title, ids));
    }
    const rest: string[] = [];
    for (const theme of BuiltinThemeRegistry.all()) {
      if (grouped.indexOf(theme.id) < 0) rest.push(theme.id);
    }
    if (rest.length > 0) groups.push(new ThemeStoreGroup('更多', rest));
    return groups;
  }

  groupEntries(group: ThemeStoreGroup): ThemeListEntry[] {
    return group.themeIds.map((id: string): ThemeListEntry => new ThemeListEntry(BuiltinThemeRegistry.findById(id)));
  }

  /** 推荐横幅：第一套还没拥有的主题；全都拥有时推最后加入的那套。 */
  storeFeaturedEntries(): ThemeListEntry[] {
    const more = this.moreThemes();
    if (more.length > 0) return [new ThemeListEntry(more[0])];
    const all = BuiltinThemeRegistry.all();
    return all.length > 0 ? [new ThemeListEntry(all[all.length - 1])] : [];
  }

  storeBannerTag(entry: ThemeListEntry): string {
    if (this.isSelected(entry.theme)) return '正在使用';
    if (this.hasThemeAccess(entry.theme.id)) return '已拥有';
    return this.storeThemePriceLabel(entry.theme.id);
  }

  storeTileTag(entry: ThemeListEntry): string {
    if (this.isTrialTheme(entry.theme.id)) return '试用中';
    if (this.isSelected(entry.theme)) return '使用中';
    return this.themeAccessLabel(entry.theme.id);
  }

  detailContextEntries(context: string): ThemeListEntry[] {
    if (context === 'owned') return this.sortedOwnedEntries('recent');
    if (context === 'owned-list') return this.sortedOwnedEntries(this.ownedSort);
    if (context === 'schemes') return this.schemeEntries();
    if (context === 'scheme-list') return this.schemeEntriesOf(this.sortedSchemes(true));
    const groups = this.storeGroups();
    if (context.startsWith('group:')) {
      const title = context.substring('group:'.length);
      for (const group of groups) {
        if (group.title === title) return this.groupEntries(group);
      }
      return [];
    }
    const entries: ThemeListEntry[] = [];
    for (const group of groups) {
      entries.push(...this.groupEntries(group));
    }
    return entries;
  }

  /** 打开竖向详情，左右滑动在 context 指的那组主题里切换；不在组里时只看这一项。 */
  openDetailFor(entry: ThemeListEntry, context: string, label: string): void {
    if (entry.customSchemeId) this.prefetchSchemePacks(entry.customSchemeId);
    const keys = this.detailContextEntries(context).map((item: ThemeListEntry): string => this.entrySelectKey(item));
    const key = this.entrySelectKey(entry);
    const index = keys.indexOf(key);
    if (index < 0) {
      this.openDetail([key], 0, label);
    } else {
      this.openDetail(keys, index, label);
    }
  }

  openSchemeDetail(schemeId: string): void {
    this.prefetchSchemePacks(schemeId);
    const keys = this.schemeEntries().map((item: ThemeListEntry): string => this.entrySelectKey(item));
    const index = keys.indexOf(`scheme:${schemeId}`);
    this.openDetail(index < 0 ? [`scheme:${schemeId}`] : keys, Math.max(0, index), '我的方案');
  }

  openDetail(keys: string[], index: number, label: string): void {
    this.detailDark = this.appDarkMode;
    this.detailKeys = keys;
    this.detailIndex = index;
    this.detailLabel = label;
    this.detailOffsets.clear();
    this.detailTopSolid = false;
    this.detailFullScene = '';
    this.detailShelfLayout = this.currentShelfLayout();
    this.detailPartsOpen = false;
    this.detailCachedCount = 0;
    this.detailOpen = true;
    this.syncDetailPages();
    clearTimeout(this.detailCacheTimer);
    this.detailCacheTimer = setTimeout(() => {
      this.detailCacheTimer = -1;
      if (this.detailOpen) this.detailCachedCount = 1;
    }, 320);
  }

  /** 把 detailKeys 换成带页键的详情页列表；页键语义同 themeEntryKey，但不必为每一项现算整套方案主题。 */
  syncDetailPages(): void {
    if (!this.detailOpen) return;
    const dark = this.variantDark() ? 'dark' : 'light';
    this.detailPageSource.replace(this.detailKeys.map((key: string): string => {
      let revision = 0;
      if (key.startsWith('scheme:')) {
        const scheme = CustomThemeSchemeStore.find(this.customSchemes, key.substring('scheme:'.length));
        revision = scheme ? scheme.revision : -1;
      }
      return `${key}|${revision}_${dark}_${this.accountEntitlementsRevision}_${this.installedThemePacksRevision}`;
    }));
  }

  closeDetail(): void {
    this.detailFullScene = '';
    this.detailOpen = false;
  }

  openDetailFull(scene: string): void {
    this.detailFullScene = scene;
    HdsFeedback.showToast('左右滑动换画面，点按退出');
  }

  /** 用户当前的书架布局；取不到或不认识时按默认的陪伴布局。 */
  currentShelfLayout(): string {
    const layout = AppStorage.get<string>('bookshelfLayoutMode') ?? '';
    return DETAIL_SHELF_LAYOUTS.indexOf(layout) >= 0 ? layout : 'companion';
  }

  /** 阅读页实景里正文能放下的整行数：卡片或屏幕的高度减去页眉、标题、页脚和上下留白。 */
  detailReaderLines(theme: ThemePack, full: boolean): number {
    const height = full ? this.contextViewportHeight - this.statusBarHeight - this.navBarHeight :
      (this.contextViewportWidth - AppSpacing.LG * 2) / DETAIL_SCENE_RATIO;
    const fixed = AppSpacing.MD * 2 + DETAIL_READER_BAR_HEIGHT * 2 + this.detailReaderTitleHeight(theme) +
      AppSpacing.MD;
    return Math.max(4, Math.floor((height - fixed) / DETAIL_READER_LINE_HEIGHT));
  }

  /** 这套主题当前深浅模式的章首装饰；没设时各字段为空。 */
  detailChapterHead(theme: ThemePack): ThemePackageChapterHead {
    return normalizeChapterHead(this.activeVariant(theme).regexEmphasis.chapterHead);
  }

  detailDropCap(theme: ThemePack): boolean {
    return ThemeChapterHeadSampleMetrics.dropCapApplies(this.detailChapterHead(theme), READER_PREVIEW_LEAD);
  }

  /** 标题区高度：平时 72，饰图放大或画成分段标题放不下时按估出的高度加上下留白。 */
  detailReaderTitleHeight(theme: ThemePack): number {
    const estimate = ThemeChapterHeadSampleMetrics.estimateHeight(this.detailChapterHead(theme),
      DETAIL_READER_TITLE_SIZE, '第十二章');
    return Math.max(DETAIL_READER_TITLE_HEIGHT, Math.ceil(estimate + AppSpacing.LG));
  }

  resolveEntry(key: string): ThemeListEntry {
    if (key.startsWith('scheme:')) {
      const scheme = CustomThemeSchemeStore.find(this.customSchemes, key.substring('scheme:'.length));
      if (scheme) return new ThemeListEntry(this.customTheme(scheme), scheme.id);
    } else if (key.startsWith('theme:') && BuiltinThemeRegistry.has(key.substring('theme:'.length))) {
      return new ThemeListEntry(BuiltinThemeRegistry.findById(key.substring('theme:'.length)));
    }
    return new ThemeListEntry(BuiltinThemeRegistry.findById(ThemeIds.PLAIN_DEFAULT));
  }

  currentDetailEntries(): ThemeListEntry[] {
    if (!this.detailOpen || this.detailKeys.length === 0) return [];
    return [this.resolveEntry(this.detailKeys[Math.min(this.detailIndex, this.detailKeys.length - 1)])];
  }

  currentDetailSchemeId(): string {
    const key = this.detailKeys[this.detailIndex] || '';
    return key.startsWith('scheme:') ? key.substring('scheme:'.length) : '';
  }

  detailPageColor(): string {
    const entries = this.currentDetailEntries();
    return entries.length > 0 ? this.activeVariant(entries[0].theme).colors.pageColor : this.pageColor();
  }

  detailPositionLabel(): string {
    if (this.detailKeys.length <= 1) return this.detailLabel;
    return `${this.detailLabel} ${this.detailIndex + 1} / ${this.detailKeys.length}`;
  }

  /** 大图高度：首屏在大图下面还能露出状态卡。 */
  detailHeroHeight(): number {
    return Math.min(this.contextViewportWidth * 1.3, this.contextViewportHeight * 0.56);
  }

  /** 记下某一页滚了多少（onDidScroll 给的是每帧增量）；是正在看的那页就顺带更新顶栏。 */
  detailScrollTracker(key: string): (xOffset: number, yOffset: number) => void {
    return (_xOffset: number, yOffset: number): void => {
      this.detailOffsets.set(key, (this.detailOffsets.get(key) || 0) + yOffset);
      if (key === this.detailKeys[this.detailIndex]) this.syncDetailTopSolid();
    };
  }

  syncDetailTopSolid(): void {
    const offset = this.detailOffsets.get(this.detailKeys[this.detailIndex] || '') || 0;
    const solid = offset > this.detailHeroHeight() - PageScaffold.BAR_HEIGHT - this.statusBarHeight;
    if (solid !== this.detailTopSolid) this.detailTopSolid = solid;
  }

  detailTextColor(): string {
    const entries = this.currentDetailEntries();
    return entries.length > 0 ? this.activeVariant(entries[0].theme).colors.primaryTextColor : this.primaryTextColor();
  }

  /** 方案组成的一句摘要：全部来自同一套，或大部分来自哪套、几项不同。 */
  schemePartsSummary(schemeId: string): string {
    const parts = this.schemeParts(schemeId);
    if (parts.length === 0) return '';
    const counts = new Map<string, number>();
    for (const part of parts) {
      counts.set(part.source, (counts.get(part.source) || 0) + 1);
    }
    let main = '';
    let best = 0;
    counts.forEach((count: number, source: string) => {
      if (count > best) {
        best = count;
        main = source;
      }
    });
    return best === parts.length ? `全部${main}` : `大部分${main} · ${parts.length - best} 项不同`;
  }

  detailHeroDescription(entry: ThemeListEntry): string {
    if (this.customSchemeAuthor(entry.customSchemeId)) return themeAuthorLine(this.customSchemeAuthor(entry.customSchemeId));
    return entry.theme.description;
  }

  detailCaption(entry: ThemeListEntry): string {
    if (entry.customSchemeId) {
      if (this.isSelected(entry.theme, entry.customSchemeId)) return '正在使用的方案';
      return this.isCustomSchemePending(entry.theme, entry.customSchemeId) ? '有改动，应用后生效' : '自定义方案';
    }
    if (this.isTrialTheme(entry.theme.id)) return '试用中 · 5 分钟后自动恢复';
    if (this.isSelected(entry.theme)) return `正在使用 · ${this.storeThemeCaption(entry.theme)}`;
    return this.storeThemeCaption(entry.theme);
  }

  /** 详情页右上角“更多”：方案的编辑、排版、重命名、分享、删除，菜单贴着按钮弹出。 */
  openDetailSchemeActions(): void {
    const schemeId = this.currentDetailSchemeId();
    if (!schemeId) return;
    this.contextMenuX = Math.max(AppSpacing.LG, this.contextViewportWidth - AppSpacing.XL - 176);
    this.contextMenuY = this.statusBarHeight + PageScaffold.BAR_HEIGHT;
    this.openCustomThemeActions(schemeId);
  }

  /** 首页背景图：方案按它的“首页背景”来源取；用户在外观里关掉时样机也不画。 */
  /** 书架预览顶部背景取自哪套主题；用户关了首页背景时返回空串。 */
  detailBackdropThemeId(theme: ThemePack, customSchemeId: string): string {
    if (AppStorage.get<boolean>(ThemeRuntime.KEY_HOME_BACKDROP_ENABLED) === false) return '';
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (scheme) {
      const sources = this.variantDark() ? scheme.settings.customDarkSources : scheme.settings.customLightSources;
      return sources.homeBackdropThemeId;
    }
    return theme.id;
  }

  /** 没有封面套装的主题，书架上的书用主题色轮着上色。 */
  stageBookTone(theme: ThemePack, index: number): string {
    const colors = this.activeVariant(theme).colors;
    const tones: string[] = [colors.accentColor, colors.buttonColor, colors.subTextColor, colors.primaryTextColor];
    const tone = tones[index % tones.length];
    return index >= tones.length ? this.withAlpha(tone, 'CC') : tone;
  }

  /** 正在用的主题显示实际桌面图标，其余显示这套主题的图标预览（主题包用它自带的标识）。 */
  stageIcon(theme: ThemePack, customSchemeId: string): ResourceStr {
    if (this.isSelected(theme, customSchemeId)) return AppIconManager.optionById(this.appIconId).preview;
    return this.customSchemeLogo(customSchemeId) || AppIconManager.optionForTheme(theme.id).preview;
  }

  canEditStartupText(theme: ThemePack): boolean {
    return theme.id !== ThemeIds.PLAIN_DEFAULT && theme.id !== ThemeIds.CUSTOM && this.hasThemeAccess(theme.id);
  }

  swatchImage(entry: ThemeListEntry): ResourceStr | null {
    if (entry.customSchemeId) {
      const custom = this.customPreviewImage(entry.customSchemeId) ||
        this.customPreviewStartupImage(entry.customSchemeId);
      if (custom) return custom;
    }
    const styleId = entry.theme.startup.styleId;
    if (!styleId || styleId === ThemeIds.PLAIN_DEFAULT) return null;
    return ThemeAssetRegistry.startupBackground(styleId, this.variantDark());
  }

  themeEntryKey(entry: ThemeListEntry): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, entry.customSchemeId);
    return `${entry.theme.id}_${entry.customSchemeId}_${scheme ? scheme.revision : 0}_` +
      `${this.variantDark() ? 'dark' : 'light'}_${this.accountEntitlementsRevision}`;
  }

  async addCustomScheme(): Promise<void> {
    if (this.addingCustomScheme) return;
    this.addingCustomScheme = true;
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const added = await CustomThemeSchemeStore.add(getContext(this), settings);
      if (!added) {
        this.refreshCustomSchemeLimit();
        HdsFeedback.showToast(`当前权益最多可创建 ${this.customSchemeLimit} 套自定义主题，已有方案保留`);
        return;
      }
      await this.refreshCustomSchemes();
      this.openSchemeDetail(added.id);
      HdsFeedback.showToast(`已添加「${added.name}」`);
    } catch (e) {
      console.error('添加自定义主题方案失败:', e);
      HdsFeedback.showToast('添加方案失败，请稍后重试');
    } finally {
      this.addingCustomScheme = false;
    }
  }

  @Builder
  customThemeActionMenu() {
    Scroll() {
      Column() {
        if (this.actionThemeKey) {
          if (this.themeRowCanApply(this.resolveEntry(this.actionThemeKey))) {
            this.contextActionItem($r('sys.symbol.checkmark'), '应用', this.primaryTextColor(), () => {
              const entry = this.resolveEntry(this.actionThemeKey);
              this.closeCustomThemeActions();
              this.selectTheme(entry.theme.id, entry.customSchemeId);
            })
          }
          this.contextActionItem($r('sys.symbol.info_circle'), '查看详情', this.primaryTextColor(), () => {
            const entry = this.resolveEntry(this.actionThemeKey);
            const context = this.actionThemeContext;
            const label = this.actionThemeLabel;
            this.closeCustomThemeActions();
            this.openDetailFor(entry, context, label);
          })
        }
        if (this.actionCustomSchemeId) {
          this.customSchemeActionItems()
        }
      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  customSchemeActionItems() {
    Column() {
      this.contextActionItem($r('sys.symbol.pin'), this.schemePinned(this.actionCustomSchemeId) ? '取消置顶' : '置顶',
        this.primaryTextColor(), () => {
          const schemeId = this.actionCustomSchemeId;
          const pin = !this.schemePinned(schemeId);
          this.closeCustomThemeActions();
          this.setSchemesPinned([schemeId], pin);
        })
      this.contextActionItem($r('sys.symbol.paintpalette'), '编辑', this.primaryTextColor(), () => {
        const schemeId = this.actionCustomSchemeId;
        this.closeCustomThemeActions();
        router.pushUrl({
          url: 'pages/ThemeColorSettings',
          params: { schemeId: schemeId }
        });
      })
      this.contextActionItem($r('sys.symbol.textformat'), '设置排版', this.primaryTextColor(), () => {
        const schemeId = this.actionCustomSchemeId;
        this.closeCustomThemeActions();
        router.pushUrl({
          url: 'pages/ThemeTypographySettings',
          params: { schemeId: schemeId }
        });
      })
      this.contextActionItem($r('sys.symbol.plus_square_on_square'), '复制方案', this.primaryTextColor(), () => {
        const schemeId = this.actionCustomSchemeId;
        this.closeCustomThemeActions();
        this.duplicateCustomScheme(schemeId);
      })
      this.contextActionItem($r('sys.symbol.square_and_pencil'), '重命名', this.primaryTextColor(), () => {
        const scheme = this.actionCustomScheme();
        if (!scheme) return;
        this.renameCustomThemeName = scheme.name;
        this.showCustomThemeActionMenu = false;
        this.showRenameCustomThemeDialog = true;
      })
      this.contextActionItem($r('sys.symbol.share'), '分享主题包', this.primaryTextColor(), () => {
        const schemeId = this.actionCustomSchemeId;
        this.closeCustomThemeActions();
        this.requestThemeExport(schemeId);
      })
      this.contextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
        this.showCustomThemeActionMenu = false;
        this.requestDeleteCustomTheme(this.actionCustomSchemeId);
      })
    }
    .width('100%')
  }

  @Builder
  contextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    PopupMenuAction(icon, label, color, action)
  }

  @Builder
  renameCustomThemeDialog() {
    Column({ space: AppSpacing.XL }) {
      Text('重命名自定义主题')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      TextInput({ placeholder: '输入方案名称', text: this.renameCustomThemeName })
        .width('100%')
        .height(42)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.renameCustomThemeName = value;
        })
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.cardColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeRenameCustomThemeDialog())
        Button('保存', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.accentColor())
          .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
          .enabled(!!this.renameCustomThemeName.trim())
          .onClick(() => this.renameCustomTheme())
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XXL)
  }

  syncShowRenameCustomThemeDialog(): void {
    this.renameCustomThemeDialogSession.sync(this.getUIContext(), this.showRenameCustomThemeDialog, (): void => {
      this.renameCustomThemeDialog();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示重命名主题弹窗失败:',
      onDismiss: (): void => {
        this.closeRenameCustomThemeDialog();
      }
    });
  }

  @Builder
  deleteCustomThemeDialog() {
    Column({ space: AppSpacing.LG }) {
      Text('删除自定义主题')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Text(this.deleteSchemeIds.length > 1 ? `确定删除选中的 ${this.deleteSchemeIds.length} 套方案吗？此操作无法撤销。` :
        `确定删除「${(this.deleteSchemeIds.length === 1 ?
          CustomThemeSchemeStore.find(this.customSchemes, this.deleteSchemeIds[0]) :
          this.actionCustomScheme())?.name || '该方案'}」吗？此操作无法撤销。`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .width('100%')
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.cardColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeDeleteCustomThemeDialog())
        Button('删除', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.dangerColor(this.appDarkMode)))
          .onClick(() => this.confirmDeleteCustomTheme())
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XXL)
  }

  syncShowDeleteCustomThemeDialog(): void {
    this.deleteCustomThemeDialogSession.sync(this.getUIContext(), this.showDeleteCustomThemeDialog, (): void => {
      this.deleteCustomThemeDialog();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示删除主题弹窗失败:',
      onDismiss: (): void => {
        this.closeDeleteCustomThemeDialog();
      }
    });
  }

  @Builder
  startupTextDialog() {
    Column({ space: AppSpacing.LG }) {
      Text(`编辑「${BuiltinThemeRegistry.findById(this.startupTextThemeId).name}」启动文案`)
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Column({ space: AppSpacing.SM }) {
        Text('主标题')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
        TextInput({ placeholder: '可留空', text: this.startupTextTitle })
          .width('100%')
          .height(42)
          .maxLength(24)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.startupTextTitle = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Column({ space: AppSpacing.SM }) {
        Text('副标题')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
        TextInput({ placeholder: '可留空', text: this.startupTextSubtitle })
          .width('100%')
          .height(42)
          .maxLength(48)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.startupTextSubtitle = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Button('恢复默认文案', { type: ButtonType.Normal })
        .height(34)
        .borderRadius(ThemeRuntime.buttonRadius())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.accentColor())
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .onClick(() => {
          this.startupTextTitle = '开源轻页';
          this.startupTextSubtitle = StartupCoverTextStore.defaultSubtitle(this.startupTextThemeId);
        })
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.cardColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closeStartupTextDialog())
        Button('保存', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.accentColor())
          .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
          .onClick(() => this.saveStartupText())
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XXL)
  }

  syncShowStartupTextDialog(): void {
    this.startupTextDialogSession.sync(this.getUIContext(), this.showStartupTextDialog, (): void => {
      this.startupTextDialog();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示启动文字弹窗失败:',
      onDismiss: (): void => {
        this.closeStartupTextDialog();
      }
    });
  }

  @Builder
  themeApplyDialog() {
    Column({ space: AppSpacing.LG }) {
      Text(`应用「${this.applyDialogThemeName}」`)
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      Text('选择要随主题一起应用的内容，关闭的选项会保留当前设置。')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .width('100%')
      if (this.applyDialogFirstUse) {
        this.themeApplyToggleRow('layout')
      }
      if (this.applyDialogHasCover) {
        this.themeApplyToggleRow('cover')
      }
      this.themeApplyToggleRow('icon')
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.cardColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.cancelThemeApply())
        Button('应用', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.accentColor())
          .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
          .onClick(() => this.confirmThemeApply())
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XXL)
  }

  syncShowThemeApplyDialog(): void {
    this.themeApplyDialogSession.sync(this.getUIContext(), this.showThemeApplyDialog, (): void => {
      this.themeApplyDialog();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示应用主题弹窗失败:',
      onDismiss: (): void => {
        this.cancelThemeApply();
      }
    });
  }

  @Builder
  themeApplyToggleRow(category: string) {
    Row({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.XXS }) {
        Text(category === 'layout' ? '使用主题预设排版' : category === 'cover' ? '应用主题封面' : '应用主题图标')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Text(category === 'layout' ? (this.applyDialogApplyLayout ? this.applyDialogLayoutOnHint :
          this.applyDialogLayoutOffHint) : category === 'cover' ?
          '书架使用主题封面与配套书籍边框' : AppIconManager.isSupported() ?
          '桌面图标同步更换为主题图标' : AppIconManager.UNSUPPORTED_MESSAGE)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      AdaptiveSwitch({
        isOn: category === 'layout' ? this.applyDialogApplyLayout :
          category === 'cover' ? this.applyDialogApplyCover : this.applyDialogApplyIcon,
        onChange: (enabled: boolean) => {
          if (category === 'layout') {
            this.applyDialogApplyLayout = enabled;
          } else if (category === 'cover') {
            this.applyDialogApplyCover = enabled;
          } else {
            this.applyDialogApplyIcon = enabled;
          }
        }
      })
    }
    .width('100%')
    .padding({ top: AppSpacing.XXS, bottom: AppSpacing.XXS })
    .alignItems(VerticalAlign.Center)
  }

  openStartupTextDialog(themeId: string): void {
    if (themeId === ThemeIds.PLAIN_DEFAULT || themeId === ThemeIds.CUSTOM) return;
    this.startupTextThemeId = themeId;
    this.startupTextTitle = StartupCoverTextStore.title(themeId, '开源轻页');
    this.startupTextSubtitle = StartupCoverTextStore.subtitle(
      themeId, StartupCoverTextStore.defaultSubtitle(themeId));
    this.showStartupTextDialog = true;
  }

  closeStartupTextDialog(): void {
    this.showStartupTextDialog = false;
    this.startupTextThemeId = '';
    this.startupTextTitle = '';
    this.startupTextSubtitle = '';
  }

  async saveStartupText(): Promise<void> {
    if (!this.startupTextThemeId) return;
    try {
      await StartupCoverTextStore.update(getContext(this), this.startupTextThemeId,
        this.startupTextTitle, this.startupTextSubtitle);
      this.closeStartupTextDialog();
      HdsFeedback.showToast('启动文案已更新');
    } catch (e) {
      console.error('保存启动文案失败:', e);
      HdsFeedback.showToast('保存启动文案失败，请重试');
    }
  }

  openCustomThemeActions(schemeId: string, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionThemeKey = '';
    this.actionCustomSchemeId = schemeId;
    this.showCustomThemeActionMenu = true;
  }

  /** 列表行长按：菜单顶上是应用和查看详情，方案再接编辑、排版、重命名、分享、删除。 */
  openThemeRowActions(entry: ThemeListEntry, context: string, label: string, event: GestureEvent): void {
    this.openCustomThemeActions(entry.customSchemeId, event);
    this.actionThemeKey = this.entrySelectKey(entry);
    this.actionThemeContext = context;
    this.actionThemeLabel = label;
  }

  closeCustomThemeActions(): void {
    this.showCustomThemeActionMenu = false;
    this.actionCustomSchemeId = '';
    this.actionThemeKey = '';
  }

  actionCustomScheme(): CustomThemeScheme | null {
    return CustomThemeSchemeStore.find(this.customSchemes, this.actionCustomSchemeId);
  }

  updateContextViewport(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
    if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
  }

  closeRenameCustomThemeDialog(): void {
    this.showRenameCustomThemeDialog = false;
    this.renameCustomThemeName = '';
    this.actionCustomSchemeId = '';
  }

  async renameCustomTheme(): Promise<void> {
    const scheme = this.actionCustomScheme();
    const name = this.renameCustomThemeName.trim();
    if (!scheme || !name) return;
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const renamed = await CustomThemeSchemeStore.rename(getContext(this), settings, scheme.id, name);
      if (!renamed) {
        HdsFeedback.showToast('名称为空、重复或方案不存在');
        return;
      }
      this.closeRenameCustomThemeDialog();
      await this.refreshCustomSchemes();
      HdsFeedback.showToast('自定义主题已重命名');
    } catch (e) {
      console.error('重命名自定义主题失败:', e);
      HdsFeedback.showToast('重命名失败，请稍后重试');
    }
  }

  requestDeleteCustomTheme(schemeId: string): void {
    if (this.customSchemes.length <= 1) {
      this.closeCustomThemeActions();
      HdsFeedback.showToast('至少需要保留一套自定义主题');
      return;
    }
    this.deleteSchemeIds = [];
    this.actionCustomSchemeId = schemeId;
    this.showDeleteCustomThemeDialog = true;
  }

  closeDeleteCustomThemeDialog(): void {
    this.showDeleteCustomThemeDialog = false;
    this.actionCustomSchemeId = '';
    this.deleteSchemeIds = [];
  }

  async confirmDeleteCustomTheme(): Promise<void> {
    const schemeIds = this.deleteSchemeIds.length > 0 ? [...this.deleteSchemeIds] : [this.actionCustomSchemeId];
    this.showDeleteCustomThemeDialog = false;
    this.deleteSchemeIds = [];
    await this.deleteCustomThemeSchemes(schemeIds);
  }

  /** 删除一套或几套方案（全部页整理模式可多选）；至少留一套，正在用的先换回默认主题。 */
  async deleteCustomThemeSchemes(requested: string[]): Promise<void> {
    const schemeIds = requested.filter((id: string): boolean => !!CustomThemeSchemeStore.find(this.customSchemes, id));
    if (schemeIds.length === 0) return;
    if (this.customSchemes.length - schemeIds.length < 1) {
      HdsFeedback.showToast('至少需要保留一套自定义主题');
      return;
    }
    const firstName = CustomThemeSchemeStore.find(this.customSchemes, schemeIds[0])?.name || '';
    try {
      if (this.appThemeId === ThemeIds.CUSTOM && schemeIds.indexOf(this.activeCustomSchemeId) >= 0) {
        await this.selectTheme(ThemeIds.PLAIN_DEFAULT, '', false);
        if (this.appThemeId === ThemeIds.CUSTOM) {
          return;
        }
      }
      // 从确认框里删除：等它退场后这些行消散，与删方案同时进行；播完在补位动画里拿掉，再重读方案。
      const keys = [...schemeIds];
      const fade = ListDissolve.fadeOut(this.getUIContext(), keys, (key: string) => {
        this.dissolvingSchemeIds = [...this.dissolvingSchemeIds, key];
      }, ListDissolve.particles('theme_settings_root', [this.accentColor(), this.primaryTextColor(), this.subTextColor()],
        (key: string): string => this.schemeRowElementId(key), (): DeleteParticleBurst[] => this.deleteParticleBursts,
        (bursts: DeleteParticleBurst[]): void => { this.deleteParticleBursts = bursts; }), ListDissolve.AFTER_DIALOG_MS);
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const deletedIds: string[] = [];
      for (const schemeId of schemeIds) {
        if (await CustomThemeSchemeStore.delete(getContext(this), settings, schemeId)) deletedIds.push(schemeId);
      }
      await fade;
      if (deletedIds.length < keys.length) {
        this.dissolvingSchemeIds = ListDissolve.without(this.dissolvingSchemeIds,
          keys.filter((id: string): boolean => deletedIds.indexOf(id) < 0));
      }
      if (deletedIds.length === 0) {
        HdsFeedback.showToast('删除失败，至少需要保留一套方案');
        return;
      }
      ListDissolve.commit(this.getUIContext(), () => {
        this.customSchemes = this.customSchemes.filter((item: CustomThemeScheme) => deletedIds.indexOf(item.id) < 0);
        this.schemeSelected = this.schemeSelected.filter((id: string): boolean => deletedIds.indexOf(id) < 0);
        this.syncSchemeOrganizeOrder();
      }, () => {
        this.dissolvingSchemeIds = ListDissolve.without(this.dissolvingSchemeIds, deletedIds);
      });
      this.actionCustomSchemeId = '';
      if (this.detailOpen && deletedIds.some((id: string): boolean => this.detailKeys.indexOf(`scheme:${id}`) >= 0)) {
        this.closeDetail();
      }
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, ListDissolve.CLOSE_MS); });
      await this.refreshCustomSchemes();
      await ThemePackageService.cleanupImportedFiles(getContext(this));
      HdsFeedback.showToast(deletedIds.length === 1 && schemeIds.length === 1 ? `已删除「${firstName}」` :
        `已删除 ${deletedIds.length} 套方案`);
    } catch (e) {
      console.error('删除自定义主题失败:', e);
      this.dissolvingSchemeIds = ListDissolve.without(this.dissolvingSchemeIds, schemeIds);
      HdsFeedback.showToast('删除失败，请稍后重试');
    }
  }

  hasThemeAccess(themeId: string): boolean {
    if (SuperExclusiveThemes.has(themeId)) return AccountSessionStore.hasOwnedEntitlement(themeId);
    if (ThemePackRegistry.isPackId(themeId)) return ThemePackRegistry.has(themeId);
    return BuiltinThemeRegistry.isFree(themeId) ||
      (themeId === this.appThemeId && !this.isTrialTheme(themeId)) ||
      AccountSessionStore.hasValidEntitlement(themeId);
  }

  unavailableCustomStartupTheme(settings: AppThemeSettings): string {
    const missingExclusive = SuperExclusiveThemes.usedByScheme(settings.customBaseThemeId,
      settings.customLightSources, settings.customDarkSources)
      .find((id: string) => !AccountSessionStore.hasOwnedEntitlement(id));
    if (missingExclusive) {
      return BuiltinThemeRegistry.findById(missingExclusive).name;
    }
    // 已安装的主题包不需要权益；缺包时按默认主题显示，不拦截应用。
    const lightThemeId = settings.customLightSources.startupThemeId;
    if (!BuiltinThemeRegistry.isFree(lightThemeId) && !ThemePackRegistry.isPackId(lightThemeId) &&
      !AccountSessionStore.hasValidEntitlement(lightThemeId)) {
      return BuiltinThemeRegistry.findById(lightThemeId).name;
    }
    const darkThemeId = settings.customDarkSources.startupThemeId;
    if (!BuiltinThemeRegistry.isFree(darkThemeId) && !ThemePackRegistry.isPackId(darkThemeId) &&
      !AccountSessionStore.hasValidEntitlement(darkThemeId)) {
      return BuiltinThemeRegistry.findById(darkThemeId).name;
    }
    return '';
  }

  /** 和行尾按钮同一套判断：试用中、正在用、正在应用的都不能再点应用。 */
  themeRowCanApply(entry: ThemeListEntry): boolean {
    const state = this.themeRowState(entry);
    return state === 'idle' || state === 'pending';
  }

  /** 行尾状态；也拼进列表键里，状态一变就重建这一行，侧滑跟着收起、按钮跟着变。 */
  /** 行的状态键：拼进列表键里，状态一变（含方案置顶、排序带的时间）就重建这一行，侧滑跟着收起。 */
  themeRowState(entry: ThemeListEntry): string {
    const scheme = entry.customSchemeId ?
      `_${this.schemePinned(entry.customSchemeId) ? 'pin' : ''}_${this.schemeSortMeta(entry.customSchemeId)}` : '';
    if (this.applyingThemeId === (entry.customSchemeId || entry.theme.id) &&
      !this.isSelected(entry.theme, entry.customSchemeId)) return `applying${scheme}`;
    if (!entry.customSchemeId && this.isTrialTheme(entry.theme.id)) return 'trial';
    if (this.isSelected(entry.theme, entry.customSchemeId)) return `selected${scheme}`;
    return `${this.isCustomSchemePending(entry.theme, entry.customSchemeId) ? 'pending' : 'idle'}${scheme}`;
  }

  isTrialTheme(themeId: string): boolean {
    return this.trialThemeId === themeId && this.trialEndsAt > Date.now() &&
      ThemeTrialManager.isActive(themeId);
  }

  isCustomSchemePending(theme: ThemePack, customSchemeId: string): boolean {
    return theme.id === ThemeIds.CUSTOM && this.appThemeId === ThemeIds.CUSTOM &&
      this.activeCustomSchemeId === customSchemeId && !this.isSelected(theme, customSchemeId);
  }

  async startThemeTrial(theme: ThemePack): Promise<void> {
    if (this.applyingThemeId) {
      return;
    }
    this.applyingThemeId = theme.id;
    try {
      await ThemeTrialManager.start(getContext(this) as common.UIAbilityContext, theme.id);
      this.appThemeId = theme.id;
      this.themeBookCoverEnabled = !!theme.book.coverAssetId;
      this.syncBars();
      HdsFeedback.showToast(`「${theme.name}」已开始试用，5分钟后自动恢复`);
    } catch (e) {
      console.error('启动主题试用失败:', e);
      HdsFeedback.showToast('主题试用启动失败，请稍后重试');
    } finally {
      this.applyingThemeId = '';
    }
  }

  stopThemeTrial(): void {
    ThemeTrialManager.stop(getContext(this) as common.UIAbilityContext);
    this.appThemeId = AppStorage.get<string>('appThemeId') || AppThemeSettingsStore.DEFAULT_THEME_ID;
    this.themeBookCoverEnabled = AppStorage.get<boolean>('appThemeBookCoverEnabled') || false;
    this.syncBars();
  }

  async acquireTheme(themeId: string): Promise<void> {
    if (ThemeTrialManager.isActive()) {
      this.stopThemeTrial();
    }
    await this.selectTheme(themeId);
  }

  /** Only themes with a live (unexpired) purchase entitlement belong here. */
  purchasedThemes(): ThemePack[] {
    const themes: ThemePack[] = [];
    for (const theme of BuiltinThemeRegistry.all()) {
      if (AccountSessionStore.hasValidEntitlement(theme.id)) {
        themes.push(theme);
      }
    }
    return themes;
  }

  /** Paid themes the user has no live entitlement for; the free default theme is never listed. */
  moreThemes(): ThemePack[] {
    const themes: ThemePack[] = [];
    for (const theme of BuiltinThemeRegistry.all()) {
      if (!BuiltinThemeRegistry.isFree(theme.id) && !AccountSessionStore.hasValidEntitlement(theme.id)) {
        themes.push(theme);
      }
    }
    return themes;
  }

  themeHasRegexBubbleCap(theme: ThemePack): boolean {
    return ThemeAssetRegistry.hasRegexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle,
      this.variantDark());
  }

  /** A custom scheme shows the panel background of the theme picked as its panel source. */
  previewTtsPanelThemeId(theme: ThemePack, customSchemeId: string): string {
    if (theme.id !== ThemeIds.CUSTOM) return theme.id;
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme) return ThemeRuntime.ttsPanelThemeId(this.variantDark());
    const sources = this.variantDark() ? scheme.settings.customDarkSources : scheme.settings.customLightSources;
    return sources.ttsPanelThemeId || sources.readerThemeId;
  }

  withAlpha(color: string, alphaHex: string): string {
    return /^#[0-9A-Fa-f]{6}$/.test(color) ? `#${alphaHex}${color.substring(1)}` : color;
  }

  /** The theme's own button radius, floored so sharp-cornered themes still read as rounded. */
  storeButtonRadius(theme: ThemePack): number {
    return Math.max(8, theme.radius.button);
  }

  /** Price text for a paid theme; never a guessed price while the catalog is missing. */
  storeThemePriceLabel(themeId: string): string {
    if (SuperExclusiveThemes.has(themeId)) return '终身超级会员专属';
    const offer = this.themeOffer(themeId);
    if (offer) return `${offer.pricePoints}点`;
    if (this.themeCatalogLoaded) return '暂未上架';
    return this.themeCatalogFailed ? '价格加载失败' : '价格加载中';
  }

  acquireButtonLabel(themeId: string, action: string): string {
    if (SuperExclusiveThemes.has(themeId)) {
      return AccountSessionStore.hasOwnedEntitlement(themeId) ? '已领取 · 应用主题' :
        (AccountSessionStore.activeMembershipSku() === 'SUPER_LIFETIME' ? '领取一年' : '终身超级会员专属');
    }
    const offer = this.themeOffer(themeId);
    if (offer) return `${action} · ${offer.pricePoints}点`;
    if (this.themeCatalogLoaded) return '暂未上架';
    return this.themeCatalogFailed ? '重新加载价格' : '价格加载中…';
  }

  /** Greyed out until the price is known; after a failed load the button becomes the retry. */
  acquireButtonEnabled(themeId: string): boolean {
    if (SuperExclusiveThemes.has(themeId)) return !this.applyingThemeId;
    return this.themeCatalogLoaded ? !!this.themeOffer(themeId) : this.themeCatalogFailed;
  }

  onAcquireButtonTap(themeId: string): void {
    if (SuperExclusiveThemes.has(themeId) || this.themeCatalogLoaded) {
      this.acquireTheme(themeId);
    } else {
      this.refreshThemeCatalog();
    }
  }

  storeThemeCaption(theme: ThemePack): string {
    if (SuperExclusiveThemes.has(theme.id)) {
      const owned = AccountSessionStore.entitlement(theme.id);
      return AccountSessionStore.hasOwnedEntitlement(theme.id) && owned ?
        `已领取 · 有效至 ${this.formatDate(owned.expiresAt)}` : '终身超级会员手动领取 · 每次一年 · 不售卖';
    }
    if (theme.id === ThemeIds.CUSTOM) {
      return '自定义方案';
    }
    if (BuiltinThemeRegistry.isFree(theme.id)) {
      return '免费使用';
    }
    const entitlement = AccountSessionStore.entitlement(theme.id);
    if (AccountSessionStore.hasMemberThemeAccess(theme.id)) return '会员免费使用';
    if (entitlement && entitlement.expiresAt > Date.now()) {
      return `有效至 ${this.formatDate(entitlement.expiresAt)}`;
    }
    const offer = this.themeOffer(theme.id);
    if (!offer) {
      return this.storeThemePriceLabel(theme.id);
    }
    return `${offer.pricePoints}点 · 有效期${offer.validDays}天`;
  }

  themeHasBookCover(theme: ThemePack): boolean {
    return !!theme.book.coverAssetId && this.themeCoverSet(theme).length > 0;
  }

  themeAccessLabel(themeId: string): string {
    if (SuperExclusiveThemes.has(themeId) && !AccountSessionStore.hasOwnedEntitlement(themeId)) {
      return '终身超级会员专属 · 领取一年';
    }
    if (AccountSessionStore.hasMemberThemeAccess(themeId)) return '会员免费';
    if (BuiltinThemeRegistry.isFree(themeId)) {
      return '免费';
    }
    const entitlement: ThemeEntitlement | null = AccountSessionStore.entitlement(themeId);
    if (entitlement && entitlement.expiresAt > Date.now()) {
      return `有效至 ${this.formatDate(entitlement.expiresAt)}`;
    }
    return this.themeOffer(themeId) ? `${this.themeOffer(themeId)?.pricePoints}点 / 1年` :
      this.storeThemePriceLabel(themeId);
  }

  formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  /** 方案指定的预览图，或主题包自带的；空则用启动封面。 */
  customPreviewImage(customSchemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    return scheme ? scheme.settings.customPreviewImagePath : '';
  }

  /** 主题包自带的标识，替代自定义主题的桌面图标预览。 */
  customSchemeLogo(customSchemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme || !scheme.packageId) return '';
    const pack = ThemePackRegistry.getByPackageId(scheme.packageId);
    return pack ? pack.logo : '';
  }

  customPreviewStartupImage(customSchemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme) return '';
    return this.variantDark() ? scheme.settings.customDarkStartupImagePath :
      scheme.settings.customLightStartupImagePath;
  }

  /** The theme's emphasis bubble in bubble form, as the reader paints paragraph-comment / 本章说 pills. */
  themeCommentPreview(theme: ThemePack): ReaderResolvedRegexEmphasis {
    return ReaderRegexBubbleStyleResolver.resolve(null,
      this.themeEmphasisContext(theme, ThemeRegexEmphasisModes.BUBBLE), false);
  }

  /** The reader's comment bubble with its label baked in, cached per look, label and size. */
  commentBubbleImage(theme: ThemePack, label: string, fontSizeVp: number, dark: boolean): ReaderCommentBubbleImage | null {
    const preview = this.themeCommentPreview(theme);
    const variant = dark ? theme.dark : theme.light;
    const style = ReaderCommentBubbleStyles.resolveThemed(preview.bubbleStyleId, dark, variant.reader.textColor,
      variant.regexEmphasis.commentBubble, preview.backgroundColor, preview.textColor, preview.emphasisColor);
    const pxPerVp = this.getUIContext().vp2px(1);
    const key = `${style.identity()}_${label}_${fontSizeVp}_${pxPerVp}`;
    const cached = this.commentBubbleImages.get(key);
    if (cached !== undefined) return cached;
    const rendered = ReaderCommentBubblePainter.renderLabel(style, label, fontSizeVp * pxPerVp);
    this.commentBubbleImages.set(key, rendered);
    return rendered;
  }

  commentBubbleImageWidth(image: ReaderCommentBubbleImage | null): number {
    return image ? this.getUIContext().px2vp(image.width) : 0;
  }

  commentBubbleImageHeight(image: ReaderCommentBubbleImage | null): number {
    return image ? this.getUIContext().px2vp(image.height) : 0;
  }

  @Builder
  commentBubbleSpan(theme: ThemePack, label: string, fontSizeVp: number, dark: boolean) {
    if (this.commentBubbleImage(theme, label, fontSizeVp, dark)) {
      ImageSpan((this.commentBubbleImage(theme, label, fontSizeVp, dark) as ReaderCommentBubbleImage).pixelMap)
        .width(this.commentBubbleImageWidth(this.commentBubbleImage(theme, label, fontSizeVp, dark)))
        .height(this.commentBubbleImageHeight(this.commentBubbleImage(theme, label, fontSizeVp, dark)))
        .objectFit(ImageFit.Contain)
        .verticalAlign(ImageSpanAlignment.CENTER)
    }
  }

  themeEmphasisContext(theme: ThemePack, mode: string): ReaderRegexEmphasisContext {
    const variant = this.activeVariant(theme);
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = mode;
    context.inheritedBubbleStyleId = variant.regexEmphasis.bubbleStyle;
    context.inheritedColor = variant.regexEmphasis.emphasisColor;
    context.inheritedTextColor = variant.regexEmphasis.emphasisTextColor;
    context.accentColor = variant.colors.accentColor;
    context.surfaceColor = variant.reader.backgroundColor;
    context.normalTextColor = variant.reader.textColor;
    context.darkMode = variant.reader.contentTone === 'dark';
    return context;
  }

  themeRegexPreview(theme: ThemePack): ReaderResolvedRegexEmphasis {
    // Theme cards must preview the theme itself even before it is purchased.
    // Runtime entitlement checks are still enforced in the reader and the
    // regex-font settings page.
    return ReaderRegexBubbleStyleResolver.resolve(null,
      this.themeEmphasisContext(theme, this.activeVariant(theme).regexEmphasis.emphasisMode), false);
  }

  /** 预览里的主题封面跟着预览的深浅色走：有深色那套封面的主题切到深色时换成它。 */
  themeCoverSet(theme: ThemePack): ResourceStr[] {
    return ThemeAssetRegistry.themeBookCovers(theme.book.coverAssetId, this.variantDark());
  }

  /** 主题包动图封面取景记下的显示区域。 */
  themeCoverCrop(theme: ThemePack, index: number): ThemeImageCrop | null {
    const covers = this.themeCoverSet(theme);
    return covers.length > 0 ?
      ThemeAssetRegistry.imageCrop(ThemeImageSlots.COVER, covers[index % covers.length], this.variantDark()) : null;
  }

  themeRegexPreviewBackground(theme: ThemePack): TextBackgroundStyle {
    const style = this.themeRegexPreview(theme);
    if (!style.backgroundEnabled) return {};
    return {
      color: style.backgroundColor,
      radius: {
        topLeft: style.radiusTopLeft,
        topRight: style.radiusTopRight,
        bottomLeft: style.radiusBottomLeft,
        bottomRight: style.radiusBottomRight
      }
    };
  }

  themeRegexPreviewShadow(theme: ThemePack): ShadowOptions | ShadowOptions[] {
    const style = this.themeRegexPreview(theme);
    if (style.textShadows.length > 0) return style.textShadows;
    return {
      radius: style.textShadowRadius,
      color: style.textShadowColor,
      offsetX: style.textShadowOffsetX,
      offsetY: style.textShadowOffsetY
    };
  }

  themeRegexPreviewDecoration(theme: ThemePack): DecorationStyleInterface {
    const style = this.themeRegexPreview(theme);
    if (!style.decorationEnabled) return { type: TextDecorationType.None };
    return {
      type: TextDecorationType.Underline,
      color: style.decorationColor,
      style: this.themeRegexDecorationStyle(style.decorationStyleId)
    };
  }

  themeRegexDecorationStyle(styleId: string): TextDecorationStyle {
    if (styleId === 'double') return TextDecorationStyle.DOUBLE;
    if (styleId === 'dotted') return TextDecorationStyle.DOTTED;
    if (styleId === 'dashed') return TextDecorationStyle.DASHED;
    if (styleId === 'wavy') return TextDecorationStyle.WAVY;
    return TextDecorationStyle.SOLID;
  }

}

/** 主题页的卡片列表：铺在外层滚动里不自己滚，只为了让行能左滑。 */
@Extend(List)
function themeCardList(background: ResourceColor) {
  .width('100%')
  .borderRadius(ThemeRuntime.cardRadius())
  .backgroundColor(background)
  .clip(true)
  .scrollBar(BarState.Off)
  .edgeEffect(EdgeEffect.None)
  .enableScrollInteraction(false)
}
