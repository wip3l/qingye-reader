import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { readStatsTracker } from '../core/stats/ReadStatsTracker';

/**
 * 阅读统计的本机开关：“记录阅读时长”总开关与“听书计入时长”。
 * 只存本机、不跟账号同步——统计本来就按设备分开记。关闭只停计时，已有记录照常查看、分享和同步。
 * AppStorage 只负责通知界面，真正生效的是 readStatsTracker。
 */
export class ReadStatsSettingsStore {
  static readonly STORE_NAME: string = 'read_stats_settings';
  static readonly KEY_RECORDING: string = 'readStatsRecording';
  static readonly KEY_COUNT_LISTENING: string = 'readStatsCountListening';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const revision = ReadStatsSettingsStore.revision;
    const store = await preferences.getPreferences(context, ReadStatsSettingsStore.STORE_NAME);
    const recording = await store.get(ReadStatsSettingsStore.KEY_RECORDING, true);
    const listening = await store.get(ReadStatsSettingsStore.KEY_COUNT_LISTENING, true);
    if (revision !== ReadStatsSettingsStore.revision) return;
    // 启动时读到“已关闭”，读盘前那几毫秒的计时直接丢掉，不落一条零碎记录。
    ReadStatsSettingsStore.apply(recording !== false, listening !== false, false);
  }

  static isRecording(): boolean {
    return AppStorage.get<boolean>(ReadStatsSettingsStore.KEY_RECORDING) !== false;
  }

  static isCountingListening(): boolean {
    return AppStorage.get<boolean>(ReadStatsSettingsStore.KEY_COUNT_LISTENING) !== false;
  }

  static save(context: Context, recording: boolean, listening: boolean): Promise<void> {
    ++ReadStatsSettingsStore.revision;
    ReadStatsSettingsStore.apply(recording, listening, true);
    const write = ReadStatsSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ReadStatsSettingsStore.STORE_NAME);
      await store.put(ReadStatsSettingsStore.KEY_RECORDING, recording);
      await store.put(ReadStatsSettingsStore.KEY_COUNT_LISTENING, listening);
      await store.flush();
    });
    ReadStatsSettingsStore.writes = write.catch(() => {});
    return write;
  }

  private static apply(recording: boolean, listening: boolean, keepCurrent: boolean): void {
    AppStorage.setOrCreate(ReadStatsSettingsStore.KEY_RECORDING, recording);
    AppStorage.setOrCreate(ReadStatsSettingsStore.KEY_COUNT_LISTENING, listening);
    readStatsTracker.setRecordingOptions(recording, listening, keepCurrent);
  }
}
