/** 在同页不同来源间隔离共享元素标识，避免书名相同或页面缓存引发串场。 */
export class SharedElementMotion {
  static coverId(scope: string, origin: string, bookUrl: string): string {
    return scope && bookUrl ? `cover:${scope}:${encodeURIComponent(origin)}:${encodeURIComponent(bookUrl)}` : '';
  }
}
