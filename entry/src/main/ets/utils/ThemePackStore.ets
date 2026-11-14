import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import hash from '@ohos.file.hash';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { InstalledThemePack, ThemePackRecord, ThemePackRegistry } from '../theme/ThemePackRegistry';
import {
  assetPath,
  checkSvgSource,
  isValidPackageId,
  kindForExtension,
  maxBytesForKind,
  partsAssetRefs,
  sniffAssetExtension,
  ThemePackageAssetKinds,
  ThemePackageParts
} from '../theme/share/ThemePackageFormat';

/**
 * 主题包素材的落盘与冷启动加载：files/theme_packs/<packageId>/{pack.json, assets/...}。
 * 冷启动时在读取主题设置之前把所有包注册进 ThemePackRegistry，方案里的 pack: 来源才能解析。
 */
export class ThemePackStore {
  static readonly DIR_NAME: string = 'theme_packs';
  static readonly RECORD_FILE: string = 'pack.json';
  private static loaded: boolean = false;

  static rootDir(context: Context): string {
    return `${context.filesDir}/${ThemePackStore.DIR_NAME}`;
  }

  static packDir(context: Context, packageId: string): string {
    return `${ThemePackStore.rootDir(context)}/${packageId}`;
  }

  /** 读取已安装的全部主题包并注册；记录损坏或素材缺失的包跳过。返回注册数量。 */
  static async loadInstalled(context: Context): Promise<number> {
    const root = ThemePackStore.rootDir(context);
    let names: string[] = [];
    try {
      if (fs.accessSync(root)) names = fs.listFileSync(root);
    } catch (_) {
      names = [];
    }
    let count = 0;
    for (const name of names) {
      if (!isValidPackageId(name)) continue;
      try {
        const installed = ThemePackStore.readInstalled(context, name);
        if (installed) {
          ThemePackRegistry.register(installed);
          count++;
        }
      } catch (e) {
        console.warn(`加载主题包 ${name} 失败:`, (e as Error).message);
      }
    }
    ThemePackStore.loaded = true;
    return count;
  }

  static isLoaded(): boolean {
    return ThemePackStore.loaded;
  }

  /**
   * 安装：assets 已经按 record.parts 里的相对路径放进 dir/assets，这里只写记录并注册。
   * 同一个 packageId 再次安装时整个替换。
   */
  static install(context: Context, record: ThemePackRecord): InstalledThemePack {
    const dir = ThemePackStore.packDir(context, record.packageId);
    ThemePackStore.writeText(`${dir}/${ThemePackStore.RECORD_FILE}`, JSON.stringify(record));
    const installed = ThemePackStore.readInstalled(context, record.packageId);
    if (!installed) {
      throw new Error('主题包安装后无法读取');
    }
    ThemePackRegistry.register(installed);
    return installed;
  }

  /** 新安装前准备空目录：旧版本的素材全部清掉。 */
  static prepareDir(context: Context, packageId: string): string {
    const dir = ThemePackStore.packDir(context, packageId);
    ThemePackStore.removeDir(dir);
    // 旧目录删除失败时仍会留着，递归 mkdir 对已存在目录会报 File exists。
    if (!ThemePackStore.exists(`${dir}/assets`)) fs.mkdirSync(`${dir}/assets`, true);
    return dir;
  }

  static uninstall(context: Context, packageId: string): void {
    ThemePackRegistry.unregister(packageId);
    ThemePackStore.removeDir(ThemePackStore.packDir(context, packageId));
  }

  /** 删掉没有任何方案再引用的包（注册表里的和只剩目录的都算）。 */
  static uninstallUnreferenced(context: Context, referenced: Set<string>): void {
    const root = ThemePackStore.rootDir(context);
    let names: string[] = [];
    try {
      if (fs.accessSync(root)) names = fs.listFileSync(root);
    } catch (_) {
      names = [];
    }
    for (const name of names) {
      if (!referenced.has(name)) ThemePackStore.uninstall(context, name);
    }
    for (const pack of ThemePackRegistry.all()) {
      if (!referenced.has(pack.packageId)) ThemePackRegistry.unregister(pack.packageId);
    }
  }

  /** 读包目录里的记录；没有或损坏返回 null。返回的是新对象，可以改完再 install()。 */
  static readRecord(context: Context, packageId: string): ThemePackRecord | null {
    const dir = ThemePackStore.packDir(context, packageId);
    const recordPath = `${dir}/${ThemePackStore.RECORD_FILE}`;
    if (!ThemePackStore.exists(recordPath)) return null;
    let parsed: ThemePackRecord | null = null;
    try {
      parsed = JSON.parse(fs.readTextSync(recordPath)) as ThemePackRecord;
    } catch (_) {
      return null;
    }
    if (!parsed || parsed.packageId !== packageId || !parsed.parts) return null;
    const record = new ThemePackRecord();
    record.packageId = packageId;
    record.name = parsed.name || '导入的主题';
    record.author = parsed.author || '';
    record.version = parsed.version || '';
    record.description = parsed.description || '';
    record.baseTheme = parsed.baseTheme || '';
    record.installedAt = parsed.installedAt || 0;
    record.credits = parsed.credits || null;
    record.navFallbackIconPackId = parsed.navFallbackIconPackId || '';
    record.homeBackdropFallbackLight = parsed.homeBackdropFallbackLight || '';
    record.homeBackdropFallbackDark = parsed.homeBackdropFallbackDark || '';
    record.parts = ThemePackStore.normalizeParts(parsed.parts);
    return record;
  }

  /**
   * 把用户选的文件收进包目录：按文件头认类型、查大小上限、SVG 查自包含，按内容哈希命名（重复文件只存一份）。
   * 返回包内相对路径（assets/<id>.<ext>）；类型不在 kinds 里时抛错。
   */
  static async importAsset(context: Context, packageId: string, sourceUri: string, kinds: string[],
    label: string): Promise<string> {
    const dir = ThemePackStore.packDir(context, packageId);
    // mkdirSync 的递归模式对已存在的目录会报 File exists。
    if (!ThemePackStore.exists(`${dir}/assets`)) fs.mkdirSync(`${dir}/assets`, true);
    const temp = `${dir}/assets/.incoming_${Date.now()}`;
    if (sourceUri.startsWith('/')) {
      // 应用沙箱里的文件（取景裁出来的图）：fs.copy 对沙箱路径的 URI 会报 EINVAL，直接按路径复制。
      fs.copyFileSync(sourceUri, temp);
    } else {
      await fs.copy(sourceUri, fileUri.getUriFromPath(temp));
    }
    try {
      const size = fs.statSync(temp).size;
      const extension = sniffAssetExtension(ThemePackStore.readHead(temp));
      const kind = kindForExtension(extension);
      if (!kind || !kinds.includes(kind)) {
        throw new Error(kinds.includes(ThemePackageAssetKinds.VECTOR) && kinds.length === 1 ?
          `${label}需要 SVG 文件` : `${label}的图片格式不支持`);
      }
      if (size <= 0 || size > maxBytesForKind(kind)) {
        throw new Error(`${label}超过大小上限`);
      }
      if (kind === ThemePackageAssetKinds.VECTOR) {
        const problem = checkSvgSource(fs.readTextSync(temp));
        if (problem) throw new Error(`${label}：${problem}`);
      }
      const digest = (await hash.hash(temp, 'sha256')).toLowerCase();
      const relativePath = assetPath(digest.substring(0, 24), extension);
      const target = `${dir}/${relativePath}`;
      if (ThemePackStore.exists(target)) {
        fs.unlinkSync(temp);
      } else {
        fs.moveFileSync(temp, target);
      }
      return relativePath;
    } catch (e) {
      try {
        if (ThemePackStore.exists(temp)) fs.unlinkSync(temp);
      } catch (_) {
      }
      throw e as Error;
    }
  }

  /** 复制方案时连素材包一起复制成新包（素材文件照搬，记录换成新 ID），两套方案以后各改各的。 */
  static copyPack(context: Context, sourcePackageId: string, targetPackageId: string): ThemePackRecord | null {
    const record = ThemePackStore.readRecord(context, sourcePackageId);
    if (!record) return null;
    const sourceDir = `${ThemePackStore.packDir(context, sourcePackageId)}/assets`;
    const targetDir = ThemePackStore.prepareDir(context, targetPackageId);
    for (const relativePath of partsAssetRefs(record.parts)) {
      const name = relativePath.substring('assets/'.length);
      if (!name || name.includes('/') || name.includes('..')) continue;
      const source = `${sourceDir}/${name}`;
      const target = `${targetDir}/assets/${name}`;
      if (ThemePackStore.exists(source) && !ThemePackStore.exists(target)) fs.copyFileSync(source, target);
    }
    record.packageId = targetPackageId;
    record.installedAt = Date.now();
    ThemePackStore.install(context, record);
    return record;
  }

  /** 删掉 assets/ 里没有任何部件再引用的文件。 */
  static pruneAssets(context: Context, record: ThemePackRecord): void {
    const dir = `${ThemePackStore.packDir(context, record.packageId)}/assets`;
    const referenced = new Set<string>(partsAssetRefs(record.parts));
    let names: string[] = [];
    try {
      if (fs.accessSync(dir)) names = fs.listFileSync(dir);
    } catch (_) {
      return;
    }
    for (const name of names) {
      if (!referenced.has(`assets/${name}`)) {
        try {
          fs.unlinkSync(`${dir}/${name}`);
        } catch (_) {
        }
      }
    }
  }

  private static readHead(path: string): Uint8Array {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(16);
      const read = fs.readSync(file.fd, buffer, { offset: 0, length: 16 });
      return new Uint8Array(buffer, 0, read);
    } finally {
      fs.closeSync(file);
    }
  }

  private static readInstalled(context: Context, packageId: string): InstalledThemePack | null {
    const dir = ThemePackStore.packDir(context, packageId);
    const record = ThemePackStore.readRecord(context, packageId);
    if (!record) return null;
    const base = BuiltinThemeRegistry.findById(BuiltinThemeRegistry.normalizeBuiltinId(record.baseTheme));
    const installed = ThemePackRegistry.build(record, base, (relativePath: string): string => {
      // 只认包目录下 assets/ 里的文件；丢失的素材当作没带，回退到基底主题。
      if (!relativePath.startsWith('assets/') || relativePath.includes('..')) return '';
      const path = `${dir}/${relativePath}`;
      return ThemePackStore.exists(path) ? fileUri.getUriFromPath(path) : '';
    });
    installed.dir = dir;
    return installed;
  }

  /** JSON 里的 parts 是普通对象；补齐缺省字段，缺失的子节保持 null。 */
  private static normalizeParts(source: ThemePackageParts): ThemePackageParts {
    const parts = new ThemePackageParts();
    parts.light = source.light || null;
    parts.dark = source.dark || null;
    parts.ttsPanelLight = source.ttsPanelLight || null;
    parts.ttsPanelDark = source.ttsPanelDark || null;
    parts.navigation = source.navigation || null;
    parts.book = source.book || null;
    if (parts.book && !Array.isArray(parts.book.covers)) parts.book.covers = [];
    if (parts.book && !Array.isArray(parts.book.coverCrops)) parts.book.coverCrops = [];
    if (parts.book && !Array.isArray(parts.book.coversDark)) parts.book.coversDark = [];
    if (parts.book && !Array.isArray(parts.book.coverCropsDark)) parts.book.coverCropsDark = [];
    if (parts.book && !parts.book.shelfFolderCrop) parts.book.shelfFolderCrop = null;
    if (parts.book && !parts.book.shelfFolderDark) parts.book.shelfFolderDark = '';
    if (parts.book && !parts.book.shelfFolderCropDark) parts.book.shelfFolderCropDark = null;
    parts.startupLight = source.startupLight || null;
    parts.startupDark = source.startupDark || null;
    parts.bubble = source.bubble || null;
    parts.homeBackdropLight = source.homeBackdropLight || '';
    parts.homeBackdropDark = source.homeBackdropDark || '';
    parts.homeBackdropLightCrop = source.homeBackdropLightCrop || null;
    parts.homeBackdropDarkCrop = source.homeBackdropDarkCrop || null;
    parts.shelfBackdrops = Array.isArray(source.shelfBackdrops) ? source.shelfBackdrops : [];
    parts.logo = source.logo || '';
    parts.preview = source.preview || '';
    parts.radius = source.radius || null;
    parts.appFont = source.appFont || '';
    parts.appFontFamily = source.appFontFamily || '';
    return parts;
  }

  static exists(path: string): boolean {
    try {
      return !!path && fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private static writeText(path: string, text: string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
  }

  private static removeDir(path: string): void {
    try {
      if (path && fs.accessSync(path)) fs.rmdirSync(path);
    } catch (e) {
      console.warn('清理主题包目录失败:', (e as Error).message);
    }
  }
}
