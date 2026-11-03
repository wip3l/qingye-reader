import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../utils/CustomThemeSchemeStore';
import { AdaptiveColorPicker } from '../components/AdaptiveColorPicker';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeComponentSourceIds, ThemeIds, ThemePack } from '../theme/ThemeModels';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { StartupCoverImageStore } from '../utils/StartupCoverImageStore';
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
  onColorChange: (color: string) => void = (_color: string): void => {};

  build() {
    Stack() {
      SettingRow({ title: this.title, showDivider: this.showDivider }) {
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
      const settings = AppThemeSettingsStore.cloneSettings(scheme.settings);
      this.draftSettings = settings;
      this.customBaseThemeId = settings.customBaseThemeId;
      this.lightAccentColor = settings.customLightAccentColor;
      this.darkAccentColor = settings.customDarkAccentColor;
      this.lightButtonColor = settings.customLightButtonColor;
      this.darkButtonColor = settings.customDarkButtonColor;
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
      if (imagePath !== this.lightStartupImagePath && imagePath !== this.darkStartupImagePath) {
        StartupCoverImageStore.remove(getContext(this), imagePath);
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
    this.sectionTitle({ title: '浅色与深色模式独立保存，可分别调整' })
  }

  @Builder
  typographySection() {
    this.sectionTitle({ title: '字体与排版' })
    Column() {
      this.componentSourceRow('应用字体', '主题自带的应用字体风格', 'typography')
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
      this.componentSourceRow('朗读/有声书面板', '朗读面板和有声书面板的背景插画与底色', 'ttsPanel')
      this.componentSourceRow('强调气泡', '正文强调方式、气泡样式及气泡配色', 'bubble', false)
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
    this.sectionTitle({ title: '应用外观' })
    Column() {
      this.componentSourceRow('导航图标', '书架、发现、搜索和我的底部图标', 'navigation')
      this.componentSourceRow('书籍素材', '主题封面、书架边框和文件夹图案', 'book', false)
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
    this.sectionTitle({ title: '形状与材质' })
    Column() {
      this.componentSourceRow('圆角形状', '卡片、按钮、气泡等圆角尺寸', 'radius')
      this.componentSourceRow('磨砂效果', '模糊、透明度、边框和阴影参数', 'glass', false)
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
    CustomThemePreview({
      themePack: this.customPreviewTheme(),
      previewDark: this.selectedMode === 'dark',
      scene: this.previewScene,
      expanded: expanded,
      startupImagePath: this.currentStartupImagePath(),
      startupTitle: this.currentStartupTitle(),
      startupSubtitle: this.currentStartupSubtitle(),
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
