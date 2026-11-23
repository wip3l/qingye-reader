// 系统栏占位与导航条显隐的统一出口。安卓构建会用 android/overlay 里的同名文件替换本文件。
// 鸿蒙上占位返回 null，由窗口的避让区接口决定安全区。
import { window } from '@kit.ArkUI';

export interface SystemInsetsPx {
  top: number;
  bottom: number;
}

export async function systemInsetsPx(): Promise<SystemInsetsPx | null> {
  return null;
}

/**
 * 阅读正文时是否总是隐藏底部导航条（不看“隐藏导航条”开关）。
 * 鸿蒙的导航条很细，页脚贴着它也看得清；安卓的三键导航栏、手势条更高，会压在页脚上。
 */
export const READER_ALWAYS_HIDES_NAVIGATION: boolean = false;

/**
 * 底部导航条会不会接走落在它上面的点击。鸿蒙的导航条只认上滑，点击照样落到应用上；
 * 安卓的三键导航栏是单独的系统窗口，贴底的按钮要整个抬到它上面才点得到。
 */
export const NAVIGATION_BAR_TAKES_TOUCHES: boolean = false;

/** 状态栏文字颜色。鸿蒙按给的颜色画。 */
export function systemBarContentColor(_lightIcons: boolean, color: string): string {
  return color;
}

/** 隐藏或恢复底部导航条。 */
export function setNavigationHidden(mainWindow: window.Window, hidden: boolean): Promise<void> {
  return mainWindow.setSpecificSystemBarEnabled('navigationIndicator', !hidden);
}
