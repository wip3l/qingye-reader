import {
  isIpLiteralHost,
  isPrivateIpAddress,
  isPrivateOrLoopbackHost,
  matchesDomainAllowlist,
  splitHostPort,
  normalizeSafePluginRelPath,
  PluginManifest,
  PluginPermission,
  requiresWebParseGate
} from '../spec/PluginManifest';
import {
  PluginAesOptions,
  PluginEngineHostPort,
  PluginHttpRequest,
  PluginHttpResponse,
  PluginSourceRouteTarget
} from './PluginHostPort';

export interface PluginLogEntry {
  timestamp: number;
  level: 'info' | 'warn' | 'error';
  message: string;
}

export interface PluginNetworkTrace {
  timestamp: number;
  method: string;
  url: string;
  status: number;
  durationMs: number;
  error?: string;
}

export interface HostCallResult {
  metaJson: string;
  bytes?: Uint8Array;
}

const METHOD_REQUIRED_PERMISSION: ReadonlyMap<string, PluginPermission> = new Map<string, PluginPermission>([
  ['secrets.get', 'secrets'],
  ['secrets.set', 'secrets'],
  ['kv.get', 'storage'],
  ['kv.set', 'storage'],
  ['kv.delete', 'storage'],
  ['kv.keys', 'storage'],
  ['fs.writeText', 'storage'],
  ['fs.writeBytes', 'storage'],
  ['fs.remove', 'storage'],
  ['http.request', 'network'],
  ['reader.getBookContext', 'bookshelf.read'],
  ['reader.getAnnotations', 'annotations.read'],
  ['reader.addAnnotation', 'annotations.write'],
  ['ui.verifyWeb', 'webview.verify'],
  ['source.getSummary', 'source.manage'],
  ['source.openRoute', 'source.manage']
]);

interface ParsedPluginUrl {
  scheme: string;
  hostPort: string;
  path: string;
  query: string;
}

/**
 * 只认 http(s)，并拒绝各网络栈解析可能不一致的写法：地址里的反斜杠、空白与控制字符、
 * 以及 `user:pass@host` 形式的凭据（凭据请放在请求头里）。
 */
function parsePluginUrl(rawUrl: string): ParsedPluginUrl {
  const urlText = rawUrl.trim();
  if (/[\s\\\u0000-\u001f\u007f]/.test(urlText)) {
    throw new Error('请求地址包含空白、反斜杠或控制字符');
  }
  const m = /^(https?):\/\/([^/?#]*)([^?#]*)(\?[^#]*)?/i.exec(urlText);
  if (!m) {
    throw new Error('仅允许发起 http:// 或 https:// 请求');
  }
  const authority = m[2];
  if (!authority) {
    throw new Error('请求地址缺少主机名');
  }
  if (authority.includes('@')) {
    throw new Error('请求地址不能内嵌用户名或密码，请改用请求头传递凭据');
  }
  return { scheme: m[1].toLowerCase(), hostPort: authority, path: m[3] || '/', query: m[4] || '' };
}

function parseUrlHost(rawUrl: string): { scheme: string; hostPort: string } {
  const parsed = parsePluginUrl(rawUrl);
  return { scheme: parsed.scheme, hostPort: parsed.hostPort };
}

function urlOrigin(rawUrl: string): string {
  const parsed = parsePluginUrl(rawUrl);
  const hp = splitHostPort(parsed.hostPort);
  const defaultPort = parsed.scheme === 'https' ? '443' : '80';
  return `${parsed.scheme}://${hp.host}:${hp.port || defaultPort}`;
}

function removeDotSegments(path: string): string {
  const out: string[] = [];
  const segments = path.split('/');
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i];
    if (seg === '.') {
      if (i === segments.length - 1) out.push('');
      continue;
    }
    if (seg === '..') {
      if (out.length > 1) out.pop();
      if (i === segments.length - 1) out.push('');
      continue;
    }
    out.push(seg);
  }
  const joined = out.join('/');
  return joined.startsWith('/') ? joined : `/${joined}`;
}

/** 把 Location 头按请求地址解析成绝对地址；协议与主机是否允许由调用方再核对。 */
export function resolveRedirectLocation(baseUrl: string, location: string): string {
  const loc = location.trim();
  if (!loc) throw new Error('重定向缺少目标地址');
  if (/^[a-z][a-z0-9+.-]*:/i.test(loc)) return loc;
  const base = parsePluginUrl(baseUrl);
  const prefix = `${base.scheme}://${base.hostPort}`;
  if (loc.startsWith('//')) return `${base.scheme}:${loc}`;
  const hashIdx = loc.indexOf('#');
  const noHash = hashIdx >= 0 ? loc.slice(0, hashIdx) : loc;
  if (!noHash) return `${prefix}${base.path}${base.query}`;
  if (noHash.startsWith('?')) return `${prefix}${base.path}${noHash}`;
  const qIdx = noHash.indexOf('?');
  const relPath = qIdx >= 0 ? noHash.slice(0, qIdx) : noHash;
  const relQuery = qIdx >= 0 ? noHash.slice(qIdx) : '';
  const merged = relPath.startsWith('/')
    ? relPath
    : `${base.path.slice(0, base.path.lastIndexOf('/') + 1) || '/'}${relPath}`;
  return `${prefix}${removeDotSegments(merged)}${relQuery}`;
}

/** 单个地址的白名单与局域网字面量检查；http.request 的每一跳都要过一遍。 */
export function assertPluginUrlPermitted(manifest: PluginManifest, rawUrl: string): void {
  const parsed = parseUrlHost(rawUrl);
  if (!matchesDomainAllowlist(parsed.hostPort, manifest.domains)) {
    throw new Error(`目标主机 "${parsed.hostPort}" 不在插件声明的 domains 白名单内`);
  }
  if (isPrivateOrLoopbackHost(parsed.hostPort) && !manifest.permissions.includes('network.lan')) {
    throw new Error(`禁止访问局域网或本机回环地址 "${parsed.hostPort}"（需声明 network.lan 权限）`);
  }
}

export function sanitizeUrlForTrace(rawUrl: string): string {
  const qIdx = rawUrl.indexOf('?');
  if (qIdx < 0) return rawUrl;
  return `${rawUrl.slice(0, qIdx)}?[REDACTED_QUERY]`;
}

export function assertPluginCallPermitted(
  manifest: PluginManifest,
  method: string,
  meta: Record<string, unknown>,
  webParseEnabled: boolean
): void {
  if (requiresWebParseGate(manifest) && !webParseEnabled) {
    throw new Error('该插件涉及在线网页内容解析，请先在插件管理中确认使用须知并启用对应插件');
  }

  const requiredPerm = METHOD_REQUIRED_PERMISSION.get(method);
  if (requiredPerm && !manifest.permissions.includes(requiredPerm)) {
    throw new Error(`插件 "${manifest.name}" 未声明权限 "${requiredPerm}"，已拦截调用 ${method}`);
  }

  if (method === 'fs.readText' || method === 'fs.readBytes' || method === 'fs.list') {
    const rel = normalizeSafePluginRelPath(String(meta['path'] || 'assets'));
    const inAssets = rel === 'assets' || rel.startsWith('assets/');
    const inData = rel === 'data' || rel.startsWith('data/');
    if (!inAssets && !inData) {
      throw new Error('插件文件读取仅限于 assets/ 或 data/ 目录');
    }
    if (inData && !manifest.permissions.includes('storage')) {
      throw new Error(`读取 data/ 目录需要声明 "storage" 权限`);
    }
  }

  if (method === 'fs.writeText' || method === 'fs.writeBytes' || method === 'fs.remove') {
    const rel = normalizeSafePluginRelPath(String(meta['path'] || ''));
    if (!rel.startsWith('data/') || rel === 'data') {
      throw new Error('插件仅允许在私有 data/ 目录下写入或删除文件');
    }
  }

  if (method === 'http.request' || method === 'ui.verifyWeb') {
    assertPluginUrlPermitted(manifest, String(meta['url'] || ''));
  }
}

const REDIRECT_STATUSES: ReadonlySet<number> = new Set<number>([301, 302, 303, 307, 308]);
const CROSS_ORIGIN_STRIPPED_HEADERS: ReadonlySet<string> = new Set<string>([
  'authorization',
  'cookie',
  'proxy-authorization'
]);

function headerValue(headers: Record<string, string> | undefined, name: string): string {
  if (!headers) return '';
  const lower = name.toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === lower) {
      const val: unknown = headers[key];
      if (Array.isArray(val)) return val.length > 0 ? String(val[0]) : '';
      return val === undefined || val === null ? '' : String(val);
    }
  }
  return '';
}

interface DnsVerdict {
  blockedAddress: string;
  expiresAt: number;
}

function utf8Bytes(str: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < str.length; i++) {
    let c = str.charCodeAt(i);
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
      const c2 = str.charCodeAt(++i);
      const cp = 0x10000 + (((c & 0x3ff) << 10) | (c2 & 0x3ff));
      out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
    } else {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(out);
}

export class PluginHostDispatcher {
  private readonly port: PluginEngineHostPort;
  private readonly getConfigMap: (pluginId: string) => Record<string, string | number | boolean>;
  private readonly setConfigValue: (pluginId: string, key: string, value: unknown) => Promise<void>;
  private readonly kvCache: Map<string, Record<string, unknown>> = new Map();
  private readonly logs: Map<string, PluginLogEntry[]> = new Map();
  private readonly traces: Map<string, PluginNetworkTrace[]> = new Map();
  private readonly dnsVerdicts: Map<string, DnsVerdict> = new Map();

  private static readonly MAX_REDIRECTS: number = 5;
  private static readonly DNS_VERDICT_TTL_MS: number = 60000;
  private static readonly MAX_DNS_VERDICTS: number = 256;
  private static readonly MAX_LOGS_PER_PLUGIN: number = 200;
  private static readonly MAX_TRACES_PER_PLUGIN: number = 80;
  private static readonly MAX_KV_JSON_BYTES: number = 8 * 1024 * 1024;

  constructor(
    port: PluginEngineHostPort,
    getConfigMap: (pluginId: string) => Record<string, string | number | boolean>,
    setConfigValue: (pluginId: string, key: string, value: unknown) => Promise<void>
  ) {
    this.port = port;
    this.getConfigMap = getConfigMap;
    this.setConfigValue = setConfigValue;
  }

  getLogs(pluginId: string): PluginLogEntry[] {
    return (this.logs.get(pluginId) || []).slice();
  }

  clearLogs(pluginId: string): void {
    this.logs.delete(pluginId);
    this.traces.delete(pluginId);
  }

  getNetworkTraces(pluginId: string): PluginNetworkTrace[] {
    return (this.traces.get(pluginId) || []).slice();
  }

  appendLog(pluginId: string, level: 'info' | 'warn' | 'error', message: string): void {
    const list = this.logs.get(pluginId) || [];
    const redacted = message.replace(/(bearer\s+|token=|password=|apikey=|secret=)[^\s&"']+/gi, '$1[REDACTED]');
    list.push({ timestamp: Date.now(), level, message: redacted.slice(0, 2000) });
    while (list.length > PluginHostDispatcher.MAX_LOGS_PER_PLUGIN) list.shift();
    this.logs.set(pluginId, list);
  }

  private appendTrace(pluginId: string, trace: PluginNetworkTrace): void {
    const list = this.traces.get(pluginId) || [];
    list.push(trace);
    while (list.length > PluginHostDispatcher.MAX_TRACES_PER_PLUGIN) list.shift();
    this.traces.set(pluginId, list);
  }

  private async ensureKv(pluginId: string): Promise<Record<string, unknown>> {
    const existing = this.kvCache.get(pluginId);
    if (existing) return existing;
    const raw = await this.port.loadPluginKvJson(pluginId);
    let parsed: Record<string, unknown> = {};
    if (raw) {
      try {
        const obj: unknown = JSON.parse(raw);
        if (typeof obj === 'object' && obj !== null && !Array.isArray(obj)) {
          parsed = obj as Record<string, unknown>;
        }
      } catch (_) {
        parsed = {};
      }
    }
    this.kvCache.set(pluginId, parsed);
    return parsed;
  }

  private async flushKv(pluginId: string, store: Record<string, unknown>): Promise<void> {
    const serialized = JSON.stringify(store);
    if (serialized.length > PluginHostDispatcher.MAX_KV_JSON_BYTES) {
      throw new Error('插件 KV 存储超过 8 MiB 配额上限');
    }
    await this.port.savePluginKvJson(pluginId, serialized);
  }

  /**
   * 引擎自己逐跳跟随重定向，每一跳都重新核对白名单、局域网字面量与 DNS 解析结果。
   * 宿主做不到停在 3xx 时（老系统）会自己跟到底，这时用它报告的 finalUrl 事后核对，不合规就丢弃响应。
   */
  private async performHttpRequest(manifest: PluginManifest, initial: PluginHttpRequest): Promise<PluginHttpResponse> {
    let req: PluginHttpRequest = initial;
    const visited: Set<string> = new Set();
    for (let hop = 0; ; hop++) {
      if (hop > 0) assertPluginUrlPermitted(manifest, req.url);
      await this.assertResolvedHostPermitted(manifest, req.url);
      visited.add(req.url);

      const t0 = Date.now();
      let resp: PluginHttpResponse;
      try {
        resp = await this.port.httpRequest(manifest.id, req);
      } catch (err) {
        this.appendTrace(manifest.id, {
          timestamp: t0,
          method: req.method || 'GET',
          url: sanitizeUrlForTrace(req.url),
          status: 0,
          durationMs: Date.now() - t0,
          error: err instanceof Error ? err.message : String(err)
        });
        throw err;
      }
      this.appendTrace(manifest.id, {
        timestamp: t0,
        method: req.method || 'GET',
        url: sanitizeUrlForTrace(req.url),
        status: resp.status,
        durationMs: Date.now() - t0
      });

      const location = REDIRECT_STATUSES.has(resp.status) ? headerValue(resp.headers, 'location') : '';
      if (!location) {
        if (resp.finalUrl && resp.finalUrl !== req.url) {
          try {
            assertPluginUrlPermitted(manifest, resp.finalUrl);
            await this.assertResolvedHostPermitted(manifest, resp.finalUrl);
          } catch (err) {
            const reason = err instanceof Error ? err.message : String(err);
            throw new Error(`请求被重定向到不允许的地址，已丢弃响应：${reason}`);
          }
        }
        return resp;
      }

      if (hop >= PluginHostDispatcher.MAX_REDIRECTS) {
        throw new Error(`重定向超过 ${PluginHostDispatcher.MAX_REDIRECTS} 次，已停止`);
      }
      const nextUrl = resolveRedirectLocation(req.url, location);
      if (visited.has(nextUrl)) {
        throw new Error('检测到重定向循环，已停止');
      }

      const method = req.method || 'GET';
      const switchToGet = (resp.status === 303 && method !== 'HEAD') ||
        ((resp.status === 301 || resp.status === 302) && method === 'POST');
      const crossOrigin = urlOrigin(nextUrl) !== urlOrigin(req.url);
      let headers: Record<string, string> | undefined = req.headers;
      if (headers && (crossOrigin || switchToGet)) {
        const kept: Record<string, string> = {};
        for (const key of Object.keys(headers)) {
          const lower = key.toLowerCase();
          if (crossOrigin && CROSS_ORIGIN_STRIPPED_HEADERS.has(lower)) continue;
          if (switchToGet && lower === 'content-type') continue;
          kept[key] = headers[key];
        }
        headers = kept;
      }
      req = {
        ...req,
        url: nextUrl,
        method: switchToGet ? 'GET' : req.method,
        headers,
        body: switchToGet ? undefined : req.body,
        bodyBytes: switchToGet ? undefined : req.bodyBytes
      };
    }
  }

  /**
   * 域名白名单管不住“公网域名解析到内网地址”。没有 network.lan 的插件在发请求前先解析一次，
   * 任何一个地址落在本机或局域网就拦截。结果缓存一分钟；解析失败交给真正的请求去报错。
   * 解析与连接之间仍有时间差（DNS 重绑定），这里挡的是静态配置与大多数重绑定尝试。
   */
  private async assertResolvedHostPermitted(manifest: PluginManifest, rawUrl: string): Promise<void> {
    if (manifest.permissions.includes('network.lan') || !this.port.resolveHostAddresses) return;
    const host = splitHostPort(parseUrlHost(rawUrl).hostPort).host;
    if (!host || isIpLiteralHost(host)) return;

    const now = Date.now();
    let verdict = this.dnsVerdicts.get(host);
    if (!verdict || verdict.expiresAt <= now) {
      let addresses: string[] = [];
      try {
        addresses = await this.port.resolveHostAddresses(host);
      } catch (_) {
        return;
      }
      const blocked = addresses.find((addr) => isPrivateIpAddress(addr)) || '';
      verdict = { blockedAddress: blocked, expiresAt: now + PluginHostDispatcher.DNS_VERDICT_TTL_MS };
      if (this.dnsVerdicts.size >= PluginHostDispatcher.MAX_DNS_VERDICTS) {
        const oldest = this.dnsVerdicts.keys().next();
        if (!oldest.done) this.dnsVerdicts.delete(oldest.value);
      }
      this.dnsVerdicts.set(host, verdict);
    }
    if (verdict.blockedAddress) {
      throw new Error(`目标主机 "${host}" 解析到局域网或本机地址 ${verdict.blockedAddress}（需声明 network.lan 权限）`);
    }
  }

  private resolvePluginPath(pluginDir: string, relRaw: string): string {
    const cleanRel = normalizeSafePluginRelPath(relRaw);
    return `${pluginDir}/${cleanRel}`;
  }

  async dispatch(
    manifest: PluginManifest,
    pluginDir: string,
    method: string,
    metaJson: string,
    bytes?: Uint8Array
  ): Promise<HostCallResult> {
    const meta: Record<string, unknown> = metaJson ? (JSON.parse(metaJson) as Record<string, unknown>) : {};
    assertPluginCallPermitted(manifest, method, meta, this.port.isWebParseEnabled());

    switch (method) {
      case 'env.info':
        return {
          metaJson: JSON.stringify({
            pluginId: manifest.id,
            version: manifest.version,
            platform: this.port.platformName(),
            darkMode: this.port.isDarkMode(),
            locale: 'zh-CN'
          })
        };

      case 'config.get': {
        const cfg = this.getConfigMap(manifest.id);
        const key = String(meta['key'] || '');
        return { metaJson: JSON.stringify(key ? (cfg[key] ?? null) : cfg) };
      }

      case 'config.set': {
        const key = String(meta['key'] || '');
        if (!key) throw new Error('config.set 缺少 key');
        await this.setConfigValue(manifest.id, key, meta['value']);
        return { metaJson: 'true' };
      }

      case 'secrets.get': {
        const val = await this.port.getSecret(manifest.id, String(meta['key'] || ''));
        return { metaJson: JSON.stringify(val) };
      }

      case 'secrets.set': {
        await this.port.setSecret(manifest.id, String(meta['key'] || ''), String(meta['value'] ?? ''));
        return { metaJson: 'true' };
      }

      case 'kv.get': {
        const store = await this.ensureKv(manifest.id);
        const k = String(meta['key'] || '');
        return { metaJson: JSON.stringify(store[k] !== undefined ? store[k] : null) };
      }

      case 'kv.set': {
        const store = await this.ensureKv(manifest.id);
        const k = String(meta['key'] || '');
        store[k] = meta['value'];
        await this.flushKv(manifest.id, store);
        return { metaJson: 'true' };
      }

      case 'kv.delete': {
        const store = await this.ensureKv(manifest.id);
        delete store[String(meta['key'] || '')];
        await this.flushKv(manifest.id, store);
        return { metaJson: 'true' };
      }

      case 'kv.keys': {
        const store = await this.ensureKv(manifest.id);
        return { metaJson: JSON.stringify(Object.keys(store)) };
      }

      case 'fs.readText': {
        const target = this.resolvePluginPath(pluginDir, String(meta['path'] || ''));
        const text = await this.port.readFileText(target);
        return { metaJson: JSON.stringify(text) };
      }

      case 'fs.readBytes': {
        const target = this.resolvePluginPath(pluginDir, String(meta['path'] || ''));
        const rawBytes = await this.port.readFileBytes(target);
        return { metaJson: 'null', bytes: rawBytes };
      }

      case 'fs.writeText': {
        const target = this.resolvePluginPath(pluginDir, String(meta['path'] || ''));
        const slash = target.lastIndexOf('/');
        if (slash > 0) await this.port.mkdirs(target.slice(0, slash));
        await this.port.writeFileText(target, String(meta['text'] ?? ''));
        return { metaJson: 'true' };
      }

      case 'fs.writeBytes': {
        const target = this.resolvePluginPath(pluginDir, String(meta['path'] || ''));
        const slash = target.lastIndexOf('/');
        if (slash > 0) await this.port.mkdirs(target.slice(0, slash));
        await this.port.writeFileBytes(target, bytes || new Uint8Array(0));
        return { metaJson: 'true' };
      }

      case 'fs.list': {
        const rel = String(meta['path'] || 'assets');
        const target = this.resolvePluginPath(pluginDir, rel);
        if (!(await this.port.exists(target))) return { metaJson: '[]' };
        const names = await this.port.listDir(target);
        return { metaJson: JSON.stringify(names) };
      }

      case 'fs.remove': {
        const target = this.resolvePluginPath(pluginDir, String(meta['path'] || ''));
        await this.port.removePath(target);
        return { metaJson: 'true' };
      }

      case 'http.request': {
        const req: PluginHttpRequest = {
          url: String(meta['url'] || ''),
          method: (String(meta['method'] || 'GET').toUpperCase()) as PluginHttpRequest['method'],
          headers: (meta['headers'] && typeof meta['headers'] === 'object')
            ? (meta['headers'] as Record<string, string>)
            : undefined,
          body: meta['body'] as string | Record<string, unknown> | undefined,
          bodyBytes: bytes,
          responseType: meta['responseType'] === 'bytes' ? 'bytes' : 'text',
          timeoutMs: typeof meta['timeoutMs'] === 'number' ? meta['timeoutMs'] : 20000,
          followRedirects: false
        };
        const resp = await this.performHttpRequest(manifest, req);
        return {
          metaJson: JSON.stringify({
            status: resp.status,
            headers: resp.headers,
            text: resp.text,
            finalUrl: resp.finalUrl
          }),
          bytes: resp.bytes
        };
      }

      case 'parser.css': {
        const out = await this.port.cssSelect(String(meta['html'] || ''), String(meta['rule'] || ''), false);
        return { metaJson: JSON.stringify(out) };
      }

      case 'parser.cssAll': {
        const out = await this.port.cssSelect(String(meta['html'] || ''), String(meta['rule'] || ''), true);
        return { metaJson: JSON.stringify(out) };
      }

      case 'parser.xpath': {
        const out = await this.port.xpathSelect(String(meta['html'] || ''), String(meta['expr'] || ''));
        return { metaJson: JSON.stringify(out) };
      }

      case 'parser.jsonpath': {
        const out = await this.port.jsonPathSelect(String(meta['json'] || ''), String(meta['expr'] || ''));
        return { metaJson: JSON.stringify(out) };
      }

      case 'parser.regex': {
        const rep = meta['replacement'] === null || meta['replacement'] === undefined
          ? null
          : String(meta['replacement']);
        const out = await this.port.regexTransform(
          String(meta['text'] || ''),
          String(meta['pattern'] || ''),
          rep
        );
        return { metaJson: JSON.stringify(out) };
      }

      case 'crypto.hash': {
        const inputBytes = bytes ?? utf8Bytes(String(meta['text'] ?? ''));
        const hex = await this.port.digestHex(String(meta['algorithm'] || 'SHA256'), inputBytes);
        return { metaJson: JSON.stringify(hex) };
      }

      case 'crypto.hmac': {
        let keyBytes: Uint8Array;
        const keyBase64 = typeof meta['keyBase64'] === 'string' ? meta['keyBase64'].trim() : '';
        const keyHex = typeof meta['keyHex'] === 'string' ? meta['keyHex'].trim() : '';
        if (keyBase64) {
          keyBytes = this.port.base64Decode(keyBase64);
        } else if (keyHex) {
          const out = new Uint8Array(Math.floor(keyHex.length / 2));
          for (let i = 0; i < out.length; i++) {
            out[i] = parseInt(keyHex.slice(i * 2, i * 2 + 2), 16) || 0;
          }
          keyBytes = out;
        } else {
          keyBytes = utf8Bytes(String(meta['key'] ?? ''));
        }
        const inputBytes = bytes ?? utf8Bytes(String(meta['text'] ?? ''));
        const hex = await this.port.hmacHex(String(meta['algorithm'] || 'SHA256'), keyBytes, inputBytes);
        return { metaJson: JSON.stringify(hex) };
      }

      case 'crypto.aesEncrypt': {
        const encrypted = await this.port.aesEncrypt(meta as unknown as PluginAesOptions, bytes || new Uint8Array(0));
        return { metaJson: 'null', bytes: encrypted };
      }

      case 'crypto.aesDecrypt': {
        const decrypted = await this.port.aesDecrypt(meta as unknown as PluginAesOptions, bytes || new Uint8Array(0));
        return { metaJson: 'null', bytes: decrypted };
      }

      case 'crypto.base64Encode': {
        const inputBytes = bytes ?? utf8Bytes(String(meta['text'] ?? ''));
        return { metaJson: JSON.stringify(this.port.base64Encode(inputBytes)) };
      }

      case 'crypto.base64Decode': {
        const decoded = this.port.base64Decode(String(meta['text'] || ''));
        return { metaJson: 'null', bytes: decoded };
      }

      case 'reader.getBookContext': {
        const ctx = await this.port.getActiveBookContext();
        return { metaJson: JSON.stringify(ctx) };
      }

      case 'reader.getAnnotations': {
        const idx = typeof meta['chapterIndex'] === 'number' ? meta['chapterIndex'] : -1;
        const list = await this.port.getBookAnnotations(idx);
        return { metaJson: JSON.stringify(list) };
      }

      case 'reader.addAnnotation': {
        const added = await this.port.addBookAnnotation(meta);
        return { metaJson: JSON.stringify(added) };
      }

      case 'ui.toast': {
        this.port.showToast(manifest.name, String(meta['message'] || ''));
        return { metaJson: 'true' };
      }

      case 'ui.openPanel': {
        const panelRel = normalizeSafePluginRelPath(String(meta['panel'] || ''));
        await this.port.openPluginPanel({
          pluginId: manifest.id,
          title: String(meta['title'] || manifest.name),
          panelPath: panelRel,
          initialData: meta['data'],
          handler: meta['handler'] ? String(meta['handler']) : undefined
        });
        return { metaJson: 'true' };
      }

      case 'ui.postPanelMessage': {
        this.port.postMessageToOpenPanel(manifest.id, meta['data']);
        return { metaJson: 'true' };
      }

      case 'ui.emitSearch': {
        const items = Array.isArray(meta['items']) ? (meta['items'] as Record<string, unknown>[]) : [];
        this.port.emitSearchBatch(manifest.id, items);
        return { metaJson: 'true' };
      }

      case 'ui.verifyWeb': {
        const rawPrefix = typeof meta['callbackUrlPrefix'] === 'string' ? meta['callbackUrlPrefix'].trim() : '';
        if (rawPrefix && !/^(https?:\/\/|[a-z][a-z0-9+.-]*:\/\/)/i.test(rawPrefix)) {
          throw new Error('ui.verifyWeb 的 callbackUrlPrefix 必须是合法的 URL 前缀');
        }
        if (rawPrefix && /^(javascript|data|file|vbscript):/i.test(rawPrefix)) {
          throw new Error('ui.verifyWeb 禁止使用不安全的 callbackUrlPrefix 协议');
        }
        const body = await this.port.openVerifyWeb(manifest.id, {
          url: String(meta['url'] || ''),
          title: meta['title'] ? String(meta['title']) : manifest.name,
          waitForSelector: meta['waitForSelector'] ? String(meta['waitForSelector']) : undefined,
          callbackUrlPrefix: rawPrefix || undefined
        });
        return { metaJson: JSON.stringify(body) };
      }

      case 'log.write': {
        const lvlRaw = String(meta['level'] || 'info');
        const level: 'info' | 'warn' | 'error' =
          lvlRaw === 'error' ? 'error' : (lvlRaw === 'warn' ? 'warn' : 'info');
        this.appendLog(manifest.id, level, String(meta['message'] || ''));
        return { metaJson: 'true' };
      }

      case 'source.getSummary': {
        if (!this.port.getSourceSummary) {
          return {
            metaJson: JSON.stringify({
              totalSources: 0,
              enabledSources: 0,
              nativeSources: 0,
              compatSources: 0,
              pluginSources: 0,
              groupCount: 0,
              onlineBooks: 0
            })
          };
        }
        const summary = await this.port.getSourceSummary();
        return { metaJson: JSON.stringify(summary) };
      }

      case 'source.openRoute': {
        const targetRaw = String(meta['target'] || '').trim();
        if (
          targetRaw !== 'BookSource' &&
          targetRaw !== 'SearchExploreSettings' &&
          targetRaw !== 'LegadoBackupImport' &&
          targetRaw !== 'WebParseNotice'
        ) {
          throw new Error(`不支持的书源管理目标页面: ${targetRaw}`);
        }
        if (!this.port.openSourceRoute) {
          return { metaJson: 'false' };
        }
        const ok = await this.port.openSourceRoute(targetRaw as PluginSourceRouteTarget);
        return { metaJson: JSON.stringify(Boolean(ok)) };
      }

      default:
        throw new Error(`未知的宿主方法调用: ${method}`);
    }
  }
}
