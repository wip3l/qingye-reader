import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { CoverDimSettings } from './CoverDimSettings';

export class CoverGallerySnapshot {
  albumsRaw: string = '';
  lightAlbumId: string = '';
  darkAlbumId: string = '';
  applyScope: string = 'all';
  targetBooksRaw: string = '';
  /** 统一封面用图集：替换书籍自带的封面（范围见 applyScope）。统一封面用主题封面时由主题设置里的开关表示，且优先于这里。 */
  replaceAlbum: boolean = false;
  /** 统一封面用图集时，书籍自带的封面和图集一起轮播。 */
  albumMix: boolean = false;
  /** 书没有封面时用什么：text 书名占位、theme 主题封面、album 图集。 */
  fallback: string = 'text';
  coverMode: string = 'sequence';
  /** 深色模式调暗封面（见 CoverDimSettings）。 */
  darkDim: boolean = false;
  darkDimLevel: number = CoverDimSettings.DEFAULT_LEVEL;
}

export class CoverGalleryStore {
  private static readonly STORE_NAME: string = 'cover_gallery_settings';
  private static readonly KEY_ALBUMS: string = 'bookshelfCoverAlbums';
  private static readonly KEY_LIGHT_ALBUM: string = 'bookshelfLightCoverAlbumId';
  private static readonly KEY_DARK_ALBUM: string = 'bookshelfDarkCoverAlbumId';
  private static readonly KEY_APPLY_SCOPE: string = 'bookshelfCoverApplyScope';
  private static readonly KEY_TARGET_BOOKS: string = 'bookshelfCoverTargetBooks';
  /** 旧版的两个开关，只在还没有新键时读一次，换算成下面三项（见 applyLegacy）。 */
  private static readonly KEY_IGNORE_SOURCE: string = 'bookshelfIgnoreSourceCover';
  private static readonly KEY_IGNORE_EMPTY_ONLY: string = 'bookshelfIgnoreEmptyCoverOnly';
  static readonly KEY_REPLACE_ALBUM: string = 'bookshelfCoverReplaceAlbum';
  static readonly KEY_ALBUM_MIX: string = 'bookshelfCoverAlbumMix';
  static readonly KEY_FALLBACK: string = 'bookshelfCoverFallback';
  private static readonly KEY_COVER_MODE: string = 'bookshelfCoverMode';
  private static cachedSnapshot: CoverGallerySnapshot | null = null;

  static async saveFromStorage(context: Context): Promise<void> {
    const snapshot = CoverGalleryStore.snapshotFromStorage();
    if (!CoverGalleryStore.hasAlbumPayload(snapshot.albumsRaw)) {
      const preferenceSnapshot = await CoverGalleryStore.loadFromPreferences(context);
      if (CoverGalleryStore.hasAlbumPayload(preferenceSnapshot.albumsRaw)) {
        await CoverGalleryStore.save(context, preferenceSnapshot);
        return;
      }
    }
    await CoverGalleryStore.save(context, snapshot);
  }

  static async save(context: Context, snapshot: CoverGallerySnapshot): Promise<void> {
    CoverGalleryStore.cachedSnapshot = CoverGalleryStore.cloneSnapshot(snapshot);
    const store = await preferences.getPreferences(context, CoverGalleryStore.STORE_NAME);
    await store.put(CoverGalleryStore.KEY_ALBUMS, snapshot.albumsRaw);
    await store.put(CoverGalleryStore.KEY_LIGHT_ALBUM, snapshot.lightAlbumId);
    await store.put(CoverGalleryStore.KEY_DARK_ALBUM, snapshot.darkAlbumId);
    await store.put(CoverGalleryStore.KEY_APPLY_SCOPE, snapshot.applyScope);
    await store.put(CoverGalleryStore.KEY_TARGET_BOOKS, snapshot.targetBooksRaw);
    await store.put(CoverGalleryStore.KEY_REPLACE_ALBUM, snapshot.replaceAlbum);
    await store.put(CoverGalleryStore.KEY_ALBUM_MIX, snapshot.albumMix);
    await store.put(CoverGalleryStore.KEY_FALLBACK, CoverGalleryStore.normalizeFallback(snapshot.fallback));
    await store.put(CoverGalleryStore.KEY_COVER_MODE, snapshot.coverMode);
    await store.put(CoverDimSettings.KEY_ENABLED, snapshot.darkDim);
    await store.put(CoverDimSettings.KEY_LEVEL, snapshot.darkDimLevel);
    await store.flush();
  }

  static async load(context: Context): Promise<CoverGallerySnapshot> {
    if (CoverGalleryStore.cachedSnapshot) {
      return CoverGalleryStore.cloneSnapshot(CoverGalleryStore.cachedSnapshot);
    }

    const storageSnapshot = CoverGalleryStore.snapshotFromStorage();
    const preferenceSnapshot = await CoverGalleryStore.loadFromPreferences(context);

    if (CoverGalleryStore.hasAlbumPayload(preferenceSnapshot.albumsRaw)) {
      return preferenceSnapshot;
    }

    if (CoverGalleryStore.hasAlbumPayload(storageSnapshot.albumsRaw)) {
      await CoverGalleryStore.save(context, storageSnapshot);
      return storageSnapshot;
    }

    return preferenceSnapshot;
  }

  static applyToStorage(snapshot: CoverGallerySnapshot): void {
    CoverGalleryStore.cachedSnapshot = CoverGalleryStore.cloneSnapshot(snapshot);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_ALBUMS, snapshot.albumsRaw);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_LIGHT_ALBUM, snapshot.lightAlbumId);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_DARK_ALBUM, snapshot.darkAlbumId);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_APPLY_SCOPE, snapshot.applyScope);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_TARGET_BOOKS, snapshot.targetBooksRaw);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_REPLACE_ALBUM, snapshot.replaceAlbum);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_ALBUM_MIX, snapshot.albumMix);
    AppStorage.setOrCreate(CoverGalleryStore.KEY_FALLBACK, CoverGalleryStore.normalizeFallback(snapshot.fallback));
    AppStorage.setOrCreate(CoverGalleryStore.KEY_COVER_MODE, snapshot.coverMode);
    AppStorage.setOrCreate(CoverDimSettings.KEY_ENABLED, snapshot.darkDim);
    AppStorage.setOrCreate(CoverDimSettings.KEY_LEVEL, snapshot.darkDimLevel);
  }

  private static async getString(store: preferences.Preferences, key: string, fallback: string): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static async getNumber(store: preferences.Preferences, key: string, fallback: number): Promise<number> {
    const value = await store.get(key, fallback);
    return typeof value === 'number' ? value : fallback;
  }

  private static async getBoolean(store: preferences.Preferences, key: string, fallback: boolean): Promise<boolean> {
    const value = await store.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  static snapshotFromStorage(): CoverGallerySnapshot {
    const snapshot = new CoverGallerySnapshot();
    snapshot.albumsRaw = AppStorage.get<string>(CoverGalleryStore.KEY_ALBUMS) || '';
    snapshot.lightAlbumId = AppStorage.get<string>(CoverGalleryStore.KEY_LIGHT_ALBUM) || '';
    snapshot.darkAlbumId = AppStorage.get<string>(CoverGalleryStore.KEY_DARK_ALBUM) || '';
    snapshot.applyScope = AppStorage.get<string>(CoverGalleryStore.KEY_APPLY_SCOPE) || 'all';
    snapshot.targetBooksRaw = AppStorage.get<string>(CoverGalleryStore.KEY_TARGET_BOOKS) || '';
    if (AppStorage.has(CoverGalleryStore.KEY_FALLBACK)) {
      snapshot.replaceAlbum = AppStorage.get<boolean>(CoverGalleryStore.KEY_REPLACE_ALBUM) || false;
      snapshot.albumMix = AppStorage.get<boolean>(CoverGalleryStore.KEY_ALBUM_MIX) || false;
      snapshot.fallback = CoverGalleryStore.fallbackFromStorage();
    } else {
      CoverGalleryStore.applyLegacy(snapshot, AppStorage.get<boolean>(CoverGalleryStore.KEY_IGNORE_SOURCE) || false,
        AppStorage.get<boolean>(CoverGalleryStore.KEY_IGNORE_EMPTY_ONLY) || false);
    }
    snapshot.coverMode = AppStorage.get<string>(CoverGalleryStore.KEY_COVER_MODE) || 'sequence';
    snapshot.darkDim = AppStorage.get<boolean>(CoverDimSettings.KEY_ENABLED) || false;
    snapshot.darkDimLevel = CoverDimSettings.normalizeLevel(AppStorage.get<number>(CoverDimSettings.KEY_LEVEL) || 0);
    return snapshot;
  }

  private static async loadFromPreferences(context: Context): Promise<CoverGallerySnapshot> {
    const store = await preferences.getPreferences(context, CoverGalleryStore.STORE_NAME);
    const snapshot = new CoverGallerySnapshot();
    snapshot.albumsRaw = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_ALBUMS, '');
    snapshot.lightAlbumId = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_LIGHT_ALBUM, '');
    snapshot.darkAlbumId = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_DARK_ALBUM, '');
    snapshot.applyScope = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_APPLY_SCOPE, 'all');
    snapshot.targetBooksRaw = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_TARGET_BOOKS, '');
    if (await store.has(CoverGalleryStore.KEY_FALLBACK)) {
      snapshot.replaceAlbum = await CoverGalleryStore.getBoolean(store, CoverGalleryStore.KEY_REPLACE_ALBUM, false);
      snapshot.albumMix = await CoverGalleryStore.getBoolean(store, CoverGalleryStore.KEY_ALBUM_MIX, false);
      snapshot.fallback = CoverGalleryStore.normalizeFallback(
        await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_FALLBACK, 'text'));
    } else {
      CoverGalleryStore.applyLegacy(snapshot,
        await CoverGalleryStore.getBoolean(store, CoverGalleryStore.KEY_IGNORE_SOURCE, false),
        await CoverGalleryStore.getBoolean(store, CoverGalleryStore.KEY_IGNORE_EMPTY_ONLY, false));
    }
    snapshot.coverMode = await CoverGalleryStore.getString(store, CoverGalleryStore.KEY_COVER_MODE, 'sequence');
    snapshot.darkDim = await CoverGalleryStore.getBoolean(store, CoverDimSettings.KEY_ENABLED, false);
    snapshot.darkDimLevel = CoverDimSettings.normalizeLevel(
      await CoverGalleryStore.getNumber(store, CoverDimSettings.KEY_LEVEL, CoverDimSettings.DEFAULT_LEVEL));
    return snapshot;
  }

  static normalizeFallback(value: string): string {
    return value === 'theme' || value === 'album' ? value : 'text';
  }

  /** 取封面的热路径上只要这一项时用，不必读整份设置。 */
  static fallbackFromStorage(): string {
    return CoverGalleryStore.normalizeFallback(AppStorage.get<string>(CoverGalleryStore.KEY_FALLBACK) || '');
  }

  /**
   * 旧版“忽略原始封面 / 仅忽略空封面”换算成新的三项，换算后每本书显示的封面不变：
   * 选了图集就是统一封面用图集（没开忽略时和自带封面一起轮播）；仅忽略空封面则是只给没有封面的书用图集。
   */
  static applyLegacy(snapshot: CoverGallerySnapshot, ignoreSource: boolean, ignoreEmptyOnly: boolean): void {
    const albumChosen = !!(snapshot.lightAlbumId || snapshot.darkAlbumId);
    if (ignoreSource && ignoreEmptyOnly) {
      snapshot.replaceAlbum = false;
      snapshot.albumMix = false;
      snapshot.fallback = albumChosen ? 'album' : 'text';
      return;
    }
    snapshot.replaceAlbum = albumChosen;
    snapshot.albumMix = albumChosen && !ignoreSource;
    snapshot.fallback = 'text';
  }

  private static hasAlbumPayload(raw: string): boolean {
    return (raw || '').trim().length > 0;
  }

  private static cloneSnapshot(source: CoverGallerySnapshot): CoverGallerySnapshot {
    const snapshot = new CoverGallerySnapshot();
    snapshot.albumsRaw = source.albumsRaw;
    snapshot.lightAlbumId = source.lightAlbumId;
    snapshot.darkAlbumId = source.darkAlbumId;
    snapshot.applyScope = source.applyScope;
    snapshot.targetBooksRaw = source.targetBooksRaw;
    snapshot.replaceAlbum = source.replaceAlbum;
    snapshot.albumMix = source.albumMix;
    snapshot.fallback = source.fallback;
    snapshot.coverMode = source.coverMode;
    snapshot.darkDim = source.darkDim;
    snapshot.darkDimLevel = source.darkDimLevel;
    return snapshot;
  }
}
