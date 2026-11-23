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

/**
 * 状态栏文字颜色。安卓的状态栏图标只有深浅两种，ArkUI-X 只认两个约定值来切换：#66000000 换深色图标、
 * #E5FFFFFF 换浅色图标，别的颜色一概不理（深色主题下图标就一直是深的）。
 */
export function systemBarContentColor(lightIcons: boolean, _color: string): string {
  return lightIcons ? '#E5FFFFFF' : '#66000000';
}

/** 三键导航栏是单独的系统窗口，落在上面的点击到不了应用。 */
export const NAVIGATION_BAR_TAKES_TOUCHES: boolean = true;

/** 安卓的导航栏会压在阅读页脚上，正文显示时总是隐藏，从屏幕边缘滑动可临时唤出。 */
export const READER_ALWAYS_HIDES_NAVIGATION: boolean = true;

export async function setNavigationHidden(_mainWindow: window.Window, hidden: boolean): Promise<void> {
  await systemBridgeObject().callMethod('setNavigationBarHidden', hidden ? '1' : '0');
}
