// 窗口亮度的统一出口。安卓构建会用 android/overlay 里的同名文件替换本文件。
// value 为 0~1，-1 表示跟随系统。
import { window } from '@kit.ArkUI';

export async function setWindowBrightness(mainWindow: window.Window, value: number): Promise<void> {
  await mainWindow.setWindowBrightness(value);
}
