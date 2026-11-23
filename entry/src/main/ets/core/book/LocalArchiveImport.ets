import fs from '@ohos.file.fs';
import util from '@ohos.util';
import zlib from '@ohos.zlib';
import {
  ZipArchiveEntry, ZipArchiveIndex, ZipCentralDirectoryInfo, ZipComicLayout, ZipSingleEntryParts
} from './ZipArchiveIndex';

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
  /** 包里的漫画图片数；没有书时用来判断能不能当漫画（CBZ）导入。 */
  imageCount: number = 0;
}

export class ComicArchiveChapter {
  title: string = '';
  /** 本章图片所在目录，图片按序号命名（00001.jpg…），按文件名排序即阅读顺序。 */
  dir: string = '';
  images: string[] = [];
}

export class ComicArchiveContent {
  chapters: ComicArchiveChapter[] = [];
  coverPath: string = '';
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
      result.imageCount = ZipArchiveIndex.imageEntries(entries).length;
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

  /**
   * 把纯图片包（CBZ）的图片解到 extractRoot：每章一个目录 c0001、c0002…，图片改名为序号保留扩展名，
   * 这样不受包内文件名编码影响，阅读时按目录列文件就能重建正文。坏掉的单张图跳过，一张都解不出来才报错。
   */
  static async extractComic(archivePath: string, extractRoot: string): Promise<ComicArchiveContent> {
    const content = new ComicArchiveContent();
    const workDir = `${extractRoot}/.work`;
    const archive = await fs.open(archivePath, fs.OpenMode.READ_ONLY);
    try {
      const layout: ZipComicLayout = ZipArchiveIndex.comicLayout(await LocalArchiveImport.readEntries(archive.fd));
      if (layout.chapters.length === 0) throw new Error('压缩包里没有可阅读的图片');
      fs.mkdirSync(workDir, true);
      let firstProblem = '';
      let serial = 0;
      for (let c = 0; c < layout.chapters.length; c++) {
        const source = layout.chapters[c];
        const chapter = new ComicArchiveChapter();
        chapter.title = source.title;
        chapter.dir = `${extractRoot}/c${LocalArchiveImport.pad(c + 1, 4)}`;
        fs.mkdirSync(chapter.dir, true);
        for (let i = 0; i < source.entries.length; i++) {
          const entry = source.entries[i];
          const problem = ZipArchiveIndex.entryProblem(entry);
          if (problem) {
            if (!firstProblem) firstProblem = problem;
            continue;
          }
          const target = `${chapter.dir}/${LocalArchiveImport.pad(i + 1, 5)}.${ZipArchiveIndex.extensionOf(entry.name)}`;
          try {
            await LocalArchiveImport.writeEntry(archive.fd, entry, workDir, serial++, target);
            chapter.images.push(target);
            if (entry === layout.cover) content.coverPath = target;
          } catch (e) {
            console.warn('[LocalArchiveImport] comic image skipped:', entry.name, e);
            if (!firstProblem) firstProblem = '图片解压失败，压缩包可能已损坏';
          }
        }
        if (chapter.images.length > 0) content.chapters.push(chapter);
      }
      if (content.chapters.length === 0) throw new Error(firstProblem || '压缩包里没有可阅读的图片');
      if (!content.coverPath) content.coverPath = content.chapters[0].images[0];
    } finally {
      await fs.close(archive);
      LocalArchiveImport.removeWorkDir(workDir);
    }
    return content;
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

  /** 解出一本书到 workDir/entry_<index>/book.<format>，返回文件路径。 */
  private static async extractEntry(fd: number, entry: ZipArchiveEntry, workDir: string, index: number,
    format: string): Promise<string> {
    const outDir = `${workDir}/entry_${index}`;
    if (!fs.accessSync(outDir)) fs.mkdirSync(outDir, true);
    const path = `${outDir}/book.${format}`;
    await LocalArchiveImport.writeEntry(fd, entry, workDir, index, path);
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

  /**
   * 把一个条目解到 target。未压缩的条目直接拷贝数据；压缩的条目把压缩数据套上单条目 ZIP 头写成小包，
   * 再用系统解压（workDir 放小包和解压出的临时文件），最后挪到 target。
   */
  private static async writeEntry(fd: number, entry: ZipArchiveEntry, workDir: string, index: number,
    target: string): Promise<void> {
    const localHeader = await LocalArchiveImport.readAt(fd, entry.localHeaderOffset, ZipArchiveIndex.LOCAL_HEADER_SIZE);
    const dataOffset = ZipArchiveIndex.localDataOffset(localHeader, entry.localHeaderOffset);
    if (entry.method === 0) {
      const out = await fs.open(target, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        await LocalArchiveImport.copyRange(fd, dataOffset, entry.compressedSize, out.fd, 0);
      } finally {
        await fs.close(out);
      }
      if (fs.statSync(target).size !== entry.uncompressedSize) throw new Error('解压结果不完整');
      return;
    }
    const storedName = `entry.${ZipArchiveIndex.extensionOf(target) || 'bin'}`;
    const parts: ZipSingleEntryParts = ZipArchiveIndex.singleEntryArchive(entry, storedName);
    const packPath = `${workDir}/pack_${index}.zip`;
    const outDir = `${workDir}/pack_${index}`;
    const pack = await fs.open(packPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      let position = await LocalArchiveImport.writeAt(pack.fd, parts.header, 0);
      position += await LocalArchiveImport.copyRange(fd, dataOffset, entry.compressedSize, pack.fd, position);
      await LocalArchiveImport.writeAt(pack.fd, parts.trailer, position);
    } finally {
      await fs.close(pack);
    }
    try {
      if (!fs.accessSync(outDir)) fs.mkdirSync(outDir, true);
      await zlib.decompressFile(packPath, outDir);
      const unpacked = `${outDir}/${storedName}`;
      if (!fs.accessSync(unpacked) || fs.statSync(unpacked).size !== entry.uncompressedSize) {
        throw new Error('解压结果不完整');
      }
      if (fs.accessSync(target)) fs.unlinkSync(target);
      fs.renameSync(unpacked, target);
    } finally {
      try {
        fs.unlinkSync(packPath);
      } catch (_) {
      }
      LocalArchiveImport.removeWorkDir(outDir);
    }
  }

  /** 从 fd 的 offset 起拷 length 字节到 out 的 position，返回写入的字节数。 */
  private static async copyRange(fd: number, offset: number, length: number, out: number,
    position: number): Promise<number> {
    let copied = 0;
    while (copied < length) {
      const size = Math.min(LocalArchiveImport.COPY_CHUNK, length - copied);
      const chunk = await LocalArchiveImport.readAt(fd, offset + copied, size);
      if (chunk.length < size) throw new Error('压缩包数据不完整');
      await LocalArchiveImport.writeAt(out, chunk, position + copied);
      copied += size;
    }
    return copied;
  }

  private static pad(value: number, width: number): string {
    let text = `${value}`;
    while (text.length < width) text = `0${text}`;
    return text;
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
