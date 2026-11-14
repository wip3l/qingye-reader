import { Book } from '@legado/sourceengine';
import { BookDisplayHelper } from './BookDisplayHelper';
import { ShelfCoverSlots } from './ShelfCoverSlots';

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

  static getDisplayCoverList(
    book: Book,
    darkMode: boolean,
    albumsRaw: string,
    lightAlbumId: string,
    darkAlbumId: string,
    applyScope: string,
    targetBooksRaw: string,
    ignoreSourceCover: boolean,
    coverMode: string,
    ignoreEmptyCoverOnly: boolean = false
  ): string[] {
    const selectedAlbumId = CoverGallerySettings.selectedAlbumId(darkMode, lightAlbumId, darkAlbumId);
    const albums = CoverGallerySettings.parseAlbums(albumsRaw);
    const album = CoverGallerySettings.getAlbum(albums, selectedAlbumId);
    // “仅忽略空封面”：书自带封面就只用它，没有封面才落到图集。
    const emptyOnly = ignoreSourceCover && ignoreEmptyCoverOnly;
    const sourceCovers = ignoreSourceCover && !emptyOnly ? [] : BookDisplayHelper.getCoverList(book);
    // 书架书都有 bookUrl；临时拼的书没有时退到书名作者，免得“固定”模式全部落到同一张。
    const seed = book.bookUrl || `${book.name}|${book.author}`;
    if (emptyOnly && sourceCovers.length > 0) {
      return CoverGallerySettings.applyCoverMode(sourceCovers, coverMode, seed, book);
    }
    if (!album || album.covers.length === 0 || !CoverGallerySettings.appliesToBook(book.bookUrl, applyScope, targetBooksRaw)) {
      return CoverGallerySettings.applyCoverMode(sourceCovers, coverMode, seed, book);
    }
    const covers = ignoreSourceCover ? album.covers : CoverGallerySettings.cleanCovers([...sourceCovers, ...album.covers]);
    return CoverGallerySettings.applyCoverMode(covers, coverMode, seed, book);
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
    return CoverGallerySettings.parseTargetBooks(targetBooksRaw).includes(bookUrl);
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
