import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { ReaderQuickJumpContent } from './ReaderQuickJumpContent';
import { ReaderBrightnessControl } from './ReaderBrightnessControl';
import { common } from '@kit.AbilityKit';
import { ReaderQuickJumpModel } from '../../core/reader/ReaderQuickJumpModel';
import { ReaderSettingSwitchRow, ReaderSettingActionRow } from './ReaderSettingRows';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { PdfPagePosition } from '../../core/book/pdf/PdfModels';
import { ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { AiAccessPolicy } from '../../account/AiAccessPolicy';

const PANEL_HEADER_HEIGHT: number = 56;
const BOTTOM_BAR_ACTIONS_HEIGHT: number = 56;
/** PDF 快速跳转可选的方式：没有章节，只在全书百分比与页数之间切换。 */
const PDF_QUICK_JUMP_MODES: string[] = ['percent', 'page'];

/**
 * PDF 与小说阅读共用材质、进度条、圆形按钮及设置行。正文与浮层独立布局。
 * 顶栏：返回、书名与页码（点按跳页）、搜索；底栏：页码进度条与目录、跳页、设置。
 * 搜索面板贴在顶栏下方，其余面板从底栏上方弹出，高度按内容计算。
 */
@Component
export struct PdfReaderControls {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('readerAiProcessingIndicatorEnabled') readerAiProcessingIndicatorEnabled: boolean = true;
  @StorageProp('readerUseBrightnessQuickAction') readerUseBrightnessQuickAction: boolean = true;
  @StorageLink('pdfQuickJumpMode') pdfQuickJumpMode: string = 'page';
  /** 收起 / 展开跳转方式与小说阅读页共用一个状态。 */
  @StorageLink('readerQuickJumpExpanded') readerQuickJumpExpanded: boolean = false;
  /** 百分比模式拖动中的读数；页码预览仍走 previewIndex。 */
  @State previewPercent: number = -1;
  @Prop darkMode: boolean = false;
  @Prop bookTitle: string = '';
  @Prop menuVisible: boolean = false;
  @Prop activePanel: string = '';
  @Prop ready: boolean = false;
  @Prop pageCount: number = 0;
  @Prop pageIndex: number = 0;
  /** 页面撤掉预览（跳转完成或取消）时，百分比模式的拖动读数也一起撤掉。 */
  @Prop @Watch('onPreviewIndexChanged') previewIndex: number = -1;
  @Prop continuous: boolean = true;
  @Prop doublePage: boolean = false;
  @Prop fitPage: boolean = false;
  @Prop wideWindow: boolean = false;
  @Prop superResolution: boolean = false;
  @Prop superResolutionAccess: string = ReaderComicSuperResolutionAccess.UNSUPPORTED;
  @Prop showOriginal: boolean = false;
  @Prop enhancementStatus: string = '';
  @Prop searchInput: string = '';
  @Prop searching: boolean = false;
  @Prop searchCompleted: boolean = false;
  @Prop searchCount: number = 0;
  @Prop searchIndex: number = -1;
  /** 有内嵌目录时为“目录”，否则按页列出。 */
  @Prop navigationTitle: string = '目录';
  /** 目录行数，用来让短目录的面板不留大片空白；0 表示未知。 */
  @Prop navigationCount: number = 0;
  @Prop brightnessValue: number = -1;
  @Prop lastManualBrightness: number = 50;
  @Prop brightnessReady: boolean = false;
  @State viewportWidth: number = 360;
  @State viewportHeight: number = 720;
  @State jumpText: string = '';
  @BuilderParam navigationContent: () => void = this.emptyContent;
  onClose: () => void = (): void => {};
  onPanelChange: (panel: string) => void = (_panel: string): void => {};
  onPageChange: (index: number) => void = (_index: number): void => {};
  /** 快速跳转进度条松手：由页面弹“确认跳转”再跳；percent 是百分比模式松手时的读数，页数模式为 -1。 */
  onQuickJump: (index: number, percent: number) => void = (_index: number, _percent: number): void => {};
  onPreview: (index: number) => void = (_index: number): void => {};
  onJump: (text: string) => void = (_text: string): void => {};
  onContinuousChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onDoublePageChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onFitPageChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onSuperResolutionChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onOriginalChange: () => void = (): void => {};
  onOpenMembership: () => void = (): void => {};
  onSearchInput: (text: string) => void = (_text: string): void => {};
  onSearch: () => void = (): void => {};
  onSearchStep: (direction: number) => void = (_direction: number): void => {};
  onBrightnessChange: (value: number, persist: boolean) => void = (_value: number, _persist: boolean): void => {};
  onLayoutElements: () => void = (): void => {};

  @Builder
  emptyContent() {}

  private panelWidth(): number {
    const available = Math.max(1, this.viewportWidth - 36);
    return this.viewportWidth >= 600 ? Math.min(available, Math.min(520, Math.max(320, this.viewportWidth * 0.52))) : available;
  }

  private panelLeft(): number {
    return this.viewportWidth >= 600 ? this.viewportWidth - 18 - this.panelWidth() : 18;
  }

  private bottomInset(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : 8;
  }

  private topBarBottom(): number {
    return this.statusBarHeight + 10 + 56;
  }

  private headerHeight(): number {
    let scale = 1;
    try {
      scale = Math.max(1, Math.min(2, (getContext(this) as common.UIAbilityContext).config.fontSizeScale || 1));
    } catch (_) {
    }
    return 44 + Math.max(0, scale - 1) * 28;
  }

  private quickJumpHeight(): number {
    return 54 + (this.readerQuickJumpExpanded ? this.headerHeight() : 0);
  }

  private bottomBarHeight(): number {
    return this.activePanel ? BOTTOM_BAR_ACTIONS_HEIGHT : this.quickJumpHeight() + 58;
  }

  private jumpMode(): string {
    return this.pdfQuickJumpMode === 'percent' ? 'percent' : 'page';
  }

  onPreviewIndexChanged(): void {
    if (this.previewIndex < 0) this.previewPercent = -1;
  }

  private percentValue(): number {
    if (this.previewPercent >= 0) return this.previewPercent;
    return PdfPagePosition.percent(this.displayIndex(), this.pageCount, true);
  }

  private setJumpMode(mode: string): void {
    this.previewPercent = -1;
    this.onPreview(-1);
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.pdfQuickJumpMode = mode === 'percent' ? 'percent' : 'page';
    });
  }

  private setJumpExpanded(expanded: boolean): void {
    if (this.readerQuickJumpExpanded === expanded) return;
    animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.readerQuickJumpExpanded = expanded;
    });
  }

  /** 百分比按每页等权换算成页码；左右箭头直接翻页，不用确认。 */
  private onJumpSlider(value: number, mode: SliderChangeMode): void {
    const percent = this.jumpMode() === 'percent';
    const page = percent ? PdfPagePosition.fromPercent(value, this.pageCount) :
      PdfPagePosition.clamp(Math.round(value), this.pageCount);
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      // 与小说阅读页一致：松手后先确认再跳；确认期间保留预览，结果出来后由页面撤掉。
      if (percent) this.previewPercent = ReaderQuickJumpModel.clampPercent(value);
      this.onPreview(page);
      this.onQuickJump(page, percent ? ReaderQuickJumpModel.clampPercent(value) : -1);
      return;
    }
    if (percent) this.previewPercent = ReaderQuickJumpModel.clampPercent(value);
    this.onPreview(page);
  }

  private superResolutionReady(): boolean {
    return this.superResolutionAccess === ReaderComicSuperResolutionAccess.READY;
  }

  private enhancementStatusLabel(): string {
    if (this.showOriginal) return '原页';
    if (!this.readerAiProcessingIndicatorEnabled) return '';
    return this.enhancementStatus || 'AI 超分';
  }

  /** 按内容估算面板高度，避免短内容下方留出大片空白；目录和设置在矮窗口里改为滚动。 */
  private panelHeight(): number {
    let desired = PANEL_HEADER_HEIGHT;
    if (this.activePanel === 'toc') desired = this.navigationCount > 0 ? Math.min(520, desired + this.navigationCount * 56 + 12) : 520;
    else if (this.activePanel === 'settings') desired += 5 * 64 + 40 + (this.superResolution && this.superResolutionReady() ? 40 : 0) + 16;
    else if (this.activePanel === 'search') desired += 44 + 8 + 36 + 16;
    else desired += 44 + 10 + 20 + 20;
    const available = this.activePanel === 'search' ?
      this.viewportHeight - this.topBarBottom() - 8 - this.bottomInset() - BOTTOM_BAR_ACTIONS_HEIGHT - 16 :
      this.viewportHeight - this.statusBarHeight - this.bottomInset() - BOTTOM_BAR_ACTIONS_HEIGHT - 96;
    return Math.max(PANEL_HEADER_HEIGHT, Math.min(desired, available));
  }

  private titleCapsuleWidth(): number {
    return Math.max(1, Math.min(560, this.viewportWidth - 36 - 80 - 24));
  }

  private displayIndex(): number {
    return this.previewIndex >= 0 ? this.previewIndex : this.pageIndex;
  }

  private pageSummary(): string {
    if (!this.ready) return 'PDF';
    return `第 ${this.pageIndex + 1} / ${this.pageCount} 页 · ${PdfPagePosition.percent(this.pageIndex, this.pageCount, true).toFixed(1)}%`;
  }

  private selectPanel(panel: string): void {
    this.onPanelChange(this.activePanel === panel ? '' : panel);
  }

  private panelTitle(): string {
    if (this.activePanel === 'toc') return this.navigationTitle;
    if (this.activePanel === 'settings') return '阅读设置';
    return this.activePanel === 'search' ? '搜索' : '跳转页码';
  }

  private panelTransition(): TransitionEffect {
    return TransitionEffect.translate({ y: this.activePanel === 'search' ? -20 : 28 }).combine(TransitionEffect.opacity(0))
      .animation({ duration: 240, curve: Curve.EaseOut });
  }

  private scrimColor(): string {
    return this.darkMode ? '#47000000' : '#1F000000';
  }

  /** 亮度条放在顶栏与底栏之间，和其它阅读页一样随菜单出现。 */
  private brightnessHeight(): number {
    const top = this.topBarBottom() + 12;
    const bottom = this.viewportHeight - this.bottomInset() - this.bottomBarHeight() - 74;
    return Math.max(0, Math.min(280, bottom - top));
  }

  private brightnessTop(): number {
    const top = this.topBarBottom() + 12;
    const bottom = this.viewportHeight - this.bottomInset() - this.bottomBarHeight() - 74;
    return top + Math.max(0, (bottom - top - this.brightnessHeight()) / 2);
  }

  @Builder
  brightnessControl() {
    ReaderBrightnessControl({
      value: this.brightnessValue, lastManualValue: this.lastManualBrightness,
      panelHeight: this.brightnessHeight(), ready: this.brightnessReady,
      dark: this.darkMode, panelColor: ThemeRuntime.cardColor(this.darkMode),
      textColor: ThemeRuntime.primaryTextColor(this.darkMode),
      accentColor: ThemeRuntime.accentColor(this.darkMode), trackColor: ThemeRuntime.dividerColor(this.darkMode),
      thumbColor: ThemeRuntime.cardColor(this.darkMode),
      onChange: (value: number, persist: boolean): void => this.onBrightnessChange(value, persist)
    })
      .position({ x: Math.max(0, this.viewportWidth - ReaderBrightnessControl.WIDTH - 12), y: this.brightnessTop() })
      .transition(TransitionEffect.OPACITY)
  }

  @Builder
  roundButton(icon: Resource, label: string, action: () => void) {
    ImmersiveBackButton({ icon: icon, iconOffsetX: 0,
      iconColor: ThemeRuntime.primaryTextColor(this.darkMode), darkMode: this.darkMode,
      buttonSize: 40, containerWidth: 40, containerHeight: 56, startInset: 0,
      materialScale: 0.83, compactLayout: true, accessibilityLabel: label, onBack: action })
  }

  @Builder
  topMenu() {
    Row() {
      this.roundButton($r('sys.symbol.chevron_left'), '返回书架', (): void => this.onClose())
      ReaderMaterialPanel({ panelWidth: this.titleCapsuleWidth(), panelHeight: 40,
        cornerRadius: 20, darkMode: this.darkMode, fallbackColor: ThemeRuntime.cardColor(this.darkMode) }) {
        Column({ space: 1 }) {
          Text(this.bookTitle).fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode)).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.pageSummary())
            .fontSize(AppFontSize.MICRO + 1).fontColor(ThemeRuntime.subTextColor(this.darkMode)).maxLines(1)
        }.width('100%').height('100%').padding({ left: 14, right: 14 })
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
          .accessibilityText(`${this.bookTitle}，${this.pageSummary()}，点按跳转页码`)
          .onClick((): void => { if (this.ready) this.selectPanel('jump'); })
      }
      if (this.ready) {
        // Inline so the icon tint follows the open panel (a by-value builder argument would not refresh).
        ImmersiveBackButton({ icon: $r('sys.symbol.magnifyingglass'), iconOffsetX: 0,
          iconColor: this.activePanel === 'search' ? ThemeRuntime.accentColor(this.darkMode) :
            ThemeRuntime.primaryTextColor(this.darkMode), darkMode: this.darkMode,
          buttonSize: 40, containerWidth: 40, containerHeight: 56, startInset: 0,
          materialScale: 0.83, compactLayout: true, accessibilityLabel: '搜索 PDF',
          onBack: (): void => this.selectPanel('search') })
      } else { Blank().width(40) }
    }.width('100%').padding({ left: 18, right: 18, top: this.statusBarHeight + 10 })
      .justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Center)
      .position({ x: 0, y: 0 }).transition(TransitionEffect.OPACITY).hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  /** 与小说、漫画阅读页底栏的 readerHdsMenuItem 相同：只有图标，点按没有胶囊底色。 */
  @Builder
  actionButton(icon: Resource, label: string, panel: string) {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon).fontSize(24).fontColor([ThemeRuntime.primaryTextColor(this.darkMode)])
      }.width(32).height(32)
    }.layoutWeight(1).height(48).enabled(this.ready).opacity(this.ready ? 1 : 0.32)
      .accessibilityText(label).id(`pdf_action_${panel}`).onClick((): void => this.selectPanel(panel))
  }

  @Builder
  actionBar() {
    Row() {
      this.actionButton($r('sys.symbol.list_bullet'), this.navigationTitle, 'toc')
      this.actionButton($r('sys.symbol.gearshape'), '阅读设置', 'settings')
    }.width('100%').height(BOTTOM_BAR_ACTIONS_HEIGHT).padding({ left: 12, right: 12 })
  }

  @Builder
  bottomMenu() {
    Column() {
      ReaderMaterialPanel({ panelWidth: this.panelWidth(), panelHeight: this.bottomBarHeight(),
        cornerRadius: 28, darkMode: this.darkMode, fallbackColor: ThemeRuntime.cardColor(this.darkMode) }) {
        Column() {
          if (!this.activePanel) {
            Column() {
              ReaderQuickJumpContent({ modes: PDF_QUICK_JUMP_MODES, mode: this.jumpMode(),
                chapterLabel: '页码', chapterUnit: '页',
                value: this.jumpMode() === 'percent' ? this.percentValue() : this.displayIndex(),
                chapterCount: this.pageCount, pageCount: this.pageCount, currentChapter: this.pageIndex,
                valueLabel: this.jumpMode() === 'percent' ?
                  `${this.percentValue().toFixed(1)}% · 第 ${this.displayIndex() + 1} 页` :
                  `${this.displayIndex() + 1} / ${this.pageCount} 页`,
                busy: !this.ready, dark: this.darkMode, textColor: ThemeRuntime.primaryTextColor(this.darkMode),
                subTextColor: ThemeRuntime.subTextColor(this.darkMode), accentColor: ThemeRuntime.accentColor(this.darkMode),
                trackColor: ThemeRuntime.dividerColor(this.darkMode), thumbColor: ThemeRuntime.cardColor(this.darkMode),
                expanded: this.readerQuickJumpExpanded, headerHeight: this.headerHeight(),
                onModeChange: (mode: string): void => this.setJumpMode(mode),
                onChange: (value: number, mode: SliderChangeMode): void => this.onJumpSlider(value, mode),
                onStep: (direction: number): void => this.onPageChange(this.pageIndex + direction),
                onExpandedChange: (expanded: boolean): void => this.setJumpExpanded(expanded),
                onSlideCancel: (): void => { this.previewPercent = -1; this.onPreview(-1); } })
            }.width('100%').height(this.quickJumpHeight())
            Divider().strokeWidth(0.5).color(ThemeRuntime.dividerColor(this.darkMode)).margin({ left: 20, right: 20 })
          }
          this.actionBar()
        }.width('100%').height('100%')
      }
    }.position({ x: this.panelLeft(), y: '100%' })
      .translate({ y: -(this.bottomInset() + this.bottomBarHeight()) }).transition(this.panelTransition())
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  /** 拖动进度条时在底栏上方提示目标页，松手才跳转。 */
  @Builder
  previewTooltip() {
    Text(`第 ${this.previewIndex + 1} 页 · ${PdfPagePosition.percent(this.previewIndex, this.pageCount, true).toFixed(1)}%`)
      .fontSize(AppFontSize.CAPTION).fontColor('#FFFFFFFF').height(36).padding({ left: 16, right: 16 })
      .borderRadius(18).backgroundColor(this.darkMode ? '#E63A3C40' : '#D94B4D52')
      .shadow({ radius: 10, color: '#50000000', offsetX: 0, offsetY: 3 })
      .position({ x: this.panelLeft() + this.panelWidth() / 2, y: '100%' })
      .translate({ x: '-50%', y: -(this.bottomInset() + this.bottomBarHeight() + 48) })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  panelHeader() {
    Row() {
      Text(this.panelTitle())
        .fontSize(AppFontSize.TITLE).fontWeight(FontWeight.Bold).fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        .layoutWeight(1).maxLines(1)
      this.roundButton($r('sys.symbol.xmark'), '关闭面板', (): void => this.onPanelChange(''))
    }.width('100%').height(PANEL_HEADER_HEIGHT).padding({ left: 24, right: 10 })
  }

  @Builder
  aiSettingsRow() {
    if (this.superResolutionReady()) {
      ReaderSettingSwitchRow({ title: 'AI超分', minimumMembership: AiAccessPolicy.trialOpen() ? '' : 'MONTHLY',
        description: '增强低清扫描页；文字页保持原生显示，会增加耗电', checked: this.superResolution,
        textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
        onChange: this.onSuperResolutionChange })
    } else {
      ReaderSettingActionRow({ title: 'AI超分', minimumMembership: AiAccessPolicy.trialOpen() ? '' : 'MONTHLY',
        description: this.superResolutionAccess === ReaderComicSuperResolutionAccess.UNSUPPORTED ?
          '需要 API 26 及以上且支持图片超分的设备' : AiAccessPolicy.blockedMessage(),
        actionText: this.superResolutionAccess === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED ? AiAccessPolicy.actionText() : '',
        textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
        buttonColor: ThemeRuntime.accentColor(this.darkMode), buttonTextColor: ThemeRuntime.onAccentColor(),
        onAction: this.onOpenMembership })
    }
  }

  @Builder
  compareBar() {
    Column() {
      ReaderMaterialPanel({ panelWidth: Math.min(this.panelWidth(), 296), panelHeight: 40, cornerRadius: 20,
        darkMode: this.darkMode, fallbackColor: ThemeRuntime.cardColor(this.darkMode) }) {
        Row({ space: 8 }) {
          Text(this.enhancementStatusLabel())
            .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.darkMode)).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button(this.showOriginal ? '查看超分' : '查看原页').id('pdf_compare_original')
            .height(32).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .backgroundColor(Color.Transparent).onClick(this.onOriginalChange)
        }.width('100%').height('100%').padding({ left: 16, right: 6 })
      }
    }.position({ x: this.panelLeft() + this.panelWidth() - Math.min(this.panelWidth(), 296), y: '100%' })
      .translate({ y: -(this.bottomInset() + this.bottomBarHeight() + 12 + 40) }).transition(this.panelTransition())
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  @Builder
  settingsContent() {
    Scroll() {
      Column({ space: 8 }) {
        ReaderSettingSwitchRow({ title: '连续滚动', description: '关闭后逐页翻阅', checked: this.continuous,
          textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
          onChange: this.onContinuousChange })
        ReaderSettingSwitchRow({ title: '双页显示', description: this.wideWindow ? '并排展示两页，适合横屏阅读' : '在宽屏窗口下可用',
          checked: this.doublePage, textColor: ThemeRuntime.primaryTextColor(this.darkMode),
          subTextColor: ThemeRuntime.subTextColor(this.darkMode), onChange: this.onDoublePageChange })
          .enabled(this.wideWindow).opacity(this.wideWindow ? 1 : 0.5)
        ReaderSettingSwitchRow({ title: '适配整页', description: '整页完整可见；关闭后按页面宽度显示', checked: this.fitPage,
          textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
          onChange: this.onFitPageChange })
        this.aiSettingsRow()
        ReaderSettingActionRow({ title: '布局元素设置', description: '控制唤出菜单时显示的快捷组件，如亮度条',
          actionText: '设置', textColor: ThemeRuntime.primaryTextColor(this.darkMode),
          subTextColor: ThemeRuntime.subTextColor(this.darkMode), buttonColor: ThemeRuntime.accentColor(this.darkMode),
          buttonTextColor: ThemeRuntime.onAccentColor(), onAction: this.onLayoutElements })
        if (this.superResolution && this.superResolutionReady()) {
          Text('AI 可能改变细小文字和数字，可通过“查看原页”对照。').fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode)).width('100%')
        }
        Text('保留文档原始版式与颜色，双指可缩放页面。').fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode)).width('100%').margin({ top: 4 })
      }.width('100%').padding({ left: 24, right: 24, bottom: 16 }).alignItems(HorizontalAlign.Start)
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
  }

  @Builder
  jumpContent() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        TextInput({ text: this.jumpText, placeholder: `1–${this.pageCount}` })
          .id('pdf_jump_input').type(InputType.Number).layoutWeight(1).height(44).borderRadius(22)
          .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          .backgroundColor(ThemeRuntime.softFillColor(this.darkMode)).enterKeyType(EnterKeyType.Go)
          .onChange((text: string): void => { this.jumpText = text; }).onSubmit((): void => this.onJump(this.jumpText))
        Button('跳转').height(44).fontSize(AppFontSize.BODY).backgroundColor(ThemeRuntime.accentColor(this.darkMode))
          .fontColor(ThemeRuntime.onAccentColor()).enabled(this.jumpText.trim().length > 0)
          .onClick((): void => this.onJump(this.jumpText))
      }
      Text(`当前第 ${this.pageIndex + 1} 页，共 ${this.pageCount} 页`).fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode)).width('100%')
    }.width('100%').padding({ left: 24, right: 24, bottom: 20 })
      .onAppear((): void => { this.jumpText = `${this.pageIndex + 1}`; })
  }

  @Builder
  searchContent() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.searchInput, placeholder: '搜索文档中的文字' }).layoutWeight(1).height(44).borderRadius(22)
          .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
          .backgroundColor(ThemeRuntime.softFillColor(this.darkMode)).enterKeyType(EnterKeyType.Search)
          .onChange(this.onSearchInput).onSubmit(this.onSearch)
        Button(this.searching ? '搜索中' : '搜索').height(44).fontSize(AppFontSize.BODY)
          .backgroundColor(ThemeRuntime.accentColor(this.darkMode)).fontColor(ThemeRuntime.onAccentColor())
          .enabled(!this.searching && this.searchInput.trim().length > 0).onClick(this.onSearch)
      }
      Row({ space: 4 }) {
        Text(this.searchCount > 0 ? `第 ${this.searchIndex + 1} / ${this.searchCount} 处匹配` :
          this.searching ? '正在查找…' : this.searchCompleted ? '未找到文字，扫描文档可能没有文字层' : '输入关键词开始搜索')
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.darkMode)).layoutWeight(1).maxLines(2)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(18).fontColor([ThemeRuntime.primaryTextColor(this.darkMode)])
        }.width(36).height(36).backgroundColor(Color.Transparent).enabled(this.searchCount > 0 && !this.searching)
          .opacity(this.searchCount > 0 && !this.searching ? 1 : 0.4)
          .accessibilityText('上一个匹配').onClick((): void => this.onSearchStep(-1))
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(18).fontColor([ThemeRuntime.primaryTextColor(this.darkMode)])
        }.width(36).height(36).backgroundColor(Color.Transparent).enabled(this.searchCount > 0 && !this.searching)
          .opacity(this.searchCount > 0 && !this.searching ? 1 : 0.4)
          .accessibilityText('下一个匹配').onClick((): void => this.onSearchStep(1))
      }.width('100%').height(36)
    }.width('100%').padding({ left: 24, right: 16, bottom: 16 })
  }

  @Builder
  floatingPanel() {
    Column() {
      ReaderMaterialPanel({ panelWidth: this.panelWidth(), panelHeight: this.panelHeight(), cornerRadius: 28,
        darkMode: this.darkMode, fallbackColor: ThemeRuntime.cardColor(this.darkMode) }) {
        Column() {
          this.panelHeader()
          if (this.activePanel === 'toc') {
            Column() { this.navigationContent() }.width('100%').layoutWeight(1)
          } else if (this.activePanel === 'settings') {
            this.settingsContent()
          } else if (this.activePanel === 'search') {
            this.searchContent()
          } else {
            this.jumpContent()
          }
        }.width('100%').height('100%')
      }
    }.position({ x: this.panelLeft(), y: this.activePanel === 'search' ? this.topBarBottom() + 8 : '100%' })
      .translate({ y: this.activePanel === 'search' ? 0 : -(this.bottomInset() + BOTTOM_BAR_ACTIONS_HEIGHT + 12 + this.panelHeight()) })
      .transition(this.panelTransition())
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.menuVisible) {
        // 搜索时正文仍可滚动查看命中位置；其余面板加一层浅遮罩，点按空白处收起。
        if (this.activePanel && this.activePanel !== 'search') {
          Column().width('100%').height('100%').backgroundColor(this.scrimColor())
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
            .onClick((): void => this.onPanelChange(''))
        }
        this.topMenu()
        if (this.ready) {
          this.bottomMenu()
          if (!this.activePanel && this.previewIndex >= 0) {
            this.previewTooltip()
          } else if (!this.activePanel && this.superResolution && this.superResolutionReady()) {
            this.compareBar()
          }
          if (this.activePanel) { this.floatingPanel() }
          if (!this.activePanel && this.previewIndex < 0 && this.readerUseBrightnessQuickAction &&
            this.brightnessHeight() >= 132) {
            this.brightnessControl()
          }
        }
      }
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
      .onSizeChange((_before: SizeOptions, after: SizeOptions): void => {
        this.viewportWidth = Number(after.width); this.viewportHeight = Number(after.height);
      })
  }
}
