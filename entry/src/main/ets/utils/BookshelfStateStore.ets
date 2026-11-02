import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class BookshelfStateStore {
  private static readonly STORE_NAME: string = 'bookshelf_state';
  private static readonly KEY_ACTIVE_GROUP_ID: string = 'activeGroupId';
  private static readonly KEY_SORT_MODE: string = 'bookshelfSortMode';
  private static readonly KEY_TYPE_TAB: string = 'bookshelfTypeTab';
  private static readonly KEY_CATEGORY_EXPANDED: string = 'bookshelfCategoryExpanded';

  static normalizeSortMode(value: string | undefined | null): string {
    if (value === 'recentAdd' || value === 'name') {
      return value;
    }
    return 'recentRead';
  }

  static async loadActiveGroupId(context: Context): Promise<number> {
    const store = await preferences.getPreferences(context, BookshelfStateStore.STORE_NAME);
    const value = await store.get(BookshelfStateStore.KEY_ACTIVE_GROUP_ID, 0);
    return typeof value === 'number' && Number.isInteger(value) ? value : 0;
  }

  static async saveActiveGroupId(context: Context, groupId: number): Promise<void> {
    const store = await preferences.getPreferences(context, BookshelfStateStore.STORE_NAME);
    await store.put(BookshelfStateStore.KEY_ACTIVE_GROUP_ID, groupId);
    await store.flush();
  }

  /**
   * Load the bookshelf sort mode from Preferences. The fallback is used for existing
   * installations that only have the value in AppStorage/PersistentStorage, allowing
   * the explicit Preferences value to be introduced without resetting their choice.
   */
  static async loadSortMode(context: Context, fallback: string = 'recentRead'): Promise<string> {
    const store = await preferences.getPreferences(context, BookshelfStateStore.STORE_NAME);
    const value = await store.get(
      BookshelfStateStore.KEY_SORT_MODE,
      BookshelfStateStore.normalizeSortMode(fallback));
    return BookshelfStateStore.normalizeSortMode(typeof value === 'string' ? value : fallback);
  }

  static async saveSortMode(context: Context, mode: string): Promise<void> {
    const store = await preferences.getPreferences(context, BookshelfStateStore.STORE_NAME);
    await store.put(BookshelfStateStore.KEY_SORT_MODE, BookshelfStateStore.normalizeSortMode(mode));
    await store.flush();
  }

  /** 书架分类栏选中的类型（all/text/image/audio/video），由调用方校验是否认识。 */
  static async loadTypeTab(context: Context): Promise<string> {
    const store = await preferences.getPreferences(context, BookshelfStateStore.STORE_NAME);
    const value = await store.get(BookshelfStateStore.KEY_TYPE_TAB, 'all');
    return typeof value === 'string' && value ? value : 'all';
  }

  static async saveTypeTab(context: Context, typeTab: string): Promise<void> {
    const store = await preferences.getPreferences(context, BookshelfStateStore.STORE_NAME);
    await store.put(BookshelfStateStore.KEY_TYPE_TAB, typeTab);
    await store.flush();
  }

  /** 分类栏是否展开；旧版本只存在 PersistentStorage 里，偏好里还没有时沿用 fallback。 */
  static async loadCategoryExpanded(context: Context, fallback: boolean = true): Promise<boolean> {
    const store = await preferences.getPreferences(context, BookshelfStateStore.STORE_NAME);
    const value = await store.get(BookshelfStateStore.KEY_CATEGORY_EXPANDED, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  static async saveCategoryExpanded(context: Context, expanded: boolean): Promise<void> {
    const store = await preferences.getPreferences(context, BookshelfStateStore.STORE_NAME);
    await store.put(BookshelfStateStore.KEY_CATEGORY_EXPANDED, expanded);
    await store.flush();
  }
}
