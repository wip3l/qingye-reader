import { NativeCppPluginDriver } from './src/main/ets/runtime/NativePluginRuntime';
import { PluginSessionPool } from './src/main/ets/runtime/PluginSessionPool';

PluginSessionPool.setDriver(new NativeCppPluginDriver());

export * from './src/main/ets/spec/PluginManifest';
export * from './src/main/ets/package/ZipArchivePrecheck';
export * from './src/main/ets/package/PluginPackageInstaller';
export * from './src/main/ets/package/PluginSignature';
export * from './src/main/ets/package/PluginTrustPolicy';
export * from './src/main/ets/host/PluginHostPort';
export * from './src/main/ets/host/PluginCapabilityGuard';
export * from './src/main/ets/runtime/PluginSessionPool';
export * from './src/main/ets/registry/PluginRegistry';
