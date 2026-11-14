// platform/KeyConsumer.ts 的安卓实现：经原生桥（KeyBridge.java）接管按键，替代鸿蒙的 inputConsumer。
// 只支持按下事件（阅读页只订阅 Action.DOWN、不重复）；键码沿用鸿蒙的（platform/InputKeys）。
import bridge from '@arkui-x.bridge';

/** 与 KeyBridge.NAME 一致。 */
const KEY_BRIDGE_NAME = 'io.legado.read/key';

export interface KeyEvent {
  action: number;
  key: { code: number, pressedTime: number, deviceId: number };
  unicodeChar: number;
  keys: Array<{ code: number, pressedTime: number, deviceId: number }>;
}

interface KeyPressedConfig {
  key: number;
  action: number;
  isRepeat: boolean;
}

type KeyCallback = (event: KeyEvent) => void;

let keyBridge: bridge.BridgeObject | null = null;
const listeners: Map<number, KeyCallback[]> = new Map<number, KeyCallback[]>();

function object(): bridge.BridgeObject {
  if (!keyBridge) {
    keyBridge = bridge.createBridge(KEY_BRIDGE_NAME);
    keyBridge.registerMethod({
      name: 'onKeyPressed',
      method: (code: Object): string => {
        const keyCode = Number(code);
        const now = Date.now();
        const key = { code: keyCode, pressedTime: now, deviceId: 0 };
        for (const callback of (listeners.get(keyCode) || []).slice()) {
          callback({ action: 1, key: key, unicodeChar: 0, keys: [key] });
        }
        return '';
      }
    }).catch((error: Error) => console.warn('[Keys] 注册按键回调失败:', error.message));
  }
  return keyBridge;
}

export namespace inputConsumer {
  export function on(_type: string, config: KeyPressedConfig, callback: KeyCallback): void {
    const list = listeners.get(config.key) || [];
    list.push(callback);
    listeners.set(config.key, list);
    object().callMethod('intercept', String(config.key)).catch(() => {});
  }

  export function off(_type: string, callback?: KeyCallback): void {
    for (const [code, list] of Array.from(listeners.entries())) {
      const kept = callback ? list.filter((item: KeyCallback): boolean => item !== callback) : [];
      if (kept.length > 0) {
        listeners.set(code, kept);
      } else if (list.length > 0) {
        listeners.delete(code);
        object().callMethod('release', String(code)).catch(() => {});
      }
    }
  }
}
