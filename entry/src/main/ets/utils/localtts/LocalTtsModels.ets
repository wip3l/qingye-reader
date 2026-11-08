import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import util from '@ohos.util';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { TtsVoiceAvailability } from '../TtsVoiceAvailability';
import { LocalTtsSpeakerInfo, LocalTtsSpeakers } from './LocalTtsSpeakers';

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
  /** 以下仅内置模型用。下载来源仓库，空则用模型的 repo。 */
  repo: string = '';
  /** 仓库里的路径，空则与 name 相同。 */
  remotePath: string = '';
  /** 固定到某个提交，免得上游改动文件后哈希对不上；空则用 main。 */
  revision: string = '';
  /**
   * 下载后要追加进 ONNX 的元数据（key=value）。有些上游模型元数据不全，sherpa-onnx 会选错前端，
   * 而元数据在 ModelProto 末尾追加一个字段即可补上，不必另找地方托管改过的文件。
   * 设置了它时 bytes/sha256 是补完后的值，sourceBytes/sourceSha256 是上游原文件的值。
   */
  onnxMeta: string = '';
  sourceBytes: number = 0;
  sourceSha256: string = '';

  constructor(name: string, bytes: number, sha256: string) {
    this.name = name;
    this.bytes = bytes;
    this.sha256 = sha256;
  }

  static from(repo: string, name: string, bytes: number, sha256: string): LocalTtsModelFile {
    const file = new LocalTtsModelFile(name, bytes, sha256);
    file.repo = repo;
    return file;
  }

  downloadBytes(): number {
    return this.onnxMeta ? this.sourceBytes : this.bytes;
  }

  downloadSha256(): string {
    return this.onnxMeta ? this.sourceSha256 : this.sha256;
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
  /** VITS 噪声参数；0 表示用 sherpa-onnx 默认值。Piper 模型按其 .onnx.json 里的推荐值填。 */
  noiseScale: number = 0;
  noiseScaleW: number = 0;
  /**
   * 同一个多说话人模型拆成的几个内置音色共用 pack（目录与文件也相同）：下载一次全部可用，删除也一起删。
   * 没下载时音色管理只显示一行音色包，标题用 packTitle。
   */
  pack: string = '';
  packTitle: string = '';
  imported: boolean = false;
  /**
   * 以下仅导入的模型用。一个多说话人模型可以添加其中几个说话人，各占一行音色，共用同一目录
   * （pack 设为 importId，删除时整包删）。speakers 是模型里的说话人总数，未知时为 1。
   */
  importId: string = '';
  importName: string = '';
  speakers: number = 1;
  speakerNames: string[] = [];
  /** 这个导入包里已添加的说话人编号，同包各行相同。 */
  importedSids: number[] = [];
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
  /** 模型里的说话人总数与名字；缺省表示旧版导入、还没检测过。 */
  speakers?: number;
  speakerNames?: string[];
  /** 已添加的说话人编号；缺省时只有 sid。 */
  sids?: number[];
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

  static readonly CATALOG: LocalTtsModel[] = [LocalTtsModels.chaowen(), LocalTtsModels.huayan()]
    .concat(LocalTtsModels.aishell3Voices());

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

  /**
   * Piper 版 AISHELL-3（174 个说话人，22.05kHz），数据集与模型都是 Apache-2.0。
   * 但它从 en_US libritts_r（LibriTTS-R，CC BY 4.0）热启动，后者又源自 en_US lessac，
   * 而 Lessac 数据集许可禁止商用；权重是否继承该限制没有定论，许可声明里已写明这条来源链。
   * 它与超文用同一套拼音音素表（85 个符号逐一相同），所以词典、tokens、规则文件直接取超文仓库的；
   * 上游 onnx 的元数据缺 has_g2pw=1，不补的话 sherpa-onnx 会退回通用词典前端，读音全错。
   * 说话人按语音识别错字率从 174 个里挑，男女各取几个音高不同的；噪声参数取模型推荐的 0.333
   * （默认的 0.667/0.8 错字率明显更高）。
   */
  private static aishell3Voices(): LocalTtsModel[] {
    const voices: string[][] = [
      ['14', '青岩', '男声 · 低沉'], ['124', '远舟', '男声 · 沉稳'], ['111', '子墨', '男声 · 温和'],
      ['43', '清朗', '男声 · 清亮'], ['118', '晚晴', '女声 · 知性'], ['25', '知夏', '女声 · 温柔'],
      ['52', '若溪', '女声 · 自然'], ['51', '星语', '女声 · 明快'], ['138', '小棠', '女声 · 甜美'],
      ['88', '安然', '女声 · 清脆']
    ];
    const lexiconRepo = 'csukuangfj2/vits-piper-zh_CN-chaowen-medium';
    return voices.map((voice: string[]): LocalTtsModel => {
      const model = new LocalTtsModel();
      model.id = `piper-zh-aishell3-${voice[0]}`;
      model.name = voice[1];
      model.description = voice[2];
      model.sid = Number(voice[0]);
      model.pack = 'piper-zh-aishell3';
      model.packTitle = `多人音色包 · 普通话 ${voices.length} 个音色`;
      model.dirName = 'vits-piper-zh_CN-aishell3-medium';
      model.repo = 'writeAPoemForYou/piper-voices-zh-AISHELL-3';
      model.kind = 'vits';
      model.modelFile = 'zh_CN-cn_aishell3-medium.onnx';
      model.lexicons = ['lexicon.txt'];
      model.ruleFsts = ['phone.fst', 'date.fst', 'number.fst'];
      model.noiseScale = 0.333;
      model.noiseScaleW = 0.333;
      const onnx = new LocalTtsModelFile('zh_CN-cn_aishell3-medium.onnx', 77639633,
        '22f09cc9f8667b37abe0b0bf8efe51e1be9bf4427929708ca1966ab5f575aa70');
      onnx.remotePath = 'zh/zh_CN/cn_aishell3/medium/zh_CN-cn_aishell3-medium.onnx';
      onnx.revision = 'be77d1b11c7bc242a6c897c513e1fd8f23aac0e3';
      onnx.onnxMeta = 'has_g2pw=1';
      onnx.sourceBytes = 77639618;
      onnx.sourceSha256 = 'f46e009dcfcaa0f8c5e6eefe23dabc36296c69123ea22df82d31078ab6e0174f';
      model.files = [
        onnx,
        LocalTtsModelFile.from(lexiconRepo, 'lexicon.txt', 2064505,
          '003e76f89fec389ec109b557f47cc315a1ac31a99091f0cc9d15949f9024416b'),
        LocalTtsModelFile.from(lexiconRepo, 'tokens.txt', 485,
          'e9e6d2838a2676749adbf0376c4cf3c3cd28eb27ed953dcc2adcab8db3c33ba7'),
        LocalTtsModelFile.from(lexiconRepo, 'date.fst', 59154,
          'eb8aa079ae3cb81d8f4404992f39d61a0cb990947512b5b8d1e54d1f6980e718'),
        LocalTtsModelFile.from(lexiconRepo, 'number.fst', 64482,
          '743f402181fcfebf76cc2f0546b71fa26476e626fbe4e460fb7b4c3a7a8bd5bd'),
        LocalTtsModelFile.from(lexiconRepo, 'phone.fst', 88630,
          '1ac2b6fa56b1442320c4de7db08353bab8963a2b57f365eebcdd3a2d3562f8d7')
      ];
      return model;
    });
  }

  /** 同一音色包里的全部音色（内置音色包或同一个导入的多说话人模型）；不属于音色包时只有它自己。 */
  static packMembers(model: LocalTtsModel): LocalTtsModel[] {
    if (!model.pack) return [model];
    return LocalTtsModels.all().filter((item: LocalTtsModel): boolean => item.pack === model.pack);
  }

  /** 音色管理里没下载的音色包只显示第一个音色那一行。 */
  static isPackLead(model: LocalTtsModel): boolean {
    return !model.pack || LocalTtsModels.packMembers(model)[0].id === model.id;
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
          models.push(...LocalTtsModels.readManifest(`${userRoot}/${name}`, name));
        }
      }
    } catch (error) {
      console.warn('[LocalTts] load imported models failed:', error);
    }
    LocalTtsModels.userModels = models;
  }

  /** 一个导入目录展开成若干音色：每个已添加的说话人一行。描述损坏时返回空数组。 */
  private static readManifest(dir: string, folder: string): LocalTtsModel[] {
    try {
      const path = `${dir}/${LocalTtsModels.USER_MANIFEST}`;
      if (!fs.accessSync(path) || fs.statSync(path).size > 256 * 1024) return [];
      const raw = JSON.parse(fs.readTextSync(path)) as LocalTtsModelManifest;
      const base = new LocalTtsModel();
      base.importId = String(raw.id || '');
      base.importName = String(raw.name || '导入的音色');
      base.kind = String(raw.kind || 'vits');
      base.modelFile = String(raw.modelFile || '');
      base.vocoderFile = String(raw.vocoderFile || '');
      base.voicesFile = String(raw.voicesFile || '');
      base.lexicons = Array.isArray(raw.lexicons) ? raw.lexicons.map((item: string): string => String(item)) : [];
      base.dataDir = String(raw.dataDir || '');
      base.ruleFsts = Array.isArray(raw.ruleFsts) ? raw.ruleFsts.map((item: string): string => String(item)) : [];
      base.files = Array.isArray(raw.files) ? raw.files.map((item: LocalTtsModelFile): LocalTtsModelFile =>
        new LocalTtsModelFile(String(item.name || ''), Number(item.bytes) || 0, '')) : [];
      base.imported = true;
      base.dirName = `${LocalTtsModels.USER_DIR}/${folder}`;
      if (!base.importId.startsWith('user-') || !base.modelFile || base.files.length === 0) return [];
      if (raw.speakers === undefined) {
        // 旧版导入没记说话人数，补检测一次写回描述，之后不再读模型文件。
        const info = LocalTtsSpeakers.detect(dir, base.modelFile, base.kind, base.voicesFile);
        raw.speakers = info.count;
        raw.speakerNames = info.names;
        LocalTtsModels.writeText(path, JSON.stringify(raw));
      }
      base.speakers = Math.max(1, Math.floor(Number(raw.speakers) || 1));
      base.speakerNames = Array.isArray(raw.speakerNames) && raw.speakerNames.length === base.speakers ?
        raw.speakerNames.map((item: string): string => String(item)) : [];
      const legacySid = Math.max(0, Math.floor(Number(raw.sid) || 0));
      const sids = (Array.isArray(raw.sids) ? raw.sids : [legacySid])
        .map((item: number): number => Math.floor(Number(item)))
        .filter((item: number, index: number, list: number[]): boolean =>
          Number.isFinite(item) && item >= 0 && item < base.speakers && list.indexOf(item) === index);
      base.importedSids = sids.length > 0 ? sids : [Math.min(legacySid, base.speakers - 1)];
      return base.importedSids.map((sid: number): LocalTtsModel => LocalTtsModels.speakerVariant(base, sid));
    } catch (error) {
      console.warn('[LocalTts] bad imported model manifest:', error);
      return [];
    }
  }

  /**
   * 导入模型某个说话人的音色。0 号沿用导入时的 id（旧版导入只有它，已选中的设置不失效），
   * 其他说话人在后面加编号。也用来试听还没添加的说话人。
   */
  static speakerVariant(base: LocalTtsModel, sid: number): LocalTtsModel {
    const model = new LocalTtsModel();
    model.importId = base.importId;
    model.importName = base.importName;
    model.id = sid === 0 ? base.importId : `${base.importId}-s${sid}`;
    model.kind = base.kind;
    model.modelFile = base.modelFile;
    model.vocoderFile = base.vocoderFile;
    model.voicesFile = base.voicesFile;
    model.lexicons = base.lexicons;
    model.dataDir = base.dataDir;
    model.ruleFsts = base.ruleFsts;
    model.files = base.files;
    model.imported = true;
    model.dirName = base.dirName;
    model.speakers = base.speakers;
    model.speakerNames = base.speakerNames;
    model.importedSids = base.importedSids;
    model.sid = sid;
    const kind = LocalTtsModels.kindLabel(model.kind);
    if (model.speakers <= 1) {
      model.name = model.importName;
      model.description = `导入 · ${kind}`;
      return model;
    }
    const info = LocalTtsModels.speakerInfo(model);
    model.pack = model.importId;
    model.packTitle = model.importName;
    model.name = `${model.importName} ${LocalTtsSpeakers.title(info, sid)}`;
    const voice = LocalTtsSpeakers.describe(info.names[sid] || '');
    model.description = `导入 · ${kind}${voice ? ` · ${voice}` : ''}`;
    return model;
  }

  static speakerInfo(model: LocalTtsModel): LocalTtsSpeakerInfo {
    const info = new LocalTtsSpeakerInfo();
    info.count = model.speakers;
    info.names = model.speakerNames;
    return info;
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
      speakers: model.speakers,
      speakerNames: model.speakerNames,
      sids: [model.sid],
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

  /** 改导入模型里已添加的说话人（至少一个），只改描述文件。 */
  static setImportedSids(model: LocalTtsModel, sids: number[]): void {
    if (!model.imported || sids.length === 0) return;
    const dir = LocalTtsModels.modelPath(model);
    if (!dir) return;
    const path = `${dir}/${LocalTtsModels.USER_MANIFEST}`;
    try {
      const raw = JSON.parse(fs.readTextSync(path)) as LocalTtsModelManifest;
      raw.sids = sids.slice().sort((a: number, b: number): number => a - b);
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
      const total = model.files.reduce((sum: number, file: LocalTtsModelFile): number =>
        sum + file.downloadBytes(), 0);
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
          if (file.onnxMeta) await LocalTtsModels.applyOnnxMeta(path, file);
        }
        done += file.downloadBytes();
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

  /**
   * 在 ONNX 文件末尾追加一条 metadata_props（ModelProto 第 14 号字段，内容是 StringStringEntryProto）。
   * protobuf 允许字段出现在任意位置，追加即生效。追加后整体再校验一次哈希，对不上就删掉、下次重下。
   */
  private static async applyOnnxMeta(path: string, file: LocalTtsModelFile): Promise<void> {
    const pair = file.onnxMeta.split('=');
    const encoder = new util.TextEncoder();
    const key = encoder.encodeInto(pair[0]);
    const value = encoder.encodeInto(pair.slice(1).join('='));
    const inner: number[] = [0x0a, key.length].concat(Array.from(key))
      .concat([0x12, value.length]).concat(Array.from(value));
    if (inner.length > 127) throw new Error('音色元数据过长');
    const bytes = new Uint8Array([0x72, inner.length].concat(inner));
    const output = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.APPEND);
    try { fs.writeSync(output.fd, bytes.buffer); } finally { fs.closeSync(output); }
    if (fs.statSync(path).size !== file.bytes || await LocalTtsModels.fileHash(path) !== file.sha256) {
      try { fs.unlinkSync(path); } catch (_) {}
      throw new Error('音色文件校验失败，请重试');
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
        const repo = file.repo || model.repo;
        const url = `${host}/${repo}/resolve/${file.revision || 'main'}/${file.remotePath || file.name}`;
        await LocalTtsModels.downloadFrom(url, file, path, progress);
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
          if (received !== file.downloadBytes()) fail('音色文件下载不完整，请重试');
          else resolve();
        };
        client.on('dataReceive', (chunk: ArrayBuffer): void => {
          if (failure) return;
          if (LocalTtsModels.downloadCancelled) { fail('已取消下载'); return; }
          if (received + chunk.byteLength > file.downloadBytes()) { fail('音色文件大小异常'); return; }
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
      if (hash !== file.downloadSha256()) throw new Error('音色文件校验失败，请重试');
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
