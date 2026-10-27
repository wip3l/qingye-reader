import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';

/** Native sharing and photo creation for already materialized image files. */
export class ImageFileExport {
  static async share(context: common.UIAbilityContext, paths: string[], extension: string = 'png'): Promise<void> {
    if (paths.length === 0 || paths.length > 100) throw new Error('一次最多分享100张图片，请分批分享');
    const utd = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(`.${extension}`,
      uniformTypeDescriptor.UniformDataType.IMAGE);
    const data = new systemShare.SharedData({ utd: utd, uri: fileUri.getUriFromPath(paths[0]) });
    for (let index = 1; index < paths.length; index++) {
      data.addRecord({ utd: utd, uri: fileUri.getUriFromPath(paths[index]) });
    }
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DETAIL,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  static async save(context: common.Context, paths: string[], extension: string = 'png'): Promise<boolean> {
    if (paths.length === 0 || paths.length > 100) throw new Error('一次最多保存100张图片，请分批保存');
    const requests: photoAccessHelper.PhotoCreationConfig[] = paths.map((_path: string, index: number): photoAccessHelper.PhotoCreationConfig => ({
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
}
