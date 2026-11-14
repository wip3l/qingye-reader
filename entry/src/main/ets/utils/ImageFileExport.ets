import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { fileUri } from '../platform/FileUri';
import { saveImages, shareFiles, ShareFile } from '../platform/Share';
import { uniformTypeDescriptor } from '@kit.ArkData';

/** Native sharing and photo creation for already materialized image files. */
export class ImageFileExport {
  static async share(context: common.UIAbilityContext, paths: string[], extension: string = 'png'): Promise<void> {
    if (paths.length === 0 || paths.length > 100) throw new Error('一次最多分享100张图片，请分批分享');
    const utd = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(`.${extension}`,
      uniformTypeDescriptor.UniformDataType.IMAGE);
    await shareFiles(context, paths.map((path: string): ShareFile => ({ path: path, utd: utd })), true);
  }

  static async save(context: common.Context, paths: string[], extension: string = 'png'): Promise<boolean> {
    if (paths.length === 0 || paths.length > 100) throw new Error('一次最多保存100张图片，请分批保存');
    return await saveImages(context, paths, extension);
  }
}
