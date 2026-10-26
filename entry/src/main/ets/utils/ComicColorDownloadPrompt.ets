import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { ComicColorModels, ComicColorizer } from '@legado/aiengine';
import { ThemeRuntime } from '../theme/ThemeRuntime';

export class ComicColorDownloadPrompt {
  static async ensure(context: common.Context, ui: UIContext, active: () => boolean,
    progress: (status: string) => void,
    onBytes: (received: number, total: number) => void = (): void => {}): Promise<boolean> {
    const bytes = ComicColorModels.missingBytes(context);
    if (bytes === 0) return true;
    if (!active() || !ComicColorizer.memberAllowed()) return false;
    const dark = AppStorage.get<boolean>('appDarkMode') || false;
    const choice = await ui.getPromptAction().showDialog({
      title: '下载漫画着色模型',
      message: `首次使用需下载约 ${(bytes / 1024 / 1024).toFixed(1)} MB 模型，建议连接 Wi-Fi。下载完成后可离线着色，漫画图片不会上传。`,
      buttons: [
        { text: '暂不开启', color: ThemeRuntime.subTextColor(dark) },
        { text: '下载并开启', color: ThemeRuntime.primaryTextColor(dark) }
      ]
    });
    if (choice.index !== 1 || !active() || !ComicColorizer.memberAllowed()) return false;
    await ComicColorModels.download(context, active, progress, onBytes);
    return active() && ComicColorizer.memberAllowed();
  }
}
