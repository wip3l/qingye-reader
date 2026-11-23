import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 主题页只记在本机的使用习惯：最近应用过的主题与方案（最近的在前）及各自的应用时间，
 * 以及“我的方案”选用的排序。主题用主题 ID，方案用 scheme:<方案 ID>。
 */
export class ThemeRecentStore {
  private static readonly STORE_NAME: string = 'theme_recent_uses';
  private static readonly KEY_IDS: string = 'ids';
  private static readonly KEY_TIMES: string = 'used_at';
  private static readonly KEY_SCHEME_SORT: string = 'scheme_sort';
  // 方案最多 100 套，再加上已拥有的主题。
  private static readonly MAX_COUNT: number = 160;

  static schemeKey(schemeId: string): string {
    return `scheme:${schemeId}`;
  }

  static async load(context: Context): Promise<string[]> {
    try {
      const store = await preferences.getPreferences(context, ThemeRecentStore.STORE_NAME);
      const value = await store.get(ThemeRecentStore.KEY_IDS, '[]');
      const parsed = JSON.parse(typeof value === 'string' ? value : '[]') as string[];
      if (!Array.isArray(parsed)) return [];
      return parsed.filter((id: string): boolean => typeof id === 'string' && id.length > 0);
    } catch (e) {
      console.warn('读取最近使用主题失败:', e);
      return [];
    }
  }

  /** 各项最近一次应用的时间（毫秒）；早先只记了顺序的项没有时间。 */
  static async loadTimes(context: Context): Promise<Map<string, number>> {
    const times = new Map<string, number>();
    try {
      const store = await preferences.getPreferences(context, ThemeRecentStore.STORE_NAME);
      const value = await store.get(ThemeRecentStore.KEY_TIMES, '{}');
      const parsed = JSON.parse(typeof value === 'string' ? value : '{}') as Record<string, number>;
      if (parsed && typeof parsed === 'object') {
        for (const key of Object.keys(parsed)) {
          const at = parsed[key];
          if (typeof at === 'number' && at > 0) times.set(key, at);
        }
      }
    } catch (e) {
      console.warn('读取主题应用时间失败:', e);
    }
    return times;
  }

  static async record(context: Context, themeId: string): Promise<string[]> {
    const ids = (await ThemeRecentStore.load(context)).filter((id: string): boolean => id !== themeId);
    ids.unshift(themeId);
    const trimmed = ids.slice(0, ThemeRecentStore.MAX_COUNT);
    const times = await ThemeRecentStore.loadTimes(context);
    const kept: Record<string, number> = {};
    for (const id of trimmed) {
      const at = id === themeId ? Date.now() : times.get(id);
      if (at) kept[id] = at;
    }
    try {
      const store = await preferences.getPreferences(context, ThemeRecentStore.STORE_NAME);
      await store.put(ThemeRecentStore.KEY_IDS, JSON.stringify(trimmed));
      await store.put(ThemeRecentStore.KEY_TIMES, JSON.stringify(kept));
      await store.flush();
    } catch (e) {
      console.warn('记录最近使用主题失败:', e);
    }
    return trimmed;
  }

  static async loadSchemeSort(context: Context): Promise<string> {
    try {
      const store = await preferences.getPreferences(context, ThemeRecentStore.STORE_NAME);
      const value = await store.get(ThemeRecentStore.KEY_SCHEME_SORT, '');
      return typeof value === 'string' ? value : '';
    } catch (e) {
      console.warn('读取方案排序失败:', e);
      return '';
    }
  }

  static async saveSchemeSort(context: Context, sort: string): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, ThemeRecentStore.STORE_NAME);
      await store.put(ThemeRecentStore.KEY_SCHEME_SORT, sort);
      await store.flush();
    } catch (e) {
      console.warn('保存方案排序失败:', e);
    }
  }
}
