import fs from '@ohos.file.fs';
import util from '@ohos.util';
import zlib from '@ohos.zlib';
import { ZipArchiveEntry, ZipArchiveIndex, ZipCentralDirectoryInfo, ZipSingleEntryParts } from './ZipArchiveIndex';

/** 从压缩包里解出的一本书，文件在临时目录，导入完由调用方删掉。 */
export class ArchiveBookFile {
  path: string = '';
  /** 条目文件名（不含包内目录），用作书名来源。 */
  name: string = '';
  /** 书的身份：压缩包 URI + 包内路径，同一个包再导入时刷新原书。 */
  identity: string = '';
  format: string = '';
}

export class ArchiveExtractResult {
  files: ArchiveBookFile[] = [];
  /** 不能导入的条目，“包内路径：原因”。 */
  failures: string[] = [];
}

/** 本地导入时的压缩包展开：只解出书籍条目，见 ZipArchiveIndex。 */
export class LocalArchiveImport {
  static readonly FORMATS: string[] = ['zip'];
  private static readonly COPY_CHUNK: number = 1024 * 1024;

  static isArchiveFormat(format: string): boolean {
    return LocalArchiveImport.FORMATS.includes((format || '').toLowerCase());
  }

  static async extractBooks(archiveUri: string, workDir: string, bookFormats: string[]): Promise<ArchiveExtractResult> {
    const result = new ArchiveExtractResult();
    const archive = await fs.open(archiveUri, fs.OpenMode.READ_ONLY);
    try {
      const entries = await LocalArchiveImport.readEntries(archive.fd);
      const books = ZipArchiveIndex.bookEntries(entries, bookFormats);
      if (!fs.accessSync(workDir)) fs.mkdirSync(workDir, true);
      for (let i = 0; i < books.length; i++) {
        const entry = books[i];
        const problem = ZipArchiveIndex.entryProblem(entry);
        if (problem) {
          result.failures.push(`${entry.name}：${problem}`);
          continue;
        }
        try {
          const file = new ArchiveBookFile();
          file.format = ZipArchiveIndex.extensionOf(entry.name);
          file.path = await LocalArchiveImport.extractEntry(archive.fd, entry, workDir, i, file.format);
          file.name = ZipArchiveIndex.baseName(entry.name);
          file.identity = `${archiveUri}#${entry.name}`;
          result.files.push(file);
        } catch (e) {
          console.error('[LocalArchiveImport] extract failed:', entry.name, e);
          result.failures.push(`${entry.name}：解压失败，压缩包可能已损坏`);
        }
      }
    } finally {
      await fs.close(archive);
    }
    return result;
  }

  static removeWorkDir(workDir: string): void {
    try {
      if (fs.accessSync(workDir)) fs.rmdirSync(workDir);
    } catch (e) {
      console.warn('[LocalArchiveImport] cleanup failed:', workDir, e);
    }
  }

  private static async readEntries(fd: number): Promise<ZipArchiveEntry[]> {
    const size = (await fs.stat(fd)).size;
    const tailLength = Math.min(size, ZipArchiveIndex.MAX_TAIL_SIZE);
    const tail = await LocalArchiveImport.readAt(fd, size - tailLength, tailLength);
    const info: ZipCentralDirectoryInfo = ZipArchiveIndex.locateCentralDirectory(tail, size - tailLength);
    if (info.zip64EndOffset >= 0) {
      ZipArchiveIndex.applyZip64End(info,
        await LocalArchiveImport.readAt(fd, info.zip64EndOffset, ZipArchiveIndex.ZIP64_END_RECORD_SIZE));
    }
    if (info.size > ZipArchiveIndex.MAX_CENTRAL_DIRECTORY_SIZE || info.offset + info.size > size) {
      throw new Error('压缩包结构不完整');
    }
    const directory = await LocalArchiveImport.readAt(fd, info.offset, info.size);
    return ZipArchiveIndex.parseCentralDirectory(directory, (bytes: Uint8Array, encoding: string): string => {
      try {
        return util.TextDecoder.create(encoding).decodeWithStream(bytes, { stream: false });
      } catch (_) {
        return util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
      }
    });
  }

  /** 把条目的压缩数据套上单条目 ZIP 头写成小包，再用系统解压；返回解出的文件路径。 */
  private static async extractEntry(fd: number, entry: ZipArchiveEntry, workDir: string, index: number,
    format: string): Promise<string> {
    const localHeader = await LocalArchiveImport.readAt(fd, entry.localHeaderOffset, ZipArchiveIndex.LOCAL_HEADER_SIZE);
    const dataOffset = ZipArchiveIndex.localDataOffset(localHeader, entry.localHeaderOffset);
    const storedName = `book.${format}`;
    const parts: ZipSingleEntryParts = ZipArchiveIndex.singleEntryArchive(entry, storedName);
    const packPath = `${workDir}/entry_${index}.zip`;
    const outDir = `${workDir}/entry_${index}`;
    const pack = await fs.open(packPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      let position = 0;
      position += await LocalArchiveImport.writeAt(pack.fd, parts.header, position);
      let copied = 0;
      while (copied < entry.compressedSize) {
        const length = Math.min(LocalArchiveImport.COPY_CHUNK, entry.compressedSize - copied);
        const chunk = await LocalArchiveImport.readAt(fd, dataOffset + copied, length);
        if (chunk.length < length) throw new Error('压缩包数据不完整');
        position += await LocalArchiveImport.writeAt(pack.fd, chunk, position);
        copied += length;
      }
      await LocalArchiveImport.writeAt(pack.fd, parts.trailer, position);
    } finally {
      await fs.close(pack);
    }
    try {
      if (!fs.accessSync(outDir)) fs.mkdirSync(outDir, true);
      await zlib.decompressFile(packPath, outDir);
    } finally {
      try {
        fs.unlinkSync(packPath);
      } catch (_) {
      }
    }
    const path = `${outDir}/${storedName}`;
    if (!fs.accessSync(path) || fs.statSync(path).size !== entry.uncompressedSize) {
      throw new Error('解压结果不完整');
    }
    // 修改时间取包内记录的时间，同一个包再导入时内容没变就不用重新解析。
    const modified = ZipArchiveIndex.modifiedMillis(entry);
    if (modified > 0) {
      try {
        fs.utimes(path, modified);
      } catch (_) {
      }
    }
    return path;
  }

  private static async readAt(fd: number, offset: number, length: number): Promise<Uint8Array> {
    const buffer = new ArrayBuffer(length);
    let filled = 0;
    while (filled < length) {
      const read = await fs.read(fd, buffer, { offset: offset + filled, length: length - filled });
      if (read <= 0) break;
      filled += read;
    }
    return new Uint8Array(buffer, 0, filled);
  }

  private static async writeAt(fd: number, bytes: Uint8Array, position: number): Promise<number> {
    let written = 0;
    while (written < bytes.length) {
      const buffer = bytes.buffer.slice(bytes.byteOffset + written, bytes.byteOffset + bytes.length);
      const count = await fs.write(fd, buffer, { offset: position + written });
      if (count <= 0) throw new Error('写入临时文件失败');
      written += count;
    }
    return written;
  }
}
