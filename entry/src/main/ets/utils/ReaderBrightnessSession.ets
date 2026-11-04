import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';

/**
 * Device-local brightness, shared by reader instances, never written into a theme or synced to another device.
 * The reader is the only window-brightness writer in the app, so leaving it always hands the window back to the
 * system (-1). The brightness read from window properties is not a reliable "original": it may report a concrete
 * level while the window is in fact following the system, and restoring that level would pin the whole app window.
 */
export class ReaderBrightnessSession {
  private static readonly FOLLOW_SYSTEM: number = -1;
  private static owner: ReaderBrightnessSession | null = null;
  private static mainWindow: window.Window | null = null;
  private static windowQueue: Promise<void> = Promise.resolve();
  private static saveQueue: Promise<void> = Promise.resolve();
  private active: boolean = false;
  private revision: number = 0;
  private loaded: boolean = false;
  private dirty: boolean = false;
  private value: number = -1;
  private context: Context | null = null;
  private onError: () => void = (): void => {};
  private reportedError: boolean = false;

  async activate(context: Context, onReady: (value: number) => void, onError: () => void): Promise<void> {
    if (this.active) {
      if (this.loaded) onReady(this.value);
      return;
    }
    this.active = true;
    this.loaded = false;
    this.context = context;
    this.onError = onError;
    this.reportedError = false;
    const revision = ++this.revision;
    if (!this.loaded) {
      try {
        await ReaderBrightnessSession.saveQueue.catch(() => {});
        const store = await preferences.getPreferences(context, 'reader_brightness');
        const saved = Number(await store.get('value', -1));
        if (!this.active || revision !== this.revision) return;
        this.value = ReaderBrightnessSession.normalize(saved);
        this.loaded = true;
      } catch (error) {
        console.warn('读取阅读亮度失败:', error);
        if (this.active && revision === this.revision) this.reportError();
        return;
      }
    }
    if (!this.active || revision !== this.revision) return;
    onReady(this.value);
    this.apply();
  }

  static normalize(value: number): number {
    if (!Number.isFinite(value) || value < 0) return -1;
    return Math.min(100, Math.max(1, Math.round(value)));
  }

  set(value: number, persist: boolean): void {
    if (!this.active || !this.loaded) return;
    this.value = ReaderBrightnessSession.normalize(value);
    this.dirty = true;
    this.apply();
    if (persist) this.save();
  }

  private apply(): void {
    const revision = ++this.revision;
    const context = this.context;
    if (!context) return;
    // Serialize native writes across old/new pages. Skip superseded drag updates before calling the window API.
    ReaderBrightnessSession.windowQueue = ReaderBrightnessSession.windowQueue.catch(() => {}).then(async () => {
      if (!this.active || revision !== this.revision) return;
      const mainWindow = await window.getLastWindow(context);
      if (!this.active || revision !== this.revision) return;
      ReaderBrightnessSession.mainWindow = mainWindow;
      ReaderBrightnessSession.owner = this;
      await mainWindow.setWindowBrightness(this.value < 0 ? ReaderBrightnessSession.FOLLOW_SYSTEM : this.value / 100);
    }).catch((error: Error) => {
      console.warn('设置阅读亮度失败:', error);
      if (this.active && revision === this.revision) this.reportError();
    });
  }

  deactivate(): void {
    if (!this.active) return;
    this.active = false;
    ++this.revision;
    if (this.loaded && this.dirty &&
      (!ReaderBrightnessSession.owner || ReaderBrightnessSession.owner === this)) this.save();
    ReaderBrightnessSession.windowQueue = ReaderBrightnessSession.windowQueue.catch(() => {}).then(async () => {
      // A retained page must not restore brightness over the reader that replaced it.
      if (this.active || ReaderBrightnessSession.owner !== this) return;
      const mainWindow = ReaderBrightnessSession.mainWindow;
      if (mainWindow) await mainWindow.setWindowBrightness(ReaderBrightnessSession.FOLLOW_SYSTEM);
      ReaderBrightnessSession.owner = null;
      ReaderBrightnessSession.mainWindow = null;
    }).catch((error: Error) => console.warn('恢复窗口亮度失败:', error));
  }

  private save(): void {
    const context = this.context;
    if (!context) return;
    const value = this.value;
    this.dirty = false;
    ReaderBrightnessSession.saveQueue = ReaderBrightnessSession.saveQueue.catch(() => {}).then(async () => {
      const store = await preferences.getPreferences(context, 'reader_brightness');
      await store.put('value', value);
      await store.flush();
    }).catch((error: Error) => {
      console.warn('保存阅读亮度失败:', error);
      if (this.active) this.reportError();
    });
  }

  private reportError(): void {
    if (this.reportedError) return;
    this.reportedError = true;
    this.onError();
  }
}
