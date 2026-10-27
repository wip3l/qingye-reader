import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ReaderKeyboard, ReaderKeyboardSettings } from '../core/reader/ReaderKeyboard';

export class ReaderKeyboardSettingsStore {
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<ReaderKeyboardSettings> {
    await ReaderKeyboardSettingsStore.writes;
    const store = await preferences.getPreferences(context, 'reader_keyboard');
    const settings = new ReaderKeyboardSettings();
    settings.enabled = await store.get('enabled', settings.enabled) as boolean;
    settings.previous = await store.get('previous', settings.previous) as number;
    settings.next = await store.get('next', settings.next) as number;
    return ReaderKeyboard.normalize(settings);
  }

  static save(context: Context, settings: ReaderKeyboardSettings): Promise<void> {
    const snapshot = ReaderKeyboard.normalize(settings);
    const write = ReaderKeyboardSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, 'reader_keyboard');
      await store.put('enabled', snapshot.enabled);
      await store.put('previous', snapshot.previous);
      await store.put('next', snapshot.next);
      await store.flush();
    });
    ReaderKeyboardSettingsStore.writes = write.catch((): void => {});
    return write;
  }
}
