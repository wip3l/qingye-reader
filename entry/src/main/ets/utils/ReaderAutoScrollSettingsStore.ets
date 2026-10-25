import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ReaderAutoScrollClock } from '../core/reader/ReaderAutoScrollClock';

/** Only speed is durable. A reading session must always be started explicitly. */
export class ReaderAutoScrollSettingsStore {
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<number> {
    await ReaderAutoScrollSettingsStore.writes;
    const store = await preferences.getPreferences(context, 'reader_auto_scroll');
    return ReaderAutoScrollClock.normalizeSpeed(Number(await store.get('linesPerMinute', 20)));
  }

  static save(context: Context, speed: number): Promise<void> {
    const value = ReaderAutoScrollClock.normalizeSpeed(speed);
    const write = ReaderAutoScrollSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, 'reader_auto_scroll');
      await store.put('linesPerMinute', value);
      await store.flush();
    });
    ReaderAutoScrollSettingsStore.writes = write.catch((): void => {});
    return write;
  }
}
