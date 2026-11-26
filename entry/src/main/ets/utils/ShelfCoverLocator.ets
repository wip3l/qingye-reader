import image from '@ohos.multimedia.image';
import { ShelfOpeningCover } from '../components/reader/ReaderShelfCoverOpening';

/**
 * Lets a reader page ask the live bookshelf two things just before leaving: where a book's cover is right now, so
 * the close animation can shrink the page back onto it, and a snapshot of the whole home page to show behind the
 * shrinking page (a covered router page is not rendered, but it can still be snapshotted offscreen). The shelf
 * registers both while it is mounted. A process-wide module: page-file statics are recreated per page instance.
 */
/** 书架上这本书现在显示的封面：多图取轮播正停着的那张；cover 为空串表示书架画的是首字色块。 */
export interface ShelfCoverLook {
  cover: ResourceStr;
  /** 主题书框，没有时为空串。 */
  frame: ResourceStr;
}

export class ShelfCoverLocator {
  private static measure: ((bookUrl: string) => ShelfOpeningCover | null) | null = null;
  private static snapshot: (() => Promise<image.PixelMap>) | null = null;
  private static lookup: ((bookUrl: string) => ShelfCoverLook | null) | null = null;

  static register(measure: (bookUrl: string) => ShelfOpeningCover | null,
    snapshot: (() => Promise<image.PixelMap>) | null = null,
    lookup: ((bookUrl: string) => ShelfCoverLook | null) | null = null): void {
    ShelfCoverLocator.measure = measure;
    ShelfCoverLocator.snapshot = snapshot;
    ShelfCoverLocator.lookup = lookup;
  }

  static unregister(measure: (bookUrl: string) => ShelfOpeningCover | null): void {
    if (ShelfCoverLocator.measure !== measure) return;
    ShelfCoverLocator.measure = null;
    ShelfCoverLocator.snapshot = null;
    ShelfCoverLocator.lookup = null;
  }

  /** 书架上这本书现在显示的封面（不管在不在屏幕内）；书架没挂载或书不在书架上时为 null。 */
  static look(bookUrl: string): ShelfCoverLook | null {
    if (!ShelfCoverLocator.lookup || !bookUrl) return null;
    try {
      return ShelfCoverLocator.lookup(bookUrl);
    } catch (_) {
      return null;
    }
  }

  /** The cover's current window bounds (vp), or null when the shelf is not mounted or the cover is not on screen. */
  static locate(bookUrl: string): ShelfOpeningCover | null {
    if (!ShelfCoverLocator.measure || !bookUrl) return null;
    try {
      const cover = ShelfCoverLocator.measure(bookUrl);
      return cover && ShelfCoverLocator.usable(cover) ? cover : null;
    } catch (_) {
      return null;
    }
  }

  /** A full-window picture of the home page as it looks right now, or null when it cannot be produced. */
  static async backdrop(): Promise<image.PixelMap | null> {
    if (!ShelfCoverLocator.snapshot) return null;
    try {
      return await ShelfCoverLocator.snapshot();
    } catch (error) {
      console.warn('书架背景截图失败:', error);
      return null;
    }
  }

  /** The same validity rule the opening animation applies to measured bounds. */
  static usable(cover: ShelfOpeningCover | null): boolean {
    return !!cover && cover.boundsWidth > 0 && cover.boundsHeight > 0 &&
      cover.windowWidth > cover.boundsWidth && cover.windowHeight > cover.boundsHeight;
  }
}
