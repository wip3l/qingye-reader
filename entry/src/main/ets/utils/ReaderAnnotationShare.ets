import { common, Context } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import pasteboard from '@ohos.pasteboard';
import { BookAnnotation } from '../model/reader/BookAnnotation';
import { HdsFeedback } from './HdsFeedback';

/** 划线面板里的“复制”“分享”，应用排版与文件排版共用。 */
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

  /** 引文、书名章节，有笔记再附上笔记，交给系统分享。 */
  static async share(context: Context, annotation: BookAnnotation): Promise<void> {
    const parts: string[] = [];
    if (annotation.bookName) parts.push(`《${annotation.bookName}》`);
    if (annotation.chapterName) parts.push(annotation.chapterName);
    let text = `「${annotation.quote.trim()}」`;
    if (parts.length > 0) text += `\n—— ${parts.join(' ')}`;
    if (annotation.note.trim()) text += `\n\n${annotation.note.trim()}`;
    try {
      const data = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        content: text
      });
      const controller = new systemShare.ShareController(data);
      await controller.show(context as common.UIAbilityContext, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (error) {
      console.warn('分享划线失败:', error);
      HdsFeedback.showToast('分享失败');
    }
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
