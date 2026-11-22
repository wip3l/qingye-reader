import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 票夹的本机选项：票面样式、两列/单列、标成读过时的出票动画。
 * 写进 Preferences 而不是 PersistentStorage：后者改过的值重启后会回到默认。
 */
export class TicketAlbumStore {
  static readonly STYLE_CARD: string = 'card';
  static readonly STYLE_MOVIE: string = 'movie';
  static readonly STYLES: string[] = ['card', 'movie'];
  static readonly STYLE_NAMES: string[] = ['藏书卡', '电影票'];
  private static readonly STORE_NAME: string = 'ticket_album';
  private static readonly KEY_STYLE: string = 'style';
  private static readonly KEY_SINGLE: string = 'single';
  private static readonly KEY_ISSUE: string = 'issueAnimation';
  private static loaded: boolean = false;
  private static style: string = 'card';
  private static single: boolean = false;
  private static issue: boolean = true;

  static normalizeStyle(style: string): string {
    return TicketAlbumStore.STYLES.includes(style) ? style : TicketAlbumStore.STYLE_CARD;
  }

  static styleName(style: string): string {
    return TicketAlbumStore.STYLE_NAMES[Math.max(0, TicketAlbumStore.STYLES.indexOf(style))];
  }

  static async load(context: Context): Promise<void> {
    if (TicketAlbumStore.loaded) return;
    try {
      const store = await preferences.getPreferences(context, TicketAlbumStore.STORE_NAME);
      const style = await store.get(TicketAlbumStore.KEY_STYLE, TicketAlbumStore.STYLE_CARD);
      const single = await store.get(TicketAlbumStore.KEY_SINGLE, false);
      const issue = await store.get(TicketAlbumStore.KEY_ISSUE, true);
      if (!TicketAlbumStore.loaded) {
        TicketAlbumStore.style = TicketAlbumStore.normalizeStyle(typeof style === 'string' ? style : '');
        TicketAlbumStore.single = single === true;
        TicketAlbumStore.issue = issue !== false;
      }
    } catch (error) {
      console.warn('读取票夹设置失败:', error);
    }
    TicketAlbumStore.loaded = true;
  }

  static currentStyle(): string {
    return TicketAlbumStore.style;
  }

  static singleColumn(): boolean {
    return TicketAlbumStore.single;
  }

  static issueAnimation(): boolean {
    return TicketAlbumStore.issue;
  }

  static async saveStyle(context: Context, style: string): Promise<void> {
    TicketAlbumStore.style = TicketAlbumStore.normalizeStyle(style);
    TicketAlbumStore.loaded = true;
    await TicketAlbumStore.put(context, TicketAlbumStore.KEY_STYLE, TicketAlbumStore.style);
  }

  static async saveSingleColumn(context: Context, single: boolean): Promise<void> {
    TicketAlbumStore.single = single;
    TicketAlbumStore.loaded = true;
    await TicketAlbumStore.put(context, TicketAlbumStore.KEY_SINGLE, single);
  }

  static async saveIssueAnimation(context: Context, enabled: boolean): Promise<void> {
    TicketAlbumStore.issue = enabled;
    TicketAlbumStore.loaded = true;
    await TicketAlbumStore.put(context, TicketAlbumStore.KEY_ISSUE, enabled);
  }

  private static async put(context: Context, key: string, value: string | boolean): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, TicketAlbumStore.STORE_NAME);
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      console.warn('保存票夹设置失败:', error);
    }
  }
}
