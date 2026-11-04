import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { ReaderQuickJumpContent } from './ReaderQuickJumpContent';
import { ReaderSettingSwitchRow, ReaderSettingActionRow } from './ReaderSettingRows';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { PdfPagePosition } from '../../core/book/pdf/PdfModels';
import { ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { AiAccessPolicy } from '../../account/AiAccessPolicy';

const PANEL_HEADER_HEIGHT: number = 56;
const BOTTOM_BAR_ACTIONS_HEIGHT: number = 56;
const BOTTOM_BAR_FULL_HEIGHT: number = 112;

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
  @Prop darkMode: boolean = false;
  @Prop bookTitle: string = '';
  @Prop menuVisible: boolean = false;
  @Prop activePanel: string = '';
  @Prop ready: boolean = false;
  @Prop pageCount: number = 0;
  @Prop pageIndex: number = 0;
  @Prop previewIndex: number = -1;
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
  @State viewportWidth: number = 360;
  @State viewportHeight: number = 720;
  @State jumpText: string = '';
  @BuilderParam navigationContent: () => void = this.emptyContent;
  onClose: () => void = (): void => {};
  onPanelChange: (panel: string) => void = (_panel: string): void => {};
  onPageChange: (index: number) => void = (_index: number): void => {};
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

  private bottomBarHeight(): number {
    return this.activePanel ? BOTTOM_BAR_ACTIONS_HEIGHT : BOTTOM_BAR_FULL_HEIGHT;
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
    else if (this.activePanel === 'settings') desired += 4 * 64 + 40 + (this.superResolution && this.superResolutionReady() ? 40 : 0) + 16;
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

  @Builder
  actionButton(icon: Resource, label: string, panel: string) {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      SymbolGlyph(icon).fontSize(24).fontColor([this.activePanel === panel ?
        ThemeRuntime.accentColor(this.darkMode) : ThemeRuntime.primaryTextColor(this.darkMode)])
    }.layoutWeight(1).height(48).backgroundColor(Color.Transparent).enabled(this.ready)
      .accessibilityText(label).id(`pdf_action_${panel}`).onClick((): void => this.selectPanel(panel))
  }

  @Builder
  actionBar() {
    Row() {
      this.actionButton($r('sys.symbol.list_bullet'), this.navigationTitle, 'toc')
      this.actionButton($r('sys.symbol.book_pages'), '跳转页码', 'jump')
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
              ReaderQuickJumpContent({ chapterLabel: '页码', chapterUnit: '页',
                value: this.displayIndex(), chapterCount: this.pageCount, pageCount: this.pageCount,
                currentChapter: this.pageIndex, valueLabel: `${this.displayIndex() + 1} / ${this.pageCount} 页`,
                busy: !this.ready, dark: this.darkMode, textColor: ThemeRuntime.primaryTextColor(this.darkMode),
                subTextColor: ThemeRuntime.subTextColor(this.darkMode), accentColor: ThemeRuntime.accentColor(this.darkMode),
                trackColor: ThemeRuntime.dividerColor(this.darkMode), thumbColor: ThemeRuntime.cardColor(this.darkMode),
                onChange: (index: number, mode: SliderChangeMode): void => {
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.onPageChange(index);
                  else this.onPreview(PdfPagePosition.clamp(index, this.pageCount));
                },
                onStep: (direction: number): void => this.onPageChange(this.pageIndex + direction),
                onExpandedChange: (_expanded: boolean): void => this.selectPanel('jump'),
                onSlideCancel: (): void => this.onPreview(-1) })
            }.width('100%').height(BOTTOM_BAR_FULL_HEIGHT - BOTTOM_BAR_ACTIONS_HEIGHT - 1)
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
      .translate({ x: '-50%', y: -(this.bottomInset() + BOTTOM_BAR_FULL_HEIGHT + 48) })
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
      .translate({ y: -(this.bottomInset() + BOTTOM_BAR_FULL_HEIGHT + 12 + 40) }).transition(this.panelTransition())
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
        }
      }
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
      .onSizeChange((_before: SizeOptions, after: SizeOptions): void => {
        this.viewportWidth = Number(after.width); this.viewportHeight = Number(after.height);
      })
  }
}
