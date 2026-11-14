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
  layoutMode: string = 'companion';
  lastReadLeafMode: string = 'adaptive';
  // 平铺布局里上次阅读的书是否置顶：off 不置顶，medium 跨两列的展开书本，large 占满一整行的继续阅读卡片。
  lastReadPinMode: string = 'large';
  lastReadPinCount: number = 1;
  bookOpenAnimation: boolean = true;
  // 书架顶部按类型（小说、漫画、有声书等）分页；关闭后所有书平铺在一页。
  typeCategoryEnabled: boolean = true;
  // 分类栏里是否有“全部”一项。
  showAllTypeTab: boolean = true;
  // 陪伴布局网格里的书高矮不一、少数斜靠；关闭后一样大、全部立正。
  companionStagger: boolean = true;
  // 陪伴布局问候与书架之间的“阅读小记”卡片。
  companionReadingNote: boolean = true;
  // 陪伴布局左上角问候语：time 按时段的内置文案，custom 用下面两行（可含占位符），off 不显示。
  greetingMode: string = 'time';
  greetingTitle: string = '';
  greetingSubtitle: string = '';
  // 陪伴布局书架网格上方的标题；空串显示默认文案。
  companionSectionTitle: string = '';
  // 打开应用后在后台检查书架上连载书的新章节；关闭后只在下拉书架时检查。属于网页解析的设置项。
  autoRefresh: boolean = true;
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
  private static readonly KEY_TYPE_CATEGORY_ENABLED: string = 'bookshelfTypeCategoryEnabled';
  private static readonly KEY_SHOW_ALL_TYPE_TAB: string = 'bookshelfShowAllTypeTab';
  private static readonly KEY_COMPANION_STAGGER: string = 'bookshelfCompanionStagger';
  private static readonly KEY_COMPANION_READING_NOTE: string = 'bookshelfCompanionReadingNote';
  private static readonly KEY_GREETING_MODE: string = 'bookshelfGreetingMode';
  private static readonly KEY_GREETING_TITLE: string = 'bookshelfGreetingTitle';
  private static readonly KEY_GREETING_SUBTITLE: string = 'bookshelfGreetingSubtitle';
  private static readonly KEY_COMPANION_SECTION_TITLE: string = 'bookshelfCompanionSectionTitle';
  private static readonly KEY_AUTO_REFRESH: string = 'bookshelfAutoRefresh';
  static readonly DEFAULT_COMPANION_SECTION_TITLE: string = '书架里，还有故事';
  static readonly COMPANION_SECTION_TITLE_MAX_LENGTH: number = 20;
  // 4.4.956 起书架默认使用“陪伴”布局：升级后把已有设置统一改一次，之后用户自己改的布局不再动。
  private static readonly KEY_COMPANION_LAYOUT_MIGRATED: string = 'bookshelfCompanionLayoutMigrated';
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
      store, BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE, 'companion'));
    settings.lastReadLeafMode = BookshelfDisplaySettingsStore.normalizeLastReadLeafMode(
      await BookshelfDisplaySettingsStore.getString(
        store, BookshelfDisplaySettingsStore.KEY_LAST_READ_LEAF_MODE, 'adaptive'));
    settings.lastReadPinMode = BookshelfDisplaySettingsStore.normalizeLastReadPinMode(
      await BookshelfDisplaySettingsStore.getString(
        store, BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_MODE, 'large'));
    const pinCount = await store.get(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_COUNT, 1);
    settings.lastReadPinCount = BookshelfDisplaySettingsStore.normalizeLastReadPinCount(
      typeof pinCount === 'number' ? pinCount : 1);
    settings.bookOpenAnimation = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_BOOK_OPEN_ANIMATION, true);
    settings.typeCategoryEnabled = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_TYPE_CATEGORY_ENABLED, true);
    settings.showAllTypeTab = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_SHOW_ALL_TYPE_TAB, true);
    settings.companionStagger = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_COMPANION_STAGGER, true);
    settings.companionReadingNote = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_COMPANION_READING_NOTE, true);
    settings.greetingMode = BookshelfDisplaySettingsStore.normalizeGreetingMode(
      await BookshelfDisplaySettingsStore.getString(store, BookshelfDisplaySettingsStore.KEY_GREETING_MODE, 'time'));
    settings.greetingTitle = await BookshelfDisplaySettingsStore.getString(
      store, BookshelfDisplaySettingsStore.KEY_GREETING_TITLE, '');
    settings.greetingSubtitle = await BookshelfDisplaySettingsStore.getString(
      store, BookshelfDisplaySettingsStore.KEY_GREETING_SUBTITLE, '');
    settings.companionSectionTitle = await BookshelfDisplaySettingsStore.getString(
      store, BookshelfDisplaySettingsStore.KEY_COMPANION_SECTION_TITLE, '');
    settings.autoRefresh = await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_AUTO_REFRESH, true);
    if (!(await BookshelfDisplaySettingsStore.getBoolean(
      store, BookshelfDisplaySettingsStore.KEY_COMPANION_LAYOUT_MIGRATED, false))) {
      settings.layoutMode = 'companion';
      await store.put(BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE, 'companion');
      await store.put(BookshelfDisplaySettingsStore.KEY_COMPANION_LAYOUT_MIGRATED, true);
      await store.flush();
      // 记为本机偏好变更，下次云同步把新布局带给其他设备，而不是被云端旧值改回。
      CloudSyncChangeTracker.markApplicationPreferenceChanged();
    }
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
    await store.put(BookshelfDisplaySettingsStore.KEY_TYPE_CATEGORY_ENABLED, settings.typeCategoryEnabled !== false);
    await store.put(BookshelfDisplaySettingsStore.KEY_SHOW_ALL_TYPE_TAB, settings.showAllTypeTab !== false);
    await store.put(BookshelfDisplaySettingsStore.KEY_COMPANION_STAGGER, settings.companionStagger !== false);
    await store.put(BookshelfDisplaySettingsStore.KEY_COMPANION_READING_NOTE, settings.companionReadingNote !== false);
    await store.put(BookshelfDisplaySettingsStore.KEY_GREETING_MODE, settings.greetingMode);
    await store.put(BookshelfDisplaySettingsStore.KEY_GREETING_TITLE, settings.greetingTitle);
    await store.put(BookshelfDisplaySettingsStore.KEY_GREETING_SUBTITLE, settings.greetingSubtitle);
    await store.put(BookshelfDisplaySettingsStore.KEY_COMPANION_SECTION_TITLE, settings.companionSectionTitle);
    await store.put(BookshelfDisplaySettingsStore.KEY_AUTO_REFRESH, settings.autoRefresh !== false);
    await store.flush();
    BookshelfDisplaySettingsStore.cachedSettings = BookshelfDisplaySettingsStore.clone(settings);
    CloudSyncChangeTracker.markApplicationPreferenceChanged();
  }

  /** 书架长按问候语与书架设置共用：只改问候语三项，其余设置取当前内存里的值。 */
  static async saveGreeting(context: Context, mode: string, title: string, subtitle: string): Promise<void> {
    const settings = BookshelfDisplaySettingsStore.fromStorage();
    settings.greetingMode = BookshelfDisplaySettingsStore.normalizeGreetingMode(mode);
    settings.greetingTitle = title;
    settings.greetingSubtitle = subtitle;
    BookshelfDisplaySettingsStore.applyToStorage(settings);
    await BookshelfDisplaySettingsStore.save(context, settings);
  }

  /** 书架长按标题与书架设置共用：只改书架标题，其余设置取当前内存里的值。空串即恢复默认。 */
  static async saveCompanionSectionTitle(context: Context, title: string): Promise<void> {
    const settings = BookshelfDisplaySettingsStore.fromStorage();
    settings.companionSectionTitle = title.trim();
    BookshelfDisplaySettingsStore.applyToStorage(settings);
    await BookshelfDisplaySettingsStore.save(context, settings);
  }

  static companionSectionTitleText(title: string): string {
    const text = (title || '').trim();
    return text ? text : BookshelfDisplaySettingsStore.DEFAULT_COMPANION_SECTION_TITLE;
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
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_TYPE_CATEGORY_ENABLED,
      settings.typeCategoryEnabled !== false);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_SHOW_ALL_TYPE_TAB, settings.showAllTypeTab !== false);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_COMPANION_STAGGER, settings.companionStagger !== false);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_COMPANION_READING_NOTE,
      settings.companionReadingNote !== false);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_GREETING_MODE, settings.greetingMode);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_GREETING_TITLE, settings.greetingTitle);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_GREETING_SUBTITLE, settings.greetingSubtitle);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_COMPANION_SECTION_TITLE, settings.companionSectionTitle);
    AppStorage.setOrCreate(BookshelfDisplaySettingsStore.KEY_AUTO_REFRESH, settings.autoRefresh !== false);
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
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_LAYOUT_MODE) ?? 'companion');
    settings.lastReadLeafMode = BookshelfDisplaySettingsStore.normalizeLastReadLeafMode(
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_LAST_READ_LEAF_MODE) ?? 'adaptive');
    settings.lastReadPinMode = BookshelfDisplaySettingsStore.normalizeLastReadPinMode(
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_MODE) ?? 'large');
    settings.lastReadPinCount = BookshelfDisplaySettingsStore.normalizeLastReadPinCount(
      AppStorage.get<number>(BookshelfDisplaySettingsStore.KEY_LAST_READ_PIN_COUNT) ?? 1);
    settings.bookOpenAnimation = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_BOOK_OPEN_ANIMATION) ?? true;
    settings.typeCategoryEnabled =
      AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_TYPE_CATEGORY_ENABLED) ?? true;
    settings.showAllTypeTab = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_SHOW_ALL_TYPE_TAB) ?? true;
    settings.companionStagger =
      AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_COMPANION_STAGGER) ?? true;
    settings.companionReadingNote =
      AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_COMPANION_READING_NOTE) ?? true;
    settings.greetingMode = BookshelfDisplaySettingsStore.normalizeGreetingMode(
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_GREETING_MODE) ?? 'time');
    settings.greetingTitle = AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_GREETING_TITLE) ?? '';
    settings.greetingSubtitle = AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_GREETING_SUBTITLE) ?? '';
    settings.companionSectionTitle =
      AppStorage.get<string>(BookshelfDisplaySettingsStore.KEY_COMPANION_SECTION_TITLE) ?? '';
    settings.autoRefresh = AppStorage.get<boolean>(BookshelfDisplaySettingsStore.KEY_AUTO_REFRESH) ?? true;
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
    if (value === 'loose' || value === 'compact' || value === 'companion') {
      return value;
    }
    return 'tile';
  }

  static normalizeGreetingMode(value: string): string {
    return value === 'custom' || value === 'off' ? value : 'time';
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
    return Number.isInteger(value) && value >= 1 && value <= 5 ? value : 1;
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
    settings.typeCategoryEnabled = source.typeCategoryEnabled !== false;
    settings.showAllTypeTab = source.showAllTypeTab !== false;
    settings.companionStagger = source.companionStagger !== false;
    settings.companionReadingNote = source.companionReadingNote !== false;
    settings.greetingMode = BookshelfDisplaySettingsStore.normalizeGreetingMode(source.greetingMode);
    settings.greetingTitle = source.greetingTitle || '';
    settings.greetingSubtitle = source.greetingSubtitle || '';
    settings.companionSectionTitle = source.companionSectionTitle || '';
    settings.autoRefresh = source.autoRefresh !== false;
    return settings;
  }
}
