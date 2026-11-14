import { ImmersiveLightSettingsStore } from '../utils/ImmersiveLightSettingsStore';
import { HomeBackdropSettingsStore } from '../utils/HomeBackdropSettingsStore';
import { AnimatedImagePolicy } from '../utils/AnimatedImagePolicy';
import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { HomeTabBarSettingsStore } from '../utils/HomeTabBarSettingsStore';
import { FootprintLayout } from '../utils/FootprintLayout';
import { HexColor } from '../utils/HexColor';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { AppThemeModeStore } from '../utils/AppThemeModeStore';
import { AppColorModeApplier } from '../utils/AppColorModeApplier';

/** 我的 › 外观：显示模式、字体与图标、沉浸材质与背景、底栏。配色和整套主题在“主题”里。 */
@Entry
@Component
struct AppearanceSettingsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appThemeMode') appThemeMode: string = 'system';
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('homeBackdropEnabled') homeBackdropEnabled: boolean = true;
  @StorageProp('headerFrosted') headerFrosted: boolean = true;
  @StorageProp('immersiveThemeTint') immersiveThemeTint: boolean = false;
  @StorageProp('animatedImagesEnabled') animatedImagesEnabled: boolean = true;
  @StorageProp('homeTabBarStyle') homeTabBarStyle: string = 'floating';
  @StorageProp('homeExtraTab') homeExtraTab: string = 'none';
  @StorageProp('footprintLayout') footprintLayoutRaw: string = '';
  @StorageProp('homeTabBarFlatOpacity') homeTabBarFlatOpacity: number = 100;
  @StorageProp('homeTabBarFlatFrosted') homeTabBarFlatFrosted: boolean = false;
  @StorageProp('homeTabBarFlatAutoHide') homeTabBarFlatAutoHide: boolean = false;
  @StorageProp('homeTabBarFloatingAdaptive') homeTabBarFloatingAdaptive: boolean = true;
  /** 网页解析关闭时首页没有发现页签，示意条和说明跟着变。 */
  @StorageProp('webParseEnabled') webParseEnabled: boolean = false;
  /** 拖动不透明度滑杆时的临时值，-1 表示没在拖。 */
  @State flatOpacityDraft: number = -1;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @State savingImmersiveLight: boolean = false;

  aboutToAppear(): void {
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack() {
      PageScaffold({ title: '外观', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    this.sectionTitle('显示')
    Column() {
      SettingRow({ title: '显示模式', description: '浅色、深色，或跟随系统自动切换' }) {
        this.themeModeSelect()
      }
      SettingNavRow({
        title: '字体设置',
        description: '全局字体、自定义字体',
        onTap: () => {
          router.pushUrl({ url: 'pages/FontSettings' });
        }
      })
      SettingNavRow({
        title: '图标设置',
        description: '更换桌面图标',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/AppIconSettings' });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('材质与背景')
    Column() {
      SettingRow({ title: '沉浸光感', description: this.immersiveLightLevelDescription() }) {
        this.immersiveLightLevelSelect()
      }
      SettingSwitchRow({
        title: '沉浸光感跟随主题色',
        description: '菜单、弹窗、面板和悬浮按钮的半透明底色带上一点主题强调色；关闭时为中性色',
        isOn: this.immersiveThemeTint,
        onChange: (value: boolean) => { this.setImmersiveThemeTint(value); }
      })
      SettingSwitchRow({
        title: '主题背景图',
        description: '主题自带背景图时，铺在书架、发现、搜索和我的页顶部',
        isOn: this.homeBackdropEnabled,
        onChange: (value: boolean) => { this.setHomeBackdropEnabled(value); }
      })
      SettingSwitchRow({
        title: '顶部磨砂',
        description: '页面顶栏背后的内容先模糊再透出；关闭后顶栏完全透明',
        isOn: this.headerFrosted,
        onChange: (value: boolean) => { this.setHeaderFrosted(value); }
      })
      SettingSwitchRow({
        title: '播放动图',
        description: `书架封面、主题封面和背景图是 GIF 或动态 WebP 时播放动画；关闭后只显示第一帧，更省电。超过 ${AnimatedImagePolicy.MAX_PLAY_LABEL} 的动图始终只显示第一帧`,
        isOn: this.animatedImagesEnabled,
        showDivider: false,
        onChange: (value: boolean) => {
          if (value === AnimatedImagePolicy.enabled()) return;
          AnimatedImagePolicy.save(getContext(this), value).catch((error: Error) => {
            console.warn('保存动图设置失败:', error);
            HdsFeedback.showToast('保存失败，请重试');
          });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('底栏')
    Column() {
      SettingRow({ title: '底栏样式', description: this.tabBarStyleDescription() }) {
        this.tabBarStyleSelect()
      }
      if (!this.flatTabBarInUse()) {
        SettingSwitchRow({
          title: '自适应宽度',
          description: this.homeTabBarFloatingAdaptive ? '底栏宽度随项目数变化，三项时更窄' :
            '底栏两侧留出固定边距，和朗读伴生条一样宽',
          isOn: this.homeTabBarFloatingAdaptive,
          onChange: (value: boolean) => this.setFloatingAdaptive(value)
        })
      }
      if (this.flatTabBarInUse()) {
        this.flatOpacityRow()
        SettingSwitchRow({
          title: '底栏磨砂',
          description: this.flatOpacityValue() < 100 ? '透出底栏的内容先模糊，透明度调低时图标也看得清' :
            '不透明度低于 100% 时生效',
          isOn: this.homeTabBarFlatFrosted,
          switchEnabled: this.flatOpacityValue() < 100,
          onChange: (value: boolean) => this.setFlatFrosted(value)
        })
        SettingSwitchRow({
          title: '滑动收起',
          description: '列表上滑时底栏自动收起，回到上方再出现',
          isOn: this.homeTabBarFlatAutoHide,
          onChange: (value: boolean) => this.setFlatAutoHide(value)
        })
      }
      SettingRow({
        title: '更多底栏项目',
        description: this.webParseEnabled ?
          '在“我的”前面加一个页签：“听”汇集正在播放、有声书和朗读设置，“足迹”展示本周阅读统计和书签' :
          '在“我的”前面加一个页签：“听”汇集正在播放和朗读设置，“足迹”展示本周阅读统计和书签',
        showDivider: this.footprintTabEnabled()
      }) {
        this.extraTabSelect()
      }
      if (this.footprintTabEnabled()) {
        SettingNavRow({
          title: '足迹页内容',
          description: '选择足迹页显示哪些内容、顺序和数量',
          value: this.footprintLayoutSummary(),
          showDivider: false,
          onTap: () => {
            router.pushUrl({ url: 'pages/FootprintLayoutSettings' });
          }
        })
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.XXL })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  themeModeValues(): string[] {
    return ['light', 'dark', 'system'];
  }

  themeModeIndex(): number {
    return Math.max(0, this.themeModeValues().indexOf(AppThemeModeStore.normalizeMode(this.appThemeMode)));
  }

  /** 与“我的”页右上角的显示模式按钮是同一个设置。 */
  applyThemeMode(index: number): void {
    const mode = AppThemeModeStore.normalizeMode(this.themeModeValues()[index] || 'system');
    if (mode === AppThemeModeStore.normalizeMode(this.appThemeMode)) return;
    const context = getContext(this) as common.UIAbilityContext;
    const systemDarkMode = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const nextDarkMode = mode === 'dark' || (mode === 'system' && systemDarkMode);
    // 先同步模式来源，setColorMode 触发的配置更新才不会读到旧模式又改回去。
    AppThemeModeStore.applyToStorage(mode);
    if (this.appDarkMode !== nextDarkMode) {
      this.appDarkMode = nextDarkMode;
    }
    AppColorModeApplier.apply(context, AppColorModeApplier.colorModeFor(mode));
    AppThemeModeStore.save(context, mode).catch((e: Error) => {
      console.warn('保存显示模式失败:', e);
    });
  }

  @Builder
  themeModeSelect() {
    Select([{ value: '浅色' }, { value: '深色' }, { value: '自动' }])
      .selected(this.themeModeIndex())
      .value(['浅色', '深色', '自动'][this.themeModeIndex()])
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
      .onSelect((index: number) => this.applyThemeMode(index))
  }

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

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  /** 弱档设备上跟随系统会按均衡渲染，在说明里告诉用户。 */
  immersiveLightLevelDescription(): string {
    return this.immersiveLightLevel === 'adaptive' && ImmersiveMaterialRuntime.deviceMaterialWeak() ?
      '本机材质档位为弱，跟随系统时按均衡显示' : '沉浸材质的光感强度';
  }

  immersiveLightLevelOptions(): SelectOption[] {
    return [
      { value: '跟随系统' },
      { value: '高' },
      { value: '均衡' },
      { value: '弱' }
    ];
  }

  immersiveLightLevelValues(): string[] {
    return ['adaptive', 'high', 'balanced', 'weak'];
  }

  immersiveLightLevelSelectedIndex(): number {
    const index = this.immersiveLightLevelValues().indexOf(this.immersiveLightLevel);
    return index >= 0 ? index : 0;
  }

  setHeaderFrosted(frosted: boolean): void {
    if (this.headerFrosted === frosted) return;
    HomeBackdropSettingsStore.saveHeaderFrosted(getContext(this), frosted).catch((error: Error) => {
      console.warn('保存顶部磨砂设置失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
  }

  setHomeBackdropEnabled(enabled: boolean): void {
    if (this.homeBackdropEnabled === enabled) return;
    HomeBackdropSettingsStore.save(getContext(this), enabled).catch((error: Error) => {
      console.warn('保存首页背景设置失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
    // 首页各页签按主题版本号重建，背景层和透明的列表底色一起切换。
    const revision = AppStorage.get<number>('themeRevision') ?? 0;
    AppStorage.setOrCreate('themeRevision', revision + 1);
  }

  setImmersiveThemeTint(enabled: boolean): void {
    if (this.immersiveThemeTint === enabled) return;
    ImmersiveLightSettingsStore.saveThemeTint(getContext(this), enabled).catch((error: Error) => {
      console.warn('保存沉浸光感主题色设置失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
    // 底色在构建时读取，按主题版本号重建首页底栏、阅读页工具栏等缓存了材质的部分。
    const revision = AppStorage.get<number>('themeRevision') ?? 0;
    AppStorage.setOrCreate('themeRevision', revision + 1);
  }

  async setImmersiveLightLevel(index: number): Promise<void> {
    if (this.savingImmersiveLight) return;
    const values = this.immersiveLightLevelValues();
    const next = index >= 0 && index < values.length ? values[index] : values[0];
    if (this.immersiveLightLevel === next) return;
    this.savingImmersiveLight = true;
    try {
      await ImmersiveLightSettingsStore.save(getContext(this), next);
      const revision = AppStorage.get<number>('themeRevision') ?? 0;
      AppStorage.setOrCreate('themeRevision', revision + 1);
    } catch (error) {
      console.warn('保存沉浸光感设置失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    } finally {
      this.savingImmersiveLight = false;
    }
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  tabBarStyleDescription(): string {
    return ImmersiveMaterialRuntime.supportsHdsTabs() ? '悬浮底栏浮在页面上，带沉浸材质；平铺底栏贴底铺满，可调透明度' :
      '本机系统不支持悬浮底栏，使用平铺底栏';
  }

  tabBarStyleIndex(): number {
    return ImmersiveMaterialRuntime.supportsHdsTabs() &&
      HomeTabBarSettingsStore.normalizeStyle(this.homeTabBarStyle) === HomeTabBarSettingsStore.STYLE_FLOATING ? 0 : 1;
  }

  /** 首页实际用的是平铺底栏（选了平铺，或系统不支持悬浮）。 */
  flatTabBarInUse(): boolean {
    return this.tabBarStyleIndex() === 1;
  }

  /** 拖动中用本页的临时值，松手才落盘；没在拖时跟随已存的值。 */
  flatOpacityValue(): number {
    return this.flatOpacityDraft >= 0 ? this.flatOpacityDraft :
      HomeTabBarSettingsStore.normalizeFlatOpacity(this.homeTabBarFlatOpacity);
  }

  flatOpacityDescription(): string {
    const value = this.flatOpacityValue();
    if (value >= 100) return '100%：纯色底栏，页面停在底栏上方';
    if (value <= 0) return '0%：只留图标，页面和背景图铺到屏幕底';
    return `${value}%：页面和背景图透过底栏铺到屏幕底`;
  }

  onFlatOpacityChange(value: number, mode: SliderChangeMode): void {
    const opacity = HomeTabBarSettingsStore.normalizeFlatOpacity(value);
    this.flatOpacityDraft = opacity;
    if (mode !== SliderChangeMode.End && mode !== SliderChangeMode.Click) return;
    this.flatOpacityDraft = -1;
    if (opacity === HomeTabBarSettingsStore.normalizeFlatOpacity(this.homeTabBarFlatOpacity)) return;
    HomeTabBarSettingsStore.saveFlatOpacity(getContext(this), opacity).catch((error: Error) => {
      console.warn('保存底栏不透明度失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
  }

  setFlatFrosted(frosted: boolean): void {
    if (frosted === this.homeTabBarFlatFrosted) return;
    HomeTabBarSettingsStore.saveFlatFrosted(getContext(this), frosted).catch((error: Error) => {
      console.warn('保存底栏磨砂设置失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
  }

  setFloatingAdaptive(adaptive: boolean): void {
    if (adaptive === this.homeTabBarFloatingAdaptive) return;
    HomeTabBarSettingsStore.saveFloatingAdaptive(getContext(this), adaptive).catch((error: Error) => {
      console.warn('保存底栏自适应宽度设置失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
  }

  setFlatAutoHide(autoHide: boolean): void {
    if (autoHide === this.homeTabBarFlatAutoHide) return;
    HomeTabBarSettingsStore.saveFlatAutoHide(getContext(this), autoHide).catch((error: Error) => {
      console.warn('保存底栏滑动收起设置失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
  }

  previewTabIds(): string[] {
    const extra = HomeTabBarSettingsStore.normalizeExtraTab(this.homeExtraTab);
    const ids: string[] = ['bookshelf'];
    if (this.webParseEnabled) ids.push('explore');
    if (extra !== HomeTabBarSettingsStore.EXTRA_NONE) ids.push(extra);
    ids.push('mine');
    return ids;
  }

  /** 示意条里垫在底栏下面的几本“书”，颜色取主题强调色的深浅变化，让透明度和磨砂一眼看得出。 */
  previewBlockColors(): string[] {
    const accent = this.accentColor();
    return [HexColor.withOpacity(accent, 0.9), HexColor.withOpacity(accent, 0.45), this.primaryTextColor(),
      HexColor.withOpacity(accent, 0.7), HexColor.withOpacity(this.primaryTextColor(), 0.35)];
  }

  /** 平铺底栏效果示意：当前主题背景图（没有时用页面底色）上叠几块内容，底部盖一条按当前设置绘制的底栏。 */
  @Builder
  flatTabBarPreview() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.pageColor())
      if (ThemeRuntime.homeBackdrop(this.appDarkMode)) {
        Image(ThemeRuntime.homeBackdrop(this.appDarkMode) as ResourceStr)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      }
      Row({ space: AppSpacing.SM }) {
        ForEach(this.previewBlockColors(), (color: string) => {
          Column()
            .layoutWeight(1)
            .height(78)
            .borderRadius(6)
            .backgroundColor(color)
        }, (color: string, index: number) => `${index}_${color}`)
      }
      .width('100%')
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
      .position({ x: 0, y: 26 })
      Row() {
        ForEach(this.previewTabIds(), (tabId: string, index: number) => {
          Column() {
            Image(ThemeAssetRegistry.navigationIcon(ThemeRuntime.iconPackId(), tabId, false))
              .width(20)
              .height(20)
              .fillColor(index === 0 ? this.accentColor() : this.subTextColor())
              .draggable(false)
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }, (tabId: string) => tabId)
      }
      .width('100%')
      .height(40)
      .backgroundColor(HomeTabBarSettingsStore.flatBarColor(this.cardColor(), this.flatOpacityValue()))
      .backgroundEffect(HomeTabBarSettingsStore.flatBarFrostEffect(
        this.homeTabBarFlatFrosted && this.flatOpacityValue() < 100))
    }
    .width('100%')
    .height(132)
    .borderRadius(12)
    .clip(true)
    .border({ width: 0.5, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
    .accessibilityLevel('no')
  }

  @Builder
  flatOpacityRow() {
    Column({ space: AppSpacing.SM }) {
      Row() {
        Text('底栏不透明度')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Blank()
        Text(`${this.flatOpacityValue()}%`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
      }
      .width('100%')
      Text(this.flatOpacityDescription())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
      Slider({ value: this.flatOpacityValue(), min: 0, max: 100, step: 5 })
        .width('100%')
        .selectedColor(this.accentColor())
        .blockColor(this.accentColor())
        .trackColor(ThemeRuntime.inputColor(this.appDarkMode))
        // 只能拖动滑块调整，点到条上不跳值，防止上下滑动页面时误触。
        .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
        .accessibilityText('底栏不透明度')
        .onChange((value: number, mode: SliderChangeMode) => this.onFlatOpacityChange(value, mode))
      this.flatTabBarPreview()
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
    .border({ width: { bottom: 0.5 }, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
  }

  extraTabValues(): string[] {
    return [HomeTabBarSettingsStore.EXTRA_NONE, HomeTabBarSettingsStore.EXTRA_LISTEN,
      HomeTabBarSettingsStore.EXTRA_FOOTPRINT];
  }

  footprintTabEnabled(): boolean {
    return HomeTabBarSettingsStore.normalizeExtraTab(this.homeExtraTab) === HomeTabBarSettingsStore.EXTRA_FOOTPRINT;
  }

  footprintLayoutSummary(): string {
    const visible = FootprintLayout.parse(this.footprintLayoutRaw).visibleOrder().length;
    return visible === FootprintLayout.SECTIONS.length ? '全部显示' : `显示 ${visible} 项`;
  }

  extraTabIndex(): number {
    return Math.max(0, this.extraTabValues().indexOf(HomeTabBarSettingsStore.normalizeExtraTab(this.homeExtraTab)));
  }

  saveTabBarStyle(index: number): void {
    const style = index === 0 ? HomeTabBarSettingsStore.STYLE_FLOATING : HomeTabBarSettingsStore.STYLE_FLAT;
    if (style === HomeTabBarSettingsStore.normalizeStyle(this.homeTabBarStyle)) return;
    HomeTabBarSettingsStore.saveStyle(getContext(this), style).catch((error: Error) => {
      console.warn('保存底栏样式失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
  }

  saveExtraTab(index: number): void {
    const extra = this.extraTabValues()[index] || HomeTabBarSettingsStore.EXTRA_NONE;
    if (extra === HomeTabBarSettingsStore.normalizeExtraTab(this.homeExtraTab)) return;
    HomeTabBarSettingsStore.saveExtraTab(getContext(this), extra).catch((error: Error) => {
      console.warn('保存底栏项目失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
  }

  @Builder
  tabBarStyleSelect() {
    Select([{ value: '悬浮' }, { value: '平铺' }])
      .enabled(ImmersiveMaterialRuntime.supportsHdsTabs())
      .selected(this.tabBarStyleIndex())
      .value(this.tabBarStyleIndex() === 0 ? '悬浮' : '平铺')
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
      .onSelect((index: number) => this.saveTabBarStyle(index))
  }

  @Builder
  extraTabSelect() {
    Select([{ value: '关' }, { value: '听' }, { value: '足迹' }])
      .selected(this.extraTabIndex())
      .value(['关', '听', '足迹'][this.extraTabIndex()])
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
      .onSelect((index: number) => this.saveExtraTab(index))
  }

  @Builder
  immersiveLightLevelSelect() {
    Select(this.immersiveLightLevelOptions())
      .enabled(!this.savingImmersiveLight)
      .selected(this.savingImmersiveLight ? -1 : this.immersiveLightLevelSelectedIndex())
      .value(this.savingImmersiveLight ? '保存中…' : this.immersiveLightLevelOptions()[this.immersiveLightLevelSelectedIndex()].value)
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
      .onSelect((index: number) => this.setImmersiveLightLevel(index))
  }
}
