export class WebDavConnection {
  id: string = '';
  name: string = '';
  baseUrl: string = '';
  username: string = '';
  libraryRoot: string = '';
  rememberPassword: boolean = true;
  secretStorageVersion: number = 1;
  enabled: boolean = true;
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class WebDavEntry {
  name: string = '';
  relativePath: string = '';
  href: string = '';
  directory: boolean = false;
  size: number = 0;
  lastModified: number = 0;
  etag: string = '';
  contentType: string = '';

  readableBook(): boolean {
    if (this.directory) return false;
    const value = this.name.toLowerCase();
    return value.endsWith('.txt') || value.endsWith('.epub') || value.endsWith('.mobi') || value.endsWith('.pdf') ||
      value.endsWith('.azw3') || value.endsWith('.azw') || value.endsWith('.fb2') || value.endsWith('.fbz') ||
      value.endsWith('.fb2.zip');
  }

  format(): string {
    const value = this.name.toLowerCase();
    if (value.endsWith('.epub')) return 'epub';
    if (value.endsWith('.mobi')) return 'mobi';
    if (value.endsWith('.azw3')) return 'azw3';
    if (value.endsWith('.azw')) return 'azw';
    if (value.endsWith('.fb2')) return 'fb2';
    if (value.endsWith('.fbz') || value.endsWith('.fb2.zip')) return 'fbz';
    if (value.endsWith('.pdf')) return 'pdf';
    if (value.endsWith('.txt')) return 'txt';
    return '';
  }
}

export class WebDavConnectionTestResult {
  ok: boolean = false;
  statusCode: number = 0;
  message: string = '';
}

export class WebDavBrowsePrefs {
  static readonly SORT_NAME: string = 'name';
  static readonly SORT_MODIFIED: string = 'modified';
  static readonly SORT_SIZE: string = 'size';

  sortMode: string = WebDavBrowsePrefs.SORT_NAME;
  /** 图片等不能阅读的文件是否直接列出；关闭时折叠成一行。 */
  showOthers: boolean = false;
  /** 搜索时是否包含子文件夹。 */
  searchDeep: boolean = false;
  /** 搜索结果只列可阅读的书籍文件和文件夹。 */
  booksOnly: boolean = false;

  static normalizeSortMode(value: string | undefined): string {
    return value === WebDavBrowsePrefs.SORT_MODIFIED || value === WebDavBrowsePrefs.SORT_SIZE ? value :
      WebDavBrowsePrefs.SORT_NAME;
  }
}

export class WebDavFileInfo {
  exists: boolean = false;
  statusCode: number = 0;
  size: number = 0;
  lastModified: number = 0;
  etag: string = '';
  contentType: string = '';
}

export class WebDavDownloadResult {
  path: string = '';
  size: number = 0;
  etag: string = '';
  lastModified: number = 0;
}
