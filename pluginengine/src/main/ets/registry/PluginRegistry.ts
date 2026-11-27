import {
  HostCallResult,
  PluginHostDispatcher,
  PluginLogEntry,
  PluginNetworkTrace
} from '../host/PluginCapabilityGuard';
import { PluginEngineHost } from '../host/PluginHostPort';
import {
  PluginInstallPreview,
  PluginPackageInstaller
} from '../package/PluginPackageInstaller';
import { evaluateInstallTrust, PluginInstallBaseline } from '../package/PluginTrustPolicy';
import {
  PluginInvokeOptions,
  PluginInvokeResult,
  PluginRuntimeMetrics,
  PluginSessionPool
} from '../runtime/PluginSessionPool';
import {
  getManifestContentSources,
  normalizePluginSettings,
  PluginCatalogConnectorContribution,
  PluginContentProcessorContribution,
  PluginFormatImporterContribution,
  PluginInteractionContribution,
  PluginManifest,
  PluginReaderActionContribution,
  PluginSourceManagerContribution,
  PluginTicketStyleContribution,
  PluginToolContribution,
  PluginTranslationContribution,
  PluginTtsContribution,
  requiresWebParseGate,
  validatePluginManifest
} from '../spec/PluginManifest';

export interface InstalledPluginRecord {
  manifest: PluginManifest;
  installDir: string;
  enabled: boolean;
  installedAt: number;
  updatedAt: number;
  settings: Record<string, string | number | boolean>;
  /** 首次安装时绑定的签名者指纹；未签名为空串。之后的升级必须来自同一签名者。 */
  signer: string;
}

interface PersistedRegistryState {
  version: number;
  plugins: {
    manifest: PluginManifest;
    installDir: string;
    enabled: boolean;
    installedAt: number;
    updatedAt: number;
    settings: Record<string, string | number | boolean>;
    signer?: string;
  }[];
}

export interface BoundPluginContribution<T> {
  plugin: InstalledPluginRecord;
  contribution: T;
}

export type PluginRegistryListener = (revision: number) => void;

export class PluginRegistry {
  private static instance: PluginRegistry | null = null;
  private records: Map<string, InstalledPluginRecord> = new Map();
  private dispatcher: PluginHostDispatcher | null = null;
  private pool: PluginSessionPool | null = null;
  private initialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  private revision: number = 1;
  private listeners: Set<PluginRegistryListener> = new Set();

  static getInstance(): PluginRegistry {
    if (!PluginRegistry.instance) {
      PluginRegistry.instance = new PluginRegistry();
    }
    return PluginRegistry.instance;
  }

  static resetForTests(): void {
    PluginRegistry.instance = null;
  }

  getRevision(): number {
    return this.revision;
  }

  subscribe(listener: PluginRegistryListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private bumpRevision(): void {
    this.revision++;
    for (const fn of this.listeners) {
      try {
        fn(this.revision);
      } catch (_) {}
    }
  }

  private ensureRuntime(): { dispatcher: PluginHostDispatcher; pool: PluginSessionPool } {
    if (!this.dispatcher || !this.pool) {
      const port = PluginEngineHost.port();
      this.dispatcher = new PluginHostDispatcher(
        port,
        (pluginId: string) => this.getSettings(pluginId),
        async (pluginId: string, key: string, val: unknown) => {
          await this.updateSettingValue(pluginId, key, val);
        }
      );
      this.pool = new PluginSessionPool(this.dispatcher);
    }
    return { dispatcher: this.dispatcher, pool: this.pool };
  }

  async ensureInitialized(): Promise<void> {
    if (this.initialized) return;
    if (this.initPromise) return this.initPromise;
    this.initPromise = this.loadFromPersistence().finally(() => {
      this.initPromise = null;
    });
    return this.initPromise;
  }

  private async loadFromPersistence(): Promise<void> {
    const port = PluginEngineHost.port();
    await port.mkdirs(port.pluginsRootDir());
    const raw = await port.loadRegistryJson();
    this.records.clear();
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as PersistedRegistryState;
        if (parsed && Array.isArray(parsed.plugins)) {
          for (const item of parsed.plugins) {
            try {
              const manifest = validatePluginManifest(item.manifest);
              if (await port.exists(item.installDir)) {
                this.records.set(manifest.id, {
                  manifest,
                  installDir: item.installDir,
                  enabled: Boolean(item.enabled),
                  installedAt: Number(item.installedAt) || Date.now(),
                  updatedAt: Number(item.updatedAt) || Date.now(),
                  settings: normalizePluginSettings(manifest, item.settings),
                  signer: typeof item.signer === 'string' ? item.signer : ''
                });
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    this.initialized = true;
    for (const rec of this.records.values()) {
      if (getManifestContentSources(rec.manifest).length > 0) {
        try {
          await port.syncShadowBookSource(rec.manifest, rec.enabled);
        } catch (_) {}
      }
    }
    this.bumpRevision();
  }

  private async persist(): Promise<void> {
    const port = PluginEngineHost.port();
    const state: PersistedRegistryState = {
      version: 1,
      plugins: Array.from(this.records.values()).map((r) => ({
        manifest: r.manifest,
        installDir: r.installDir,
        enabled: r.enabled,
        installedAt: r.installedAt,
        updatedAt: r.updatedAt,
        settings: r.settings,
        signer: r.signer
      }))
    };
    await port.saveRegistryJson(JSON.stringify(state));
  }

  listAll(): InstalledPluginRecord[] {
    return Array.from(this.records.values()).sort((a, b) => b.updatedAt - a.updatedAt);
  }

  listEnabled(webParseEnabled: boolean = PluginEngineHost.isInstalled() ? PluginEngineHost.port().isWebParseEnabled() : false): InstalledPluginRecord[] {
    return this.listAll().filter((rec) => {
      if (!rec.enabled) return false;
      if (requiresWebParseGate(rec.manifest) && !webParseEnabled) return false;
      return true;
    });
  }

  getPlugin(pluginId: string): InstalledPluginRecord | undefined {
    return this.records.get(pluginId);
  }

  getSettings(pluginId: string): Record<string, string | number | boolean> {
    const rec = this.records.get(pluginId);
    if (!rec) return {};
    return { ...rec.settings };
  }

  async updateSettingValue(pluginId: string, key: string, value: unknown): Promise<void> {
    const rec = this.records.get(pluginId);
    if (!rec) return;
    const nextRaw: Record<string, unknown> = { ...rec.settings, [key]: value };
    rec.settings = normalizePluginSettings(rec.manifest, nextRaw);
    await this.persist();
    this.bumpRevision();
  }

  async saveSettingsBatch(pluginId: string, values: Record<string, unknown>): Promise<void> {
    const rec = this.records.get(pluginId);
    if (!rec) return;
    rec.settings = normalizePluginSettings(rec.manifest, { ...rec.settings, ...values });
    await this.persist();
    this.bumpRevision();
  }

  async prepareInstall(zipAbsPath: string): Promise<PluginInstallPreview> {
    await this.ensureInitialized();
    const existing = new Map<string, PluginInstallBaseline>();
    for (const [id, rec] of this.records.entries()) {
      existing.set(id, PluginRegistry.baselineOf(rec));
    }
    return PluginPackageInstaller.prepareFromZipFile(zipAbsPath, PluginEngineHost.port(), existing);
  }

  private static baselineOf(rec: InstalledPluginRecord): PluginInstallBaseline {
    return {
      version: rec.manifest.version,
      signer: rec.signer,
      permissions: rec.manifest.permissions.slice(),
      domains: rec.manifest.domains.slice()
    };
  }

  async commitInstall(preview: PluginInstallPreview): Promise<InstalledPluginRecord> {
    await this.ensureInitialized();
    const port = PluginEngineHost.port();
    const { pool } = this.ensureRuntime();
    const prev = this.records.get(preview.manifest.id);
    // 预览之后已安装状态可能变了（另一次安装、调试页直接安装），提交前按当前记录再判一次。
    evaluateInstallTrust(preview.manifest, preview.signerFingerprint, prev ? PluginRegistry.baselineOf(prev) : undefined);
    if (prev) {
      pool.releasePlugin(prev.manifest.id);
    }

    const installDir = await PluginPackageInstaller.commitPreview(preview, port);
    const now = Date.now();
    const record: InstalledPluginRecord = {
      manifest: preview.manifest,
      installDir,
      enabled: prev ? prev.enabled : true,
      installedAt: prev ? prev.installedAt : now,
      updatedAt: now,
      settings: normalizePluginSettings(preview.manifest, prev ? prev.settings : null),
      signer: preview.signerFingerprint
    };
    this.records.set(record.manifest.id, record);
    await this.persist();
    if (getManifestContentSources(record.manifest).length > 0) {
      await port.syncShadowBookSource(record.manifest, record.enabled);
    } else if (prev && getManifestContentSources(prev.manifest).length > 0) {
      await port.removeShadowBookSource(record.manifest.id);
    }
    this.bumpRevision();
    return record;
  }

  async discardInstall(preview: PluginInstallPreview): Promise<void> {
    await PluginPackageInstaller.discardPreview(preview, PluginEngineHost.port());
  }

  async setPluginEnabled(pluginId: string, enabled: boolean): Promise<void> {
    await this.ensureInitialized();
    const rec = this.records.get(pluginId);
    if (!rec || rec.enabled === enabled) return;
    rec.enabled = enabled;
    if (!enabled) {
      this.ensureRuntime().pool.releasePlugin(pluginId);
    }
    await this.persist();
    if (getManifestContentSources(rec.manifest).length > 0) {
      await PluginEngineHost.port().syncShadowBookSource(rec.manifest, enabled);
    }
    this.bumpRevision();
  }

  async uninstallPlugin(pluginId: string): Promise<void> {
    await this.ensureInitialized();
    const rec = this.records.get(pluginId);
    if (!rec) return;
    const port = PluginEngineHost.port();
    const { dispatcher, pool } = this.ensureRuntime();
    pool.releasePlugin(pluginId);
    dispatcher.clearLogs(pluginId);
    this.records.delete(pluginId);
    await this.persist();

    if (getManifestContentSources(rec.manifest).length > 0) {
      await port.removeShadowBookSource(pluginId);
    }
    try {
      await port.clearPluginSecrets(pluginId);
    } catch (_) {}
    try {
      await port.savePluginKvJson(pluginId, '');
    } catch (_) {}
    const basePluginDir = `${port.pluginsRootDir()}/${pluginId}`;
    if (await port.exists(basePluginDir)) {
      await port.removePath(basePluginDir);
    }
    this.bumpRevision();
  }

  async invokePlugin<T = unknown>(
    pluginId: string,
    handlerName: string,
    args: Record<string, unknown>,
    options: PluginInvokeOptions = {}
  ): Promise<PluginInvokeResult<T>> {
    await this.ensureInitialized();
    const rec = this.records.get(pluginId);
    if (!rec) {
      throw new Error(`插件未安装: ${pluginId}`);
    }
    if (!rec.enabled) {
      throw new Error(`插件已禁用: ${rec.manifest.name}`);
    }
    if (requiresWebParseGate(rec.manifest) && !PluginEngineHost.port().isWebParseEnabled()) {
      throw new Error('请先在插件管理中确认使用须知并启用对应插件');
    }
    const { pool } = this.ensureRuntime();
    return pool.invoke<T>(rec.manifest, rec.installDir, handlerName, args, options);
  }

  async dispatchPanelHostCall(
    pluginId: string,
    method: string,
    metaJson: string,
    bytes?: Uint8Array
  ): Promise<HostCallResult> {
    await this.ensureInitialized();
    const rec = this.records.get(pluginId);
    if (!rec || !rec.enabled) {
      throw new Error('插件不存在或未启用');
    }
    if (method === 'plugin.call') {
      const parsed = metaJson ? (JSON.parse(metaJson) as Record<string, unknown>) : {};
      const handler = String(parsed['handler'] || '');
      const payload = (parsed['payload'] && typeof parsed['payload'] === 'object')
        ? (parsed['payload'] as Record<string, unknown>)
        : {};
      if (!handler) throw new Error('plugin.call 缺少 handler 函数名');
      const wallTimeoutMs = rec.manifest.permissions.includes('webview.verify') ? 300000 : undefined;
      const res = await this.invokePlugin(pluginId, handler, payload, { bytes, wallTimeoutMs });
      return { metaJson: JSON.stringify(res.data), bytes: res.bytes };
    }
    const { dispatcher } = this.ensureRuntime();
    return dispatcher.dispatch(rec.manifest, rec.installDir, method, metaJson, bytes);
  }

  getLogs(pluginId: string): PluginLogEntry[] {
    return this.ensureRuntime().dispatcher.getLogs(pluginId);
  }

  clearLogs(pluginId: string): void {
    this.ensureRuntime().dispatcher.clearLogs(pluginId);
  }

  getNetworkTraces(pluginId: string): PluginNetworkTrace[] {
    return this.ensureRuntime().dispatcher.getNetworkTraces(pluginId);
  }

  getMetrics(pluginId: string): PluginRuntimeMetrics {
    return this.ensureRuntime().pool.getMetrics(pluginId);
  }

  onMemoryPressure(): void {
    if (this.pool) this.pool.onMemoryPressure();
  }

  // --- Typed Contribution Queries ---

  getTranslationProviders(): BoundPluginContribution<PluginTranslationContribution>[] {
    return this.listEnabled()
      .filter((r) => r.manifest.contributes.translation !== undefined)
      .map((r) => ({ plugin: r, contribution: r.manifest.contributes.translation! }));
  }

  getReaderActions(
    placement: 'selection' | 'menu',
    bookType?: 'text' | 'epub' | 'comic' | 'pdf'
  ): BoundPluginContribution<PluginReaderActionContribution>[] {
    const out: BoundPluginContribution<PluginReaderActionContribution>[] = [];
    for (const rec of this.listEnabled()) {
      const list = rec.manifest.contributes.readerActions || [];
      for (const act of list) {
        if (act.placement !== placement) continue;
        if (bookType && act.bookTypes && act.bookTypes.length > 0 && !act.bookTypes.includes(bookType)) {
          continue;
        }
        out.push({ plugin: rec, contribution: act });
      }
    }
    return out;
  }

  getContentProcessors(): BoundPluginContribution<PluginContentProcessorContribution>[] {
    return this.listEnabled()
      .filter((r) => r.manifest.contributes.contentProcessor !== undefined)
      .map((r) => ({ plugin: r, contribution: r.manifest.contributes.contentProcessor! }))
      .sort((a, b) => (a.contribution.order ?? 100) - (b.contribution.order ?? 100));
  }

  contentProcessorSignature(): string {
    const processors = this.getContentProcessors();
    if (processors.length === 0) return '';
    return processors
      .map((p) => `${p.plugin.manifest.id}@${p.plugin.manifest.version}:${JSON.stringify(p.plugin.settings)}`)
      .join('|');
  }

  getInteractionProviders(): BoundPluginContribution<PluginInteractionContribution>[] {
    return this.listEnabled()
      .filter((r) => r.manifest.contributes.interaction !== undefined)
      .map((r) => ({ plugin: r, contribution: r.manifest.contributes.interaction! }));
  }

  getTtsProviders(): BoundPluginContribution<PluginTtsContribution>[] {
    return this.listEnabled()
      .filter((r) => r.manifest.contributes.tts !== undefined)
      .map((r) => ({ plugin: r, contribution: r.manifest.contributes.tts! }));
  }

  getFormatImporters(): BoundPluginContribution<PluginFormatImporterContribution>[] {
    const out: BoundPluginContribution<PluginFormatImporterContribution>[] = [];
    for (const rec of this.listEnabled()) {
      for (const imp of rec.manifest.contributes.formatImporters || []) {
        out.push({ plugin: rec, contribution: imp });
      }
    }
    return out;
  }

  findFormatImporterByExtension(ext: string): BoundPluginContribution<PluginFormatImporterContribution> | null {
    const clean = ext.trim().toLowerCase().replace(/^\./, '');
    for (const item of this.getFormatImporters()) {
      if (item.contribution.extensions.includes(clean)) return item;
    }
    return null;
  }

  getCatalogConnectors(): BoundPluginContribution<PluginCatalogConnectorContribution>[] {
    const out: BoundPluginContribution<PluginCatalogConnectorContribution>[] = [];
    for (const rec of this.listEnabled()) {
      for (const cat of rec.manifest.contributes.catalogConnectors || []) {
        out.push({ plugin: rec, contribution: cat });
      }
    }
    return out;
  }

  getToolPanels(): BoundPluginContribution<PluginToolContribution>[] {
    const out: BoundPluginContribution<PluginToolContribution>[] = [];
    for (const rec of this.listEnabled()) {
      for (const tool of rec.manifest.contributes.tools || []) {
        out.push({ plugin: rec, contribution: tool });
      }
    }
    return out;
  }

  hasActiveOnlineReadingPlugin(): boolean {
    for (const rec of this.records.values()) {
      if (!rec.enabled) continue;
      if (
        rec.manifest.contributes.sourceManager !== undefined ||
        getManifestContentSources(rec.manifest).length > 0
      ) {
        return true;
      }
    }
    return false;
  }

  hasActiveSourceManager(): boolean {
    for (const rec of this.records.values()) {
      if (!rec.enabled) continue;
      if (rec.manifest.contributes.sourceManager !== undefined) {
        return true;
      }
    }
    return false;
  }

  hasActiveWebParseGatedPlugin(): boolean {
    for (const rec of this.records.values()) {
      if (!rec.enabled) continue;
      if (requiresWebParseGate(rec.manifest)) {
        return true;
      }
    }
    return false;
  }

  getSourceManagers(): BoundPluginContribution<PluginSourceManagerContribution>[] {
    return this.listEnabled()
      .filter((r) => r.manifest.contributes.sourceManager !== undefined)
      .map((r) => ({ plugin: r, contribution: r.manifest.contributes.sourceManager! }));
  }

  getTicketStyles(): BoundPluginContribution<PluginTicketStyleContribution>[] {
    const out: BoundPluginContribution<PluginTicketStyleContribution>[] = [];
    for (const rec of this.listEnabled()) {
      for (const style of rec.manifest.contributes.ticketStyles || []) {
        out.push({ plugin: rec, contribution: style });
      }
    }
    return out;
  }
}
