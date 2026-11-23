// platform/FileUri.ts 的安卓实现。@ohos.file.fileuri 没有跨平台实现，应用只用到路径与 file:// 地址互转和取文件名。
// 沙箱路径直接拼成 file://<绝对路径>。

class FileUriImpl {
  private raw: string;

  constructor(uriOrPath: string) {
    this.raw = uriOrPath || '';
  }

  get path(): string {
    let value = this.raw;
    if (value.startsWith('file://')) {
      value = value.substring('file://'.length);
      // file://<bundle>/data/... 形式去掉包名段
      if (!value.startsWith('/')) {
        const slash = value.indexOf('/');
        value = slash >= 0 ? value.substring(slash) : '';
      }
    }
    const query = value.indexOf('?');
    if (query >= 0) value = value.substring(0, query);
    try {
      return decodeURIComponent(value);
    } catch (_) {
      return value;
    }
  }

  get name(): string {
    const path = this.path;
    return path.substring(path.lastIndexOf('/') + 1);
  }

  toString(): string {
    return this.raw.startsWith('file://') ? this.raw : 'file://' + this.raw;
  }

  getFullDirectoryUri(): string {
    const path = this.path;
    return 'file://' + path.substring(0, Math.max(0, path.lastIndexOf('/')));
  }

  isRemoteUri(): boolean {
    return false;
  }
}

export namespace fileUri {
  export class FileUri extends FileUriImpl {
  }

  export function getUriFromPath(path: string): string {
    if (!path) return '';
    if (path.startsWith('file://')) return path;
    return 'file://' + path;
  }
}
