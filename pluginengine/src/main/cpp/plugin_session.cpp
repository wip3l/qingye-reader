// Copyright (c) 2026 qingye-plugin-reader contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "guest_engine.h"
#include "napi/native_api.h"

#include <pthread.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace qyplugin {

namespace {

using Clock = std::chrono::steady_clock;

enum class JobKind { LoadEntry, Invoke };

struct SessionJob {
    int64_t id = 0;
    int64_t generation = 0;
    JobKind kind = JobKind::Invoke;
    std::string target;
    HostPayload input;
    int cpuTimeoutMs = 3000;
};

struct SessionOutcome {
    bool success = false;
    HostPayload output;
    std::string error;
    bool timedOut = false;
    bool cancelled = false;
    double cpuMs = 0;
    double wallMs = 0;
    double hostWaitMs = 0;
    int hostCalls = 0;
    size_t memoryBytes = 0;
};

enum class WireKind { HostCall, JobDone };

struct WireMessage {
    WireKind kind = WireKind::HostCall;
    int64_t sessionId = 0;
    int64_t id = 0;
    std::string method;
    HostPayload payload;
    SessionOutcome outcome;
};

struct PendingHostCall {
    bool done = false;
    bool ok = false;
    HostPayload response;
};

struct MainThreadState {
    int64_t sessionId = 0;
    std::unordered_map<int64_t, napi_deferred> deferreds;
};

double ToMillis(Clock::duration d)
{
    return std::chrono::duration<double, std::milli>(d).count();
}

class PluginSession final : public std::enable_shared_from_this<PluginSession> {
public:
    PluginSession(
        int64_t id,
        std::string runtimeKind,
        std::string pluginRoot,
        size_t memoryLimitBytes,
        size_t stackLimitBytes,
        int hostTimeoutMs)
        : id_(id),
          runtimeKind_(std::move(runtimeKind)),
          pluginRoot_(std::move(pluginRoot)),
          memoryLimitBytes_(memoryLimitBytes),
          stackLimitBytes_(stackLimitBytes),
          hostTimeoutMs_(hostTimeoutMs)
    {
    }

    int64_t id() const { return id_; }
    MainThreadState* mainState() const { return mainState_; }

    void attach(napi_threadsafe_function tsfn, MainThreadState* mainState)
    {
        tsfn_ = tsfn;
        mainState_ = mainState;
    }

    bool start()
    {
        pthread_attr_t attr;
        if (pthread_attr_init(&attr) != 0) return false;
        const size_t stackSize = std::max<size_t>(stackLimitBytes_ + 1024 * 1024, 2 * 1024 * 1024);
        pthread_attr_setstacksize(&attr, stackSize);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        auto* holder = new std::shared_ptr<PluginSession>(shared_from_this());
        pthread_t tid;
        int rc = pthread_create(&tid, &attr, &PluginSession::ThreadEntry, holder);
        pthread_attr_destroy(&attr);
        if (rc != 0) {
            delete holder;
            return false;
        }
        return true;
    }

    void enqueue(SessionJob job)
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            job.generation = cancelGen_.load();
            jobs_.push_back(std::move(job));
        }
        cv_.notify_all();
    }

    bool resolveHostCall(int64_t callId, bool ok, HostPayload response)
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = pendingCalls_.find(callId);
            if (it == pendingCalls_.end()) return false;
            it->second.done = true;
            it->second.ok = ok;
            it->second.response = std::move(response);
        }
        cv_.notify_all();
        return true;
    }

    void cancel()
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            cancelGen_.fetch_add(1);
            if (activeEngine_) {
                activeEngine_->notifyInterrupt();
            }
        }
        cv_.notify_all();
    }

    void close()
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            closing_.store(true);
        }
        cancel();
    }

private:
    static void* ThreadEntry(void* arg)
    {
        auto* holder = static_cast<std::shared_ptr<PluginSession>*>(arg);
        std::shared_ptr<PluginSession> self = *holder;
        delete holder;
        self->runLoop();
        return nullptr;
    }

    bool isAborted(int64_t jobGen) const
    {
        return closing_.load() || cancelGen_.load() != jobGen;
    }

    void runLoop()
    {
        std::unique_ptr<GuestEngine> engine =
            runtimeKind_ == "python" ? CreatePocketPyGuest() : CreateQuickJsGuest();
        std::string initErr;
        int64_t currentGen = 0;
        double currentHostWaitMs = 0;
        int currentHostCalls = 0;

        auto invoker = [&](const std::string& method,
                           const HostPayload& req,
                           HostPayload& resp,
                           std::string& errOut) -> bool {
            if (isAborted(currentGen)) {
                errOut = "plugin execution cancelled";
                return false;
            }
            int64_t callId = 0;
            {
                std::lock_guard<std::mutex> lock(mutex_);
                callId = nextCallId_++;
                pendingCalls_[callId] = PendingHostCall {};
            }
            auto* msg = new WireMessage();
            msg->kind = WireKind::HostCall;
            msg->sessionId = id_;
            msg->id = callId;
            msg->method = method;
            msg->payload = req;
            if (napi_call_threadsafe_function(tsfn_, msg, napi_tsfn_nonblocking) != napi_ok) {
                delete msg;
                std::lock_guard<std::mutex> lock(mutex_);
                pendingCalls_.erase(callId);
                errOut = "host unavailable";
                return false;
            }

            const auto waitStart = Clock::now();
            PendingHostCall settled;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                cv_.wait_until(
                    lock,
                    waitStart + std::chrono::milliseconds(hostTimeoutMs_),
                    [&]() { return pendingCalls_[callId].done || isAborted(currentGen); });
                settled = std::move(pendingCalls_[callId]);
                pendingCalls_.erase(callId);
            }
            currentHostWaitMs += ToMillis(Clock::now() - waitStart);
            currentHostCalls++;

            if (!settled.done) {
                errOut = isAborted(currentGen) ? "plugin execution cancelled"
                                               : ("host call timed out: " + method);
                return false;
            }
            if (!settled.ok) {
                errOut = settled.response.metaJson.empty()
                    ? ("host call failed: " + method)
                    : settled.response.metaJson;
                return false;
            }
            resp = std::move(settled.response);
            return true;
        };

        const bool initialized = engine->initialize(
            pluginRoot_, memoryLimitBytes_, stackLimitBytes_, invoker, initErr);
        {
            std::lock_guard<std::mutex> lock(mutex_);
            activeEngine_ = initialized ? engine.get() : nullptr;
        }

        while (true) {
            SessionJob job;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                cv_.wait(lock, [&]() { return !jobs_.empty() || closing_.load(); });
                if (jobs_.empty() && closing_.load()) break;
                job = std::move(jobs_.front());
                jobs_.pop_front();
            }

            SessionOutcome outcome;
            if (isAborted(job.generation)) {
                outcome.cancelled = true;
                outcome.error = "plugin execution cancelled";
            } else if (!initialized) {
                outcome.error = initErr.empty() ? "failed to initialize guest runtime" : initErr;
            } else {
                currentGen = job.generation;
                currentHostWaitMs = 0;
                currentHostCalls = 0;
                const auto started = Clock::now();
                bool ok = false;
                if (job.kind == JobKind::LoadEntry) {
                    ok = engine->loadEntry(
                        job.target, job.cpuTimeoutMs, outcome.error, outcome.timedOut, outcome.cancelled);
                    if (ok) outcome.output.metaJson = "true";
                } else {
                    ok = engine->invoke(
                        job.target, job.input, job.cpuTimeoutMs, outcome.output,
                        outcome.error, outcome.timedOut, outcome.cancelled);
                }
                outcome.success = ok;
                outcome.wallMs = ToMillis(Clock::now() - started);
                outcome.hostWaitMs = currentHostWaitMs;
                outcome.cpuMs = std::max(0.0, outcome.wallMs - currentHostWaitMs);
                outcome.hostCalls = currentHostCalls;
                engine->collectGarbage();
                outcome.memoryBytes = engine->memoryUsageBytes();
            }

            auto* doneMsg = new WireMessage();
            doneMsg->kind = WireKind::JobDone;
            doneMsg->sessionId = id_;
            doneMsg->id = job.id;
            doneMsg->outcome = std::move(outcome);
            if (napi_call_threadsafe_function(tsfn_, doneMsg, napi_tsfn_nonblocking) != napi_ok) {
                delete doneMsg;
            }
        }

        {
            std::lock_guard<std::mutex> lock(mutex_);
            activeEngine_ = nullptr;
        }
        engine.reset();
        napi_release_threadsafe_function(tsfn_, napi_tsfn_release);
    }

    int64_t id_ = 0;
    std::string runtimeKind_;
    std::string pluginRoot_;
    size_t memoryLimitBytes_ = 64 * 1024 * 1024;
    size_t stackLimitBytes_ = 1024 * 1024;
    int hostTimeoutMs_ = 60000;

    napi_threadsafe_function tsfn_ = nullptr;
    MainThreadState* mainState_ = nullptr;

    std::mutex mutex_;
    std::condition_variable cv_;
    std::deque<SessionJob> jobs_;
    std::unordered_map<int64_t, PendingHostCall> pendingCalls_;
    int64_t nextCallId_ = 1;
    std::atomic<int64_t> cancelGen_ { 0 };
    std::atomic<bool> closing_ { false };
    GuestEngine* activeEngine_ = nullptr;
};

std::mutex g_sessionsMutex;
std::unordered_map<int64_t, std::shared_ptr<PluginSession>> g_sessions;
int64_t g_nextSessionId = 1;
int64_t g_nextJobId = 1;

std::shared_ptr<PluginSession> FindSession(int64_t id)
{
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    auto it = g_sessions.find(id);
    return it == g_sessions.end() ? nullptr : it->second;
}

std::string ReadNapiString(napi_env env, napi_value value)
{
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok) return "";
    std::string out(len, '\0');
    napi_get_value_string_utf8(env, value, &out[0], len + 1, &len);
    return out;
}

bool ReadOptionalBytes(napi_env env, napi_value value, HostPayload& payload, std::string& errOut)
{
    if (!value) return true;
    napi_valuetype vt = napi_undefined;
    napi_typeof(env, value, &vt);
    if (vt == napi_undefined || vt == napi_null) return true;

    bool isTyped = false;
    napi_is_typedarray(env, value, &isTyped);
    if (isTyped) {
        napi_typedarray_type taType;
        size_t len = 0;
        void* data = nullptr;
        napi_value ab = nullptr;
        size_t offset = 0;
        if (napi_get_typedarray_info(env, value, &taType, &len, &data, &ab, &offset) != napi_ok) {
            errOut = "invalid TypedArray";
            return false;
        }
        if (len > MAX_PLUGIN_BINARY_BYTES) {
            errOut = "binary payload exceeds 32 MiB limit";
            return false;
        }
        payload.hasBytes = true;
        if (len > 0 && data) {
            auto* bytesPtr = static_cast<const uint8_t*>(data);
            payload.bytes.assign(bytesPtr, bytesPtr + len);
        }
        return true;
    }

    bool isAb = false;
    napi_is_arraybuffer(env, value, &isAb);
    if (isAb) {
        void* data = nullptr;
        size_t len = 0;
        if (napi_get_arraybuffer_info(env, value, &data, &len) != napi_ok) {
            errOut = "invalid ArrayBuffer";
            return false;
        }
        if (len > MAX_PLUGIN_BINARY_BYTES) {
            errOut = "binary payload exceeds 32 MiB limit";
            return false;
        }
        payload.hasBytes = true;
        if (len > 0 && data) {
            auto* bytesPtr = static_cast<const uint8_t*>(data);
            payload.bytes.assign(bytesPtr, bytesPtr + len);
        }
        return true;
    }

    errOut = "expected Uint8Array or ArrayBuffer";
    return false;
}

napi_value CreateArrayBufferCopy(napi_env env, const std::vector<uint8_t>& bytes)
{
    void* outData = nullptr;
    napi_value ab = nullptr;
    if (napi_create_arraybuffer(env, bytes.size(), &outData, &ab) != napi_ok) return nullptr;
    if (!bytes.empty() && outData) {
        std::memcpy(outData, bytes.data(), bytes.size());
    }
    return ab;
}

napi_value BuildOutcomeObject(napi_env env, const SessionOutcome& outcome)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);

    auto setBool = [&](const char* k, bool v) {
        napi_value val;
        napi_get_boolean(env, v, &val);
        napi_set_named_property(env, obj, k, val);
    };
    auto setStr = [&](const char* k, const std::string& v) {
        napi_value val;
        napi_create_string_utf8(env, v.c_str(), v.size(), &val);
        napi_set_named_property(env, obj, k, val);
    };
    auto setNum = [&](const char* k, double v) {
        napi_value val;
        napi_create_double(env, v, &val);
        napi_set_named_property(env, obj, k, val);
    };

    setBool("success", outcome.success);
    setStr("metaJson", outcome.output.metaJson);
    setStr("error", outcome.error);
    setBool("timedOut", outcome.timedOut);
    setBool("cancelled", outcome.cancelled);
    setNum("cpuMs", outcome.cpuMs);
    setNum("wallMs", outcome.wallMs);
    setNum("hostWaitMs", outcome.hostWaitMs);
    setNum("hostCalls", static_cast<double>(outcome.hostCalls));
    setNum("memoryBytes", static_cast<double>(outcome.memoryBytes));

    if (outcome.output.hasBytes) {
        napi_value ab = CreateArrayBufferCopy(env, outcome.output.bytes);
        if (ab) napi_set_named_property(env, obj, "bytes", ab);
    }
    return obj;
}

void CallArkTsFromSession(napi_env env, napi_value jsCb, void* context, void* data)
{
    auto* state = static_cast<MainThreadState*>(context);
    std::unique_ptr<WireMessage> msg(static_cast<WireMessage*>(data));
    if (!env || !state || !msg) return;

    if (msg->kind == WireKind::HostCall) {
        if (!jsCb) {
            auto s = FindSession(msg->sessionId);
            if (s) {
                HostPayload errResp;
                errResp.metaJson = "host callback unavailable";
                s->resolveHostCall(msg->id, false, std::move(errResp));
            }
            return;
        }
        napi_value argv[4] {};
        napi_create_int64(env, msg->id, &argv[0]);
        napi_create_string_utf8(env, msg->method.c_str(), msg->method.size(), &argv[1]);
        napi_create_string_utf8(env, msg->payload.metaJson.c_str(), msg->payload.metaJson.size(), &argv[2]);
        if (msg->payload.hasBytes) {
            argv[3] = CreateArrayBufferCopy(env, msg->payload.bytes);
        } else {
            napi_get_undefined(env, &argv[3]);
        }
        napi_value global = nullptr;
        napi_get_global(env, &global);
        napi_value ignored = nullptr;
        if (napi_call_function(env, global, jsCb, 4, argv, &ignored) != napi_ok) {
            bool pending = false;
            if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
                napi_value cleared = nullptr;
                napi_get_and_clear_last_exception(env, &cleared);
            }
            auto s = FindSession(msg->sessionId);
            if (s) {
                HostPayload errResp;
                errResp.metaJson = "ArkTS host callback threw synchronously";
                s->resolveHostCall(msg->id, false, std::move(errResp));
            }
        }
        return;
    }

    auto it = state->deferreds.find(msg->id);
    if (it == state->deferreds.end()) return;
    napi_deferred deferred = it->second;
    // Erase before resolving so synchronous .then() continuations see idle state.
    state->deferreds.erase(it);
    napi_value resultObj = BuildOutcomeObject(env, msg->outcome);
    napi_resolve_deferred(env, deferred, resultObj);
}

void FinalizeMainState(napi_env env, void* finalizeData, void* /*hint*/)
{
    auto* state = static_cast<MainThreadState*>(finalizeData);
    if (!state) return;
    if (env) {
        for (auto& kv : state->deferreds) {
            SessionOutcome closedOutcome;
            closedOutcome.cancelled = true;
            closedOutcome.error = "session closed";
            napi_resolve_deferred(env, kv.second, BuildOutcomeObject(env, closedOutcome));
        }
    }
    delete state;
}

napi_value NapiSessionCreate(napi_env env, napi_callback_info info)
{
    size_t argc = 6;
    napi_value args[6] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 6) {
        napi_throw_type_error(env, nullptr, "sessionCreate expects 6 arguments");
        return nullptr;
    }

    std::string runtimeKind = ReadNapiString(env, args[0]);
    std::string pluginRoot = ReadNapiString(env, args[1]);
    int64_t memBytes = 64 * 1024 * 1024;
    int64_t stackBytes = 1024 * 1024;
    int32_t hostTimeoutMs = 60000;
    napi_get_value_int64(env, args[2], &memBytes);
    napi_get_value_int64(env, args[3], &stackBytes);
    napi_get_value_int32(env, args[4], &hostTimeoutMs);

    size_t clampedMem = static_cast<size_t>(std::clamp<int64_t>(memBytes, 4 * 1024 * 1024, 256 * 1024 * 1024));
    size_t clampedStack = static_cast<size_t>(std::clamp<int64_t>(stackBytes, 128 * 1024, 8 * 1024 * 1024));
    int clampedHostTimeout = std::clamp<int32_t>(hostTimeoutMs, 500, 600000);

    int64_t id = 0;
    {
        std::lock_guard<std::mutex> lock(g_sessionsMutex);
        id = g_nextSessionId++;
    }

    auto session = std::make_shared<PluginSession>(
        id, runtimeKind, pluginRoot, clampedMem, clampedStack, clampedHostTimeout);
    auto* mainState = new MainThreadState { id, {} };

    napi_value resName = nullptr;
    napi_create_string_utf8(env, "PluginSessionTSFN", NAPI_AUTO_LENGTH, &resName);
    napi_threadsafe_function tsfn = nullptr;
    if (napi_create_threadsafe_function(
            env, args[5], nullptr, resName, 0, 1,
            mainState, &FinalizeMainState, mainState, &CallArkTsFromSession, &tsfn) != napi_ok) {
        delete mainState;
        napi_throw_error(env, nullptr, "failed to create threadsafe function");
        return nullptr;
    }

    session->attach(tsfn, mainState);
    {
        std::lock_guard<std::mutex> lock(g_sessionsMutex);
        g_sessions[id] = session;
    }
    if (!session->start()) {
        {
            std::lock_guard<std::mutex> lock(g_sessionsMutex);
            g_sessions.erase(id);
        }
        napi_release_threadsafe_function(tsfn, napi_tsfn_release);
        napi_throw_error(env, nullptr, "failed to spawn plugin session thread");
        return nullptr;
    }

    napi_value outId = nullptr;
    napi_create_int64(env, id, &outId);
    return outId;
}

napi_value NapiSessionLoadEntry(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t sessionId = 0;
    int32_t cpuTimeoutMs = 5000;
    napi_get_value_int64(env, args[0], &sessionId);
    std::string entryPath = ReadNapiString(env, args[1]);
    napi_get_value_int32(env, args[2], &cpuTimeoutMs);

    auto session = FindSession(sessionId);
    if (!session) {
        napi_throw_error(env, nullptr, "plugin session not found");
        return nullptr;
    }

    napi_deferred deferred = nullptr;
    napi_value promise = nullptr;
    napi_create_promise(env, &deferred, &promise);

    int64_t jobId = g_nextJobId++;
    session->mainState()->deferreds[jobId] = deferred;

    SessionJob job;
    job.id = jobId;
    job.kind = JobKind::LoadEntry;
    job.target = std::move(entryPath);
    job.cpuTimeoutMs = std::clamp<int32_t>(cpuTimeoutMs, 50, 120000);
    session->enqueue(std::move(job));
    return promise;
}

napi_value NapiSessionInvoke(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t sessionId = 0;
    int32_t cpuTimeoutMs = 3000;
    napi_get_value_int64(env, args[0], &sessionId);
    std::string exportName = ReadNapiString(env, args[1]);
    std::string metaJson = ReadNapiString(env, args[2]);
    napi_get_value_int32(env, args[4], &cpuTimeoutMs);

    auto session = FindSession(sessionId);
    if (!session) {
        napi_throw_error(env, nullptr, "plugin session not found");
        return nullptr;
    }

    SessionJob job;
    job.kind = JobKind::Invoke;
    job.target = std::move(exportName);
    job.input.metaJson = std::move(metaJson);
    job.cpuTimeoutMs = std::clamp<int32_t>(cpuTimeoutMs, 50, 120000);
    std::string binErr;
    if (!ReadOptionalBytes(env, args[3], job.input, binErr)) {
        napi_throw_type_error(env, nullptr, binErr.c_str());
        return nullptr;
    }

    napi_deferred deferred = nullptr;
    napi_value promise = nullptr;
    napi_create_promise(env, &deferred, &promise);

    int64_t jobId = g_nextJobId++;
    job.id = jobId;
    session->mainState()->deferreds[jobId] = deferred;
    session->enqueue(std::move(job));
    return promise;
}

napi_value NapiSessionResolve(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t sessionId = 0;
    int64_t callId = 0;
    bool ok = false;
    napi_get_value_int64(env, args[0], &sessionId);
    napi_get_value_int64(env, args[1], &callId);
    napi_get_value_bool(env, args[2], &ok);

    HostPayload resp;
    resp.metaJson = ReadNapiString(env, args[3]);
    std::string binErr;
    if (argc >= 5 && !ReadOptionalBytes(env, args[4], resp, binErr)) {
        ok = false;
        resp = HostPayload {};
        resp.metaJson = binErr;
    }

    auto session = FindSession(sessionId);
    bool resolved = session ? session->resolveHostCall(callId, ok, std::move(resp)) : false;
    napi_value out = nullptr;
    napi_get_boolean(env, resolved, &out);
    return out;
}

napi_value NapiSessionCancel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t sessionId = 0;
    napi_get_value_int64(env, args[0], &sessionId);
    auto session = FindSession(sessionId);
    if (session) session->cancel();
    napi_value undef = nullptr;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value NapiSessionRelease(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t sessionId = 0;
    napi_get_value_int64(env, args[0], &sessionId);
    std::shared_ptr<PluginSession> session;
    {
        std::lock_guard<std::mutex> lock(g_sessionsMutex);
        auto it = g_sessions.find(sessionId);
        if (it != g_sessions.end()) {
            session = it->second;
            g_sessions.erase(it);
        }
    }
    if (session) session->close();
    napi_value undef = nullptr;
    napi_get_undefined(env, &undef);
    return undef;
}

} // namespace

void DefinePluginSessionExports(napi_env env, napi_value exports)
{
    napi_property_descriptor props[] = {
        { "sessionCreate", nullptr, NapiSessionCreate, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sessionLoadEntry", nullptr, NapiSessionLoadEntry, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sessionInvoke", nullptr, NapiSessionInvoke, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sessionResolve", nullptr, NapiSessionResolve, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sessionCancel", nullptr, NapiSessionCancel, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sessionRelease", nullptr, NapiSessionRelease, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(props) / sizeof(props[0]), props);
}

} // namespace qyplugin
