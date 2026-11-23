// platform/SystemInsets.ts 的安卓实现。
// ArkUI-X 的 getWindowAvoidArea 在安卓上返回全 0，经原生桥（SystemBridge.java）读系统栏实际高度；
// 导航条显隐同样经原生桥（ArkUI-X 不支持 navigationIndicator）。
import bridge from '@arkui-x.bridge';
import { window } from '@kit.ArkUI';

/** 与 SystemBridge.NAME 一致。 */
const SYSTEM_BRIDGE_NAME = 'io.legado.read/system';

export interface SystemInsetsPx {
  top: number;
  bottom: number;
}

let systemBridge: bridge.BridgeObject | null = null;

function systemBridgeObject(): bridge.BridgeObject {
  if (!systemBridge) systemBridge = bridge.createBridge(SYSTEM_BRIDGE_NAME);
  return systemBridge;
}

export async function systemInsetsPx(): Promise<SystemInsetsPx | null> {
  const raw = await systemBridgeObject().callMethod('getSystemInsets');
  const result = JSON.parse(String(raw)) as Record<string, Object>;
  if (result['error']) throw new Error(String(result['error']));
  return { top: Number(result['top']) || 0, bottom: Number(result['bottom']) || 0 };
}

/** 三键导航栏是单独的系统窗口，落在上面的点击到不了应用。 */
export const NAVIGATION_BAR_TAKES_TOUCHES: boolean = true;

/** 安卓的导航栏会压在阅读页脚上，正文显示时总是隐藏，从屏幕边缘滑动可临时唤出。 */
export const READER_ALWAYS_HIDES_NAVIGATION: boolean = true;

export async function setNavigationHidden(_mainWindow: window.Window, hidden: boolean): Promise<void> {
  await systemBridgeObject().callMethod('setNavigationBarHidden', hidden ? '1' : '0');
}
