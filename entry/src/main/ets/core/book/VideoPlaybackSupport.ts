/** 视频专用解析结果，不能把媒体头带到网页域。 */
export class VideoPlaybackSource {
  url: string = '';
  pageUrl: string = '';
  headers: Record<string, string> = {};
  error: string = '';
}

export class VideoPlaybackSupport {
  static httpUrl(raw: string): string {
    const value = (raw || '').trim();
    return /^https?:\/\/[^\s/?#@]+(?:[/?#][^\s]*)?$/i.test(value) && !/[\r\n\\]/.test(value) ? value : '';
  }

  /** 只用明确的媒体规格错误码，不把无效资源、网络、权限错误当作编码问题。 */
  static unsupported(code: number): boolean {
    return code === 5400106;
  }

  static failureText(code: number): string {
    if (VideoPlaybackSupport.unsupported(code)) return '当前播放器不支持此视频规格';
    if (code === 5411005) return '视频访问被拒绝，请检查登录状态或书源权限';
    if (code === 5411002 || code === 5400104) return '播放超时，请检查网络后重试';
    return code > 0 ? `播放失败（错误码 ${code}）` : '播放失败，请重试';
  }

  static position(value: number): number {
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }
}
