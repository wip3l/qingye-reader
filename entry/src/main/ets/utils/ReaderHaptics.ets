import { vibrator } from '@kit.SensorServiceKit';
import { ReaderInputScopes } from './ReaderInputScopes';

/**
 * 翻页震感：手动翻页时给一下轻震，跨章时稍重一些。按阅读类型开关（ReaderInputScopes.KEY_PAGE_TURN_HAPTICS）。
 * 触发点：小说 runPageTurnAnimation、漫画翻页视图、快照翻页（PDF/EPUB 原版）、滚动模式与条漫的点击/按键翻屏。
 * 听书自动翻页、自动滚动和手指拖动滚动不震。
 */
export class ReaderHaptics {
  private static softEffect: string = '';
  private static hardEffect: string = '';

  /** 改某一类的开关；刚打开时震一下让人感受强度。 */
  static async toggle(context: Context, kind: number, on: boolean): Promise<void> {
    await ReaderInputScopes.toggle(context, ReaderInputScopes.KEY_PAGE_TURN_HAPTICS, kind, on);
    if (on) ReaderHaptics.vibrate(false);
  }

  static pageTurned(kind: number, crossChapter: boolean): void {
    if (!ReaderInputScopes.enabled(ReaderInputScopes.KEY_PAGE_TURN_HAPTICS, kind)) return;
    ReaderHaptics.vibrate(crossChapter);
  }

  private static vibrate(crossChapter: boolean): void {
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
