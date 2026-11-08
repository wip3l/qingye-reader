import { AnimatorResult } from '@kit.ArkUI';

/**
 * 翻页、翻屏动画的期望帧率。手指在屏幕上时系统有触控提频，动画自然跑满高刷；音量键、智控键、
 * 键盘翻页没有触控，未声明期望帧率的动画会按系统默认策略降到 60Hz，看起来比点击翻页肉。
 * 所以由按键也能触发的翻页动画（属性动画 animateTo 与 Animator）都显式请求 120Hz，60Hz 屏上自动取 60。
 */
export const READER_TURN_FRAME_RATE: ExpectedFrameRateRange = { min: 60, max: 120, expected: 120 };

/** 给 Animator 设期望帧率；个别系统版本不支持时忽略，动画照常播放。 */
export function applyReaderTurnFrameRate(animator: AnimatorResult): void {
  try {
    animator.setExpectedFrameRateRange(READER_TURN_FRAME_RATE);
  } catch (error) {
    console.warn('[ReaderTurnFrameRate] setExpectedFrameRateRange failed:', error);
  }
}
