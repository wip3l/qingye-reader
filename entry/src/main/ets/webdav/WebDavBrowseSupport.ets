import { WebDavBrowsePrefs, WebDavEntry } from './WebDavModels';
import { compareText } from '../platform/TextCompare';

export type WebDavListLoader = (relativePath: string) => Promise<WebDavEntry[]>;

/** 远程书籍页的排序、分组、搜索匹配等纯逻辑，不碰界面和网络。 */
export class WebDavBrowseSupport {
  static sortEntries(entries: WebDavEntry[], mode: string): WebDavEntry[] {
    const sorted = entries.slice();
    sorted.sort((left: WebDavEntry, right: WebDavEntry): number => {
      if (left.directory !== right.directory) return left.directory ? -1 : 1;
      if (mode === WebDavBrowsePrefs.SORT_MODIFIED && left.lastModified !== right.lastModified) {
        return right.lastModified - left.lastModified;
      }
      if (mode === WebDavBrowsePrefs.SORT_SIZE && !left.directory && left.size !== right.size) {
        return right.size - left.size;
      }
      return compareText(left.name, right.name, 'zh-Hans-CN', { numeric: true });
    });
    return sorted;
  }

  static sortLabel(mode: string): string {
    if (mode === WebDavBrowsePrefs.SORT_MODIFIED) return '时间';
    if (mode === WebDavBrowsePrefs.SORT_SIZE) return '大小';
    return '名称';
  }

  static normalizeKeyword(keyword: string): string {
    return (keyword || '').trim().toLowerCase();
  }

  /** booksOnly 时只留可阅读的书和文件夹（文件夹方便顺着找进去）。keyword 须先经 normalizeKeyword。 */
  static matchesSearch(entry: WebDavEntry, keyword: string, booksOnly: boolean): boolean {
    if (!keyword) return false;
    if (booksOnly && !entry.directory && !entry.readableBook()) return false;
    return entry.name.toLowerCase().includes(keyword);
  }

  static parentPath(relativePath: string): string {
    const index = relativePath.lastIndexOf('/');
    return index >= 0 ? relativePath.substring(0, index) : '';
  }

  /** 搜索结果所在位置，相对搜索起点：起点本层写“当前文件夹”，更深的写“刘慈欣 › 资料”。 */
  static locationLabel(entry: WebDavEntry, basePath: string): string {
    const parent = WebDavBrowseSupport.parentPath(entry.relativePath);
    if (parent === basePath) return '当前文件夹';
    const relative = basePath && parent.startsWith(`${basePath}/`) ? parent.substring(basePath.length + 1) : parent;
    return relative.split('/').join(' › ');
  }

  /** 路径条各段对应的完整相对路径：'a/b/c' → ['a', 'a/b', 'a/b/c']。 */
  static breadcrumbPaths(currentPath: string): string[] {
    if (!currentPath) return [];
    const parts = currentPath.split('/').filter((part: string): boolean => part.length > 0);
    const paths: string[] = [];
    for (let index = 0; index < parts.length; index++) {
      paths.push(parts.slice(0, index + 1).join('/'));
    }
    return paths;
  }

  static lastSegment(path: string): string {
    const index = path.lastIndexOf('/');
    return index >= 0 ? path.substring(index + 1) : path;
  }

  /** 书脊色块：深浅模式共用，白字在上面都够对比度。 */
  static formatColor(format: string): string {
    if (format === 'epub') return '#2F7F6F';
    if (format === 'pdf') return '#A8472F';
    if (format === 'mobi') return '#93600F';
    return '#5F5F66';
  }
}

/**
 * 从某个文件夹往下逐层查子文件夹，查到一层就回调一批命中项。
 * 同时最多 CONCURRENCY 个请求，避免坚果云等网盘限流；列目录交给 loader，页面在里面复用本次浏览的目录缓存。
 */
export class WebDavFolderSearch {
  static readonly CONCURRENCY: number = 2;
  static readonly MAX_FOLDERS: number = 3000;
  static readonly MAX_RESULTS: number = 500;

  scanned: number = 0;
  failed: number = 0;
  /** 达到文件夹或结果上限后提前停下。 */
  truncated: boolean = false;
  private cancelled: boolean = false;
  private found: number = 0;
  private readonly loader: WebDavListLoader;
  private readonly keyword: string;
  private readonly booksOnly: boolean;

  constructor(loader: WebDavListLoader, keyword: string, booksOnly: boolean) {
    this.loader = loader;
    this.keyword = WebDavBrowseSupport.normalizeKeyword(keyword);
    this.booksOnly = booksOnly;
  }

  cancel(): void {
    this.cancelled = true;
  }

  isCancelled(): boolean {
    return this.cancelled;
  }

  /** startEntries 是起点那一层（已由页面列出并单独筛过），这里只查它下面的子文件夹。 */
  run(startEntries: WebDavEntry[], onBatch: (matches: WebDavEntry[]) => void): Promise<void> {
    const queue: string[] = startEntries.filter((entry: WebDavEntry): boolean => entry.directory)
      .map((entry: WebDavEntry): string => entry.relativePath);
    let active = 0;
    return new Promise<void>((resolve: () => void): void => {
      const pump = (): void => {
        while (!this.cancelled && active < WebDavFolderSearch.CONCURRENCY && queue.length > 0) {
          if (this.scanned + active >= WebDavFolderSearch.MAX_FOLDERS || this.found >= WebDavFolderSearch.MAX_RESULTS) {
            this.truncated = true;
            queue.length = 0;
            break;
          }
          const path = queue.shift() as string;
          active++;
          this.loader(path).then((entries: WebDavEntry[]): void => {
            if (this.cancelled) return;
            this.scanned++;
            const matches: WebDavEntry[] = [];
            for (const entry of entries) {
              if (entry.directory) queue.push(entry.relativePath);
              if (WebDavBrowseSupport.matchesSearch(entry, this.keyword, this.booksOnly)) matches.push(entry);
            }
            this.found += matches.length;
            onBatch(matches);
          }).catch((_error: Object): void => {
            this.failed++;
          }).finally((): void => {
            active--;
            if (active === 0 && (this.cancelled || queue.length === 0)) {
              resolve();
              return;
            }
            pump();
          });
        }
        if (active === 0) resolve();
      };
      pump();
    });
  }
}
