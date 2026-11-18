import { promptAction, router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../utils/CustomThemeSchemeStore';
import { AdaptiveColorPicker } from '../components/AdaptiveColorPicker';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import {
  ThemeBubbleStyleLabels,
  ThemeTitleEmphasisTokens,
  ThemeColorOverrides,
  ThemeColorTokens,
  ThemeComponentSourceIds,
  ThemeEmphasisOverrides,
  ThemeIds,
  ThemePack,
  ThemeRadiusOverrides,
  ThemeRegexEmphasisTokens,
  ThemeStartupTextStyle,
  SuperExclusiveThemes
} from '../theme/ThemeModels';
import { ThemeAccessPolicy } from '../account/ThemeAccessPolicy';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { InstalledThemePack, InstalledThemePackReader, ThemeImageSlots, ThemePackRegistry } from '../theme/ThemePackRegistry';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { StartupCoverImageStore } from '../utils/StartupCoverImageStore';
import { SchemeAssetResult, SchemeAssetService, SchemeFontOption } from '../utils/SchemeAssetService';
import { SchemePreviewImageStore } from '../utils/SchemePreviewImageStore';
import {
  COMMENT_BUBBLE_ORNAMENT_NAMES,
  COMMENT_BUBBLE_ORNAMENTS,
  COMMENT_BUBBLE_SHAPE_NAMES,
  COMMENT_BUBBLE_SHAPES,
  COMMENT_IMAGE_NONE,
  COMMENT_IMAGE_OVERHANG_BOTTOM,
  COMMENT_IMAGE_OVERHANG_TOP,
  COMMENT_ORNAMENT_CORNER_NAMES,
  COMMENT_ORNAMENT_CORNERS,
  commentBubbleFor,
  commentBubbleHasImage,
  commentBubbleIsEmpty,
  commentImageOverhang,
  CommentImageRepeat,
  copyCommentImage,
  normalizeCommentBubble,
  ThemePackageBubbleSlice,
  TITLE_BUBBLE_SAME_AS_EMPHASIS,
  isPackTitleBubbleStyle,
  packTitleBubbleStyleId,
  packReaderBackgroundId,
  SHELF_BACKDROP_LAYOUT_NAMES,
  SHELF_BACKDROP_LAYOUTS,
  ThemeImageCrop,
  ThemePackageBubble,
  ThemePackageCommentBubble,
  ThemePackageLimits
} from '../theme/share/ThemePackageFormat';
import {
  CHAPTER_HEAD_NONE,
  CHAPTER_HEAD_PLACEMENT_NAMES,
  CHAPTER_HEAD_PLACEMENTS,
  chapterHeadIsEmpty,
  normalizeChapterHead,
  normalizeDropCapRatio,
  normalizeOrnamentScale,
  ThemePackageChapterHead
} from '../theme/share/ThemePackageFormat';
import {
  ReaderCommentBubbleImage,
  ReaderCommentBubblePainter,
  ReaderCommentBubbleStyle,
  ReaderCommentBubbleStyles
} from '../core/reader/ReaderCommentBubble';
import { ReaderRegexBubbleStyleResolver, ReaderRegexEmphasisContext } from '../model/reader/ReaderRegexFontRule';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { CloudThemeSync } from '../account/CloudThemeSync';
import { ListDissolve } from '../utils/ListDissolve';
import { DeleteParticleBurst, DeleteParticleLayer, DeleteParticles } from '../components/common/DeleteParticles';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ThemeModeSwitch } from '../components/theme/ThemeModeSwitch';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { CustomThemePreview } from '../components/theme/CustomThemePreview';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ThemeTypographyDraft } from '../utils/ThemeTypographyDraft';
import {
  ReaderHeaderFooterEditor,
  ReaderTypographyField,
  ReaderTypographyStepper
} from '../components/reader/ReaderLayoutSettings';
import { ReaderInfoBarConfig } from '../core/reader/ReaderInfoBarModel';
import { ReaderParagraphIndent } from '../core/reader/ReaderParagraphIndent';
import { ThemeCropRequest, ThemeImageCropper } from '../components/theme/ThemeImageCropper';
import { BubbleFrameStretchRequest, ThemeBubbleFrameStretcher } from '../components/theme/ThemeBubbleFrameStretcher';
import { CommentImageStretchRequest, ThemeCommentImageStretcher } from '../components/theme/ThemeCommentImageStretcher';
import { ThemeBubbleFramePreview } from '../components/theme/ThemeBubbleFramePreview';
import { ThemeCroppedImage } from '../components/theme/ThemeCroppedImage';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { TtsPanelThemeStyles } from '../theme/TtsPanelThemeStyles';
import { HexColor } from '../utils/HexColor';
import { AnimatedImagePolicy } from '../utils/AnimatedImagePolicy';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';

const DROP_CAP_LINE_NAMES: string[] = ['不处理', '占 2 行', '占 3 行'];

interface ThemeEditorSectionTitleOptions {
  title: string;
}

interface RadiusRowOptions {
  title: string;
  key: string;
}

interface AssetRowOptions {
  title: string;
  description: string;
  onTap: () => void;
  divider?: boolean;
  // 上传类入口属于高级自定义，非会员点开先提示开通；移除类入口不受限。
  member?: boolean;
}

/** 素材槽：自传（own）、跟随来源主题（inherit）或空（empty）。 */
interface AssetSlotOptions {
  label: string;
  image: ResourceStr;
  state: string;
  slotWidth: number;
  slotHeight: number;
  onTap: () => void;
  rotation?: number;
  icon?: boolean;
  // 书架边框这类中心透明的 SVG：不套 fillColor，否则透明的中心也会被填成一整块。
  untinted?: boolean;
  // 动图取景记下的显示区域，按区域显示缩略图。
  crop?: ThemeImageCrop | null;
}

/** 顶栏浅色/深色开关的宽度：比排版页窄一些，给标题和“完成”留位置。 */
const HEADER_MODE_SWITCH_WIDTH: number = 128;

interface CoverTileOptions {
  index: number;
  uri: string;
}

/** 方案阅读页颜色（customLight/Dark Reader*）：直接改方案设置，换阅读来源时整组重置为来源主题的值。 */
class ThemeEditorReaderColors {
  backgroundColor: string = '';
  textColor: string = '';
  subTextColor: string = '';
  contentTone: string = 'light';
}

/** 编辑器的建议：只提醒、不拦保存，点了跳到对应场景页签里的分组（mode 非空时一并切到那个模式）。 */
class ThemeEditorIssue {
  text: string = '';
  detail: string = '';
  section: string = '';
  group: string = '';
  mode: string = '';
  swatch: string = '';
}

class ThemeEditorUndoEntry {
  settings: AppThemeSettings = new AppThemeSettings();
  mode: string = 'light';
  // 排版页签的改动只记改动前的阅读排版，撤销时不动方案的其他设置。
  typography: ReaderSettings | null = null;
}

@Component
struct ThemeColorOption {
  @Prop color: string = '';
  @Prop title: string = '';
  @Prop appDarkMode: boolean = false;
  @Prop cardColor: string = '#FFFFFF';
  @Prop primaryTextColor: string = '#1F1F1F';
  @Prop accentColor: string = '#007DFF';
  @Prop showDivider: boolean = true;
  @Prop description: string = '';
  /** 与桌面编辑器 alpha 字段对应：允许输入 #AARRGGBB，取色面板带透明度滑杆。 */
  @Prop allowAlpha: boolean = false;
  onColorChange: (color: string) => void = (_color: string): void => {};

  build() {
    Stack() {
      SettingRow({ title: this.title, description: this.description, showDivider: this.showDivider }) {
        Text(this.color)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .margin({ right: AppSpacing.MD })
        Row()
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(this.color)
          .border({ width: 2, color: this.appDarkMode ? '#55FFFFFF' : '#22000000' })
      }

      AdaptiveColorPicker({
        value: this.color,
        placeholder: this.color,
        appDarkMode: this.appDarkMode,
        accentColor: this.accentColor,
        allowAlpha: this.allowAlpha,
        optionTitle: this.title,
        hideOptionTrigger: true,
        onColorChange: (color: string) => {
          this.onColorChange(color);
        }
      })
    }
    .width('100%')
    .margin({ top: 1 })
  }
}

@Extend(Column)
function editorCard(color: string) {
  .width('calc(100% - 24vp)')
  .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
  .backgroundColor(color)
  .borderRadius(ThemeRuntime.cardRadius())
  .clip(true)
}

/** 取景结果：要导入的文件，以及动图取景记下的显示区域（静图已经裁进文件，为 null）。 */
class PickedArtwork {
  uri: string = '';
  fromFile: boolean = false;
}

class FramedImage {
  path: string = '';
  crop: ThemeImageCrop | null = null;
}

@Entry
@Component
struct ThemeColorSettingsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appThemeId') appThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('accountEntitlementsRevision') accountEntitlementsRevision: number = 0;
  @StorageLink('accountMembershipSku') membershipSku: string = '';
  @State selectedMode: string = 'light';
  @State lightAccentColor: string = '#007DFF';
  @State darkAccentColor: string = '#4E9BFF';
  @State lightButtonColor: string = '#007DFF';
  @State darkButtonColor: string = '#3F8CFF';
  @State customBaseThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @State lightSources: ThemeComponentSourceIds = new ThemeComponentSourceIds();
  @State darkSources: ThemeComponentSourceIds = new ThemeComponentSourceIds();
  @State lightStartupImagePath: string = '';
  @State darkStartupImagePath: string = '';
  @State lightStartupTitle: string = '开源轻页';
  @State darkStartupTitle: string = '开源轻页';
  @State lightStartupSubtitle: string = '';
  @State darkStartupSubtitle: string = '';
  @State lightPalette: ThemeColorOverrides = new ThemeColorOverrides();
  @State darkPalette: ThemeColorOverrides = new ThemeColorOverrides();
  @State lightEmphasis: ThemeEmphasisOverrides = new ThemeEmphasisOverrides();
  @State darkEmphasis: ThemeEmphasisOverrides = new ThemeEmphasisOverrides();
  // 段评气泡小样按外观缓存，不是状态。
  private commentPreviewImages: Map<string, ReaderCommentBubbleImage | null> =
    new Map<string, ReaderCommentBubbleImage | null>();
  // 方案自己上传的素材所在的包；空表示还没上传过。
  @State ownPackageId: string = '';
  @StorageLink('installedThemePacksRevision') installedPacksRevision: number = 0;
  // 素材上传/移除只改包与草稿，不改其他状态；靠它让预览和上传行重绘。
  @State assetRevision: number = 0;
  /** 正在消散的封面格子（模式_序号），见 ListDissolve。 */
  @State dissolvingCoverKeys: string[] = [];
  @State deleteParticleBursts: DeleteParticleBurst[] = [];
  // 拖动左上/右下“角饰大小”时的实时百分比；松手保存完回到 -1，改读主题包里的值。
  @State leadingScaleDrag: number = -1;
  @State trailingScaleDrag: number = -1;
  @State chapterHeadScaleDrag: number = -1;
  @State dropCapRatioDrag: number = -1;
  @State appFontFamily: string = '';
  @State fontLibrary: SchemeFontOption[] = [];
  @State radiusOverride: ThemeRadiusOverrides = new ThemeRadiusOverrides();
  @State lightStartupText: ThemeStartupTextStyle = new ThemeStartupTextStyle();
  @State darkStartupText: ThemeStartupTextStyle = new ThemeStartupTextStyle();
  @State previewImagePath: string = '';
  @State availableThemes: ThemePack[] = [];
  // 页签按场景分（global / shelf / reader / typography / other），预览画面跟着页签走；
  // “其他”里是朗读面板、启动页和方案信息，预览跟着展开的分组走。
  @State editorSection: string = 'global';
  // 每个场景下同一时间只展开一个分组；空串表示全部收起。
  @State openGroup: string = 'palette';
  // 展开了“更多”的分组。
  @State moreGroups: string[] = [];
  // 往下滚时预览收矮，给控件让地方。
  @State previewShrunk: boolean = false;
  @State previewScene: string = 'mine';
  @State fullPreview: boolean = false;
  @State undoAvailable: boolean = false;
  @State schemeName: string = '';
  @State editorReady: boolean = false;
  @State saving: boolean = false;
  @State saveFailed: boolean = false;
  @State readerProfile: ReaderSettings = new ReaderSettings();
  @State readerProfileBound: boolean = false;
  // 排版页签编辑的就是 readerProfile；页眉页脚三项单独成状态，交给页眉页脚控件双向绑定。
  @State typoHeaderEnabled: boolean = false;
  @State typoFooterEnabled: boolean = true;
  @State typoInfoBarConfig: string = '';
  @State typoStepperKey: number = 0;
  @State typoActiveScheme: boolean = false;
  @State typoFollowsTheme: boolean = true;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State viewportHeight: number = 0;
  @State viewportWidth: number = 360;
  @State closing: boolean = false;
  @State lightReader: ThemeEditorReaderColors = new ThemeEditorReaderColors();
  @State darkReader: ThemeEditorReaderColors = new ThemeEditorReaderColors();
  @State schemeAuthor: string = '';
  @State nameDraft: string = '';
  @State schemeDescription: string = '';
  @State cropRequest: ThemeCropRequest = new ThemeCropRequest();
  @State cropVisible: boolean = false;
  @State frameStretchRequest: BubbleFrameStretchRequest = new BubbleFrameStretchRequest();
  @State frameStretchVisible: boolean = false;
  @State commentStretchRequest: CommentImageStretchRequest = new CommentImageStretchRequest();
  @State commentStretchVisible: boolean = false;
  @State checksExpanded: boolean = false;
  // 素材尺寸类建议要读图片，异步算好放这里；颜色类建议随状态即时算。
  @State assetIssues: ThemeEditorIssue[] = [];
  @State previewShelfLayout: string = 'companion';
  @State showShelfLayoutMenu: boolean = false;
  private schemeId: string = '';
  private cropResolve: ((result: string) => void) | null = null;
  private frameStretchResolve: ((settings: ThemePackageBubble | null) => void) | null = null;
  private commentStretchResolve: ((settings: ThemePackageCommentBubble | null) => void) | null = null;
  // 动图取景交回的显示区域；frameImage 读走后清空。
  private cropArea: ThemeImageCrop | null = null;
  private draftSettings: AppThemeSettings = new AppThemeSettings();
  private saveQueue: Promise<void> = Promise.resolve();
  private settingsLoaded: boolean = false;
  private settingsLoading: boolean = false;
  private editorScroller: Scroller = new Scroller();
  private undoEntries: ThemeEditorUndoEntry[] = [];
  private obsoleteStartupPaths: string[] = [];
  private pendingSaves: number = 0;
  private returningFromTypography: boolean = false;
  // 上一次已记入撤销的排版，下一次改动时作为“改动前”存进撤销记录。
  private typoCommitted: ReaderSettings = new ReaderSettings();
  private typoUndoAt: number = 0;
  private typoDirty: boolean = false;
  private typoSaveFailed: boolean = false;
  private typoSaveTimer: number = -1;
  private typoSaveQueue: Promise<void> = Promise.resolve();
  private fontDraftRevision: number = -1;

  aboutToAppear(): void {
    this.reloadSettings();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadSettings();
    if (this.returningFromTypography) {
      this.returningFromTypography = false;
      this.reloadReaderProfile();
    }
    this.pullFontDraft();
    this.syncBars();
  }

  onPageHide(): void {
    this.flushTypography();
  }

  onBackPress(): boolean {
    if (this.cropVisible) {
      this.finishCrop('');
      return true;
    }
    if (this.frameStretchVisible) {
      this.finishFrameStretch(null);
      return true;
    }
    if (this.commentStretchVisible) {
      this.finishCommentStretch(null);
      return true;
    }
    this.handleBack();
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: this.fullPreview ? '主题预览' : (this.schemeName || '编辑主题'),
        scrollable: false, collapsible: false, onBack: () => this.handleBack(), content: () => {
        this.pageContent()
      }, actions: () => {
        this.titleActions()
      } })
      if (this.cropVisible) {
        ThemeImageCropper({
          request: this.cropRequest,
          onDone: (path: string) => this.finishCrop(path),
          onArea: (crop: ThemeImageCrop) => {
            this.cropArea = crop;
            this.finishCrop(this.cropRequest.uri);
          },
          onOriginal: () => this.finishCrop(this.cropRequest.uri),
          onCancel: () => this.finishCrop('')
        })
      }
      if (this.frameStretchVisible) {
        ThemeBubbleFrameStretcher({
          request: this.frameStretchRequest,
          onDone: (settings: ThemePackageBubble) => this.finishFrameStretch(settings),
          onCancel: () => this.finishFrameStretch(null)
        })
      }
      if (this.commentStretchVisible) {
        ThemeCommentImageStretcher({
          request: this.commentStretchRequest,
          onDone: (settings: ThemePackageCommentBubble) => this.finishCommentStretch(settings),
          onCancel: () => this.finishCommentStretch(null)
        })
      }
      if (this.deleteParticleBursts.length > 0) {
        DeleteParticleLayer({ bursts: this.deleteParticleBursts })
      }
    }
    .id('theme_color_settings_root')
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewportHeight = Number(newArea.height);
      this.viewportWidth = Number(newArea.width);
    })
  }

  @Builder
  pageContent() {
    Column() {
      if (this.fullPreview) {
        Column() {
          this.previewSurface(true)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        this.sceneGrid()
      } else {
        if (!this.compactEditor()) {
          this.previewPanel()
        }
        this.sectionTabs()
        Scroll(this.editorScroller) {
          Column() {
            if (this.compactEditor()) {
              this.previewPanel()
            }
            if (!this.editorReady) {
              this.sectionTitle({ title: '正在读取主题方案…' })
            } else {
              if (this.checksExpanded) {
                this.issuesList()
              }
              if (this.editorSection === 'shelf') {
                this.shelfSection()
              } else if (this.editorSection === 'reader') {
                this.readerSection()
              } else if (this.editorSection === 'typography') {
                this.typographySection()
              } else if (this.editorSection === 'other') {
                this.otherSection()
              } else {
                this.globalSection()
              }
            }
            this.sectionTitle({ title: this.saveFailed ? '保存失败，请点击完成重试' :
              '修改自动保存到方案，返回主题页后手动启用' })
          }
          .width('100%')
          .padding({ bottom: this.navBarHeight + AppSpacing.XXL })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onDidScroll(() => this.syncPreviewShrink())
      }
    }
    .width('100%')
    .height('100%')
    .enabled(!this.closing)
  }

  async reloadSettings(): Promise<void> {
    if (this.settingsLoaded || this.settingsLoading) {
      return;
    }
    this.settingsLoading = true;
    try {
      const currentSettings = await AppThemeSettingsStore.load(getContext(this));
      const params = router.getParams() as Record<string, string>;
      this.schemeId = (params['schemeId'] || this.schemeId || '').trim();
      const schemes = await CustomThemeSchemeStore.load(getContext(this), currentSettings);
      let scheme = CustomThemeSchemeStore.find(schemes, this.schemeId);
      if (!scheme && schemes.length > 0) {
        scheme = schemes[0];
        this.schemeId = scheme.id;
      }
      if (!scheme) {
        return;
      }
      // 素材包还在云端时先下载：在缺包的方案上改素材会建出一个残缺的包，再同步回去就覆盖了云端的完整版本。
      if (CloudThemeSync.remotePacksOf(scheme).length > 0) {
        HdsFeedback.showToast('正在下载云端的主题素材…');
      }
      try {
        await CloudThemeSync.ensureSchemePacks(getContext(this), scheme);
      } catch (e) {
        HdsFeedback.showToast(`主题素材下载失败：${(e as Error).message}`);
      }
      this.schemeName = scheme.name;
      this.schemeAuthor = scheme.author;
      this.nameDraft = scheme.name;
      this.schemeDescription = scheme.description;
      this.previewShelfLayout = AppStorage.get<string>('bookshelfLayoutMode') || 'companion';
      this.ownPackageId = SchemeAssetService.packageIdOf(scheme);
      try {
        const reader = await ReaderSettingsStore.load(getContext(this));
        this.fontLibrary = SchemeAssetService.fontOptions(reader.customFontsRaw);
      } catch (_) {
        this.fontLibrary = [];
      }
      const settings = AppThemeSettingsStore.cloneSettings(scheme.settings);
      this.draftSettings = settings;
      this.customBaseThemeId = settings.customBaseThemeId;
      this.lightAccentColor = settings.customLightAccentColor;
      this.darkAccentColor = settings.customDarkAccentColor;
      this.lightButtonColor = settings.customLightButtonColor;
      this.darkButtonColor = settings.customDarkButtonColor;
      this.loadOverrides(settings);
      this.lightSources = AppThemeSettingsStore.cloneSources(
        settings.customLightSources, settings.customBaseThemeId);
      this.darkSources = AppThemeSettingsStore.cloneSources(
        settings.customDarkSources, settings.customBaseThemeId);
      this.lightStartupImagePath = settings.customLightStartupImagePath;
      this.darkStartupImagePath = settings.customDarkStartupImagePath;
      this.lightStartupTitle = settings.customLightStartupTitle;
      this.darkStartupTitle = settings.customDarkStartupTitle;
      this.lightStartupSubtitle = settings.customLightStartupSubtitle;
      this.darkStartupSubtitle = settings.customDarkStartupSubtitle;
      this.refreshAvailableThemes();
      this.settingsLoaded = true;
      this.editorReady = true;
      this.refreshAssetIssues();
      await this.reloadReaderProfile();
    } catch (e) {
      console.warn('读取主题色设置失败:', e);
    } finally {
      this.settingsLoading = false;
    }
  }

  onSettingChanged(): Promise<void> {
    if (!this.settingsLoaded) return Promise.resolve();
    const settings = this.settingsFromState();
    this.draftSettings = settings;
    this.pendingSaves++;
    this.saving = true;
    this.saveQueue = this.saveQueue.then(async () => {
      try {
        await this.persistCurrentScheme(settings);
        this.saveFailed = false;
      } catch (e) {
        this.saveFailed = true;
        console.warn('保存自定义主题方案失败:', e);
      } finally {
        this.pendingSaves--;
        this.saving = this.pendingSaves > 0;
      }
    });
    return this.saveQueue;
  }

  async persistCurrentScheme(settings: AppThemeSettings): Promise<void> {
    const currentSettings = await AppThemeSettingsStore.load(getContext(this));
    const scheme = new CustomThemeScheme();
    scheme.id = this.schemeId;
    scheme.name = this.schemeName;
    scheme.settings = settings;
    await CustomThemeSchemeStore.saveScheme(getContext(this), currentSettings, scheme);
  }

  async closeEditor(): Promise<void> {
    if (this.closing) {
      return;
    }
    this.closing = true;
    try {
      await this.commitName();
      await this.saveInfo();
      await this.onSettingChanged();
      if (this.saveFailed) {
        this.closing = false;
        HdsFeedback.showToast('保存主题方案失败，请重试');
        return;
      }
      await this.flushTypography();
      if (this.typoSaveFailed) {
        this.closing = false;
        return;
      }
      this.cleanupStartupImages();
      this.getUIContext().getRouter().back();
    } catch (e) {
      this.closing = false;
      console.warn('返回主题页前保存方案失败:', e);
    }
  }

  async setComponentSource(category: string, themeId: string): Promise<void> {
    if (!themeId) return;
    if (themeId === this.sourceThemeId(category)) return;
    if (SuperExclusiveThemes.has(themeId) && !AccountSessionStore.hasOwnedEntitlement(themeId)) {
      this.refreshAvailableThemes();
      return;
    }
    try {
      this.rememberChange();
      const settings = this.settingsFromState();
      const dark = this.selectedMode === 'dark';
      const sources = AppThemeSettingsStore.cloneSources(
        dark ? settings.customDarkSources : settings.customLightSources,
        settings.customBaseThemeId);
      this.setSourceValue(sources, category, themeId);
      if (dark) settings.customDarkSources = sources;
      else settings.customLightSources = sources;
      if (category === 'layout') {
        const otherSources = AppThemeSettingsStore.cloneSources(
          dark ? settings.customLightSources : settings.customDarkSources,
          settings.customBaseThemeId);
        this.setSourceValue(otherSources, category, themeId);
        if (dark) settings.customLightSources = otherSources;
        else settings.customDarkSources = otherSources;
      }
      this.copyVariantOverrides(settings, BuiltinThemeRegistry.findById(themeId), dark, category);
      this.loadReaderColors(settings);
      this.draftSettings = settings;
      this.lightSources = AppThemeSettingsStore.cloneSources(
        settings.customLightSources, settings.customBaseThemeId);
      this.darkSources = AppThemeSettingsStore.cloneSources(
        settings.customDarkSources, settings.customBaseThemeId);
      this.lightAccentColor = settings.customLightAccentColor;
      this.darkAccentColor = settings.customDarkAccentColor;
      this.lightButtonColor = settings.customLightButtonColor;
      this.darkButtonColor = settings.customDarkButtonColor;
      await this.onSettingChanged();
    } catch (e) {
      console.warn('保存自定义主题方案部件失败:', e);
    }
  }

  setSourceValue(sources: ThemeComponentSourceIds, category: string, themeId: string): void {
    if (category === 'startup') sources.startupThemeId = themeId;
    else if (category === 'palette') sources.paletteThemeId = themeId;
    else if (category === 'reader') sources.readerThemeId = themeId;
    else if (category === 'ttsPanel') sources.ttsPanelThemeId = themeId;
    else if (category === 'bubble') sources.bubbleThemeId = themeId;
    else if (category === 'navigation') sources.navigationThemeId = themeId;
    else if (category === 'book') sources.bookThemeId = themeId;
    else if (category === 'homeBackdrop') sources.homeBackdropThemeId = themeId;
    else if (category === 'typography') sources.typographyThemeId = themeId;
    else if (category === 'layout') sources.layoutThemeId = themeId;
    else if (category === 'radius') sources.radiusThemeId = themeId;
    else if (category === 'glass') sources.glassThemeId = themeId;
  }

  copyVariantOverrides(settings: AppThemeSettings, theme: ThemePack, dark: boolean, category: string): void {
    const variant = dark ? theme.dark : theme.light;
    if (category === 'palette') {
      if (dark) {
        settings.customDarkAccentColor = variant.colors.accentColor;
        settings.customDarkButtonColor = variant.colors.buttonColor;
      } else {
        settings.customLightAccentColor = variant.colors.accentColor;
        settings.customLightButtonColor = variant.colors.buttonColor;
      }
    }
    if (category !== 'reader') return;
    if (dark) {
      settings.customDarkReaderBackgroundColor = variant.reader.backgroundColor;
      settings.customDarkReaderTextColor = variant.reader.textColor;
      settings.customDarkReaderSubTextColor = variant.reader.subTextColor;
      settings.customDarkReaderBackgroundAssetId = variant.reader.backgroundAssetId;
      settings.customDarkReaderBackgroundImageFit = variant.reader.backgroundImageFit;
      settings.customDarkReaderContentTone = variant.reader.contentTone;
    } else {
      settings.customLightReaderBackgroundColor = variant.reader.backgroundColor;
      settings.customLightReaderTextColor = variant.reader.textColor;
      settings.customLightReaderSubTextColor = variant.reader.subTextColor;
      settings.customLightReaderBackgroundAssetId = variant.reader.backgroundAssetId;
      settings.customLightReaderBackgroundImageFit = variant.reader.backgroundImageFit;
      settings.customLightReaderContentTone = variant.reader.contentTone;
    }
  }

  currentSources(): ThemeComponentSourceIds {
    return this.selectedMode === 'dark' ? this.darkSources : this.lightSources;
  }

  static readonly SOURCE_CATEGORIES: string[] = ['startup', 'palette', 'reader', 'ttsPanel', 'bubble', 'navigation',
    'book', 'homeBackdrop', 'typography', 'layout', 'radius', 'glass'];

  /** 每个场景页签能看的预览画面，第一个是切到这个页签时显示的。 */
  sceneChoices(section: string = this.editorSection): string[] {
    if (section === 'shelf') return ['bookshelf', 'explore', 'mine'];
    if (section === 'reader' || section === 'typography') return ['reader'];
    if (section === 'other') return ['tts', 'startup', 'card'];
    return ['mine', 'explore', 'bookshelf'];
  }

  defaultGroup(section: string): string {
    if (section === 'shelf') return 'navigation';
    if (section === 'reader') return 'reader';
    if (section === 'typography') return 'typoBody';
    if (section === 'other') return 'ttsPanel';
    return 'palette';
  }

  /** “其他”页签里各分组对应的预览画面。 */
  otherSceneFor(group: string): string {
    if (group === 'ttsPanel') return 'tts';
    if (group === 'info' || group === 'card') return 'card';
    return 'startup';
  }

  openSection(section: string, group: string = ''): void {
    this.editorSection = section;
    this.openGroup = group || this.defaultGroup(section);
    this.previewScene = section === 'other' ? this.otherSceneFor(this.openGroup) : this.sceneChoices(section)[0];
    this.previewShrunk = false;
    this.editorScroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  toggleGroup(key: string): void {
    this.openGroup = this.openGroup === key ? '' : key;
    if (this.editorSection === 'other' && this.openGroup) {
      this.previewScene = this.otherSceneFor(this.openGroup);
    }
  }

  moreOpen(key: string): boolean {
    return this.moreGroups.includes(key);
  }

  toggleMore(key: string): void {
    this.moreGroups = this.moreOpen(key) ? this.moreGroups.filter((item: string): boolean => item !== key) :
      this.moreGroups.concat([key]);
  }

  /** 预览里左右滑：在这个页签能看的几个画面之间切换。 */
  stepPreviewScene(forward: boolean): void {
    const choices = this.sceneChoices();
    if (choices.length < 2) return;
    const index = Math.max(0, choices.indexOf(this.previewScene));
    this.previewScene = choices[(index + (forward ? 1 : choices.length - 1)) % choices.length];
  }

  /** 预览固定在列表上方时，往下滚收矮、滚回顶部恢复；两个阈值错开，避免在临界处来回跳。 */
  syncPreviewShrink(): void {
    if (this.compactEditor()) return;
    const offset = this.editorScroller.currentOffset().yOffset;
    if (offset > 72 && !this.previewShrunk) {
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.previewShrunk = true;
      });
    } else if (offset < 4 && this.previewShrunk) {
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.previewShrunk = false;
      });
    }
  }

  handleBack(): void {
    if (this.fullPreview) {
      this.fullPreview = false;
    } else {
      this.closeEditor();
    }
  }

  /** 当前模式下所有部件都取自同一套主题时返回它，混搭时返回空串。 */
  uniformSourceId(): string {
    const first = this.sourceThemeId(ThemeColorSettingsPage.SOURCE_CATEGORIES[0]);
    for (const category of ThemeColorSettingsPage.SOURCE_CATEGORIES) {
      if (this.sourceThemeId(category) !== first) return '';
    }
    return first;
  }

  baseThemeLabel(): string {
    const id = this.uniformSourceId();
    return id ? BuiltinThemeRegistry.findById(id).name : '混搭';
  }

  baseThemeIndex(): number {
    const id = this.uniformSourceId();
    for (let index = 0; index < this.availableThemes.length; index++) {
      if (this.availableThemes[index].id === id) return index;
    }
    return -1;
  }

  /** 基础主题：浅色、深色的全部部件来源一次换成同一套，逐项覆盖和上传的素材不删，之后可以再逐组改回去。 */
  async applyBaseTheme(themeId: string): Promise<void> {
    if (!themeId || (this.sourceUsesOnly(this.lightSources, themeId) &&
      this.sourceUsesOnly(this.darkSources, themeId))) {
      return;
    }
    if (SuperExclusiveThemes.has(themeId) && !AccountSessionStore.hasOwnedEntitlement(themeId)) {
      this.refreshAvailableThemes();
      return;
    }
    try {
      this.rememberChange();
      const settings = this.settingsFromState();
      const theme = BuiltinThemeRegistry.findById(themeId);
      for (const dark of [false, true]) {
        const sources = AppThemeSettingsStore.cloneSources(
          dark ? settings.customDarkSources : settings.customLightSources, settings.customBaseThemeId);
        for (const category of ThemeColorSettingsPage.SOURCE_CATEGORIES) {
          this.setSourceValue(sources, category, themeId);
        }
        if (dark) settings.customDarkSources = sources;
        else settings.customLightSources = sources;
        this.copyVariantOverrides(settings, theme, dark, 'palette');
        this.copyVariantOverrides(settings, theme, dark, 'reader');
      }
      this.loadReaderColors(settings);
      this.draftSettings = settings;
      this.lightSources = AppThemeSettingsStore.cloneSources(
        settings.customLightSources, settings.customBaseThemeId);
      this.darkSources = AppThemeSettingsStore.cloneSources(
        settings.customDarkSources, settings.customBaseThemeId);
      this.lightAccentColor = settings.customLightAccentColor;
      this.darkAccentColor = settings.customDarkAccentColor;
      this.lightButtonColor = settings.customLightButtonColor;
      this.darkButtonColor = settings.customDarkButtonColor;
      this.assetRevision++;
      await this.onSettingChanged();
      HdsFeedback.showToast(`已全部换成「${theme.name}」，可以撤销`);
    } catch (e) {
      console.warn('更换基础主题失败:', e);
    }
  }

  sourceUsesOnly(sources: ThemeComponentSourceIds, themeId: string): boolean {
    return sources.startupThemeId === themeId && sources.paletteThemeId === themeId &&
      sources.readerThemeId === themeId && sources.ttsPanelThemeId === themeId &&
      sources.bubbleThemeId === themeId && sources.navigationThemeId === themeId &&
      sources.bookThemeId === themeId && sources.homeBackdropThemeId === themeId &&
      sources.typographyThemeId === themeId && sources.layoutThemeId === themeId &&
      sources.radiusThemeId === themeId && sources.glassThemeId === themeId;
  }

  sourceName(category: string): string {
    return BuiltinThemeRegistry.findById(this.sourceThemeId(category)).name;
  }

  /** 分组收起时标题右侧的一句当前状态。 */
  groupSummary(key: string): string {
    // 主题包记录不是状态变量：读 assetRevision，素材变了才会重新取值。
    if (this.assetRevision < 0 || !this.editorReady) return '';
    if (key === 'base') return this.baseThemeLabel();
    if (key === 'radius') return `卡片 ${this.radiusValue('card')} · 按钮 ${this.radiusValue('button')}`;
    if (key === 'font') return this.appFontIndex() > 0 ? this.appFontLabel() : this.sourceName('typography');
    if (key === 'navigation') return this.ownNavigationActive() ? '已上传' : this.sourceName('navigation');
    if (key === 'book') {
      return this.ownCoverPaths().length > 0 ? `封面 ${this.ownCoverPaths().length} 张` : this.sourceName('book');
    }
    if (key === 'homeBackdrop') return this.ownHomeBackdrop() ? '已上传' : this.sourceName('homeBackdrop');
    if (key === 'bubble') return this.bubbleStyleLabel(this.effectiveEmphasis().bubbleStyle) || this.sourceName('bubble');
    if (key === 'comment') return this.commentShapeLabel();
    if (key === 'title') {
      return this.effectiveTitle().mode === 'bubble' ? this.titleStyleLabel(this.effectiveTitleStyle()) : this.titleModeLabel();
    }
    if (key === 'chapterHead') {
      if (this.currentEmphasis().chapterHead === CHAPTER_HEAD_NONE) return '不显示';
      const head = this.effectiveChapterHead();
      const parts: string[] = [];
      if (head.image) parts.push(CHAPTER_HEAD_PLACEMENT_NAMES[Math.max(0, CHAPTER_HEAD_PLACEMENTS.indexOf(head.placement || 'side'))]);
      if (head.dropCapLines > 0) parts.push(head.dropCapImage ? '首字印章' : '首字放大');
      if (parts.length > 0) return parts.join(' · ');
      return head.numberColor ? '序号行颜色' : '未设置';
    }
    if (key === 'typoBody') return `字号 ${this.readerProfile.fontSize} · 行距 ${this.readerProfile.lineHeight}`;
    if (key === 'typoBars') {
      return `页眉 ${this.typoHeaderEnabled ? '开' : '关'} · 页脚 ${this.typoFooterEnabled ? '开' : '关'}`;
    }
    if (key === 'typoFont') return this.readerFontLabel(this.readerProfile.bodyFontMode);
    if (key === 'typoMore') return `取自 ${this.sourceName('layout')}`;
    if (key === 'ttsPanel') return this.ownTtsPanel() ? '已上传插画' : this.sourceName('ttsPanel');
    if (key === 'startup') return this.currentStartupImagePath() ? '已上传' : this.sourceName('startup');
    if (key === 'startupText') return this.currentStartupTitle() || '未填写';
    if (key === 'startupStyle') {
      return AppThemeSettingsStore.hasStartupTextStyle(this.currentStartupText()) ? '自定义' : '默认';
    }
    if (key === 'info') return this.schemeName;
    if (key === 'card') return this.previewImagePath ? '有预览图' : '用启动封面';
    return '';
  }

  /** 配色、阅读背景两组收起时用色块代替文字。 */
  groupDots(key: string): string[] {
    if (!this.editorReady) return [];
    if (key === 'palette') {
      const colors = this.effectiveColors();
      return [this.currentAccentColor(), this.currentButtonColor(), colors.pageColor, colors.primaryTextColor];
    }
    if (key === 'reader') return [this.currentReader().backgroundColor, this.currentReader().textColor];
    return [];
  }

  openIssue(issue: ThemeEditorIssue): void {
    if (issue.mode) this.selectedMode = issue.mode;
    this.checksExpanded = false;
    this.openSection(issue.section, issue.group);
  }

  rememberChange(): void {
    const entry = new ThemeEditorUndoEntry();
    entry.settings = this.settingsFromState();
    entry.mode = this.selectedMode;
    this.undoEntries.push(entry);
    if (this.undoEntries.length > 20) this.undoEntries.shift();
    this.undoAvailable = true;
  }

  undoChange(): void {
    const entry = this.undoEntries.pop();
    if (!entry) return;
    if (entry.typography) {
      this.applyTypography(entry.typography);
      this.typoUndoAt = 0;
      this.typoDirty = true;
      this.scheduleTypographySave();
      this.undoAvailable = this.undoEntries.length > 0;
      return;
    }
    this.trackObsoleteStartupPath(this.lightStartupImagePath);
    this.trackObsoleteStartupPath(this.darkStartupImagePath);
    const settings = entry.settings;
    this.draftSettings = settings;
    this.selectedMode = entry.mode;
    this.customBaseThemeId = settings.customBaseThemeId;
    this.lightSources = AppThemeSettingsStore.cloneSources(settings.customLightSources, settings.customBaseThemeId);
    this.darkSources = AppThemeSettingsStore.cloneSources(settings.customDarkSources, settings.customBaseThemeId);
    this.lightAccentColor = settings.customLightAccentColor;
    this.darkAccentColor = settings.customDarkAccentColor;
    this.lightButtonColor = settings.customLightButtonColor;
    this.darkButtonColor = settings.customDarkButtonColor;
    this.loadOverrides(settings);
    this.lightStartupImagePath = settings.customLightStartupImagePath;
    this.darkStartupImagePath = settings.customDarkStartupImagePath;
    this.lightStartupTitle = settings.customLightStartupTitle;
    this.darkStartupTitle = settings.customDarkStartupTitle;
    this.lightStartupSubtitle = settings.customLightStartupSubtitle;
    this.darkStartupSubtitle = settings.customDarkStartupSubtitle;
    this.undoAvailable = this.undoEntries.length > 0;
    this.assetRevision++;
    this.onSettingChanged();
  }

  trackObsoleteStartupPath(imagePath: string): void {
    if (imagePath && this.obsoleteStartupPaths.indexOf(imagePath) < 0) {
      this.obsoleteStartupPaths.push(imagePath);
    }
  }

  cleanupStartupImages(): void {
    // 撤销仍可能恢复旧封面，成功保存并退出编辑器后再清理不再引用的图片。
    for (const imagePath of this.obsoleteStartupPaths) {
      if (imagePath !== this.lightStartupImagePath && imagePath !== this.darkStartupImagePath &&
        imagePath !== this.previewImagePath) {
        StartupCoverImageStore.remove(getContext(this), imagePath);
        SchemePreviewImageStore.remove(getContext(this), imagePath);
      }
    }
    this.obsoleteStartupPaths = [];
  }

  async reloadReaderProfile(): Promise<void> {
    if (!this.schemeId) return;
    try {
      const profileId = ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, this.schemeId);
      this.readerProfileBound = await ReaderSettingsStore.hasThemeTypography(getContext(this), profileId);
      this.typoActiveScheme = profileId === ReaderSettingsStore.activeProfileId();
      this.typoFollowsTheme = await ReaderSettingsStore.typographyFollowsTheme(getContext(this));
      this.applyTypography(await ReaderSettingsStore.loadProfile(getContext(this), profileId));
    } catch (e) {
      console.warn('读取主题排版预览失败:', e);
    }
  }

  static copyReaderSettings(source: ReaderSettings): ReaderSettings {
    return JSON.parse(JSON.stringify(source)) as ReaderSettings;
  }

  /** 把一份阅读排版放进编辑状态（读取、撤销、套用、恢复默认都走这里），步进控件随之重建。 */
  applyTypography(settings: ReaderSettings): void {
    const next = ThemeColorSettingsPage.copyReaderSettings(settings);
    this.readerProfile = next;
    this.typoHeaderEnabled = next.readerHeaderEnabled;
    this.typoFooterEnabled = next.readerFooterEnabled;
    this.typoInfoBarConfig = next.readerInfoBarConfig;
    this.typoStepperKey++;
    this.typoCommitted = this.typographySnapshot();
  }

  /** 把页眉页脚的三项状态合回去，得到完整的待保存排版。 */
  typographySnapshot(): ReaderSettings {
    const settings = ThemeColorSettingsPage.copyReaderSettings(this.readerProfile);
    settings.readerHeaderEnabled = this.typoHeaderEnabled;
    settings.readerFooterEnabled = this.typoFooterEnabled;
    settings.readerInfoBarConfig = this.typoInfoBarConfig;
    return settings;
  }

  /**
   * 排版改动之后调用：记一步撤销（连续微调并成一步，免得点几下加减就占满撤销记录），
   * 稍后一次写进这套方案的阅读档案。
   */
  onTypographyChanged(): void {
    const now = Date.now();
    const last = this.undoEntries.length > 0 ? this.undoEntries[this.undoEntries.length - 1] : null;
    if (!last || !last.typography || now - this.typoUndoAt > 1500) {
      const entry = new ThemeEditorUndoEntry();
      entry.typography = this.typoCommitted;
      entry.mode = this.selectedMode;
      this.undoEntries.push(entry);
      if (this.undoEntries.length > 20) this.undoEntries.shift();
      this.undoAvailable = true;
    }
    this.typoUndoAt = now;
    this.typoCommitted = this.typographySnapshot();
    this.readerProfileBound = true;
    this.typoDirty = true;
    this.scheduleTypographySave();
  }

  scheduleTypographySave(): void {
    if (this.typoSaveTimer >= 0) clearTimeout(this.typoSaveTimer);
    this.typoSaveTimer = setTimeout(() => {
      this.typoSaveTimer = -1;
      this.flushTypography();
    }, 400);
  }

  /** 把还没写入的排版立即保存；离开页面、进下级页面和点“完成”前都要等它。 */
  flushTypography(): Promise<void> {
    if (this.typoSaveTimer >= 0) {
      clearTimeout(this.typoSaveTimer);
      this.typoSaveTimer = -1;
    }
    if (!this.typoDirty || !this.schemeId) return this.typoSaveQueue;
    this.typoDirty = false;
    const snapshot = this.typographySnapshot();
    const profileId = ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, this.schemeId);
    this.typoSaveQueue = this.typoSaveQueue.then(async () => {
      try {
        await ReaderSettingsStore.saveTypographyToProfile(getContext(this), profileId, snapshot);
        this.typoSaveFailed = false;
      } catch (e) {
        this.typoSaveFailed = true;
        this.typoDirty = true;
        console.error('保存主题排版失败:', e);
        HdsFeedback.showToast('保存排版失败，请重试');
      }
    });
    return this.typoSaveQueue;
  }

  typographyValues(): number[] {
    const values: number[] = new Array<number>(ReaderTypographyField.COUNT).fill(0);
    values[ReaderTypographyField.FONT_SIZE] = this.readerProfile.fontSize;
    values[ReaderTypographyField.FONT_WEIGHT] = this.readerProfile.fontWeight;
    values[ReaderTypographyField.LETTER_SPACING] = this.readerProfile.letterSpacing;
    values[ReaderTypographyField.LINE_HEIGHT] = this.readerProfile.lineHeight;
    values[ReaderTypographyField.PARAGRAPH_SPACING] = this.readerProfile.paragraphSpacing;
    values[ReaderTypographyField.MARGIN_LEFT] = this.readerProfile.marginLeft;
    values[ReaderTypographyField.MARGIN_RIGHT] = this.readerProfile.marginRight;
    values[ReaderTypographyField.MARGIN_TOP] = this.readerProfile.marginTop;
    values[ReaderTypographyField.MARGIN_BOTTOM] = this.readerProfile.marginBottom;
    values[ReaderTypographyField.COMMENT_BUBBLE_SIZE] = this.readerProfile.commentBubbleSize;
    return values;
  }

  applyTypographyValues(values: number[]): void {
    if (values.length < ReaderTypographyField.COUNT) return;
    this.readerProfile.fontSize = values[ReaderTypographyField.FONT_SIZE];
    this.readerProfile.fontWeight = values[ReaderTypographyField.FONT_WEIGHT];
    this.readerProfile.letterSpacing = values[ReaderTypographyField.LETTER_SPACING];
    this.readerProfile.lineHeight = values[ReaderTypographyField.LINE_HEIGHT];
    this.readerProfile.paragraphSpacing = values[ReaderTypographyField.PARAGRAPH_SPACING];
    this.readerProfile.marginLeft = values[ReaderTypographyField.MARGIN_LEFT];
    this.readerProfile.marginRight = values[ReaderTypographyField.MARGIN_RIGHT];
    this.readerProfile.marginTop = values[ReaderTypographyField.MARGIN_TOP];
    this.readerProfile.marginBottom = values[ReaderTypographyField.MARGIN_BOTTOM];
    this.readerProfile.commentBubbleSize = values[ReaderTypographyField.COMMENT_BUBBLE_SIZE];
    this.onTypographyChanged();
  }

  typoAlignValues(): string[] {
    return ['justify', 'start', 'end'];
  }

  typoAlignIndex(): number {
    return Math.max(0, this.typoAlignValues().indexOf(this.readerProfile.textAlign));
  }

  readerFontLabel(mode: string): string {
    if (mode === 'system') return '系统字体';
    if (mode === 'custom') return '自定义字体';
    return '跟随全局字体';
  }

  /** 阅读字体页带草稿参数打开：它改的是这份排版，不是正在使用的阅读设置。 */
  openFontSettings(): void {
    if (!this.editorReady || this.closing) return;
    ThemeTypographyDraft.begin(this.typographySnapshot());
    this.fontDraftRevision = ThemeTypographyDraft.revision();
    const params: Record<string, Object> = {};
    params[ThemeTypographyDraft.DRAFT_PARAM] = true;
    router.pushUrl({ url: 'pages/ReaderFontSettings', params: params }).catch(() => {
      ThemeTypographyDraft.end();
      this.fontDraftRevision = -1;
      HdsFeedback.showToast('打开阅读字体失败，请重试');
    });
  }

  /** 从阅读字体页回来时，取回它在草稿里改过的字体与强调规则。 */
  pullFontDraft(): void {
    const fontDraft = ThemeTypographyDraft.current();
    if (!fontDraft || this.fontDraftRevision < 0) return;
    if (ThemeTypographyDraft.revision() !== this.fontDraftRevision) {
      const next = this.typographySnapshot();
      next.fontSize = fontDraft.fontSize;
      next.fontWeight = fontDraft.fontWeight;
      next.bodyFontMode = fontDraft.bodyFontMode;
      next.bodyFontFamily = fontDraft.bodyFontFamily;
      next.titleFontMode = fontDraft.titleFontMode;
      next.titleFontFamily = fontDraft.titleFontFamily;
      next.titleFontSize = fontDraft.titleFontSize;
      next.titleFontWeight = fontDraft.titleFontWeight;
      next.titleStyleRaw = fontDraft.titleStyleRaw || '';
      next.regexFontEnabled = fontDraft.regexFontEnabled;
      next.regexFontPattern = fontDraft.regexFontPattern;
      next.regexFontMode = fontDraft.regexFontMode;
      next.regexFontFamily = fontDraft.regexFontFamily;
      next.regexFontSize = fontDraft.regexFontSize;
      next.regexShadowColor = fontDraft.regexShadowColor;
      next.regexFontRulesRaw = fontDraft.regexFontRulesRaw;
      this.replaceTypography(next);
    }
    ThemeTypographyDraft.end();
    this.fontDraftRevision = -1;
  }

  /** 整份换掉排版（字体页带回、套用、恢复默认）：单独记一步撤销。 */
  replaceTypography(next: ReaderSettings): void {
    const before = this.typoCommitted;
    this.applyTypography(next);
    this.typoCommitted = before;
    this.typoUndoAt = 0;
    this.onTypographyChanged();
    this.typoUndoAt = 0;
  }

  async copyCurrentTypography(): Promise<void> {
    try {
      const current = await ReaderSettingsStore.load(getContext(this));
      const next = this.typographySnapshot();
      ReaderSettingsStore.copyTypography(current, next);
      this.replaceTypography(next);
      HdsFeedback.showToast('已套用当前阅读排版，可以撤销');
    } catch (e) {
      console.warn('读取当前阅读排版失败:', e);
      HdsFeedback.showToast('读取当前阅读排版失败');
    }
  }

  /** 恢复默认会一次清掉多项排版，容易误点，先确认。 */
  async confirmResetTypography(): Promise<void> {
    try {
      const result = await promptAction.showDialog({
        title: '恢复默认排版？',
        message: '字号、间距、边距与页眉页脚会恢复默认，字体和强调规则保留。',
        buttons: [{ text: '取消', color: this.subTextColor() },
          { text: '恢复默认', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
      });
      if (result.index !== 1) return;
    } catch (e) {
      console.warn('显示恢复默认排版确认失败:', e);
      return;
    }
    const defaults = new ReaderSettings();
    const next = this.typographySnapshot();
    next.fontSize = defaults.fontSize;
    next.fontWeight = defaults.fontWeight;
    next.letterSpacing = defaults.letterSpacing;
    next.textAlign = defaults.textAlign;
    next.lineHeight = defaults.lineHeight;
    next.paragraphSpacing = defaults.paragraphSpacing;
    next.paragraphIndent = defaults.paragraphIndent;
    next.marginLeft = defaults.marginLeft;
    next.marginRight = defaults.marginRight;
    next.marginTop = defaults.marginTop;
    next.marginBottom = defaults.marginBottom;
    next.commentBubbleSize = defaults.commentBubbleSize;
    next.extendToStatusBar = defaults.extendToStatusBar;
    next.titleFontSize = defaults.titleFontSize;
    next.titleFontWeight = defaults.titleFontWeight;
    next.titleStyleRaw = defaults.titleStyleRaw;
    next.readerHeaderEnabled = defaults.readerHeaderEnabled;
    next.readerFooterEnabled = defaults.readerFooterEnabled;
    next.readerInfoBarConfig = new ReaderInfoBarConfig().serialize();
    this.replaceTypography(next);
    HdsFeedback.showToast('已恢复默认排版，可以撤销');
  }

  typographyNote(): string {
    if (this.typoActiveScheme) return '这套主题正在使用，排版改动立即生效。';
    if (!this.typoFollowsTheme) return '当前关闭了“排版跟随主题”，打开后切换到这套主题时这里的排版才会生效。';
    return '排版与这套主题绑定，切换到它时一起生效；在阅读页里继续调整，也会记在这套主题上。';
  }

  /** 整页预览：按真实分页看一页正文，那一页有自己的保存。 */
  async openTypography(): Promise<void> {
    if (!this.editorReady || this.closing) return;
    await this.onSettingChanged();
    if (this.saveFailed) {
      HdsFeedback.showToast('保存主题方案失败，请重试');
      return;
    }
    await this.flushTypography();
    if (this.typoSaveFailed) return;
    this.returningFromTypography = true;
    await this.getUIContext().getRouter().pushUrl({
      url: 'pages/ThemeTypographySettings',
      params: { schemeId: this.schemeId, previewDark: this.selectedMode === 'dark' }
    }).catch(() => {
      this.returningFromTypography = false;
      HdsFeedback.showToast('打开主题排版失败，请重试');
    });
  }

  sourceThemeId(category: string): string {
    if (category === 'layout') return this.lightSources.layoutThemeId;
    const sources = this.currentSources();
    if (category === 'startup') return sources.startupThemeId;
    if (category === 'palette') return sources.paletteThemeId;
    if (category === 'reader') return sources.readerThemeId;
    if (category === 'ttsPanel') return sources.ttsPanelThemeId;
    if (category === 'bubble') return sources.bubbleThemeId;
    if (category === 'navigation') return sources.navigationThemeId;
    if (category === 'book') return sources.bookThemeId;
    if (category === 'homeBackdrop') return sources.homeBackdropThemeId;
    if (category === 'typography') return sources.typographyThemeId;
    if (category === 'layout') return sources.layoutThemeId;
    if (category === 'radius') return sources.radiusThemeId;
    return sources.glassThemeId;
  }

  themeOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const theme of this.availableThemes) {
      options.push({ value: theme.name });
    }
    return options;
  }

  sourceSelectedIndex(category: string): number {
    const themeId = this.sourceThemeId(category);
    for (let index = 0; index < this.availableThemes.length; index++) {
      if (this.availableThemes[index].id === themeId) return index;
    }
    return 0;
  }

  settingsFromState(): AppThemeSettings {
    const settings = AppThemeSettingsStore.cloneSettings(this.draftSettings);
    settings.themeId = ThemeIds.CUSTOM;
    settings.customBaseThemeId = this.customBaseThemeId;
    settings.customLightSources = AppThemeSettingsStore.cloneSources(
      this.lightSources, this.customBaseThemeId);
    settings.customDarkSources = AppThemeSettingsStore.cloneSources(
      this.darkSources, this.customBaseThemeId);
    settings.customDarkSources.layoutThemeId = settings.customLightSources.layoutThemeId;
    settings.customLightAccentColor = this.lightAccentColor;
    settings.customDarkAccentColor = this.darkAccentColor;
    settings.customLightButtonColor = this.lightButtonColor;
    settings.customDarkButtonColor = this.darkButtonColor;
    settings.lightAccentColor = this.lightAccentColor;
    settings.darkAccentColor = this.darkAccentColor;
    settings.lightButtonColor = this.lightButtonColor;
    settings.darkButtonColor = this.darkButtonColor;
    settings.customLightPalette = AppThemeSettingsStore.normalizePalette(this.lightPalette);
    settings.customDarkPalette = AppThemeSettingsStore.normalizePalette(this.darkPalette);
    settings.customLightEmphasis = AppThemeSettingsStore.normalizeEmphasis(this.lightEmphasis);
    settings.customDarkEmphasis = AppThemeSettingsStore.normalizeEmphasis(this.darkEmphasis);
    settings.customAppFontFamily = this.appFontFamily;
    settings.customRadius = AppThemeSettingsStore.normalizeRadius(this.radiusOverride);
    settings.customLightStartupText = AppThemeSettingsStore.normalizeStartupText(this.lightStartupText);
    settings.customDarkStartupText = AppThemeSettingsStore.normalizeStartupText(this.darkStartupText);
    settings.customPreviewImagePath = this.previewImagePath;
    settings.customLightStartupImagePath = this.lightStartupImagePath;
    settings.customDarkStartupImagePath = this.darkStartupImagePath;
    settings.customLightStartupTitle = this.lightStartupTitle;
    settings.customDarkStartupTitle = this.darkStartupTitle;
    settings.customLightStartupSubtitle = this.lightStartupSubtitle;
    settings.customDarkStartupSubtitle = this.darkStartupSubtitle;
    settings.customLightReaderBackgroundColor = this.lightReader.backgroundColor;
    settings.customLightReaderTextColor = this.lightReader.textColor;
    settings.customLightReaderSubTextColor = this.lightReader.subTextColor;
    settings.customLightReaderContentTone = this.lightReader.contentTone;
    settings.customDarkReaderBackgroundColor = this.darkReader.backgroundColor;
    settings.customDarkReaderTextColor = this.darkReader.textColor;
    settings.customDarkReaderSubTextColor = this.darkReader.subTextColor;
    settings.customDarkReaderContentTone = this.darkReader.contentTone;
    return AppThemeSettingsStore.cloneSettings(settings);
  }

  currentStartupImagePath(): string {
    return this.selectedMode === 'dark' ? this.darkStartupImagePath : this.lightStartupImagePath;
  }

  currentStartupTitle(): string {
    return this.selectedMode === 'dark' ? this.darkStartupTitle : this.lightStartupTitle;
  }

  currentStartupSubtitle(): string {
    return this.selectedMode === 'dark' ? this.darkStartupSubtitle : this.lightStartupSubtitle;
  }

  setCurrentStartupTitle(value: string): void {
    if (value === this.currentStartupTitle()) return;
    this.rememberChange();
    if (this.selectedMode === 'dark') this.darkStartupTitle = value;
    else this.lightStartupTitle = value;
    this.onSettingChanged();
  }

  setCurrentStartupSubtitle(value: string): void {
    if (value === this.currentStartupSubtitle()) return;
    this.rememberChange();
    if (this.selectedMode === 'dark') this.darkStartupSubtitle = value;
    else this.lightStartupSubtitle = value;
    this.onSettingChanged();
  }

  async chooseStartupImage(): Promise<void> {
    try {
      const darkMode = this.selectedMode === 'dark';
      const oldPath = this.currentStartupImagePath();
      const picked = await StartupCoverImageStore.pickSource(getContext(this));
      if (!picked) return;
      const cropped = await this.cropImage(picked, '启动封面取景', 841, 1870, 841, false);
      if (!cropped) return;
      const imagePath = await StartupCoverImageStore.saveFrom(getContext(this), this.schemeId, darkMode, cropped);
      this.discardCropFile(cropped, picked);
      this.rememberChange();
      if (darkMode) this.darkStartupImagePath = imagePath;
      else this.lightStartupImagePath = imagePath;
      await this.onSettingChanged();
      if (oldPath !== imagePath) this.trackObsoleteStartupPath(oldPath);
      HdsFeedback.showToast(`${darkMode ? '深色' : '浅色'}启动封面已更新`);
    } catch (e) {
      console.error('上传自定义启动封面失败:', e);
      HdsFeedback.showToast('上传启动封面失败，请重试');
    }
  }

  async resetStartupImage(): Promise<void> {
    const darkMode = this.selectedMode === 'dark';
    const oldPath = this.currentStartupImagePath();
    if (!oldPath) return;
    this.rememberChange();
    if (darkMode) this.darkStartupImagePath = '';
    else this.lightStartupImagePath = '';
    await this.onSettingChanged();
    this.trackObsoleteStartupPath(oldPath);
    HdsFeedback.showToast('已恢复所选主题的启动封面');
  }

  customPreviewTheme(): ThemePack {
    // 来源指向方案自己的素材包时，图片取自包注册表（不是状态变量）；读 assetRevision 让素材增删后跟着刷新。
    const revision = this.assetRevision;
    if (revision < 0) return BuiltinThemeRegistry.findById(this.customBaseThemeId);
    return AppThemeSettingsStore.customTheme(
      this.settingsFromState(),
      this.selectedMode === 'dark'
    );
  }

  refreshAvailableThemes(): void {
    const themes = BuiltinThemeRegistry.all();
    const available: ThemePack[] = [];
    const trialThemeId = AppStorage.get<string>('themeTrialThemeId') || '';
    for (const theme of themes) {
      if (SuperExclusiveThemes.has(theme.id) && !AccountSessionStore.hasOwnedEntitlement(theme.id)) continue;
      if (BuiltinThemeRegistry.isFree(theme.id) ||
        (theme.id === this.appThemeId && theme.id !== trialThemeId) ||
        AccountSessionStore.hasValidEntitlement(theme.id)) {
        available.push(theme);
      }
    }
    // 已安装的主题包也能当部件来源，与内置主题混搭。
    for (const pack of ThemePackRegistry.all()) {
      available.push(BuiltinThemeRegistry.findById(pack.themeId));
    }
    this.availableThemes = available;
  }

  isSourceInUse(themeId: string): boolean {
    return this.sourceUsesTheme(this.lightSources, themeId) || this.sourceUsesTheme(this.darkSources, themeId);
  }

  sourceUsesTheme(sources: ThemeComponentSourceIds, themeId: string): boolean {
    return sources.startupThemeId === themeId || sources.paletteThemeId === themeId ||
      sources.readerThemeId === themeId || sources.ttsPanelThemeId === themeId ||
      sources.bubbleThemeId === themeId || sources.navigationThemeId === themeId ||
      sources.bookThemeId === themeId || sources.homeBackdropThemeId === themeId ||
      sources.typographyThemeId === themeId ||
      sources.layoutThemeId === themeId || sources.radiusThemeId === themeId ||
      sources.glassThemeId === themeId;
  }

  setCurrentAccentColor(color: string): void {
    const normalized = AppThemeSettingsStore.normalizeColor(color, this.currentAccentColor());
    if (normalized === this.currentAccentColor()) return;
    this.rememberChange();
    if (this.selectedMode === 'dark') {
      this.darkAccentColor = normalized;
    } else {
      this.lightAccentColor = normalized;
    }
    this.onSettingChanged();
  }

  setCurrentButtonColor(color: string): void {
    const normalized = AppThemeSettingsStore.normalizeColor(color, this.currentButtonColor());
    if (normalized === this.currentButtonColor()) return;
    this.rememberChange();
    if (this.selectedMode === 'dark') {
      this.darkButtonColor = normalized;
    } else {
      this.lightButtonColor = normalized;
    }
    this.onSettingChanged();
  }

  currentAccentColor(): string {
    return this.selectedMode === 'dark' ? this.darkAccentColor : this.lightAccentColor;
  }

  currentButtonColor(): string {
    return this.selectedMode === 'dark' ? this.darkButtonColor : this.lightButtonColor;
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

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleActions() {
    Row({ space: AppSpacing.SM }) {
      this.modeToggle()
      if (this.undoAvailable && !this.fullPreview) {
        ImmersiveHeaderAction({ icon: $r('sys.symbol.arrow_counterclockwise'),
          accessibilityLabel: '撤销上一次主题修改', onTap: () => this.undoChange() })
      }
      ImmersiveHeaderAction({
        label: this.saving ? '保存中' : (this.fullPreview ? '收起' : '完成'),
        actionEnabled: this.editorReady && !this.saving,
        accessibilityLabel: this.fullPreview ? '收起主题预览' : '保存方案并返回主题页',
        onTap: () => {
          if (this.fullPreview) this.fullPreview = false;
          else this.closeEditor();
        }
      })
    }
    .margin({ right: AppSpacing.XL })
  }

  /** 顶栏里的浅色/深色开关：切的是正在编辑和预览的那一套，不改应用当前的显示模式。 */
  @Builder
  modeToggle() {
    ThemeModeSwitch({
      selectedDark: this.selectedMode === 'dark',
      darkMode: this.appDarkMode,
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      subTextColor: this.subTextColor(),
      fallbackColor: this.cardColor(),
      switchWidth: HEADER_MODE_SWITCH_WIDTH,
      switchHeight: ImmersiveHeaderAction.SIZE,
      accessibilityPrefix: '编辑',
      onChange: (dark: boolean) => {
        this.selectedMode = dark ? 'dark' : 'light';
      }
    })
  }

  @Builder
  sectionTabs() {
    // 五个页签放在一条底板里平分宽度；朗读、启动、方案信息内容少，合在“其他”里。
    Row() {
      Row() {
        this.sectionTab('整体', 'global')
        this.sectionTab('书架', 'shelf')
        this.sectionTab('阅读', 'reader')
        this.sectionTab('排版', 'typography')
        this.sectionTab('其他', 'other')
      }
      .width('100%')
      .padding(3)
      .borderRadius(ThemeRuntime.mediumRadius() + 3)
      .backgroundColor(this.cardColor())
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.XS })
  }

  @Builder
  sectionTab(label: string, section: string) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(36)
      .padding(0)
      .fontSize(AppFontSize.BODY)
      .fontWeight(this.editorSection === section ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.editorSection === section ? ThemeRuntime.accentColor(this.appDarkMode) : this.subTextColor())
      .backgroundColor(this.editorSection === section ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
      .borderRadius(ThemeRuntime.mediumRadius())
      .accessibilitySelected(this.editorSection === section)
      .onClick(() => {
        if (this.editorSection !== section) this.openSection(section);
      })
  }

  /**
   * 分组标题行：点按展开或收起，同一时间只展开一组。scope 为 split 标“分浅深”、shared 标“共用”、空串不标。
   * 参数都是固定值，摘要和色块在里面读状态（按值传进来的不会刷新）。
   */
  @Builder
  groupHeader(key: string, title: string, scope: string) {
    Row({ space: AppSpacing.SM }) {
      Text(title)
        .fontSize(AppFontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
      if (scope) {
        Text(scope === 'split' ? '分浅深' : '共用')
          .fontSize(AppFontSize.MICRO)
          .fontColor(this.subTextColor())
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(5)
          .border({ width: 1, color: ThemeRuntime.dividerColor(this.appDarkMode) })
      }
      Text(this.groupSummary(key))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)
      ForEach(this.groupDots(key), (color: string) => {
        Row()
          .width(14)
          .height(14)
          .borderRadius(7)
          .backgroundColor(color)
          .border({ width: 1, color: this.appDarkMode ? '#55FFFFFF' : '#22000000' })
      }, (color: string, index: number) => `${key}_${index}_${color}`)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([this.subTextColor()])
        .rotate({ angle: this.openGroup === key ? 90 : 0 })
    }
    .width('100%')
    .height(52)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .accessibilityGroup(true)
    .accessibilityText(`${title}，${this.openGroup === key ? '已展开，点按收起' : '已收起，点按展开'}`)
    .onClick(() => this.toggleGroup(key))
  }

  /** 分组里不常改的项收在“更多”下面。 */
  @Builder
  moreRow(key: string, label: string) {
    Row({ space: AppSpacing.XS }) {
      Text(this.moreOpen(key) ? '收起' : label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
      SymbolGlyph(this.moreOpen(key) ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
    }
    .width('100%')
    .height(40)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .accessibilityGroup(true)
    .accessibilityText(this.moreOpen(key) ? '收起更多选项' : label)
    .onClick(() => this.toggleMore(key))
  }

  // ---- 页签：整体 ----

  @Builder
  globalSection() {
    Column() {
      this.groupHeader('base', '基础主题', 'shared')
      if (this.openGroup === 'base') {
        this.baseThemeRow()
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('palette', '配色', 'split')
      if (this.openGroup === 'palette') {
        this.componentSourceRow('palette')
        this.colorOptions()
        this.moreRow('palette', '逐项覆盖页面、卡片、文字等 7 种颜色')
        if (this.moreOpen('palette')) {
          Stack() {
            Column() {
              this.paletteOverrideRow('页面底色', 'pageColor')
              this.paletteOverrideRow('卡片色', 'cardColor')
              this.paletteOverrideRow('输入框色', 'inputColor')
              this.paletteOverrideRow('正文字色', 'primaryTextColor')
              this.paletteOverrideRow('辅助文字色', 'subTextColor')
              this.paletteOverrideRow('分割线色', 'dividerColor')
              this.paletteOverrideRow('危险色', 'dangerColor')
            }
            .width('100%')
            .opacity(this.advancedOpacity())
            this.advancedLockLayer()
          }
          .width('100%')
          if (AppThemeSettingsStore.hasPaletteOverride(this.currentPalette())) {
            this.resetRow('恢复为所选主题的配色', () => this.resetPalette())
          }
        }
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('radius', '圆角', 'shared')
      if (this.openGroup === 'radius') {
        this.componentSourceRow('radius')
        this.radiusRows()
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('font', '应用字体', 'shared')
      if (this.openGroup === 'font') {
        this.componentSourceRow('typography')
        this.appFontRow()
      }
    }
    .editorCard(this.cardColor())
  }

  @Builder
  baseThemeRow() {
    SettingRow({ title: '整套取自', description: '配色、图标、封面等全部换成这套，之后再逐组微调',
      showDivider: false }) {
      Select(this.themeOptions())
        .id('theme_editor_base_theme')
        .width('44%')
        .selected(this.baseThemeIndex())
        .value(this.baseThemeLabel())
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => {
          if (index >= 0 && index < this.availableThemes.length) {
            this.applyBaseTheme(this.availableThemes[index].id);
          }
        })
    }
  }

  // ---- 页签：书架 ----

  @Builder
  shelfSection() {
    Column() {
      this.groupHeader('navigation', '导航图标', 'split')
      if (this.openGroup === 'navigation') {
        this.componentSourceRow('navigation')
        if (this.assetRevision >= 0) {
          this.navigationSlots()
        }
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('book', '封面与书架素材', 'split')
      if (this.openGroup === 'book') {
        this.componentSourceRow('book')
        if (this.assetRevision >= 0) {
          this.bookSlots()
        }
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('homeBackdrop', '首页背景', 'split')
      if (this.openGroup === 'homeBackdrop') {
        this.componentSourceRow('homeBackdrop')
        if (this.assetRevision >= 0) {
          this.homeBackdropSlot()
        }
      }
    }
    .editorCard(this.cardColor())
  }

  // ---- 页签：阅读 ----

  @Builder
  readerSection() {
    Column() {
      this.groupHeader('reader', '阅读背景', 'split')
      if (this.openGroup === 'reader') {
        this.componentSourceRow('reader')
        this.readerColorRows()
        if (this.assetRevision >= 0) {
          this.readerSlots()
        }
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('bubble', '强调气泡', 'split')
      if (this.openGroup === 'bubble') {
        this.componentSourceRow('bubble')
        this.emphasisOverrideRows()
        if (this.assetRevision >= 0) {
          this.bubbleSlots()
        }
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('title', '标题强调', 'split')
      if (this.openGroup === 'title') {
        this.componentSourceRow('bubble', '跟强调气泡一起取自')
        this.titleGroupRows()
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('chapterHead', '章首装饰', 'split')
      if (this.openGroup === 'chapterHead') {
        this.componentSourceRow('bubble', '跟强调气泡一起取自')
        this.chapterHeadGroupRows()
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('comment', '段评气泡', 'split')
      if (this.openGroup === 'comment') {
        this.commentGroupRows()
      }
    }
    .editorCard(this.cardColor())
  }

  // ---- 页签：排版 ----

  @Builder
  typographySection() {
    Column() {
      this.groupHeader('typoBody', '正文排版', 'shared')
      if (this.openGroup === 'typoBody') {
        ForEach([this.typoStepperKey], (key: number) => {
          Row() {
            ReaderTypographyStepper({
              initialValues: this.typographyValues(),
              dark: this.appDarkMode,
              textColor: this.primaryTextColor(),
              subTextColor: this.subTextColor(),
              accentColor: ThemeRuntime.accentColor(this.appDarkMode),
              inputColor: this.inputColor(),
              menuColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode),
              onChange: (values: number[]): void => this.applyTypographyValues(values)
            })
          }
          .width('calc(100% - 32vp)')
          .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
          .border({ width: { bottom: 0.5 }, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
        }, (key: number) => `theme_editor_typography_stepper_${key}`)
        this.typoIndentRow()
        this.typoAlignRow()
        SettingSwitchRow({
          title: '正文扩展至状态栏',
          description: '隐藏状态栏，正文延伸到屏幕顶部',
          isOn: this.readerProfile.extendToStatusBar,
          showDivider: false,
          onChange: (value: boolean) => {
            if (this.readerProfile.extendToStatusBar === value) return;
            this.readerProfile.extendToStatusBar = value;
            this.onTypographyChanged();
          }
        })
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('typoBars', '页眉页脚', '')
      if (this.openGroup === 'typoBars') {
        ReaderHeaderFooterEditor({
          headerBaseInset: ReaderInfoBarConfig.headerBaseInset(this.readerProfile.extendToStatusBar,
            this.statusBarHeight),
          footerBaseInset: ReaderInfoBarConfig.footerBaseInset(this.navBarHeight),
          dark: this.appDarkMode,
          modeDark: this.selectedMode === 'dark',
          textColor: this.primaryTextColor(),
          subTextColor: this.subTextColor(),
          accentColor: ThemeRuntime.accentColor(this.appDarkMode),
          switchColor: ThemeRuntime.buttonColor(this.appDarkMode),
          menuColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode),
          cardStyle: true,
          dividerColor: ThemeRuntime.hairlineColor(this.appDarkMode),
          readerHeaderEnabled: $typoHeaderEnabled,
          readerFooterEnabled: $typoFooterEnabled,
          readerInfoBarConfig: $typoInfoBarConfig,
          onChanged: (_headerEnabled: boolean, _footerEnabled: boolean, _infoBarConfig: string): void => {
            this.onTypographyChanged();
          }
        })
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('typoFont', '阅读字体', 'shared')
      if (this.openGroup === 'typoFont') {
        SettingNavRow({
          title: '正文与标题字体',
          description: `正文 ${this.readerProfile.fontSize} · 标题 ${this.readerProfile.titleFontSize} · 正则强调与气泡`,
          showDivider: false,
          onTap: () => this.openFontSettings()
        })
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('typoMore', '更多', '')
      if (this.openGroup === 'typoMore') {
        this.componentSourceRow('layout', '推荐排版取自')
        if (!this.typoActiveScheme) {
          SettingNavRow({ title: '套用当前阅读排版', description: '把正在使用的排版和字体复制到这套主题',
            onTap: () => this.copyCurrentTypography() })
        }
        SettingNavRow({ title: '恢复默认排版', description: '字号、间距、边距与页眉页脚恢复默认，字体和强调规则保留',
          onTap: () => this.confirmResetTypography() })
        SettingNavRow({ title: '整页预览', description: '按真实分页看一页正文，也可以在那里调整并保存',
          showDivider: false, onTap: () => this.openTypography() })
      }
    }
    .editorCard(this.cardColor())
    Text(this.typographyNote())
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .lineHeight(18)
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }

  /** 下拉的选中项在 builder 里读状态：按值传进来的不会刷新。 */
  @Builder
  typoIndentRow() {
    SettingRow({ title: '段首缩进', description: '正文每段首行的缩进字符数' }) {
      Select([{ value: '0字符' }, { value: '1字符' }, { value: '2字符' }, { value: '3字符' }, { value: '4字符' }])
        .id('theme_editor_typography_indent')
        .selected(ReaderParagraphIndent.normalize(this.readerProfile.paragraphIndent))
        .value(`${ReaderParagraphIndent.normalize(this.readerProfile.paragraphIndent)}字符`)
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => {
          const indent = ReaderParagraphIndent.normalize(index);
          if (indent === this.readerProfile.paragraphIndent) return;
          this.readerProfile.paragraphIndent = indent;
          this.onTypographyChanged();
        })
    }
  }

  @Builder
  typoAlignRow() {
    SettingRow({ title: '正文对齐方式', description: '正文段落的水平对齐' }) {
      Select([{ value: '两端对齐' }, { value: '左对齐' }, { value: '右对齐' }])
        .id('theme_editor_typography_align')
        .selected(this.typoAlignIndex())
        .value(['两端对齐', '左对齐', '右对齐'][this.typoAlignIndex()])
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => {
          const align = this.typoAlignValues()[Math.max(0, Math.min(index, 2))];
          if (align === this.readerProfile.textAlign) return;
          this.readerProfile.textAlign = align;
          this.onTypographyChanged();
        })
    }
  }

  // ---- 页签：其他（朗读面板、启动页、方案信息）----

  @Builder
  otherSection() {
    this.sectionTitle({ title: '朗读' })
    this.ttsSection()
    this.sectionTitle({ title: '启动页' })
    this.startupSection()
    this.sectionTitle({ title: '方案' })
    this.infoSection()
  }

  @Builder
  commentGroupRows() {
    Stack() {
      Column() {
        this.commentBubbleControls()
      }
      .width('100%')
      .opacity(this.advancedOpacity())
      this.advancedLockLayer()
    }
    .width('100%')
  }

  // ---- “其他”页签：朗读 ----

  @Builder
  ttsSection() {
    Column() {
      this.groupHeader('ttsPanel', '朗读 / 有声书面板', 'split')
      if (this.openGroup === 'ttsPanel') {
        this.componentSourceRow('ttsPanel')
        if (this.assetRevision >= 0) {
          this.ttsSlots()
        }
      }
    }
    .editorCard(this.cardColor())
  }

  // ---- “其他”页签：启动 ----

  @Builder
  startupSection() {
    Column() {
      this.groupHeader('startup', '启动图', 'split')
      if (this.openGroup === 'startup') {
        this.componentSourceRow('startup')
        Row({ space: AppSpacing.XL }) {
          this.assetSlot({ label: '竖图', image: this.startupSlotImage(),
            state: this.currentStartupImagePath() ? 'own' : 'inherit', slotWidth: 48, slotHeight: 106,
            onTap: () => this.tapStartupSlot() })
          Text('上传后按 841 × 1870 取景；底部约五分之一叠文案，别放主体。只做一种模式时另一种沿用它')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('startupText', '文案', 'split')
      if (this.openGroup === 'startupText') {
        this.startupTextInputs()
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('startupStyle', '文案样式', 'split')
      if (this.openGroup === 'startupStyle') {
        this.startupTextStyleOptions()
      }
    }
    .editorCard(this.cardColor())
  }

  // ---- “其他”页签：方案信息 ----

  @Builder
  infoSection() {
    Column() {
      this.groupHeader('info', '方案信息', '')
      if (this.openGroup === 'info') {
        this.infoInputs()
      }
    }
    .editorCard(this.cardColor())
    Column() {
      this.groupHeader('card', '主题卡片', '')
      if (this.openGroup === 'card') {
        if (this.assetRevision >= 0) {
          this.brandSlots()
        }
      }
    }
    .editorCard(this.cardColor())
  }

  /** 当前模式下方案实际生效的界面配色（来源主题 + 覆盖）。 */
  effectiveColors(): ThemeColorTokens {
    const theme = this.customPreviewTheme();
    return this.selectedMode === 'dark' ? theme.dark.colors : theme.light.colors;
  }

  effectiveEmphasis(): ThemeRegexEmphasisTokens {
    const theme = this.customPreviewTheme();
    return this.selectedMode === 'dark' ? theme.dark.regexEmphasis : theme.light.regexEmphasis;
  }

  colorTokenValue(colors: ThemeColorTokens, key: string): string {
    if (key === 'pageColor') return colors.pageColor;
    if (key === 'cardColor') return colors.cardColor;
    if (key === 'inputColor') return colors.inputColor;
    if (key === 'primaryTextColor') return colors.primaryTextColor;
    if (key === 'subTextColor') return colors.subTextColor;
    if (key === 'dividerColor') return colors.dividerColor;
    return colors.dangerColor;
  }

  overrideValue(override: ThemeColorOverrides, key: string): string {
    if (key === 'pageColor') return override.pageColor;
    if (key === 'cardColor') return override.cardColor;
    if (key === 'inputColor') return override.inputColor;
    if (key === 'primaryTextColor') return override.primaryTextColor;
    if (key === 'subTextColor') return override.subTextColor;
    if (key === 'dividerColor') return override.dividerColor;
    return override.dangerColor;
  }

  setOverrideValue(override: ThemeColorOverrides, key: string, value: string): void {
    if (key === 'pageColor') override.pageColor = value;
    else if (key === 'cardColor') override.cardColor = value;
    else if (key === 'inputColor') override.inputColor = value;
    else if (key === 'primaryTextColor') override.primaryTextColor = value;
    else if (key === 'subTextColor') override.subTextColor = value;
    else if (key === 'dividerColor') override.dividerColor = value;
    else override.dangerColor = value;
  }

  currentPalette(): ThemeColorOverrides {
    return this.selectedMode === 'dark' ? this.darkPalette : this.lightPalette;
  }

  currentEmphasis(): ThemeEmphasisOverrides {
    return this.selectedMode === 'dark' ? this.darkEmphasis : this.lightEmphasis;
  }

  loadOverrides(settings: AppThemeSettings): void {
    this.lightPalette = AppThemeSettingsStore.normalizePalette(settings.customLightPalette);
    this.darkPalette = AppThemeSettingsStore.normalizePalette(settings.customDarkPalette);
    this.lightEmphasis = AppThemeSettingsStore.normalizeEmphasis(settings.customLightEmphasis);
    this.darkEmphasis = AppThemeSettingsStore.normalizeEmphasis(settings.customDarkEmphasis);
    this.appFontFamily = settings.customAppFontFamily || '';
    this.radiusOverride = AppThemeSettingsStore.normalizeRadius(settings.customRadius);
    this.lightStartupText = AppThemeSettingsStore.normalizeStartupText(settings.customLightStartupText);
    this.darkStartupText = AppThemeSettingsStore.normalizeStartupText(settings.customDarkStartupText);
    this.previewImagePath = settings.customPreviewImagePath || '';
    this.loadReaderColors(settings);
  }

  loadReaderColors(settings: AppThemeSettings): void {
    const light = new ThemeEditorReaderColors();
    light.backgroundColor = settings.customLightReaderBackgroundColor;
    light.textColor = settings.customLightReaderTextColor;
    light.subTextColor = settings.customLightReaderSubTextColor;
    light.contentTone = settings.customLightReaderContentTone === 'dark' ? 'dark' : 'light';
    const dark = new ThemeEditorReaderColors();
    dark.backgroundColor = settings.customDarkReaderBackgroundColor;
    dark.textColor = settings.customDarkReaderTextColor;
    dark.subTextColor = settings.customDarkReaderSubTextColor;
    dark.contentTone = settings.customDarkReaderContentTone === 'light' ? 'light' : 'dark';
    this.lightReader = light;
    this.darkReader = dark;
  }

  paletteDescription(key: string): string {
    if (this.overrideValue(this.currentPalette(), key)) return '自定义';
    return `跟随「${BuiltinThemeRegistry.findById(this.currentSources().paletteThemeId).name}」`;
  }

  setPaletteColor(key: string, color: string): void {
    if (this.advancedLocked()) return;
    const current = this.colorTokenValue(this.effectiveColors(), key);
    const normalized = AppThemeSettingsStore.normalizeColor(color, current);
    if (normalized === current && this.overrideValue(this.currentPalette(), key)) return;
    if (normalized === current && !this.overrideValue(this.currentPalette(), key)) return;
    this.rememberChange();
    // @State 只观察第一层，整个对象换新实例才会刷新。
    const next = AppThemeSettingsStore.normalizePalette(this.currentPalette());
    this.setOverrideValue(next, key, normalized);
    if (this.selectedMode === 'dark') this.darkPalette = next;
    else this.lightPalette = next;
    this.onSettingChanged();
  }

  resetPalette(): void {
    this.rememberChange();
    if (this.selectedMode === 'dark') this.darkPalette = new ThemeColorOverrides();
    else this.lightPalette = new ThemeColorOverrides();
    this.onSettingChanged();
  }

  emphasisModeOptions(): SelectOption[] {
    return [{ value: '跟随主题' }, { value: '不强调' }, { value: '文字变色' }, { value: '高亮' }, { value: '气泡' }];
  }

  emphasisModeIds(): string[] {
    return ['', 'none', 'text', 'highlight', 'bubble'];
  }

  emphasisModeLabel(): string {
    const labels: string[] = ['跟随主题', '不强调', '文字变色', '高亮', '气泡'];
    return labels[this.emphasisModeIndex()];
  }

  emphasisModeIndex(): number {
    const index = this.emphasisModeIds().indexOf(this.currentEmphasis().mode);
    return index < 0 ? 0 : index;
  }

  /** 跟随主题 + 用户能用的内置气泡 + 已安装主题包自带的气泡。 */
  bubbleStyleIds(): string[] {
    const ids: string[] = [''];
    for (const id of ThemeBubbleStyleLabels.BUILTIN_IDS) {
      if (ThemeAccessPolicy.canUseBubbleStyle(id)) ids.push(id);
    }
    for (const pack of ThemePackRegistry.all()) {
      if (pack.hasBubble()) ids.push(pack.themeId);
    }
    const current = this.currentEmphasis().bubbleStyle;
    if (current && !ids.includes(current)) ids.push(current);
    return ids;
  }

  bubbleStyleLabel(id: string): string {
    if (!id) return '跟随主题';
    const pack = ThemePackRegistry.get(id);
    if (pack) return `${pack.name}（主题包）`;
    return ThemeBubbleStyleLabels.label(id);
  }

  bubbleStyleOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const id of this.bubbleStyleIds()) {
      options.push({ value: this.bubbleStyleLabel(id) });
    }
    return options;
  }

  bubbleStyleIndex(): number {
    const index = this.bubbleStyleIds().indexOf(this.currentEmphasis().bubbleStyle);
    return index < 0 ? 0 : index;
  }

  updateEmphasis(apply: (next: ThemeEmphasisOverrides) => void): void {
    if (this.advancedLocked()) return;
    this.rememberChange();
    const next = AppThemeSettingsStore.normalizeEmphasis(this.currentEmphasis());
    apply(next);
    if (this.selectedMode === 'dark') this.darkEmphasis = next;
    else this.lightEmphasis = next;
    this.onSettingChanged();
  }

  setEmphasisMode(index: number): void {
    const ids = this.emphasisModeIds();
    if (index < 0 || index >= ids.length || ids[index] === this.currentEmphasis().mode) return;
    this.updateEmphasis((next: ThemeEmphasisOverrides): void => {
      next.mode = ids[index];
    });
  }

  setEmphasisStyle(index: number): void {
    const ids = this.bubbleStyleIds();
    if (index < 0 || index >= ids.length || ids[index] === this.currentEmphasis().bubbleStyle) return;
    this.updateEmphasis((next: ThemeEmphasisOverrides): void => {
      next.bubbleStyle = ids[index];
    });
  }

  setEmphasisColor(textColor: boolean, color: string): void {
    const tokens = this.effectiveEmphasis();
    const current = textColor ? tokens.emphasisTextColor : tokens.emphasisColor;
    const normalized = HexColor.normalizeAlpha(color, current);
    const override = this.currentEmphasis();
    if (normalized === current && (textColor ? override.textColor : override.color)) return;
    if (normalized === current && !(textColor ? override.textColor : override.color)) return;
    this.updateEmphasis((next: ThemeEmphasisOverrides): void => {
      if (textColor) next.textColor = normalized;
      else next.color = normalized;
    });
  }

  resetEmphasis(): void {
    this.rememberChange();
    if (this.selectedMode === 'dark') this.darkEmphasis = new ThemeEmphasisOverrides();
    else this.lightEmphasis = new ThemeEmphasisOverrides();
    this.onSettingChanged();
  }

  emphasisSourceName(): string {
    return BuiltinThemeRegistry.findById(this.currentSources().bubbleThemeId).name;
  }

  @Builder
  paletteOverrideRow(title: string, key: string) {
    ThemeColorOption({
      title: title,
      description: this.paletteDescription(key),
      color: this.colorTokenValue(this.effectiveColors(), key),
      showDivider: key !== 'dangerColor' || AppThemeSettingsStore.hasPaletteOverride(this.currentPalette()),
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        this.setPaletteColor(key, color);
      }
    })
  }

  @Builder
  resetRow(label: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
    .onClick(() => onTap())
  }

  @Builder
  emphasisOverrideRows() {
    Stack() {
      Column() {
        this.emphasisOverrideControls()
      }
      .width('100%')
      .opacity(this.advancedOpacity())
      this.advancedLockLayer()
    }
    .width('100%')
    if (AppThemeSettingsStore.hasEmphasisOverride(this.currentEmphasis())) {
      this.resetRow('恢复为所选主题的强调气泡', () => this.resetEmphasis())
    }
  }

  @Builder
  emphasisOverrideControls() {
    SettingRow({ title: '强调方式', description: this.currentEmphasis().mode ? '自定义' : `跟随「${this.emphasisSourceName()}」` }) {
      Select(this.emphasisModeOptions())
        .id('theme_editor_emphasis_mode')
        .width('44%')
        .selected(this.emphasisModeIndex())
        .value(this.emphasisModeLabel())
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => this.setEmphasisMode(index))
    }
    SettingRow({ title: '气泡样式', description: this.currentEmphasis().bubbleStyle ? '自定义' : `跟随「${this.emphasisSourceName()}」` }) {
      Select(this.bubbleStyleOptions())
        .id('theme_editor_emphasis_style')
        .width('44%')
        .selected(this.bubbleStyleIndex())
        .value(this.bubbleStyleLabel(this.currentEmphasis().bubbleStyle))
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => this.setEmphasisStyle(index))
    }
    ThemeColorOption({
      title: '强调底色',
      description: this.currentEmphasis().color ? '自定义' : `跟随「${this.emphasisSourceName()}」`,
      color: this.effectiveEmphasis().emphasisColor,
      allowAlpha: true,
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        this.setEmphasisColor(false, color);
      }
    })
    ThemeColorOption({
      title: '强调文字色',
      description: this.currentEmphasis().textColor ? '自定义' : `跟随「${this.emphasisSourceName()}」`,
      color: this.effectiveEmphasis().emphasisTextColor,
      allowAlpha: true,
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        this.setEmphasisColor(true, color);
      }
    })
  }

  // ---- 标题强调：浅色、深色各一套，覆盖存在强调覆盖的 title 里，标题气泡素材在方案素材包的 titleBubble ----

  @Builder
  titleGroupRows() {
    Stack() {
      Column() {
        this.titleEmphasisControls()
      }
      .width('100%')
      .opacity(this.advancedOpacity())
      this.advancedLockLayer()
    }
    .width('100%')
    if (this.effectiveTitle().mode === 'bubble' && this.assetRevision >= 0) {
      this.titleBubbleSlots()
    }
    this.resetRow('从强调气泡复制', () => this.copyTitleFromEmphasis())
    if (AppThemeSettingsStore.titleEmphasisOverridden(this.currentEmphasis().title)) {
      this.resetRow(`恢复${this.modeLabel()}标题强调为所选主题的设置`, () => this.resetTitleEmphasis())
    }
  }

  @Builder
  titleEmphasisControls() {
    SettingRow({ title: '强调方式', description: this.titleDescription(this.currentEmphasis().title.mode) }) {
      Select(this.titleModeOptions())
        .id('theme_editor_title_mode')
        .width('44%')
        .selected(this.titleModeIndex())
        .value(this.titleModeLabel())
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => this.setTitleMode(index))
    }
    if (this.effectiveTitle().mode === 'bubble') {
      SettingRow({ title: '气泡样式', description: this.titleDescription(this.currentEmphasis().title.bubbleStyle) }) {
        Select(this.titleStyleOptions())
          .id('theme_editor_title_style')
          .width('44%')
          .selected(this.titleStyleIndex())
          .value(this.titleStyleLabel(this.effectiveTitleStyle()))
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .optionFont({ family: this.applicationFontFamily })
          .selectedOptionFont({ family: this.applicationFontFamily })
          .fontColor(this.subTextColor())
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.END)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .optionBgColor(Color.Transparent)
          .divider(null)
          .optionFontColor(this.primaryTextColor())
          .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
          .onSelect((index: number) => this.setTitleStyle(index))
      }
    }
    // 仅文字色只用文字色，底色行藏起来免得误调。
    if (this.titleHasColors() && this.effectiveTitle().mode !== 'text') {
      ThemeColorOption({
        title: '强调底色',
        description: this.titleDescription(this.currentEmphasis().title.color),
        color: this.effectiveTitleColor(false),
        allowAlpha: true,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setTitleColor(false, color);
        }
      })
    }
    if (this.titleHasColors()) {
      ThemeColorOption({
        title: '强调文字色',
        description: this.titleDescription(this.currentEmphasis().title.textColor),
        color: this.effectiveTitleColor(true),
        allowAlpha: true,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setTitleColor(true, color);
        }
      })
    }
  }

  @Builder
  titleBubbleSlots() {
    Row({ space: AppSpacing.XL }) {
      this.assetSlot({ label: '端饰', image: this.ownTitleBubbleItem(false),
        state: this.ownTitleBubbleItem(false) ? 'own' : 'empty',
        slotWidth: 56, slotHeight: 56, onTap: () => this.tapTitleBubbleSlot(false) })
      this.assetSlot({ label: '边框', image: this.ownTitleBubbleItem(true),
        state: this.ownTitleBubbleItem(true) ? 'own' : 'empty',
        slotWidth: 56, slotHeight: 56, onTap: () => this.tapTitleBubbleSlot(true) })
      Text(this.titleBubbleHint())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
  }

  // ---- 章首装饰：标题饰图、序号行颜色，浅色、深色各一套，素材和设置在方案素材包的 chapterHead，
  // 强调覆盖的 chapterHead 指向素材包 ----

  @Builder
  chapterHeadGroupRows() {
    Row({ space: AppSpacing.XL }) {
      this.assetSlot({ label: '标题饰图', image: this.chapterHeadSlotImage(),
        state: this.chapterHeadSlotState(),
        slotWidth: 56, slotHeight: 56, onTap: () => this.tapChapterHeadSlot() })
      Text(this.chapterHeadHint())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    if (this.chapterHeadAdjustable()) {
      SettingRow({ title: '饰图位置', description: '左侧时贴版心左边、上下对齐整组标题；上方、下方时单独占一行' }) {
        Select(this.chapterHeadPlacementOptions())
          .id('theme_editor_chapter_head_placement')
          .width('44%')
          .selected(this.chapterHeadPlacementIndex())
          .value(CHAPTER_HEAD_PLACEMENT_NAMES[this.chapterHeadPlacementIndex()])
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .optionFont({ family: this.applicationFontFamily })
          .selectedOptionFont({ family: this.applicationFontFamily })
          .fontColor(this.subTextColor())
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.END)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .optionBgColor(Color.Transparent)
          .divider(null)
          .optionFontColor(this.primaryTextColor())
          .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
          .onSelect((index: number) => this.setChapterHeadPlacement(index))
      }
      Column({ space: AppSpacing.XS }) {
        Row() {
          Text('饰图大小')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Text(`${this.chapterHeadScalePercent()}%`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        Slider({ value: this.chapterHeadScalePercent(), min: 50, max: 200, step: 10, style: SliderStyle.OutSet })
          .id('theme_editor_chapter_head_scale')
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
          .width('100%')
          .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
          .accessibilityText('标题饰图大小')
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.setChapterHeadScale(value);
            } else {
              this.chapterHeadScaleDrag = Math.round(value);
            }
          })
      }
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
    }
    ThemeColorOption({
      title: '序号行颜色',
      description: this.chapterHeadNumberDescription(),
      color: this.chapterHeadNumberColor(),
      allowAlpha: true,
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        this.setChapterHeadNumberColor(color);
      }
    })
    if (this.ownChapterHeadNumberColor()) {
      this.resetRow('序号行改回和标题同色', () => this.setChapterHeadNumberColor(''))
    }
    SettingRow({ title: '首字装饰', description: '每章第一段的第一个字放大，后面的字绕着它排；开头是引号、数字、字母时这一章不处理' }) {
      Select(this.dropCapLineOptions())
        .id('theme_editor_drop_cap_lines')
        .width('44%')
        .selected(this.dropCapLineIndex())
        .value(DROP_CAP_LINE_NAMES[this.dropCapLineIndex()])
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => this.setDropCapLines(index))
    }
    if (this.effectiveChapterHead().dropCapLines > 0) {
      Row({ space: AppSpacing.XL }) {
        this.assetSlot({ label: '首字印章', image: this.dropCapSlotImage(),
          state: this.dropCapSlotState(),
          slotWidth: 56, slotHeight: 56, onTap: () => this.tapDropCapSlot() })
        Text(this.dropCapHint())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
      ThemeColorOption({
        title: '首字颜色',
        description: this.effectiveChapterHead().dropCapColor ? '自定义' : '和正文同色',
        color: this.effectiveChapterHead().dropCapColor || this.commentPreviewTextColor(this.selectedMode === 'dark'),
        allowAlpha: true,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setDropCapColor(color);
        }
      })
      if (this.effectiveChapterHead().dropCapColor) {
        this.resetRow('首字改回和正文同色', () => this.setDropCapColor(''))
      }
      if (this.effectiveChapterHead().dropCapImage) {
        Column({ space: AppSpacing.XS }) {
          Row() {
            Text('字在印章里的大小')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Text(`${this.dropCapRatioPercent()}%`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          Slider({ value: this.dropCapRatioPercent(), min: 40, max: 90, step: 2, style: SliderStyle.OutSet })
            .id('theme_editor_drop_cap_ratio')
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
            .width('100%')
            .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
            .accessibilityText('字在印章里的大小')
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.setDropCapRatio(value);
              } else {
                this.dropCapRatioDrag = Math.round(value);
              }
            })
        }
        .width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
      }
    }
    if (this.currentEmphasis().chapterHead === CHAPTER_HEAD_NONE) {
      this.resetRow('恢复为所选主题的章首装饰', () => this.setChapterHeadOverride(''))
    } else if (!this.currentEmphasis().chapterHead && !chapterHeadIsEmpty(this.sourceChapterHead())) {
      this.resetRow('不显示所选主题的章首装饰', () => this.setChapterHeadOverride(CHAPTER_HEAD_NONE))
    }
  }

  // ---- 段评气泡（含本章说），浅色、深色各一套，存在强调覆盖的 comment 里 ----

  @Builder
  commentBubbleControls() {
    this.commentBubblePreviewRow()
    this.commentKindRow()
    if (this.commentImageActive()) {
      this.commentImageSlotRow()
      SettingRow({ title: '中间部分', description: '文字变长时两条拉伸线之间怎么填满' }) {
        Select(this.commentRepeatOptions())
          .id('theme_editor_comment_repeat')
          .width('44%')
          .selected(this.commentRepeatIndex())
          .value(this.commentRepeatIndex() === 1 ? '平铺' : '拉伸')
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .optionFont({ family: this.applicationFontFamily })
          .selectedOptionFont({ family: this.applicationFontFamily })
          .fontColor(this.subTextColor())
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.END)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .optionBgColor(Color.Transparent)
          .divider(null)
          .optionFontColor(this.primaryTextColor())
          .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
          .enabled(this.commentImageOwnActive(this.selectedMode === 'dark'))
          .onSelect((index: number) => this.setCommentImageRepeat(index === 1))
      }
      SettingRow({ title: '染成底色', description: '单色剪影图适用，彩色图保持关闭' }) {
        Toggle({ type: ToggleType.Switch, isOn: this.commentImageTint() })
          .enabled(this.commentImageOwnActive(this.selectedMode === 'dark'))
          .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
          .onChange((isOn: boolean) => this.setCommentImageTint(isOn))
      }
    } else {
      this.commentShapeRows()
    }
    if (!this.commentImageActive() ? this.effectiveComment().shape !== 'outline' : this.commentImageTint()) {
      ThemeColorOption({
        title: '底色',
        description: this.commentDescription('fill'),
        color: this.commentStyleColor('fill'),
        allowAlpha: true,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setCommentColor('fill', color);
        }
      })
    }
    if (!this.commentImageActive()) {
      ThemeColorOption({
        title: '描边',
        description: this.commentDescription('stroke'),
        color: this.commentStyleColor('stroke'),
        allowAlpha: true,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setCommentColor('stroke', color);
        }
      })
    }
    ThemeColorOption({
      title: '文字色',
      description: this.commentDescription('text'),
      color: this.commentStyleColor('text'),
      allowAlpha: true,
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        this.setCommentColor('text', color);
      }
    })
    SettingRow({ title: '角标', description: this.commentDescription('ornament') }) {
      Select(this.commentOrnamentOptions())
        .id('theme_editor_comment_ornament')
        .width('44%')
        .selected(this.commentOrnamentIndex())
        .value(this.commentOrnamentLabel())
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => this.setCommentOrnament(index))
    }
    if (this.commentPreviewStyle(this.selectedMode === 'dark').ornamentImage) {
      this.commentOrnamentRows()
    }
    if (this.commentPreviewStyle(this.selectedMode === 'dark').ornament) {
      ThemeColorOption({
        title: '角标颜色',
        description: this.commentPreviewStyle(this.selectedMode === 'dark').ornamentImage ?
          (this.currentEmphasis().comment.ornamentColor ? '自定义，整张角标图染成这个颜色' : '不设时角标图按原色') :
          this.commentDescription('ornamentColor'),
        color: this.commentStyleColor('ornamentColor'),
        allowAlpha: true,
        showDivider: false,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setCommentColor('ornamentColor', color);
        }
      })
    }
    if (this.selectedMode === 'dark' && !commentBubbleIsEmpty(this.lightEmphasis.comment)) {
      this.resetRow('从浅色复制形状、图片和角标', () => this.copyCommentShapeFromLight())
    }
    if (!commentBubbleIsEmpty(this.currentEmphasis().comment)) {
      this.resetRow(`恢复${this.modeLabel()}段评气泡跟随气泡样式`, () => this.resetComment())
    }
  }

  @Builder
  commentShapeRows() {
    SettingRow({ title: '形状', description: this.commentDescription('shape') }) {
      Select(this.commentShapeOptions())
        .id('theme_editor_comment_shape')
        .width('44%')
        .selected(this.commentShapeIndex())
        .value(this.commentShapeLabel())
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => this.setCommentShape(index))
    }
    if (this.effectiveComment().shape === 'rounded') {
      SettingRow({ title: '圆角', description: this.commentDescription('radius') }) {
        Select(this.commentRadiusOptions())
          .id('theme_editor_comment_radius')
          .width('44%')
          .selected(this.commentRadiusIndex())
          .value(this.commentRadiusLabel())
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .optionFont({ family: this.applicationFontFamily })
          .selectedOptionFont({ family: this.applicationFontFamily })
          .fontColor(this.subTextColor())
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.END)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .optionBgColor(Color.Transparent)
          .divider(null)
          .optionFontColor(this.primaryTextColor())
          .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
          .onSelect((index: number) => this.setCommentRadius(index))
      }
    }
  }

  /** 外观：绘制（形状与颜色）或图片（上传的气泡图）。 */
  @Builder
  commentKindRow() {
    Row({ space: AppSpacing.SM }) {
      Text('外观')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Row({ space: 2 }) {
        this.commentKindChip('绘制', !this.commentImageActive(), () => this.setCommentKind(false))
        this.commentKindChip('图片', this.commentImageActive(), () => this.setCommentKind(true))
      }
      .padding(2)
      .borderRadius(18)
      .backgroundColor(this.inputColor())
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
  }

  @Builder
  commentKindChip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(selected ? ThemeRuntime.accentColor(this.appDarkMode) : this.subTextColor())
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .width(64)
      .height(30)
      .borderRadius(15)
      .backgroundColor(selected ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
      .accessibilitySelected(selected)
      .onClick(onTap)
  }

  @Builder
  commentImageSlotRow() {
    Row({ space: AppSpacing.XL }) {
      this.assetSlot({ label: '气泡图', image: this.commentImageActive() ? this.effectiveComment().image : '',
        state: this.commentImageOwnActive(this.selectedMode === 'dark') ? 'own' :
          (this.commentImageActive() ? 'inherit' : 'empty'),
        slotWidth: 92, slotHeight: 56, icon: false, onTap: () => this.tapCommentImageSlot() })
      Column({ space: AppSpacing.XS }) {
        Text(this.commentImageHint())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
        if (this.commentImageOverhangWarning()) {
          Text(this.commentImageOverhangWarning())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.LG })
  }

  @Builder
  commentOrnamentRows() {
    Row({ space: AppSpacing.XL }) {
      this.assetSlot({ label: '角标图', image: this.effectiveComment().ornamentImage,
        state: this.commentOrnamentOwnActive(this.selectedMode === 'dark') ? 'own' : 'inherit',
        slotWidth: 56, slotHeight: 56, icon: true, onTap: () => this.tapCommentOrnamentSlot() })
      Column({ space: AppSpacing.SM }) {
        Row({ space: 2 }) {
          ForEach(COMMENT_ORNAMENT_CORNERS, (corner: string, index: number) => {
            this.commentKindChip(COMMENT_ORNAMENT_CORNER_NAMES[index], this.commentOrnamentCorner() === corner,
              () => this.setCommentOrnamentCorner(corner))
          }, (corner: string) => corner)
        }
        .padding(2)
        .borderRadius(18)
        .backgroundColor(this.inputColor())
        Row() {
          Text('大小')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
          Slider({ value: this.commentOrnamentSizePercent(), min: 50, max: 150, step: 5, style: SliderStyle.OutSet })
            .id('theme_editor_comment_ornament_size')
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
            .layoutWeight(1)
            .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
            .accessibilityText('角标大小')
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.setCommentOrnamentSize(Math.round(value));
              }
            })
          Text(`${this.commentOrnamentSizePercent()}%`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .width(40)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.MD })
  }

  /** 浅色、深色两个小样并排，各放在自己模式的阅读底色上。 */
  @Builder
  commentBubblePreviewRow() {
    Row({ space: AppSpacing.MD }) {
      this.commentBubblePreviewCell(false)
      this.commentBubblePreviewCell(true)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
  }

  @Builder
  commentBubblePreviewCell(dark: boolean) {
    Column({ space: AppSpacing.XXS }) {
      Text(dark ? '深色' : '浅色')
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.commentPreviewTextColor(dark))
        .opacity(0.6)
      Row({ space: AppSpacing.XXS }) {
        Text('他抬头道：走吧。')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.commentPreviewTextColor(dark))
          .maxLines(1)
        if (this.commentPreviewImage(dark)) {
          Image((this.commentPreviewImage(dark) as ReaderCommentBubbleImage).pixelMap)
            .width(this.getUIContext().px2vp((this.commentPreviewImage(dark) as ReaderCommentBubbleImage).width))
            .height(this.getUIContext().px2vp((this.commentPreviewImage(dark) as ReaderCommentBubbleImage).height))
            .objectFit(ImageFit.Contain)
            .draggable(false)
        }
      }
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpacing.MD, right: AppSpacing.SM, top: AppSpacing.SM, bottom: AppSpacing.SM })
    .borderRadius(10)
    .backgroundColor(this.commentPreviewPaper(dark))
    .border({ width: this.selectedMode === (dark ? 'dark' : 'light') ? 1.5 : 0,
      color: ThemeRuntime.accentColor(this.appDarkMode) })
    .accessibilityText(`${dark ? '深色' : '浅色'}段评气泡预览`)
  }

  /** 合并了来源主题与方案覆盖之后、这个模式实际的段评设置。 */
  effectiveComment(): ThemePackageCommentBubble {
    return normalizeCommentBubble(this.effectiveEmphasis().commentBubble);
  }

  commentPreviewStyle(dark: boolean): ReaderCommentBubbleStyle {
    const theme = this.customPreviewTheme();
    const variant = dark ? theme.dark : theme.light;
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = 'bubble';
    context.inheritedBubbleStyleId = variant.regexEmphasis.bubbleStyle;
    context.inheritedColor = variant.regexEmphasis.emphasisColor;
    context.inheritedTextColor = variant.regexEmphasis.emphasisTextColor;
    context.accentColor = variant.colors.accentColor;
    context.surfaceColor = variant.reader.backgroundColor;
    context.normalTextColor = variant.reader.textColor;
    context.darkMode = dark;
    const bubble = ReaderRegexBubbleStyleResolver.resolve(null, context, false);
    return ReaderCommentBubbleStyles.resolveThemed(bubble.bubbleStyleId, dark, variant.reader.textColor,
      variant.regexEmphasis.commentBubble, bubble.backgroundColor, bubble.textColor, bubble.emphasisColor);
  }

  commentPreviewImage(dark: boolean): ReaderCommentBubbleImage | null {
    const style = this.commentPreviewStyle(dark);
    const pxPerVp = this.getUIContext().vp2px(1);
    const key = `${style.identity()}_${pxPerVp}`;
    const cached = this.commentPreviewImages.get(key);
    if (cached !== undefined) return cached;
    if (this.commentPreviewImages.size > 24) this.commentPreviewImages.clear();
    const rendered = ReaderCommentBubblePainter.renderLabel(style, '12', AppFontSize.CAPTION * 0.85 * pxPerVp);
    this.commentPreviewImages.set(key, rendered);
    return rendered;
  }

  commentPreviewPaper(dark: boolean): string {
    const theme = this.customPreviewTheme();
    return (dark ? theme.dark : theme.light).reader.backgroundColor;
  }

  commentPreviewTextColor(dark: boolean): string {
    const theme = this.customPreviewTheme();
    return (dark ? theme.dark : theme.light).reader.textColor;
  }

  commentStyleColor(key: string): string {
    const style = this.commentPreviewStyle(this.selectedMode === 'dark');
    let value = style.text;
    if (key === 'fill') value = style.fill;
    else if (key === 'stroke') value = style.stroke;
    else if (key === 'ornamentColor') value = style.ornamentColor;
    const hex = (value >>> 0).toString(16).toUpperCase();
    return `#${'00000000'.substring(hex.length)}${hex}`;
  }

  /** 方案自己改过就写“自定义”，否则说明跟的是谁。 */
  commentDescription(key: string): string {
    const own = this.currentEmphasis().comment;
    const values: Record<string, string> = {
      'shape': own.shape, 'radius': own.radius >= 0 ? 'set' : '', 'fill': own.fill, 'stroke': own.stroke,
      'text': own.text, 'ornament': own.ornament, 'ornamentColor': own.ornamentColor
    };
    if (values[key]) return '自定义';
    if (key === 'stroke' && this.effectiveComment().shape === 'outline') return '跟随正文墨色';
    if (key === 'text' && this.effectiveComment().shape === 'outline') return '跟随正文墨色';
    return `跟随「${this.emphasisSourceName()}」`;
  }

  commentShapeIds(): string[] {
    return [''].concat(COMMENT_BUBBLE_SHAPES);
  }

  commentShapeOptions(): SelectOption[] {
    return ['跟随气泡样式'].concat(COMMENT_BUBBLE_SHAPE_NAMES).map((name: string): SelectOption => ({ value: name }));
  }

  commentShapeIndex(): number {
    return Math.max(0, this.commentShapeIds().indexOf(this.currentEmphasis().comment.shape));
  }

  commentShapeLabel(): string {
    return (['跟随气泡样式'].concat(COMMENT_BUBBLE_SHAPE_NAMES))[this.commentShapeIndex()];
  }

  commentRadiusValues(): number[] {
    return [-1, 0.1, 0.2, 0.35, 0.5];
  }

  commentRadiusOptions(): SelectOption[] {
    return ['默认', '小', '中', '大', '全圆'].map((name: string): SelectOption => ({ value: name }));
  }

  commentRadiusIndex(): number {
    return Math.max(0, this.commentRadiusValues().indexOf(this.currentEmphasis().comment.radius));
  }

  commentRadiusLabel(): string {
    return ['默认', '小', '中', '大', '全圆'][this.commentRadiusIndex()];
  }

  commentOrnamentIds(): string[] {
    return [''].concat(COMMENT_BUBBLE_ORNAMENTS);
  }

  commentOrnamentOptions(): SelectOption[] {
    return ['跟随气泡样式'].concat(COMMENT_BUBBLE_ORNAMENT_NAMES).map((name: string): SelectOption => ({ value: name }));
  }

  commentOrnamentIndex(): number {
    return Math.max(0, this.commentOrnamentIds().indexOf(this.currentEmphasis().comment.ornament));
  }

  commentOrnamentLabel(): string {
    return (['跟随气泡样式'].concat(COMMENT_BUBBLE_ORNAMENT_NAMES))[this.commentOrnamentIndex()];
  }

  updateComment(apply: (next: ThemePackageCommentBubble) => void): void {
    this.updateEmphasis((next: ThemeEmphasisOverrides): void => {
      const comment = normalizeCommentBubble(next.comment);
      apply(comment);
      next.comment = normalizeCommentBubble(comment);
    });
  }

  setCommentShape(index: number): void {
    const ids = this.commentShapeIds();
    if (index < 0 || index >= ids.length || ids[index] === this.currentEmphasis().comment.shape) return;
    this.updateComment((next: ThemePackageCommentBubble): void => {
      next.shape = ids[index];
    });
  }

  setCommentRadius(index: number): void {
    const values = this.commentRadiusValues();
    if (index < 0 || index >= values.length || values[index] === this.currentEmphasis().comment.radius) return;
    this.updateComment((next: ThemePackageCommentBubble): void => {
      next.radius = values[index];
    });
  }

  setCommentOrnament(index: number): void {
    const ids = this.commentOrnamentIds();
    if (index < 0 || index >= ids.length) return;
    if (ids[index] === 'custom') {
      if (this.commentPreviewStyle(this.selectedMode === 'dark').ornamentImage) return;
      this.useCustomOrnament();
      return;
    }
    if (ids[index] === this.currentEmphasis().comment.ornament) return;
    this.updateComment((next: ThemePackageCommentBubble): void => {
      next.ornament = ids[index];
      next.ornamentImage = '';
    });
  }

  setCommentColor(key: string, color: string): void {
    const normalized = HexColor.parseAlpha(color);
    if (!normalized) return;
    const own = this.currentEmphasis().comment;
    const current = key === 'fill' ? own.fill : key === 'stroke' ? own.stroke :
      key === 'text' ? own.text : own.ornamentColor;
    // 取色器打开再关上会把显示中的颜色原样交回来：没改过的项不要因此变成“自定义”。6 位色按不透明比较。
    const argb = (value: string): string => (value.length === 7 ? `#FF${value.substring(1)}` : value).toUpperCase();
    if (!current && argb(normalized) === argb(this.commentStyleColor(key))) return;
    if (current && argb(normalized) === argb(current)) return;
    this.updateComment((next: ThemePackageCommentBubble): void => {
      if (key === 'fill') next.fill = normalized;
      else if (key === 'stroke') next.stroke = normalized;
      else if (key === 'text') next.text = normalized;
      else next.ornamentColor = normalized;
    });
  }

  /** 深色的颜色多半和浅色不同，只搬形状、圆角、气泡图与角标（图片按“沿用浅色”处理）。 */
  copyCommentShapeFromLight(): void {
    const light = normalizeCommentBubble(this.lightEmphasis.comment);
    this.updateComment((next: ThemePackageCommentBubble): void => {
      next.shape = light.shape;
      next.radius = light.radius;
      next.ornament = light.ornament;
      next.image = light.image;
      next.ornamentImage = light.ornamentImage;
      next.ornamentCorner = light.ornamentCorner;
      next.ornamentSize = light.ornamentSize;
    });
    HdsFeedback.showToast('已按浅色设置形状、图片和角标');
  }

  resetComment(): void {
    this.updateComment((next: ThemePackageCommentBubble): void => {
      const empty = new ThemePackageCommentBubble();
      next.shape = empty.shape;
      next.radius = empty.radius;
      next.fill = empty.fill;
      next.stroke = empty.stroke;
      next.text = empty.text;
      next.ornament = empty.ornament;
      next.ornamentColor = empty.ornamentColor;
      next.image = empty.image;
      next.ornamentImage = empty.ornamentImage;
      next.ornamentCorner = empty.ornamentCorner;
      next.ornamentSize = empty.ornamentSize;
    });
  }

  // ---- 段评气泡图与角标图：素材在方案素材包这个模式的 commentBubble 里，覆盖用 pack:<id> 指过去 ----

  /** 这个模式实际用的是气泡图（来源主题的或方案自己的）。 */
  commentImageActive(): boolean {
    return commentBubbleHasImage(this.effectiveComment());
  }

  /** 方案素材包里给这个模式用的段评设置（含另一模式沿用过来的图）。 */
  ownCommentResolved(dark: boolean): ThemePackageCommentBubble | null {
    const pack = this.ownPack();
    if (!pack || this.assetRevision < 0) return null;
    return commentBubbleFor(pack.record.parts, dark);
  }

  /** 这个模式自己上传的段评设置（不含沿用）。 */
  ownCommentPart(dark: boolean): ThemePackageCommentBubble {
    const pack = this.ownPack();
    const variant = pack && this.assetRevision >= 0 ? (dark ? pack.record.parts.dark : pack.record.parts.light) : null;
    return normalizeCommentBubble(variant ? variant.commentBubble : null);
  }

  ownCommentHasImage(dark: boolean): boolean {
    return commentBubbleHasImage(this.ownCommentPart(dark));
  }

  emphasisFor(dark: boolean): ThemeEmphasisOverrides {
    return dark ? this.darkEmphasis : this.lightEmphasis;
  }

  /** 这个模式正在用方案自己上传的气泡图。 */
  commentImageOwnActive(dark: boolean): boolean {
    const own = this.ownThemeId();
    return !!own && normalizeCommentBubble(this.emphasisFor(dark).comment).image === own &&
      commentBubbleHasImage(this.ownCommentResolved(dark));
  }

  commentOrnamentOwnActive(dark: boolean): boolean {
    const own = this.ownThemeId();
    const resolved = this.ownCommentResolved(dark);
    return !!own && normalizeCommentBubble(this.emphasisFor(dark).comment).ornamentImage === own && !!resolved &&
      !!resolved.ornamentImage;
  }

  /** 气泡样式来源主题自己带的段评设置（不含方案覆盖）。 */
  commentSourceComment(dark: boolean): ThemePackageCommentBubble {
    const sources = dark ? this.darkSources : this.lightSources;
    const theme = BuiltinThemeRegistry.findById(sources.bubbleThemeId);
    return normalizeCommentBubble((dark ? theme.dark : theme.light).regexEmphasis.commentBubble);
  }

  commentImageHint(): string {
    const dark = this.selectedMode === 'dark';
    if (!this.commentImageOwnActive(dark)) {
      return this.commentImageActive() ? `取自「${this.emphasisSourceName()}」，点按可换成自己的` :
        '整只气泡画成一张透明底图，尾巴画在下方；上传后可调拉伸线和文字区';
    }
    if (dark && !this.ownCommentHasImage(true)) {
      return '深色沿用浅色那张。浅色图在深色纸面上看不清时，单独传一张或打开染色';
    }
    const mode = dark ? '深色' : '浅色';
    return `${mode}用自己上传的气泡图。点按可调拉伸线和文字区、替换或移除`;
  }

  commentImageOverhangWarning(): string {
    const style = this.commentPreviewStyle(this.selectedMode === 'dark');
    if (!style.image) return '';
    const box = new ThemePackageBubbleSlice();
    box.top = style.textTop;
    box.bottom = style.textBottom;
    const reach = commentImageOverhang(box);
    if (reach[0] <= COMMENT_IMAGE_OVERHANG_TOP && reach[1] <= COMMENT_IMAGE_OVERHANG_BOTTOM) return '';
    return '图片上下超出文字区较多，正文行距小时可能压到上下行';
  }

  /** 这个模式用的那张图的拉伸设置（方案自己的）。 */
  ownCommentImageSettings(dark: boolean): ThemePackageCommentBubble {
    const resolved = this.ownCommentResolved(dark);
    const settings = new ThemePackageCommentBubble();
    if (!resolved) return settings;
    copyCommentImage(settings, resolved);
    return settings;
  }

  commentImageTint(): boolean {
    return this.commentPreviewStyle(this.selectedMode === 'dark').imageTint;
  }

  commentRepeatOptions(): SelectOption[] {
    return ['拉伸', '平铺'].map((name: string): SelectOption => ({ value: name }));
  }

  commentRepeatIndex(): number {
    return this.commentPreviewStyle(this.selectedMode === 'dark').imageRound ? 1 : 0;
  }

  /** 只改这个模式的方案覆盖（不跟随 selectedMode）。 */
  updateCommentFor(dark: boolean, apply: (next: ThemePackageCommentBubble) => void): void {
    if (this.advancedLocked()) return;
    this.rememberChange();
    const next = AppThemeSettingsStore.normalizeEmphasis(this.emphasisFor(dark));
    const comment = normalizeCommentBubble(next.comment);
    apply(comment);
    next.comment = normalizeCommentBubble(comment);
    if (dark) this.darkEmphasis = next;
    else this.lightEmphasis = next;
    this.onSettingChanged();
  }

  async setCommentKind(useImage: boolean): Promise<void> {
    if (useImage === this.commentImageActive()) return;
    if (!(await this.ensureAdvanced())) return;
    const dark = this.selectedMode === 'dark';
    if (!useImage) {
      this.updateCommentFor(dark, (next: ThemePackageCommentBubble): void => {
        next.image = COMMENT_IMAGE_NONE;
      });
      return;
    }
    const own = this.ownThemeId();
    if (own && commentBubbleHasImage(this.ownCommentResolved(dark))) {
      this.updateCommentFor(dark, (next: ThemePackageCommentBubble): void => {
        next.image = own;
      });
    } else if (commentBubbleHasImage(this.commentSourceComment(dark))) {
      this.updateCommentFor(dark, (next: ThemePackageCommentBubble): void => {
        next.image = '';
      });
    } else {
      await this.uploadCommentImage(dark);
    }
  }

  async uploadCommentImage(dark: boolean): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    // 换图时沿用原来的平铺、换行和染色，文字区与拉伸线按新图给默认位置。
    const previous = this.ownCommentImageSettings(dark);
    previous.imageSlice = null;
    previous.imageText = null;
    const settings = await this.stretchCommentImage(uris[0], previous, dark);
    if (!settings) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setCommentImage(getContext(this), this.schemeId, uris[0], this.sourceThemeId('bubble'),
        settings, dark), '', false, false, '');
    const own = this.ownThemeId();
    if (!own || !this.ownCommentHasImage(dark)) return;
    this.updateCommentFor(dark, (next: ThemePackageCommentBubble): void => {
      next.image = own;
    });
    // 另一种模式还没做选择、来源也没有图时一起指过来：它没有自己的图就沿用这张。
    const other = normalizeCommentBubble(this.emphasisFor(!dark).comment);
    if (!other.image && !commentBubbleHasImage(this.commentSourceComment(!dark))) {
      this.updateCommentFor(!dark, (next: ThemePackageCommentBubble): void => {
        next.image = own;
      });
    }
    HdsFeedback.showToast(dark ? '深色段评气泡图已更新' : '段评气泡图已更新');
  }

  async tapCommentImageSlot(): Promise<void> {
    // 菜单期间可能切换浅色/深色，操作的是点开时那个模式。
    const dark = this.selectedMode === 'dark';
    if (!(await this.ensureAdvanced())) return;
    if (!this.commentImageOwnActive(dark)) {
      await this.uploadCommentImage(dark);
      return;
    }
    const mode = dark ? '深色' : '浅色';
    const ownHere = this.ownCommentHasImage(dark);
    const otherOwn = this.ownCommentHasImage(!dark);
    const items: string[] = ['调整拉伸线与文字区', ownHere ? '替换图片' : `换一张${mode}专用的`];
    if (ownHere) items.push(dark ? '浅色也用这张' : '深色也用这张');
    items.push(dark && ownHere && otherOwn ? '移除，沿用浅色那张' : '移除气泡图');
    const choice = await this.slotMenuItems(`${mode} · 段评气泡图`, items);
    if (choice < 0) return;
    const picked = items[choice];
    if (picked.startsWith('调整')) {
      await this.adjustCommentImage(dark);
    } else if (picked.startsWith('替换') || picked.startsWith('换一张')) {
      await this.uploadCommentImage(dark);
    } else if (picked.endsWith('也用这张')) {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.copyCommentImageToOtherMode(getContext(this), this.schemeId, dark), '', false, false,
        `${dark ? '浅色' : '深色'}也用这张气泡图了`);
      const own = this.ownThemeId();
      if (own) {
        this.updateCommentFor(!dark, (next: ThemePackageCommentBubble): void => {
          next.image = own;
        });
      }
    } else {
      await this.removeCommentImage(dark, picked.includes('沿用'));
    }
  }

  async adjustCommentImage(dark: boolean): Promise<void> {
    const resolved = this.ownCommentResolved(dark);
    const pack = this.ownPack();
    if (!resolved || !pack || !commentBubbleHasImage(resolved)) return;
    const uri = this.ownAssetUri(resolved.image);
    if (!uri) return;
    const settings = await this.stretchCommentImage(uri, this.ownCommentImageSettings(dark), dark);
    if (!settings) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setCommentImageSettings(getContext(this), this.schemeId, settings, dark),
      '', false, false, '拉伸线与文字区已更新');
  }

  /**
   * 移除这个模式自己的气泡图。keepFallback 为 true（深色移除后沿用浅色那张）时覆盖不动；否则这个模式改回画形状：
   * 另一模式还有图（会被沿用过来）时写 none，不然清掉覆盖。两种模式都没有图了，指向素材包的覆盖一起清掉。
   */
  async removeCommentImage(dark: boolean, keepFallback: boolean): Promise<void> {
    const previous = this.ownThemeId();
    if (this.ownCommentHasImage(dark)) {
      await this.runAssetClear((): Promise<SchemeAssetResult> =>
        SchemeAssetService.clearCommentImage(getContext(this), this.schemeId, dark), '');
    }
    if (keepFallback) return;
    const otherHasImage = this.ownCommentHasImage(!dark) || commentBubbleHasImage(this.commentSourceComment(dark));
    this.updateCommentFor(dark, (next: ThemePackageCommentBubble): void => {
      next.image = otherHasImage ? COMMENT_IMAGE_NONE : '';
    });
    if (!this.ownCommentHasImage(false) && !this.ownCommentHasImage(true)) {
      for (const mode of [false, true]) {
        if (normalizeCommentBubble(this.emphasisFor(mode).comment).image === previous && previous) {
          this.updateCommentFor(mode, (next: ThemePackageCommentBubble): void => {
            next.image = '';
          });
        }
      }
    }
  }

  async setCommentImageRepeat(round: boolean): Promise<void> {
    const dark = this.selectedMode === 'dark';
    if (!this.commentImageOwnActive(dark) || round === this.commentPreviewStyle(dark).imageRound) return;
    const settings = this.ownCommentImageSettings(dark);
    settings.imageRepeat = round ? CommentImageRepeat.ROUND : '';
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setCommentImageSettings(getContext(this), this.schemeId, settings, dark), '', false, false, '');
  }

  async setCommentImageTint(on: boolean): Promise<void> {
    const dark = this.selectedMode === 'dark';
    // 开关重建时可能原样回调一次（见 Toggle 重建触发 onChange），值没变就不动。
    if (!this.commentImageOwnActive(dark) || on === this.commentPreviewStyle(dark).imageTint) return;
    const settings = this.ownCommentImageSettings(dark);
    settings.imageTint = on;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setCommentImageSettings(getContext(this), this.schemeId, settings, dark), '', false, false, '');
  }

  /** 打开拉伸与文字区页；点“使用”交回设置，取消返回 null。 */
  stretchCommentImage(uri: string, settings: ThemePackageCommentBubble,
    dark: boolean): Promise<ThemePackageCommentBubble | null> {
    return new Promise<ThemePackageCommentBubble | null>((resolve: (result: ThemePackageCommentBubble | null) => void) => {
      const request = new CommentImageStretchRequest();
      const style = this.commentPreviewStyle(dark);
      const hex = (value: number): string => {
        const text = (value >>> 0).toString(16).toUpperCase();
        return `#${'00000000'.substring(text.length)}${text}`;
      };
      request.uri = uri;
      request.settings = settings;
      request.paperColor = this.commentPreviewPaper(dark);
      request.inkColor = this.commentPreviewTextColor(dark);
      request.textColor = hex(style.text);
      request.fillColor = hex(style.fill);
      request.modeLabel = dark ? '深色' : '浅色';
      this.commentStretchResolve = resolve;
      this.commentStretchRequest = request;
      this.commentStretchVisible = true;
    });
  }

  finishCommentStretch(settings: ThemePackageCommentBubble | null): void {
    const resolve = this.commentStretchResolve;
    this.commentStretchResolve = null;
    this.commentStretchVisible = false;
    if (resolve) resolve(settings);
  }

  // 角标图

  commentOrnamentCorner(): string {
    return this.commentPreviewStyle(this.selectedMode === 'dark').ornamentCorner || 'topRight';
  }

  commentOrnamentSizePercent(): number {
    return Math.round(this.commentPreviewStyle(this.selectedMode === 'dark').ornamentSize * 100);
  }

  setCommentOrnamentCorner(corner: string): void {
    const value = corner === 'topRight' ? '' : corner;
    if (value === (this.commentPreviewStyle(this.selectedMode === 'dark').ornamentCorner || '')) return;
    this.updateComment((next: ThemePackageCommentBubble): void => {
      next.ornamentCorner = value;
    });
  }

  setCommentOrnamentSize(percent: number): void {
    const value = Math.max(50, Math.min(150, percent)) / 100;
    if (Math.abs(value - this.commentPreviewStyle(this.selectedMode === 'dark').ornamentSize) < 0.001) return;
    this.updateComment((next: ThemePackageCommentBubble): void => {
      next.ornamentSize = value;
    });
  }

  /** 选了“自定义图片”：方案已有角标图就指过去，来源主题自带就跟随，否则马上选一张。 */
  async useCustomOrnament(): Promise<void> {
    if (!(await this.ensureAdvanced())) return;
    const dark = this.selectedMode === 'dark';
    const own = this.ownThemeId();
    const resolved = this.ownCommentResolved(dark);
    if (own && resolved && resolved.ornamentImage) {
      this.updateCommentFor(dark, (next: ThemePackageCommentBubble): void => {
        next.ornament = 'custom';
        next.ornamentImage = own;
      });
      return;
    }
    const source = this.commentSourceComment(dark);
    if (source.ornament === 'custom' && source.ornamentImage) {
      this.updateCommentFor(dark, (next: ThemePackageCommentBubble): void => {
        next.ornament = 'custom';
        next.ornamentImage = '';
      });
      return;
    }
    await this.uploadCommentOrnament(dark);
    // 没选图时下拉退回原来的选项。
    this.assetRevision++;
  }

  async uploadCommentOrnament(dark: boolean): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setCommentOrnament(getContext(this), this.schemeId, uris[0], this.sourceThemeId('bubble'), dark),
      '', false, false, '');
    const own = this.ownThemeId();
    if (!own || !this.ownCommentPart(dark).ornamentImage) return;
    this.updateCommentFor(dark, (next: ThemePackageCommentBubble): void => {
      next.ornament = 'custom';
      next.ornamentImage = own;
    });
    const other = normalizeCommentBubble(this.emphasisFor(!dark).comment);
    if (!other.ornament && !other.ornamentImage) {
      this.updateCommentFor(!dark, (next: ThemePackageCommentBubble): void => {
        next.ornament = 'custom';
        next.ornamentImage = own;
      });
    }
    HdsFeedback.showToast(dark ? '深色段评角标图已更新' : '段评角标图已更新');
  }

  async tapCommentOrnamentSlot(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    if (!(await this.ensureAdvanced())) return;
    if (!this.commentOrnamentOwnActive(dark)) {
      await this.uploadCommentOrnament(dark);
      return;
    }
    const mode = dark ? '深色' : '浅色';
    const ownHere = !!this.ownCommentPart(dark).ornamentImage;
    const items: string[] = [ownHere ? '替换角标图' : `换一张${mode}专用的`];
    if (ownHere) items.push(dark ? '浅色也用这张' : '深色也用这张');
    items.push('移除角标图');
    const choice = await this.slotMenuItems(`${mode} · 段评角标图`, items);
    if (choice < 0) return;
    const picked = items[choice];
    if (picked.startsWith('替换') || picked.startsWith('换一张')) {
      await this.uploadCommentOrnament(dark);
    } else if (picked.endsWith('也用这张')) {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.copyCommentOrnamentToOtherMode(getContext(this), this.schemeId, dark), '', false, false,
        `${dark ? '浅色' : '深色'}也用这张角标图了`);
      const own = this.ownThemeId();
      if (own) {
        this.updateCommentFor(!dark, (next: ThemePackageCommentBubble): void => {
          next.ornament = 'custom';
          next.ornamentImage = own;
        });
      }
    } else {
      const previous = this.ownThemeId();
      if (ownHere) {
        await this.runAssetClear((): Promise<SchemeAssetResult> =>
          SchemeAssetService.clearCommentOrnament(getContext(this), this.schemeId, dark), '');
      }
      this.updateCommentFor(dark, (next: ThemePackageCommentBubble): void => {
        next.ornament = '';
        next.ornamentImage = '';
      });
      if (!this.ownCommentPart(false).ornamentImage && !this.ownCommentPart(true).ornamentImage && previous) {
        const other = normalizeCommentBubble(this.emphasisFor(!dark).comment);
        if (other.ornamentImage === previous) {
          this.updateCommentFor(!dark, (next: ThemePackageCommentBubble): void => {
            next.ornament = '';
            next.ornamentImage = '';
          });
        }
      }
    }
  }

  /** 系统操作菜单，按给的顺序列出，返回序号；取消返回 -1。“移除”开头的用危险色。 */
  async slotMenuItems(title: string, items: string[]): Promise<number> {
    const b: promptAction.Button[] = items.map((item: string): promptAction.Button =>
      ({ text: item, color: this.menuColor(item) }));
    if (b.length === 0) return -1;
    let buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?] = [b[0]];
    if (b.length === 2) buttons = [b[0], b[1]];
    else if (b.length === 3) buttons = [b[0], b[1], b[2]];
    else if (b.length >= 4) buttons = [b[0], b[1], b[2], b[3]];
    try {
      const result: promptAction.ActionMenuSuccessResponse = await this.getUIContext().getPromptAction().showActionMenu({
        title: title,
        buttons: buttons
      });
      return result.index;
    } catch (_) {
      return -1;
    }
  }

  @Builder
  sectionTitle($$: ThemeEditorSectionTitleOptions) {
    Text($$.title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  currentReader(): ThemeEditorReaderColors {
    return this.selectedMode === 'dark' ? this.darkReader : this.lightReader;
  }

  readerColorValue(key: string): string {
    const reader = this.currentReader();
    if (key === 'textColor') return reader.textColor;
    if (key === 'subTextColor') return reader.subTextColor;
    return reader.backgroundColor;
  }

  readerSourceValue(key: string): string {
    const theme = BuiltinThemeRegistry.findById(this.currentSources().readerThemeId);
    const reader = this.selectedMode === 'dark' ? theme.dark.reader : theme.light.reader;
    if (key === 'textColor') return reader.textColor;
    if (key === 'subTextColor') return reader.subTextColor;
    if (key === 'contentTone') return reader.contentTone;
    return reader.backgroundColor;
  }

  readerColorDescription(key: string): string {
    const background = this.currentReader().backgroundColor;
    if (key === 'textColor' && ThemeColorSettingsPage.contrast(this.currentReader().textColor, background) < 4.5) {
      return `与阅读底色对比 ${ThemeColorSettingsPage.contrast(this.currentReader().textColor, background).toFixed(1)}，偏低`;
    }
    if (key === 'subTextColor' && ThemeColorSettingsPage.contrast(this.currentReader().subTextColor, background) < 3) {
      return `与阅读底色对比 ${ThemeColorSettingsPage.contrast(this.currentReader().subTextColor, background).toFixed(1)}，偏低`;
    }
    const value = this.readerColorValue(key);
    if (value.toUpperCase() === this.readerSourceValue(key).toUpperCase()) {
      return `跟随「${BuiltinThemeRegistry.findById(this.currentSources().readerThemeId).name}」`;
    }
    return '自定义';
  }

  setReaderColor(key: string, color: string): void {
    if (this.advancedLocked()) return;
    const current = this.readerColorValue(key);
    const normalized = AppThemeSettingsStore.normalizeColor(color, current);
    if (normalized === current) return;
    this.rememberChange();
    const next = this.copyReader(this.currentReader());
    if (key === 'textColor') next.textColor = normalized;
    else if (key === 'subTextColor') next.subTextColor = normalized;
    else next.backgroundColor = normalized;
    this.storeReader(next);
  }

  setReaderTone(tone: string): void {
    if (this.advancedLocked()) {
      this.ensureAdvanced();
      return;
    }
    if (tone === this.currentReader().contentTone) return;
    this.rememberChange();
    const next = this.copyReader(this.currentReader());
    next.contentTone = tone;
    this.storeReader(next);
  }

  copyReader(source: ThemeEditorReaderColors): ThemeEditorReaderColors {
    const next = new ThemeEditorReaderColors();
    next.backgroundColor = source.backgroundColor;
    next.textColor = source.textColor;
    next.subTextColor = source.subTextColor;
    next.contentTone = source.contentTone;
    return next;
  }

  storeReader(next: ThemeEditorReaderColors): void {
    if (this.selectedMode === 'dark') this.darkReader = next;
    else this.lightReader = next;
    this.onSettingChanged();
  }

  @Builder
  readerColorRows() {
    Stack() {
      Column() {
        this.readerColorRow('阅读底色', 'backgroundColor')
        this.readerColorRow('正文颜色', 'textColor')
        this.readerColorRow('页眉页脚', 'subTextColor')
        SettingRow({ title: '内容明暗', description: '阅读页上的浮层和图标跟着它用深色或浅色' }) {
          Row({ space: AppSpacing.XXS }) {
            this.toneButton('浅', 'light')
            this.toneButton('深', 'dark')
          }
          .padding(AppSpacing.XXS)
          .borderRadius(14)
          .backgroundColor(this.inputColor())
        }
      }
      .width('100%')
      .opacity(this.advancedOpacity())
      this.advancedLockLayer()
    }
    .width('100%')
  }

  @Builder
  readerColorRow(title: string, key: string) {
    ThemeColorOption({
      title: title,
      description: this.readerColorDescription(key),
      color: this.readerColorValue(key),
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        this.setReaderColor(key, color);
      }
    })
  }

  @Builder
  toneButton(label: string, tone: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.currentReader().contentTone === tone ? this.primaryTextColor() : this.subTextColor())
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XS, bottom: AppSpacing.XS })
      .borderRadius(12)
      .backgroundColor(this.currentReader().contentTone === tone ? this.cardColor() : Color.Transparent)
      .accessibilityText(`内容明暗：${label}`)
      .accessibilitySelected(this.currentReader().contentTone === tone)
      .onClick(() => this.setReaderTone(tone))
  }

  readerAssetId(): string {
    return this.selectedMode === 'dark' ? this.draftSettings.customDarkReaderBackgroundAssetId :
      this.draftSettings.customLightReaderBackgroundAssetId;
  }

  /** 这个模式的阅读背景用的是方案自传的素材时返回 ornaments / image，否则为空。 */
  ownReaderMode(): string {
    const own = this.ownThemeId();
    return own && this.readerAssetId().startsWith(`${own}:`) ? this.readerAssetMode() : '';
  }

  /** 方案自传的阅读背景（角饰模式，或可以叠角饰的整图模式），否则为 null。 */
  ownOrnamentReader(): InstalledThemePackReader | null {
    const mode = this.ownReaderMode();
    if (mode !== 'ornaments' && mode !== 'image') return null;
    const pack = this.ownPack();
    return pack ? pack.reader(this.selectedMode === 'dark') : null;
  }

  readerSlotState(slot: string): string {
    const mode = this.ownReaderMode();
    const id = this.readerAssetId();
    if (slot === 'image') {
      if (mode === 'image') return 'own';
      return ThemeColorSettingsPage.hasImage(ThemeAssetRegistry.readerBackground(id)) ? 'inherit' : 'empty';
    }
    // 自传角饰可以只有一角，空着的那角显示成待上传。
    const own = this.ownOrnamentReader();
    if (own) return (slot === 'trailing' ? own.trailing : own.leading) ? 'own' : 'empty';
    const image = slot === 'trailing' ? ThemeAssetRegistry.readerBackgroundTrailingDecoration(id) :
      ThemeAssetRegistry.readerBackgroundDecoration(id);
    return ThemeColorSettingsPage.hasImage(image) ? 'inherit' : 'empty';
  }

  readerOrnamentScalePercent(trailing: boolean): number {
    const drag = trailing ? this.trailingScaleDrag : this.leadingScaleDrag;
    if (drag >= 0) return drag;
    // 主题包记录不是状态变量：读 assetRevision，保存后才会重新取值。
    if (this.assetRevision < 0) return 100;
    const own = this.ownOrnamentReader();
    if (!own) return 100;
    return Math.round((trailing ? own.trailingScale : own.leadingScale) * 100);
  }

  /** 这一角有自传的图时才能调大小。 */
  readerOrnamentScalable(trailing: boolean): boolean {
    if (this.assetRevision < 0) return false;
    const own = this.ownOrnamentReader();
    return !!own && !!(trailing ? own.trailing : own.leading);
  }

  setOrnamentScaleDrag(trailing: boolean, percent: number): void {
    if (trailing) this.trailingScaleDrag = percent;
    else this.leadingScaleDrag = percent;
  }

  async setReaderOrnamentScale(trailing: boolean, percent: number): Promise<void> {
    this.setOrnamentScaleDrag(trailing, Math.round(percent));
    try {
      if (!(await this.ensureAdvanced())) return;
      const dark = this.selectedMode === 'dark';
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.setReaderOrnamentScale(getContext(this), this.schemeId, dark, trailing, percent / 100),
        '', false, false, '');
    } finally {
      this.setOrnamentScaleDrag(trailing, -1);
    }
  }

  @Builder
  ornamentScaleRow(trailing: boolean) {
    Column({ space: AppSpacing.XS }) {
      Row() {
        Text(trailing ? '右下角饰大小' : '左上角饰大小')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(this.readerOrnamentScalable(trailing) ? `${this.readerOrnamentScalePercent(trailing)}%` :
          (trailing ? '上传右下角饰后可调' : '上传左上角饰后可调'))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Slider({ value: this.readerOrnamentScalePercent(trailing), min: 50, max: 200, step: 10,
        style: SliderStyle.OutSet })
        .id(trailing ? 'theme_editor_reader_trailing_scale' : 'theme_editor_reader_leading_scale')
        .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
        .width('100%')
        .enabled(this.readerOrnamentScalable(trailing))
        .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
        .accessibilityText(trailing ? '右下角饰大小' : '左上角饰大小')
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.setReaderOrnamentScale(trailing, value);
          } else {
            this.setOrnamentScaleDrag(trailing, Math.round(value));
          }
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
    .opacity(this.readerOrnamentScalable(trailing) ? 1 : 0.45)
  }

  @Builder
  readerSlots() {
    Column({ space: AppSpacing.MD }) {
      Text('背景素材')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Row({ space: AppSpacing.XL }) {
        this.assetSlot({ label: '左上角饰', image: ThemeAssetRegistry.readerBackgroundDecoration(this.readerAssetId()),
          state: this.readerSlotState('leading'), slotWidth: 64, slotHeight: 64,
          onTap: () => this.tapReaderSlot('leading') })
        this.assetSlot({ label: '右下角饰',
          image: ThemeAssetRegistry.readerBackgroundTrailingDecoration(this.readerAssetId()),
          rotation: ThemeAssetRegistry.readerBackgroundTrailingRotation(this.readerAssetId()),
          state: this.readerSlotState('trailing'), slotWidth: 64, slotHeight: 64,
          onTap: () => this.tapReaderSlot('trailing') })
        this.assetSlot({ label: '整图', image: ThemeAssetRegistry.readerBackground(this.readerAssetId()),
          state: this.readerSlotState('image'), slotWidth: 40, slotHeight: 64,
          onTap: () => this.tapReaderSlot('image') })
      }
      .width('100%')
      Text('角饰可以只传左上或右下一张，也可以两张都传；右下角也能直接用左上角那张旋转 180°。传了整图时角饰叠在整图上面')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    this.moreRow('reader', '角饰大小与整图铺放')
    if (this.moreOpen('reader')) {
      this.readerMoreRows()
    }
    if (this.ownReaderMode()) {
      this.resetRow(`恢复为所选主题的${this.modeLabel()}阅读背景`, () => this.clearReaderAssets())
    }
  }

  @Builder
  readerMoreRows() {
    this.ornamentScaleRow(false)
    this.ornamentScaleRow(true)
    Column() {
      SettingRow({ title: '整图铺放', description: this.ownReaderMode() === 'image' ? '整图背景在阅读页上的铺法' : '上传整图后可选',
        showDivider: !!this.ownReaderMode() }) {
        Select([{ value: '铺满裁切' }, { value: '完整显示' }, { value: '拉伸' }])
          .id('theme_editor_reader_fit')
          .width('44%')
          .enabled(this.ownReaderMode() === 'image')
          .selected(this.readerFitIndex())
          .value(['铺满裁切', '完整显示', '拉伸'][this.readerFitIndex()])
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .optionFont({ family: this.applicationFontFamily })
          .selectedOptionFont({ family: this.applicationFontFamily })
          .fontColor(this.subTextColor())
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.END)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .optionBgColor(Color.Transparent)
          .divider(null)
          .optionFontColor(this.primaryTextColor())
          .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
          .onSelect((index: number) => this.setReaderFit(index))
      }
    }
    .width('100%')
    .opacity(this.ownReaderMode() === 'image' ? 1 : 0.45)
  }

  readerFitIndex(): number {
    const pack = this.ownPack();
    const fit = pack ? pack.reader(this.selectedMode === 'dark').imageFit : 'cover';
    if (fit === 'contain') return 1;
    if (fit === 'fill') return 2;
    return 0;
  }

  async setReaderFit(index: number): Promise<void> {
    if (!(await this.ensureAdvanced())) return;
    const fit = index === 1 ? 'contain' : (index === 2 ? 'fill' : 'cover');
    const dark = this.selectedMode === 'dark';
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setReaderImageFit(getContext(this), this.schemeId, dark, fit), '', false, false, '');
  }

  async tapReaderSlot(slot: string): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const other = dark ? '浅色' : '深色';
    const own = this.ownOrnamentReader();
    if (this.readerSlotState(slot) !== 'own') {
      if (!(await this.ensureAdvanced())) return;
      if (slot === 'image') {
        await this.uploadReaderImage();
      } else if (slot === 'trailing' && own && own.leading) {
        // 已有左上角饰：右下角可以单独上传，也可以直接用左上角那张旋转。
        const choice = await this.slotMenu(`${this.modeLabel()} · 右下角饰`, '上传图片', '用左上角那张旋转 180°');
        if (choice === 0) await this.uploadReaderOrnament(true);
        else if (choice === 1) await this.mirrorReaderTrailing();
      } else {
        await this.uploadReaderOrnament(slot === 'trailing');
      }
      return;
    }
    const copyLabel = `${other}模式也用这套`;
    let actions: string[] = [];
    if (slot === 'image') {
      actions = ['替换', copyLabel, '移除整图背景'];
    } else if (slot === 'trailing') {
      const mirrored = !!own && !!own.leading && own.trailing === own.leading;
      actions = ['替换', mirrored || !own || !own.leading ? copyLabel : '改用左上角那张旋转', '移除右下角饰'];
    } else {
      actions = ['替换', copyLabel, '移除左上角饰'];
    }
    const name = slot === 'image' ? '整图背景' : (slot === 'trailing' ? '右下角饰' : '左上角饰');
    const choice = await this.slotMenu(`${this.modeLabel()} · ${name}`, actions[0], actions[1], actions[2]);
    if (choice < 0) return;
    const action = actions[choice];
    if (action === '替换') {
      await this.replaceGuarded(() => slot === 'image' ? this.uploadReaderImage() :
        this.uploadReaderOrnament(slot === 'trailing'));
    } else if (action === copyLabel) {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.copyToOtherMode(getContext(this), this.schemeId, 'reader', dark), '', false, false, '');
      if (this.ownPackageId) {
        this.rememberChange();
        this.setReaderBackgroundAssetFor(!dark, packReaderBackgroundId(this.ownPackageId, !dark));
        HdsFeedback.showToast(`${other}模式的阅读背景已换成同一套`);
      }
    } else if (action === '改用左上角那张旋转') {
      await this.mirrorReaderTrailing();
    } else {
      await this.clearReaderSlot(slot);
    }
  }

  async mirrorReaderTrailing(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setReaderTrailingMirror(getContext(this), this.schemeId, dark), '', false, false, '');
  }

  async clearReaderSlot(slot: string): Promise<void> {
    const dark = this.selectedMode === 'dark';
    await this.runAssetClear((): Promise<SchemeAssetResult> =>
      SchemeAssetService.clearReaderSlot(getContext(this), this.schemeId, dark, slot), '');
    if (!this.readerAssetMode()) {
      const sourceTheme = BuiltinThemeRegistry.findById(this.sourceThemeId('reader'));
      this.rememberChange();
      this.setReaderBackgroundAsset(dark ? sourceTheme.dark.reader.backgroundAssetId :
        sourceTheme.light.reader.backgroundAssetId);
    }
  }

  ownBubbleActive(): boolean {
    const own = this.ownThemeId();
    const pack = this.ownPack();
    return !!own && !!pack && pack.hasBubble() && this.effectiveEmphasis().bubbleStyle === own;
  }

  @Builder
  bubbleSlots() {
    Row({ space: AppSpacing.XL }) {
      this.assetSlot({ label: '端饰', image: this.bubbleCapImage(),
        state: this.ownBubbleItem(false) ? 'own' :
          (ThemeColorSettingsPage.hasImage(this.bubbleCapImage()) ? 'inherit' : 'empty'),
        slotWidth: 56, slotHeight: 56, onTap: () => this.tapBubbleSlot(false) })
      this.assetSlot({ label: '边框', image: this.bubbleFrameImage(),
        state: this.ownBubbleItem(true) ? 'own' :
          (ThemeColorSettingsPage.hasImage(this.bubbleFrameImage()) ? 'inherit' : 'empty'),
        slotWidth: 56, slotHeight: 56, onTap: () => this.tapBubbleSlot(true) })
      Text(this.bubbleSlotHint())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    if (this.ownBubbleFrameUri()) {
      Column({ space: AppSpacing.XS }) {
        Text('预览').fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
        ThemeBubbleFramePreview({
          uri: this.ownBubbleFrameUri(),
          capUri: this.ownBubbleCapUri(),
          settings: this.ownBubbleFrameSettings(),
          textColor: this.effectiveEmphasis().emphasisTextColor,
          bubbleColor: this.effectiveEmphasis().emphasisColor,
          paperColor: this.currentReader().backgroundColor,
          normalTextColor: this.currentReader().textColor
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.LG })
    }
  }

  bubbleCapImage(): ResourceStr {
    const style = this.effectiveEmphasis().bubbleStyle;
    const dark = this.selectedMode === 'dark';
    return ThemeAssetRegistry.hasRegexBubbleCap(style, dark) ? ThemeAssetRegistry.regexBubbleCap(style, dark) : '';
  }

  /** 只有主题包的边框会在正文里逐行画出；内置样式的横幅边框不画，这里也不显示。 */
  bubbleFrameImage(): ResourceStr {
    const style = this.effectiveEmphasis().bubbleStyle;
    const dark = this.selectedMode === 'dark';
    return ThemePackRegistry.isPackId(style) && ThemeAssetRegistry.hasRegexBubbleFrame(style, dark) ?
      ThemeAssetRegistry.regexBubbleFrame(style, dark) : '';
  }

  /** 方案自己包里、属于这个模式的那一项（浅色看 parts.bubble，深色看 parts.bubbleDark）；没有时为空串。 */
  ownBubbleItem(frame: boolean, dark: boolean = this.selectedMode === 'dark'): string {
    const pack = this.ownPack();
    if (!pack || this.assetRevision < 0 || !this.ownBubbleActive()) return '';
    const bubble = dark ? pack.record.parts.bubbleDark : pack.record.parts.bubble;
    if (!bubble) return '';
    return (frame ? bubble.frame : bubble.cap) || '';
  }

  bubbleSlotHint(): string {
    const base = '端饰是正方形 SVG 或透明底位图，放在强调文字两端，右端自动旋转。边框按行拉伸，上传后可调拉伸区域';
    if (this.selectedMode !== 'dark') return `${base}。切到深色可以再传只在深色模式用的`;
    if (!this.ownBubbleActive()) return base;
    const cap = this.ownBubbleItem(false) ? '端饰用单独上传的' : '端饰沿用浅色的';
    const frame = this.ownBubbleItem(true) ? '边框用单独上传的' : '边框沿用浅色的';
    const tint = this.ownBubbleItem(true) ? '' : '。浅色素材在深色纸面上看不清时，单独上传一张或给边框打开染色';
    return `深色模式${cap}，${frame}${tint}`;
  }

  /** 方案自己的边框（正在使用时），深色没有单独那张时是浅色的；卡片里的预览只看它。 */
  ownBubbleFrameUri(): string {
    const pack = this.ownPack();
    return this.assetRevision >= 0 && this.ownBubbleActive() && pack ?
      pack.bubble(this.selectedMode === 'dark').frame : '';
  }

  ownBubbleCapUri(): string {
    const pack = this.ownPack();
    return this.assetRevision >= 0 && this.ownBubbleActive() && pack ?
      pack.bubble(this.selectedMode === 'dark').cap : '';
  }

  /** 这个模式实际用的那张边框的拉伸设置。 */
  ownBubbleFrameSettings(dark: boolean = this.selectedMode === 'dark'): ThemePackageBubble {
    const settings = new ThemePackageBubble();
    const pack = this.ownPack();
    if (!pack || this.assetRevision < 0) return settings;
    const bubble = pack.bubble(dark);
    settings.frameSlice = bubble.frameSlice;
    settings.frameRepeat = bubble.frameRepeat;
    settings.frameBreak = bubble.frameBreak;
    settings.frameTint = bubble.frameTint;
    return settings;
  }

  async tapBubbleSlot(frame: boolean): Promise<void> {
    // 菜单期间用户可能切换浅色/深色，操作的是点开时那个模式的那一项。
    const dark = this.selectedMode === 'dark';
    if (!this.ownBubbleItem(frame, dark)) {
      if (!(await this.ensureAdvanced())) return;
      if (frame) await this.uploadBubbleFrame(dark);
      else await this.uploadBubbleCap(dark);
      return;
    }
    const title = `${dark ? '深色' : '浅色'} · ${frame ? '气泡边框' : '气泡端饰'}`;
    if (frame) {
      const choice = await this.slotMenu(title, '调整拉伸区域', '替换', dark ? '移除，沿用浅色的边框' : '移除边框');
      if (choice === 0) {
        await this.replaceGuarded(() => this.adjustBubbleFrame(dark));
      } else if (choice === 1) {
        await this.replaceGuarded(() => this.uploadBubbleFrame(dark));
      } else if (choice === 2) {
        await this.clearBubblePart(true, dark);
      }
      return;
    }
    const choice = await this.slotMenu(title, '替换', dark ? '移除，沿用浅色的端饰' : '移除端饰');
    if (choice === 0) {
      await this.replaceGuarded(() => this.uploadBubbleCap(dark));
    } else if (choice === 1) {
      await this.clearBubblePart(false, dark);
    }
  }

  /** 移除某个模式的端饰或边框；两种模式的端饰、边框全没了时整个包内气泡清掉，强调样式退回所选主题。 */
  async clearBubblePart(frame: boolean, dark: boolean): Promise<void> {
    const pack = this.ownPack();
    const parts = pack ? pack.record.parts : null;
    const remaining: string[] = [];
    if (parts) {
      for (const mode of [false, true]) {
        const bubble = mode ? parts.bubbleDark : parts.bubble;
        if (!bubble) continue;
        if (bubble.cap && !(mode === dark && !frame)) remaining.push(bubble.cap);
        if (bubble.frame && !(mode === dark && frame)) remaining.push(bubble.frame);
      }
    }
    if (remaining.length === 0) {
      await this.clearBubbleAssets();
      return;
    }
    await this.runAssetClear((): Promise<SchemeAssetResult> => frame ?
      SchemeAssetService.clearBubbleFrame(getContext(this), this.schemeId, dark) :
      SchemeAssetService.clearBubbleCap(getContext(this), this.schemeId, dark), '');
  }

  ownTtsPanel(): boolean {
    const own = this.ownThemeId();
    const pack = this.ownPack();
    if (!own || !pack || this.currentSources().ttsPanelThemeId !== own) return false;
    return !!(this.selectedMode === 'dark' ? pack.record.parts.ttsPanelDark : pack.record.parts.ttsPanelLight);
  }

  ttsSourceId(): string {
    return this.currentSources().ttsPanelThemeId || this.currentSources().readerThemeId;
  }

  @Builder
  ttsSlots() {
    Row({ space: AppSpacing.XL }) {
      this.assetSlot({ label: '插画 720 × 520',
        image: TtsPanelThemeStyles.resolve(this.ttsSourceId(), this.selectedMode === 'dark').artwork,
        state: this.ownTtsPanel() ? 'own' : 'inherit', slotWidth: 100, slotHeight: 72,
        onTap: () => this.tapTtsSlot() })
      Text(this.ownTtsPanel() ? '下面三种颜色上传时按当前配色取值，可以再逐项调整' :
        '上传这个模式的插画后，可以调天空色、面板底色和柔光')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    Stack() {
      Column() {
        this.ttsColorRow('天空色', 'sky')
        this.ttsColorRow('面板底色', 'surface')
        this.ttsColorRow('柔光', 'glow')
      }
      .width('100%')
      .opacity(this.ownTtsPanel() && !this.advancedLocked() ? 1 : 0.45)
      if (!this.ownTtsPanel() || this.advancedLocked()) {
        Column()
          .width('100%')
          .height('100%')
          .accessibilityText(this.advancedLocked() ? '会员专享，了解会员' : '先上传这个模式的面板插画')
          .onClick(() => {
            if (this.advancedLocked()) this.ensureAdvanced();
            else HdsFeedback.showToast('先上传这个模式的面板插画');
          })
      }
    }
    .width('100%')
  }

  ttsColorValue(key: string): string {
    const style = TtsPanelThemeStyles.resolve(this.ttsSourceId(), this.selectedMode === 'dark');
    if (key === 'sky') return style.skyColor;
    if (key === 'surface') return style.surfaceColor;
    return style.glowColor;
  }

  @Builder
  ttsColorRow(title: string, key: string) {
    ThemeColorOption({
      title: title,
      description: key === 'glow' ? '播放区的强调光，可带透明度' : (key === 'surface' ? '不透明，接近页面色，保证文字看得清' : '插画背后的渐变起点'),
      color: this.ttsColorValue(key),
      allowAlpha: key === 'glow',
      showDivider: key !== 'glow' || this.ownTtsPanel(),
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        this.setTtsColor(key, color);
      }
    })
  }

  async setTtsColor(key: string, color: string): Promise<void> {
    if (!this.ownTtsPanel() || this.advancedLocked()) return;
    const current = this.ttsColorValue(key);
    const normalized = key === 'glow' ? HexColor.normalizeAlpha(color, current) :
      AppThemeSettingsStore.normalizeColor(color, current);
    if (normalized.toUpperCase() === current.toUpperCase()) return;
    const dark = this.selectedMode === 'dark';
    await this.runAssetUpload((): Promise<SchemeAssetResult> => SchemeAssetService.setTtsColors(getContext(this),
      this.schemeId, dark, key === 'sky' ? normalized : '', key === 'surface' ? normalized : '',
      key === 'glow' ? normalized : ''), '', false, false, '');
  }

  async tapTtsSlot(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const other = dark ? '浅色' : '深色';
    if (!this.ownTtsPanel()) {
      if (!(await this.ensureAdvanced())) return;
      await this.uploadTtsArtwork();
      return;
    }
    const choice = await this.slotMenu(`${this.modeLabel()} · 面板插画`, '替换', `${other}模式也用这张`,
      `移除${this.modeLabel()}插画`);
    if (choice === 0) {
      await this.replaceGuarded(() => this.uploadTtsArtwork());
    } else if (choice === 1) {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.copyToOtherMode(getContext(this), this.schemeId, 'ttsPanel', dark),
        'ttsPanel', dark, !dark, `${other}模式的面板插画已换成同一张`);
    } else if (choice === 2) {
      await this.runAssetClear((): Promise<SchemeAssetResult> =>
        SchemeAssetService.clearTtsMode(getContext(this), this.schemeId, dark), '');
      const pack = this.ownPack();
      if (!pack || !(dark ? pack.record.parts.ttsPanelDark : pack.record.parts.ttsPanelLight)) {
        this.detachModeSource('ttsPanel', dark);
      }
    }
  }

  /** 只把当前模式指向素材包的来源退回包的基底主题（另一种模式可能还在用自己的素材）。 */
  detachModeSource(category: string, dark: boolean): void {
    const own = this.ownThemeId();
    const sources = dark ? this.darkSources : this.lightSources;
    if (!own || this.sourceValueFor(sources, category) !== own) return;
    this.applyPackSource(category, SchemeAssetService.baseThemeOf(this.ownPackageId), !dark, dark);
  }

  // ---- 页签：首页与书架 ----

  ownNavigationActive(): boolean {
    const own = this.ownThemeId();
    const pack = this.ownPack();
    return !!own && !!pack && !!pack.record.parts.navigation && this.currentSources().navigationThemeId === own;
  }

  navSlotValue(key: string): string {
    const pack = this.ownPack();
    if (!this.ownNavigationActive() || !pack || !pack.record.parts.navigation) return '';
    return (pack.record.parts.navigation as Object as Record<string, string>)[key] || '';
  }

  navSlotState(key: string): string {
    if (this.navSlotValue(key)) return 'own';
    return key.endsWith('Selected') ? 'empty' : 'inherit';
  }

  navSlotImage(key: string): ResourceStr {
    const value = this.navSlotValue(key);
    if (value) return this.ownAssetUri(value);
    if (key.endsWith('Selected')) return '';
    return ThemeAssetRegistry.navigationIcon(this.customPreviewTheme().navigation.iconPackId, key, false);
  }

  @Builder
  navSlot(key: string, label: string) {
    this.assetSlot({ label: label, image: this.navSlotImage(key), state: this.navSlotState(key),
      slotWidth: 52, slotHeight: 52, icon: true, onTap: () => this.tapNavSlot(key) })
  }

  @Builder
  navigationSlots() {
    Column({ space: AppSpacing.MD }) {
      Text('普通')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      Row() {
        this.navSlot('bookshelf', '书架')
        this.navSlot('explore', '发现')
        this.navSlot('listen', '听')
        this.navSlot('footprint', '足迹')
        this.navSlot('mine', '我的')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      Text('选中态 · 可选')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      Row() {
        this.navSlot('bookshelfSelected', '书架')
        this.navSlot('exploreSelected', '发现')
        this.navSlot('listenSelected', '听')
        this.navSlot('footprintSelected', '足迹')
        this.navSlot('mineSelected', '我的')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      Text(this.navigationHint())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    Column() {
      SettingRow({ title: '只显示图标', description: this.ownNavigationActive() ? '底栏不显示文字，图标要能认出是哪个页签' :
        '上传导航图标后可用' }) {
        Toggle({ type: ToggleType.Switch, isOn: this.navLabelsHidden() })
          .enabled(this.ownNavigationActive())
          .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
          .onChange((isOn: boolean) => this.setNavLabelsHidden(isOn))
      }
    }
    .width('100%')
    .opacity(this.ownNavigationActive() ? this.advancedOpacity() : 0.45)
    SettingNavRow({ title: '一次选多个图标', description: '文件名含 bookshelf、explore、listen、footprint、mine 时自动对号',
      showDivider: this.ownNavigationActive(), onTap: () => {
        if (this.advancedLocked()) this.ensureAdvanced();
        else this.uploadNavigation();
      } })
    if (this.ownNavigationActive()) {
      this.resetRow('移除全部上传的导航图标', () => this.clearNavigationAssets())
    }
  }

  navigationHint(): string {
    const missing = ['bookshelf', 'explore', 'mine']
      .filter((key: string): boolean => !this.navSlotValue(key)).length;
    if (this.ownNavigationActive() && missing > 0) {
      return `还差 ${missing} 个普通图标：缺的先用基底主题的图标，传齐三个之前分享导出时不带导航图标`;
    }
    return 'SVG 跟随主题色着色；位图（PNG、WebP、JPG、GIF）保持原色。选中态没给的页签，选中时仍用普通图标。' +
      '“听”“足迹”是可选的第四个页签，不传就用基底主题的图标';
  }

  navLabelsHidden(): boolean {
    const pack = this.ownPack();
    return this.ownNavigationActive() && !!pack && !!pack.record.parts.navigation &&
      pack.record.parts.navigation.labels === 'hidden';
  }

  async setNavLabelsHidden(hidden: boolean): Promise<void> {
    if (hidden === this.navLabelsHidden()) return;
    if (!(await this.ensureAdvanced())) {
      this.assetRevision++;
      return;
    }
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setNavigationLabelsHidden(getContext(this), this.schemeId, hidden), '', false, false,
      hidden ? '底栏改为只显示图标' : '底栏恢复显示文字');
  }

  async tapNavSlot(key: string): Promise<void> {
    if (this.navSlotState(key) === 'own') {
      const choice = await this.slotMenu(SchemeAssetService.navigationLabel(key), '替换', '移除');
      if (choice === 0) {
        await this.replaceGuarded(() => this.uploadNavigationIcon(key));
      } else if (choice === 1) {
        await this.runAssetClear((): Promise<SchemeAssetResult> =>
          SchemeAssetService.clearNavigationIcon(getContext(this), this.schemeId, key), 'navigation');
      }
      return;
    }
    if (!(await this.ensureAdvanced())) return;
    if (key.endsWith('Selected') && !this.navSlotValue(key.replace('Selected', '')) && !this.ownNavigationActive()) {
      HdsFeedback.showToast('先上传普通图标，再给它配选中态');
      return;
    }
    await this.uploadNavigationIcon(key);
  }

  async uploadNavigationIcon(key: string): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setNavigationIcon(getContext(this), this.schemeId, key, uris[0], this.sourceThemeId('navigation')),
      'navigation', true, true, `${SchemeAssetService.navigationLabel(key)}已更新`);
  }

  ownBookActive(): boolean {
    const own = this.ownThemeId();
    const pack = this.ownPack();
    return !!own && !!pack && !!pack.record.parts.book && this.currentSources().bookThemeId === own;
  }

  /** 当前模式自己的那套封面：浅色是 covers，深色是 coversDark（空着表示深色沿用浅色那套）。 */
  ownCoverPaths(): string[] {
    const pack = this.ownPack();
    if (!this.ownBookActive() || !pack || !pack.record.parts.book) return [];
    const book = pack.record.parts.book;
    return (this.selectedMode === 'dark' ? (book.coversDark || []) : book.covers).slice();
  }

  /** 当前模式没有自己的封面时淡显的几张：另一个模式上传的那套，或来源主题的封面。 */
  inheritedCovers(): ResourceStr[] {
    return ThemeAssetRegistry.themeBookCovers(this.customPreviewTheme().book.coverAssetId,
      this.selectedMode === 'dark').slice(0, 4);
  }

  /** 当前模式没有自己的封面、正借用另一个模式上传的那套。 */
  borrowsOtherModeCovers(): boolean {
    if (!this.ownBookActive() || this.ownCoverPaths().length > 0) return false;
    return SchemeAssetService.coverCount(this.ownPackageId, this.selectedMode !== 'dark') > 0;
  }

  coverHint(): string {
    if (this.ownCoverPaths().length > 0) {
      return this.selectedMode === 'dark' ?
        '和浅色封面张数相同、顺序对应时，同一本书切换深浅色还是同一幅画' : '';
    }
    if (this.borrowsOtherModeCovers()) {
      return this.selectedMode === 'dark' ? '深色模式沿用浅色那套封面；在这里添加后，深色单独用一套' :
        '浅色还没有自己的封面，暂用深色那套';
    }
    if (this.inheritedCovers().length === 0) return '';
    return `淡显的是「${BuiltinThemeRegistry.findById(this.sourceThemeId('book')).name}」的封面，上传后换成自己的`;
  }

  @Builder
  bookSlots() {
    Column({ space: AppSpacing.SM }) {
      Row() {
        Text(`封面 · ${this.modeLabel()} ${this.ownCoverPaths().length} / ${ThemePackageLimits.MAX_COVERS}`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(this.ownCoverPaths().length > 0 ? '长按拖动调整轮播顺序' : '450 × 660，上传后先取景')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      List({ space: AppSpacing.MD }) {
        if (this.ownCoverPaths().length > 0) {
          ForEach(this.ownCoverPaths(), (path: string, index: number) => {
            ListItem() {
              this.coverTile({ index: index, uri: this.ownAssetUri(path) })
            }
          }, (path: string, index: number) => `cover_${this.selectedMode}_${index}_${path}_${this.assetRevision}`)
            .onMove((from: number, to: number) => {
              this.moveCover(from, to);
            })
        } else {
          ForEach(this.inheritedCovers(), (cover: ResourceStr, index: number) => {
            ListItem() {
              Image(cover)
                .width(50)
                .height(74)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .opacity(0.5)
                .draggable(false)
            }
          }, (_cover: ResourceStr, index: number) =>
            `inherited_cover_${this.selectedMode}_${index}_${this.assetRevision}`)
        }
        if (this.ownCoverPaths().length < ThemePackageLimits.MAX_COVERS) {
          ListItem() {
            this.addTile(50, 74, '添加封面', () => {
              if (this.advancedLocked()) this.ensureAdvanced();
              else this.uploadCovers();
            })
          }
        }
      }
      .listDirection(Axis.Horizontal)
      .width('100%')
      .height(84)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      if (this.coverHint()) {
        Text(this.coverHint())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
      }
      Row({ space: AppSpacing.XL }) {
        this.assetSlot({ label: '书架边框', image: this.shelfFrameImage(), state: this.shelfPartState(false),
          slotWidth: 50, slotHeight: 74, untinted: true, onTap: () => this.tapShelfPart(false) })
        this.assetSlot({ label: '分组文件夹', image: this.shelfFolderImage(),
          state: this.shelfPartState(true), slotWidth: 50, slotHeight: 74, onTap: () => this.tapShelfPart(true),
          crop: ThemeAssetRegistry.imageCrop(ThemeImageSlots.FOLDER, this.shelfFolderImage(),
            this.selectedMode === 'dark') })
        Text(this.shelfPartHint())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: AppSpacing.MD })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    if (this.selectedMode === 'dark' && this.ownCoverPaths().length > 0) {
      this.resetRow('移除深色封面，沿用浅色那套', () => this.clearDarkCovers())
    }
    if (this.ownBookActive()) {
      this.resetRow('移除全部上传的书籍素材', () => this.clearBookAssets())
    }
  }

  @Builder
  coverTile($$: CoverTileOptions) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (ThemeAssetRegistry.imageCrop(ThemeImageSlots.COVER, $$.uri, this.selectedMode === 'dark')) {
        ThemeCroppedImage({ src: $$.uri,
          crop: ThemeAssetRegistry.imageCrop(ThemeImageSlots.COVER, $$.uri,
            this.selectedMode === 'dark') as ThemeImageCrop })
          .width('100%')
          .height('100%')
      } else {
        Image($$.uri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      }
      Text(`${$$.index + 1}`)
        .fontSize(AppFontSize.MICRO)
        .fontColor('#FFFFFF')
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
        .borderRadius(6)
        .backgroundColor('#73000000')
        .margin(AppSpacing.XXS)
    }
    .width(50)
    .height(74)
    .borderRadius(8)
    .clip(true)
    .accessibilityText(`第 ${$$.index + 1} 张封面`)
    .opacity(ListDissolve.opacity(this.isCoverDissolving($$.index)))
    .scale(ListDissolve.scale(this.isCoverDissolving($$.index)))
    .blur(ListDissolve.blur(this.isCoverDissolving($$.index)))
    .hitTestBehavior(this.isCoverDissolving($$.index) ? HitTestMode.None : HitTestMode.Default)
    .id(this.coverTileElementId(this.coverTileKey(this.selectedMode === 'dark' ? 'dark' : 'light', $$.index)))
    .onClick(() => this.tapCover($$.index))
  }

  /** 当前所选模式下的书架边框：深色没有自己那张时就是浅色的（反过来也一样）。 */
  shelfFrameImage(): ResourceStr {
    const id = this.customPreviewTheme().book.shelfFrameAssetId;
    return id ? ThemeAssetRegistry.themeShelfFrame(id, this.selectedMode === 'dark') : '';
  }

  /** 方案自己上传的、属于当前模式的那张书架边框（包内相对路径）。 */
  ownShelfFramePath(): string {
    const pack = this.ownPack();
    const book = pack ? pack.record.parts.book : null;
    if (!this.ownBookActive() || !book) return '';
    return (this.selectedMode === 'dark' ? book.shelfFrameDark : book.shelfFrame) || '';
  }

  /** 当前所选模式下的文件夹插画：深色没有自己那张时就是浅色的（反过来也一样）。 */
  shelfFolderImage(): ResourceStr {
    const id = this.customPreviewTheme().book.shelfFolderAssetId;
    return id ? ThemeAssetRegistry.themeShelfFolder(id, this.selectedMode === 'dark') : '';
  }

  /** 方案自己上传的、属于当前模式的那张文件夹插画（包内相对路径）。 */
  ownShelfFolderPath(): string {
    const pack = this.ownPack();
    const book = pack ? pack.record.parts.book : null;
    if (!this.ownBookActive() || !book) return '';
    return (this.selectedMode === 'dark' ? book.shelfFolderDark : book.shelfFolder) || '';
  }

  shelfPartState(folder: boolean): string {
    const pack = this.ownPack();
    const book = pack ? pack.record.parts.book : null;
    if (folder ? !!this.ownShelfFolderPath() : !!this.ownShelfFramePath()) return 'own';
    return ThemeColorSettingsPage.hasImage(folder ? this.shelfFolderImage() : this.shelfFrameImage()) ? 'inherit' : 'empty';
  }

  shelfPartHint(): string {
    const base = '边框是 SVG 或透明底位图，与封面同比例、中心透明；文件夹是 450 × 660 位图';
    // 格子很窄，放不下“浅色 / 深色”，哪种模式用哪张写在这段说明里。
    if (this.selectedMode !== 'dark') return `${base}，切到深色可以各再传一张只在深色模式用的`;
    const frame = this.ownShelfFramePath() ? '边框用单独上传的这张' : '边框沿用浅色那张';
    const folder = this.ownShelfFolderPath() ? '文件夹图用单独上传的这张' : '文件夹图沿用浅色那张';
    return `${base}。深色模式${frame}，${folder}`;
  }

  async tapShelfPart(folder: boolean): Promise<void> {
    if (this.shelfPartState(folder) !== 'own') {
      if (!(await this.ensureAdvanced())) return;
      if (folder) await this.uploadShelfFolder();
      else await this.uploadShelfFrame();
      return;
    }
    // 菜单期间用户可能切换浅色/深色，文件夹插画操作的是点开时那个模式的那张。
    const dark = this.selectedMode === 'dark';
    const choice = await this.slotMenu(`${dark ? '深色' : '浅色'} · ${folder ? '分组文件夹' : '书架边框'}`, '替换',
      dark ? '移除，沿用浅色那张' : '移除');
    if (choice === 0) {
      await this.replaceGuarded(() => folder ? this.uploadShelfFolder(dark) : this.uploadShelfFrame(dark));
    } else if (choice === 1) {
      await this.runAssetClear((): Promise<SchemeAssetResult> => folder ?
        SchemeAssetService.clearShelfFolder(getContext(this), this.schemeId, dark) :
        SchemeAssetService.clearShelfFrame(getContext(this), this.schemeId, dark), 'book');
    }
  }

  async tapCover(index: number): Promise<void> {
    // 菜单和取景期间用户可能切换浅色/深色，操作的那套封面以点开时为准。
    const dark = this.selectedMode === 'dark';
    const name = `${dark ? '深色' : '浅色'} · 第 ${index + 1} 张封面`;
    const choice = index > 0 ?
      await this.slotMenu(name, '替换这张', '移到第一张', '删除这张') :
      await this.slotMenu(name, '替换这张', '删除这张');
    const action = index > 0 ? choice : (choice === 1 ? 2 : choice);
    if (action === 0) {
      if (!(await this.ensureAdvanced())) return;
      const uris = await SchemeAssetService.pickImages(getContext(this), 1);
      if (uris.length === 0) return;
      const framed = await this.frameImage(uris[0], '封面取景', 450, 660, 450, false);
      if (!framed) return;
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.replaceCover(getContext(this), this.schemeId, index, framed.path, framed.crop, dark),
        'book', true, true, '封面已替换');
      this.discardCropFile(framed.path, uris[0]);
    } else if (action === 1) {
      await this.moveCover(index, 0, dark);
    } else if (action === 2) {
      // 这张封面先散成颗粒（颜色取封面主色，等操作菜单退场再开始），再从方案里删掉；删完整排封面会重建。
      const keys = [this.coverTileKey(dark ? 'dark' : 'light', index)];
      const ui = this.getUIContext();
      const colors = await DeleteParticles.pickColors(ui, this.coverTileElementId(keys[0]),
        [this.currentAccentColor(), this.primaryTextColor(), this.subTextColor()]);
      await ListDissolve.fadeOut(ui, keys, (key: string) => {
        this.dissolvingCoverKeys = [...this.dissolvingCoverKeys, key];
      }, ListDissolve.particles('theme_color_settings_root', colors,
        (key: string): string => this.coverTileElementId(key), (): DeleteParticleBurst[] => this.deleteParticleBursts,
        (bursts: DeleteParticleBurst[]): void => { this.deleteParticleBursts = bursts; }), ListDissolve.AFTER_DIALOG_MS);
      await this.runAssetClear((): Promise<SchemeAssetResult> =>
        SchemeAssetService.removeCover(getContext(this), this.schemeId, index, dark), 'book');
      setTimeout(() => {
        this.dissolvingCoverKeys = ListDissolve.without(this.dissolvingCoverKeys, keys);
      }, ListDissolve.CLEAR_DELAY_MS);
    }
  }

  coverTileKey(mode: string, index: number): string {
    return `${mode}_${index}`;
  }

  coverTileElementId(key: string): string {
    return `theme_cover_tile_${key}`;
  }

  isCoverDissolving(index: number): boolean {
    return this.dissolvingCoverKeys.length > 0 &&
      this.dissolvingCoverKeys.indexOf(this.coverTileKey(this.selectedMode === 'dark' ? 'dark' : 'light', index)) >= 0;
  }

  async moveCover(from: number, to: number, dark: boolean = this.selectedMode === 'dark'): Promise<void> {
    if (from === to) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.moveCover(getContext(this), this.schemeId, from, to, dark), '', false, false, '');
  }

  async clearDarkCovers(): Promise<void> {
    await this.runAssetClear((): Promise<SchemeAssetResult> =>
      SchemeAssetService.clearDarkCovers(getContext(this), this.schemeId), 'book');
  }

  ownHomeBackdrop(): boolean {
    const own = this.ownThemeId();
    const pack = this.ownPack();
    return !!own && !!pack && !!pack.homeBackdrop(this.selectedMode === 'dark') &&
      this.currentSources().homeBackdropThemeId === own;
  }

  homeBackdropImage(): ResourceStr {
    const image = ThemeAssetRegistry.homeBackdrop(this.currentSources().homeBackdropThemeId, this.selectedMode === 'dark');
    return image === null ? '' : image;
  }

  /** 方案自己给这种书架布局、当前模式单独传了背景，且“首页背景”来源指着方案自己的素材包。 */
  ownShelfBackdrop(layout: string): boolean {
    const own = this.ownThemeId();
    return !!own && this.currentSources().homeBackdropThemeId === own &&
      SchemeAssetService.hasShelfBackdrop(this.ownPackageId, layout, this.selectedMode === 'dark');
  }

  /** 书架用这种布局时实际显示的背景：专属那张，没有就是通用那张。 */
  shelfBackdropImage(layout: string): ResourceStr {
    const image = ThemeAssetRegistry.homeBackdrop(this.currentSources().homeBackdropThemeId,
      this.selectedMode === 'dark', layout);
    return image === null ? '' : image;
  }

  shelfBackdropState(layout: string): string {
    if (this.ownShelfBackdrop(layout)) return 'own';
    return ThemeColorSettingsPage.hasImage(this.shelfBackdropImage(layout)) ? 'inherit' : 'empty';
  }

  @Builder
  shelfBackdropSlot(layout: string, label: string) {
    this.assetSlot({ label: label, image: this.shelfBackdropImage(layout), state: this.shelfBackdropState(layout),
      slotWidth: 52, slotHeight: 65, onTap: () => this.tapShelfBackdrop(layout),
      crop: ThemeAssetRegistry.imageCrop(ThemeImageSlots.BACKDROP, this.shelfBackdropImage(layout),
        this.selectedMode === 'dark', layout) })
  }

  @Builder
  homeBackdropSlot() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.XL }) {
        this.assetSlot({ label: '通用 4 : 5', image: this.homeBackdropImage(),
          state: this.ownHomeBackdrop() ? 'own' : (ThemeColorSettingsPage.hasImage(this.homeBackdropImage()) ? 'inherit' : 'empty'),
          slotWidth: 64, slotHeight: 80, onTap: () => this.tapHomeBackdrop(),
          crop: ThemeAssetRegistry.imageCrop(ThemeImageSlots.BACKDROP, this.homeBackdropImage(), this.selectedMode === 'dark') })
        Text('书架、发现和我的页顶部共用，画面放上半部分，向下自动淡成页面底色。浅色、深色各一张，互不借用')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      Text('按书架布局 · 可选')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      Row() {
        this.shelfBackdropSlot(SHELF_BACKDROP_LAYOUTS[0], SHELF_BACKDROP_LAYOUT_NAMES[0])
        this.shelfBackdropSlot(SHELF_BACKDROP_LAYOUTS[1], SHELF_BACKDROP_LAYOUT_NAMES[1])
        this.shelfBackdropSlot(SHELF_BACKDROP_LAYOUTS[2], SHELF_BACKDROP_LAYOUT_NAMES[2])
        this.shelfBackdropSlot(SHELF_BACKDROP_LAYOUTS[3], SHELF_BACKDROP_LAYOUT_NAMES[3])
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      Text('只在书架页生效：书架用哪种布局就显示哪一张，没单独上传的布局用上面那张通用背景')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
  }

  shelfLayoutName(layout: string): string {
    return SHELF_BACKDROP_LAYOUT_NAMES[SHELF_BACKDROP_LAYOUTS.indexOf(layout)] || '';
  }

  async tapShelfBackdrop(layout: string): Promise<void> {
    // 菜单、选图和取景期间用户可能切换浅色/深色，操作的是点开时那个模式的那张。
    const dark = this.selectedMode === 'dark';
    const name = this.shelfLayoutName(layout);
    if (!this.ownShelfBackdrop(layout)) {
      if (!(await this.ensureAdvanced())) return;
      await this.uploadHomeBackdrop(layout, dark);
      return;
    }
    const choice = await this.slotMenu(`${dark ? '深色' : '浅色'} · ${name}布局背景`, '替换', '其他布局也用这张',
      '移除，沿用通用背景');
    if (choice === 0) {
      await this.replaceGuarded(() => this.uploadHomeBackdrop(layout, dark));
    } else if (choice === 1) {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.copyShelfBackdropToOtherLayouts(getContext(this), this.schemeId, layout, dark),
        'homeBackdrop', !dark, dark, `四种布局的${dark ? '深色' : '浅色'}书架背景已换成同一张`);
    } else if (choice === 2) {
      await this.clearHomeBackdrop(layout, dark);
    }
  }

  async tapHomeBackdrop(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const other = dark ? '浅色' : '深色';
    if (!this.ownHomeBackdrop()) {
      if (!(await this.ensureAdvanced())) return;
      await this.uploadHomeBackdrop();
      return;
    }
    const choice = await this.slotMenu(`${this.modeLabel()} · 首页背景`, '替换', `${other}模式也用这张`, '移除');
    if (choice === 0) {
      await this.replaceGuarded(() => this.uploadHomeBackdrop());
    } else if (choice === 1) {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.copyToOtherMode(getContext(this), this.schemeId, 'homeBackdrop', dark),
        'homeBackdrop', dark, !dark, `${other}模式的首页背景已换成同一张`);
    } else if (choice === 2) {
      await this.clearHomeBackdrop();
    }
  }

  // ---- 页签：封面与信息 ----

  startupSlotImage(): ResourceStr {
    const path = this.currentStartupImagePath();
    if (path) return path;
    return ThemeAssetRegistry.startupBackground(this.currentSources().startupThemeId, this.selectedMode === 'dark');
  }

  async tapStartupSlot(): Promise<void> {
    if (!this.currentStartupImagePath()) {
      await this.chooseStartupImage();
      return;
    }
    const choice = await this.slotMenu(`${this.modeLabel()} · 启动封面`, '替换', '移除，恢复为所选主题的封面');
    if (choice === 0) await this.chooseStartupImage();
    else if (choice === 1) await this.resetStartupImage();
  }

  @Builder
  startupTextInputs() {
    Column({ space: AppSpacing.SM }) {
      Text('主标题')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      TextInput({ placeholder: '可留空', text: this.currentStartupTitle() })
        .width('100%')
        .height(42)
        .maxLength(24)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => this.setCurrentStartupTitle(value))
      Text('副标题')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ top: AppSpacing.SM })
      TextInput({ placeholder: '可留空', text: this.currentStartupSubtitle() })
        .width('100%')
        .height(42)
        .maxLength(48)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => this.setCurrentStartupSubtitle(value))
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.LG })
    .alignItems(HorizontalAlign.Start)
  }

  ownLogo(): boolean {
    const pack = this.ownPack();
    return !!pack && !!pack.record.parts.logo;
  }

  @Builder
  brandSlots() {
    Row({ space: AppSpacing.XL }) {
      this.assetSlot({ label: '主题标识', image: this.ownLogo() ? (this.ownPack()?.logo || '') : '',
        state: this.ownLogo() ? 'own' : 'empty', slotWidth: 56, slotHeight: 56, icon: true,
        onTap: () => this.tapLogo() })
      this.assetSlot({ label: '预览图 3 : 4', image: this.previewImagePath,
        state: this.previewImagePath ? 'own' : 'empty', slotWidth: 54, slotHeight: 72,
        onTap: () => this.tapPreviewImage() })
      Text('标识是卡片右上角和详情页名字旁的小图（正方形 SVG 或透明底位图）。没有预览图时卡片显示启动封面')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
  }

  async tapLogo(): Promise<void> {
    if (this.ownLogo()) {
      const choice = await this.slotMenu('主题标识', '替换', '移除');
      if (choice === 0) await this.replaceGuarded(() => this.uploadLogo());
      else if (choice === 1) {
        await this.runAssetClear((): Promise<SchemeAssetResult> =>
          SchemeAssetService.clearLogo(getContext(this), this.schemeId), '');
      }
      return;
    }
    if (!(await this.ensureAdvanced())) return;
    await this.uploadLogo();
  }

  async uploadLogo(): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setLogo(getContext(this), this.schemeId, uris[0], this.sourceThemeId('startup')),
      '', false, false, '主题标识已更新');
  }

  async tapPreviewImage(): Promise<void> {
    if (!this.previewImagePath) {
      await this.choosePreviewImage();
      return;
    }
    const choice = await this.slotMenu('方案预览图', '替换', '移除，改用启动封面');
    if (choice === 0) await this.choosePreviewImage();
    else if (choice === 1) await this.resetPreviewImage();
  }

  @Builder
  infoInputs() {
    Column({ space: AppSpacing.SM }) {
      Text('名称')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      TextInput({ placeholder: '方案名称', text: this.nameDraft })
        .width('100%')
        .height(42)
        .maxLength(ThemePackageLimits.MAX_NAME_LENGTH)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.nameDraft = value;
        })
        .onSubmit(() => this.commitName())
        .onBlur(() => this.commitName())
      Text('作者')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ top: AppSpacing.SM })
      TextInput({ placeholder: '可留空；分享导出时作为署名', text: this.schemeAuthor })
        .width('100%')
        .height(42)
        .maxLength(ThemePackageLimits.MAX_AUTHOR_LENGTH)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.schemeAuthor = value;
        })
        .onBlur(() => this.saveInfo())
      Text('说明')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ top: AppSpacing.SM })
      TextArea({ placeholder: '一两句话介绍这套主题，最多 120 字', text: this.schemeDescription })
        .width('100%')
        .height(88)
        .maxLength(ThemePackageLimits.MAX_DESCRIPTION_LENGTH)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.schemeDescription = value;
        })
        .onBlur(() => this.saveInfo())
      Text('分享导出时自动带上，导入的人在预览里能看到作者和说明')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ top: AppSpacing.XS })
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .alignItems(HorizontalAlign.Start)
  }

  async commitName(): Promise<void> {
    const name = this.nameDraft.trim();
    if (!name || name === this.schemeName) {
      this.nameDraft = this.schemeName;
      return;
    }
    try {
      const appSettings = await AppThemeSettingsStore.load(getContext(this));
      const renamed = await CustomThemeSchemeStore.rename(getContext(this), appSettings, this.schemeId, name);
      if (renamed) {
        this.schemeName = name;
      } else {
        this.nameDraft = this.schemeName;
        HdsFeedback.showToast('已有同名方案，换个名字吧');
      }
    } catch (e) {
      console.warn('重命名方案失败:', e);
      this.nameDraft = this.schemeName;
    }
  }

  async saveInfo(): Promise<void> {
    try {
      const appSettings = await AppThemeSettingsStore.load(getContext(this));
      await CustomThemeSchemeStore.updateInfo(getContext(this), appSettings, this.schemeId,
        this.schemeAuthor.trim(), this.schemeDescription.trim());
    } catch (e) {
      console.warn('保存方案信息失败:', e);
    }
  }

  // ---- 素材槽 ----

  ownPack(): InstalledThemePack | null {
    // 主题包记录不是状态变量：读 assetRevision，只移掉包里某一项（包和来源都没变）时格子也会重新取值。
    if (this.assetRevision < 0) return null;
    return this.ownPackageId ? ThemePackRegistry.getByPackageId(this.ownPackageId) : null;
  }

  ownAssetUri(relativePath: string): string {
    const pack = this.ownPack();
    if (!pack || !relativePath.startsWith('assets/') || relativePath.includes('..')) return '';
    return fileUri.getUriFromPath(`${pack.dir}/${relativePath}`);
  }

  static hasImage(value: ResourceStr): boolean {
    return typeof value !== 'string' || value.length > 0;
  }

  /** 按引用传参（对象字面量），上传后的状态才会刷新（见“按值 @Builder 的下拉不刷新”）。 */
  @Builder
  assetSlot($$: AssetSlotOptions) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if ($$.state !== 'empty' && ThemeColorSettingsPage.hasImage($$.image) && $$.crop) {
          ThemeCroppedImage({ src: $$.image, crop: $$.crop as ThemeImageCrop })
            .width('100%')
            .height('100%')
            .opacity($$.state === 'own' ? 1 : 0.5)
        } else if ($$.state !== 'empty' && ThemeColorSettingsPage.hasImage($$.image) && $$.untinted) {
          Image($$.image)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .rotate({ angle: $$.rotation || 0 })
            .opacity($$.state === 'own' ? 1 : 0.5)
            .draggable(false)
        } else if ($$.state !== 'empty' && ThemeColorSettingsPage.hasImage($$.image)) {
          Image($$.image)
            .width($$.icon ? '60%' : '100%')
            .height($$.icon ? '60%' : '100%')
            .objectFit($$.icon ? ImageFit.Contain : ImageFit.Cover)
            .fillColor(this.primaryTextColor())
            .rotate({ angle: $$.rotation || 0 })
            .opacity($$.state === 'own' ? 1 : 0.5)
            .draggable(false)
        } else {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([this.subTextColor()])
        }
        if ($$.state === 'own') {
          Text('自传')
            .fontSize(9)
            .fontColor(ThemeRuntime.onAccentColor())
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
            .borderRadius(5)
            .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode))
            .margin(AppSpacing.XXS)
        } else if ($$.state === 'inherit' && ThemeColorSettingsPage.hasImage($$.image)) {
          Text('跟随')
            .fontSize(9)
            .fontColor(this.subTextColor())
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
            .borderRadius(5)
            .backgroundColor(this.cardColor())
            .margin(AppSpacing.XXS)
        }
      }
      .width($$.slotWidth)
      .height($$.slotHeight)
      .align(Alignment.Center)
      .borderRadius(12)
      .clip(true)
      .backgroundColor(this.inputColor())
      .border($$.state === 'empty' || !ThemeColorSettingsPage.hasImage($$.image) ?
        { width: 1.5, color: this.subTextColor(), style: BorderStyle.Dashed } : { width: 0 })
      Text($$.label)
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
        .maxLines(1)
    }
    .accessibilityText(`${$$.label}，${$$.state === 'own' ? '已上传，点按替换或移除' : '点按上传'}`)
    .onClick(() => $$.onTap())
  }

  @Builder
  addTile(tileWidth: number, tileHeight: number, label: string, onTap: () => void) {
    Stack() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(20)
        .fontColor([this.subTextColor()])
    }
    .width(tileWidth)
    .height(tileHeight)
    .borderRadius(8)
    .border({ width: 1.5, color: this.subTextColor(), style: BorderStyle.Dashed })
    .accessibilityText(label)
    .onClick(() => onTap())
  }

  /** 系统操作菜单，返回按钮序号；取消返回 -1。最后一项是移除类操作时用危险色。 */
  async slotMenu(title: string, first: string, second: string, third: string = ''): Promise<number> {
    const a: promptAction.Button = { text: first, color: this.menuColor(first) };
    const b: promptAction.Button = { text: second, color: this.menuColor(second) };
    const c: promptAction.Button = { text: third, color: this.menuColor(third) };
    try {
      const result: promptAction.ActionMenuSuccessResponse = await this.getUIContext().getPromptAction().showActionMenu({
        title: title,
        buttons: third ? [a, b, c] : [a, b]
      });
      return result.index;
    } catch (_) {
      return -1;
    }
  }

  menuColor(label: string): string {
    return label.startsWith('移除') || label.startsWith('删除') ? ThemeRuntime.dangerColor(this.appDarkMode) :
      this.primaryTextColor();
  }

  async replaceGuarded(action: () => Promise<void>): Promise<void> {
    if (!(await this.ensureAdvanced())) return;
    await action();
  }

  // ---- 取景 ----

  /**
   * 打开取景层，返回裁好的文件路径；选“用原图”返回原 URI，取消返回空串。
   * areaOnly 时不裁文件、返回原 URI，框住的区域放在 cropArea。
   */
  cropImage(uri: string, title: string, ratioWidth: number, ratioHeight: number, maxWidth: number, png: boolean,
    index: number = 0, total: number = 1, areaOnly: boolean = false): Promise<string> {
    return new Promise<string>((resolve: (result: string) => void) => {
      const request = new ThemeCropRequest();
      request.uri = uri;
      request.title = title;
      request.ratioWidth = ratioWidth;
      request.ratioHeight = ratioHeight;
      request.maxWidth = maxWidth;
      request.png = png;
      request.index = index;
      request.total = total;
      request.areaOnly = areaOnly;
      this.cropResolve = resolve;
      this.cropRequest = request;
      this.cropVisible = true;
    });
  }

  /**
   * 素材位取景。静图裁成新文件；动图文件原样使用，取景只记下显示区域（重新编码会只剩第一帧），
   * 超过播放上限的动图拒收。取消或拒收时返回 null。
   */
  async frameImage(uri: string, title: string, ratioWidth: number, ratioHeight: number, maxWidth: number,
    png: boolean, index: number = 0, total: number = 1): Promise<FramedImage | null> {
    const oversize = await AnimatedImagePolicy.oversizeAnimatedMessage(uri);
    if (oversize) {
      HdsFeedback.showToast(oversize);
      return null;
    }
    const animated = await AnimatedImagePolicy.isAnimated(uri);
    this.cropArea = null;
    const path = await this.cropImage(uri, title, ratioWidth, ratioHeight, maxWidth, png, index, total, animated);
    const crop = this.cropArea;
    this.cropArea = null;
    if (!path) return null;
    const result = new FramedImage();
    result.path = path;
    result.crop = animated ? crop : null;
    return result;
  }

  finishCrop(result: string): void {
    const resolve = this.cropResolve;
    this.cropResolve = null;
    this.cropVisible = false;
    if (resolve) resolve(result);
  }

  /** 取景生成的缓存文件收进素材包后就没用了。 */
  discardCropFile(path: string, original: string): void {
    if (!path || path === original || !path.startsWith(getContext(this).cacheDir)) return;
    try {
      fs.unlinkSync(path);
    } catch (_) {
    }
  }

  // ---- 建议 ----

  static luminance(color: string): number {
    const hex = (color || '').replace('#', '');
    const rgb = hex.length >= 6 ? hex.substring(hex.length - 6) : '000000';
    const channel = (offset: number): number => {
      const value = parseInt(rgb.substring(offset, offset + 2), 16) / 255;
      return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * channel(0) + 0.7152 * channel(2) + 0.0722 * channel(4);
  }

  static contrast(foreground: string, background: string): number {
    const a = ThemeColorSettingsPage.luminance(foreground);
    const b = ThemeColorSettingsPage.luminance(background);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  }

  /** 颜色类建议（两种模式都查）加上异步算好的素材尺寸建议。 */
  editorIssues(): ThemeEditorIssue[] {
    const issues: ThemeEditorIssue[] = [];
    const settings = this.settingsFromState();
    for (const dark of [false, true]) {
      const label = dark ? '深色' : '浅色';
      const theme = AppThemeSettingsStore.customTheme(settings, dark);
      const colors = dark ? theme.dark.colors : theme.light.colors;
      const reader = dark ? this.darkReader : this.lightReader;
      const add = (text: string, detail: string, section: string, group: string, swatch: string): void => {
        const issue = new ThemeEditorIssue();
        issue.text = `${label} · ${text}`;
        issue.detail = detail;
        issue.section = section;
        issue.group = group;
        issue.mode = dark ? 'dark' : 'light';
        issue.swatch = swatch;
        issues.push(issue);
      };
      const body = ThemeColorSettingsPage.contrast(reader.textColor, reader.backgroundColor);
      if (body < 4.5) add(`正文与阅读底色对比 ${body.toFixed(1)}`, '低于 4.5，长时间读会累', 'reader', 'reader', reader.textColor);
      const header = ThemeColorSettingsPage.contrast(reader.subTextColor, reader.backgroundColor);
      if (header < 3) add(`页眉页脚与阅读底色对比 ${header.toFixed(1)}`, '低于 3，页码和时间可能看不清', 'reader', 'reader', reader.subTextColor);
      const primary = ThemeColorSettingsPage.contrast(colors.primaryTextColor, colors.pageColor);
      if (primary < 4.5) add(`主文字与页面对比 ${primary.toFixed(1)}`, '低于 4.5，列表文字不够清楚', 'global', 'palette', colors.primaryTextColor);
      const sub = ThemeColorSettingsPage.contrast(colors.subTextColor, colors.pageColor);
      if (sub < 3) add(`辅助文字与页面对比 ${sub.toFixed(1)}`, '低于 3，说明文字可能看不清', 'global', 'palette', colors.subTextColor);
    }
    if (this.ownNavigationActive()) {
      const missing = ['bookshelf', 'explore', 'mine'].filter((key: string): boolean => !this.navSlotValue(key));
      if (missing.length > 0) {
        const issue = new ThemeEditorIssue();
        issue.text = `导航图标还差 ${missing.length} 个`;
        issue.detail = '缺的先用基底主题的图标，传齐之前分享导出时不带导航图标';
        issue.section = 'shelf';
        issue.group = 'navigation';
        issues.push(issue);
      }
    }
    for (const issue of this.assetIssues) issues.push(issue);
    return issues;
  }

  /** 读方案自传位图的实际尺寸，比素材槽要求小太多时提醒（高分屏上会发虚）。 */
  async refreshAssetIssues(): Promise<void> {
    const pack = this.ownPack();
    const issues: ThemeEditorIssue[] = [];
    if (pack) {
      const parts = pack.record.parts;
      const check = async (relativePath: string, label: string, minWidth: number, minHeight: number,
        section: string, group: string): Promise<void> => {
        if (!relativePath || relativePath.endsWith('.svg')) return;
        const size = await ThemeColorSettingsPage.imageSize(`${pack.dir}/${relativePath}`);
        if (size.length < 2 || (size[0] >= minWidth * 0.75 && size[1] >= minHeight * 0.75)) return;
        const issue = new ThemeEditorIssue();
        issue.text = `${label}只有 ${size[0]} × ${size[1]}`;
        issue.detail = `小于 ${minWidth} × ${minHeight}，屏幕上会发虚`;
        issue.section = section;
        issue.group = group;
        issues.push(issue);
      };
      if (parts.book) {
        for (let index = 0; index < parts.book.covers.length; index++) {
          await check(parts.book.covers[index], `第 ${index + 1} 张封面`, 450, 660, 'shelf', 'book');
        }
        const darkCovers = parts.book.coversDark || [];
        for (let index = 0; index < darkCovers.length; index++) {
          await check(darkCovers[index], `深色第 ${index + 1} 张封面`, 450, 660, 'shelf', 'book');
        }
        await check(parts.book.shelfFolder, '文件夹插画', 450, 660, 'shelf', 'book');
        await check(parts.book.shelfFolderDark || '', '深色文件夹插画', 450, 660, 'shelf', 'book');
      }
      await check(parts.homeBackdropLight, '浅色首页背景', 1080, 1350, 'shelf', 'homeBackdrop');
      await check(parts.homeBackdropDark, '深色首页背景', 1080, 1350, 'shelf', 'homeBackdrop');
      for (const item of parts.shelfBackdrops || []) {
        const name = this.shelfLayoutName(item.layout);
        await check(item.light, `浅色${name}布局书架背景`, 1080, 1350, 'shelf', 'homeBackdrop');
        await check(item.dark, `深色${name}布局书架背景`, 1080, 1350, 'shelf', 'homeBackdrop');
      }
      if (parts.ttsPanelLight) await check(parts.ttsPanelLight.artwork, '浅色面板插画', 720, 520, 'other', 'ttsPanel');
      if (parts.ttsPanelDark) await check(parts.ttsPanelDark.artwork, '深色面板插画', 720, 520, 'other', 'ttsPanel');
    }
    this.assetIssues = issues;
  }

  static async imageSize(path: string): Promise<number[]> {
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(path);
      const info = await source.getImageInfo();
      return [info.size.width, info.size.height];
    } catch (_) {
      return [];
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (_) {
        }
      }
    }
  }

  warnSurface(): string {
    return this.appDarkMode ? '#3A2A12' : '#FFF4E5';
  }

  warnText(): string {
    return this.appDarkMode ? '#FFC67A' : '#7A4300';
  }

  /** 建议清单：点预览标题行的角标后出现在列表顶部，点某条跳到对应页签并展开那一组。 */
  @Builder
  issuesList() {
    if (this.editorIssues().length > 0) {
      Column() {
        Row({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(16)
            .fontColor([this.warnText()])
          Text(`${this.editorIssues().length} 项建议 · 只做提醒，不影响保存`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.warnText())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_up'))
            .fontSize(14)
            .fontColor([this.warnText()])
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
        .accessibilityText('收起建议')
        .onClick(() => {
          this.checksExpanded = false;
        })
        ForEach(this.editorIssues(), (issue: ThemeEditorIssue) => {
          Row({ space: AppSpacing.MD }) {
            if (issue.swatch) {
              Column()
                .width(18)
                .height(18)
                .borderRadius(5)
                .backgroundColor(issue.swatch)
                .border({ width: 1, color: '#22000000' })
            }
            Column({ space: AppSpacing.XXS }) {
              Text(issue.text)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.primaryTextColor())
              Text(issue.detail)
                .fontSize(AppFontSize.MICRO)
                .fontColor(this.warnText())
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('去看看')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
          }
          .width('100%')
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
          .onClick(() => this.openIssue(issue))
        }, (issue: ThemeEditorIssue) => issue.text)
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
      .padding({ bottom: AppSpacing.SM })
      .borderRadius(ThemeRuntime.cardRadius())
      .backgroundColor(this.warnSurface())
      .clip(true)
    }
  }

  /** 预览标题行里的建议角标。 */
  @Builder
  issuesBadge() {
    if (this.editorReady && this.editorIssues().length > 0) {
      Text(`${this.editorIssues().length} 项建议`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.warnText())
        .height(28)
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
        .borderRadius(14)
        .backgroundColor(this.warnSurface())
        .margin({ right: AppSpacing.SM })
        .accessibilityText(`${this.editorIssues().length} 项建议，点按${this.checksExpanded ? '收起' : '查看'}`)
        .onClick(() => {
          this.checksExpanded = !this.checksExpanded;
          if (this.checksExpanded) this.editorScroller.scrollTo({ xOffset: 0, yOffset: 0 });
        })
    }
  }

  @Builder
  componentSourceRow(category: string, title: string = '取自') {
    SettingRow({ title: title }) {
      Select(this.themeOptions())
        .id(`theme_editor_source_${category}`)
        .width('44%')
        .selected(this.sourceSelectedIndex(category))
        .value(BuiltinThemeRegistry.findById(this.sourceThemeId(category)).name)
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => {
          if (index >= 0 && index < this.availableThemes.length) {
            this.setComponentSource(category, this.availableThemes[index].id);
          }
        })
    }
  }

  @Builder
  colorOptions() {
    if (this.selectedMode === 'dark') {
      ThemeColorOption({
        title: '按钮色',
        color: this.darkButtonColor,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setCurrentButtonColor(color);
        }
      })
      ThemeColorOption({
        title: '强调色',
        color: this.darkAccentColor,
        showDivider: false,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setCurrentAccentColor(color);
        }
      })
    } else {
      ThemeColorOption({
        title: '按钮色',
        color: this.lightButtonColor,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setCurrentButtonColor(color);
        }
      })
      ThemeColorOption({
        title: '强调色',
        color: this.lightAccentColor,
        showDivider: false,
        appDarkMode: this.appDarkMode,
        cardColor: this.cardColor(),
        primaryTextColor: this.primaryTextColor(),
        accentColor: ThemeRuntime.accentColor(this.appDarkMode),
        onColorChange: (color: string) => {
          this.setCurrentAccentColor(color);
        }
      })
    }
  }

  // ---- 高级自定义的会员限制 ----

  /**
   * 逐项配色、强调覆盖、上传素材、界面字体、圆角、启动文案样式和方案预览图是会员专享的高级自定义。
   * 只限制修改：会员到期后已保存的值照常生效，恢复与移除也不受限（与方案额度只限新增一致）。
   */
  advancedLocked(): boolean {
    return this.membershipSku === '' || AccountSessionStore.activeMembershipSku() === '';
  }

  advancedOpacity(): number {
    return this.advancedLocked() ? 0.45 : 1;
  }

  async ensureAdvanced(): Promise<boolean> {
    if (!this.advancedLocked()) return true;
    const result = await promptAction.showDialog({
      title: '高级主题自定义 · 会员专享',
      message: '开通任一档会员后，可以逐项调整配色和强调气泡，上传封面、图标、背景等素材，绑定界面字体，' +
        '调整圆角与启动封面文案样式，并设置方案预览图。已保存的改动在会员到期后继续生效。',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '了解会员', color: ThemeRuntime.accentColor(this.appDarkMode) }
      ]
    });
    if (result.index === 1) {
      router.pushUrl({ url: 'pages/AccountCenter' });
    }
    return false;
  }

  /** 盖在高级选项上的透明层：拦下拾色器、下拉与滑杆的操作，改为提示开通会员。 */
  @Builder
  advancedLockLayer() {
    if (this.advancedLocked()) {
      Column()
        .width('100%')
        .height('100%')
        .accessibilityText('会员专享，了解会员')
        .onClick(() => {
          this.ensureAdvanced();
        })
    }
  }

  // ---- 方案自己上传的素材 ----

  ownThemeId(): string {
    return this.ownPackageId ? `pack:${this.ownPackageId}` : '';
  }

  /** 某类素材上传后，部件来源指向方案自己的素材包；封面、图标与两种模式无关，浅深一起指过去。 */
  applyPackSource(category: string, themeId: string, light: boolean, dark: boolean): void {
    this.rememberChange();
    if (light) {
      const sources = AppThemeSettingsStore.cloneSources(this.lightSources, this.customBaseThemeId);
      this.setSourceValue(sources, category, themeId);
      this.lightSources = sources;
    }
    if (dark) {
      const sources = AppThemeSettingsStore.cloneSources(this.darkSources, this.customBaseThemeId);
      this.setSourceValue(sources, category, themeId);
      this.darkSources = sources;
    }
    this.onSettingChanged();
  }

  /** 素材移掉后，指向素材包的来源退回包的基底主题（第一次上传时该部件所选的主题）。 */
  detachPackSource(category: string, previousThemeId: string, fallbackThemeId: string): void {
    const lightUses = this.sourceValueFor(this.lightSources, category) === previousThemeId &&
      !this.packPartRemains(category, false);
    const darkUses = this.sourceValueFor(this.darkSources, category) === previousThemeId &&
      !this.packPartRemains(category, true);
    if (!lightUses && !darkUses) return;
    this.applyPackSource(category, fallbackThemeId, lightUses, darkUses);
  }

  /**
   * 只移掉部件里的一项（某个导航图标、某张封面、某个模式的首页背景）后，包里这一部件还在就不退回基底，
   * 否则删一个选中态图标会把已传的普通图标也一起换回基底主题。
   */
  packPartRemains(category: string, dark: boolean): boolean {
    const pack = this.ownPack();
    if (!pack) return false;
    const parts = pack.record.parts;
    if (category === 'navigation') return !!parts.navigation;
    if (category === 'book') return !!parts.book;
    if (category === 'homeBackdrop') return !!(dark ? parts.homeBackdropDark : parts.homeBackdropLight) || pack.hasShelfBackdrop(dark);
    return false;
  }

  sourceValueFor(sources: ThemeComponentSourceIds, category: string): string {
    if (category === 'book') return sources.bookThemeId;
    if (category === 'homeBackdrop') return sources.homeBackdropThemeId;
    if (category === 'navigation') return sources.navigationThemeId;
    if (category === 'ttsPanel') return sources.ttsPanelThemeId;
    if (category === 'bubble') return sources.bubbleThemeId;
    if (category === 'reader') return sources.readerThemeId;
    if (category === 'startup') return sources.startupThemeId;
    return sources.paletteThemeId;
  }

  async runAssetUpload(action: () => Promise<SchemeAssetResult>, category: string, light: boolean,
    dark: boolean, notice: string): Promise<void> {
    try {
      // 先把编辑中的改动落盘，素材服务读到的才是当前方案。
      await this.onSettingChanged();
      const result = await action();
      this.ownPackageId = result.packageId;
      this.assetRevision++;
      this.refreshAvailableThemes();
      if (category && result.themeId) this.applyPackSource(category, result.themeId, light, dark);
      if (notice) HdsFeedback.showToast(notice);
      this.refreshAssetIssues();
    } catch (e) {
      console.error('上传方案素材失败:', e);
      HdsFeedback.showToast((e as Error).message || '上传失败，请重试');
    }
  }

  async runAssetClear(action: () => Promise<SchemeAssetResult>, category: string,
    fallbackThemeId: string = ''): Promise<void> {
    const previous = this.ownThemeId();
    const fallback = fallbackThemeId || SchemeAssetService.baseThemeOf(this.ownPackageId);
    try {
      await this.onSettingChanged();
      const result = await action();
      this.ownPackageId = result.packageId;
      this.assetRevision++;
      this.refreshAvailableThemes();
      if (category) {
        this.detachPackSource(category, previous, fallback);
      }
      if (!result.packageId) {
        // 包已经卸掉：所有还指着它的来源都退回基底主题。
        for (const item of ['book', 'navigation', 'ttsPanel', 'bubble', 'reader', 'startup', 'palette', 'homeBackdrop']) {
          this.detachPackSource(item, previous, fallback);
        }
      }
      HdsFeedback.showToast('已移除上传的素材');
      this.refreshAssetIssues();
    } catch (e) {
      console.error('移除方案素材失败:', e);
      HdsFeedback.showToast((e as Error).message || '移除失败，请重试');
    }
  }

  async uploadCovers(): Promise<void> {
    // 加进当前所选模式的那套封面；选图、取景期间切换了模式也以点“添加”时为准。
    const dark = this.selectedMode === 'dark';
    const room = ThemePackageLimits.MAX_COVERS - SchemeAssetService.coverCount(this.ownPackageId, dark);
    if (room <= 0) {
      HdsFeedback.showToast(`${dark ? '深色' : '浅色'}封面最多 ${ThemePackageLimits.MAX_COVERS} 张，请先移除`);
      return;
    }
    const picked = await SchemeAssetService.pickImages(getContext(this), room);
    if (picked.length === 0) return;
    // 一张张取景；取消的那张跳过。
    const uris: string[] = [];
    const crops: Array<ThemeImageCrop | null> = [];
    for (let index = 0; index < picked.length; index++) {
      const framed = await this.frameImage(picked[index], '封面取景', 450, 660, 450, false, index, picked.length);
      if (!framed) continue;
      uris.push(framed.path);
      crops.push(framed.crop);
    }
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.addCovers(getContext(this), this.schemeId, uris, this.sourceThemeId('book'), crops, dark),
      'book', true, true, `已加入 ${uris.length} 张${dark ? '深色' : '浅色'}封面`);
    for (let index = 0; index < uris.length; index++) this.discardCropFile(uris[index], '');
  }

  /** 上传到当前所选模式的那张；选图期间切换了模式也以开始时为准。 */
  async uploadShelfFrame(dark: boolean = this.selectedMode === 'dark'): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setShelfFrame(getContext(this), this.schemeId, uris[0], this.sourceThemeId('book'), dark),
      'book', true, true, dark ? '深色书架边框已更新' : '书架边框已更新');
  }

  /** 上传到当前所选模式的那张；选图、取景期间切换了模式也以开始时为准。 */
  async uploadShelfFolder(dark: boolean = this.selectedMode === 'dark'): Promise<void> {
    const picked = await SchemeAssetService.pickImages(getContext(this), 1);
    if (picked.length === 0) return;
    const framed = await this.frameImage(picked[0], '文件夹插画取景', 450, 660, 450, true);
    if (!framed) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setShelfFolder(getContext(this), this.schemeId, framed.path, this.sourceThemeId('book'),
        framed.crop, dark),
      'book', true, true, `${dark ? '深色' : '浅色'}文件夹插画已更新`);
    this.discardCropFile(framed.path, picked[0]);
  }

  modeLabel(): string {
    return this.selectedMode === 'dark' ? '深色' : '浅色';
  }

  readerAssetMode(): string {
    return SchemeAssetService.readerMode(this.ownPackageId, this.selectedMode === 'dark');
  }

  /** 阅读背景素材不换阅读来源主题（文字色、底色照旧），只把这个模式的背景素材键指向方案自己的包。 */
  setReaderBackgroundAsset(assetId: string): void {
    this.setReaderBackgroundAssetFor(this.selectedMode === 'dark', assetId);
  }

  setReaderBackgroundAssetFor(dark: boolean, assetId: string): void {
    const settings = this.settingsFromState();
    if (dark) settings.customDarkReaderBackgroundAssetId = assetId;
    else settings.customLightReaderBackgroundAssetId = assetId;
    this.draftSettings = settings;
    this.assetRevision++;
    this.onSettingChanged();
  }

  /**
   * “SVG 或位图”又常从相册取图的素材位（阅读角饰、朗读面板插画）：先问从图库选还是选文件，SVG 只能走文件。
   * 返回选中的地址和是否来自文件选择器；取消时地址为空。
   */
  async pickGalleryOrFile(title: string): Promise<PickedArtwork> {
    const picked = new PickedArtwork();
    const choice = await this.slotMenu(title, '从图库选', '选文件（可选 SVG）');
    if (choice === 0) {
      const uris = await SchemeAssetService.pickImages(getContext(this), 1);
      picked.uri = uris.length > 0 ? uris[0] : '';
    } else if (choice === 1) {
      const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
      picked.uri = uris.length > 0 ? uris[0] : '';
      picked.fromFile = true;
    }
    return picked;
  }

  async uploadReaderOrnament(trailing: boolean): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const chosen = await this.pickGalleryOrFile(trailing ? '右下角饰' : '左上角饰');
    if (!chosen.uri) return;
    const uris = [chosen.uri];
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setReaderOrnament(getContext(this), this.schemeId, uris[0], trailing, dark,
        this.sourceThemeId('reader')), '', false, false, '');
    if (this.ownPackageId) {
      this.rememberChange();
      this.setReaderBackgroundAsset(packReaderBackgroundId(this.ownPackageId, dark));
      HdsFeedback.showToast(`${this.modeLabel()}阅读角饰已更新`);
    }
  }

  async uploadReaderImage(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const uris = await SchemeAssetService.pickImages(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setReaderImage(getContext(this), this.schemeId, uris[0], dark, this.sourceThemeId('reader')),
      '', false, false, '');
    if (this.ownPackageId) {
      this.rememberChange();
      this.setReaderBackgroundAsset(packReaderBackgroundId(this.ownPackageId, dark));
      HdsFeedback.showToast(`${this.modeLabel()}阅读背景已更新`);
    }
  }

  async clearReaderAssets(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const sourceTheme = BuiltinThemeRegistry.findById(this.sourceThemeId('reader'));
    await this.runAssetClear((): Promise<SchemeAssetResult> =>
      SchemeAssetService.clearReader(getContext(this), this.schemeId, dark), '');
    this.rememberChange();
    this.setReaderBackgroundAsset(dark ? sourceTheme.dark.reader.backgroundAssetId :
      sourceTheme.light.reader.backgroundAssetId);
  }

  async uploadNavigation(): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), SchemeAssetService.NAVIGATION_TABS.length);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setNavigation(getContext(this), this.schemeId, uris, this.sourceThemeId('navigation')),
      'navigation', true, true, '导航图标已更新');
  }

  async uploadTtsArtwork(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const chosen = await this.pickGalleryOrFile('面板插画');
    if (!chosen.uri) return;
    const picked = [chosen.uri];
    // 选文件来的（多半是 SVG）按原样收，不过取景；图库来的照旧裁成 720 × 520。
    const path = chosen.fromFile ? chosen.uri : await this.cropImage(picked[0], '面板插画取景', 720, 520, 720, true);
    if (!path) return;
    const scheme = new CustomThemeScheme();
    scheme.id = this.schemeId;
    scheme.settings = this.settingsFromState();
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setTtsArtwork(getContext(this), this.schemeId, path, dark, scheme,
        this.sourceThemeId('ttsPanel')),
      'ttsPanel', !dark, dark, `${dark ? '深色' : '浅色'}面板插画已更新`);
    this.discardCropFile(path, picked[0]);
  }

  /** shelfLayout 为空是各页签通用的那张，否则是书架那种布局专属的那张。 */
  async uploadHomeBackdrop(shelfLayout: string = '', dark: boolean = this.selectedMode === 'dark'): Promise<void> {
    const picked = await SchemeAssetService.pickImages(getContext(this), 1);
    if (picked.length === 0) return;
    const name = shelfLayout ? `${this.shelfLayoutName(shelfLayout)}布局书架背景` : '首页背景';
    const framed = await this.frameImage(picked[0], `${name}取景`, 1080, 1350, 1080, false);
    if (!framed) return;
    // 来源还是内置主题时记下它（见 SchemeAssetService.rememberHomeBackdropFallback），所以要传点开时那个模式的来源。
    const source = this.sourceValueFor(dark ? this.darkSources : this.lightSources, 'homeBackdrop');
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setHomeBackdrop(getContext(this), this.schemeId, framed.path, dark, source, framed.crop,
        shelfLayout),
      'homeBackdrop', !dark, dark, `${dark ? '深色' : '浅色'}${name}已更新`);
    this.discardCropFile(framed.path, picked[0]);
  }

  async clearHomeBackdrop(shelfLayout: string = '', dark: boolean = this.selectedMode === 'dark'): Promise<void> {
    // 这个模式的背景全移掉后，来源退回上传前所选的主题，而不是素材包的基底主题。
    const fallback = SchemeAssetService.homeBackdropFallbackOf(this.ownPackageId, dark);
    await this.runAssetClear((): Promise<SchemeAssetResult> =>
      SchemeAssetService.clearHomeBackdrop(getContext(this), this.schemeId, dark, shelfLayout), 'homeBackdrop',
      fallback);
  }

  /** dark 为 true 时传的是深色模式单独的那张；选图期间切换了模式也以开始时为准。 */
  async uploadBubbleCap(dark: boolean = this.selectedMode === 'dark'): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setBubbleCap(getContext(this), this.schemeId, uris[0], this.sourceThemeId('bubble'), dark),
      '', false, false, '');
    if (this.ownThemeId()) this.applyPackBubbleStyle(this.ownThemeId());
    HdsFeedback.showToast(dark ? '深色气泡端饰已更新' : '气泡端饰已更新');
  }

  async uploadBubbleFrame(dark: boolean = this.selectedMode === 'dark'): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    // 换图时沿用原来的拉伸方式和颜色，拉伸线按新图重新给默认位置。深色第一次传时沿用浅色那张的设置。
    const previous = this.ownBubbleFrameSettings(dark);
    previous.frameSlice = null;
    const settings = await this.stretchBubbleFrame(uris[0], previous);
    if (!settings) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setBubbleFrame(getContext(this), this.schemeId, uris[0], this.sourceThemeId('bubble'),
        settings, dark), '', false, false, '');
    if (this.ownThemeId()) this.applyPackBubbleStyle(this.ownThemeId());
    HdsFeedback.showToast(dark ? '深色气泡边框已更新' : '气泡边框已更新');
  }

  async adjustBubbleFrame(dark: boolean = this.selectedMode === 'dark'): Promise<void> {
    const pack = this.ownPack();
    const uri = pack && this.ownBubbleItem(true, dark) ? pack.bubble(dark).frame : '';
    if (!uri) return;
    const settings = await this.stretchBubbleFrame(uri, this.ownBubbleFrameSettings(dark));
    if (!settings) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setBubbleFrameSettings(getContext(this), this.schemeId, settings, dark),
      '', false, false, '拉伸区域已更新');
  }

  /** 打开拉伸区域页；点“使用”交回设置，取消返回 null。 */
  stretchBubbleFrame(uri: string, settings: ThemePackageBubble): Promise<ThemePackageBubble | null> {
    return new Promise<ThemePackageBubble | null>((resolve: (result: ThemePackageBubble | null) => void) => {
      const request = new BubbleFrameStretchRequest();
      const emphasis = this.effectiveEmphasis();
      request.uri = uri;
      request.settings = settings;
      request.textColor = emphasis.emphasisTextColor;
      request.bubbleColor = emphasis.emphasisColor;
      this.frameStretchResolve = resolve;
      this.frameStretchRequest = request;
      this.frameStretchVisible = true;
    });
  }

  finishFrameStretch(settings: ThemePackageBubble | null): void {
    const resolve = this.frameStretchResolve;
    this.frameStretchResolve = null;
    this.frameStretchVisible = false;
    if (resolve) resolve(settings);
  }

  /** 包内气泡通过方案的强调覆盖生效，浅深两种模式一起指过去，颜色仍跟来源主题。 */
  applyPackBubbleStyle(styleId: string): void {
    this.rememberChange();
    const light = AppThemeSettingsStore.normalizeEmphasis(this.lightEmphasis);
    const dark = AppThemeSettingsStore.normalizeEmphasis(this.darkEmphasis);
    light.bubbleStyle = styleId;
    dark.bubbleStyle = styleId;
    this.lightEmphasis = light;
    this.darkEmphasis = dark;
    this.onSettingChanged();
  }

  async clearBookAssets(): Promise<void> {
    await this.runAssetClear((): Promise<SchemeAssetResult> =>
      SchemeAssetService.clearBook(getContext(this), this.schemeId), 'book');
  }

  async clearNavigationAssets(): Promise<void> {
    await this.runAssetClear((): Promise<SchemeAssetResult> =>
      SchemeAssetService.clearNavigation(getContext(this), this.schemeId), 'navigation');
  }

  async clearTtsAssets(): Promise<void> {
    await this.runAssetClear((): Promise<SchemeAssetResult> =>
      SchemeAssetService.clearTts(getContext(this), this.schemeId), 'ttsPanel');
  }

  async clearBubbleAssets(): Promise<void> {
    const previous = this.ownThemeId();
    await this.runAssetClear((): Promise<SchemeAssetResult> =>
      SchemeAssetService.clearBubble(getContext(this), this.schemeId), '');
    if (this.lightEmphasis.bubbleStyle === previous || this.darkEmphasis.bubbleStyle === previous) {
      this.rememberChange();
      const light = AppThemeSettingsStore.normalizeEmphasis(this.lightEmphasis);
      const dark = AppThemeSettingsStore.normalizeEmphasis(this.darkEmphasis);
      if (light.bubbleStyle === previous) light.bubbleStyle = '';
      if (dark.bubbleStyle === previous) dark.bubbleStyle = '';
      this.lightEmphasis = light;
      this.darkEmphasis = dark;
      this.onSettingChanged();
    }
  }

  // ---- 标题强调 ----

  effectiveTitle(): ThemeTitleEmphasisTokens {
    return this.effectiveEmphasis().title || new ThemeTitleEmphasisTokens();
  }

  /** 来源主题自己的标题强调（不含方案覆盖）。 */
  sourceTitle(dark: boolean = this.selectedMode === 'dark'): ThemeTitleEmphasisTokens {
    const sources = dark ? this.darkSources : this.lightSources;
    const theme = BuiltinThemeRegistry.findById(sources.bubbleThemeId);
    return (dark ? theme.dark : theme.light).regexEmphasis.title || new ThemeTitleEmphasisTokens();
  }

  titleDescription(own: string): string {
    if (own) return '自定义';
    return this.sourceTitle().mode ? `跟随「${this.emphasisSourceName()}」` : '所选主题没有设置';
  }

  titleModeIds(): string[] {
    return ['', 'none', 'text', 'highlight', 'bubble'];
  }

  titleModeOptions(): SelectOption[] {
    return ['不设置', '无', '仅文字色', '高亮底色', '气泡'].map((name: string): SelectOption => ({ value: name }));
  }

  titleModeIndex(): number {
    return Math.max(0, this.titleModeIds().indexOf(this.effectiveTitle().mode));
  }

  titleModeLabel(): string {
    return ['不设置', '无', '仅文字色', '高亮底色', '气泡'][this.titleModeIndex()];
  }

  titleHasColors(): boolean {
    const mode = this.effectiveTitle().mode;
    return mode === 'text' || mode === 'highlight' || mode === 'bubble';
  }

  /** 同强调气泡、能用的内置气泡、已安装主题包的气泡，以及方案自己的标题气泡。 */
  titleStyleIds(): string[] {
    const ids: string[] = [TITLE_BUBBLE_SAME_AS_EMPHASIS];
    const own = this.ownThemeId();
    if (own && SchemeAssetService.hasTitleBubble(this.ownPackageId)) ids.push(packTitleBubbleStyleId(own));
    for (const id of ThemeBubbleStyleLabels.BUILTIN_IDS) {
      if (ThemeAccessPolicy.canUseBubbleStyle(id)) ids.push(id);
    }
    for (const pack of ThemePackRegistry.all()) {
      if (pack.hasTitleBubble() && pack.themeId !== own) ids.push(packTitleBubbleStyleId(pack.themeId));
      if (pack.hasBubble()) ids.push(pack.themeId);
    }
    const current = this.effectiveTitleStyle();
    if (current && !ids.includes(current)) ids.push(current);
    return ids;
  }

  /** 空串（没指定样式）按同强调气泡算。 */
  effectiveTitleStyle(): string {
    return this.effectiveTitle().bubbleStyle || TITLE_BUBBLE_SAME_AS_EMPHASIS;
  }

  titleStyleLabel(id: string): string {
    if (!id || id === TITLE_BUBBLE_SAME_AS_EMPHASIS) return '同强调气泡';
    if (isPackTitleBubbleStyle(id)) {
      const pack = ThemePackRegistry.get(id);
      return pack && pack.themeId === this.ownThemeId() ? '本主题标题气泡' : `${pack ? pack.name : '主题包'}（标题气泡）`;
    }
    return this.bubbleStyleLabel(id);
  }

  titleStyleOptions(): SelectOption[] {
    return this.titleStyleIds().map((id: string): SelectOption => ({ value: this.titleStyleLabel(id) }));
  }

  titleStyleIndex(): number {
    return Math.max(0, this.titleStyleIds().indexOf(this.effectiveTitleStyle()));
  }

  effectiveTitleColor(textColor: boolean): string {
    const title = this.effectiveTitle();
    const emphasis = this.effectiveEmphasis();
    return textColor ? (title.textColor || emphasis.emphasisTextColor) : (title.color || emphasis.emphasisColor);
  }

  updateTitle(apply: (next: ThemeTitleEmphasisTokens) => void, dark: boolean = this.selectedMode === 'dark'): void {
    if (this.advancedLocked()) return;
    this.rememberChange();
    const next = AppThemeSettingsStore.normalizeEmphasis(dark ? this.darkEmphasis : this.lightEmphasis);
    const title = AppThemeSettingsStore.normalizeTitleEmphasis(next.title);
    apply(title);
    next.title = AppThemeSettingsStore.normalizeTitleEmphasis(title);
    if (dark) this.darkEmphasis = next;
    else this.lightEmphasis = next;
    this.onSettingChanged();
  }

  setTitleMode(index: number): void {
    const ids = this.titleModeIds();
    if (index < 0 || index >= ids.length || ids[index] === this.effectiveTitle().mode) return;
    const sourceMode = this.sourceTitle().mode;
    this.updateTitle((next: ThemeTitleEmphasisTokens): void => {
      // 选“不设置”时，来源主题自己设了标题强调就写 off 强制不设置，否则清空覆盖。
      if (!ids[index]) {
        next.mode = sourceMode ? 'off' : '';
        next.bubbleStyle = '';
        next.color = '';
        next.textColor = '';
        return;
      }
      next.mode = ids[index] === sourceMode ? '' : ids[index];
    });
  }

  setTitleStyle(index: number): void {
    const ids = this.titleStyleIds();
    if (index < 0 || index >= ids.length || ids[index] === this.effectiveTitleStyle()) return;
    this.updateTitle((next: ThemeTitleEmphasisTokens): void => {
      next.bubbleStyle = ids[index];
      if (!next.mode) next.mode = 'bubble';
    });
  }

  setTitleColor(textColor: boolean, color: string): void {
    const current = this.effectiveTitleColor(textColor);
    const normalized = HexColor.normalizeAlpha(color, current);
    if (normalized === current) return;
    this.updateTitle((next: ThemeTitleEmphasisTokens): void => {
      if (!next.mode) next.mode = this.effectiveTitle().mode || 'bubble';
      if (textColor) next.textColor = normalized;
      else next.color = normalized;
    });
  }

  /** 把这个模式正文强调的方式、底色和文字色搬到标题强调，气泡样式用“同强调气泡”。 */
  copyTitleFromEmphasis(): void {
    const emphasis = this.effectiveEmphasis();
    const mode = emphasis.emphasisMode === 'none' || emphasis.emphasisMode === 'text' ||
      emphasis.emphasisMode === 'highlight' ? emphasis.emphasisMode : 'bubble';
    this.updateTitle((next: ThemeTitleEmphasisTokens): void => {
      next.mode = mode;
      next.bubbleStyle = TITLE_BUBBLE_SAME_AS_EMPHASIS;
      next.color = emphasis.emphasisColor;
      next.textColor = emphasis.emphasisTextColor;
    });
    HdsFeedback.showToast('已按强调气泡设置标题强调');
  }

  resetTitleEmphasis(): void {
    this.updateTitle((next: ThemeTitleEmphasisTokens): void => {
      next.mode = '';
      next.bubbleStyle = '';
      next.color = '';
      next.textColor = '';
    });
  }

  // 标题气泡素材

  ownTitleBubbleItem(frame: boolean, dark: boolean = this.selectedMode === 'dark'): string {
    const pack = this.ownPack();
    if (!pack || this.assetRevision < 0) return '';
    const bubble = dark ? pack.record.parts.titleBubbleDark : pack.record.parts.titleBubble;
    if (!bubble) return '';
    const value = (frame ? bubble.frame : bubble.cap) || '';
    return value ? this.ownAssetUri(value) || value : '';
  }

  titleBubbleHint(): string {
    const base = '只在章节标题上用的端饰和边框：端饰是正方形 SVG 或透明底位图，边框按行拉伸，上传后可调拉伸区域';
    if (this.selectedMode !== 'dark') return `${base}。切到深色可以再传只在深色模式用的`;
    return '深色模式没传的那一项沿用浅色的。浅色素材在深色纸面上看不清时，单独上传一张或给边框打开染色';
  }

  titleBubbleFrameSettings(dark: boolean): ThemePackageBubble {
    const settings = new ThemePackageBubble();
    const pack = this.ownPack();
    if (!pack || this.assetRevision < 0) return settings;
    const bubble = pack.titleBubble(dark);
    settings.frameSlice = bubble.frameSlice;
    settings.frameRepeat = bubble.frameRepeat;
    settings.frameBreak = bubble.frameBreak;
    settings.frameTint = bubble.frameTint;
    return settings;
  }

  async tapTitleBubbleSlot(frame: boolean): Promise<void> {
    const dark = this.selectedMode === 'dark';
    if (!(await this.ensureAdvanced())) return;
    if (!this.ownTitleBubbleItem(frame, dark)) {
      await this.uploadTitleBubble(frame, dark);
      return;
    }
    const title = `${dark ? '深色' : '浅色'} · ${frame ? '标题气泡边框' : '标题气泡端饰'}`;
    const items: string[] = frame ? ['调整拉伸区域', '替换', dark ? '移除，沿用浅色的边框' : '移除边框'] :
      ['替换', dark ? '移除，沿用浅色的端饰' : '移除端饰'];
    const choice = await this.slotMenuItems(title, items);
    if (choice < 0) return;
    const picked = items[choice];
    if (picked.startsWith('调整')) {
      const pack = this.ownPack();
      const uri = pack ? pack.titleBubble(dark).frame : '';
      if (!uri) return;
      const settings = await this.stretchBubbleFrame(uri, this.titleBubbleFrameSettings(dark));
      if (!settings) return;
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.setBubbleFrameSettings(getContext(this), this.schemeId, settings, dark, true),
        '', false, false, '拉伸区域已更新');
    } else if (picked.startsWith('替换')) {
      await this.uploadTitleBubble(frame, dark);
    } else {
      await this.clearTitleBubblePart(frame, dark);
    }
  }

  async uploadTitleBubble(frame: boolean, dark: boolean): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    if (frame) {
      const previous = this.titleBubbleFrameSettings(dark);
      previous.frameSlice = null;
      const settings = await this.stretchBubbleFrame(uris[0], previous);
      if (!settings) return;
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.setBubbleFrame(getContext(this), this.schemeId, uris[0], this.sourceThemeId('bubble'),
          settings, dark, true), '', false, false, '');
    } else {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.setBubbleCap(getContext(this), this.schemeId, uris[0], this.sourceThemeId('bubble'), dark,
          true), '', false, false, '');
    }
    const own = this.ownThemeId();
    if (!own || !SchemeAssetService.hasTitleBubble(this.ownPackageId)) return;
    this.applyTitlePackStyle(packTitleBubbleStyleId(own));
    HdsFeedback.showToast(`${dark ? '深色' : ''}标题气泡${frame ? '边框' : '端饰'}已更新`);
  }

  /** 传了标题气泡后两种模式的标题强调都指过去（没设方式的补成气泡），颜色仍按原来的。 */
  applyTitlePackStyle(styleId: string): void {
    for (const dark of [false, true]) {
      this.updateTitle((next: ThemeTitleEmphasisTokens): void => {
        next.bubbleStyle = styleId;
        if (!next.mode || next.mode === 'off') next.mode = 'bubble';
      }, dark);
    }
  }

  /** 移除某个模式的标题端饰或边框；两种模式都没有了时，指向它的标题样式改回同强调气泡。 */
  async clearTitleBubblePart(frame: boolean, dark: boolean): Promise<void> {
    const previous = this.ownThemeId();
    await this.runAssetClear((): Promise<SchemeAssetResult> => frame ?
      SchemeAssetService.clearBubbleFrame(getContext(this), this.schemeId, dark, true) :
      SchemeAssetService.clearBubbleCap(getContext(this), this.schemeId, dark, true), '');
    if (!previous || SchemeAssetService.hasTitleBubble(this.ownPackageId)) return;
    const styleId = packTitleBubbleStyleId(previous);
    for (const mode of [false, true]) {
      const current = AppThemeSettingsStore.normalizeTitleEmphasis((mode ? this.darkEmphasis : this.lightEmphasis).title);
      if (current.bubbleStyle === styleId) {
        this.updateTitle((next: ThemeTitleEmphasisTokens): void => {
          next.bubbleStyle = TITLE_BUBBLE_SAME_AS_EMPHASIS;
        }, mode);
      }
    }
  }

  // ---- 章首装饰 ----

  /** 来源主题自己的章首装饰（不含方案覆盖）。 */
  sourceChapterHead(dark: boolean = this.selectedMode === 'dark'): ThemePackageChapterHead {
    const sources = dark ? this.darkSources : this.lightSources;
    const theme = BuiltinThemeRegistry.findById(sources.bubbleThemeId);
    return normalizeChapterHead((dark ? theme.dark : theme.light).regexEmphasis.chapterHead);
  }

  /** 方案素材包这个模式实际用的章首装饰（素材是包内相对路径）；主题包记录不是状态变量，读 assetRevision 刷新。 */
  ownChapterHead(dark: boolean = this.selectedMode === 'dark'): ThemePackageChapterHead {
    if (this.assetRevision < 0) return new ThemePackageChapterHead();
    return SchemeAssetService.chapterHead(this.ownPackageId, dark) || new ThemePackageChapterHead();
  }

  /** 当前模式生效的章首装饰（来源主题 + 方案覆盖），饰图是本机地址。 */
  effectiveChapterHead(): ThemePackageChapterHead {
    return normalizeChapterHead(this.effectiveEmphasis().chapterHead);
  }

  chapterHeadSlotImage(): ResourceStr {
    const own = this.ownChapterHead().image;
    if (own) return this.ownAssetUri(own) || own;
    return ThemeAssetRegistry.chapterArtwork(this.effectiveChapterHead().image);
  }

  chapterHeadSlotState(): string {
    if (this.assetRevision >= 0 && SchemeAssetService.hasOwnChapterHeadImage(this.ownPackageId,
      this.selectedMode === 'dark')) return 'own';
    return this.effectiveChapterHead().image || this.ownChapterHead().image ? 'inherit' : 'empty';
  }

  /** 饰图来自方案自己的素材包时才能调位置和大小。 */
  chapterHeadAdjustable(): boolean {
    return !!this.ownChapterHead().image && this.currentEmphasis().chapterHead === this.ownThemeId();
  }

  chapterHeadHint(): string {
    if (this.currentEmphasis().chapterHead === CHAPTER_HEAD_NONE) return '已设为不显示所选主题的章首装饰。上传一张图会改用你自己的';
    const base = '画在每章标题旁的一张图：SVG 或透明底位图。放左侧适合竖长的图，放上方、下方适合横长的花纹';
    if (this.selectedMode !== 'dark') return `${base}。切到深色可以再传只在深色模式用的`;
    return '深色模式没传时沿用浅色那张。浅色的图在深色纸面上看不清时，单独上传一张';
  }

  chapterHeadPlacementOptions(): SelectOption[] {
    return CHAPTER_HEAD_PLACEMENT_NAMES.map((name: string): SelectOption => ({ value: name }));
  }

  chapterHeadPlacementIndex(): number {
    return Math.max(0, CHAPTER_HEAD_PLACEMENTS.indexOf(this.ownChapterHead().placement || 'side'));
  }

  chapterHeadScalePercent(): number {
    if (this.chapterHeadScaleDrag >= 0) return this.chapterHeadScaleDrag;
    return Math.round(this.ownChapterHead().scale * 100);
  }

  ownChapterHeadNumberColor(): string {
    return this.currentEmphasis().chapterHead === this.ownThemeId() ? this.ownChapterHead().numberColor : '';
  }

  /** 色块上显示的颜色：没设时是标题本来的颜色。 */
  chapterHeadNumberColor(): string {
    return this.effectiveChapterHead().numberColor || this.commentPreviewTextColor(this.selectedMode === 'dark');
  }

  chapterHeadNumberDescription(): string {
    const hint = '分段标题第一段（“第十二章”那一行）的颜色，读者开了标题分段才看得出';
    return this.effectiveChapterHead().numberColor ? hint : `${hint}。现在和标题同色`;
  }

  /** 只改这个模式的覆盖：空串跟随所选主题，none 不显示。 */
  setChapterHeadOverride(value: string): void {
    if (this.advancedLocked()) return;
    const dark = this.selectedMode === 'dark';
    const next = AppThemeSettingsStore.normalizeEmphasis(dark ? this.darkEmphasis : this.lightEmphasis);
    if (next.chapterHead === value) return;
    this.rememberChange();
    next.chapterHead = value;
    if (dark) this.darkEmphasis = next;
    else this.lightEmphasis = next;
    this.onSettingChanged();
  }

  /**
   * 素材包里的章首装饰变了之后，两种模式的覆盖跟着对齐：包里这个模式有就指向素材包，
   * 没有了而覆盖还指着素材包的改回跟随所选主题。
   */
  syncChapterHeadOverride(previousThemeId: string): void {
    const own = this.ownThemeId();
    let changed = false;
    for (const dark of [false, true]) {
      const next = AppThemeSettingsStore.normalizeEmphasis(dark ? this.darkEmphasis : this.lightEmphasis);
      const has = !!own && !!SchemeAssetService.chapterHead(this.ownPackageId, dark);
      const pointsAtPack = !!next.chapterHead && (next.chapterHead === own || next.chapterHead === previousThemeId);
      const target = has ? own : (pointsAtPack ? '' : next.chapterHead);
      if (next.chapterHead === target) continue;
      if (!changed) this.rememberChange();
      changed = true;
      next.chapterHead = target;
      if (dark) this.darkEmphasis = next;
      else this.lightEmphasis = next;
    }
    if (changed) this.onSettingChanged();
  }

  // 首字装饰：行数、颜色、字占比和印章图都写在方案素材包这个模式的 chapterHead 里。

  dropCapLineOptions(): SelectOption[] {
    return DROP_CAP_LINE_NAMES.map((name: string): SelectOption => ({ value: name }));
  }

  dropCapLineIndex(): number {
    const lines = this.effectiveChapterHead().dropCapLines;
    return lines === 3 ? 2 : (lines === 2 ? 1 : 0);
  }

  dropCapRatioPercent(): number {
    if (this.dropCapRatioDrag >= 0) return this.dropCapRatioDrag;
    return Math.round(this.effectiveChapterHead().dropCapRatio * 100);
  }

  dropCapSlotImage(): ResourceStr {
    const own = this.ownChapterHead().dropCapImage;
    if (own && this.currentEmphasis().chapterHead === this.ownThemeId()) return this.ownAssetUri(own) || own;
    return ThemeAssetRegistry.chapterArtwork(this.effectiveChapterHead().dropCapImage);
  }

  dropCapSlotState(): string {
    if (this.assetRevision >= 0 && SchemeAssetService.hasOwnDropCapImage(this.ownPackageId,
      this.selectedMode === 'dark')) return 'own';
    return this.effectiveChapterHead().dropCapImage ? 'inherit' : 'empty';
  }

  dropCapHint(): string {
    const base = '垫在首字底下的一张图，字画在正中：正方形、中间留空的 SVG 或透明底位图。不传就只把字放大';
    if (this.selectedMode !== 'dark') return base;
    return '深色模式没单独设首字时沿用浅色那套。浅色的印章在深色纸面上看不清时，单独上传一张';
  }

  /** 首字的三项设置一起存；没改的项沿用当前生效的值。 */
  async saveDropCap(lines: number, color: string, ratio: number): Promise<void> {
    if (!(await this.ensureAdvanced())) return;
    const dark = this.selectedMode === 'dark';
    const previous = this.ownThemeId();
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setChapterHeadDropCap(getContext(this), this.schemeId, this.sourceThemeId('bubble'), dark,
        lines, color, ratio), '', false, false, '');
    this.syncChapterHeadOverride(previous);
  }

  async setDropCapLines(index: number): Promise<void> {
    if (index < 0 || index > 2 || index === this.dropCapLineIndex()) return;
    const head = this.effectiveChapterHead();
    await this.saveDropCap(index === 0 ? 0 : index + 1, head.dropCapColor, head.dropCapRatio);
  }

  async setDropCapColor(color: string): Promise<void> {
    const head = this.effectiveChapterHead();
    const normalized = color ? HexColor.normalizeAlpha(color, '') : '';
    if ((color && !normalized) || normalized === head.dropCapColor || head.dropCapLines === 0) return;
    await this.saveDropCap(head.dropCapLines, normalized, head.dropCapRatio);
  }

  async setDropCapRatio(percent: number): Promise<void> {
    this.dropCapRatioDrag = Math.round(percent);
    try {
      const head = this.effectiveChapterHead();
      if (head.dropCapLines === 0) return;
      await this.saveDropCap(head.dropCapLines, head.dropCapColor, normalizeDropCapRatio(percent / 100));
    } finally {
      this.dropCapRatioDrag = -1;
    }
  }

  async tapDropCapSlot(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    if (!(await this.ensureAdvanced())) return;
    if (!SchemeAssetService.hasOwnDropCapImage(this.ownPackageId, dark)) {
      await this.uploadDropCapImage(dark);
      return;
    }
    const items: string[] = ['替换', '移除印章，只放大首字'];
    const choice = await this.slotMenuItems(`${dark ? '深色' : '浅色'} · 首字印章`, items);
    if (choice === 0) {
      await this.uploadDropCapImage(dark);
    } else if (choice === 1) {
      const previous = this.ownThemeId();
      await this.runAssetClear((): Promise<SchemeAssetResult> =>
        SchemeAssetService.clearChapterHeadDropCapImage(getContext(this), this.schemeId, dark), '');
      this.syncChapterHeadOverride(previous);
    }
  }

  async uploadDropCapImage(dark: boolean): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    const previous = this.ownThemeId();
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setChapterHeadDropCapImage(getContext(this), this.schemeId, uris[0],
        this.sourceThemeId('bubble'), dark), '', false, false, `${dark ? '深色' : ''}首字印章已更新`);
    this.syncChapterHeadOverride(previous);
  }

  async tapChapterHeadSlot(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    if (!(await this.ensureAdvanced())) return;
    if (!SchemeAssetService.hasOwnChapterHeadImage(this.ownPackageId, dark)) {
      await this.uploadChapterHeadImage(dark);
      return;
    }
    const items: string[] = ['替换', dark ? '移除，沿用浅色的饰图' : '移除饰图'];
    const choice = await this.slotMenuItems(`${dark ? '深色' : '浅色'} · 标题饰图`, items);
    if (choice === 0) {
      await this.uploadChapterHeadImage(dark);
    } else if (choice === 1) {
      const previous = this.ownThemeId();
      await this.runAssetClear((): Promise<SchemeAssetResult> =>
        SchemeAssetService.clearChapterHeadImage(getContext(this), this.schemeId, dark), '');
      this.syncChapterHeadOverride(previous);
    }
  }

  async uploadChapterHeadImage(dark: boolean): Promise<void> {
    const uris = await SchemeAssetService.pickArtworkFiles(getContext(this), 1);
    if (uris.length === 0) return;
    const previous = this.ownThemeId();
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setChapterHeadImage(getContext(this), this.schemeId, uris[0], this.sourceThemeId('bubble'),
        dark), '', false, false, `${dark ? '深色' : ''}标题饰图已更新`);
    this.syncChapterHeadOverride(previous);
  }

  async setChapterHeadPlacement(index: number): Promise<void> {
    if (index < 0 || index >= CHAPTER_HEAD_PLACEMENTS.length || index === this.chapterHeadPlacementIndex()) return;
    if (!(await this.ensureAdvanced())) return;
    const dark = this.selectedMode === 'dark';
    const placement = index === 0 ? '' : CHAPTER_HEAD_PLACEMENTS[index];
    const scale = this.ownChapterHead(dark).scale;
    const previous = this.ownThemeId();
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setChapterHeadLayout(getContext(this), this.schemeId, dark, placement, scale),
      '', false, false, '');
    this.syncChapterHeadOverride(previous);
  }

  async setChapterHeadScale(percent: number): Promise<void> {
    this.chapterHeadScaleDrag = Math.round(percent);
    try {
      if (!(await this.ensureAdvanced())) return;
      const dark = this.selectedMode === 'dark';
      const placement = this.ownChapterHead(dark).placement;
      const previous = this.ownThemeId();
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.setChapterHeadLayout(getContext(this), this.schemeId, dark, placement,
          normalizeOrnamentScale(percent / 100)), '', false, false, '');
      this.syncChapterHeadOverride(previous);
    } finally {
      this.chapterHeadScaleDrag = -1;
    }
  }

  /** 空串改回和标题同色。来源主题带的章首装饰不会被带进素材包：设了自己的颜色后整套改用素材包的。 */
  async setChapterHeadNumberColor(color: string): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const normalized = color ? HexColor.normalizeAlpha(color, '') : '';
    if (color && !normalized) return;
    if (normalized === this.ownChapterHeadNumberColor()) return;
    if (!(await this.ensureAdvanced())) return;
    const previous = this.ownThemeId();
    if (normalized) {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.setChapterHeadNumberColor(getContext(this), this.schemeId, this.sourceThemeId('bubble'),
          dark, normalized), '', false, false, '');
    } else {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.setChapterHeadNumberColor(getContext(this), this.schemeId, '', dark, ''),
        '', false, false, '');
    }
    this.syncChapterHeadOverride(previous);
  }

  // ---- 界面字体 ----

  appFontOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '跟随所选主题' }];
    for (const font of this.fontLibrary) options.push({ value: font.name });
    return options;
  }

  appFontIndex(): number {
    if (!this.appFontFamily) return 0;
    const index = this.fontLibrary.findIndex((font: SchemeFontOption): boolean => font.family === this.appFontFamily);
    return index < 0 ? 0 : index + 1;
  }

  appFontLabel(): string {
    const index = this.appFontIndex();
    if (index === 0) return this.appFontFamily ? '（字体已不在字体库）' : '跟随所选主题';
    return this.fontLibrary[index - 1].name;
  }

  setAppFont(index: number): void {
    if (this.advancedLocked()) return;
    const family = index <= 0 || index > this.fontLibrary.length ? '' : this.fontLibrary[index - 1].family;
    if (family === this.appFontFamily) return;
    this.rememberChange();
    this.appFontFamily = family;
    this.onSettingChanged();
  }

  @Builder
  appFontRow() {
    Stack() {
      Column() {
        this.appFontControl()
      }
      .width('100%')
      .opacity(this.advancedOpacity())
      this.advancedLockLayer()
    }
    .width('100%')
  }

  @Builder
  appFontControl() {
    SettingRow({ title: '界面字体文件', description: this.fontLibrary.length > 0 ?
      '绑定字体库里的字体；阅读字体选“跟随主题”时生效，随导出打包' : '字体库里还没有自定义字体，先在阅读设置里添加' }) {
      Select(this.appFontOptions())
        .id('theme_editor_app_font')
        .width('44%')
        .selected(this.appFontIndex())
        .value(this.appFontLabel())
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => this.setAppFont(index))
    }
  }

  // ---- 圆角 ----

  radiusValue(key: string): number {
    const override = this.radiusOverrideValue(key);
    if (override >= 0) return override;
    const radius = this.customPreviewTheme().radius;
    if (key === 'small') return radius.small;
    if (key === 'medium') return radius.medium;
    if (key === 'large') return radius.large;
    if (key === 'card') return radius.card;
    if (key === 'button') return radius.button;
    return radius.bubble;
  }

  radiusOverrideValue(key: string): number {
    const o = this.radiusOverride;
    if (key === 'small') return o.small;
    if (key === 'medium') return o.medium;
    if (key === 'large') return o.large;
    if (key === 'card') return o.card;
    if (key === 'button') return o.button;
    return o.bubble;
  }

  setRadius(key: string, value: number): void {
    if (this.advancedLocked()) return;
    const rounded = Math.max(0, Math.min(48, Math.round(value)));
    if (rounded === this.radiusValue(key) && this.radiusOverrideValue(key) >= 0) return;
    this.rememberChange();
    const next = AppThemeSettingsStore.normalizeRadius(this.radiusOverride);
    if (key === 'small') next.small = rounded;
    else if (key === 'medium') next.medium = rounded;
    else if (key === 'large') next.large = rounded;
    else if (key === 'card') next.card = rounded;
    else if (key === 'button') next.button = rounded;
    else next.bubble = rounded;
    this.radiusOverride = next;
    this.onSettingChanged();
  }

  resetRadius(): void {
    this.rememberChange();
    this.radiusOverride = new ThemeRadiusOverrides();
    this.onSettingChanged();
  }

  @Builder
  radiusRows() {
    Stack() {
      Column() {
        this.radiusRow({ title: '小圆角', key: 'small' })
        this.radiusRow({ title: '中圆角', key: 'medium' })
        this.radiusRow({ title: '大圆角', key: 'large' })
        this.radiusRow({ title: '卡片', key: 'card' })
        this.radiusRow({ title: '按钮', key: 'button' })
        this.radiusRow({ title: '气泡', key: 'bubble' })
      }
      .width('100%')
      .opacity(this.advancedOpacity())
      this.advancedLockLayer()
    }
    .width('100%')
    if (AppThemeSettingsStore.hasRadiusOverride(this.radiusOverride)) {
      this.resetRow('恢复为所选主题的圆角', () => this.resetRadius())
    }
  }

  @Builder
  radiusRow($$: RadiusRowOptions) {
    Column({ space: AppSpacing.XS }) {
      Row() {
        Text($$.title)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.radiusValue($$.key)}${this.radiusOverrideValue($$.key) >= 0 ? '' : ' · 跟随'}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Slider({ value: this.radiusValue($$.key), min: 0, max: 48, step: 1, style: SliderStyle.OutSet })
        .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
        .width('100%')
        .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.setRadius($$.key, value);
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
  }

  // ---- 启动封面文案样式 ----

  currentStartupText(): ThemeStartupTextStyle {
    return this.selectedMode === 'dark' ? this.darkStartupText : this.lightStartupText;
  }

  updateStartupText(apply: (next: ThemeStartupTextStyle) => void): void {
    if (this.advancedLocked()) return;
    this.rememberChange();
    const next = AppThemeSettingsStore.normalizeStartupText(this.currentStartupText());
    apply(next);
    if (this.selectedMode === 'dark') this.darkStartupText = next;
    else this.lightStartupText = next;
    this.onSettingChanged();
  }

  resetStartupText(): void {
    this.rememberChange();
    if (this.selectedMode === 'dark') this.darkStartupText = new ThemeStartupTextStyle();
    else this.lightStartupText = new ThemeStartupTextStyle();
    this.onSettingChanged();
  }

  @Builder
  startupTextStyleOptions() {
    Column() {
      Stack() {
        Column() {
          this.startupTextControls()
        }
        .width('100%')
        .opacity(this.advancedOpacity())
        this.advancedLockLayer()
      }
      .width('100%')
      if (AppThemeSettingsStore.hasStartupTextStyle(this.currentStartupText())) {
        this.resetRow(`恢复${this.modeLabel()}文案默认样式`, () => this.resetStartupText())
      }
    }
    .width('100%')
  }

  @Builder
  startupTextControls() {
    ThemeColorOption({
      title: '标题颜色',
      description: this.currentStartupText().titleColor ? '自定义' : '默认白色',
      color: this.currentStartupText().titleColor || '#FFFFFF',
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        const normalized = AppThemeSettingsStore.normalizeColor(color, '#FFFFFF');
        this.updateStartupText((next: ThemeStartupTextStyle): void => {
          next.titleColor = normalized;
        });
      }
    })
    ThemeColorOption({
      title: '副标题颜色',
      description: this.currentStartupText().subtitleColor ? '自定义' : '默认白色',
      color: this.currentStartupText().subtitleColor || '#FFFFFF',
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        const normalized = AppThemeSettingsStore.normalizeColor(color, '#FFFFFF');
        this.updateStartupText((next: ThemeStartupTextStyle): void => {
          next.subtitleColor = normalized;
        });
      }
    })
    this.startupSizeRow({ title: '标题字号', key: 'title' })
    this.startupSizeRow({ title: '副标题字号', key: 'subtitle' })
  }

  startupSizeValue(key: string): number {
    const style = this.currentStartupText();
    if (key === 'title') return style.titleSize > 0 ? style.titleSize : 21;
    return style.subtitleSize > 0 ? style.subtitleSize : 12;
  }

  @Builder
  startupSizeRow($$: RadiusRowOptions) {
    Column({ space: AppSpacing.XS }) {
      Row() {
        Text($$.title)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${this.startupSizeValue($$.key)}${($$.key === 'title' ? this.currentStartupText().titleSize :
          this.currentStartupText().subtitleSize) > 0 ? '' : ' · 默认'}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Slider({ value: this.startupSizeValue($$.key), min: $$.key === 'title' ? 12 : 8,
        max: $$.key === 'title' ? 48 : 28, step: 1, style: SliderStyle.OutSet })
        .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
        .width('100%')
        .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode !== SliderChangeMode.End && mode !== SliderChangeMode.Click) return;
          const size = Math.round(value);
          this.updateStartupText((next: ThemeStartupTextStyle): void => {
            if ($$.key === 'title') next.titleSize = size;
            else next.subtitleSize = size;
          });
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
  }

  // ---- 方案预览图 ----

  async choosePreviewImage(): Promise<void> {
    if (!(await this.ensureAdvanced())) return;
    try {
      const old = this.previewImagePath;
      const picked = await SchemeAssetService.pickImages(getContext(this), 1);
      if (picked.length === 0) return;
      const cropped = await this.cropImage(picked[0], '预览图取景', 3, 4, 720, false);
      if (!cropped) return;
      const path = await SchemePreviewImageStore.saveFrom(getContext(this), this.schemeId, cropped);
      this.discardCropFile(cropped, picked[0]);
      this.rememberChange();
      this.previewImagePath = path;
      await this.onSettingChanged();
      if (old && old !== path) this.trackObsoleteStartupPath(old);
      HdsFeedback.showToast('方案预览图已更新');
    } catch (e) {
      console.error('上传方案预览图失败:', e);
      HdsFeedback.showToast('上传预览图失败，请重试');
    }
  }

  async resetPreviewImage(): Promise<void> {
    const old = this.previewImagePath;
    if (!old) return;
    this.rememberChange();
    this.previewImagePath = '';
    await this.onSettingChanged();
    this.trackObsoleteStartupPath(old);
  }

  @Builder
  previewPanel() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Text(`${this.sceneLabel(this.previewScene)} · ${this.selectedMode === 'dark' ? '深色' : '浅色'}` +
          (this.sceneChoices().length > 1 ? ' · 左右滑动换画面' : ''))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.previewScene === 'bookshelf') {
          this.shelfLayoutButton(false)
        }
        this.issuesBadge()
        ImmersiveHeaderAction({ label: '放大', accessibilityLabel: '放大主题预览',
          onTap: () => { this.fullPreview = true; } })
      }
      .width('100%')
      this.previewSurface(false)
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
  }

  static readonly SCENES: string[] = ['bookshelf', 'explore', 'mine', 'reader', 'tts', 'startup', 'card'];

  sceneLabel(scene: string): string {
    if (scene === 'explore') return '发现';
    if (scene === 'mine') return '我的';
    if (scene === 'reader') return '阅读';
    if (scene === 'tts') return '朗读';
    if (scene === 'startup') return '启动';
    if (scene === 'card') return '卡片';
    return '书架';
  }

  /** 沉浸光感胶囊的宽度：悬浮材质只接受具体宽度，中文按字号估算。 */
  capsuleWidth(label: string, fontSize: number, extra: number): number {
    let textWidth = 0;
    for (const char of label) {
      textWidth += char.charCodeAt(0) > 0xFF ? fontSize : fontSize * 0.6;
    }
    return Math.ceil(textWidth) + extra;
  }

  /** 放大预览底部的画面格：两行，首页三个页签在上，阅读相关在下，图标加文字，拇指够得着。 */
  @Builder
  sceneGrid() {
    Column({ space: AppSpacing.XS }) {
      Row({ space: AppSpacing.XS }) {
        this.sceneCell('书架', 'bookshelf', $r('sys.symbol.bookshelf'))
        this.sceneCell('发现', 'explore', $r('sys.symbol.square_grid_2x2'))
        this.sceneCell('我的', 'mine', $r('sys.symbol.person'))
        this.sceneCell('阅读', 'reader', $r('sys.symbol.book_pages'))
      }
      .width('100%')
      Row({ space: AppSpacing.XS }) {
        this.sceneCell('朗读', 'tts', $r('sys.symbol.earphone'))
        this.sceneCell('启动', 'startup', $r('sys.symbol.picture'))
        this.sceneCell('卡片', 'card', $r('sys.symbol.rectangle_3_group'))
        // 最后一格：看书架时是布局切换，其他画面留空，两行格子等宽对齐。
        if (this.previewScene === 'bookshelf') {
          this.shelfLayoutCell()
        } else {
          Blank()
            .layoutWeight(1)
            .height(52)
        }
      }
      .width('100%')
    }
    .width('calc(100% - 24vp)')
    .padding(AppSpacing.XS)
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD,
      bottom: this.navBarHeight + AppSpacing.MD })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  sceneCell(label: string, scene: string, icon: Resource) {
    Column({ space: AppSpacing.XXS }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.previewScene === scene ? ThemeRuntime.accentColor(this.appDarkMode) : this.subTextColor()])
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.previewScene === scene ? ThemeRuntime.accentColor(this.appDarkMode) : this.subTextColor())
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(this.previewScene === scene ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
    .accessibilityText(`${label}场景预览`)
    .accessibilitySelected(this.previewScene === scene)
    .onClick(() => { this.previewScene = scene; })
  }

  shelfLayoutLabel(layout: string): string {
    if (layout === 'tile') return '平铺';
    if (layout === 'loose') return '宽松';
    if (layout === 'compact') return '紧凑';
    return '陪伴';
  }

  /** 放大预览底部画面格里的布局切换：点开弹出菜单选四种书架布局。 */
  @Builder
  shelfLayoutCell() {
    Column({ space: AppSpacing.XXS }) {
      SymbolGlyph($r('sys.symbol.square_grid_2x2'))
        .fontSize(20)
        .fontColor([this.primaryTextColor()])
      Row({ space: 2 }) {
        Text(this.shelfLayoutLabel(this.previewShelfLayout))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.primaryTextColor())
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(10)
          .fontColor([this.subTextColor()])
      }
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .borderRadius(ThemeRuntime.mediumRadius())
    .border({ width: 1, color: ThemeRuntime.dividerColor(this.appDarkMode) })
    .accessibilityGroup(true)
    .accessibilityText(`书架布局：${this.shelfLayoutLabel(this.previewShelfLayout)}，点按切换`)
    .onClick(() => {
      this.showShelfLayoutMenu = true;
    })
    .bindPopup(this.showShelfLayoutMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.shelfLayoutMenuContent()
    }, Placement.TopRight, this.appDarkMode, ThemeRuntime.accentColor(this.appDarkMode), () => {
      this.showShelfLayoutMenu = false;
    }))
  }

  /** 预览标题行里的布局按钮（不盖在画面上）：沉浸光感胶囊，点开弹出菜单选四种书架布局。 */
  @Builder
  shelfLayoutButton(expanded: boolean) {
    Column() {
      ImmersiveMaterialSurface({
        surfaceWidth: this.capsuleWidth(this.shelfLayoutLabel(this.previewShelfLayout), AppFontSize.CAPTION,
          14 + 12 + AppSpacing.XS * 2 + 24),
        surfaceHeight: expanded ? ImmersiveHeaderAction.SIZE : 32, darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(), glowColor: `#40${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`
      }) {
        Row({ space: AppSpacing.XS }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(14)
            .fontColor([this.primaryTextColor()])
          Text(this.shelfLayoutLabel(this.previewShelfLayout))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.primaryTextColor())
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([this.subTextColor()])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityGroup(true)
        .accessibilityText(`书架布局：${this.shelfLayoutLabel(this.previewShelfLayout)}，点按切换`)
        .onClick(() => {
          this.showShelfLayoutMenu = true;
        })
      }
    }
    .margin({ right: AppSpacing.SM })
    .bindPopup(this.showShelfLayoutMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.shelfLayoutMenuContent()
    }, Placement.BottomRight, this.appDarkMode, ThemeRuntime.accentColor(this.appDarkMode), () => {
      this.showShelfLayoutMenu = false;
    }))
  }

  @Builder
  shelfLayoutMenuContent() {
    Column() {
      ForEach(['companion', 'tile', 'loose', 'compact'], (layout: string) => {
        PopupMenuAction(undefined, this.shelfLayoutLabel(layout), layout === this.previewShelfLayout ?
          ThemeRuntime.accentColor(this.appDarkMode) : this.primaryTextColor(), () => {
          this.showShelfLayoutMenu = false;
          this.previewShelfLayout = layout;
        }, true, layout === this.previewShelfLayout ? '当前' : '')
      }, (layout: string) => `shelf_layout_menu_${layout}_${this.previewShelfLayout}`)
    }
    .width(140)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  previewSurface(expanded: boolean) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.assetRevision >= 0) {
        this.previewSurfaceContent(expanded)
      }
    }
    .width('100%')
    .height(expanded ? '100%' : (this.previewShrunk ? 112 : this.compactPreviewHeight()))
    // 只认横向滑动，竖向留给列表滚动。
    .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 24 })
      .onActionEnd((event: GestureEvent) => {
        if (!expanded && Math.abs(event.offsetX) > 24) this.stepPreviewScene(event.offsetX < 0);
      }))
  }

  @Builder
  previewSurfaceContent(expanded: boolean) {
    CustomThemePreview({
      themePack: this.customPreviewTheme(),
      previewDark: this.selectedMode === 'dark',
      scene: this.previewScene,
      expanded: expanded,
      startupImagePath: this.currentStartupImagePath(),
      startupTitle: this.currentStartupTitle(),
      startupSubtitle: this.currentStartupSubtitle(),
      startupTitleColor: this.currentStartupText().titleColor,
      startupSubtitleColor: this.currentStartupText().subtitleColor,
      startupTitleSize: this.currentStartupText().titleSize,
      startupSubtitleSize: this.currentStartupText().subtitleSize,
      ttsThemeId: this.currentSources().ttsPanelThemeId || this.currentSources().readerThemeId,
      homeBackdropThemeId: this.currentSources().homeBackdropThemeId,
      readerSettings: this.readerProfile,
      useReaderProfile: this.readerProfileBound,
      shelfLayout: this.previewShelfLayout,
      schemeName: this.schemeName,
      cardImagePath: this.previewImagePath,
      logoThemeId: this.ownLogo() ? this.ownThemeId() : '',
      assetRevision: this.assetRevision
    })
      .width('100%')
      .height('100%')
  }

  compactPreviewHeight(): number {
    // 给分组设置和软键盘保留空间，横屏或小窗口下也能继续滚动编辑。
    return Math.max(136, Math.min(208, this.viewportHeight > 0 ? this.viewportHeight * 0.26 : 208));
  }

  compactEditor(): boolean {
    return this.viewportHeight > 0 && this.viewportHeight < 520;
  }
}
