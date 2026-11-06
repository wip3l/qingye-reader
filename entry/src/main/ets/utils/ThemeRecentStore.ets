import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/** 最近应用过的内置主题 ID，最近的在前；主题页“已拥有”只露出几套时按它排。 */
export class ThemeRecentStore {
  private static readonly STORE_NAME: string = 'theme_recent_uses';
  private static readonly KEY_IDS: string = 'ids';
  private static readonly MAX_COUNT: number = 40;

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

  static async record(context: Context, themeId: string): Promise<string[]> {
    const ids = (await ThemeRecentStore.load(context)).filter((id: string): boolean => id !== themeId);
    ids.unshift(themeId);
    const trimmed = ids.slice(0, ThemeRecentStore.MAX_COUNT);
    try {
      const store = await preferences.getPreferences(context, ThemeRecentStore.STORE_NAME);
      await store.put(ThemeRecentStore.KEY_IDS, JSON.stringify(trimmed));
      await store.flush();
    } catch (e) {
      console.warn('记录最近使用主题失败:', e);
    }
    return trimmed;
  }
}
