import { Context } from '@kit.AbilityKit';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';

export class StartupCoverImageStore {
  static async pickAndSave(context: Context, schemeId: string, darkMode: boolean): Promise<string> {
    const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const result = await new picker.PhotoViewPicker(context).select(options);
    if (!result || result.photoUris.length === 0) return '';
    const source = result.photoUris[0];
    const dir = `${context.filesDir}/theme_startups`;
    try {
      await fs.mkdir(dir, true);
    } catch (_) {
    }
    const safeId = (schemeId || 'custom').replace(/[^a-zA-Z0-9_-]/g, '_');
    const mode = darkMode ? 'dark' : 'light';
    const path = `${dir}/${safeId}_${mode}_${Date.now()}${StartupCoverImageStore.extension(source)}`;
    const copySource = source.startsWith('/') ? fileUri.getUriFromPath(source) : source;
    await fs.copy(copySource, fileUri.getUriFromPath(path));
    return fileUri.getUriFromPath(path);
  }

  static remove(context: Context, uri: string): void {
    if (!uri) return;
    try {
      const path = uri.startsWith('file://') ? new fileUri.FileUri(uri).path : uri;
      if (path.startsWith(`${context.filesDir}/theme_startups/`) && fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.warn('删除自定义启动封面失败:', e);
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
