import { ImmersiveLightSettingsStore } from '../utils/ImmersiveLightSettingsStore';
import { SmartGripSettingsStore } from '../utils/SmartGripSettingsStore';
import { HomeBackdropSettingsStore } from '../utils/HomeBackdropSettingsStore';
import { AnimatedImagePolicy } from '../utils/AnimatedImagePolicy';
import { promptAction, router } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { lanReaderServer } from '../core/lan/LanReaderServer';
import { LanReaderPasswordStore } from '../core/lan/LanReaderPasswordStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ReaderCacheBudget, ReaderCacheCleanup } from '../core/book/ReaderCacheBudget';
import { ReaderCacheBudgetPolicy } from '../core/book/ReaderCacheBudgetPolicy';
import { AudioOfflineStore } from '../core/book/AudioOfflineStore';
import { NetworkSettingsStore } from '../utils/NetworkSettingsStore';
import { HomeTabBarSettingsStore } from '../utils/HomeTabBarSettingsStore';
import { FootprintLayout } from '../utils/FootprintLayout';
import { HexColor } from '../utils/HexColor';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';

@Entry
@Component
struct OtherSettingsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageLink('networkForceHttp1') networkForceHttp1: boolean = false;
  @StorageLink('readerImageConcurrency') readerImageConcurrency: number = 4;
  @State savingNetwork: boolean = false;
  @State savingImageConcurrency: boolean = false;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('smartGripEnabled') smartGripEnabled: boolean = true;
  @StorageLink('homeBackdropEnabled') homeBackdropEnabled: boolean = true;
  @StorageProp('animatedImagesEnabled') animatedImagesEnabled: boolean = true;
  @StorageProp('homeTabBarStyle') homeTabBarStyle: string = 'floating';
  @StorageProp('homeExtraTab') homeExtraTab: string = 'none';
  @StorageProp('footprintLayout') footprintLayoutRaw: string = '';
  @StorageProp('homeTabBarFlatOpacity') homeTabBarFlatOpacity: number = 100;
  @StorageProp('homeTabBarFlatFrosted') homeTabBarFlatFrosted: boolean = false;
  @StorageProp('homeTabBarFlatAutoHide') homeTabBarFlatAutoHide: boolean = false;
  /** 拖动不透明度滑杆时的临时值，-1 表示没在拖。 */
  @State flatOpacityDraft: number = -1;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('lanReaderEnabled') lanReaderEnabled: boolean = false;
  @StorageLink('lanReaderAddress') lanReaderAddress: string = '';
  @StorageLink('lanReaderStatus') lanReaderStatus: string = '已关闭';
  @StorageLink('lanReaderToken') lanReaderToken: string = '';
  @StorageLink('lanReaderPassword') lanReaderPassword: string = '';
  @StorageProp('lanReaderPasswordUnreadable') lanReaderPasswordUnreadable: boolean = false;
  @StorageLink('lanReaderBackgroundStatus') lanReaderBackgroundStatus: string = '未启动';
  @State lanReaderPasswordDraft: string = '';
  /** -1 表示还在统计。 */
  @State textCacheBytes: number = -1;
  @State comicCacheBytes: number = -1;
  @State offlineBytes: number = -1;
  @State audioOfflineBytes: number = -1;
  @State audioOfflineAutoBytes: number = 0;
  @State audioOfflineBooks: number = 0;
  @State audioOfflineChapters: number = 0;
  @State cacheClearing: boolean = false;
  @State savingImmersiveLight: boolean = false;

  aboutToAppear(): void {
    this.lanReaderPasswordDraft = this.lanReaderPasswordUnreadable ? '' : this.lanReaderPassword;
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
    this.refreshCacheUsage();
  }

  build() {
    Stack() {
      PageScaffold({ title: '其他设置', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    this.sectionTitle('数据')
    Column() {
      SettingNavRow({
        title: '数据导入',
        description: '从备份文件导入书源、书架、进度、本地图书和设置',
        onTap: () => {
          router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'import' } });
        }
      })
      SettingNavRow({
        title: '数据导出',
        description: '将书源、书架、进度、本地图书和设置导出为备份',
        onTap: () => {
          router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'export' } });
        }
      })
      SettingNavRow({
        title: '导入安卓阅读备份',
        description: '导入安卓版阅读导出的 ZIP 备份，恢复书源、书架、阅读进度和记录',
        showDivider: false,
        onTap: () => {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/DataBackup',
            params: { mode: 'import', sourceFormat: 'legado-android' }
          });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('缓存')
    Column() {
      SettingRow({
        title: '小说自动缓存',
        description: this.cacheUsageText(this.textCacheBytes, ReaderCacheBudget.TEXT_LIMIT_BYTES,
          '正文数据量；超限清理最久未用的章节，离线内容另计，使用中可暂时超限'),
        onTap: () => this.confirmClearCache(true)
      }) {
        this.cacheClearLabel()
      }
      SettingRow({
        title: '漫画自动缓存',
        description: this.cacheUsageText(this.comicCacheBytes, ReaderCacheBudget.COMIC_LIMIT_BYTES,
          '原图和处理结果合计；离线原图另计，使用中可暂时超限'),
        showDivider: false,
        onTap: () => this.confirmClearCache(false)
      }) {
        this.cacheClearLabel()
      }
      SettingRow({
        title: '离线内容',
        description: (this.offlineBytes === -2 ? '统计失败，重新进入后重试' : this.offlineBytes < 0 ? '正在统计…' : ReaderCacheBudgetPolicy.formatBytes(this.offlineBytes)) +
          '\n手动缓存的正文与漫画原图，不参与自动清理',
        onTap: () => this.confirmClearOffline()
      }) {
        this.cacheClearLabel()
      }
      SettingRow({
        title: '有声书离线音频',
        description: this.audioOfflineUsageText() +
          '\n手动下载的不参与自动清理；边听边下的听完自动删除。下载选项在“阅读与收听 › 有声书”',
        showDivider: false,
        onTap: () => this.confirmClearAudioOffline()
      }) {
        this.cacheClearLabel()
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('浏览器看书')
    Column() {
      SettingSwitchRow({
        title: '浏览器看书',
        description: '同一局域网内的设备可用浏览器访问本机书架',
        isOn: this.lanReaderEnabled,
        onChange: (value: boolean) => {
          this.setLanReaderEnabled(value);
        }
      })
      if (this.lanReaderEnabled) {
        this.lanReaderAddressRow()
        this.lanReaderPasswordRow()
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('交互')
    Column() {
      SettingSwitchRow({
        title: '智感握姿',
        description: '根据左右手握持，自动调整导航栏和部分操作按钮的位置；需设备支持',
        isOn: this.smartGripEnabled,
        showDivider: false,
        onChange: (value: boolean) => {
          SmartGripSettingsStore.save(getContext(this), value).catch((error: Error) => {
            console.warn('保存智感握姿设置失败:', error);
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
        description: '在发现和我的之间加一个页签：“听”汇集正在播放、有声书和朗读设置，“足迹”展示本周阅读统计和书签',
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
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('外观')
    Column() {
      SettingRow({ title: '沉浸光感', description: this.immersiveLightLevelDescription() }) {
        this.immersiveLightLevelSelect()
      }
      SettingSwitchRow({
        title: '主题背景图',
        description: '主题自带背景图时，铺在书架、发现、搜索和我的页顶部',
        isOn: this.homeBackdropEnabled,
        onChange: (value: boolean) => { this.setHomeBackdropEnabled(value); }
      })
      SettingSwitchRow({
        title: '播放动图',
        description: `书架封面、主题封面和背景图是 GIF 或动态 WebP 时播放动画；关闭后只显示第一帧，更省电。超过 ${AnimatedImagePolicy.MAX_PLAY_LABEL} 的动图始终只显示第一帧`,
        isOn: this.animatedImagesEnabled,
        onChange: (value: boolean) => {
          if (value === AnimatedImagePolicy.enabled()) return;
          AnimatedImagePolicy.save(getContext(this), value).catch((error: Error) => {
            console.warn('保存动图设置失败:', error);
            HdsFeedback.showToast('保存失败，请重试');
          });
        }
      })
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

    this.sectionTitle('兼容与诊断')
    Column() {
      SettingRow({ title: '图片下载并发', description: '默认 4 张；网络较快时可提高，图片站限流或加载不稳时调回 4 张' }) {
        Select([{ value: '4 张' }, { value: '8 张' }, { value: '12 张' }])
          .selected(Math.max(0, [4, 8, 12].indexOf(this.readerImageConcurrency)))
          .value(`${this.readerImageConcurrency} 张`)
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .optionFont({ family: this.applicationFontFamily })
          .selectedOptionFont({ family: this.applicationFontFamily })
          .fontColor(this.primaryTextColor())
          .backgroundColor(Color.Transparent)
          .enabled(!this.savingImageConcurrency)
          .onSelect((index: number) => { this.saveImageConcurrency([4, 8, 12][index] || 4); })
      }
      SettingSwitchRow({
        title: 'HTTP/1.1 兼容模式',
        description: '书源连接反复出现传输错误时可尝试开启，对后续原生网络请求生效',
        isOn: this.networkForceHttp1,
        onChange: (value: boolean) => { this.saveHttpCompatibility(value); }
      })
      SettingNavRow({
        title: '后台脚本线程验证',
        description: '检查 QuickJS 后台线程的响应、超时取消与并发',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/ScriptThreadProbe' });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  private async saveHttpCompatibility(value: boolean): Promise<void> {
    if (this.savingNetwork) return;
    this.savingNetwork = true;
    try {
      await NetworkSettingsStore.save(this.getUIContext().getHostContext()!, value);
    } catch (_) {
      HdsFeedback.showToast('网络设置保存失败，请重试');
    } finally {
      this.savingNetwork = false;
    }
  }

  private async saveImageConcurrency(value: number): Promise<void> {
    if (this.savingImageConcurrency) return;
    this.savingImageConcurrency = true;
    try {
      await NetworkSettingsStore.saveImageConcurrency(this.getUIContext().getHostContext()!, value);
    } catch (_) {
      HdsFeedback.showToast('图片并发设置保存失败，请重试');
    } finally {
      this.savingImageConcurrency = false;
    }
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

  @Builder
  cacheClearLabel() {
    Text('清理')
      .fontSize(AppFontSize.BODY)
      .fontColor(this.cacheClearing ? this.subTextColor() : this.accentColor())
      .margin({ left: AppSpacing.LG })
  }

  cacheUsageText(bytes: number, limit: number, note: string): string {
    const usage = bytes === -2 ? '统计失败，重新进入后重试' : bytes < 0 ? '正在统计…' :
      `${ReaderCacheBudgetPolicy.formatBytes(bytes)} / ${ReaderCacheBudgetPolicy.formatBytes(limit)}`;
    return `${usage}\n${note}`;
  }

  async refreshCacheUsage(): Promise<void> {
    try {
      this.textCacheBytes = await ReaderCacheBudget.textUsageBytes();
    } catch (e) {
      console.warn('统计正文缓存失败:', e);
      this.textCacheBytes = -2;
    }
    try {
      this.comicCacheBytes = await ReaderCacheBudget.comicUsageBytes();
      this.offlineBytes = await ReaderCacheBudget.textUsageBytes(true) + await ReaderCacheBudget.comicUsageBytes(true);
    } catch (e) {
      console.warn('统计漫画缓存失败:', e);
      this.comicCacheBytes = -2;
      this.offlineBytes = -2;
    }
    try {
      const usage = await AudioOfflineStore.usage();
      this.audioOfflineBooks = usage.books;
      this.audioOfflineChapters = usage.chapters;
      this.audioOfflineAutoBytes = usage.autoBytes;
      this.audioOfflineBytes = usage.bytes;
    } catch (e) {
      console.warn('统计离线音频失败:', e);
      this.audioOfflineBytes = -2;
    }
  }

  audioOfflineUsageText(): string {
    if (this.audioOfflineBytes === -2) return '统计失败，重新进入后重试';
    if (this.audioOfflineBytes < 0) return '正在统计…';
    if (this.audioOfflineChapters === 0) return '暂无';
    const auto = this.audioOfflineAutoBytes > 0 ?
      `（边听边下 ${ReaderCacheBudgetPolicy.formatBytes(this.audioOfflineAutoBytes)}）` : '';
    return `${ReaderCacheBudgetPolicy.formatBytes(this.audioOfflineBytes)}${auto} · ${this.audioOfflineBooks} 本书 ${this.audioOfflineChapters} 章`;
  }

  async confirmClearAudioOffline(): Promise<void> {
    if (this.cacheClearing) return;
    try {
      const answer = await promptAction.showDialog({
        title: '删除离线音频？',
        message: '删除所有手动下载的有声书音频，之后收听需要联网。正在播放的章节会继续播完。',
        buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.appDarkMode) },
          { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
      });
      if (answer.index !== 1) return;
      this.cacheClearing = true;
      const released = await AudioOfflineStore.clearAll();
      HdsFeedback.showToast(`已清理 ${ReaderCacheBudgetPolicy.formatBytes(released)} 数据`);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) { HdsFeedback.showToast('删除离线音频失败'); }
    finally { this.cacheClearing = false; }
    await this.refreshCacheUsage();
  }

  async confirmClearCache(text: boolean): Promise<void> {
    if (this.cacheClearing) return;
    const dark = this.appDarkMode;
    try {
      const result = await promptAction.showDialog({
        title: text ? '清理小说自动缓存？' : '清理漫画自动缓存？',
        message: text ? '删除阅读时自动缓存的正文。手动离线内容、本地书和正在使用的书会保留。之后阅读可能需要联网。' :
          '删除自动缓存的图片和可重新生成的处理结果，保留离线原图及正在使用、最近 10 分钟访问的图片。之后阅读可能需要联网补图。',
        buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(dark) },
          { text: '清理', color: ThemeRuntime.dangerColor(dark) }]
      });
      if (result.index !== 1) return;
    } catch (e) {
      console.warn('显示清理缓存确认失败:', e);
      return;
    }
    this.cacheClearing = true;
    try {
      const cleanup = text ? await ReaderCacheBudget.clearText() : await ReaderCacheBudget.clearComic();
      HdsFeedback.showToast(this.cleanupSummary(cleanup));
    } catch (e) {
      HdsFeedback.showToast(`清理失败：${(e as Error).message}`);
    } finally {
      this.cacheClearing = false;
    }
    await this.refreshCacheUsage();
  }

  async confirmClearOffline(): Promise<void> {
    if (this.cacheClearing) return;
    try {
      const answer = await promptAction.showDialog({
        title: '删除离线内容？',
        message: '删除手动缓存的在线小说正文与漫画原图，之后需要联网重新缓存。本地导入书和正在使用的内容会保留。',
        buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.appDarkMode) },
          { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
      });
      if (answer.index !== 1) return;
      this.cacheClearing = true;
      HdsFeedback.showToast(this.cleanupSummary(await ReaderCacheBudget.clearOffline()));
    } catch (e) { HdsFeedback.showToast('删除离线内容失败'); }
    finally { this.cacheClearing = false; }
    await this.refreshCacheUsage();
  }

  cleanupSummary(cleanup: ReaderCacheCleanup): string {
    const parts: string[] = [`已清理 ${ReaderCacheBudgetPolicy.formatBytes(cleanup.releasedBytes)} 数据`];
    if (cleanup.protectedCount > 0) parts.push(`使用中保留 ${cleanup.protectedCount} 项`);
    if (cleanup.failed > 0) parts.push(`${cleanup.failed} 项删除失败`);
    return parts.join('，');
  }

  lanReaderUrl(): string {

    return this.lanReaderAddress;
  }

  @Builder
  lanReaderPasswordRow() {
    Column() {
      Text('访问密码（可选）')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Row({ space: AppSpacing.MD }) {
        TextInput({ text: this.lanReaderPasswordDraft, placeholder: '留空则无需密码' })
          .type(InputType.Password)
          .layoutWeight(1)
          .onChange((value: string) => this.lanReaderPasswordDraft = value)
        Button(this.lanReaderPassword ? '修改' : '设置')
          .fontSize(AppFontSize.BODY)
          .onClick(() => this.saveLanReaderPassword())
        if (this.lanReaderPassword) {
          Button('清除')
            .fontSize(AppFontSize.BODY)
            .onClick(() => {
              this.lanReaderPasswordDraft = '';
              this.saveLanReaderPassword();
            })
        }
      }
      .width('100%')
      .margin({ top: AppSpacing.MD })
      Text(this.lanReaderPasswordUnreadable ? '已保存的密码无法读取，浏览器访问已锁定，请重新设置密码' :
        (this.lanReaderPassword ? '已设置密码，访问地址无需携带 token' : '未设置密码，局域网内打开地址即可进入'))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .margin({ top: AppSpacing.XS })
        .width('100%')
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
  }

  async saveLanReaderPassword(): Promise<void> {
    const password = this.lanReaderPasswordDraft.trim();
    if (password.length > 64) {
      HdsFeedback.showToast('密码最多 64 个字符');
      return;
    }
    try {
      await LanReaderPasswordStore.save(getContext(this), password);
    } catch (error) {
      HdsFeedback.showToast(`访问密码保存失败：${(error as Error).message}`);
      return;
    }
    lanReaderServer.setPassword(password);
    this.lanReaderPasswordDraft = password;
    HdsFeedback.showToast(password ? '访问密码已设置' : '已取消访问密码');
  }

  @Builder
  lanReaderAddressRow() {
    Row() {
      Text(this.lanReaderUrl() || this.lanReaderStatus)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(2)
        .onClick(() => this.copyLanReaderAddress())
      Button() {
        Text('⧉')
          .fontSize(AppFontSize.TITLE)
      }
      .width(40)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.copyLanReaderAddress())
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .alignItems(VerticalAlign.Center)
  }

  async copyLanReaderAddress(): Promise<void> {
    const address = this.lanReaderUrl();
    if (!address) return;
    try {
      const board = pasteboard.getSystemPasteboard();
      await board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, address));
      HdsFeedback.showToast('访问地址已复制');
    } catch (error) {
      console.error('复制浏览器看书地址失败', error);
      HdsFeedback.showToast('复制失败，请长按地址复制');
    }
  }

  async setLanReaderEnabled(enabled: boolean): Promise<void> {
    this.lanReaderEnabled = enabled;
    if (!enabled) {
      await lanReaderServer.stop();
      return;
    }
    try {
      await lanReaderServer.start(getContext(this));
    } catch (error) {
      this.lanReaderEnabled = false;
      this.lanReaderStatus = '启动失败';
      console.error('浏览器看书服务启动失败', error);
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

  setFlatAutoHide(autoHide: boolean): void {
    if (autoHide === this.homeTabBarFlatAutoHide) return;
    HomeTabBarSettingsStore.saveFlatAutoHide(getContext(this), autoHide).catch((error: Error) => {
      console.warn('保存底栏滑动收起设置失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    });
  }

  previewTabIds(): string[] {
    const extra = HomeTabBarSettingsStore.normalizeExtraTab(this.homeExtraTab);
    return extra === HomeTabBarSettingsStore.EXTRA_NONE ? ['bookshelf', 'explore', 'mine'] :
      ['bookshelf', 'explore', extra, 'mine'];
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
