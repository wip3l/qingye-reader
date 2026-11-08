import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import zlib from '@ohos.zlib';
import { ZipEntryInfo, ZipEntryInspector, ZipInspectLimits } from '../../theme/share/ZipEntryInspector';
import { LocalTtsModel, LocalTtsModelFile, LocalTtsModels } from './LocalTtsModels';
import { LocalTtsSpeakers } from './LocalTtsSpeakers';

class ImportedFile {
  path: string = '';
  bytes: number = 0;

  constructor(path: string, bytes: number) {
    this.path = path;
    this.bytes = bytes;
  }
}

/**
 * 用户导入自己的 sherpa-onnx 模型（只收 zip）。按包里的文件名识别结构：
 *  - VITS / Piper：一个 .onnx + tokens.txt + lexicon.txt 或 espeak-ng-data/
 *  - Matcha：声学模型 + 声码器（文件名含 vocos / hifigan / vocoder）
 *  - Kokoro：带 voices.bin
 * 不兼容的模型可能在加载时让进程直接退出（原生层 abort），LocalTtsModels 的 loading 标记会在
 * 下次启动时把它停用，所以这里只做“文件齐不齐”的检查，不尝试试加载。
 */
export class LocalTtsImport {
  private static readonly MAX_ZIP_BYTES: number = 1024 * 1024 * 1024;
  private static readonly MAX_UNCOMPRESSED: number = 1536 * 1024 * 1024;
  private static readonly MAX_ENTRY: number = 900 * 1024 * 1024;
  private static readonly MAX_ENTRIES: number = 4000;
  private static busy: boolean = false;

  static isBusy(): boolean {
    return LocalTtsImport.busy;
  }

  /** 选择 zip；取消时返回空串。 */
  static async pick(context: Context): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['模型压缩包|.zip'];
    const result = await new picker.DocumentViewPicker(context).select(options);
    return result && result.length > 0 ? result[0] : '';
  }

  static async importZip(context: Context, uri: string, stage: (text: string) => void): Promise<LocalTtsModel> {
    if (!LocalTtsModels.memberAllowed()) throw new Error(LocalTtsModels.MEMBER_REQUIRED);
    if (LocalTtsImport.busy) throw new Error('正在导入其他模型');
    LocalTtsImport.busy = true;
    const workDir = `${context.tempDir}/local_tts_import_${Date.now()}`;
    let step = '读取文件';
    try {
      fs.mkdirSync(workDir, true);
      stage('正在读取压缩包');
      const zipPath = `${workDir}/source.zip`;
      await fs.copy(uri.startsWith('/') ? fileUri.getUriFromPath(uri) : uri, fileUri.getUriFromPath(zipPath));
      const size = fs.statSync(zipPath).size;
      if (size > LocalTtsImport.MAX_ZIP_BYTES) throw new Error('压缩包超过 1GB，无法导入');
      step = '检查压缩包';
      const entries = LocalTtsImport.inspect(zipPath, size);
      const root = ZipEntryInspector.commonRoot(entries);
      step = '解压';
      stage('正在解压');
      const outDir = `${workDir}/out`;
      fs.mkdirSync(outDir, true);
      await zlib.decompressFile(zipPath, outDir);
      fs.unlinkSync(zipPath);
      const baseDir = root ? `${outDir}/${root.substring(0, root.length - 1)}` : outDir;
      step = '识别模型';
      stage('正在识别模型');
      const model = LocalTtsImport.detect(baseDir, LocalTtsImport.displayName(uri));
      LocalTtsImport.dropUnused(baseDir, model);
      step = '保存';
      stage('正在保存');
      const folder = model.id;
      model.dirName = `${LocalTtsModels.USER_DIR}/${folder}`;
      const userRoot = `${LocalTtsModels.rootDir(context)}/${LocalTtsModels.USER_DIR}`;
      LocalTtsModels.ensureDir(userRoot);
      const target = `${userRoot}/${folder}`;
      try {
        fs.renameSync(baseDir, target);
      } catch (_) {
        fs.copyDirSync(baseDir, userRoot, 1);
        const copied = `${userRoot}/${baseDir.substring(baseDir.lastIndexOf('/') + 1)}`;
        if (copied !== target) fs.renameSync(copied, target);
      }
      LocalTtsModels.registerImported(target, model);
      return LocalTtsModels.all().find((item: LocalTtsModel): boolean =>
        item.importId === model.id && item.sid === model.sid) || model;
    } catch (error) {
      const message = ((error as Error).message || String(error)).replace(/主题包/g, '压缩包');
      throw new Error(message.startsWith('模型') || message.startsWith('压缩包') || message.startsWith('缺少') ||
        message.startsWith('这个') || message.startsWith('离线') ? message : `导入失败（${step}）：${message}`);
    } finally {
      LocalTtsImport.busy = false;
      try { fs.rmdirSync(workDir); } catch (_) {}
    }
  }

  private static inspect(zipPath: string, size: number): ZipEntryInfo[] {
    const file = fs.openSync(zipPath, fs.OpenMode.READ_ONLY);
    try {
      const limits = new ZipInspectLimits();
      limits.maxEntries = LocalTtsImport.MAX_ENTRIES;
      limits.maxTotalUncompressed = LocalTtsImport.MAX_UNCOMPRESSED;
      limits.maxEntryUncompressed = LocalTtsImport.MAX_ENTRY;
      return ZipEntryInspector.inspect(size, (offset: number, length: number): Uint8Array => {
        const buffer = new ArrayBuffer(length);
        const read = fs.readSync(file.fd, buffer, { offset: offset, length: length });
        return new Uint8Array(buffer, 0, read);
      }, limits);
    } finally {
      fs.closeSync(file);
    }
  }

  private static displayName(uri: string): string {
    let name = uri.substring(uri.lastIndexOf('/') + 1);
    try { name = decodeURIComponent(name); } catch (_) {}
    name = name.replace(/\.zip$/i, '').trim();
    return name.length > 40 ? name.substring(0, 40) : (name || '导入的音色');
  }

  private static listTop(dir: string): ImportedFile[] {
    const files: ImportedFile[] = [];
    for (const name of fs.listFileSync(dir)) {
      const stat = fs.statSync(`${dir}/${name}`);
      if (stat.isFile()) files.push(new ImportedFile(name, stat.size));
    }
    return files;
  }

  private static isDir(path: string): boolean {
    try { return fs.accessSync(path) && fs.statSync(path).isDirectory(); } catch (_) { return false; }
  }

  /** 按文件名判断模型结构，组装出要交给引擎的文件清单。 */
  static detect(dir: string, name: string): LocalTtsModel {
    const files = LocalTtsImport.listTop(dir);
    const names = files.map((file: ImportedFile): string => file.path);
    const lower = (value: string): string => value.toLowerCase();
    if (!names.includes('tokens.txt')) {
      throw new Error('缺少 tokens.txt，这不像 sherpa-onnx 的语音合成模型');
    }
    const onnx = names.filter((item: string): boolean => lower(item).endsWith('.onnx'));
    if (onnx.length === 0) throw new Error('缺少 .onnx 模型文件');
    if (onnx.some((item: string): boolean => /encoder|decoder|flow|text_conditioner/i.test(item))) {
      throw new Error('这个模型需要参考音频或多段网络，暂不支持');
    }
    const vocoders = onnx.filter((item: string): boolean => /vocos|hifigan|vocoder/i.test(item));
    const acoustic = onnx.filter((item: string): boolean => !vocoders.includes(item));
    // int8 量化在这个运行库上反而更慢，fp16 根本加载不了：有 fp32 版就用 fp32。
    const usable = acoustic.filter((item: string): boolean => !/fp16/i.test(item));
    if (usable.length === 0) throw new Error('这个运行库不支持 fp16 模型，请换 fp32 版本');
    const preferred = usable.filter((item: string): boolean => !/int8/i.test(item));
    const candidates = preferred.length > 0 ? preferred : usable;
    const pickMain = (): string => {
      if (candidates.includes('model.onnx')) return 'model.onnx';
      if (candidates.length > 1) {
        const sizes = candidates.map((item: string): number =>
          files.find((file: ImportedFile): boolean => file.path === item)?.bytes || 0);
        let best = 0;
        for (let i = 1; i < sizes.length; i++) if (sizes[i] > sizes[best]) best = i;
        return candidates[best];
      }
      return candidates[0];
    };

    const model = new LocalTtsModel();
    model.id = `user-${Date.now()}`;
    model.name = name;
    model.imported = true;
    model.modelFile = pickMain();
    model.dataDir = LocalTtsImport.isDir(`${dir}/espeak-ng-data`) ? 'espeak-ng-data' : '';
    model.ruleFsts = names.filter((item: string): boolean => lower(item).endsWith('.fst')).sort();

    if (names.includes('voices.bin')) {
      model.kind = 'kokoro';
      model.voicesFile = 'voices.bin';
      const order = ['lexicon-us-en.txt', 'lexicon-gb-en.txt', 'lexicon-zh.txt'];
      model.lexicons = names.filter((item: string): boolean => /^lexicon.*\.txt$/i.test(item))
        .sort((a: string, b: string): number => (order.indexOf(a) + 99 * Number(order.indexOf(a) < 0)) -
          (order.indexOf(b) + 99 * Number(order.indexOf(b) < 0)));
      // 多语言 kokoro 里英文词典有两份，同时传会互相覆盖，只留美式。
      if (model.lexicons.includes('lexicon-us-en.txt')) {
        model.lexicons = model.lexicons.filter((item: string): boolean => item !== 'lexicon-gb-en.txt');
      }
      if (!model.dataDir) throw new Error('Kokoro 模型缺少 espeak-ng-data 目录');
    } else if (vocoders.length > 0 || /matcha|model-steps/i.test(model.modelFile)) {
      model.kind = 'matcha';
      if (vocoders.length === 0) {
        throw new Error('Matcha 模型缺少声码器（如 vocos-22khz-univ.onnx），请放进同一个压缩包');
      }
      model.vocoderFile = vocoders[0];
      model.lexicons = names.includes('lexicon.txt') ? ['lexicon.txt'] : [];
      if (model.lexicons.length === 0 && !model.dataDir) {
        throw new Error('缺少 lexicon.txt 或 espeak-ng-data 目录');
      }
    } else {
      model.kind = 'vits';
      model.lexicons = names.includes('lexicon.txt') ? ['lexicon.txt'] : [];
      if (model.lexicons.length === 0 && !model.dataDir) {
        throw new Error('缺少 lexicon.txt 或 espeak-ng-data 目录');
      }
    }

    const referenced: string[] = [model.modelFile, 'tokens.txt'];
    if (model.vocoderFile) referenced.push(model.vocoderFile);
    if (model.voicesFile) referenced.push(model.voicesFile);
    referenced.push(...model.lexicons, ...model.ruleFsts);
    model.files = referenced.map((item: string): LocalTtsModelFile =>
      new LocalTtsModelFile(item, files.find((file: ImportedFile): boolean => file.path === item)?.bytes || 0, ''));
    if (model.dataDir) {
      const phontab = `${dir}/${model.dataDir}/phontab`;
      if (!fs.accessSync(phontab)) throw new Error('espeak-ng-data 目录不完整（缺少 phontab）');
      model.files.push(new LocalTtsModelFile(`${model.dataDir}/phontab`, fs.statSync(phontab).size, ''));
    }
    const speakers = LocalTtsSpeakers.detect(dir, model.modelFile, model.kind, model.voicesFile);
    model.speakers = speakers.count;
    model.speakerNames = speakers.names;
    model.sid = LocalTtsSpeakers.defaultSid(speakers);
    return model;
  }

  /** 没用上的大文件（同一模型的 int8/fp16 副本、上百 MB 的 rule.far）不保留，省存储。 */
  private static dropUnused(dir: string, model: LocalTtsModel): void {
    const keep = model.files.map((file: LocalTtsModelFile): string => file.name);
    for (const name of fs.listFileSync(dir)) {
      const lower = name.toLowerCase();
      if ((lower.endsWith('.onnx') || lower.endsWith('.far')) && !keep.includes(name)) {
        try { fs.unlinkSync(`${dir}/${name}`); } catch (_) {}
      }
    }
  }
}
