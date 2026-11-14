// 系统栏占位的统一出口。安卓构建会用 android/overlay 里的同名文件替换本文件。
// 鸿蒙上返回 null，由窗口的避让区接口决定安全区。

export interface SystemInsetsPx {
  top: number;
  bottom: number;
}

export async function systemInsetsPx(): Promise<SystemInsetsPx | null> {
  return null;
}
