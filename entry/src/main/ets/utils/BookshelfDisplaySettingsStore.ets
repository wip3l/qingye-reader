import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { CloudSyncChangeTracker } from '../account/CloudSyncChangeTracker';
import { BookshelfCoverBadgeSettings } from './BookshelfCoverBadgeSettings';

export class BookshelfDisplaySettings {
  showTags: boolean = true;
  showSource: boolean = true;
  showIntro: boolean = true;
  showFullIntro: boolean = false;
  showProgressBar: boolean = false;
  showLastReadTime: boolean = true;
  showLastReadChapter: boolean = false;
  showTypeBadge: boolean = true;
  // 空串代表旧版数据；必须等旧开关读完后再迁移，不能用默认布局覆盖用户偏好。
  coverBadges: string = '';
  layoutMode: string = 'tile';
  lastReadLeafMode: string = 'adaptive';
  // 平铺布局里上次阅读的书是否置顶：off 不置顶，medium 跨两列的展开书本，large 占满一整行的继续阅读卡片。
  lastReadPinMode: string = 'large';
  lastReadPinCount: number = 3;
  bookOpenAnimation: boolean = true;
}

export class BookshelfDisplaySettingsStore {
  private static readonly STORE_NAME: string = 'bookshelf_display_settings';
  private static readonly KEY_SHOW_TAGS: string = 'bookshelfShowTags';
  private static readonly KEY_SHOW_SOURCE: string = 'bookshelfShowSource';
  private static readonly KEY_SHOW_INTRO: string = 'bookshelfShowIntro';
  private static readonly KEY_SHOW_FULL_INTRO: string = 'bookshelfShowFullIntro';
  private static readonly KEY_SHOW_PROGRESS_BAR: string = 'bookshelfShowProgressBar';
  private static readonly KEY_SHOW_LAST_READ_TIME: string = 'bookshelfShowLastReadTime';
  private static readonly KEY_SHOW_LAST_READ_CHAPTER: string = 'bookshelfShowLastReadChapter';
  private static readonly KEY_SHOW_TYPE_BADGE: string = 'bookshelfShowTypeBadge';
  private static readonly KEY_COVER_BADGES: string = 'bookshelfCoverBadges';
  private static readonly KEY_LAYOUT_MODE: string = 'bookshelfLayoutMode';
  private static readonly KEY_LAST_READ_LEAF_MODE: string = 'bookshelfLastReadLeafMode';
  private static readonly KEY_LAST_READ_PIN_MODE: string = 'bookshelfLastReadPinMode';
  private static readonly KEY_LAST_READ_PIN_COUNT: string = 'bookshelfLastReadPinCount';
  private static readonly KEY_BOOK_OPEN_ANIMATION: string = 'bookshelfBookOpenAnimation';
  private static cachedSettings: BookshelfDisplaySettings | null = null;

  static async load(context: Context): Promise<BookshelfDisplaySettings> {
    if (BookshelfDisplaySettingsStore.cachedSettings) {
      return BookshelfDisplaySettingsStore.clone(BookshelfDisplaySettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, BookshelfDisplaySettingsStore.STORE_NAME);
    const settings = new BookshelfDisplaySettings();
    settings.showTags = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_TAGS, true);
    settings.showSource = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_SOURCE, true);
    settings.showIntro = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_INTRO, true);
    settings.showFullIntro = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO, false);
    settings.showProgressBar = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR, false);
    settings.showLastReadTime = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_TIME, true);
    settings.showLastReadChapter = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_CHAPTER, false);
    settings.showTypeBadge = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_TYPE_BADGE, true);
    settings.coverBadges = BookshelfCoverBadgeSettings.normalize(await BookshelfDisplaySettingsStore.getString(
      store, BookshelfDisplaySettingsStore.KEY_COVER_BADGES, ''), settings.showTypeBadge, settings.showSource);
    settings.layoutMode = BookshelfDisplaySettingsStore.normalizeLayoutMode(await BookshelfDisplaySettingsStore.getString(
      store, BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE, 'tile'));
    settings.lastReadLeafMode = BookshelfDisplaySettingsStore.normalizeLastReadLeafMode(
      await BookshelfDisplaySettingsStore.getString(
        store, BookshelfDisplaySettingsStore.KEY_LAST_READ_LEAF_MODE, 'adaptive'));
    settings.lastReadPinMode = BookshelfDisplaySettingsStore.normalizeLastReadPinMode(
      await BookshelfDisplaySettingsStore.getString(
        store, BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_MODE, 'large'));
    const pinCount = await store.get(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_COUNT, 3);
    settings.lastReadPinCount = BookshelfDisplaySettingsStore.normalizeLastReadPinCount(
      typeof pinCount === 'number' ? pinCount : 3);
    settings.bookOpenAnimation = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_BOOK_OPEN_ANIMATION, true);
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: BookshelfDisplaySettings): Promise<void> {
    settings = BookshelfDisplaySettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, BookshelfDisplaySettingsStore.STORE_NAME);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_TAGS, settings.showTags);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_SOURCE, settings.showSource);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_INTRO, settings.showIntro);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO, settings.showFullIntro);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR, settings.showProgressBar);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_TIME, settings.showLastReadTime);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_CHAPTER, settings.showLastReadChapter);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_TYPE_BADGE, settings.showTypeBadge !== false);
    await store.put(BookshelfDisplaySettingsStore.KEY_COVER_BADGES, settings.coverBadges);
    await store.put(BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE,
      BookshelfDisplaySettingsStore.normalizeLayoutMode(settings.layoutMode));
    await store.put(BookshelfDisplaySettingsStore.KEY_LAST_READ_LEAF_MODE,
      BookshelfDisplaySettingsStore.normalizeLastReadLeafMode(settings.lastReadLeafMode));
    await store.put(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_MODE,
      BookshelfDisplaySettingsStore.normalizeLastReadPinMode(settings.lastReadPinMode));
    await store.put(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_COUNT, settings.lastReadPinCount);
    await store.put(BookshelfDisplaySettingsStore.KEY_BOOK_OPEN_ANIMATION, settings.bookOpenAnimation !== false);
    await store.flush();
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    CloudSyncChangeTracker.markApplicationPreferenceChanged();
  }

  static applyToStorage(settings: BookshelfDisplaySettings): void {
    settings = BookshelfDisplaySettingsStore.clone(settings);
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_TAGS, settings.showTags);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_SOURCE, settings.showSource);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_INTRO, settings.showIntro);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO, settings.showFullIntro);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR, settings.showProgressBar);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_TIME, settings.showLastReadTime);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_CHAPTER, settings.showLastReadChapter);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_TYPE_BADGE, settings.showTypeBadge !== false);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_COVER_BADGES, settings.coverBadges);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE,
      BookshelfDisplaySettingsStore.normalizeLayoutMode(settings.layoutMode));
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_LAST_READ_LEAF_MODE,
      BookshelfDisplaySettingsStore.normalizeLastReadLeafMode(settings.lastReadLeafMode));
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_MODE,
      BookshelfDisplaySettingsStore.normalizeLastReadPinMode(settings.lastReadPinMode));
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_COUNT, settings.lastReadPinCount);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_BOOK_OPEN_ANIMATION,
      settings.bookOpenAnimation !== false);
  }

  static fromStorage(): BookshelfDisplaySettings {
    const settings = new BookshelfDisplaySettings();
    settings.showTags = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_TAGS) ?? true;
    settings.showSource = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_SOURCE) ?? true;
    settings.showIntro = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_INTRO) ?? true;
    settings.showFullIntro = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_FULL_INTRO) ?? false;
    settings.showProgressBar = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_PROGRESS_BAR) ?? false;
    settings.showLastReadTime = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_TIME) ?? true;
    settings.showLastReadChapter = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_LAST_READ_CHAPTER) ?? false;
    settings.showTypeBadge = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_TYPE_BADGE) ?? true;
    settings.coverBadges = BookshelfCoverBadgeSettings.normalize(
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_COVER_BADGES) ?? '', settings.showTypeBadge, settings.showSource);
    settings.layoutMode = BookshelfDisplaySettingsStore.normalizeLayoutMode(
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE) ?? 'tile');
    settings.lastReadLeafMode = BookshelfDisplaySettingsStore.normalizeLastReadLeafMode(
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_LAST_READ_LEAF_MODE) ?? 'adaptive');
    settings.lastReadPinMode = BookshelfDisplaySettingsStore.normalizeLastReadPinMode(
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_MODE) ?? 'large');
    settings.lastReadPinCount = BookshelfDisplaySettingsStore.normalizeLastReadPinCount(
      AppStorage.get<number>(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_COUNT) ?? 3);
    settings.bookOpenAnimation = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_BOOK_OPEN_ANIMATION) ?? true;
    return settings;
  }

  private static async getBoolean(
    store: preferences.Preferences,
    key: string,
    fallback: boolean
  ): Promise<boolean> {
    const value = await store.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static normalizeLayoutMode(value: string): string {
    if (value === 'loose' || value === 'compact') {
      return value;
    }
    return 'tile';
  }

  private static normalizeLastReadLeafMode(value: string): string {
    if (value === 'bookInfo' || value === 'contentPreview') {
      return value;
    }
    return 'adaptive';
  }

  private static normalizeLastReadPinMode(value: string): string {
    if (value === 'off' || value === 'medium') {
      return value;
    }
    return 'large';
  }

  static normalizeLastReadPinCount(value: number): number {
    return Number.isInteger(value) && value >= 1 && value <= 5 ? value : 3;
  }

  private static clone(source: BookshelfDisplaySettings): BookshelfDisplaySettings {
    const settings = new BookshelfDisplaySettings();
    settings.showTags = source.showTags;
    settings.coverBadges = BookshelfCoverBadgeSettings.normalize(source.coverBadges,
      source.showTypeBadge !== false, source.showSource !== false);
    settings.showSource = BookshelfCoverBadgeSettings.location(settings.coverBadges, 'source') >= 0;
    settings.showIntro = source.showIntro;
    settings.showFullIntro = source.showFullIntro;
    settings.showProgressBar = source.showProgressBar;
    settings.showLastReadTime = source.showLastReadTime;
    settings.showLastReadChapter = source.showLastReadChapter;
    settings.showTypeBadge = BookshelfCoverBadgeSettings.location(settings.coverBadges, 'type') >= 0;
    settings.layoutMode = BookshelfDisplaySettingsStore.normalizeLayoutMode(source.layoutMode);
    settings.lastReadLeafMode = BookshelfDisplaySettingsStore.normalizeLastReadLeafMode(source.lastReadLeafMode);
    settings.lastReadPinMode = BookshelfDisplaySettingsStore.normalizeLastReadPinMode(source.lastReadPinMode);
    settings.lastReadPinCount = BookshelfDisplaySettingsStore.normalizeLastReadPinCount(source.lastReadPinCount);
    settings.bookOpenAnimation = source.bookOpenAnimation !== false;
    return settings;
  }
}
