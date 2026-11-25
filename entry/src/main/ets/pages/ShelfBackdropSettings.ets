import display from '@ohos.display';
import { promptAction } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeIds, ThemePack } from '../theme/ThemeModels';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { ThemeDetailScene } from '../components/theme/ThemeDetailScene';
import { ReaderSettingTabStrip } from '../components/reader/ReaderSettingGroups';
import { ReaderBackgroundDisplayControl } from '../components/reader/ReaderBackgroundDisplayControl';
import { ReaderBackgroundDisplay } from '../utils/ReaderBackgroundDisplay';
import { ReaderRasterAssets } from '../core/reader/ReaderRasterAssets';
import { ShelfBackdropConfig, ShelfBackdropLook, ShelfBackdropStore } from '../utils/ShelfBackdropStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SHELF_BACKDROP_LAYOUTS, SHELF_BACKDROP_LAYOUT_NAMES } from '../theme/share/ThemePackageFormat';
import { ThemedDialog } from '../utils/ThemedDialog';

/**
 * 书架设置 › 书架背景：跟随主题，或单独上传一张铺在顶部 / 全屏。
 * 顶部是书架实景预览（主题详情那套 ThemeDetailScene，按两倍画布排好再缩小），全屏裁切时可在预览上拖动取景；
 * 上方的浅色 / 深色切换同时决定预览哪种模式、下面编辑的是哪张图和哪一档淡化、模糊。
 * 拖动途中只 preview（书架跟着变、不写盘），松手 save。
 */
@Entry
@Component
struct ShelfBackdropSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') @Watch('refreshPreviewPack') themeRevision: number = 0;
  @StorageProp('bookshelfLayoutMode') bookshelfLayoutMode: string = 'companion';
  @StorageProp('homeBackdropEnabled') homeBackdropEnabled: boolean = true;
  @State config: ShelfBackdropConfig = ShelfBackdropStore.current();
  @State @Watch('refreshPreviewPack') editDark: boolean = false;
  /** 预览用的主题，只在切模式、主题变化时重拼；滑条拖动途中不重算。 */
  @State previewThemePack: ThemePack = new ThemePack();
  @State previewLayout: string = 'companion';
  @State busy: boolean = false;
  private dragStartPosition: number = -1;
  /** 预览缩小倍数：按 1/PREVIEW_SCALE 倍的画布排版，看得到顶栏、几本书和底栏。 */
  private static readonly PREVIEW_SCALE: number = 0.5;
  private static readonly PREVIEW_WIDTH: number = 160;

  aboutToAppear(): void {
    this.editDark = this.appDarkMode;
    this.previewLayout = SHELF_BACKDROP_LAYOUTS.indexOf(this.bookshelfLayoutMode) >= 0 ?
      this.bookshelfLayoutMode : 'companion';
    this.config = ShelfBackdropStore.current();
    this.refreshPreviewPack();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '书架背景', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.MD }) {
      this.previewBox()
      Text(this.previewHint())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
      Row() {
        ReaderSettingTabStrip({
          labels: ['浅色', '深色'],
          selected: this.editDark ? 1 : 0,
          dense: true,
          dark: this.appDarkMode,
          textColor: this.primaryTextColor(),
          subTextColor: this.subTextColor(),
          onSelect: (index: number): void => { this.editDark = index === 1; }
        })
          .width(132)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      ReaderSettingTabStrip({
        labels: SHELF_BACKDROP_LAYOUT_NAMES,
        selected: Math.max(0, SHELF_BACKDROP_LAYOUTS.indexOf(this.previewLayout)),
        dense: true,
        dark: this.appDarkMode,
        textColor: this.primaryTextColor(),
        subTextColor: this.subTextColor(),
        onSelect: (index: number): void => { this.previewLayout = SHELF_BACKDROP_LAYOUTS[index]; }
      })
        .width(264)
        .accessibilityText('预览用的书架布局')
    }
    .width('100%')
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.SM })
    .alignItems(HorizontalAlign.Center)

    Column() {
      Column({ space: AppSpacing.SM }) {
        this.rowTitle('背景来源')
        ReaderSettingTabStrip({
          labels: ['跟随主题', '自定义图片'],
          selected: this.isCustom() ? 1 : 0,
          dense: true,
          dark: this.appDarkMode,
          textColor: this.primaryTextColor(),
          subTextColor: this.subTextColor(),
          onSelect: (index: number): void => { this.selectSource(index === 1); }
        })
        this.rowHint(this.sourceDescription())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
      if (this.isCustom()) {
        this.divider()
        this.imageRow()
        this.divider()
        Column({ space: AppSpacing.SM }) {
          this.rowTitle('显示方式')
          ReaderSettingTabStrip({
            labels: ['顶部淡出', '全屏'],
            selected: this.isFull() ? 1 : 0,
            dense: true,
            dark: this.appDarkMode,
            textColor: this.primaryTextColor(),
            subTextColor: this.subTextColor(),
            onSelect: (index: number): void => {
              this.commit((config: ShelfBackdropConfig): void => {
                config.display = index === 1 ? ShelfBackdropStore.DISPLAY_FULL : ShelfBackdropStore.DISPLAY_TOP;
              });
            }
          })
          this.rowHint(this.isFull() ? '铺满整屏，延伸到状态栏和底栏后面，书架滚动时背景不动' :
            '按 4 : 5 铺在顶部，往下淡成底色')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
        if (this.isFull()) {
          this.divider()
          Column() {
            ReaderBackgroundDisplayControl({
              fit: this.config.fit,
              cropPosition: this.editPosition(),
              gap: this.config.gap,
              imageUri: this.editImage(),
              viewportWidth: this.screenWidth(),
              viewportHeight: this.screenHeight(),
              dark: this.appDarkMode,
              textColor: this.primaryTextColor(),
              subTextColor: this.subTextColor(),
              accentColor: this.accentColor(),
              onChange: (value: ReaderBackgroundDisplay, commit: boolean): void => {
                const apply = (config: ShelfBackdropConfig): void => {
                  config.fit = value.fit;
                  config.gap = value.gap;
                  this.setEditPosition(config, value.position);
                };
                if (commit) this.commit(apply); else this.preview(apply);
              }
            })
          }
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
          this.divider()
          this.sliderRow(`淡化 · ${this.editDark ? '深色' : '浅色'}`, '盖一层页面底色，书名更清楚',
            this.editDark ? this.config.darkWash : this.config.lightWash, ShelfBackdropStore.MAX_WASH, '%',
            (config: ShelfBackdropConfig, value: number): void => {
              if (this.editDark) config.darkWash = value; else config.lightWash = value;
            })
          this.divider()
          this.sliderRow(`模糊 · ${this.editDark ? '深色' : '浅色'}`, '图片太花时调高',
            this.editDark ? this.config.darkBlur : this.config.lightBlur, ShelfBackdropStore.MAX_BLUR, '',
            (config: ShelfBackdropConfig, value: number): void => {
              if (this.editDark) config.darkBlur = value; else config.lightBlur = value;
            })
        }
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    Text('只在书架和书架分组页显示，四种书架布局共用；发现、我的页仍用主题背景。图片只存本机，不跟主题走。')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD })
  }

  @Builder
  previewBox() {
    Stack({ alignContent: Alignment.TopStart }) {
      ThemeDetailScene({
        themePack: this.previewThemePack,
        previewDark: this.editDark,
        scene: 'shelf',
        shelfLayout: this.previewLayout,
        homeBackdropThemeId: this.previewThemeBackdropId(),
        customBackdrop: this.previewLook()
      })
        .width(ShelfBackdropSettingsPage.PREVIEW_WIDTH / ShelfBackdropSettingsPage.PREVIEW_SCALE)
        .height(this.previewHeight() / ShelfBackdropSettingsPage.PREVIEW_SCALE)
        .scale({ x: ShelfBackdropSettingsPage.PREVIEW_SCALE, y: ShelfBackdropSettingsPage.PREVIEW_SCALE,
          centerX: 0, centerY: 0 })
        .hitTestBehavior(HitTestMode.None)
    }
    .width(ShelfBackdropSettingsPage.PREVIEW_WIDTH)
    .height(this.previewHeight())
    .borderRadius(18)
    .clip(true)
    .border({ width: 0.5, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
    .shadow({ radius: 16, color: this.appDarkMode ? '#66000000' : '#26000000', offsetY: 6 })
    .gesture(
      // 只在能取景时认拖动，其余时候让页面照常上下滚。
      PanGesture({ direction: this.dragDirection(), distance: 2 })
        .onActionStart(() => { this.dragStartPosition = this.editPosition(); })
        .onActionUpdate((event: GestureEvent) => this.dragCrop(event))
        .onActionEnd((event: GestureEvent) => {
          this.dragCrop(event);
          this.dragStartPosition = -1;
          this.commit((): void => {});
        })
    )
    .accessibilityText(`书架${this.editDark ? '深色' : '浅色'}背景预览`)
  }

  @Builder
  rowTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(this.primaryTextColor())
  }

  @Builder
  rowHint(text: string) {
    Text(text)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .width('100%')
  }

  @Builder
  imageRow() {
    Row({ space: AppSpacing.LG }) {
      Stack() {
        if (this.slotImage()) {
          Image(this.slotImage())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .draggable(false)
            .opacity(this.slotMirrorsLight() ? 0.55 : 1)
        } else {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([this.subTextColor()])
        }
        if (this.slotMirrorsLight()) {
          Text('同浅色')
            .fontSize(AppFontSize.MICRO)
            .fontColor('#FFFFFF')
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(4)
            .backgroundColor('#73000000')
        }
      }
      .width(52)
      .height(92)
      .borderRadius(9)
      .clip(true)
      .backgroundColor(this.slotImage() ? Color.Transparent : ThemeRuntime.inputColor(this.appDarkMode))
      .border({ width: 0.5, color: ThemeRuntime.hairlineColor(this.appDarkMode) })

      Column({ space: AppSpacing.XS }) {
        Text(this.editDark ? '深色图片' : '浅色图片')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Text(this.imageDescription())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .onClick(() => this.tapImage())
    .accessibilityText(`${this.editDark ? '深色' : '浅色'}图片，${this.imageDescription()}`)
  }

  @Builder
  sliderRow(title: string, hint: string, value: number, max: number, unit: string,
    apply: (config: ShelfBackdropConfig, value: number) => void) {
    Column({ space: AppSpacing.XS }) {
      Row() {
        Text(title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Blank()
        Text(hint)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Row({ space: AppSpacing.MD }) {
        Slider({ value: value, min: 0, max: max, step: 1 })
          .layoutWeight(1)
          .height(36)
          .selectedColor(this.accentColor())
          .blockColor(this.accentColor())
          .trackColor(this.appDarkMode ? '#33FFFFFF' : '#1F000000')
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
          .accessibilityText(title)
          .onChange((next: number, mode: SliderChangeMode) => {
            const rounded = Math.round(next);
            const change = (config: ShelfBackdropConfig): void => apply(config, rounded);
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.commit(change);
            else this.preview(change);
          })
        Text(`${value}${unit}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width(36)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.SM })
  }

  @Builder
  divider() {
    Divider()
      .strokeWidth(0.5)
      .color(ThemeRuntime.hairlineColor(this.appDarkMode))
      .width('calc(100% - 32vp)')
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
  }

  // ---------- 状态 ----------

  isCustom(): boolean {
    return this.config.source === ShelfBackdropStore.SOURCE_CUSTOM;
  }

  isFull(): boolean {
    return this.config.display === ShelfBackdropStore.DISPLAY_FULL;
  }

  /** 当前编辑模式实际显示的那张图：深色没单独传时是浅色那张。 */
  editImage(): string {
    return this.editDark && this.config.darkImage ? this.config.darkImage : this.config.lightImage;
  }

  editPosition(): number {
    return this.editDark && this.config.darkImage ? this.config.darkPosition : this.config.lightPosition;
  }

  setEditPosition(config: ShelfBackdropConfig, position: number): void {
    if (this.editDark && config.darkImage) config.darkPosition = position; else config.lightPosition = position;
  }

  slotImage(): string {
    return this.editImage();
  }

  slotMirrorsLight(): boolean {
    return this.editDark && !this.config.darkImage && !!this.config.lightImage;
  }

  imageDescription(): string {
    if (this.editDark) {
      if (this.config.darkImage) return '点按更换，或改回和浅色用同一张';
      return this.config.lightImage ? '没单独上传，用浅色那张；点按上传深色专用的' : '点按上传；也可以只传浅色那张';
    }
    return this.config.lightImage ? '点按更换' : '点按从相册选一张，竖图效果最好';
  }

  sourceDescription(): string {
    if (this.isCustom()) {
      return this.config.lightImage ? '用这里上传的图，主题换了也不变' : '还没上传图片，书架暂时仍用主题背景';
    }
    if (ThemeAssetRegistry.shelfBackdropDisplay(ThemeRuntime.homeBackdropThemeId(this.editDark))) {
      return '用当前主题的书架背景，按主题的设置铺满全屏';
    }
    return '用当前主题的书架背景，铺在顶部往下淡出；主题没有背景图时是纯色';
  }

  previewHint(): string {
    const look = this.previewLook();
    if (!look.image) return this.isCustom() ? '上传图片后在这里预览' : '当前主题的书架背景';
    if (look.display !== ShelfBackdropStore.DISPLAY_FULL) return '顶部淡出不需要取景';
    if (look.fit === ReaderBackgroundDisplay.FIT_COVER && this.cropAxis()) return '在预览上拖动，调整取景';
    return '这种显示方式不需要取景';
  }

  previewLook(): ShelfBackdropLook {
    return ShelfBackdropStore.lookOf(this.config, this.editDark) ?? new ShelfBackdropLook();
  }

  /** 预览用的主题：自定义方案按当前方案拼出来，内置主题和主题包直接取。 */
  refreshPreviewPack(): void {
    this.previewThemePack = ThemeRuntime.currentThemeId() === ThemeIds.CUSTOM ?
      AppThemeSettingsStore.currentCustomTheme(this.editDark) :
      BuiltinThemeRegistry.findById(ThemeRuntime.currentThemeId());
  }

  previewThemeBackdropId(): string {
    if (!this.homeBackdropEnabled) return '';
    return ThemeRuntime.homeBackdropThemeId(this.editDark);
  }

  previewHeight(): number {
    const width = this.screenWidth();
    const height = this.screenHeight();
    const ratio = width > 0 && height > 0 ? Math.min(2.4, Math.max(1.2, height / width)) : 2.1;
    return Math.round(ShelfBackdropSettingsPage.PREVIEW_WIDTH * ratio);
  }

  screenWidth(): number {
    try {
      return display.getDefaultDisplaySync().width;
    } catch (_) {
      return 0;
    }
  }

  screenHeight(): number {
    try {
      return display.getDefaultDisplaySync().height;
    } catch (_) {
      return 0;
    }
  }

  cropAxis(): string {
    return ReaderBackgroundDisplay.croppedAxis(ReaderRasterAssets.imageAspect(this.editImage()),
      ShelfBackdropSettingsPage.PREVIEW_WIDTH, this.previewHeight());
  }

  dragDirection(): PanDirection {
    const look = this.previewLook();
    if (!look.image || look.display !== ShelfBackdropStore.DISPLAY_FULL ||
      look.fit !== ReaderBackgroundDisplay.FIT_COVER) {
      return PanDirection.None;
    }
    const axis = this.cropAxis();
    if (axis === 'v') return PanDirection.Vertical;
    if (axis === 'h') return PanDirection.Horizontal;
    return PanDirection.None;
  }

  /** 在预览上拖动取景：手指往下拖露出图的上半部分，位置按预览里被裁掉的长度换算成百分比。 */
  dragCrop(event: GestureEvent): void {
    const look = this.previewLook();
    if (this.dragStartPosition < 0 || !look.image || look.display !== ShelfBackdropStore.DISPLAY_FULL ||
      look.fit !== ReaderBackgroundDisplay.FIT_COVER) {
      return;
    }
    const axis = this.cropAxis();
    if (!axis) return;
    const aspect = ReaderRasterAssets.imageAspect(this.editImage());
    const width = ShelfBackdropSettingsPage.PREVIEW_WIDTH;
    const height = this.previewHeight();
    const rect = ReaderBackgroundDisplay.coverRect(aspect, width, height, 50);
    const overflow = axis === 'v' ? rect[3] - height : rect[2] - width;
    if (overflow <= 0) return;
    const delta = axis === 'v' ? event.offsetY : event.offsetX;
    const position = ReaderBackgroundDisplay.normalizePosition(this.dragStartPosition - delta / overflow * 100);
    if (position === this.editPosition()) return;
    this.preview((config: ShelfBackdropConfig): void => this.setEditPosition(config, position));
  }

  // ---------- 修改 ----------

  /** 改内存里的设置让书架和预览跟着变，不写盘。 */
  preview(change: (config: ShelfBackdropConfig) => void): void {
    const next = ShelfBackdropStore.current();
    change(next);
    ShelfBackdropStore.preview(next);
    this.config = ShelfBackdropStore.current();
  }

  commit(change: (config: ShelfBackdropConfig) => void): void {
    const next = ShelfBackdropStore.current();
    change(next);
    ShelfBackdropStore.save(getContext(this), next).catch((error: Error) => {
      console.warn('保存书架背景失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
    this.config = ShelfBackdropStore.current();
  }

  async selectSource(custom: boolean): Promise<void> {
    if (custom === this.isCustom()) return;
    if (custom && !this.config.lightImage) {
      // 第一次选自定义就直接去选图；取消了就还是跟随主题。
      const uri = await this.pick(false);
      if (!uri) return;
      this.commit((config: ShelfBackdropConfig): void => {
        config.source = ShelfBackdropStore.SOURCE_CUSTOM;
        config.lightImage = uri;
        config.lightPosition = 50;
      });
      return;
    }
    this.commit((config: ShelfBackdropConfig): void => {
      config.source = custom ? ShelfBackdropStore.SOURCE_CUSTOM : ShelfBackdropStore.SOURCE_THEME;
    });
  }

  async tapImage(): Promise<void> {
    const dark = this.editDark;
    if (dark && this.config.darkImage) {
      const choice = await this.menu('深色图片', '更换', '改回和浅色用同一张');
      if (choice === 0) await this.replace(true);
      else if (choice === 1) this.commit((config: ShelfBackdropConfig): void => { config.darkImage = ''; });
      return;
    }
    if (dark || !this.config.lightImage) {
      await this.replace(dark);
      return;
    }
    const choice = await this.menu('浅色图片', '更换', '移除，改回跟随主题');
    if (choice === 0) await this.replace(false);
    else if (choice === 1) {
      this.commit((config: ShelfBackdropConfig): void => {
        config.source = ShelfBackdropStore.SOURCE_THEME;
        config.lightImage = '';
        config.darkImage = '';
      });
    }
  }

  async replace(dark: boolean): Promise<void> {
    const uri = await this.pick(dark);
    if (!uri) return;
    this.commit((config: ShelfBackdropConfig): void => {
      if (dark) {
        config.darkImage = uri;
        config.darkPosition = 50;
      } else {
        config.lightImage = uri;
        config.lightPosition = 50;
      }
    });
  }

  async pick(dark: boolean): Promise<string> {
    if (this.busy) return '';
    this.busy = true;
    try {
      return await ShelfBackdropStore.pickImage(getContext(this), dark);
    } catch (error) {
      console.warn('选择书架背景图失败:', error);
      HdsFeedback.showToast('图片读取失败，请换一张试试');
      return '';
    } finally {
      this.busy = false;
    }
  }

  /** 系统操作菜单，返回按钮序号，取消返回 -1；以“移除”开头的用危险色。 */
  async menu(title: string, first: string, second: string): Promise<number> {
    const a: promptAction.Button = { text: first, color: this.menuColor(first) };
    const b: promptAction.Button = { text: second, color: this.menuColor(second) };
    try {
      const result: promptAction.ActionMenuSuccessResponse =
        await ThemedDialog.showActionMenu(this.getUIContext(), { title: title, buttons: [a, b] });
      return result.index;
    } catch (_) {
      return -1;
    }
  }

  menuColor(label: string): string {
    return label.startsWith('移除') ? ThemeRuntime.dangerColor(this.appDarkMode) : this.primaryTextColor();
  }

  // ---------- 颜色 ----------

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
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
}
