import { preferences } from '@kit.ArkData';
import { LocalTtsModel, LocalTtsModels } from './LocalTtsModels';

/**
 * 当前选中的离线音色。朗读设置的其他字段由各页面整体读写（TtsSettingsStore.save），
 * 这个键单独存取，免得没改到它的页面保存时把它覆盖掉。选系统/云端/自定义/MiMo 音色时要调 clear。
 */
export class LocalTtsSelection {
  static readonly STORAGE_KEY: string = 'ttsLocalVoiceId';
  private static readonly STORE_NAME: string = 'tts_settings';

  static async load(context: Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, LocalTtsSelection.STORE_NAME);
      const id = await store.get(LocalTtsSelection.STORAGE_KEY, '') as string;
      AppStorage.setOrCreate(LocalTtsSelection.STORAGE_KEY, id || '');
    } catch (error) {
      console.warn('[LocalTts] load selection failed:', error);
      AppStorage.setOrCreate(LocalTtsSelection.STORAGE_KEY, '');
    }
  }

  static selectedId(): string {
    return (AppStorage.get<string>(LocalTtsSelection.STORAGE_KEY) || '').trim();
  }

  /** 选中且已下载的离线音色；选了但文件已删掉时视为没选。 */
  static current(): LocalTtsModel | undefined {
    const id = LocalTtsSelection.selectedId();
    if (!id || !LocalTtsModels.isInstalled(id)) return undefined;
    const model = LocalTtsModels.find(id);
    return model && LocalTtsModels.isEnabled(model) ? model : undefined;
  }

  static isSelected(model: LocalTtsModel): boolean {
    return LocalTtsSelection.selectedId() === model.id;
  }

  static select(context: Context, id: string): void {
    LocalTtsSelection.write(context, id);
  }

  static clear(context: Context): void {
    if (!LocalTtsSelection.selectedId()) return;
    LocalTtsSelection.write(context, '');
  }

  private static write(context: Context, id: string): void {
    AppStorage.setOrCreate(LocalTtsSelection.STORAGE_KEY, id);
    preferences.getPreferences(context, LocalTtsSelection.STORE_NAME).then(async (store): Promise<void> => {
      await store.put(LocalTtsSelection.STORAGE_KEY, id);
      await store.flush();
    }).catch((error: Error): void => {
      console.warn('[LocalTts] save selection failed:', error);
    });
  }
}
