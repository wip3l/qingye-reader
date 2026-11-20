import { Context } from '@kit.AbilityKit';
import { Book, BookGroup } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { BookshelfDisplaySettingsStore } from './BookshelfDisplaySettingsStore';
import { BookshelfStateStore } from './BookshelfStateStore';
import { PrivateShelfStore } from './PrivateShelfStore';
import { ReaderReplaceRuleStore } from './ReaderReplaceRuleStore';
import { SearchExplorePendingBook } from './SearchExplorePendingBook';
import { ShelfCoverSlots } from './ShelfCoverSlots';

/** 书架页挂载时直接拿来显示的一份书架数据。 */
export class ShelfSnapshot {
  /** 数据库里的全部书（含暂时隐藏的），书架页自己再按可见性过滤。 */
  storedBooks: Book[] = [];
  groups: BookGroup[] = [];
  /** 冷启动预读出来、还没被书架页用过：要按下面三项恢复上次停留的位置。 */
  startup: boolean = false;
  rememberGroup: boolean = false;
  /** 已核对过分组还在；不在或没开“记住打开分组”时为 0。 */
  activeGroupId: number = 0;
  typeTab: string = 'all';
  /** 刚读出来的，用完不必再读一遍；否则书架页显示后还要照常重读。 */
  fresh: boolean = false;
  loadedAt: number = 0;
}

/**
 * 书架数据在启动页期间读好，首页第一帧就带着书出来，不经过空白占位。
 * 之后每次读书架也留一份，首页因主题、深浅色切换重建书架页时先用它垫着。
 */
export class ShelfPreload {
  private static readonly FRESH_MS: number = 5000;
  /** 从开始预读算起，启动页最多等这么久；超过就照常进首页，由书架页自己读。 */
  private static readonly WAIT_LIMIT_MS: number = 1500;
  private static startedAt: number = 0;
  private static pending: Promise<void> | null = null;
  private static snapshot: ShelfSnapshot | null = null;

  static start(context: Context): void {
    if (ShelfPreload.pending) return;
    ShelfPreload.startedAt = Date.now();
    ShelfPreload.pending = ShelfPreload.run(context).catch((e: Error): void => {
      console.warn('预读书架失败:', e);
    });
  }

  /** 预读完成或到了等待上限就返回；没开始预读时立即返回。 */
  static wait(): Promise<void> {
    const pending = ShelfPreload.pending;
    if (!pending || ShelfPreload.snapshot) return Promise.resolve();
    const remaining = ShelfPreload.WAIT_LIMIT_MS - (Date.now() - ShelfPreload.startedAt);
    if (remaining <= 0) return Promise.resolve();
    return new Promise<void>((resolve: () => void): void => {
      const timer = setTimeout((): void => resolve(), remaining);
      pending.then((): void => {
        clearTimeout(timer);
        resolve();
      });
    });
  }

  /** 书架页挂载时取；冷启动那份只算一次“刚读出来”。 */
  static take(): ShelfSnapshot | null {
    const current = ShelfPreload.snapshot;
    if (!current) return null;
    const result = new ShelfSnapshot();
    result.storedBooks = current.storedBooks;
    result.groups = current.groups;
    result.startup = current.startup;
    result.rememberGroup = current.rememberGroup;
    result.activeGroupId = current.activeGroupId;
    result.typeTab = current.typeTab;
    result.loadedAt = current.loadedAt;
    result.fresh = current.startup && Date.now() - current.loadedAt < ShelfPreload.FRESH_MS;
    current.startup = false;
    return result;
  }

  /** 书架页每次读完书架后留一份。 */
  static remember(storedBooks: Book[], groups: BookGroup[]): void {
    const snapshot = new ShelfSnapshot();
    snapshot.storedBooks = storedBooks;
    snapshot.groups = groups;
    snapshot.loadedAt = Date.now();
    ShelfPreload.snapshot = snapshot;
  }

  private static async run(context: Context): Promise<void> {
    // 章节名净化规则、隐私书架开关、显示设置都影响书架第一帧，和读库同时进行。
    const rulesTask = ReaderReplaceRuleStore.load(context).then((): void => {}).catch((e: Error): void => {
      console.warn('预读替换净化规则失败:', e);
    });
    const privateTask = PrivateShelfStore.load(context).catch((e: Error): void => {
      console.warn('预读隐私书架设置失败:', e);
    });
    const stateTask = ShelfPreload.restoreState(context);

    const db = AppDatabase.getInstance();
    await db.initWithContext(context);
    const storedBooks = await db.getAllBooks();
    const groups = await db.getCustomBookGroups();
    await ShelfCoverSlots.sync(context,
      storedBooks.filter((book: Book) => !SearchExplorePendingBook.isPendingAddToShelf(book)));
    await rulesTask;
    await privateTask;
    const state = await stateTask;
    // 等待期间书架页已经自己读过了（超过等待上限），以它留下的为准。
    if (ShelfPreload.snapshot) return;

    const snapshot = new ShelfSnapshot();
    snapshot.storedBooks = storedBooks;
    snapshot.groups = groups;
    snapshot.startup = true;
    snapshot.rememberGroup = state.rememberGroup;
    snapshot.activeGroupId = state.rememberGroup &&
      groups.some((group: BookGroup) => group.groupId === state.activeGroupId) ? state.activeGroupId : 0;
    snapshot.typeTab = state.typeTab;
    snapshot.loadedAt = Date.now();
    ShelfPreload.snapshot = snapshot;
  }

  /** 显示设置、排序、分类栏展开状态直接放进 AppStorage，书架页挂载时读到的就是最终值。 */
  private static async restoreState(context: Context): Promise<ShelfSnapshot> {
    const state = new ShelfSnapshot();
    try {
      const settings = await BookshelfDisplaySettingsStore.load(context);
      BookshelfDisplaySettingsStore.applyToStorage(settings);
      state.rememberGroup = settings.rememberGroup;
    } catch (e) {
      console.warn('预读书架显示设置失败:', e);
    }
    try {
      // 旧版本只存在 PersistentStorage 里，偏好里还没有时沿用 AppStorage 当前值。
      const fallbackMode = BookshelfStateStore.normalizeSortMode(AppStorage.get<string>('bookshelfSortMode'));
      AppStorage.setOrCreate('bookshelfSortMode', await BookshelfStateStore.loadSortMode(context, fallbackMode));
      const fallbackExpanded = AppStorage.get<boolean>('bookshelfCategoryExpanded') !== false;
      AppStorage.setOrCreate('bookshelfCategoryExpanded',
        await BookshelfStateStore.loadCategoryExpanded(context, fallbackExpanded));
      if (state.rememberGroup) {
        state.activeGroupId = await BookshelfStateStore.loadActiveGroupId(context);
        state.typeTab = await BookshelfStateStore.loadTypeTab(context);
      }
    } catch (e) {
      console.warn('预读书架状态失败:', e);
    }
    return state;
  }
}
