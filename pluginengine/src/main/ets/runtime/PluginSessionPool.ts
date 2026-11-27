import { PluginHostDispatcher } from '../host/PluginCapabilityGuard';
import { PluginManifest } from '../spec/PluginManifest';

export interface DriverSessionOutcome {
  success: boolean;
  metaJson: string;
  bytes?: ArrayBuffer;
  error: string;
  timedOut: boolean;
  cancelled: boolean;
  cpuMs: number;
  wallMs: number;
  hostWaitMs: number;
  hostCalls: number;
  memoryBytes: number;
}

export interface PluginNativeDriver {
  sessionCreate(
    runtimeKind: 'js' | 'python',
    pluginRoot: string,
    memoryLimitBytes: number,
    stackLimitBytes: number,
    hostTimeoutMs: number,
    onHostCall: (callId: number, method: string, metaJson: string, bytes?: ArrayBuffer) => void
  ): number;
  sessionLoadEntry(sessionId: number, entryRelPath: string, cpuTimeoutMs: number): Promise<DriverSessionOutcome>;
  sessionInvoke(
    sessionId: number,
    exportName: string,
    metaJson: string,
    bytes: Uint8Array | undefined,
    cpuTimeoutMs: number
  ): Promise<DriverSessionOutcome>;
  sessionResolve(
    sessionId: number,
    callId: number,
    ok: boolean,
    metaJson: string,
    bytes?: Uint8Array
  ): boolean;
  sessionCancel(sessionId: number): void;
  sessionRelease(sessionId: number): void;
}

export interface PluginRuntimeMetrics {
  pluginId: string;
  activeSession: boolean;
  totalInvocations: number;
  lastCpuMs: number;
  lastWallMs: number;
  lastHostWaitMs: number;
  lastMemoryBytes: number;
  lastError: string;
}

export interface PluginInvokeOptions {
  cpuTimeoutMs?: number;
  wallTimeoutMs?: number;
  bytes?: Uint8Array;
}

export interface PluginInvokeResult<T = unknown> {
  data: T;
  bytes?: Uint8Array;
  cpuMs: number;
  wallMs: number;
  hostWaitMs: number;
  memoryBytes: number;
}

interface ManagedSession {
  sessionId: number;
  key: string;
  pluginId: string;
  busy: boolean;
  entryLoaded: boolean;
  lastUsedAt: number;
  idleTimer: ReturnType<typeof setTimeout> | null;
}

export class PluginSessionPool {
  private static driver: PluginNativeDriver | null = null;
  private readonly sessions: Map<string, ManagedSession> = new Map();
  private readonly metrics: Map<string, PluginRuntimeMetrics> = new Map();
  private readonly dispatcher: PluginHostDispatcher;

  private static readonly DEFAULT_MEMORY_LIMIT: number = 64 * 1024 * 1024;
  private static readonly DEFAULT_STACK_LIMIT: number = 1024 * 1024;
  private static readonly DEFAULT_HOST_TIMEOUT_MS: number = 60000;
  private static readonly INTERACTIVE_WEB_HOST_TIMEOUT_MS: number = 300000;
  private static readonly DEFAULT_CPU_TIMEOUT_MS: number = 3000;
  private static readonly DEFAULT_WALL_TIMEOUT_MS: number = 45000;
  private static readonly IDLE_TTL_MS: number = 90000;

  constructor(dispatcher: PluginHostDispatcher) {
    this.dispatcher = dispatcher;
  }

  static setDriver(driver: PluginNativeDriver): void {
    PluginSessionPool.driver = driver;
  }

  private requireDriver(): PluginNativeDriver {
    if (!PluginSessionPool.driver) {
      throw new Error('PluginNativeDriver 未安装');
    }
    return PluginSessionPool.driver;
  }

  getMetrics(pluginId: string): PluginRuntimeMetrics {
    const m = this.metrics.get(pluginId);
    const active = Array.from(this.sessions.values()).some((s) => s.pluginId === pluginId);
    if (!m) {
      return {
        pluginId,
        activeSession: active,
        totalInvocations: 0,
        lastCpuMs: 0,
        lastWallMs: 0,
        lastHostWaitMs: 0,
        lastMemoryBytes: 0,
        lastError: ''
      };
    }
    return { ...m, activeSession: active };
  }

  private sessionKey(manifest: PluginManifest): string {
    return `${manifest.id}@${manifest.version}:${manifest.runtime}`;
  }

  private scheduleIdleRelease(managed: ManagedSession): void {
    if (managed.idleTimer !== null) {
      clearTimeout(managed.idleTimer);
    }
    managed.idleTimer = setTimeout(() => {
      managed.idleTimer = null;
      if (!managed.busy) {
        this.releaseSessionKey(managed.key);
      }
    }, PluginSessionPool.IDLE_TTL_MS);
  }

  releasePlugin(pluginId: string): void {
    for (const [key, session] of this.sessions.entries()) {
      if (session.pluginId === pluginId) {
        this.releaseSessionKey(key);
      }
    }
  }

  onMemoryPressure(): void {
    for (const [key, session] of this.sessions.entries()) {
      if (!session.busy) {
        this.releaseSessionKey(key);
      }
    }
  }

  private releaseSessionKey(key: string): void {
    const managed = this.sessions.get(key);
    if (!managed) return;
    this.sessions.delete(key);
    if (managed.idleTimer !== null) {
      clearTimeout(managed.idleTimer);
      managed.idleTimer = null;
    }
    try {
      this.requireDriver().sessionRelease(managed.sessionId);
    } catch (_) {}
  }

  private createManagedSession(manifest: PluginManifest, pluginDir: string): ManagedSession {
    if (manifest.runtime !== 'js' && manifest.runtime !== 'python') {
      throw new Error(`runtime="${manifest.runtime}" 不支持启动后台脚本会话`);
    }
    const driver = this.requireDriver();
    const key = this.sessionKey(manifest);
    let sessionId = 0;
    const hostTimeoutMs = manifest.permissions.includes('webview.verify')
      ? PluginSessionPool.INTERACTIVE_WEB_HOST_TIMEOUT_MS
      : PluginSessionPool.DEFAULT_HOST_TIMEOUT_MS;
    sessionId = driver.sessionCreate(
      manifest.runtime,
      pluginDir,
      PluginSessionPool.DEFAULT_MEMORY_LIMIT,
      PluginSessionPool.DEFAULT_STACK_LIMIT,
      hostTimeoutMs,
      (callId: number, method: string, metaJson: string, bytes?: ArrayBuffer) => {
        const u8 = bytes ? new Uint8Array(bytes) : undefined;
        this.dispatcher.dispatch(manifest, pluginDir, method, metaJson, u8)
          .then((res) => {
            driver.sessionResolve(sessionId, callId, true, res.metaJson, res.bytes);
          })
          .catch((err: unknown) => {
            const msg = err instanceof Error ? err.message : String(err);
            driver.sessionResolve(sessionId, callId, false, msg);
          });
      }
    );
    const managed: ManagedSession = {
      sessionId,
      key,
      pluginId: manifest.id,
      busy: false,
      entryLoaded: false,
      lastUsedAt: Date.now(),
      idleTimer: null
    };
    return managed;
  }

  async invoke<T = unknown>(
    manifest: PluginManifest,
    pluginDir: string,
    handlerName: string,
    args: Record<string, unknown>,
    options: PluginInvokeOptions = {}
  ): Promise<PluginInvokeResult<T>> {
    const driver = this.requireDriver();
    const key = this.sessionKey(manifest);
    let managed = this.sessions.get(key);
    let ephemeral = false;

    if (!managed) {
      managed = this.createManagedSession(manifest, pluginDir);
      this.sessions.set(key, managed);
    } else if (managed.busy) {
      // Spin up an isolated overflow session if primary is busy on a concurrent call
      managed = this.createManagedSession(manifest, pluginDir);
      ephemeral = true;
    }

    if (managed.idleTimer !== null) {
      clearTimeout(managed.idleTimer);
      managed.idleTimer = null;
    }
    managed.busy = true;
    managed.lastUsedAt = Date.now();

    const cpuTimeout = options.cpuTimeoutMs ?? PluginSessionPool.DEFAULT_CPU_TIMEOUT_MS;
    const wallTimeout = options.wallTimeoutMs ?? PluginSessionPool.DEFAULT_WALL_TIMEOUT_MS;
    const watchdog = setTimeout(() => {
      try {
        driver.sessionCancel(managed!.sessionId);
      } catch (_) {}
    }, wallTimeout);

    try {
      if (!managed.entryLoaded) {
        const loadOut = await driver.sessionLoadEntry(managed.sessionId, manifest.main, Math.max(cpuTimeout, 5000));
        if (!loadOut.success) {
          this.recordMetrics(manifest.id, loadOut, loadOut.error || '加载插件入口失败');
          if (!ephemeral) this.releaseSessionKey(key);
          throw new Error(loadOut.error || '加载插件入口失败');
        }
        managed.entryLoaded = true;
      }

      const payloadJson = JSON.stringify(args ?? {});
      const outcome = await driver.sessionInvoke(
        managed.sessionId,
        handlerName,
        payloadJson,
        options.bytes,
        cpuTimeout
      );

      this.recordMetrics(manifest.id, outcome, outcome.success ? '' : outcome.error);
      if (!outcome.success) {
        if (outcome.timedOut && !ephemeral) {
          this.releaseSessionKey(key);
        }
        throw new Error(outcome.error || `插件函数 ${handlerName} 执行失败`);
      }

      const parsed = outcome.metaJson ? (JSON.parse(outcome.metaJson) as T) : (null as unknown as T);
      return {
        data: parsed,
        bytes: outcome.bytes ? new Uint8Array(outcome.bytes) : undefined,
        cpuMs: outcome.cpuMs,
        wallMs: outcome.wallMs,
        hostWaitMs: outcome.hostWaitMs,
        memoryBytes: outcome.memoryBytes
      };
    } finally {
      clearTimeout(watchdog);
      managed.busy = false;
      managed.lastUsedAt = Date.now();
      if (ephemeral) {
        try {
          driver.sessionRelease(managed.sessionId);
        } catch (_) {}
      } else if (this.sessions.get(key) === managed) {
        this.scheduleIdleRelease(managed);
      }
    }
  }

  private recordMetrics(pluginId: string, out: DriverSessionOutcome, errorText: string): void {
    const prev = this.metrics.get(pluginId);
    this.metrics.set(pluginId, {
      pluginId,
      activeSession: true,
      totalInvocations: (prev?.totalInvocations ?? 0) + 1,
      lastCpuMs: out.cpuMs,
      lastWallMs: out.wallMs,
      lastHostWaitMs: out.hostWaitMs,
      lastMemoryBytes: out.memoryBytes,
      lastError: errorText
    });
  }
}
