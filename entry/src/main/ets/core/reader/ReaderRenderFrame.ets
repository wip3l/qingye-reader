import { FrameCallback, UIContext } from '@ohos.arkui.UIContext';

class ReaderIdleFrameCallback extends FrameCallback {
  private finish: () => void;
  constructor(finish: () => void) { super(); this.finish = finish; }
  onIdle(_timeLeftInNano: number): void { this.finish(); }
}

class ReaderIdleBudgetFrameCallback extends FrameCallback {
  private accept: (timeLeftMs: number) => void;
  constructor(accept: (timeLeftMs: number) => void) { super(); this.accept = accept; }
  onIdle(timeLeftInNano: number): void { this.accept(timeLeftInNano / 1000000); }
}

/** Wait for ArkUI's next completed frame; this is not a physical-display presentation fence. */
export class ReaderRenderFrame {
  /**
   * Resolve inside a frame's idle slot that still has at least minIdleMs left, or after timeoutMs regardless.
   * Synchronous layout work started here lands after the frame's own UI work instead of on top of it, which is
   * what makes background pagination survive a running page-turn animation without stealing its frames.
   */
  static waitIdle(uiContext: UIContext, minIdleMs: number, timeoutMs: number = 32): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      let done = false;
      let timer = -1;
      const finish = (): void => {
        if (done) return;
        done = true;
        if (timer >= 0) clearTimeout(timer);
        resolve();
      };
      const post = (): void => {
        if (done) return;
        try {
          uiContext.postFrameCallback(new ReaderIdleBudgetFrameCallback((timeLeftMs: number): void => {
            if (timeLeftMs >= minIdleMs) finish(); else post();
          }));
        } catch (_) { finish(); }
      };
      timer = setTimeout(finish, timeoutMs);
      post();
    });
  }

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
