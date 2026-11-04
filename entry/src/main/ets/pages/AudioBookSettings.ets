import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingSwitchRow } from '../components/common/SettingRow';
import { AudioOfflineStore } from '../core/book/AudioOfflineStore';
import { AudioBookSettingsStore } from '../utils/AudioBookSettingsStore';
import { AudioOfflineSettingsStore } from '../utils/AudioOfflineSettingsStore';
import { AudioPrefetch } from '../utils/AudioPrefetch';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';

/** 阅读与收听 → 有声书：打开时是否自动播放，以及离线下载的设备设置。离线音频的占用与清理在其他设置的缓存里。 */
@Entry
@Component
struct AudioBookSettingsPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageLink('audioBookAutoPlay') autoPlay: boolean = true;
  @StorageLink('audioOfflineWifiOnly') wifiOnly: boolean = false;
  @StorageLink('audioOfflineCapBytes') capBytes: number = 0;
  @StorageLink('audioPrefetchCount') prefetchCount: number = 0;

  onPageShow(): void {
    const context = this.getUIContext().getHostContext();
    if (context) syncSystemBars(context, this.darkMode);
  }

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private accentColor(): string {
    return ThemeRuntime.accentColor(this.darkMode);
  }

  private optionColor(selected: boolean): string {
    return selected ? this.accentColor() : ThemeRuntime.primaryTextColor(this.darkMode);
  }

  private prefetchLabel(count: number): string {
    return count > 0 ? `后 ${count} 章` : '关闭';
  }

  async pickPrefetch(): Promise<void> {
    const options = AudioOfflineSettingsStore.PREFETCH_OPTIONS;
    const current = AudioOfflineStore.prefetchCount();
    const buttons: promptAction.Button[] = options.map((count: number): promptAction.Button => ({
      text: `${count === current ? '✓ ' : ''}${count > 0 ? `提前下载后 ${count} 章` : '关闭'}`,
      color: this.optionColor(count === current)
    }));
    let index = -1;
    try {
      const result = await this.getUIContext().getPromptAction().showActionMenu({
        title: '边听边下：支持移动网络，会消耗流量；听完自动删除，手动下载的不受影响',
        buttons: [buttons[0], buttons[1], buttons[2], buttons[3]]
      });
      index = result.index;
    } catch (_) {
      return;
    }
    if (index < 0 || index >= options.length) return;
    try {
      await AudioOfflineSettingsStore.savePrefetch(this.context(), options[index]);
    } catch (error) {
      console.warn('保存边听边下失败:', error);
      HdsFeedback.showToast('边听边下设置保存失败，请重试');
      return;
    }
    // 开启后从正在听的那本书下一次切章起生效；关闭则立即停掉还没下完的预下载。
    if (options[index] <= 0) AudioPrefetch.get().cancel();
  }

  async pickCap(): Promise<void> {
    const options = AudioOfflineSettingsStore.CAP_OPTIONS;
    const buttons: promptAction.Button[] = options.map((bytes: number): promptAction.Button => ({
      text: `${bytes === this.capBytes ? '✓ ' : ''}${AudioOfflineSettingsStore.capLabel(bytes)}`,
      color: this.optionColor(bytes === this.capBytes)
    }));
    try {
      const result = await this.getUIContext().getPromptAction().showActionMenu({
        title: '离线音频上限',
        buttons: [buttons[0], buttons[1], buttons[2], buttons[3], buttons[4]]
      });
      if (result.index >= 0 && result.index < options.length) {
        await AudioOfflineSettingsStore.saveCap(this.context(), options[result.index]);
      }
    } catch (_) {
      // 点空白处取消。
    }
  }

  @Builder
  sectionTitle(label: string) {
    Text(label).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.darkMode)).width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  pageContent() {
    this.sectionTitle('播放')
    Column() {
      SettingSwitchRow({
        title: '打开时自动播放',
        description: '关闭后打开有声书只停在上次听到的位置，点播放才开始',
        isOn: this.autoPlay,
        showDivider: false,
        onChange: (value: boolean): void => {
          AudioBookSettingsStore.saveAutoPlay(this.context(), value)
            .catch((error: Error) => console.warn('保存自动播放失败:', error));
        }
      })
    }.width('calc(100% - 24vp)').margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius()).clip(true).backgroundColor(ThemeRuntime.cardColor(this.darkMode))

    this.sectionTitle('离线下载')
    Column() {
      SettingNavRow({
        title: '边听边下',
        description: '提前下载正在听的书后面几章，支持移动网络；听完自动删除',
        value: this.prefetchLabel(this.prefetchCount),
        onTap: (): void => {
          this.pickPrefetch().catch((error: Error) => console.warn('打开边听边下菜单失败:', error));
        }
      })
      SettingSwitchRow({
        title: '手动下载仅用 Wi-Fi',
        description: '手动下载在移动网络下等待 Wi-Fi；关闭后用流量下载前会先确认。边听边下不受此限制',
        isOn: this.wifiOnly,
        onChange: (value: boolean): void => {
          AudioOfflineSettingsStore.saveWifiOnly(this.context(), value)
            .catch((error: Error) => console.warn('保存仅 Wi-Fi 下载失败:', error));
        }
      })
      SettingNavRow({
        title: '离线音频上限',
        description: '超出后先删最早的边听边下章节，仍不够时停止下载',
        value: AudioOfflineSettingsStore.capLabel(this.capBytes),
        showDivider: false,
        onTap: (): void => {
          this.pickCap().catch((error: Error) => console.warn('打开离线音频上限菜单失败:', error));
        }
      })
    }.width('calc(100% - 24vp)').margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius()).clip(true).backgroundColor(ThemeRuntime.cardColor(this.darkMode))

    Text('离线音频占用的空间可在“其他设置 › 缓存”中查看和清理。')
      .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.darkMode)).width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.XXL })
  }

  build() {
    Stack() {
      PageScaffold({ title: '有声书设置', content: (): void => { this.pageContent(); } })
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
