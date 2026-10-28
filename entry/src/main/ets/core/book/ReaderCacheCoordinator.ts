/** Short cache mutations share one queue. Never hold it over network or image inference. */
export class ReaderCacheCoordinator {
  private static chain: Promise<void> = Promise.resolve();
  private static books: Map<string, number> = new Map();
  private static files: Map<string, number> = new Map();
  private static readers: Set<() => string> = new Set();
  private static provider: () => string[] = (): string[] => [];
  static onRelease: () => void = (): void => {};

  static run<T>(task: () => Promise<T>): Promise<T> {
    const next = ReaderCacheCoordinator.chain.then(task, task);
    ReaderCacheCoordinator.chain = next.then((): void => {}, (): void => {});
    return next;
  }

  static setBooksProvider(provider: () => string[]): void { ReaderCacheCoordinator.provider = provider; }

  static protectedBooks(): string[] {
    return [...new Set<string>([...ReaderCacheCoordinator.provider(), ...ReaderCacheCoordinator.books.keys(),
      ...Array.from(ReaderCacheCoordinator.readers).map((reader: () => string): string => reader()).filter((book: string): boolean => !!book)])];
  }

  static watchReader(reader: () => string): () => void {
    ReaderCacheCoordinator.readers.add(reader);
    ReaderCacheCoordinator.onRelease();
    return (): void => {
      if (ReaderCacheCoordinator.readers.delete(reader)) ReaderCacheCoordinator.onRelease();
    };
  }

  static retainBook(book: string): () => void {
    return ReaderCacheCoordinator.retain(ReaderCacheCoordinator.books, book);
  }

  static retainFile(path: string): () => void {
    return ReaderCacheCoordinator.retain(ReaderCacheCoordinator.files, ReaderCacheCoordinator.path(path));
  }

  static fileInUse(path: string): boolean {
    return ReaderCacheCoordinator.files.has(ReaderCacheCoordinator.path(path));
  }

  static path(value: string): string {
    if (!value.startsWith('file://')) return value;
    const slash = value.indexOf('/', 7);
    try { return decodeURIComponent(value.substring(slash >= 0 ? slash : 7)); } catch (_) { return ''; }
  }

  private static retain(items: Map<string, number>, key: string): () => void {
    if (!key) return (): void => {};
    items.set(key, (items.get(key) || 0) + 1);
    let released = false;
    return (): void => {
      if (released) return;
      released = true;
      const count = (items.get(key) || 1) - 1;
      if (count > 0) items.set(key, count);
      else items.delete(key);
      ReaderCacheCoordinator.onRelease();
    };
  }
}
