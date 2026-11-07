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
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRecentStore } from '../utils/ThemeRecentStore';
import { ReaderThemeBackground } from '../components/ReaderThemeBackground';
import { TtsPanelThemeBackground } from '../components/TtsPanelThemeBackground';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { SuperExclusiveThemes, ThemeIds, ThemePack, ThemeRegexEmphasisModes, ThemeVariant } from '../theme/ThemeModels';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemePackRegistry } from '../theme/ThemePackRegistry';
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
import { PopupMenuAction } from '../components/common/PopupMenuAction';

const STORE_BOOK_COVER_RATIO = 46 / 64;
const SHELF_BOOK_TITLES: string[] = ['长夜', '山海', '雾中', '北窗', '星河', '归途'];
// “我的”页已拥有区只露这么多套，其余进“全部”列表，免得把方案挤到很下面。
const OWNED_PREVIEW_COUNT = 3;
const ROW_THUMB_WIDTH = 36;
const ROW_THUMB_HEIGHT = 56;
const CURRENT_HERO_HEIGHT = 188;
const STORE_TILE_WIDTH = 100;
const STORE_TILE_HEIGHT = 168;
const DETAIL_READER_LINES = 7;
const DETAIL_READER_FONT_SIZE = 15;
const DETAIL_READER_LINE_HEIGHT = 27;
const DETAIL_SCRIM = '#59000000';

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
  @StorageLink('accountEntitlementsRevision') @Watch('refreshCustomSchemeLimit')
  accountEntitlementsRevision: number = 0;
  @StorageLink('themeTrialThemeId') trialThemeId: string = '';
  @StorageLink('themeTrialEndsAt') trialEndsAt: number = 0;
  @StorageLink('activeCustomThemeSchemeId') activeCustomSchemeId: string = '';
  @StorageLink('activeCustomThemeSchemeRevision') activeCustomSchemeRevision: number = 0;
  @StorageLink('customThemeSchemesRevision') @Watch('onCustomThemeSchemesRevisionChanged')
  customThemeSchemesRevision: number = 0;
  @StorageLink('startupCoverTextsRevision') startupCoverTextsRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State applyingThemeId: string = '';
  @State homeSegment: string = 'mine';
  @State ownedListOpen: boolean = false;
  @State ownedSort: string = 'recent';
  @State recentThemeIds: string[] = [];
  // 竖向详情页：detailKeys 是同一列表里可左右滑动的项（theme:<主题 ID> 或 scheme:<方案 ID>）。
  @State detailOpen: boolean = false;
  @State detailKeys: string[] = [];
  @State detailIndex: number = 0;
  @State detailLabel: string = '';
  // 详情页可单独切浅色 / 深色预览，不改应用的深浅色。
  @State detailDark: boolean = false;
  @State customSchemes: CustomThemeScheme[] = [];
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

  refreshCustomSchemeLimit(): void {
    this.customSchemeLimit = CustomThemeQuota.current();
  }

  customSchemeAuthor(customSchemeId: string): string {
    if (!customSchemeId) return '';
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    return scheme ? scheme.author : '';
  }

  /** 方案由主题包安装而来，但本机没有这个包的素材（换设备同步过来、或目录被清掉）。 */
  customSchemePackMissing(customSchemeId: string): boolean {
    if (!customSchemeId) return false;
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    return !!scheme && !!scheme.packageId && !ThemePackRegistry.getByPackageId(scheme.packageId);
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
    if (this.detailOpen) {
      this.closeDetail();
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
    }
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
  @Builder
  shelfBook(theme: ThemePack, index: number) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (this.themeHasBookCover(theme)) {
          Image(this.themeCoverSet(theme)[index % this.themeCoverSet(theme).length])
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
            .draggable(false)
          Image(ThemeAssetRegistry.themeShelfFrame(theme.book.shelfFrameAssetId))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
            .draggable(false)
        } else {
          Text(SHELF_BOOK_TITLES[index % SHELF_BOOK_TITLES.length])
            .fontSize(AppFontSize.BODY)
            .fontFamily(theme.typography.appFontFamily)
            .fontColor('#FFFFFF')
            .margin(AppSpacing.SM)
        }
      }
      .width('100%')
      .aspectRatio(STORE_BOOK_COVER_RATIO)
      .borderRadius(theme.radius.small)
      .clip(true)
      .backgroundColor(this.themeHasBookCover(theme) ? Color.Transparent : this.stageBookTone(theme, index))
      Text(SHELF_BOOK_TITLES[index % SHELF_BOOK_TITLES.length])
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.activeVariant(theme).colors.primaryTextColor)
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /** 正文样张：对白套这套主题的强调样式，段评数画成主题的段评气泡。 */
  @Builder
  readerSampleText(theme: ThemePack, fontSize: number, lineHeight: number, maxLines: number) {
    Text() {
      ForEach(READER_PREVIEW_SEGMENTS, (segment: ReaderPreviewSegment) => {
        if (segment.comment) {
          Span(' ')
          this.commentBubbleSpan(theme, segment.text, fontSize * 0.85,
            this.activeVariant(theme).reader.contentTone === 'dark')
        } else if (!segment.emphasis) {
          Span(segment.text)
        } else if (this.themeHasRegexBubbleCap(theme)) {
          ContainerSpan() {
            ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle))
              .width(fontSize)
              .height(fontSize)
              .objectFit(ImageFit.Contain)
              .verticalAlign(ImageSpanAlignment.CENTER)
            Span(segment.text)
              .fontColor(this.themeRegexPreview(theme).textColor)
              .textShadow(this.themeRegexPreviewShadow(theme))
            ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle))
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
      }, (_segment: ReaderPreviewSegment, index: number) => `reader_preview_${theme.id}_${index}`)
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

  /** 我的：当前主题大图与它的设置，已拥有只露几套（其余进“全部”），方案紧跟在后面。 */
  @Builder
  mineContent() {
    Column({ space: AppSpacing.MD }) {
      ForEach(this.currentThemeEntries(), (entry: ThemeListEntry) => {
        this.currentHero(entry)
      }, (entry: ThemeListEntry) => `current_${this.themeEntryKey(entry)}`)
      this.currentSettingsCard()

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
      if (this.ownedPreviewEntries().length > 0) {
        List() {
          ForEach(this.ownedPreviewEntries(), (entry: ThemeListEntry, index: number) => {
            this.swipeThemeItem(entry, 'owned', '已拥有', index > 0)
          }, (entry: ThemeListEntry) => `owned_preview_${this.themeEntryKey(entry)}_${this.themeRowState(entry)}`)
        }
        .themeCardList(this.cardColor())
      }

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
        List() {
          ForEach(this.schemeEntries(), (entry: ThemeListEntry, index: number) => {
            this.swipeThemeItem(entry, 'schemes', '我的方案', index > 0)
          }, (entry: ThemeListEntry) => `scheme_row_${this.themeEntryKey(entry)}_${this.themeRowState(entry)}`)
        }
        .themeCardList(this.cardColor())
      }
      Text('左滑可应用或删除，长按还可复制、设置排版、重命名或分享')
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
        .padding({ left: AppSpacing.XXS })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontFamily(entry.theme.typography.appFontFamily)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
        }
        Text(`${this.themeRowSubtitle(entry)} · 查看详情`)
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
    .height(CURRENT_HERO_HEIGHT)
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .accessibilityText(`正在使用「${entry.theme.name}」，查看详情`)
    .onClick(() => this.openDetailFor(entry, entry.customSchemeId ? 'schemes' : 'owned',
      entry.customSchemeId ? '我的方案' : '已拥有'))
  }

  /** 当前主题的设置：桌面图标、主题封面开关、启动文案；方案另有编辑和排版入口。 */
  @Builder
  currentSettingsCard() {
    Column() {
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
      .onClick(() => {
        router.pushUrl({ url: 'pages/AppIconSettings' });
      })
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
            Text(this.themeBookCoverEnabled ? '书架使用主题封面和配套边框' : '保留每本书原有封面')
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
        .height(62)
        .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
      }
      if (this.currentCanEditStartupText()) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.dividerColor(this.appDarkMode))
          .margin({ left: AppSpacing.LG })
        this.settingsRow('启动封面文案', '编辑', () => {
          this.openStartupTextDialog(this.appThemeId);
        })
      }
      if (this.appThemeId === ThemeIds.CUSTOM && this.activeCustomSchemeId) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.dividerColor(this.appDarkMode))
          .margin({ left: AppSpacing.LG })
        this.settingsRow('编辑方案', '', () => {
          router.pushUrl({ url: 'pages/ThemeColorSettings', params: { schemeId: this.activeCustomSchemeId } });
        })
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.dividerColor(this.appDarkMode))
          .margin({ left: AppSpacing.LG })
        this.settingsRow('设置方案排版', '', () => {
          router.pushUrl({ url: 'pages/ThemeTypographySettings', params: { schemeId: this.activeCustomSchemeId } });
        })
      }
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .clip(true)
  }

  @Builder
  settingsRow(label: string, value: string, action: () => void) {
    Row({ space: AppSpacing.SM }) {
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      if (value) {
        Text(value)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(54)
    .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(action)
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
              Text(entry.theme.name)
                .fontSize(AppFontSize.BODY_LARGE)
                .fontWeight(FontWeight.Medium)
                .fontFamily(entry.theme.typography.appFontFamily)
                .fontColor(this.primaryTextColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)
            }
            Text(this.themeRowSubtitle(entry))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.customSchemePackMissing(entry.customSchemeId) ?
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

  /** 竖向详情：同一列表里左右滑动切换，每页整页用这套主题（深浅色可单独切换预览）的配色。 */
  @Builder
  detailOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Swiper() {
          ForEach(this.detailKeys, (key: string) => {
            this.detailPage(this.resolveEntry(key))
          }, (key: string) => `detail_${this.themeEntryKey(this.resolveEntry(key))}`)
        }
        .index(this.detailIndex)
        .indicator(false)
        .loop(false)
        .duration(280)
        .cachedCount(1)
        .disableSwipe(this.detailKeys.length <= 1)
        .onChange((index: number) => {
          this.detailIndex = index;
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.detailPageColor())
    .transition(TransitionEffect.translate({ y: 64 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 260, curve: Curve.Friction }))
  }

  @Builder
  /** 详情顶栏：返回和“更多”用二级页顶栏同款的沉浸光感按钮，位置也和 PageScaffold 对齐。 */
  @Builder
  detailTopBar() {
    Row({ space: AppSpacing.SM }) {
      this.immersiveBack(() => {
        this.closeDetail();
      })
      Blank()
      Text(this.detailPositionLabel())
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
        .height(28)
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
        .borderRadius(14)
        .backgroundColor(DETAIL_SCRIM)
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
  }

  @Builder
  immersiveBack(action: () => void) {
    ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
      buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
      accessibilityLabel: '返回主题', onBack: action })
  }

  @Builder
  detailPage(entry: ThemeListEntry) {
    Scroll() {
      Column({ space: AppSpacing.MD }) {
        this.detailHero(entry)
        Column({ space: AppSpacing.MD }) {
          this.detailInfoCard(entry)
          if (entry.customSchemeId) {
            this.detailSectionTitle(entry.theme, `方案组成 · ${this.detailDark ? '深色' : '浅色'}`)
            this.schemePartsCard(entry)
          }
          this.detailSectionTitle(entry.theme, '阅读页')
          this.detailReaderCard(entry.theme)
          this.detailSectionTitle(entry.theme, '听书面板')
          this.detailListenCard(entry)
          this.detailSectionTitle(entry.theme, '书架与导航')
          this.detailShelfCard(entry)
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
  }

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
        Row() {
          ForEach([false, true], (dark: boolean) => {
            Text(dark ? '深色' : '浅色')
              .fontSize(AppFontSize.CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.detailDark === dark ? '#242320' : '#FFFFFF')
              .backgroundColor(this.detailDark === dark ? '#FFFFFF' : Color.Transparent)
              .height(30)
              .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
              .borderRadius(15)
              .accessibilityText(`预览${dark ? '深色' : '浅色'}`)
              .accessibilityRole(AccessibilityRoleType.BUTTON)
              .onClick(() => {
                this.detailDark = dark;
              })
          }, (dark: boolean) => `detail_mode_${dark}`)
        }
        .padding(3)
        .borderRadius(18)
        .backgroundColor(DETAIL_SCRIM)
        .margin({ top: AppSpacing.XS })
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
        if (this.customSchemePackMissing(entry.customSchemeId)) {
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

  @Builder
  schemePartsCard(entry: ThemeListEntry) {
    Column() {
      ForEach(this.schemeParts(entry.customSchemeId), (part: SchemePartRow, index: number) => {
        Column() {
          if (index > 0) {
            Divider()
              .strokeWidth(0.5)
              .color(this.activeVariant(entry.theme).colors.dividerColor)
              .margin({ left: AppSpacing.LG })
          }
          Row() {
            Text(part.label)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.activeVariant(entry.theme).colors.primaryTextColor)
              .layoutWeight(1)
            Text(part.source)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.activeVariant(entry.theme).colors.subTextColor)
          }
          .width('100%')
          .height(46)
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        }
      }, (part: SchemePartRow, index: number) => `scheme_part_${index}_${part.source}`)
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.activeVariant(entry.theme).colors.cardColor)
    .clip(true)
  }

  @Builder
  detailReaderCard(theme: ThemePack) {
    Stack({ alignContent: Alignment.TopStart }) {
      ReaderThemeBackground({
        surfaceColor: this.activeVariant(theme).reader.backgroundColor,
        backgroundAssetId: this.activeVariant(theme).reader.backgroundAssetId,
        compact: false
      })
      Column({ space: AppSpacing.SM }) {
        Text('第十二章 · 灯下')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.activeVariant(theme).reader.subTextColor)
        this.readerSampleText(theme, DETAIL_READER_FONT_SIZE, DETAIL_READER_LINE_HEIGHT, DETAIL_READER_LINES)
      }
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(AppSpacing.LG * 2 + 18 + AppSpacing.SM + DETAIL_READER_LINES * DETAIL_READER_LINE_HEIGHT)
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
  }

  @Builder
  detailListenCard(entry: ThemeListEntry) {
    Stack({ alignContent: Alignment.Start }) {
      TtsPanelThemeBackground({
        themeId: this.previewTtsPanelThemeId(entry.theme, entry.customSchemeId),
        darkMode: this.variantDark()
      })
      Row({ space: AppSpacing.LG }) {
        if (this.themeHasBookCover(entry.theme)) {
          Image(ThemeAssetRegistry.themeBookCover(entry.theme.book.coverAssetId))
            .width(72)
            .aspectRatio(STORE_BOOK_COVER_RATIO)
            .borderRadius(entry.theme.radius.small)
            .objectFit(ImageFit.Cover)
            .draggable(false)
        } else {
          Column()
            .width(72)
            .aspectRatio(STORE_BOOK_COVER_RATIO)
            .borderRadius(entry.theme.radius.small)
            .backgroundColor(this.activeVariant(entry.theme).colors.accentColor)
        }
        Column({ space: AppSpacing.MD }) {
          Text('第十二章 · 灯下')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontFamily(entry.theme.typography.appFontFamily)
            .fontColor(this.activeVariant(entry.theme).colors.primaryTextColor)
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.withAlpha(this.activeVariant(entry.theme).colors.primaryTextColor, '26'))
            Row()
              .width('42%')
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.activeVariant(entry.theme).colors.accentColor)
          }
          .width('100%')
          Row({ space: AppSpacing.XL }) {
            SymbolGlyph($r('sys.symbol.backward_end_fill'))
              .fontSize(20)
              .fontColor([this.activeVariant(entry.theme).colors.primaryTextColor])
            Stack() {
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(18)
                .fontColor([ThemeRuntime.onAccentColor(this.activeVariant(entry.theme).colors.buttonColor)])
            }
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor(this.activeVariant(entry.theme).colors.buttonColor)
            SymbolGlyph($r('sys.symbol.forward_end_fill'))
              .fontSize(20)
              .fontColor([this.activeVariant(entry.theme).colors.primaryTextColor])
          }
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(AppSpacing.LG)
    }
    .width('100%')
    .height(136)
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
  }

  @Builder
  detailShelfCard(entry: ThemeListEntry) {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.MD }) {
        ForEach([0, 1, 2], (index: number) => {
          this.shelfBook(entry.theme, index)
        }, (index: number) => `detail_book_${index}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      Row() {
        ForEach(['bookshelf', 'explore', 'search', 'mine'], (tabId: string, index: number) => {
          Image(ThemeAssetRegistry.navigationIcon(entry.theme.navigation.iconPackId, tabId, index === 0))
            .width(ThemeAssetRegistry.navigationHidesLabels(entry.theme.navigation.iconPackId) ? 30 : 22)
            .height(ThemeAssetRegistry.navigationHidesLabels(entry.theme.navigation.iconPackId) ? 30 : 22)
            .fillColor(index === 0 ? this.activeVariant(entry.theme).colors.accentColor :
              this.activeVariant(entry.theme).colors.subTextColor)
            .draggable(false)
        }, (tabId: string) => `detail_nav_${tabId}`)
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Center)
      .borderRadius(24)
      .backgroundColor(this.activeVariant(entry.theme).colors.inputColor)
      .border({ width: 1, color: this.activeVariant(entry.theme).colors.dividerColor })
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.activeVariant(entry.theme).colors.pageColor)
    .backgroundImage(this.stageHomeBackdrop(entry.theme, entry.customSchemeId) || '')
    .backgroundImageSize(ImageSize.Cover)
    .backgroundImagePosition(Alignment.Top)
    .border({ width: 1, color: this.activeVariant(entry.theme).colors.dividerColor })
    .clip(true)
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
    if (!this.typographyFollowsTheme) return '排版不跟随主题，所有主题共用当前排版';
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
        this.recentThemeIds = await ThemeRecentStore.record(getContext(this), themeId);
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
            iconNotice = '；桌面图标切换失败，可在图标设置中重试';
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

  schemeEntries(): ThemeListEntry[] {
    const entries: ThemeListEntry[] = [];
    for (const scheme of this.customSchemes) {
      entries.push(new ThemeListEntry(this.customTheme(scheme), scheme.id));
    }
    return entries;
  }

  entrySelectKey(entry: ThemeListEntry): string {
    return entry.customSchemeId ? `scheme:${entry.customSchemeId}` : `theme:${entry.theme.id}`;
  }

  async loadRecentThemes(): Promise<void> {
    this.recentThemeIds = await ThemeRecentStore.load(getContext(this));
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
      if (this.customSchemePackMissing(entry.customSchemeId)) return '主题包素材不在这台设备上';
      if (this.isCustomSchemePending(entry.theme, entry.customSchemeId)) return '有改动 · 待应用';
      return this.schemeSourcesSummary(entry.customSchemeId);
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
    const keys = this.schemeEntries().map((item: ThemeListEntry): string => this.entrySelectKey(item));
    const index = keys.indexOf(`scheme:${schemeId}`);
    this.openDetail(index < 0 ? [`scheme:${schemeId}`] : keys, Math.max(0, index), '我的方案');
  }

  openDetail(keys: string[], index: number, label: string): void {
    this.detailDark = this.appDarkMode;
    this.detailKeys = keys;
    this.detailIndex = index;
    this.detailLabel = label;
    this.detailOpen = true;
  }

  closeDetail(): void {
    this.detailOpen = false;
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
    return `${this.detailLabel} ${this.detailIndex + 1} / ${this.detailKeys.length} · 左右滑动切换`;
  }

  detailHeroHeight(): number {
    return Math.min(this.contextViewportWidth * 1.3, this.contextViewportHeight * 0.62);
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

  /** 首页背景图：方案按它的“首页背景”来源取；用户在其他设置里关掉时样机也不画。 */
  stageHomeBackdrop(theme: ThemePack, customSchemeId: string): ResourceStr | null {
    if (AppStorage.get<boolean>(ThemeRuntime.KEY_HOME_BACKDROP_ENABLED) === false) return null;
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (scheme) {
      const sources = this.variantDark() ? scheme.settings.customDarkSources : scheme.settings.customLightSources;
      return ThemeAssetRegistry.homeBackdrop(sources.homeBackdropThemeId, this.variantDark());
    }
    return ThemeAssetRegistry.homeBackdrop(theme.id, this.variantDark());
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
      Text(`确定删除「${this.actionCustomScheme()?.name || '该方案'}」吗？此操作无法撤销。`)
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
    this.actionCustomSchemeId = schemeId;
    this.showDeleteCustomThemeDialog = true;
  }

  closeDeleteCustomThemeDialog(): void {
    this.showDeleteCustomThemeDialog = false;
    this.actionCustomSchemeId = '';
  }

  async confirmDeleteCustomTheme(): Promise<void> {
    const schemeId = this.actionCustomSchemeId;
    this.showDeleteCustomThemeDialog = false;
    await this.deleteCustomThemeScheme(schemeId);
  }

  async deleteCustomThemeScheme(schemeId: string): Promise<void> {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    if (!scheme) return;
    if (this.customSchemes.length <= 1) {
      HdsFeedback.showToast('至少需要保留一套自定义主题');
      return;
    }
    try {
      if (this.appThemeId === ThemeIds.CUSTOM && this.activeCustomSchemeId === schemeId) {
        await this.selectTheme(ThemeIds.PLAIN_DEFAULT, '', false);
        if (this.appThemeId === ThemeIds.CUSTOM) {
          return;
        }
      }
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const deleted = await CustomThemeSchemeStore.delete(getContext(this), settings, schemeId);
      if (!deleted) {
        HdsFeedback.showToast('删除失败，至少需要保留一套方案');
        return;
      }
      this.actionCustomSchemeId = '';
      if (this.detailOpen && this.detailKeys.indexOf(`scheme:${schemeId}`) >= 0) {
        this.closeDetail();
      }
      await this.refreshCustomSchemes();
      await ThemePackageService.cleanupImportedFiles(getContext(this));
      HdsFeedback.showToast(`已删除「${scheme.name}」`);
    } catch (e) {
      console.error('删除自定义主题失败:', e);
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
  themeRowState(entry: ThemeListEntry): string {
    if (this.applyingThemeId === (entry.customSchemeId || entry.theme.id) &&
      !this.isSelected(entry.theme, entry.customSchemeId)) return 'applying';
    if (!entry.customSchemeId && this.isTrialTheme(entry.theme.id)) return 'trial';
    if (this.isSelected(entry.theme, entry.customSchemeId)) return 'selected';
    return this.isCustomSchemePending(entry.theme, entry.customSchemeId) ? 'pending' : 'idle';
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
    return ThemeAssetRegistry.hasRegexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle);
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
    const style = ReaderCommentBubbleStyles.resolve(this.themeCommentPreview(theme).bubbleStyleId, dark,
      (dark ? theme.dark : theme.light).reader.textColor);
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

  themeCoverSet(theme: ThemePack): ResourceStr[] {
    return ThemeAssetRegistry.themeBookCovers(theme.book.coverAssetId);
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
