import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 段评、热评、本章说三项各自的显示设置。
 * 保存为一串 "热评样式,每页上限,行数,段评气泡,本章说"：
 * 热评样式 0 关闭、1 卡片、2 引文、3 挂件，段评带热评原文时把这条评论画在段落下方；
 * 每页上限 0 表示不限，只限制段评热评，书源自带的热评卡总是显示；行数 1 或 2；
 * 段评气泡 0 不显示、1 显示（热评关闭时，热评入口也按气泡算）；
 * 本章说 0 不显示、1 气泡、2 卡片（只有单独成段的入口画成整宽卡片）。
 * 旧版本只存前三项：气泡按显示，本章说跟随当时的热评样式（关闭时是气泡，否则是卡片）。
 * Preferences 是唯一的保存来源，AppStorage 只负责通知阅读页重新排版。
 */
export class ReaderCommentCardSettings {
  static readonly KEY: string = 'readerCommentCard';
  static readonly STORE_NAME: string = 'reader_comment_card_settings';
  static readonly STYLE_OFF: number = 0;
  static readonly STYLE_CARD: number = 1;
  static readonly STYLE_QUOTE: number = 2;
  static readonly STYLE_TAG: number = 3;
  static readonly CHAPTER_OFF: number = 0;
  static readonly CHAPTER_BUBBLE: number = 1;
  static readonly CHAPTER_CARD: number = 2;
  static readonly DEFAULT: string = '1,2,1,1,2';
  static readonly STYLE_LABELS: string[] = ['关闭', '卡片', '引文', '挂件'];
  static readonly MAX_VALUES: number[] = [1, 2, 0];
  static readonly MAX_LABELS: string[] = ['1 张', '2 张', '不限'];
  static readonly LINE_LABELS: string[] = ['一行', '两行'];
  static readonly CHAPTER_LABELS: string[] = ['关闭', '气泡', '卡片'];
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static style(raw: string): number {
    const value = Number.parseInt(ReaderCommentCardSettings.normalize(raw).split(',')[0], 10);
    return value;
  }

  static maxPerPage(raw: string): number {
    return Number.parseInt(ReaderCommentCardSettings.normalize(raw).split(',')[1], 10);
  }

  static lines(raw: string): number {
    return Number.parseInt(ReaderCommentCardSettings.normalize(raw).split(',')[2], 10);
  }

  static bubbles(raw: string): boolean {
    return ReaderCommentCardSettings.normalize(raw).split(',')[3] === '1';
  }

  static chapter(raw: string): number {
    return Number.parseInt(ReaderCommentCardSettings.normalize(raw).split(',')[4], 10);
  }

  static encode(style: number, maxPerPage: number, lines: number, bubbles: boolean, chapter: number): string {
    return ReaderCommentCardSettings.normalize(`${style},${maxPerPage},${lines},${bubbles ? 1 : 0},${chapter}`);
  }

  static normalize(raw: string): string {
    const parts = (raw || '').split(',').map((part: string): number => Number.parseInt(part.trim(), 10));
    const defaults = ReaderCommentCardSettings.DEFAULT.split(',')
      .map((part: string): number => Number.parseInt(part, 10));
    const style = parts.length > 0 && Number.isInteger(parts[0]) && parts[0] >= 0 && parts[0] <= 3 ? parts[0] :
      defaults[0];
    const max = parts.length > 1 && ReaderCommentCardSettings.MAX_VALUES.includes(parts[1]) ? parts[1] : defaults[1];
    const lines = parts.length > 2 && (parts[2] === 1 || parts[2] === 2) ? parts[2] : defaults[2];
    const bubbles = parts.length > 3 && parts[3] === 0 ? 0 : 1;
    const chapter = parts.length > 4 && Number.isInteger(parts[4]) && parts[4] >= 0 && parts[4] <= 2 ? parts[4] :
      (style === ReaderCommentCardSettings.STYLE_OFF ? ReaderCommentCardSettings.CHAPTER_BUBBLE :
        ReaderCommentCardSettings.CHAPTER_CARD);
    return `${style},${max},${lines},${bubbles},${chapter}`;
  }

  static async load(context: Context): Promise<void> {
    const revision = ReaderCommentCardSettings.revision;
    const store = await preferences.getPreferences(context, ReaderCommentCardSettings.STORE_NAME);
    const value = await store.get(ReaderCommentCardSettings.KEY, ReaderCommentCardSettings.DEFAULT);
    // 读取期间用户已经改过设置时，以新值为准。
    if (revision !== ReaderCommentCardSettings.revision) return;
    AppStorage.setOrCreate(ReaderCommentCardSettings.KEY,
      ReaderCommentCardSettings.normalize(typeof value === 'string' ? value : ''));
  }

  static save(context: Context, value: string): Promise<void> {
    const next = ReaderCommentCardSettings.normalize(value);
    ++ReaderCommentCardSettings.revision;
    AppStorage.setOrCreate(ReaderCommentCardSettings.KEY, next);
    const write = ReaderCommentCardSettings.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ReaderCommentCardSettings.STORE_NAME);
      await store.put(ReaderCommentCardSettings.KEY, next);
      await store.flush();
    });
    ReaderCommentCardSettings.writes = write.catch((error: Error): void => {
      console.warn('保存段评显示设置失败:', error);
    });
    return write;
  }
}
