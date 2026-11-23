// platform/BiometricAuth.ets 的安卓实现：经原生桥（BiometricBridge.java）用系统 BiometricPrompt。
// 对外接口与鸿蒙实现相同（isAvailable / authenticate / BiometricAuthOutcome）。
import bridge from '@arkui-x.bridge';

/** 与 BiometricBridge.NAME 一致。 */
const BIOMETRIC_BRIDGE_NAME = 'io.legado.read/biometric';

export enum BiometricAuthOutcome {
  SUCCESS,
  /** 用户点了认证框上的导航按钮（如“使用密码”）。 */
  USE_PASSWORD,
  /** 用户关掉了认证框。 */
  CANCELED,
  /** 没认出来、次数过多被锁、系统拒绝等，应退回应用自己的密码。 */
  FAILED
}

let biometricBridge: bridge.BridgeObject | null = null;

function object(): bridge.BridgeObject {
  if (!biometricBridge) biometricBridge = bridge.createBridge(BIOMETRIC_BRIDGE_NAME);
  return biometricBridge;
}

export class BiometricAuth {
  static isAvailable(): boolean {
    try {
      return String(object().callMethodSync('available')) === '1';
    } catch (_) {
      return false;
    }
  }

  static async authenticate(title: string, navigationButtonText?: string): Promise<BiometricAuthOutcome> {
    if (!BiometricAuth.isAvailable()) return BiometricAuthOutcome.FAILED;
    try {
      const result = String(await object().callMethod('authenticate', title, navigationButtonText || '取消',
        navigationButtonText ? '1' : '0'));
      if (result === 'success') return BiometricAuthOutcome.SUCCESS;
      if (result === 'usePassword') return BiometricAuthOutcome.USE_PASSWORD;
      if (result === 'canceled') return BiometricAuthOutcome.CANCELED;
      return BiometricAuthOutcome.FAILED;
    } catch (error) {
      console.warn('系统生物认证失败:', (error as Error).message);
      return BiometricAuthOutcome.FAILED;
    }
  }
}
