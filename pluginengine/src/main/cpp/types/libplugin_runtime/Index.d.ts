export interface PluginSessionOutcome {
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

export type PluginHostCallCallback = (
  callId: number,
  method: string,
  metaJson: string,
  bytes?: ArrayBuffer
) => void;

export interface PluginRuntimeNativeApi {
  sessionCreate(
    runtimeKind: 'js' | 'python',
    pluginRoot: string,
    memoryLimitBytes: number,
    stackLimitBytes: number,
    hostTimeoutMs: number,
    onHostCall: PluginHostCallCallback
  ): number;
  sessionLoadEntry(
    sessionId: number,
    entryRelPath: string,
    cpuTimeoutMs: number
  ): Promise<PluginSessionOutcome>;
  sessionInvoke(
    sessionId: number,
    exportName: string,
    metaJson: string,
    bytes: Uint8Array | undefined,
    cpuTimeoutMs: number
  ): Promise<PluginSessionOutcome>;
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

declare const pluginRuntime: PluginRuntimeNativeApi;
export default pluginRuntime;
