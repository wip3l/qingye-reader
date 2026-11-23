import lazy { motion } from '@kit.MultimodalAwarenessKit';
import deviceInfo from '@ohos.deviceInfo';

/**
 * 订阅左右手握持（智感握姿）。onSide 收到 -1 左手、1 右手；双手、未握持和未知状态不回调，
 * 让控件保留上次位置，避免放下手机时来回跳。只管自己的回调，不影响其他页面和系统控件的订阅。
 */
export class HoldingHandTracker {
  private subscribed: boolean = false;
  private onSide: (side: number) => void;
  private callback: (status: motion.HoldingHandStatus) => void = (status: motion.HoldingHandStatus): void => {
    if (!this.subscribed) return;
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) this.onSide(-1);
    else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) this.onSide(1);
  };

  constructor(onSide: (side: number) => void) {
    this.onSide = onSide;
  }

  start(): void {
    if (this.subscribed || deviceInfo.sdkApiVersion < 20 ||
      !canIUse('SystemCapability.MultimodalAwareness.Motion')) return;
    try {
      this.subscribed = true;
      motion.on('holdingHandChanged', this.callback);
    } catch (error) {
      this.subscribed = false;
      console.warn('握姿感知不可用，控件保持默认位置:', error);
    }
  }

  stop(): void {
    if (!this.subscribed) return;
    this.subscribed = false;
    try {
      motion.off('holdingHandChanged', this.callback);
    } catch (error) {
      console.warn('释放握姿监听失败:', error);
    }
  }
}
