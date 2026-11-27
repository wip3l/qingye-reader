import { router } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { ReaderTitleSplit } from '../core/reader/ReaderTitleSplit';
import {
  ReaderChapterDecoration,
  ReaderDropCapMode,
  ReaderTitleStyleCodec,
  ReaderTitleStyleSettings
} from '../model/reader/ReaderTitleStyle';
import { ReaderChapterHead } from '../model/reader/ReaderChapterHead';
import { DROP_CAP_STYLE_RAISE } from '../theme/share/ThemePackageFormat';
import { ReaderFontWeightStepper } from '../components/reader/ReaderFontWeightStepper';
import { ReaderWeightedText, ReaderWeightedTextSpan } from '../components/reader/ReaderWeightedText';
import { ReaderTypographyPreview, ReaderTypographyPreviewConfig } from '../components/reader/ReaderTypographyPreview';
import { ReaderV2DocumentParser } from '../core/reader/ReaderV2Document';
import { ReaderV2BubbleFrame, ReaderV2Color, ReaderV2SpanStyleRange } from '../core/reader/ReaderV2Style';
import { ReaderParagraphIndentMatcher } from '../core/reader/ReaderParagraphIndent';
import { ReaderTextNormalizer } from '../core/reader/ReaderTextNormalizer';
import { ReaderRegexSample } from '../core/reader/ReaderRegexSample';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderFontPreviewImage, ReaderFontPreviewImages, ReaderFontPreviewRequest } from '../utils/ReaderFontPreviewImages';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ColorCodePicker } from '../components/ColorCodePicker';
import { AdaptiveIconButton } from '../components/AdaptiveIconButton';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { MaterialSegmentTabs } from '../components/common/MaterialSegmentTabs';
import { SettingSegment } from '../components/common/SettingSegment';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderRegexFontCodec,
  ReaderRegexFontRule,
  ReaderRegexLegacySettings,
  ReaderRegexScope,
  ReaderResolvedRegexEmphasis,
  ReaderTitleEmphasis,
  ReaderTitleEmphasisPlan
} from '../model/reader/ReaderRegexFontRule';
import { ReaderRegexRuleHits, ReaderRuleMatchSpec } from '../core/reader/ReaderRegexRuleHits';
import { ReaderDialogueMatcher } from '../core/reader/ReaderDialogueMatcher';
import { ReaderNameStyle } from '../model/reader/ReaderNameStyle';
import { ReaderNamePatterns } from '../core/reader/ReaderNamePatterns';
import { MimoBookCast, MimoStore } from '../utils/mimo/MimoStore';
import { MimoRole } from '../core/mimo/MimoPolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ListDissolve } from '../utils/ListDissolve';
import { DeleteParticleBurst, DeleteParticleLayer } from '../components/common/DeleteParticles';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemePackRegistry } from '../theme/ThemePackRegistry';
import { ThemeAccessPolicy } from '../account/ThemeAccessPolicy';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { CloudAutoSync, CloudRemoteFont } from '../account/CloudAutoSync';
import { CloudFontMenu } from '../account/CloudFontMenu';
import { ThemeTypographyDraft } from '../utils/ThemeTypographyDraft';
import { ReaderTitlePreviewStore } from '../utils/ReaderTitlePreviewStore';
import { ThemedDialog } from '../utils/ThemedDialog';

class ReaderCustomFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class ReaderCustomFontData {
  fonts: ReaderCustomFontItem[] = [];
}

/** 字体设置分四段显示，顶部切换；默认停在正文字体。 */
export const READER_FONT_SECTION_LABELS: string[] = ['自定义字体', '正文字体', '标题字体', '正则字体'];
export const READER_FONT_SECTION_BODY: number = 1;

/** 共用规则控件时，编辑页草稿用的下标（-1 已被标题强调占用）。 */
const EDITING_REGEX_RULE_INDEX: number = -2;
/** 人名样式不在规则列表里，编辑时用这个下标（小于 0，和新建一样不在列表里找）。 */
const NAME_STYLE_RULE_INDEX = -3;
const NAME_STYLE_BOOK_PARAM = ReaderNameStyle.PARAM_BOOK;
const NAME_STYLE_ROLE_PARAM = ReaderNameStyle.PARAM_ROLE;
/** 正则规则列表的行高：列表嵌在页面滚动里，按行数给定高度。 */
const REGEX_RULE_ROW_HEIGHT: number = 64;
const TITLE_PREVIEW_BOX_ID: string = 'reader_title_preview_box';
/** 规则预览没有命中时，直接画成强调效果的那几个字。 */
const REGEX_PREVIEW_FALLBACK_SAMPLE: string = '强调文字';

/** 规则预览的排版结果，带上标题强调占掉的范围，规则命中和它重叠时让给标题强调。 */
class RegexRulePreview {
  config: ReaderTypographyPreviewConfig;
  titleStyles: ReaderV2SpanStyleRange[];

  constructor(config: ReaderTypographyPreviewConfig, titleStyles: ReaderV2SpanStyleRange[]) {
    this.config = config;
    this.titleStyles = titleStyles;
  }
}

class ReaderBubbleStyleOption {
  styleId: string = '';
  label: string = '';

  constructor(styleId: string, label: string) {
    this.styleId = styleId;
    this.label = label;
  }
}

@Component
export struct ReaderFontSettingsEditor {
  @Prop embedded: boolean = false;
  // 外层自己放切换栏时传入当前分段（小说设置的悬浮面板把切换栏固定在面板顶部）；-1 表示由本组件显示切换栏。
  @Prop fontSection: number = -1;
  @State ownFontSection: number = READER_FONT_SECTION_BODY;
  @State editorWidth: number = 0;
  private pageScroller: Scroller = new Scroller();
  // 标题预览框的真实高度；滚出屏幕时冻结在这个高度（0 为不冻结）。
  private titlePreviewHeight: number = 0;
  @State titlePreviewFrozenHeight: number = 0;
  // 字体列表的名字预览图生成好后加一，让对应行换成图片。
  @State customFontPreviewVersion: number = 0;
  private customFontPreviewAlive: boolean = true;
  private onCustomFontPreviewReady: () => void = (): void => {
    if (this.customFontPreviewAlive) this.customFontPreviewVersion++;
  };
  // customFonts() 每次都要解析 JSON 并逐个检查文件，列表每一行会调好几次；按原始串缓存，字体多时不再拖住主线程。
  private customFontsCacheRaw: string = '';
  private customFontsCache: ReaderCustomFontItem[] = [];
  onStylePreviewChanged: (settings: ReaderSettings) => void = (_settings: ReaderSettings): void => {};
  onCloseReady: (close: () => void) => void = (_close: () => void): void => {};
  onShownReady: (show: () => void) => void = (_show: () => void): void => {};
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
  @State titlePreviewText: string = ReaderTitlePreviewStore.DEFAULT_TEXT;
  // 示例编辑框展开的位置：顶部标题预览 'preview'、标题分段 'split'，空串为收起。
  @State titlePreviewEditingAt: string = '';
  // 读出上次的示例之前用户已经改过，就不再用读到的值覆盖。
  private titlePreviewTouched: boolean = false;
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
  /** 正在拖动排序的规则 id；嵌入时只给这一行补卡片底色。 */
  @State draggingRegexRuleId: string = '';
  /** 长按弹出菜单的规则 id；空表示没有菜单。 */
  @State regexRuleMenuId: string = '';
  /** 正在消散的正则规则 id，见 ListDissolve。 */
  @State dissolvingRuleIds: string[] = [];
  @State deleteParticleBursts: DeleteParticleBurst[] = [];
  @State regexHighlightRefreshKey: number = 0;
  @State activeRegexInputKey: string = '';
  // 正则规则在单独的编辑页里改草稿，点保存才写回列表；新建规则的下标为 -1。
  @State regexEditorShown: boolean = false;
  @State editingRegexRule: ReaderRegexFontRule = new ReaderRegexFontRule();
  private editingRegexRuleIndex: number = -1;
  private editingRegexRuleSnapshot: string = '';
  private readerSettingsLoaded: boolean = false;
  private readerSettingsLoading: boolean = false;
  private closingReaderFontSettings: boolean = false;
  private latestReaderFontStyleSave: Promise<void> = Promise.resolve();
  private latestReaderFontStyleSettings: ReaderSettings | null = null;
  private readerFontStyleSaveTimerId: number = -1;
  // 从主题排版页打开时只编辑那一页的草稿，保存与否由主题排版页决定。
  private draftMode: boolean = false;
  // 人名样式模式（见 openNameStyleEditor）：改的是哪本书、哪个人（空为全书的人名样式）。
  private nameStyleBook: string = '';
  private nameStyleRoleId: string = '';
  private nameStyleRoleName: string = '';
  private nameStyleOpened: boolean = false;
  private nameStylePreviewNames: string[] = [];
  private nameStyleSnapshotExtra: string = '';
  @State nameStyleColorMode: string = ReaderNameStyle.MODE_ROLE;
  @State nameStyleFollow: boolean = false;

  aboutToAppear(): void {
    this.onCloseReady(() => { this.closeReaderFontSettings(); });
    this.onShownReady(() => { this.onPageShow(); });
    const params = router.getParams() as Record<string, Object> | undefined;
    // 从“本书人物”打开：直接进规则编辑页改本书的人名样式（或某个人单独的样式），保存写回人物档案。
    if (!this.embedded && params && typeof params[NAME_STYLE_BOOK_PARAM] === 'string') {
      this.nameStyleBook = params[NAME_STYLE_BOOK_PARAM] as string;
      this.nameStyleRoleId = typeof params[NAME_STYLE_ROLE_PARAM] === 'string' ?
        params[NAME_STYLE_ROLE_PARAM] as string : '';
    }
    this.draftMode = !!params && params[ThemeTypographyDraft.DRAFT_PARAM] === true &&
      ThemeTypographyDraft.current() !== null;
    this.loadSettings();
    this.loadTitlePreviewText();
    this.syncBars();
  }

  async loadTitlePreviewText(): Promise<void> {
    try {
      const text = await ReaderTitlePreviewStore.load(getContext(this));
      if (!this.titlePreviewTouched) this.titlePreviewText = text;
    } catch (e) {
      console.warn('读取标题预览示例失败:', e);
    }
  }

  setTitlePreviewText(text: string): void {
    this.titlePreviewTouched = true;
    this.titlePreviewText = text;
    ReaderTitlePreviewStore.save(getContext(this), text).catch((e: Error) => {
      console.warn('保存标题预览示例失败:', e);
    });
  }

  aboutToDisappear(): void {
    this.customFontPreviewAlive = false;
    this.flushScheduledSettingsSave();
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
    if (this.regexEditorShown) {
      this.leaveRegexRuleEditor();
      return;
    }
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
      if (this.isNameStyleMode() && !this.nameStyleOpened) this.openNameStyleEditor();
      this.onStylePreviewChanged(settings);
    } catch (e) {
      console.warn('加载阅读字体设置失败:', e);
    } finally {
      this.readerSettingsLoading = false;
    }
  }

  build() {
    Column() {
      if (this.isNameStyleMode()) {
        // 只用来改人名样式时底下不放字体设置页，编辑页收起时不会先露出它再返回。
        Blank()
      } else if (this.embedded) {
        this.pageContent()
      } else {
        PageScaffold({ title: this.draftMode ? '主题阅读字体' : '阅读字体', scroller: this.pageScroller,
          onBack: () => this.closeReaderFontSettings(), content: () => {
          this.pageContent()
        } })
      }

      // 同一节点只能挂一个模态，标题预览面板已占了根节点，规则编辑页单独挂在 1×1 节点上。
      Column().width(1).height(1).position({ x: 0, y: 0 }).hitTestBehavior(HitTestMode.None)
        .bindContentCover($$this.regexEditorShown, this.regexRuleEditorCover(), {
          transition: this.regexEditorTransition(),
          // 侧滑返回也走“是否保存？”，由 leaveRegexRuleEditor 决定关不关。
          onWillDismiss: (_action: DismissContentCoverAction): void => this.leaveRegexRuleEditor()
        })
    }
    .width('100%')
    .height(this.embedded ? 'auto' : '100%')
    .onAreaChange((_previous: Area, current: Area) => {
      const width = Number(current.width);
      if (width > 0 && Math.abs(width - this.editorWidth) >= 1) this.editorWidth = width;
    })
    .backgroundColor(this.embedded ? Color.Transparent : this.pageColor())
    .expandSafeArea(this.embedded ? [] : [SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.titleReadingPreview, this.titleReadingPreviewSheet, {
      height: SheetSize.LARGE, dragBar: true, showClose: true,
      backgroundColor: ThemeRuntime.readerBackgroundColor(this.appDarkMode)
    })
  }

  regexEditorTransition(): TransitionEffect {
    const appear = TransitionEffect.translate({ x: 48 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 260, curve: Curve.Friction });
    const disappear = TransitionEffect.translate({ x: 48 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 180, curve: Curve.EaseIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  activeFontSection(): number {
    return this.fontSection >= 0 ? this.fontSection : this.ownFontSection;
  }

  @Builder
  pageContent() {
    if (this.fontSection < 0) {
      Row() {
        MaterialSegmentTabs({ labels: READER_FONT_SECTION_LABELS, selectedIndex: this.ownFontSection,
          tabsWidth: Math.max(1, (this.editorWidth || 360) - AppSpacing.LG * 2), idPrefix: 'reader_font_section',
          onSelect: (index: number) => { this.ownFontSection = index; } })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: AppSpacing.SM })
    }
    if (this.activeFontSection() === 0) {
      this.customFontSection()
    } else if (this.activeFontSection() === 1) {
      this.bodyFontSection()
    } else if (this.activeFontSection() === 2) {
      this.titleFontSection()
    } else {
      this.regexFontSection()
    }
  }

  @Builder
  customFontSection() {
    this.customFontEntryItem()
    this.sectionTitle('已上传的字体')
    Column() {
      if (this.customFonts().length === 0) {
        Text('还没有上传字体，点上方“上传 / 管理”添加 ttf、otf、ttc 字体文件。')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
      }
      ForEach(this.customFonts(), (font: ReaderCustomFontItem, index: number) => {
        this.customFontRow(font, index)
      }, (font: ReaderCustomFontItem) => font.filePath || font.familyName)
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.embedded ? Color.Transparent : this.cardColor())
  }

  @Builder
  customFontRow(font: ReaderCustomFontItem, index: number) {
    Row({ space: AppSpacing.MD }) {
      Row() {
        if (this.customFontPreviewImage(font, index) !== null) {
          Image(this.customFontPreviewImage(font, index)?.uri ?? '')
            .width(this.customFontPreviewImage(font, index)?.widthVp ?? 0)
            .height(this.customFontPreviewImage(font, index)?.heightVp ?? 0)
            .objectFit(ImageFit.Contain)
            .syncLoad(true)
            .draggable(false)
            .accessibilityText(font.sourceName || font.familyName)
        } else {
          Text(font.sourceName || font.familyName)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
            .fontFamily(this.applicationFontFamily)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      if (this.customFontUsage(index)) {
        Text(this.customFontUsage(index))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
      }
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 52 })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .border({ width: { bottom: index < this.customFonts().length - 1 ? 0.5 : 0 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 列表里用字体本身显示名字：用预先画好的名字图片，不注册字体（注册一款就要把整个字体常驻内存）。
   * 图片还没画好或画不出时返回 null，这一行先用界面字体显示。
   */
  customFontPreviewImage(font: ReaderCustomFontItem, index: number): ReaderFontPreviewImage | null {
    // 读一次版本号，图片生成好后这一行跟着刷新。
    if (this.customFontPreviewVersion < 0 || !font.filePath) return null;
    const context = this.getUIContext();
    ReaderFontPreviewImages.init(getContext(this).cacheDir);
    const request = new ReaderFontPreviewRequest();
    request.filePath = font.filePath;
    request.label = font.sourceName || font.familyName;
    request.fontSizeFp = AppFontSize.BODY_LARGE;
    request.color = this.primaryTextColor();
    request.density = context.vp2px(1);
    request.fontScale = context.fp2px(1) / Math.max(0.01, context.vp2px(1));
    // 行宽：卡片左右各 12vp 外边距、行内左右各 16vp，“在用”标记约 110vp。
    request.maxWidthVp = Math.max(80, (this.editorWidth || 360) - 56 - (this.customFontUsage(index) ? 110 : 0));
    return ReaderFontPreviewImages.lookup(request, this.onCustomFontPreviewReady);
  }

  /** 这款字体正被正文或标题使用时，在列表里标出来。 */
  customFontUsage(index: number): string {
    const optionIndex = index + 2;
    const uses: string[] = [];
    if (this.selectedFontIndex(this.readerBodyFontMode, this.readerBodyFontFamily) === optionIndex) {
      uses.push('正文');
    }
    if (this.selectedFontIndex(this.readerTitleFontMode, this.readerTitleFontFamily) === optionIndex) {
      uses.push('标题');
    }
    return uses.length > 0 ? `${uses.join('、')}在用` : '';
  }

  @Builder
  bodyFontSection() {
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
      this.bodyDropCapItem()
      if (!this.embedded) {
        this.bodyPreviewItem()
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.embedded ? Color.Transparent : this.cardColor())
  }

  @Builder
  titleFontSection() {
    this.sectionTitle('标题字体设置')
    Column() {
      if (!this.embedded) {
        this.titlePreviewItem()
      }
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
    .backgroundColor(this.embedded ? Color.Transparent : this.cardColor())
  }

  @Builder
  regexFontSection() {
    this.sectionTitle('正则字体设置')
    // 开关和规则分成两张卡：规则是用户自己建的条目，和普通设置项分开才认得出来。
    Column() {
      this.regexEnableSwitchItem()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.embedded ? Color.Transparent : this.cardColor())
    if (this.readerRegexFontEnabled) {
      this.regexRulesGroupTitle()
      // 编辑器可能嵌在主题编辑器里、没有统一的根层，粒子层套在规则卡片外面（外层不裁切，颗粒能飘出卡片）。
      Stack() {
        if (this.regexRules.length === 0) {
          Column() {
            this.emptyRegexRule()
          }
          .width('100%')
          .borderRadius(ThemeRuntime.cardRadius())
          .clip(true)
          .backgroundColor(this.embedded ? Color.Transparent : this.cardColor())
        } else {
          // 同一段字被几条规则命中时用靠上的那条，所以列表顺序就是优先级：长按一行拖动调整。
          // 外层是页面的滚动容器，列表按行数给定高度，不自己滚。
          List() {
            // 键里不能带下标或“是否最后一行”：拖动只换位置，键一变条目就重建、拖动会断。
            // 序号和分隔线在行里按 id 现查。
            ForEach(this.regexRules, (rule: ReaderRegexFontRule) => {
              ListItem() {
                this.regexRuleRow(rule)
              }
              // 左滑出“停用/启用”和“删除”。不设整条滑到底就执行，免得拖过头误删。
              .swipeAction({
                end: {
                  builder: () => {
                    this.regexRuleSwipeActions(rule)
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
              // 键里带启用状态：切换后条目重建，左滑出来的按钮随之收回。
            }, (rule: ReaderRegexFontRule) => `${rule.id}|${rule.name}|${rule.pattern}|${rule.scope}|${rule.enabled}|${rule.matcher}|${this.dialogueRuleSummary(rule)}`)
              .onMove((from: number, to: number) => this.moveRegexRuleDuringDrag(from, to), {
                onDragStart: (index: number) => {
                  this.draggingRegexRuleId = index >= 0 && index < this.regexRules.length ? this.regexRules[index].id : '';
                },
                onDrop: (_index: number) => {
                  this.draggingRegexRuleId = '';
                  this.saveSettings();
                }
              })
          }
          .width('100%')
          .height(REGEX_RULE_ROW_HEIGHT * this.regexRules.length)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .borderRadius(ThemeRuntime.cardRadius())
          .clip(true)
          .backgroundColor(this.embedded ? Color.Transparent : this.cardColor())
        }

        if (this.deleteParticleBursts.length > 0) {
          DeleteParticleLayer({ bursts: this.deleteParticleBursts })
        }
      }
      .id('reader_regex_rules_root')
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      if (this.regexRules.length >= 2) {
        this.regexRuleOrderHint()
      }
    }
  }

  @Builder
  regexRuleOrderHint() {
    Row({ space: AppSpacing.XS }) {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(14)
        .fontColor([this.subTextColor()])
        .margin({ top: 2 })
      Text('同一段文字被几条规则命中时，用排在上面的那条。按住前方把手拖动调整顺序，左滑或长按可停用。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM })
  }

  @Builder
  regexRuleSwipeActions(rule: ReaderRegexFontRule) {
    Row() {
      Column({ space: AppSpacing.XS }) {
        SymbolGlyph(rule.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'))
          .fontSize(20)
          .fontColor(['#FFFFFF'])
        Text(rule.enabled ? '停用' : '启用')
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFF')
      }
      .width(64)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
      .accessibilityText(rule.enabled ? '停用规则' : '启用规则')
      .onClick(() => this.toggleRegexRuleEnabled(rule.id))
      Column({ space: AppSpacing.XS }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor(['#FFFFFF'])
        Text('删除')
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFF')
      }
      .width(64)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
      .accessibilityText('删除规则')
      .onClick(() => this.confirmDeleteRegexRule(rule))
    }
    .height(REGEX_RULE_ROW_HEIGHT)
  }

  /** 长按规则弹出的菜单：编辑、停用/启用、删除。 */
  @Builder
  regexRuleMenu() {
    Column() {
      PopupMenuAction($r('sys.symbol.square_and_pencil'), '编辑', this.primaryTextColor(), () => {
        const ruleId = this.regexRuleMenuId;
        this.regexRuleMenuId = '';
        const index = this.regexRules.findIndex((rule: ReaderRegexFontRule) => rule.id === ruleId);
        if (index >= 0) this.openRegexRuleEditor(index, this.regexRules[index]);
      })
      PopupMenuAction(this.regexRuleMenuEnabled() ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'),
        this.regexRuleMenuEnabled() ? '停用' : '启用', this.primaryTextColor(), () => {
          const ruleId = this.regexRuleMenuId;
          this.regexRuleMenuId = '';
          if (ruleId) this.toggleRegexRuleEnabled(ruleId);
        })
      PopupMenuAction($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
        const ruleId = this.regexRuleMenuId;
        this.regexRuleMenuId = '';
        const rule = this.regexRules.find((item: ReaderRegexFontRule) => item.id === ruleId);
        if (rule) this.confirmDeleteRegexRule(rule);
      })
    }
    .width(168)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  regexRuleMenuEnabled(): boolean {
    const rule = this.regexRules.find((item: ReaderRegexFontRule) => item.id === this.regexRuleMenuId);
    return rule ? rule.enabled : true;
  }

  regexRuleDisabledCount(): number {
    return this.regexRules.filter((rule: ReaderRegexFontRule): boolean => !rule.enabled).length;
  }

  /** 拖动中只改顺序；松手由 onDrop 保存一次。 */
  moveRegexRuleDuringDrag(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 || from >= this.regexRules.length || to >= this.regexRules.length) return;
    const next = this.regexRules.slice();
    const moved = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.regexRules = next;
  }

  regexRuleNumber(ruleId: string): number {
    return this.regexRules.findIndex((rule: ReaderRegexFontRule) => rule.id === ruleId) + 1;
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
    this.onStylePreviewChanged(settings);
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

  /** “新建 › 对话”：智能对话规则。 */
  addDialogueRule(): void {
    this.addRegexRule('对话', '', true);
  }

  /** 模板按钮直接进新建页，保存后才加入列表。 */
  addRegexRule(name: string, pattern: string, dialogue: boolean = false): void {
    const rule = new ReaderRegexFontRule();
    rule.id = this.newRuleId();
    rule.name = name;
    rule.pattern = pattern;
    if (dialogue) ReaderRegexFontCodec.makeDialogue(rule);
    rule.fontMode = 'global';
    rule.fontSize = this.readerRegexFontSize || this.readerFontSize;
    rule.emphasisMode = 'inherit';
    rule.bubbleStyleId = 'inherit';
    rule.emphasisColor = '';
    rule.highlightColorEnabled = false;
    rule.shadowColor = '';
    this.openRegexRuleEditor(-1, rule);
  }

  openRegexRuleEditor(index: number, rule: ReaderRegexFontRule): void {
    this.editingRegexRuleIndex = index;
    this.editingRegexRule = ReaderRegexFontCodec.cloneRule(rule);
    this.editingRegexRuleSnapshot = this.encodeRegexRules([this.editingRegexRule]);
    this.activeRegexInputKey = '';
    this.bumpRegexHighlightRefresh();
    this.regexEditorShown = true;
  }

  isEditingNewRegexRule(): boolean {
    return this.editingRegexRuleIndex < 0;
  }

  editingRegexRuleListIndex(): number {
    for (let i = 0; i < this.regexRules.length; i++) {
      if (this.regexRules[i].id === this.editingRegexRule.id) {
        return i;
      }
    }
    return -1;
  }

  saveRegexRuleEditor(): void {
    if (!this.regexEditorShown) return;
    if (this.isNameStyleMode()) {
      this.saveNameStyle();
      return;
    }
    const rule = ReaderRegexFontCodec.cloneRule(this.editingRegexRule);
    const next = this.regexRules.slice();
    const index = this.editingRegexRuleListIndex();
    if (index >= 0) {
      next[index] = rule;
    } else {
      next.push(rule);
    }
    this.regexRules = next;
    this.bumpRegexHighlightRefresh();
    this.saveSettings(next);
    this.closeRegexRuleEditor();
  }

  /** 返回时有改动（新建的规则总算有改动）就问是否保存。 */
  leaveRegexRuleEditor(): void {
    if (!this.regexEditorShown) return;
    const changed = this.isNameStyleMode() ? this.nameStyleChanged() : (this.isEditingNewRegexRule() ||
      this.encodeRegexRules([this.editingRegexRule]) !== this.editingRegexRuleSnapshot);
    if (!changed) {
      this.closeRegexRuleEditor();
      return;
    }
    ThemedDialog.showAlertDialog(this.getUIContext(), {
      title: '是否保存？',
      message: this.isNameStyleMode() ? '人名样式的修改还没有保存。' :
        (this.isEditingNewRegexRule() ? '这条新规则还没有保存。' : '这条规则的修改还没有保存。'),
      primaryButton: { value: '不保存', action: () => this.closeRegexRuleEditor() },
      secondaryButton: { value: '保存', action: () => this.saveRegexRuleEditor() }
    });
  }

  async deleteEditingRegexRule(): Promise<void> {
    const index = this.editingRegexRuleListIndex();
    this.closeRegexRuleEditor();
    if (index < 0 || index >= this.regexRules.length) return;
    // 编辑面板滑走后这一条再消散，播完在补位动画里删掉。
    await this.dissolveRegexRule(`${this.regexRules[index].id}`);
  }

  /** 列表左滑删除：先确认，再按编辑页删除同样消散。 */
  confirmDeleteRegexRule(rule: ReaderRegexFontRule): void {
    ThemedDialog.showAlertDialog(this.getUIContext(), {
      title: '删除规则',
      message: `确定删除“${rule.name || '正则规则'}”吗？只想暂时不用可以选“停用”。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: ThemeRuntime.dangerColor(this.appDarkMode),
        action: () => {
          this.dissolveRegexRule(`${rule.id}`);
        }
      }
    });
  }

  toggleRegexRuleEnabled(ruleId: string): void {
    this.updateRegexRuleById(ruleId, (target: ReaderRegexFontRule) => {
      target.enabled = !target.enabled;
    });
  }

  async dissolveRegexRule(ruleId: string): Promise<void> {
    const keys = [ruleId];
    await ListDissolve.fadeOut(this.getUIContext(), keys, (key: string) => {
      this.dissolvingRuleIds = [...this.dissolvingRuleIds, key];
    }, ListDissolve.particles('reader_regex_rules_root', [this.accentColor(), this.primaryTextColor(), this.subTextColor()],
      (key: string): string => this.regexRuleElementId(key), (): DeleteParticleBurst[] => this.deleteParticleBursts,
      (bursts: DeleteParticleBurst[]): void => { this.deleteParticleBursts = bursts; }), ListDissolve.AFTER_DIALOG_MS);
    ListDissolve.commit(this.getUIContext(), () => {
      const current = this.regexRules.findIndex((rule: ReaderRegexFontRule) => `${rule.id}` === ruleId);
      if (current >= 0) this.removeRegexRule(current);
    }, () => {
      this.dissolvingRuleIds = ListDissolve.without(this.dissolvingRuleIds, keys);
    });
  }

  regexRuleElementId(key: string): string {
    return `reader_regex_rule_${encodeURIComponent(key)}`;
  }

  isRegexRuleDissolving(rule: ReaderRegexFontRule): boolean {
    return this.dissolvingRuleIds.length > 0 && this.dissolvingRuleIds.indexOf(`${rule.id}`) >= 0;
  }

  closeRegexRuleEditor(): void {
    this.activeRegexInputKey = '';
    this.regexEditorShown = false;
    // 只为改人名样式打开的这一页：编辑页收起就回到本书人物页。
    if (this.isNameStyleMode()) router.back();
  }

  updateRegexRule(index: number, updater: (rule: ReaderRegexFontRule) => void): void {
    if (index === EDITING_REGEX_RULE_INDEX) {
      const draft = ReaderRegexFontCodec.cloneRule(this.editingRegexRule);
      updater(draft);
      this.editingRegexRule = draft;
      this.bumpRegexHighlightRefresh();
      return;
    }
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
    if (raw === this.customFontsCacheRaw) {
      return this.customFontsCache;
    }
    this.customFontsCache = this.parseCustomFonts(raw);
    this.customFontsCacheRaw = raw;
    return this.customFontsCache;
  }

  parseCustomFonts(raw: string): ReaderCustomFontItem[] {
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
    if (this.embedded) return;
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  customFontEntryItem() {
    Row() {
      Text('自定义字体')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      Text('上传 / 管理')
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
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
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

  /**
   * 首字装饰：四张样式卡（跟随主题 / 下沉 / 放大 / 关闭）加行数。设置和标题样式存在一起（随主题排版走），
   * 入口放在正文这一组。跟随主题时行数显示主题的值、不能改；主题没设首字时不显示行数。
   */
  @Builder
  bodyDropCapItem() {
    Column() {
      Column({ space: AppSpacing.XS }) {
        Text('首字装饰').fontSize(AppFontSize.BODY_LARGE).fontColor(this.primaryTextColor())
        Text(`${ReaderChapterHead.describeDropCap(ThemeRuntime.chapterHeadTokens(this.appDarkMode))
          }；开头是引号、数字、字母时不处理`)
          .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Row({ space: AppSpacing.SM }) {
        this.dropCapTile(ReaderDropCapMode.THEME, '跟随主题')
        this.dropCapTile(ReaderDropCapMode.SINK, '下沉')
        this.dropCapTile(ReaderDropCapMode.RAISE, '放大')
        this.dropCapTile(ReaderDropCapMode.OFF, '关闭')
      }
      .width('100%')
      .margin({ top: AppSpacing.MD })
      if (this.dropCapLinesShown()) {
        Row({ space: AppSpacing.MD }) {
          Column({ space: AppSpacing.XXS }) {
            Text(this.dropCapRaised() ? '首字高度' : '占几行')
              .fontSize(AppFontSize.BODY).fontColor(this.primaryTextColor())
            Text(this.dropCapLinesHint()).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          this.fontSizeStepButton($r('sys.symbol.minus'), '首字少占一行',
            () => this.dropCapLinesEditable() && this.titleStyle.dropCapLines > ReaderDropCapMode.MIN_LINES, () => {
              this.updateTitleSplit('dropCapLines', `${this.titleStyle.dropCapLines - 1}`);
            })
          Text(`${this.dropCapLinesValue()} 行`)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.dropCapLinesEditable() ? this.primaryTextColor() : this.subTextColor())
            .width(52)
            .textAlign(TextAlign.Center)
          this.fontSizeStepButton($r('sys.symbol.plus'), '首字多占一行',
            () => this.dropCapLinesEditable() && this.titleStyle.dropCapLines < ReaderDropCapMode.MAX_LINES, () => {
              this.updateTitleSplit('dropCapLines', `${this.titleStyle.dropCapLines + 1}`);
            })
        }
        .width('100%')
        .margin({ top: AppSpacing.LG })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: AppSpacing.MD, bottom: AppSpacing.LG })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  /** 一张首字样式卡：上面是这种样式的示意（几条正文线加一个首字方块），下面是名字。 */
  @Builder
  dropCapTile(mode: string, label: string) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (mode === ReaderDropCapMode.OFF) {
          this.dropCapTileBar(12, 6)
          this.dropCapTileBar(4, 16)
          this.dropCapTileBar(4, 26)
          this.dropCapTileBar(4, 36)
        } else if (mode === ReaderDropCapMode.RAISE) {
          this.dropCapTileCap(4, 0, 17)
          this.dropCapTileBar(25, 14)
          this.dropCapTileBar(4, 24)
          this.dropCapTileBar(4, 33)
        } else {
          this.dropCapTileCap(4, 4, 15)
          this.dropCapTileBar(23, 6)
          this.dropCapTileBar(23, 16)
          this.dropCapTileBar(4, 26)
          this.dropCapTileBar(4, 36)
          if (mode === ReaderDropCapMode.THEME) {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(9)
              .fontColor([this.accentColor()])
              .position({ right: 0, top: -4 })
          }
        }
      }
      .width('100%')
      .height(40)
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.titleStyle.dropCap === mode ? this.accentColor() : this.primaryTextColor())
        .fontWeight(this.titleStyle.dropCap === mode ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ left: 6, right: 6, top: 8, bottom: 6 })
    .borderRadius(14)
    .backgroundColor(this.titleStyle.dropCap === mode ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) :
      this.inputColor())
    .border({ width: 1.5, color: this.titleStyle.dropCap === mode ? this.accentColor() : Color.Transparent })
    .accessibilityText(`首字装饰：${label}`)
    .accessibilitySelected(this.titleStyle.dropCap === mode)
    .onClick(() => {
      if (this.titleStyle.dropCap === mode) return;
      this.updateTitleSplit('dropCap', mode);
    })
  }

  @Builder
  dropCapTileBar(x: number, y: number) {
    Row()
      .width(`calc(100% - ${x + 4}vp)`)
      .height(3)
      .borderRadius(1.5)
      .backgroundColor(this.subTextColor())
      .opacity(0.35)
      .position({ x: x, y: y })
  }

  @Builder
  dropCapTileCap(x: number, y: number, size: number) {
    Row()
      .width(size)
      .height(size)
      .borderRadius(4)
      .backgroundColor(this.accentColor())
      .opacity(0.55)
      .position({ x: x, y: y })
  }

  /** 跟随主题且主题没设首字、或关闭时，不显示行数。 */
  dropCapLinesShown(): boolean {
    const mode = this.titleStyle.dropCap;
    if (mode === ReaderDropCapMode.OFF) return false;
    if (mode !== ReaderDropCapMode.THEME) return true;
    const tokens = ThemeRuntime.chapterHeadTokens(this.appDarkMode);
    return !!tokens && tokens.dropCapLines >= 2;
  }

  /** 实际生效的是放大样式（自选放大，或跟随主题且主题设的是放大）。 */
  dropCapRaised(): boolean {
    if (this.titleStyle.dropCap === ReaderDropCapMode.RAISE) return true;
    if (this.titleStyle.dropCap !== ReaderDropCapMode.THEME) return false;
    const tokens = ThemeRuntime.chapterHeadTokens(this.appDarkMode);
    return !!tokens && tokens.dropCapStyle === DROP_CAP_STYLE_RAISE;
  }

  dropCapLinesEditable(): boolean {
    return this.titleStyle.dropCap === ReaderDropCapMode.SINK || this.titleStyle.dropCap === ReaderDropCapMode.RAISE;
  }

  dropCapLinesValue(): number {
    if (this.dropCapLinesEditable()) return this.titleStyle.dropCapLines;
    const tokens = ThemeRuntime.chapterHeadTokens(this.appDarkMode);
    return ReaderDropCapMode.normalizeLines(tokens ? tokens.dropCapLines : 0);
  }

  dropCapLinesHint(): string {
    if (this.titleStyle.dropCap === ReaderDropCapMode.RAISE) return '按几行的高度放大，只占第一行';
    if (this.titleStyle.dropCap === ReaderDropCapMode.SINK) return '首段前几行绕开首字';
    return '跟随主题时由主题决定，选“下沉”或“放大”后可改';
  }

  @Builder
  bodyFontSizeStepper() {
    Row({ space: AppSpacing.MD }) {
      Text('字体大小')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      this.fontSizeStepButton($r('sys.symbol.minus'), '减小正文字体', () => this.readerFontSize > 14, () => {
        this.setBodyFontSize(this.readerFontSize - 1);
      })
      Text(`${this.readerFontSize}sp`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .width(52)
        .height(36)
        .textAlign(TextAlign.Center)
      this.fontSizeStepButton($r('sys.symbol.plus'), '增大正文字体', () => this.readerFontSize < 50, () => {
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
      this.fontSizeStepButton($r('sys.symbol.minus'), '减小标题字体', () => this.readerTitleFontSize > 14, () => {
        this.setTitleFontSize(this.readerTitleFontSize - 1);
      })
      Text(`${this.readerTitleFontSize}sp`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .width(52)
        .height(36)
        .textAlign(TextAlign.Center)
      this.fontSizeStepButton($r('sys.symbol.plus'), '增大标题字体', () => this.readerTitleFontSize < 50, () => {
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
  fontSizeStepButton(icon: Resource, accessibilityText: string, enabled: () => boolean, action: () => void) {
    // enabled 必须是取值函数：@Builder 多参数按值传递，直接传 boolean 只取首次建出时的值，
    // 到过上下限再回来按钮会一直灰着点不了；在绑定里调用才会跟着状态刷新。
    AdaptiveIconButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      buttonEnabled: enabled(),
      buttonSize: 34,
      iconSize: 17,
      fillColor: this.inputColor(),
      iconColor: this.primaryTextColor(),
      disabledIconColor: this.subTextColor(),
      action: action
    })
  }

  /** 规则组标题：写明条数，右侧“新建”菜单里选模板，代替原来卡片里的三个按钮。 */
  @Builder
  regexRulesGroupTitle() {
    Row() {
      Text(`我的规则 · ${this.regexRules.length}` +
        (this.regexRuleDisabledCount() > 0 ? `（${this.regexRuleDisabledCount()} 条已停用）` : ''))
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
      Row({ space: AppSpacing.XXS }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(16)
          .fontColor([this.accentColor()])
        Text('新建')
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor())
      }
      .height(32)
      .padding({ left: AppSpacing.SM, right: AppSpacing.SM })
      .borderRadius(16)
      .alignItems(VerticalAlign.Center)
      .accessibilityText('新建规则')
      .bindMenu([
        { value: '对话', action: () => { this.addDialogueRule(); } },
        { value: '关键字匹配', action: () => { this.addRegexRule('关键字匹配', '关键词'); } },
        { value: '空白规则', action: () => { this.addRegexRule('正则规则', ''); } }
      ])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: AppSpacing.XL, right: AppSpacing.MD, top: AppSpacing.XL, bottom: AppSpacing.SM })
  }

  @Builder
  emptyRegexRule() {
    Text('还没有规则，点右上角“新建”添加。')
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('calc(100% - 32vp)')
      .padding({ left: 0, right: 0, top: AppSpacing.LG, bottom: AppSpacing.LG })
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
  }

  @Builder
  regexRuleRow(rule: ReaderRegexFontRule) {
    Row({ space: AppSpacing.SM }) {
      // 和书源管理一样：只有前方把手不挂长按菜单，长按它才由 List 抬起拖动；其余部分长按出菜单。
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
      }
      .width(32)
      .height('100%')
      .margin({ left: -AppSpacing.SM })
      .hitTestBehavior(HitTestMode.Transparent)
      // 序号按 id 现查：拖动不重建条目，ForEach 的下标会停在旧值。
      Text(`${this.regexRuleNumber(rule.id)}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width(16)
        .textAlign(TextAlign.Center)
        .opacity(rule.enabled ? 1 : 0.5)
      Row({ space: AppSpacing.MD }) {
        Column({ space: AppSpacing.XXS }) {
          Row({ space: AppSpacing.SM }) {
            Text(rule.name || `规则${this.regexRuleNumber(rule.id)}`)
              .fontSize(AppFontSize.BODY_LARGE)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
            if (ReaderRegexScope.badge(rule.scope)) {
              Text(ReaderRegexScope.badge(rule.scope))
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(6)
                .backgroundColor(this.inputColor())
            }
            if (!rule.enabled) {
              Text('已停用')
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(6)
                .backgroundColor(this.inputColor())
            }
          }
          .width('100%')
          // 正则用等宽字体，读起来像表达式，不像说明文字；智能对话写开关摘要。
          Text(ReaderRegexFontCodec.isDialogue(rule) ? this.dialogueRuleSummary(rule) :
            (rule.pattern || '未设置正则表达式'))
            .fontSize(AppFontSize.CAPTION)
            .fontFamily(rule.pattern && !ReaderRegexFontCodec.isDialogue(rule) ? 'monospace' :
              this.applicationFontFamily)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .opacity(rule.enabled ? 1 : 0.5)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
      }
      .layoutWeight(1)
      .height('100%')
      .gesture(LongPressGesture({ repeat: false }).onAction(() => {
        this.regexRuleMenuId = rule.id;
      }))
      .bindPopup(this.regexRuleMenuId === rule.id, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
        (): void => {
          this.regexRuleMenu()
        }, Placement.Bottom, this.appDarkMode, this.accentColor(), () => {
          if (this.regexRuleMenuId === rule.id) this.regexRuleMenuId = '';
        }))
    }
    .width('calc(100% - 32vp)')
    .height(REGEX_RULE_ROW_HEIGHT)
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    // 嵌在悬浮样式面板里时卡片是透明的；拖起来的那一行要盖住下面的行，拖动时补上卡片色。
    .backgroundColor(!this.embedded || this.draggingRegexRuleId === rule.id ? this.cardColor() : Color.Transparent)
    .border({ width: { bottom: this.regexRuleNumber(rule.id) < this.regexRules.length ? 0.5 : 0 },
      color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(`第 ${this.regexRuleNumber(rule.id)} 条，${rule.name || '正则规则'}${rule.enabled ? '' : '，已停用'}，` +
      '点按编辑，长按出菜单，长按前方把手拖动调整顺序，左滑停用或删除')
    .opacity(ListDissolve.opacity(this.isRegexRuleDissolving(rule)))
    .scale(ListDissolve.scale(this.isRegexRuleDissolving(rule)))
    .blur(ListDissolve.blur(this.isRegexRuleDissolving(rule)))
    .hitTestBehavior(this.isRegexRuleDissolving(rule) ? HitTestMode.None : HitTestMode.Default)
    .id(this.regexRuleElementId(`${rule.id}`))
    .onClick(() => {
      for (let i = 0; i < this.regexRules.length; i++) {
        if (this.regexRules[i].id === rule.id) {
          this.openRegexRuleEditor(i, this.regexRules[i]);
          return;
        }
      }
    })
  }

  isNameStyleMode(): boolean {
    return this.nameStyleBook !== '';
  }

  /** 改某个人的样式、又开着“跟随人名样式”时，编辑页只留开关和预览。 */
  nameStyleEditable(): boolean {
    return !(this.isNameStyleMode() && this.nameStyleRoleId !== '' && this.nameStyleFollow);
  }

  nameStyleTitle(): string {
    return this.nameStyleRoleId ? `${this.nameStyleRoleName}的人名样式` : '人名样式';
  }

  /**
   * 人名样式和正则规则用同一个编辑页：规则从本书人物档案里取（没设过用默认样式），隐藏名称、匹配方式、正则、
   * 段首缩进和“命中里显示其他规则”，顶上换成“按人物 / 统一颜色”（某个人则是“跟随人名样式”）。保存写回人物档案。
   */
  openNameStyleEditor(): void {
    this.nameStyleOpened = true;
    let cast: MimoBookCast;
    try {
      cast = MimoStore.cast(this.nameStyleBook);
    } catch (error) {
      console.warn('读取本书人物失败:', error);
      router.back();
      return;
    }
    const characters = ReaderNameStyle.characters(cast);
    const colors = ReaderNameStyle.colors(cast);
    let rule = ReaderNameStyle.sharedRule(cast, this.readerFontSize);
    this.nameStyleColorMode = ReaderNameStyle.colorMode(cast);
    this.nameStyleFollow = false;
    let names: string[] = characters.slice(0, 4).map((role: MimoRole): string => role.name);
    if (this.nameStyleRoleId) {
      const index = characters.findIndex((role: MimoRole): boolean => role.id === this.nameStyleRoleId);
      if (index < 0) {
        router.back();
        return;
      }
      const role = characters[index];
      this.nameStyleRoleName = role.name;
      const own = ReaderNameStyle.ownRule(role);
      this.nameStyleFollow = !own;
      if (own) {
        rule = own;
      } else if (this.nameStyleColorMode === ReaderNameStyle.MODE_ROLE && colors[index] >= 0) {
        // 从人名样式起步时，颜色先取这个人现在的颜色，改起来是在它的基础上改。
        const pair = ReaderNamePatterns.PALETTE[colors[index]];
        rule.customTextColor = pair[0];
        rule.customTextColorDark = pair[1];
        rule.customHighlightColor = pair[0];
        rule.customHighlightColorDark = pair[1];
        rule.customBubbleColor = pair[0];
        rule.customBubbleColorDark = pair[1];
      }
      names = [role.name].concat(role.aliases || []);
    }
    rule.pattern = ReaderNamePatterns.pattern(names);
    rule.matcher = '';
    this.nameStylePreviewNames = names.filter((name: string): boolean =>
      (name || '').trim().length >= ReaderNamePatterns.MIN_NAME_LENGTH);
    this.openRegexRuleEditor(NAME_STYLE_RULE_INDEX, rule);
    this.nameStyleSnapshotExtra = `${this.nameStyleColorMode}|${this.nameStyleFollow}`;
  }

  nameStyleChanged(): boolean {
    return this.encodeRegexRules([this.editingRegexRule]) !== this.editingRegexRuleSnapshot ||
      `${this.nameStyleColorMode}|${this.nameStyleFollow}` !== this.nameStyleSnapshotExtra;
  }

  saveNameStyle(): void {
    try {
      const cast = MimoStore.cast(this.nameStyleBook);
      const rule = ReaderRegexFontCodec.cloneRule(this.editingRegexRule);
      rule.id = 'name_style';
      rule.name = '人名';
      rule.pattern = '';
      rule.matcher = '';
      if (this.nameStyleRoleId) {
        const role = cast.roles.find((item: MimoRole): boolean => item.id === this.nameStyleRoleId);
        if (role) role.nameRule = this.nameStyleFollow ? '' : ReaderNameStyle.encodeOne(rule);
      } else {
        cast.nameRule = ReaderNameStyle.encodeOne(rule);
        cast.nameColorMode = this.nameStyleColorMode;
      }
      MimoStore.saveCast(this.nameStyleBook, cast);
    } catch (error) {
      console.warn('保存人名样式失败:', error);
      HdsFeedback.showToast('保存人名样式失败');
    }
    this.closeRegexRuleEditor();
  }

  /** 人名样式编辑页顶上：全书是“按人物 / 统一颜色”，某个人是“跟随人名样式”开关。 */
  @Builder
  nameStyleHeader() {
    if (this.nameStyleRoleId) {
      Row({ space: AppSpacing.MD }) {
        Column({ space: 2 }) {
          Text('跟随人名样式')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
          Text(`关掉后单独设置，只影响“${this.nameStylePreviewNames.join('、') || this.nameStyleRoleName}”`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        AdaptiveSwitch({
          isOn: this.nameStyleFollow,
          accessibilityLabel: '跟随人名样式',
          onChange: (isOn: boolean) => {
            this.nameStyleFollow = isOn;
            this.bumpRegexHighlightRefresh();
          }
        })
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
    } else {
      Column({ space: AppSpacing.SM }) {
        Text('颜色')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
        SettingSegment({
          labels: ['按人物', '统一颜色'],
          selected: this.nameStyleColorMode === ReaderNameStyle.MODE_ONE ? 1 : 0,
          inset: false,
          onSelect: (selected: number) => {
            this.nameStyleColorMode = selected === 1 ? ReaderNameStyle.MODE_ONE : ReaderNameStyle.MODE_ROLE;
          }
        })
        Text(this.nameStyleColorMode === ReaderNameStyle.MODE_ONE ? '所有人名都用下面“自定义”里设的颜色。' :
          '各人用自己的颜色（在本书人物页点色点更换），下面“自定义”里的颜色不用；“跟随主题”“无强调”时不按人分色。')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  regexRuleEditorCover() {
    PageScaffold({ title: this.isNameStyleMode() ? this.nameStyleTitle() :
      (this.isEditingNewRegexRule() ? '新建规则' : '编辑规则'),
      onBack: () => this.leaveRegexRuleEditor(),
      actions: () => {
        this.regexRuleEditorActions()
      },
      content: () => {
        this.regexRuleEditorContent(this.regexHighlightRefreshKey)
      } })
  }

  @Builder
  regexRuleEditorActions() {
    ImmersiveHeaderAction({
      label: '保存',
      tint: ThemeRuntime.buttonColor(this.appDarkMode),
      onTap: () => this.saveRegexRuleEditor()
    })
      .margin({ right: AppSpacing.XL })
  }

  /** 规则编辑里的开关行：cross/fix/short 是智能对话的三项，nest 是“命中里显示其他规则”。值直接读编辑中的规则。 */
  @Builder
  regexDialogueSwitch(kind: string) {
    Row({ space: AppSpacing.MD }) {
      Column({ space: 2 }) {
        Text(this.regexSwitchTitle(kind))
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Text(this.regexSwitchDescription(kind))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      AdaptiveSwitch({
        isOn: this.regexSwitchValue(kind),
        accessibilityLabel: this.regexSwitchTitle(kind),
        onChange: (isOn: boolean) => {
          this.updateRegexRule(EDITING_REGEX_RULE_INDEX, (target: ReaderRegexFontRule) => {
            if (kind === 'cross') target.dialogueCrossParagraph = isOn;
            else if (kind === 'fix') target.dialogueFixQuotes = isOn;
            else if (kind === 'short') target.dialogueSkipShort = isOn;
            else target.nestOthers = isOn;
          });
        }
      })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
    .alignItems(VerticalAlign.Center)
  }

  regexSwitchTitle(kind: string): string {
    if (kind === 'cross') return '跨段对话';
    if (kind === 'fix') return '纠正写反的引号';
    if (kind === 'short') return '短引号不算对话';
    return ReaderRegexFontCodec.isDialogue(this.editingRegexRule) ? '对话里显示其他规则' : '命中里显示其他规则';
  }

  regexSwitchDescription(kind: string): string {
    if (kind === 'cross') return '段末没收引号、下一段又以引号开头时，接着算对话';
    if (kind === 'fix') return '如“你好“、”快走！”这类写反方向的引号';
    if (kind === 'short') return '引号里字少又没有句末标点时按普通文字显示，如招式名、称号；偶尔会漏掉很短的对话';
    return '人名等规则落在这里也上色，只换文字颜色和粗细，字号与气泡不变';
  }

  /** 规则列表里智能对话的副标题：开着的几项。 */
  dialogueRuleSummary(rule: ReaderRegexFontRule): string {
    const parts: string[] = ['智能对话'];
    if (rule.dialogueCrossParagraph) parts.push('跨段');
    if (rule.dialogueFixQuotes) parts.push('纠正引号');
    if (rule.dialogueSkipShort) parts.push('短引号不算');
    if (rule.nestOthers) parts.push('显示其他规则');
    return parts.join(' · ');
  }

  regexSwitchValue(kind: string): boolean {
    const rule = this.editingRegexRule;
    if (kind === 'cross') return rule.dialogueCrossParagraph;
    if (kind === 'fix') return rule.dialogueFixQuotes;
    if (kind === 'short') return rule.dialogueSkipShort;
    return rule.nestOthers;
  }

  @Builder
  regexRuleEditorContent(refreshKey: number) {
    Column() {
      Column({ space: AppSpacing.MD }) {
        if (this.isNameStyleMode()) {
          this.nameStyleHeader()
        }
        if (!this.isNameStyleMode()) {
        TextInput({ text: this.editingRegexRule.name, placeholder: '规则名称' })
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(ThemeRuntime.mediumRadius())
          .onEditChange((isEditing: boolean) => {
            this.setRegexInputEditing(this.editingRegexRule.id, 'name', isEditing);
          })
          .onChange((value: string) => {
            if (!this.isRegexInputEditing(this.editingRegexRule.id, 'name')) {
              return;
            }
            this.updateRegexRule(EDITING_REGEX_RULE_INDEX, (target: ReaderRegexFontRule) => {
              target.name = value;
            });
          })

        Column({ space: AppSpacing.SM }) {
          Text('匹配方式')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .width('100%')
          SettingSegment({
            labels: ['智能对话', '正则表达式'],
            selected: ReaderRegexFontCodec.isDialogue(this.editingRegexRule) ? 0 : 1,
            inset: false,
            onSelect: (selected: number) => {
              this.updateRegexRule(EDITING_REGEX_RULE_INDEX, (target: ReaderRegexFontRule) => {
                if (selected === 0) {
                  if (ReaderRegexFontCodec.isDialogue(target)) return;
                  target.matcher = ReaderRegexRuleHits.DIALOGUE;
                  // 正则框留给切回时用：没填的填上兜底正则，旧版本应用读到也能大致上色。
                  if (!target.pattern.trim()) target.pattern = ReaderDialogueMatcher.FALLBACK_PATTERN;
                  target.nestOthers = true;
                } else {
                  target.matcher = '';
                }
              });
            }
          })
        }
        .width('100%')

        if (ReaderRegexFontCodec.isDialogue(this.editingRegexRule)) {
          Column() {
            this.regexDialogueSwitch('cross')
            this.regexDialogueSwitch('fix')
            this.regexDialogueSwitch('short')
          }
          .width('100%')
        } else {
          TextInput({ text: this.editingRegexRule.pattern, placeholder: '正则表达式' })
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .placeholderColor(this.subTextColor())
            .backgroundColor(this.inputColor())
            .borderRadius(ThemeRuntime.mediumRadius())
            .onEditChange((isEditing: boolean) => {
              this.setRegexInputEditing(this.editingRegexRule.id, 'pattern', isEditing);
            })
            .onChange((value: string) => {
              if (!this.isRegexInputEditing(this.editingRegexRule.id, 'pattern')) {
                return;
              }
              this.updateRegexRule(EDITING_REGEX_RULE_INDEX, (target: ReaderRegexFontRule) => {
                target.pattern = value;
              });
            })
        }
        }

        if (this.nameStyleEditable()) {
        Column({ space: AppSpacing.SM }) {
          Text('作用范围')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .width('100%')
          SettingSegment({
            labels: ReaderRegexScope.LABELS,
            selected: ReaderRegexScope.index(this.editingRegexRule.scope),
            inset: false,
            onSelect: (selected: number) => {
              this.updateRegexRule(EDITING_REGEX_RULE_INDEX, (target: ReaderRegexFontRule) => {
                target.scope = ReaderRegexScope.IDS[selected];
              });
            }
          })
          if (this.regexRuleHiddenInTitle(this.editingRegexRule)) {
            Text('标题强调开着时，标题按标题强调显示，这条规则在标题里不显示。')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .width('100%')
          }
        }
        .width('100%')

        if (!this.isNameStyleMode() && ReaderRegexScope.includesBody(this.editingRegexRule.scope)) {
          Column({ space: AppSpacing.SM }) {
            Text('段首缩进（字符）')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .width('100%')
            SettingSegment({
              labels: ['跟随全局', '0', '1', '2', '3', '4'],
              selected: this.editingRegexRule.paragraphIndent + 1,
              inset: false,
              onSelect: (selected: number) => {
                this.updateRegexRule(EDITING_REGEX_RULE_INDEX, (target: ReaderRegexFontRule) => {
                  target.paragraphIndent = selected - 1;
                });
              }
            })
            Text('以命中文字开头的段落按这里的字符数缩进，其余段落不变。')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .width('100%')
          }
          .width('100%')
        }

        if (!this.isNameStyleMode()) {
          this.regexDialogueSwitch('nest')
        }

        this.compactFontModeItem('字体类型', this.editingRegexRule.fontMode, this.editingRegexRule.fontFamily,
          (mode: string, family: string) => {
            this.updateRegexRule(EDITING_REGEX_RULE_INDEX, (target: ReaderRegexFontRule) => {
              target.fontMode = mode;
              target.fontFamily = family;
            });
          })
        this.regexFontSizeStepper(EDITING_REGEX_RULE_INDEX)
        ReaderFontWeightStepper({ value: this.editingRegexRule.fontWeight, scope: '规则', nested: true,
          textColor: this.primaryTextColor(), disabledColor: this.subTextColor(), dividerColor: this.settingsDividerColor(),
          onChange: (value: number) => {
            this.updateRegexRule(EDITING_REGEX_RULE_INDEX, (target: ReaderRegexFontRule) => { target.fontWeight = value; });
          } })

        this.regexEmphasisSettings(EDITING_REGEX_RULE_INDEX, refreshKey)
        }

        // 编辑页盖住了设置页顶部的实时预览，嵌入时也显示规则预览。
        this.regexRulePreviewItem(EDITING_REGEX_RULE_INDEX, refreshKey)
      }
      .width('calc(100% - 32vp)')
      .padding({ left: 0, right: 0, top: AppSpacing.LG, bottom: AppSpacing.LG })
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    if (!this.isEditingNewRegexRule() && !this.isNameStyleMode()) {
      Button('删除规则')
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .backgroundColor(this.cardColor())
        .width('calc(100% - 24vp)')
        .height(44)
        .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XXL })
        .onClick(() => {
          this.deleteEditingRegexRule();
        })
    }
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
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .id(`reader_title_${kind}_indicator`)
        .width(`${100 / this.titleSegmentOptions(kind).length}%`)
        .height(32)
        .borderRadius(16)
        .backgroundColor(this.cardColor())
        .shadow({ radius: 4, color: '#1A000000', offsetX: 0, offsetY: 1 })
        .translate({ x: `${this.titleSegmentSelected(kind) * 100}%` })
        .animation({ duration: 180, curve: Curve.EaseOut })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
      Row() {
        ForEach(this.titleSegmentOptions(kind), (option: string, index: number) => {
          Button(option, { type: ButtonType.Capsule, stateEffect: true })
            .id(`reader_title_${kind}_${index}`)
            .layoutWeight(1)
            .height(32)
            .padding({ left: 4, right: 4 })
            .fontSize(AppFontSize.BODY)
            .fontWeight(index === this.titleSegmentSelected(kind) ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(index === this.titleSegmentSelected(kind) ? this.primaryTextColor() : this.subTextColor())
            .backgroundColor(Color.Transparent)
            .accessibilitySelected(index === this.titleSegmentSelected(kind))
            .accessibilityText(`${label}：${option}${index === this.titleSegmentSelected(kind) ? '，已选中' : ''}`)
            .onClick(() => this.selectTitleSegment(kind, index))
        }, (option: string) => `${kind}_${option}`)
      }.width('100%')
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
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.XS }) {
          Text('标题装饰').fontSize(AppFontSize.BODY_LARGE).fontColor(this.primaryTextColor())
          Text(`显示主题给标题配的饰图和序号行颜色。${
            ReaderChapterHead.describeTitle(ThemeRuntime.chapterHeadTokens(this.appDarkMode))}`)
            .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        AdaptiveSwitch({ isOn: this.titleStyle.decoration !== ReaderChapterDecoration.OFF,
          onChange: (checked: boolean) => this.updateTitleSplit('decoration',
            checked ? ReaderChapterDecoration.THEME : ReaderChapterDecoration.OFF) })
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
          () => (top ? this.titleStyle.marginTop : this.titleStyle.marginBottom) > 0,
          () => this.adjustTitleMargin(top, -1))
        Slider({ value: top ? this.titleStyle.marginTop : this.titleStyle.marginBottom, min: 0,
          max: ReaderTitleSplit.MAX_MARGIN, step: 1 })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
          .layoutWeight(1)
          .selectedColor(this.accentColor())
          .blockColor(this.accentColor())
          .trackColor(this.inputColor())
          // 只能拖动滑块调整，点到条上不跳值，防止滑动面板时误触。
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
          .onChange((current: number) => this.updateTitleSplit(top ? 'marginTop' : 'marginBottom', `${current}`))
          .accessibilityText(`标题${label}`)
        this.fontSizeStepButton($r('sys.symbol.plus'), `增大标题${label}`,
          () => (top ? this.titleStyle.marginTop : this.titleStyle.marginBottom) < ReaderTitleSplit.MAX_MARGIN,
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
        // 阅读页里的字体面板不显示顶部标题预览，分段结果旁边也能看到并更换示例。
        Row({ space: AppSpacing.XS }) {
          Text(`示例：${this.titlePreviewText}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          this.titlePreviewEditButton('split')
        }.width('100%')
        if (this.titlePreviewEditingAt === 'split') {
          this.titlePreviewEditor()
        }
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
          () => secondary ? this.titleStyle.secondaryScale > 0.5 : this.titleStyle.lineGap > 0,
          () => this.adjustTitleSplit(secondary, -1))
        Slider({ value: secondary ? this.titleStyle.secondaryScale : this.titleStyle.lineGap,
          min: secondary ? 0.5 : 0, max: secondary ? 3 : 40, step: secondary ? 0.1 : 1 })
          .layoutWeight(1)
          .selectedColor(this.accentColor())
          .blockColor(this.accentColor())
          .trackColor(this.inputColor())
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
          .onChange((current: number) => {
            this.updateTitleSplit(secondary ? 'secondaryScale' : 'lineGap', `${current}`);
          })
          .accessibilityText(label)
        this.fontSizeStepButton($r('sys.symbol.plus'), `增大${label}`,
          () => secondary ? this.titleStyle.secondaryScale < 3 : this.titleStyle.lineGap < 40,
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
    else if (field === 'decoration') next.decoration = ReaderChapterDecoration.normalize(content);
    else if (field === 'dropCap') next.dropCap = ReaderDropCapMode.normalize(content);
    else if (field === 'dropCapLines') next.dropCapLines = ReaderDropCapMode.normalizeLines(Number(content));
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
      this.titleGroupTitle('标题强调', this.titleEmphasisHint())
      this.regexEmphasisSettings(-1, this.regexHighlightRefreshKey)
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .padding({ top: AppSpacing.XL, bottom: AppSpacing.LG })
  }

  /** 跟随主题时写出当前主题给标题设了什么。 */
  titleEmphasisHint(): string {
    const base = '不受“正则字体”开关影响。“跟随主题”用主题设的标题强调，“同正文强调”和对话用同一套；主题没设或选“无强调”时标题沿用正则规则的效果';
    if (this.titleStyle.emphasis.emphasisMode !== ReaderTitleEmphasis.THEME) return base;
    return `${base}。${ReaderTitleEmphasis.describe(ThemeRuntime.titleEmphasisTokens(this.appDarkMode))}`;
  }

  /** 标题强调的规则与上下文（跟随主题时换成主题的标题强调）；不画时返回 null。 */
  titleEmphasisPlan(context: ReaderRegexEmphasisContext): ReaderTitleEmphasisPlan | null {
    return ReaderTitleEmphasis.plan(this.titleStyle.emphasis, ThemeRuntime.titleEmphasisTokens(this.appDarkMode), context);
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
    input.chapterHead = ReaderChapterHead.style(ThemeRuntime.chapterHeadTokens(this.appDarkMode), this.titleStyle.decoration,
      this.titleStyle.dropCap, this.titleStyle.dropCapLines);
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
    const body = withBody ? '\n' + this.previewIndentedBody(
      '清晨的风穿过长街，带来一阵粽叶的清香。街角的小摊刚刚支起，竹篮里整整齐齐地码着新煮好的粽子。\n' +
      '“卖鸭蛋，卖粽子喽——”一声吆喝，把沉睡的小城轻轻唤醒。',
      this.readerRegexFontEnabled ? ReaderRegexFontCodec.activeRules(this.regexRules) : []) : '';
    config.document = ReaderV2DocumentParser.parse(this.titlePreviewText + body, 0, this.titlePreviewText, [], this.titleStyle);
    const titlePlan = this.titleEmphasisPlan(this.typographyPreviewContext());
    if (titlePlan) {
      for (const block of config.document.blocks) {
        if (!block.title) continue;
        const size = this.readerTitleFontSize * (block.titleSegment > 0 ? this.titleStyle.secondaryScale : 1);
        const style = this.typographyPreviewEmphasis(titlePlan.rule, size,
          input.titleFontFamily, this.readerTitleFontWeight, titlePlan.context);
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
    const titleStyles = config.styles.slice();
    const content = config.document.displayText;
    const titleRanges = this.previewTitleRanges(config);
    const rules = ReaderRegexFontCodec.activeRules(this.regexRules);
    for (const hit of ReaderRegexRuleHits.collect(ReaderRegexFontCodec.matchSpecs(rules), content, titleRanges)) {
      const rule = rules[hit.ruleIndex];
      // Explicit title emphasis takes precedence; regex fonts still apply outside its ranges.
      let ranges: number[][] = [[hit.start, hit.end]];
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
        if (hit.overlay) {
          config.styles.push(ReaderV2SpanStyleRange.overlayOf(style, rule.fontWeight, range[0], range[1]));
          continue;
        }
        style.start = range[0];
        style.end = range[1];
        config.styles.push(style);
      }
    }
  }

  typographyPreviewContext(): ReaderRegexEmphasisContext {
    const context = this.regexEmphasisContext();
    context.surfaceColor = ThemeRuntime.readerBackgroundColor(this.appDarkMode);
    context.normalTextColor = ThemeRuntime.readerTextColor(this.appDarkMode);
    return context;
  }

  typographyPreviewEmphasis(rule: ReaderRegexFontRule, size: number, family: string,
    weight: number, planned: ReaderRegexEmphasisContext | null = null): ReaderV2SpanStyleRange {
    const context = planned || this.typographyPreviewContext();
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
    ReaderV2BubbleFrame.decorate(style, resolved.bubbleDecorationEnabled, resolved.bubbleStyleId,
      ThemeAssetRegistry.hasRegexBubbleCap(resolved.bubbleStyleId, this.appDarkMode),
      uiContext.vp2px(Math.max(15, Math.min(22, size * 0.72))),
      ThemePackRegistry.bubbleFrame(resolved.bubbleStyleId, this.appDarkMode), this.appDarkMode);
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
        .scrollBar(BarState.Off)
        .onAreaChange((_oldArea: Area, area: Area) => {
          const height = Number(area.height);
          if (height > 0 && Math.abs(height - this.titleReadingPreviewHeight) > 0.5) this.titleReadingPreviewHeight = height;
        })
    }.width('100%').height('100%')
  }

  @Builder
  titlePreviewEditButton(at: string) {
    Button(this.titlePreviewEditingAt === at ? '完成' : '换示例')
      .fontSize(AppFontSize.CAPTION).fontColor(this.accentColor()).backgroundColor(Color.Transparent)
      .height(32).padding({ left: 8, right: 8 })
      .onClick(() => { this.titlePreviewEditingAt = this.titlePreviewEditingAt === at ? '' : at; })
  }

  @Builder
  titlePreviewEditor() {
    TextInput({ text: this.titlePreviewText, placeholder: '输入示例标题' })
      .fontColor(this.primaryTextColor()).fontSize(AppFontSize.BODY)
      .backgroundColor(this.inputColor()).maxLength(160)
      .onChange((content: string) => { this.setTitlePreviewText(content); })
    Row({ space: AppSpacing.SM }) {
      Button('短标题')
        .fontSize(AppFontSize.CAPTION).fontColor(this.primaryTextColor()).backgroundColor(this.inputColor())
        .height(30).padding({ left: 12, right: 12 })
        .onClick(() => { this.setTitlePreviewText(ReaderTitlePreviewStore.DEFAULT_TEXT); })
      Button('长标题')
        .fontSize(AppFontSize.CAPTION).fontColor(this.primaryTextColor()).backgroundColor(this.inputColor())
        .height(30).padding({ left: 12, right: 12 })
        .onClick(() => { this.setTitlePreviewText('第494章：天下承平，一世长安，人间烟火寻常巷陌'); })
    }.width('100%')
  }

  /** 预览放在标题设置的最前面，调整下面任一项都能直接看到效果。 */
  @Builder
  titlePreviewItem() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.XS }) {
        Text('标题预览').fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).layoutWeight(1)
        this.titlePreviewEditButton('preview')
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
        .id(TITLE_PREVIEW_BOX_ID)
        // 边距、第二段字号、行距等一改预览就变高变矮，会把下面的设置项顶上顶下。
        // 预览整个滚出屏幕时冻结高度，拖下面的滑动条页面纹丝不动；滚回来再按真实高度补滚动。
        .height(this.titlePreviewFrozenHeight > 0 ? this.titlePreviewFrozenHeight : 'auto')
        .clip(true)
        .onVisibleAreaChange([0.0], (isExpanding: boolean, ratio: number) => {
          if (isExpanding) {
            this.titlePreviewFrozenHeight = 0;
          } else if (ratio <= 0 && this.titlePreviewHeight > 0) {
            this.titlePreviewFrozenHeight = this.titlePreviewHeight;
          }
        })
        .onDisAppear(() => { this.titlePreviewFrozenHeight = 0; })
        .onSizeChange((previous: SizeOptions, current: SizeOptions) => {
          this.keepContentBelowPreview(previous, current);
        })
      if (this.titlePreviewEditingAt === 'preview') {
        this.titlePreviewEditor()
      }
    }
    .width('calc(100% - 32vp)')
    .padding({ left: 0, right: 0, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
  }

  /** 预览上沿已在顶栏后面时，预览变高多少页面就往下滚多少，看着的设置项留在原处。 */
  keepContentBelowPreview(previous: SizeOptions, current: SizeOptions): void {
    if (this.embedded) return;
    const oldHeight = Number(previous.height ?? 0);
    const newHeight = Number(current.height ?? 0);
    if (this.titlePreviewFrozenHeight <= 0 && newHeight > 0) this.titlePreviewHeight = newHeight;
    // 刚出现或换了宽度（旋转、分屏）时不算“内容变高”，不补滚动。
    if (oldHeight <= 0 || newHeight <= 0 || Math.abs(Number(previous.width ?? 0) - Number(current.width ?? 0)) >= 1) return;
    const delta = newHeight - oldHeight;
    if (Math.abs(delta) < 0.5 || this.pageScroller.currentOffset().yOffset <= 0) return;
    const uiContext = this.getUIContext();
    const box = uiContext.getComponentUtils().getRectangleById(TITLE_PREVIEW_BOX_ID);
    const headerBottom = uiContext.vp2px((AppStorage.get<number>('statusBarHeight') ?? 0) + PageScaffold.BAR_HEIGHT);
    if (box.windowOffset.y >= headerBottom) return;
    // 滑动条拖动时的改动带着系统隐式动画，不包一层 0 时长动画的话滚动会被放慢成“先跳再滑回”。
    uiContext.animateTo({ duration: 0 }, () => { this.pageScroller.scrollBy(0, delta); });
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
    if (index === EDITING_REGEX_RULE_INDEX) return this.editingRegexRule;
    if (index >= 0 && index < this.regexRules.length) {
      return this.regexRules[index];
    }
    return new ReaderRegexFontRule();
  }

  /**
   * 规则预览的候选正文，按顺序试，取第一个真被规则命中的：内置“对话”“关键字匹配”先用写好的样例，
   * 再用按正则拼出的样例（ReaderRegexSample）的几种放法。
   */
  regexPreviewBodies(rule: ReaderRegexFontRule): string[] {
    const bodies: string[] = [];
    if (this.isNameStyleMode()) {
      const first = this.nameStylePreviewNames.length > 0 ? this.nameStylePreviewNames[0] : '林舟';
      const second = this.nameStylePreviewNames.length > 1 ? this.nameStylePreviewNames[1] : first;
      bodies.push(`${first}站在门边，看着檐下的雨。\n“${second}，进来吧。”${first}笑了笑。`);
      return bodies;
    }
    if (ReaderRegexFontCodec.isDialogue(rule)) {
      // 依次露出跨段对话、写反的引号；开了“短引号不算对话”再加一句招式名。
      bodies.push('他说：“你好。”她点头说：「走吧。」\n“那年冬天特别冷，河面冻得能跑马。\n“开春冰就化了。”\n' +
        '“你别过来“他喊道，“我数到三。”\n”快走！”她拉起他就跑。' + (rule.dialogueSkipShort ? '\n他一招“回风拂柳”使出，剑尖停在半空。' : ''));
      return bodies;
    }
    if (rule.name === '对话') {
      bodies.push('他说：“你好。”她点头说：「走吧。」\n“这就来。”她应了一声。');
    } else if (rule.name === '关键字匹配') {
      bodies.push(`这里包含${this.regexPreviewKeyword(rule.pattern)}，命中后会使用当前正则字体。`);
    }
    const sample = ReaderRegexSample.generate(rule.pattern);
    if (sample) {
      for (const body of ReaderRegexSample.placements(sample)) bodies.push(body);
    }
    return bodies;
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

  /** 规则预览里的标题样例，让“仅标题/仅正文”看得出差别。 */
  regexPreviewTitle(rule: ReaderRegexFontRule): string {
    if (rule.name === '对话' || ReaderRegexFontCodec.isDialogue(rule)) {
      return '第三章 “重逢”';
    }
    if (rule.name === '关键字匹配') {
      return `第三章 ${this.regexPreviewKeyword(rule.pattern)}`;
    }
    return '第三章 重逢';
  }

  /** 预览正文按阅读页的办法加段首缩进：全局字符数，规则另设了缩进的段落用规则的。 */
  previewIndentedBody(text: string, rules: ReaderRegexFontRule[]): string {
    const matcher = new ReaderParagraphIndentMatcher(ReaderRegexFontCodec.indentOverrides(rules));
    return text.split('\n').map((line: string): string => ReaderTextNormalizer.indentLine(line,
      this.previewLayoutSettings.paragraphIndent, matcher.isEmpty() ? null : matcher)).join('\n');
  }

  previewTitleRanges(config: ReaderTypographyPreviewConfig): number[][] {
    const ranges: number[][] = [];
    for (const block of config.document.blocks) {
      if (block.title) ranges.push([block.displayStart, block.displayEnd]);
    }
    return ranges;
  }

  /** 规则管到标题、但标题强调画出来时，标题归标题强调，规则在标题里看不到。 */
  regexRuleHiddenInTitle(rule: ReaderRegexFontRule): boolean {
    return ReaderRegexScope.includesTitle(rule.scope) && this.titleEmphasisPlan(this.regexEmphasisContext()) !== null;
  }

  regexPreviewDimStyle(start: number, end: number, fontSizePx: number, family: string, weight: number,
    color: number): ReaderV2SpanStyleRange {
    const style = new ReaderV2SpanStyleRange(start, end);
    style.fontSizePx = fontSizePx;
    style.fontFamily = family;
    style.fontWeight = weight;
    style.colorEnabled = true;
    style.color = color;
    return style;
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
    if (index === -1) {
      // 标题强调：跟随主题时按主题的标题强调；不画时返回“无”的结果。
      const plan = this.titleEmphasisPlan(this.regexEmphasisContext());
      if (!plan) return new ReaderResolvedRegexEmphasis();
      return ReaderRegexBubbleStyleResolver.resolve(plan.rule, plan.context);
    }
    return ReaderRegexBubbleStyleResolver.resolve(this.regexRuleAt(index), this.regexEmphasisContext());
  }

  @Builder
  regexRulePreviewItem(index: number, refreshKey: number) {
    Column({ space: AppSpacing.SM }) {
      Text('规则预览')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .width('100%')
      ReaderTypographyPreview({ config: this.regexRulePreviewConfig(index, refreshKey) })
        .width('100%')
    }
    .width('100%')
    .padding({ top: AppSpacing.XS, bottom: AppSpacing.XXS })
  }

  /**
   * 规则预览走阅读页同一套排版与绘制（ReaderTypographyPreview），主题包的边框、端饰和正文里一致；
   * 只是颜色按设置卡片取，和卡片底色相配。正文取 regexPreviewBodies 里第一个被命中的；都没命中
   * （或正则没填、写错）时末尾加一行说明，把“强调文字”直接画成这条规则的强调效果，气泡和颜色照样看得到。
   */
  regexRulePreviewConfig(index: number, refreshKey: number): ReaderTypographyPreviewConfig {
    const rule = this.regexRuleAt(index);
    const dialogue = ReaderRegexFontCodec.isDialogue(rule);
    const pattern = rule.pattern.trim();
    let valid = dialogue;
    if (!dialogue && pattern) {
      try {
        valid = new RegExp(rule.pattern, 'g') !== null;
      } catch (_) {
        valid = false;
      }
    }
    if (valid && refreshKey >= -1) {
      const spec = ReaderRegexFontCodec.matchSpecs([rule])[0];
      for (const body of this.regexPreviewBodies(rule)) {
        const preview = this.regexRulePreviewBase(rule, body, false);
        if (this.applyRegexPreviewMatches(preview, rule, spec) > 0) return preview.config;
      }
    }
    const note = !dialogue && !pattern ? '还没填正则，强调效果：' :
      (valid ? '示例正文没有命中这条规则，强调效果：' : '正则写法有误，强调效果：');
    const preview = this.regexRulePreviewBase(rule,
      `${ReaderRegexSample.LEAD_LINE}\n${ReaderRegexSample.TAIL_LINE}\n${note}${REGEX_PREVIEW_FALLBACK_SAMPLE}`, true);
    const config = preview.config;
    const content = config.document.displayText;
    const sampleStart = content.lastIndexOf(REGEX_PREVIEW_FALLBACK_SAMPLE);
    if (sampleStart < 0) return config;
    const noteStart = content.lastIndexOf(note, sampleStart);
    const input = config.input;
    if (noteStart >= 0) {
      const dimColor = ((input.textColor & 0x00FFFFFF) | 0x80000000) >>> 0;
      config.styles.push(this.regexPreviewDimStyle(noteStart, sampleStart, input.fontSizePx * 0.85,
        input.bodyFontFamily, this.readerFontWeight, dimColor));
    }
    const style = this.typographyPreviewEmphasis(rule, rule.fontSize,
      this.previewFontFamily(rule.fontMode, rule.fontFamily), rule.fontWeight, this.regexEmphasisContext());
    style.start = sampleStart;
    style.end = sampleStart + REGEX_PREVIEW_FALLBACK_SAMPLE.length;
    config.styles.push(style);
    return config;
  }

  /** 规则在预览正文里的命中逐个画上强调，返回画了几处；范围外、和标题强调重叠的不算。 */
  applyRegexPreviewMatches(preview: RegexRulePreview, rule: ReaderRegexFontRule, spec: ReaderRuleMatchSpec): number {
    const config = preview.config;
    const emphasisContext = this.regexEmphasisContext();
    const content = config.document.displayText;
    const titleRanges = this.previewTitleRanges(config);
    let count = 0;
    for (const range of ReaderRegexRuleHits.ranges(spec, content)) {
      const start = range[0];
      const end = range[1];
      if (ReaderRegexScope.accepts(rule.scope, start, end, titleRanges) &&
        !preview.titleStyles.some((item: ReaderV2SpanStyleRange): boolean => start < item.end && end > item.start)) {
        const style = this.typographyPreviewEmphasis(rule, rule.fontSize,
          this.previewFontFamily(rule.fontMode, rule.fontFamily), rule.fontWeight, emphasisContext);
        style.start = start;
        style.end = end;
        config.styles.push(style);
        count++;
      }
    }
    return count;
  }

  /** 预览的排版与标题部分：标题强调、范围没管到的行调淡。keepLastLine 时最后一行正文不调淡（兜底样本行）。 */
  regexRulePreviewBase(rule: ReaderRegexFontRule, body: string, keepLastLine: boolean): RegexRulePreview {
    const config = new ReaderTypographyPreviewConfig();
    const layout = this.previewLayoutSettings;
    const uiContext = this.getUIContext();
    const input = config.input;
    input.fontSizePx = uiContext.fp2px(this.readerFontSize);
    input.fontWeight = this.readerFontWeight;
    input.lineSpacingPx = uiContext.vp2px(layout.lineHeight);
    input.letterSpacingPx = uiContext.fp2px(layout.letterSpacing);
    input.textAlign = 'left';
    input.bodyFontFamily = this.bodyPreviewFontFamily();
    input.titleFontFamily = this.titlePreviewFontFamily();
    input.textColor = ReaderV2Color.parse(this.primaryTextColor(), 0xFF202124);
    input.commentsEnabled = false;
    config.fontSizeVp = this.readerFontSize;
    const title = this.regexPreviewTitle(rule);
    config.document = ReaderV2DocumentParser.parse(
      `${title}\n${this.previewIndentedBody(body, [rule])}`, 0, title, [], this.titleStyle);
    const emphasisContext = this.regexEmphasisContext();
    const titlePlan = this.titleEmphasisPlan(emphasisContext);
    const titleInScope = ReaderRegexScope.includesTitle(rule.scope);
    const bodyInScope = ReaderRegexScope.includesBody(rule.scope);
    const dimColor = ((input.textColor & 0x00FFFFFF) | 0x60000000) >>> 0;
    let lastBodyBlock = -1;
    for (let blockIndex = 0; keepLastLine && blockIndex < config.document.blocks.length; blockIndex++) {
      const block = config.document.blocks[blockIndex];
      if (!block.title && block.displayEnd > block.displayStart) lastBodyBlock = blockIndex;
    }
    // 和阅读页一致：标题强调画出来时标题归它；范围没管到的那一行调淡。
    const titleStyles: ReaderV2SpanStyleRange[] = [];
    for (let blockIndex = 0; blockIndex < config.document.blocks.length; blockIndex++) {
      const block = config.document.blocks[blockIndex];
      if (block.displayEnd <= block.displayStart || blockIndex === lastBodyBlock) continue;
      if (block.title) {
        const size = this.readerTitleFontSize * (block.titleSegment > 0 ? this.titleStyle.secondaryScale : 1);
        if (titleInScope && titlePlan) {
          const style = this.typographyPreviewEmphasis(titlePlan.rule, size, input.titleFontFamily,
            this.readerTitleFontWeight, titlePlan.context);
          style.start = block.displayStart;
          style.end = block.displayEnd;
          style.repeatCaps = true;
          titleStyles.push(style);
          config.styles.push(style);
        } else if (!titleInScope) {
          config.styles.push(this.regexPreviewDimStyle(block.displayStart, block.displayEnd, uiContext.fp2px(size),
            input.titleFontFamily, this.readerTitleFontWeight, dimColor));
        }
      } else if (!bodyInScope) {
        config.styles.push(this.regexPreviewDimStyle(block.displayStart, block.displayEnd, input.fontSizePx,
          input.bodyFontFamily, this.readerFontWeight, dimColor));
      }
    }
    return new RegexRulePreview(config, titleStyles);
  }

  /** 正则规则三项；标题强调（rule -1）四项：跟随主题（标题）、同正文强调、无强调、自定义。 */
  emphasisModeOptions(rule: number = 0): SelectOption[] {
    if (rule === -1) {
      return [{ value: '跟随主题' }, { value: '同正文强调' }, { value: '无强调' }, { value: '自定义' }];
    }
    return [
      { value: '跟随主题' },
      { value: '无强调' },
      { value: '自定义' }
    ];
  }

  emphasisModeIds(rule: number = 0): string[] {
    return rule === -1 ? [ReaderTitleEmphasis.THEME, 'inherit', 'none', 'custom'] : ['inherit', 'none', 'custom'];
  }

  emphasisModeIndex(mode: string, rule: number = 0): number {
    const normalized = mode === 'text' || mode === 'highlight' || mode === 'bubble' ? 'custom' : mode;
    return Math.max(0, this.emphasisModeIds(rule).indexOf(normalized));
  }

  emphasisModeByIndex(index: number, rule: number = 0): string {
    const ids = this.emphasisModeIds(rule);
    return index >= 0 && index < ids.length ? ids[index] : ids[0];
  }

  isCustomEmphasisMode(mode: string): boolean {
    return mode === 'custom' || mode === 'text' || mode === 'highlight' || mode === 'bubble';
  }

  emphasisModeLabel(mode: string, rule: number = 0): string {
    const options = this.emphasisModeOptions(rule);
    return String(options[this.emphasisModeIndex(mode, rule)].value);
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
    this.appendAccessibleBubbleStyle(options, 'celestial-orbit', '星穹御签', revision);
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
        Select(this.emphasisModeOptions(index))
          .selected(this.emphasisModeIndex(this.regexRuleAt(index).emphasisMode, index))
          .value(this.emphasisModeLabel(this.regexRuleAt(index).emphasisMode, index))
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .optionFont({ family: this.applicationFontFamily })
          .selectedOptionFont({ family: this.applicationFontFamily })
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
              target.emphasisMode = this.emphasisModeByIndex(selectedIndex, index);
            });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.isCustomEmphasisMode(this.regexRuleAt(index).emphasisMode)) {
        this.regexEmphasisToggle('设置文字色', this.regexRuleAt(index).customTextColorEnabled, (enabled: boolean) => {
          this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
            target.customTextColorEnabled = enabled;
            if (enabled && !target.customTextColor.trim()) {
              target.customTextColor = this.accentColor();
            }
          });
        })
        if (this.regexRuleAt(index).customTextColorEnabled) {
          this.regexDayNightColorRow(index, 'text', '文字颜色')
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
          this.regexDayNightColorRow(index, 'highlight', '高亮色块颜色')
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
              .optionFont({ family: this.applicationFontFamily })
              .selectedOptionFont({ family: this.applicationFontFamily })
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
          this.regexDayNightColorRow(index, 'bubble', '强调气泡颜色')
        }
      }
    }
    .width('100%')
  }

  /** 规则自定义颜色在浅色/深色模式下的值；kind 为 text、highlight、bubble。深色为空表示同浅色。 */
  regexRuleColor(index: number, kind: string, dark: boolean): string {
    const rule = this.regexRuleAt(index);
    if (kind === 'text') return dark ? rule.customTextColorDark : rule.customTextColor;
    if (kind === 'highlight') return dark ? rule.customHighlightColorDark : rule.customHighlightColor;
    return dark ? rule.customBubbleColorDark : rule.customBubbleColor;
  }

  setRegexRuleColor(index: number, kind: string, dark: boolean, value: string): void {
    this.updateRegexRule(index, (target: ReaderRegexFontRule) => {
      if (dark) {
        // 深色色块可以选“同白天”清空；其余输入按浅色那份兜底。
        const next = value.trim() === '' ? '' : this.normalizeColorInput(value,
          this.regexRuleColor(index, kind, false) || this.accentColor());
        if (kind === 'text') target.customTextColorDark = next;
        else if (kind === 'highlight') target.customHighlightColorDark = next;
        else target.customBubbleColorDark = next;
        return;
      }
      if (kind === 'text') {
        target.customTextColor = this.normalizeColorInput(value, target.customTextColor || this.accentColor());
      } else if (kind === 'highlight') {
        target.customHighlightColor = this.normalizeColorInput(value,
          target.customHighlightColor || this.accentColor());
      } else {
        target.customBubbleColor = this.normalizeColorInput(value, target.customBubbleColor || this.accentColor());
      }
    });
  }

  /** 一行并排白天、夜间两枚色块，各点各改；夜间没设时画成虚线空心圈，表示同白天。 */
  @Builder
  regexDayNightColorRow(index: number, kind: string, title: string) {
    Row({ space: AppSpacing.SM }) {
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      ColorCodePicker({
        allowAlpha: true,
        value: this.regexRuleColor(index, kind, false),
        placeholder: this.accentColor(),
        appDarkMode: this.appDarkMode,
        accentColor: this.accentColor(),
        optionTitle: `${title}（白天）`,
        swatchCaption: '白天',
        swatchNight: false,
        onColorChange: (value: string) => {
          this.setRegexRuleColor(index, kind, false, value);
        }
      })
      ColorCodePicker({
        allowAlpha: true,
        allowEmpty: true,
        emptyOptionLabel: '同白天',
        value: this.regexRuleColor(index, kind, true),
        placeholder: this.regexRuleColor(index, kind, false) || this.accentColor(),
        appDarkMode: this.appDarkMode,
        accentColor: this.accentColor(),
        optionTitle: `${title}（夜间）`,
        swatchCaption: this.regexRuleColor(index, kind, true).trim() ? '夜间' : '同白天',
        swatchNight: true,
        onColorChange: (value: string) => {
          this.setRegexRuleColor(index, kind, true, value);
        }
      })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
    .border({ width: { bottom: 0.5 }, color: this.settingsDividerColor() })
    .alignItems(VerticalAlign.Center)
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
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
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
        () => Math.round(this.regexRuleAt(index).fontSize) > 14, () => {
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
        () => Math.round(this.regexRuleAt(index).fontSize) < 50, () => {
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
    .alignItems(VerticalAlign.Center)
  }

}

/** 路由页面与样式悬浮框复用同一套字体控件和保存队列。 */
@Entry
@Component
struct ReaderFontSettingsPage {
  private closeEditor: () => void = () => { router.back(); };
  private showEditor: () => void = () => {};

  onPageShow(): void {
    this.showEditor();
  }

  onBackPress(): boolean {
    this.closeEditor();
    return true;
  }

  build() {
    Stack() {
      ReaderFontSettingsEditor({ onCloseReady: (close: () => void) => { this.closeEditor = close; },
        onShownReady: (show: () => void) => { this.showEditor = show; } })
    }
    .width('100%')
    .height('100%')
  }
}
