// platform/WindowBrightness.ts 的安卓实现。
// ArkUI-X 的 setWindowBrightness 不接受 -1（跟随系统），经原生桥（SystemBridge.java）直接改窗口属性。
import { window } from '@kit.ArkUI';
import bridge from '@arkui-x.bridge';

/** 与 SystemBridge.NAME 一致。 */
const SYSTEM_BRIDGE_NAME = 'io.legado.read/system';

let systemBridge: bridge.BridgeObject | null = null;

export async function setWindowBrightness(_mainWindow: window.Window, value: number): Promise<void> {
  if (!systemBridge) systemBridge = bridge.createBridge(SYSTEM_BRIDGE_NAME);
  const raw = await systemBridge.callMethod('setWindowBrightness', String(value));
  const result = JSON.parse(String(raw)) as Record<string, string>;
  if (result.error) throw new Error(result.error);
}
