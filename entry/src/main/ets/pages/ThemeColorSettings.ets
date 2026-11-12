import { promptAction, router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../utils/CustomThemeSchemeStore';
import { AdaptiveColorPicker } from '../components/AdaptiveColorPicker';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import {
  ThemeBubbleStyleLabels,
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
import { InstalledThemePack, ThemeImageSlots, ThemePackRegistry } from '../theme/ThemePackRegistry';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { StartupCoverImageStore } from '../utils/StartupCoverImageStore';
import { SchemeAssetResult, SchemeAssetService, SchemeFontOption } from '../utils/SchemeAssetService';
import { SchemePreviewImageStore } from '../utils/SchemePreviewImageStore';
import { packReaderBackgroundId, ThemeImageCrop, ThemePackageLimits } from '../theme/share/ThemePackageFormat';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow } from '../components/common/SettingRow';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { CustomThemePreview } from '../components/theme/CustomThemePreview';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ThemeCropRequest, ThemeImageCropper } from '../components/theme/ThemeImageCropper';
import { ThemeCroppedImage } from '../components/theme/ThemeCroppedImage';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { TtsPanelThemeStyles } from '../theme/TtsPanelThemeStyles';
import { HexColor } from '../utils/HexColor';
import { AnimatedImagePolicy } from '../utils/AnimatedImagePolicy';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';

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
  // 动图取景记下的显示区域，按区域显示缩略图。
  crop?: ThemeImageCrop | null;
}

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

/** 编辑器顶部的建议：只提醒、不拦保存，点了跳到对应页签。 */
class ThemeEditorIssue {
  text: string = '';
  detail: string = '';
  section: string = '';
  swatch: string = '';
}

class ThemeEditorUndoEntry {
  settings: AppThemeSettings = new AppThemeSettings();
  mode: string = 'light';
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
  .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
  .backgroundColor(color)
  .borderRadius(ThemeRuntime.cardRadius())
  .clip(true)
}

/** 取景结果：要导入的文件，以及动图取景记下的显示区域（静图已经裁进文件，为 null）。 */
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
  // 方案自己上传的素材所在的包；空表示还没上传过。
  @State ownPackageId: string = '';
  @StorageLink('installedThemePacksRevision') installedPacksRevision: number = 0;
  // 素材上传/移除只改包与草稿，不改其他状态；靠它让预览和上传行重绘。
  @State assetRevision: number = 0;
  @State appFontFamily: string = '';
  @State fontLibrary: SchemeFontOption[] = [];
  @State radiusOverride: ThemeRadiusOverrides = new ThemeRadiusOverrides();
  @State lightStartupText: ThemeStartupTextStyle = new ThemeStartupTextStyle();
  @State darkStartupText: ThemeStartupTextStyle = new ThemeStartupTextStyle();
  @State previewImagePath: string = '';
  @State availableThemes: ThemePack[] = [];
  @State editorSection: string = '';
  @State previewScene: string = 'bookshelf';
  @State fullPreview: boolean = false;
  @State undoAvailable: boolean = false;
  @State schemeName: string = '';
  @State editorReady: boolean = false;
  @State saving: boolean = false;
  @State saveFailed: boolean = false;
  @State readerProfile: ReaderSettings = new ReaderSettings();
  @State readerProfileBound: boolean = false;
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
  @State checksExpanded: boolean = false;
  // 素材尺寸类建议要读图片，异步算好放这里；颜色类建议随状态即时算。
  @State assetIssues: ThemeEditorIssue[] = [];
  @State previewShelfLayout: string = 'companion';
  @State showSceneMenu: boolean = false;
  @State showShelfLayoutMenu: boolean = false;
  private schemeId: string = '';
  private cropResolve: ((result: string) => void) | null = null;
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
    this.syncBars();
  }

  onBackPress(): boolean {
    if (this.cropVisible) {
      this.finishCrop('');
      return true;
    }
    this.handleBack();
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: this.fullPreview ? '主题预览' : this.sectionName(),
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
    }
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
      this.modeOptions()
      if (this.fullPreview) {
        Column() {
          this.previewSurface(true)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        this.sceneGrid()
      } else {
        if (this.editorSection) {
          if (!this.compactEditor()) {
            this.previewPanel()
          }
          this.sectionTabs()
        }
        Scroll(this.editorScroller) {
          Column() {
            if (this.editorSection && this.compactEditor()) {
              this.previewPanel()
            }
            if (this.editorReady && this.advancedLocked()) {
              this.advancedNotice()
            }
            if (this.editorReady && this.editorSection && this.editorSection !== 'typography') {
              this.issuesBanner()
            }
            if (!this.editorReady) {
              this.sectionTitle({ title: '正在读取主题方案…' })
            } else if (!this.editorSection) {
              this.overviewContent()
              this.previewPanel()
            } else if (this.editorSection === 'colors') {
              this.colorSection()
            } else if (this.editorSection === 'reading') {
              this.readingSection()
            } else if (this.editorSection === 'home') {
              this.homeSection()
            } else if (this.editorSection === 'cover') {
              this.coverSection()
            } else {
              this.typographySection()
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
      this.previewScene = this.sceneForSource(category);
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

  sectionName(): string {
    if (this.editorSection === 'colors') return '配色';
    if (this.editorSection === 'reading') return '阅读与朗读';
    if (this.editorSection === 'home') return '首页与书架';
    if (this.editorSection === 'cover') return '封面与信息';
    if (this.editorSection === 'typography') return '字体与排版';
    return '编辑主题';
  }

  openSection(section: string): void {
    this.editorSection = section;
    this.previewScene = section === 'cover' ? 'startup' :
      (section === 'reading' || section === 'typography' ? 'reader' : 'bookshelf');
    this.editorScroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  handleBack(): void {
    if (this.fullPreview) {
      this.fullPreview = false;
    } else if (this.editorSection) {
      this.editorSection = '';
      this.editorScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    } else {
      this.closeEditor();
    }
  }

  sceneForSource(category: string): string {
    if (category === 'startup') return 'startup';
    if (category === 'ttsPanel' || category === 'glass') return 'tts';
    if (category === 'reader' || category === 'bubble' || category === 'layout') return 'reader';
    return 'bookshelf';
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
      this.readerProfile = await ReaderSettingsStore.loadProfile(getContext(this), profileId);
    } catch (e) {
      console.warn('读取主题排版预览失败:', e);
    }
  }

  async openTypography(): Promise<void> {
    if (!this.editorReady || this.closing) return;
    await this.onSettingChanged();
    if (this.saveFailed) {
      HdsFeedback.showToast('保存主题方案失败，请重试');
      return;
    }
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
    Row({ space: AppSpacing.MD }) {
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

  @Builder
  overviewContent() {
    this.sectionTitle({ title: this.schemeName })
    Column() {
      SettingNavRow({ title: '配色', description: '完整配色、强调色与按钮色',
        onTap: () => this.openSection('colors') })
      SettingNavRow({ title: '阅读与朗读', description: '阅读背景与颜色、强调气泡、朗读面板',
        onTap: () => this.openSection('reading') })
      SettingNavRow({ title: '首页与书架', description: '导航图标、封面与书架素材、首页背景、圆角',
        onTap: () => this.openSection('home') })
      SettingNavRow({ title: '封面与信息', description: '启动封面、主题标识与预览图、作者和说明',
        onTap: () => this.openSection('cover') })
      SettingNavRow({ title: '字体与排版', description: '应用字体、阅读排版与页面边距',
        showDivider: false, onTap: () => this.openSection('typography') })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
  }

  @Builder
  sectionTabs() {
    Row({ space: AppSpacing.XS }) {
      this.sectionTab('配色', 'colors')
      this.sectionTab('阅读', 'reading')
      this.sectionTab('首页', 'home')
      this.sectionTab('封面', 'cover')
      this.sectionTab('排版', 'typography')
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.XS })
  }

  @Builder
  sectionTab(label: string, section: string) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(40)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.editorSection === section ? ThemeRuntime.accentColor(this.appDarkMode) : this.subTextColor())
      .backgroundColor(this.editorSection === section ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
      .borderRadius(ThemeRuntime.mediumRadius())
      .accessibilitySelected(this.editorSection === section)
      .onClick(() => this.openSection(section))
  }

  @Builder
  colorSection() {
    this.sectionTitle({ title: `${this.selectedMode === 'dark' ? '深色' : '浅色'}模式 · 配色` })
    Column() {
      this.componentSourceRow('完整配色', '页面、卡片、文字与基础颜色', 'palette', false)
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    Column() {
      this.colorOptions()
      Row({ space: AppSpacing.XL }) {
        Text('主要按钮')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor())
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
          .backgroundColor(this.currentButtonColor())
          .borderRadius(this.customPreviewTheme().radius.button)
        Text('强调文字')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.currentAccentColor())
      }
      .width('100%')
      .padding(AppSpacing.XL)
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    this.sectionTitle({ title: '逐项覆盖 · 没改过的颜色跟随上面所选的主题' })
    Column() {
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
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    this.sectionTitle({ title: '浅色与深色模式独立保存，可分别调整' })
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
      showDivider: AppThemeSettingsStore.hasEmphasisOverride(this.currentEmphasis()),
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        this.setEmphasisColor(true, color);
      }
    })
  }

  @Builder
  typographySection() {
    this.sectionTitle({ title: '字体与排版' })
    Column() {
      this.componentSourceRow('应用字体', '主题自带的应用字体风格', 'typography')
      this.appFontRow()
      this.componentSourceRow('推荐阅读排版', '字号、行距、段距和页面边距，浅深共用', 'layout')
      SettingNavRow({ title: '详细阅读排版', description: '正文与标题字体、间距、页眉页脚等',
        showDivider: false, onTap: () => this.openTypography() })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    this.sectionTitle({ title: this.readerProfileBound ? '已保存这套主题的阅读排版，浅深色模式共用' :
      '阅读排版在浅深色模式间共用，可进入详细阅读排版继续调整' })
  }

  @Builder
  sectionTitle($$: ThemeEditorSectionTitleOptions) {
    Text($$.title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  modeOptions() {
    Row() {
      ImmersiveMaterialSurface({
        surfaceWidth: Math.max(40, this.viewportWidth - AppSpacing.LG * 2), surfaceHeight: 44, darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(), glowColor: `#40${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`
      }) {
        Row({ space: AppSpacing.XS }) {
          this.modeButton('浅色模式', 'light')
          this.modeButton('深色模式', 'dark')
        }
        .width('100%')
        .height('100%')
        .padding(AppSpacing.XS)
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XS, bottom: AppSpacing.XS })
  }

  @Builder
  modeButton(title: string, mode: string) {
    Stack({ alignContent: Alignment.Center }) {
      Text(title)
        .fontSize(AppFontSize.BODY)
          .fontColor(this.selectedMode === mode ? ThemeRuntime.accentColor(this.appDarkMode) : this.subTextColor())
    }
      .layoutWeight(1)
      .height(36)
      .borderRadius(19)
      .backgroundColor(this.selectedMode === mode ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
      .accessibilityText(title)
      .accessibilitySelected(this.selectedMode === mode)
      .onClick(() => {
        this.selectedMode = mode;
      })
  }

  // ---- 页签：阅读与朗读 ----

  @Builder
  readingSection() {
    this.sectionTitle({ title: `阅读背景 · ${this.modeLabel()}` })
    Column() {
      this.componentSourceRow('来源', '换来源时，阅读颜色和背景素材一起换成它的', 'reader')
      this.readerColorRows()
      if (this.assetRevision >= 0) {
        this.readerSlots()
      }
    }
    .editorCard(this.cardColor())
    this.sectionTitle({ title: '强调气泡' })
    Column() {
      this.componentSourceRow('来源', '正文强调方式、气泡样式及气泡配色', 'bubble')
      this.emphasisOverrideRows()
      if (this.assetRevision >= 0) {
        this.bubbleSlots()
      }
    }
    .editorCard(this.cardColor())
    this.sectionTitle({ title: `朗读 / 有声书面板 · ${this.modeLabel()}` })
    Column() {
      this.componentSourceRow('来源', '面板的背景插画与底色', 'ttsPanel')
      if (this.assetRevision >= 0) {
        this.ttsSlots()
      }
    }
    .editorCard(this.cardColor())
    this.sectionTitle({ title: '浅色与深色模式分别保存，切换顶部的模式分别调整' })
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

  ownPackVariantTrailingSeparate(): boolean {
    const pack = this.ownPack();
    if (!pack) return false;
    const reader = pack.reader(this.selectedMode === 'dark');
    return reader.mode === 'ornaments' && !!reader.trailing && reader.trailing !== reader.leading;
  }

  readerSlotState(slot: string): string {
    const mode = this.ownReaderMode();
    const id = this.readerAssetId();
    if (slot === 'image') {
      if (mode === 'image') return 'own';
      return ThemeColorSettingsPage.hasImage(ThemeAssetRegistry.readerBackground(id)) ? 'inherit' : 'empty';
    }
    if (slot === 'trailing') {
      if (mode === 'ornaments' && this.ownPackVariantTrailingSeparate()) return 'own';
      return ThemeColorSettingsPage.hasImage(ThemeAssetRegistry.readerBackgroundTrailingDecoration(id)) ? 'inherit' : 'empty';
    }
    if (mode === 'ornaments') return 'own';
    return ThemeColorSettingsPage.hasImage(ThemeAssetRegistry.readerBackgroundDecoration(id)) ? 'inherit' : 'empty';
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
      Text('不单独传右下角饰时，用左上角那张旋转 180°；整图会替换角饰')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
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
    if (this.ownReaderMode()) {
      this.resetRow(`恢复为所选主题的${this.modeLabel()}阅读背景`, () => this.clearReaderAssets())
    }
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
    if (this.readerSlotState(slot) !== 'own') {
      if (!(await this.ensureAdvanced())) return;
      if (slot === 'image') await this.uploadReaderImage();
      else await this.uploadReaderOrnament(slot === 'trailing');
      return;
    }
    if (slot === 'trailing') {
      const choice = await this.slotMenu(`${this.modeLabel()} · 右下角饰`, '替换', '移除，改用左上角那张旋转');
      if (choice === 0) await this.replaceGuarded(() => this.uploadReaderOrnament(true));
      else if (choice === 1) await this.clearReaderSlot('trailing');
      return;
    }
    const name = slot === 'image' ? '整图背景' : '角饰';
    const choice = await this.slotMenu(`${this.modeLabel()} · ${name}`, '替换', `${other}模式也用这套`,
      `移除${name}`);
    if (choice === 0) {
      await this.replaceGuarded(() => slot === 'image' ? this.uploadReaderImage() : this.uploadReaderOrnament(false));
    } else if (choice === 1) {
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.copyToOtherMode(getContext(this), this.schemeId, 'reader', dark), '', false, false, '');
      if (this.ownPackageId) {
        this.rememberChange();
        this.setReaderBackgroundAssetFor(!dark, packReaderBackgroundId(this.ownPackageId, !dark));
        HdsFeedback.showToast(`${other}模式的阅读背景已换成同一套`);
      }
    } else if (choice === 2) {
      await this.clearReaderSlot(slot);
    }
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
        state: this.ownBubbleActive() ? 'own' : (ThemeColorSettingsPage.hasImage(this.bubbleCapImage()) ? 'inherit' : 'empty'),
        slotWidth: 56, slotHeight: 56, onTap: () => this.tapBubbleSlot(false) })
      this.assetSlot({ label: '边框', image: this.bubbleFrameImage(),
        state: this.ownBubbleActive() && !!this.ownPack()?.bubbleFrame ? 'own' :
          (ThemeColorSettingsPage.hasImage(this.bubbleFrameImage()) ? 'inherit' : 'empty'),
        slotWidth: 56, slotHeight: 56, onTap: () => this.tapBubbleSlot(true) })
      Text('正方形 SVG 端饰放在强调文字两端，右端自动旋转；边框可选')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
  }

  bubbleCapImage(): ResourceStr {
    const style = this.effectiveEmphasis().bubbleStyle;
    return ThemeAssetRegistry.hasRegexBubbleCap(style) ? ThemeAssetRegistry.regexBubbleCap(style) : '';
  }

  bubbleFrameImage(): ResourceStr {
    const style = this.effectiveEmphasis().bubbleStyle;
    return ThemeAssetRegistry.hasRegexBubbleFrame(style) ? ThemeAssetRegistry.regexBubbleFrame(style) : '';
  }

  async tapBubbleSlot(frame: boolean): Promise<void> {
    const pack = this.ownPack();
    const own = this.ownBubbleActive() && (!frame || (!!pack && !!pack.bubbleFrame));
    if (!own) {
      if (!(await this.ensureAdvanced())) return;
      if (frame) await this.uploadBubbleFrame();
      else await this.uploadBubbleCap();
      return;
    }
    const choice = await this.slotMenu(frame ? '气泡边框' : '气泡端饰', '替换', frame ? '移除边框' : '移除端饰和边框');
    if (choice === 0) {
      await this.replaceGuarded(() => frame ? this.uploadBubbleFrame() : this.uploadBubbleCap());
    } else if (choice === 1) {
      if (frame) {
        await this.runAssetClear((): Promise<SchemeAssetResult> =>
          SchemeAssetService.clearBubbleFrame(getContext(this), this.schemeId), '');
      } else {
        await this.clearBubbleAssets();
      }
    }
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

  @Builder
  homeSection() {
    this.sectionTitle({ title: '导航图标' })
    Column() {
      this.componentSourceRow('来源', '书架、发现和我的底部图标', 'navigation')
      if (this.assetRevision >= 0) {
        this.navigationSlots()
      }
    }
    .editorCard(this.cardColor())
    this.sectionTitle({ title: '书籍素材' })
    Column() {
      this.componentSourceRow('来源', '主题封面、书架边框和文件夹图案', 'book')
      if (this.assetRevision >= 0) {
        this.bookSlots()
      }
    }
    .editorCard(this.cardColor())
    this.sectionTitle({ title: `首页背景 · ${this.modeLabel()}` })
    Column() {
      this.componentSourceRow('来源', '选没有背景图的主题即不显示', 'homeBackdrop')
      if (this.assetRevision >= 0) {
        this.homeBackdropSlot()
      }
    }
    .editorCard(this.cardColor())
    this.sectionTitle({ title: '圆角 · 浅深共用' })
    Column() {
      this.componentSourceRow('来源', '卡片、按钮、气泡等圆角尺寸', 'radius')
      this.radiusRows()
    }
    .editorCard(this.cardColor())
  }

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
    return 'SVG 跟随主题色着色；PNG / WebP 保持原色。选中态没给的页签，选中时仍用普通图标。' +
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
    const uris = await SchemeAssetService.pickIconFiles(getContext(this), 1);
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

  ownCoverPaths(): string[] {
    const pack = this.ownPack();
    if (!this.ownBookActive() || !pack || !pack.record.parts.book) return [];
    return pack.record.parts.book.covers.slice();
  }

  inheritedCovers(): ResourceStr[] {
    return ThemeAssetRegistry.themeBookCovers(this.customPreviewTheme().book.coverAssetId).slice(0, 4);
  }

  @Builder
  bookSlots() {
    Column({ space: AppSpacing.SM }) {
      Row() {
        Text(`封面 ${this.ownCoverPaths().length} / ${ThemePackageLimits.MAX_COVERS}`)
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
          }, (path: string, index: number) => `cover_${index}_${path}_${this.assetRevision}`)
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
          }, (_cover: ResourceStr, index: number) => `inherited_cover_${index}_${this.assetRevision}`)
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
      if (this.ownCoverPaths().length === 0 && this.inheritedCovers().length > 0) {
        Text(`淡显的是「${BuiltinThemeRegistry.findById(this.sourceThemeId('book')).name}」的封面，上传后换成自己的`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
      }
      Row({ space: AppSpacing.XL }) {
        this.assetSlot({ label: '书架边框', image: this.shelfFrameImage(), state: this.shelfPartState(false),
          slotWidth: 50, slotHeight: 74, onTap: () => this.tapShelfPart(false) })
        this.assetSlot({ label: '分组文件夹', image: this.shelfFolderImage(), state: this.shelfPartState(true),
          slotWidth: 50, slotHeight: 74, onTap: () => this.tapShelfPart(true),
          crop: ThemeAssetRegistry.imageCrop(ThemeImageSlots.FOLDER, this.shelfFolderImage()) })
        Text('边框是 SVG，与封面同比例、中心透明；文件夹是 450 × 660 位图')
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
    if (this.ownBookActive()) {
      this.resetRow('移除全部上传的书籍素材', () => this.clearBookAssets())
    }
  }

  @Builder
  coverTile($$: CoverTileOptions) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (ThemeAssetRegistry.imageCrop(ThemeImageSlots.COVER, $$.uri)) {
        ThemeCroppedImage({ src: $$.uri,
          crop: ThemeAssetRegistry.imageCrop(ThemeImageSlots.COVER, $$.uri) as ThemeImageCrop })
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
    .onClick(() => this.tapCover($$.index))
  }

  shelfFrameImage(): ResourceStr {
    const id = this.customPreviewTheme().book.shelfFrameAssetId;
    return id ? ThemeAssetRegistry.themeShelfFrame(id) : '';
  }

  shelfFolderImage(): ResourceStr {
    const id = this.customPreviewTheme().book.shelfFolderAssetId;
    return id ? ThemeAssetRegistry.themeShelfFolder(id) : '';
  }

  shelfPartState(folder: boolean): string {
    const pack = this.ownPack();
    const book = pack ? pack.record.parts.book : null;
    if (this.ownBookActive() && book && (folder ? book.shelfFolder : book.shelfFrame)) return 'own';
    return ThemeColorSettingsPage.hasImage(folder ? this.shelfFolderImage() : this.shelfFrameImage()) ? 'inherit' : 'empty';
  }

  async tapShelfPart(folder: boolean): Promise<void> {
    if (this.shelfPartState(folder) !== 'own') {
      if (!(await this.ensureAdvanced())) return;
      if (folder) await this.uploadShelfFolder();
      else await this.uploadShelfFrame();
      return;
    }
    const choice = await this.slotMenu(folder ? '分组文件夹' : '书架边框', '替换', '移除');
    if (choice === 0) {
      await this.replaceGuarded(() => folder ? this.uploadShelfFolder() : this.uploadShelfFrame());
    } else if (choice === 1) {
      await this.runAssetClear((): Promise<SchemeAssetResult> => folder ?
        SchemeAssetService.clearShelfFolder(getContext(this), this.schemeId) :
        SchemeAssetService.clearShelfFrame(getContext(this), this.schemeId), 'book');
    }
  }

  async tapCover(index: number): Promise<void> {
    const choice = index > 0 ?
      await this.slotMenu(`第 ${index + 1} 张封面`, '替换这张', '移到第一张', '删除这张') :
      await this.slotMenu('第 1 张封面', '替换这张', '删除这张');
    const action = index > 0 ? choice : (choice === 1 ? 2 : choice);
    if (action === 0) {
      if (!(await this.ensureAdvanced())) return;
      const uris = await SchemeAssetService.pickImages(getContext(this), 1);
      if (uris.length === 0) return;
      const framed = await this.frameImage(uris[0], '封面取景', 450, 660, 450, false);
      if (!framed) return;
      await this.runAssetUpload((): Promise<SchemeAssetResult> =>
        SchemeAssetService.replaceCover(getContext(this), this.schemeId, index, framed.path, framed.crop), 'book',
        true, true, '封面已替换');
      this.discardCropFile(framed.path, uris[0]);
    } else if (action === 1) {
      await this.moveCover(index, 0);
    } else if (action === 2) {
      await this.runAssetClear((): Promise<SchemeAssetResult> =>
        SchemeAssetService.removeCover(getContext(this), this.schemeId, index), 'book');
    }
  }

  async moveCover(from: number, to: number): Promise<void> {
    if (from === to) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.moveCover(getContext(this), this.schemeId, from, to), '', false, false, '');
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

  @Builder
  homeBackdropSlot() {
    Row({ space: AppSpacing.XL }) {
      this.assetSlot({ label: '4 : 5', image: this.homeBackdropImage(),
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
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
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

  @Builder
  coverSection() {
    this.sectionTitle({ title: `启动封面 · ${this.modeLabel()}` })
    Column() {
      this.componentSourceRow('来源', '插画与应用标识', 'startup')
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
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.SM })
      this.startupTextInputs()
    }
    .editorCard(this.cardColor())
    this.sectionTitle({ title: '文案样式 · 不改时跟随默认（白字）' })
    this.startupTextStyleOptions()
    this.sectionTitle({ title: '主题卡片' })
    Column() {
      if (this.assetRevision >= 0) {
        this.brandSlots()
      }
    }
    .editorCard(this.cardColor())
    this.sectionTitle({ title: '方案信息' })
    Column() {
      this.infoInputs()
    }
    .editorCard(this.cardColor())
  }

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
      Text('标识是卡片右上角和详情页名字旁的小图（正方形 SVG 或透明 PNG）。没有预览图时卡片显示启动封面')
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
    const uris = await SchemeAssetService.pickIconFiles(getContext(this), 1);
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
      const add = (text: string, detail: string, section: string, swatch: string): void => {
        const issue = new ThemeEditorIssue();
        issue.text = `${label} · ${text}`;
        issue.detail = detail;
        issue.section = section;
        issue.swatch = swatch;
        issues.push(issue);
      };
      const body = ThemeColorSettingsPage.contrast(reader.textColor, reader.backgroundColor);
      if (body < 4.5) add(`正文与阅读底色对比 ${body.toFixed(1)}`, '低于 4.5，长时间读会累', 'reading', reader.textColor);
      const header = ThemeColorSettingsPage.contrast(reader.subTextColor, reader.backgroundColor);
      if (header < 3) add(`页眉页脚与阅读底色对比 ${header.toFixed(1)}`, '低于 3，页码和时间可能看不清', 'reading', reader.subTextColor);
      const primary = ThemeColorSettingsPage.contrast(colors.primaryTextColor, colors.pageColor);
      if (primary < 4.5) add(`主文字与页面对比 ${primary.toFixed(1)}`, '低于 4.5，列表文字不够清楚', 'colors', colors.primaryTextColor);
      const sub = ThemeColorSettingsPage.contrast(colors.subTextColor, colors.pageColor);
      if (sub < 3) add(`辅助文字与页面对比 ${sub.toFixed(1)}`, '低于 3，说明文字可能看不清', 'colors', colors.subTextColor);
    }
    if (this.ownNavigationActive()) {
      const missing = ['bookshelf', 'explore', 'mine'].filter((key: string): boolean => !this.navSlotValue(key));
      if (missing.length > 0) {
        const issue = new ThemeEditorIssue();
        issue.text = `导航图标还差 ${missing.length} 个`;
        issue.detail = '缺的先用基底主题的图标，传齐之前分享导出时不带导航图标';
        issue.section = 'home';
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
        section: string): Promise<void> => {
        if (!relativePath || relativePath.endsWith('.svg')) return;
        const size = await ThemeColorSettingsPage.imageSize(`${pack.dir}/${relativePath}`);
        if (size.length < 2 || (size[0] >= minWidth * 0.75 && size[1] >= minHeight * 0.75)) return;
        const issue = new ThemeEditorIssue();
        issue.text = `${label}只有 ${size[0]} × ${size[1]}`;
        issue.detail = `小于 ${minWidth} × ${minHeight}，屏幕上会发虚`;
        issue.section = section;
        issues.push(issue);
      };
      if (parts.book) {
        for (let index = 0; index < parts.book.covers.length; index++) {
          await check(parts.book.covers[index], `第 ${index + 1} 张封面`, 450, 660, 'home');
        }
        await check(parts.book.shelfFolder, '文件夹插画', 450, 660, 'home');
      }
      await check(parts.homeBackdropLight, '浅色首页背景', 1080, 1350, 'home');
      await check(parts.homeBackdropDark, '深色首页背景', 1080, 1350, 'home');
      if (parts.ttsPanelLight) await check(parts.ttsPanelLight.artwork, '浅色面板插画', 720, 520, 'reading');
      if (parts.ttsPanelDark) await check(parts.ttsPanelDark.artwork, '深色面板插画', 720, 520, 'reading');
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

  @Builder
  issuesBanner() {
    if (this.editorIssues().length > 0) {
      Column() {
        Row({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(16)
            .fontColor([this.warnText()])
          Text(this.checksExpanded ? `${this.editorIssues().length} 项建议` :
            `${this.editorIssues().length} 项建议 · ${this.editorIssues()[0].text}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.warnText())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.checksExpanded) {
            SymbolGlyph($r('sys.symbol.chevron_up'))
              .fontSize(14)
              .fontColor([this.warnText()])
          } else {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([this.warnText()])
          }
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
        .accessibilityText(this.checksExpanded ? '收起建议' : '展开建议')
        .onClick(() => {
          this.checksExpanded = !this.checksExpanded;
        })
        if (this.checksExpanded) {
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
              if (issue.section !== this.editorSection) {
                Text('去看看')
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
            .onClick(() => {
              if (issue.section !== this.editorSection) this.openSection(issue.section);
            })
          }, (issue: ThemeEditorIssue) => issue.text)
          Text('只做提醒，不影响保存')
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.warnText())
            .width('100%')
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.MD })
        }
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
      .borderRadius(ThemeRuntime.cardRadius())
      .backgroundColor(this.warnSurface())
      .clip(true)
    }
  }

  @Builder
  componentSourceRow(title: string, desc: string, category: string, divider: boolean = true) {
    SettingRow({ title: title, description: desc, showDivider: divider }) {
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

  @Builder
  advancedNotice() {
    Text('浅色显示的高级选项为会员专享，点开可了解会员')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD })
      .onClick(() => {
        this.ensureAdvanced();
      })
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
    if (category === 'homeBackdrop') return !!(dark ? parts.homeBackdropDark : parts.homeBackdropLight);
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

  async runAssetClear(action: () => Promise<SchemeAssetResult>, category: string): Promise<void> {
    const previous = this.ownThemeId();
    const fallback = SchemeAssetService.baseThemeOf(this.ownPackageId);
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
    const room = ThemePackageLimits.MAX_COVERS - SchemeAssetService.coverCount(this.ownPackageId);
    if (room <= 0) {
      HdsFeedback.showToast(`封面最多 ${ThemePackageLimits.MAX_COVERS} 张，请先移除`);
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
      SchemeAssetService.addCovers(getContext(this), this.schemeId, uris, this.sourceThemeId('book'), crops),
      'book', true, true, `已加入 ${uris.length} 张封面`);
    for (let index = 0; index < uris.length; index++) this.discardCropFile(uris[index], '');
  }

  async uploadShelfFrame(): Promise<void> {
    const uris = await SchemeAssetService.pickSvgFiles(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setShelfFrame(getContext(this), this.schemeId, uris[0], this.sourceThemeId('book')),
      'book', true, true, '书架边框已更新');
  }

  async uploadShelfFolder(): Promise<void> {
    const picked = await SchemeAssetService.pickImages(getContext(this), 1);
    if (picked.length === 0) return;
    const framed = await this.frameImage(picked[0], '文件夹插画取景', 450, 660, 450, true);
    if (!framed) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setShelfFolder(getContext(this), this.schemeId, framed.path, this.sourceThemeId('book'),
        framed.crop),
      'book', true, true, '文件夹插画已更新');
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

  async uploadReaderOrnament(trailing: boolean): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const uris = await SchemeAssetService.pickImages(getContext(this), 1);
    if (uris.length === 0) return;
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
    const uris = await SchemeAssetService.pickIconFiles(getContext(this), SchemeAssetService.NAVIGATION_TABS.length);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setNavigation(getContext(this), this.schemeId, uris, this.sourceThemeId('navigation')),
      'navigation', true, true, '导航图标已更新');
  }

  async uploadTtsArtwork(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const picked = await SchemeAssetService.pickImages(getContext(this), 1);
    if (picked.length === 0) return;
    const path = await this.cropImage(picked[0], '面板插画取景', 720, 520, 720, true);
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

  async uploadHomeBackdrop(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const picked = await SchemeAssetService.pickImages(getContext(this), 1);
    if (picked.length === 0) return;
    const framed = await this.frameImage(picked[0], '首页背景取景', 1080, 1350, 1080, false);
    if (!framed) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setHomeBackdrop(getContext(this), this.schemeId, framed.path, dark,
        this.sourceThemeId('homeBackdrop'), framed.crop),
      'homeBackdrop', !dark, dark, `${dark ? '深色' : '浅色'}首页背景已更新`);
    this.discardCropFile(framed.path, picked[0]);
  }

  async clearHomeBackdrop(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    await this.runAssetClear((): Promise<SchemeAssetResult> =>
      SchemeAssetService.clearHomeBackdrop(getContext(this), this.schemeId, dark), 'homeBackdrop');
  }

  async uploadBubbleCap(): Promise<void> {
    const uris = await SchemeAssetService.pickSvgFiles(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setBubbleCap(getContext(this), this.schemeId, uris[0], this.sourceThemeId('bubble')),
      '', false, false, '');
    if (this.ownThemeId()) this.applyPackBubbleStyle(this.ownThemeId());
    HdsFeedback.showToast('气泡端饰已更新');
  }

  async uploadBubbleFrame(): Promise<void> {
    if (!SchemeAssetService.hasBubble(this.ownPackageId)) {
      HdsFeedback.showToast('请先上传气泡端饰');
      return;
    }
    const uris = await SchemeAssetService.pickSvgFiles(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setBubbleFrame(getContext(this), this.schemeId, uris[0], this.sourceThemeId('bubble')),
      '', false, false, '气泡边框已更新');
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
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
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
        Text(`预览 · ${this.selectedMode === 'dark' ? '深色' : '浅色'}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .layoutWeight(1)
        this.sceneMenuButton()
        ImmersiveHeaderAction({ label: '放大预览', accessibilityLabel: '放大主题预览',
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

  sceneIcon(scene: string): Resource {
    if (scene === 'explore') return $r('sys.symbol.square_grid_2x2');
    if (scene === 'mine') return $r('sys.symbol.person');
    if (scene === 'reader') return $r('sys.symbol.book_pages');
    if (scene === 'tts') return $r('sys.symbol.earphone');
    if (scene === 'startup') return $r('sys.symbol.picture');
    if (scene === 'card') return $r('sys.symbol.rectangle_3_group');
    return $r('sys.symbol.bookshelf');
  }

  /** 沉浸光感胶囊的宽度：悬浮材质只接受具体宽度，中文按字号估算。 */
  capsuleWidth(label: string, fontSize: number, extra: number): number {
    let textWidth = 0;
    for (const char of label) {
      textWidth += char.charCodeAt(0) > 0xFF ? fontSize : fontSize * 0.6;
    }
    return Math.ceil(textWidth) + extra;
  }

  /** 小预览的画面切换：标题行里的沉浸光感下拉按钮，窄屏也不挤。 */
  @Builder
  sceneMenuButton() {
    Column() {
      ImmersiveMaterialSurface({
        surfaceWidth: this.capsuleWidth(this.sceneLabel(this.previewScene), AppFontSize.BODY, 14 + AppSpacing.XS + 26),
        surfaceHeight: ImmersiveHeaderAction.SIZE, darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(), glowColor: `#40${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`
      }) {
        Row({ space: AppSpacing.XS }) {
          Text(this.sceneLabel(this.previewScene))
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([this.subTextColor()])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityGroup(true)
        .accessibilityText(`预览画面：${this.sceneLabel(this.previewScene)}，点按切换`)
        .onClick(() => {
          this.showSceneMenu = true;
        })
      }
    }
    .margin({ right: AppSpacing.SM })
    .bindPopup(this.showSceneMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.sceneMenuContent()
    }, Placement.BottomRight, this.appDarkMode, ThemeRuntime.accentColor(this.appDarkMode), () => {
      this.showSceneMenu = false;
    }))
  }

  @Builder
  sceneMenuContent() {
    Scroll() {
      Column() {
        ForEach(ThemeColorSettingsPage.SCENES, (scene: string) => {
          PopupMenuAction(this.sceneIcon(scene), this.sceneLabel(scene), scene === this.previewScene ?
            ThemeRuntime.accentColor(this.appDarkMode) : this.primaryTextColor(), () => {
            this.showSceneMenu = false;
            this.previewScene = scene;
          }, true, scene === this.previewScene ? '当前' : '')
        }, (scene: string) => `scene_menu_${scene}_${this.previewScene}`)
      }
      .width('100%')
    }
    .width(160)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
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
        // 补一个空格位，两行格子等宽对齐。
        Blank()
          .layoutWeight(1)
          .height(52)
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

  /** 书架画面右上角的布局按钮：沉浸光感胶囊，点开弹出菜单选四种书架布局。 */
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
    .margin(AppSpacing.SM)
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
      if (this.previewScene === 'bookshelf') {
        this.shelfLayoutButton(expanded)
      }
    }
    .width('100%')
    .height(expanded ? '100%' : this.compactPreviewHeight())
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
      logoThemeId: this.ownLogo() ? this.ownThemeId() : ''
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
