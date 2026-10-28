/** Per-search arrival ledger. Metadata updates, recycling and category changes must not replay entries. */
export class ResultArrivalTracker {
  private seen: Set<string> = new Set<string>();
  private pending: Map<string, number> = new Map<string, number>();
  private prepared: Set<string> = new Set<string>();
  private windowStart: number = -1;
  private windowCount: number = 0;

  reset(): void {
    this.seen.clear();
    this.pending.clear();
    this.prepared.clear();
    this.windowStart = -1;
    this.windowCount = 0;
  }

  record(keys: string[], active: boolean, now: number): void {
    this.pending.forEach((arrivedAt: number, key: string): void => {
      if (now - arrivedAt > 500 || !active) this.pending.delete(key);
    });
    for (const key of keys) {
      if (this.seen.has(key)) continue;
      this.seen.add(key);
      if (active) this.pending.set(key, now);
    }
  }

  /** Cover preparation may finish long after raw metadata arrives. Admit each identity only once. */
  markReady(key: string, active: boolean, now: number): void {
    if (this.prepared.has(key)) return;
    this.prepared.add(key);
    if (active) this.pending.set(key, now);
    else this.pending.delete(key);
  }

  /** Returns a bounded stagger delay, or -1 for an existing/offscreen/stale result. */
  claim(key: string, now: number): number {
    const arrivedAt = this.pending.get(key);
    this.pending.delete(key);
    if (arrivedAt === undefined || now - arrivedAt > 500) return -1;
    if (this.windowStart < 0 || now - this.windowStart >= 320) {
      this.windowStart = now;
      this.windowCount = 0;
    }
    if (this.windowCount >= 6) return -1;
    return this.windowCount++ * 25;
  }

  discardPending(): void {
    this.pending.clear();
  }
}
