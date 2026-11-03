import { FrameCallback, UIContext } from '@ohos.arkui.UIContext';

class ReaderIdleFrameCallback extends FrameCallback {
  private finish: () => void;
  constructor(finish: () => void) { super(); this.finish = finish; }
  onIdle(_timeLeftInNano: number): void { this.finish(); }
}

/** Wait for ArkUI's next completed frame; this is not a physical-display presentation fence. */
export class ReaderRenderFrame {
  static wait(uiContext: UIContext, timeoutMs: number = 80): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      let done = false;
      let timer = -1;
      const finish = (): void => {
        if (done) return;
        done = true;
        if (timer >= 0) clearTimeout(timer);
        resolve();
      };
      timer = setTimeout(finish, timeoutMs);
      try { uiContext.postFrameCallback(new ReaderIdleFrameCallback(finish)); }
      catch (_) { finish(); }
    });
  }
}
