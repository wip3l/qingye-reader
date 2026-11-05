import { common, Context } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import hash from '@ohos.file.hash';
import picker from '@ohos.file.picker';
import zlib from '@ohos.zlib';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { CustomThemeQuota } from '../../account/CustomThemeQuota';
import { ReaderRegexFontCodec, ReaderRegexFontRule, ReaderRegexLegacySettings } from '../../model/reader/ReaderRegexFontRule';
import { ThemeAccessPolicy } from '../../account/ThemeAccessPolicy';
import { AppThemeSettings, AppThemeSettingsStore } from '../../utils/AppThemeSettingsStore';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../../utils/CustomThemeSchemeStore';
import { ReaderFontBootstrap } from '../../utils/ReaderFontBootstrap';
import { ReaderFontHelper } from '../../utils/ReaderFontHelper';
import { ReaderSettings, ReaderSettingsStore } from '../../utils/ReaderSettingsStore';
import { ReaderThemeHelper } from '../../utils/ReaderThemeHelper';
import { BuiltinThemeRegistry } from '../BuiltinThemeRegistry';
import { ThemeIds, ThemePack } from '../ThemeModels';
import { InstalledThemePack, ThemePackRecord, ThemePackRegistry } from '../ThemePackRegistry';
import { ThemePackStore } from '../../utils/ThemePackStore';
import {
  applyLayout,
  assetIdFromRef,
  assetPath,
  assetPathExtension,
  assetRef,
  checkSvgSource,
  decodeManifest,
  decodeTheme,
  describeParts,
  encodeManifest,
  encodeTheme,
  findAsset,
  findAssetByPath,
  IMAGE_SETTING_KEYS,
  isLocalFileReference,
  isPackThemeId,
  kindForExtension,
  mapPartsAssetRefs,
  maxBytesForKind,
  mergeRules,
  packageFileName,
  packageIdOfThemeId,
  packThemeId,
  partsAssetRefs,
  pickLayout,
  QYTHEME_EXTENSION,
  remapFonts,
  replaceOwnPackIdWithSelf,
  restrictSources,
  sanitizeAuthor,
  sanitizeThemeName,
  sniffAssetExtension,
  SourceRestriction,
  THEME_SOURCE_FIELDS,
  ThemePackageAsset,
  ThemePackageAssetKinds,
  ThemePackageCredits,
  ThemePackageEmphasis,
  ThemePackageFeatures,
  ThemePackageFont,
  ThemePackageLimits,
  ThemePackageManifest,
  ThemePackageParts,
  ThemePackageTheme
} from './ThemePackageFormat';
import { ZipEntryInfo, ZipEntryInspector, ZipInspectLimits } from './ZipEntryInspector';

class CustomFontRecord {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class CustomFontList {
  fonts: CustomFontRecord[] = [];
}

export class ThemeExportFontInfo {
  family: string = '';
  name: string = '';
  // 用在哪里，例如“正文、标题”“强调规则”。
  usage: string = '';
  // 只被强调规则用到：不附带规则时不打包。
  ruleOnly: boolean = false;
  filePath: string = '';
  size: number = 0;
  available: boolean = false;
}

/** 导出面板展示用：方案里有什么、要打包多少、缺了什么。 */
export class ThemeExportPlan {
  schemeId: string = '';
  name: string = '';
  author: string = '';
  imageCount: number = 0;
  imageBytes: number = 0;
  missingImages: string[] = [];
  ruleCount: number = 0;
  fonts: ThemeExportFontInfo[] = [];
  // 随包打出去的主题包素材（方案由主题包安装而来，或部件里选了某个主题包）。
  packName: string = '';
  packAssetCount: number = 0;
  packAssetBytes: number = 0;
  // 方案不是这个主题包自己的方案：导出为新包，原作者记在 credits。
  packRemix: boolean = false;
}

export class ThemeExportOptions {
  includeAuthor: boolean = false;
  authorName: string = '';
  includeRules: boolean = false;
  includeFonts: boolean = false;
}

export class ThemeExportResult {
  zipPath: string = '';
  fileName: string = '';
  size: number = 0;
  workDir: string = '';
}

/** 导入前的检查结果，用户确认后才写入。 */
export class ThemeImportPreview {
  workDir: string = '';
  baseDir: string = '';
  manifest: ThemePackageManifest = new ThemePackageManifest();
  theme: ThemePackageTheme = new ThemePackageTheme();
  settingsJson: string = '';
  replaced: string[] = [];
  unknown: string[] = [];
  missingFonts: string[] = [];
  lockedBubbles: string[] = [];
  ruleCount: number = 0;
  bundledFontCount: number = 0;
  imageCount: number = 0;
  hasLayout: boolean = false;
  // 包内部件（格式 2）：描述列表、包 ID，以及本机已有同一个包时要更新的方案。
  parts: string[] = [];
  packageId: string = '';
  updateSchemeId: string = '';
  updateSchemeName: string = '';
}

export class ThemeImportResult {
  scheme: CustomThemeScheme = new CustomThemeScheme();
  addedRules: number = 0;
  skippedRules: number = 0;
  missingFonts: string[] = [];
  // 更新了正在使用的方案：调用方需要重新应用主题。
  replacedActive: boolean = false;
}

const IMAGE_KEY_LABELS: Map<string, string> = new Map<string, string>([
  ['customLightStartupImagePath', '浅色启动封面图片'],
  ['customDarkStartupImagePath', '深色启动封面图片'],
  ['customPreviewImagePath', '方案预览图'],
  ['customLightReaderBackgroundAssetId', '浅色阅读背景图片'],
  ['customDarkReaderBackgroundAssetId', '深色阅读背景图片']
]);

/**
 * 自定义主题分享（Beta，会员专享）：把一套自定义方案打成 .qytheme 主题包，或从主题包导入为新方案。
 * 格式与校验规则见 ThemePackageFormat。
 */
export class ThemePackageService {
  static readonly IMPORTED_FILE_PREFIX: string = 'qytheme_';

  /** 导出和导入都需要有效会员。 */
  static isAvailable(): boolean {
    return AccountSessionStore.activeMembershipSku() !== '';
  }

  static async planExport(context: Context, scheme: CustomThemeScheme): Promise<ThemeExportPlan> {
    const plan = new ThemeExportPlan();
    plan.schemeId = scheme.id;
    plan.name = scheme.name;
    plan.author = scheme.author;
    const settingsRecord = ThemePackageService.settingsRecord(scheme.settings);
    const seen = new Set<string>();
    for (const key of IMAGE_SETTING_KEYS) {
      const value = settingsRecord[key];
      if (typeof value !== 'string' || !isLocalFileReference(value)) continue;
      const path = ThemePackageService.pathFromUri(value);
      if (!ThemePackageService.exists(path)) {
        plan.missingImages.push(IMAGE_KEY_LABELS.get(key) || key);
        continue;
      }
      if (seen.has(path)) continue;
      seen.add(path);
      plan.imageCount++;
      plan.imageBytes += fs.statSync(path).size;
    }
    const profile = await ThemePackageService.schemeProfile(context, scheme);
    plan.ruleCount = ThemePackageService.profileRules(profile).length;
    plan.fonts = ThemePackageService.effectiveFonts(profile, true, scheme.settings.customAppFontFamily);
    const bundled = ThemePackageService.bundledPack(scheme);
    if (bundled) {
      plan.packName = bundled.name;
      plan.packRemix = scheme.packageId !== bundled.packageId;
      for (const relativePath of partsAssetRefs(bundled.record.parts)) {
        const path = `${bundled.dir}/${relativePath}`;
        if (!ThemePackageService.exists(path)) continue;
        plan.packAssetCount++;
        plan.packAssetBytes += fs.statSync(path).size;
      }
    }
    return plan;
  }

  /** 方案引用到的、要随包打出去的主题包：方案本身由包安装而来，或者部件里选了某个已安装的包。 */
  static bundledPack(scheme: CustomThemeScheme): InstalledThemePack | null {
    if (scheme.packageId) {
      const own = ThemePackRegistry.getByPackageId(scheme.packageId);
      if (own) return own;
    }
    for (const id of ThemePackageService.referencedPackageIds(ThemePackageService.settingsRecord(scheme.settings))) {
      const pack = ThemePackRegistry.getByPackageId(id);
      if (pack) return pack;
    }
    return null;
  }

  /** 方案设置里出现的全部主题包 ID（基底、各部件来源、阅读背景键）。 */
  static referencedPackageIds(settings: Record<string, Object>): string[] {
    const ids: string[] = [];
    const add = (value: Object | undefined): void => {
      const id = typeof value === 'string' ? packageIdOfThemeId(value) : '';
      if (id && !ids.includes(id)) ids.push(id);
    };
    add(settings['customBaseThemeId']);
    for (const modeKey of ['customLightSources', 'customDarkSources']) {
      const sources = settings[modeKey];
      if (!sources || typeof sources !== 'object') continue;
      const record = sources as Record<string, Object>;
      for (const field of THEME_SOURCE_FIELDS) add(record[field.key]);
    }
    add(settings['customLightReaderBackgroundAssetId']);
    add(settings['customDarkReaderBackgroundAssetId']);
    return ids;
  }

  /** 导出时：指向其他主题包（不随包打出去的）的来源换成默认主题，导入方没有那些素材。 */
  private static detachOtherPacks(settings: Record<string, Object>, keepPackageId: string): void {
    const fallback = BuiltinThemeRegistry.DEFAULT_THEME_ID;
    const other = (value: Object | undefined): boolean => {
      const id = typeof value === 'string' ? packageIdOfThemeId(value) : '';
      return !!id && id !== keepPackageId;
    };
    if (other(settings['customBaseThemeId'])) settings['customBaseThemeId'] = fallback;
    for (const modeKey of ['customLightSources', 'customDarkSources']) {
      const sources = settings[modeKey];
      if (!sources || typeof sources !== 'object') continue;
      const record = sources as Record<string, Object>;
      for (const field of THEME_SOURCE_FIELDS) {
        if (other(record[field.key])) record[field.key] = fallback;
      }
    }
    const defaults = BuiltinThemeRegistry.findById(fallback);
    if (other(settings['customLightReaderBackgroundAssetId'])) {
      settings['customLightReaderBackgroundAssetId'] = defaults.light.reader.backgroundAssetId;
    }
    if (other(settings['customDarkReaderBackgroundAssetId'])) {
      settings['customDarkReaderBackgroundAssetId'] = defaults.dark.reader.backgroundAssetId;
    }
  }

  /** 在临时目录生成主题包（ZIP），之后由用户选择保存到文件或分享。 */
  static async buildPackage(context: Context, scheme: CustomThemeScheme,
    options: ThemeExportOptions): Promise<ThemeExportResult> {
    const workDir = `${context.tempDir}/qytheme_export_${Date.now()}`;
    const pkgDir = `${workDir}/theme`;
    const assetsDir = `${pkgDir}/assets`;
    fs.mkdirSync(assetsDir, true);
    try {
      const bundled = ThemePackageService.bundledPack(scheme);
      const manifest = new ThemePackageManifest();
      // 没带主题包素材的方案仍按格式 1 导出，老版本应用也能导入。
      manifest.formatVersion = bundled ? 2 : 1;
      manifest.packageId = bundled && scheme.packageId === bundled.packageId ? bundled.packageId :
        ThemePackageService.randomHex(16);
      manifest.name = sanitizeThemeName(scheme.name) || '自定义主题';
      manifest.author = options.includeAuthor ? sanitizeAuthor(options.authorName) : '';
      if (options.includeAuthor && !manifest.author) {
        throw new Error('请填写作者名称');
      }
      manifest.exportedAt = Date.now();
      manifest.appVersion = ThemePackageService.appVersion();
      manifest.requires = [ThemePackageFeatures.CUSTOM_SCHEME, ThemePackageFeatures.READER_LAYOUT];
      if (bundled) {
        manifest.requires.push(ThemePackageFeatures.THEME_PARTS);
        manifest.version = bundled.version;
        manifest.description = bundled.description;
        manifest.baseTheme = bundled.baseTheme;
        if (scheme.packageId === bundled.packageId) {
          manifest.credits = bundled.credits;
        } else {
          // 混搭了别人的主题包素材：按新包导出，原包和原作者记在 credits 里。
          const credits = new ThemePackageCredits();
          credits.packageId = bundled.packageId;
          credits.name = bundled.name;
          credits.author = bundled.author;
          manifest.credits = credits;
        }
      }

      const settingsRecord = ThemePackageService.settingsRecord(scheme.settings);
      // 是否使用主题封面、应用时是否带排版是本机偏好，不随主题走。
      settingsRecord['themeBookCoverEnabled'] = false;
      settingsRecord['themeApplyLayoutEnabled'] = false;
      if (AppThemeSettingsStore.hasOverrides(scheme.settings)) {
        manifest.requires.push(ThemePackageFeatures.SCHEME_OVERRIDES);
      }
      // 指向随包打出去的主题包的来源写成 pack:self，导入时换成导入方安装后的 ID。
      ThemePackageService.detachOtherPacks(settingsRecord, bundled ? bundled.packageId : '');
      if (bundled) replaceOwnPackIdWithSelf(settingsRecord, bundled.themeId);
      const copied = new Map<string, string>();
      for (const key of IMAGE_SETTING_KEYS) {
        const value = settingsRecord[key];
        if (typeof value !== 'string' || !isLocalFileReference(value)) continue;
        const path = ThemePackageService.pathFromUri(value);
        if (!ThemePackageService.exists(path)) {
          throw new Error(`${IMAGE_KEY_LABELS.get(key) || '图片'}已丢失，请在编辑主题里重新上传后再导出`);
        }
        let id = copied.get(path) || '';
        if (!id) {
          const asset = await ThemePackageService.packAsset(path, assetsDir, ThemePackageAssetKinds.IMAGE, '');
          manifest.assets.push(asset);
          id = asset.id;
          copied.set(path, id);
        }
        settingsRecord[key] = assetRef(id);
      }

      const profile = await ThemePackageService.schemeProfile(context, scheme);
      const profileRecord = ThemePackageService.readerRecord(profile);
      // 全局字体是整机设置，导入方不会被改动；方案正文/标题跟随全局字体且全局用的是自定义字体时，
      // 换成直接绑定这款字体，导入后效果一致。
      if (profile.fontMode === ReaderSettingsStore.FONT_MODE_CUSTOM && profile.fontFamily) {
        for (const pair of [['bodyFontMode', 'bodyFontFamily'], ['titleFontMode', 'titleFontFamily']]) {
          if (profileRecord[pair[0]] === 'global') {
            profileRecord[pair[0]] = 'custom';
            profileRecord[pair[1]] = profile.fontFamily;
          }
        }
      }
      const theme = new ThemePackageTheme();
      theme.settingsJson = JSON.stringify(settingsRecord);
      theme.layoutJson = JSON.stringify(pickLayout(profileRecord));

      const rules = options.includeRules ? ThemePackageService.profileRules(profile) : [];
      if (rules.length > 0) {
        manifest.requires.push(ThemePackageFeatures.EMPHASIS_RULES);
        theme.emphasis = new ThemePackageEmphasis();
        theme.emphasis.enabled = profile.regexFontEnabled;
        theme.emphasis.rulesJson = JSON.stringify(ReaderRegexFontCodec.cleanRules(rules));
      }

      // 只打包这套方案实际生效的字体：正文、标题，以及开着强调规则时规则用的字体。
      // 规则开关关着时，规则字体只记名字，导入方看得到用的是哪款。
      const effective = ThemePackageService.effectiveFonts(profile, options.includeRules,
        scheme.settings.customAppFontFamily);
      for (const family of ThemePackageService.boundFamilies(profileRecord, rules, scheme.settings.customAppFontFamily)) {
        const info = effective.find((item: ThemeExportFontInfo): boolean => item.family === family);
        const font = new ThemePackageFont();
        font.family = family;
        font.name = info ? info.name : ThemePackageService.fontDisplayName(profile, family);
        // 文件已丢失的字体只记名字，导入方会退回全局字体；导出面板已提示。
        if (options.includeFonts && info && info.available) {
          const existing = manifest.assets.find((item: ThemePackageAsset): boolean =>
            item.kind === ThemePackageAssetKinds.FONT && item.name === info.name && item.size === info.size);
          if (existing) {
            font.assetId = existing.id;
          } else {
            const asset = await ThemePackageService.packAsset(info.filePath, assetsDir,
              ThemePackageAssetKinds.FONT, info.name);
            manifest.assets.push(asset);
            font.assetId = asset.id;
          }
        }
        theme.fonts.push(font);
      }
      if (bundled) {
        theme.parts = await ThemePackageService.packParts(bundled, assetsDir, manifest);
      }
      if (manifest.assets.some((item: ThemePackageAsset): boolean => item.kind === ThemePackageAssetKinds.FONT)) {
        manifest.requires.push(ThemePackageFeatures.FONTS);
      }
      if (manifest.assets.length > ThemePackageLimits.MAX_ASSETS) {
        throw new Error('主题素材过多，无法导出');
      }

      ThemePackageService.writeText(`${pkgDir}/manifest.json`, encodeManifest(manifest));
      ThemePackageService.writeText(`${pkgDir}/theme.json`, encodeTheme(theme));
      // 系统压缩接口要求输出路径是 .zip；保存时再用 .qytheme 作为文件名。
      const zipPath = `${workDir}/theme.zip`;
      await zlib.compressFile(pkgDir, zipPath, { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION });
      const result = new ThemeExportResult();
      result.zipPath = zipPath;
      result.fileName = packageFileName(manifest.name);
      result.size = fs.statSync(zipPath).size;
      result.workDir = workDir;
      if (result.size > ThemePackageLimits.MAX_PACKAGE_BYTES) {
        throw new Error('主题包超过 80 MB，请减少附带的字体后再导出');
      }
      return result;
    } catch (e) {
      ThemePackageService.removeDir(workDir);
      throw e as Error;
    }
  }

  /** 用系统保存面板写到用户选的位置；取消时返回 false。 */
  static async saveToFile(context: Context, result: ThemeExportResult): Promise<boolean> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [result.fileName];
    const uris = await new picker.DocumentViewPicker(context).save(options);
    if (!uris || uris.length === 0) {
      return false;
    }
    await fs.copy(fileUri.getUriFromPath(result.zipPath), uris[0]);
    return true;
  }

  static async share(context: common.UIAbilityContext, result: ThemeExportResult): Promise<void> {
    // 分享出去的文件名就是接收方看到的名字，复制一份带 .qytheme 后缀的。
    const sharePath = `${result.workDir}/${result.fileName}`;
    if (!ThemePackageService.exists(sharePath)) {
      fs.copyFileSync(result.zipPath, sharePath);
    }
    let utd = 'general.zip-archive';
    try {
      utd = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(QYTHEME_EXTENSION, 'general.zip-archive');
    } catch (_) {
    }
    const data = new systemShare.SharedData({
      utd: utd,
      uri: fileUri.getUriFromPath(sharePath),
      title: result.fileName
    });
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  static discardExport(result: ThemeExportResult | null): void {
    if (result) ThemePackageService.removeDir(result.workDir);
  }

  /** 选择主题包文件；取消时返回空串。 */
  static async pickPackage(context: Context): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = [`主题包|${QYTHEME_EXTENSION}`];
    const result = await new picker.DocumentViewPicker(context).select(options);
    return result && result.length > 0 ? result[0] : '';
  }

  /** 复制到临时目录、检查压缩包结构、解压、核对清单与每个素材的摘要，算出导入后会有哪些替换。 */
  static async prepareImport(context: Context, uri: string): Promise<ThemeImportPreview> {
    const workDir = `${context.tempDir}/qytheme_import_${Date.now()}`;
    fs.mkdirSync(workDir, true);
    // 出错时把走到的步骤带进提示，用户反馈“无法读取”时能分清是文件、解压还是校验的问题。
    let stage = '读取文件';
    try {
      const zipPath = `${workDir}/source.zip`;
      const sourcePath = ThemePackageService.pathFromUri(uri);
      console.info(`[qytheme] import source uri=${uri} path=${sourcePath} exists=${ThemePackageService.exists(sourcePath)}`);
      if (ThemePackageService.exists(sourcePath)) {
        // 应用自己沙箱里的文件（例如分享收到后已落盘的包）直接拷贝；fs.copy 对这类 URI 会报 EINVAL。
        fs.copyFileSync(sourcePath, zipPath);
      } else {
        const copySource = uri.startsWith('/') ? fileUri.getUriFromPath(uri) : uri;
        await fs.copy(copySource, fileUri.getUriFromPath(zipPath));
      }
      const size = fs.statSync(zipPath).size;
      if (size > ThemePackageLimits.MAX_PACKAGE_BYTES) {
        throw new Error('主题包超过 80 MB，无法导入');
      }
      stage = '检查压缩包';
      const entries = ThemePackageService.inspectZip(zipPath, size);
      const root = ZipEntryInspector.commonRoot(entries);
      const outDir = `${workDir}/out`;
      fs.mkdirSync(outDir, true);
      stage = '解压';
      await zlib.decompressFile(zipPath, outDir);
      fs.unlinkSync(zipPath);
      const baseDir = root ? `${outDir}/${root.substring(0, root.length - 1)}` : outDir;
      stage = '读取清单';
      const manifest = decodeManifest(ThemePackageService.readSmallText(`${baseDir}/manifest.json`));
      stage = '核对素材';
      if (manifest.formatVersion >= 2) {
        await ThemePackageService.collectAssets(entries, root, baseDir, manifest);
      } else {
        ThemePackageService.checkEntries(entries, root, manifest);
        for (const asset of manifest.assets) {
          await ThemePackageService.verifyAsset(baseDir, asset);
        }
      }
      stage = '读取主题设置';
      const theme = decodeTheme(ThemePackageService.readSmallText(`${baseDir}/theme.json`), manifest);
      stage = '整理预览';

      const preview = new ThemeImportPreview();
      preview.workDir = workDir;
      preview.baseDir = baseDir;
      preview.manifest = manifest;
      preview.theme = theme;
      preview.hasLayout = !!theme.layoutJson;
      const ownThemeId = theme.parts ? packThemeId(manifest.packageId) : '';
      if (theme.parts) {
        preview.packageId = manifest.packageId;
        preview.parts = describeParts(theme.parts);
        if (theme.parts.appFont) {
          // 界面字体和阅读字体走同一条安装路径：记成一个字体绑定，安装后换成本机字体名。
          const asset = findAsset(manifest, assetIdFromRef(theme.parts.appFont));
          const font = new ThemePackageFont();
          font.family = ThemePackageService.appFontFamilyKey(manifest.packageId);
          font.name = asset && asset.name ? asset.name : `${manifest.name} 界面字体`;
          font.assetId = asset ? asset.id : '';
          if (font.assetId) theme.fonts.push(font);
        }
        const appSettings = await AppThemeSettingsStore.load(context);
        const schemes = await CustomThemeSchemeStore.load(context, appSettings);
        const existing = CustomThemeSchemeStore.findByPackageId(schemes, manifest.packageId);
        if (existing) {
          preview.updateSchemeId = existing.id;
          preview.updateSchemeName = existing.name;
        }
      }
      if (theme.settingsJson) {
        const settings = JSON.parse(theme.settingsJson) as Record<string, Object>;
        const restriction: SourceRestriction = restrictSources(settings,
          (themeId: string): boolean => themeId === ownThemeId || ThemePackageService.canUseTheme(themeId),
          (themeId: string): boolean => themeId === ownThemeId ||
            (BuiltinThemeRegistry.has(themeId) && themeId !== ThemeIds.CUSTOM),
          (themeId: string): string => BuiltinThemeRegistry.findById(themeId).name,
          BuiltinThemeRegistry.DEFAULT_THEME_ID);
        preview.replaced = restriction.replaced;
        preview.unknown = restriction.unknown;
        ThemePackageService.restrictBackgroundAssets(settings, preview.replaced, ownThemeId);
        ThemePackageService.restrictEmphasisOverrides(settings, preview.lockedBubbles, ownThemeId);
        preview.settingsJson = JSON.stringify(settings);
        for (const key of IMAGE_SETTING_KEYS) {
          const value = settings[key];
          if (typeof value === 'string' && assetIdFromRef(value)) preview.imageCount++;
        }
      }
      if (theme.emphasis) {
        const rules = ReaderRegexFontCodec.decode(theme.emphasis.rulesJson);
        preview.ruleCount = rules.length;
        for (const rule of rules) {
          if (rule.bubbleStyleId === ownThemeId) continue;
          if (!ThemeAccessPolicy.canUseBubbleStyle(rule.bubbleStyleId)) {
            const label = `${rule.name}（${ThemeAccessPolicy.requiredThemeNameForBubbleStyle(rule.bubbleStyleId) || '主题包'}）`;
            if (!preview.lockedBubbles.includes(label)) preview.lockedBubbles.push(label);
          }
        }
      }
      for (const font of theme.fonts) {
        if (font.assetId) {
          preview.bundledFontCount++;
        } else {
          const name = font.name || font.family;
          if (!preview.missingFonts.includes(name)) preview.missingFonts.push(name);
        }
      }
      return preview;
    } catch (e) {
      ThemePackageService.removeDir(workDir);
      const message = (e as Error).message || String(e);
      console.error(`读取主题包失败（${stage}）:`, message);
      throw new Error(message.startsWith('主题包') || message.startsWith('这') ? message : `${message}（${stage}）`);
    }
  }

  private static appFontFamilyKey(packageId: string): string {
    return `qytheme-app-font:${packageId}`;
  }

  static discardImport(preview: ThemeImportPreview | null): void {
    if (preview) ThemePackageService.removeDir(preview.workDir);
  }

  /**
   * 写入导入结果：安装图片、字体和主题包素材，新建（或替换）方案，并给这套方案建一份阅读设置——
   * 以当前（或被替换方案）的设置为底，换上包内排版，包内强调规则追加在原有规则之后。
   */
  static async commitImport(context: Context, uiContext: UIContext | null, preview: ThemeImportPreview,
    replaceSchemeId: string): Promise<ThemeImportResult> {
    let installedPackageId = '';
    try {
      const appSettings = await AppThemeSettingsStore.load(context);
      const schemes = await CustomThemeSchemeStore.load(context, appSettings);
      const activeSchemeId = AppStorage.get<string>(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID) || '';
      const replacesActive = !!replaceSchemeId && appSettings.themeId === ThemeIds.CUSTOM &&
        activeSchemeId === replaceSchemeId;
      if (replaceSchemeId) {
        // 同一个主题包的新版本可以原位更新正在使用的方案，调用方随后重新应用；其他替换仍不允许。
        if (replacesActive && replaceSchemeId !== preview.updateSchemeId) {
          throw new Error('正在使用的方案不能被替换，请先换用其他主题');
        }
      } else if (schemes.length >= CustomThemeQuota.current()) {
        throw new Error(`已达到 ${CustomThemeQuota.current()} 套方案上限，请选择替换一套已有方案`);
      }
      const manifest = preview.manifest;
      const settings: Record<string, Object> | null = preview.settingsJson ?
        JSON.parse(preview.settingsJson) as Record<string, Object> : null;
      if (settings) {
        for (const key of IMAGE_SETTING_KEYS) {
          const value = settings[key];
          const id = typeof value === 'string' ? assetIdFromRef(value) : '';
          if (!id) continue;
          const asset = findAsset(manifest, id);
          if (!asset) {
            settings[key] = '';
            continue;
          }
          const dir = key === 'customPreviewImagePath' ? 'theme_previews' :
            (key.endsWith('ImagePath') ? 'theme_startups' : 'reader_backgrounds');
          settings[key] = fileUri.getUriFromPath(ThemePackageService.installAsset(context, preview.baseDir, asset, dir));
        }
      }

      const baseProfile = replaceSchemeId ?
        await ReaderSettingsStore.loadProfile(context, ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, replaceSchemeId)) :
        await ReaderSettingsStore.load(context);
      const installed = await ThemePackageService.installFonts(context, uiContext, preview, baseProfile);
      const displayNames = new Map<string, string>();
      for (const font of preview.theme.fonts) {
        displayNames.set(font.family, font.name || font.family);
      }
      const profileRecord = ThemePackageService.readerRecord(baseProfile);
      const layout = preview.theme.layoutJson ? JSON.parse(preview.theme.layoutJson) as Record<string, Object> : null;
      const incomingRules: Record<string, Object>[] = preview.theme.emphasis ?
        JSON.parse(JSON.stringify(ReaderRegexFontCodec.cleanRules(
          ReaderRegexFontCodec.decode(preview.theme.emphasis.rulesJson)))) as Record<string, Object>[] : [];
      const result = new ThemeImportResult();
      result.missingFonts = remapFonts(layout, incomingRules, installed, displayNames);
      if (settings && typeof settings['customAppFontFamily'] === 'string' && settings['customAppFontFamily']) {
        // 界面字体绑定也换成本机安装后的字体名；没带文件就退回跟随来源主题。
        const family = settings['customAppFontFamily'] as string;
        const mapped = installed.get(family) || '';
        settings['customAppFontFamily'] = mapped;
        if (!mapped) {
          const name = displayNames.get(family) || family;
          if (!result.missingFonts.includes(name)) result.missingFonts.push(name);
        }
      }
      if (layout) {
        applyLayout(profileRecord, layout);
      }
      profileRecord['themeIndex'] = ReaderThemeHelper.APP_THEME_INDEX;
      profileRecord['lightThemeIndex'] = ReaderThemeHelper.APP_THEME_INDEX;
      profileRecord['darkThemeIndex'] = ReaderThemeHelper.APP_THEME_INDEX;
      if (incomingRules.length > 0 && preview.theme.emphasis) {
        const existing = ReaderRegexFontCodec.encode(ThemePackageService.profileRules(baseProfile));
        const merged = mergeRules(existing, JSON.stringify(incomingRules), Date.now());
        profileRecord['regexFontRulesRaw'] = ReaderRegexFontCodec.encode(
          ReaderRegexFontCodec.decode(merged.rulesJson));
        // 作者开着强调规则就打开，即使规则全都和本机已有的重复（没有新增）也要生效。
        if (preview.theme.emphasis.enabled) {
          profileRecord['regexFontEnabled'] = true;
        }
        result.addedRules = merged.added;
        result.skippedRules = merged.skipped;
      }

      // 包内部件：素材进 theme_packs/<packageId>/，注册为主题 pack:<packageId>。
      const parts = preview.theme.parts;
      if (parts) {
        if (parts.appFont) {
          const family = installed.get(ThemePackageService.appFontFamilyKey(manifest.packageId)) || '';
          if (family) parts.appFontFamily = family;
        }
        ThemePackageService.installPack(context, preview, parts);
        installedPackageId = manifest.packageId;
      }

      let schemeSettings: AppThemeSettings;
      if (settings) {
        schemeSettings = AppThemeSettingsStore.cloneSettings(
          JSON.parse(JSON.stringify(settings)) as AppThemeSettings);
      } else if (parts) {
        // 手写的主题包没有方案设置：所有部件都指向这个包，颜色与阅读背景取包里的令牌。
        const base = AppThemeSettingsStore.createForTheme(packThemeId(manifest.packageId));
        schemeSettings = AppThemeSettingsStore.activateTheme(ThemeIds.CUSTOM, base);
        schemeSettings.customLightStartupTitle = parts.startupLight ? parts.startupLight.title :
          (parts.startupDark ? parts.startupDark.title : '开源轻页');
        schemeSettings.customLightStartupSubtitle = parts.startupLight ? parts.startupLight.subtitle :
          (parts.startupDark ? parts.startupDark.subtitle : '');
        schemeSettings.customDarkStartupTitle = parts.startupDark ? parts.startupDark.title :
          schemeSettings.customLightStartupTitle;
        schemeSettings.customDarkStartupSubtitle = parts.startupDark ? parts.startupDark.subtitle :
          schemeSettings.customLightStartupSubtitle;
        const installedPack = ThemePackRegistry.getByPackageId(manifest.packageId);
        if (installedPack && installedPack.preview) schemeSettings.customPreviewImagePath = installedPack.preview;
      } else {
        throw new Error('主题包的主题设置已损坏');
      }
      schemeSettings.themeId = ThemeIds.CUSTOM;
      schemeSettings.themeBookCoverEnabled = false;
      schemeSettings.themeApplyLayoutEnabled = false;
      const scheme = await CustomThemeSchemeStore.addImported(context, appSettings, manifest.name, schemeSettings,
        manifest.author, replaceSchemeId, parts ? manifest.packageId : '');
      if (!scheme) {
        throw new Error(replaceSchemeId ? '要替换的方案已不存在' :
          `已达到 ${CustomThemeQuota.current()} 套方案上限`);
      }
      await ReaderSettingsStore.writeProfile(context, ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id),
        JSON.parse(JSON.stringify(profileRecord)) as ReaderSettings);
      if (layout) {
        // 包里带了作者的排版：应用这套主题时默认沿用它，而不是重置成预设排版。
        await ReaderSettingsStore.markTypographyBound(context,
          ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id));
      }
      result.scheme = scheme;
      result.replacedActive = replacesActive;
      installedPackageId = '';
      if (replaceSchemeId) {
        await ThemePackageService.cleanupImportedFiles(context);
      }
      return result;
    } catch (e) {
      // 新装的包没有方案引用就是垃圾；更新失败时旧版本已被覆盖，留给清理按引用处理。
      if (installedPackageId && !preview.updateSchemeId) ThemePackStore.uninstall(context, installedPackageId);
      throw e as Error;
    } finally {
      ThemePackageService.discardImport(preview);
    }
  }

  /** 素材按内容命名复制进包目录，记录写成相对路径，然后注册。 */
  private static installPack(context: Context, preview: ThemeImportPreview, parts: ThemePackageParts): void {
    const manifest = preview.manifest;
    const dir = ThemePackStore.prepareDir(context, manifest.packageId);
    const paths = new Map<string, string>();
    for (const ref of partsAssetRefs(parts)) {
      const asset = findAsset(manifest, assetIdFromRef(ref));
      if (!asset) {
        throw new Error('主题包缺少素材文件');
      }
      const extension = asset.path.substring(asset.path.lastIndexOf('.') + 1);
      const relativePath = assetPath(asset.id, extension);
      const target = `${dir}/${relativePath}`;
      if (!ThemePackageService.exists(target)) {
        fs.copyFileSync(`${preview.baseDir}/${asset.path}`, target);
      }
      paths.set(ref, relativePath);
    }
    const record = new ThemePackRecord();
    record.packageId = manifest.packageId;
    record.name = manifest.name;
    record.author = manifest.author;
    record.version = manifest.version;
    record.description = manifest.description;
    record.baseTheme = isPackThemeId(manifest.baseTheme) ? BuiltinThemeRegistry.DEFAULT_THEME_ID :
      BuiltinThemeRegistry.normalizeBuiltinId(manifest.baseTheme);
    record.installedAt = Date.now();
    record.credits = manifest.credits;
    record.parts = mapPartsAssetRefs(parts, (ref: string): string => paths.get(ref) || '');
    ThemePackStore.install(context, record);
  }

  /** 导出时把已安装主题包的素材复制进包，按格式 2 登记到清单；parts 里的引用就是包内路径。 */
  private static async packParts(bundled: InstalledThemePack, assetsDir: string,
    manifest: ThemePackageManifest): Promise<ThemePackageParts> {
    const record = bundled.record.parts;
    for (const relativePath of partsAssetRefs(record)) {
      const source = `${bundled.dir}/${relativePath}`;
      if (!ThemePackageService.exists(source)) {
        throw new Error('主题包的素材已丢失，请重新导入这个主题包后再导出');
      }
      if (findAssetByPath(manifest, relativePath)) continue;
      const extension = assetPathExtension(relativePath);
      const kind = kindForExtension(extension);
      const size = fs.statSync(source).size;
      if (!kind || size <= 0 || size > maxBytesForKind(kind)) {
        throw new Error('主题包素材超出大小上限');
      }
      const sha256 = (await hash.hash(source, 'sha256')).toLowerCase();
      const asset = new ThemePackageAsset();
      asset.id = sha256.substring(0, 24);
      asset.kind = kind;
      asset.size = size;
      asset.sha256 = sha256;
      asset.path = relativePath;
      manifest.assets.push(asset);
      fs.copyFileSync(source, `${assetsDir}/${relativePath.substring('assets/'.length)}`);
    }
    return JSON.parse(JSON.stringify(record)) as ThemePackageParts;
  }

  /** 删除或替换方案后，清掉没有任何方案再引用的导入图片（只清本功能写入的 qytheme_ 文件）。 */
  static async cleanupImportedFiles(context: Context): Promise<void> {
    try {
      const appSettings = await AppThemeSettingsStore.load(context);
      const schemes = await CustomThemeSchemeStore.load(context, appSettings);
      const referenced = new Set<string>();
      const collect = (settings: AppThemeSettings): void => {
        const record = ThemePackageService.settingsRecord(settings);
        for (const key of IMAGE_SETTING_KEYS) {
          const value = record[key];
          if (typeof value === 'string' && isLocalFileReference(value)) {
            referenced.add(ThemePackageService.pathFromUri(value));
          }
        }
      };
      collect(appSettings);
      const referencedPacks = new Set<string>();
      const collectPacks = (settings: AppThemeSettings): void => {
        for (const id of ThemePackageService.referencedPackageIds(ThemePackageService.settingsRecord(settings))) {
          referencedPacks.add(id);
        }
      };
      collectPacks(appSettings);
      for (const scheme of schemes) {
        collect(scheme.settings);
        collectPacks(scheme.settings);
        if (scheme.packageId) referencedPacks.add(scheme.packageId);
      }
      ThemePackStore.uninstallUnreferenced(context, referencedPacks);
      for (const dir of ['theme_startups', 'theme_previews', 'reader_backgrounds']) {
        const fullDir = `${context.filesDir}/${dir}`;
        let names: string[] = [];
        try {
          names = fs.listFileSync(fullDir);
        } catch (_) {
          continue;
        }
        for (const name of names) {
          const path = `${fullDir}/${name}`;
          if (name.startsWith(ThemePackageService.IMPORTED_FILE_PREFIX) && !referenced.has(path)) {
            fs.unlinkSync(path);
          }
        }
      }
    } catch (e) {
      console.warn('清理导入主题图片失败:', (e as Error).message);
    }
  }

  /** 导入方能否使用某个内置主题的部件：免费、已获得或会员主题库内；试用中的主题不算。 */
  static canUseTheme(themeId: string): boolean {
    if (ThemePackRegistry.isPackId(themeId)) return ThemePackRegistry.has(themeId);
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE) return AccountSessionStore.hasOwnedEntitlement(themeId);
    return BuiltinThemeRegistry.isFree(themeId) || AccountSessionStore.hasValidEntitlement(themeId);
  }

  // ---- 导出辅助 ----

  private static async schemeProfile(context: Context, scheme: CustomThemeScheme): Promise<ReaderSettings> {
    return await ReaderSettingsStore.loadProfile(context, ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id));
  }

  private static profileRules(profile: ReaderSettings): ReaderRegexFontRule[] {
    const legacy = new ReaderRegexLegacySettings();
    legacy.pattern = profile.regexFontPattern;
    legacy.fontMode = profile.regexFontMode;
    legacy.fontFamily = profile.regexFontFamily;
    legacy.fontSize = profile.regexFontSize;
    legacy.shadowColor = profile.regexShadowColor;
    return ReaderRegexFontCodec.decode(profile.regexFontRulesRaw, legacy);
  }

  /** 排版和规则实际绑定的自定义字体名（去重）。 */
  private static boundFamilies(profileRecord: Record<string, Object>, rules: ReaderRegexFontRule[],
    appFontFamily: string = ''): string[] {
    const families: string[] = [];
    const add = (mode: Object, family: Object): void => {
      if (mode === 'custom' && typeof family === 'string' && family && !families.includes(family)) {
        families.push(family);
      }
    };
    add('custom', appFontFamily);
    add(profileRecord['bodyFontMode'], profileRecord['bodyFontFamily']);
    add(profileRecord['titleFontMode'], profileRecord['titleFontFamily']);
    for (const rule of rules) {
      add(rule.fontMode, rule.fontFamily);
    }
    return families;
  }

  /**
   * 这套方案实际生效的自定义字体：正文、标题（跟随全局字体且全局用的是自定义字体时算全局这款），
   * withRules 时再加上强调规则用的字体（规则总开关关着时不算）。字体库里其他字体不在其列。
   */
  private static effectiveFonts(profile: ReaderSettings, withRules: boolean,
    appFontFamily: string = ''): ThemeExportFontInfo[] {
    const library = ThemePackageService.fontLibrary(profile.customFontsRaw);
    const globalCustom = profile.fontMode === ReaderSettingsStore.FONT_MODE_CUSTOM ? profile.fontFamily : '';
    const result: ThemeExportFontInfo[] = [];
    const add = (mode: string, family: string, usage: string, ruleOnly: boolean): void => {
      const resolved = mode === 'custom' ? family : (mode === 'global' && !ruleOnly ? globalCustom : '');
      if (!resolved) return;
      const existing = result.find((item: ThemeExportFontInfo): boolean => item.family === resolved);
      if (existing) {
        if (!existing.usage.includes(usage)) existing.usage += `、${usage}`;
        existing.ruleOnly = existing.ruleOnly && ruleOnly;
        return;
      }
      const info = new ThemeExportFontInfo();
      info.family = resolved;
      info.usage = usage;
      info.ruleOnly = ruleOnly;
      const item = library.find((font: CustomFontRecord): boolean => font.familyName === resolved);
      if (item) {
        info.name = ReaderFontHelper.resolveDisplayName(item.sourceName, item.filePath);
        info.filePath = item.filePath;
        info.available = ThemePackageService.exists(item.filePath);
        info.size = info.available ? fs.statSync(item.filePath).size : 0;
      } else {
        info.name = resolved;
      }
      result.push(info);
    };
    add(profile.bodyFontMode, profile.bodyFontFamily, '正文', false);
    add(profile.titleFontMode, profile.titleFontFamily, '标题', false);
    if (appFontFamily) add('custom', appFontFamily, '界面', false);
    if (withRules && profile.regexFontEnabled) {
      for (const rule of ThemePackageService.profileRules(profile)) {
        add(rule.fontMode, rule.fontFamily, '强调规则', true);
      }
    }
    return result;
  }

  private static fontDisplayName(profile: ReaderSettings, family: string): string {
    const item = ThemePackageService.fontLibrary(profile.customFontsRaw)
      .find((font: CustomFontRecord): boolean => font.familyName === family);
    return item ? ReaderFontHelper.resolveDisplayName(item.sourceName, item.filePath) : '';
  }

  private static async packAsset(path: string, assetsDir: string, kind: string,
    name: string): Promise<ThemePackageAsset> {
    const size = fs.statSync(path).size;
    const maxSize = kind === ThemePackageAssetKinds.FONT ?
      ThemePackageLimits.MAX_FONT_BYTES : ThemePackageLimits.MAX_IMAGE_BYTES;
    if (size <= 0 || size > maxSize) {
      throw new Error(kind === ThemePackageAssetKinds.FONT ? `字体「${name}」超过 40 MB，无法附带` :
        '图片超过 20 MB，无法导出');
    }
    const extension = sniffAssetExtension(ThemePackageService.readHead(path));
    if (!extension || kindForExtension(extension) !== kind) {
      throw new Error(kind === ThemePackageAssetKinds.FONT ? `字体「${name}」的格式不支持` : '有图片的格式不支持导出');
    }
    const sha256 = (await hash.hash(path, 'sha256')).toLowerCase();
    const asset = new ThemePackageAsset();
    asset.id = sha256.substring(0, 24);
    asset.kind = kind;
    asset.size = size;
    asset.sha256 = sha256;
    asset.name = name;
    asset.path = assetPath(asset.id, extension);
    fs.copyFileSync(path, `${assetsDir}/${asset.id}.${extension}`);
    return asset;
  }

  // ---- 导入辅助 ----

  private static inspectZip(zipPath: string, size: number): ZipEntryInfo[] {
    const file = fs.openSync(zipPath, fs.OpenMode.READ_ONLY);
    try {
      const limits = new ZipInspectLimits();
      limits.maxEntries = ThemePackageLimits.MAX_ZIP_ENTRIES;
      limits.maxTotalUncompressed = ThemePackageLimits.MAX_TOTAL_UNCOMPRESSED;
      limits.maxEntryUncompressed = ThemePackageLimits.MAX_FONT_BYTES;
      return ZipEntryInspector.inspect(size, (offset: number, length: number): Uint8Array => {
        const buffer = new ArrayBuffer(length);
        const read = fs.readSync(file.fd, buffer, { offset: offset, length: length });
        return new Uint8Array(buffer, 0, read);
      }, limits);
    } finally {
      fs.closeSync(file);
    }
  }

  /** 包里只能有 manifest.json、theme.json 和清单列出的素材，素材大小要与清单一致。 */
  private static checkEntries(entries: ZipEntryInfo[], root: string, manifest: ThemePackageManifest): void {
    const found = new Set<string>();
    for (const entry of entries) {
      const name = entry.name.substring(root.length);
      if (entry.directory) {
        if (name === '' || name === 'assets/') continue;
        throw new Error('主题包内含有无法识别的内容');
      }
      if (name === 'manifest.json' || name === 'theme.json') {
        if (entry.uncompressedSize > ThemePackageLimits.MAX_JSON_BYTES) {
          throw new Error('主题包的设置文件过大');
        }
        found.add(name);
        continue;
      }
      const asset = manifest.assets.find((item: ThemePackageAsset): boolean => item.path === name);
      if (!asset || asset.size !== entry.uncompressedSize) {
        throw new Error('主题包内含有无法识别的内容');
      }
      found.add(name);
    }
    if (!found.has('manifest.json') || !found.has('theme.json')) {
      throw new Error('主题包不完整');
    }
    for (const asset of manifest.assets) {
      if (!found.has(asset.path)) {
        throw new Error('主题包缺少素材文件');
      }
    }
  }

  /**
   * 格式 2：assets/ 下的文件就是素材，清单里写没写都算；清单写了大小或摘要就核对。
   * 每个素材嗅探类型、算摘要并生成 ID；SVG 另做自包含检查。
   */
  private static async collectAssets(entries: ZipEntryInfo[], root: string, baseDir: string,
    manifest: ThemePackageManifest): Promise<void> {
    const found = new Set<string>();
    for (const entry of entries) {
      const name = entry.name.substring(root.length);
      if (entry.directory) {
        if (name === '' || name === 'assets/') continue;
        throw new Error('主题包内含有无法识别的内容');
      }
      if (name === 'manifest.json' || name === 'theme.json') {
        if (entry.uncompressedSize > ThemePackageLimits.MAX_JSON_BYTES) {
          throw new Error('主题包的设置文件过大');
        }
        found.add(name);
        continue;
      }
      const extension = assetPathExtension(name);
      if (!extension) {
        throw new Error(`主题包内有无法识别的文件：${sanitizeThemeName(name.replace(/[\/]/g, ' / '))}`);
      }
      const kind = kindForExtension(extension);
      if (entry.uncompressedSize <= 0 || entry.uncompressedSize > maxBytesForKind(kind)) {
        throw new Error('主题包素材超出大小上限');
      }
      let asset = findAssetByPath(manifest, name);
      if (!asset) {
        if (manifest.assets.length >= ThemePackageLimits.MAX_ASSETS) {
          throw new Error('主题包素材数量超出上限');
        }
        asset = new ThemePackageAsset();
        asset.path = name;
        asset.kind = kind;
        manifest.assets.push(asset);
      } else if (asset.size > 0 && asset.size !== entry.uncompressedSize) {
        throw new Error('主题包清单登记的素材大小与文件不符');
      }
      if (kind === ThemePackageAssetKinds.FONT && !manifest.requires.includes(ThemePackageFeatures.FONTS)) {
        throw new Error('主题包带了字体文件，清单的 requires 需要加上 fonts-v1');
      }
      found.add(name);
    }
    if (!found.has('manifest.json') || !found.has('theme.json')) {
      throw new Error('主题包不完整');
    }
    for (const asset of manifest.assets) {
      if (!found.has(asset.path)) {
        throw new Error(`主题包缺少素材文件：${asset.path}`);
      }
      const path = `${baseDir}/${asset.path}`;
      if (!ThemePackageService.exists(path)) {
        throw new Error(`主题包缺少素材文件：${asset.path}`);
      }
      const extension = assetPathExtension(asset.path);
      const sniffed = sniffAssetExtension(ThemePackageService.readHead(path));
      if (sniffed !== extension) {
        throw new Error(`主题包素材 ${asset.path} 的内容与扩展名不符`);
      }
      const digest = (await hash.hash(path, 'sha256')).toLowerCase();
      if (asset.sha256 && asset.sha256 !== digest) {
        throw new Error('主题包已损坏（素材校验失败）');
      }
      asset.sha256 = digest;
      asset.id = digest.substring(0, 24);
      asset.size = fs.statSync(path).size;
      if (asset.kind === ThemePackageAssetKinds.VECTOR) {
        const problem = checkSvgSource(fs.readTextSync(path));
        if (problem) {
          throw new Error(`主题包素材 ${asset.path}：${problem}`);
        }
      }
    }
  }

  private static async verifyAsset(baseDir: string, asset: ThemePackageAsset): Promise<void> {
    const path = `${baseDir}/${asset.path}`;
    if (!ThemePackageService.exists(path) || fs.statSync(path).size !== asset.size) {
      throw new Error('主题包缺少素材文件');
    }
    const dot = asset.path.lastIndexOf('.');
    if (sniffAssetExtension(ThemePackageService.readHead(path)) !== asset.path.substring(dot + 1)) {
      throw new Error('主题包内有素材格式与声明不符');
    }
    const digest = (await hash.hash(path, 'sha256')).toLowerCase();
    if (digest !== asset.sha256) {
      throw new Error('主题包已损坏（素材校验失败）');
    }
  }

  /** 方案覆盖的气泡样式若导入方用不了（未获得的主题、没装的包），改回跟随来源主题。 */
  private static restrictEmphasisOverrides(settings: Record<string, Object>, locked: string[],
    ownThemeId: string): void {
    for (const key of ['customLightEmphasis', 'customDarkEmphasis']) {
      const override = settings[key];
      if (!override || typeof override !== 'object') continue;
      const record = override as Record<string, Object>;
      const style = typeof record['bubbleStyle'] === 'string' ? record['bubbleStyle'] as string : '';
      if (!style || style === ownThemeId || ThemeAccessPolicy.canUseBubbleStyle(style)) continue;
      record['bubbleStyle'] = '';
      const label = `${key === 'customLightEmphasis' ? '浅色' : '深色'} · 方案气泡样式（${
        ThemeAccessPolicy.requiredThemeNameForBubbleStyle(style) || '主题包'}）`;
      if (!locked.includes(label)) locked.push(label);
    }
  }

  /** 包内阅读背景若是内置素材键，导入方得能使用拥有它的某个主题，否则换成替代主题的背景。 */
  private static restrictBackgroundAssets(settings: Record<string, Object>, replaced: string[],
    ownThemeId: string = ''): void {
    const themes: ThemePack[] = BuiltinThemeRegistry.all();
    const fallback = BuiltinThemeRegistry.findById(BuiltinThemeRegistry.DEFAULT_THEME_ID);
    const modes: string[][] = [['customLightReaderBackgroundAssetId', 'light', '浅色'],
      ['customDarkReaderBackgroundAssetId', 'dark', '深色']];
    for (const mode of modes) {
      const value = settings[mode[0]];
      if (typeof value !== 'string' || !value || assetIdFromRef(value)) continue;
      if (isPackThemeId(value)) {
        const packageId = packageIdOfThemeId(value);
        if ((ownThemeId && packageIdOfThemeId(ownThemeId) === packageId) || ThemePackRegistry.has(value)) continue;
        settings[mode[0]] = mode[1] === 'light' ? fallback.light.reader.backgroundAssetId :
          fallback.dark.reader.backgroundAssetId;
        replaced.push(`${mode[2]} · 阅读背景素材`);
        continue;
      }
      const allowed = themes.some((theme: ThemePack): boolean => ThemePackageService.canUseTheme(theme.id) &&
        (theme.light.reader.backgroundAssetId === value || theme.dark.reader.backgroundAssetId === value));
      if (!allowed) {
        settings[mode[0]] = mode[1] === 'light' ? fallback.light.reader.backgroundAssetId :
          fallback.dark.reader.backgroundAssetId;
        replaced.push(`${mode[2]} · 阅读背景素材`);
      }
    }
  }

  /** 素材按内容命名：同一张图重复导入只存一份。 */
  private static installAsset(context: Context, baseDir: string, asset: ThemePackageAsset, dir: string): string {
    const fullDir = `${context.filesDir}/${dir}`;
    fs.mkdirSync(fullDir, true);
    const dot = asset.path.lastIndexOf('.');
    const target = `${fullDir}/${ThemePackageService.IMPORTED_FILE_PREFIX}${asset.id}${asset.path.substring(dot)}`;
    if (!ThemePackageService.exists(target) || fs.statSync(target).size !== asset.size) {
      fs.copyFileSync(`${baseDir}/${asset.path}`, target);
    }
    return target;
  }

  /**
   * 安装包内字体：字体库里已有内容相同的文件就复用，否则存进字体目录并加入字体库。
   * 返回“导出方字体名 → 本机字体名”。
   */
  private static async installFonts(context: Context, uiContext: UIContext | null, preview: ThemeImportPreview,
    current: ReaderSettings): Promise<Map<string, string>> {
    const installed = new Map<string, string>();
    const bundled = preview.theme.fonts.filter((font: ThemePackageFont): boolean => !!font.assetId);
    if (bundled.length === 0) return installed;
    const library = ThemePackageService.fontLibrary(current.customFontsRaw);
    let changed = false;
    for (const font of bundled) {
      const asset = findAsset(preview.manifest, font.assetId);
      if (!asset) continue;
      let family = '';
      for (const item of library) {
        if (!ThemePackageService.exists(item.filePath) || fs.statSync(item.filePath).size !== asset.size) continue;
        if ((await hash.hash(item.filePath, 'sha256')).toLowerCase() === asset.sha256) {
          family = item.familyName;
          break;
        }
      }
      if (!family) {
        const target = ThemePackageService.installAsset(context, preview.baseDir, asset, 'reader_fonts');
        family = ReaderFontHelper.stableFontFamily(target);
        if (!library.some((item: CustomFontRecord): boolean => item.filePath === target)) {
          const record = new CustomFontRecord();
          record.familyName = family;
          record.filePath = target;
          record.sourceName = font.name || asset.name || '主题字体';
          library.push(record);
          changed = true;
        }
      }
      installed.set(font.family, family);
    }
    if (changed) {
      const data = new CustomFontList();
      data.fonts = library;
      const latest = await ReaderSettingsStore.load(context);
      await ReaderSettingsStore.saveFontSettings(context, latest.fontFamily, latest.fontFilePath,
        latest.fontSourceName, latest.fontMode, latest.systemFontFamily, JSON.stringify(data));
      current.customFontsRaw = JSON.stringify(data);
      await ReaderFontBootstrap.registerFromSettings(context, uiContext, 'theme-import');
    }
    return installed;
  }

  // ---- 通用 ----

  private static fontLibrary(raw: string): CustomFontRecord[] {
    const text = (raw || '').trim();
    if (!text) return [];
    try {
      const parsed = JSON.parse(text) as CustomFontList | CustomFontRecord[];
      const list = Array.isArray(parsed) ? parsed as CustomFontRecord[] : ((parsed as CustomFontList).fonts || []);
      const result: CustomFontRecord[] = [];
      for (const item of list) {
        if (!item || !item.filePath) continue;
        const record = new CustomFontRecord();
        record.familyName = item.familyName || ReaderFontHelper.stableFontFamily(item.filePath);
        record.filePath = item.filePath;
        record.sourceName = item.sourceName || '';
        result.push(record);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  private static settingsRecord(settings: AppThemeSettings): Record<string, Object> {
    return JSON.parse(JSON.stringify(settings)) as Record<string, Object>;
  }

  private static readerRecord(settings: ReaderSettings): Record<string, Object> {
    return JSON.parse(JSON.stringify(settings)) as Record<string, Object>;
  }

  private static pathFromUri(value: string): string {
    if (value.startsWith('file://')) {
      try {
        return new fileUri.FileUri(value).path;
      } catch (_) {
        return decodeURIComponent(value.substring(7));
      }
    }
    return value;
  }

  private static exists(path: string): boolean {
    try {
      return !!path && fs.accessSync(path);
    } catch (_) {
      return false;
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

  private static readSmallText(path: string): string {
    if (!ThemePackageService.exists(path) || fs.statSync(path).size > ThemePackageLimits.MAX_JSON_BYTES) {
      throw new Error('主题包不完整');
    }
    return fs.readTextSync(path);
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
      console.warn('清理主题包临时目录失败:', (e as Error).message);
    }
  }

  private static randomHex(bytes: number): string {
    const random = new Uint8Array(bytes);
    for (let i = 0; i < bytes; i++) {
      random[i] = Math.floor(Math.random() * 256);
    }
    let hex = '';
    for (let i = 0; i < random.length; i++) {
      hex += (random[i] < 16 ? '0' : '') + random[i].toString(16);
    }
    return hex;
  }

  private static appVersion(): string {
    try {
      return bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName || '';
    } catch (_) {
      return '';
    }
  }
}
