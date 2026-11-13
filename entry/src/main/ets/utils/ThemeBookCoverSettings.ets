import { Book } from '@legado/sourceengine';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { CoverGallerySettings } from './CoverGallerySettings';

/** 各页面共用主题封面的顺序和轮播间隔。 */
export class ThemeBookCoverSettings {
  static enabled(darkMode: boolean, enabled: boolean): boolean {
    return enabled &&
      ThemeAssetRegistry.themeBookCovers(ThemeRuntime.bookTokens(darkMode).coverAssetId, darkMode).length > 0;
  }

  /** coverMode 传组件里的状态变量才会随设置刷新；不传时读当前存储。 */
  static covers(book: Book, darkMode: boolean, coverMode: string = ThemeBookCoverSettings.storedMode()): ResourceStr[] {
    return ThemeBookCoverSettings.coversForAsset(book, ThemeRuntime.bookTokens(darkMode).coverAssetId, darkMode,
      coverMode);
  }

  /**
   * “固定”模式每本书只留轮播的首张，和静态载体（卡片、媒体信息）取的是同一张。
   * 起始序号只由书决定，浅深两套封面张数相同时同一本书在两种模式下落在同一序号上。
   */
  static coversForAsset(book: Book, assetId: string, darkMode: boolean,
    coverMode: string = ThemeBookCoverSettings.storedMode()): ResourceStr[] {
    const covers = ThemeAssetRegistry.themeBookCovers(assetId, darkMode);
    if (covers.length <= 1) return covers;
    const seed = ThemeBookCoverSettings.seed(book);
    const start = seed % covers.length;
    if (CoverGallerySettings.isFixedMode(coverMode)) return [covers[start]];
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
    return ThemeAssetRegistry.themeShelfFrame(ThemeRuntime.bookTokens(darkMode).shelfFrameAssetId);
  }
}
