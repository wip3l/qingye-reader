// Copyright (c) 2026 qingye-plugin-reader contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef PLUGIN_RUNTIME_GUEST_ENGINE_H
#define PLUGIN_RUNTIME_GUEST_ENGINE_H

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace qyplugin {

constexpr size_t MAX_PLUGIN_BINARY_BYTES = 32 * 1024 * 1024;
constexpr size_t MAX_MODULE_FILE_BYTES = 8 * 1024 * 1024;

struct HostPayload {
    std::string metaJson;
    bool hasBytes = false;
    std::vector<uint8_t> bytes;
};

using HostInvoker = std::function<bool(
    const std::string& method,
    const HostPayload& request,
    HostPayload& response,
    std::string& errorOut)>;

class GuestEngine {
public:
    virtual ~GuestEngine() = default;

    virtual bool initialize(
        const std::string& pluginRoot,
        size_t memoryLimitBytes,
        size_t stackLimitBytes,
        HostInvoker invoker,
        std::string& errorOut) = 0;

    virtual bool loadEntry(
        const std::string& entryRelPath,
        int cpuTimeoutMs,
        std::string& errorOut,
        bool& timedOut,
        bool& cancelled) = 0;

    virtual bool invoke(
        const std::string& exportName,
        const HostPayload& input,
        int cpuTimeoutMs,
        HostPayload& output,
        std::string& errorOut,
        bool& timedOut,
        bool& cancelled) = 0;

    virtual void notifyInterrupt() = 0;
    virtual void clearInterrupt() = 0;
    virtual void collectGarbage() = 0;
    virtual size_t memoryUsageBytes() const = 0;
};

std::unique_ptr<GuestEngine> CreateQuickJsGuest();
std::unique_ptr<GuestEngine> CreatePocketPyGuest();

bool NormalizeSafeRelativePath(
    const std::string& baseRelDir,
    const std::string& requestedPath,
    std::string& normalizedRelOut);

bool ReadPluginTextFile(
    const std::string& pluginRoot,
    const std::string& safeRelPath,
    std::string& contentOut,
    std::string& errorOut);

} // namespace qyplugin

#endif // PLUGIN_RUNTIME_GUEST_ENGINE_H
