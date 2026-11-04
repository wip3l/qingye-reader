/**
 * Bridges UIAbility lifecycle events to the currently active reader page.
 *
 * Locking the screen does not consistently dispatch page-level onPageHide on every HarmonyOS device,
 * while UIAbility.onBackground is guaranteed for both Home and lock-screen background transitions.
 */
export class ReaderProgressCheckpoint {
  private static ownerId: string = '';
  private static saveAction: (() => Promise<void>) | null = null;
  private static bookUrlState: (() => string) | null = null;
  private static backgroundOwnerId: string = '';
  private static backgroundBookUrlState: (() => string) | null = null;

  static attach(ownerId: string, saveAction: () => Promise<void>, bookUrlState: () => string): void {
    ReaderProgressCheckpoint.ownerId = ownerId;
    ReaderProgressCheckpoint.saveAction = saveAction;
    ReaderProgressCheckpoint.bookUrlState = bookUrlState;
  }

  static detach(ownerId: string): void {
    if (!ownerId || ReaderProgressCheckpoint.ownerId !== ownerId) return;
    ReaderProgressCheckpoint.ownerId = '';
    ReaderProgressCheckpoint.saveAction = null;
    ReaderProgressCheckpoint.bookUrlState = null;
  }

  /**
   * A reader that left the route stack but still drives TTS keeps advancing its book. It may keep writing
   * progress unless a visible reader page has the same book open; that page then owns the book's progress.
   */
  static retainBackground(ownerId: string, bookUrlState: () => string): void {
    if (!ownerId) return;
    ReaderProgressCheckpoint.backgroundOwnerId = ownerId;
    ReaderProgressCheckpoint.backgroundBookUrlState = bookUrlState;
  }

  static releaseBackground(ownerId: string): void {
    if (!ownerId || ReaderProgressCheckpoint.backgroundOwnerId !== ownerId) return;
    ReaderProgressCheckpoint.backgroundOwnerId = '';
    ReaderProgressCheckpoint.backgroundBookUrlState = null;
  }

  /** A retained/disappearing reader may finish after a newer reader page has attached. */
  static canWrite(ownerId: string): boolean {
    if (!ownerId) return false;
    if (ReaderProgressCheckpoint.ownerId === ownerId) return true;
    if (ReaderProgressCheckpoint.backgroundOwnerId !== ownerId) return false;
    if (!ReaderProgressCheckpoint.ownerId) return true;
    // The URLs are read live: the visible reader learns its book after attaching and may switch source later.
    const visibleBookUrl = ReaderProgressCheckpoint.bookUrlState ? ReaderProgressCheckpoint.bookUrlState() : '';
    const backgroundBookUrl = ReaderProgressCheckpoint.backgroundBookUrlState ?
      ReaderProgressCheckpoint.backgroundBookUrlState() : '';
    return !!visibleBookUrl && !!backgroundBookUrl && visibleBookUrl !== backgroundBookUrl;
  }

  /** 当前挂着的阅读页正在读的书；没有阅读页时为空串。 */
  static activeBookUrl(): string {
    return ReaderProgressCheckpoint.bookUrlState ? ReaderProgressCheckpoint.bookUrlState() : '';
  }

  static request(reason: string): Promise<void> {
    const action = ReaderProgressCheckpoint.saveAction;
    if (!action) return Promise.resolve();
    return action().catch((error: Error) => {
      console.warn(`[ReaderProgressCheckpoint] ${reason} save failed:`, error);
    });
  }
}
