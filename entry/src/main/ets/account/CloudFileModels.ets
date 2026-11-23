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
  /** 自定义主题：主题包（packageId）或某套方案的启动封面与预览图（schemeId），二者只有一个。 */
  packageId?: string;
  schemeId?: string;
}
export class CloudFileItem {
  id: string = '';
  name: string = '';
  kind: string = '';
  bytes: number = 0;
  state: string = '';
  manifestHash: string = '';
  meta: CloudFileMeta | null = null;
  /** 服务端创建时间（毫秒）；同一主题有多份时留最新的。旧服务端不返回，为 0。 */
  createdAt: number = 0;
}
/** 一次自动上传：本机文件、云端名称、类型与附加信息；key 用来记住本轮失败的内容。 */
export class CloudUploadJob {
  path: string = '';
  name: string = '';
  kind: string = '';
  meta: CloudFileMeta | null = null;
  manifestHash: string = '';
  key: string = '';
  /** 失败时同步问题里显示的名称。 */
  label: string = '';
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
