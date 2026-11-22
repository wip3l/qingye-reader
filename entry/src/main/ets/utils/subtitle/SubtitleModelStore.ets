import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import http from '@ohos.net.http';
import picker from '@ohos.file.picker';
import statvfs from '@ohos.file.statvfs';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/** 字幕模型的一个文件：本地文件名、下载来源（仓库按顺序试）、大小与 SHA-256。 */
export class SubtitleModelFile {
  name: string;
  repos: string[];
  revisions: string[];
  remotePath: string;
  bytes: number;
  sha256: string;

  constructor(name: string, repos: string[], revisions: string[], remotePath: string, bytes: number, sha256: string) {
    this.name = name;
    this.repos = repos;
    this.revisions = revisions;
    this.remotePath = remotePath;
    this.bytes = bytes;
    this.sha256 = sha256;
  }
}

/**
 * 听书字幕的识别模型：sherpa-onnx 中文 Zipformer CTC（int8，Apache-2.0）加 CT-Transformer 标点（int8）。
 * 不进安装包，第一次用时从 Hugging Face（先走国内镜像）下载，或由用户导入同样的文件；大小和哈希都对上才算装好。
 * 模型文件不合规时 onnxruntime 会在原生层直接 abort 进程，所以只认下面这几个固定文件。
 */
export class SubtitleModelStore {
  static readonly STATE_KEY: string = 'subtitleModelState';
  static readonly RECEIVED_KEY: string = 'subtitleModelReceived';
  static readonly ERROR_KEY: string = 'subtitleModelError';
  static readonly NONE: string = 'none';
  static readonly DOWNLOADING: string = 'downloading';
  static readonly INSTALLED: string = 'installed';
  static readonly VERSION: string = 'zipformer-ctc-zh-int8-20250703+ct-punct-int8';
  static readonly ASR: string = 'model.int8.onnx';
  static readonly TOKENS: string = 'tokens.txt';
  static readonly PUNCT: string = 'punct.int8.onnx';
  static readonly CANCELED: string = '已取消下载';

  private static readonly DIR: string = 'subtitle_models/zipformer-ctc-zh-int8-20250703';
  private static readonly HOSTS: string[] = ['https://hf-mirror.com', 'https://huggingface.co'];
  private static readonly ASR_REPO: string = 'csukuangfj/sherpa-onnx-zipformer-ctc-zh-int8-2025-07-03';
  private static readonly ASR_REVISION: string = '824c678e9b80f301110e3ea8cee9819a7994c049';
  // 官方只在 GitHub 发布 tar.bz2；这两个仓库是同一文件的原样转存，哈希与官方包内一致。
  private static readonly PUNCT_REPOS: string[] = [
    'ranger810/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8',
    'lorneluo/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8'
  ];
  private static readonly PUNCT_REVISIONS: string[] = [
    '5cccf43af83e4fc50d1d55b8410312e87709be70',
    'fc2be466e3c11927b306a31cdee23c9c38da44cc'
  ];
  static readonly FILES: SubtitleModelFile[] = [
    new SubtitleModelFile(SubtitleModelStore.ASR, [SubtitleModelStore.ASR_REPO], [SubtitleModelStore.ASR_REVISION],
      'model.int8.onnx', 367074356, 'e291b9c468b651e2697caa09bc684326c3addc6a019e78eb537cfd1a8248ca07'),
    new SubtitleModelFile(SubtitleModelStore.TOKENS, [SubtitleModelStore.ASR_REPO], [SubtitleModelStore.ASR_REVISION],
      'tokens.txt', 13366, '6fed8c6c248516f38e7faa19404b57413e8ce259f1cbc1fa4aebc86eac32fdfd'),
    new SubtitleModelFile(SubtitleModelStore.PUNCT, SubtitleModelStore.PUNCT_REPOS, SubtitleModelStore.PUNCT_REVISIONS,
      'model.int8.onnx', 75519198, '65a3fb9f5ad7bfb96bf69e0dc4481df97f6ee60513c1d94ce981ba6effd524b1')
  ];
  /** 下载前至少留出的可用空间。 */
  private static readonly SPARE_BYTES: number = 200 * 1024 * 1024;
  private static readonly LOADING_MARKER: string = '.loading';

  private static running: Promise<void> | null = null;
  private static cancelled: boolean = false;

  static totalBytes(): number {
    return SubtitleModelStore.FILES.reduce((sum: number, file: SubtitleModelFile): number => sum + file.bytes, 0);
  }

  /** 约多少 MB，界面上显示用。 */
  static totalLabel(): string {
    return `${Math.round(SubtitleModelStore.totalBytes() / 1024 / 1024)} MB`;
  }

  static directory(): string {
    const root = AppStorage.get<string>('appFilesDir') || '';
    return root ? `${root}/${SubtitleModelStore.DIR}` : '';
  }

  static path(name: string): string {
    return `${SubtitleModelStore.directory()}/${name}`;
  }

  /** 三个文件都在且大小对得上。哈希在下载和导入时已经核对过，这里不重算。 */
  static installed(): boolean {
    const dir = SubtitleModelStore.directory();
    if (!dir) return false;
    for (const file of SubtitleModelStore.FILES) {
      try {
        if (fs.statSync(`${dir}/${file.name}`).size !== file.bytes) return false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  static state(): string {
    return AppStorage.get<string>(SubtitleModelStore.STATE_KEY) || SubtitleModelStore.NONE;
  }

  static isDownloading(): boolean {
    return SubtitleModelStore.running !== null;
  }

  /** 启动或模型变动后同步一次状态。 */
  static refresh(): void {
    if (SubtitleModelStore.running) return;
    AppStorage.setOrCreate(SubtitleModelStore.STATE_KEY,
      SubtitleModelStore.installed() ? SubtitleModelStore.INSTALLED : SubtitleModelStore.NONE);
  }

  /** 已下载的字节数（含未下完的部分），用于显示进度。 */
  static receivedBytes(): number {
    return AppStorage.get<number>(SubtitleModelStore.RECEIVED_KEY) || 0;
  }

  /** 下载缺的文件，可续传。已有下载在进行时等它结束。会员判断由调用方先做。 */
  static download(): Promise<void> {
    if (SubtitleModelStore.running) return SubtitleModelStore.running;
    SubtitleModelStore.cancelled = false;
    AppStorage.setOrCreate(SubtitleModelStore.ERROR_KEY, '');
    AppStorage.setOrCreate(SubtitleModelStore.STATE_KEY, SubtitleModelStore.DOWNLOADING);
    const task = SubtitleModelStore.downloadAll().catch((error: Error): void => {
      const message = error?.message || '下载失败，请重试';
      AppStorage.setOrCreate(SubtitleModelStore.ERROR_KEY, message === SubtitleModelStore.CANCELED ? '' : message);
      throw error;
    }).finally((): void => {
      SubtitleModelStore.running = null;
      SubtitleModelStore.refresh();
    });
    SubtitleModelStore.running = task;
    return task;
  }

  static cancel(): void {
    if (SubtitleModelStore.running) SubtitleModelStore.cancelled = true;
  }

  /** 删除模型（含下了一半的文件）。正在识别的 Worker 要先由调用方停掉。 */
  static remove(): void {
    SubtitleModelStore.cancel();
    const dir = SubtitleModelStore.directory();
    try {
      if (dir && fs.accessSync(dir)) fs.rmdirSync(dir);
    } catch (error) {
      console.warn('[Subtitle] remove model failed:', error);
    }
    AppStorage.setOrCreate(SubtitleModelStore.RECEIVED_KEY, 0);
    SubtitleModelStore.refresh();
  }

  /**
   * 加载前在标记里记下次数，第一次识别成功后删掉。原生层加载失败会直接结束进程；
   * 连续两次加载都没走到识别成功，就认为这份模型用不了，删掉让用户重新下载。
   * 只差一次可能是加载那几秒里用户正好退出了应用，不算。
   */
  static markLoading(): void {
    const marker = SubtitleModelStore.path(SubtitleModelStore.LOADING_MARKER);
    const count = SubtitleModelStore.loadingCount() + 1;
    try {
      const file = fs.openSync(marker, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, `${count}`); } finally { fs.closeSync(file); }
    } catch (_) {}
  }

  static clearLoading(): void {
    try { fs.unlinkSync(SubtitleModelStore.path(SubtitleModelStore.LOADING_MARKER)); } catch (_) {}
  }

  /** 连续两次加载都中途退出：返回 true 并删掉模型。 */
  static recoverInterruptedLoad(): boolean {
    if (SubtitleModelStore.loadingCount() < 2) return false;
    console.warn('[Subtitle] model load did not finish twice, removing model');
    SubtitleModelStore.remove();
    return true;
  }

  private static loadingCount(): number {
    try {
      const value = Number.parseInt(fs.readTextSync(SubtitleModelStore.path(SubtitleModelStore.LOADING_MARKER)), 10);
      return Number.isFinite(value) ? value : 1;
    } catch (_) {
      return 0;
    }
  }

  /**
   * 导入下载好的模型文件（可多选）：按大小和哈希认出是哪个文件，对上的放进模型目录。
   * 返回认出的文件数；取消选择返回 -1。
   */
  static async importFiles(context: Context, progress: (text: string) => void): Promise<number> {
    if (SubtitleModelStore.running) throw new Error('模型正在下载，请先取消下载');
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = SubtitleModelStore.FILES.length;
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (!uris || uris.length === 0) return -1;
    const dir = SubtitleModelStore.directory();
    if (!dir) throw new Error('无法保存模型');
    fs.mkdirSync(dir, true);
    let matched = 0;
    for (let i = 0; i < uris.length; i++) {
      progress(`正在检查第 ${i + 1} / ${uris.length} 个文件`);
      const temp = `${dir}/import_${Date.now()}.part`;
      try {
        const result = await SubtitleModelStore.copyAndHash(uris[i], temp);
        const file = SubtitleModelStore.FILES.find((item: SubtitleModelFile): boolean =>
          item.bytes === result.bytes && item.sha256 === result.sha256);
        if (!file) continue;
        fs.renameSync(temp, `${dir}/${file.name}`);
        matched++;
      } finally {
        try { if (fs.accessSync(temp)) fs.unlinkSync(temp); } catch (_) {}
      }
    }
    SubtitleModelStore.refresh();
    return matched;
  }

  /** 缺哪几个文件，给导入失败时的提示用。 */
  static missingNames(): string[] {
    const dir = SubtitleModelStore.directory();
    return SubtitleModelStore.FILES.filter((file: SubtitleModelFile): boolean => {
      try {
        return fs.statSync(`${dir}/${file.name}`).size !== file.bytes;
      } catch (_) {
        return true;
      }
    }).map((file: SubtitleModelFile): string => file === SubtitleModelStore.FILES[2] ? '标点模型 model.int8.onnx' :
      file.name === SubtitleModelStore.ASR ? '识别模型 model.int8.onnx' : file.name);
  }

  private static async copyAndHash(uri: string, target: string): Promise<HashResult> {
    const source = await fs.open(uri.startsWith('/') ? fileUri.getUriFromPath(uri) : uri, fs.OpenMode.READ_ONLY);
    const output = await fs.open(target, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    const digest = cryptoFramework.createMd('SHA256');
    const buffer = new ArrayBuffer(4 * 1024 * 1024);
    let bytes = 0;
    const limit = SubtitleModelStore.FILES.reduce((max: number, file: SubtitleModelFile): number =>
      Math.max(max, file.bytes), 0);
    try {
      while (true) {
        const count = await fs.read(source.fd, buffer);
        if (count <= 0) break;
        bytes += count;
        // 比最大的模型文件还大，肯定不是，不用再读。
        if (bytes > limit) break;
        const chunk: ArrayBuffer = buffer.slice(0, count);
        await digest.update({ data: new Uint8Array(chunk) });
        await SubtitleModelStore.writeAll(output.fd, chunk);
      }
    } finally {
      await fs.close(source);
      await fs.close(output);
    }
    const result = new HashResult();
    result.bytes = bytes;
    result.sha256 = bytes > limit ? '' : SubtitleModelStore.hex((await digest.digest()).data);
    return result;
  }

  private static async downloadAll(): Promise<void> {
    const dir = SubtitleModelStore.directory();
    if (!dir) throw new Error('无法保存模型');
    fs.mkdirSync(dir, true);
    let done = 0;
    let remaining = 0;
    for (const file of SubtitleModelStore.FILES) {
      const path = `${dir}/${file.name}`;
      if (SubtitleModelStore.sizeOf(path) === file.bytes) {
        done += file.bytes;
        continue;
      }
      remaining += file.bytes - Math.max(0, SubtitleModelStore.sizeOf(`${path}.part`));
    }
    AppStorage.setOrCreate(SubtitleModelStore.RECEIVED_KEY, done);
    if (remaining > 0) {
      let free = 0;
      try { free = await statvfs.getFreeSize(dir); } catch (_) { free = Number.MAX_SAFE_INTEGER; }
      if (free < remaining + SubtitleModelStore.SPARE_BYTES) {
        throw new Error(`存储空间不足，需要约 ${Math.ceil((remaining + SubtitleModelStore.SPARE_BYTES) / 1024 / 1024)} MB`);
      }
    }
    for (const file of SubtitleModelStore.FILES) {
      const path = `${dir}/${file.name}`;
      if (SubtitleModelStore.sizeOf(path) === file.bytes) continue;
      const base = done;
      await SubtitleModelStore.downloadFile(file, path, (received: number): void => {
        AppStorage.setOrCreate(SubtitleModelStore.RECEIVED_KEY, base + received);
      });
      done += file.bytes;
    }
    AppStorage.setOrCreate(SubtitleModelStore.RECEIVED_KEY, done);
  }

  private static async downloadFile(file: SubtitleModelFile, path: string,
    progress: (received: number) => void): Promise<void> {
    let lastError: Error = new Error('模型下载失败，请检查网络后重试');
    for (const host of SubtitleModelStore.HOSTS) {
      for (let i = 0; i < file.repos.length; i++) {
        if (SubtitleModelStore.cancelled) throw new Error(SubtitleModelStore.CANCELED);
        const url = `${host}/${file.repos[i]}/resolve/${file.revisions[i]}/${file.remotePath}`;
        try {
          await SubtitleModelStore.downloadFrom(url, file, path, progress);
          return;
        } catch (error) {
          lastError = error as Error;
          if (SubtitleModelStore.cancelled) throw new Error(SubtitleModelStore.CANCELED);
          // 存储写不进去换来源也没用。
          if (lastError.message.startsWith('无法保存')) throw lastError;
          console.warn(`[Subtitle] download ${file.name} from ${host} failed:`, lastError.message);
        }
      }
    }
    throw lastError;
  }

  /**
   * 流式写入 .part 并累计 SHA-256。已有 .part 时先把它算进哈希，再用 Range 接着下；
   * 服务器不认 Range（响应头里没有 Content-Range）时清空重下。大小和哈希都对上才改名。
   */
  private static async downloadFrom(url: string, file: SubtitleModelFile, path: string,
    progress: (received: number) => void): Promise<void> {
    const temp = `${path}.part`;
    // 服务器不认 Range 时要换一个新的哈希对象从头算，所以放在 holder 里。
    const digest: DigestHolder = { md: cryptoFramework.createMd('SHA256') };
    let offset = Math.max(0, SubtitleModelStore.sizeOf(temp));
    if (offset > file.bytes) {
      fs.unlinkSync(temp);
      offset = 0;
    }
    if (offset > 0) await SubtitleModelStore.hashExisting(temp, offset, digest.md);
    if (offset === file.bytes) {
      await SubtitleModelStore.finish(temp, path, file, digest.md);
      return;
    }
    const output = await fs.open(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.APPEND);
    const client = http.createHttp();
    let received = offset;
    progress(received);
    let failure = '';
    let timer = -1;
    try {
      await new Promise<void>((resolve, reject): void => {
        let ended = false;
        let accepted = false;
        let headersChecked = false;
        const fail = (message: string): void => {
          if (failure) return;
          failure = message;
          reject(new Error(message));
          try { client.destroy(); } catch (_) {}
        };
        const complete = (): void => {
          if (!ended || !accepted || failure) return;
          if (received !== file.bytes) fail('模型下载不完整，请重试');
          else resolve();
        };
        const restartFromZero = (): void => {
          fs.truncateSync(output.fd, 0);
          received = 0;
          digest.md = cryptoFramework.createMd('SHA256');
          progress(0);
        };
        client.on('headersReceive', (header: Object): void => {
          if (headersChecked) return;
          headersChecked = true;
          if (offset > 0 && !SubtitleModelStore.hasContentRange(header)) restartFromZero();
        });
        client.on('dataReceive', (chunk: ArrayBuffer): void => {
          if (failure) return;
          if (SubtitleModelStore.cancelled) { fail(SubtitleModelStore.CANCELED); return; }
          if (!headersChecked) {
            headersChecked = true;
            if (offset > 0) restartFromZero();
          }
          if (received + chunk.byteLength > file.bytes) { fail('模型文件大小异常'); return; }
          try {
            SubtitleModelStore.writeAllSync(output.fd, chunk);
            digest.md.updateSync({ data: new Uint8Array(chunk) });
            received += chunk.byteLength;
            progress(received);
          } catch (_) {
            fail('无法保存模型文件，请检查存储空间后重试');
          }
        });
        client.on('dataEnd', (): void => {
          ended = true;
          complete();
        });
        const deadline = Date.now() + 60 * 60 * 1000;
        timer = setInterval((): void => {
          if (SubtitleModelStore.cancelled) fail(SubtitleModelStore.CANCELED);
          else if (Date.now() > deadline) fail('模型下载超时，请重试');
        }, 300);
        const header: Record<string, string> = {};
        if (offset > 0) header['Range'] = `bytes=${offset}-`;
        client.requestInStream(url, {
          method: http.RequestMethod.GET, header: header, connectTimeout: 20000, readTimeout: 60000, usingProxy: false
        }).then((status: number): void => {
          if (status !== 200 && status !== 206) { fail(`模型下载失败（${status}）`); return; }
          accepted = true;
          complete();
        }).catch((): void => { fail('模型下载失败，请检查网络后重试'); });
      });
    } finally {
      if (timer >= 0) clearInterval(timer);
      try { client.off('headersReceive'); client.off('dataReceive'); client.off('dataEnd'); client.destroy(); } catch (_) {}
      await fs.close(output);
    }
    await SubtitleModelStore.finish(temp, path, file, digest.md);
  }

  private static async finish(temp: string, path: string, file: SubtitleModelFile, digest: cryptoFramework.Md):
    Promise<void> {
    const hash = SubtitleModelStore.hex((await digest.digest()).data);
    if (hash !== file.sha256) {
      try { fs.unlinkSync(temp); } catch (_) {}
      throw new Error('模型文件校验失败，请重试');
    }
    fs.renameSync(temp, path);
  }

  private static async hashExisting(path: string, bytes: number, digest: cryptoFramework.Md): Promise<void> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    const buffer = new ArrayBuffer(4 * 1024 * 1024);
    let read = 0;
    try {
      while (read < bytes) {
        if (SubtitleModelStore.cancelled) throw new Error(SubtitleModelStore.CANCELED);
        const count = await fs.read(file.fd, buffer, { offset: read, length: Math.min(buffer.byteLength, bytes - read) });
        if (count <= 0) break;
        await digest.update({ data: new Uint8Array(buffer.slice(0, count)) });
        read += count;
      }
    } finally {
      await fs.close(file);
    }
    if (read !== bytes) throw new Error('模型下载不完整，请重试');
  }

  private static hasContentRange(header: Object): boolean {
    const record = header as Record<string, Object>;
    for (const key of Object.keys(record)) {
      if (key.toLowerCase() === 'content-range') return true;
    }
    return false;
  }

  private static writeAllSync(fd: number, chunk: ArrayBuffer): void {
    let offset = 0;
    while (offset < chunk.byteLength) {
      const count = fs.writeSync(fd, chunk.slice(offset));
      if (count <= 0) throw new Error('写入失败');
      offset += count;
    }
  }

  private static async writeAll(fd: number, chunk: ArrayBuffer): Promise<void> {
    let offset = 0;
    while (offset < chunk.byteLength) {
      const count = await fs.write(fd, chunk.slice(offset));
      if (count <= 0) throw new Error('无法保存模型文件，请检查存储空间后重试');
      offset += count;
    }
  }

  private static sizeOf(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (_) {
      return -1;
    }
  }

  private static hex(bytes: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) hex += bytes[i].toString(16).padStart(2, '0');
    return hex;
  }
}

class HashResult {
  bytes: number = 0;
  sha256: string = '';
}

interface DigestHolder {
  md: cryptoFramework.Md;
}
