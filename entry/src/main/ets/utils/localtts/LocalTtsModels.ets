import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { TtsVoiceAvailability } from '../TtsVoiceAvailability';

/**
 * 离线神经网络音色（sherpa-onnx）的模型目录、下载、导入登记与校验。
 *
 * 模型不进安装包：内置音色由会员按需下载到 files/local-tts/<模型目录>，逐个文件校验大小和 SHA-256；
 * 用户导入的模型放在 files/local-tts/user/<id>，旁边存一份 user-model.json 描述文件结构。
 * sherpa-onnx 加载坏文件时原生层会直接 abort 整个进程，ArkTS 拦不住，所以：
 *  - 没有 installed.json 或文件大小不对，一律视为未安装，绝不交给引擎加载；
 *  - 加载与首句合成期间留一个 loading 标记，进程被带崩后下次启动据此把模型停用（见 recoverInterruptedLoads）。
 */
export class LocalTtsModelFile {
  name: string = '';
  bytes: number = 0;
  /** 内置模型下载时校验用；导入的模型为空，只核对大小。 */
  sha256: string = '';

  constructor(name: string, bytes: number, sha256: string) {
    this.name = name;
    this.bytes = bytes;
    this.sha256 = sha256;
  }
}

export class LocalTtsModel {
  id: string = '';
  name: string = '';
  description: string = '';
  /** 相对 files/local-tts 的目录。 */
  dirName: string = '';
  /** Hugging Face 仓库路径（仅内置模型），下载时拼在各个镜像域名后面。 */
  repo: string = '';
  /** sherpa-onnx 模型结构：vits（含 Piper）、matcha、kokoro。 */
  kind: string = 'vits';
  modelFile: string = '';
  /** matcha 的声码器。 */
  vocoderFile: string = '';
  /** kokoro 的音色向量文件。 */
  voicesFile: string = '';
  lexicons: string[] = [];
  /** espeak-ng 数据目录（旧版 Piper、kokoro 用）；空表示不用。 */
  dataDir: string = '';
  ruleFsts: string[] = [];
  /** 多说话人模型朗读用的说话人编号。 */
  sid: number = 0;
  imported: boolean = false;
  files: LocalTtsModelFile[] = [];

  totalBytes(): number {
    return this.files.reduce((sum: number, file: LocalTtsModelFile): number => sum + file.bytes, 0);
  }
}

class LocalTtsInstallMarker {
  id: string = '';
  installedAt: number = 0;
}

/** user-model.json 的结构；JSON.parse 的结果逐字段取，不信任其中的类型。 */
interface LocalTtsModelManifest {
  id?: string;
  name?: string;
  kind?: string;
  modelFile?: string;
  vocoderFile?: string;
  voicesFile?: string;
  lexicons?: string[];
  dataDir?: string;
  ruleFsts?: string[];
  sid?: number;
  files?: LocalTtsModelFile[];
}

export class LocalTtsModels {
  static readonly MEMBER_REQUIRED: string = '离线音色为会员专享，开通会员后即可使用';
  /** 已安装模型 id，换行分隔；界面靠它刷新“已下载/已导入”状态。 */
  static readonly STORAGE_INSTALLED: string = 'localTtsInstalledIds';
  /** 正在下载的模型 id 与进度文字，跨页面共享（离开音色管理页后台继续下载）。 */
  static readonly STORAGE_DOWNLOADING: string = 'localTtsDownloadingId';
  static readonly STORAGE_PROGRESS: string = 'localTtsDownloadProgress';
  static readonly USER_DIR: string = 'user';
  static readonly USER_MANIFEST: string = 'user-model.json';
  private static readonly ROOT_DIR: string = 'local-tts';
  private static readonly MARKER: string = 'installed.json';
  private static readonly LOADING_MARKER: string = 'loading';
  // 镜像在前：国内直连 huggingface.co 经常失败。两个都失败才报错。
  private static readonly HOSTS: string[] = ['https://hf-mirror.com', 'https://huggingface.co'];
  private static root: string = '';
  private static downloadActive: boolean = false;
  private static downloadCancelled: boolean = false;
  private static userModels: LocalTtsModel[] = [];

  static readonly CATALOG: LocalTtsModel[] = [LocalTtsModels.chaowen(), LocalTtsModels.huayan()];

  private static chaowen(): LocalTtsModel {
    const model = new LocalTtsModel();
    model.id = 'piper-zh-chaowen';
    model.name = '超文';
    model.description = '男声 · 普通话';
    model.dirName = 'vits-piper-zh_CN-chaowen-medium';
    model.repo = 'csukuangfj2/vits-piper-zh_CN-chaowen-medium';
    model.kind = 'vits';
    model.modelFile = 'zh_CN-chaowen-medium.onnx';
    model.lexicons = ['lexicon.txt'];
    model.ruleFsts = ['phone.fst', 'date.fst', 'number.fst'];
    model.files = [
      new LocalTtsModelFile('zh_CN-chaowen-medium.onnx', 63222141,
        '1cb646ea826a6ee73e329ea06319fb8d459da8a35be6c1ba30210387deb3bc55'),
      new LocalTtsModelFile('lexicon.txt', 2064505,
        '003e76f89fec389ec109b557f47cc315a1ac31a99091f0cc9d15949f9024416b'),
      new LocalTtsModelFile('tokens.txt', 485,
        'e9e6d2838a2676749adbf0376c4cf3c3cd28eb27ed953dcc2adcab8db3c33ba7'),
      new LocalTtsModelFile('date.fst', 59154,
        'eb8aa079ae3cb81d8f4404992f39d61a0cb990947512b5b8d1e54d1f6980e718'),
      new LocalTtsModelFile('number.fst', 64482,
        '743f402181fcfebf76cc2f0546b71fa26476e626fbe4e460fb7b4c3a7a8bd5bd'),
      new LocalTtsModelFile('phone.fst', 88630,
        '1ac2b6fa56b1442320c4de7db08353bab8963a2b57f365eebcdd3a2d3562f8d7')
    ];
    return model;
  }

  /** 旧版 Piper 转换：发音走 espeak-ng，只带中文要用的几个 espeak-ng-data 文件（约 2MB）。 */
  private static huayan(): LocalTtsModel {
    const model = new LocalTtsModel();
    model.id = 'piper-zh-huayan';
    model.name = '花颜';
    model.description = '女声 · 普通话';
    model.dirName = 'vits-piper-zh_CN-huayan-medium';
    model.repo = 'csukuangfj/vits-piper-zh_CN-huayan-medium';
    model.kind = 'vits';
    model.modelFile = 'zh_CN-huayan-medium.onnx';
    model.dataDir = 'espeak-ng-data';
    model.files = [
      new LocalTtsModelFile('zh_CN-huayan-medium.onnx', 63201423,
        '04234ec24907e9efa7e153669e07d4e0cf6d260adc005323aa929386dae53f86'),
      new LocalTtsModelFile('tokens.txt', 907,
        '2619c1a9de1bcf928162f40c583caf39368cfd6b2340c7bcad51dc634411ec36'),
      new LocalTtsModelFile('espeak-ng-data/phontab', 55796,
        '886f3fa402cb0ba73d483aa8ad000af47a6b7cc06293c75a97913fba68a530f6'),
      new LocalTtsModelFile('espeak-ng-data/phonindex', 39074,
        '3ca7b8fa3b42624e4b0f152707e7a39245fce569aa99ea47c055d9e622fcf0c4'),
      new LocalTtsModelFile('espeak-ng-data/phondata', 550424,
        '4e0288957874029a8c3c9f41a8f517ad4bf18127046decbdd4b9d1d6807ce3a3'),
      new LocalTtsModelFile('espeak-ng-data/intonations', 2040,
        '3f8af65fd3eda9759a10f021d61361c120871f463515229c925995c7f90918cc'),
      new LocalTtsModelFile('espeak-ng-data/cmn_dict', 1566335,
        '109aaa7708d3727382acb3ae41d8e2094a7e2bb9f651a81835be22a6f08071fe'),
      new LocalTtsModelFile('espeak-ng-data/lang/sit/cmn', 686,
        'a130a38e3b622735c2401cb37f6719f46995e84a133729185cef9a543ec0b072')
    ];
    return model;
  }

  /** 内置音色在前，导入的按导入顺序排在后面。 */
  static all(): LocalTtsModel[] {
    return LocalTtsModels.CATALOG.concat(LocalTtsModels.userModels);
  }

  static find(id: string): LocalTtsModel | undefined {
    return LocalTtsModels.all().find((model: LocalTtsModel): boolean => model.id === id);
  }

  static memberAllowed(): boolean {
    return AccountSessionStore.activeMembershipSku() !== '';
  }

  static voiceKey(model: LocalTtsModel): string {
    return `local_${model.id}`;
  }

  static voiceTitle(model: LocalTtsModel): string {
    return `${model.name} · ${model.description} · 离线`;
  }

  static sizeText(model: LocalTtsModel): string {
    return `${Math.round(model.totalBytes() / 1024 / 1024)} MB`;
  }

  static rootDir(context: Context): string {
    LocalTtsModels.root = `${context.getApplicationContext().filesDir}/${LocalTtsModels.ROOT_DIR}`;
    return LocalTtsModels.root;
  }

  static modelDir(context: Context, model: LocalTtsModel): string {
    return `${LocalTtsModels.rootDir(context)}/${model.dirName}`;
  }

  /** 不带 Context 的版本，给朗读引擎用；根目录在启动扫描时记下。 */
  static modelPath(model: LocalTtsModel): string {
    return LocalTtsModels.root ? `${LocalTtsModels.root}/${model.dirName}` : '';
  }

  static installedIds(): string[] {
    return (AppStorage.get<string>(LocalTtsModels.STORAGE_INSTALLED) || '').split('\n')
      .filter((id: string): boolean => !!id);
  }

  static isInstalled(id: string): boolean {
    return LocalTtsModels.installedIds().includes(id);
  }

  static installedModels(): LocalTtsModel[] {
    return LocalTtsModels.all().filter((model: LocalTtsModel): boolean => LocalTtsModels.isInstalled(model.id));
  }

  static availabilityKey(model: LocalTtsModel): string {
    return TtsVoiceAvailability.localKey(model.id);
  }

  /** 左滑禁用的离线音色不出现在朗读时的可选列表里，和系统/云端音色一致。 */
  static isEnabled(model: LocalTtsModel): boolean {
    return TtsVoiceAvailability.isEnabled(AppStorage.get<string>('ttsDisabledVoiceKeys') || '',
      LocalTtsModels.availabilityKey(model));
  }

  /** 已下载或已导入、且未禁用、可以选来朗读的离线音色。 */
  static selectableModels(): LocalTtsModel[] {
    return LocalTtsModels.installedModels().filter((model: LocalTtsModel): boolean => LocalTtsModels.isEnabled(model));
  }

  static refreshInstalled(context: Context): void {
    LocalTtsModels.rootDir(context);
    LocalTtsModels.refreshInstalledPaths();
  }

  /**
   * 启动时调用：上次加载或首句合成时进程被原生层带崩（留下了 loading 标记）的模型视为损坏，
   * 撤销安装标记，避免每次朗读都崩一次。内置音色可以重新下载，导入的会显示为“加载失败”。
   */
  static recoverInterruptedLoads(context: Context): void {
    LocalTtsModels.rootDir(context);
    LocalTtsModels.loadUserModels();
    for (const model of LocalTtsModels.all()) {
      const dir = LocalTtsModels.modelPath(model);
      try {
        if (!fs.accessSync(`${dir}/${LocalTtsModels.LOADING_MARKER}`)) continue;
        console.warn(`[LocalTts] model ${model.id} crashed while loading last time, marking it uninstalled`);
        try { fs.unlinkSync(`${dir}/${LocalTtsModels.MARKER}`); } catch (_) {}
        fs.unlinkSync(`${dir}/${LocalTtsModels.LOADING_MARKER}`);
      } catch (_) {
      }
    }
    LocalTtsModels.refreshInstalledPaths();
  }

  static markLoading(dir: string): void {
    try {
      const file = fs.openSync(`${dir}/${LocalTtsModels.LOADING_MARKER}`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.closeSync(file);
    } catch (error) {
      console.warn('[LocalTts] write loading marker failed:', error);
    }
  }

  static clearLoading(dir: string): void {
    try { fs.unlinkSync(`${dir}/${LocalTtsModels.LOADING_MARKER}`); } catch (_) {}
  }

  static refreshInstalledPaths(): void {
    const ids: string[] = [];
    for (const model of LocalTtsModels.all()) {
      if (LocalTtsModels.verifyDir(LocalTtsModels.modelPath(model), model)) ids.push(model.id);
    }
    // 导入模型的列表变化（新导入/删除）也靠这个字符串变化通知界面，所以把总数也拼进去。
    AppStorage.setOrCreate(LocalTtsModels.STORAGE_INSTALLED,
      ids.join('\n') + `\n#${LocalTtsModels.userModels.length}`);
  }

  /** 加载前的快速检查：标记文件存在、每个文件大小一致。哈希只在下载时算一次。 */
  static verifyOnDisk(context: Context, model: LocalTtsModel): boolean {
    return LocalTtsModels.verifyDir(LocalTtsModels.modelDir(context, model), model);
  }

  static verifyDir(dir: string, model: LocalTtsModel): boolean {
    if (!dir) return false;
    try {
      if (!fs.accessSync(`${dir}/${LocalTtsModels.MARKER}`)) return false;
      for (const file of model.files) {
        const path = `${dir}/${file.name}`;
        if (!fs.accessSync(path) || fs.statSync(path).size !== file.bytes) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /** 读 files/local-tts/user 下的导入模型描述。描述损坏的目录直接忽略（删除时一并清掉）。 */
  static loadUserModels(): void {
    const models: LocalTtsModel[] = [];
    const userRoot = `${LocalTtsModels.root}/${LocalTtsModels.USER_DIR}`;
    try {
      if (LocalTtsModels.root && fs.accessSync(userRoot)) {
        const names = fs.listFileSync(userRoot).sort();
        for (const name of names) {
          const model = LocalTtsModels.readManifest(`${userRoot}/${name}`, name);
          if (model) models.push(model);
        }
      }
    } catch (error) {
      console.warn('[LocalTts] load imported models failed:', error);
    }
    LocalTtsModels.userModels = models;
  }

  private static readManifest(dir: string, folder: string): LocalTtsModel | undefined {
    try {
      const path = `${dir}/${LocalTtsModels.USER_MANIFEST}`;
      if (!fs.accessSync(path) || fs.statSync(path).size > 256 * 1024) return undefined;
      const raw = JSON.parse(fs.readTextSync(path)) as LocalTtsModelManifest;
      const model = new LocalTtsModel();
      model.id = String(raw.id || '');
      model.name = String(raw.name || '导入的音色');
      model.kind = String(raw.kind || 'vits');
      model.modelFile = String(raw.modelFile || '');
      model.vocoderFile = String(raw.vocoderFile || '');
      model.voicesFile = String(raw.voicesFile || '');
      model.lexicons = Array.isArray(raw.lexicons) ? raw.lexicons.map((item: string): string => String(item)) : [];
      model.dataDir = String(raw.dataDir || '');
      model.ruleFsts = Array.isArray(raw.ruleFsts) ? raw.ruleFsts.map((item: string): string => String(item)) : [];
      model.sid = Math.max(0, Math.floor(Number(raw.sid) || 0));
      model.files = Array.isArray(raw.files) ? raw.files.map((item: LocalTtsModelFile): LocalTtsModelFile =>
        new LocalTtsModelFile(String(item.name || ''), Number(item.bytes) || 0, '')) : [];
      model.imported = true;
      model.dirName = `${LocalTtsModels.USER_DIR}/${folder}`;
      model.description = `导入 · ${LocalTtsModels.kindLabel(model.kind)}`;
      if (!model.id.startsWith('user-') || !model.modelFile || model.files.length === 0) return undefined;
      return model;
    } catch (error) {
      console.warn('[LocalTts] bad imported model manifest:', error);
      return undefined;
    }
  }

  static kindLabel(kind: string): string {
    if (kind === 'matcha') return 'Matcha';
    if (kind === 'kokoro') return 'Kokoro';
    return 'VITS';
  }

  /** 导入流程把文件放好后调用：写描述和安装标记，加入列表。 */
  static registerImported(dir: string, model: LocalTtsModel): void {
    const manifest: LocalTtsModelManifest = {
      id: model.id,
      name: model.name,
      kind: model.kind,
      modelFile: model.modelFile,
      vocoderFile: model.vocoderFile,
      voicesFile: model.voicesFile,
      lexicons: model.lexicons,
      dataDir: model.dataDir,
      ruleFsts: model.ruleFsts,
      sid: model.sid,
      files: model.files
    };
    LocalTtsModels.writeText(`${dir}/${LocalTtsModels.USER_MANIFEST}`, JSON.stringify(manifest));
    const marker = new LocalTtsInstallMarker();
    marker.id = model.id;
    marker.installedAt = Date.now();
    LocalTtsModels.writeText(`${dir}/${LocalTtsModels.MARKER}`, JSON.stringify(marker));
    LocalTtsModels.loadUserModels();
    LocalTtsModels.refreshInstalledPaths();
  }

  /** 改名、改说话人编号等，只改描述文件。 */
  static updateImported(model: LocalTtsModel): void {
    if (!model.imported) return;
    const dir = LocalTtsModels.modelPath(model);
    if (!dir) return;
    const path = `${dir}/${LocalTtsModels.USER_MANIFEST}`;
    try {
      const raw = JSON.parse(fs.readTextSync(path)) as LocalTtsModelManifest;
      raw.name = model.name;
      raw.sid = model.sid;
      LocalTtsModels.writeText(path, JSON.stringify(raw));
    } catch (error) {
      console.warn('[LocalTts] update imported model failed:', error);
    }
    LocalTtsModels.loadUserModels();
    LocalTtsModels.refreshInstalledPaths();
  }

  static isDownloading(): boolean {
    return LocalTtsModels.downloadActive;
  }

  static cancelDownload(): void {
    if (LocalTtsModels.downloadActive) LocalTtsModels.downloadCancelled = true;
  }

  /** 下载并校验内置音色的全部文件；同一时间只允许一个下载任务。进度写到 AppStorage。 */
  static async install(context: Context, model: LocalTtsModel): Promise<void> {
    if (!LocalTtsModels.memberAllowed()) throw new Error(LocalTtsModels.MEMBER_REQUIRED);
    if (model.imported || !model.repo) throw new Error('这个音色不能下载');
    if (LocalTtsModels.downloadActive) throw new Error('已有音色正在下载');
    LocalTtsModels.downloadActive = true;
    LocalTtsModels.downloadCancelled = false;
    AppStorage.setOrCreate(LocalTtsModels.STORAGE_DOWNLOADING, model.id);
    AppStorage.setOrCreate(LocalTtsModels.STORAGE_PROGRESS, '准备下载');
    const dir = LocalTtsModels.modelDir(context, model);
    try {
      LocalTtsModels.ensureDir(LocalTtsModels.rootDir(context));
      LocalTtsModels.ensureDir(dir);
      try { fs.unlinkSync(`${dir}/${LocalTtsModels.MARKER}`); } catch (_) {}
      const total = model.totalBytes();
      let done = 0;
      for (const file of model.files) {
        const path = `${dir}/${file.name}`;
        LocalTtsModels.ensureParents(dir, file.name);
        if (!(fs.accessSync(path) && fs.statSync(path).size === file.bytes &&
          await LocalTtsModels.fileHash(path) === file.sha256)) {
          await LocalTtsModels.downloadFile(model, file, path, (received: number): void => {
            const percent = Math.min(99, Math.floor((done + received) * 100 / total));
            AppStorage.setOrCreate(LocalTtsModels.STORAGE_PROGRESS, `下载中 ${percent}%`);
          });
        }
        done += file.bytes;
      }
      const marker = new LocalTtsInstallMarker();
      marker.id = model.id;
      marker.installedAt = Date.now();
      LocalTtsModels.writeText(`${dir}/${LocalTtsModels.MARKER}`, JSON.stringify(marker));
      LocalTtsModels.refreshInstalled(context);
    } finally {
      LocalTtsModels.downloadActive = false;
      LocalTtsModels.downloadCancelled = false;
      AppStorage.setOrCreate(LocalTtsModels.STORAGE_DOWNLOADING, '');
      AppStorage.setOrCreate(LocalTtsModels.STORAGE_PROGRESS, '');
    }
  }

  /** 内置音色删掉文件、可再下载；导入的音色连同描述一起删除，从列表消失。 */
  static remove(context: Context, model: LocalTtsModel): void {
    const dir = LocalTtsModels.modelDir(context, model);
    try { fs.unlinkSync(`${dir}/${LocalTtsModels.MARKER}`); } catch (_) {}
    try { fs.unlinkSync(`${dir}/${LocalTtsModels.USER_MANIFEST}`); } catch (_) {}
    try { fs.rmdirSync(dir); } catch (error) { console.warn('[LocalTts] remove model dir failed:', error); }
    LocalTtsModels.loadUserModels();
    LocalTtsModels.refreshInstalled(context);
  }

  static ensureDir(path: string): void {
    if (!fs.accessSync(path)) fs.mkdirSync(path, true);
  }

  /** 文件名可以带子目录（如 espeak-ng-data/lang/sit/cmn），逐级建好父目录。 */
  private static ensureParents(dir: string, name: string): void {
    const parts = name.split('/');
    let current = dir;
    for (let i = 0; i < parts.length - 1; i++) {
      current = `${current}/${parts[i]}`;
      LocalTtsModels.ensureDir(current);
    }
  }

  private static writeText(path: string, text: string): void {
    const output = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(output.fd, text); } finally { fs.closeSync(output); }
  }

  private static async downloadFile(model: LocalTtsModel, file: LocalTtsModelFile, path: string,
    progress: (received: number) => void): Promise<void> {
    let lastError: Error = new Error('下载失败');
    for (const host of LocalTtsModels.HOSTS) {
      if (LocalTtsModels.downloadCancelled) throw new Error('已取消下载');
      try {
        await LocalTtsModels.downloadFrom(`${host}/${model.repo}/resolve/main/${file.name}`, file, path, progress);
        return;
      } catch (error) {
        lastError = error as Error;
        if (LocalTtsModels.downloadCancelled) throw new Error('已取消下载');
        console.warn(`[LocalTts] download ${file.name} from ${host} failed:`, lastError.message);
      }
    }
    throw lastError;
  }

  /** 流式写入 .part，同时累计 SHA-256；大小和哈希都对上才改名成正式文件。 */
  private static async downloadFrom(url: string, file: LocalTtsModelFile, path: string,
    progress: (received: number) => void): Promise<void> {
    const temp = `${path}.part`;
    const output = await fs.open(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    const digest = cryptoFramework.createMd('SHA256');
    const client = http.createHttp();
    let received = 0;
    let failure = '';
    let timer = -1;
    let completed = false;
    try {
      await new Promise<void>((resolve, reject): void => {
        let ended = false;
        let accepted = false;
        const fail = (message: string): void => {
          if (failure) return;
          failure = message;
          reject(new Error(message));
          try { client.destroy(); } catch (_) {}
        };
        const complete = (): void => {
          if (!ended || !accepted || failure) return;
          if (received !== file.bytes) fail('音色文件下载不完整，请重试');
          else resolve();
        };
        client.on('dataReceive', (chunk: ArrayBuffer): void => {
          if (failure) return;
          if (LocalTtsModels.downloadCancelled) { fail('已取消下载'); return; }
          if (received + chunk.byteLength > file.bytes) { fail('音色文件大小异常'); return; }
          try {
            let offset = 0;
            while (offset < chunk.byteLength) {
              const count = fs.writeSync(output.fd, chunk.slice(offset));
              if (count <= 0) throw new Error('写入失败');
              offset += count;
            }
            digest.updateSync({ data: new Uint8Array(chunk) });
            received += chunk.byteLength;
            progress(received);
          } catch (_) {
            fail('无法保存音色文件，请检查存储空间后重试');
          }
        });
        client.on('dataEnd', (): void => { ended = true; complete(); });
        const deadline = Date.now() + 20 * 60 * 1000;
        timer = setInterval((): void => {
          if (LocalTtsModels.downloadCancelled) fail('已取消下载');
          else if (Date.now() > deadline) fail('音色下载超时，请重试');
        }, 300);
        client.requestInStream(url, {
          method: http.RequestMethod.GET, connectTimeout: 20000, readTimeout: 60000, usingProxy: false
        }).then((status: number): void => {
          if (status !== 200) { fail(`音色下载失败（${status}）`); return; }
          accepted = true;
          complete();
        }).catch((): void => { fail('音色下载失败，请检查网络后重试'); });
      });
      const hash = LocalTtsModels.hex(digest.digestSync().data);
      if (hash !== file.sha256) throw new Error('音色文件校验失败，请重试');
      completed = true;
    } finally {
      if (timer >= 0) clearInterval(timer);
      try { client.off('dataReceive'); client.off('dataEnd'); client.destroy(); } catch (_) {}
      await fs.close(output);
      if (completed) {
        await fs.rename(temp, path);
      } else {
        try { fs.unlinkSync(temp); } catch (_) {}
      }
    }
  }

  private static async fileHash(path: string): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256');
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(1024 * 1024);
      while (true) {
        const count = await fs.read(file.fd, buffer);
        if (count <= 0) break;
        await digest.update({ data: new Uint8Array(buffer, 0, count) });
      }
    } finally {
      await fs.close(file);
    }
    return LocalTtsModels.hex((await digest.digest()).data);
  }

  private static hex(bytes: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) hex += bytes[i].toString(16).padStart(2, '0');
    return hex;
  }
}
