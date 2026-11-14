// 按键码与触摸动作枚举的统一出口。这两个枚举所在的模块没有跨平台实现，
// 命名导入会让整页加载失败，安卓构建会用 android/overlay 里的同名文件替换本文件。
export { KeyCode, Action } from '@kit.InputKit';
