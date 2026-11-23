import { Book, BookChapter, BookTypeSupport, ReaderActionMarker } from '@legado/sourceengine';

/**
 * 图文书里的视频章（原生书源目录标了 type: video，书本身不是视频类型）。
 *
 * 阅读页不去取这一章的正文，只排一张播放卡片：翻页照常经过它，阅读进度停在这一章，不会被视频的秒数打乱；
 * 预读、缓存、朗读拿到的也只是这张卡片，不会把视频地址当正文存下来或念出来。点卡片上的按钮进入播放页，
 * 播放页只列这本书的视频章，播放进度单独记录（见 MixedVideoProgress）。
 */
export class MixedVideoChapter {
  static readonly SCHEME: string = 'legado-video-chapter:';

  static isMixedVideo(book: Book | null | undefined, chapter: BookChapter | null | undefined): boolean {
    return !!book && !!chapter && BookChapter.isVideoChapter(chapter) && !BookTypeSupport.isVideo(book);
  }

  /** 视频类书籍之外的书：播放页按“图文书里的视频章”处理。 */
  static isMixedBook(book: Book | null | undefined): boolean {
    return !!book && !BookTypeSupport.isVideo(book);
  }

  static cardText(chapter: BookChapter): string {
    const button = ReaderActionMarker.create('▶ 播放视频', `${MixedVideoChapter.SCHEME}${chapter.index}`,
      chapter.title || '视频');
    return `本章是视频，点下面的按钮播放。\n\n${button}`;
  }

  static isPlayAction(url: string): boolean {
    return (url || '').startsWith(MixedVideoChapter.SCHEME);
  }

  /** 播放按钮对应的章节序号；不是播放按钮或序号无效时为 -1。 */
  static chapterIndexOf(url: string): number {
    if (!MixedVideoChapter.isPlayAction(url)) return -1;
    const index = Number(url.substring(MixedVideoChapter.SCHEME.length));
    return Number.isInteger(index) && index >= 0 ? index : -1;
  }
}
