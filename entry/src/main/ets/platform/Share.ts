// 系统分享面板、保存图片到相册的统一出口。安卓构建会用 android/overlay 里的同名文件替换本文件。
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';

export interface ShareFile {
  /** 沙箱路径 */
  path: string;
  /** 统一类型描述符，如 general.image、general.plain-text */
  utd: string;
  title?: string;
}

function record(file: ShareFile): systemShare.SharedRecord {
  const item: systemShare.SharedRecord = { utd: file.utd, uri: fileUri.getUriFromPath(file.path) };
  if (file.title) item.title = file.title;
  return item;
}

/** 拉起系统分享面板。detailPreview 为 true 时用详情预览（图片、文本），否则用默认预览。 */
export async function shareFiles(context: common.UIAbilityContext, files: ShareFile[], detailPreview: boolean):
  Promise<void> {
  if (files.length === 0) return;
  const data = new systemShare.SharedData(record(files[0]));
  for (let index = 1; index < files.length; index++) data.addRecord(record(files[index]));
  const controller = new systemShare.ShareController(data);
  await controller.show(context, {
    previewMode: detailPreview ? systemShare.SharePreviewMode.DETAIL : systemShare.SharePreviewMode.DEFAULT,
    selectionMode: systemShare.SelectionMode.SINGLE
  });
}

/** 经系统的创建对话框把图片存进相册；用户取消时返回 false。 */
export async function saveImages(context: common.Context, paths: string[], extension: string): Promise<boolean> {
  const requests: photoAccessHelper.PhotoCreationConfig[] = paths.map((_path: string, index: number):
    photoAccessHelper.PhotoCreationConfig => ({
    title: `qingye_${Date.now()}_${index + 1}`, fileNameExtension: extension,
    photoType: photoAccessHelper.PhotoType.IMAGE
  }));
  const targets = await photoAccessHelper.getPhotoAccessHelper(context).showAssetsCreationDialog(
    paths.map((path: string): string => fileUri.getUriFromPath(path)), requests);
  if (!targets || targets.length === 0) return false;
  if (targets.length !== paths.length) throw new Error('保存图片数量不一致，请重试');
  for (let index = 0; index < targets.length; index++) {
    const target = fileIo.openSync(targets[index], fileIo.OpenMode.WRITE_ONLY);
    try { await fileIo.copyFile(paths[index], target.fd); } finally { fileIo.closeSync(target); }
  }
  return true;
}
