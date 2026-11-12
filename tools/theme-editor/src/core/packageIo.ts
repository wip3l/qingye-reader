/**
 * 编辑器的主题包读写。不依赖 Electron 与 DOM，Node 回归测试直接加载。
 *
 * 校验全部走应用自己的格式层（entry/.../theme/share 下的 ThemePackageFormat.ts 与 ZipEntryInspector.ts），
 * 流程与 ThemePackageService 导入时一致：检查 ZIP 中央目录 → 去掉公共顶层目录 → 解码清单 → 核对素材 → 解码 theme.json。
 * 应用会拒绝的包，编辑器在导出前就拒绝，错误文案也相同。
 *
 * 编辑模型里的素材引用一律是 assets/<文件名>（格式 2 的写法）；打开应用导出的包时把 qytheme-asset:<id> 换成路径，
 * 方案设置里指向这个包自己的来源换回 pack:self，这样改了 packageId 也不会断。
 */
import { unzipSync, zipSync, strToU8, strFromU8 } from 'fflate';
import type { Zippable } from 'fflate';
import {
  QYTHEME_ASSET_PREFIX, ThemePackageAsset, ThemePackageAssetKinds, ThemePackageFeatures, ThemePackageLimits,
  ThemePackageManifest, ThemePackageTheme, IMAGE_SETTING_KEYS, assetPathExtension, checkSvgSource, decodeManifest,
  decodeTheme, encodeParts, findAssetByPath, isValidPackageId, kindForExtension, mapPartsAssetRefs, maxBytesForKind,
  packThemeId, replaceOwnPackIdWithSelf, sniffAssetExtension
} from '../../../../entry/src/main/ets/theme/share/ThemePackageFormat.ts';
import { ZipEntryInfo, ZipEntryInspector, ZipInspectLimits } from '../../../../entry/src/main/ets/theme/share/ZipEntryInspector.ts';

export type Json = any;

export interface EditorAsset {
  path: string;
  bytes: Uint8Array;
  kind: string;
  ext: string;
  width: number;
  height: number;
}

export interface EditorManifest {
  packageId: string;
  name: string;
  author: string;
  version: string;
  description: string;
  baseTheme: string;
  credits: { packageId: string; name: string; author: string } | null;
  /** 打开时清单里的 requires，导出时与按内容算出的能力取并集（只保留应用认得的）。 */
  requires: string[];
}

export interface EditorFont {
  family: string;
  name: string;
  /** 字体文件的 assets/ 路径；空表示导出方当时没有附带字体文件。 */
  assetPath: string;
}

export interface EditorProject {
  manifest: EditorManifest;
  /** 与 theme.json 的 parts 同形，素材写 assets/ 路径。 */
  parts: Json;
  /** 应用导出的方案包才有：原样保留、原样写回。 */
  settings: Json | null;
  layout: Json | null;
  emphasis: { enabled: boolean; rules: Json[] } | null;
  fonts: EditorFont[];
  assets: Map<string, EditorAsset>;
  /** 打开时的格式版本；新建为 2。 */
  sourceFormatVersion: number;
}

export interface LoadResult {
  project: EditorProject;
  /** 严格校验没通过时的原因；此时工程是尽量读出来的，修好后可以再导出。 */
  problems: string[];
}

export type FileMap = Map<string, Uint8Array>;

const IMAGE_MIME: Record<string, string> = {
  png: 'image/png', jpg: 'image/jpeg', webp: 'image/webp', gif: 'image/gif', bmp: 'image/bmp', svg: 'image/svg+xml',
  ttf: 'font/ttf', otf: 'font/otf', ttc: 'font/collection'
};

export function mimeForExtension(ext: string): string {
  return IMAGE_MIME[ext] || 'application/octet-stream';
}

export function emptyParts(): Json {
  return {
    light: { colors: {}, reader: {}, emphasis: {} },
    dark: { colors: {}, reader: {}, emphasis: {} },
    ttsPanel: { light: {}, dark: {} },
    navigation: {},
    book: { covers: [] },
    startup: { light: {}, dark: {} },
    bubble: {},
    homeBackdrop: {},
    logo: '',
    preview: '',
    radius: {},
    typography: {}
  };
}

export function randomPackageId(): string {
  let hex = '';
  for (let i = 0; i < 8; i++) hex += Math.floor(Math.random() * 16).toString(16);
  return `custom-${hex}`;
}

export function newProject(baseTheme: string): EditorProject {
  return {
    manifest: { packageId: randomPackageId(), name: '', author: '', version: '1.0', description: '', baseTheme,
      credits: null, requires: [] },
    parts: emptyParts(),
    settings: null,
    layout: null,
    emphasis: null,
    fonts: [],
    assets: new Map(),
    sourceFormatVersion: 2
  };
}

// ---- 图片尺寸（只读文件头，不解码） ----

export function imageSize(bytes: Uint8Array, ext: string): { width: number; height: number } {
  const none = { width: 0, height: 0 };
  const b = bytes;
  try {
    if (ext === 'png' && b.length >= 24) {
      return { width: readU32BE(b, 16), height: readU32BE(b, 20) };
    }
    if (ext === 'gif' && b.length >= 10) return { width: b[6] | (b[7] << 8), height: b[8] | (b[9] << 8) };
    if (ext === 'bmp' && b.length >= 26) {
      return { width: Math.abs(readI32LE(b, 18)), height: Math.abs(readI32LE(b, 22)) };
    }
    if (ext === 'webp' && b.length >= 30) {
      const chunk = String.fromCharCode(b[12], b[13], b[14], b[15]);
      if (chunk === 'VP8 ') return { width: (b[26] | (b[27] << 8)) & 0x3FFF, height: (b[28] | (b[29] << 8)) & 0x3FFF };
      if (chunk === 'VP8L') {
        return { width: 1 + (((b[22] & 0x3F) << 8) | b[21]), height: 1 + (((b[24] & 0x0F) << 10) | (b[23] << 2) | ((b[22] & 0xC0) >> 6)) };
      }
      if (chunk === 'VP8X') return { width: 1 + (b[24] | (b[25] << 8) | (b[26] << 16)), height: 1 + (b[27] | (b[28] << 8) | (b[29] << 16)) };
      return none;
    }
    if (ext === 'jpg') {
      let i = 2;
      while (i + 9 < b.length) {
        if (b[i] !== 0xFF) { i++; continue; }
        const marker = b[i + 1];
        if (marker === 0xD8 || marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7) || marker === 0xFF) { i += marker === 0xFF ? 1 : 2; continue; }
        if ((marker >= 0xC0 && marker <= 0xCF) && marker !== 0xC4 && marker !== 0xC8 && marker !== 0xCC) {
          return { width: (b[i + 7] << 8) | b[i + 8], height: (b[i + 5] << 8) | b[i + 6] };
        }
        i += 2 + ((b[i + 2] << 8) | b[i + 3]);
      }
      return none;
    }
    if (ext === 'svg') {
      const text = strFromU8(b.subarray(0, Math.min(b.length, 4096)));
      const viewBox = /viewBox\s*=\s*["']\s*[-\d.]+[\s,]+[-\d.]+[\s,]+([\d.]+)[\s,]+([\d.]+)\s*["']/i.exec(text);
      if (viewBox) return { width: Math.round(+viewBox[1]), height: Math.round(+viewBox[2]) };
      const w = /<svg[^>]*\swidth\s*=\s*["']([\d.]+)/i.exec(text);
      const h = /<svg[^>]*\sheight\s*=\s*["']([\d.]+)/i.exec(text);
      if (w && h) return { width: Math.round(+w[1]), height: Math.round(+h[1]) };
    }
  } catch (_) {
    // 文件头不完整时当作未知尺寸。
  }
  return none;
}

function readU32BE(b: Uint8Array, o: number): number {
  return ((b[o] << 24) >>> 0) + (b[o + 1] << 16) + (b[o + 2] << 8) + b[o + 3];
}

function readI32LE(b: Uint8Array, o: number): number {
  return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
}

/** 把一份文件做成编辑器素材：按文件头认格式，扩展名跟着内容走。认不出时返回原因。 */
export function makeAsset(path: string, bytes: Uint8Array): EditorAsset | string {
  const ext = sniffAssetExtension(bytes.subarray(0, 64));
  const kind = ext ? kindForExtension(ext) : '';
  if (!kind) return '认不出这个文件的格式，只支持 PNG、JPG、WebP、GIF、BMP、SVG、TTF、OTF、TTC';
  if (bytes.length > maxBytesForKind(kind)) {
    return `文件过大（${formatSize(bytes.length)}），这类素材上限 ${formatSize(maxBytesForKind(kind))}`;
  }
  if (kind === ThemePackageAssetKinds.VECTOR) {
    const problem = checkSvgSource(strFromU8(bytes));
    if (problem) return problem;
  }
  const size = kind === ThemePackageAssetKinds.FONT ? { width: 0, height: 0 } : imageSize(bytes, ext);
  return { path, bytes, kind, ext, width: size.width, height: size.height };
}

export function formatSize(n: number): string {
  if (n >= 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${Math.max(1, Math.round(n / 1024))} KB`;
}

/** 用户文件名 → assets/ 允许的名字（[A-Za-z0-9][A-Za-z0-9_-]*，扩展名按实际格式）。 */
export function safeAssetPath(fileName: string, ext: string, taken: (path: string) => boolean): string {
  const dot = fileName.lastIndexOf('.');
  const stem = (dot > 0 ? fileName.substring(0, dot) : fileName).toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '_').replace(/^[^a-z0-9]+/, '').replace(/_+$/, '').substring(0, 48) || 'asset';
  let path = `assets/${stem}.${ext}`;
  let n = 2;
  while (taken(path)) path = `assets/${stem}_${n++}.${ext}`;
  return path;
}

// ---- ZIP ----

function zipLimits(): ZipInspectLimits {
  const limits = new ZipInspectLimits();
  limits.maxEntries = ThemePackageLimits.MAX_ZIP_ENTRIES;
  limits.maxTotalUncompressed = ThemePackageLimits.MAX_TOTAL_UNCOMPRESSED;
  limits.maxEntryUncompressed = ThemePackageLimits.MAX_FONT_BYTES;
  return limits;
}

/** 与应用导入一致：先查中央目录，再解压，去掉公共顶层目录。 */
export function readZip(bytes: Uint8Array): FileMap {
  if (bytes.length > ThemePackageLimits.MAX_PACKAGE_BYTES) throw new Error('主题包超过 80 MB，无法导入');
  const entries: ZipEntryInfo[] = ZipEntryInspector.inspect(bytes.length,
    (offset: number, length: number): Uint8Array => bytes.subarray(offset, Math.min(bytes.length, offset + length)),
    zipLimits());
  const root = ZipEntryInspector.commonRoot(entries);
  const raw = unzipSync(bytes);
  const files: FileMap = new Map();
  for (const entry of entries) {
    if (entry.directory) {
      const name = entry.name.substring(root.length);
      if (name === '' || name === 'assets/') continue;
      throw new Error('主题包内含有无法识别的内容');
    }
    const data = raw[entry.name];
    if (!data) throw new Error('主题包已损坏');
    files.set(entry.name.substring(root.length), data);
  }
  return files;
}

export function writeZip(files: FileMap): Uint8Array {
  const zippable: Zippable = {};
  for (const [name, data] of files) {
    const ext = name.substring(name.lastIndexOf('.') + 1);
    // 位图本身已压缩，直接存储；JSON、SVG 和字体压一下。
    const store = ext === 'png' || ext === 'jpg' || ext === 'webp' || ext === 'gif';
    zippable[name] = [data, { level: store ? 0 : 6 }];
  }
  return zipSync(zippable);
}

// ---- 摘要 ----

const digestCache: WeakMap<Uint8Array, string> = new WeakMap();

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const cached = digestCache.get(bytes);
  if (cached) return cached;
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes as BufferSource));
  let hex = '';
  for (const byte of digest) hex += byte.toString(16).padStart(2, '0');
  digestCache.set(bytes, hex);
  return hex;
}

// ---- 严格校验：照搬 ThemePackageService 的导入流程 ----

export interface VerifiedPackage {
  manifest: ThemePackageManifest;
  theme: ThemePackageTheme;
}

export async function verifyFiles(files: FileMap): Promise<VerifiedPackage> {
  const manifestBytes = files.get('manifest.json');
  const themeBytes = files.get('theme.json');
  if (!manifestBytes || !themeBytes) throw new Error('主题包不完整');
  if (manifestBytes.length > ThemePackageLimits.MAX_JSON_BYTES || themeBytes.length > ThemePackageLimits.MAX_JSON_BYTES) {
    throw new Error('主题包的设置文件过大');
  }
  const manifest = decodeManifest(strFromU8(manifestBytes));
  if (manifest.formatVersion >= 2) {
    await collectAssets(files, manifest);
  } else {
    await checkVersion1Assets(files, manifest);
  }
  const theme = decodeTheme(strFromU8(themeBytes), manifest);
  return { manifest, theme };
}

async function collectAssets(files: FileMap, manifest: ThemePackageManifest): Promise<void> {
  for (const [name, data] of files) {
    if (name === 'manifest.json' || name === 'theme.json') continue;
    const extension = assetPathExtension(name);
    if (!extension) throw new Error(`主题包内有无法识别的文件：${name}`);
    const kind = kindForExtension(extension);
    if (data.length <= 0 || data.length > maxBytesForKind(kind)) throw new Error('主题包素材超出大小上限');
    let asset = findAssetByPath(manifest, name);
    if (!asset) {
      if (manifest.assets.length >= ThemePackageLimits.MAX_ASSETS) throw new Error('主题包素材数量超出上限');
      asset = new ThemePackageAsset();
      asset.path = name;
      asset.kind = kind;
      manifest.assets.push(asset);
    } else if (asset.size > 0 && asset.size !== data.length) {
      throw new Error('主题包清单登记的素材大小与文件不符');
    }
    if (kind === ThemePackageAssetKinds.FONT && !manifest.requires.includes(ThemePackageFeatures.FONTS)) {
      throw new Error('主题包带了字体文件，清单的 requires 需要加上 fonts-v1');
    }
  }
  for (const asset of manifest.assets) {
    const data = files.get(asset.path);
    if (!data) throw new Error(`主题包缺少素材文件：${asset.path}`);
    if (sniffAssetExtension(data.subarray(0, 64)) !== assetPathExtension(asset.path)) {
      throw new Error(`主题包素材 ${asset.path} 的内容与扩展名不符`);
    }
    const digest = await sha256Hex(data);
    if (asset.sha256 && asset.sha256 !== digest) throw new Error('主题包已损坏（素材校验失败）');
    asset.sha256 = digest;
    asset.id = digest.substring(0, 24);
    asset.size = data.length;
    if (asset.kind === ThemePackageAssetKinds.VECTOR) {
      const problem = checkSvgSource(strFromU8(data));
      if (problem) throw new Error(`主题包素材 ${asset.path}：${problem}`);
    }
  }
}

async function checkVersion1Assets(files: FileMap, manifest: ThemePackageManifest): Promise<void> {
  for (const [name, data] of files) {
    if (name === 'manifest.json' || name === 'theme.json') continue;
    const asset = manifest.assets.find((item: ThemePackageAsset): boolean => item.path === name);
    if (!asset || asset.size !== data.length) throw new Error('主题包内含有无法识别的内容');
  }
  for (const asset of manifest.assets) {
    const data = files.get(asset.path);
    if (!data || data.length !== asset.size) throw new Error('主题包缺少素材文件');
    const dot = asset.path.lastIndexOf('.');
    if (sniffAssetExtension(data.subarray(0, 64)) !== asset.path.substring(dot + 1)) {
      throw new Error('主题包内有素材格式与声明不符');
    }
    if (await sha256Hex(data) !== asset.sha256) throw new Error('主题包已损坏（素材校验失败）');
  }
}

// ---- 打开 ----

export async function loadProject(files: FileMap): Promise<LoadResult> {
  try {
    const verified = await verifyFiles(files);
    return { project: fromVerified(verified, files), problems: [] };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { project: lenientProject(files), problems: [message] };
  }
}

function fromVerified(verified: VerifiedPackage, files: FileMap): EditorProject {
  const { manifest, theme } = verified;
  const pathById = new Map<string, string>();
  for (const asset of manifest.assets) pathById.set(asset.id, asset.path);
  const toPath = (ref: string): string => {
    if (typeof ref !== 'string' || !ref) return '';
    if (ref.startsWith(QYTHEME_ASSET_PREFIX)) return pathById.get(ref.substring(QYTHEME_ASSET_PREFIX.length)) || '';
    return ref;
  };
  const project = newProject(manifest.baseTheme || 'plain-default');
  project.sourceFormatVersion = manifest.formatVersion;
  project.manifest = {
    packageId: isValidPackageId(manifest.packageId) ? manifest.packageId : randomPackageId(),
    name: manifest.name,
    author: manifest.author,
    version: manifest.version,
    description: manifest.description,
    baseTheme: manifest.baseTheme || 'plain-default',
    credits: manifest.credits ? { ...manifest.credits } : null,
    requires: [...manifest.requires]
  };
  if (theme.parts) project.parts = mergeParts(encodeParts(mapPartsAssetRefs(theme.parts, toPath)));
  if (theme.settingsJson) {
    const settings = JSON.parse(theme.settingsJson);
    for (const key of IMAGE_SETTING_KEYS) {
      if (typeof settings[key] === 'string' && settings[key].startsWith(QYTHEME_ASSET_PREFIX)) settings[key] = toPath(settings[key]);
    }
    if (isValidPackageId(manifest.packageId)) replaceOwnPackIdWithSelf(settings, packThemeId(manifest.packageId));
    project.settings = settings;
  }
  if (theme.layoutJson) project.layout = JSON.parse(theme.layoutJson);
  if (theme.emphasis) project.emphasis = { enabled: theme.emphasis.enabled, rules: JSON.parse(theme.emphasis.rulesJson) };
  project.fonts = theme.fonts.map((font) => ({ family: font.family, name: font.name, assetPath: font.assetId ? pathById.get(font.assetId) || '' : '' }));
  for (const asset of manifest.assets) {
    const data = files.get(asset.path);
    if (!data) continue;
    const made = makeAsset(asset.path, data);
    if (typeof made !== 'string') project.assets.set(asset.path, made);
  }
  return project;
}

/** 严格校验不过时尽量读：JSON 能解析的部分照收，素材按文件头收，修好后再走严格导出。 */
function lenientProject(files: FileMap): EditorProject {
  const parse = (name: string): Json => {
    const data = files.get(name);
    if (!data) return {};
    try {
      const value = JSON.parse(strFromU8(data));
      return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
    } catch (_) {
      return {};
    }
  };
  const m = parse('manifest.json');
  const t = parse('theme.json');
  const str = (v: Json): string => (typeof v === 'string' ? v : '');
  const project = newProject(str(m.baseTheme) || 'plain-default');
  project.sourceFormatVersion = typeof m.formatVersion === 'number' ? m.formatVersion : 2;
  project.manifest.packageId = isValidPackageId(str(m.packageId)) ? str(m.packageId) : randomPackageId();
  project.manifest.name = str(m.name).substring(0, ThemePackageLimits.MAX_NAME_LENGTH);
  project.manifest.author = str(m.author).substring(0, ThemePackageLimits.MAX_AUTHOR_LENGTH);
  project.manifest.version = str(m.version).substring(0, ThemePackageLimits.MAX_VERSION_LENGTH);
  project.manifest.description = str(m.description).substring(0, ThemePackageLimits.MAX_DESCRIPTION_LENGTH);
  project.manifest.requires = Array.isArray(m.requires) ? m.requires.filter((x: Json) => typeof x === 'string') : [];
  const declared = new Map<string, string>();
  if (Array.isArray(m.assets)) {
    for (const item of m.assets) {
      if (item && typeof item.id === 'string' && typeof item.path === 'string') declared.set(item.id, item.path);
    }
  }
  const toPath = (v: Json): Json => {
    if (typeof v === 'string' && v.startsWith(QYTHEME_ASSET_PREFIX)) return declared.get(v.substring(QYTHEME_ASSET_PREFIX.length)) || '';
    if (Array.isArray(v)) return v.map(toPath);
    if (v && typeof v === 'object') {
      const out: Json = {};
      for (const [k, x] of Object.entries(v)) out[k] = toPath(x);
      return out;
    }
    return v;
  };
  if (t.parts && typeof t.parts === 'object') project.parts = mergeParts(toPath(t.parts));
  if (t.settings && typeof t.settings === 'object') project.settings = toPath(t.settings);
  if (t.layout && typeof t.layout === 'object') project.layout = t.layout;
  if (t.emphasis && typeof t.emphasis === 'object' && Array.isArray(t.emphasis.rules)) {
    project.emphasis = { enabled: t.emphasis.enabled === true, rules: t.emphasis.rules };
  }
  if (Array.isArray(t.fonts)) {
    project.fonts = t.fonts.filter((f: Json) => f && typeof f.family === 'string').map((f: Json) => ({
      family: f.family, name: str(f.name), assetPath: str(toPath(str(f.assetId))) }));
  }
  for (const [name, data] of files) {
    if (!name.startsWith('assets/') || name.indexOf('/', 7) >= 0) continue;
    const made = makeAsset(name, data);
    if (typeof made !== 'string') {
      // 扩展名与内容不符时按内容改名，引用跟着改。
      const fixed = name.substring(0, name.lastIndexOf('.') + 1) + made.ext;
      made.path = fixed;
      project.assets.set(fixed, made);
      if (fixed !== name) renameRef(project, name, fixed);
    }
  }
  return project;
}

/** 把编辑模型补成完整的骨架，界面按固定路径读写。 */
function mergeParts(source: Json): Json {
  const parts = emptyParts();
  const merge = (target: Json, from: Json): void => {
    if (!from || typeof from !== 'object') return;
    for (const [key, value] of Object.entries(from)) {
      if (value && typeof value === 'object' && !Array.isArray(value) && target[key] && typeof target[key] === 'object' && !Array.isArray(target[key])) {
        merge(target[key], value);
      } else if (value !== null && value !== undefined) {
        target[key] = Array.isArray(value) ? [...value] : value;
      }
    }
  };
  merge(parts, source);
  return parts;
}

export function renameRef(project: EditorProject, from: string, to: string): void {
  const swap = (v: Json): Json => {
    if (v === from) return to;
    if (Array.isArray(v)) return v.map(swap);
    if (v && typeof v === 'object') {
      for (const key of Object.keys(v)) v[key] = swap(v[key]);
    }
    return v;
  };
  swap(project.parts);
  if (project.settings) swap(project.settings);
  for (const font of project.fonts) if (font.assetPath === from) font.assetPath = to;
}

// ---- 导出 ----

/** parts 里所有 assets/ 引用。 */
export function collectRefs(value: Json, out: Set<string> = new Set()): Set<string> {
  if (typeof value === 'string') {
    if (value.startsWith('assets/')) out.add(value);
  } else if (Array.isArray(value)) {
    for (const item of value) collectRefs(item, out);
  } else if (value && typeof value === 'object') {
    for (const item of Object.values(value)) collectRefs(item, out);
  }
  return out;
}

export function usedAssetPaths(project: EditorProject): string[] {
  const refs = collectRefs(normalizedParts(project.parts));
  if (project.settings) {
    for (const key of IMAGE_SETTING_KEYS) {
      const value = project.settings[key];
      if (typeof value === 'string' && value.startsWith('assets/')) refs.add(value);
    }
  }
  for (const font of project.fonts) if (font.assetPath) refs.add(font.assetPath);
  return [...refs].sort();
}

function isEmptyValue(value: Json): boolean {
  if (value === '' || value === null || value === undefined) return true;
  if (Array.isArray(value)) return value.length === 0;
  if (typeof value === 'object') return Object.keys(value).length === 0;
  return false;
}

function strip(value: Json): Json {
  if (Array.isArray(value)) return value.map(strip).filter((x: Json) => !isEmptyValue(x));
  if (value && typeof value === 'object') {
    const out: Json = {};
    for (const [key, item] of Object.entries(value)) {
      const cleaned = strip(item);
      if (!isEmptyValue(cleaned)) out[key] = cleaned;
    }
    return out;
  }
  return value;
}

/**
 * 写进 theme.json 的 parts：去掉空值；背景方式切换后残留的另一种素材不写；
 * 一个字段都没填的朗读面板、启动封面不写（填了一部分的照写，让格式层报出缺什么）。
 */
export function normalizedParts(parts: Json): Json {
  const copy = JSON.parse(JSON.stringify(parts || {}));
  for (const mode of ['light', 'dark']) {
    const reader = copy[mode] && copy[mode].reader;
    if (!reader) continue;
    const bgMode = reader.backgroundMode || '';
    if (bgMode === 'image' || bgMode === 'none') { delete reader.leading; delete reader.trailing; }
    if (bgMode === 'ornaments' || bgMode === 'none') delete reader.image;
    if (bgMode !== 'image' && !reader.image) delete reader.imageFit;
    if (reader.imageFit === 'cover' && Object.keys(strip(reader)).length === 1) delete reader.imageFit;
  }
  // 动图取景的显示区域只对它记下的那张图有效：换了图、删了封面后留下的不写（也不带上旧图）。
  const book = copy.book;
  if (book && typeof book === 'object') {
    const covers: Json[] = Array.isArray(book.covers) ? book.covers : [];
    if (Array.isArray(book.coverCrops)) book.coverCrops = book.coverCrops.filter((crop: Json) => crop && covers.includes(crop.image));
    if (book.shelfFolderCrop && book.shelfFolderCrop.image !== book.shelfFolder) delete book.shelfFolderCrop;
  }
  const backdrop = copy.homeBackdrop;
  if (backdrop && typeof backdrop === 'object') {
    for (const mode of ['light', 'dark']) {
      const key = `${mode}Crop`;
      if (backdrop[key] && backdrop[key].image !== backdrop[mode]) delete backdrop[key];
    }
  }
  const result = strip(copy);
  // 旧版本应用还有“搜索”页签，导入时要求四个导航图标都在：没给就用发现的图标顶上（应用导出时同样处理）。
  const nav = result.navigation;
  if (nav && nav.explore && !nav.search) {
    nav.search = nav.explore;
    if (nav.exploreSelected && !nav.searchSelected) nav.searchSelected = nav.exploreSelected;
  }
  if (result.radius) {
    for (const key of Object.keys(result.radius)) {
      if (typeof result.radius[key] !== 'number') delete result.radius[key];
    }
    if (!Object.keys(result.radius).length) delete result.radius;
  }
  return result;
}

const OVERRIDE_SETTING_KEYS: string[] = ['customLightPalette', 'customDarkPalette', 'customLightEmphasis',
  'customDarkEmphasis', 'customRadius', 'customLightStartupText', 'customDarkStartupText', 'customAppFontFamily'];

export async function buildFiles(project: EditorProject): Promise<FileMap> {
  const parts = normalizedParts(project.parts);
  const used = usedAssetPaths(project);
  const files: FileMap = new Map();
  const assets: Json[] = [];
  let hasFont = false;
  for (const path of used) {
    const asset = project.assets.get(path);
    if (!asset) throw new Error(`素材 ${path} 不在素材库里（被删除了或没有上传成功）`);
    if (asset.kind === ThemePackageAssetKinds.FONT) hasFont = true;
    files.set(path, asset.bytes);
    assets.push({ path, sha256: await sha256Hex(asset.bytes), size: asset.bytes.length });
  }
  const requires = new Set<string>([ThemePackageFeatures.CUSTOM_SCHEME]);
  if (Object.keys(parts).length) requires.add(ThemePackageFeatures.THEME_PARTS);
  if (project.layout) requires.add(ThemePackageFeatures.READER_LAYOUT);
  if (project.emphasis) requires.add(ThemePackageFeatures.EMPHASIS_RULES);
  if (hasFont) requires.add(ThemePackageFeatures.FONTS);
  if (project.settings) {
    const overrides = OVERRIDE_SETTING_KEYS.some((key) => !isEmptyValue(strip(project.settings[key])));
    if (overrides || project.manifest.requires.includes(ThemePackageFeatures.SCHEME_OVERRIDES)) {
      requires.add(ThemePackageFeatures.SCHEME_OVERRIDES);
    }
  }
  const m = project.manifest;
  const manifest: Json = { format: 'qytheme', formatVersion: 2, packageId: m.packageId, name: m.name };
  if (m.author) manifest.author = m.author;
  if (m.version) manifest.version = m.version;
  if (m.description) manifest.description = m.description;
  if (m.baseTheme) manifest.baseTheme = m.baseTheme;
  manifest.requires = ThemePackageFeatures.KNOWN.filter((key) => requires.has(key));
  if (m.credits && m.credits.packageId) manifest.credits = m.credits;
  manifest.assets = assets;
  const theme: Json = {};
  if (Object.keys(parts).length) theme.parts = parts;
  if (project.settings) theme.settings = project.settings;
  if (project.layout) theme.layout = project.layout;
  if (project.emphasis) theme.emphasis = project.emphasis;
  if (project.fonts.length) {
    theme.fonts = project.fonts.map((f) => (f.assetPath ? { family: f.family, name: f.name, assetId: f.assetPath } : { family: f.family, name: f.name }));
  }
  files.set('manifest.json', strToU8(JSON.stringify(manifest, null, 2)));
  files.set('theme.json', strToU8(JSON.stringify(theme, null, 2)));
  return files;
}

/** 导出：生成文件、用格式层完整校验一遍，通过才返回。 */
export async function exportFiles(project: EditorProject): Promise<FileMap> {
  const files = await buildFiles(project);
  await verifyFiles(files);
  let total = 0;
  for (const data of files.values()) total += data.length;
  if (total > ThemePackageLimits.MAX_TOTAL_UNCOMPRESSED) throw new Error('主题包解压后超出大小上限');
  if (files.size > ThemePackageLimits.MAX_ZIP_ENTRIES) throw new Error(`主题包内文件过多（${files.size} 个）`);
  return files;
}

export async function exportZip(project: EditorProject): Promise<Uint8Array> {
  const zip = writeZip(await exportFiles(project));
  if (zip.length > ThemePackageLimits.MAX_PACKAGE_BYTES) throw new Error('主题包超过 80 MB，应用无法导入');
  return zip;
}

// ---- 草稿：编辑中的工程原样存下来（可以是还没通过校验的状态） ----

export function serializeDraft(project: EditorProject, meta: Json): Uint8Array {
  const files: FileMap = new Map();
  const state = {
    meta,
    manifest: project.manifest,
    parts: project.parts,
    settings: project.settings,
    layout: project.layout,
    emphasis: project.emphasis,
    fonts: project.fonts,
    sourceFormatVersion: project.sourceFormatVersion,
    assets: [...project.assets.keys()]
  };
  files.set('draft.json', strToU8(JSON.stringify(state)));
  for (const [path, asset] of project.assets) files.set(path, asset.bytes);
  return writeZip(files);
}

export function deserializeDraft(bytes: Uint8Array): { project: EditorProject; meta: Json } {
  const raw = unzipSync(bytes);
  const state = JSON.parse(strFromU8(raw['draft.json']));
  const project = newProject(state.manifest.baseTheme);
  project.manifest = state.manifest;
  project.parts = mergeParts(state.parts);
  project.settings = state.settings;
  project.layout = state.layout;
  project.emphasis = state.emphasis;
  project.fonts = state.fonts || [];
  project.sourceFormatVersion = state.sourceFormatVersion || 2;
  for (const path of state.assets as string[]) {
    const data = raw[path];
    if (!data) continue;
    const made = makeAsset(path, data);
    if (typeof made !== 'string') project.assets.set(path, made);
  }
  return { project, meta: state.meta };
}

export { mimeForExtension as assetMime };
