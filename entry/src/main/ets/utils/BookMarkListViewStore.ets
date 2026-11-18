import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * “我的标记”页上次用的布局（读书手账 / 卡片列表 / 封面墙），只存本机。默认读书手账。
 * 写进 Preferences 而不是 PersistentStorage：后者改过的值重启后会回到默认。
 */
export class BookMarkListViewStore {
  static readonly JOURNAL: string = 'journal';
  static readonly WALL: string = 'wall';
  static readonly LIST: string = 'list';
  private static readonly STORE_NAME: string = 'book_mark_list';
  private static readonly KEY: string = 'view';
  /** 进程内已知的值；空串表示还没读过。 */
  private static cached: string = '';

  static normalize(view: string): string {
    return view === BookMarkListViewStore.WALL || view === BookMarkListViewStore.LIST ? view :
      BookMarkListViewStore.JOURNAL;
  }

  static async load(context: Context): Promise<string> {
    if (BookMarkListViewStore.cached) return BookMarkListViewStore.cached;
    try {
      const store = await preferences.getPreferences(context, BookMarkListViewStore.STORE_NAME);
      const value = await store.get(BookMarkListViewStore.KEY, BookMarkListViewStore.JOURNAL);
      // 读的途中用户已经切过视图，就以切过的为准。
      if (!BookMarkListViewStore.cached) {
        BookMarkListViewStore.cached = BookMarkListViewStore.normalize(typeof value === 'string' ? value : '');
      }
      return BookMarkListViewStore.cached;
    } catch (error) {
      console.warn('读取我的标记视图失败:', error);
      return BookMarkListViewStore.cached || BookMarkListViewStore.JOURNAL;
    }
  }

  static async save(context: Context, view: string): Promise<void> {
    const value = BookMarkListViewStore.normalize(view);
    BookMarkListViewStore.cached = value;
    try {
      const store = await preferences.getPreferences(context, BookMarkListViewStore.STORE_NAME);
      await store.put(BookMarkListViewStore.KEY, value);
      await store.flush();
    } catch (error) {
      console.warn('保存我的标记视图失败:', error);
    }
  }
}
