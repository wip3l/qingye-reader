// 文件地址与路径互转的统一出口。@ohos.file.fileuri 没有跨平台实现，
// 安卓构建会用 android/overlay 里的同名文件替换本文件。
export { fileUri } from '@kit.CoreFileKit';
