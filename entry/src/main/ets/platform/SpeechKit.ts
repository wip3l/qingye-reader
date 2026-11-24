// 系统朗读引擎的统一出口。安卓构建会用 android/overlay 里的同名文件替换本文件。
export { textToSpeech } from '@kit.CoreSpeechKit';

/** 安卓实现用它放合成的临时音频；鸿蒙上不需要。 */
export function setSpeechCacheDir(_dir: string): void {
}
