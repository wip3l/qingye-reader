import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { fileUri } from '../platform/FileUri';
import zlib from '@ohos.zlib';
import hash from '@ohos.file.hash';
import preferences from '@ohos.data.preferences';
import { util } from '@kit.ArkTS';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { AccountSessionStore } from './AccountSessionStore';
import { CloudSyncSettingsStore } from './CloudSyncSettingsStore';
import { CloudSyncIssueStore } from './CloudSyncIssueStore';
import { CloudFileClient } from './CloudFileClient';
import { CloudFileItem, CloudFileMeta, CloudTombstone, CloudUploadJob } from './CloudFileModels';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../utils/CustomThemeSchemeStore';
import { ThemePackStore } from '../utils/ThemePackStore';
import { ThemePackRegistry } from '../theme/ThemePackRegistry';
import { ThemePackageService } from '../theme/share/ThemePackageService';
import { isValidPackageId } from '../theme/share/ThemePackageFormat';
import { ThemeIds } from '../theme/ThemeModels';

class ThemeSyncEntry {
  key: string = '';
  hash: string = '';
}

/** 每个账号一份：各主题上次与云端一致时的指纹，以及上次对账时本机还在用的主题。 */
class ThemeSyncState {
  synced: ThemeSyncEntry[] = [];
  refs: string[] = [];
}

class FileHashRecord {
  path: string = '';
  size: number = 0;
  mtime: number = 0;
  hash: string = '';
}

/** 方案图片包里的清单：三个位置各自的文件名，空表示没有。 */
class SchemeImageManifest {
  schemeId: string = '';
  light: string = '';
  dark: string = '';
  preview: string = '';
}

class PackHead {
  packageId: string = '';
}

/** 本机的一项自定义主题：主题包（pack:<id>）或一套方案的图片（scheme:<id>）。 */
class LocalThemeItem {
  key: string = '';
  packageId: string = '';
  schemeId: string = '';
  name: string = '';
  /** 内容指纹；本机没有内容（包没装、方案没有图片）时为空。 */
  hash: string = '';
  installed: boolean = false;
  /** 正在使用的方案用到的包，云端有新版本或本机缺包时立即下载。 */
  active: boolean = false;
}

/**
 * 终身超级会员的自定义主题云同步，搭在 CloudAutoSync 的云文件对账上：
 * - 每个被方案用到的主题包打成一个文件（meta.packageId），每套方案的启动封面与预览图打成一个文件（meta.schemeId）；
 * - 内容指纹记在 meta.contentHash，同一主题云端只留最新上传的一份；
 * - 本机改过、云端没变就上传；云端变了、或第一次在这台设备上对账、或两边都改了，以云端为准；
 * - 本机不用了（方案删了、换了包）就删云端副本，其他设备随方案列表同步自然卸掉；
 * - 正在使用的方案缺包时立即下载，其余方案的包在主题页标“云端”，应用或打开时再下载。
 * 方案设置本身仍走数据同步（custom_theme_schemes），这里只管图片等文件。
 */
export class CloudThemeSync {
  /** 云端有、本机还没下载的主题包 ID 列表（JSON），主题页据此显示“云端”。 */
  static readonly STORAGE_REMOTE_PACKS: string = 'cloudRemoteThemePacksRaw';
  static readonly KIND: string = 'THEME';
  private static readonly STORE: string = 'cloud_auto_sync';
  private static readonly SAFE_NAME: RegExp = /^[A-Za-z0-9._-]{1,120}$/;
  private static readonly CLOUD_IMAGE_PREFIX: string = 'qytheme_cloud_';
  private static remoteFiles: Map<string, CloudFileItem> = new Map<string, CloudFileItem>();
  private static downloads: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  /** 查过云端也没有的包：到下一轮对账前不再为它现查列表。 */
  private static absent: Set<string> = new Set<string>();

  /** 云文件或删除标记对应的主题键；不是主题文件时为空。 */
  static themeKey(meta: CloudFileMeta | null): string {
    if (meta?.packageId) return `pack:${meta.packageId}`;
    if (meta?.schemeId) return `scheme:${meta.schemeId}`;
    return '';
  }

  static remotePackageIds(): string[] {
    const raw = AppStorage.get<string>(CloudThemeSync.STORAGE_REMOTE_PACKS) || '';
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw) as string[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  /** 方案用到、本机没有、云端有的主题包。 */
  static remotePacksOf(scheme: CustomThemeScheme | null): string[] {
    if (!scheme) return [];
    const remote = CloudThemeSync.remotePackageIds();
    return CloudThemeSync.schemePackageIds(scheme).filter((id: string): boolean =>
      remote.includes(id) && !ThemePackRegistry.getByPackageId(id));
  }

  static clearRemote(): void {
    CloudThemeSync.remoteFiles.clear();
    CloudThemeSync.publishRemote([]);
  }

  /**
   * 对账一轮。files / tombstones 是本轮读到的云端列表，要上传的放进 uploads（由 CloudAutoSync 统一上传），
   * 下载和删除在这里直接做。
   */
  static async sync(context: Context, userId: string, files: CloudFileItem[], tombstones: CloudTombstone[],
    uploads: CloudUploadJob[]): Promise<void> {
    const state = await CloudThemeSync.loadState(context, userId);
    const synced = new Map<string, string>();
    for (const entry of state.synced) synced.set(entry.key, entry.hash);
    const local = await CloudThemeSync.collectLocal(context);
    const cloud = new Map<string, CloudFileItem>();
    const stale: CloudFileItem[] = [];
    for (const file of files) {
      if (file.kind !== CloudThemeSync.KIND) continue;
      const key = CloudThemeSync.themeKey(file.meta);
      if (!key) continue;
      const old = cloud.get(key);
      if (!old) {
        cloud.set(key, file);
      } else if (CloudThemeSync.newer(file, old)) {
        stale.push(old);
        cloud.set(key, file);
      } else {
        stale.push(file);
      }
    }
    // 同一主题被重新上传过：旧的几份不再需要。
    for (const file of stale) {
      try {
        await CloudFileClient.remove(file.id, 'DETACHED');
      } catch (e) {
        console.warn('[CloudThemeSync] remove old copy failed:', (e as Error).message);
      }
    }
    const tombs = tombstones.filter((tomb: CloudTombstone) => tomb.kind === CloudThemeSync.KIND);
    const remote: string[] = [];
    CloudThemeSync.remoteFiles.clear();
    CloudThemeSync.absent.clear();
    let downloadBlocked = '';
    const retry: string[] = [];
    const keys: string[] = Array.from(local.keys());
    for (const key of Array.from(cloud.keys())) {
      if (!local.has(key)) keys.push(key);
    }
    for (const key of keys) {
      if (AccountSessionStore.account().userId !== userId) return;
      const item = local.get(key);
      const file = cloud.get(key) || null;
      const cloudHash = file?.meta?.contentHash || '';
      const known = synced.get(key);
      if (!item) {
        // 上次还在用、这次不用了：方案删掉或换了包，云端副本跟着删；删不掉下次再试。
        if (file && state.refs.includes(key)) {
          try {
            await CloudFileClient.remove(file.id, 'REMOVED');
          } catch (e) {
            console.warn('[CloudThemeSync] remove unused theme failed:', (e as Error).message);
            retry.push(key);
          }
        }
        synced.delete(key);
        continue;
      }
      if (file) {
        if (item.hash && item.hash === cloudHash) {
          synced.set(key, item.hash);
          continue;
        }
        if (known !== undefined && cloudHash === known && item.hash !== known && (item.hash || item.schemeId)) {
          // 本机改过、云端还是上次那份：上传本机的；方案图片全删了就删云端的。
          if (item.hash) {
            const job = await CloudThemeSync.uploadJob(context, item);
            if (job) uploads.push(job);
          } else {
            try {
              await CloudFileClient.remove(file.id, 'REMOVED');
              synced.delete(key);
            } catch (e) {
              console.warn('[CloudThemeSync] remove cleared images failed:', (e as Error).message);
            }
          }
          continue;
        }
        // 云端更新、这台设备第一次对账、或两边都改了：以云端为准。
        if (item.packageId && !item.installed && !item.active) {
          remote.push(item.packageId);
          CloudThemeSync.remoteFiles.set(item.packageId, file);
          continue;
        }
        if (downloadBlocked) continue;
        try {
          if (item.schemeId) {
            await CloudThemeSync.applySchemeFile(context, item.schemeId, file);
          } else {
            await CloudThemeSync.installPackFile(context, item.packageId, file);
          }
          synced.set(key, cloudHash);
        } catch (e) {
          const message = (e as Error).message || '下载失败';
          console.warn('[CloudThemeSync] download failed:', key, message);
          if (message.includes('下载额度')) downloadBlocked = message;
          CloudThemeSync.recordIssue(context, userId, `theme-download:${key}`,
            `自定义主题“${item.name}”未能下载`, message);
          if (item.packageId && !item.installed) {
            remote.push(item.packageId);
            CloudThemeSync.remoteFiles.set(item.packageId, file);
          }
        }
        continue;
      }
      if (!item.hash) {
        synced.delete(key);
        continue;
      }
      const tomb = tombs.find((entry: CloudTombstone) => CloudThemeSync.themeKey(entry.meta) === key &&
        entry.meta?.contentHash === item.hash);
      if (tomb) {
        // DETACHED：用户在云空间页删了云端副本，没再改过就不重新上传。
        // REMOVED：别的设备删掉了这套方案的图片，本机没改过就一起清掉；主题包随方案列表同步卸载，这里不动。
        if (tomb.reason === 'REMOVED' && item.schemeId && known === item.hash) {
          try {
            await CloudThemeSync.writeSchemeImages(context, item.schemeId, '', '', '');
            synced.delete(key);
          } catch (e) {
            console.warn('[CloudThemeSync] clear removed images failed:', (e as Error).message);
          }
        }
        continue;
      }
      const job = await CloudThemeSync.uploadJob(context, item);
      if (job) uploads.push(job);
    }
    state.synced = [];
    synced.forEach((value: string, key: string) => {
      const entry = new ThemeSyncEntry();
      entry.key = key;
      entry.hash = value;
      state.synced.push(entry);
    });
    state.refs = Array.from(local.keys()).concat(retry);
    await CloudThemeSync.saveState(context, userId, state);
    CloudThemeSync.publishRemote(remote);
  }

  /** 上传成功的主题记成已同步，免得下一轮之前本机再改时被当作两边都改了。 */
  static async recordUploaded(context: Context, userId: string, jobKeys: string[]): Promise<void> {
    const prefix = `${CloudThemeSync.KIND}:`;
    const done = jobKeys.filter((key: string) => key.startsWith(prefix));
    if (done.length === 0) return;
    const state = await CloudThemeSync.loadState(context, userId);
    for (const jobKey of done) {
      const body = jobKey.substring(prefix.length);
      const split = body.lastIndexOf(':');
      if (split <= 0) continue;
      CloudThemeSync.setSynced(state, body.substring(0, split), body.substring(split + 1));
    }
    await CloudThemeSync.saveState(context, userId, state);
  }

  /** 删掉本轮打包的临时文件（上传前已复制进传输目录）。 */
  static cleanupStaging(context: Context): void {
    CloudThemeSync.removeDir(`${context.tempDir}/cloud_theme_upload`);
  }

  /**
   * 应用或打开方案前调用：方案用到、本机没有的主题包从云端下载。
   * 没有需要下载的返回 false；下载失败抛错。
   */
  static async ensureSchemePacks(context: Context, scheme: CustomThemeScheme | null): Promise<boolean> {
    if (!scheme) return false;
    const missing = CloudThemeSync.schemePackageIds(scheme).filter((id: string): boolean =>
      !ThemePackRegistry.getByPackageId(id) && !CloudThemeSync.absent.has(id));
    if (missing.length === 0 || !await CloudThemeSync.enabled(context)) return false;
    const userId = AccountSessionStore.account().userId;
    let files: CloudFileItem[] | null = null;
    let downloaded = false;
    for (const packageId of missing) {
      let file = CloudThemeSync.remoteFiles.get(packageId) || null;
      if (!file) {
        // 冷启动后还没对账：现查一次云端列表。
        if (!files) {
          files = (await CloudFileClient.listAll()).filter((item: CloudFileItem) =>
            item.kind === CloudThemeSync.KIND && item.state === 'READY');
        }
        for (const item of files) {
          if (item.meta?.packageId === packageId && (!file || CloudThemeSync.newer(item, file))) file = item;
        }
      }
      if (!file) {
        CloudThemeSync.absent.add(packageId);
        continue;
      }
      await CloudThemeSync.installPackFile(context, packageId, file);
      const state = await CloudThemeSync.loadState(context, userId);
      CloudThemeSync.setSynced(state, `pack:${packageId}`, file.meta?.contentHash || '');
      await CloudThemeSync.saveState(context, userId, state);
      downloaded = true;
    }
    if (downloaded) {
      CloudThemeSync.publishRemote(CloudThemeSync.remotePackageIds().filter((id: string): boolean =>
        !ThemePackRegistry.getByPackageId(id)));
    }
    return downloaded;
  }

  /** 方案用到的全部主题包：自己的素材包、各部件来源和阅读背景键里的包。 */
  static schemePackageIds(scheme: CustomThemeScheme): string[] {
    const ids = CloudThemeSync.settingsPackageIds(scheme.settings);
    if (scheme.packageId && isValidPackageId(scheme.packageId) && !ids.includes(scheme.packageId)) {
      ids.push(scheme.packageId);
    }
    return ids;
  }

  private static settingsPackageIds(settings: AppThemeSettings): string[] {
    const record = JSON.parse(JSON.stringify(settings)) as Record<string, Object>;
    return ThemePackageService.referencedPackageIds(record).filter((id: string): boolean => isValidPackageId(id));
  }

  private static async enabled(context: Context): Promise<boolean> {
    const userId = AccountSessionStore.account().userId;
    if (!userId || !AccountSessionStore.isLoggedIn() || AccountSessionStore.activeMembershipSku() !== 'SUPER_LIFETIME') {
      return false;
    }
    if (CloudSyncSettingsStore.currentAccountId() !== userId) await CloudSyncSettingsStore.load(context, userId);
    return CloudSyncSettingsStore.currentAccountId() === userId && CloudSyncSettingsStore.current().customThemesEnabled;
  }

  private static async collectLocal(context: Context): Promise<Map<string, LocalThemeItem>> {
    const result = new Map<string, LocalThemeItem>();
    const appSettings = await AppThemeSettingsStore.load(context);
    const schemes = await CustomThemeSchemeStore.load(context, appSettings);
    const customActive = appSettings.themeId === ThemeIds.CUSTOM;
    const activeId = AppStorage.get<string>(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID) || '';
    const activePacks = new Set<string>(customActive ? CloudThemeSync.settingsPackageIds(appSettings) : []);
    const packNames = new Map<string, string>();
    const hashes = await CloudThemeSync.loadFileHashes(context);
    const visited: FileHashRecord[] = [];
    for (const scheme of schemes) {
      const ids = CloudThemeSync.schemePackageIds(scheme);
      for (const id of ids) {
        if (customActive && scheme.id === activeId) activePacks.add(id);
        if (!packNames.has(id)) packNames.set(id, scheme.name);
      }
      const item = new LocalThemeItem();
      item.key = `scheme:${scheme.id}`;
      item.schemeId = scheme.id;
      item.name = scheme.name || '自定义主题';
      item.hash = await CloudThemeSync.schemeImagesHash(context, scheme.settings, hashes, visited);
      result.set(item.key, item);
    }
    for (const id of Array.from(packNames.keys())) {
      const item = new LocalThemeItem();
      item.key = `pack:${id}`;
      item.packageId = id;
      const pack = ThemePackRegistry.getByPackageId(id);
      item.name = pack?.name || packNames.get(id) || '自定义主题';
      item.active = activePacks.has(id);
      item.installed = ThemePackStore.exists(`${ThemePackStore.packDir(context, id)}/${ThemePackStore.RECORD_FILE}`);
      item.hash = item.installed ? await CloudThemeSync.packHash(context, id, hashes, visited) : '';
      result.set(item.key, item);
    }
    await CloudThemeSync.saveFileHashes(context, visited);
    return result;
  }

  /** 包的指纹：pack.json 与 assets/ 下每个文件的内容；以点开头的临时文件不算。 */
  private static async packHash(context: Context, packageId: string, cache: FileHashRecord[],
    visited: FileHashRecord[]): Promise<string> {
    const dir = ThemePackStore.packDir(context, packageId);
    const lines: string[] = [];
    lines.push(`pack.json:${await CloudThemeSync.fileHash(`${dir}/${ThemePackStore.RECORD_FILE}`, cache, visited)}`);
    for (const name of CloudThemeSync.assetNames(`${dir}/assets`)) {
      lines.push(`${name}:${await CloudThemeSync.fileHash(`${dir}/assets/${name}`, cache, visited)}`);
    }
    return CloudThemeSync.sha256Text(lines.join('\n'));
  }

  /** 方案图片的指纹：三个位置各自的文件内容；一张都没有时为空。 */
  private static async schemeImagesHash(context: Context, settings: AppThemeSettings, cache: FileHashRecord[],
    visited: FileHashRecord[]): Promise<string> {
    const lines: string[] = [];
    const slots: string[][] = [['light', settings.customLightStartupImagePath],
      ['dark', settings.customDarkStartupImagePath], ['preview', settings.customPreviewImagePath]];
    for (const slot of slots) {
      const path = CloudThemeSync.localPath(context, slot[1]);
      if (path) lines.push(`${slot[0]}:${await CloudThemeSync.fileHash(path, cache, visited)}`);
    }
    return lines.length ? CloudThemeSync.sha256Text(`scheme-images\n${lines.join('\n')}`) : '';
  }

  private static async uploadJob(context: Context, item: LocalThemeItem): Promise<CloudUploadJob | null> {
    try {
      const zip = item.packageId ? await CloudThemeSync.buildPackZip(context, item.packageId) :
        await CloudThemeSync.buildSchemeZip(context, item.schemeId);
      if (!zip) return null;
      const job = new CloudUploadJob();
      job.path = zip;
      job.kind = CloudThemeSync.KIND;
      job.name = `theme-${(item.packageId || item.schemeId).replace(/[^A-Za-z0-9._-]/g, '_')}.zip`.slice(0, 190);
      const meta = new CloudFileMeta();
      if (item.packageId) meta.packageId = item.packageId;
      else meta.schemeId = item.schemeId;
      meta.contentHash = item.hash;
      job.meta = meta;
      job.key = `${CloudThemeSync.KIND}:${item.key}:${item.hash}`;
      job.label = item.name;
      return job;
    } catch (e) {
      console.warn('[CloudThemeSync] pack failed:', item.key, (e as Error).message);
      return null;
    }
  }

  private static async buildPackZip(context: Context, packageId: string): Promise<string> {
    const source = ThemePackStore.packDir(context, packageId);
    const work = CloudThemeSync.freshDir(`${context.tempDir}/cloud_theme_upload/p_${packageId}`);
    const root = `${work}/pack`;
    fs.mkdirSync(`${root}/assets`, true);
    fs.copyFileSync(`${source}/${ThemePackStore.RECORD_FILE}`, `${root}/${ThemePackStore.RECORD_FILE}`);
    for (const name of CloudThemeSync.assetNames(`${source}/assets`)) {
      fs.copyFileSync(`${source}/assets/${name}`, `${root}/assets/${name}`);
    }
    const zip = `${work}/theme.zip`;
    await zlib.compressFile(root, zip, { level: zlib.CompressLevel.COMPRESS_LEVEL_NO_COMPRESSION });
    return zip;
  }

  private static async buildSchemeZip(context: Context, schemeId: string): Promise<string> {
    const appSettings = await AppThemeSettingsStore.load(context);
    const scheme = CustomThemeSchemeStore.find(await CustomThemeSchemeStore.load(context, appSettings), schemeId);
    if (!scheme) return '';
    const work = CloudThemeSync.freshDir(
      `${context.tempDir}/cloud_theme_upload/s_${schemeId.replace(/[^A-Za-z0-9_-]/g, '_')}`);
    const root = `${work}/images`;
    fs.mkdirSync(root, true);
    const manifest = new SchemeImageManifest();
    manifest.schemeId = schemeId;
    const copy = (slot: string, uri: string): string => {
      const path = CloudThemeSync.localPath(context, uri);
      if (!path) return '';
      const name = `${slot}${CloudThemeSync.extensionOf(path)}`;
      fs.copyFileSync(path, `${root}/${name}`);
      return name;
    };
    manifest.light = copy('light', scheme.settings.customLightStartupImagePath);
    manifest.dark = copy('dark', scheme.settings.customDarkStartupImagePath);
    manifest.preview = copy('preview', scheme.settings.customPreviewImagePath);
    if (!manifest.light && !manifest.dark && !manifest.preview) return '';
    CloudThemeSync.writeText(`${root}/scheme.json`, JSON.stringify(manifest));
    const zip = `${work}/images.zip`;
    await zlib.compressFile(root, zip, { level: zlib.CompressLevel.COMPRESS_LEVEL_NO_COMPRESSION });
    return zip;
  }

  /** 下载主题包并整包换掉本机的；正在使用的方案用到它时重新应用主题。同一个包并发只下一次。 */
  private static async installPackFile(context: Context, packageId: string, file: CloudFileItem): Promise<void> {
    const running = CloudThemeSync.downloads.get(packageId);
    if (running) return running;
    const task = CloudThemeSync.doInstallPack(context, packageId, file);
    CloudThemeSync.downloads.set(packageId, task);
    try {
      await task;
    } finally {
      CloudThemeSync.downloads.delete(packageId);
    }
  }

  private static async doInstallPack(context: Context, packageId: string, file: CloudFileItem): Promise<void> {
    if (!isValidPackageId(packageId)) throw new Error('主题包标识无效');
    const work = CloudThemeSync.freshDir(`${context.tempDir}/cloud_theme_download/p_${packageId}`);
    try {
      const root = await CloudThemeSync.downloadAndExtract(context, file, work, ThemePackStore.RECORD_FILE);
      const head = JSON.parse(fs.readTextSync(`${root}/${ThemePackStore.RECORD_FILE}`)) as PackHead;
      if (!head || head.packageId !== packageId) throw new Error('主题包内容与标识不符');
      const dir = ThemePackStore.prepareDir(context, packageId);
      fs.copyFileSync(`${root}/${ThemePackStore.RECORD_FILE}`, `${dir}/${ThemePackStore.RECORD_FILE}`);
      for (const name of CloudThemeSync.assetNames(`${root}/assets`)) {
        fs.copyFileSync(`${root}/assets/${name}`, `${dir}/assets/${name}`);
      }
      ThemePackStore.registerExisting(context, packageId);
    } finally {
      CloudThemeSync.removeDir(work);
    }
    await CloudThemeSync.refreshAppliedTheme(context, packageId);
  }

  private static async applySchemeFile(context: Context, schemeId: string, file: CloudFileItem): Promise<void> {
    const safeId = schemeId.replace(/[^A-Za-z0-9_-]/g, '_');
    const work = CloudThemeSync.freshDir(`${context.tempDir}/cloud_theme_download/s_${safeId}`);
    try {
      const root = await CloudThemeSync.downloadAndExtract(context, file, work, 'scheme.json');
      const manifest = JSON.parse(fs.readTextSync(`${root}/scheme.json`)) as SchemeImageManifest;
      if (!manifest || manifest.schemeId !== schemeId) throw new Error('方案图片与方案不符');
      const place = (slot: string, name: string, dirName: string): string => {
        if (!name || !CloudThemeSync.SAFE_NAME.test(name) || !ThemePackStore.exists(`${root}/${name}`)) return '';
        const dir = `${context.filesDir}/${dirName}`;
        if (!ThemePackStore.exists(dir)) fs.mkdirSync(dir, true);
        const target = `${dir}/${CloudThemeSync.CLOUD_IMAGE_PREFIX}${safeId}_${slot}_${Date.now()}` +
          CloudThemeSync.extensionOf(name);
        fs.copyFileSync(`${root}/${name}`, target);
        return fileUri.getUriFromPath(target);
      };
      await CloudThemeSync.writeSchemeImages(context, schemeId, place('light', manifest.light, 'theme_startups'),
        place('dark', manifest.dark, 'theme_startups'), place('preview', manifest.preview, 'theme_previews'));
    } finally {
      CloudThemeSync.removeDir(work);
    }
  }

  /** 写入方案的三张图；正在使用的方案同时写进当前主题设置。被替换掉的云端下载图片随手删掉。 */
  private static async writeSchemeImages(context: Context, schemeId: string, light: string, dark: string,
    preview: string): Promise<void> {
    const appSettings = await AppThemeSettingsStore.load(context);
    const before = CustomThemeSchemeStore.find(await CustomThemeSchemeStore.load(context, appSettings), schemeId);
    if (!before) return;
    if (!await CustomThemeSchemeStore.setLocalImages(context, appSettings, schemeId, light, dark, preview)) return;
    const activeId = AppStorage.get<string>(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID) || '';
    if (appSettings.themeId === ThemeIds.CUSTOM && activeId === schemeId) {
      appSettings.customLightStartupImagePath = light;
      appSettings.customDarkStartupImagePath = dark;
      appSettings.customPreviewImagePath = preview;
      await AppThemeSettingsStore.save(context, appSettings);
      AppThemeSettingsStore.applyToStorage(appSettings);
    }
    const kept = [light, dark, preview];
    for (const old of [before.settings.customLightStartupImagePath, before.settings.customDarkStartupImagePath,
      before.settings.customPreviewImagePath]) {
      if (!old || kept.includes(old)) continue;
      const path = CloudThemeSync.localPath(context, old);
      // 只删这里下载的；用户自己选的图片可能还被别的方案用着。
      if (path && path.substring(path.lastIndexOf('/') + 1).startsWith(CloudThemeSync.CLOUD_IMAGE_PREFIX)) {
        try {
          fs.unlinkSync(path);
        } catch (e) {
          console.warn('[CloudThemeSync] delete replaced image failed:', e);
        }
      }
    }
  }

  /** 当前主题用到刚装好的包时重新应用，界面立刻换成包里的素材。 */
  private static async refreshAppliedTheme(context: Context, packageId: string): Promise<void> {
    const settings = await AppThemeSettingsStore.load(context);
    if (settings.themeId === ThemeIds.CUSTOM && CloudThemeSync.settingsPackageIds(settings).includes(packageId)) {
      AppThemeSettingsStore.applyToStorage(settings);
    }
    AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_REVISION,
      (AppStorage.get<number>(CustomThemeSchemeStore.STORAGE_REVISION) || 0) + 1);
  }

  /** 下载并解压，返回含 marker 文件的目录（系统压缩接口可能多包一层目录）。 */
  private static async downloadAndExtract(context: Context, file: CloudFileItem, work: string,
    marker: string): Promise<string> {
    const downloaded = await CloudFileClient.download(context, file, () => {});
    const zip = `${work}/download.zip`;
    try {
      fs.copyFileSync(downloaded, zip);
    } finally {
      try { fs.unlinkSync(downloaded); } catch (e) { /* the transfer copy is only a cache */ }
    }
    const out = `${work}/out`;
    fs.mkdirSync(out, true);
    await zlib.decompressFile(zip, out);
    if (ThemePackStore.exists(`${out}/${marker}`)) return out;
    for (const name of fs.listFileSync(out)) {
      const dir = `${out}/${name}`;
      if (ThemePackStore.exists(`${dir}/${marker}`)) return dir;
    }
    throw new Error('云端主题文件不完整');
  }

  private static newer(a: CloudFileItem, b: CloudFileItem): boolean {
    return a.createdAt !== b.createdAt ? a.createdAt > b.createdAt : a.id > b.id;
  }

  private static setSynced(state: ThemeSyncState, key: string, value: string): void {
    const existing = state.synced.find((entry: ThemeSyncEntry) => entry.key === key);
    if (existing) {
      existing.hash = value;
      return;
    }
    const entry = new ThemeSyncEntry();
    entry.key = key;
    entry.hash = value;
    state.synced.push(entry);
  }

  private static publishRemote(ids: string[]): void {
    const raw = JSON.stringify(ids.slice().sort());
    if ((AppStorage.get<string>(CloudThemeSync.STORAGE_REMOTE_PACKS) || '[]') === raw) return;
    AppStorage.setOrCreate(CloudThemeSync.STORAGE_REMOTE_PACKS, raw);
  }

  private static recordIssue(context: Context, userId: string, key: string, title: string, message: string): void {
    CloudSyncIssueStore.record(context, userId,
      [CloudSyncIssueStore.create(CloudSyncIssueStore.KIND_FILE, key, title, message)]).catch((error: Error) => {
      console.warn('[CloudThemeSync] record issue failed:', error.message);
    });
  }

  /** 应用沙箱 files 目录里存在的文件路径；其他值（内置素材、空值、相册 URI）返回空。 */
  private static localPath(context: Context, value: string): string {
    const text = (value || '').trim();
    if (!text) return '';
    let path = '';
    try {
      path = text.startsWith('file://') ? new fileUri.FileUri(text).path : (text.startsWith('/') ? text : '');
    } catch (e) {
      return '';
    }
    if (!path || !path.startsWith(`${context.filesDir}/`) || path.includes('/../')) return '';
    return ThemePackStore.exists(path) ? path : '';
  }

  private static assetNames(dir: string): string[] {
    let names: string[] = [];
    try {
      if (fs.accessSync(dir)) names = fs.listFileSync(dir);
    } catch (e) {
      return [];
    }
    return names.filter((name: string): boolean => !name.startsWith('.') && CloudThemeSync.SAFE_NAME.test(name) &&
      ThemePackStore.exists(`${dir}/${name}`) && fs.statSync(`${dir}/${name}`).isFile()).sort();
  }

  private static extensionOf(path: string): string {
    const name = path.substring(path.lastIndexOf('/') + 1).toLowerCase();
    const dot = name.lastIndexOf('.');
    const ext = dot > 0 ? name.substring(dot) : '';
    return /^\.[a-z0-9]{1,5}$/.test(ext) ? ext : '.jpg';
  }

  /** 文件内容指纹按路径、大小和修改时间缓存，避免每次对账重读图片。 */
  private static async fileHash(path: string, cache: FileHashRecord[], visited: FileHashRecord[]): Promise<string> {
    const stat = fs.statSync(path);
    const cached = cache.find((entry: FileHashRecord) => entry.path === path);
    let record: FileHashRecord;
    if (cached && cached.size === stat.size && cached.mtime === stat.mtime && cached.hash) {
      record = cached;
    } else {
      record = new FileHashRecord();
      record.path = path;
      record.size = stat.size;
      record.mtime = stat.mtime;
      record.hash = (await hash.hash(path, 'sha256')).toLowerCase();
    }
    if (!visited.some((entry: FileHashRecord) => entry.path === path)) visited.push(record);
    return record.hash;
  }

  private static async loadFileHashes(context: Context): Promise<FileHashRecord[]> {
    const store = await preferences.getPreferences(context, CloudThemeSync.STORE);
    const raw = await store.get('theme_file_hashes', '') as string;
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw) as FileHashRecord[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  /** 只留这次用到的文件，删掉的图片不会一直占着记录。 */
  private static async saveFileHashes(context: Context, records: FileHashRecord[]): Promise<void> {
    const store = await preferences.getPreferences(context, CloudThemeSync.STORE);
    await store.put('theme_file_hashes', JSON.stringify(records));
    await store.flush();
  }

  private static async loadState(context: Context, userId: string): Promise<ThemeSyncState> {
    const store = await preferences.getPreferences(context, CloudThemeSync.STORE);
    const raw = await store.get(`theme_state:${userId}`, '') as string;
    const state = new ThemeSyncState();
    if (!raw) return state;
    try {
      const parsed = JSON.parse(raw) as ThemeSyncState;
      state.synced = Array.isArray(parsed.synced) ? parsed.synced : [];
      state.refs = Array.isArray(parsed.refs) ? parsed.refs : [];
    } catch (e) {
      // A damaged record only costs one round of "cloud wins".
    }
    return state;
  }

  private static async saveState(context: Context, userId: string, state: ThemeSyncState): Promise<void> {
    const store = await preferences.getPreferences(context, CloudThemeSync.STORE);
    await store.put(`theme_state:${userId}`, JSON.stringify(state));
    await store.flush();
  }

  private static sha256Text(text: string): string {
    const md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data: new util.TextEncoder().encodeInto(text) });
    let result = '';
    for (const byte of md.digestSync().data) result += byte.toString(16).padStart(2, '0');
    return result;
  }

  private static freshDir(path: string): string {
    CloudThemeSync.removeDir(path);
    fs.mkdirSync(path, true);
    return path;
  }

  private static removeDir(path: string): void {
    try {
      if (path && fs.accessSync(path)) fs.rmdirSync(path);
    } catch (e) {
      console.warn('[CloudThemeSync] remove dir failed:', (e as Error).message);
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
}
