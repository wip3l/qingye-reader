import { Context } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import connection from '@ohos.net.connection';
import preferences from '@ohos.data.preferences';
import zlib from '@ohos.zlib';
import {
  AnalyzeRule,
  BudgetedRegexReplace,
  digestHashHex,
  HttpClient,
  HttpRequest,
  JsonPathEvaluator,
  NativeSourceInteraction
} from '@legado/sourceengine';
import {
  buildPluginShadowSourceUrl,
  InstalledPluginRecord,
  PluginAesOptions,
  PluginAnnotationItem,
  PluginBookContext,
  PluginEngineHost,
  PluginEngineHostPort,
  PluginHttpRequest,
  PluginHttpResponse,
  PluginManifest,
  PluginPanelOpenSpec,
  PluginRegistry,
  PluginVerifyWebSpec
} from '@legado/pluginengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { BookAnnotation } from '../../model/reader/BookAnnotation';
import { ReadBookEngine } from '../book/ReadBookEngine';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { HuksSecretStore } from '../../utils/HuksSecretStore';
import { PluginFeatureStore } from '../../utils/PluginFeatureStore';
import { PluginTtsVoices } from './PluginTtsVoices';

export type PanelOpenListener = (spec: PluginPanelOpenSpec) => void;
export type PanelMessageListener = (data: Object | null) => void;
export type SearchEmitListener = (pluginId: string, items: Record<string, Object | null>[]) => void;

const REGISTRY_PREFS_NAME: string = 'qingye_plugin_registry_v1';
const KV_PREFS_PREFIX: string = 'qingye_plugin_kv_';
const SECRET_STORE_NAME: string = 'qingye_plugin_secrets_v1';
const SECRET_KEY_ALIAS: string = 'qingye_plugin_secret_master_v1';

/**
 * 插件引擎的宿主实现：文件、加密存储、网络、解析与加解密、网页登录等能力都经这里交给插件。
 * 本应用只接朗读音色（tts）和工具面板（tools）两类扩展点；在线书源类插件（contentSource）不接，
 * 影子书源的同步因此是空操作。整个插件功能受“实验室 › 插件”总开关管：关闭时不初始化、不运行插件。
 */
export class AppPluginHost implements PluginEngineHostPort {
  private static installedInstance: AppPluginHost | null = null;
  private static panelOpenListeners: Set<PanelOpenListener> = new Set();
  private static panelMsgListeners: Map<string, Set<PanelMessageListener>> = new Map();
  private static searchEmitListeners: Map<string, Set<SearchEmitListener>> = new Map();

  private readonly context: Context;
  private readonly secretStore: HuksSecretStore = new HuksSecretStore(SECRET_STORE_NAME, SECRET_KEY_ALIAS);
  private readonly httpClient: HttpClient = new HttpClient(20000);

  constructor(context: Context) {
    this.context = context;
  }

  /** 可重复调用：已装过就什么都不做。启动时开关开着、或之后第一次打开开关时调用。 */
  static install(context: Context): void {
    if (AppPluginHost.installedInstance) return;
    const appCtx = context.getApplicationContext();
    const host = new AppPluginHost(appCtx);
    AppPluginHost.installedInstance = host;
    PluginEngineHost.install(host);
    AppStorage.setOrCreate('pluginRegistryRevision', 1);
    PluginRegistry.getInstance().subscribe((rev: number) => {
      AppStorage.setOrCreate('pluginRegistryRevision', rev);
      // 实验室页只显示启用数，不为此加载插件引擎。
      AppStorage.setOrCreate('pluginEnabledCount',
        PluginRegistry.getInstance().listAll().filter((rec: InstalledPluginRecord): boolean => rec.enabled).length);
    });
    PluginTtsVoices.install();
    // 总开关打开（含冷启动读出已开启）时才读入已装插件。
    PluginFeatureStore.subscribe((enabled: boolean) => {
      if (enabled) AppPluginHost.initializeRegistry();
    });
    if (PluginFeatureStore.enabled()) AppPluginHost.initializeRegistry();
  }

  private static initializeRegistry(): void {
    PluginRegistry.getInstance().ensureInitialized().catch((err: Object) => {
      console.warn('[PluginHost] 初始化已安装插件失败:', err instanceof Error ? err.message : String(err));
    });
  }

  static subscribePanelOpen(fn: PanelOpenListener): () => void {
    AppPluginHost.panelOpenListeners.add(fn);
    return () => {
      AppPluginHost.panelOpenListeners.delete(fn);
    };
  }

  static subscribePanelMessages(pluginId: string, fn: PanelMessageListener): () => void {
    const set = AppPluginHost.panelMsgListeners.get(pluginId) || new Set<PanelMessageListener>();
    set.add(fn);
    AppPluginHost.panelMsgListeners.set(pluginId, set);
    return () => {
      const s = AppPluginHost.panelMsgListeners.get(pluginId);
      if (s) s.delete(fn);
    };
  }

  static registerSearchEmitSink(pluginId: string, fn: SearchEmitListener): () => void {
    const set = AppPluginHost.searchEmitListeners.get(pluginId) || new Set<SearchEmitListener>();
    set.add(fn);
    AppPluginHost.searchEmitListeners.set(pluginId, set);
    return () => {
      const current = AppPluginHost.searchEmitListeners.get(pluginId);
      if (current) {
        current.delete(fn);
        if (current.size === 0) {
          AppPluginHost.searchEmitListeners.delete(pluginId);
        }
      }
    };
  }

  static shadowBookSourceUrl(pluginId: string, sourceId: string = ''): string {
    return buildPluginShadowSourceUrl(pluginId, sourceId);
  }

  pluginsRootDir(): string {
    return `${this.context.filesDir}/plugins`;
  }

  tempRootDir(): string {
    return `${this.context.cacheDir}/plugin_temp`;
  }

  platformName(): 'harmonyos' | 'node' {
    return 'harmonyos';
  }

  isDarkMode(): boolean {
    return AppStorage.get<boolean>('appDarkMode') === true;
  }

  isWebParseEnabled(): boolean {
    // 引擎把带网页登录或通配域名的插件放在“在线内容”门槛后面；本应用打开插件总开关时已经同意过插件须知，
    // 门槛就跟总开关走，不和网页解析的开关绑在一起。
    return PluginFeatureStore.enabled();
  }

  async readFileBytes(absPath: string): Promise<Uint8Array> {
    const stat = await fs.stat(absPath);
    const fd = await fs.open(absPath, fs.OpenMode.READ_ONLY);
    try {
      const buf = new ArrayBuffer(stat.size);
      if (stat.size > 0) {
        await fs.read(fd.fd, buf);
      }
      return new Uint8Array(buf);
    } finally {
      await fs.close(fd);
    }
  }

  async readFileText(absPath: string): Promise<string> {
    const bytes = await this.readFileBytes(absPath);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  async writeFileBytes(absPath: string, data: Uint8Array): Promise<void> {
    const fd = await fs.open(absPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try {
      if (data.byteLength > 0) {
        const copy = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
        await fs.write(fd.fd, copy);
      }
    } finally {
      await fs.close(fd);
    }
  }

  async writeFileText(absPath: string, text: string): Promise<void> {
    const encoded = new util.TextEncoder().encodeInto(text);
    await this.writeFileBytes(absPath, encoded);
  }

  async listDir(absPath: string): Promise<string[]> {
    return await fs.listFile(absPath);
  }

  async exists(absPath: string): Promise<boolean> {
    if (!absPath) return false;
    try {
      return await fs.access(absPath);
    } catch (_) {
      return false;
    }
  }

  async mkdirs(absPath: string): Promise<void> {
    if (!absPath || (await this.exists(absPath))) return;
    try {
      await fs.mkdir(absPath, true);
    } catch (e) {
      if (!(await this.exists(absPath))) {
        throw e instanceof Error ? e : new Error(String(e));
      }
    }
  }

  async removePath(absPath: string): Promise<void> {
    if (!(await this.exists(absPath))) return;
    const stat = await fs.stat(absPath);
    if (stat.isDirectory()) {
      await fs.rmdir(absPath);
    } else {
      await fs.unlink(absPath);
    }
  }

  private async copyPathRecursive(fromAbsPath: string, toAbsPath: string): Promise<void> {
    const stat = await fs.stat(fromAbsPath);
    if (stat.isDirectory()) {
      await this.mkdirs(toAbsPath);
      const children = await fs.listFile(fromAbsPath);
      for (const name of children) {
        await this.copyPathRecursive(`${fromAbsPath}/${name}`, `${toAbsPath}/${name}`);
      }
      return;
    }
    const slash = toAbsPath.lastIndexOf('/');
    if (slash > 0) {
      await this.mkdirs(toAbsPath.slice(0, slash));
    }
    await fs.copyFile(fromAbsPath, toAbsPath);
  }

  async renamePath(fromAbsPath: string, toAbsPath: string): Promise<void> {
    const slash = toAbsPath.lastIndexOf('/');
    if (slash > 0) {
      await this.mkdirs(toAbsPath.slice(0, slash));
    }
    try {
      await fs.rename(fromAbsPath, toAbsPath);
    } catch (_) {
      await this.copyPathRecursive(fromAbsPath, toAbsPath);
      await this.removePath(fromAbsPath);
    }
  }

  async extractZip(zipAbsPath: string, destDirAbsPath: string): Promise<void> {
    await this.mkdirs(destDirAbsPath);
    if (zipAbsPath.toLowerCase().endsWith('.zip')) {
      await zlib.decompressFile(zipAbsPath, destDirAbsPath);
      return;
    }
    await this.mkdirs(this.tempRootDir());
    const tempZip = `${this.tempRootDir()}/extract_${Date.now()}_${Math.floor(Math.random() * 100000)}.zip`;
    await fs.copyFile(zipAbsPath, tempZip);
    try {
      await zlib.decompressFile(tempZip, destDirAbsPath);
    } finally {
      await this.removePath(tempZip);
    }
  }

  async sha256Hex(data: Uint8Array): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data });
    const digest = await md.digest();
    let hex = '';
    for (let i = 0; i < digest.data.length; i++) {
      hex += digest.data[i].toString(16).padStart(2, '0');
    }
    return hex;
  }

  async verifyEd25519(publicKeySpki: Uint8Array, data: Uint8Array, signature: Uint8Array): Promise<boolean> {
    const generator = cryptoFramework.createAsyKeyGenerator('Ed25519');
    const keyPair = await generator.convertKey({ data: publicKeySpki }, null);
    const verifier = cryptoFramework.createVerify('Ed25519');
    await verifier.init(keyPair.pubKey);
    // Ed25519 不支持分段 update，整段数据交给 verify。
    return await verifier.verify({ data: data }, { data: signature });
  }

  async loadRegistryJson(): Promise<string> {
    const store = await preferences.getPreferences(this.context, REGISTRY_PREFS_NAME);
    const val = await store.get('registry_state', '');
    return typeof val === 'string' ? val : '';
  }

  async saveRegistryJson(rawJson: string): Promise<void> {
    const store = await preferences.getPreferences(this.context, REGISTRY_PREFS_NAME);
    await store.put('registry_state', rawJson);
    await store.flush();
  }

  private kvStoreName(pluginId: string): string {
    const safe = pluginId.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 48);
    return `${KV_PREFS_PREFIX}${safe}`;
  }

  async loadPluginKvJson(pluginId: string): Promise<string> {
    const store = await preferences.getPreferences(this.context, this.kvStoreName(pluginId));
    const val = await store.get('kv_blob', '');
    return typeof val === 'string' ? val : '';
  }

  async savePluginKvJson(pluginId: string, rawJson: string): Promise<void> {
    const store = await preferences.getPreferences(this.context, this.kvStoreName(pluginId));
    if (!rawJson) {
      await store.clear();
    } else {
      await store.put('kv_blob', rawJson);
    }
    await store.flush();
  }

  async getSecret(pluginId: string, key: string): Promise<string> {
    const res = await this.secretStore.read(this.context, `${pluginId}:${key}`);
    return res.value;
  }

  async setSecret(pluginId: string, key: string, value: string): Promise<void> {
    await this.secretStore.save(this.context, `${pluginId}:${key}`, value);
  }

  async clearPluginSecrets(pluginId: string): Promise<void> {
    const store = await preferences.getPreferences(this.context, SECRET_STORE_NAME);
    const all = await store.getAll() as Record<string, Object>;
    const prefix = `${pluginId}:`;
    let touched = false;
    for (const k of Object.keys(all)) {
      if (k.startsWith(prefix)) {
        await store.delete(k);
        touched = true;
      }
    }
    if (touched) await store.flush();
  }

  async httpRequest(pluginId: string, req: PluginHttpRequest): Promise<PluginHttpResponse> {
    const headers: Record<string, string> = {};
    if (req.headers) {
      for (const k of Object.keys(req.headers)) {
        headers[k] = req.headers[k];
      }
    }
    let bodyText: string | undefined;
    let bodyBuf: ArrayBuffer | undefined;

    if (req.bodyBytes) {
      bodyBuf = req.bodyBytes.buffer.slice(
        req.bodyBytes.byteOffset,
        req.bodyBytes.byteOffset + req.bodyBytes.byteLength
      ) as ArrayBuffer;
    } else if (typeof req.body === 'string') {
      bodyText = req.body;
    } else if (req.body && typeof req.body === 'object') {
      bodyText = JSON.stringify(req.body);
      if (!Object.keys(headers).some((h) => h.toLowerCase() === 'content-type')) {
        headers['Content-Type'] = 'application/json; charset=utf-8';
      }
    }

    const timeout = Math.min(Math.max(req.timeoutMs ?? 20000, 1000), 60000);
    const httpReq: HttpRequest = {
      url: req.url,
      method: req.method || 'GET',
      headers,
      body: bodyText,
      bodyBytes: bodyBuf,
      connectTimeout: timeout,
      readTimeout: timeout,
      deadlineAt: Date.now() + timeout + 2000,
      cookieSource: `plugin://${pluginId}`,
      noTimeoutRetry: true,
      followRedirects: req.followRedirects !== false
    };

    if (req.responseType === 'bytes') {
      const binResp = await this.httpClient.executeBinary(httpReq);
      if (!binResp.success && binResp.statusCode === 0) {
        throw new Error(binResp.error || '网络请求失败');
      }
      return {
        status: binResp.statusCode,
        headers: binResp.headers || {},
        text: '',
        bytes: binResp.data,
        finalUrl: binResp.finalUrl || binResp.url
      };
    }

    const resp = await this.httpClient.execute(httpReq);
    if (!resp.success && resp.statusCode === 0) {
      throw new Error(resp.error || '网络请求失败');
    }
    return {
      status: resp.statusCode,
      headers: resp.headers || {},
      text: resp.body || '',
      finalUrl: resp.finalUrl || resp.url
    };
  }

  async resolveHostAddresses(host: string): Promise<string[]> {
    const list = await connection.getAddressesByName(host);
    return (list || []).map((item: connection.NetAddress): string => item.address).filter((a: string): boolean => !!a);
  }

  async cssSelect(html: string, rule: string, all: boolean): Promise<string | string[]> {
    const analyzer = new AnalyzeRule(html).setDeadline(2000).enableChainedReplacements();
    return all ? analyzer.getStringList(rule) : analyzer.getString(rule);
  }

  async xpathSelect(html: string, expr: string): Promise<string[]> {
    const normalized = expr.startsWith('@XPath:') || expr.startsWith('//') ? expr : `//${expr}`;
    const analyzer = new AnalyzeRule(html).setDeadline(2000);
    return analyzer.getStringList(normalized);
  }

  async jsonPathSelect(jsonText: string, expr: string): Promise<Object | null> {
    return JsonPathEvaluator.evaluate(jsonText, expr) as Object | null;
  }

  async regexTransform(text: string, pattern: string, replacement: string | null): Promise<string | string[]> {
    if (replacement !== null) {
      const replacer = new BudgetedRegexReplace(pattern, '', text.includes('\r'));
      return replacer.replace(text, replacement, Date.now() + 1500) ?? text;
    }
    const re = new RegExp(pattern, 'g');
    const matches: string[] = [];
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      matches.push(m[1] !== undefined ? m[1] : m[0]);
      if (m[0].length === 0) re.lastIndex++;
      if (matches.length >= 10000) break;
    }
    return matches;
  }

  async digestHex(algorithm: string, data: Uint8Array): Promise<string> {
    const algUpper = algorithm.trim().toUpperCase().replace('-', '');
    if (algUpper === 'MD5' || algUpper === 'SHA1' || algUpper === 'SHA256' || algUpper === 'SHA512') {
      const md = cryptoFramework.createMd(algUpper);
      await md.update({ data });
      const out = await md.digest();
      let hex = '';
      for (let i = 0; i < out.data.length; i++) {
        hex += out.data[i].toString(16).padStart(2, '0');
      }
      return hex;
    }
    const text = util.TextDecoder.create('utf-8').decodeToString(data);
    return digestHashHex(algorithm, text);
  }

  async hmacHex(algorithm: string, key: Uint8Array, data: Uint8Array): Promise<string> {
    const algUpper = algorithm.trim().toUpperCase().replace('-', '');
    const symGen = cryptoFramework.createSymKeyGenerator('HMAC');
    const symKey = await symGen.convertKey({ data: key });
    const mac = cryptoFramework.createMac(algUpper);
    await mac.init(symKey);
    await mac.update({ data });
    const out = await mac.doFinal();
    let hex = '';
    for (let i = 0; i < out.data.length; i++) {
      hex += out.data[i].toString(16).padStart(2, '0');
    }
    return hex;
  }

  private decodeKeyOrIv(hex?: string, b64?: string, utf8?: string): Uint8Array {
    if (hex) {
      const clean = hex.trim();
      const out = new Uint8Array(Math.floor(clean.length / 2));
      for (let i = 0; i < out.length; i++) {
        out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16) || 0;
      }
      return out;
    }
    if (b64) {
      return new util.Base64Helper().decodeSync(b64.trim());
    }
    if (utf8) {
      return new util.TextEncoder().encodeInto(utf8);
    }
    return new Uint8Array(0);
  }

  private async runAes(options: PluginAesOptions, input: Uint8Array, encrypt: boolean): Promise<Uint8Array> {
    const keyBytes = this.decodeKeyOrIv(options.keyHex, options.keyBase64, options.keyUtf8);
    const bits = keyBytes.byteLength * 8;
    if (bits !== 128 && bits !== 192 && bits !== 256) {
      throw new Error(`AES 密钥长度必须为 16/24/32 字节（当前 ${keyBytes.byteLength}）`);
    }
    const mode = options.mode || 'CBC';
    const pad = options.padding || 'PKCS7';
    const algSpec = `AES${bits}|${mode}|${pad}`;
    const keyGen = cryptoFramework.createSymKeyGenerator(`AES${bits}`);
    const symKey = await keyGen.convertKey({ data: keyBytes });
    const cipher = cryptoFramework.createCipher(algSpec);
    if (mode === 'ECB') {
      await cipher.init(
        encrypt ? cryptoFramework.CryptoMode.ENCRYPT_MODE : cryptoFramework.CryptoMode.DECRYPT_MODE,
        symKey,
        null
      );
    } else {
      const ivBytes = this.decodeKeyOrIv(options.ivHex, options.ivBase64, options.ivUtf8);
      const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: ivBytes } };
      await cipher.init(
        encrypt ? cryptoFramework.CryptoMode.ENCRYPT_MODE : cryptoFramework.CryptoMode.DECRYPT_MODE,
        symKey,
        params
      );
    }
    const res = await cipher.doFinal({ data: input });
    return res.data;
  }

  async aesEncrypt(options: PluginAesOptions, plain: Uint8Array): Promise<Uint8Array> {
    return this.runAes(options, plain, true);
  }

  async aesDecrypt(options: PluginAesOptions, cipher: Uint8Array): Promise<Uint8Array> {
    return this.runAes(options, cipher, false);
  }

  base64Encode(data: Uint8Array): string {
    return new util.Base64Helper().encodeToStringSync(data);
  }

  base64Decode(b64: string): Uint8Array {
    return new util.Base64Helper().decodeSync(b64);
  }

  async getActiveBookContext(): Promise<PluginBookContext | null> {
    const engine = ReadBookEngine.get();
    const book = engine.book;
    if (!book) return null;
    const idx = engine.curIdx;
    const ch = engine.chapters[idx];
    return {
      bookUrl: book.bookUrl,
      name: book.name,
      author: book.author,
      origin: book.origin,
      chapterIndex: idx,
      chapterTitle: ch ? ch.title : ''
    };
  }

  async getBookAnnotations(chapterIndex: number): Promise<PluginAnnotationItem[]> {
    const book = ReadBookEngine.get().book;
    if (!book) return [];
    const db = AppDatabase.getInstance();
    await db.initWithContext(this.context);
    const rows = await db.getBookAnnotations(book.bookUrl);
    return rows
      .filter((a: BookAnnotation) => chapterIndex < 0 || a.chapterIndex === chapterIndex)
      .map((a: BookAnnotation): PluginAnnotationItem => ({
        id: `${a.id}`,
        chapterIndex: a.chapterIndex,
        chapterTitle: a.chapterName,
        selectedText: a.quote,
        noteText: a.note,
        color: a.color,
        createdAt: a.updateTime || a.createTime
      }));
  }

  async addBookAnnotation(spec: Record<string, Object | null>): Promise<boolean> {
    const engine = ReadBookEngine.get();
    const book = engine.book;
    if (!book) return false;
    const db = AppDatabase.getInstance();
    await db.initWithContext(this.context);
    const ann = new BookAnnotation();
    ann.bookUrl = book.bookUrl;
    ann.bookName = book.name;
    const rawChapterIdx = spec['chapterIndex'];
    ann.chapterIndex = typeof rawChapterIdx === 'number'
      ? rawChapterIdx
      : engine.curIdx;
    ann.chapterName = String(spec['chapterTitle'] || engine.chapters[ann.chapterIndex]?.title || '');
    ann.quote = String(spec['selectedText'] || spec['bookText'] || '');
    ann.note = String(spec['noteText'] || spec['content'] || '');
    ann.color = String(spec['color'] || '#3B82F6');
    ann.style = 'bg';
    const rawStart = spec['startOffset'];
    const rawEnd = spec['endOffset'];
    ann.start = typeof rawStart === 'number' ? rawStart : 0;
    ann.end = typeof rawEnd === 'number'
      ? rawEnd
      : (ann.start + ann.quote.length);
    ann.excerpt = spec['excerpt'] === true;
    ann.createTime = Date.now();
    ann.updateTime = ann.createTime;
    if (!ann.quote) return false;
    await db.insertBookAnnotation(ann);
    return true;
  }

  showToast(pluginName: string, message: string): void {
    const clean = message.trim();
    if (!clean) return;
    HdsFeedback.showToast(pluginName ? `${pluginName}：${clean}` : clean);
  }

  async openPluginPanel(spec: PluginPanelOpenSpec): Promise<void> {
    for (const fn of AppPluginHost.panelOpenListeners) {
      try {
        fn(spec);
      } catch (_) {}
    }
  }

  postMessageToOpenPanel(pluginId: string, data: Object | null): void {
    const set = AppPluginHost.panelMsgListeners.get(pluginId);
    if (!set) return;
    for (const fn of set) {
      try {
        fn(data);
      } catch (_) {}
    }
  }

  emitSearchBatch(pluginId: string, items: Record<string, Object | null>[]): void {
    const sinks = AppPluginHost.searchEmitListeners.get(pluginId);
    if (!sinks) return;
    for (const sink of sinks) {
      try {
        sink(pluginId, items);
      } catch (_) {}
    }
  }

  registerSearchEmitSink(pluginId: string, fn: SearchEmitListener): () => void {
    return AppPluginHost.registerSearchEmitSink(pluginId, fn);
  }

  async openVerifyWeb(pluginId: string, spec: PluginVerifyWebSpec): Promise<string> {
    const handler = NativeSourceInteraction.handler();
    if (!handler) {
      throw new Error('当前环境无法打开网页验证窗口');
    }
    AppStorage.setOrCreate('pendingVerificationCallbackPrefix', spec.callbackUrlPrefix || '');
    try {
      const res = await handler.openBrowser({
        sourceUrl: AppPluginHost.shadowBookSourceUrl(pluginId),
        sourceName: spec.title || pluginId,
        url: spec.url,
        title: spec.title || '网页验证'
      }, true);
      if (res.error) {
        throw new Error(res.error);
      }
      return res.body || '';
    } finally {
      AppStorage.setOrCreate('pendingVerificationCallbackPrefix', '');
    }
  }

  /** 在线书源类插件本应用不接，没有影子书源要同步。 */
  async syncShadowBookSource(_manifest: PluginManifest, _enabled: boolean): Promise<void> {
  }

  async removeShadowBookSource(_pluginId: string): Promise<void> {
  }
}
