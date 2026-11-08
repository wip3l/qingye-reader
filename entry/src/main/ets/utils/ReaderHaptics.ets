import { preferences } from '@kit.ArkData';
import { vibrator } from '@kit.SensorServiceKit';

/**
 * 翻页震感：手动翻页时给一下轻震，跨章时稍重一些。全局设置（阅读通用），小说、漫画、PDF、EPUB 原版
 * 都生效；存在 reader_settings 里但不进主题档案，换主题不变，随数据备份一起走。
 * 触发点：小说 runPageTurnAnimation、漫画翻页视图、快照翻页（PDF/EPUB 原版）、滚动模式与条漫的点击/按键翻屏。
 * 听书自动翻页、自动滚动和手指拖动滚动不震。
 */
export class ReaderHaptics {
  static readonly KEY_ENABLED: string = 'readerPageTurnHaptics';
  private static readonly STORE_NAME: string = 'reader_settings';
  private static loaded: boolean = false;
  private static softEffect: string = '';
  private static hardEffect: string = '';

  static async load(context: Context): Promise<void> {
    if (ReaderHaptics.loaded) return;
    try {
      const store = await preferences.getPreferences(context, ReaderHaptics.STORE_NAME);
      AppStorage.setOrCreate(ReaderHaptics.KEY_ENABLED, (await store.get(ReaderHaptics.KEY_ENABLED, false)) === true);
      ReaderHaptics.loaded = true;
    } catch (error) {
      console.warn('[ReaderHaptics] load failed:', error);
    }
  }

  static async setEnabled(context: Context, enabled: boolean): Promise<void> {
    AppStorage.setOrCreate(ReaderHaptics.KEY_ENABLED, enabled);
    const store = await preferences.getPreferences(context, ReaderHaptics.STORE_NAME);
    await store.put(ReaderHaptics.KEY_ENABLED, enabled);
    await store.flush();
    if (enabled) ReaderHaptics.pageTurned(false);
  }

  static pageTurned(crossChapter: boolean): void {
    if (AppStorage.get<boolean>(ReaderHaptics.KEY_ENABLED) !== true) return;
    const effectId = crossChapter ? ReaderHaptics.hard() : ReaderHaptics.soft();
    if (effectId === '-') return;
    try {
      vibrator.startVibration({ type: 'preset', effectId: effectId, count: 1 }, { usage: 'touch' })
        .catch((error: Error): void => console.warn('[ReaderHaptics] vibrate failed:', error));
    } catch (error) {
      console.warn('[ReaderHaptics] vibrate failed:', error);
    }
  }

  private static soft(): string {
    if (!ReaderHaptics.softEffect) {
      ReaderHaptics.softEffect = ReaderHaptics.firstSupported([vibrator.HapticFeedback.EFFECT_SOFT,
        vibrator.EffectId.EFFECT_CLOCK_TIMER]);
    }
    return ReaderHaptics.softEffect;
  }

  private static hard(): string {
    if (!ReaderHaptics.hardEffect) {
      ReaderHaptics.hardEffect = ReaderHaptics.firstSupported([vibrator.HapticFeedback.EFFECT_HARD,
        vibrator.HapticFeedback.EFFECT_SOFT, vibrator.EffectId.EFFECT_CLOCK_TIMER]);
    }
    return ReaderHaptics.hardEffect;
  }

  /** 设备不支持任何预置效果时返回 '-'，之后不再查询也不震。 */
  private static firstSupported(effects: string[]): string {
    for (const effect of effects) {
      try {
        if (vibrator.isSupportEffectSync(effect)) return effect;
      } catch (_) {
      }
    }
    return '-';
  }
}
