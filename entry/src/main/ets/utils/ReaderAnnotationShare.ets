import pasteboard from '@ohos.pasteboard';
import { router } from '@kit.ArkUI';
import { Book } from '@legado/sourceengine';
import { BookAnnotation } from '../model/reader/BookAnnotation';
import { ExcerptPosterSession, ExcerptPosterSnapshot } from '../core/excerpt/ExcerptPosterModel';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { HdsFeedback } from './HdsFeedback';

/** 划线面板里的“复制”“分享”（分享图），应用排版与文件排版、我的摘录共用。 */
export class ReaderAnnotationShare {
  static async copy(annotation: BookAnnotation): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, annotation.quote));
      HdsFeedback.showToast('已复制');
    } catch (error) {
      console.warn('复制划线失败:', error);
      HdsFeedback.showToast('复制失败，请重试');
    }
  }

  /** 打开摘录分享图页。book 是书架上的这本书，书已删了传 null（没有封面、作者）。 */
  static openPoster(annotation: BookAnnotation, book: Book | null): void {
    const snapshot = new ExcerptPosterSnapshot();
    snapshot.quote = annotation.quote;
    snapshot.note = annotation.note;
    snapshot.bookName = book?.name || annotation.bookName;
    snapshot.author = book?.author || '';
    snapshot.chapterName = annotation.chapterName;
    snapshot.time = annotation.createTime || annotation.updateTime;
    snapshot.coverUrl = book ? (book.customCoverUrl || book.coverUrl || '') : '';
    snapshot.color = annotation.color;
    snapshot.nickname = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().displayName : '';
    ExcerptPosterSession.put(snapshot);
    router.pushUrl({ url: 'pages/ExcerptShare' }).catch((error: Error): void => {
      ExcerptPosterSession.take();
      console.warn('打开摘录分享图失败:', error);
      HdsFeedback.showToast('打开分享页面失败，请重试');
    });
  }

  /** 摘录增删改后调用，足迹页的“最近摘录”据此重读。 */
  static notifyExcerptsChanged(): void {
    AppStorage.setOrCreate<number>(ReaderAnnotationShare.EXCERPT_REVISION_KEY,
      (AppStorage.get<number>(ReaderAnnotationShare.EXCERPT_REVISION_KEY) || 0) + 1);
  }

  static readonly EXCERPT_REVISION_KEY: string = 'excerptRevision';

  static timeLabel(time: number): string {
    const elapsed = Date.now() - time;
    if (elapsed < 60000) return '刚刚';
    if (elapsed < 3600000) return `${Math.floor(elapsed / 60000)} 分钟前`;
    const date = new Date(time);
    const today = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const clock = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
    if (date.toDateString() === today.toDateString()) return clock;
    const day = `${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    return date.getFullYear() === today.getFullYear() ? `${day} ${clock}` : `${date.getFullYear()}-${day}`;
  }
}
