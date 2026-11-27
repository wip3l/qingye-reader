import { preferences } from '@kit.ArkData';
import { ReaderReadingRulerSteps } from '../core/reader/ReaderReadingRulerSteps';

/**
 * 阅读尺设置：开关、样式、聚焦行数、浓度。和护眼一样只存本机、所有书共用，不写进主题、不云同步；
 * 读出后放进 AppStorage，阅读页与设置面板直接订阅。
 */
export class ReaderReadingRuler {
  static readonly KEY_ON: string = 'readerRulerOn';
  static readonly KEY_STYLE: string = 'readerRulerStyle';
  static readonly KEY_LINES: string = 'readerRulerLines';
  static readonly KEY_STRENGTH: string = 'readerRulerStrength';
  private static readonly PREFS: string = 'reader_ruler';
  private static loaded: boolean = false;
  private static loading: Promise<void> | null = null;
  private static context: Context | null = null;
  private static saveQueue: Promise<void> = Promise.resolve();

  static load(context: Context): Promise<void> {
    ReaderReadingRuler.context = context;
    if (ReaderReadingRuler.loaded) return Promise.resolve();
    if (ReaderReadingRuler.loading) return ReaderReadingRuler.loading;
    ReaderReadingRuler.loading = (async (): Promise<void> => {
      try {
        const store = await preferences.getPreferences(context, ReaderReadingRuler.PREFS);
        AppStorage.setOrCreate<boolean>(ReaderReadingRuler.KEY_ON, (await store.get('on', false)) === true);
        AppStorage.setOrCreate<string>(ReaderReadingRuler.KEY_STYLE,
          ReaderReadingRulerSteps.normalizeStyle(String(await store.get('style', ReaderReadingRulerSteps.STYLE_MASK))));
        AppStorage.setOrCreate<number>(ReaderReadingRuler.KEY_LINES,
          ReaderReadingRulerSteps.normalizeLines(Number(await store.get('lines', ReaderReadingRulerSteps.DEFAULT_LINES))));
        AppStorage.setOrCreate<number>(ReaderReadingRuler.KEY_STRENGTH, ReaderReadingRulerSteps.normalizeStrength(
          Number(await store.get('strength', ReaderReadingRulerSteps.DEFAULT_STRENGTH))));
        ReaderReadingRuler.loaded = true;
      } catch (error) {
        console.warn('读取阅读尺设置失败:', error);
      } finally {
        ReaderReadingRuler.loading = null;
      }
    })();
    return ReaderReadingRuler.loading;
  }

  static isOn(): boolean {
    return AppStorage.get<boolean>(ReaderReadingRuler.KEY_ON) === true;
  }

  static style(): string {
    return ReaderReadingRulerSteps.normalizeStyle(AppStorage.get<string>(ReaderReadingRuler.KEY_STYLE) ?? '');
  }

  static lines(): number {
    return ReaderReadingRulerSteps.normalizeLines(
      AppStorage.get<number>(ReaderReadingRuler.KEY_LINES) ?? ReaderReadingRulerSteps.DEFAULT_LINES);
  }

  static strength(): number {
    return ReaderReadingRulerSteps.normalizeStrength(
      AppStorage.get<number>(ReaderReadingRuler.KEY_STRENGTH) ?? ReaderReadingRulerSteps.DEFAULT_STRENGTH);
  }

  static setOn(on: boolean): void {
    AppStorage.setOrCreate<boolean>(ReaderReadingRuler.KEY_ON, on);
    ReaderReadingRuler.save();
  }

  static setStyle(style: string): void {
    AppStorage.setOrCreate<string>(ReaderReadingRuler.KEY_STYLE, ReaderReadingRulerSteps.normalizeStyle(style));
    ReaderReadingRuler.save();
  }

  static setLines(lines: number): void {
    AppStorage.setOrCreate<number>(ReaderReadingRuler.KEY_LINES, ReaderReadingRulerSteps.normalizeLines(lines));
    ReaderReadingRuler.save();
  }

  static setStrength(strength: number): void {
    AppStorage.setOrCreate<number>(ReaderReadingRuler.KEY_STRENGTH,
      ReaderReadingRulerSteps.normalizeStrength(strength));
    ReaderReadingRuler.save();
  }

  private static save(): void {
    const context = ReaderReadingRuler.context;
    if (!context || !ReaderReadingRuler.loaded) return;
    const on = ReaderReadingRuler.isOn();
    const style = ReaderReadingRuler.style();
    const lines = ReaderReadingRuler.lines();
    const strength = ReaderReadingRuler.strength();
    ReaderReadingRuler.saveQueue = ReaderReadingRuler.saveQueue.catch(() => {}).then(async () => {
      const store = await preferences.getPreferences(context, ReaderReadingRuler.PREFS);
      await store.put('on', on);
      await store.put('style', style);
      await store.put('lines', lines);
      await store.put('strength', strength);
      await store.flush();
    }).catch((error: Error) => console.warn('保存阅读尺设置失败:', error));
  }
}
