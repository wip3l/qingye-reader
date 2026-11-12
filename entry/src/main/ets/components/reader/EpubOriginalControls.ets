import { common } from '@kit.AbilityKit';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { PopupMenuAction } from '../common/PopupMenuAction';
import { ReaderFloatingMaterialBar, ReaderMaterialPanel } from './ReaderFloatingMaterialBar';
import { ReaderTitleCapsule } from './ReaderTitleCapsule';
import { ReaderQuickJumpContent } from './ReaderQuickJumpContent';
import { READER_QUICK_JUMP_CAPSULE_HEIGHT, ReaderQuickJumpCapsule } from './ReaderQuickJumpCapsule';
import { ReaderBrightnessControl } from './ReaderBrightnessControl';
import { ReaderChromeMotion } from './ReaderChromeMotion';
import { ReaderSettingActionRow, ReaderSettingLabel, ReaderSettingSelectRow, ReaderSettingSwitchRow } from './ReaderSettingRows';
import { ReaderQuickJumpModel } from '../../core/reader/ReaderQuickJumpModel';
import { ReaderPageTurnAnimation } from '../../core/reader/ReaderPageTurnAnimation';
import { ReaderNightImage } from '../../core/reader/ReaderNightImage';
import { ReaderHeaderFooterSettings, ReaderTypographyField, ReaderTypographyStepper } from './ReaderLayoutSettings';
import { ReaderSettingsStore } from '../../utils/ReaderSettingsStore';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ReaderHaptics } from '../../utils/ReaderHaptics';
import { ReaderInputKind, ReaderInputScopes } from '../../utils/ReaderInputScopes';
import { AppFontSize } from '../../theme/AppFontSize';
import { ReaderTtsCapsule } from './ReaderTtsControls';

const PANEL_HEADER_HEIGHT: number = 56;
const ACTION_ROW_HEIGHT: number = 56;
const MUSIC_CAPSULE_MIN_WIDTH: number = 132;
const MUSIC_CAPSULE_MAX_WIDTH: number = 220;

/**
 * EPUB 文件排版页的菜单，与普通阅读页的布局和逻辑一致：
 * - 顶栏：返回、书名与进度胶囊、“更多操作”（添加书签、使用应用排版、布局元素设置）；
 * - 底栏：快速跳转（章节 / 全书百分比 / 本章页数三种模式，可收起，松手确认后跳转，模式与收起状态和普通阅读页共用）
 *   加目录、阅读设置、日夜三个按钮；关掉快速跳转组件时只剩按钮行；
 * - 右侧亮度条随菜单出现，受“使用快速亮度组件”控制；
 * - 底栏右上方的朗读按钮（受“使用快速朗读组件”控制），朗读中换成朗读胶囊，与普通阅读页相同；
 * - 书里的音频在放或暂停时，底栏左上方一枚音乐胶囊：曲名、进度、播放 / 暂停、关闭。
 * 材质、圆形按钮、进度条、设置行都是阅读页共用组件（沉浸光感）。真正的跳转由页面执行。
 */
@Component
export struct EpubOriginalControls {
  static readonly MIN_ZOOM: number = 50;
  static readonly MAX_ZOOM: number = 250;
  static readonly ZOOM_STEP: number = 10;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('readerUseChapterQuickJump') readerUseChapterQuickJump: boolean = true;
  @StorageLink('readerUseBrightnessQuickAction') readerUseBrightnessQuickAction: boolean = true;
  @StorageLink('readerQuickJumpMode') readerQuickJumpMode: string = 'chapter';
  @StorageLink('readerQuickJumpExpanded') readerQuickJumpExpanded: boolean = false;
  @StorageLink('readerUseTtsQuickAction') readerUseTtsQuickAction: boolean = true;
  @StorageProp('appThemeMode') appThemeMode: string = 'system';
  @Prop darkMode: boolean = false;
  @Prop bookTitle: string = '';
  @Prop progressLabel: string = '';
  @Prop menuVisible: boolean = false;
  @Prop activePanel: string = '';
  @Prop ready: boolean = false;
  /** 正在载入章节或等待跳转确认：进度条不接受操作。 */
  @Prop busy: boolean = false;
  @Prop chapterIndex: number = 0;
  @Prop chapterCount: number = 0;
  @Prop pageIndex: number = 0;
  @Prop pageCount: number = 1;
  @Prop paged: boolean = true;
  @Prop zoom: number = 100;
  @Prop brightnessValue: number = -1;
  @Prop lastManualBrightness: number = 50;
  @Prop brightnessReady: boolean = false;
  @Prop volumeTurnPage: boolean = false;
  @Prop smartKeyTurnPage: boolean = false;
  @Prop smartKeySupported: boolean = false;
  /** 翻页震感按阅读类型存；这里的开关只改小说一类。 */
  @StorageProp('readerPageTurnHapticsScope') pageTurnHapticsScope: number = 0;
  /** 翻页动画，与普通阅读页共用。 */
  @Prop pageTurnAnimation: number = ReaderPageTurnAnimation.SLIDE;
  /** 页眉默认位置（状态栏下方或屏幕顶端），页眉页脚设置里的位置步进以它为基准。 */
  @Prop headerBaseInset: number = 0;
  /** 四侧边距：左、右、上、下，与普通阅读页共用。 */
  @Prop margins: number[] = [18, 18, 18, 18];
  @Prop tapZoneSummary: string = '';
  /** “字体”下拉的选项（书本字体、阅读字体、系统黑体/宋体、上传的字体）与当前选中项。 */
  @Prop fontLabels: string[] = [];
  @Prop fontSelected: number = 0;
  /** 只换正文（保留标题、代码和书里单独设了字体的文字）；否则全部文字都换。 */
  @Prop fontBodyOnly: boolean = true;
  @Prop nightImageMode: string = ReaderNightImage.ORIGINAL;
  /** 朗读会话还在（在念或暂停）：朗读按钮换成胶囊。 */
  @Prop ttsActive: boolean = false;
  @Prop ttsPaused: boolean = false;
  @Prop ttsSubtitle: string = '';
  /** 书里的音频：'' 没在放、loading、playing、paused（见 EpubAudioPlayer）。 */
  @Prop musicState: string = '';
  @Prop musicTitle: string = '';
  /** “0:04 / 3:33”；还不知道时长时为空。 */
  @Prop musicTime: string = '';
  /** 智感握姿：-1 左手、1 右手、0 未知（朗读控件按默认靠右）。 */
  @Prop holdingHandSide: number = 0;
  @State viewportWidth: number = 360;
  @State viewportHeight: number = 720;
  @State showMore: boolean = false;
  @State sliderActive: boolean = false;
  @State previewValue: number = 0;
  @State tooltipVisible: boolean = false;
  /** 页面记下的撤销目标章，-1 表示没有可撤销的跳转。 */
  @Prop quickJumpUndoChapter: number = -1;
  private dayNightLongPressed: boolean = false;
  @BuilderParam tocContent: () => void = this.emptyContent;
  titleOf: (index: number) => string = (index: number): string => `第${index + 1}章`;
  onClose: () => void = (): void => {};
  onPanelChange: (panel: string) => void = (_panel: string): void => {};
  /** 快速跳转松手：mode 为 chapter / percent / page，value 为章节序号、全书百分比或本章页码。 */
  onQuickJump: (mode: string, value: number) => void = (_mode: string, _value: number): void => {};
  onQuickJumpUndo: () => void = (): void => {};
  onStep: (direction: number) => void = (_direction: number): void => {};
  onPagedChange: (paged: boolean) => void = (_paged: boolean): void => {};
  onZoomChange: (zoom: number) => void = (_zoom: number): void => {};
  onPageTurnAnimationChange: (type: number) => void = (_type: number): void => {};
  onMarginsChange: (left: number, right: number, top: number, bottom: number) => void =
    (_left: number, _right: number, _top: number, _bottom: number): void => {};
  onTapZones: () => void = (): void => {};
  onFontSelect: (index: number) => void = (_index: number): void => {};
  onFontBodyOnlyChange: (bodyOnly: boolean) => void = (_bodyOnly: boolean): void => {};
  onNightImageModeChange: (mode: string) => void = (_mode: string): void => {};
  onReaderChromeChange: (headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string) => void =
    (_headerEnabled: boolean, _footerEnabled: boolean, _infoBarConfig: string): void => {};
  /** 与普通阅读页的日夜按钮相同：点按在日间、夜间之间切换（应用全局），长按改为跟随系统。 */
  onDayNight: () => void = (): void => {};
  onAutoMode: () => void = (): void => {};
  onBrightnessChange: (value: number, persist: boolean) => void = (_value: number, _persist: boolean): void => {};
  onLayoutElements: () => void = (): void => {};
  onAddBookmark: () => void = (): void => {};
  onVolumeTurnChange: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onSmartKeyTurnChange: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onAppLayout: () => void = (): void => {};
  /** 打开朗读面板（没在念就从当前屏开始念）。 */
  onTtsOpen: () => void = (): void => {};
  onTtsToggle: () => void = (): void => {};
  onTtsStop: () => void = (): void => {};
  onMusicToggle: () => void = (): void => {};
  onMusicStop: () => void = (): void => {};

  @Builder
  emptyContent() {}

  private resetPreview(): void {
    this.sliderActive = false;
    this.tooltipVisible = false;
  }

  private panelWidth(): number {
    return EpubOriginalControls.panelWidthFor(this.viewportWidth);
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

  /** 与普通阅读页 readerBottomMenuPanelHeight 相同：快速跳转加 58 的按钮行，关掉时只有按钮行。 */
  private bottomBarHeight(): number {
    return this.readerUseChapterQuickJump && !this.activePanel ? this.quickJumpHeight() + 58 : ACTION_ROW_HEIGHT;
  }

  private panelHeight(): number {
    const desired = this.activePanel === 'toc' ?
      (this.chapterCount > 0 ? Math.min(520, PANEL_HEADER_HEIGHT + this.chapterCount * 56 + 12) : 520) :
      PANEL_HEADER_HEIGHT + (this.smartKeySupported ? 5 : 4) * 64 + 56 + 16;
    const available = this.viewportHeight - this.statusBarHeight - this.bottomInset() - ACTION_ROW_HEIGHT - 96;
    return Math.max(PANEL_HEADER_HEIGHT, Math.min(desired, available));
  }

  /** 与普通阅读页 readerTocPanelHeight 相同：屏高的 81%，矮窗口里不低于 280。页面按同样的算法给面板定尺寸。 */
  private tocPanelHeight(): number {
    return EpubOriginalControls.tocPanelHeight(this.viewportHeight, this.bottomInset());
  }

  static tocPanelHeight(viewportHeight: number, bottomInset: number): number {
    const available = Math.max(1, viewportHeight - bottomInset - ACTION_ROW_HEIGHT - 4 - 12);
    return Math.min(available, Math.max(Math.min(280, available), viewportHeight * 0.81));
  }

  static panelWidthFor(viewportWidth: number): number {
    const available = Math.max(1, viewportWidth - 36);
    return viewportWidth >= 600 ? Math.min(available, Math.min(520, Math.max(320, viewportWidth * 0.52))) : available;
  }

  private titleCapsuleWidth(): number {
    return Math.max(1, Math.min(560, this.viewportWidth - 36 - 80 - 24));
  }

  private mode(): string {
    return ReaderQuickJumpModel.normalizeMode(this.readerQuickJumpMode);
  }

  /** 与 ReaderInfoBarText.bookPercent 相同：每章等权，章内按 (页码 + 1) / 页数。 */
  private bookPercent(): number {
    const count = Math.max(1, this.chapterCount);
    const pages = Math.max(1, this.pageCount);
    const inChapter = Math.min(1, (Math.max(0, this.pageIndex) + 1) / pages);
    return Math.max(0, Math.min(100, (Math.max(0, Math.min(this.chapterIndex, count - 1)) + inChapter) / count * 100));
  }

  private sliderValue(): number {
    if (this.sliderActive) return this.previewValue;
    const mode = this.mode();
    if (mode === 'percent') return this.bookPercent();
    return mode === 'page' ? this.pageIndex : this.chapterIndex;
  }

  private previewChapter(): number {
    const mode = this.mode();
    if (mode === 'chapter') return Math.max(0, Math.min(this.chapterCount - 1, Math.round(this.sliderValue())));
    if (mode === 'percent') return ReaderQuickJumpModel.fromPercent(this.sliderValue(), this.chapterCount).chapterIndex;
    return this.chapterIndex;
  }

  private valueLabel(): string {
    if (this.chapterCount === 0) return '暂无章节';
    const mode = this.mode();
    if (mode === 'percent') return `${this.sliderValue().toFixed(1)}% · 全书`;
    if (mode === 'page') return `${Math.round(this.sliderValue()) + 1} / ${Math.max(1, this.pageCount)} 页`;
    return `${Math.round(this.sliderValue()) + 1} / ${this.chapterCount} 章`;
  }

  private onSlider(value: number, mode: SliderChangeMode): void {
    if (this.busy || !this.ready || this.chapterCount === 0) return;
    const jumpMode = this.mode();
    this.previewValue = jumpMode === 'percent' ? ReaderQuickJumpModel.clampPercent(value) :
      Math.max(0, Math.min(Math.round(value), (jumpMode === 'page' ? Math.max(1, this.pageCount) : this.chapterCount) - 1));
    this.sliderActive = true;
    this.tooltipVisible = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.tooltipVisible = false;
      const target = this.previewValue;
      this.onQuickJump(jumpMode, target);
      this.sliderActive = false;
    }
  }

  private setMode(mode: string): void {
    if (this.busy) return;
    this.resetPreview();
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.readerQuickJumpMode = ReaderQuickJumpModel.normalizeMode(mode);
    });
    ReaderSettingsStore.saveLayoutElementSettings(getContext(this),
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_USE_TTS_QUICK_ACTION) ?? true,
      this.readerUseChapterQuickJump,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_USE_AUTO_SCROLL_QUICK_ACTION) ?? true,
      this.readerQuickJumpMode).catch((error: Error) => {
      console.error('保存快速跳转模式失败:', error);
      HdsFeedback.showToast('跳转模式保存失败');
    });
  }

  private setExpanded(expanded: boolean): void {
    if (this.readerQuickJumpExpanded === expanded) return;
    animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.readerQuickJumpExpanded = expanded;
    });
  }

  private selectPanel(panel: string): void {
    this.resetPreview();
    this.onPanelChange(this.activePanel === panel ? '' : panel);
  }

  private panelTransition(): TransitionEffect {
    return TransitionEffect.translate({ y: 28 }).combine(TransitionEffect.opacity(0))
      .animation({ duration: 240, curve: Curve.EaseOut });
  }

  /** 浮层底色与普通阅读页 readerSolidPanelColor 相同，不随应用主题的卡片色变。 */
  private solidPanelColor(): string {
    return this.darkMode ? '#191B1F' : '#FFFFFF';
  }

  private scrimColor(): string {
    return this.darkMode ? '#47000000' : '#1F000000';
  }

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
  roundButton(icon: Resource, label: string, action: () => void) {
    ImmersiveBackButton({ icon: icon, iconOffsetX: 0,
      iconColor: ThemeRuntime.primaryTextColor(this.darkMode), darkMode: this.darkMode,
      buttonSize: 40, containerWidth: 40, containerHeight: 56, startInset: 0,
      materialScale: 0.83, compactLayout: true, accessibilityLabel: label, onBack: action })
  }

  @Builder
  moreMenu() {
    Column() {
      PopupMenuAction($r('sys.symbol.bookmark'), '添加书签', ThemeRuntime.primaryTextColor(this.darkMode), () => {
        this.showMore = false;
        this.onAddBookmark();
      })
      PopupMenuAction($r('sys.symbol.play'), this.ttsActive ? '朗读控制' : '开始朗读',
        ThemeRuntime.primaryTextColor(this.darkMode), () => {
          this.showMore = false;
          this.onTtsOpen();
        })
      PopupMenuAction($r('sys.symbol.book'), '使用应用排版', ThemeRuntime.primaryTextColor(this.darkMode), () => {
        this.showMore = false;
        this.onAppLayout();
      })
      PopupMenuAction($r('sys.symbol.square_grid_2x2'), '布局元素设置', ThemeRuntime.primaryTextColor(this.darkMode),
        () => {
          this.showMore = false;
          this.onLayoutElements();
        })
    }
    .width(220)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  topMenu() {
    Row() {
      this.roundButton($r('sys.symbol.chevron_left'), '返回书架', (): void => this.onClose())
      ReaderTitleCapsule({ capsuleWidth: this.titleCapsuleWidth(), darkMode: this.darkMode }) {
        Column({ space: 1 }) {
          Text(this.bookTitle).fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode)).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.progressLabel)
            .fontSize(AppFontSize.MICRO + 1).fontColor(ThemeRuntime.subTextColor(this.darkMode)).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').height('100%').padding({ left: 14, right: 14 })
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
          .accessibilityText(`${this.bookTitle}，${this.progressLabel}，点按打开目录`)
          .onClick((): void => { if (this.ready) this.selectPanel('toc'); })
      }
      Stack() {
        this.roundButton($r('sys.symbol.more'), '更多操作', (): void => { this.showMore = !this.showMore; })
      }
      .bindPopup(this.showMore, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
        this.moreMenu()
      }, Placement.BottomRight, this.darkMode, ThemeRuntime.accentColor(this.darkMode), (): void => {
        this.showMore = false;
      }))
    }.width('100%').padding({ left: 18, right: 18, top: this.statusBarHeight + 10 })
      .justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Center)
      .position({ x: 0, y: 0 }).transition(ReaderChromeMotion.top(this.topBarBottom()))
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  /** 与普通阅读页底栏的 readerHdsMenuItem 相同：只有图标，点按没有胶囊底色。 */
  @Builder
  actionIcon(icon: Resource, label: string, action: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon).fontSize(24).fontColor([ThemeRuntime.primaryTextColor(this.darkMode)])
      }.width(32).height(32)
    }.layoutWeight(1).height(48).enabled(this.ready).opacity(this.ready ? 1 : 0.32)
      .accessibilityText(label).onClick(action)
  }

  private dayNightIcon(): Resource {
    if (this.appThemeMode === 'system') return $r('sys.symbol.circle_lefthalf_inset_filled');
    return this.appThemeMode === 'dark' ? $r('sys.symbol.moon') : $r('sys.symbol.sun_max');
  }

  @Builder
  dayNightButton() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.dayNightIcon()).fontSize(24).fontColor([ThemeRuntime.primaryTextColor(this.darkMode)])
      }.width(32).height(32)
    }.layoutWeight(1).height(48).enabled(this.ready).opacity(this.ready ? 1 : 0.32)
      .accessibilityText('切换日间或夜间模式，长按跟随系统')
      .onClick((): void => {
        if (this.dayNightLongPressed) {
          this.dayNightLongPressed = false;
          return;
        }
        this.onDayNight();
      })
      .gesture(LongPressGesture({ duration: 600, repeat: false }).onAction((): void => {
        this.dayNightLongPressed = true;
        this.onAutoMode();
      }))
  }

  @Builder
  actionRow(rowHeight: number = ACTION_ROW_HEIGHT) {
    Row() {
      this.actionIcon($r('sys.symbol.list_bullet'), '目录', (): void => this.selectPanel('toc'))
      this.actionIcon($r('sys.symbol.gearshape'), '阅读设置', (): void => this.selectPanel('settings'))
      this.dayNightButton()
    }.width('100%').height(rowHeight).padding({ left: 12, right: 12 })
  }

  @Builder
  quickJump() {
    ReaderQuickJumpContent({
      mode: this.mode(),
      chapterLabel: '章节',
      chapterUnit: '章',
      value: this.sliderValue(),
      chapterCount: this.chapterCount,
      pageCount: Math.max(1, this.pageCount),
      currentChapter: this.chapterIndex,
      valueLabel: this.busy ? '正在定位…' : this.valueLabel(),
      busy: this.busy || !this.ready,
      dark: this.darkMode,
      textColor: ThemeRuntime.primaryTextColor(this.darkMode),
      subTextColor: ThemeRuntime.subTextColor(this.darkMode),
      accentColor: ThemeRuntime.accentColor(this.darkMode),
      trackColor: ThemeRuntime.dividerColor(this.darkMode),
      thumbColor: this.solidPanelColor(),
      expanded: this.readerQuickJumpExpanded,
      headerHeight: this.headerHeight(),
      onModeChange: (mode: string): void => this.setMode(mode),
      onChange: (value: number, mode: SliderChangeMode): void => this.onSlider(value, mode),
      onStep: (direction: number): void => {
        this.resetPreview();
        this.onStep(direction);
      },
      onExpandedChange: (expanded: boolean): void => this.setExpanded(expanded),
      onSlideCancel: (): void => this.resetPreview()
    })
  }

  @Builder
  bottomMenu() {
    Column() {
      if (this.readerUseChapterQuickJump && !this.activePanel) {
        ReaderMaterialPanel({ panelWidth: this.panelWidth(), panelHeight: this.bottomBarHeight(),
          cornerRadius: 28, darkMode: this.darkMode, fallbackColor: this.solidPanelColor() }) {
          Column() {
            Column() { this.quickJump() }.width('100%').height(this.quickJumpHeight())
            Divider().strokeWidth(0.5).color(ThemeRuntime.dividerColor(this.darkMode)).margin({ left: 20, right: 20 })
            this.actionRow()
          }.width('100%').height('100%').justifyContent(FlexAlign.End)
        }
      } else if (ImmersiveMaterialRuntime.supportsHds()) {
        // 只剩操作按钮时与普通阅读页单独的操作栏相同：48vp 高的薄底色悬浮胶囊，带投影。
        ReaderFloatingMaterialBar({ barWidth: this.panelWidth(), fallbackColor: this.solidPanelColor(),
          darkMode: this.darkMode }) {
          this.actionRow(48)
        }
      } else {
        ReaderMaterialPanel({ panelWidth: this.panelWidth(), panelHeight: this.bottomBarHeight(),
          cornerRadius: 28, darkMode: this.darkMode, fallbackColor: this.solidPanelColor() }) {
          this.actionRow()
        }
      }
    }.width(this.panelWidth()).height(this.bottomBarHeight()).justifyContent(FlexAlign.Center)
      .position({ x: this.panelLeft(), y: '100%' })
      .translate({ y: -(this.bottomInset() + this.bottomBarHeight()) })
      .transition(ReaderChromeMotion.bottom(this.bottomInset() + this.bottomBarHeight()))
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  /** 朗读按钮与胶囊停在底栏上方（与普通阅读页 readerTtsQuickActionLeft 相同：默认靠右，左手握持时靠左）。 */
  private ttsAnchorTop(height: number): number {
    return this.viewportHeight - this.bottomInset() - this.bottomBarHeight() - 14 - height;
  }

  private ttsOnLeft(): boolean {
    return this.holdingHandSide < 0;
  }

  /** 朗读控件的左边：左手握持贴屏幕左边距（大屏底栏靠右时也一样），否则对齐底栏右端。 */
  private ttsLeft(width: number): number {
    if (this.ttsOnLeft()) return Math.min(18, this.panelLeft());
    return Math.max(8, this.panelLeft() + this.panelWidth() - width);
  }

  /** 音乐胶囊与朗读控件分占两边：朗读在左时音乐靠底栏右端。 */
  private musicLeft(): number {
    if (!this.ttsOnLeft() || !this.readerUseTtsQuickAction) return this.panelLeft();
    return this.panelLeft() + this.panelWidth() - this.musicCapsuleWidth();
  }

  @Builder
  ttsQuickAction() {
    if (this.ttsActive) {
      ReaderTtsCapsule({
        title: this.ttsPaused ? '已暂停' : '朗读中',
        subtitle: this.ttsSubtitle,
        paused: this.ttsPaused,
        playbackKey: `epub_tts_capsule_${this.ttsPaused}`,
        panelColor: this.solidPanelColor(),
        panelBorderColor: this.darkMode ? '#26FFFFFF' : '#14000000',
        panelShadowColor: this.darkMode ? '#66000000' : '#1F000000',
        dark: this.darkMode,
        textColor: ThemeRuntime.primaryTextColor(this.darkMode),
        subTextColor: ThemeRuntime.subTextColor(this.darkMode),
        accentColor: ThemeRuntime.accentColor(this.darkMode),
        onOpen: (): void => this.onTtsOpen(),
        onToggle: (): void => this.onTtsToggle(),
        onClose: (): void => this.onTtsStop()
      })
        .position({ x: 0, y: 0 })
        .translate({
          x: this.ttsLeft(ReaderTtsCapsule.WIDTH),
          y: this.ttsAnchorTop(ReaderTtsCapsule.HEIGHT)
        })
        .transition(ReaderChromeMotion.bottom(this.bottomInset() + this.bottomBarHeight() + ReaderTtsCapsule.HEIGHT))
    } else {
      Stack() {
        ImmersiveBackButton({ icon: $r('sys.symbol.play'), iconOffsetX: 0,
          iconColor: ThemeRuntime.primaryTextColor(this.darkMode), darkMode: this.darkMode,
          buttonSize: 48, containerWidth: 48, containerHeight: 48, startInset: 0, compactLayout: true,
          accessibilityLabel: '开始朗读', onBack: (): void => this.onTtsOpen() })
      }
      .width(48)
      .height(48)
      .position({ x: this.ttsLeft(48), y: this.ttsAnchorTop(48) })
      .transition(ReaderChromeMotion.bottom(this.bottomInset() + this.bottomBarHeight() + 48))
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    }
  }

  /** 音乐胶囊的宽度：右边让出朗读按钮或朗读胶囊。 */
  private musicCapsuleWidth(): number {
    const tts = !this.readerUseTtsQuickAction ? 0 : (this.ttsActive ? ReaderTtsCapsule.WIDTH : 48);
    return Math.max(MUSIC_CAPSULE_MIN_WIDTH, Math.min(MUSIC_CAPSULE_MAX_WIDTH, this.panelWidth() - tts - 12));
  }

  @Builder
  musicQuickAction() {
    Column() {
      ReaderMaterialPanel({
        panelWidth: this.musicCapsuleWidth(),
        panelHeight: ReaderTtsCapsule.HEIGHT,
        cornerRadius: ReaderTtsCapsule.HEIGHT / 2,
        darkMode: this.darkMode,
        fallbackColor: this.solidPanelColor()
      }) {
        Row({ space: 6 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle().width(30).height(30).fill(ThemeRuntime.accentColor(this.darkMode))
            SymbolGlyph($r('sys.symbol.music')).fontSize(15).fontColor(['#FFFFFF'])
          }
          .width(30)
          .height(30)

          Column({ space: 1 }) {
            Text(this.musicTitle || '书中音乐')
              .fontSize(AppFontSize.CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.musicState === 'paused' ? `已暂停 ${this.musicTime}` :
              (this.musicState === 'loading' ? '准备中' : this.musicTime))
              .fontSize(9)
              .fontColor(ThemeRuntime.subTextColor(this.darkMode))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          SymbolGlyph(this.musicState === 'paused' ? $r('sys.symbol.play') : $r('sys.symbol.pause'))
            .id(`epub_music_capsule_${this.musicState === 'paused'}`)
            .fontSize(17)
            .fontColor([ThemeRuntime.primaryTextColor(this.darkMode)])
            .width(28)
            .height(34)
            .accessibilityText(this.musicState === 'paused' ? '继续播放' : '暂停')
            .onClick((): void => this.onMusicToggle())
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([ThemeRuntime.subTextColor(this.darkMode)])
            .width(24)
            .height(34)
            .accessibilityText('停止播放')
            .onClick((): void => this.onMusicStop())
        }
        .width('100%')
        .height('100%')
        .padding({ left: 8, right: 4 })
      }
    }
    .width(this.musicCapsuleWidth())
    .height(ReaderTtsCapsule.HEIGHT)
    .borderRadius(ReaderTtsCapsule.HEIGHT / 2)
    .position({ x: this.musicLeft(), y: this.ttsAnchorTop(ReaderTtsCapsule.HEIGHT) })
    .transition(ReaderChromeMotion.bottom(this.bottomInset() + this.bottomBarHeight() + ReaderTtsCapsule.HEIGHT))
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  private capsuleVisible(): boolean {
    return !this.activePanel && (this.tooltipVisible || this.quickJumpUndoChapter >= 0);
  }

  private capsuleWidth(): number {
    return Math.max(200, Math.min(360, this.panelWidth() - 32));
  }

  /** 快速跳转胶囊，与普通阅读页相同：拖动时显示目标章名与读数，跳转后留着撤销键。 */
  @Builder
  quickJumpCapsule() {
    Column() {
      ReaderQuickJumpCapsule({
        title: this.titleOf(this.tooltipVisible ? this.previewChapter() : this.chapterIndex),
        detail: this.valueLabel(),
        canUndo: this.quickJumpUndoChapter >= 0 && !this.tooltipVisible && !this.busy,
        undoLabel: this.quickJumpUndoChapter >= 0 ?
          `回到跳转前的位置，${this.titleOf(this.quickJumpUndoChapter)}` : '回到跳转前的位置',
        capsuleWidth: this.capsuleWidth(),
        darkMode: this.darkMode,
        fallbackColor: this.solidPanelColor(),
        textColor: ThemeRuntime.primaryTextColor(this.darkMode),
        subTextColor: ThemeRuntime.subTextColor(this.darkMode),
        dividerColor: ThemeRuntime.dividerColor(this.darkMode),
        onUndo: (): void => this.onQuickJumpUndo()
      })
    }.width(this.capsuleWidth()).height(READER_QUICK_JUMP_CAPSULE_HEIGHT)
      .position({ x: this.panelLeft() + (this.panelWidth() - this.capsuleWidth()) / 2, y: '100%' })
      .translate({ y: -(this.bottomInset() + this.bottomBarHeight() + 10 + READER_QUICK_JUMP_CAPSULE_HEIGHT) })
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
        .animation({ duration: 180, curve: Curve.EaseOut }))
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  @Builder
  brightnessControl() {
    ReaderBrightnessControl({
      value: this.brightnessValue, lastManualValue: this.lastManualBrightness,
      panelHeight: this.brightnessHeight(), ready: this.brightnessReady,
      dark: this.darkMode, panelColor: this.solidPanelColor(),
      textColor: ThemeRuntime.primaryTextColor(this.darkMode),
      accentColor: ThemeRuntime.accentColor(this.darkMode), trackColor: ThemeRuntime.dividerColor(this.darkMode),
      thumbColor: this.solidPanelColor(),
      onChange: (value: number, persist: boolean): void => this.onBrightnessChange(value, persist)
    })
      .position({ x: Math.max(0, this.viewportWidth - ReaderBrightnessControl.WIDTH - 12), y: this.brightnessTop() })
      .transition(ReaderChromeMotion.side(ReaderBrightnessControl.WIDTH + 12))
  }

  @Builder
  panelHeader() {
    Row() {
      Text(this.activePanel === 'toc' ? '目录' : '阅读设置')
        .fontSize(AppFontSize.TITLE).fontWeight(FontWeight.Bold).fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        .layoutWeight(1).maxLines(1)
      this.roundButton($r('sys.symbol.xmark'), '关闭面板', (): void => this.onPanelChange(''))
    }.width('100%').height(PANEL_HEADER_HEIGHT).padding({ left: 24, right: 10 })
  }

  /** 边距调节控件要整组初值（见 ReaderTypographyField），只有四侧边距这几格有意义。 */
  private marginStepperValues(): number[] {
    const values: number[] = [];
    for (let field = 0; field < ReaderTypographyField.COUNT; field++) values.push(0);
    values[ReaderTypographyField.MARGIN_LEFT] = this.margins[0] ?? 18;
    values[ReaderTypographyField.MARGIN_RIGHT] = this.margins[1] ?? 18;
    values[ReaderTypographyField.MARGIN_TOP] = this.margins[2] ?? 18;
    values[ReaderTypographyField.MARGIN_BOTTOM] = this.margins[3] ?? 18;
    return values;
  }

  @Builder
  settingsContent() {
    Scroll() {
      Column({ space: 8 }) {
        ReaderSettingSelectRow({ title: '翻页方式', description: '左右翻页按屏分页；上下滚动整章连续',
          options: [{ value: '左右翻页' }, { value: '上下滚动' }], selected: this.paged ? 0 : 1,
          textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
          accentColor: ThemeRuntime.accentColor(this.darkMode), dark: this.darkMode,
          menuColor: this.solidPanelColor(),
          onSelect: (index: number): void => this.onPagedChange(index === 0) })
        if (this.paged) {
          // 与普通阅读页同一个设置、同一组选项；文件排版用截图播放同样的动画。
          ReaderSettingSelectRow({ title: '翻页动画', description: '与应用排版共用',
            options: ReaderPageTurnAnimation.labels().map((label: string): SelectOption => ({ value: label })),
            selected: Math.max(0, ReaderPageTurnAnimation.types().indexOf(this.pageTurnAnimation)),
            textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
            accentColor: ThemeRuntime.accentColor(this.darkMode), dark: this.darkMode,
            menuColor: this.solidPanelColor(),
            onSelect: (index: number): void => {
              const types = ReaderPageTurnAnimation.types();
              if (index >= 0 && index < types.length) this.onPageTurnAnimationChange(types[index]);
            } })
        }
        // 与普通阅读页排版里的同一组边距、同一个调节控件，只列出四侧边距。
        ReaderTypographyStepper({
          initialValues: this.marginStepperValues(),
          fields: [ReaderTypographyField.MARGIN_LEFT, ReaderTypographyField.MARGIN_RIGHT,
            ReaderTypographyField.MARGIN_TOP, ReaderTypographyField.MARGIN_BOTTOM],
          dark: this.darkMode,
          textColor: ThemeRuntime.primaryTextColor(this.darkMode),
          subTextColor: ThemeRuntime.subTextColor(this.darkMode),
          accentColor: ThemeRuntime.accentColor(this.darkMode),
          inputColor: this.solidPanelColor(),
          menuColor: this.solidPanelColor(),
          onChange: (values: number[]): void => this.onMarginsChange(values[ReaderTypographyField.MARGIN_LEFT],
            values[ReaderTypographyField.MARGIN_RIGHT], values[ReaderTypographyField.MARGIN_TOP],
            values[ReaderTypographyField.MARGIN_BOTTOM])
        })
        ReaderSettingSelectRow({ title: '字体', description: '只换字形，字号与排版仍按书的样式',
          options: this.fontLabels.map((label: string): SelectOption => ({ value: label })),
          selected: this.fontSelected,
          textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
          accentColor: ThemeRuntime.accentColor(this.darkMode), dark: this.darkMode,
          menuColor: this.solidPanelColor(),
          onSelect: (index: number): void => this.onFontSelect(index) })
        if (this.fontSelected > 0) {
          ReaderSettingSelectRow({ title: '替换范围',
            description: this.fontBodyOnly ? '标题、代码和书里单独设了字体的文字保持原样' : '书里所有文字都换成这款字体',
            options: [{ value: '只换正文' }, { value: '全部文字' }], selected: this.fontBodyOnly ? 0 : 1,
            textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
            accentColor: ThemeRuntime.accentColor(this.darkMode), dark: this.darkMode,
            menuColor: this.solidPanelColor(),
            onSelect: (index: number): void => this.onFontBodyOnlyChange(index === 0) })
        }
        // 与普通阅读页同一个设置。
        ReaderSettingSelectRow({ title: '夜间图片', description: ReaderNightImage.DESCRIPTION,
          options: ReaderNightImage.LABELS.map((label: string): SelectOption => ({ value: label })),
          selected: Math.max(0, ReaderNightImage.VALUES.indexOf(this.nightImageMode)),
          textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
          accentColor: ThemeRuntime.accentColor(this.darkMode), dark: this.darkMode,
          menuColor: this.solidPanelColor(),
          onSelect: (index: number): void => {
            if (index >= 0 && index < ReaderNightImage.VALUES.length) this.onNightImageModeChange(ReaderNightImage.VALUES[index]);
          } })
        ReaderSettingActionRow({ title: '点击区域动作', description: this.tapZoneSummary,
          actionText: '配置', textColor: ThemeRuntime.primaryTextColor(this.darkMode),
          subTextColor: ThemeRuntime.subTextColor(this.darkMode), buttonColor: ThemeRuntime.accentColor(this.darkMode),
          buttonTextColor: ThemeRuntime.onAccentColor(), onAction: this.onTapZones })
        // 与排版设置里的步进项（如“页脚不透明度”）同一种写法：一行，左边标题，右边减、数值、加。
        Row({ space: 12 }) {
          ReaderSettingLabel({ title: '字号缩放', description: '按比例放大或缩小书里的文字',
            textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode) })
          ImmersiveBackButton({ icon: $r('sys.symbol.minus'), accessibilityLabel: '减小字号缩放',
            iconColor: ThemeRuntime.primaryTextColor(this.darkMode), disabledIconColor: ThemeRuntime.subTextColor(this.darkMode),
            darkMode: this.darkMode, buttonEnabled: this.zoom > EpubOriginalControls.MIN_ZOOM,
            buttonSize: 34, containerWidth: 34, containerHeight: 34, startInset: 0, compactLayout: true,
            onBack: (): void => this.onZoomChange(this.zoom - EpubOriginalControls.ZOOM_STEP) })
          Text(`${this.zoom}%`)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .width(52)
            .textAlign(TextAlign.Center)
          ImmersiveBackButton({ icon: $r('sys.symbol.plus'), accessibilityLabel: '增大字号缩放',
            iconColor: ThemeRuntime.primaryTextColor(this.darkMode), disabledIconColor: ThemeRuntime.subTextColor(this.darkMode),
            darkMode: this.darkMode, buttonEnabled: this.zoom < EpubOriginalControls.MAX_ZOOM,
            buttonSize: 34, containerWidth: 34, containerHeight: 34, startInset: 0, compactLayout: true,
            onBack: (): void => this.onZoomChange(this.zoom + EpubOriginalControls.ZOOM_STEP) })
        }
        .width('100%')
        .constraintSize({ minHeight: 56 })
        .alignItems(VerticalAlign.Center)
        // 与普通阅读页的阅读设置同一个开关：在这里改了，回到普通阅读页也是这个设置。
        ReaderSettingSwitchRow({ title: '音量键翻页', description: '音量上/下键翻到上一页/下一页，只改小说',
          checked: this.volumeTurnPage, textColor: ThemeRuntime.primaryTextColor(this.darkMode),
          subTextColor: ThemeRuntime.subTextColor(this.darkMode), onChange: this.onVolumeTurnChange })
        if (this.smartKeySupported) {
          ReaderSettingSwitchRow({ title: '智控键翻页', description: '智控键上滑/下滑翻到上一页/下一页，只改小说',
            checked: this.smartKeyTurnPage, textColor: ThemeRuntime.primaryTextColor(this.darkMode),
            subTextColor: ThemeRuntime.subTextColor(this.darkMode), onChange: this.onSmartKeyTurnChange })
        }
        ReaderSettingSwitchRow({ title: '翻页震感', description: '翻页时轻震一下，只改小说',
          checked: ReaderInputScopes.includes(this.pageTurnHapticsScope, ReaderInputKind.NOVEL),
          textColor: ThemeRuntime.primaryTextColor(this.darkMode), subTextColor: ThemeRuntime.subTextColor(this.darkMode),
          onChange: (checked: boolean): void => {
            ReaderHaptics.toggle(this.getUIContext().getHostContext() as Context, ReaderInputKind.NOVEL, checked)
              .catch((e: Error) => console.error('[EpubOriginal] save haptics failed:', e));
          } })
        ReaderSettingActionRow({ title: '使用应用排版', description: '改回阅读主题、字体与仿真翻页排版这本书',
          actionText: '切换', textColor: ThemeRuntime.primaryTextColor(this.darkMode),
          subTextColor: ThemeRuntime.subTextColor(this.darkMode), buttonColor: ThemeRuntime.accentColor(this.darkMode),
          buttonTextColor: ThemeRuntime.onAccentColor(), onAction: this.onAppLayout })
        Text('页眉页脚').fontSize(AppFontSize.BODY).fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.primaryTextColor(this.darkMode)).width('100%').margin({ top: 8 })
        // 与普通阅读页“排版 · 页眉页脚”同一个设置组，改动两边同时生效。
        ReaderHeaderFooterSettings({
          headerBaseInset: this.headerBaseInset,
          dark: this.darkMode,
          modeDark: this.darkMode,
          textColor: ThemeRuntime.primaryTextColor(this.darkMode),
          subTextColor: ThemeRuntime.subTextColor(this.darkMode),
          accentColor: ThemeRuntime.accentColor(this.darkMode),
          switchColor: ThemeRuntime.accentColor(this.darkMode),
          menuColor: this.solidPanelColor(),
          onChanged: (headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string): void =>
            this.onReaderChromeChange(headerEnabled, footerEnabled, infoBarConfig)
        })
        Text('文件排版按书本身的样式显示，阅读主题、字号和行距在这里不生效；边距、点击区域、页眉页脚与翻页动画和应用排版共用设置。应用处于夜间模式时，页面整体转成深色，图片按“夜间图片”处理。').fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode)).width('100%').margin({ top: 4 })
      }.width('100%').padding({ left: 24, right: 24, bottom: 16 }).alignItems(HorizontalAlign.Start)
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
  }

  @Builder
  floatingPanel() {
    Column() {
      ReaderMaterialPanel({ panelWidth: this.panelWidth(), panelHeight: this.panelHeight(), cornerRadius: 28,
        darkMode: this.darkMode, fallbackColor: this.solidPanelColor() }) {
        Column() {
          this.panelHeader()
          if (this.activePanel === 'toc') {
            Column() { this.tocContent() }.width('100%').layoutWeight(1)
          } else {
            this.settingsContent()
          }
        }.width('100%').height('100%')
      }
    }.position({ x: this.panelLeft(), y: '100%' })
      .translate({ y: -(this.bottomInset() + ACTION_ROW_HEIGHT + 12 + this.panelHeight()) })
      .transition(this.panelTransition())
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.menuVisible) {
        // 菜单开着时整层遮住网页：点空白处只收起菜单或面板，不会再被网页当成翻页点击。
        Column().width('100%').height('100%')
          .backgroundColor(this.activePanel ? this.scrimColor() : Color.Transparent)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
          .onClick((): void => this.onPanelChange(this.activePanel ? '' : 'close'))
        this.topMenu()
        if (this.ready) {
          this.bottomMenu()
          if (this.capsuleVisible()) this.quickJumpCapsule()
          if (this.activePanel === 'toc') {
            // 目录 / 书签面板是页面传进来的阅读页通用面板（ReaderTocPanel），自带材质与标题，这里只负责摆放。
            Column() { this.tocContent() }
              .position({ x: this.panelLeft(), y: '100%' })
              .translate({ y: -(this.bottomInset() + ACTION_ROW_HEIGHT + 4 + this.tocPanelHeight()) })
              .transition(this.panelTransition())
              .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
          } else if (this.activePanel) {
            this.floatingPanel()
          }
          if (!this.activePanel && this.readerUseBrightnessQuickAction && this.brightnessHeight() >= 132) {
            this.brightnessControl()
          }
          if (!this.activePanel && !this.capsuleVisible() && this.readerUseTtsQuickAction) {
            this.ttsQuickAction()
          }
          if (!this.activePanel && !this.capsuleVisible() && this.musicState) {
            this.musicQuickAction()
          }
        }
      }
    }.width('100%').height('100%')
    // 菜单开着时挡住下面的网页，否则同一次点击会先被遮罩收起菜单、再被网页当成点按把菜单唤出来；
    // 菜单收起时这一层是空的，让触摸全部交给网页。
    .hitTestBehavior(this.menuVisible ? HitTestMode.Default : HitTestMode.Transparent)
      .onSizeChange((_before: SizeOptions, after: SizeOptions): void => {
        this.viewportWidth = Number(after.width); this.viewportHeight = Number(after.height);
      })
  }
}
