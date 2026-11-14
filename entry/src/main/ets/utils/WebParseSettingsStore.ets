import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { AppDatabase } from '../model/data/AppDatabase';

/** 使用须知里的一条：小标题加一两句说明。 */
export class WebParseNoticeItem {
  title: string;
  body: string;

  constructor(title: string, body: string) {
    this.title = title;
    this.body = body;
  }
}

/**
 * “我的 › 在线阅读”里的网页解析总开关。关闭时应用只是本地阅读器：发现与搜索、书源管理、
 * 在线书籍及其缓存、相关设置项全部不出现，外部传入的书源也不接收。
 *
 * 叫法：关闭时也能看到的界面（开关说明、使用须知、关于、会员页）用中性的“规则”，
 * 只有开启后才出现的界面用“书源”。新增文案按它在哪种状态下可见来选词。
 *
 * 默认关闭，首次打开要先同意使用须知；同意的须知版本和时间只记在本机。
 * 升级前已经添加过书源的用户保持开启，下次启动时补看一次须知。
 * AppStorage 只负责通知界面，开关值以这里的 Preferences 为准。
 */
export class WebParseSettingsStore {
  static readonly KEY: string = 'webParseEnabled';
  /** 开关是开的，但当前版本的须知还没同意过（升级用户或须知改版）。 */
  static readonly KEY_NOTICE_PENDING: string = 'webParseNoticePending';
  static readonly STORE_NAME: string = 'web_parse_settings';
  /** 须知的意思有实质改动时加一，已开启的用户会被要求重新确认；只改措辞不加。 */
  static readonly NOTICE_VERSION: number = 1;
  /** 已开启后再查看、或补确认时的页面标题。 */
  static readonly NOTICE_TITLE: string = '网页解析使用须知';
  /** 第一次开启前的页面标题。 */
  static readonly NOTICE_TITLE_BEFORE_ENABLE: string = '开启前，请先了解';
  static readonly NOTICE_INTRO: string =
    '网页解析是一个工具功能：你告诉它去哪个网页、怎么读，它帮你排好版。在开启之前，有几件事想和你说清楚。';
  static readonly NOTICE_ITEMS: WebParseNoticeItem[] = [
    new WebParseNoticeItem('本应用不提供内容',
      '本应用没有内置任何规则，也不提供、不推荐任何网站的内容。'),
    new WebParseNoticeItem('规则由你添加',
      '开启后，本应用只按你添加的规则，在你的设备上打开你指定的网页并重新排版，和用浏览器打开同一个网页是一回事。'),
    new WebParseNoticeItem('请访问你有权访问的内容',
      '请遵守对应网站的服务条款和所在地的法律法规，不要用它获取未经授权的作品，或绕过付费与访问限制。'),
    new WebParseNoticeItem('使用的后果由你负责',
      '添加哪些规则、访问哪些网页由你决定，由此产生的后果也由你自行承担，本应用开发者不对此承担责任。'),
    new WebParseNoticeItem('你的数据只属于你',
      '规则和相关数据保存在你的设备上。开启数据同步后，它们只作为你的私有数据保存，不公开，也不能分享给他人。'),
    new WebParseNoticeItem('权利人如何联系我们',
      '如果你是权利人，认为这个功能被用于侵害你的权益，可以在“关于 › 交流与反馈”里找到邮箱联系我们。')
  ];
  static readonly NOTICE_CHECK_LABEL: string = '我已了解并同意以上内容';
  private static readonly KEY_NOTICE_VERSION: string = 'noticeVersion';
  private static readonly KEY_NOTICE_ACCEPTED_AT: string = 'noticeAcceptedAt';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  /** 非界面代码用它判断；界面用 @StorageProp('webParseEnabled')。 */
  static enabled(): boolean {
    return AppStorage.get<boolean>(WebParseSettingsStore.KEY) === true;
  }

  /** 开关关闭时，来自网页解析的书不出现在书架、听书页等列表里；数据保留，重新开启后恢复。 */
  static visibleBook(origin: string): boolean {
    return WebParseSettingsStore.enabled() || origin === 'local';
  }

  static async load(context: Context): Promise<void> {
    const revision = WebParseSettingsStore.revision;
    const store = await preferences.getPreferences(context, WebParseSettingsStore.STORE_NAME);
    const saved = await store.get(WebParseSettingsStore.KEY, '');
    const noticeVersion = Number(await store.get(WebParseSettingsStore.KEY_NOTICE_VERSION, 0)) || 0;
    let enabled = saved === true;
    if (typeof saved !== 'boolean') {
      // 第一次运行带这个开关的版本：已经有书源的是老用户，保持可用；否则按新安装处理。
      enabled = await WebParseSettingsStore.hasExistingRules(context);
      if (revision !== WebParseSettingsStore.revision) return;
      await store.put(WebParseSettingsStore.KEY, enabled);
      await store.flush();
    }
    if (revision !== WebParseSettingsStore.revision) return;
    AppStorage.setOrCreate(WebParseSettingsStore.KEY, enabled);
    AppStorage.setOrCreate(WebParseSettingsStore.KEY_NOTICE_PENDING,
      enabled && noticeVersion < WebParseSettingsStore.NOTICE_VERSION);
  }

  private static async hasExistingRules(context: Context): Promise<boolean> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(context);
      return await db.countBookSources() > 0;
    } catch (error) {
      console.warn('检查已有书源失败:', error);
      return false;
    }
  }

  /** 用户同意当前版本的须知并开启。 */
  static accept(context: Context): Promise<void> {
    return WebParseSettingsStore.write(context, true, true);
  }

  /** 关闭只改开关，已同意的须知版本保留，再次开启仍要重新确认。 */
  static disable(context: Context): Promise<void> {
    return WebParseSettingsStore.write(context, false, false);
  }

  private static write(context: Context, enabled: boolean, accepted: boolean): Promise<void> {
    ++WebParseSettingsStore.revision;
    AppStorage.setOrCreate(WebParseSettingsStore.KEY, enabled);
    AppStorage.setOrCreate(WebParseSettingsStore.KEY_NOTICE_PENDING, false);
    const write = WebParseSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, WebParseSettingsStore.STORE_NAME);
      await store.put(WebParseSettingsStore.KEY, enabled);
      if (accepted) {
        await store.put(WebParseSettingsStore.KEY_NOTICE_VERSION, WebParseSettingsStore.NOTICE_VERSION);
        await store.put(WebParseSettingsStore.KEY_NOTICE_ACCEPTED_AT, Date.now());
      }
      await store.flush();
    });
    WebParseSettingsStore.writes = write.catch(() => {});
    return write;
  }
}
