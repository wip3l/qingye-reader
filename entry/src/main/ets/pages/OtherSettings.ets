import { promptAction, router } from '@kit.ArkUI';
import { SmartGripSettingsStore } from '../utils/SmartGripSettingsStore';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ReaderCacheBudget, ReaderCacheCleanup } from '../core/book/ReaderCacheBudget';
import { ReaderCacheBudgetPolicy } from '../core/book/ReaderCacheBudgetPolicy';
import { AudioOfflineStore } from '../core/book/AudioOfflineStore';

/** 我的 › 其他设置：数据导入导出、缓存、交互。外观相关的在“外观”，在线阅读有自己的入口，试验性功能在“实验室”。 */
@Entry
@Component
struct OtherSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('smartGripEnabled') smartGripEnabled: boolean = true;
  /** 缓存只来自网页解析的内容，开关关闭时整组不显示。 */
  @StorageProp('webParseEnabled') webParseEnabled: boolean = false;
  /** -1 表示还在统计。 */
  @State textCacheBytes: number = -1;
  @State comicCacheBytes: number = -1;
  @State offlineBytes: number = -1;
  @State audioOfflineBytes: number = -1;
  @State audioOfflineAutoBytes: number = 0;
  @State audioOfflineBooks: number = 0;
  @State audioOfflineChapters: number = 0;
  @State cacheClearing: boolean = false;

  aboutToAppear(): void {
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
    if (this.webParseEnabled) this.refreshCacheUsage();
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
        description: this.webParseEnabled ? '从备份文件导入书源、书架、进度、本地图书和设置' :
          '从备份文件导入书架、进度、本地图书和设置',
        onTap: () => {
          router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'import' } });
        }
      })
      SettingNavRow({
        title: '数据导出',
        description: this.webParseEnabled ? '将书源、书架、进度、本地图书和设置导出为备份' :
          '将书架、进度、本地图书和设置导出为备份',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'export' } });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    if (this.webParseEnabled) {
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
    }

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
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.XXL })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
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
}
