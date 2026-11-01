import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { MobiBook, MobiBookParser } from './MobiBookParser';

export class MobiExtractedTocItem {
  part: number = 0;
  fragment: string = '';
  title: string = '';
}

/** 拆好的 MOBI：只带路径和元数据，跨线程传回时很小。 */
export class MobiExtractSummary {
  title: string = '';
  author: string = '';
  coverPath: string = '';
  partPaths: string[] = [];
  toc: MobiExtractedTocItem[] = [];
}

/**
 * 读 MOBI、解析，再把正文段和图片写进 extractRoot 下的 text/、images/。
 * 全程同步，供 TaskPool 在后台线程调用；解析成功后才清空旧的解压目录，解析失败不动已有内容。
 */
export function extractMobiBook(mobiPath: string, extractRoot: string): MobiExtractSummary {
  const mobi = MobiBookParser.parse(readFileBytes(mobiPath), (value: Uint8Array, encoding: string): string => {
    try {
      return util.TextDecoder.create(encoding).decodeWithStream(value, { stream: false });
    } catch (_) {
      return util.TextDecoder.create('utf-8').decodeWithStream(value, { stream: false });
    }
  }, '../images');
  if (fs.accessSync(extractRoot)) fs.rmdirSync(extractRoot);
  fs.mkdirSync(`${extractRoot}/text`, true);
  fs.mkdirSync(`${extractRoot}/images`, true);
  return writeMobiFiles(mobi, extractRoot);
}

function writeMobiFiles(mobi: MobiBook, extractRoot: string): MobiExtractSummary {
  const summary = new MobiExtractSummary();
  summary.title = mobi.title;
  summary.author = mobi.author;
  for (const image of mobi.images) {
    const path = `${extractRoot}/images/${MobiBookParser.imageName(image)}`;
    writeFileBytes(path, image.bytes);
    if (image.recIndex === mobi.coverRecIndex) summary.coverPath = path;
  }
  const encoder = new util.TextEncoder();
  for (let i = 0; i < mobi.parts.length; i++) {
    const path = `${extractRoot}/text/part${`${i + 1}`.padStart(5, '0')}.html`;
    const html = `<html><head><meta charset="utf-8"/></head><body>${mobi.parts[i]}</body></html>`;
    writeFileBytes(path, encoder.encodeInto(html));
    summary.partPaths.push(path);
  }
  for (const item of mobi.toc) {
    const entry = new MobiExtractedTocItem();
    entry.part = item.part;
    entry.fragment = item.fragment;
    entry.title = item.title;
    summary.toc.push(entry);
  }
  return summary;
}

function readFileBytes(path: string): Uint8Array {
  const size = fs.statSync(path).size;
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const buffer = new ArrayBuffer(size);
    let offset = size > 0 ? fs.readSync(file.fd, buffer, { offset: 0, length: size }) : 0;
    if (offset <= 0 || offset >= size) return new Uint8Array(buffer, 0, Math.max(0, offset));
    // readSync 的 offset 是文件位置，数据总写在 buffer 开头：短读时续读到临时缓冲再拷过去。
    const bytes = new Uint8Array(buffer);
    while (offset < size) {
      const chunk = new ArrayBuffer(size - offset);
      const read = fs.readSync(file.fd, chunk, { offset: offset, length: size - offset });
      if (read <= 0) break;
      bytes.set(new Uint8Array(chunk, 0, read), offset);
      offset += read;
    }
    return bytes.subarray(0, offset);
  } finally {
    fs.closeSync(file);
  }
}

function writeFileBytes(path: string, bytes: Uint8Array): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    let offset = 0;
    // writeSync 可能短写，按返回值续写。
    while (offset < bytes.byteLength) {
      const written = fs.writeSync(file.fd,
        bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.byteLength));
      if (written <= 0) throw new Error(`写入失败：${path}`);
      offset += written;
    }
  } finally {
    fs.closeSync(file);
  }
}
