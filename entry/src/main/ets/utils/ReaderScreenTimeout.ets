import { window } from '@kit.ArkUI';
import { ReaderSettingsStore } from './ReaderSettingsStore';

/**
 * 阅读设置里的“亮屏时间”：页面可见时让屏幕保持常亮，设了分钟数就在无操作这么久后交还系统；
 * 跟随系统时不干预。与普通阅读页同一个设置。
 */
export class ReaderScreenTimeout {
  private minutes: number = ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM;
  private timer: number = -1;
  private serial: number = 0;
  private readonly tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }

  setMinutes(minutes: number): void {
    this.minutes = ReaderSettingsStore.normalizeScreenTimeoutMinutes(minutes);
  }

  apply(context: Context | undefined, visible: boolean): void {
    this.clearTimer();
    const serial = ++this.serial;
    if (!visible || this.minutes === ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM) {
      this.keepOn(context, false, serial);
      return;
    }
    this.keepOn(context, true, serial);
    if (this.minutes > 0) {
      this.timer = setTimeout((): void => {
        this.timer = -1;
        if (serial === this.serial) this.keepOn(context, false, serial);
      }, this.minutes * 60 * 1000);
    }
  }

  /** 有操作时重新计时。 */
  refresh(context: Context | undefined, visible: boolean): void {
    if (visible && this.minutes > 0) this.apply(context, visible);
  }

  release(context: Context | undefined): void {
    this.clearTimer();
    this.keepOn(context, false, ++this.serial);
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private keepOn(context: Context | undefined, enabled: boolean, serial: number): void {
    if (!context) return;
    window.getLastWindow(context).then((mainWindow: window.Window): void => {
      if (serial !== this.serial) return;
      mainWindow.setWindowKeepScreenOn(enabled).catch((error: Error): void => {
        console.warn(`[${this.tag}] keep screen on failed:`, error);
      });
    }).catch((error: Error): void => { console.warn(`[${this.tag}] window failed:`, error); });
  }
}
