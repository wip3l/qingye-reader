import { EpubHtmlConverter } from './EpubHtmlConverter';
import { MobiBook, MobiBookParser, MobiImage, MobiTocItem } from './MobiBookParser';
import type { MobiTextDecoder } from './MobiBookParser';

/** 索引记录里的一条：标签（名字）和各个 tag 的取值。 */
class Kf8IndexEntry {
  label: string = '';
  tags: Map<number, number[]> = new Map<number, number[]>();
}

class Kf8Index {
  entries: Kf8IndexEntry[] = [];
  /** CNCX 字符串池：键是 tag 里给的偏移（记录序号 × 0x10000 + 记录内偏移）。 */
  cncx: Map<number, string> = new Map<number, string>();
}

/** 拼好的一段正文（一个骨架加上插进去的片段），start/end 是它在“插入坐标”里占的范围。 */
class Kf8Part {
  start: number = 0;
  end: number = 0;
  bytes: Uint8Array = new Uint8Array(0);
}

class Kf8Position {
  part: number = -1;
  local: number = 0;
}

class Kf8VarInt {
  consumed: number = 0;
  value: number = 0;
}

/**
 * KF8（AZW3，以及 MOBI 头版本 8 的书）解析成和 MOBI6 一样的 MobiBook，之后写文件、分章与 MOBI 相同：
 * 正文（第一条“流”）由骨架表（SKEL）和片段表（FRAG）拼回每个 XHTML 文件；
 * kindle:pos:fid 链接与 NCX 目录的位置换成插在对应位置的锚点；kindle:embed 换成写出的图片；
 * 样式表（kindle:flow）不用。DRM 加密与 HUFF/CDIC 压缩给出明确提示。
 */
export class Kf8BookParser {
  private static readonly MAX_TEXT_BYTES: number = 256 * 1024 * 1024;
  private static readonly NONE: number = 0xFFFFFFFF;

  /** PalmDB 是 BOOKMOBI、第 0 条记录的 MOBI 头版本 ≥ 8。旧版 MOBI 与 KF8 合在一起的文件仍按 MOBI6 读。 */
  static isKf8(data: Uint8Array): boolean {
    if (data.length < 86 || Kf8BookParser.ascii(data, 60, 8) !== 'BOOKMOBI') return false;
    const offsets = Kf8BookParser.recordOffsets(data);
    const header = Kf8BookParser.record(data, offsets, 0);
    if (header.length < 40 || Kf8BookParser.ascii(header, 16, 4) !== 'MOBI') return false;
    return Kf8BookParser.u32(header, 36) >= 8;
  }

  static parse(data: Uint8Array, decode: MobiTextDecoder, imageDir: string): MobiBook {
    if (data.length < 86 || Kf8BookParser.ascii(data, 60, 8) !== 'BOOKMOBI') throw new Error('不是有效的 AZW3 文件');
    const offsets = Kf8BookParser.recordOffsets(data);
    if (offsets.length === 0) throw new Error('AZW3 文件没有记录');
    const record = (index: number): Uint8Array => Kf8BookParser.record(data, offsets, index);
    const header = record(0);
    if (header.length < 256 || Kf8BookParser.ascii(header, 16, 4) !== 'MOBI') throw new Error('AZW3 文件头不完整');
    const compression = Kf8BookParser.u16(header, 0);
    const textRecordCount = Kf8BookParser.u16(header, 8);
    if (Kf8BookParser.u16(header, 12) !== 0) throw new Error('这本书有 DRM 加密，无法导入');
    if (compression === 17480) throw new Error('这本书使用 HUFF/CDIC 压缩，暂不支持，请转换为 EPUB 后导入');
    if (compression !== 1 && compression !== 2) throw new Error(`不支持的压缩方式（${compression}）`);

    const book = new MobiBook();
    const mobiLength = Kf8BookParser.u32(header, 20);
    const encoding = Kf8BookParser.u32(header, 28) === 65001 ? 'utf-8' : 'windows-1252';
    const nameOffset = Kf8BookParser.u32(header, 84);
    const nameLength = Kf8BookParser.u32(header, 88);
    if (nameLength > 0 && nameOffset + nameLength <= header.length) {
      book.title = decode(header.subarray(nameOffset, nameOffset + nameLength), encoding).trim();
    }
    if ((Kf8BookParser.u32(header, 128) & 0x40) !== 0) {
      MobiBookParser.readExth(header, 16 + mobiLength, encoding, decode, book);
    }
    if (!book.title) book.title = Kf8BookParser.ascii(data, 0, 32).replace(/\u0000[\s\S]*$/, '').replace(/_/g, ' ').trim();
    const extraFlags = mobiLength >= 0xE4 && header.length >= 0xF4 ? Kf8BookParser.u16(header, 0xF2) : 0;
    const resourceStart = Kf8BookParser.u32(header, 108);
    const fdstIndex = Kf8BookParser.u32(header, 192);
    const ncxIndex = Kf8BookParser.u32(header, 244);
    const fragIndex = Kf8BookParser.u32(header, 248);
    const skelIndex = Kf8BookParser.u32(header, 252);

    // 正文记录：解压、去掉尾部附加数据后拼起来；FDST 把它分成几条流，第一条是 XHTML。
    const chunks: Uint8Array[] = [];
    let total = 0;
    for (let i = 1; i <= textRecordCount && i < offsets.length; i++) {
      let raw = record(i);
      raw = raw.subarray(0, Math.max(0, raw.length - MobiBookParser.trailingSize(raw, extraFlags)));
      const text = compression === 2 ? MobiBookParser.palmDocDecompress(raw) : raw;
      total += text.length;
      if (total > Kf8BookParser.MAX_TEXT_BYTES) throw new Error('AZW3 正文过大');
      chunks.push(text);
    }
    const raw = Kf8BookParser.concat(chunks, total);
    let flow = raw;
    if (fdstIndex !== Kf8BookParser.NONE && fdstIndex < offsets.length) {
      const fdst = record(fdstIndex);
      if (Kf8BookParser.ascii(fdst, 0, 4) === 'FDST' && Kf8BookParser.u32(fdst, 8) > 0) {
        const start = Kf8BookParser.u32(fdst, 12);
        const end = Math.min(raw.length, Kf8BookParser.u32(fdst, 16));
        if (start < end) flow = raw.subarray(start, end);
      }
    }

    // 图片：从资源记录起，认得出的图片按资源序号（从 1 起）编号，kindle:embed 用的就是这个序号。
    if (resourceStart !== Kf8BookParser.NONE && resourceStart > 0) {
      for (let index = resourceStart; index < offsets.length; index++) {
        const bytes = record(index);
        const ext = MobiBookParser.imageExtension(bytes);
        if (!ext) continue;
        const image = new MobiImage();
        image.recIndex = index - resourceStart + 1;
        image.bytes = bytes;
        image.ext = ext;
        book.images.push(image);
      }
    }
    if (book.coverRecIndex > 0 && !book.images.some((image: MobiImage): boolean => image.recIndex === book.coverRecIndex)) {
      book.coverRecIndex = 0;
    }

    const skeletons = Kf8BookParser.readIndex(skelIndex, record, offsets.length, decode).entries;
    const fragments = Kf8BookParser.readIndex(fragIndex, record, offsets.length, decode).entries;
    const parts = Kf8BookParser.assemble(flow, skeletons, fragments);
    const fragmentStarts = fragments.map((entry: Kf8IndexEntry): number => parseInt(entry.label, 10) || 0);
    const ncx = Kf8BookParser.readIndex(ncxIndex, record, offsets.length, decode);
    Kf8BookParser.buildBook(book, parts, fragmentStarts, ncx, encoding, decode, imageDir);
    return book;
  }

  /**
   * 骨架 i 是 flow[skelPos, skelPos+skelLen)；它后面紧跟着属于它的片段，按顺序取各自的长度，
   * 依次插到骨架的 insertPos − skelPos 处（插入位置已经算上前面插进去的片段）。
   */
  static assemble(flow: Uint8Array, skeletons: Kf8IndexEntry[], fragments: Kf8IndexEntry[]): Kf8Part[] {
    const parts: Kf8Part[] = [];
    if (skeletons.length === 0) {
      const whole = new Kf8Part();
      whole.end = flow.length;
      whole.bytes = flow;
      parts.push(whole);
      return parts;
    }
    let fragmentPointer = 0;
    for (const skeleton of skeletons) {
      const range = skeleton.tags.get(6) || [];
      const skelPos = range.length > 0 ? range[0] : 0;
      const skelLen = range.length > 1 ? range[1] : 0;
      const count = (skeleton.tags.get(1) || [0])[0] || 0;
      let assembled: Uint8Array = flow.slice(skelPos, Math.min(flow.length, skelPos + skelLen));
      let base = skelPos + skelLen;
      for (let k = 0; k < count && fragmentPointer < fragments.length; k++) {
        const fragment = fragments[fragmentPointer++];
        const length = (fragment.tags.get(6) || [0, 0])[1] || 0;
        const slice = flow.subarray(base, Math.min(flow.length, base + length));
        const insertAt = Math.max(0, Math.min(assembled.length, (parseInt(fragment.label, 10) || 0) - skelPos));
        const next = new Uint8Array(assembled.length + slice.length);
        next.set(assembled.subarray(0, insertAt), 0);
        next.set(slice, insertAt);
        next.set(assembled.subarray(insertAt), insertAt + slice.length);
        assembled = next;
        base += length;
      }
      const part = new Kf8Part();
      part.start = skelPos;
      part.end = skelPos + assembled.length;
      part.bytes = assembled;
      parts.push(part);
    }
    return parts;
  }

  /** 链接、目录指向的位置 → 插锚点 → 解码 → 改写 kindle: 地址 → 取 body；目录条目指向锚点。 */
  private static buildBook(book: MobiBook, parts: Kf8Part[], fragmentStarts: number[], ncx: Kf8Index,
    encoding: string, decode: MobiTextDecoder, imageDir: string): void {
    const anchorIds: Map<string, string> = new Map<string, string>();
    const perPart: Map<number, number[]> = new Map<number, number[]>();
    let anchorCount = 0;
    const anchorFor = (position: Kf8Position): string => {
      const key = `${position.part}:${position.local}`;
      let id = anchorIds.get(key);
      if (!id) {
        id = `kf${++anchorCount}`;
        anchorIds.set(key, id);
        const list = perPart.get(position.part) || [];
        list.push(position.local);
        perPart.set(position.part, list);
      }
      return id;
    };
    // 每段 body 的范围只算一次：书里的链接成千上万时，逐个从头找 </body> 会很慢。
    const bodies: Map<number, number[]> = new Map<number, number[]>();
    const locate = (pos: number): Kf8Position => {
      const result = new Kf8Position();
      for (let i = 0; i < parts.length; i++) {
        if (pos >= parts[i].start && pos < parts[i].end) {
          let body = bodies.get(i);
          if (!body) {
            body = Kf8BookParser.bodyRange(parts[i].bytes);
            bodies.set(i, body);
          }
          result.part = i;
          result.local = Kf8BookParser.anchorPoint(parts[i].bytes, pos - parts[i].start, body[0], body[1]);
          return result;
        }
      }
      return result;
    };
    const fidPosition = (fid: number, off: number): Kf8Position =>
      fid >= 0 && fid < fragmentStarts.length ? locate(fragmentStarts[fid] + off) : new Kf8Position();

    // 链接：kindle:pos:fid:XXXX:off:YYYYYYYYYY（32 进制）。
    const links: Map<string, string> = new Map<string, string>();
    for (const part of parts) {
      for (const target of Kf8BookParser.posFidLinks(part.bytes)) {
        if (links.has(target)) continue;
        const match = /^([0-9a-v]{4}):off:([0-9a-v]{10})$/i.exec(target);
        if (!match) continue;
        const position = fidPosition(parseInt(match[1], 32), parseInt(match[2], 32));
        if (position.part < 0) continue;
        links.set(target, `${Kf8BookParser.partFile(position.part)}#${anchorFor(position)}`);
      }
    }

    // 目录：NCX 条目的 tag 6 是 [fid, off]，老一些的用 tag 1 的绝对位置；标题在 CNCX 里。
    const tocPositions: Kf8Position[] = [];
    const tocTitles: string[] = [];
    for (const entry of ncx.entries) {
      const fidOff = entry.tags.get(6);
      const offset = entry.tags.get(1);
      const position = fidOff && fidOff.length >= 2 ? fidPosition(fidOff[0], fidOff[1]) :
        (offset && offset.length > 0 ? locate(offset[0]) : new Kf8Position());
      const titleKey = (entry.tags.get(3) || [-1])[0];
      const title = (ncx.cncx.get(titleKey) || '').trim();
      if (position.part < 0 || !title) continue;
      anchorFor(position);
      tocPositions.push(position);
      tocTitles.push(title);
    }

    for (let i = 0; i < parts.length; i++) {
      const locals = (perPart.get(i) || []).slice().sort((a: number, b: number): number => a - b);
      const anchors = locals.map((local: number): string => `<a id="${anchorIds.get(`${i}:${local}`) || ''}"></a>`);
      let html = decode(Kf8BookParser.insertAll(parts[i].bytes, locals, anchors), encoding);
      html = html.replace(/kindle:pos:fid:([0-9a-v]{4}):off:([0-9a-v]{10})/gi,
        (whole: string, fid: string, off: string): string => links.get(`${fid}:off:${off}`) || '#');
      html = html.replace(/kindle:embed:([0-9a-v]{4})(\?mime=[^"')\s]*)?/gi, (_whole: string, value: string): string => {
        const image = book.images.find((item: MobiImage): boolean => item.recIndex === parseInt(value, 32));
        return image ? `${imageDir}/${MobiBookParser.imageName(image)}` : '';
      });
      // 样式表、SVG 等另外的流不用。
      html = html.replace(/<link\b[^>]*kindle:flow[^>]*>/gi, '');
      book.parts.push(EpubHtmlConverter.bodyOf(html));
    }
    for (let i = 0; i < tocPositions.length; i++) {
      const item = new MobiTocItem();
      item.part = tocPositions[i].part;
      item.fragment = anchorIds.get(`${tocPositions[i].part}:${tocPositions[i].local}`) || '';
      item.title = tocTitles[i];
      book.toc.push(item);
    }
  }

  static partFile(index: number): string {
    return `part${`${index + 1}`.padStart(5, '0')}.html`;
  }

  /**
   * 锚点落点：限制在 <body> 里；落在一个标签中间时，开始标签挪到它前面，结束标签挪到它后面。
   */
  static anchorPoint(bytes: Uint8Array, local: number, bodyStart: number, bodyEnd: number): number {
    let at = Math.max(bodyStart, Math.min(local, bodyEnd));
    const lt = Kf8BookParser.lastIndexOfByte(bytes, 0x3C, at - 1);
    const gt = Kf8BookParser.lastIndexOfByte(bytes, 0x3E, at - 1);
    if (lt > gt && lt >= bodyStart) {
      if (bytes[lt + 1] === 0x2F) {
        const close = bytes.indexOf(0x3E, at);
        at = close >= 0 ? close + 1 : at;
      } else {
        at = lt;
      }
    }
    return at;
  }

  /** body 内容的 [开始, 结束)：开始在 <body ...> 之后，结束在最后一个 </body> 处；没有 body 时是整段。 */
  static bodyRange(bytes: Uint8Array): number[] {
    const body = Kf8BookParser.indexOfAscii(bytes, '<body', 0);
    const close = body >= 0 ? bytes.indexOf(0x3E, body) : -1;
    const start = close >= 0 ? close + 1 : 0;
    const end = Kf8BookParser.lastIndexOfAscii(bytes, '</body', bytes.length);
    return [start, end >= start ? end : bytes.length];
  }

  /** 按从小到大的位置一次插入多段 ASCII 文本。 */
  static insertAll(bytes: Uint8Array, positions: number[], texts: string[]): Uint8Array {
    if (positions.length === 0) return bytes;
    let extra = 0;
    for (const text of texts) extra += text.length;
    const out = new Uint8Array(bytes.length + extra);
    let read = 0;
    let write = 0;
    for (let i = 0; i < positions.length; i++) {
      const at = Math.max(read, Math.min(bytes.length, positions[i]));
      out.set(bytes.subarray(read, at), write);
      write += at - read;
      read = at;
      const text = texts[i];
      for (let c = 0; c < text.length; c++) out[write + c] = text.charCodeAt(c) & 0xFF;
      write += text.length;
    }
    out.set(bytes.subarray(read), write);
    return out;
  }

  /** 正文里所有 kindle:pos:fid 链接的 “XXXX:off:YYYYYYYYYY” 部分。 */
  private static posFidLinks(bytes: Uint8Array): string[] {
    const result: string[] = [];
    const marker = 'kindle:pos:fid:';
    let at = Kf8BookParser.indexOfAscii(bytes, marker, 0);
    while (at >= 0) {
      const start = at + marker.length;
      result.push(Kf8BookParser.ascii(bytes, start, 19));
      at = Kf8BookParser.indexOfAscii(bytes, marker, start);
    }
    return result;
  }

  /**
   * INDX 索引：第一条记录是总头（含 TAGX 标签表和 CNCX 记录数），后面 count 条是数据记录（IDXT 给出每条的位置），
   * 再后面是 CNCX 字符串记录。每条：1 字节标签长度、标签、控制字节，再按 TAGX 读出各 tag 的变长整数。
   */
  static readIndex(first: number, record: (index: number) => Uint8Array, recordCount: number,
    decode: MobiTextDecoder): Kf8Index {
    const result = new Kf8Index();
    if (first <= 0 || first === Kf8BookParser.NONE || first >= recordCount) return result;
    const head = record(first);
    if (Kf8BookParser.ascii(head, 0, 4) !== 'INDX') return result;
    const headerLength = Kf8BookParser.u32(head, 4);
    const count = Kf8BookParser.u32(head, 24);
    const cncxCount = Kf8BookParser.u32(head, 52);
    if (Kf8BookParser.ascii(head, headerLength, 4) !== 'TAGX') return result;
    const tagxLength = Kf8BookParser.u32(head, headerLength + 4);
    const controlByteCount = Kf8BookParser.u32(head, headerLength + 8);
    const table: number[][] = [];
    for (let at = headerLength + 12; at + 4 <= headerLength + tagxLength && at + 4 <= head.length; at += 4) {
      table.push([head[at], head[at + 1], head[at + 2], head[at + 3]]);
    }
    for (let i = 0; i < cncxCount; i++) {
      const data = record(first + count + 1 + i);
      let offset = 0;
      while (offset < data.length && data[offset] !== 0) {
        const start = offset;
        const length = Kf8BookParser.forwardVarint(data, offset);
        offset += length.consumed;
        result.cncx.set(i * 0x10000 + start, decode(data.subarray(offset, offset + length.value), 'utf-8'));
        offset += length.value;
      }
    }
    for (let i = 1; i <= count; i++) {
      const data = record(first + i);
      if (Kf8BookParser.ascii(data, 0, 4) !== 'INDX') continue;
      const idxt = Kf8BookParser.u32(data, 20);
      const entryCount = Kf8BookParser.u32(data, 24);
      const positions: number[] = [];
      for (let j = 0; j < entryCount; j++) positions.push(Kf8BookParser.u16(data, idxt + 4 + 2 * j));
      for (let j = 0; j < entryCount; j++) {
        const start = positions[j];
        const end = j + 1 < entryCount ? positions[j + 1] : idxt;
        if (start >= end || start >= data.length) continue;
        const labelLength = data[start];
        const entry = new Kf8IndexEntry();
        entry.label = Kf8BookParser.ascii(data, start + 1, labelLength);
        entry.tags = Kf8BookParser.readTagMap(controlByteCount, table, data, start + 1 + labelLength, end);
        result.entries.push(entry);
      }
    }
    return result;
  }

  /** 按 TAGX 标签表读一条的 tag 值（与 KindleUnpack 的 getTagMap 同一算法）。 */
  static readTagMap(controlByteCount: number, table: number[][], data: Uint8Array, start: number,
    end: number): Map<number, number[]> {
    const result: Map<number, number[]> = new Map<number, number[]>();
    let controlIndex = 0;
    let dataAt = start + controlByteCount;
    const pending: number[][] = [];
    for (const row of table) {
      const tag = row[0];
      const perEntry = row[1];
      let mask = row[2];
      if (row[3] === 0x01) {
        controlIndex++;
        continue;
      }
      let value = data[start + controlIndex] & mask;
      if (value === 0) continue;
      if (value === mask) {
        if (Kf8BookParser.bitCount(mask) > 1) {
          const width = Kf8BookParser.forwardVarint(data, dataAt);
          dataAt += width.consumed;
          pending.push([tag, -1, width.value, perEntry]);
        } else {
          pending.push([tag, 1, -1, perEntry]);
        }
      } else {
        while ((mask & 0x01) === 0) {
          mask >>= 1;
          value >>= 1;
        }
        pending.push([tag, value, -1, perEntry]);
      }
    }
    for (const item of pending) {
      const values: number[] = [];
      if (item[1] >= 0) {
        for (let n = 0; n < item[1] * item[3] && dataAt < end; n++) {
          const read = Kf8BookParser.forwardVarint(data, dataAt);
          dataAt += read.consumed;
          values.push(read.value);
        }
      } else {
        let consumed = 0;
        while (consumed < item[2] && dataAt < end) {
          const read = Kf8BookParser.forwardVarint(data, dataAt);
          dataAt += read.consumed;
          consumed += read.consumed;
          values.push(read.value);
        }
      }
      result.set(item[0], values);
    }
    return result;
  }

  /** 前向变长整数：每字节低 7 位，最高位为 1 的那个字节是最后一个。 */
  static forwardVarint(data: Uint8Array, offset: number): Kf8VarInt {
    const result = new Kf8VarInt();
    while (offset + result.consumed < data.length) {
      const byte = data[offset + result.consumed];
      result.consumed++;
      result.value = result.value * 128 + (byte & 0x7F);
      if ((byte & 0x80) !== 0) break;
    }
    return result;
  }

  private static bitCount(value: number): number {
    let count = 0;
    let rest = value;
    while (rest !== 0) {
      count += rest & 1;
      rest >>= 1;
    }
    return count;
  }

  static recordOffsets(data: Uint8Array): number[] {
    const recordCount = Kf8BookParser.u16(data, 76);
    const offsets: number[] = [];
    for (let i = 0; i < recordCount; i++) {
      const at = 78 + i * 8;
      if (at + 4 > data.length) break;
      offsets.push(Kf8BookParser.u32(data, at));
    }
    return offsets;
  }

  static record(data: Uint8Array, offsets: number[], index: number): Uint8Array {
    if (index < 0 || index >= offsets.length) return new Uint8Array(0);
    const start = offsets[index];
    const end = index + 1 < offsets.length ? offsets[index + 1] : data.length;
    if (start >= end || end > data.length) return new Uint8Array(0);
    return data.subarray(start, end);
  }

  private static concat(chunks: Uint8Array[], total: number): Uint8Array {
    const bytes = new Uint8Array(total);
    let cursor = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, cursor);
      cursor += chunk.length;
    }
    return bytes;
  }

  private static indexOfAscii(bytes: Uint8Array, text: string, from: number): number {
    const first = text.charCodeAt(0);
    let at = bytes.indexOf(first, from);
    while (at >= 0 && at + text.length <= bytes.length) {
      let matched = true;
      for (let i = 1; i < text.length; i++) {
        const byte = bytes[at + i];
        const want = text.charCodeAt(i);
        if (byte !== want && !(want >= 0x61 && want <= 0x7A && byte === want - 0x20)) {
          matched = false;
          break;
        }
      }
      if (matched) return at;
      at = bytes.indexOf(first, at + 1);
    }
    return -1;
  }

  private static lastIndexOfAscii(bytes: Uint8Array, text: string, before: number): number {
    let at = Kf8BookParser.indexOfAscii(bytes, text, 0);
    let last = -1;
    while (at >= 0 && at < before) {
      last = at;
      at = Kf8BookParser.indexOfAscii(bytes, text, at + 1);
    }
    return last;
  }

  private static lastIndexOfByte(bytes: Uint8Array, value: number, from: number): number {
    for (let i = Math.min(from, bytes.length - 1); i >= 0; i--) {
      if (bytes[i] === value) return i;
    }
    return -1;
  }

  private static ascii(bytes: Uint8Array, start: number, length: number): string {
    let text = '';
    for (let i = start; i < start + length && i < bytes.length; i++) text += String.fromCharCode(bytes[i]);
    return text;
  }

  private static u16(bytes: Uint8Array, at: number): number {
    return at + 2 <= bytes.length ? (bytes[at] << 8) | bytes[at + 1] : 0;
  }

  private static u32(bytes: Uint8Array, at: number): number {
    return at + 4 <= bytes.length ?
      ((bytes[at] * 0x1000000) + ((bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3])) : 0;
  }
}
