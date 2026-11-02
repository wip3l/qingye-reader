import { router } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { ReaderTitleSplit } from '../core/reader/ReaderTitleSplit';
import { ReaderTitleStyleCodec, ReaderTitleStyleSettings } from '../model/reader/ReaderTitleStyle';
import { ReaderFontWeightStepper } from '../components/reader/ReaderFontWeightStepper';
import { ReaderWeightedText, ReaderWeightedTextSpan } from '../components/reader/ReaderWeightedText';
import { ReaderTypographyPreview, ReaderTypographyPreviewConfig } from '../components/reader/ReaderTypographyPreview';
import { ReaderV2DocumentParser } from '../core/reader/ReaderV2Document';
import { ReaderV2Color, ReaderV2SpanStyleRange } from '../core/reader/ReaderV2Style';
import { ReaderParagraphIndent } from '../core/reader/ReaderParagraphIndent';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { AdaptiveColorPicker } from '../components/AdaptiveColorPicker';
import { AdaptiveIconButton } from '../components/AdaptiveIconButton';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderRegexFontCodec,
  ReaderRegexFontRule,
  ReaderRegexLegacySettings,
  ReaderResolvedRegexEmphasis
} from '../model/reader/ReaderRegexFontRule';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemeAccessPolicy } from '../account/ThemeAccessPolicy';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CloudAutoSync, CloudRemoteFont } from '../account/CloudAutoSync';
import { CloudFontMenu } from '../account/CloudFontMenu';
import { ThemeTypographyDraft } from '../utils/ThemeTypographyDraft';

class ReaderCustomFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class ReaderCustomFontData {
  fonts: ReaderCustomFontItem[] = [];
}

class ReaderRegexPreviewSlice {
  text: string = '';
  highlighted: boolean = false;
  key: string = '';
}

class ReaderBubbleStyleOption {
  styleId: string = '';
  label: string = '';

  constructor(styleId: string, label: string) {
    this.styleId = styleId;
    this.label = label;
  }
}

@Entry
@Component
struct ReaderFontSettingsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('accountEntitlementsRevision') accountEntitlementsRevision: number = 0;
  // 正文排版与阅读字体共用 fontWeight；主题草稿仍只提交到草稿。
  @State readerFontWeight: number = 400;
  @State readerFontSize: number = 20;
  @State readerBodyFontMode: string = 'global';
  @State readerBodyFontFamily: string = '';
  @State readerTitleFontMode: string = 'global';
  @State readerTitleFontFamily: string = '';
  @State readerTitleFontSize: number = 22;
  @State readerTitleFontWeight: number = 600;
  @State titleStyle: ReaderTitleStyleSettings = new ReaderTitleStyleSettings();
  @State titlePreviewText: string = '第七十四章：卖鸭蛋，卖粽子喽';
  @State titlePreviewEditing: boolean = false;
  @State titleReadingPreview: boolean = false;
  @State titleReadingPreviewHeight: number = 720;
  @State previewLayoutSettings: ReaderSettings = new ReaderSettings();
  @State readerRegexFontEnabled: boolean = false;
  @State readerRegexFontPattern: string = '';
  @State readerRegexFontMode: string = 'global';
  @State readerRegexFontFamily: string = '';
  @State readerRegexFontSize: number = 20;
  @State readerRegexShadowColor: string = '';
  @State readerRegexFontRulesRaw: string = '';
  @StorageLink('readerFontFamily') readerFontFamily: string = '';
  @StorageLink('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageLink('readerFontMode') readerFontMode: string = 'device';
  @StorageLink('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @StorageLink('cloudRemoteFontsRaw') cloudRemoteFontsRaw: string = '';
  private downloadingRemoteFont: boolean = false;
  @State regexRules: ReaderRegexFontRule[] = [];
  @State regexHighlightRefreshKey: number = 0;
  @State activeRegexInputKey: string = '';
  private readerSettingsLoaded: boolean = false;
  private readerSettingsLoading: boolean = false;
  private closingReaderFontSettings: boolean = false;
  private latestReaderFontStyleSave: Promise<void> = Promise.resolve();
  private latestReaderFontStyleSettings: ReaderSettings | null = null;
  private readerFontStyleSaveTimerId: number = -1;
  // 从主题排版页打开时只编辑那一页的草稿，保存与否由主题排版页决定。
  private draftMode: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    this.draftMode = !!params && params[ThemeTypographyDraft.DRAFT_PARAM] === true &&
      ThemeTypographyDraft.current() !== null;
    this.loadSettings();
    this.syncBars();
  }

  onPageShow(): void {
    if (!this.readerSettingsLoaded && !this.readerSettingsLoading) {
      this.loadSettings();
    }
    this.syncBars();
  }

  onBackPress(): boolean {
    this.closeReaderFontSettings();
    return true;
  }

  async closeReaderFontSettings(): Promise<void> {
    if (this.closingReaderFontSettings) {
      return;
    }
    this.closingReaderFontSettings = true;
    this.flushScheduledSettingsSave();
    if (this.draftMode) {
      router.back();
      return;
    }
    // Every editing control saves its own updated snapshot. Re-encoding the component
    // state while the route is being removed can read a stale ForEach item and overwrite
    // the just-persisted regex switches, which is especially visible when this page was
    // opened above the still-mounted reader page.
    try {
      await this.latestReaderFontStyleSave;
    } catch (e) {
      console.warn('等待当前阅读字体设置保存失败:', e);
    }
    await ReaderSettingsStore.waitForReaderFontStyleSaves();
    if (this.latestReaderFontStyleSettings) {
      await ReaderSettingsStore.saveReaderFontStyleSettings(
        getContext(this),
        this.latestReaderFontStyleSettings
      );
      await ReaderSettingsStore.waitForReaderFontStyleSaves();
    }
    router.back();
  }

  async loadSettings(): Promise<void> {
    if (this.readerSettingsLoading) {
      return;
    }
    this.readerSettingsLoading = true;
    try {
      const draft = this.draftMode ? ThemeTypographyDraft.current() : null;
      const settings = draft ? draft : await ReaderSettingsStore.load(getContext(this));
      this.previewLayoutSettings = settings;
      this.readerFontSize = settings.fontSize;
      this.readerFontWeight = settings.fontWeight;
      this.readerBodyFontMode = settings.bodyFontMode;
      this.readerBodyFontFamily = settings.bodyFontFamily;
      this.readerTitleFontMode = settings.titleFontMode;
      this.readerTitleFontFamily = settings.titleFontFamily;
      this.readerTitleFontSize = settings.titleFontSize;
      this.readerTitleFontWeight = settings.titleFontWeight;
      this.titleStyle = ReaderTitleStyleCodec.decode(settings.titleStyleRaw);
      this.readerRegexFontEnabled = settings.regexFontEnabled;
      this.readerRegexFontPattern = settings.regexFontPattern;
      this.readerRegexFontMode = settings.regexFontMode;
      this.readerRegexFontFamily = settings.regexFontFamily;
      this.readerRegexFontSize = settings.regexFontSize;
      this.readerRegexShadowColor = settings.regexShadowColor;
      this.readerRegexFontRulesRaw = settings.regexFontRulesRaw;
      this.regexRules = this.parseRegexRules(settings);
      this.bumpRegexHighlightRefresh();
      this.readerSettingsLoaded = true;
    } catch (e) {
      console.warn('加载阅读字体设置失败:', e);
    } finally {
      this.readerSettingsLoading = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: this.draftMode ? '主题阅读字体' : '阅读字体', onBack: () => this.closeReaderFontSettings(), content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.titleReadingPreview, this.titleReadingPreviewSheet, {
      height: SheetSize.LARGE, dragBar: true, showClose: true,
      backgroundColor: ThemeRuntime.readerBackgroundColor(this.appDarkMode)
    })
  }

  @Builder
  pageContent() {
    this.customFontEntryItem()

    this.sectionTitle('正文字体设置')
    Column() {
      this.fontModeItem('字体类型', this.readerBodyFontMode, this.readerBodyFontFamily, (mode: string, family: string) => {
        this.readerBodyFontMode = mode;
        this.readerBodyFontFamily = family;
        this.saveSettings();
      })
      this.bodyFontSizeStepper()
      ReaderFontWeightStepper({ value: this.readerFontWeight, scope: '正文',
        textColor: this.primaryTextColor(), disabledColor: this.subTextColor(), dividerColor: this.settingsDividerColor(),
        onChange: (value: number) => {
          this.readerFontWeight = value;
          this.saveSettings();
        } })
      this.bodyPreviewItem()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('标题字体设置')
    Column() {
      this.titlePreviewItem()
      this.fontModeItem('字体类型', this.readerTitleFontMode, this.readerTitleFontFamily, (mode: string, family: string) => {
        this.readerTitleFontMode = mode;
        this.readerTitleFontFamily = family;
        this.saveSettings();
      })
      this.titleFontSizeStepper()
      ReaderFontWeightStepper({ value: this.readerTitleFontWeight, scope: '标题',
        textColor: this.primaryTextColor(), disabledColor: this.subTextColor(), dividerColor: this.settingsDividerColor(),
        onChange: (value: number) => {
          this.readerTitleFontWeight = value;
          this.saveSettings();
        } })
      this.titleLayoutSettings()
      this.titleSplitSettings()
      this.titleEmphasisSettings()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('正则字体设置')
    Column() {
      this.regexEnableSwitchItem()
      if (this.readerRegexFontEnabled) {
        this.regexTemplateActions()
        if (this.regexRules.length === 0) {
          this.emptyRegexRule()
        }
        ForEach(this.regexRules, (rule: ReaderRegexFontRule, index: number) => {
          this.regexRulePanel(rule, index, this.regexHighlightRefreshKey)
        }, (rule: ReaderRegexFontRule) => rule.id)
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  saveSettings(regexRules: ReaderRegexFontRule[] = this.regexRules): void {
    if (!this.readerSettingsLoaded || this.closingReaderFontSettings) {
      return;
    }
    const settings = new ReaderSettings();
    settings.fontSize = this.readerFontSize;
    settings.fontWeight = this.readerFontWeight;
    settings.bodyFontMode = this.normalizeFontMode(this.readerBodyFontMode);
    settings.bodyFontFamily = this.readerBodyFontFamily;
    settings.titleFontMode = this.normalizeFontMode(this.readerTitleFontMode);
    settings.titleFontFamily = this.readerTitleFontFamily;
    settings.titleFontSize = this.readerTitleFontSize;
    settings.titleFontWeight = this.readerTitleFontWeight;
    settings.titleStyleRaw = ReaderTitleStyleCodec.encode(this.titleStyle);
    settings.regexFontEnabled = this.readerRegexFontEnabled;
    settings.regexFontPattern = this.readerRegexFontPattern;
    settings.regexFontMode = this.normalizeFontMode(this.readerRegexFontMode);
    settings.regexFontFamily = this.readerRegexFontFamily;
    settings.regexFontSize = this.readerRegexFontSize;
    settings.regexShadowColor = this.readerRegexShadowColor;
    const rulesRaw = this.encodeRegexRules(regexRules);
    this.readerRegexFontRulesRaw = rulesRaw;
    settings.regexFontRulesRaw = rulesRaw;
    this.latestReaderFontStyleSettings = settings;
    this.scheduleSettingsSave();
  }

  scheduleSettingsSave(): void {
    if (this.readerFontStyleSaveTimerId >= 0) {
      clearTimeout(this.readerFontStyleSaveTimerId);
    }
    this.readerFontStyleSaveTimerId = setTimeout(() => {
      this.readerFontStyleSaveTimerId = -1;
      this.persistLatestSettings();
    }, 120);
  }

  flushScheduledSettingsSave(): void {
    if (this.readerFontStyleSaveTimerId >= 0) {
      clearTimeout(this.readerFontStyleSaveTimerId);
      this.readerFontStyleSaveTimerId = -1;
      this.persistLatestSettings();
    }
  }

  persistLatestSettings(): void {
    if (!this.latestReaderFontStyleSettings) return;
    if (this.draftMode) {
      ThemeTypographyDraft.applyFontStyle(this.latestReaderFontStyleSettings);
      return;
    }
    this.latestReaderFontStyleSave = ReaderSettingsStore.saveReaderFontStyleSettings(
      getContext(this), this.latestReaderFontStyleSettings);
    this.latestReaderFontStyleSave.catch((e: Error) => {
      console.warn('保存阅读字体设置失败:', e);
    });
  }

  setBodyFontSize(value: number): void {
    this.readerFontSize = Math.max(14, Math.min(Math.round(value), 50));
    this.saveSettings();
  }

  setTitleFontSize(value: number): void {
    this.readerTitleFontSize = Math.max(14, Math.min(Math.round(value), 50));
    this.saveSettings();
  }

  parseRegexRules(settings: ReaderSettings): ReaderRegexFontRule[] {
    const legacy = new ReaderRegexLegacySettings();
    legacy.pattern = settings.regexFontPattern;
    legacy.fontMode = settings.regexFontMode;
    legacy.fontFamily = settings.regexFontFamily;
    legacy.fontSize = settings.regexFontSize;
    legacy.shadowColor = settings.regexShadowColor;
    return ReaderRegexFontCodec.decode(settings.regexFontRulesRaw || this.readerRegexFontRulesRaw, legacy);
  }

  encodeRegexRules(rules: ReaderRegexFontRule[]): string {
    return ReaderRegexFontCodec.encode(rules);
  }

  newRuleId(): string {
    return ReaderRegexFontCodec.newRuleId();
  }

  addRegexRule(name: string, pattern: string): void {
    const rule = new ReaderRegexFontRule();
    rule.id = this.newRuleId();
    rule.name = name;
    rule.pattern = pattern;
    rule.fontMode = 'global';
    rule.fontSize = this.readerRegexFontSize || this.readerFontSize;
    rule.emphasisMode = 'inherit';
    rule.bubbleStyleId = 'inherit';
    rule.emphasisColor = '';
    rule.highlightColorEnabled = false;
    rule.shadowColor = '';
    rule.expanded = true;
    this.regexRules = [...this.regexRules, rule];
    this.bumpRegexHighlightRefresh();
    this.saveSettings();
  }

  updateRegexRule(index: number, updater: (rule: ReaderRegexFontRule) => void): void {
    // Title emphasis uses the same controls and resolver without joining the regex rule list.
    if (index === -1) {
      const title = ReaderTitleStyleCodec.decode(ReaderTitleStyleCodec.encode(this.titleStyle));
      updater(title.emphasis);
      this.titleStyle = title;
      this.bumpRegexHighlightRefresh();
      this.saveSettings();
      return;
    }
    const next = this.regexRules.slice();
    if (index < 0 || index >= next.length) {
      return;
    }
    const source = next[index];
    const rule = ReaderRegexFontCodec.cloneRule(source);
    updater(rule);
    next[index] = rule;
    this.regexRules = next;
    this.bumpRegexHighlightRefresh();
    this.saveSettings(next);
  }

  updateRegexRuleById(ruleId: string, updater: (rule: ReaderRegexFontRule) => void): void {
    for (let i = 0; i < this.regexRules.length; i++) {
      if (this.regexRules[i].id === ruleId) {
        this.updateRegexRule(i, updater);
        return;
      }
    }
  }

  removeRegexRule(index: number): void {
    const next = this.regexRules.slice();
    if (index < 0 || index >= next.length) {
      return;
    }
    next.splice(index, 1);
    this.regexRules = next;
    this.bumpRegexHighlightRefresh();
    this.saveSettings();
  }

  bumpRegexHighlightRefresh(): void {
    this.regexHighlightRefreshKey = this.regexHighlightRefreshKey + 1;
  }

  regexInputKey(ruleId: string, field: string): string {
    return `${ruleId}:${field}`;
  }

  setRegexInputEditing(ruleId: string, field: string, editing: boolean): void {
    const key = this.regexInputKey(ruleId, field);
    if (editing) {
      this.activeRegexInputKey = key;
      return;
    }
    if (this.activeRegexInputKey === key) {
      this.activeRegexInputKey = '';
    }
  }

  isRegexInputEditing(ruleId: string, field: string): boolean {
    return this.activeRegexInputKey === this.regexInputKey(ruleId, field);
  }

  normalizeFontMode(mode: string): string {
    if (mode === 'system' || mode === 'custom') {
      return mode;
    }
    return 'global';
  }

  fontOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '跟随全局字体' }, { value: '系统字体' }];
    for (const item of this.customFonts()) {
      options.push({ value: item.sourceName || item.familyName || '自定义字体' });
    }
    for (const font of this.remoteFonts()) {
      options.push(CloudFontMenu.option(font));
    }
    return options;
  }

  /** 云端有、本机未下载的字体（终身超级会员字体云同步），排在本机字体之后。 */
  remoteFonts(): CloudRemoteFont[] {
    return CloudAutoSync.parseRemoteFonts(this.cloudRemoteFontsRaw);
  }

  remoteFontStart(): number {
    return 2 + this.customFonts().length;
  }

  /** 选中云端字体：静默下载导入，完成后按本机字体应用。 */
  async selectRemoteFont(remoteIndex: number, apply: (customIndex: number) => void): Promise<void> {
    const font = this.remoteFonts()[remoteIndex];
    if (!font || this.downloadingRemoteFont) return;
    this.downloadingRemoteFont = true;
    try {
      const filePath = await CloudAutoSync.ensureFontDownloaded(getContext(this), font);
      const index = this.customFonts().findIndex((item: ReaderCustomFontItem) => item.filePath === filePath);
      if (index >= 0) apply(index);
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error && e.message ? e.message : '云端字体下载失败，请稍后重试');
    } finally {
      this.downloadingRemoteFont = false;
    }
  }


  selectedFontIndex(mode: string, family: string): number {
    if (mode === 'system') {
      return 1;
    }
    if (mode === 'custom') {
      const fonts = this.customFonts();
      for (let i = 0; i < fonts.length; i++) {
        const normalizedFamily = fonts[i].filePath ?
          ReaderFontHelper.normalizeFontFamily(fonts[i].filePath) : fonts[i].familyName;
        if (fonts[i].familyName === family || normalizedFamily === family) {
          return i + 2;
        }
      }
    }
    return 0;
  }

  selectedFontValue(mode: string, family: string): string {
    const options = this.fontOptions();
    const index = this.selectedFontIndex(mode, family);
    if (index >= 0 && index < options.length) {
      return String(options[index].value);
    }
    return '跟随全局字体';
  }

  customFonts(): ReaderCustomFontItem[] {
    const raw = (this.readerCustomFontsRaw || '').trim();
    if (!raw) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as ReaderCustomFontData | ReaderCustomFontItem[];
      const source = Array.isArray(parsed) ? parsed as ReaderCustomFontItem[] : ((parsed as ReaderCustomFontData).fonts || []);
      const result: ReaderCustomFontItem[] = [];
      for (const item of source) {
        if (!item || !item.familyName || !ReaderFontHelper.fontFileExists(item.filePath)) {
          continue;
        }
        const font = new ReaderCustomFontItem();
        font.familyName = item.familyName;
        font.filePath = item.filePath || '';
        font.sourceName = ReaderFontHelper.resolveDisplayName(
          item.sourceName || item.familyName, font.filePath);
        result.push(font);
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  modeAndFamilyByIndex(index: number): string[] {
    if (index === 1) {
      return ['system', ''];
    }
    if (index >= 2) {
      const fonts = this.customFonts();
      const fontIndex = index - 2;
      if (fontIndex >= 0 && fontIndex < fonts.length) {
        const family = this.registerCustomFont(fonts[fontIndex]);
        if (!family) {
          HdsFeedback.showToast('字体注册失败，请更换字体文件');
          return [];
        }
        return ['custom', family];
      }
    }
    return ['global', ''];
  }

  registerCustomFont(font: ReaderCustomFontItem): string {
    if (!font || !font.filePath) {
      return '';
    }
    const item = new ReaderFontItem();
    item.familyName = font.familyName || ReaderFontHelper.normalizeFontFamily(font.filePath);
    item.filePath = font.filePath;
    item.sourceName = ReaderFontHelper.resolveDisplayName(font.sourceName, font.filePath);
    const result = ReaderFontHelper.registerFont(this.getUIContext(), item);
    return result.registered ? result.familyName : '';
  }

  resolveCustomFontFamily(family: string): string {
    if (!family) {
      return '';
    }
    const fonts = this.customFonts();
    for (const item of fonts) {
      const stableFamily = item.filePath ? ReaderFontHelper.normalizeFontFamily(item.filePath) : item.familyName;
      if (item.familyName === family || stableFamily === family) {
        return this.registerCustomFont(item) || stableFamily || family;
      }
    }
    return family;
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

  settingsDividerColor(): string {
    return ThemeRuntime.hairlineColor(this.appDarkMode);
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

  /**
   * Keep the font selectors on this page on the same menu material.  HDS
   * Select menus otherwise inherit a system shadow that can differ between
   * the top-level font rows and the nested regex rule rows.
   */
  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  customFontEntryItem() {
    Row() {
      Text('自定义字体')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Text('上传 / 删除')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .margin({ right: AppSpacing.MD })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('calc(100% - 24vp)')
    .constraintSize({ minHeight: 56 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/CustomFontManager' });
    })
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  fontModeItem(title: string, mode: string, family: string, onChange: (mode: string, family: string) => void) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Select(this.fontOptions())
        .selected(this.selectedFontIndex(mode, family))
        .value(this.selectedFontValue(mode, family))
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .divider(null)
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => {
          if (index >= this.remoteFontStart()) {
            this.selectRemoteFont(index - this.remoteFontStart(), (customIndex: number) => {
              const downloaded = this.modeAndFamilyByIndex(customIndex + 2);
              if (downloaded.length === 2) onChange(downloaded[0], downloaded[1]);
            });
            return;
          }
          const result = this.modeAndFamilyByIndex(index);
          if (result.length === 2) onChange(result[0], result[1]);
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  bodyFontSizeStepper() {
    Row({ space: AppSpacing.MD }) {
      Text('字体大小')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      this.fontSizeStepButton($r('sys.symbol.minus'), '减小正文字体', this.readerFontSize > 14, () => {
        this.setBodyFontSize(this.readerFontSize - 1);
      })
      Text(`${this.readerFontSize}sp`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .width(52)
        .height(36)
        .textAlign(TextAlign.Center)
      this.fontSizeStepButton($r('sys.symbol.plus'), '增大正文字体', this.readerFontSize !== 50, () => {
        this.setBodyFontSize(this.readerFontSize + 1);
      })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  titleFontSizeStepper() {
    Row({ space: AppSpacing.MD }) {
      Text('字体大小')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      this.fontSizeStepButton($r('sys.symbol.minus'), '减小标题字体', this.readerTitleFontSize > 14, () => {
        this.setTitleFontSize(this.readerTitleFontSize - 1);
      })
      Text(`${this.readerTitleFontSize}sp`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .width(52)
        .height(36)
        .textAlign(TextAlign.Center)
      this.fontSizeStepButton($r('sys.symbol.plus'), '增大标题字体', this.readerTitleFontSize !== 50, () => {
        this.setTitleFontSize(this.readerTitleFontSize + 1);
      })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  fontSizeStepButton(icon: Resource, accessibilityText: string, enabled: boolean, action: () => void) {
    AdaptiveIconButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      buttonEnabled: enabled,
      buttonSize: 34,
      iconSize: 17,
      fillColor: this.inputColor(),
      iconColor: this.primaryTextColor(),
      disabledIconColor: this.subTextColor(),
      action: action
    })
  }

  @Builder
  regexTemplateActions() {
    Column({ space: AppSpacing.MD }) {
      Text('添加规则')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Row({ space: AppSpacing.MD }) {
        Button('对话')
          .fontSize(AppFontSize.BODY)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.addRegexRule('对话', '“[^”\\n]*”|「[^」\\n]*」|『[^』\\n]*』|"[^"\\n]*"');
          })
        Button('关键字匹配')
          .fontSize(AppFontSize.BODY)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.addRegexRule('关键字匹配', '关键词');
          })
        Button('空白规则')
          .fontSize(AppFontSize.BODY)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.addRegexRule('正则规则', '');
          })
      }
      .width('100%')
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  @Builder
  emptyRegexRule() {
    Text('暂无正则规则')
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('calc(100% - 32vp)')
      .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.MD })
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
      .backgroundColor(Color.Transparent)
      .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  @Builder
  regexRulePanel(rule: ReaderRegexFontRule, index: number, refreshKey: number) {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Column({ space: AppSpacing.XS }) {
          Text(rule.name || `规则${index + 1}`)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(rule.pattern || '未设置正则表达式')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button(this.isRegexRuleExpanded(index, refreshKey) ? '收起' : '展开')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .backgroundColor(this.inputColor())
          .height(32)
          .onClick(() => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
              target.expanded = !target.expanded;
            });
          })
        Button('删除')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .backgroundColor(this.inputColor())
          .height(32)
          .onClick(() => {
            this.removeRegexRule(index);
          })
      }
      .width('100%')

      if (this.isRegexRuleExpanded(index, refreshKey)) {
        TextInput({ text: rule.name, placeholder: '规则名称' })
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(ThemeRuntime.mediumRadius())
          .onEditChange((isEditing: boolean) => {
            this.setRegexInputEditing(rule.id, 'name', isEditing);
          })
          .onChange((value: string) => {
            if (!this.isRegexInputEditing(rule.id, 'name')) {
              return;
            }
            this.updateRegexRuleById(rule.id, (target: ReaderRegexFontRule) => {
              target.name = value;
            });
          })

        TextInput({ text: rule.pattern, placeholder: '正则表达式' })
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(ThemeRuntime.mediumRadius())
          .onEditChange((isEditing: boolean) => {
            this.setRegexInputEditing(rule.id, 'pattern', isEditing);
          })
          .onChange((value: string) => {
            if (!this.isRegexInputEditing(rule.id, 'pattern')) {
              return;
            }
            this.updateRegexRuleById(rule.id, (target: ReaderRegexFontRule) => {
              target.pattern = value;
            });
          })

        this.compactFontModeItem('字体类型', rule.fontMode, rule.fontFamily, (mode: string, family: string) => {
          this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
            target.fontMode = mode;
            target.fontFamily = family;
          });
        })
        this.regexFontSizeStepper(index)
        ReaderFontWeightStepper({ value: this.regexRuleAt(index).fontWeight, scope: '规则', nested: true,
          textColor: this.primaryTextColor(), disabledColor: this.subTextColor(), dividerColor: this.settingsDividerColor(),
          onChange: (value: number) => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => { target.fontWeight = value; });
          } })

        this.regexEmphasisSettings(index, refreshKey)

        this.regexRulePreviewItem(index, refreshKey)
      }
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  @Builder
  bodyPreviewItem() {
    Column({ space: AppSpacing.MD }) {
      Text('正文预览')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .width('100%')
      ReaderWeightedText({ spans: [ReaderWeightedTextSpan.create(this.getUIContext(),
        '这是一段阅读正文预览，文字会跟随当前正文字体设置显示。', this.readerFontSize,
        this.bodyPreviewFontFamily(), this.primaryTextColor())], weight: this.readerFontWeight, maxLines: 2 })
        .width('100%')
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  /** 子分组标题：布局、分段、强调各占一组，组内控件直接可见。 */
  @Builder
  titleGroupTitle(title: string, hint: string) {
    Column({ space: AppSpacing.XXS }) {
      Text(title).fontSize(AppFontSize.CAPTION).fontWeight(FontWeight.Medium).fontColor(this.subTextColor())
      if (hint) {
        Text(hint).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).opacity(0.8)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  titleSegmentOptions(kind: string): string[] {
    return kind === 'alignment' ? ['左对齐', '居中', '右对齐'] : ['关闭', '按位置', '按标记', '按正则'];
  }

  titleSegmentSelected(kind: string): number {
    return kind === 'alignment' ? this.titleAlignmentIndex() : this.titleSplitModeIndex();
  }

  selectTitleSegment(kind: string, index: number): void {
    if (kind === 'alignment') this.updateTitleSplit('alignment', ['left', 'center', 'right'][index] || 'center');
    else this.updateTitleSplit('mode', ['off', 'position', 'marker', 'regex'][index] || 'off');
  }

  // Reads the selection from state inside the builder: by-value builder arguments would not refresh.
  @Builder
  titleSegmented(kind: string, label: string) {
    Row() {
      ForEach(this.titleSegmentOptions(kind), (option: string, index: number) => {
        Button(option, { type: ButtonType.Capsule, stateEffect: true })
          .layoutWeight(1)
          .height(32)
          .padding({ left: 4, right: 4 })
          .fontSize(AppFontSize.BODY)
          .fontWeight(index === this.titleSegmentSelected(kind) ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(index === this.titleSegmentSelected(kind) ? this.primaryTextColor() : this.subTextColor())
          .backgroundColor(index === this.titleSegmentSelected(kind) ? this.cardColor() : Color.Transparent)
          .shadow(index === this.titleSegmentSelected(kind) ?
            { radius: 4, color: '#1A000000', offsetX: 0, offsetY: 1 } : { radius: 0, color: Color.Transparent })
          .accessibilityText(`${label}：${option}${index === this.titleSegmentSelected(kind) ? '，已选中' : ''}`)
          .onClick(() => this.selectTitleSegment(kind, index))
      }, (option: string) => `${kind}_${option}`)
    }
    .width('100%')
    .height(40)
    .padding(4)
    .borderRadius(20)
    .backgroundColor(this.inputColor())
  }

  @Builder
  titleLayoutSettings() {
    Column({ space: AppSpacing.MD }) {
      this.titleGroupTitle('标题布局', '')
      Row({ space: AppSpacing.LG }) {
        Text('对齐方式')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Column() {
          this.titleSegmented('alignment', '标题对齐方式')
        }.width(216)
      }.width('100%').constraintSize({ minHeight: 48 })
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.XS }) {
          Text('标题单页').fontSize(AppFontSize.BODY_LARGE).fontColor(this.primaryTextColor())
          Text('每章标题单独成页，正文从下一页开始')
            .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        AdaptiveSwitch({ isOn: this.titleStyle.singlePage,
          onChange: (checked: boolean) => this.updateTitleSplit('singlePage', `${checked}`) })
      }.width('100%').constraintSize({ minHeight: 56 })
      this.titleMarginSlider('上边距', true)
      this.titleMarginSlider('下边距', false)
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .padding({ top: AppSpacing.XL, bottom: AppSpacing.LG })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  @Builder
  titleMarginSlider(label: string, top: boolean) {
    Column({ space: AppSpacing.XS }) {
      Row() {
        Text(label).fontSize(AppFontSize.BODY).fontColor(this.primaryTextColor()).layoutWeight(1)
        Text(`${top ? this.titleStyle.marginTop : this.titleStyle.marginBottom} vp`)
          .fontSize(AppFontSize.BODY).fontColor(this.accentColor())
      }.width('100%')
      Row({ space: AppSpacing.MD }) {
        this.fontSizeStepButton($r('sys.symbol.minus'), `减小标题${label}`,
          (top ? this.titleStyle.marginTop : this.titleStyle.marginBottom) > 0,
          () => this.adjustTitleMargin(top, -1))
        Slider({ value: top ? this.titleStyle.marginTop : this.titleStyle.marginBottom, min: 0, max: 120, step: 1 })
          .layoutWeight(1)
          .selectedColor(this.accentColor())
          .blockColor(this.accentColor())
          .trackColor(this.inputColor())
          .onChange((current: number) => this.updateTitleSplit(top ? 'marginTop' : 'marginBottom', `${current}`))
          .accessibilityText(`标题${label}`)
        this.fontSizeStepButton($r('sys.symbol.plus'), `增大标题${label}`,
          (top ? this.titleStyle.marginTop : this.titleStyle.marginBottom) < 120,
          () => this.adjustTitleMargin(top, 1))
      }.width('100%')
    }.width('100%')
  }

  adjustTitleMargin(top: boolean, direction: number): void {
    this.updateTitleSplit(top ? 'marginTop' : 'marginBottom',
      `${(top ? this.titleStyle.marginTop : this.titleStyle.marginBottom) + direction}`);
  }

  titleAlignmentIndex(): number {
    return Math.max(0, ['left', 'center', 'right'].indexOf(this.titleStyle.alignment));
  }

  titlePreviewAlignment(): text.TextAlign {
    if (this.titleStyle.alignment === 'left') return text.TextAlign.LEFT;
    if (this.titleStyle.alignment === 'right') return text.TextAlign.RIGHT;
    return text.TextAlign.CENTER;
  }

  @Builder
  titleSplitSettings() {
    Column({ space: AppSpacing.MD }) {
      this.titleGroupTitle('标题分段', '把标题拆成两行，第二行可单独放大；只改排版，不改原文')
      this.titleSegmented('splitMode', '标题分段方式')
      if (this.titleStyle.mode !== 'off') {
        this.titleSplitInput()
        Text(this.titleSplitHelp())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
        this.titleSplitResult()
        this.titleSplitSlider('第二段字号', true)
        this.titleSplitSlider('标题行距', false)
      }
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .padding({ top: AppSpacing.XL, bottom: AppSpacing.LG })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  @Builder
  titleSplitInput() {
    if (this.titleStyle.mode === 'position') {
      Row({ space: AppSpacing.SM }) {
        Text('在第').fontSize(AppFontSize.BODY_LARGE).fontColor(this.primaryTextColor())
        TextInput({ text: this.titleStyle.position, placeholder: '6' })
          .type(InputType.Number)
          .maxLength(3)
          .width(76)
          .height(40)
          .textAlign(TextAlign.Center)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((content: string) => this.updateTitleSplit('position', content))
          .accessibilityText('分段位置，第几个字之后')
        Text('个字后换行').fontSize(AppFontSize.BODY_LARGE).fontColor(this.primaryTextColor())
      }.width('100%').constraintSize({ minHeight: 44 })
    } else {
      TextInput({ text: this.titleSplitContent(), placeholder: this.titleSplitContentLabel() })
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .maxLength(180)
        .onChange((content: string) => this.updateTitleSplit(this.titleStyle.mode, content))
        .accessibilityText(this.titleSplitContentLabel())
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.titleSplitPresets(), (preset: string[]) => {
          Button(preset[0], { type: ButtonType.Capsule, stateEffect: true })
            .height(30)
            .padding({ left: 12, right: 12 })
            .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.titleSplitContent() === preset[1] ? this.accentColor() : this.primaryTextColor())
            .backgroundColor(this.titleSplitContent() === preset[1] ?
              ThemeRuntime.accentSurfaceColor(this.appDarkMode) : this.inputColor())
            .accessibilityText(`使用${preset[0]}分段`)
            .onClick(() => this.updateTitleSplit(this.titleStyle.mode, preset[1]))
        }, (preset: string[]) => `${this.titleStyle.mode}_${preset[0]}`)
      }.width('100%')
    }
  }

  /** 常用标记与正则，点一下即可套用；每项为 [显示文字, 实际值]。 */
  titleSplitPresets(): string[][] {
    if (this.titleStyle.mode === 'marker') {
      return [['：', '：'], [':', ':'], ['空格', ' '], ['全角空格', String.fromCharCode(0x3000)], ['——', '——']];
    }
    return [['第N章', '^第[零一二三四五六七八九十百千万0-9]+章[：: ]*'],
      ['第N回', '^第[零一二三四五六七八九十百千万0-9]+回[：: ]*'],
      ['第N节', '^第[零一二三四五六七八九十百千万0-9]+节[：: ]*'],
      ['Chapter N', '^Chapter *[0-9]+[:.：]? *']];
  }

  /** 用示例标题即时说明分段结果；输入有误时直接给出原因。 */
  @Builder
  titleSplitResult() {
    if (ReaderTitleSplit.validationError(this.titleStyle)) {
      Text(ReaderTitleSplit.validationError(this.titleStyle))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .width('100%')
    } else if (this.titlePreviewParts().length > 1) {
      Column({ space: AppSpacing.XS }) {
        ForEach(this.titlePreviewParts(), (part: string, index: number) => {
          Row({ space: AppSpacing.MD }) {
            Text(index === 0 ? '第一段' : '第二段')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
            Text(part)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
        }, (part: string, index: number) => `${index}_${part}`)
      }
      .width('100%')
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(this.inputColor())
    } else {
      Text('示例标题里没有找到分段位置，这类标题阅读时保持原样')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
    }
  }

  @Builder
  titleSplitSlider(label: string, secondary: boolean) {
    Column({ space: AppSpacing.XS }) {
      Row() {
        Text(label).fontSize(AppFontSize.BODY).fontColor(this.primaryTextColor()).layoutWeight(1)
        Text(secondary ? `${this.titleStyle.secondaryScale.toFixed(1)} 倍` : `${this.titleStyle.lineGap} vp`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.accentColor())
      }.width('100%')
      Row({ space: AppSpacing.MD }) {
        this.fontSizeStepButton($r('sys.symbol.minus'), `减小${label}`,
          secondary ? this.titleStyle.secondaryScale > 0.5 : this.titleStyle.lineGap > 0,
          () => this.adjustTitleSplit(secondary, -1))
        Slider({ value: secondary ? this.titleStyle.secondaryScale : this.titleStyle.lineGap,
          min: secondary ? 0.5 : 0, max: secondary ? 2 : 40, step: secondary ? 0.1 : 1 })
          .layoutWeight(1)
          .selectedColor(this.accentColor())
          .blockColor(this.accentColor())
          .trackColor(this.inputColor())
          .onChange((current: number) => {
            this.updateTitleSplit(secondary ? 'secondaryScale' : 'lineGap', `${current}`);
          })
          .accessibilityText(label)
        this.fontSizeStepButton($r('sys.symbol.plus'), `增大${label}`,
          secondary ? this.titleStyle.secondaryScale < 2 : this.titleStyle.lineGap < 40,
          () => this.adjustTitleSplit(secondary, 1))
      }.width('100%')
    }.width('100%').padding({ top: AppSpacing.XS })
  }

  titleSplitModeIndex(): number {
    return Math.max(0, ['off', 'position', 'marker', 'regex'].indexOf(this.titleStyle.mode));
  }

  titleSplitContentLabel(): string {
    if (this.titleStyle.mode === 'position') return '分段位置';
    return this.titleStyle.mode === 'regex' ? '分段正则' : '分段标记';
  }

  titleSplitContent(): string {
    if (this.titleStyle.mode === 'position') return this.titleStyle.position;
    return this.titleStyle.mode === 'regex' ? this.titleStyle.regex : this.titleStyle.marker;
  }

  titleSplitHelp(): string {
    if (this.titleStyle.mode === 'position') return '汉字、标点和空格都算一个字。';
    return this.titleStyle.mode === 'regex' ? '在第一次匹配的末尾换行，匹配内容留在第一段。' :
      '在第一个标记后换行，标记留在第一段。';
  }

  updateTitleSplit(field: string, content: string): void {
    const next = ReaderTitleStyleCodec.decode(ReaderTitleStyleCodec.encode(this.titleStyle));
    if (field === 'mode') next.mode = ReaderTitleSplit.normalizeMode(content);
    else if (field === 'position') next.position = content;
    else if (field === 'marker') next.marker = content;
    else if (field === 'regex') next.regex = content;
    else if (field === 'secondaryScale') next.secondaryScale = ReaderTitleSplit.normalizeScale(Number(content));
    else if (field === 'lineGap') next.lineGap = ReaderTitleSplit.normalizeGap(Number(content));
    else if (field === 'alignment') next.alignment = ReaderTitleSplit.normalizeAlignment(content);
    else if (field === 'marginTop') next.marginTop = ReaderTitleSplit.normalizeMargin(Number(content));
    else if (field === 'marginBottom') next.marginBottom = ReaderTitleSplit.normalizeMargin(Number(content));
    else if (field === 'singlePage') next.singlePage = content === 'true';
    this.titleStyle = next;
    this.saveSettings();
  }

  adjustTitleSplit(secondary: boolean, direction: number): void {
    this.updateTitleSplit(secondary ? 'secondaryScale' : 'lineGap', secondary ?
      `${this.titleStyle.secondaryScale + direction * 0.1}` : `${this.titleStyle.lineGap + direction}`);
  }

  @Builder
  titleEmphasisSettings() {
    Column({ space: AppSpacing.MD }) {
      this.titleGroupTitle('标题强调', '不受“正则字体”开关影响；选“无强调”时标题沿用正则规则的效果')
      this.regexEmphasisSettings(-1, this.regexHighlightRefreshKey)
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .padding({ top: AppSpacing.XL, bottom: AppSpacing.LG })
  }

  titlePreviewParts(): string[] {
    return ReaderTitleSplit.parts(this.titlePreviewText, this.titleStyle);
  }

  typographyPreviewConfig(withBody: boolean): ReaderTypographyPreviewConfig {
    const config = new ReaderTypographyPreviewConfig();
    const layout = this.previewLayoutSettings;
    const context = this.getUIContext();
    const input = config.input;
    input.fontSizePx = context.fp2px(this.readerFontSize);
    input.fontWeight = this.readerFontWeight;
    input.titleFontSizePx = context.fp2px(this.readerTitleFontSize);
    input.titleFontWeight = this.readerTitleFontWeight;
    input.titleSecondaryScale = this.titleStyle.secondaryScale;
    input.titleLineGapPx = context.vp2px(this.titleStyle.mode === 'off' ? layout.lineHeight : this.titleStyle.lineGap);
    input.titleAlignment = this.titleStyle.alignment;
    input.titleMarginTopPx = context.vp2px(this.titleStyle.marginTop);
    input.titleMarginBottomPx = context.vp2px(this.titleStyle.marginBottom);
    input.titleSinglePage = withBody && this.titleStyle.singlePage;
    input.lineSpacingPx = context.vp2px(layout.lineHeight);
    input.paragraphSpacingPx = context.vp2px(layout.paragraphSpacing);
    input.letterSpacingPx = context.fp2px(layout.letterSpacing);
    input.textAlign = layout.textAlign;
    input.marginLeftPx = context.vp2px(layout.marginLeft);
    input.marginRightPx = context.vp2px(layout.marginRight);
    input.marginTopPx = context.vp2px(withBody ? layout.marginTop : 0);
    input.marginBottomPx = context.vp2px(withBody ? layout.marginBottom : 0);
    input.bodyFontFamily = this.bodyPreviewFontFamily();
    input.titleFontFamily = this.titlePreviewFontFamily();
    input.textColor = ReaderV2Color.parse(ThemeRuntime.readerTextColor(this.appDarkMode), 0xFF202124);
    input.commentsEnabled = false;
    config.fontSizeVp = this.readerFontSize;
    config.viewportHeightVp = this.titleReadingPreviewHeight;
    const indent = '　'.repeat(ReaderParagraphIndent.normalize(layout.paragraphIndent));
    const body = withBody ? '\n' + indent +
      '清晨的风穿过长街，带来一阵粽叶的清香。街角的小摊刚刚支起，竹篮里整整齐齐地码着新煮好的粽子。\n' +
      indent + '“卖鸭蛋，卖粽子喽——”一声吆喝，把沉睡的小城轻轻唤醒。' : '';
    config.document = ReaderV2DocumentParser.parse(this.titlePreviewText + body, 0, this.titlePreviewText, [], this.titleStyle);
    if (this.titleStyle.emphasis.emphasisMode !== 'none') {
      for (const block of config.document.blocks) {
        if (!block.title) continue;
        const size = this.readerTitleFontSize * (block.titleSegment > 0 ? this.titleStyle.secondaryScale : 1);
        const style = this.typographyPreviewEmphasis(this.titleStyle.emphasis, size,
          input.titleFontFamily, this.readerTitleFontWeight);
        style.start = block.displayStart;
        style.end = block.displayEnd;
        style.repeatCaps = true;
        config.styles.push(style);
      }
    }
    this.typographyPreviewRegexStyles(config);
    return config;
  }

  typographyPreviewRegexStyles(config: ReaderTypographyPreviewConfig): void {
    if (!this.readerRegexFontEnabled) return;
    const matches: ReaderV2SpanStyleRange[] = [];
    const titleStyles = config.styles.slice();
    const content = config.document.displayText;
    for (const rule of this.regexRules) {
      if (!rule.pattern.trim()) continue;
      let regex: RegExp;
      try { regex = new RegExp(rule.pattern, 'g'); } catch (_) { continue; }
      let match = regex.exec(content);
      while (match) {
        const start = match.index;
        const end = start + match[0].length;
        if (end > start && !matches.some((item: ReaderV2SpanStyleRange): boolean => start < item.end && end > item.start)) {
          matches.push(new ReaderV2SpanStyleRange(start, end));
          // Explicit title emphasis takes precedence; regex fonts still apply outside its ranges.
          let ranges: number[][] = [[start, end]];
          for (const title of titleStyles) {
            const next: number[][] = [];
            for (const range of ranges) {
              if (range[1] <= title.start || range[0] >= title.end) next.push(range);
              else {
                if (range[0] < title.start) next.push([range[0], title.start]);
                if (range[1] > title.end) next.push([title.end, range[1]]);
              }
            }
            ranges = next;
          }
          for (const range of ranges) {
            const style = this.typographyPreviewEmphasis(rule, rule.fontSize,
              this.previewFontFamily(rule.fontMode, rule.fontFamily), rule.fontWeight);
            style.start = range[0];
            style.end = range[1];
            config.styles.push(style);
          }
        }
        if (end <= start) {
          if (start >= content.length) break;
          regex.lastIndex = Math.max(regex.lastIndex + 1, start + 1);
        }
        match = regex.exec(content);
      }
    }
  }

  typographyPreviewEmphasis(rule: ReaderRegexFontRule, size: number, family: string,
    weight: number): ReaderV2SpanStyleRange {
    const context = this.regexEmphasisContext();
    context.surfaceColor = ThemeRuntime.readerBackgroundColor(this.appDarkMode);
    context.normalTextColor = ThemeRuntime.readerTextColor(this.appDarkMode);
    const resolved = ReaderRegexBubbleStyleResolver.resolve(rule, context);
    const uiContext = this.getUIContext();
    const style = new ReaderV2SpanStyleRange();
    style.fontSizePx = uiContext.fp2px(size);
    style.fontFamily = family;
    style.fontWeight = weight;
    style.colorEnabled = true;
    style.color = ReaderV2Color.parse(resolved.textColor, 0xFF202124);
    style.backgroundEnabled = resolved.backgroundEnabled;
    style.backgroundColor = ReaderV2Color.parse(resolved.backgroundColor, 0x00000000);
    style.radiusTopLeftPx = Math.max(1, uiContext.vp2px(resolved.radiusTopLeft));
    style.radiusTopRightPx = Math.max(1, uiContext.vp2px(resolved.radiusTopRight));
    style.radiusBottomLeftPx = Math.max(1, uiContext.vp2px(resolved.radiusBottomLeft));
    style.radiusBottomRightPx = Math.max(1, uiContext.vp2px(resolved.radiusBottomRight));
    style.shadowEnabled = resolved.textShadowRadius > 0;
    style.shadowColor = ReaderV2Color.parse(resolved.textShadowColor, 0x00000000);
    style.shadowRadiusPx = Math.max(1, uiContext.vp2px(Math.max(0, resolved.textShadowRadius)));
    style.shadowOffsetXPx = Math.max(1, uiContext.vp2px(Math.max(0, resolved.textShadowOffsetX)));
    style.shadowOffsetYPx = Math.max(1, uiContext.vp2px(Math.max(0, resolved.textShadowOffsetY)));
    style.decorationEnabled = resolved.bubbleDecorationEnabled && ThemeAssetRegistry.hasRegexBubbleCap(resolved.bubbleStyleId);
    style.decorationStyleId = style.decorationEnabled ? resolved.bubbleStyleId : '';
    style.decorationSizePx = style.decorationEnabled ? uiContext.vp2px(Math.max(15, Math.min(22, size * 0.72))) : 0;
    return style;
  }

  @Builder
  titlePreviewContent() {
    ReaderTypographyPreview({ config: this.typographyPreviewConfig(false) })
  }

  @Builder
  titleReadingPreviewSheet() {
    Column() {
      Text('阅读预览').fontSize(AppFontSize.SUBTITLE).fontColor(ThemeRuntime.readerTextColor(this.appDarkMode))
        .margin({ top: 48, bottom: AppSpacing.LG })
      Scroll() {
        ReaderTypographyPreview({ config: this.typographyPreviewConfig(true) })
      }.width('100%').layoutWeight(1)
        .onAreaChange((_oldArea: Area, area: Area) => {
          const height = Number(area.height);
          if (height > 0 && Math.abs(height - this.titleReadingPreviewHeight) > 0.5) this.titleReadingPreviewHeight = height;
        })
    }.width('100%').height('100%')
  }

  /** 预览放在标题设置的最前面，调整下面任一项都能直接看到效果。 */
  @Builder
  titlePreviewItem() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.XS }) {
        Text('标题预览').fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).layoutWeight(1)
        Button(this.titlePreviewEditing ? '完成' : '换示例')
          .fontSize(AppFontSize.CAPTION).fontColor(this.accentColor()).backgroundColor(Color.Transparent)
          .height(32).padding({ left: 8, right: 8 })
          .onClick(() => { this.titlePreviewEditing = !this.titlePreviewEditing; })
        Button('阅读预览')
          .fontSize(AppFontSize.CAPTION).fontColor(this.accentColor()).backgroundColor(Color.Transparent)
          .height(32).padding({ left: 8, right: 8 })
          .onClick(() => { this.titleReadingPreview = true; })
      }.width('100%')
      Column() {
        this.titlePreviewContent()
      }.width('100%').padding({ top: AppSpacing.XXL, bottom: AppSpacing.XXL })
        .backgroundColor(ThemeRuntime.readerBackgroundColor(this.appDarkMode))
        .borderRadius(ThemeRuntime.mediumRadius())
      if (this.titlePreviewEditing) {
        TextInput({ text: this.titlePreviewText, placeholder: '输入示例标题' })
          .fontColor(this.primaryTextColor()).fontSize(AppFontSize.BODY)
          .backgroundColor(this.inputColor()).maxLength(160)
          .onChange((content: string) => { this.titlePreviewText = content; })
        Row({ space: AppSpacing.SM }) {
          Button('短标题')
            .fontSize(AppFontSize.CAPTION).fontColor(this.primaryTextColor()).backgroundColor(this.inputColor())
            .height(30).padding({ left: 12, right: 12 })
            .onClick(() => { this.titlePreviewText = '第七十四章：卖鸭蛋，卖粽子喽'; })
          Button('长标题')
            .fontSize(AppFontSize.CAPTION).fontColor(this.primaryTextColor()).backgroundColor(this.inputColor())
            .height(30).padding({ left: 12, right: 12 })
            .onClick(() => { this.titlePreviewText = '第494章：天下承平，一世长安，人间烟火寻常巷陌'; })
        }.width('100%')
      }
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  previewFontFamily(mode: string, family: string): string {
    if (mode === 'system') {
      return this.systemPreviewFontFamily();
    }
    if (mode === 'custom' && family) {
      return this.resolveCustomFontFamily(family);
    }
    return this.readerFontFamily ||
      ReaderFontBootstrap.defaultFontFamily(this.readerFontMode, this.systemPreviewFontFamily());
  }

  bodyPreviewFontFamily(): string {
    return this.previewFontFamily(this.readerBodyFontMode, this.readerBodyFontFamily);
  }

  systemPreviewFontFamily(): string {
    return this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext()) || '';
  }

  titlePreviewFontFamily(): string {
    if (this.readerTitleFontMode === 'global' && !this.readerTitleFontFamily) {
      return this.previewFontFamily('global', '');
    }
    return this.previewFontFamily(this.readerTitleFontMode, this.readerTitleFontFamily);
  }

  normalizeColorInput(color: string, fallback: string): string {
    return ReaderRegexBubbleStyleResolver.normalizeColor(color, fallback);
  }

  regexRuleAt(index: number): ReaderRegexFontRule {
    if (index === -1) return this.titleStyle.emphasis;
    if (index >= 0 && index < this.regexRules.length) {
      return this.regexRules[index];
    }
    return new ReaderRegexFontRule();
  }

  isRegexRuleExpanded(index: number, refreshKey: number): boolean {
    const key = refreshKey >= 0 ? true : true;
    return this.regexRuleAt(index).expanded && key;
  }

  regexPreviewText(rule: ReaderRegexFontRule): string {
    if (rule.name === '对话') {
      return '他说：“你好。”她点头说：「走吧。」';
    }
    if (rule.name === '关键字匹配') {
      return `这里包含${this.regexPreviewKeyword(rule.pattern)}，命中后会使用当前正则字体。`;
    }
    if (rule.pattern.trim()) {
      return `命中示例：${rule.pattern}`;
    }
    return '正则规则预览文本';
  }

  regexPreviewKeyword(pattern: string): string {
    let value = (pattern || '').trim();
    if (!value) {
      return '关键词';
    }
    const firstKeyword = value.split('|')[0].trim();
    if (firstKeyword) {
      value = firstKeyword;
    }
    value = value.replace(/\\b/g, '').replace(/^\^/, '').replace(/\$$/, '');
    return value || '关键词';
  }

  regexPreviewSlices(index: number, refreshKey: number): ReaderRegexPreviewSlice[] {
    const rule = this.regexRuleAt(index);
    const text = this.regexPreviewText(rule);
    const keySeed = refreshKey >= 0 ? refreshKey : 0;
    if (!rule.pattern.trim()) {
      return [this.previewSlice(text, false, `preview_plain_${keySeed}`)];
    }
    try {
      const regex = new RegExp(rule.pattern, 'g');
      const result: ReaderRegexPreviewSlice[] = [];
      let cursor = 0;
      let count = 0;
      let match = regex.exec(text);
      while (match && match.index >= 0) {
        const start = Math.max(cursor, match.index);
        const end = Math.max(start, Math.min(text.length, match.index + (match[0] || '').length));
        if (end <= start) {
          if (start >= text.length || regex.lastIndex >= text.length) {
            break;
          }
          regex.lastIndex = Math.max(regex.lastIndex + 1, start + 1);
          match = regex.exec(text);
          continue;
        }
        if (start > cursor) {
          result.push(this.previewSlice(text.substring(cursor, start), false, `preview_plain_${keySeed}_${cursor}_${start}`));
        }
        result.push(this.previewSlice(text.substring(start, end), true, `preview_hit_${keySeed}_${start}_${end}_${count}`));
        cursor = end;
        count++;
        regex.lastIndex = Math.max(regex.lastIndex, end);
        match = regex.exec(text);
      }
      if (result.length === 0) {
        return [this.previewSlice(text, false, `preview_miss_${keySeed}`)];
      }
      if (cursor < text.length) {
        result.push(this.previewSlice(text.substring(cursor), false, `preview_plain_${keySeed}_${cursor}_${text.length}`));
      }
      return result;
    } catch (e) {
      return [this.previewSlice('正则表达式无效', false, `preview_error_${keySeed}`)];
    }
  }

  previewSlice(text: string, highlighted: boolean, key: string): ReaderRegexPreviewSlice {
    const slice = new ReaderRegexPreviewSlice();
    slice.text = text;
    slice.highlighted = highlighted;
    slice.key = key;
    return slice;
  }

  themeRegexEmphasisMode(): string {
    return ThemeRuntime.regexEmphasisMode();
  }

  themeRegexBubbleStyleId(): string {
    return ThemeRuntime.regexBubbleStyle();
  }

  themeRegexEmphasisColor(): string {
    return ThemeRuntime.regexEmphasisColor(this.appDarkMode);
  }

  regexEmphasisContext(): ReaderRegexEmphasisContext {
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = this.themeRegexEmphasisMode();
    context.inheritedBubbleStyleId = this.themeRegexBubbleStyleId();
    context.inheritedColor = this.themeRegexEmphasisColor();
    context.inheritedTextColor = ThemeRuntime.regexEmphasisTextColor(this.appDarkMode);
    context.accentColor = this.accentColor();
    context.surfaceColor = this.cardColor();
    context.normalTextColor = this.primaryTextColor();
    context.darkMode = this.appDarkMode;
    return context;
  }

  resolvedRegexEmphasis(index: number): ReaderResolvedRegexEmphasis {
    return ReaderRegexBubbleStyleResolver.resolve(this.regexRuleAt(index), this.regexEmphasisContext());
  }

  regexPreviewTextColor(highlighted: boolean, index: number): string {
    return highlighted ? this.resolvedRegexEmphasis(index).textColor : this.primaryTextColor();
  }

  regexPreviewBackgroundStyle(highlighted: boolean, index: number): TextBackgroundStyle {
    const style = this.resolvedRegexEmphasis(index);
    if (!highlighted || !style.backgroundEnabled) {
      return {};
    }
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

  regexPreviewTextShadow(highlighted: boolean, index: number): ShadowOptions | ShadowOptions[] {
    const style = this.resolvedRegexEmphasis(index);
    if (!highlighted) {
      return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
    }
    if (style.textShadows.length > 0) {
      return style.textShadows;
    }
    return {
      radius: style.textShadowRadius,
      color: style.textShadowColor,
      offsetX: style.textShadowOffsetX,
      offsetY: style.textShadowOffsetY
    };
  }

  regexPreviewDecoration(highlighted: boolean, index: number): DecorationStyleInterface {
    if (!highlighted) {
      return { type: TextDecorationType.None };
    }
    const style = this.resolvedRegexEmphasis(index);
    if (!style.decorationEnabled) {
      return { type: TextDecorationType.None };
    }
    return {
      type: TextDecorationType.Underline,
      color: style.decorationColor,
      style: this.regexDecorationStyle(style.decorationStyleId)
    };
  }

  regexDecorationStyle(styleId: string): TextDecorationStyle {
    if (styleId === 'double') return TextDecorationStyle.DOUBLE;
    if (styleId === 'dotted') return TextDecorationStyle.DOTTED;
    if (styleId === 'dashed') return TextDecorationStyle.DASHED;
    if (styleId === 'wavy') return TextDecorationStyle.WAVY;
    return TextDecorationStyle.SOLID;
  }

  shouldUseRegexPreviewDecoration(slice: ReaderRegexPreviewSlice, index: number): boolean {
    if (!slice.highlighted) {
      return false;
    }
    const style = this.resolvedRegexEmphasis(index);
    return style.bubbleDecorationEnabled && ThemeAssetRegistry.hasRegexBubbleCap(style.bubbleStyleId);
  }

  regexPreviewBubbleStyleId(index: number): string {
    return this.resolvedRegexEmphasis(index).bubbleStyleId;
  }

  regexPreviewBubbleCapSize(index: number): number {
    return Math.max(15, Math.min(22, this.regexRuleAt(index).fontSize * 0.72));
  }

  @Builder
  regexRulePreviewItem(index: number, refreshKey: number) {
    Column({ space: AppSpacing.SM }) {
      Text('规则预览')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .width('100%')
      ReaderWeightedText({ spans: this.weightedRegexPreviewSpans(index, refreshKey),
        weight: this.readerFontWeight, maxLines: 3 })
      .width('100%')
    }
    .width('100%')
    .padding({ top: AppSpacing.XS, bottom: AppSpacing.XXS })
  }

  weightedRegexPreviewSpans(index: number, refreshKey: number): ReaderWeightedTextSpan[] {
    const rule = this.regexRuleAt(index);
    return this.regexPreviewSlices(index, refreshKey).map((slice: ReaderRegexPreviewSlice): ReaderWeightedTextSpan => {
      const span = ReaderWeightedTextSpan.create(this.getUIContext(), slice.text,
        slice.highlighted ? rule.fontSize : this.readerFontSize,
        slice.highlighted ? this.previewFontFamily(rule.fontMode, rule.fontFamily) : this.bodyPreviewFontFamily(),
        this.regexPreviewTextColor(slice.highlighted, index), 0, 0,
        slice.highlighted ? this.resolvedRegexEmphasis(index) : undefined);
      span.weight = slice.highlighted ? rule.fontWeight : this.readerFontWeight;
      if (this.shouldUseRegexPreviewDecoration(slice, index)) {
        span.capStyleId = this.regexPreviewBubbleStyleId(index);
        span.capSizePx = this.getUIContext().vp2px(this.regexPreviewBubbleCapSize(index));
      }
      return span;
    });
  }

  emphasisModeOptions(): SelectOption[] {
    return [
      { value: '跟随主题' },
      { value: '无强调' },
      { value: '自定义' }
    ];
  }

  emphasisModeIndex(mode: string): number {
    if (mode === 'none') {
      return 1;
    }
    if (mode === 'custom' || mode === 'text' || mode === 'highlight' || mode === 'bubble') {
      return 2;
    }
    return 0;
  }

  emphasisModeByIndex(index: number): string {
    if (index === 1) {
      return 'none';
    }
    if (index === 2) {
      return 'custom';
    }
    return 'inherit';
  }

  emphasisModeLabel(mode: string): string {
    const options = this.emphasisModeOptions();
    return String(options[this.emphasisModeIndex(mode)].value);
  }

  bubbleStyleOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const item of this.accessibleBubbleStyleOptions()) {
      options.push({ value: item.label });
    }
    return options;
  }

  accessibleBubbleStyleOptions(): ReaderBubbleStyleOption[] {
    const options: ReaderBubbleStyleOption[] = [
      new ReaderBubbleStyleOption('inherit', '跟随主题'),
      new ReaderBubbleStyleOption('qq-soft', '柔和'),
      new ReaderBubbleStyleOption('qq-solid', '实色'),
      new ReaderBubbleStyleOption('capsule', '圆角胶囊'),
      new ReaderBubbleStyleOption('paper', '纸笺'),
      new ReaderBubbleStyleOption('neon', '霓虹')
    ];
    const revision = this.accountEntitlementsRevision;
    this.appendAccessibleBubbleStyle(options, 'classic-glass', '经典玻璃', revision);
    this.appendAccessibleBubbleStyle(options, 'warm-scroll', '暖纸卷轴', revision);
    this.appendAccessibleBubbleStyle(options, 'forest-dew', '林间露珠', revision);
    this.appendAccessibleBubbleStyle(options, 'ink-brush', '水墨笔触', revision);
    this.appendAccessibleBubbleStyle(options, 'neon-pulse', '霓虹脉冲', revision);
    this.appendAccessibleBubbleStyle(options, 'strawberry-ribbon', '草莓软框', revision);
    this.appendAccessibleBubbleStyle(options, 'crimson-stamp', '赤墨印章', revision);
    this.appendAccessibleBubbleStyle(options, 'celadon-slip', '青瓷纸笺', revision);
    this.appendAccessibleBubbleStyle(options, 'rose-frame', '玫瑰信框', revision);
    this.appendAccessibleBubbleStyle(options, 'moon-halo', '月光描边', revision);
    this.appendAccessibleBubbleStyle(options, 'sword-talisman', '剑符', revision);
    this.appendAccessibleBubbleStyle(options, 'qingluan-jade', '青鸾玉令', revision);
    this.appendAccessibleBubbleStyle(options, 'pipi-soft-paw', '皮皮软爪', revision);
    this.appendAccessibleBubbleStyle(options, 'mecha-comm', '通讯频道', revision);
    this.appendAccessibleBubbleStyle(options, 'starwish-ribbon', '星愿丝带', revision);
    this.appendAccessibleBubbleStyle(options, 'pencil-mark', '铅笔划线', revision);
    this.appendAccessibleBubbleStyle(options, 'gilded-orbit', '曜金藏签', revision);
    this.appendAccessibleBubbleStyle(options, 'harbor-postcard', '港湾邮笺', revision);
    return options;
  }

  appendAccessibleBubbleStyle(options: ReaderBubbleStyleOption[], styleId: string, label: string,
    revision: number): void {
    if (ThemeAccessPolicy.canUseBubbleStyle(styleId) || revision < 0) {
      options.push(new ReaderBubbleStyleOption(styleId, label));
    }
  }

  bubbleStyleIndex(styleId: string): number {
    const options = this.accessibleBubbleStyleOptions();
    for (let index = 0; index < options.length; index++) {
      if (options[index].styleId === styleId) {
        return index;
      }
    }
    return 0;
  }

  bubbleStyleByIndex(index: number): string {
    const options = this.accessibleBubbleStyleOptions();
    return index >= 0 && index < options.length ? options[index].styleId : 'inherit';
  }

  bubbleStyleLabel(styleId: string): string {
    const options = this.bubbleStyleOptions();
    return String(options[this.bubbleStyleIndex(styleId)].value);
  }

  @Builder
  regexEmphasisSettings(index: number, refreshKey: number) {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Text('强调效果')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Select(this.emphasisModeOptions())
          .selected(this.emphasisModeIndex(this.regexRuleAt(index).emphasisMode))
          .value(this.emphasisModeLabel(this.regexRuleAt(index).emphasisMode))
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .fontColor(this.subTextColor())
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.END)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .divider(null)
          .opacity(refreshKey >= 0 ? 1 : 1)
          .optionBgColor(Color.Transparent)
          .optionFontColor(this.primaryTextColor())
          .selectedOptionFontColor(this.accentColor())
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
          .onSelect((selectedIndex: number) => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
              target.emphasisMode = this.emphasisModeByIndex(selectedIndex);
            });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.emphasisModeIndex(this.regexRuleAt(index).emphasisMode) === 2) {
        this.regexEmphasisToggle('设置文字色', this.regexRuleAt(index).customTextColorEnabled, (enabled: boolean) => {
          this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
            target.customTextColorEnabled = enabled;
            if (enabled && !target.customTextColor.trim()) {
              target.customTextColor = this.accentColor();
            }
          });
        })
        if (this.regexRuleAt(index).customTextColorEnabled) {
          AdaptiveColorPicker({
            allowAlpha: true,
            value: this.regexRuleAt(index).customTextColor,
            placeholder: this.accentColor(),
            appDarkMode: this.appDarkMode,
            accentColor: this.accentColor(),
            optionTitle: '文字颜色',
            directSelection: true,
            onColorChange: (value: string) => {
              this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                target.customTextColor = this.normalizeColorInput(value, target.customTextColor || this.accentColor());
              });
            }
          })
        }

        this.regexEmphasisToggle('设置高亮色块', this.regexRuleAt(index).customHighlightEnabled,
          (enabled: boolean) => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
              target.customHighlightEnabled = enabled;
              if (enabled && !target.customHighlightColor.trim()) {
                target.customHighlightColor = this.accentColor();
              }
            });
          })
        if (this.regexRuleAt(index).customHighlightEnabled) {
          AdaptiveColorPicker({
            allowAlpha: true,
            value: this.regexRuleAt(index).customHighlightColor,
            placeholder: this.accentColor(),
            appDarkMode: this.appDarkMode,
            accentColor: this.accentColor(),
            optionTitle: '高亮色块颜色',
            directSelection: true,
            onColorChange: (value: string) => {
              this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                target.customHighlightColor = this.normalizeColorInput(value,
                  target.customHighlightColor || this.accentColor());
              });
            }
          })
        }

        this.regexEmphasisToggle('设置强调气泡', this.regexRuleAt(index).customBubbleEnabled,
          (enabled: boolean) => {
            this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
              target.customBubbleEnabled = enabled;
              if (enabled && !target.customBubbleColor.trim()) {
                target.customBubbleColor = this.accentColor();
              }
            });
          })
        if (this.regexRuleAt(index).customBubbleEnabled) {
          Row() {
            Text('气泡风格')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Select(this.bubbleStyleOptions())
              .selected(this.bubbleStyleIndex(this.regexRuleAt(index).bubbleStyleId))
              .value(this.bubbleStyleLabel(this.regexRuleAt(index).bubbleStyleId))
              .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
              .fontColor(this.subTextColor())
              .backgroundColor(Color.Transparent)
              .arrowPosition(ArrowPosition.END)
              .padding({ left: 0, right: 0 })
              .borderRadius(16)
              .border({ width: 0 })
              .divider(null)
              .optionBgColor(Color.Transparent)
              .optionFontColor(this.primaryTextColor())
              .selectedOptionFontColor(this.accentColor())
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
              .menuBackgroundBlurStyle(BlurStyle.NONE)
              .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
              .onSelect((selectedIndex: number) => {
                const selectedStyleId = this.bubbleStyleByIndex(selectedIndex);
                this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                  target.bubbleStyleId = selectedStyleId;
                });
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          AdaptiveColorPicker({
            allowAlpha: true,
            value: this.regexRuleAt(index).customBubbleColor,
            placeholder: this.accentColor(),
            appDarkMode: this.appDarkMode,
            accentColor: this.accentColor(),
            optionTitle: '强调气泡颜色',
            directSelection: true,
            onColorChange: (value: string) => {
              this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
                target.customBubbleColor = this.normalizeColorInput(value,
                  target.customBubbleColor || this.accentColor());
              });
            }
          })
        }
      }
    }
    .width('100%')
  }

  @Builder
  regexEmphasisToggle(title: string, enabled: boolean, onChange: (enabled: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      AdaptiveSwitch({ isOn: enabled,
        onChange: (checked: boolean) => {
          onChange(checked);
        },
      })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.MD })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }
  @Builder
  compactFontModeItem(title: string, mode: string, family: string, onChange: (mode: string, family: string) => void) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Select(this.fontOptions())
        .selected(this.selectedFontIndex(mode, family))
        .value(this.selectedFontValue(mode, family))
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .divider(null)
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => {
          if (index >= this.remoteFontStart()) {
            this.selectRemoteFont(index - this.remoteFontStart(), (customIndex: number) => {
              const downloaded = this.modeAndFamilyByIndex(customIndex + 2);
              if (downloaded.length === 2) onChange(downloaded[0], downloaded[1]);
            });
            return;
          }
          const result = this.modeAndFamilyByIndex(index);
          if (result.length === 2) onChange(result[0], result[1]);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.MD })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  regexFontSizeStepper(index: number) {
    Row({ space: AppSpacing.MD }) {
      Text('字体大小')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      this.fontSizeStepButton($r('sys.symbol.minus'), '减小规则字体',
        this.regexRuleAt(index).fontSize > 14, () => {
        this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
          target.fontSize = Math.max(14, Math.round(target.fontSize) - 1);
        });
      })
      Text(`${Math.round(this.regexRuleAt(index).fontSize)}sp`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .width(52)
        .height(36)
        .textAlign(TextAlign.Center)
      this.fontSizeStepButton($r('sys.symbol.plus'), '增大规则字体',
        this.regexRuleAt(index).fontSize !== 50, () => {
        this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
          target.fontSize = Math.min(50, Math.round(target.fontSize) + 1);
        });
      })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.MD })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  regexEnableSwitchItem() {
    Row() {
      Text('启用正则字体')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      AdaptiveSwitch({ isOn: this.readerRegexFontEnabled,
        onChange: (checked: boolean) => {
          this.readerRegexFontEnabled = checked;
          this.saveSettings();
        },
      })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

}
