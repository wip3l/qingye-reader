import { PluginEngineHostPort } from '../host/PluginHostPort';
import { normalizeSafePluginRelPath } from '../spec/PluginManifest';

/**
 * 插件包签名（可选）。
 *
 * 签名文件放在包内 `META-INF/qyplugin.sig.json`，列出除它以外每个文件的 SHA-256，
 * 并用作者的 Ed25519 私钥对规范化清单文本签名。安装时逐个核对解压出来的文件，
 * 多一个、少一个或内容不同都拒绝，所以压缩包解析差异也藏不住文件。
 *
 * 签名者身份就是公钥（SPKI DER）的 SHA-256 指纹；首次安装时绑定到插件 id，
 * 之后的升级必须来自同一指纹，见 PluginTrustPolicy。
 */

export const PLUGIN_SIGNATURE_PATH: string = 'META-INF/qyplugin.sig.json';
export const PLUGIN_SIGNATURE_FORMAT: string = 'qyplugin-signature';
export const PLUGIN_SIGNATURE_ALGORITHM: string = 'Ed25519';
const SIGNED_TEXT_HEADER: string = 'qyplugin-signature-v1';
const SHA256_HEX_RE: RegExp = /^[0-9a-f]{64}$/;
const BASE64_RE: RegExp = /^[A-Za-z0-9+/]+={0,2}$/;

export interface PluginSignedFile {
  path: string;
  sha256: string;
}

export interface PluginSignatureDocument {
  format: string;
  version: number;
  algorithm: string;
  publicKey: string;
  files: PluginSignedFile[];
  signature: string;
}

export interface PluginSignatureInfo {
  signed: boolean;
  /** 签名公钥的 SHA-256（小写十六进制）；未签名为空串。 */
  fingerprint: string;
}

function compareText(a: string, b: string): number {
  return a < b ? -1 : (a > b ? 1 : 0);
}

export function sortSignedFiles(files: PluginSignedFile[]): PluginSignedFile[] {
  return files.slice().sort((a, b) => compareText(a.path, b.path));
}

/** 被签名的文本：固定表头加按路径排序的 `路径<TAB>sha256` 行，每行以换行结尾。 */
export function buildSignedText(files: PluginSignedFile[]): string {
  let text = `${SIGNED_TEXT_HEADER}\n`;
  for (const f of sortSignedFiles(files)) {
    text += `${f.path}\t${f.sha256}\n`;
  }
  return text;
}

export function utf8Encode(str: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < str.length; i++) {
    let c = str.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
      const c2 = str.charCodeAt(i + 1);
      if (c2 >= 0xdc00 && c2 <= 0xdfff) {
        i++;
        c = 0x10000 + (((c & 0x3ff) << 10) | (c2 & 0x3ff));
      }
    }
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c < 0x10000) {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    } else {
      out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(out);
}

function isRecord(val: unknown): val is Record<string, unknown> {
  return typeof val === 'object' && val !== null && !Array.isArray(val);
}

export function parseSignatureDocument(raw: unknown): PluginSignatureDocument {
  if (!isRecord(raw)) throw new Error('签名文件必须是 JSON 对象');
  if (raw['format'] !== PLUGIN_SIGNATURE_FORMAT || raw['version'] !== 1) {
    throw new Error('不支持的签名文件格式，请升级应用');
  }
  if (raw['algorithm'] !== PLUGIN_SIGNATURE_ALGORITHM) {
    throw new Error(`不支持的签名算法: ${String(raw['algorithm'])}`);
  }
  const publicKey = typeof raw['publicKey'] === 'string' ? raw['publicKey'].trim() : '';
  const signature = typeof raw['signature'] === 'string' ? raw['signature'].trim() : '';
  if (!BASE64_RE.test(publicKey) || !BASE64_RE.test(signature)) {
    throw new Error('签名文件缺少公钥或签名');
  }
  const rawFiles = Array.isArray(raw['files']) ? raw['files'] : [];
  if (rawFiles.length === 0) throw new Error('签名文件没有列出任何文件');
  const seen: Set<string> = new Set();
  const files: PluginSignedFile[] = [];
  for (const item of rawFiles) {
    if (!isRecord(item)) throw new Error('签名清单格式错误');
    const rawPath = typeof item['path'] === 'string' ? item['path'] : '';
    const path = normalizeSafePluginRelPath(rawPath);
    if (path !== rawPath) throw new Error(`签名清单路径不规范: ${rawPath}`);
    if (path === PLUGIN_SIGNATURE_PATH) throw new Error('签名清单不能包含签名文件自身');
    const lowerKey = path.toLowerCase();
    if (seen.has(lowerKey)) throw new Error(`签名清单路径重复: ${path}`);
    seen.add(lowerKey);
    const sha256 = typeof item['sha256'] === 'string' ? item['sha256'] : '';
    if (!SHA256_HEX_RE.test(sha256)) throw new Error(`签名清单的摘要格式错误: ${path}`);
    files.push({ path, sha256 });
  }
  return {
    format: PLUGIN_SIGNATURE_FORMAT,
    version: 1,
    algorithm: PLUGIN_SIGNATURE_ALGORITHM,
    publicKey,
    files: sortSignedFiles(files),
    signature
  };
}

/** 列出目录下全部文件的相对路径（listDir 对文件会抛错，以此区分文件与目录）。 */
async function listFilesRecursive(port: PluginEngineHostPort, rootDir: string): Promise<string[]> {
  const out: string[] = [];
  const walk = async (absDir: string, relPrefix: string): Promise<void> => {
    const names = await port.listDir(absDir);
    for (const name of names) {
      const abs = `${absDir}/${name}`;
      const rel = relPrefix ? `${relPrefix}/${name}` : name;
      let childNames: string[] | null = null;
      try {
        childNames = await port.listDir(abs);
      } catch (_) {
        childNames = null;
      }
      if (childNames === null) {
        out.push(rel);
      } else {
        await walk(abs, rel);
      }
    }
  };
  await walk(rootDir, '');
  return out;
}

/** 签名者指纹的展示形式：前 24 位十六进制，四位一组。 */
export function formatSignerFingerprint(fingerprint: string): string {
  const hex = fingerprint.toUpperCase().slice(0, 24);
  const groups: string[] = [];
  for (let i = 0; i < hex.length; i += 4) groups.push(hex.slice(i, i + 4));
  return groups.join(' ');
}

/**
 * 校验解压后的插件目录。没有签名文件返回 `{ signed: false }`；
 * 有签名文件但签名无效、文件对不上或平台无法验签时抛错，不会退回到“当作未签名”。
 */
export async function verifyPluginPackageSignature(
  packageRootDir: string,
  port: PluginEngineHostPort
): Promise<PluginSignatureInfo> {
  const sigAbsPath = `${packageRootDir}/${PLUGIN_SIGNATURE_PATH}`;
  if (!(await port.exists(sigAbsPath))) {
    return { signed: false, fingerprint: '' };
  }
  let rawDoc: unknown;
  try {
    rawDoc = JSON.parse(await port.readFileText(sigAbsPath));
  } catch (_) {
    throw new Error('签名文件不是合法的 JSON');
  }
  const doc = parseSignatureDocument(rawDoc);
  if (!port.verifyEd25519) {
    throw new Error('当前系统无法校验插件签名，已停止安装');
  }

  const publicKey = port.base64Decode(doc.publicKey);
  const signature = port.base64Decode(doc.signature);
  let valid = false;
  try {
    valid = await port.verifyEd25519(publicKey, utf8Encode(buildSignedText(doc.files)), signature);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`插件签名校验失败：${reason}`);
  }
  if (!valid) {
    throw new Error('插件签名无效：安装包在签名后被改动，或签名已损坏');
  }

  const actual = (await listFilesRecursive(port, packageRootDir)).filter((p) => p !== PLUGIN_SIGNATURE_PATH);
  const signedPaths: Set<string> = new Set(doc.files.map((f) => f.path));
  for (const rel of actual) {
    if (!signedPaths.has(rel)) throw new Error(`安装包含有未签名的文件: ${rel}`);
  }
  const actualSet: Set<string> = new Set(actual);
  for (const f of doc.files) {
    if (!actualSet.has(f.path)) throw new Error(`签名清单中的文件缺失: ${f.path}`);
    const digest = (await port.sha256Hex(await port.readFileBytes(`${packageRootDir}/${f.path}`))).toLowerCase();
    if (digest !== f.sha256) throw new Error(`文件内容与签名不符: ${f.path}`);
  }

  return { signed: true, fingerprint: (await port.sha256Hex(publicKey)).toLowerCase() };
}
