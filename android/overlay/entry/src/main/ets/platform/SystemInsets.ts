// platform/SystemInsets.ts 的安卓实现。
// ArkUI-X 的 getWindowAvoidArea 在安卓上返回全 0，经原生桥（SystemBridge.java）读系统栏实际高度。
import bridge from '@arkui-x.bridge';

/** 与 SystemBridge.NAME 一致。 */
const SYSTEM_BRIDGE_NAME = 'io.legado.read/system';

export interface SystemInsetsPx {
  top: number;
  bottom: number;
}

let systemBridge: bridge.BridgeObject | null = null;

export async function systemInsetsPx(): Promise<SystemInsetsPx | null> {
  if (!systemBridge) systemBridge = bridge.createBridge(SYSTEM_BRIDGE_NAME);
  const raw = await systemBridge.callMethod('getSystemInsets');
  const result = JSON.parse(String(raw)) as Record<string, Object>;
  if (result['error']) throw new Error(String(result['error']));
  return { top: Number(result['top']) || 0, bottom: Number(result['bottom']) || 0 };
}
