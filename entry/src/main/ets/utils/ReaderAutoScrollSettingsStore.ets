import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ReaderAutoScrollClock } from '../core/reader/ReaderAutoScrollClock';

/** 平滑滚动：整屏文字匀速上移。百叶窗：画面不动，读过的行逐行翻成下一页。 */
export const READER_AUTO_SCROLL_MODE_SCROLL: string = 'scroll';
export const READER_AUTO_SCROLL_MODE_BLINDS: string = 'blinds';

/** Only speed and mode are durable. A reading session must always be started explicitly. */
export class ReaderAutoScrollSettingsStore {
  private static writes: Promise<void> = Promise.resolve();

  static normalizeMode(value: string): string {
    return value === READER_AUTO_SCROLL_MODE_BLINDS ? READER_AUTO_SCROLL_MODE_BLINDS : READER_AUTO_SCROLL_MODE_SCROLL;
  }

  static async load(context: Context): Promise<number> {
    await ReaderAutoScrollSettingsStore.writes;
    const store = await preferences.getPreferences(context, 'reader_auto_scroll');
    return ReaderAutoScrollClock.normalizeSpeed(Number(await store.get('linesPerMinute', 20)));
  }

  /** 百叶窗叶片效果，取值与 READER_BLINDS_EFFECT_* 一致：flip 逐行翻转（默认）、fade 逐行淡入、wipe 平滑擦除。 */
  static normalizeBlindsEffect(value: string): string {
    return value === 'fade' || value === 'wipe' ? value : 'flip';
  }

  static async loadBlindsEffect(context: Context): Promise<string> {
    await ReaderAutoScrollSettingsStore.writes;
    const store = await preferences.getPreferences(context, 'reader_auto_scroll');
    return ReaderAutoScrollSettingsStore.normalizeBlindsEffect(String(await store.get('blindsEffect', 'flip')));
  }

  static saveBlindsEffect(context: Context, effect: string): Promise<void> {
    return ReaderAutoScrollSettingsStore.enqueue(context, 'blindsEffect',
      ReaderAutoScrollSettingsStore.normalizeBlindsEffect(effect));
  }

  static async loadMode(context: Context): Promise<string> {
    await ReaderAutoScrollSettingsStore.writes;
    const store = await preferences.getPreferences(context, 'reader_auto_scroll');
    return ReaderAutoScrollSettingsStore.normalizeMode(String(await store.get('mode', READER_AUTO_SCROLL_MODE_SCROLL)));
  }

  static save(context: Context, speed: number): Promise<void> {
    const value = ReaderAutoScrollClock.normalizeSpeed(speed);
    return ReaderAutoScrollSettingsStore.enqueue(context, 'linesPerMinute', value);
  }

  static saveMode(context: Context, mode: string): Promise<void> {
    return ReaderAutoScrollSettingsStore.enqueue(context, 'mode', ReaderAutoScrollSettingsStore.normalizeMode(mode));
  }

  private static enqueue(context: Context, key: string, value: number | string): Promise<void> {
    const write = ReaderAutoScrollSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, 'reader_auto_scroll');
      await store.put(key, value);
      await store.flush();
    });
    ReaderAutoScrollSettingsStore.writes = write.catch((): void => {});
    return write;
  }
}
