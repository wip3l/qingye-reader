import { router } from '@kit.ArkUI';
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
  ThemeStartupTextStyle
} from '../theme/ThemeModels';
import { ThemeAccessPolicy } from '../account/ThemeAccessPolicy';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ThemePackRegistry } from '../theme/ThemePackRegistry';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { StartupCoverImageStore } from '../utils/StartupCoverImageStore';
import { SchemeAssetResult, SchemeAssetService, SchemeFontOption } from '../utils/SchemeAssetService';
import { SchemePreviewImageStore } from '../utils/SchemePreviewImageStore';
import { packReaderBackgroundId, ThemePackageLimits } from '../theme/share/ThemePackageFormat';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow } from '../components/common/SettingRow';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { CustomThemePreview } from '../components/theme/CustomThemePreview';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';

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

@Entry
@Component
struct ThemeColorSettingsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appThemeId') appThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('accountEntitlementsRevision') accountEntitlementsRevision: number = 0;
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
  private schemeId: string = '';
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
        this.sceneOptions()
        this.previewSurface(true)
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
            if (!this.editorReady) {
              this.sectionTitle({ title: '正在读取主题方案…' })
            } else if (!this.editorSection) {
              this.overviewContent()
              this.previewPanel()
            } else if (this.editorSection === 'colors') {
              this.colorSection()
            } else if (this.editorSection === 'parts') {
              this.sourceOptions()
            } else if (this.editorSection === 'cover') {
              this.sectionTitle({ title: '启动封面' })
              Column() {
                this.componentSourceRow('封面主题', '插画与应用标识', 'startup', false)
              }
              .width('calc(100% - 24vp)')
              .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
              .backgroundColor(this.cardColor())
              .borderRadius(ThemeRuntime.cardRadius())
              this.startupCoverOptions()
              this.sectionTitle({ title: '文案样式 · 不改时跟随默认（白字）' })
              this.startupTextStyleOptions()
              this.sectionTitle({ title: '方案预览图 · 主题页卡片上显示，不传时用启动封面' })
              this.previewImageOptions()
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
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE && !AccountSessionStore.hasOwnedEntitlement(themeId)) {
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
    if (this.editorSection === 'parts') return '主题部件';
    if (this.editorSection === 'cover') return '启动封面';
    if (this.editorSection === 'typography') return '字体与排版';
    return '编辑主题';
  }

  openSection(section: string): void {
    this.editorSection = section;
    this.previewScene = section === 'cover' ? 'startup' :
      (section === 'parts' || section === 'typography' ? 'reader' : 'bookshelf');
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
      this.readerProfileBound = await ReaderSettingsStore.isTypographyBound(getContext(this), profileId);
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
      const imagePath = await StartupCoverImageStore.pickAndSave(getContext(this), this.schemeId, darkMode);
      if (!imagePath) return;
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
      if (theme.id === ThemeIds.OBSIDIAN_ARCHIVE && !AccountSessionStore.hasOwnedEntitlement(theme.id)) continue;
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
      sources.bookThemeId === themeId || sources.typographyThemeId === themeId ||
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
      SettingNavRow({ title: '主题部件', description: '阅读、朗读、导航与书籍素材',
        onTap: () => this.openSection('parts') })
      SettingNavRow({ title: '启动封面', description: '封面图片、主标题与副标题',
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
      this.sectionTab('部件', 'parts')
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
      this.paletteOverrideRow('页面底色', 'pageColor')
      this.paletteOverrideRow('卡片色', 'cardColor')
      this.paletteOverrideRow('输入框色', 'inputColor')
      this.paletteOverrideRow('正文字色', 'primaryTextColor')
      this.paletteOverrideRow('辅助文字色', 'subTextColor')
      this.paletteOverrideRow('分割线色', 'dividerColor')
      this.paletteOverrideRow('危险色', 'dangerColor')
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
  }

  paletteDescription(key: string): string {
    if (this.overrideValue(this.currentPalette(), key)) return '自定义';
    return `跟随「${BuiltinThemeRegistry.findById(this.currentSources().paletteThemeId).name}」`;
  }

  setPaletteColor(key: string, color: string): void {
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
    const normalized = AppThemeSettingsStore.normalizeColor(color, current);
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
      showDivider: AppThemeSettingsStore.hasEmphasisOverride(this.currentEmphasis()),
      appDarkMode: this.appDarkMode,
      cardColor: this.cardColor(),
      primaryTextColor: this.primaryTextColor(),
      accentColor: ThemeRuntime.accentColor(this.appDarkMode),
      onColorChange: (color: string) => {
        this.setEmphasisColor(true, color);
      }
    })
    if (AppThemeSettingsStore.hasEmphasisOverride(this.currentEmphasis())) {
      this.resetRow('恢复为所选主题的强调气泡', () => this.resetEmphasis())
    }
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
    this.sectionTitle({ title: this.readerProfileBound ? '已保存专属阅读排版，优先于主题推荐排版，浅深色模式共用' :
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

  @Builder
  sourceOptions() {
    this.sectionTitle({ title: '阅读体验' })
    Column() {
      this.componentSourceRow('阅读背景', '阅读背景、正文颜色和背景素材', 'reader')
      this.readerAssetRows()
      this.componentSourceRow('朗读/有声书面板', '朗读面板和有声书面板的背景插画与底色', 'ttsPanel')
      this.ttsAssetRows()
      this.componentSourceRow('强调气泡', '正文强调方式、气泡样式及气泡配色', 'bubble')
      this.emphasisOverrideRows()
      this.bubbleAssetRows()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
    this.sectionTitle({ title: '应用外观' })
    Column() {
      this.componentSourceRow('导航图标', '书架、发现、搜索和我的底部图标', 'navigation')
      this.navigationAssetRows()
      this.componentSourceRow('书籍素材', '主题封面、书架边框和文件夹图案', 'book')
      this.bookAssetRows()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
    this.sectionTitle({ title: '形状' })
    Column() {
      this.componentSourceRow('圆角形状', '卡片、按钮、气泡等圆角尺寸', 'radius')
      this.radiusRows()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
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
    const lightUses = this.sourceValueFor(this.lightSources, category) === previousThemeId;
    const darkUses = this.sourceValueFor(this.darkSources, category) === previousThemeId;
    if (!lightUses && !darkUses) return;
    this.applyPackSource(category, fallbackThemeId, lightUses, darkUses);
  }

  sourceValueFor(sources: ThemeComponentSourceIds, category: string): string {
    if (category === 'book') return sources.bookThemeId;
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
        for (const item of ['book', 'navigation', 'ttsPanel', 'bubble', 'reader', 'startup', 'palette']) {
          this.detachPackSource(item, previous, fallback);
        }
      }
      HdsFeedback.showToast('已移除上传的素材');
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
    const uris = await SchemeAssetService.pickImages(getContext(this), room);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.addCovers(getContext(this), this.schemeId, uris, this.sourceThemeId('book')),
      'book', true, true, `已加入 ${uris.length} 张封面`);
  }

  async uploadShelfFrame(): Promise<void> {
    const uris = await SchemeAssetService.pickSvgFiles(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setShelfFrame(getContext(this), this.schemeId, uris[0], this.sourceThemeId('book')),
      'book', true, true, '书架边框已更新');
  }

  async uploadShelfFolder(): Promise<void> {
    const uris = await SchemeAssetService.pickImages(getContext(this), 1);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setShelfFolder(getContext(this), this.schemeId, uris[0], this.sourceThemeId('book')),
      'book', true, true, '文件夹插画已更新');
  }

  modeLabel(): string {
    return this.selectedMode === 'dark' ? '深色' : '浅色';
  }

  readerAssetMode(): string {
    return SchemeAssetService.readerMode(this.ownPackageId, this.selectedMode === 'dark');
  }

  /** 阅读背景素材不换阅读来源主题（文字色、底色照旧），只把这个模式的背景素材键指向方案自己的包。 */
  setReaderBackgroundAsset(assetId: string): void {
    const dark = this.selectedMode === 'dark';
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
    const uris = await SchemeAssetService.pickSvgFiles(getContext(this), 4);
    if (uris.length === 0) return;
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setNavigation(getContext(this), this.schemeId, uris, this.sourceThemeId('navigation')),
      'navigation', true, true, '导航图标已更新');
  }

  async uploadTtsArtwork(): Promise<void> {
    const dark = this.selectedMode === 'dark';
    const uris = await SchemeAssetService.pickImages(getContext(this), 1);
    if (uris.length === 0) return;
    const scheme = new CustomThemeScheme();
    scheme.id = this.schemeId;
    scheme.settings = this.settingsFromState();
    await this.runAssetUpload((): Promise<SchemeAssetResult> =>
      SchemeAssetService.setTtsArtwork(getContext(this), this.schemeId, uris[0], dark, scheme,
        this.sourceThemeId('ttsPanel')),
      'ttsPanel', !dark, dark, `${dark ? '深色' : '浅色'}面板插画已更新`);
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

  /** 按引用传参（对象字面量）：按值传的 @Builder 不会随上传后的状态刷新（见“按值 @Builder 的下拉不刷新”）。 */
  @Builder
  assetRow($$: AssetRowOptions) {
    SettingNavRow({ title: $$.title, description: $$.description, showDivider: $$.divider !== false,
      onTap: () => $$.onTap() })
  }

  @Builder
  bookAssetRows() {
    if (this.assetRevision >= 0) {
      this.bookAssetRowsContent()
    }
  }

  @Builder
  bookAssetRowsContent() {
    this.assetRow({ title: '上传封面图片',
      description: `最多 ${ThemePackageLimits.MAX_COVERS} 张，书架按书轮播；已有 ${SchemeAssetService.coverCount(this.ownPackageId)} 张`,
      onTap: () => this.uploadCovers() })
    this.assetRow({ title: '上传书架边框', description: 'SVG，中心透明，只画外框和角花', onTap: () => this.uploadShelfFrame() })
    this.assetRow({ title: '上传文件夹插画', description: '平铺分组的文件夹图案，450 × 660',
      onTap: () => this.uploadShelfFolder(), divider: SchemeAssetService.hasBook(this.ownPackageId) })
    if (SchemeAssetService.hasBook(this.ownPackageId)) {
      this.assetRow({ title: '移除上传的书籍素材', description: '恢复为所选主题的封面、边框与插画',
        onTap: () => this.clearBookAssets(), divider: false })
    }
  }

  @Builder
  readerAssetRows() {
    if (this.assetRevision >= 0) {
      this.readerAssetRowsContent()
    }
  }

  @Builder
  readerAssetRowsContent() {
    this.assetRow({ title: `上传${this.modeLabel()}左上角饰`, description: '透明底的 SVG 或位图，贴在阅读页左上角',
      onTap: () => this.uploadReaderOrnament(false) })
    this.assetRow({ title: `上传${this.modeLabel()}右下角饰`, description: '不传时用左上角那张旋转 180°',
      onTap: () => this.uploadReaderOrnament(true) })
    this.assetRow({ title: `上传${this.modeLabel()}整图背景`, description: '竖屏位图，铺满阅读页；会替换角饰',
      onTap: () => this.uploadReaderImage(), divider: !!this.readerAssetMode() })
    if (this.readerAssetMode()) {
      this.assetRow({ title: `移除${this.modeLabel()}阅读背景素材`,
        description: this.readerAssetMode() === 'image' ? '当前为整图，恢复为所选主题的背景' : '当前为角饰，恢复为所选主题的背景',
        onTap: () => this.clearReaderAssets(), divider: false })
    }
  }

  @Builder
  navigationAssetRows() {
    if (this.assetRevision >= 0) {
      this.navigationAssetRowsContent()
    }
  }

  @Builder
  navigationAssetRowsContent() {
    this.assetRow({ title: '上传导航图标', description: '一次选 4 个 SVG，文件名含 bookshelf、explore、search、mine',
      onTap: () => this.uploadNavigation() })
    if (SchemeAssetService.hasNavigation(this.ownPackageId)) {
      this.assetRow({ title: '移除上传的导航图标', description: '恢复为所选主题的图标',
        onTap: () => this.clearNavigationAssets() })
    }
  }

  @Builder
  ttsAssetRows() {
    if (this.assetRevision >= 0) {
      this.ttsAssetRowsContent()
    }
  }

  @Builder
  ttsAssetRowsContent() {
    this.assetRow({ title: `上传${this.selectedMode === 'dark' ? '深色' : '浅色'}面板插画`,
      description: '720 × 520，贴顶等比缩放，下半部渐隐到面板底色', onTap: () => this.uploadTtsArtwork() })
    if (SchemeAssetService.hasTts(this.ownPackageId)) {
      this.assetRow({ title: '移除上传的面板插画', description: '恢复为所选主题的面板', onTap: () => this.clearTtsAssets() })
    }
  }

  @Builder
  bubbleAssetRows() {
    if (this.assetRevision >= 0) {
      this.bubbleAssetRowsContent()
    }
  }

  @Builder
  bubbleAssetRowsContent() {
    this.assetRow({ title: '上传气泡端饰', description: '正方形 SVG，放在强调文字两端', onTap: () => this.uploadBubbleCap() })
    this.assetRow({ title: '上传气泡边框', description: 'SVG，可选，先上传端饰', onTap: () => this.uploadBubbleFrame(),
      divider: SchemeAssetService.hasBubble(this.ownPackageId) })
    if (SchemeAssetService.hasBubble(this.ownPackageId)) {
      this.assetRow({ title: '移除上传的气泡素材', description: '气泡样式恢复为跟随所选主题',
        onTap: () => this.clearBubbleAssets(), divider: false })
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
    const family = index <= 0 || index > this.fontLibrary.length ? '' : this.fontLibrary[index - 1].family;
    if (family === this.appFontFamily) return;
    this.rememberChange();
    this.appFontFamily = family;
    this.onSettingChanged();
  }

  @Builder
  appFontRow() {
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
    this.radiusRow({ title: '小圆角', key: 'small' })
    this.radiusRow({ title: '中圆角', key: 'medium' })
    this.radiusRow({ title: '大圆角', key: 'large' })
    this.radiusRow({ title: '卡片', key: 'card' })
    this.radiusRow({ title: '按钮', key: 'button' })
    this.radiusRow({ title: '气泡', key: 'bubble' })
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
    try {
      const old = this.previewImagePath;
      const path = await SchemePreviewImageStore.pickAndSave(getContext(this), this.schemeId);
      if (!path) return;
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
  previewImageOptions() {
    Column({ space: AppSpacing.MD }) {
      if (this.previewImagePath) {
        Image(this.previewImagePath)
          .width('100%')
          .height(120)
          .objectFit(ImageFit.Cover)
          .borderRadius(ThemeRuntime.mediumRadius())
          .draggable(false)
      }
      Row({ space: AppSpacing.MD }) {
        Button(this.previewImagePath ? '更换预览图' : '上传预览图', { type: ButtonType.Normal })
          .height(38)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
          .layoutWeight(1)
          .onClick(() => this.choosePreviewImage())
        if (this.previewImagePath) {
          Button('恢复用启动封面', { type: ButtonType.Normal })
            .height(38)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
            .backgroundColor(this.inputColor())
            .layoutWeight(1)
            .onClick(() => this.resetPreviewImage())
        }
      }
      .width('100%')
    }
    .width('calc(100% - 24vp)')
    .padding(AppSpacing.LG)
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  startupCoverOptions() {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.MD }) {
        Button(this.currentStartupImagePath() ? '更换自定义封面' : '上传自定义封面',
          { type: ButtonType.Normal })
          .height(38)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
          .layoutWeight(1)
          .onClick(() => this.chooseStartupImage())
        if (this.currentStartupImagePath()) {
          Button('恢复主题封面', { type: ButtonType.Normal })
            .height(38)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
            .backgroundColor(this.inputColor())
            .layoutWeight(1)
            .onClick(() => this.resetStartupImage())
        }
      }
      .width('100%')

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
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: AppSpacing.SM }) {
        Text('副标题')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
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
      .alignItems(HorizontalAlign.Start)
    }
    .width('calc(100% - 24vp)')
    .padding(AppSpacing.LG)
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  previewPanel() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Text(`预览 · ${this.selectedMode === 'dark' ? '深色' : '浅色'}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .layoutWeight(1)
        ImmersiveHeaderAction({ label: '放大预览', accessibilityLabel: '放大主题预览',
          onTap: () => { this.fullPreview = true; } })
      }
      .width('100%')
      this.sceneOptions()
      this.previewSurface(false)
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
  }

  @Builder
  sceneOptions() {
    Row({ space: AppSpacing.XS }) {
      this.sceneOption('书架', 'bookshelf')
      this.sceneOption('阅读', 'reader')
      this.sceneOption('启动', 'startup')
      this.sceneOption('朗读', 'tts')
    }
    .width('100%')
  }

  @Builder
  sceneOption(label: string, scene: string) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(36)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.previewScene === scene ? ThemeRuntime.accentColor(this.appDarkMode) : this.subTextColor())
      .backgroundColor(this.previewScene === scene ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
      .borderRadius(ThemeRuntime.mediumRadius())
      .accessibilitySelected(this.previewScene === scene)
      .accessibilityText(`${label}场景预览`)
      .onClick(() => { this.previewScene = scene; })
  }

  @Builder
  previewSurface(expanded: boolean) {
    if (this.assetRevision >= 0) {
      this.previewSurfaceContent(expanded)
    }
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
      readerSettings: this.readerProfile,
      useReaderProfile: this.readerProfileBound
    })
      .width('100%')
      .height(expanded ? '100%' : this.compactPreviewHeight())
      .layoutWeight(expanded ? 1 : 0)
  }

  compactPreviewHeight(): number {
    // 给分组设置和软键盘保留空间，横屏或小窗口下也能继续滚动编辑。
    return Math.max(136, Math.min(208, this.viewportHeight > 0 ? this.viewportHeight * 0.26 : 208));
  }

  compactEditor(): boolean {
    return this.viewportHeight > 0 && this.viewportHeight < 520;
  }
}
