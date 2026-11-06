#!/usr/bin/env node
// 压缩包导入的回归检查：在脚本里拼出各种 ZIP（UTF-8 / GBK / 无标志 UTF-8 文件名、Unicode 路径扩展、
// 数据描述符、加密、非常规压缩方式、ZIP64、带注释），校验 ZipArchiveIndex 的目录解析、书籍条目筛选，
// 以及重新封装出的单条目 ZIP 能被 Python zipfile 正常解出且内容一致。
// 文件读写与系统解压（LocalArchiveImport.ets）在真机上验证。
// Usage: node --experimental-strip-types scripts/zip-archive-import-check.mjs

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { ZipArchiveIndex, cleanup } = await loadReaderModules();

let failures = 0;
const check = (condition, message, detail = '') => {
  if (condition) {
    console.log(`  ok - ${message}`);
  } else {
    failures++;
    console.error(`  FAIL - ${message}${detail ? `\n         ${detail}` : ''}`);
  }
};
const equal = (actual, expected, message) =>
  check(JSON.stringify(actual) === JSON.stringify(expected), message,
    `expected ${JSON.stringify(expected)}\n         actual   ${JSON.stringify(actual)}`);
const throwsWith = (fn, pattern, message) => {
  try {
    fn();
    check(false, message, 'no error thrown');
  } catch (error) {
    check(pattern.test(error.message), message, error.message);
  }
};

const utf8 = (text) => new TextEncoder().encode(text);
const decode = (bytes, encoding) => new TextDecoder(encoding).decode(bytes);
const concat = (...arrays) => {
  const out = new Uint8Array(arrays.reduce((sum, item) => sum + item.length, 0));
  let at = 0;
  for (const item of arrays) {
    out.set(item, at);
    at += item.length;
  }
  return out;
};
const le = (size, value) => {
  const out = new Uint8Array(size);
  const view = new DataView(out.buffer);
  if (size === 2) view.setUint16(0, value, true);
  else if (size === 4) view.setUint32(0, value >>> 0, true);
  else {
    view.setUint32(0, value % 0x100000000, true);
    view.setUint32(4, Math.floor(value / 0x100000000), true);
  }
  return out;
};
// 2024-03-15 10:20:30 的 DOS 时间。
const DOS_DATE = ((2024 - 1980) << 9) | (3 << 5) | 15;
const DOS_TIME = (10 << 11) | (20 << 5) | 15;

/**
 * 拼一个 ZIP。entry: { name: Uint8Array, data: Uint8Array, method?, flags?, extra?, descriptor?, zip64? }
 * descriptor=true 时本地头的 CRC 和大小写 0，数据后跟数据描述符；zip64=true 时中央目录用 ZIP64 扩展。
 */
function buildZip(entries, { comment = new Uint8Array(0), zip64End = false } = {}) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const entry of entries) {
    const method = entry.method ?? 8;
    const payload = method === 8 ? new Uint8Array(zlib.deflateRawSync(entry.data)) : entry.data;
    const crc = zlib.crc32(entry.data);
    const flags = (entry.flags ?? 0) | (entry.descriptor ? 0x0008 : 0);
    const extra = entry.extra ?? new Uint8Array(0);
    const local = concat(le(4, 0x04034b50), le(2, 20), le(2, flags), le(2, method), le(2, DOS_TIME), le(2, DOS_DATE),
      le(4, entry.descriptor ? 0 : crc), le(4, entry.descriptor ? 0 : payload.length),
      le(4, entry.descriptor ? 0 : entry.data.length), le(2, entry.name.length), le(2, 0), entry.name);
    const descriptor = entry.descriptor ?
      concat(le(4, 0x08074b50), le(4, crc), le(4, payload.length), le(4, entry.data.length)) : new Uint8Array(0);
    locals.push(local, payload, descriptor);
    let centralExtra = extra;
    let sizes = [payload.length, entry.data.length, offset];
    if (entry.zip64) {
      centralExtra = concat(extra, le(2, 0x0001), le(2, 24), le(8, entry.data.length), le(8, payload.length), le(8, offset));
      sizes = [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF];
    }
    centrals.push(concat(le(4, 0x02014b50), le(2, 20), le(2, 20), le(2, flags), le(2, method), le(2, DOS_TIME),
      le(2, DOS_DATE), le(4, crc), le(4, sizes[0]), le(4, sizes[1]), le(2, entry.name.length),
      le(2, centralExtra.length), le(2, 0), le(2, 0), le(2, 0), le(4, 0), le(4, sizes[2]), entry.name, centralExtra));
    offset += local.length + payload.length + descriptor.length;
  }
  const central = concat(...centrals);
  const parts = [...locals, central];
  if (zip64End) {
    const endAt = offset + central.length;
    parts.push(concat(le(4, 0x06064b50), le(8, 44), le(2, 45), le(2, 45), le(4, 0), le(4, 0),
      le(8, entries.length), le(8, entries.length), le(8, central.length), le(8, offset)));
    parts.push(concat(le(4, 0x07064b50), le(4, 0), le(8, endAt), le(4, 1)));
    parts.push(concat(le(4, 0x06054b50), le(2, 0), le(2, 0), le(2, 0xFFFF), le(2, 0xFFFF),
      le(4, 0xFFFFFFFF), le(4, 0xFFFFFFFF), le(2, comment.length), comment));
  } else {
    parts.push(concat(le(4, 0x06054b50), le(2, 0), le(2, 0), le(2, entries.length), le(2, entries.length),
      le(4, central.length), le(4, offset), le(2, comment.length), comment));
  }
  return concat(...parts);
}

/** 按 LocalArchiveImport 的流程读目录：取文件尾、必要时读 ZIP64 结束记录、再解析中央目录。 */
function readEntries(zip) {
  const tailLength = Math.min(zip.length, ZipArchiveIndex.MAX_TAIL_SIZE);
  const tailOffset = zip.length - tailLength;
  const info = ZipArchiveIndex.locateCentralDirectory(zip.subarray(tailOffset), tailOffset);
  if (info.zip64EndOffset >= 0) {
    ZipArchiveIndex.applyZip64End(info,
      zip.subarray(info.zip64EndOffset, info.zip64EndOffset + ZipArchiveIndex.ZIP64_END_RECORD_SIZE));
  }
  return ZipArchiveIndex.parseCentralDirectory(zip.subarray(info.offset, info.offset + info.size), decode);
}

/** 重新封装成单条目 ZIP（LocalArchiveImport 写临时包的同一步骤）。 */
function rewrap(zip, entry, storedName) {
  const dataAt = ZipArchiveIndex.localDataOffset(
    zip.subarray(entry.localHeaderOffset, entry.localHeaderOffset + ZipArchiveIndex.LOCAL_HEADER_SIZE),
    entry.localHeaderOffset);
  const parts = ZipArchiveIndex.singleEntryArchive(entry, storedName);
  return concat(parts.header, zip.subarray(dataAt, dataAt + entry.compressedSize), parts.trailer);
}

const python = spawnSync('python', ['--version']).status === 0 ? 'python' : '';
const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'zip-archive-check-'));
let packIndex = 0;
/** 用 Python zipfile 解开单条目包（CRC 校验由 zipfile 完成），返回 [文件名, 内容]。 */
function extractWithPython(pack) {
  const file = path.join(workDir, `pack_${packIndex++}.zip`);
  fs.writeFileSync(file, pack);
  const script = 'import sys,zipfile\nz=zipfile.ZipFile(sys.argv[1])\nn=z.namelist()\n' +
    'sys.stdout.write(n[0]+"\\n"+z.read(n[0]).hex()) if len(n)==1 else sys.exit("entries:"+str(len(n)))';
  const run = spawnSync(python, ['-I', '-c', script, file], { encoding: 'utf-8' });
  if (run.status !== 0) throw new Error(run.stderr || `python exit ${run.status}`);
  const [name, hex] = run.stdout.split(/\r?\n/);
  return [name, Buffer.from(hex, 'hex').toString('utf-8')];
}

try {
  const text = '第一章 开始\n' + '正文内容。'.repeat(2000);
  const gbkName = new Uint8Array([0xC8, 0xFD, 0xCC, 0xE5, 0x2E, 0x74, 0x78, 0x74]); // “三体.txt”
  const staleName = utf8('old.txt');
  const unicodeExtra = concat(le(2, 0x7075), le(2, 5 + utf8('小说/新名.txt').length), new Uint8Array([1]),
    le(4, zlib.crc32(staleName)), utf8('小说/新名.txt'));

  console.log('central directory');
  const zip = buildZip([
    { name: utf8('合集/'), data: new Uint8Array(0), method: 0, flags: 0x0800 },
    { name: utf8('合集/诡秘之主.txt'), data: utf8(text), flags: 0x0800 },
    { name: gbkName, data: utf8('三体正文') },
    { name: utf8('mac/雪中悍刀行.epub'), data: utf8('epub-bytes'), method: 0 },
    { name: staleName, data: utf8('unicode path'), extra: unicodeExtra },
    { name: utf8('stream.pdf'), data: utf8('%PDF-1.4 stream'), descriptor: true },
    { name: utf8('__MACOSX/合集/._诡秘之主.txt'), data: utf8('fork'), flags: 0x0800 },
    { name: utf8('合集/._隐藏.txt'), data: utf8('fork'), flags: 0x0800 },
    { name: utf8('封面.jpg'), data: utf8('jpg'), flags: 0x0800 },
    { name: utf8('inner.zip'), data: utf8('zip'), method: 0 },
    { name: utf8('secret.mobi'), data: utf8('enc'), flags: 0x0001, method: 0 },
    { name: utf8('bzip.txt'), data: utf8('bz'), method: 0 },
  ], { comment: utf8('archive comment') });
  const entries = readEntries(zip);
  equal(entries.length, 12, 'reads every central directory record past an archive comment');
  equal(entries[2].name, '三体.txt', 'GBK file name without the UTF-8 flag decodes as GB18030');
  equal(entries[3].name, 'mac/雪中悍刀行.epub', 'unflagged UTF-8 file name (macOS) stays UTF-8');
  equal(entries[4].name, '小说/新名.txt', 'Info-ZIP Unicode path extra wins when its CRC matches the raw name');
  const books = ZipArchiveIndex.bookEntries(entries, ['txt', 'epub', 'mobi', 'pdf']);
  equal(books.map((entry) => entry.name),
    ['合集/诡秘之主.txt', '三体.txt', 'mac/雪中悍刀行.epub', '小说/新名.txt', 'stream.pdf', 'secret.mobi', 'bzip.txt'],
    'keeps book files only: skips folders, __MACOSX, ._ forks, images and nested archives');
  equal(ZipArchiveIndex.baseName('合集/诡秘之主.txt'), '诡秘之主.txt', 'baseName drops the in-archive folder');

  console.log('entry problems');
  equal(ZipArchiveIndex.entryProblem(books[0]), '', 'deflated entry is importable');
  equal(ZipArchiveIndex.entryProblem(books[2]), '', 'stored entry is importable');
  equal(ZipArchiveIndex.entryProblem(books[5]), '已加密，暂不支持', 'encrypted entry is reported');
  const bzip = { ...books[6], method: 12 };
  check(/压缩方式不支持/.test(ZipArchiveIndex.entryProblem(bzip)), 'bzip2 / other methods are reported');
  check(/1 GB/.test(ZipArchiveIndex.entryProblem({ ...books[0], uncompressedSize: 2 * 1024 * 1024 * 1024 })),
    'entries over the size cap are reported');
  check(/损坏/.test(ZipArchiveIndex.entryProblem({ ...books[2], uncompressedSize: books[2].compressedSize + 1 })),
    'stored entry whose sizes disagree is reported');

  console.log('descriptor entry sizes');
  equal([books[4].crc32 === zlib.crc32(utf8('%PDF-1.4 stream')), books[4].uncompressedSize],
    [true, utf8('%PDF-1.4 stream').length], 'data-descriptor entry takes CRC and size from the central directory');

  const modified = new Date(ZipArchiveIndex.modifiedMillis(books[0]));
  equal([modified.getFullYear(), modified.getMonth() + 1, modified.getDate(), modified.getHours(),
    modified.getMinutes(), modified.getSeconds()], [2024, 3, 15, 10, 20, 30], 'DOS timestamp converts to local time');
  equal(ZipArchiveIndex.modifiedMillis({ ...books[0], dosDate: 0 }), 0, 'invalid DOS date yields 0');

  console.log('single-entry repack');
  if (!python) {
    console.log('  skip - python not found; repack extraction not checked');
  } else {
    for (const [index, expected, ext] of [[0, text, 'txt'], [1, '三体正文', 'txt'], [2, 'epub-bytes', 'epub'],
      [4, '%PDF-1.4 stream', 'pdf']]) {
      const [name, content] = extractWithPython(rewrap(zip, books[index], `book.${ext}`));
      check(name === `book.${ext}` && content === expected, `repacked ${books[index].name} extracts intact`,
        `${name} ${content.slice(0, 30)}`);
    }
  }

  console.log('zip64');
  const zip64 = buildZip([{ name: utf8('大书.txt'), data: utf8(text), flags: 0x0800, zip64: true }], { zip64End: true });
  const big = readEntries(zip64);
  equal([big.length, big[0].name, big[0].uncompressedSize, big[0].localHeaderOffset],
    [1, '大书.txt', utf8(text).length, 0], 'ZIP64 end record and extra field supply count, sizes and offset');
  if (python) {
    const [, content] = extractWithPython(rewrap(zip64, big[0], 'book.txt'));
    check(content === text, 'ZIP64 entry repacks into a plain single-entry ZIP');
  }

  console.log('invalid input');
  throwsWith(() => readEntries(utf8('not a zip file at all, just text')), /不是有效的 ZIP/, 'non-ZIP file is rejected');
  throwsWith(() => readEntries(zip.subarray(0, zip.length - 40)), /不是有效的 ZIP|结构不完整/,
    'truncated archive is rejected');
  throwsWith(() => ZipArchiveIndex.localDataOffset(new Uint8Array(30), 0), /损坏/, 'bad local header is rejected');
} finally {
  fs.rmSync(workDir, { recursive: true, force: true });
  cleanup();
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall zip archive checks passed');
