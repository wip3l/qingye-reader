import fs from '@ohos.file.fs';
import util from '@ohos.util';

/** 模型里有几个说话人、各叫什么。names 为空时只按编号显示。 */
export class LocalTtsSpeakerInfo {
  count: number = 1;
  names: string[] = [];
}

/**
 * 读导入模型的说话人信息。sherpa-onnx 导出的模型把 n_speakers、speaker_names 写在 ONNX 的
 * metadata_props 里（ModelProto 第 14 号字段）。顶层字段只有十来个，几百 MB 的 graph 按长度跳过，
 * 所以只读几十个字节加元数据本身，不用把模型读进内存。
 */
export class LocalTtsSpeakers {
  /** Kokoro 每个音色是 510×1×256 个 float32。 */
  private static readonly KOKORO_VOICE_BYTES: number = 510 * 256 * 4;
  private static readonly MAX_SPEAKERS: number = 4096;
  private static readonly MAX_META_BYTES: number = 1024 * 1024;

  static detect(dir: string, modelFile: string, kind: string, voicesFile: string): LocalTtsSpeakerInfo {
    const info = new LocalTtsSpeakerInfo();
    let meta = new Map<string, string>();
    try {
      meta = LocalTtsSpeakers.readOnnxMeta(`${dir}/${modelFile}`);
    } catch (error) {
      console.warn('[LocalTts] read onnx metadata failed:', error);
    }
    let count = Math.floor(Number(meta.get('n_speakers') || '0'));
    if (kind === 'kokoro' && voicesFile && !(count > 0)) {
      try {
        const bytes = fs.statSync(`${dir}/${voicesFile}`).size;
        if (bytes > 0 && bytes % LocalTtsSpeakers.KOKORO_VOICE_BYTES === 0) {
          count = bytes / LocalTtsSpeakers.KOKORO_VOICE_BYTES;
        }
      } catch (_) {
      }
    }
    if (!(count > 0) || count > LocalTtsSpeakers.MAX_SPEAKERS) return info;
    info.count = count;
    const names = (meta.get('speaker_names') || '').split(',').map((item: string): string => item.trim());
    if (names.length === count && names.every((item: string): boolean => item.length > 0 && item.length <= 40)) {
      info.names = names;
    }
    return info;
  }

  /** 默认说话人：有中文音色（Kokoro 的 zf_/zm_）就用第一个中文的，否则 0 号。 */
  static defaultSid(info: LocalTtsSpeakerInfo): number {
    const index = info.names.findIndex((name: string): boolean => /^z[fm]_/i.test(name));
    return index >= 0 ? index : 0;
  }

  /** 列表里的名字：有名字用名字，没有就是“N 号”。 */
  static title(info: LocalTtsSpeakerInfo, sid: number): string {
    return info.names[sid] || `${sid} 号`;
  }

  /** Kokoro 音色名前两个字母是语种和性别，翻成中文；认不出来返回空串。 */
  static describe(name: string): string {
    const match = /^([a-z])([fm])_/i.exec(name || '');
    if (!match) return '';
    const languages: Record<string, string> = {
      'a': '美式英语', 'b': '英式英语', 'z': '中文', 'j': '日语', 'e': '西班牙语', 'f': '法语',
      'h': '印地语', 'i': '意大利语', 'p': '葡萄牙语'
    };
    const language = languages[match[1].toLowerCase()];
    if (!language) return '';
    return `${language}${match[2].toLowerCase() === 'f' ? '女声' : '男声'}`;
  }

  /** 逐个读顶层字段，只解析 metadata_props，其余按线格式跳过。 */
  static readOnnxMeta(path: string): Map<string, string> {
    const result = new Map<string, string>();
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(path).size;
      const decoder = util.TextDecoder.create('utf-8');
      let offset = 0;
      // 每次读一小段来解析 tag 和长度；varint 最长 10 字节，两个加起来 20 字节足够。
      const head = new Uint8Array(20);
      while (offset < size) {
        const read = fs.readSync(file.fd, head.buffer, { offset: offset, length: Math.min(20, size - offset) });
        if (read <= 0) break;
        const tag = LocalTtsSpeakers.varint(head, 0, read);
        if (tag.next < 0) break;
        const field = Math.floor(tag.value / 8);
        const wire = tag.value % 8;
        let cursor = offset + tag.next;
        if (wire === 0) {
          const value = LocalTtsSpeakers.varint(head, tag.next, read);
          if (value.next < 0) break;
          cursor = offset + value.next;
        } else if (wire === 1) {
          cursor += 8;
        } else if (wire === 5) {
          cursor += 4;
        } else if (wire === 2) {
          const length = LocalTtsSpeakers.varint(head, tag.next, read);
          if (length.next < 0) break;
          const start = offset + length.next;
          if (start + length.value > size) break;
          if (field === 14 && length.value <= LocalTtsSpeakers.MAX_META_BYTES) {
            const body = new Uint8Array(length.value);
            fs.readSync(file.fd, body.buffer, { offset: start, length: length.value });
            LocalTtsSpeakers.readEntry(body, decoder, result);
          }
          cursor = start + length.value;
        } else {
          break;
        }
        offset = cursor;
      }
    } finally {
      fs.closeSync(file);
    }
    return result;
  }

  /** StringStringEntryProto：1 号字段 key，2 号字段 value。 */
  private static readEntry(body: Uint8Array, decoder: util.TextDecoder, result: Map<string, string>): void {
    let key = '';
    let value = '';
    let index = 0;
    while (index < body.length) {
      const tag = LocalTtsSpeakers.varint(body, index, body.length);
      if (tag.next < 0 || tag.value % 8 !== 2) return;
      const length = LocalTtsSpeakers.varint(body, tag.next, body.length);
      if (length.next < 0 || length.next + length.value > body.length) return;
      const text = decoder.decodeToString(body.subarray(length.next, length.next + length.value));
      const field = Math.floor(tag.value / 8);
      if (field === 1) key = text;
      else if (field === 2) value = text;
      index = length.next + length.value;
    }
    if (key) result.set(key, value);
  }

  /** 读一个 varint；用乘法累加，避免位运算在超过 2^31 时溢出。next 为 -1 表示数据不够或格式不对。 */
  private static varint(bytes: Uint8Array, start: number, end: number): VarintResult {
    let value = 0;
    let scale = 1;
    for (let index = start; index < end && index < start + 10; index++) {
      const byte = bytes[index];
      value += (byte & 0x7f) * scale;
      scale *= 128;
      if (byte < 0x80) return new VarintResult(value, index + 1);
    }
    return new VarintResult(0, -1);
  }
}

class VarintResult {
  value: number;
  next: number;

  constructor(value: number, next: number) {
    this.value = value;
    this.next = next;
  }
}
