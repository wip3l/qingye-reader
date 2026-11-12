import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 热评卡片：段评带热评原文时，把这条评论画在段落下方；章末单独成段的本章说入口画成整宽卡片。
 * 保存为一串 "样式,每页上限,行数"：样式 0 关闭（只显示气泡）、1 卡片、2 引文、3 挂件；
 * 每页上限 0 表示不限，只限制段评热评，书源自带的热评卡总是显示；行数 1 或 2。
 * Preferences 是唯一的保存来源，AppStorage 只负责通知阅读页重新排版。
 */
export class ReaderCommentCardSettings {
  static readonly KEY: string = 'readerCommentCard';
  static readonly STORE_NAME: string = 'reader_comment_card_settings';
  static readonly STYLE_OFF: number = 0;
  static readonly STYLE_CARD: number = 1;
  static readonly STYLE_QUOTE: number = 2;
  static readonly STYLE_TAG: number = 3;
  static readonly DEFAULT: string = '1,2,1';
  static readonly STYLE_LABELS: string[] = ['关闭', '卡片', '引文', '挂件'];
  static readonly MAX_VALUES: number[] = [1, 2, 0];
  static readonly MAX_LABELS: string[] = ['1 张', '2 张', '不限'];
  static readonly LINE_LABELS: string[] = ['一行', '两行'];
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

  static encode(style: number, maxPerPage: number, lines: number): string {
    return ReaderCommentCardSettings.normalize(`${style},${maxPerPage},${lines}`);
  }

  static normalize(raw: string): string {
    const parts = (raw || '').split(',').map((part: string): number => Number.parseInt(part.trim(), 10));
    const defaults = ReaderCommentCardSettings.DEFAULT.split(',')
      .map((part: string): number => Number.parseInt(part, 10));
    const style = parts.length > 0 && Number.isInteger(parts[0]) && parts[0] >= 0 && parts[0] <= 3 ? parts[0] :
      defaults[0];
    const max = parts.length > 1 && ReaderCommentCardSettings.MAX_VALUES.includes(parts[1]) ? parts[1] : defaults[1];
    const lines = parts.length > 2 && (parts[2] === 1 || parts[2] === 2) ? parts[2] : defaults[2];
    return `${style},${max},${lines}`;
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
      console.warn('保存热评卡片设置失败:', error);
    });
    return write;
  }
}
