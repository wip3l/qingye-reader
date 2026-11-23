import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * 票夹的本机选项：票面样式、两列/单列、标成读过时的出票动画。
 * 写进 Preferences 而不是 PersistentStorage：后者改过的值重启后会回到默认。
 */
export class TicketAlbumStore {
  /** 影票：纸质电影票版式，默认样式。 */
  static readonly STYLE_PAPER: string = 'paper';
  /** 暗场：满版封面接黑色票根。 */
  static readonly STYLE_NIGHT: string = 'night';
  static readonly STYLE_CARD: string = 'card';
  static readonly STYLE_BORROW: string = 'borrow';
  static readonly STYLE_TRAIN: string = 'train';
  /** 早期的“电影票”，已由影票取代；存着这个值的按影票处理。 */
  private static readonly LEGACY_MOVIE: string = 'movie';
  static readonly STYLES: string[] = ['paper', 'night', 'card', 'borrow', 'train'];
  static readonly STYLE_NAMES: string[] = ['影票', '暗场', '藏书卡', '借书卡', '车票'];
  private static readonly STORE_NAME: string = 'ticket_album';
  private static readonly KEY_STYLE: string = 'style';
  private static readonly KEY_SINGLE: string = 'single';
  private static readonly KEY_ISSUE: string = 'issueAnimation';
  private static readonly KEY_COVER_SR: string = 'coverSuperResolution';
  /** 票面封面超分开关在 AppStorage 里的键，票面组件据此即时开关；默认开。 */
  static readonly COVER_SR_STORAGE_KEY: string = 'ticketCoverSuperResolution';
  private static readonly KEY_ORIGINAL_COVER: string = 'originalCover';
  /** 票面用书籍原始封面的开关在 AppStorage 里的键；默认关（跟书架一样的封面）。 */
  static readonly ORIGINAL_COVER_STORAGE_KEY: string = 'ticketOriginalCover';
  private static loaded: boolean = false;
  private static style: string = 'paper';
  private static single: boolean = false;
  private static issue: boolean = true;

  static normalizeStyle(style: string): string {
    if (style === TicketAlbumStore.LEGACY_MOVIE) return TicketAlbumStore.STYLE_PAPER;
    return TicketAlbumStore.STYLES.includes(style) ? style : TicketAlbumStore.STYLE_PAPER;
  }

  static styleName(style: string): string {
    return TicketAlbumStore.STYLE_NAMES[Math.max(0, TicketAlbumStore.STYLES.indexOf(style))];
  }

  static async load(context: Context): Promise<void> {
    if (TicketAlbumStore.loaded) return;
    try {
      const store = await preferences.getPreferences(context, TicketAlbumStore.STORE_NAME);
      const style = await store.get(TicketAlbumStore.KEY_STYLE, TicketAlbumStore.STYLE_PAPER);
      const single = await store.get(TicketAlbumStore.KEY_SINGLE, false);
      const issue = await store.get(TicketAlbumStore.KEY_ISSUE, true);
      const coverSr = await store.get(TicketAlbumStore.KEY_COVER_SR, true);
      const originalCover = await store.get(TicketAlbumStore.KEY_ORIGINAL_COVER, false);
      if (!TicketAlbumStore.loaded) {
        TicketAlbumStore.style = TicketAlbumStore.normalizeStyle(typeof style === 'string' ? style : '');
        TicketAlbumStore.single = single === true;
        TicketAlbumStore.issue = issue !== false;
        AppStorage.setOrCreate(TicketAlbumStore.COVER_SR_STORAGE_KEY, coverSr !== false);
        AppStorage.setOrCreate(TicketAlbumStore.ORIGINAL_COVER_STORAGE_KEY, originalCover === true);
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

  static coverSuperResolution(): boolean {
    return AppStorage.get<boolean>(TicketAlbumStore.COVER_SR_STORAGE_KEY) !== false;
  }

  static async saveCoverSuperResolution(context: Context, enabled: boolean): Promise<void> {
    AppStorage.setOrCreate(TicketAlbumStore.COVER_SR_STORAGE_KEY, enabled);
    TicketAlbumStore.loaded = true;
    await TicketAlbumStore.put(context, TicketAlbumStore.KEY_COVER_SR, enabled);
  }

  static originalCover(): boolean {
    return AppStorage.get<boolean>(TicketAlbumStore.ORIGINAL_COVER_STORAGE_KEY) === true;
  }

  static async saveOriginalCover(context: Context, enabled: boolean): Promise<void> {
    AppStorage.setOrCreate(TicketAlbumStore.ORIGINAL_COVER_STORAGE_KEY, enabled);
    TicketAlbumStore.loaded = true;
    await TicketAlbumStore.put(context, TicketAlbumStore.KEY_ORIGINAL_COVER, enabled);
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
