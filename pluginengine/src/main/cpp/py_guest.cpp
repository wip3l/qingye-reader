// Copyright (c) 2026 qingye-plugin-reader contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "guest_engine.h"

#ifndef PK_ENABLE_THREAD
#define PK_ENABLE_THREAD 1
#endif
#ifndef PK_ENABLE_OS
#define PK_ENABLE_OS 0
#endif
#ifndef PK_NO_EXPORT_C_API
#define PK_NO_EXPORT_C_API 1
#endif
#include "pocketpy.h"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>

namespace qyplugin {

namespace {

using Clock = std::chrono::steady_clock;

// Serializes active PocketPy bytecode execution across sessions because PocketPy v1.4 shares
// pool64/pool128 and StrName interning tables, while releasing the lock during blocking host I/O!
std::mutex g_pyVmMutex;

struct PyHardAbort {
    bool timedOut = false;
    bool cancelled = false;
    bool outOfMemory = false;
};

const char* kPyPrelude = R"PY(
import json
import sys
import _qingye_native

def _raw_call(method, meta=None, data_bytes=None):
    payload = json.dumps(meta if meta is not None else {})
    res_meta, res_bytes = _qingye_native.host_call(method, payload, data_bytes)
    parsed = json.loads(res_meta) if res_meta else None
    if res_bytes is not None:
        if isinstance(parsed, dict):
            parsed['bytes'] = res_bytes
            return parsed
        return res_bytes
    return parsed

class _EnvNamespace:
    def info(self):
        return _raw_call('env.info', {})

class _ConfigNamespace:
    def get(self, key=''):
        return _raw_call('config.get', {'key': key or ''})
    def set(self, key, value):
        return _raw_call('config.set', {'key': str(key), 'value': value})

class _SecretsNamespace:
    def get(self, key):
        return _raw_call('secrets.get', {'key': str(key)})
    def set(self, key, value):
        return _raw_call('secrets.set', {'key': str(key), 'value': str(value or '')})

class _KvNamespace:
    def get(self, key, fallback=None):
        val = _raw_call('kv.get', {'key': str(key)})
        return fallback if val is None else val
    def set(self, key, value):
        return _raw_call('kv.set', {'key': str(key), 'value': value})
    def delete(self, key):
        return _raw_call('kv.delete', {'key': str(key)})
    def keys(self):
        return _raw_call('kv.keys', {})

class _FsNamespace:
    def read_text(self, path):
        return _raw_call('fs.readText', {'path': str(path)})
    readText = read_text

    def read_bytes(self, path):
        res = _raw_call('fs.readBytes', {'path': str(path)})
        if isinstance(res, bytes):
            return res
        if isinstance(res, dict) and 'bytes' in res:
            return res['bytes']
        return b''
    readBytes = read_bytes

    def write_text(self, path, text):
        return _raw_call('fs.writeText', {'path': str(path), 'text': str(text or '')})
    writeText = write_text

    def write_bytes(self, path, data):
        return _raw_call('fs.writeBytes', {'path': str(path)}, data)
    writeBytes = write_bytes

    def list(self, path=''):
        return _raw_call('fs.list', {'path': str(path)})

    def remove(self, path):
        return _raw_call('fs.remove', {'path': str(path)})

class _HttpNamespace:
    def request(self, options=None, body_bytes=None):
        return _raw_call('http.request', options or {}, body_bytes)
    def get(self, url, options=None):
        opts = dict(options) if options else {}
        opts['url'] = str(url)
        opts['method'] = 'GET'
        return _raw_call('http.request', opts)
    def post(self, url, body=None, options=None):
        opts = dict(options) if options else {}
        opts['url'] = str(url)
        opts['method'] = 'POST'
        if isinstance(body, bytes):
            return _raw_call('http.request', opts, body)
        opts['body'] = body
        return _raw_call('http.request', opts)

class _ParserNamespace:
    def css(self, html, rule):
        return _raw_call('parser.css', {'html': str(html or ''), 'rule': str(rule)})
    def css_all(self, html, rule):
        return _raw_call('parser.cssAll', {'html': str(html or ''), 'rule': str(rule)})
    cssAll = css_all
    def xpath(self, html, expr):
        return _raw_call('parser.xpath', {'html': str(html or ''), 'expr': str(expr)})
    def jsonpath(self, data, expr):
        raw = data if isinstance(data, str) else json.dumps(data)
        return _raw_call('parser.jsonpath', {'json': raw, 'expr': str(expr)})
    def regex(self, text, pattern, replacement=None):
        return _raw_call('parser.regex', {'text': str(text or ''), 'pattern': str(pattern), 'replacement': replacement})

class _CryptoNamespace:
    def hash(self, algorithm, data):
        if isinstance(data, bytes):
            return _raw_call('crypto.hash', {'algorithm': str(algorithm)}, data)
        return _raw_call('crypto.hash', {'algorithm': str(algorithm), 'text': str(data)})
    def hmac(self, algorithm, key, data):
        meta = {'algorithm': str(algorithm)}
        if isinstance(key, dict):
            if 'base64' in key:
                meta['keyBase64'] = str(key['base64'])
            elif 'hex' in key:
                meta['keyHex'] = str(key['hex'])
            else:
                meta['key'] = str(key.get('utf8', ''))
        else:
            meta['key'] = str(key)
        if isinstance(data, bytes):
            return _raw_call('crypto.hmac', meta, data)
        meta['text'] = str(data)
        return _raw_call('crypto.hmac', meta)
    def aes_encrypt(self, options, plain_bytes):
        return _raw_call('crypto.aesEncrypt', options or {}, plain_bytes)
    aesEncrypt = aes_encrypt
    def aes_decrypt(self, options, cipher_bytes):
        return _raw_call('crypto.aesDecrypt', options or {}, cipher_bytes)
    aesDecrypt = aes_decrypt
    def base64_encode(self, data):
        if isinstance(data, bytes):
            return _raw_call('crypto.base64Encode', {}, data)
        return _raw_call('crypto.base64Encode', {'text': str(data)})
    base64Encode = base64_encode
    def base64_decode(self, b64_text):
        res = _raw_call('crypto.base64Decode', {'text': str(b64_text or '')})
        if isinstance(res, bytes):
            return res
        if isinstance(res, dict) and 'bytes' in res:
            return res['bytes']
        return b''
    base64Decode = base64_decode

class _ReaderNamespace:
    def get_book_context(self):
        return _raw_call('reader.getBookContext', {})
    getBookContext = get_book_context
    def get_annotations(self, chapter_index=-1):
        return _raw_call('reader.getAnnotations', {'chapterIndex': int(chapter_index)})
    getAnnotations = get_annotations
    def add_annotation(self, spec):
        return _raw_call('reader.addAnnotation', spec or {})
    addAnnotation = add_annotation

class _SourceNamespace:
    def get_summary(self):
        return _raw_call('source.getSummary', {})
    getSummary = get_summary
    def open_route(self, target):
        return _raw_call('source.openRoute', {'target': str(target or '')})
    openRoute = open_route

class _UiNamespace:
    def toast(self, message):
        return _raw_call('ui.toast', {'message': str(message or '')})
    def open_panel(self, spec):
        return _raw_call('ui.openPanel', spec or {})
    openPanel = open_panel
    def post_panel_message(self, data):
        return _raw_call('ui.postPanelMessage', {'data': data})
    postPanelMessage = post_panel_message
    def emit_search(self, items):
        return _raw_call('ui.emitSearch', {'items': list(items) if items else []})
    emitSearch = emit_search
    def verify_web(self, spec):
        return _raw_call('ui.verifyWeb', spec or {})
    verifyWeb = verify_web

class _LogNamespace:
    def info(self, *args):
        return _raw_call('log.write', {'level': 'info', 'message': ' '.join([str(x) for x in args])})
    def warn(self, *args):
        return _raw_call('log.write', {'level': 'warn', 'message': ' '.join([str(x) for x in args])})
    def error(self, *args):
        return _raw_call('log.write', {'level': 'error', 'message': ' '.join([str(x) for x in args])})

class _QingyeModule:
    raw_call = staticmethod(_raw_call)
    env = _EnvNamespace()
    config = _ConfigNamespace()
    secrets = _SecretsNamespace()
    kv = _KvNamespace()
    fs = _FsNamespace()
    http = _HttpNamespace()
    parser = _ParserNamespace()
    crypto = _CryptoNamespace()
    reader = _ReaderNamespace()
    source = _SourceNamespace()
    ui = _UiNamespace()
    log = _LogNamespace()

def __qy_dispatch(fn, json_arg, bin_arg):
    arg = json.loads(json_arg) if json_arg else {}
    res = fn(arg) if bin_arg is None else fn(arg, bin_arg)
    if isinstance(res, bytes):
        return ('null', res)
    if isinstance(res, dict) and '__bytes' in res and isinstance(res['__bytes'], bytes):
        b = res['__bytes']
        copy_dict = {}
        for k in res:
            if k != '__bytes':
                copy_dict[k] = res[k]
        return (json.dumps(copy_dict), b)
    return (json.dumps(res), None)
)PY";

class PocketPyGuestEngine;
thread_local PocketPyGuestEngine* t_activePyGuest = nullptr;

class PocketPyGuestEngine final : public GuestEngine {
public:
    ~PocketPyGuestEngine() override
    {
        std::lock_guard<std::mutex> lock(g_pyVmMutex);
        delete vm_;
        vm_ = nullptr;
    }

    bool initialize(
        const std::string& pluginRoot,
        size_t memoryLimitBytes,
        size_t /*stackLimitBytes*/,
        HostInvoker invoker,
        std::string& errorOut) override
    {
        pluginRoot_ = pluginRoot;
        memoryLimitBytes_ = memoryLimitBytes;
        invoker_ = std::move(invoker);

        std::lock_guard<std::mutex> lock(g_pyVmMutex);
        t_activePyGuest = this;
        try {
            vm_ = new pkpy::VM(false);
            vm_->_ceval_on_step = &PocketPyGuestEngine::OnStep;
            vm_->_import_handler = &PocketPyGuestEngine::OnImport;
            vm_->_stdout = &PocketPyGuestEngine::OnStdout;
            vm_->_stderr = &PocketPyGuestEngine::OnStderr;

            pkpy::PyVar nativeMod = vm_->new_module("_qingye_native");
            vm_->bind_func(nativeMod, "host_call", 3, &PocketPyGuestEngine::NativeHostCall);

            deadline_ = Clock::now() + std::chrono::milliseconds(5000);
            stepCount_ = 0;
            pkpy::CodeObject_ preCo = vm_->compile(kPyPrelude, "<qingye-py-prelude>", pkpy::EXEC_MODE);
            vm_->_exec(preCo, vm_->_main);

            pkpy::PyVar qyMod = vm_->new_module("qingye");
            pkpy::PyVar clsObj = vm_->_main->attr().try_get("_QingyeModule");
            pkpy::PyVar inst = vm_->call(clsObj);
            for (const char* attrName : {
                     "raw_call", "env", "config", "secrets", "kv", "fs",
                     "http", "parser", "crypto", "reader", "source", "ui", "log" }) {
                qyMod->attr().set(attrName, vm_->getattr(inst, attrName));
            }
        } catch (const pkpy::Exception& e) {
            errorOut = e.summary().str();
            t_activePyGuest = nullptr;
            return false;
        } catch (const std::exception& e) {
            errorOut = e.what();
            t_activePyGuest = nullptr;
            return false;
        }
        t_activePyGuest = nullptr;
        return true;
    }

    bool loadEntry(
        const std::string& entryRelPath,
        int cpuTimeoutMs,
        std::string& errorOut,
        bool& timedOut,
        bool& cancelled) override
    {
        std::string cleanRel;
        if (!NormalizeSafeRelativePath("", entryRelPath, cleanRel)) {
            errorOut = "invalid Python entry path: " + entryRelPath;
            return false;
        }
        std::string source;
        if (!ReadPluginTextFile(pluginRoot_, cleanRel, source, errorOut)) {
            return false;
        }

        std::lock_guard<std::mutex> lock(g_pyVmMutex);
        t_activePyGuest = this;
        clearInterrupt();
        stepCount_ = 0;
        deadline_ = Clock::now() + std::chrono::milliseconds(cpuTimeoutMs);

        try {
            pkpy::CodeObject_ co = vm_->compile(source, cleanRel, pkpy::EXEC_MODE);
            vm_->_exec(co, vm_->_main);
            t_activePyGuest = nullptr;
            return true;
        } catch (const PyHardAbort& ab) {
            ResetVmStacks();
            timedOut = ab.timedOut;
            cancelled = ab.cancelled;
            errorOut = ab.cancelled ? "plugin execution cancelled"
                : (ab.outOfMemory ? "Python plugin exceeded memory limit" : "plugin CPU budget exceeded");
        } catch (const pkpy::Exception& e) {
            ResetVmStacks();
            errorOut = e.summary().str();
        } catch (const std::exception& e) {
            ResetVmStacks();
            errorOut = e.what();
        }
        t_activePyGuest = nullptr;
        return false;
    }

    bool invoke(
        const std::string& exportName,
        const HostPayload& input,
        int cpuTimeoutMs,
        HostPayload& output,
        std::string& errorOut,
        bool& timedOut,
        bool& cancelled) override
    {
        std::lock_guard<std::mutex> lock(g_pyVmMutex);
        t_activePyGuest = this;
        clearInterrupt();
        stepCount_ = 0;
        deadline_ = Clock::now() + std::chrono::milliseconds(cpuTimeoutMs);

        try {
            pkpy::VM* vm = vm_;
            pkpy::PyVar fn = vm->_main->attr().try_get(exportName.c_str());
            if (fn == nullptr) {
                errorOut = "exported Python function not found: " + exportName;
                t_activePyGuest = nullptr;
                return false;
            }
            pkpy::PyVar dispatcher = vm->_main->attr().try_get("__qy_dispatch");
            const std::string& jsonStr = input.metaJson.empty() ? "{}" : input.metaJson;
            pkpy::PyVar pyJson = pkpy::VAR(pkpy::Str(jsonStr));
            pkpy::PyVar pyBin = vm->None;
            if (input.hasBytes) {
                auto* copy = new unsigned char[input.bytes.size() ? input.bytes.size() : 1];
                if (!input.bytes.empty()) {
                    std::memcpy(copy, input.bytes.data(), input.bytes.size());
                }
                pyBin = pkpy::VAR(pkpy::Bytes(copy, static_cast<int>(input.bytes.size())));
            }

            pkpy::PyVar tupleRes = vm->call(dispatcher, fn, pyJson, pyBin);
            pkpy::Tuple& tup = pkpy::CAST(pkpy::Tuple&, tupleRes);
            output = HostPayload {};
            output.metaJson = pkpy::CAST(pkpy::Str&, tup[0]).str();
            if (tup[1] != vm->None) {
                pkpy::Bytes& b = pkpy::CAST(pkpy::Bytes&, tup[1]);
                if (static_cast<size_t>(b.size()) > MAX_PLUGIN_BINARY_BYTES) {
                    errorOut = "Python binary return exceeds 32 MiB limit";
                    t_activePyGuest = nullptr;
                    return false;
                }
                output.hasBytes = true;
                if (b.size() > 0) {
                    output.bytes.assign(b.data(), b.data() + b.size());
                }
            }
            t_activePyGuest = nullptr;
            return true;
        } catch (const PyHardAbort& ab) {
            ResetVmStacks();
            timedOut = ab.timedOut;
            cancelled = ab.cancelled;
            errorOut = ab.cancelled ? "plugin execution cancelled"
                : (ab.outOfMemory ? "Python plugin exceeded memory limit" : "plugin CPU budget exceeded");
        } catch (const pkpy::Exception& e) {
            ResetVmStacks();
            errorOut = e.summary().str();
        } catch (const std::exception& e) {
            ResetVmStacks();
            errorOut = e.what();
        }
        t_activePyGuest = nullptr;
        return false;
    }

    void notifyInterrupt() override
    {
        interrupted_.store(true);
    }

    void clearInterrupt() override
    {
        interrupted_.store(false);
    }

    void collectGarbage() override
    {
        std::lock_guard<std::mutex> lock(g_pyVmMutex);
        if (vm_) vm_->heap.collect();
    }

    size_t memoryUsageBytes() const override
    {
        std::lock_guard<std::mutex> lock(g_pyVmMutex);
        return EstimateHeapBytesUnlocked();
    }

private:
    size_t EstimateHeapBytesUnlocked() const
    {
        if (!vm_) return 0;
        // Approximate managed object overhead (~96 bytes per live/nursery PyObject + interned frames)
        return (vm_->heap.gen.size() + vm_->heap._no_gc.size()) * 96;
    }

    void ResetVmStacks()
    {
        if (!vm_) return;
        vm_->callstack.clear();
        vm_->s_data.clear();
        vm_->heap._gc_lock_counter = 0;
    }

    static void OnStep(pkpy::VM* /*vm*/, pkpy::Frame* /*frame*/, pkpy::Bytecode /*bc*/)
    {
        PocketPyGuestEngine* self = t_activePyGuest;
        if (!self) return;
        if ((++self->stepCount_ & 0x3FF) != 0) return;

        if (self->interrupted_.load()) {
            throw PyHardAbort { false, true, false };
        }
        if (Clock::now() >= self->deadline_) {
            throw PyHardAbort { true, false, false };
        }
        if (self->EstimateHeapBytesUnlocked() > self->memoryLimitBytes_) {
            throw PyHardAbort { false, false, true };
        }
    }

    static unsigned char* OnImport(const char* name, int* outSize)
    {
        PocketPyGuestEngine* self = t_activePyGuest;
        if (!self || !name || !outSize) return nullptr;
        std::string rel(name);
        for (char& ch : rel) {
            if (ch == '\\') ch = '/';
        }
        std::string content;
        std::string err;
        if (!ReadPluginTextFile(self->pluginRoot_, rel, content, err)) {
            return nullptr;
        }
        auto* buf = static_cast<unsigned char*>(std::malloc(content.size() ? content.size() : 1));
        if (!buf) return nullptr;
        if (!content.empty()) {
            std::memcpy(buf, content.data(), content.size());
        }
        *outSize = static_cast<int>(content.size());
        return buf;
    }

    static void OnStdout(const char* buf, int size)
    {
        PocketPyGuestEngine* self = t_activePyGuest;
        if (!self || size <= 0) return;
        std::string msg(buf, static_cast<size_t>(size));
        while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) msg.pop_back();
        if (msg.empty()) return;
        self->ForwardPrint("info", msg);
    }

    static void OnStderr(const char* buf, int size)
    {
        PocketPyGuestEngine* self = t_activePyGuest;
        if (!self || size <= 0) return;
        std::string msg(buf, static_cast<size_t>(size));
        while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) msg.pop_back();
        if (msg.empty()) return;
        self->ForwardPrint("error", msg);
    }

    void ForwardPrint(const char* level, const std::string& text)
    {
        std::string escaped;
        escaped.reserve(text.size() + 16);
        for (unsigned char c : text) {
            if (c == '\\') escaped += "\\\\";
            else if (c == '"') escaped += "\\\"";
            else if (c == '\n') escaped += "\\n";
            else if (c == '\r') escaped += "\\r";
            else if (c == '\t') escaped += "\\t";
            else if (c >= 0x20) escaped.push_back(static_cast<char>(c));
        }
        HostPayload req;
        req.metaJson = std::string("{\"level\":\"") + level + "\",\"message\":\"" + escaped + "\"}";
        HostPayload resp;
        std::string err;
        const auto waitStart = Clock::now();
        t_activePyGuest = nullptr;
        g_pyVmMutex.unlock();
        invoker_("log.write", req, resp, err);
        g_pyVmMutex.lock();
        t_activePyGuest = this;
        deadline_ += (Clock::now() - waitStart);
    }

    static pkpy::PyVar NativeHostCall(pkpy::VM* vm, pkpy::ArgsView args)
    {
        PocketPyGuestEngine* self = t_activePyGuest;
        if (!self) vm->RuntimeError("inactive Python plugin session");

        std::string method = pkpy::CAST(pkpy::Str&, args[0]).str();
        HostPayload req;
        req.metaJson = pkpy::CAST(pkpy::Str&, args[1]).str();
        if (args[2] != vm->None) {
            pkpy::Bytes& b = pkpy::CAST(pkpy::Bytes&, args[2]);
            if (static_cast<size_t>(b.size()) > MAX_PLUGIN_BINARY_BYTES) {
                vm->ValueError("binary payload exceeds 32 MiB limit");
            }
            req.hasBytes = true;
            if (b.size() > 0) {
                req.bytes.assign(b.data(), b.data() + b.size());
            }
        }

        HostPayload resp;
        std::string hostErr;
        const auto waitStart = Clock::now();
        // Release g_pyVmMutex while waiting for async ArkTS host work (network, DB, UI)
        t_activePyGuest = nullptr;
        g_pyVmMutex.unlock();
        const bool ok = self->invoker_(method, req, resp, hostErr);
        g_pyVmMutex.lock();
        t_activePyGuest = self;
        self->deadline_ += (Clock::now() - waitStart);

        if (self->interrupted_.load()) {
            throw PyHardAbort { false, true, false };
        }
        if (!ok) {
            vm->RuntimeError(hostErr.empty() ? ("host call failed: " + method) : hostErr);
        }

        pkpy::PyVar pyMeta = pkpy::VAR(pkpy::Str(resp.metaJson));
        pkpy::PyVar pyBytes = vm->None;
        if (resp.hasBytes) {
            auto* copy = new unsigned char[resp.bytes.size() ? resp.bytes.size() : 1];
            if (!resp.bytes.empty()) {
                std::memcpy(copy, resp.bytes.data(), resp.bytes.size());
            }
            pyBytes = pkpy::VAR(pkpy::Bytes(copy, static_cast<int>(resp.bytes.size())));
        }
        return pkpy::VAR(pkpy::Tuple(pyMeta, pyBytes));
    }

    std::string pluginRoot_;
    size_t memoryLimitBytes_ = 64 * 1024 * 1024;
    HostInvoker invoker_;
    pkpy::VM* vm_ = nullptr;
    uint64_t stepCount_ = 0;
    std::atomic<bool> interrupted_ { false };
    Clock::time_point deadline_ {};
};

} // namespace

std::unique_ptr<GuestEngine> CreatePocketPyGuest()
{
    return std::make_unique<PocketPyGuestEngine>();
}

} // namespace qyplugin
