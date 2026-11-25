import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import preferences from '@ohos.data.preferences';

/**
 * 实验室 › 墨水屏灰阶：整个主窗口转为灰阶（setWindowGrayScale），页面、弹窗、半模态、Toast、图片与视频一起变灰；
 * 系统状态栏、桌面卡片、通知和系统面板不在本窗口里，不受影响。灰阶由系统合成时处理，不需要逐页离屏滤镜。
 * 只存本机，不参与云同步。读取设置与窗口加载完成谁先谁后都可以，两边就绪后才真正设置。
 */
export class WindowGrayscaleStore {
  static readonly KEY: string = 'labWindowGrayscale';
  private static readonly STORE: string = 'display_lab_settings';
  /** 设备不支持窗口灰阶时接口报的错误码。 */
  static readonly UNSUPPORTED: number = 801;
  private static enabled: boolean = false;
  private static mainWindow: window.Window | null = null;
  /** 当前窗口上已设置的值；新窗口为 false，没开过就不去调接口。 */
  private static applied: boolean = false;
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const revision = WindowGrayscaleStore.revision;
    const store = await preferences.getPreferences(context, WindowGrayscaleStore.STORE);
    const value = await store.get(WindowGrayscaleStore.KEY, false);
    if (revision !== WindowGrayscaleStore.revision) return;
    WindowGrayscaleStore.enabled = value === true;
    AppStorage.setOrCreate(WindowGrayscaleStore.KEY, WindowGrayscaleStore.enabled);
    WindowGrayscaleStore.sync().catch((error: BusinessError) => {
      console.warn('恢复墨水屏灰阶失败:', error?.code, error?.message);
    });
  }

  /** 主窗口加载页面内容之后调用（接口要求 loadContent 完成后才能设置）。 */
  static attach(mainWindow: window.Window): void {
    WindowGrayscaleStore.mainWindow = mainWindow;
    WindowGrayscaleStore.applied = false;
    WindowGrayscaleStore.sync().catch((error: BusinessError) => {
      console.warn('设置墨水屏灰阶失败:', error?.code, error?.message);
    });
  }

  static detach(): void {
    WindowGrayscaleStore.mainWindow = null;
    WindowGrayscaleStore.applied = false;
  }

  /** 回到前台时补设一次，防止窗口重建或系统重置后丢失。 */
  static reapply(): void {
    if (!WindowGrayscaleStore.enabled) return;
    WindowGrayscaleStore.applied = false;
    WindowGrayscaleStore.sync().catch((error: BusinessError) => {
      console.warn('补设墨水屏灰阶失败:', error?.code, error?.message);
    });
  }

  /**
   * 先对窗口生效再落盘；窗口设置失败（如设备不支持，错误码 801）时不保存，并把错误抛给调用方提示。
   */
  static save(context: Context, value: boolean): Promise<void> {
    ++WindowGrayscaleStore.revision;
    const write = WindowGrayscaleStore.writes.then(async (): Promise<void> => {
      const previous = WindowGrayscaleStore.enabled;
      WindowGrayscaleStore.enabled = value;
      // 先跟着开关改，失败再改回去：开关组件不双向绑定，值真的变一次它才会弹回。
      AppStorage.setOrCreate(WindowGrayscaleStore.KEY, value);
      try {
        await WindowGrayscaleStore.sync();
      } catch (error) {
        WindowGrayscaleStore.enabled = previous;
        AppStorage.setOrCreate(WindowGrayscaleStore.KEY, previous);
        throw error as Error;
      }
      const store = await preferences.getPreferences(context, WindowGrayscaleStore.STORE);
      await store.put(WindowGrayscaleStore.KEY, value);
      await store.flush();
    });
    WindowGrayscaleStore.writes = write.catch(() => {});
    return write;
  }

  static isUnsupported(error: Object): boolean {
    return (error as BusinessError)?.code === WindowGrayscaleStore.UNSUPPORTED;
  }

  private static async sync(): Promise<void> {
    const target = WindowGrayscaleStore.mainWindow;
    const value = WindowGrayscaleStore.enabled;
    if (!target || value === WindowGrayscaleStore.applied) return;
    await target.setWindowGrayScale(value ? 1 : 0);
    if (target === WindowGrayscaleStore.mainWindow) WindowGrayscaleStore.applied = value;
  }
}
