import { normalizeSafePluginRelPath } from '../spec/PluginManifest';

export interface PluginZipEntry {
  path: string;
  compressedSize: number;
  uncompressedSize: number;
  compressionMethod: number;
}

export interface PluginZipLimits {
  maxCompressedBytes: number;
  maxUncompressedBytes: number;
  maxEntries: number;
}

export const DEFAULT_PLUGIN_ZIP_LIMITS: PluginZipLimits = {
  maxCompressedBytes: 32 * 1024 * 1024,
  maxUncompressedBytes: 64 * 1024 * 1024,
  maxEntries: 256
};

const EOCD_SIG: number = 0x06054b50;
const CEN_SIG: number = 0x02014b50;
const ZIP64_LIMIT_16: number = 0xffff;
const ZIP64_LIMIT_32: number = 0xffffffff;

function readU16LE(buf: Uint8Array, offset: number): number {
  return buf[offset] | (buf[offset + 1] << 8);
}

function readU32LE(buf: Uint8Array, offset: number): number {
  return (
    buf[offset] |
    (buf[offset + 1] << 8) |
    (buf[offset + 2] << 16) |
    (buf[offset + 3] * 0x1000000)
  ) >>> 0;
}

function decodeUtf8(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i++];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
    } else if ((b0 & 0xe0) === 0xc0 && i < bytes.length) {
      out += String.fromCharCode(((b0 & 0x1f) << 6) | (bytes[i++] & 0x3f));
    } else if ((b0 & 0xf0) === 0xe0 && i + 1 < bytes.length) {
      const b1 = bytes[i++];
      const b2 = bytes[i++];
      out += String.fromCharCode(((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f));
    } else if ((b0 & 0xf8) === 0xf0 && i + 2 < bytes.length) {
      const b1 = bytes[i++];
      const b2 = bytes[i++];
      const b3 = bytes[i++];
      const cp = (((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f)) - 0x10000;
      out += String.fromCharCode(0xd800 | (cp >> 10), 0xdc00 | (cp & 0x3ff));
    } else {
      throw new Error('插件包内文件名包含非法 UTF-8 字节');
    }
  }
  return out;
}

export function inspectPluginZipBytes(
  zipBytes: Uint8Array,
  limits: PluginZipLimits = DEFAULT_PLUGIN_ZIP_LIMITS
): PluginZipEntry[] {
  if (zipBytes.byteLength < 22) {
    throw new Error('不是有效的 .qyplugin 压缩包（文件过小）');
  }
  if (zipBytes.byteLength > limits.maxCompressedBytes) {
    throw new Error(`插件压缩包超过上限（最大 ${(limits.maxCompressedBytes / 1048576).toFixed(0)} MiB）`);
  }

  const minEocd = Math.max(0, zipBytes.byteLength - 65557);
  let eocdOffset = -1;
  for (let pos = zipBytes.byteLength - 22; pos >= minEocd; pos--) {
    if (readU32LE(zipBytes, pos) === EOCD_SIG) {
      const commentLen = readU16LE(zipBytes, pos + 20);
      if (pos + 22 + commentLen === zipBytes.byteLength) {
        eocdOffset = pos;
        break;
      }
    }
  }
  if (eocdOffset < 0) {
    throw new Error('无法识别 .qyplugin ZIP 中央目录结尾记录');
  }

  const totalEntries = readU16LE(zipBytes, eocdOffset + 10);
  const cdSize = readU32LE(zipBytes, eocdOffset + 12);
  const cdOffset = readU32LE(zipBytes, eocdOffset + 16);
  if (totalEntries === ZIP64_LIMIT_16 || cdSize === ZIP64_LIMIT_32 || cdOffset === ZIP64_LIMIT_32) {
    throw new Error('插件包不支持 ZIP64 格式');
  }
  if (totalEntries === 0) {
    throw new Error('插件包为空');
  }
  if (totalEntries > limits.maxEntries) {
    throw new Error(`插件包内文件数量超过上限（最多 ${limits.maxEntries} 个）`);
  }
  if (cdOffset + cdSize > eocdOffset) {
    throw new Error('插件包 ZIP 中央目录越界或已损坏');
  }

  const entries: PluginZipEntry[] = [];
  const seenPaths: Set<string> = new Set();
  let totalUncompressed = 0;
  let cursor = cdOffset;

  for (let i = 0; i < totalEntries; i++) {
    if (cursor + 46 > eocdOffset || readU32LE(zipBytes, cursor) !== CEN_SIG) {
      throw new Error('插件包 ZIP 中央目录条目损坏');
    }
    const gpFlags = readU16LE(zipBytes, cursor + 8);
    if ((gpFlags & 0x0001) !== 0) {
      throw new Error('插件包不支持加密压缩包');
    }
    const method = readU16LE(zipBytes, cursor + 10);
    if (method !== 0 && method !== 8) {
      throw new Error(`插件包包含不支持的压缩算法 (method=${method})`);
    }
    const compSize = readU32LE(zipBytes, cursor + 20);
    const uncompSize = readU32LE(zipBytes, cursor + 24);
    if (compSize === ZIP64_LIMIT_32 || uncompSize === ZIP64_LIMIT_32) {
      throw new Error('插件包条目不支持 ZIP64');
    }
    const nameLen = readU16LE(zipBytes, cursor + 28);
    const extraLen = readU16LE(zipBytes, cursor + 30);
    const commentLen = readU16LE(zipBytes, cursor + 32);
    const externalAttr = readU32LE(zipBytes, cursor + 38);
    const unixMode = (externalAttr >>> 16) & 0xf000;
    if (unixMode === 0xa000) {
      throw new Error('插件包内禁止包含符号链接 (symlink)');
    }

    const nameEnd = cursor + 46 + nameLen;
    if (nameEnd + extraLen + commentLen > eocdOffset) {
      throw new Error('插件包文件名记录越界');
    }
    const rawName = decodeUtf8(zipBytes.subarray(cursor + 46, nameEnd));
    cursor = nameEnd + extraLen + commentLen;

    if (rawName.endsWith('/')) {
      continue;
    }
    const normalized = normalizeSafePluginRelPath(rawName);
    const lowerKey = normalized.toLowerCase();
    if (seenPaths.has(lowerKey)) {
      throw new Error(`插件包内存在重复路径: ${normalized}`);
    }
    seenPaths.add(lowerKey);

    totalUncompressed += uncompSize;
    if (totalUncompressed > limits.maxUncompressedBytes) {
      throw new Error(`插件包解压总大小超过上限（最大 ${(limits.maxUncompressedBytes / 1048576).toFixed(0)} MiB）`);
    }

    entries.push({
      path: normalized,
      compressedSize: compSize,
      uncompressedSize: uncompSize,
      compressionMethod: method
    });
  }

  return entries;
}
