import { Context } from '@kit.AbilityKit';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';

/** 自定义方案卡片的预览图：本机文件，不同步；导出时随包打出去。 */
export class SchemePreviewImageStore {
  static readonly DIR_NAME: string = 'theme_previews';

  static async pickAndSave(context: Context, schemeId: string): Promise<string> {
    const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const result = await new picker.PhotoViewPicker(context).select(options);
    if (!result || result.photoUris.length === 0) return '';
    const source = result.photoUris[0];
    const dir = `${context.filesDir}/${SchemePreviewImageStore.DIR_NAME}`;
    try {
      if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    } catch (_) {
    }
    const safeId = (schemeId || 'custom').replace(/[^a-zA-Z0-9_-]/g, '_');
    const path = `${dir}/${safeId}_${Date.now()}${SchemePreviewImageStore.extension(source)}`;
    const copySource = source.startsWith('/') ? fileUri.getUriFromPath(source) : source;
    await fs.copy(copySource, fileUri.getUriFromPath(path));
    return fileUri.getUriFromPath(path);
  }

  static remove(context: Context, uri: string): void {
    if (!uri) return;
    try {
      const path = uri.startsWith('file://') ? new fileUri.FileUri(uri).path : uri;
      if (path.startsWith(`${context.filesDir}/${SchemePreviewImageStore.DIR_NAME}/`) && fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.warn('删除方案预览图失败:', e);
    }
  }

  private static extension(value: string): string {
    const lower = (value || '').toLowerCase();
    if (lower.includes('.png')) return '.png';
    if (lower.includes('.webp')) return '.webp';
    if (lower.includes('.bmp')) return '.bmp';
    if (lower.includes('.gif')) return '.gif';
    return '.jpg';
  }
}
