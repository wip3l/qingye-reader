import { Book } from '@legado/sourceengine';
import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { BookshelfSortHelper } from './BookshelfSortHelper';
import { BookIdentity } from './BookIdentity';

/**
 * 封面模式“固定”下每本书的封面序号：按加入书架的先后依次编号，封面取 序号 % 张数。
 *
 * 序号记下来就不再变，所以排序方式、打开书改变阅读时间、置顶（会改 shelfModifiedTime）都不影响封面；
 * 删书后它的序号空出来，给下一本新加入的书用，不会让别的书错位。按作品（书名+作者+类型）记，换源不换封面；
 * 认不出作品的（本地书等）按 bookUrl 记。不在书架上的书没有序号，调用方退回按书哈希。进程内单例。
 */
export class ShelfCoverSlots {
  private static readonly STORE_NAME: string = 'shelf_cover_slots';
  private static readonly KEY_SLOTS: string = 'slots';
  /** BookCover 监听它重算封面。 */
  static readonly REVISION_KEY: string = 'shelfCoverSlotRevision';
  private static slots: Map<string, number> = new Map<string, number>();
  private static loading: Promise<void> | null = null;

  static slotOf(book: Book): number {
    if (!book) return -1;
    const slot = ShelfCoverSlots.slots.get(ShelfCoverSlots.keyOf(book));
    return slot === undefined ? -1 : slot;
  }

  /** shelfBooks 是书架上的全部书（含隐私书架、暂时隐藏的网页书源书）；不在其中的记录会被清掉。 */
  static async sync(context: Context, shelfBooks: Book[]): Promise<void> {
    await ShelfCoverSlots.ensureLoaded(context);
    const present = new Set<string>();
    const pending: Book[] = [];
    for (const book of shelfBooks) {
      const key = ShelfCoverSlots.keyOf(book);
      if (!key || present.has(key)) continue;
      present.add(key);
      if (!ShelfCoverSlots.slots.has(key)) pending.push(book);
    }
    let changed = false;
    ShelfCoverSlots.slots.forEach((_: number, key: string) => {
      if (!present.has(key)) changed = true;
    });
    if (changed) {
      const kept = new Map<string, number>();
      ShelfCoverSlots.slots.forEach((slot: number, key: string) => {
        if (present.has(key)) kept.set(key, slot);
      });
      ShelfCoverSlots.slots = kept;
    }
    if (pending.length > 0) {
      pending.sort((a: Book, b: Book) =>
        BookshelfSortHelper.getBookAddTime(a) - BookshelfSortHelper.getBookAddTime(b) ||
          a.name.localeCompare(b.name, 'zh-Hans-CN-u-co-pinyin') || a.bookUrl.localeCompare(b.bookUrl));
      const used = new Set<number>();
      ShelfCoverSlots.slots.forEach((slot: number) => used.add(slot));
      let next = 0;
      for (const book of pending) {
        while (used.has(next)) next++;
        ShelfCoverSlots.slots.set(ShelfCoverSlots.keyOf(book), next);
        used.add(next);
      }
      changed = true;
    }
    if (!changed) return;
    AppStorage.setOrCreate<number>(ShelfCoverSlots.REVISION_KEY,
      (AppStorage.get<number>(ShelfCoverSlots.REVISION_KEY) || 0) + 1);
    try {
      const store = await preferences.getPreferences(context, ShelfCoverSlots.STORE_NAME);
      const record: Record<string, number> = {};
      ShelfCoverSlots.slots.forEach((slot: number, key: string) => record[key] = slot);
      await store.put(ShelfCoverSlots.KEY_SLOTS, JSON.stringify(record));
      await store.flush();
    } catch (e) {
      console.warn('保存固定封面序号失败:', e);
    }
  }

  private static ensureLoaded(context: Context): Promise<void> {
    if (!ShelfCoverSlots.loading) ShelfCoverSlots.loading = ShelfCoverSlots.load(context);
    return ShelfCoverSlots.loading;
  }

  private static async load(context: Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, ShelfCoverSlots.STORE_NAME);
      const raw = await store.get(ShelfCoverSlots.KEY_SLOTS, '') as string;
      if (!raw) return;
      const record = JSON.parse(raw) as Record<string, number>;
      const slots = new Map<string, number>();
      Object.keys(record).forEach((key: string) => {
        const slot = record[key];
        if (typeof slot === 'number' && Number.isInteger(slot) && slot >= 0) slots.set(key, slot);
      });
      ShelfCoverSlots.slots = slots;
    } catch (e) {
      console.warn('读取固定封面序号失败:', e);
    }
  }

  private static keyOf(book: Book): string {
    return BookIdentity.workKeyOf(book) || book.bookUrl || '';
  }
}
