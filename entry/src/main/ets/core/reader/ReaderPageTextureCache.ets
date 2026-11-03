import image from '@ohos.multimedia.image';

class ReaderPageTextureEntry {
  bitmap: image.PixelMap;
  bytes: number;
  leases: number = 0;
  retired: boolean = false;
  private disposed: boolean = false;
  private onDispose: () => void;

  constructor(bitmap: image.PixelMap, bytes: number, onDispose: () => void) {
    this.bitmap = bitmap; this.bytes = bytes; this.onDispose = onDispose;
  }

  releaseIfUnused(): void {
    if (!this.retired || this.leases > 0 || this.disposed) return;
    this.disposed = true;
    this.bitmap.release().catch((): void => {});
    this.onDispose();
  }
}

/** Active frames retain a lease even after an LRU entry is replaced or invalidated. */
export class ReaderPageTextureLease {
  bitmap: image.PixelMap;
  private entry: ReaderPageTextureEntry;
  private released: boolean = false;

  constructor(entry: ReaderPageTextureEntry) {
    this.entry = entry; this.bitmap = entry.bitmap; entry.leases++;
  }

  release(): void {
    if (this.released) return;
    this.released = true;
    this.entry.leases--;
    this.entry.releaseIfUnused();
  }
}

/** At most two idle outgoing leaves. In-use frames may temporarily exceed the idle budget. */
export class ReaderPageTextureCache {
  private entries: Map<string, ReaderPageTextureEntry> = new Map<string, ReaderPageTextureEntry>();
  private bytes: number = 0;
  private readonly maxBytes: number = 24 * 1024 * 1024;

  acquire(key: string): ReaderPageTextureLease | null {
    const entry = this.entries.get(key);
    if (!entry) return null;
    this.entries.delete(key); this.entries.set(key, entry);
    return new ReaderPageTextureLease(entry);
  }

  put(key: string, bitmap: image.PixelMap, bytes: number): ReaderPageTextureLease {
    const old = this.entries.get(key);
    if (old) { this.entries.delete(key); old.retired = true; old.releaseIfUnused(); }
    const size = Math.max(0, bytes);
    this.bytes += size;
    const entry = new ReaderPageTextureEntry(bitmap, size, (): void => { this.bytes -= size; });
    const lease = new ReaderPageTextureLease(entry);
    this.entries.set(key, entry);
    while (this.entries.size > 2 || this.bytes > this.maxBytes) {
      const oldest = this.entries.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      const evicted = this.entries.get(oldest);
      this.entries.delete(oldest);
      if (evicted) { evicted.retired = true; evicted.releaseIfUnused(); }
    }
    return lease;
  }

  clear(): void {
    for (const entry of this.entries.values()) { entry.retired = true; entry.releaseIfUnused(); }
    this.entries.clear();
  }
}
