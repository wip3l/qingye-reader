import { PluginEngineHostPort } from '../host/PluginHostPort';
import {
  getManifestContentSources,
  PLUGIN_PERMISSION_LABELS,
  PluginManifest,
  PluginPermission,
  requiresWebParseGate,
  validatePluginManifest
} from '../spec/PluginManifest';
import { inspectPluginZipBytes, PluginZipEntry } from './ZipArchivePrecheck';
import { verifyPluginPackageSignature } from './PluginSignature';
import { evaluateInstallTrust, PluginInstallBaseline } from './PluginTrustPolicy';

export interface PluginInstallPreview {
  stagingDir: string;
  packageRootDir: string;
  manifest: PluginManifest;
  entryCount: number;
  uncompressedBytes: number;
  isUpgrade: boolean;
  previousVersion: string;
  requiresWebParse: boolean;
  highRiskNotes: string[];
  contributionLabels: string[];
  /** 安装包是否带有效签名，以及签名者指纹（未签名为空串）。 */
  signed: boolean;
  signerFingerprint: string;
  /** 来源与升级相关的提示（未签名、签名者变化等）。 */
  trustNotes: string[];
  /** 升级时相对已安装版本新增的权限与域名。 */
  addedPermissions: string[];
  addedDomains: string[];
}

function summarizeContributions(manifest: PluginManifest): string[] {
  const c = manifest.contributes;
  const labels: string[] = [];
  if (c.translation) labels.push(`翻译引擎（${c.translation.languagePairs.length} 组语言）`);
  if (c.readerActions && c.readerActions.length > 0) labels.push(`阅读动作（${c.readerActions.length} 项）`);
  if (c.contentProcessor) labels.push(`正文处理（${c.contentProcessor.title}）`);
  if (c.interaction) labels.push(`段落互动（${c.interaction.title}）`);
  if (c.tts) labels.push(`朗读音色（${c.tts.voices.length} 款）`);
  if (c.formatImporters && c.formatImporters.length > 0) {
    const exts = c.formatImporters.flatMap((i) => i.extensions).join(' / ');
    labels.push(`本地格式导入（${exts}）`);
  }
  if (c.catalogConnectors && c.catalogConnectors.length > 0) {
    labels.push(`远程书库（${c.catalogConnectors.map((x) => x.name).join('、')}）`);
  }
  if (c.sourceManager) labels.push(`书源管理与在线阅读（${c.sourceManager.title}）`);
  const contentSources = getManifestContentSources(manifest);
  if (contentSources.length > 0) {
    labels.push(`在线内容源（${contentSources.map((s) => s.name).join(' / ')}）`);
  }
  if (c.tools && c.tools.length > 0) labels.push(`独立工具页（${c.tools.length} 个）`);
  if (c.ticketStyles && c.ticketStyles.length > 0) {
    labels.push(`票夹样式（${c.ticketStyles.map((s) => s.name).join('、')}）`);
  }
  return labels;
}

/** 涉及隐私或越出插件自身空间的权限，安装预览逐条提示；storage 只动插件自己的数据，不单列。 */
const RISK_NOTE_PERMISSIONS: PluginPermission[] = [
  'reader.selection',
  'reader.content',
  'bookshelf.read',
  'annotations.read',
  'annotations.write',
  'secrets',
  'network.lan',
  'webview.verify',
  'source.manage',
  'book.import',
  'tts'
];

export function computeRiskNotes(manifest: PluginManifest): string[] {
  const notes: string[] = [];
  if (manifest.domains.includes('*')) {
    notes.push('申请访问任意外部网站域名（*），仅用于你自行配置的站点与规则');
  } else if (manifest.domains.length > 0) {
    notes.push(`申请联网访问域名：${manifest.domains.join(', ')}`);
  }
  for (const perm of RISK_NOTE_PERMISSIONS) {
    if (manifest.permissions.includes(perm)) {
      notes.push(`${PLUGIN_PERMISSION_LABELS.get(perm) || perm}（${perm}）`);
    }
  }
  return notes;
}

function detectExtractedRoot(entries: PluginZipEntry[], stagingDir: string): string {
  const hasRootManifest = entries.some((e) => e.path === 'manifest.json');
  if (hasRootManifest) return stagingDir;
  const topFolders: Set<string> = new Set();
  for (const e of entries) {
    const slash = e.path.indexOf('/');
    if (slash <= 0) return stagingDir;
    topFolders.add(e.path.slice(0, slash));
  }
  if (topFolders.size === 1) {
    const single = Array.from(topFolders)[0];
    if (entries.some((e) => e.path === `${single}/manifest.json`)) {
      return `${stagingDir}/${single}`;
    }
  }
  return stagingDir;
}

export class PluginPackageInstaller {
  static async prepareFromZipFile(
    zipAbsPath: string,
    port: PluginEngineHostPort,
    existing: ReadonlyMap<string, PluginInstallBaseline>
  ): Promise<PluginInstallPreview> {
    const zipBytes = await port.readFileBytes(zipAbsPath);
    const entries = inspectPluginZipBytes(zipBytes);
    const uncompressedBytes = entries.reduce((acc, item) => acc + item.uncompressedSize, 0);

    const stagingDir = `${port.tempRootDir()}/plugin_stage_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    await port.mkdirs(stagingDir);
    try {
      const parentDirs = new Set<string>();
      for (const entry of entries) {
        const slash = entry.path.lastIndexOf('/');
        if (slash > 0) {
          parentDirs.add(`${stagingDir}/${entry.path.slice(0, slash)}`);
        }
      }
      for (const dir of parentDirs) {
        await port.mkdirs(dir);
      }
      await port.extractZip(zipAbsPath, stagingDir);
      const packageRootDir = detectExtractedRoot(entries, stagingDir);
      const manifestPath = `${packageRootDir}/manifest.json`;
      if (!(await port.exists(manifestPath))) {
        throw new Error('插件包内缺少 manifest.json');
      }
      const rawManifestText = await port.readFileText(manifestPath);
      let parsedJson: unknown;
      try {
        parsedJson = JSON.parse(rawManifestText);
      } catch (_) {
        throw new Error('manifest.json 不是合法的 JSON 格式');
      }
      const manifest = validatePluginManifest(parsedJson);

      await PluginPackageInstaller.verifyRequiredFiles(packageRootDir, manifest, port);
      const signature = await verifyPluginPackageSignature(packageRootDir, port);
      const baseline = existing.get(manifest.id);
      const trust = evaluateInstallTrust(manifest, signature.fingerprint, baseline);

      const prevVer = baseline ? baseline.version : '';
      return {
        stagingDir,
        packageRootDir,
        manifest,
        entryCount: entries.length,
        uncompressedBytes,
        isUpgrade: prevVer.length > 0,
        previousVersion: prevVer,
        requiresWebParse: requiresWebParseGate(manifest),
        highRiskNotes: computeRiskNotes(manifest),
        contributionLabels: summarizeContributions(manifest),
        signed: signature.signed,
        signerFingerprint: signature.fingerprint,
        trustNotes: trust.notes,
        addedPermissions: trust.addedPermissions,
        addedDomains: trust.addedDomains
      };
    } catch (err) {
      try {
        await port.removePath(stagingDir);
      } catch (_) {}
      throw err;
    }
  }

  private static async verifyRequiredFiles(
    packageRootDir: string,
    manifest: PluginManifest,
    port: PluginEngineHostPort
  ): Promise<void> {
    if (manifest.main && !(await port.exists(`${packageRootDir}/${manifest.main}`))) {
      throw new Error(`插件入口文件不存在: ${manifest.main}`);
    }
    if (manifest.icon && !(await port.exists(`${packageRootDir}/${manifest.icon}`))) {
      throw new Error(`插件图标文件不存在: ${manifest.icon}`);
    }
    const panels: string[] = [];
    if (manifest.contributes.readerActions) {
      for (const act of manifest.contributes.readerActions) {
        if (act.panel) panels.push(act.panel);
      }
    }
    if (manifest.contributes.interaction?.panel) {
      panels.push(manifest.contributes.interaction.panel);
    }
    if (manifest.contributes.sourceManager?.panel) {
      panels.push(manifest.contributes.sourceManager.panel);
    }
    if (manifest.contributes.tools) {
      for (const tool of manifest.contributes.tools) {
        panels.push(tool.panel);
      }
    }
    for (const p of panels) {
      if (!(await port.exists(`${packageRootDir}/${p}`))) {
        throw new Error(`插件声明的面板 HTML 文件不存在: ${p}`);
      }
    }

    if (manifest.contributes.ticketStyles) {
      for (const style of manifest.contributes.ticketStyles) {
        const tplAbs = `${packageRootDir}/${style.template}`;
        if (!(await port.exists(tplAbs))) {
          throw new Error(`票夹样式 "${style.name}" 的模板文件不存在: ${style.template}`);
        }
        try {
          const parsedTpl: unknown = JSON.parse(await port.readFileText(tplAbs));
          if (!parsedTpl || typeof parsedTpl !== 'object' || Array.isArray(parsedTpl)) {
            throw new Error('顶层必须是 JSON 对象');
          }
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          throw new Error(`票夹样式 "${style.name}" 的模板文件格式无效 (${style.template}): ${msg}`);
        }
        if (style.backTemplate) {
          const backAbs = `${packageRootDir}/${style.backTemplate}`;
          if (!(await port.exists(backAbs))) {
            throw new Error(`票夹样式 "${style.name}" 的背面模板文件不存在: ${style.backTemplate}`);
          }
          try {
            const parsedBack: unknown = JSON.parse(await port.readFileText(backAbs));
            if (!parsedBack || typeof parsedBack !== 'object' || Array.isArray(parsedBack)) {
              throw new Error('顶层必须是 JSON 对象');
            }
          } catch (e) {
            const msg = e instanceof Error ? e.message : String(e);
            throw new Error(`票夹样式 "${style.name}" 的背面模板文件格式无效 (${style.backTemplate}): ${msg}`);
          }
        }
        if (style.fonts) {
          for (const font of style.fonts) {
            if (!(await port.exists(`${packageRootDir}/${font.src}`))) {
              throw new Error(`票夹样式 "${style.name}" 声明的字体文件不存在: ${font.src}`);
            }
          }
        }
      }
    }

    for (const asset of manifest.assets) {
      const target = `${packageRootDir}/${asset.path}`;
      if (!(await port.exists(target))) {
        throw new Error(`清单登记的素材文件缺失: ${asset.path}`);
      }
      if (asset.sha256 || asset.size !== undefined) {
        const content = await port.readFileBytes(target);
        if (asset.size !== undefined && content.byteLength !== asset.size) {
          throw new Error(`素材大小校验不匹配: ${asset.path}`);
        }
        if (asset.sha256) {
          const actualHash = (await port.sha256Hex(content)).toLowerCase();
          if (actualHash !== asset.sha256.toLowerCase()) {
            throw new Error(`素材 SHA-256 校验失败: ${asset.path}`);
          }
        }
      }
    }
  }

  static async commitPreview(
    preview: PluginInstallPreview,
    port: PluginEngineHostPort
  ): Promise<string> {
    const basePluginDir = `${port.pluginsRootDir()}/${preview.manifest.id}`;
    const currentDir = `${basePluginDir}/current`;
    const backupDir = `${basePluginDir}/prev_${Date.now()}`;
    const dataDir = `${basePluginDir}/current/data`;
    const preservedDataTemp = `${basePluginDir}/data_preserve_${Date.now()}`;

    await port.mkdirs(basePluginDir);
    let hadData = false;
    if (await port.exists(dataDir)) {
      await port.renamePath(dataDir, preservedDataTemp);
      hadData = true;
    }

    const hadCurrent = await port.exists(currentDir);
    if (hadCurrent) {
      await port.renamePath(currentDir, backupDir);
    }

    try {
      await port.renamePath(preview.packageRootDir, currentDir);
      if (hadData) {
        if (await port.exists(`${currentDir}/data`)) {
          await port.removePath(`${currentDir}/data`);
        }
        await port.renamePath(preservedDataTemp, `${currentDir}/data`);
      } else {
        await port.mkdirs(`${currentDir}/data`);
      }
      if (hadCurrent) {
        await port.removePath(backupDir);
      }
      if (preview.stagingDir !== preview.packageRootDir && (await port.exists(preview.stagingDir))) {
        await port.removePath(preview.stagingDir);
      }
      return currentDir;
    } catch (err) {
      if (hadCurrent && !(await port.exists(currentDir)) && (await port.exists(backupDir))) {
        try {
          await port.renamePath(backupDir, currentDir);
          if (hadData && (await port.exists(preservedDataTemp))) {
            await port.renamePath(preservedDataTemp, `${currentDir}/data`);
          }
        } catch (_) {}
      }
      throw err;
    }
  }

  static async discardPreview(preview: PluginInstallPreview, port: PluginEngineHostPort): Promise<void> {
    if (await port.exists(preview.stagingDir)) {
      await port.removePath(preview.stagingDir);
    }
  }
}
