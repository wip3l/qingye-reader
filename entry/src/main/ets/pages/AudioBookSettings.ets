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
import { SubtitleModelStore } from '../utils/subtitle/SubtitleModelStore';
import { AudioSubtitleService } from '../utils/subtitle/AudioSubtitleService';

/**
 * 阅读与收听 → 有声书：打开时是否自动播放、离线下载的设备设置，以及 AI 字幕的识别模型。
 * 离线音频的占用与清理在其他设置的缓存里。
 */
@Entry
@Component
struct AudioBookSettingsPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageLink('audioBookAutoPlay') autoPlay: boolean = true;
  @StorageLink('audioOfflineWifiOnly') wifiOnly: boolean = false;
  @StorageLink('audioOfflineCapBytes') capBytes: number = 0;
  @StorageLink('audioPrefetchCount') prefetchCount: number = 0;
  @StorageLink('audioSubtitlePrefetchNext') subtitlePrefetchNext: boolean = true;
  @StorageProp('subtitleModelState') subtitleModelState: string = SubtitleModelStore.NONE;
  @StorageProp('subtitleModelReceived') subtitleModelReceived: number = 0;
  @StorageProp('subtitleModelError') subtitleModelError: string = '';
  @State subtitleImporting: string = '';

  aboutToAppear(): void {
    SubtitleModelStore.refresh();
  }

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

  private subtitleModelDescription(): string {
    if (this.subtitleImporting) return this.subtitleImporting;
    if (this.subtitleModelState === SubtitleModelStore.DOWNLOADING) {
      const total = SubtitleModelStore.totalBytes();
      return `正在下载 ${Math.round(this.subtitleModelReceived / 1024 / 1024)} / ${SubtitleModelStore.totalLabel()}` +
        `（${Math.floor(this.subtitleModelReceived * 100 / total)}%）`;
    }
    if (this.subtitleModelState === SubtitleModelStore.INSTALLED) {
      return `已安装 · ${SubtitleModelStore.totalLabel()} · 本地识别，不上传音频`;
    }
    return this.subtitleModelError ? `下载失败：${this.subtitleModelError}` :
      `未安装 · 约 ${SubtitleModelStore.totalLabel()}，在听书面板选“字幕”时也可下载`;
  }

  private subtitleModelAction(): string {
    if (this.subtitleModelState === SubtitleModelStore.DOWNLOADING) return '取消';
    return this.subtitleModelState === SubtitleModelStore.INSTALLED ? '删除' : '下载';
  }

  async onSubtitleModelTap(): Promise<void> {
    if (this.subtitleImporting) return;
    if (this.subtitleModelState === SubtitleModelStore.DOWNLOADING) {
      SubtitleModelStore.cancel();
      return;
    }
    const prompt = this.getUIContext().getPromptAction();
    if (this.subtitleModelState === SubtitleModelStore.INSTALLED) {
      try {
        const result = await prompt.showDialog({
          title: '删除字幕模型？',
          message: `释放约 ${SubtitleModelStore.totalLabel()}。已经生成的字幕会保留，之后要再识别新章节需重新下载。`,
          buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.darkMode) },
            { text: '删除', color: ThemeRuntime.dangerColor(this.darkMode) }]
        });
        if (result.index !== 1) return;
      } catch (_) {
        return;
      }
      AudioSubtitleService.get().onModelRemoved();
      SubtitleModelStore.remove();
      HdsFeedback.showToast('已删除字幕模型');
      return;
    }
    if (AudioOfflineStore.network() === 'cellular') {
      try {
        const result = await prompt.showDialog({
          title: '正在使用移动网络',
          message: `字幕模型约 ${SubtitleModelStore.totalLabel()}，会消耗较多流量。确定现在下载？`,
          buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.darkMode) },
            { text: '用流量下载', color: ThemeRuntime.dangerColor(this.darkMode) }]
        });
        if (result.index !== 1) return;
      } catch (_) {
        return;
      }
    }
    AudioSubtitleService.get().downloadModel();
  }

  async importSubtitleModel(): Promise<void> {
    if (this.subtitleImporting) return;
    if (this.subtitleModelState === SubtitleModelStore.DOWNLOADING) {
      HdsFeedback.showToast('模型正在下载，请先取消下载');
      return;
    }
    try {
      const matched = await SubtitleModelStore.importFiles(this.context(), (text: string): void => {
        this.subtitleImporting = text;
      });
      this.subtitleImporting = '';
      if (matched < 0) return;
      if (SubtitleModelStore.installed()) {
        HdsFeedback.showToast('字幕模型已就绪');
        AudioSubtitleService.get().retry();
      } else if (matched === 0) {
        HdsFeedback.showToast('没有认出字幕模型文件，请选择未改动过的原文件');
      } else {
        HdsFeedback.showToast(`已导入 ${matched} 个文件，还缺：${SubtitleModelStore.missingNames().join('、')}`);
      }
    } catch (error) {
      this.subtitleImporting = '';
      HdsFeedback.showToast((error as Error)?.message || '导入失败，请重试');
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
        description: '关闭后打开有声书不自动播放，停在上次位置',
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
        description: '提前下载后面几章（含移动网络），听完自动删除',
        value: this.prefetchLabel(this.prefetchCount),
        onTap: (): void => {
          this.pickPrefetch().catch((error: Error) => console.warn('打开边听边下菜单失败:', error));
        }
      })
      SettingSwitchRow({
        title: '手动下载仅用 Wi-Fi',
        description: '关闭后用流量下载前会先确认；边听边下不受限',
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
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD })

    this.sectionTitle('AI 字幕')
    Column() {
      SettingNavRow({
        title: '识别模型',
        description: this.subtitleModelDescription(),
        value: this.subtitleImporting ? '' : this.subtitleModelAction(),
        onTap: (): void => {
          this.onSubtitleModelTap().catch((error: Error) => console.warn('处理字幕模型失败:', error));
        }
      })
      SettingSwitchRow({
        title: '提前识别下一章',
        description: '当前章识别完后，接着处理已下载的下一章开头',
        isOn: this.subtitlePrefetchNext,
        onChange: (value: boolean): void => {
          AudioBookSettingsStore.saveSubtitlePrefetchNext(this.context(), value)
            .catch((error: Error) => console.warn('保存提前识别下一章失败:', error));
        }
      })
      SettingNavRow({
        title: '导入模型文件',
        description: '网络不好时，选择在别处下载好的识别模型、tokens.txt 和标点模型（可多选）',
        value: '选择',
        showDivider: false,
        onTap: (): void => {
          this.importSubtitleModel().catch((error: Error) => console.warn('导入字幕模型失败:', error));
        }
      })
    }.width('calc(100% - 24vp)').margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius()).clip(true).backgroundColor(ThemeRuntime.cardColor(this.darkMode))

    Text('字幕在听书面板封面下方的“字幕”页签里显示，识别全在手机上完成。在线章节会先按边听边下取本章音频，听过后自动删除。')
      .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.darkMode)).width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.XXL })
  }

  build() {
    Stack() {
      PageScaffold({ title: '有声书设置', content: (): void => { this.pageContent(); } })
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
