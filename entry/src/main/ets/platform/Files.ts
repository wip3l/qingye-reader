// 选文件、存文件、复制文件的统一出口。安卓构建会用 android/overlay 里的同名文件替换本文件。
//
// 鸿蒙上选择器返回的地址可以直接交给 fs；安卓上选择器返回 content:// 地址，fs 打不开，
// 安卓实现会先经原生桥复制进缓存目录，再返回沙箱路径。所以共用代码拿到的结果要按“地址或沙箱路径”对待：
// 以 / 开头的是沙箱路径，其余是地址。两种都可以直接交给 copyFile。
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import util from '@ohos.util';
import { Context } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';

function toUri(uriOrPath: string): string {
  return uriOrPath.startsWith('/') ? fileUri.getUriFromPath(uriOrPath) : uriOrPath;
}

/** 选文档。fileSuffixFilters 照鸿蒙写法给（如 `'电子书|.txt,.epub'`），安卓实现会自己换算。 */
export async function selectDocuments(context: Context, options: picker.DocumentSelectOptions): Promise<string[]> {
  const result = await new picker.DocumentViewPicker(context).select(options);
  return result || [];
}

/** 选图片，最多 maxCount 张。 */
export async function selectImages(context: Context, maxCount: number = 1): Promise<string[]> {
  const options = new picker.PhotoSelectOptions();
  options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = maxCount;
  const result = await new picker.PhotoViewPicker(context).select(options);
  return result && result.photoUris ? result.photoUris : [];
}

/** 弹保存面板，返回用户选定的保存地址。之后用 copyFile 把文件写过去。 */
export async function saveDocuments(context: Context, options: picker.DocumentSaveOptions): Promise<string[]> {
  const result = await new picker.DocumentViewPicker(context).save(options);
  return result || [];
}

/** 把文本整个写进 target（保存面板给的地址或沙箱路径），覆盖原有内容。 */
export async function writeTextFile(context: Context, target: string, text: string): Promise<void> {
  const bytes = new util.TextEncoder().encodeInto(text);
  const file = await fs.open(target, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try {
    await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
  } finally {
    await fs.close(file);
  }
}

/** 复制文件，两端都可以是地址或沙箱路径。行为同 fs.copy。 */
export async function copyFile(source: string, target: string): Promise<void> {
  await fs.copy(toUri(source), toUri(target));
}
