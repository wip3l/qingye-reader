import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { WebParseNoticeItem } from './WebParseSettingsStore';

/**
 * “我的 › 实验室 › 插件”总开关。关闭时插件一律不运行：插件管理不出现，插件提供的音色不进音色列表，
 * 已装的插件和它们的数据都保留，重新开启后恢复。
 *
 * 默认关闭；每次打开都要先在须知页同意（和网页解析一样），同意的须知版本和时间只记在本机，不参与同步。
 * 单个插件的启用开关不再弹须知。AppStorage 只负责通知界面，开关值以这里的 Preferences 为准。
 */
export class PluginFeatureStore {
  static readonly KEY: string = 'pluginFeatureEnabled';
  static readonly STORE_NAME: string = 'plugin_feature_settings';
  /** 须知的意思有实质改动时加一；只改措辞不加。 */
  static readonly NOTICE_VERSION: number = 1;
  static readonly NOTICE_TITLE: string = '插件使用须知';
  static readonly NOTICE_TITLE_BEFORE_ENABLE: string = '开启前，请先了解';
  static readonly NOTICE_INTRO: string =
    '插件功能开启后，你可以安装第三方开发的插件，它们会在你的设备上运行自己的代码。在开启之前，有几件事想和你说清楚。';
  static readonly NOTICE_ITEMS: WebParseNoticeItem[] = [
    new WebParseNoticeItem('插件不是本应用的一部分',
      '插件由第三方开发和维护。本应用不内置、不提供、也不推荐任何插件，不审核插件的内容。'),
    new WebParseNoticeItem('插件只能做它声明过的事',
      '插件只能使用安装时列出的权限，联网也只能访问声明过的域名，超出范围的请求会被拦下。'),
    new WebParseNoticeItem('只安装你信任的来源',
      '未签名的插件无法确认作者是谁，以后更新时也无法核对新版是不是同一作者发布的。'),
    new WebParseNoticeItem('使用的后果由你负责',
      '插件连接哪些服务、获取哪些内容，请遵守对应服务的条款和所在地的法律法规。由此产生的后果由你自行承担，本应用开发者不对此承担责任。'),
    new WebParseNoticeItem('插件的数据留在本机',
      '插件的设置、登录令牌和数据只保存在你的设备上，不参与数据同步，卸载插件时一并删除。'),
    new WebParseNoticeItem('出了问题怎么办',
      '插件出错或不再需要时，随时可以在插件管理里停用或卸载，也可以直接关掉插件功能。插件本身的问题请联系插件作者。')
  ];
  static readonly NOTICE_CHECK_LABEL: string = '我已了解并同意以上内容';
  private static readonly KEY_NOTICE_VERSION: string = 'noticeVersion';
  private static readonly KEY_NOTICE_ACCEPTED_AT: string = 'noticeAcceptedAt';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();
  private static listeners: Set<(enabled: boolean) => void> = new Set();

  /** 非界面代码用它判断；界面用 @StorageProp('pluginFeatureEnabled')。 */
  static enabled(): boolean {
    return AppStorage.get<boolean>(PluginFeatureStore.KEY) === true;
  }

  /** 开关变化（含冷启动读出开启）时回调，插件宿主据此初始化已装插件。 */
  static subscribe(fn: (enabled: boolean) => void): () => void {
    PluginFeatureStore.listeners.add(fn);
    return () => {
      PluginFeatureStore.listeners.delete(fn);
    };
  }

  static async load(context: Context): Promise<void> {
    const revision = PluginFeatureStore.revision;
    const store = await preferences.getPreferences(context, PluginFeatureStore.STORE_NAME);
    const saved = await store.get(PluginFeatureStore.KEY, false);
    const noticeVersion = Number(await store.get(PluginFeatureStore.KEY_NOTICE_VERSION, 0)) || 0;
    if (revision !== PluginFeatureStore.revision) return;
    // 须知改版后，已开启的用户在重新同意前按关闭处理。
    PluginFeatureStore.publish(saved === true && noticeVersion >= PluginFeatureStore.NOTICE_VERSION);
  }

  /** 用户同意当前版本的须知并开启。 */
  static accept(context: Context): Promise<void> {
    return PluginFeatureStore.write(context, true, true);
  }

  /** 关闭只改开关，再次开启仍要重新确认须知。 */
  static disable(context: Context): Promise<void> {
    return PluginFeatureStore.write(context, false, false);
  }

  private static publish(enabled: boolean): void {
    AppStorage.setOrCreate(PluginFeatureStore.KEY, enabled);
    for (const fn of PluginFeatureStore.listeners) {
      try {
        fn(enabled);
      } catch (_) {
      }
    }
  }

  private static write(context: Context, enabled: boolean, accepted: boolean): Promise<void> {
    ++PluginFeatureStore.revision;
    PluginFeatureStore.publish(enabled);
    const write = PluginFeatureStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, PluginFeatureStore.STORE_NAME);
      await store.put(PluginFeatureStore.KEY, enabled);
      if (accepted) {
        await store.put(PluginFeatureStore.KEY_NOTICE_VERSION, PluginFeatureStore.NOTICE_VERSION);
        await store.put(PluginFeatureStore.KEY_NOTICE_ACCEPTED_AT, Date.now());
      }
      await store.flush();
    });
    PluginFeatureStore.writes = write.catch(() => {});
    return write;
  }
}
