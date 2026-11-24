import { AudioOfflinePolicy } from './AudioOfflinePolicy';

/** 播放列表里一个地址指向的是另一份播放列表（多码率、音轨、字幕）还是媒体数据（分片、密钥、初始化段）。 */
export interface PlaylistUriMapper {
  playlist: (absoluteUrl: string) => string;
  media: (absoluteUrl: string) => string;
}

/**
 * 视频书源写了 content.playlist 时，播放列表经应用内的本机代理（VideoPlaylistProxy）取回、处理后再交给播放器。
 * 这里是其中不依赖系统接口的部分：判断响应是不是 HLS 播放列表、改写地址、按 lowLatency 关掉 LL-HLS 的分片预告。
 */
export class VideoPlaylistSupport {
  /** 播放列表要整段读完才能改写；超过这个大小按出错处理，免得把视频文件当播放列表读进内存。 */
  static readonly MAX_PLAYLIST_BYTES: number = 2 * 1024 * 1024;

  /** 指向另一份播放列表的标签；其余带 URI 的标签（KEY、MAP、PART、PRELOAD-HINT 等）指向媒体数据。 */
  private static readonly PLAYLIST_TAGS: string[] = ['#EXT-X-MEDIA', '#EXT-X-I-FRAME-STREAM-INF', '#EXT-X-RENDITION-REPORT'];

  static withoutBom(text: string): string {
    return text && text.charCodeAt(0) === 0xFEFF ? text.substring(1) : (text || '');
  }

  /** 正文开头是否为 #EXTM3U。 */
  static looksLikePlaylist(text: string): boolean {
    return VideoPlaylistSupport.withoutBom(text).trimStart().startsWith('#EXTM3U');
  }

  /**
   * 去掉 LL-HLS 专用的标签，播放器就按普通 HLS 只取完整分片、普通间隔刷新。
   * SERVER-CONTROL 一并去掉：它声明的 CAN-BLOCK-RELOAD 会让播放器发阻塞式刷新（_HLS_msn）。
   */
  static stripLowLatency(text: string): string {
    const lines = text.split(/\r?\n/);
    const kept = lines.filter((line: string): boolean => !/^#EXT-X-(?:PART|PART-INF|PRELOAD-HINT|RENDITION-REPORT|SERVER-CONTROL)(?::|$)/
      .test(line.trim()));
    return kept.join('\n');
  }

  /**
   * 播放列表由本机代理转交，播放器会按代理地址补全相对地址，所以每个地址都要先按源站地址补全，再交给 mapper：
   * 子播放列表仍指回代理（以后改写脚本要处理到它们），分片、密钥等媒体数据直接指向源站，由播放器自己下载。
   * data:、skd: 之类非 http 地址原样保留。
   */
  static rewrite(text: string, baseUrl: string, lowLatency: boolean, mapper: PlaylistUriMapper): string {
    const clean = VideoPlaylistSupport.withoutBom(text);
    const source = lowLatency ? clean : VideoPlaylistSupport.stripLowLatency(clean);
    const map = (reference: string, playlist: boolean): string => {
      const absolute = AudioOfflinePolicy.resolveUrl(reference, baseUrl);
      if (!/^https?:\/\//i.test(absolute)) return reference;
      return playlist ? mapper.playlist(absolute) : mapper.media(absolute);
    };
    let nextIsPlaylist = false;
    const out: string[] = [];
    for (const raw of source.split(/\r?\n/)) {
      const line = raw.trim();
      if (!line) {
        out.push(raw);
        continue;
      }
      if (line.startsWith('#')) {
        if (line.startsWith('#EXT-X-STREAM-INF')) nextIsPlaylist = true;
        const tag = line.split(':')[0];
        const playlistTag = VideoPlaylistSupport.PLAYLIST_TAGS.includes(tag);
        out.push(raw.replace(/URI="([^"]*)"/g, (_whole: string, uri: string): string => `URI="${map(uri, playlistTag)}"`));
        continue;
      }
      const isPlaylist = nextIsPlaylist || /\.m3u8(?:[?#]|$)/i.test(line);
      nextIsPlaylist = false;
      out.push(map(line, isPlaylist));
    }
    return out.join('\n');
  }
}
