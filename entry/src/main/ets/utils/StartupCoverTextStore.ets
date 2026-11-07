import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { CloudSyncChangeTracker } from '../account/CloudSyncChangeTracker';
import { ThemeIds } from '../theme/ThemeModels';

export class StartupCoverTextEntry {
  themeId: string = '';
  title: string = '';
  subtitle: string = '';
}

export class StartupCoverTextStore {
  static readonly STORAGE_RAW: string = 'startupCoverTextsRaw';
  static readonly STORAGE_REVISION: string = 'startupCoverTextsRevision';
  private static readonly STORE_NAME: string = 'startup_cover_texts';
  private static readonly KEY_RAW: string = 'texts';

  static async load(context: Context): Promise<string> {
    const store = await preferences.getPreferences(context, StartupCoverTextStore.STORE_NAME);
    const value = await store.get(StartupCoverTextStore.KEY_RAW, '');
    const raw = typeof value === 'string' ? value : '';
    StartupCoverTextStore.applyToStorage(raw);
    return raw;
  }

  static applyToStorage(raw: string): void {
    AppStorage.setOrCreate(StartupCoverTextStore.STORAGE_RAW, raw || '');
    AppStorage.setOrCreate(StartupCoverTextStore.STORAGE_REVISION,
      AppStorage.get<number>(StartupCoverTextStore.STORAGE_REVISION) || 0);
  }

  static title(themeId: string, fallback: string): string {
    const entry = StartupCoverTextStore.find(StartupCoverTextStore.entries(), themeId);
    return entry ? entry.title : fallback;
  }

  static subtitle(themeId: string, fallback: string): string {
    const entry = StartupCoverTextStore.find(StartupCoverTextStore.entries(), themeId);
    return entry ? entry.subtitle : fallback;
  }

  static defaultSubtitle(themeId: string): string {
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE) return '字里山河，耳畔书声';
    if (themeId === ThemeIds.CELESTIAL_VAULT) return '以星为签，此生珍藏';
    if (themeId === ThemeIds.CLASSIC_BLUE) return '在字里，遇见辽阔';
    if (themeId === ThemeIds.WARM_PAPER) return '一页暖光，静读时光';
    if (themeId === ThemeIds.FOREST_MIST) return '林深见字，雾散成章';
    if (themeId === ThemeIds.INK_WASH) return '墨落有声，纸上见山';
    if (themeId === ThemeIds.NEON_NIGHT) return '穿过夜色，抵达故事';
    if (themeId === ThemeIds.STRAWBERRY_CREAM) return '甜一点，也轻一点';
    if (themeId === ThemeIds.CRIMSON_ARCHIVE) return '翻开档案，读取真相';
    if (themeId === ThemeIds.PLUM_TEA) return '梅影入卷，茶烟伴读';
    if (themeId === ThemeIds.ROSE_LETTER) return '每一页，都是来信';
    if (themeId === ThemeIds.MOON_CRANE) return '月照书海，鹤引星河';
    if (themeId === ThemeIds.SWORD_FROST) return '一页入江湖，万卷见天地';
    if (themeId === ThemeIds.QINGLUAN_WATER) return '心有清光，自可照见江湖';
    if (themeId === ThemeIds.CAT_PIPI) return '皮皮陪你，慢慢翻页';
    if (themeId === ThemeIds.AZURE_MECHA) return '系统就绪，向下一章出击';
    if (themeId === ThemeIds.STARWISH_MAGIC) return '许个愿，翻开下一页';
    if (themeId === ThemeIds.LETTERPRESS_PAGE) return '翻开这一页，世界安静下来';
    return '';
  }

  static async update(context: Context, themeId: string, title: string, subtitle: string): Promise<void> {
    const normalizedId = (themeId || '').trim();
    if (!normalizedId) return;
    const entries = StartupCoverTextStore.entries();
    let entry = StartupCoverTextStore.find(entries, normalizedId);
    if (!entry) {
      entry = new StartupCoverTextEntry();
      entry.themeId = normalizedId;
      entries.push(entry);
    }
    entry.title = (title || '').trim();
    entry.subtitle = (subtitle || '').trim();
    const raw = JSON.stringify(entries);
    const store = await preferences.getPreferences(context, StartupCoverTextStore.STORE_NAME);
    await store.put(StartupCoverTextStore.KEY_RAW, raw);
    await store.flush();
    AppStorage.setOrCreate(StartupCoverTextStore.STORAGE_RAW, raw);
    AppStorage.setOrCreate(StartupCoverTextStore.STORAGE_REVISION,
      (AppStorage.get<number>(StartupCoverTextStore.STORAGE_REVISION) || 0) + 1);
    CloudSyncChangeTracker.markApplicationPreferenceChanged();
  }

  private static entries(): StartupCoverTextEntry[] {
    const raw = AppStorage.get<string>(StartupCoverTextStore.STORAGE_RAW) || '';
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw) as StartupCoverTextEntry[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return [];
    }
  }

  private static find(entries: StartupCoverTextEntry[], themeId: string): StartupCoverTextEntry | null {
    for (const entry of entries) {
      if (entry && entry.themeId === themeId) return entry;
    }
    return null;
  }
}
