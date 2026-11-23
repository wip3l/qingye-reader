import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { Book, BookGroup } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { BookshelfStateStore } from './BookshelfStateStore';
import { NewBookGroup, NewBookGroupMode } from './NewBookGroup';

/** “新书默认分组”设置与“上次选的分组”，只存本机。规则见 NewBookGroup。 */
export class NewBookGroupStore {
  private static readonly STORE_NAME: string = 'new_book_group';
  private static readonly KEY_MODE: string = 'mode';
  private static readonly KEY_LAST_GROUP_ID: string = 'lastGroupId';

  static async loadMode(context: Context): Promise<NewBookGroupMode> {
    const store = await preferences.getPreferences(context, NewBookGroupStore.STORE_NAME);
    const value = await store.get(NewBookGroupStore.KEY_MODE, 'none');
    return NewBookGroup.normalizeMode(typeof value === 'string' ? value : 'none');
  }

  static async saveMode(context: Context, mode: string): Promise<void> {
    const store = await preferences.getPreferences(context, NewBookGroupStore.STORE_NAME);
    await store.put(NewBookGroupStore.KEY_MODE, NewBookGroup.normalizeMode(mode));
    await store.flush();
  }

  /** 详情页“放进分组”选完后记下，选“未分组”记 0。 */
  static async saveLastGroupId(context: Context, groupId: number): Promise<void> {
    const store = await preferences.getPreferences(context, NewBookGroupStore.STORE_NAME);
    await store.put(NewBookGroupStore.KEY_LAST_GROUP_ID, groupId > 0 ? groupId : 0);
    await store.flush();
  }

  private static async loadLastGroupId(store: preferences.Preferences): Promise<number> {
    const value = await store.get(NewBookGroupStore.KEY_LAST_GROUP_ID, 0);
    return typeof value === 'number' && Number.isInteger(value) ? value : 0;
  }

  /** 按设置算出新书应放进的分组；未分组返回 null。调用前数据库须已初始化。 */
  static async resolve(context: Context): Promise<BookGroup | null> {
    const store = await preferences.getPreferences(context, NewBookGroupStore.STORE_NAME);
    const modeValue = await store.get(NewBookGroupStore.KEY_MODE, 'none');
    const mode = NewBookGroup.normalizeMode(typeof modeValue === 'string' ? modeValue : 'none');
    if (mode === 'none') return null;
    const lastGroupId = mode === 'last' ? await NewBookGroupStore.loadLastGroupId(store) : 0;
    const shelfGroupId = mode === 'shelf' ? await BookshelfStateStore.loadActiveGroupId(context) : 0;
    const groups = await AppDatabase.getInstance().getCustomBookGroups();
    const groupId = NewBookGroup.pick(mode, lastGroupId, shelfGroupId,
      groups.map((group: BookGroup): number => group.groupId));
    return groups.find((group: BookGroup): boolean => group.groupId === groupId) ?? null;
  }

  /**
   * 给即将入架的新书（或试读转正的书）套上默认分组，返回分组名；未分组或读设置失败返回空串、分组不动。
   * 调用方随后自己写库。
   */
  static async apply(context: Context, book: Book): Promise<string> {
    try {
      const group = await NewBookGroupStore.resolve(context);
      if (!group) return '';
      book.group = group.groupId;
      return group.groupName;
    } catch (error) {
      console.warn('读取新书默认分组失败:', error);
      return '';
    }
  }
}
