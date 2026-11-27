import { PluginManifest } from '../spec/PluginManifest';

export interface PluginHttpRequest {
  url: string;
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'HEAD';
  headers?: Record<string, string>;
  body?: string | Object | null;
  bodyBytes?: Uint8Array;
  responseType?: 'text' | 'bytes';
  timeoutMs?: number;
  /**
   * false：宿主不得自动跟随重定向，须把 3xx（含 Location 头）原样返回，由引擎逐跳核对。
   * 平台做不到时可以照常跟随，但要在 finalUrl 里如实报告最终地址；无法观测时留空。
   */
  followRedirects?: boolean;
}

export interface PluginHttpResponse {
  status: number;
  headers: Record<string, string>;
  text: string;
  bytes?: Uint8Array;
  finalUrl: string;
}

export interface PluginAesOptions {
  mode: 'CBC' | 'ECB' | 'CTR';
  padding?: 'PKCS7' | 'NoPadding';
  keyHex?: string;
  keyBase64?: string;
  keyUtf8?: string;
  ivHex?: string;
  ivBase64?: string;
  ivUtf8?: string;
}

export interface PluginBookContext {
  bookUrl: string;
  name: string;
  author: string;
  origin: string;
  chapterIndex: number;
  chapterTitle: string;
}

export interface PluginAnnotationItem {
  id: string;
  chapterIndex: number;
  chapterTitle: string;
  selectedText: string;
  noteText: string;
  color: string;
  createdAt: number;
}

export interface PluginPanelOpenSpec {
  pluginId: string;
  title: string;
  panelPath: string;
  initialData?: Object | null;
  handler?: string;
}

export interface PluginVerifyWebSpec {
  url: string;
  title?: string;
  waitForSelector?: string;
  callbackUrlPrefix?: string;
}

export type PluginSourceRouteTarget =
  | 'BookSource'
  | 'SearchExploreSettings'
  | 'LegadoBackupImport'
  | 'WebParseNotice';

export interface PluginSourceSummary {
  totalSources: number;
  enabledSources: number;
  nativeSources: number;
  compatSources: number;
  pluginSources: number;
  groupCount: number;
  onlineBooks: number;
}

export interface PluginEngineHostPort {
  pluginsRootDir(): string;
  tempRootDir(): string;
  platformName(): 'harmonyos' | 'node';
  isDarkMode(): boolean;
  /** 本机是否已确认《在线内容扩展使用须知》，用于放行 requiresWebParseGate(manifest) 的已启用插件。 */
  isWebParseEnabled(): boolean;

  // File & archive operations for installer and sandboxed plugin fs
  readFileBytes(absPath: string): Promise<Uint8Array>;
  readFileText(absPath: string): Promise<string>;
  writeFileBytes(absPath: string, data: Uint8Array): Promise<void>;
  writeFileText(absPath: string, text: string): Promise<void>;
  listDir(absPath: string): Promise<string[]>;
  exists(absPath: string): Promise<boolean>;
  mkdirs(absPath: string): Promise<void>;
  removePath(absPath: string): Promise<void>;
  renamePath(fromAbsPath: string, toAbsPath: string): Promise<void>;
  extractZip(zipAbsPath: string, destDirAbsPath: string): Promise<void>;
  sha256Hex(data: Uint8Array): Promise<string>;
  /** 用 SPKI DER 公钥校验 Ed25519 签名；平台不支持时不实现，带签名的安装包会被拒绝。 */
  verifyEd25519?(publicKeySpki: Uint8Array, data: Uint8Array, signature: Uint8Array): Promise<boolean>;

  // Persistence for registry, per-plugin config, kv, and encrypted secrets
  loadRegistryJson(): Promise<string>;
  saveRegistryJson(rawJson: string): Promise<void>;
  loadPluginKvJson(pluginId: string): Promise<string>;
  savePluginKvJson(pluginId: string, rawJson: string): Promise<void>;
  getSecret(pluginId: string, key: string): Promise<string>;
  setSecret(pluginId: string, key: string, value: string): Promise<void>;
  clearPluginSecrets(pluginId: string): Promise<void>;

  // Host capabilities exposed to plugins
  httpRequest(pluginId: string, req: PluginHttpRequest): Promise<PluginHttpResponse>;
  /** 解析域名的全部 IP，供引擎拦截“公网域名指向内网”；不提供时只做字面量检查。 */
  resolveHostAddresses?(host: string): Promise<string[]>;
  cssSelect(html: string, rule: string, all: boolean): Promise<string | string[]>;
  xpathSelect(html: string, expr: string): Promise<string[]>;
  jsonPathSelect(jsonText: string, expr: string): Promise<Object | null>;
  regexTransform(text: string, pattern: string, replacement: string | null): Promise<string | string[]>;
  digestHex(algorithm: string, data: Uint8Array): Promise<string>;
  hmacHex(algorithm: string, key: Uint8Array, data: Uint8Array): Promise<string>;
  aesEncrypt(options: PluginAesOptions, plain: Uint8Array): Promise<Uint8Array>;
  aesDecrypt(options: PluginAesOptions, cipher: Uint8Array): Promise<Uint8Array>;
  base64Encode(data: Uint8Array): string;
  base64Decode(b64: string): Uint8Array;

  // Reader & UI hooks
  getActiveBookContext(): Promise<PluginBookContext | null>;
  getBookAnnotations(chapterIndex: number): Promise<PluginAnnotationItem[]>;
  addBookAnnotation(spec: Record<string, Object | null>): Promise<boolean>;
  showToast(pluginName: string, message: string): void;
  openPluginPanel(spec: PluginPanelOpenSpec): Promise<void>;
  postMessageToOpenPanel(pluginId: string, data: Object | null): void;
  emitSearchBatch(pluginId: string, items: Record<string, Object | null>[]): void;
  registerSearchEmitSink?(pluginId: string, fn: (pluginId: string, items: Record<string, Object | null>[]) => void): () => void;
  openVerifyWeb(pluginId: string, spec: PluginVerifyWebSpec): Promise<string>;

  // Shadow book source lifecycle sync for contentSource plugins
  syncShadowBookSource(manifest: PluginManifest, enabled: boolean): Promise<void>;
  removeShadowBookSource(pluginId: string): Promise<void>;

  // Online reading & book source manager bridge hooks (optional for test mocks)
  getSourceSummary?(): Promise<PluginSourceSummary>;
  openSourceRoute?(target: PluginSourceRouteTarget): Promise<boolean>;
}

export class PluginEngineHost {
  private static installedPort: PluginEngineHostPort | null = null;

  static install(port: PluginEngineHostPort): void {
    PluginEngineHost.installedPort = port;
  }

  static isInstalled(): boolean {
    return PluginEngineHost.installedPort !== null;
  }

  static port(): PluginEngineHostPort {
    if (!PluginEngineHost.installedPort) {
      throw new Error('PluginEngineHostPort 尚未初始化');
    }
    return PluginEngineHost.installedPort;
  }
}
