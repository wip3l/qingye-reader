import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { HttpClient, HttpRequest, digestHashHex, TlsTrustStore, HttpDigestChallenge, HttpAuth } from '@legado/sourceengine';
import { AppCookies } from '../platform/Cookies';
import {
  OpdsEntry,
  OpdsFeed,
  OpdsLink,
  OpdsSearchTemplate,
  OpdsServerConfig
} from './OpdsModels';
import { OpdsXmlParser } from './OpdsXmlParser';
import { OpdsError } from './OpdsError';
import { OpdsKavita } from './OpdsKavita';
import { streamReadTimeout } from '../platform/HttpTimeouts';

export interface OpdsDownloadHandle {
  promise: Promise<void>;
  cancel(): void;
}

export interface OpdsCatalogRoot {
  url: string;
  feed: OpdsFeed;
}

interface OpdsWireResponse {
  statusCode: number;
  headers: Record<string, string>;
}

interface OpdsStreamResult extends OpdsWireResponse {
  received: number;
  total: number;
  writeError: string;
}

// 同一书库在会话内协商出的认证方式；页面和下载各自 new 的 OpdsClient 共用，避免每次重新试探。
class OpdsAuthState {
  scheme: string = '';
  digest: HttpDigestChallenge | null = null;
  nonceCount: number = 0;
  verified: boolean = false;
}

export class OpdsClient {
  private static readonly MAX_REDIRECTS: number = 5;
  private static readonly MAX_FEED_BYTES: number = 10 * 1024 * 1024;
  private static readonly authStates: Map<string, OpdsAuthState> = new Map();
  private readonly server: OpdsServerConfig;
  private readonly password: string;
  private readonly timeout: number;
  private readonly httpClient: HttpClient;

  constructor(server: OpdsServerConfig, password: string) {
    this.server = server;
    this.password = password || '';
    this.timeout = 30000;
    this.httpClient = new HttpClient(this.timeout);
  }

  async fetchFeed(url: string): Promise<OpdsFeed> {
    const body = await this.fetchAtom(url);
    try {
      return OpdsXmlParser.parseFeed(body, url);
    } catch (error) {
      throw new OpdsError('not-opds', `OPDS 目录解析失败：${OpdsError.message(error as Object)}`);
    }
  }

  // 书库入口：按用户填的地址连不上时，依次换尾斜杠写法、补 /opds 再试，返回实际可用的地址。
  async fetchCatalog(url: string): Promise<OpdsCatalogRoot> {
    const candidates = OpdsClient.catalogCandidates(url);
    let first: Error | null = null;
    let budget = candidates.length;
    for (let index = 0; index < candidates.length && index < budget; index++) {
      try {
        const feed = await this.fetchFeed(candidates[index]);
        return { url: candidates[index], feed: feed };
      } catch (error) {
        if (!first) {
          first = error as Error;
          budget = 1 + OpdsClient.extraAddressBudget(error as Object, candidates.length - 1);
        }
      }
    }
    const viaKavita = await this.fetchKavitaCatalog(url, first as Error);
    if (viaKavita) return viaKavita;
    throw first as Error;
  }

  // Kavita 的 OPDS 只认地址里的密钥。填的是网页地址，或已存的密钥失效（被轮换）时，
  // 用账号密码登录取回密钥、拼出 OPDS 地址。不适用时返回 null，由调用方抛出原错误。
  private async fetchKavitaCatalog(url: string, failure: Error): Promise<OpdsCatalogRoot | null> {
    if (!(failure instanceof OpdsError)) return null;
    let sites: string[] = [];
    if (failure.serverKind === 'kavita') {
      sites = OpdsKavita.siteCandidates(url);
    } else if (failure.code === 'auth' && OpdsKavita.isOpdsUrl(url)) {
      sites = [OpdsKavita.siteOfOpdsUrl(url)];
    }
    if (sites.length === 0 || !this.server.username || !this.password) return null;
    let loginFailure: OpdsError | null = null;
    for (const site of sites) {
      let key = '';
      try {
        key = await this.kavitaLogin(site);
      } catch (error) {
        // 路径不对时 Kavita 会回网页而不是报错，所以以最后一个候选（站点根）的结果为准
        loginFailure = error as OpdsError;
        if (loginFailure.code === 'auth') break;
        continue;
      }
      const catalogUrl = OpdsKavita.opdsUrl(site, key);
      const feed = await this.fetchFeed(catalogUrl);
      return { url: catalogUrl, feed: feed };
    }
    throw (loginFailure || failure) as Error;
  }

  private async kavitaLogin(site: string): Promise<string> {
    const response = await this.httpClient.execute({
      url: OpdsKavita.loginUrl(site),
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: OpdsKavita.loginBody(this.server.username, this.password),
      useCookieJar: false,
      maxResponseBytes: 1024 * 1024
    });
    if (response.statusCode === 401 || response.statusCode === 403) {
      throw new OpdsError('auth', 'Kavita 登录失败：用户名或密码错误，或该账号被禁止登录', response.statusCode);
    }
    if (!response.success) {
      throw new OpdsError('network', response.statusCode > 0 ?
        `Kavita 登录失败（HTTP ${response.statusCode}）` : (response.error || 'Kavita 登录失败：网络连接失败'),
        response.statusCode);
    }
    const key = OpdsKavita.keyFromLoginResponse(response.body || '');
    if (!key) {
      throw new OpdsError('not-opds', 'Kavita 登录成功，但没有取到 OPDS 密钥。请确认服务器已开启 OPDS，' +
        '或在 Kavita 网页端的用户设置里复制 OPDS 地址');
    }
    return key;
  }

  // 首个地址失败后还值得再试几个地址。服务器有响应但地址不对：全部试完；
  // 连接层失败（如 /opds 被重定向到丢了端口的地址）：只再试一个，免得主机不通时干等；
  // 认证、证书、超时：换地址也没用。
  private static extraAddressBudget(error: Object, remaining: number): number {
    if (!(error instanceof OpdsError)) return 0;
    // Kavita 对任何未知路径都回同一个网页，换地址没有意义。
    if (error.serverKind === 'kavita') return 0;
    if (error.code === 'not-opds' || error.code === 'not-found') return remaining;
    if (error.code !== 'network') return 0;
    if (error.httpStatus > 0) return remaining;
    return /2300028|timed?\s*out|timeout/i.test(error.userMessage) ? 0 : Math.min(1, remaining);
  }

  static catalogCandidates(url: string): string[] {
    const value = (url || '').trim();
    const candidates: string[] = [value];
    if (!/^https?:\/\//i.test(value) || value.indexOf('?') >= 0 || value.indexOf('#') >= 0) return candidates;
    const trimmed = value.replace(/\/+$/, '');
    const add = (candidate: string): void => {
      if (candidates.indexOf(candidate) < 0) candidates.push(candidate);
    };
    // 站点根地址带不带斜杠是同一个资源，不必重复请求。
    if (!/^https?:\/\/[^/]+$/i.test(trimmed)) add(value.endsWith('/') ? trimmed : `${trimmed}/`);
    if (!/\/opds$/i.test(trimmed)) {
      add(`${trimmed}/opds/`);
      add(`${trimmed}/opds`);
    }
    return candidates;
  }

  async fetchEntry(url: string): Promise<OpdsEntry> {
    const body = await this.fetchAtom(url);
    try {
      return OpdsXmlParser.parseEntry(body, url);
    } catch (error) {
      throw new OpdsError('not-opds', `OPDS 条目解析失败：${OpdsError.message(error as Object)}`);
    }
  }

  async search(template: OpdsSearchTemplate, query: string): Promise<OpdsFeed> {
    const url = OpdsClient.searchUrlFromTemplate(template, query);
    console.info('[OPDS] 搜索请求:', this.hostForLog(url));
    return await this.fetchFeed(url);
  }

  static searchUrlFromTemplate(template: OpdsSearchTemplate, query: string): string {
    const indexOffset = Math.floor(template.indexOffset || 1);
    const pageOffset = Math.floor(template.pageOffset || 1);
    let url = OpdsClient.replaceOpenSearchPlaceholder(template.urlTemplate || '', 'searchTerms',
      encodeURIComponent(query));
    url = OpdsClient.replaceOpenSearchPlaceholder(url, 'startIndex', `${indexOffset}`);
    url = OpdsClient.replaceOpenSearchPlaceholder(url, 'startPage', `${pageOffset}`);
    url = OpdsClient.replaceOpenSearchPlaceholder(url, 'page', `${pageOffset}`);
    url = OpdsClient.replaceOpenSearchPlaceholder(url, 'count', '');
    url = OpdsClient.replaceOpenSearchPlaceholder(url, 'searchRel', '');
    // 其余可选参数（{language?} 等）按规范留空。
    return url.replace(/\{[A-Za-z][A-Za-z0-9:]*\?\}/g, '');
  }

  async resolveSearchTemplate(feedUrl: string, feed: OpdsFeed): Promise<OpdsSearchTemplate | null> {
    let description: OpdsLink | null = null;
    let inline: OpdsLink | null = null;
    for (const link of feed.links) {
      if ((link.rel || '').trim().toLowerCase() !== 'search' || !link.href) continue;
      if (link.href.indexOf('{searchTerms') >= 0) {
        if (!inline) inline = link;
      } else if (!description) {
        description = link;
      }
    }
    if (description) {
      try {
        const descriptionUrl = OpdsXmlParser.resolveUrl(description.href, feedUrl);
        const body = await this.fetchXml(descriptionUrl);
        const template = OpdsXmlParser.parseSearchTemplate(body);
        if (template && template.urlTemplate) {
          template.urlTemplate = OpdsXmlParser.resolveUrl(template.urlTemplate, descriptionUrl);
          return template;
        }
      } catch (_) {
      }
    }
    // Calibre 内容服务器不提供 OpenSearch 描述文档，rel=search 的 href 本身就是搜索模板。
    if (inline) {
      const template = new OpdsSearchTemplate();
      template.urlTemplate = OpdsXmlParser.resolveUrl(inline.href, feedUrl);
      return template;
    }
    return null;
  }

  // 需要带凭据才能取到的资源（如开启登录的 Calibre 封面）；无凭据或跨主机时返回 false。
  usesCredentialsFor(url: string): boolean {
    // Kavita 的密钥就在地址里，账号密码只用于登录换密钥，不随请求发送。
    if (OpdsKavita.isOpdsUrl(url) || OpdsKavita.isOpdsUrl(this.server.baseUrl)) return false;
    return !!this.server.username && this.sameHost(url);
  }

  async fetchBinary(url: string, maxBytes: number): Promise<Uint8Array> {
    const response = await this.sendAuthorized(url, async (authorization: string) => {
      const request: HttpRequest = {
        url: url,
        method: 'GET',
        headers: { 'Accept': 'image/*,*/*;q=0.8' }
      };
      if (authorization) request.headers['Authorization'] = authorization;
      return await this.httpClient.executeBinary(request, maxBytes);
    });
    if (!response.success) {
      throw new OpdsError('network', response.error || `书库请求失败（HTTP ${response.statusCode}）`);
    }
    return response.data;
  }

  downloadBook(url: string, destPath: string,
    onProgress?: (received: number, total: number) => void): OpdsDownloadHandle {
    let cancelled = false;
    let active: http.HttpRequest | null = null;
    let rejectRef: (error: OpdsError) => void = (error: OpdsError): void => {};
    const run = async (): Promise<void> => {
      if (fs.accessSync(destPath)) fs.unlinkSync(destPath);
      this.ensureParent(destPath);
      const target = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      let keepFile = false;
      try {
        const result = await this.sendAuthorized(url, async (authorization: string) => {
          if (cancelled) throw new OpdsError('cancelled', '已取消');
          return await this.streamToFile(url, authorization, target.fd, onProgress,
            (client: http.HttpRequest | null): void => {
              active = client;
            });
        });
        if (result.writeError) throw new OpdsError('unknown', result.writeError);
        if (result.statusCode === 401 || result.statusCode === 403) {
          throw new OpdsError('auth', `书库拒绝下载（HTTP ${result.statusCode}），请检查账号、密码和下载权限`);
        }
        if (result.statusCode < 200 || result.statusCode >= 300) {
          throw new OpdsError('network', `书库下载失败（HTTP ${result.statusCode}）`);
        }
        // 压缩传输时 Content-Length 是压缩后的长度，与落盘字节数不可比。
        const encoded = !!this.headerValue(result.headers, 'content-encoding');
        if (!encoded && result.total > 0 && result.received !== result.total) {
          throw new OpdsError('network', '下载文件长度不完整');
        }
        keepFile = true;
      } catch (error) {
        throw error instanceof OpdsError ? error : this.toDownloadError(url, error as Object);
      } finally {
        try { fs.closeSync(target); } catch (_) {}
        if (!keepFile) {
          try { fs.unlinkSync(destPath); } catch (_) {}
        }
      }
    };
    const promise = new Promise<void>((resolve, reject): void => {
      rejectRef = reject;
      run().then(resolve, (error: Object): void => {
        if (!cancelled) reject(error);
      });
    });
    const handle: OpdsDownloadHandle = {
      promise: promise,
      cancel: (): void => {
        if (cancelled) return;
        cancelled = true;
        const client = active as http.HttpRequest | null;
        if (client) {
          try { client.destroy(); } catch (_) {}
        }
        rejectRef(new OpdsError('cancelled', '已取消'));
      }
    };
    return handle;
  }

  // 单次流式下载；认证重试时会被再次调用，所以每次都从文件头重写。
  private async streamToFile(url: string, authorization: string, fd: number,
    onProgress: ((received: number, total: number) => void) | undefined,
    track: (client: http.HttpRequest | null) => void): Promise<OpdsStreamResult> {
    const result: OpdsStreamResult = { statusCode: 0, headers: {}, received: 0, total: 0, writeError: '' };
    fs.truncateSync(fd, 0);
    const client = http.createHttp();
    track(client);
    const onHeaders = (value: Object): void => {
      result.headers = (value || {}) as Record<string, string>;
      result.total = Math.max(0, Number(this.headerValue(result.headers, 'content-length')) || 0);
      if (onProgress) onProgress(0, result.total);
    };
    const onData = (chunk: ArrayBuffer): void => {
      if (result.writeError) return;
      try {
        const count = fs.writeSync(fd, chunk, { offset: result.received });
        if (count !== chunk.byteLength) throw new Error('写入下载缓存不完整');
        result.received += count;
        if (onProgress) onProgress(result.received, result.total);
      } catch (error) {
        result.writeError = OpdsError.message(error as Object, '写入下载缓存失败');
        try { client.destroy(); } catch (_) {}
      }
    };
    client.on('headersReceive', onHeaders);
    client.on('dataReceive', onData);
    try {
      result.statusCode = await client.requestInStream(url, this.buildDownloadOptions(url, authorization));
    } catch (error) {
      if (!result.writeError) throw error as Error;
    } finally {
      track(null);
      try { client.off('headersReceive', onHeaders); } catch (_) {}
      try { client.off('dataReceive', onData); } catch (_) {}
      try { client.destroy(); } catch (_) {}
    }
    return result;
  }

  private async fetchAtom(url: string): Promise<string> {
    const body = await this.fetchXml(url);
    const head = body.substring(0, 4096);
    if (!/<(?:[A-Za-z_][\w.-]*:)?(?:feed|entry)[\s>]/.test(head)) {
      if (/<title>\s*Kavita/i.test(head)) {
        const kavita = new OpdsError('not-opds', '这是 Kavita 的网页地址，不是 OPDS 地址。请在书库设置里打开「需要登录」' +
          '并填写 Kavita 的账号密码，应用会自动获取 OPDS 地址；也可以在 Kavita 网页端的用户设置里复制 OPDS 地址直接填入');
        kavita.serverKind = 'kavita';
        throw kavita;
      }
      throw new OpdsError('not-opds', '该地址不是有效的 OPDS 目录。Calibre、talebook 的地址一般以 /opds 结尾');
    }
    return body;
  }

  private async fetchXml(url: string): Promise<string> {
    const response = await this.sendAuthorized(url, async (authorization: string) => {
      const request: HttpRequest = {
        url: url,
        method: 'GET',
        headers: {
          'Accept': 'application/atom+xml;profile=opds-catalog, application/atom+xml;q=0.9, ' +
            'application/xml;q=0.8, */*;q=0.5'
        },
        maxResponseBytes: OpdsClient.MAX_FEED_BYTES
      };
      if (authorization) request.headers['Authorization'] = authorization;
      return await this.httpClient.execute(request);
    });
    if (response.statusCode === 401 || response.statusCode === 403) {
      throw new OpdsError('auth', this.server.username ? '用户名或密码错误' : '书库需要登录，请在书库设置里填写账号和密码');
    }
    if (response.statusCode === 404) {
      throw new OpdsError('not-found', '书库地址不存在（404）', 404);
    }
    if (!response.success) {
      const detail = response.error || '';
      if (response.statusCode === 0) {
        // 有的服务器发完分块响应后直接断开连接，系统网络栈会报错但正文其实已收全。
        if (OpdsClient.isCompleteDocument(response.body || '')) return response.body;
        if (detail.indexOf('证书校验失败') >= 0) {
          throw new OpdsError('certificate', detail);
        }
        throw new OpdsError('network', detail || '网络连接失败');
      }
      throw new OpdsError('network', `书库请求失败（HTTP ${response.statusCode}）`, response.statusCode);
    }
    return response.body || '';
  }

  private static isCompleteDocument(body: string): boolean {
    const tail = body.substring(Math.max(0, body.length - 256));
    return /<\/(?:[A-Za-z_][\w.-]*:)?(?:feed|entry|OpenSearchDescription)\s*>\s*$/.test(tail);
  }

  // 认证协商：先按 Basic 发；服务器要求 Digest 时（Calibre 内容服务器在非 HTTPS 下的默认方式）改用 Digest 重发。
  // Calibre 在 Digest 模式下收到 Basic 头会直接回 400 且不带质询，所以还要裸请求一次去取质询。
  private async sendAuthorized<T extends OpdsWireResponse>(url: string,
    send: (authorization: string) => Promise<T>): Promise<T> {
    if (!this.usesCredentialsFor(url)) return await send('');
    const state = this.authState();
    const wasDigest = state.scheme === 'digest';
    let response = await send(this.authorization(state, url));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (!state.scheme) state.scheme = 'basic';
      state.verified = true;
      return response;
    }
    if (response.statusCode !== 401 && (wasDigest || response.statusCode !== 400)) return response;
    let header = this.headerValue(response.headers, 'www-authenticate');
    if (!wasDigest && (response.statusCode === 400 || !header)) {
      const probe = await send('');
      if (probe.statusCode >= 200 && probe.statusCode < 300) return probe;
      if (probe.statusCode !== 401) return response;
      header = this.headerValue(probe.headers, 'www-authenticate');
    }
    const challenge = HttpAuth.digestChallenge(header);
    if (!challenge) return response;
    // 已经用 Digest 发过且被拒：只有 nonce 过期或此前验证通过过才重试，
    // 否则就是密码不对，重试只会白白累加服务器的失败计数（Calibre 会封禁来源地址）。
    const retry = !wasDigest || challenge.stale || state.verified;
    state.scheme = 'digest';
    state.digest = challenge;
    state.nonceCount = 0;
    state.verified = false;
    if (!retry) return response;
    response = await send(this.authorization(state, url));
    if (response.statusCode >= 200 && response.statusCode < 300) state.verified = true;
    return response;
  }

  private authState(): OpdsAuthState {
    const key = `${this.server.id}|${this.server.username}`;
    let state = OpdsClient.authStates.get(key);
    if (!state) {
      state = new OpdsAuthState();
      OpdsClient.authStates.set(key, state);
    }
    return state;
  }

  private authorization(state: OpdsAuthState, url: string): string {
    if (state.scheme === 'digest' && state.digest) {
      state.nonceCount++;
      const cnonce = util.generateRandomUUID(true).replace(/-/g, '').substring(0, 16);
      return HttpAuth.digestAuthorization(state.digest, this.server.username, this.password, 'GET', url,
        state.nonceCount, cnonce, digestHashHex);
    }
    const authorization = new util.Base64Helper().encodeToStringSync(
      new util.TextEncoder().encodeInto(`${this.server.username}:${this.password}`));
    return `Basic ${authorization}`;
  }

  // 凭据只发给书库所在主机：目录里的外链（封面 CDN、第三方下载地址）不该拿到账号密码。
  private sameHost(url: string): boolean {
    const host = this.hostOf(url);
    return !!host && host === this.hostOf(this.server.baseUrl);
  }

  private hostOf(url: string): string {
    const match = (url || '').match(/^https?:\/\/(?:[^/?#@]*@)?(\[[^\]]*\]|[^/:?#]*)/i);
    return match && match[1] ? match[1].toLowerCase() : '';
  }

  private buildDownloadOptions(url: string, authorization: string): http.HttpRequestOptions {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: this.downloadHeaders(url, authorization),
      connectTimeout: this.timeout,
      readTimeout: streamReadTimeout(Math.max(this.timeout, 120000), 30 * 60 * 1000),
      maxRedirects: OpdsClient.MAX_REDIRECTS
    };
    this.applyTlsTrust(options, url);
    return options;
  }

  private downloadHeaders(url: string, authorization: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': '*/*',
      'User-Agent': 'LegadoHarmony-OPDS/1.0'
    };
    if (authorization) headers['Authorization'] = authorization;
    const cookie = AppCookies.getCookie(url);
    if (cookie) headers['Cookie'] = cookie;
    return headers;
  }

  private toDownloadError(url: string, error: Object): OpdsError {
    const message = OpdsError.message(error, '未知网络错误');
    if (TlsTrustStore.isCertificateError(message)) {
      return new OpdsError('certificate', this.decorateTlsError(url, message));
    }
    return new OpdsError('network', message);
  }

  private decorateTlsError(url: string, error: string): string {
    if (!TlsTrustStore.isCertificateError(error) || /证书主机\s*[：:]/.test(error || '')) return error;
    const host = TlsTrustStore.hostFromUrl(url);
    return host ? `证书校验失败（证书主机：${host}）：${error}` : error;
  }

  private applyTlsTrust(options: http.HttpRequestOptions, url: string): void {
    if (TlsTrustStore.isTrustedUrl(url)) {
      options.remoteValidation = 'skip';
    }
  }

  // OpenSearch 模板参数有必填 {name} 和可选 {name?} 两种写法。
  private static replaceOpenSearchPlaceholder(url: string, name: string, value: string): string {
    return url.split(`{${name}}`).join(value).split(`{${name}?}`).join(value);
  }

  private headerValue(headers: Record<string, string>, name: string): string {
    const target = name.toLowerCase();
    for (const key of Object.keys(headers || {})) {
      if (key.toLowerCase() === target) return String(headers[key] || '');
    }
    return '';
  }

  private ensureParent(path: string): void {
    const normalized = path.replace(/\\/g, '/');
    const index = normalized.lastIndexOf('/');
    if (index <= 0) return;
    const parent = normalized.substring(0, index);
    if (!fs.accessSync(parent)) fs.mkdirSync(parent, true);
  }

  private hostForLog(url: string): string {
    const match = (url || '').match(/^https?:\/\/([^/:?#]+)/i);
    return match && match[1] ? match[1] : '(unknown host)';
  }
}
