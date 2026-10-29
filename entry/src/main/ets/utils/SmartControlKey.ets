import { inputDevice, KeyCode } from '@kit.InputKit';
import deviceInfo from '@ohos.deviceInfo';

/**
 * 智控键上滑/下滑（API 26 起可由前台应用通过 inputConsumer 接管）。
 * 只有部分机型的智控键支持滑动，是否支持以输入设备上报为准，结果写入 AppStorage 供设置页显示开关。
 */
export class SmartControlKey {
  static readonly STORAGE_SUPPORTED: string = 'readerSmartKeyTurnSupported';
  private static detecting: Promise<boolean> | null = null;

  /** 上滑、下滑两个键值；旧系统没有这两个枚举值，返回空数组。 */
  static slideKeys(): Array<KeyCode> {
    if (deviceInfo.sdkApiVersion < 26) return [];
    return [KeyCode.KEYCODE_FINGERPRINT_SLIDE_UP, KeyCode.KEYCODE_FINGERPRINT_SLIDE_DOWN];
  }

  /** 进程内只检测一次；多次调用共用同一个结果。 */
  static detect(): Promise<boolean> {
    if (!SmartControlKey.detecting) {
      SmartControlKey.detecting = SmartControlKey.queryDevices().then((supported: boolean): boolean => {
        AppStorage.setOrCreate(SmartControlKey.STORAGE_SUPPORTED, supported);
        return supported;
      });
    }
    return SmartControlKey.detecting;
  }

  private static async queryDevices(): Promise<boolean> {
    const keys: Array<KeyCode> = SmartControlKey.slideKeys();
    if (keys.length === 0) return false;
    try {
      const ids: Array<number> = await inputDevice.getDeviceList();
      for (const id of ids) {
        const result: Array<boolean> = await inputDevice.supportKeys(id, keys);
        if (result.some((value: boolean): boolean => value)) {
          console.info(`智控键滑动由输入设备 ${id} 上报`);
          return true;
        }
      }
      console.info(`没有输入设备上报智控键滑动，设备数 ${ids.length}`);
    } catch (err) {
      console.warn('检测智控键滑动失败:', err);
    }
    return false;
  }
}
