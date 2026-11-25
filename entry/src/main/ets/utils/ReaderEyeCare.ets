import { preferences } from '@kit.ArkData';

/**
 * 阅读页护眼：在阅读页最上面盖一层暖色正片叠底滤层，白色变暖、蓝光减少，黑色仍是黑色。
 * 系统没有给应用开放系统护眼模式的开关，所以由应用自己画。
 * 开关与强度只存本机（和阅读亮度同一个 Preferences 文件），不写进主题、不云同步；
 * 读出后放进 AppStorage，亮度条与各阅读页的滤层直接订阅。
 */
export class ReaderEyeCare {
  static readonly KEY_ON: string = 'readerEyeCareOn';
  static readonly KEY_LEVEL: string = 'readerEyeCareLevel';
  static readonly DEFAULT_LEVEL: number = 40;
  private static readonly PREFS: string = 'reader_brightness';
  private static loaded: boolean = false;
  private static loading: Promise<void> | null = null;
  private static context: Context | null = null;
  private static hinted: boolean = true;
  private static saveQueue: Promise<void> = Promise.resolve();

  static normalizeLevel(value: number): number {
    if (!Number.isFinite(value)) return ReaderEyeCare.DEFAULT_LEVEL;
    return Math.min(100, Math.max(1, Math.round(value)));
  }

  /** 强度 1~100 对应的滤层颜色（带透明度的琥珀色）；夜间同强度略收，免得整屏发棕。 */
  static filterColor(level: number, dark: boolean): string {
    const base = 0.06 + 0.40 * (ReaderEyeCare.normalizeLevel(level) - 1) / 99;
    const alpha = Math.round(Math.min(1, dark ? base * 0.8 : base) * 255);
    return `#${alpha.toString(16).padStart(2, '0').toUpperCase()}FFA852`;
  }

  /** 进入阅读页时读一次；之后整个应用进程共用 AppStorage 里的值。 */
  static load(context: Context): Promise<void> {
    ReaderEyeCare.context = context;
    if (ReaderEyeCare.loaded) return Promise.resolve();
    if (ReaderEyeCare.loading) return ReaderEyeCare.loading;
    ReaderEyeCare.loading = (async (): Promise<void> => {
      try {
        const store = await preferences.getPreferences(context, ReaderEyeCare.PREFS);
        const on = (await store.get('eyeCare', false)) === true;
        const level = ReaderEyeCare.normalizeLevel(Number(await store.get('eyeCareLevel', ReaderEyeCare.DEFAULT_LEVEL)));
        ReaderEyeCare.hinted = (await store.get('eyeCareHinted', false)) === true;
        AppStorage.setOrCreate<boolean>(ReaderEyeCare.KEY_ON, on);
        AppStorage.setOrCreate<number>(ReaderEyeCare.KEY_LEVEL, level);
        ReaderEyeCare.loaded = true;
      } catch (error) {
        console.warn('读取护眼设置失败:', error);
      } finally {
        ReaderEyeCare.loading = null;
      }
    })();
    return ReaderEyeCare.loading;
  }

  static isOn(): boolean {
    return AppStorage.get<boolean>(ReaderEyeCare.KEY_ON) === true;
  }

  static level(): number {
    return ReaderEyeCare.normalizeLevel(AppStorage.get<number>(ReaderEyeCare.KEY_LEVEL) ?? ReaderEyeCare.DEFAULT_LEVEL);
  }

  /** 开关护眼；返回 true 表示这是第一次打开，调用方提示一次“长按调强度”。 */
  static setOn(on: boolean): boolean {
    AppStorage.setOrCreate<boolean>(ReaderEyeCare.KEY_ON, on);
    const firstTime = on && !ReaderEyeCare.hinted;
    if (firstTime) ReaderEyeCare.hinted = true;
    ReaderEyeCare.save(firstTime);
    return firstTime;
  }

  /** 拖动中只更新滤层，松手（persist）时落盘。 */
  static setLevel(level: number, persist: boolean): void {
    AppStorage.setOrCreate<number>(ReaderEyeCare.KEY_LEVEL, ReaderEyeCare.normalizeLevel(level));
    if (persist) ReaderEyeCare.save(false);
  }

  private static save(markHinted: boolean): void {
    const context = ReaderEyeCare.context;
    if (!context || !ReaderEyeCare.loaded) return;
    const on = ReaderEyeCare.isOn();
    const level = ReaderEyeCare.level();
    ReaderEyeCare.saveQueue = ReaderEyeCare.saveQueue.catch(() => {}).then(async () => {
      const store = await preferences.getPreferences(context, ReaderEyeCare.PREFS);
      await store.put('eyeCare', on);
      await store.put('eyeCareLevel', level);
      if (markHinted) await store.put('eyeCareHinted', true);
      await store.flush();
    }).catch((error: Error) => console.warn('保存护眼设置失败:', error));
  }
}
