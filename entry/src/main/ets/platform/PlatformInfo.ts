// 当前构建面向的平台。鸿蒙构建恒为 false；安卓构建会用 android/overlay 里的同名文件替换本文件。
// 只用来关掉安卓上不存在的系统能力，不要用它分叉业务逻辑。
export class PlatformInfo {
  static readonly ANDROID: boolean = false;
}
