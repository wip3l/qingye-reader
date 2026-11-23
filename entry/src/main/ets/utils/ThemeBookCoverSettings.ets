import { Book } from '@legado/sourceengine';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { BookDisplayHelper } from './BookDisplayHelper';
import { CoverGallerySettings } from './CoverGallerySettings';
import { ShelfCoverSlots } from './ShelfCoverSlots';
import { CoverGallerySnapshot, CoverGalleryStore } from './CoverGalleryStore';

/** 各页面共用主题封面的顺序和轮播间隔。 */
export class ThemeBookCoverSettings {
  static enabled(darkMode: boolean, enabled: boolean): boolean {
    return enabled &&
      ThemeAssetRegistry.themeBookCovers(ThemeRuntime.bookTokens(darkMode).coverAssetId, darkMode).length > 0;
  }

  /**
   * 这本书是否显示主题封面。enabled 是“统一封面用主题封面”的开关：开着时除了单独设置过封面的书都用主题封面；
   * 关着时只有“没有封面时用主题封面”且这本书确实取不到别的图才用。主题没有封面套装时都不用。
   */
  static enabledFor(book: Book | null | undefined, darkMode: boolean, enabled: boolean,
    settings: CoverGallerySnapshot | null = null): boolean {
    if (!book || BookDisplayHelper.hasCustomCover(book) || !ThemeBookCoverSettings.enabled(darkMode, true)) return false;
    if (enabled) return true;
    const fallback = settings ? settings.fallback : CoverGalleryStore.fallbackFromStorage();
    if (fallback !== 'theme') return false;
    return CoverGallerySettings.coversFor(book, darkMode, settings || CoverGalleryStore.snapshotFromStorage()).length === 0;
  }

  /** coverMode 传组件里的状态变量才会随设置刷新；不传时读当前存储。 */
  static covers(book: Book, darkMode: boolean, coverMode: string = ThemeBookCoverSettings.storedMode()): ResourceStr[] {
    return ThemeBookCoverSettings.coversForAsset(book, ThemeRuntime.bookTokens(darkMode).coverAssetId, darkMode,
      coverMode);
  }

  /**
   * “固定”模式每本书只留一张：书架上的书按加入先后的序号轮流分（见 ShelfCoverSlots），其余取轮播首张。
   * 起始序号只由书决定，浅深两套封面张数相同时同一本书在两种模式下落在同一序号上。
   */
  static coversForAsset(book: Book, assetId: string, darkMode: boolean,
    coverMode: string = ThemeBookCoverSettings.storedMode()): ResourceStr[] {
    const covers = ThemeAssetRegistry.themeBookCovers(assetId, darkMode);
    if (covers.length <= 1) return covers;
    const seed = ThemeBookCoverSettings.seed(book);
    const start = seed % covers.length;
    if (CoverGallerySettings.isFixedMode(coverMode)) {
      const slot = ShelfCoverSlots.slotOf(book);
      return [covers[slot >= 0 ? slot % covers.length : start]];
    }
    const result: ResourceStr[] = [];
    const direction = seed % 2 === 0 ? 1 : covers.length - 1;
    for (let index = 0; index < covers.length; index++) {
      result.push(covers[(start + index * direction) % covers.length]);
    }
    return result;
  }

  static storedMode(): string {
    return AppStorage.get<string>('bookshelfCoverMode') || 'sequence';
  }

  static seed(book: Book): number {
    const key = `${book.bookUrl}|${book.name}|${book.author}`;
    let hash = 17;
    for (let index = 0; index < key.length; index++) hash = (hash * 31 + key.charCodeAt(index)) & 0x7FFFFFFF;
    return hash;
  }

  static interval(book: Book): number {
    return 3200 + ThemeBookCoverSettings.seed(book) % 5 * 420;
  }

  static frame(darkMode: boolean): ResourceStr {
    return ThemeAssetRegistry.themeShelfFrame(ThemeRuntime.bookTokens(darkMode).shelfFrameAssetId, darkMode);
  }

  /**
   * 书架封面套的主题边框：“主题边框”开着且主题有边框时返回边框图，否则空。和是否用主题封面无关，
   * 书自带的封面、图集封面、单独设置的封面和首字占位都套。enabled 传组件里的状态变量才会随设置刷新。
   */
  static frameIf(darkMode: boolean, enabled: boolean = ThemeBookCoverSettings.frameEnabledFromStorage()): ResourceStr {
    return enabled ? ThemeBookCoverSettings.frame(darkMode) : '';
  }

  static frameEnabledFromStorage(): boolean {
    return AppStorage.get<boolean>('appThemeBookFrameEnabled') || false;
  }
}
