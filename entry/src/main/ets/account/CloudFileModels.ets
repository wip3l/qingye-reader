export class CloudFileSummary {
  configured: boolean = false;
  eligible: boolean = false;
  usedBytes: number = 0;
  quotaBytes: number = 1073741824;
  downloadBytes: number = 0;
  downloadQuotaBytes: number = 1073741824;
  chunkBytes: number = 1048576;
  cycleEndsAt: number | null = null;
}
/** 自动同步时随文件保存的少量信息：书名、作者、格式、内容指纹或字体名。 */
export class CloudFileMeta {
  title?: string;
  author?: string;
  format?: string;
  /** 阅读内容分类，与 TXT/EPUB 等文件格式分开保存。 */
  mediaCategory?: string;
  contentHash?: string;
  fontName?: string;
}
export class CloudFileItem {
  id: string = '';
  name: string = '';
  kind: string = '';
  bytes: number = 0;
  state: string = '';
  manifestHash: string = '';
  meta: CloudFileMeta | null = null;
}
/** 删除标记：REMOVED 表示用户移除了书或字体，DETACHED 表示只删了云端副本。 */
export class CloudTombstone {
  id: string = '';
  kind: string = '';
  manifestHash: string = '';
  meta: CloudFileMeta | null = null;
  reason: string = '';
  removedAt: number = 0;
}
export class CloudTombstoneList {
  tombstones: CloudTombstone[] = [];
}
export class CloudFileList {
  files: CloudFileItem[] = [];
  nextCursor: string = '';
}
export class CloudChunk {
  index: number = 0;
  bytes: number = 0;
  sha256: string = '';
}
export class CloudManifest extends CloudFileItem {
  chunkBytes: number = 1048576;
  chunks: CloudChunk[] = [];
}
export class CloudTransferTicket extends CloudChunk {
  url: string = '';
  expiresAt: number = 0;
  md5: string = '';
  ready: boolean = false;
}
export class CloudUploadTask {
  manifestHash: string = '';
  meta: CloudFileMeta | null = null;
  /** 由自动同步发起；手动上传页面不会替它继续或取消。 */
  auto: boolean = false;
  reused: boolean = false;
  requestId: string = '';
  fileId: string = '';
  path: string = '';
  name: string = '';
  kind: string = '';
  bytes: number = 0;
}
