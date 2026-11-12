/** One preparation operation; cancellation cannot interrupt an atomic database commit. */
export class SourceSwitchOperation {
  private stopped: boolean = false;
  private committing: boolean = false;
  private rejectWait: ((error: Error) => void) | null = null;
  private deadline: number;
  private cancelWork: () => void;

  constructor(cancelWork: () => void, totalTimeoutMs: number = 90000) {
    this.cancelWork = cancelWork;
    this.deadline = Date.now() + totalTimeoutMs;
  }

  isCancelled(): boolean { return this.stopped; }
  isCommitting(): boolean { return this.committing; }

  cancel(): void {
    if (this.committing || this.stopped) return;
    this.stopped = true;
    this.cancelWork();
    if (this.rejectWait) this.rejectWait(new Error('已取消换规则'));
  }

  check(): void {
    if (this.stopped) throw new Error('已取消换规则');
  }

  beginCommit(): void {
    this.check();
    if (Date.now() >= this.deadline) {
      this.cancel();
      throw new Error('换规则超时，已保留原规则');
    }
    this.committing = true;
  }

  async stage<T>(label: string, timeoutMs: number, work: () => Promise<T>): Promise<T> {
    this.check();
    const started = Date.now();
    const budget = Math.min(timeoutMs, this.deadline - started);
    if (budget <= 0) {
      this.cancel();
      throw new Error(`${label}超时，已保留原规则`);
    }
    let timer = -1;
    const interrupted = new Promise<T>((_resolve, reject): void => {
      this.rejectWait = reject;
      timer = setTimeout((): void => {
        // Reject with the stage name before cancellation rejects the same wait.
        reject(new Error(`${label}超时，已保留原规则`));
        this.cancel();
      }, budget);
    });
    try {
      const value = await Promise.race([interrupted, work()]);
      this.check();
      if (Date.now() - started >= budget) {
        this.cancel();
        throw new Error(`${label}超时，已保留原规则`);
      }
      return value;
    } finally {
      clearTimeout(timer);
      this.rejectWait = null;
      console.info(`[ChangeSource] stage=${label} elapsed=${Date.now() - started}ms`);
    }
  }
}
