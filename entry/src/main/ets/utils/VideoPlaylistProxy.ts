import { socket } from '@kit.NetworkKit';
import http from '@ohos.net.http';
import { util } from '@kit.ArkTS';
import { VideoPlaylistMode } from '../core/book/VideoPlaybackSupport';
import { VideoPlaylistSupport } from '../core/book/VideoPlaylistSupport';

/** 一次播放用到的代理地址；播放列表地址按出现顺序编号，地址里不带源站信息。 */
export class VideoPlaylistSession {
  readonly token: string;
  readonly headers: Record<string, string>;
  readonly lowLatency: boolean;
  entryUrl: string = '';
  /** 最近一次取播放列表失败的原因，播放出错时显示给用户。 */
  lastError: string = '';
  playlistCount: number = 0;
  private ids: Map<string, string> = new Map();
  private urls: Map<string, string> = new Map();
  private sequence: number = 0;

  constructor(token: string, headers: Record<string, string>, lowLatency: boolean) {
    this.token = token;
    this.headers = headers;
    this.lowLatency = lowLatency;
  }

  idFor(url: string): string {
    const known = this.ids.get(url);
    if (known) return known;
    const id = String(++this.sequence);
    this.ids.set(url, id);
    this.urls.set(id, url);
    // 直播的子播放列表地址可能每次都带新签名：只留最近的一批，旧编号失效后播放器拿到的新列表里已是新编号。
    if (this.urls.size > MAX_PLAYLIST_IDS) {
      const oldest = this.urls.keys().next().value as string;
      const oldUrl = this.urls.get(oldest) || '';
      this.urls.delete(oldest);
      this.ids.delete(oldUrl);
    }
    return id;
  }

  urlFor(id: string): string {
    return this.urls.get(id) || '';
  }
}

const MAX_PLAYLIST_IDS: number = 256;
const MAX_CONNECTIONS: number = 16;
const REQUEST_HEAD_LIMIT: number = 16 * 1024;
const REQUEST_TIMEOUT_MS: number = 15000;
const UPSTREAM_TIMEOUT_MS: number = 15000;
/** 最后一次播放结束后多久关掉端口；换集时马上又会用到，不必反复开关。 */
const IDLE_STOP_MS: number = 60000;
const LOG_FIRST: number = 3;
const LOG_EVERY: number = 20;

/**
 * 书源写了 content.playlist 的视频：播放器向应用在 127.0.0.1 开的小服务取 HLS 播放列表，
 * 应用带上书源请求头向源站取回、按书源要求处理并把地址补全后交回。分片、密钥等媒体数据仍由播放器直接向源站下载，
 * 走系统自己的下载器——实测接管全部请求（MediaSourceLoader）时，系统缓冲满会偶尔丢掉分片，这里不再经手媒体数据。
 * 只监听本机地址，路径里带每次播放随机生成的口令，别的应用拿不到书源请求头。
 */
export class VideoPlaylistProxy {
  private static instance: VideoPlaylistProxy | null = null;
  private server: socket.TCPSocketServer | null = null;
  private port: number = 0;
  private starting: Promise<boolean> | null = null;
  private sessions: Map<string, VideoPlaylistSession> = new Map();
  private connections: Map<number, socket.TCPSocketConnection> = new Map();
  private idleTimer: number = -1;

  static shared(): VideoPlaylistProxy {
    if (!VideoPlaylistProxy.instance) VideoPlaylistProxy.instance = new VideoPlaylistProxy();
    return VideoPlaylistProxy.instance;
  }

  /** 开不了本机端口（安卓版等）时返回 null，调用方照常直接播放原地址。 */
  async open(url: string, headers: Record<string, string>, mode: VideoPlaylistMode): Promise<VideoPlaylistSession | null> {
    if (this.idleTimer >= 0) {
      clearTimeout(this.idleTimer);
      this.idleTimer = -1;
    }
    if (!(await this.ensureServer())) return null;
    const token = util.generateRandomUUID(false).replace(/-/g, '');
    const session = new VideoPlaylistSession(token, headers, mode.lowLatency);
    session.entryUrl = this.proxyUrl(session, session.idFor(url));
    this.sessions.set(token, session);
    return session;
  }

  close(session: VideoPlaylistSession): void {
    if (!this.sessions.delete(session.token)) return;
    console.info(`[VideoPlaylistProxy] session closed playlists=${session.playlistCount}`);
    if (this.sessions.size > 0 || this.idleTimer >= 0) return;
    this.idleTimer = setTimeout((): void => {
      this.idleTimer = -1;
      if (this.sessions.size === 0) this.stopServer();
    }, IDLE_STOP_MS);
  }

  private proxyUrl(session: VideoPlaylistSession, id: string): string {
    return `http://127.0.0.1:${this.port}/${session.token}/${id}.m3u8`;
  }

  private ensureServer(): Promise<boolean> {
    if (this.server) return Promise.resolve(true);
    if (this.starting) return this.starting;
    this.starting = this.startServer().finally((): void => {
      this.starting = null;
    });
    return this.starting;
  }

  private async startServer(): Promise<boolean> {
    for (let attempt = 0; attempt < 5; attempt++) {
      const port = 20000 + Math.floor(Math.random() * 40000);
      const server = socket.constructTCPSocketServerInstance();
      try {
        await server.listen({ address: '127.0.0.1', family: 1, port: port });
        // 要在 listen 成功之后注册 connect，否则端口在监听但连接到不了回调（同 LanReaderServer）。
        server.on('connect', (client: socket.TCPSocketConnection): void => this.accept(client));
        server.on('error', (error: Error): void => console.warn('[VideoPlaylistProxy] socket error', error.message));
        this.server = server;
        this.port = port;
        console.info(`[VideoPlaylistProxy] listening on 127.0.0.1:${port}`);
        return true;
      } catch (error) {
        console.warn(`[VideoPlaylistProxy] listen ${port} failed: ${(error as Error).message}`);
        try {
          await server.close();
        } catch (_) {
        }
      }
    }
    return false;
  }

  private stopServer(): void {
    const server = this.server;
    this.server = null;
    this.port = 0;
    this.connections.forEach((client: socket.TCPSocketConnection): void => {
      client.close().catch((): void => {});
    });
    this.connections.clear();
    if (server) server.close().catch((): void => {});
    console.info('[VideoPlaylistProxy] stopped');
  }

  private accept(client: socket.TCPSocketConnection): void {
    if (this.connections.size >= MAX_CONNECTIONS) {
      client.close().catch((): void => {});
      return;
    }
    const id = client.clientId;
    this.connections.set(id, client);
    let head = '';
    let handled = false;
    const timer = setTimeout((): void => {
      if (!handled) client.close().catch((): void => {});
    }, REQUEST_TIMEOUT_MS);
    const cleanup = (): void => {
      clearTimeout(timer);
      this.connections.delete(id);
    };
    client.on('message', (info: socket.SocketMessageInfo): void => {
      if (handled) return;
      head += util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(info.message));
      if (head.length > REQUEST_HEAD_LIMIT) {
        handled = true;
        client.close().catch((): void => {});
        return;
      }
      const end = head.indexOf('\r\n\r\n');
      if (end < 0) return;
      handled = true;
      clearTimeout(timer);
      this.handle(client, head.substring(0, end)).catch((error: Error): void => {
        console.warn('[VideoPlaylistProxy] request failed', error.message);
        client.close().catch((): void => {});
      });
    });
    client.on('close', cleanup);
    client.on('error', cleanup);
  }

  private async handle(client: socket.TCPSocketConnection, head: string): Promise<void> {
    const parts = (head.split('\r\n')[0] || '').split(' ');
    const method = (parts[0] || '').toUpperCase();
    if (method !== 'GET' && method !== 'HEAD') {
      await this.respond(client, 405, null, method === 'HEAD');
      return;
    }
    const target = parts[1] || '';
    const match = target.match(/^\/([0-9a-f]{32})\/(\d+)\.m3u8(?:\?(.*))?$/i);
    const session = match ? this.sessions.get(match[1].toLowerCase()) : undefined;
    const upstreamBase = session && match ? session.urlFor(match[2]) : '';
    if (!session || !match || !upstreamBase) {
      await this.respond(client, 404, null, method === 'HEAD');
      return;
    }
    // LL-HLS 的阻塞刷新参数（_HLS_msn 等）是播放器加在代理地址上的，原样带给源站。
    const query = match[3] || '';
    const upstream = query ? `${upstreamBase}${upstreamBase.includes('?') ? '&' : '?'}${query}` : upstreamBase;
    const started = Date.now();
    const result = await this.fetchPlaylist(session, upstream);
    if (!result) {
      await this.respond(client, 502, null, method === 'HEAD');
      return;
    }
    // 相对地址按请求的源站地址补全；源站重定向到别的目录时，系统网络接口拿不到最终地址，这种站点需要书源给绝对地址。
    const rewritten = VideoPlaylistSupport.rewrite(result, upstreamBase, session.lowLatency, {
      playlist: (url: string): string => this.proxyUrl(session, session.idFor(url)),
      media: (url: string): string => url
    });
    session.playlistCount++;
    const count = session.playlistCount;
    if (count <= LOG_FIRST || count % LOG_EVERY === 0) {
      console.info(`[VideoPlaylistProxy] playlist #${count} ${rewritten.length}ch ${Date.now() - started}ms ` +
        `${VideoPlaylistProxy.shortUrl(upstreamBase)}`);
    }
    const bytes = new util.TextEncoder().encodeInto(rewritten);
    await this.respond(client, 200, bytes, method === 'HEAD');
  }

  private async fetchPlaylist(session: VideoPlaylistSession, url: string): Promise<string | null> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: session.headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: UPSTREAM_TIMEOUT_MS,
        readTimeout: UPSTREAM_TIMEOUT_MS,
        usingCache: false
      });
      const status = response.responseCode;
      if (status < 200 || status >= 300) {
        this.fail(session, `取播放列表失败（HTTP ${status}）`, url);
        return null;
      }
      const data = response.result as ArrayBuffer;
      if (!data || data.byteLength === 0) {
        this.fail(session, '播放列表是空的', url);
        return null;
      }
      if (data.byteLength > VideoPlaylistSupport.MAX_PLAYLIST_BYTES) {
        this.fail(session, '播放列表超过 2 MB', url);
        return null;
      }
      const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(data));
      if (!VideoPlaylistSupport.looksLikePlaylist(text)) {
        // 多半是登录页、风控页或者地址不是 HLS：交给播放器只会报“格式不支持”。
        this.fail(session, '返回的不是 HLS 播放列表', url);
        return null;
      }
      return text;
    } catch (error) {
      const message = error && (error as Error).message ? (error as Error).message : '网络错误';
      this.fail(session, `取播放列表失败：${message}`, url);
      return null;
    } finally {
      request.destroy();
    }
  }

  private fail(session: VideoPlaylistSession, reason: string, url: string): void {
    session.lastError = reason;
    console.warn(`[VideoPlaylistProxy] ${reason} ${VideoPlaylistProxy.shortUrl(url)}`);
  }

  private async respond(client: socket.TCPSocketConnection, status: number, body: Uint8Array | null,
    headOnly: boolean): Promise<void> {
    const reason = status === 200 ? 'OK' : (status === 404 ? 'Not Found' : (status === 405 ? 'Method Not Allowed' :
      'Bad Gateway'));
    const length = body ? body.byteLength : 0;
    const header = `HTTP/1.1 ${status} ${reason}\r\n` +
      (body ? 'Content-Type: application/vnd.apple.mpegurl\r\n' : '') +
      `Content-Length: ${length}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n`;
    try {
      await client.send({ data: header, encoding: 'UTF-8' });
      if (body && length > 0 && !headOnly) {
        await client.send({ data: body.buffer.slice(body.byteOffset, body.byteOffset + length) as ArrayBuffer });
      }
    } finally {
      client.close().catch((): void => {});
    }
  }

  /** 日志里不写查询参数，里面常有签名和令牌。 */
  private static shortUrl(url: string): string {
    const plain = (url || '').replace(/[?#].*$/, '');
    return plain.length > 96 ? `…${plain.substring(plain.length - 95)}` : plain;
  }
}
