import pluginRuntime, {
  PluginHostCallCallback,
  PluginSessionOutcome
} from 'libplugin_runtime.so';
import { PluginNativeDriver } from './PluginSessionPool';

export class NativeCppPluginDriver implements PluginNativeDriver {
  sessionCreate(
    runtimeKind: 'js' | 'python',
    pluginRoot: string,
    memoryLimitBytes: number,
    stackLimitBytes: number,
    hostTimeoutMs: number,
    onHostCall: PluginHostCallCallback
  ): number {
    return pluginRuntime.sessionCreate(
      runtimeKind,
      pluginRoot,
      memoryLimitBytes,
      stackLimitBytes,
      hostTimeoutMs,
      onHostCall
    );
  }

  sessionLoadEntry(sessionId: number, entryRelPath: string, cpuTimeoutMs: number): Promise<PluginSessionOutcome> {
    return pluginRuntime.sessionLoadEntry(sessionId, entryRelPath, cpuTimeoutMs);
  }

  sessionInvoke(
    sessionId: number,
    exportName: string,
    metaJson: string,
    bytes: Uint8Array | undefined,
    cpuTimeoutMs: number
  ): Promise<PluginSessionOutcome> {
    return pluginRuntime.sessionInvoke(sessionId, exportName, metaJson, bytes, cpuTimeoutMs);
  }

  sessionResolve(
    sessionId: number,
    callId: number,
    ok: boolean,
    metaJson: string,
    bytes?: Uint8Array
  ): boolean {
    return pluginRuntime.sessionResolve(sessionId, callId, ok, metaJson, bytes);
  }

  sessionCancel(sessionId: number): void {
    pluginRuntime.sessionCancel(sessionId);
  }

  sessionRelease(sessionId: number): void {
    pluginRuntime.sessionRelease(sessionId);
  }
}
