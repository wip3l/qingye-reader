/**
 * 有声书离线下载里不碰系统接口的判断：m3u8 解析、续传是否可接、边听边下的目标与淘汰。
 * 单独成文件是为了能在 Node 回归脚本里直接测。
 */

export class HlsVariant {
  url: string = '';
  bandwidth: number = 0;
}

export class HlsSegment {
  url: string = '';
  sequence: number = 0;
  /** NONE 或 AES-128；其他加密方式在解析时就判为不支持。 */
  keyMethod: string = 'NONE';
  keyUrl: string = '';
  /** 32 位十六进制；为空时按媒体序号推算。 */
  ivHex: string = '';
}

export class HlsPlaylist {
  /** 主列表（多码率）时非空，媒体列表时为空。 */
  variants: HlsVariant[] = [];
  segments: HlsSegment[] = [];
  /** fMP4 的初始化段（EXT-X-MAP）。 */
  mapUrl: string = '';
  endList: boolean = false;
  /** 不支持离线的原因（SAMPLE-AES、DRM、直播流等），为空表示可以下载。 */
  unsupported: string = '';
}

/** 一章离线音频的登记信息，只放淘汰与核对要用的字段。 */
export class AudioOfflineEntry {
  chapterIndex: number = 0;
  chapterUrl: string = '';
  chapterTitle: string = '';
  voice: string = '';
  bytes: number = 0;
  createdAt: number = 0;
  auto: boolean = false;
}

/** 续传用的半截文件说明，写在 .part.json 里。 */
export class AudioPartialMeta {
  chapterUrl: string = '';
  voice: string = '';
  /** 已写入 .part 的字节数；m3u8 时是已完成分片的总和。 */
  bytes: number = 0;
  /** 整个文件的长度（Content-Range 里的总长），不知道时为 0。 */
  total: number = 0;
  etag: string = '';
  lastModified: string = '';
  /** m3u8 已完成的分片数；直链为 0。 */
  segmentsDone: number = 0;
  /** 1 表示这是拼接中的 m3u8，0 表示直链。 */
  segmented: number = 0;
  updatedAt: number = 0;
}

export class AudioOfflinePolicy {
  static readonly NOT_SEGMENTED_LIVE: string = '直播流没有结尾，无法离线';
  static readonly PROTECTED: string = '受保护的音频，无法离线';

  static isPlaylistText(text: string): boolean {
    return (text || '').replace(/^﻿/, '').trimStart().startsWith('#EXTM3U');
  }

  static parsePlaylist(text: string, baseUrl: string): HlsPlaylist {
    const playlist = new HlsPlaylist();
    const lines = (text || '').replace(/^﻿/, '').split(/\r?\n/).map((line: string): string => line.trim());
    let sequence = 0;
    let keyMethod = 'NONE';
    let keyUrl = '';
    let ivHex = '';
    let pendingBandwidth = -1;
    for (const line of lines) {
      if (!line) continue;
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        pendingBandwidth = Number(AudioOfflinePolicy.attribute(line, 'BANDWIDTH')) || 0;
      } else if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = Number(line.substring('#EXT-X-MEDIA-SEQUENCE:'.length)) || 0;
      } else if (line.startsWith('#EXT-X-KEY:')) {
        keyMethod = (AudioOfflinePolicy.attribute(line, 'METHOD') || 'NONE').toUpperCase();
        const uri = AudioOfflinePolicy.attribute(line, 'URI');
        keyUrl = uri ? AudioOfflinePolicy.resolveUrl(uri, baseUrl) : '';
        ivHex = (AudioOfflinePolicy.attribute(line, 'IV') || '').replace(/^0x/i, '');
        const format = AudioOfflinePolicy.attribute(line, 'KEYFORMAT');
        if (keyMethod !== 'NONE' && keyMethod !== 'AES-128') playlist.unsupported = AudioOfflinePolicy.PROTECTED;
        if (format && format !== 'identity') playlist.unsupported = AudioOfflinePolicy.PROTECTED;
      } else if (line.startsWith('#EXT-X-MAP:')) {
        const uri = AudioOfflinePolicy.attribute(line, 'URI');
        if (uri) playlist.mapUrl = AudioOfflinePolicy.resolveUrl(uri, baseUrl);
      } else if (line.startsWith('#EXT-X-ENDLIST')) {
        playlist.endList = true;
      } else if (!line.startsWith('#')) {
        const url = AudioOfflinePolicy.resolveUrl(line, baseUrl);
        if (pendingBandwidth >= 0) {
          const variant = new HlsVariant();
          variant.url = url;
          variant.bandwidth = pendingBandwidth;
          playlist.variants.push(variant);
          pendingBandwidth = -1;
        } else {
          const segment = new HlsSegment();
          segment.url = url;
          segment.sequence = sequence++;
          segment.keyMethod = keyMethod;
          segment.keyUrl = keyUrl;
          segment.ivHex = ivHex;
          playlist.segments.push(segment);
        }
      }
    }
    if (!playlist.unsupported && playlist.variants.length === 0 && !playlist.endList) {
      playlist.unsupported = AudioOfflinePolicy.NOT_SEGMENTED_LIVE;
    }
    return playlist;
  }

  /** 听书够用就行：选码率最低的一档，省流量也省空间。码率都缺失时取第一项。 */
  static pickVariant(variants: HlsVariant[]): HlsVariant | null {
    if (variants.length === 0) return null;
    const known = variants.filter((item: HlsVariant): boolean => item.bandwidth > 0);
    if (known.length === 0) return variants[0];
    return known.reduce((best: HlsVariant, item: HlsVariant): HlsVariant => item.bandwidth < best.bandwidth ? item : best);
  }

  /** AES-128 没写 IV 时，IV 是媒体序号的 16 字节大端表示。 */
  static segmentIv(segment: HlsSegment): Uint8Array {
    const iv = new Uint8Array(16);
    const hex = segment.ivHex.padStart(32, '0').slice(-32);
    if (segment.ivHex && /^[0-9a-f]+$/i.test(hex)) {
      for (let i = 0; i < 16; i++) iv[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
      return iv;
    }
    let value = Math.max(0, Math.floor(segment.sequence));
    for (let i = 15; i >= 0 && value > 0; i--) {
      iv[i] = value % 256;
      value = Math.floor(value / 256);
    }
    return iv;
  }

  /** 拼接后文件的扩展名：有初始化段是 fMP4，否则按分片扩展名，默认 ts。 */
  static segmentedExtension(playlist: HlsPlaylist): string {
    if (playlist.mapUrl) return 'm4a';
    const first = playlist.segments.length > 0 ? playlist.segments[0].url.split(/[?#]/)[0] : '';
    const match = first.match(/\.(aac|mp3|ts)$/i);
    return match ? match[1].toLowerCase() : 'ts';
  }

  /**
   * 直链续传：只有服务器按请求的起点返回 206，且文件没变过（ETag / Last-Modified / 总长一致）才接着写。
   * 返回 'append' 接着写，'restart' 从头写。
   */
  static resumeDecision(status: number, contentRange: string, meta: AudioPartialMeta,
    etag: string, lastModified: string): string {
    if (status !== 206 || meta.bytes <= 0) return 'restart';
    const match = (contentRange || '').match(/bytes\s+(\d+)-\d+\/(\d+|\*)/i);
    if (!match || Number(match[1]) !== meta.bytes) return 'restart';
    const total = match[2] === '*' ? 0 : Number(match[2]);
    if (meta.etag && etag) return meta.etag === etag ? 'append' : 'restart';
    if (meta.lastModified && lastModified) return meta.lastModified === lastModified ? 'append' : 'restart';
    // 没有校验头时只能比总长；总长也不知道就不冒险拼接。
    return meta.total > 0 && total === meta.total ? 'append' : 'restart';
  }

  /** 半截文件还能不能用：章节地址和音色都得对得上，且不超过保留期。 */
  static partialUsable(meta: AudioPartialMeta | null, chapterUrl: string, voice: string, now: number,
    keepMs: number): boolean {
    return !!meta && meta.bytes > 0 && meta.chapterUrl === chapterUrl && meta.voice === voice &&
      now - meta.updatedAt <= keepMs;
  }

  /** 边听边下要补的章节：当前章之后 count 章里还没下载的。 */
  static prefetchTargets(currentIndex: number, count: number, total: number, downloaded: Set<number>): number[] {
    const targets: number[] = [];
    for (let index = currentIndex + 1; index <= currentIndex + count && index < total; index++) {
      if (index >= 0 && !downloaded.has(index)) targets.push(index);
    }
    return targets;
  }

  /** 边听边下下载、并且已经听过的章节（当前章之前）可以删；手动下载的永远不自动删。 */
  static listenedAutoEntries(entries: AudioOfflineEntry[], currentIndex: number): AudioOfflineEntry[] {
    return entries.filter((entry: AudioOfflineEntry): boolean => entry.auto && entry.chapterIndex < currentIndex);
  }

  /**
   * 为腾出 needBytes 空间要删的边听边下章节：先删听过的，再按下载时间从旧到新；
   * 正在播的章节和它之后的预下载最后才动。不够腾出时返回能删的全部，由调用方判断是否仍超限。
   */
  static capEvictions(entries: AudioOfflineEntry[], currentIndex: number, needBytes: number): AudioOfflineEntry[] {
    if (needBytes <= 0) return [];
    const autos = entries.filter((entry: AudioOfflineEntry): boolean => entry.auto && entry.chapterIndex !== currentIndex);
    autos.sort((left: AudioOfflineEntry, right: AudioOfflineEntry): number => {
      const leftListened = left.chapterIndex < currentIndex ? 0 : 1;
      const rightListened = right.chapterIndex < currentIndex ? 0 : 1;
      return leftListened !== rightListened ? leftListened - rightListened : left.createdAt - right.createdAt;
    });
    const chosen: AudioOfflineEntry[] = [];
    let freed = 0;
    for (const entry of autos) {
      if (freed >= needBytes) break;
      chosen.push(entry);
      freed += Math.max(0, entry.bytes);
    }
    return chosen;
  }

  /**
   * 离线记录是不是这一章：章节地址相同，或标题相同（有的书源每次刷新目录地址里的令牌都会变）。
   * 两样都没记的旧记录只能按序号认。
   */
  static entryMatches(entry: AudioOfflineEntry, chapterUrl: string, chapterTitle: string): boolean {
    if (entry.chapterUrl && entry.chapterUrl === chapterUrl) return true;
    if (entry.chapterTitle && entry.chapterTitle === chapterTitle) return true;
    return !entry.chapterUrl && !entry.chapterTitle;
  }

  /**
   * 目录刷新后把离线记录对回新序号。返回 新序号 → 旧序号；对不上的记录不出现在结果里。
   * 原位置还对得上就不动；否则按唯一的地址、再按唯一的标题找新位置。重复的不认，宁可当作没下载也不能播错章。
   */
  static remapEntries(entries: AudioOfflineEntry[], chapterUrls: string[], chapterTitles: string[]): Map<number, number> {
    const urlPositions = AudioOfflinePolicy.uniquePositions(chapterUrls);
    const titlePositions = AudioOfflinePolicy.uniquePositions(chapterTitles);
    const result = new Map<number, number>();
    const place = (target: number | undefined, entry: AudioOfflineEntry): boolean => {
      if (target === undefined || result.has(target)) return false;
      result.set(target, entry.chapterIndex);
      return true;
    };
    for (const entry of entries) {
      const index = entry.chapterIndex;
      if (index < chapterUrls.length &&
        AudioOfflinePolicy.entryMatches(entry, chapterUrls[index] || '', chapterTitles[index] || '') && place(index, entry)) {
        continue;
      }
      if (entry.chapterUrl && place(urlPositions.get(entry.chapterUrl), entry)) continue;
      if (entry.chapterTitle) place(titlePositions.get(entry.chapterTitle), entry);
    }
    return result;
  }

  /** 值 → 唯一出现的位置；出现多次的值不收录。 */
  private static uniquePositions(values: string[]): Map<string, number> {
    const positions = new Map<string, number>();
    const duplicated = new Set<string>();
    values.forEach((value: string, index: number): void => {
      if (!value || duplicated.has(value)) return;
      if (positions.has(value)) {
        positions.delete(value);
        duplicated.add(value);
      } else {
        positions.set(value, index);
      }
    });
    return positions;
  }

  static resolveUrl(reference: string, base: string): string {
    const value = (reference || '').trim();
    if (/^[a-z][a-z0-9+.-]*:/i.test(value)) return value;
    const baseMatch = (base || '').match(/^([a-z][a-z0-9+.-]*:)\/\/([^/?#]*)([^?#]*)/i);
    if (!baseMatch) return value;
    const scheme = baseMatch[1];
    const host = baseMatch[2];
    if (value.startsWith('//')) return `${scheme}${value}`;
    let path = '';
    let query = '';
    const queryIndex = value.search(/[?#]/);
    const pathPart = queryIndex >= 0 ? value.substring(0, queryIndex) : value;
    query = queryIndex >= 0 ? value.substring(queryIndex) : '';
    if (pathPart.startsWith('/')) {
      path = pathPart;
    } else {
      const baseDir = baseMatch[3].substring(0, baseMatch[3].lastIndexOf('/') + 1) || '/';
      path = baseDir + pathPart;
    }
    const output: string[] = [];
    for (const part of path.split('/')) {
      if (part === '..') output.pop();
      else if (part !== '.') output.push(part);
    }
    let normalized = output.join('/');
    if (!normalized.startsWith('/')) normalized = `/${normalized}`;
    if ((pathPart.endsWith('/.') || pathPart.endsWith('/..')) && !normalized.endsWith('/')) normalized += '/';
    return `${scheme}//${host}${normalized}${query}`;
  }

  private static attribute(line: string, name: string): string {
    const pattern = new RegExp(`(?:^|[:,])${name}=("([^"]*)"|[^,]*)`, 'i');
    const match = line.match(pattern);
    if (!match) return '';
    return match[2] !== undefined ? match[2] : match[1];
  }
}
