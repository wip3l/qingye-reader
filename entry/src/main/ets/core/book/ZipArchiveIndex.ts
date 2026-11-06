/**
 * ZIP 中央目录解析，供“导入压缩包里的书”使用；只做字节解析，不碰文件系统。
 *
 * 不直接整包 decompressFile：Windows 打的包文件名多是 GBK，系统解压会变乱码，而书名取自文件名；
 * 包里的图片、说明之类也不该解出来占空间。做法是自己读目录、解码文件名，挑出书籍条目，
 * 再把每个条目的原始压缩数据套上一个只含该条目的最小 ZIP 头，交给系统解压（CRC 由系统校验）。
 */

export class ZipArchiveEntry {
  /** 包内完整路径，已统一为 '/' 分隔。 */
  name: string = '';
  flags: number = 0;
  method: number = 0;
  dosTime: number = 0;
  dosDate: number = 0;
  crc32: number = 0;
  compressedSize: number = 0;
  uncompressedSize: number = 0;
  localHeaderOffset: number = 0;
}

export class ZipCentralDirectoryInfo {
  offset: number = 0;
  size: number = 0;
  entryCount: number = 0;
  /** 需要再读 ZIP64 结束记录时为其文件偏移，否则为 -1。 */
  zip64EndOffset: number = -1;
}

export class ZipSingleEntryParts {
  /** 写在原始压缩数据前面的本地文件头。 */
  header: Uint8Array = new Uint8Array(0);
  /** 写在原始压缩数据后面的中央目录与结束记录。 */
  trailer: Uint8Array = new Uint8Array(0);
}

export type ZipNameDecoder = (bytes: Uint8Array, encoding: string) => string;

const SIG_LOCAL = 0x04034b50;
const SIG_CENTRAL = 0x02014b50;
const SIG_END = 0x06054b50;
const SIG_ZIP64_END = 0x06064b50;
const SIG_ZIP64_LOCATOR = 0x07064b50;
const FLAG_ENCRYPTED = 0x0001;
const FLAG_UTF8 = 0x0800;
const EXTRA_ZIP64 = 0x0001;
const EXTRA_UNICODE_PATH = 0x7075;
const MAX_32 = 0xFFFFFFFF;

let crcTable: Uint32Array | null = null;

export class ZipArchiveIndex {
  static readonly END_RECORD_SIZE: number = 22;
  static readonly ZIP64_END_RECORD_SIZE: number = 56;
  static readonly LOCAL_HEADER_SIZE: number = 30;
  /** 结束记录可能带最长 65535 字节的注释，前面还可能紧挨 ZIP64 定位记录。 */
  static readonly MAX_TAIL_SIZE: number = 22 + 0xFFFF + 20;
  /** 单本书解压后的上限；也保证重新封装时不需要 ZIP64。 */
  static readonly MAX_ENTRY_SIZE: number = 1024 * 1024 * 1024;
  static readonly MAX_CENTRAL_DIRECTORY_SIZE: number = 64 * 1024 * 1024;

  /** tail 是文件末尾的一段字节，tailOffset 是它在文件里的起点。 */
  static locateCentralDirectory(tail: Uint8Array, tailOffset: number): ZipCentralDirectoryInfo {
    const view = ZipArchiveIndex.viewOf(tail);
    for (let at = tail.length - ZipArchiveIndex.END_RECORD_SIZE; at >= 0; at--) {
      if (view.getUint32(at, true) !== SIG_END) continue;
      const commentLength = view.getUint16(at + 20, true);
      if (at + ZipArchiveIndex.END_RECORD_SIZE + commentLength > tail.length) continue;
      const info = new ZipCentralDirectoryInfo();
      info.entryCount = view.getUint16(at + 10, true);
      info.size = view.getUint32(at + 12, true);
      info.offset = view.getUint32(at + 16, true);
      const locatorAt = at - 20;
      if (locatorAt >= 0 && view.getUint32(locatorAt, true) === SIG_ZIP64_LOCATOR) {
        info.zip64EndOffset = ZipArchiveIndex.readUint64(view, locatorAt + 8);
      } else if (info.entryCount === 0xFFFF || info.size === MAX_32 || info.offset === MAX_32) {
        throw new Error('压缩包结构不完整');
      }
      if (info.zip64EndOffset < 0 && tailOffset + at < info.offset + info.size) {
        throw new Error('压缩包结构不完整');
      }
      return info;
    }
    throw new Error('不是有效的 ZIP 压缩包，或文件不完整');
  }

  static applyZip64End(info: ZipCentralDirectoryInfo, record: Uint8Array): void {
    const view = ZipArchiveIndex.viewOf(record);
    if (record.length < ZipArchiveIndex.ZIP64_END_RECORD_SIZE || view.getUint32(0, true) !== SIG_ZIP64_END) {
      throw new Error('压缩包结构不完整');
    }
    info.entryCount = ZipArchiveIndex.readUint64(view, 32);
    info.size = ZipArchiveIndex.readUint64(view, 40);
    info.offset = ZipArchiveIndex.readUint64(view, 48);
    info.zip64EndOffset = -1;
  }

  static parseCentralDirectory(bytes: Uint8Array, decode: ZipNameDecoder): ZipArchiveEntry[] {
    const view = ZipArchiveIndex.viewOf(bytes);
    const entries: ZipArchiveEntry[] = [];
    let at = 0;
    while (at + 46 <= bytes.length && view.getUint32(at, true) === SIG_CENTRAL) {
      const nameLength = view.getUint16(at + 28, true);
      const extraLength = view.getUint16(at + 30, true);
      const commentLength = view.getUint16(at + 32, true);
      const nameStart = at + 46;
      const extraStart = nameStart + nameLength;
      const next = extraStart + extraLength + commentLength;
      if (next > bytes.length) break;
      const entry = new ZipArchiveEntry();
      entry.flags = view.getUint16(at + 8, true);
      entry.method = view.getUint16(at + 10, true);
      entry.dosTime = view.getUint16(at + 12, true);
      entry.dosDate = view.getUint16(at + 14, true);
      entry.crc32 = view.getUint32(at + 16, true);
      entry.compressedSize = view.getUint32(at + 20, true);
      entry.uncompressedSize = view.getUint32(at + 24, true);
      entry.localHeaderOffset = view.getUint32(at + 42, true);
      const rawName = bytes.subarray(nameStart, extraStart);
      const extra = bytes.subarray(extraStart, extraStart + extraLength);
      ZipArchiveIndex.applyZip64Extra(entry, extra);
      entry.name = ZipArchiveIndex.decodeName(rawName, extra, entry.flags, decode).replace(/\\/g, '/');
      entries.push(entry);
      at = next;
    }
    return entries;
  }

  /** 包里可以导入的书：按扩展名挑，跳过目录和 macOS 打包带的资源叉文件。 */
  static bookEntries(entries: ZipArchiveEntry[], formats: string[]): ZipArchiveEntry[] {
    return entries.filter((entry: ZipArchiveEntry): boolean => {
      if (!entry.name || entry.name.endsWith('/')) return false;
      if (entry.name.startsWith('__MACOSX/') || ZipArchiveIndex.baseName(entry.name).startsWith('._')) return false;
      return formats.includes(ZipArchiveIndex.extensionOf(entry.name));
    });
  }

  /** 不能导入的原因；能导入时为空串。 */
  static entryProblem(entry: ZipArchiveEntry): string {
    if ((entry.flags & FLAG_ENCRYPTED) !== 0 || entry.method === 99) return '已加密，暂不支持';
    if (entry.method !== 0 && entry.method !== 8) return '压缩方式不支持，请改用标准 ZIP 重新打包';
    if (entry.uncompressedSize > ZipArchiveIndex.MAX_ENTRY_SIZE ||
      entry.compressedSize > ZipArchiveIndex.MAX_ENTRY_SIZE) return '文件超过 1 GB';
    if (entry.method === 0 && entry.compressedSize !== entry.uncompressedSize) return '文件已损坏';
    return '';
  }

  /** 读本地文件头（固定 30 字节），返回压缩数据在文件里的起点。 */
  static localDataOffset(header: Uint8Array, headerOffset: number): number {
    const view = ZipArchiveIndex.viewOf(header);
    if (header.length < ZipArchiveIndex.LOCAL_HEADER_SIZE || view.getUint32(0, true) !== SIG_LOCAL) {
      throw new Error('压缩包已损坏');
    }
    return headerOffset + ZipArchiveIndex.LOCAL_HEADER_SIZE + view.getUint16(26, true) + view.getUint16(28, true);
  }

  /**
   * 只含这一个条目的 ZIP：header + 原始压缩数据 + trailer。大小与 CRC 取自中央目录，
   * 所以原条目用了数据描述符（本地头里大小为 0）也能正确解出。
   */
  static singleEntryArchive(entry: ZipArchiveEntry, storedName: string): ZipSingleEntryParts {
    const name = ZipArchiveIndex.asciiBytes(storedName);
    const flags = entry.flags & 0x0006;
    const header = new Uint8Array(30 + name.length);
    const local = ZipArchiveIndex.viewOf(header);
    local.setUint32(0, SIG_LOCAL, true);
    local.setUint16(4, 20, true);
    local.setUint16(6, flags, true);
    local.setUint16(8, entry.method, true);
    local.setUint16(10, entry.dosTime, true);
    local.setUint16(12, entry.dosDate, true);
    local.setUint32(14, entry.crc32 >>> 0, true);
    local.setUint32(18, entry.compressedSize, true);
    local.setUint32(22, entry.uncompressedSize, true);
    local.setUint16(26, name.length, true);
    header.set(name, 30);

    const centralSize = 46 + name.length;
    const trailer = new Uint8Array(centralSize + 22);
    const tail = ZipArchiveIndex.viewOf(trailer);
    tail.setUint32(0, SIG_CENTRAL, true);
    tail.setUint16(4, 20, true);
    tail.setUint16(6, 20, true);
    tail.setUint16(8, flags, true);
    tail.setUint16(10, entry.method, true);
    tail.setUint16(12, entry.dosTime, true);
    tail.setUint16(14, entry.dosDate, true);
    tail.setUint32(16, entry.crc32 >>> 0, true);
    tail.setUint32(20, entry.compressedSize, true);
    tail.setUint32(24, entry.uncompressedSize, true);
    tail.setUint16(28, name.length, true);
    trailer.set(name, 46);
    tail.setUint32(centralSize, SIG_END, true);
    tail.setUint16(centralSize + 8, 1, true);
    tail.setUint16(centralSize + 10, 1, true);
    tail.setUint32(centralSize + 12, centralSize, true);
    tail.setUint32(centralSize + 16, header.length + entry.compressedSize, true);
    const parts = new ZipSingleEntryParts();
    parts.header = header;
    parts.trailer = trailer;
    return parts;
  }

  /** 条目修改时间（本地时间）的毫秒数；字段无效时为 0。 */
  static modifiedMillis(entry: ZipArchiveEntry): number {
    const month = (entry.dosDate >> 5) & 0x0F;
    const day = entry.dosDate & 0x1F;
    if (month < 1 || month > 12 || day < 1) return 0;
    const year = ((entry.dosDate >> 9) & 0x7F) + 1980;
    const time = new Date(year, month - 1, day, (entry.dosTime >> 11) & 0x1F, (entry.dosTime >> 5) & 0x3F,
      (entry.dosTime & 0x1F) * 2).getTime();
    return isNaN(time) ? 0 : time;
  }

  static baseName(name: string): string {
    const clean = name.replace(/\/+$/, '');
    const index = clean.lastIndexOf('/');
    return index >= 0 ? clean.substring(index + 1) : clean;
  }

  static extensionOf(name: string): string {
    const base = ZipArchiveIndex.baseName(name);
    const index = base.lastIndexOf('.');
    return index > 0 ? base.substring(index + 1).toLowerCase() : '';
  }

  /**
   * 文件名编码：标志位声明 UTF-8，或带 Info-ZIP Unicode 路径扩展（CRC 对得上原名）时按 UTF-8；
   * 否则合法 UTF-8 就按 UTF-8（macOS 打包不设标志位），再不行按 GB18030（Windows 中文系统打包）。
   */
  private static decodeName(raw: Uint8Array, extra: Uint8Array, flags: number, decode: ZipNameDecoder): string {
    if ((flags & FLAG_UTF8) !== 0) return decode(raw, 'utf-8');
    const unicodePath = ZipArchiveIndex.unicodePathExtra(raw, extra);
    if (unicodePath) return decode(unicodePath, 'utf-8');
    let ascii = true;
    for (let i = 0; i < raw.length; i++) {
      if (raw[i] >= 0x80) {
        ascii = false;
        break;
      }
    }
    if (ascii) return decode(raw, 'utf-8');
    return decode(raw, ZipArchiveIndex.isValidUtf8(raw) ? 'utf-8' : 'gb18030');
  }

  private static unicodePathExtra(raw: Uint8Array, extra: Uint8Array): Uint8Array | null {
    const view = ZipArchiveIndex.viewOf(extra);
    let at = 0;
    while (at + 4 <= extra.length) {
      const id = view.getUint16(at, true);
      const size = view.getUint16(at + 2, true);
      const body = at + 4;
      if (body + size > extra.length) break;
      if (id === EXTRA_UNICODE_PATH && size > 5 && extra[body] === 1 &&
        view.getUint32(body + 1, true) === ZipArchiveIndex.crc32(raw)) {
        return extra.subarray(body + 5, body + size);
      }
      at = body + size;
    }
    return null;
  }

  private static applyZip64Extra(entry: ZipArchiveEntry, extra: Uint8Array): void {
    if (entry.uncompressedSize !== MAX_32 && entry.compressedSize !== MAX_32 &&
      entry.localHeaderOffset !== MAX_32) return;
    const view = ZipArchiveIndex.viewOf(extra);
    let at = 0;
    while (at + 4 <= extra.length) {
      const id = view.getUint16(at, true);
      const size = view.getUint16(at + 2, true);
      let field = at + 4;
      const end = field + size;
      if (end > extra.length) return;
      if (id === EXTRA_ZIP64) {
        if (entry.uncompressedSize === MAX_32 && field + 8 <= end) {
          entry.uncompressedSize = ZipArchiveIndex.readUint64(view, field);
          field += 8;
        }
        if (entry.compressedSize === MAX_32 && field + 8 <= end) {
          entry.compressedSize = ZipArchiveIndex.readUint64(view, field);
          field += 8;
        }
        if (entry.localHeaderOffset === MAX_32 && field + 8 <= end) {
          entry.localHeaderOffset = ZipArchiveIndex.readUint64(view, field);
        }
        return;
      }
      at = end;
    }
  }

  private static isValidUtf8(bytes: Uint8Array): boolean {
    let i = 0;
    while (i < bytes.length) {
      const byte = bytes[i];
      let follow = 0;
      if (byte < 0x80) {
        i++;
        continue;
      } else if (byte >= 0xC2 && byte <= 0xDF) {
        follow = 1;
      } else if (byte >= 0xE0 && byte <= 0xEF) {
        follow = 2;
      } else if (byte >= 0xF0 && byte <= 0xF4) {
        follow = 3;
      } else {
        return false;
      }
      if (i + follow >= bytes.length) return false;
      for (let k = 1; k <= follow; k++) {
        if ((bytes[i + k] & 0xC0) !== 0x80) return false;
      }
      i += follow + 1;
    }
    return true;
  }

  private static crc32(bytes: Uint8Array): number {
    if (!crcTable) {
      crcTable = new Uint32Array(256);
      for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        crcTable[n] = c >>> 0;
      }
    }
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) crc = crcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  private static asciiBytes(value: string): Uint8Array {
    const bytes = new Uint8Array(value.length);
    for (let i = 0; i < value.length; i++) bytes[i] = value.charCodeAt(i) & 0x7F;
    return bytes;
  }

  private static readUint64(view: DataView, at: number): number {
    return view.getUint32(at + 4, true) * 0x100000000 + view.getUint32(at, true);
  }

  private static viewOf(bytes: Uint8Array): DataView {
    return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }
}
