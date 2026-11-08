import { preferences } from '@kit.ArkData';

/** 阅读类型位。EPUB 原版排版阅读页算小说。 */
export class ReaderInputKind {
  static readonly NOVEL: number = 1;
  static readonly COMIC: number = 2;
  static readonly PDF: number = 4;
  static readonly ALL: number = 7;
  static readonly LABELS: string[] = ['小说', '漫画', 'PDF'];
  static readonly VALUES: number[] = [1, 2, 4];
}

/**
 * 按阅读类型生效的全局设置：音量键翻页、智控键翻页、翻页震感。每项存一个类型位掩码，0 即关闭。
 * 存在 reader_settings 里但不进主题档案，换主题不变，随数据备份一起走。
 * 设置页“阅读通用”里按类型多选；各阅读页面板里的开关只改自己那一类。
 */
export class ReaderInputScopes {
  static readonly KEY_VOLUME_TURN: string = 'readerVolumeTurnScope';
  static readonly KEY_SMART_KEY_TURN: string = 'readerSmartKeyTurnScope';
  static readonly KEY_PAGE_TURN_HAPTICS: string = 'readerPageTurnHapticsScope';
  private static readonly STORE_NAME: string = 'reader_settings';
  private static readonly KEYS: string[] = [ReaderInputScopes.KEY_VOLUME_TURN, ReaderInputScopes.KEY_SMART_KEY_TURN,
    ReaderInputScopes.KEY_PAGE_TURN_HAPTICS];
  // 旧版的布尔开关：音量键、智控键原先跟主题档案走（当前档案的值同时写在这两个键上），震感原先就是全局布尔。
  // 第一次读取时开着的迁移成三类全开，关着的全关，之后不再读。
  private static readonly LEGACY_KEYS: string[] = ['readerVolumeTurnPage', 'readerSmartKeyTurnPage',
    'readerPageTurnHaptics'];
  private static loading: Promise<void> | null = null;

  /** 读入 AppStorage；重复调用共用同一次读取。 */
  static load(context: Context): Promise<void> {
    if (!ReaderInputScopes.loading) {
      ReaderInputScopes.loading = ReaderInputScopes.loadFromStore(context).catch((error: Error): void => {
        ReaderInputScopes.loading = null;
        console.warn('[ReaderInputScopes] load failed:', error);
      });
    }
    return ReaderInputScopes.loading;
  }

  private static async loadFromStore(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, ReaderInputScopes.STORE_NAME);
    let migrated = false;
    for (let i = 0; i < ReaderInputScopes.KEYS.length; i++) {
      const key = ReaderInputScopes.KEYS[i];
      let scope = 0;
      if (await store.has(key)) {
        scope = ReaderInputScopes.normalize(Number(await store.get(key, 0)));
      } else {
        const legacyKey = ReaderInputScopes.LEGACY_KEYS[i];
        const legacy = (await store.has(legacyKey)) ? (await store.get(legacyKey, false)) === true :
          AppStorage.get<boolean>(legacyKey) === true;
        scope = legacy ? ReaderInputKind.ALL : 0;
        await store.put(key, scope);
        migrated = true;
      }
      AppStorage.setOrCreate(key, scope);
    }
    if (migrated) await store.flush();
  }

  static normalize(scope: number): number {
    return Number.isFinite(scope) ? (Math.round(scope) & ReaderInputKind.ALL) : 0;
  }

  static includes(scope: number, kind: number): boolean {
    return (ReaderInputScopes.normalize(scope) & kind) !== 0;
  }

  static enabled(key: string, kind: number): boolean {
    return ReaderInputScopes.includes(AppStorage.get<number>(key) ?? 0, kind);
  }

  static async set(context: Context, key: string, scope: number): Promise<void> {
    const value = ReaderInputScopes.normalize(scope);
    AppStorage.setOrCreate(key, value);
    const store = await preferences.getPreferences(context, ReaderInputScopes.STORE_NAME);
    await store.put(key, value);
    await store.flush();
  }

  /** 打开或关闭某一类，其他类不变。 */
  static toggle(context: Context, key: string, kind: number, on: boolean): Promise<void> {
    const current = ReaderInputScopes.normalize(AppStorage.get<number>(key) ?? 0);
    return ReaderInputScopes.set(context, key, on ? (current | kind) : (current & ~kind));
  }
}
