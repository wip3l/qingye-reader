// 流式下载的读超时。安卓构建会用 android/overlay 里的同名文件替换本文件。
// 鸿蒙上 readTimeout 是“多久没收到数据”，大文件照样能下完；整体时限由各下载自己的计时器管。

/** idleMs：多久没数据算断了；totalMs：这次下载最长允许多久（各下载自己的总时限）。 */
export function streamReadTimeout(idleMs: number, _totalMs: number): number {
  return idleMs;
}
