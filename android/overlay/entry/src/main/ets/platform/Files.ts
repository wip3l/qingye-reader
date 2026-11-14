// platform/Files.ts 的安卓实现。
//
// 安卓的选择器和保存面板给的是 content:// 地址，ArkUI-X 的 fs 只认沙箱路径，fs.copy 也不可用。
// 地址相关的读写经原生桥（android/project/.../FileBridge.java）完成：
// - 选出的文件先复制进 <cacheDir>/picked/<批次>/<序号>/<原文件名>，返回沙箱路径，文件名和后缀保持原样；
// - 写往保存地址时由原生侧打开地址写入。
// 缓存里的副本超过一天会在下次选文件时清掉，调用方要用的话应自己再复制一份（导入逻辑本来就会）。
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import util from '@ohos.util';
import bridge from '@arkui-x.bridge';
import { Context } from '@kit.AbilityKit';
import { fileUri } from './FileUri';

/** 与 FileBridge.NAME 一致。 */
const BRIDGE_NAME = 'io.legado.read/file';
const PICKED_DIR = 'picked';
const PICKED_KEEP_MS = 24 * 60 * 60 * 1000;
const IMAGE_SUFFIXES = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic', '.heif'];

interface BridgeResult {
  error?: string;
  path?: string;
  name?: string;
  size?: number;
  mtime?: number;
}

let fileBridge: bridge.BridgeObject | null = null;

async function callBridge(method: string, ...args: string[]): Promise<BridgeResult> {
  if (!fileBridge) fileBridge = bridge.createBridge(BRIDGE_NAME);
  const raw = await fileBridge.callMethod(method, ...args);
  const result = JSON.parse(String(raw)) as BridgeResult;
  if (result.error) throw new Error(result.error);
  return result;
}

function isLocal(uriOrPath: string): boolean {
  return uriOrPath.startsWith('/') || uriOrPath.startsWith('file://');
}

function localPath(uriOrPath: string): string {
  return uriOrPath.startsWith('file://') ? new fileUri.FileUri(uriOrPath).path : uriOrPath;
}

/** `'电子书|.txt,.epub'`、`'.zip'` 这类鸿蒙写法 → ['txt', 'epub', 'zip']。 */
function suffixesOf(filters: string[] | undefined): string[] {
  const out: string[] = [];
  for (const filter of filters || []) {
    const list = filter.includes('|') ? filter.substring(filter.indexOf('|') + 1) : filter;
    for (const item of list.split(',')) {
      const suffix = item.trim().replace(/^\*?\./, '').toLowerCase();
      if (suffix && suffix !== '*' && !out.includes(suffix)) out.push(suffix);
    }
  }
  return out;
}

function extensionOf(name: string): string {
  const index = name.lastIndexOf('.');
  return index > 0 ? name.substring(index + 1).toLowerCase() : '';
}

/** 文件名里去掉路径分隔符等不能落盘的字符。 */
function safeName(name: string, fallback: string): string {
  const clean = (name || '').replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').trim();
  return clean && clean !== '.' && clean !== '..' ? clean : fallback;
}

function removeTree(path: string): void {
  try {
    if (fs.statSync(path).isDirectory()) {
      fs.rmdirSync(path);
    } else {
      fs.unlinkSync(path);
    }
  } catch (_) {
    // 清理失败不影响本次选择
  }
}

function cleanupPicked(root: string): void {
  try {
    if (!fs.accessSync(root)) return;
    const now = Date.now();
    for (const name of fs.listFileSync(root)) {
      const batch = `${root}/${name}`;
      // 批次目录名就是创建时间
      const created = Number(name);
      if (!Number.isFinite(created) || now - created > PICKED_KEEP_MS) removeTree(batch);
    }
  } catch (_) {
    // 同上
  }
}

/** 把选择器给的地址逐个复制进缓存，按后缀筛掉不要的，返回沙箱路径。 */
async function materialize(context: Context, uris: string[], suffixes: string[]): Promise<string[]> {
  const root = `${context.cacheDir}/${PICKED_DIR}`;
  cleanupPicked(root);
  const batch = `${root}/${Date.now()}`;
  const paths: string[] = [];
  for (let index = 0; index < uris.length; index++) {
    const uri = uris[index];
    if (!uri) continue;
    if (isLocal(uri)) {
      paths.push(localPath(uri));
      continue;
    }
    const info = await callBridge('stat', uri);
    const name = safeName(info.name || '', `file${index}`);
    const extension = extensionOf(name);
    // 选择器没法按后缀过滤（见 selectDocuments），在这里补上。没有后缀的放行，交给调用方按内容判断。
    if (suffixes.length > 0 && extension && !suffixes.includes(extension)) {
      console.warn(`[Files] 跳过不符合后缀要求的文件：${name}`);
      continue;
    }
    const copied = await callBridge('copyToPath', uri, `${batch}/${index}/${name}`);
    paths.push(copied.path || `${batch}/${index}/${name}`);
  }
  return paths;
}

export async function selectDocuments(context: Context, options: picker.DocumentSelectOptions): Promise<string[]> {
  const suffixes = suffixesOf(options.fileSuffixFilters);
  // ArkUI-X 的安卓选择器把每一项过滤条件按文件名猜成一个 MIME 类型，'电子书|.txt,.epub' 这种写法只剩最后一种，
  // 猜不出的（.umd、.qytheme 等）和提供方报成 application/octet-stream 的文件都会变灰。干脆不过滤，选完再按后缀筛。
  options.fileSuffixFilters = [];
  const uris = await new picker.DocumentViewPicker(context).select(options);
  return materialize(context, uris || [], suffixes);
}

export async function selectImages(context: Context, maxCount: number = 1): Promise<string[]> {
  // 安卓上没有 PhotoViewPicker，用文档选择器选图片。这几个后缀安卓都能换算成对应的 image/* 类型。
  const options = new picker.DocumentSelectOptions();
  options.selectMode = picker.DocumentSelectMode.FILE;
  options.maxSelectNumber = maxCount;
  options.fileSuffixFilters = IMAGE_SUFFIXES.slice();
  const uris = await new picker.DocumentViewPicker(context).select(options);
  const paths = await materialize(context, uris || [], IMAGE_SUFFIXES.map((item: string) => item.substring(1)));
  return paths.slice(0, Math.max(1, maxCount));
}

export async function saveDocuments(context: Context, options: picker.DocumentSaveOptions): Promise<string[]> {
  const result = await new picker.DocumentViewPicker(context).save(options);
  return result || [];
}

export async function writeTextFile(context: Context, target: string, text: string): Promise<void> {
  const bytes = new util.TextEncoder().encodeInto(text);
  if (isLocal(target)) {
    const file = fs.openSync(localPath(target), fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
    } finally {
      fs.closeSync(file);
    }
    return;
  }
  // 地址只能由原生侧写入：先落到缓存里的临时文件，再整个复制过去。
  const temp = `${context.cacheDir}/write-${Date.now()}-${Math.floor(Math.random() * 1e6)}.tmp`;
  await writeTextFile(context, temp, text);
  try {
    await callBridge('copyFromPath', temp, target);
  } finally {
    try { fs.unlinkSync(temp); } catch (_) { /* 缓存目录会被系统清理 */ }
  }
}

export async function copyFile(source: string, target: string): Promise<void> {
  if (isLocal(source) && isLocal(target)) {
    await fs.copyFile(localPath(source), localPath(target));
    return;
  }
  if (isLocal(source)) {
    await callBridge('copyFromPath', localPath(source), target);
    return;
  }
  if (isLocal(target)) {
    await callBridge('copyToPath', source, localPath(target));
    return;
  }
  throw new Error('不支持在两个地址之间直接复制');
}
