import { Book } from '@legado/sourceengine';
import { BookDisplayHelper } from './BookDisplayHelper';
import { ShelfCoverSlots } from './ShelfCoverSlots';
import { CoverGallerySnapshot } from './CoverGalleryStore';

export class CoverAlbum {
  id: string = '';
  name: string = '';
  covers: string[] = [];
}

class CoverAlbumData {
  albums: CoverAlbum[] = [];
}

export class CoverGallerySettings {
  static parseAlbums(raw: string): CoverAlbum[] {
    const value = (raw || '').trim();
    if (!value) {
      return [];
    }
    try {
      const parsed = JSON.parse(value) as CoverAlbumData | CoverAlbum[];
      const source = Array.isArray(parsed) ? parsed as CoverAlbum[] : ((parsed as CoverAlbumData).albums || []);
      const albums: CoverAlbum[] = [];
      for (const item of source) {
        if (!item || !item.id) {
          continue;
        }
        const album = new CoverAlbum();
        album.id = item.id;
        album.name = item.name || '未命名图集';
        album.covers = CoverGallerySettings.cleanCovers(item.covers || []);
        albums.push(album);
      }
      return albums;
    } catch (e) {
      return [];
    }
  }

  static encodeAlbums(albums: CoverAlbum[]): string {
    const data = new CoverAlbumData();
    data.albums = [];
    for (const item of albums) {
      if (!item || !item.id) {
        continue;
      }
      const album = new CoverAlbum();
      album.id = item.id;
      album.name = item.name || '未命名图集';
      album.covers = CoverGallerySettings.cleanCovers(item.covers || []);
      data.albums.push(album);
    }
    return JSON.stringify(data);
  }

  static selectedAlbumId(darkMode: boolean, lightAlbumId: string, darkAlbumId: string): string {
    return darkMode ? darkAlbumId : lightAlbumId;
  }

  static getAlbum(albums: CoverAlbum[], id: string): CoverAlbum | null {
    if (!id) {
      return null;
    }
    for (const album of albums) {
      if (album.id === id) {
        return album;
      }
    }
    return null;
  }

  /**
   * 一本书不走主题封面时显示哪些图，从上到下依次取用：
   * 单独设置的封面 → 统一封面用的图集（replaceAlbum，受应用范围限制）→ 书籍自带封面 → 没有封面时的图集（fallback 为 album）。
   * 都没有时返回空，由调用方显示书名占位。主题封面在这之外判断，见 ThemeBookCoverSettings.enabledFor。
   */
  static getDisplayCoverList(
    book: Book,
    darkMode: boolean,
    albumsRaw: string,
    lightAlbumId: string,
    darkAlbumId: string,
    applyScope: string,
    targetBooksRaw: string,
    coverMode: string,
    replaceAlbum: boolean,
    albumMix: boolean,
    fallback: string
  ): string[] {
    // 单独设置的封面最优先：不和图集混排，也不参与封面模式挑图。
    const customCovers = BookDisplayHelper.decodeCoverList(book.customCoverUrl);
    if (customCovers.length > 0) {
      return CoverGallerySettings.cleanCovers(customCovers);
    }
    const selectedAlbumId = CoverGallerySettings.selectedAlbumId(darkMode, lightAlbumId, darkAlbumId);
    const album = CoverGallerySettings.getAlbum(CoverGallerySettings.cachedAlbums(albumsRaw), selectedAlbumId);
    const albumCovers = album ? album.covers : [];
    const ownCovers = BookDisplayHelper.getCoverList(book);
    // 书架书都有 bookUrl；临时拼的书没有时退到书名作者，免得“固定”模式全部落到同一张。
    const seed = book.bookUrl || `${book.name}|${book.author}`;
    if (replaceAlbum && albumCovers.length > 0 &&
      CoverGallerySettings.appliesToBook(book.bookUrl, applyScope, targetBooksRaw)) {
      const covers = albumMix ? CoverGallerySettings.cleanCovers([...ownCovers, ...albumCovers]) : albumCovers;
      return CoverGallerySettings.applyCoverMode(covers, coverMode, seed, book);
    }
    if (ownCovers.length > 0) {
      return CoverGallerySettings.applyCoverMode(ownCovers, coverMode, seed, book);
    }
    if (fallback === 'album' && albumCovers.length > 0) {
      return CoverGallerySettings.applyCoverMode(albumCovers, coverMode, seed, book);
    }
    return [];
  }

  /** 不走主题封面时这本书的图来自哪里：custom、album、mixed（自带与图集轮播）、own、none。判断顺序与 getDisplayCoverList 一致。 */
  static sourceKind(book: Book, darkMode: boolean, settings: CoverGallerySnapshot): string {
    if (BookDisplayHelper.hasCustomCover(book)) return 'custom';
    const album = CoverGallerySettings.getAlbum(CoverGallerySettings.cachedAlbums(settings.albumsRaw),
      CoverGallerySettings.selectedAlbumId(darkMode, settings.lightAlbumId, settings.darkAlbumId));
    const hasAlbum = !!album && album.covers.length > 0;
    const hasOwn = BookDisplayHelper.getCoverList(book).length > 0;
    if (settings.replaceAlbum && hasAlbum &&
      CoverGallerySettings.appliesToBook(book.bookUrl, settings.applyScope, settings.targetBooksRaw)) {
      return settings.albumMix && hasOwn ? 'mixed' : 'album';
    }
    if (hasOwn) return 'own';
    return settings.fallback === 'album' && hasAlbum ? 'album' : 'none';
  }

  /** 按一份设置取图，参数含义同 getDisplayCoverList。 */
  static coversFor(book: Book, darkMode: boolean, settings: CoverGallerySnapshot): string[] {
    return CoverGallerySettings.getDisplayCoverList(book, darkMode, settings.albumsRaw, settings.lightAlbumId,
      settings.darkAlbumId, settings.applyScope, settings.targetBooksRaw, settings.coverMode, settings.replaceAlbum,
      settings.albumMix, settings.fallback);
  }

  /** 统一封面用图集且不和自带封面轮播时，这本书直接用图集，不必先知道它有没有封面；其余情况返回空。 */
  static replaceOnlyAlbumCovers(book: Book, darkMode: boolean, settings: CoverGallerySnapshot): string[] {
    if (!settings.replaceAlbum || settings.albumMix || BookDisplayHelper.hasCustomCover(book)) return [];
    const bare = new Book();
    bare.bookUrl = book.bookUrl;
    bare.name = book.name;
    bare.author = book.author;
    bare.origin = book.origin;
    const quiet = new CoverGallerySnapshot();
    quiet.albumsRaw = settings.albumsRaw;
    quiet.lightAlbumId = settings.lightAlbumId;
    quiet.darkAlbumId = settings.darkAlbumId;
    quiet.applyScope = settings.applyScope;
    quiet.targetBooksRaw = settings.targetBooksRaw;
    quiet.coverMode = settings.coverMode;
    quiet.replaceAlbum = true;
    return CoverGallerySettings.coversFor(bare, darkMode, quiet);
  }

  static parseTargetBooks(raw: string): string[] {
    const value = (raw || '').trim();
    if (!value) {
      return [];
    }
    try {
      const parsed = JSON.parse(value) as string[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: string[] = [];
      for (const item of parsed) {
        const value = (item || '').trim();
        if (value && !result.includes(value)) {
          result.push(value);
        }
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  static encodeTargetBooks(bookUrls: string[]): string {
    const result: string[] = [];
    for (const item of bookUrls) {
      const value = (item || '').trim();
      if (value && !result.includes(value)) {
        result.push(value);
      }
    }
    return JSON.stringify(result);
  }

  static createAlbum(name: string): CoverAlbum {
    const album = new CoverAlbum();
    album.id = `album_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    album.name = name || '新建图集';
    album.covers = [];
    return album;
  }

  private static appliesToBook(bookUrl: string, applyScope: string, targetBooksRaw: string): boolean {
    if (applyScope !== 'books') {
      return true;
    }
    return CoverGallerySettings.cachedTargetBooks(targetBooksRaw).includes(bookUrl);
  }

  /**
   * 书架每本书取封面都要解析一次图集设置，一个格子要取好几次；按原始字符串记住上次的解析结果。
   * 只给本类只读使用（applyCoverMode 总是返回新数组），对外的 parseAlbums 仍每次返回新对象，调用方可以放心改。
   */
  private static albumsMemoRaw: string | null = null;
  private static albumsMemo: CoverAlbum[] = [];
  private static targetBooksMemoRaw: string | null = null;
  private static targetBooksMemo: string[] = [];

  private static cachedAlbums(raw: string): CoverAlbum[] {
    if (raw !== CoverGallerySettings.albumsMemoRaw) {
      CoverGallerySettings.albumsMemo = CoverGallerySettings.parseAlbums(raw);
      CoverGallerySettings.albumsMemoRaw = raw;
    }
    return CoverGallerySettings.albumsMemo;
  }

  private static cachedTargetBooks(raw: string): string[] {
    if (raw !== CoverGallerySettings.targetBooksMemoRaw) {
      CoverGallerySettings.targetBooksMemo = CoverGallerySettings.parseTargetBooks(raw);
      CoverGallerySettings.targetBooksMemoRaw = raw;
    }
    return CoverGallerySettings.targetBooksMemo;
  }

  /** 封面模式：sequence 轮播全部、random 每小时换一张、fixed 每本书固定一张（书架上的书按加入先后的序号轮流分，见 ShelfCoverSlots；其余按书算哈希）。 */
  static isFixedMode(coverMode: string): boolean {
    return coverMode === 'fixed';
  }

  private static applyCoverMode(covers: string[], coverMode: string, seed: string, book: Book): string[] {
    const cleaned = CoverGallerySettings.cleanCovers(covers);
    if (cleaned.length <= 1) {
      return cleaned;
    }
    if (CoverGallerySettings.isFixedMode(coverMode)) {
      const slot = ShelfCoverSlots.slotOf(book);
      const index = slot >= 0 ? slot : Math.abs(CoverGallerySettings.hashText(seed));
      return [cleaned[index % cleaned.length]];
    }
    if (coverMode !== 'random') {
      return cleaned;
    }
    const index = Math.abs(CoverGallerySettings.hashText(`${seed}_${Math.floor(Date.now() / 3600000)}`)) % cleaned.length;
    return [cleaned[index]];
  }

  private static cleanCovers(covers: string[]): string[] {
    const cleaned: string[] = [];
    for (const cover of covers) {
      const value = (cover || '').trim();
      if (value && !cleaned.includes(value)) {
        cleaned.push(value);
      }
    }
    return cleaned;
  }

  private static hashText(value: string): number {
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = value.charCodeAt(i) + ((hash << 5) - hash);
    }
    return hash;
  }
}
