import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ReaderPdfSettings } from './ReaderPdfSettings';

/** Shares the existing preference file, so full app backup/restore includes PDF defaults. */
export class ReaderPdfSettingsStore {
  private static readonly STORE_NAME: string = 'reader_settings';
  private static readonly KEY: string = 'readerPdfSettings';
  private static pendingSave: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<ReaderPdfSettings> {
    await ReaderPdfSettingsStore.pendingSave.catch((): void => {});
    try {
      const store = await preferences.getPreferences(context, ReaderPdfSettingsStore.STORE_NAME);
      const raw = await store.get(ReaderPdfSettingsStore.KEY, '');
      return ReaderPdfSettings.parse(typeof raw === 'string' ? raw : '');
    } catch (error) { console.warn('[PDF] defaults load failed:', error); return new ReaderPdfSettings(); }
  }

  static save(context: Context, settings: ReaderPdfSettings): Promise<void> {
    const raw = settings.toJson();
    const task = ReaderPdfSettingsStore.pendingSave.catch((): void => {}).then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ReaderPdfSettingsStore.STORE_NAME);
      await store.put(ReaderPdfSettingsStore.KEY, raw);
      await store.flush();
    });
    ReaderPdfSettingsStore.pendingSave = task;
    return task;
  }
}
