import { Context } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import graphicsText from '@ohos.graphics.text';
import { ReaderFontHelper, ReaderFontItem } from './ReaderFontHelper';
import { ReaderSettings, ReaderSettingsStore } from './ReaderSettingsStore';
import { ReaderSystemFontHelper } from './ReaderSystemFontHelper';
import { ThemeRuntime } from '../theme/ThemeRuntime';

export class ReaderFontBootstrap {
  /**
   * 全局字体模式 readerFontMode：custom 为自定义字体；device 为跟随系统，不看主题包，也是默认值；
   * system 是历史名，实际表示跟随主题（主题包没写字体时也就是系统字体）。
   */
  static readonly FONT_MODE_DEVICE: string = ReaderSettingsStore.FONT_MODE_DEVICE;
  static readonly FONT_MODE_THEME: string = ReaderSettingsStore.FONT_MODE_THEME;

  // 本进程是否调过 setFont。ArkUI 只在应用没设过自定义字体时，才会在系统换主题字体后重新加载它；
  // setFont 没法撤销，所以能不设就不设。
  private static applicationFontSet: boolean = false;

  /** 没选自定义字体时的默认字体：只有明确选了跟随主题才用主题字体，其余都用系统字体。 */
  static defaultFontFamily(fontMode: string, systemFontFamily: string): string {
    if (fontMode === ReaderFontBootstrap.FONT_MODE_THEME) {
      return ThemeRuntime.fontFamily() || systemFontFamily;
    }
    return systemFontFamily;
  }

  // The user's global font wins over the theme font; the theme font only applies while "跟随主题" is selected.
  static applicationFontFamily(): string {
    const activeFamily = AppStorage.get<string>('readerActiveFontFamily') || '';
    if (activeFamily && AppStorage.get<boolean>('readerFontRegistered')) {
      return activeFamily;
    }
    if (AppStorage.get<string>('readerFontMode') === ReaderFontBootstrap.FONT_MODE_THEME) {
      return ThemeRuntime.fontFamily() || AppStorage.get<string>('readerSystemFontFamily') || '';
    }
    return ReaderSystemFontHelper.FALLBACK_SYSTEM_FONT_FAMILY;
  }

  /** 所有设置应用全局字体的地方都走这里，按 applicationFontFamily() 的同一套优先级取字体。 */
  static applyApplicationFont(context: Context, source: string): void {
    const family = ReaderFontBootstrap.applicationFontFamily();
    if (family === ReaderSystemFontHelper.FALLBACK_SYSTEM_FONT_FAMILY && !ReaderFontBootstrap.applicationFontSet) {
      // 用系统字体且本进程还没设过字体时保持不设，交给 ArkUI 跟随系统主题字体。
      AppStorage.setOrCreate<string>('applicationFontFamily', family);
      return;
    }
    ReaderFontBootstrap.setApplicationFont(context, family, source);
  }

  private static setApplicationFont(context: Context, family: string, source: string): void {
    // Select 的收起文本需要显式 font.family；发布可观察的字体供所有下拉控件同步更新。
    AppStorage.setOrCreate<string>('applicationFontFamily', family);
    try {
      context.getApplicationContext().setFont(family);
      ReaderFontBootstrap.applicationFontSet = true;
    } catch (err) {
      hilog.warn(0x0000, 'testTag', 'Apply application font failed source=%{public}s family=%{public}s err=%{public}s',
        source, family, JSON.stringify(err));
    }
  }

  /**
   * 应用在后台时系统换了全局字体：清掉排版缓存、重新探测系统字体并记下，
   * 没选自定义字体时重设应用字体，再发 systemFontRevision 让阅读器重新分页。
   * 调用方要等 ArkUI 处理完这次配置变化（它会重新加载主题字体）再调这里。
   */
  static onSystemFontChanged(context: Context, uiContext: UIContext | null, source: string): void {
    try {
      graphicsText.FontCollection.getGlobalInstance().clearCaches();
    } catch (err) {
      hilog.warn(0x0000, 'testTag', 'Clear font caches failed source=%{public}s err=%{public}s',
        source, JSON.stringify(err));
    }
    const systemFontFamily = ReaderSystemFontHelper.applyToStorage(uiContext);
    const customFontActive = !!AppStorage.get<string>('readerActiveFontFamily') &&
      !!AppStorage.get<boolean>('readerFontRegistered');
    if (!customFontActive) {
      ReaderFontBootstrap.applyApplicationFont(context, source);
    }
    AppStorage.setOrCreate<number>('systemFontRevision', (AppStorage.get<number>('systemFontRevision') || 0) + 1);
    hilog.info(0x0000, 'testTag',
      'System font changed source=%{public}s family=%{public}s custom=%{public}s appFontSet=%{public}s',
      source, systemFontFamily, String(customFontActive), String(ReaderFontBootstrap.applicationFontSet));
    ReaderSettingsStore.load(context).then((settings: ReaderSettings) => {
      if (settings.systemFontFamily === systemFontFamily) {
        return;
      }
      return ReaderSettingsStore.saveFontSettings(
        context,
        settings.fontFamily,
        settings.fontFilePath,
        settings.fontSourceName,
        settings.fontMode,
        systemFontFamily,
        settings.customFontsRaw
      );
    }).catch((err: Error) => {
      hilog.warn(0x0000, 'testTag', 'Save changed system font failed source=%{public}s err=%{public}s',
        source, JSON.stringify(err));
    });
  }

  static async registerFromSettings(context: Context, uiContext: UIContext | null, source: string): Promise<boolean> {
    try {
      const settings = await ReaderSettingsStore.load(context);
      return ReaderFontBootstrap.registerSettings(context, uiContext, settings, source);
    } catch (err) {
      hilog.warn(0x0000, 'testTag', 'Reader font bootstrap load failed source=%{public}s err=%{public}s',
        source, JSON.stringify(err));
      return false;
    }
  }

  private static registerSettings(
    context: Context,
    uiContext: UIContext | null,
    settings: ReaderSettings,
    source: string
  ): boolean {
    if (!settings.fontFilePath) {
      const systemFontFamily = ReaderSystemFontHelper.applyToStorage(uiContext);
      AppStorage.setOrCreate('readerActiveFontFamily', '');
      AppStorage.setOrCreate('readerFontRegistered', false);
      ReaderFontBootstrap.applyApplicationFont(context, source);
      if (settings.systemFontFamily !== systemFontFamily) {
        ReaderSettingsStore.saveFontSettings(
          context,
          '',
          '',
          settings.fontSourceName,
          settings.fontMode,
          systemFontFamily,
          settings.customFontsRaw
        ).catch((err: Error) => {
          hilog.warn(0x0000, 'testTag',
            'Reader font bootstrap save system font failed source=%{public}s err=%{public}s',
            source, JSON.stringify(err));
        });
      }
      return false;
    }

    const fontItem = new ReaderFontItem();
    fontItem.familyName = settings.fontFamily || ReaderFontHelper.normalizeFontFamily(settings.fontFilePath);
    fontItem.filePath = settings.fontFilePath;
    fontItem.sourceName = ReaderFontHelper.resolveDisplayName(settings.fontSourceName, settings.fontFilePath);

    const result = ReaderFontHelper.registerFont(uiContext, fontItem);
    if (!result.registered) {
      AppStorage.setOrCreate('readerActiveFontFamily', '');
      AppStorage.setOrCreate('readerFontRegistered', false);
      ReaderFontBootstrap.applyApplicationFont(context, source);
      hilog.warn(0x0000, 'testTag',
        'Reader font bootstrap failed source=%{public}s path=%{public}s family=%{public}s ark=%{public}s legacy=%{public}s graphics=%{public}s errors=%{public}s',
        source, result.filePath || settings.fontFilePath, result.familyName, String(result.arkUiRegistered),
        String(result.legacyRegistered), String(result.graphicsTextRegistered), result.errorSummary);
      return false;
    }

    AppStorage.setOrCreate('readerActiveFontFamily', result.familyName);
    AppStorage.setOrCreate('readerFontRegistered', true);
    if (result.filePath !== settings.fontFilePath) {
      AppStorage.setOrCreate('readerFontFilePath', result.filePath);
      ReaderSettingsStore.saveFontSettings(
        context,
        ReaderFontHelper.normalizeFontFamily(result.filePath),
        result.filePath,
        settings.fontSourceName,
        settings.fontMode,
        settings.systemFontFamily,
        settings.customFontsRaw
      ).catch((err: Error) => {
        hilog.warn(0x0000, 'testTag',
          'Reader font bootstrap save migrated path failed source=%{public}s err=%{public}s',
          source, JSON.stringify(err));
      });
    }

    ReaderFontBootstrap.setApplicationFont(context, result.familyName, source);

    hilog.info(0x0000, 'testTag',
      'Reader font bootstrap success source=%{public}s family=%{public}s path=%{public}s arkSrc=%{public}s graphicsSrc=%{public}s',
      source, result.familyName, result.filePath, result.arkUiSource, result.graphicsTextSource);
    return true;
  }
}
