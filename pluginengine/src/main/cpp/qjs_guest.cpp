// Copyright (c) 2026 qingye-plugin-reader contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "guest_engine.h"

extern "C" {
#include "cutils.h"
#include "libbf.h"
#include "quickjs.h"
}

#include <atomic>
#include <chrono>
#include <cstring>

namespace qyplugin {

namespace {

using Clock = std::chrono::steady_clock;

const char* kJsPrelude = R"JS(
(function(g) {
  const rawHost = g.__qy_host;
  delete g.__qy_host;

  class TextEncoder {
    get encoding() { return 'utf-8'; }
    encode(str = '') {
      const s = String(str);
      const out = [];
      for (let i = 0; i < s.length; i++) {
        let c = s.charCodeAt(i);
        if (c < 0x80) {
          out.push(c);
        } else if (c < 0x800) {
          out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
        } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
          const c2 = s.charCodeAt(i + 1);
          if (c2 >= 0xdc00 && c2 <= 0xdfff) {
            c = 0x10000 + (((c & 0x3ff) << 10) | (c2 & 0x3ff));
            i++;
            out.push(
              0xf0 | (c >> 18),
              0x80 | ((c >> 12) & 0x3f),
              0x80 | ((c >> 6) & 0x3f),
              0x80 | (c & 0x3f)
            );
          } else {
            out.push(0xef, 0xbf, 0xbd);
          }
        } else {
          out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
        }
      }
      return new Uint8Array(out);
    }
  }

  class TextDecoder {
    constructor(label = 'utf-8') {
      const norm = String(label || 'utf-8').toLowerCase();
      if (norm !== 'utf-8' && norm !== 'utf8') {
        throw new RangeError('Only utf-8 TextDecoder is supported in sandbox');
      }
    }
    get encoding() { return 'utf-8'; }
    decode(input) {
      if (!input) return '';
      const bytes = input instanceof Uint8Array
        ? input
        : (ArrayBuffer.isView(input)
          ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength)
          : new Uint8Array(input));
      let out = '';
      let i = 0;
      while (i < bytes.length) {
        const b0 = bytes[i++];
        if (b0 < 0x80) {
          out += String.fromCharCode(b0);
        } else if ((b0 & 0xe0) === 0xc0 && i < bytes.length) {
          const b1 = bytes[i++];
          out += String.fromCharCode(((b0 & 0x1f) << 6) | (b1 & 0x3f));
        } else if ((b0 & 0xf0) === 0xe0 && i + 1 < bytes.length) {
          const b1 = bytes[i++], b2 = bytes[i++];
          out += String.fromCharCode(((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f));
        } else if ((b0 & 0xf8) === 0xf0 && i + 2 < bytes.length) {
          const b1 = bytes[i++], b2 = bytes[i++], b3 = bytes[i++];
          const cp = (((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f)) - 0x10000;
          out += String.fromCharCode(0xd800 | (cp >> 10), 0xdc00 | (cp & 0x3ff));
        } else {
          out += '\ufffd';
        }
      }
      return out;
    }
  }

  class URLSearchParams {
    constructor(init = '') {
      this._pairs = [];
      if (typeof init === 'string') {
        const clean = init.startsWith('?') ? init.slice(1) : init;
        if (clean) {
          for (const part of clean.split('&')) {
            if (!part) continue;
            const idx = part.indexOf('=');
            const k = idx >= 0 ? part.slice(0, idx) : part;
            const v = idx >= 0 ? part.slice(idx + 1) : '';
            this._pairs.push([
              decodeURIComponent(k.replace(/\+/g, ' ')),
              decodeURIComponent(v.replace(/\+/g, ' '))
            ]);
          }
        }
      } else if (init && typeof init === 'object') {
        for (const [k, v] of Object.entries(init)) {
          this._pairs.push([String(k), String(v)]);
        }
      }
    }
    get(name) {
      const hit = this._pairs.find((p) => p[0] === String(name));
      return hit ? hit[1] : null;
    }
    getAll(name) {
      return this._pairs.filter((p) => p[0] === String(name)).map((p) => p[1]);
    }
    has(name) {
      return this._pairs.some((p) => p[0] === String(name));
    }
    set(name, value) {
      const k = String(name), v = String(value);
      let replaced = false;
      this._pairs = this._pairs.filter((p) => {
        if (p[0] !== k) return true;
        if (!replaced) { p[1] = v; replaced = true; return true; }
        return false;
      });
      if (!replaced) this._pairs.push([k, v]);
    }
    append(name, value) {
      this._pairs.push([String(name), String(value)]);
    }
    delete(name) {
      const k = String(name);
      this._pairs = this._pairs.filter((p) => p[0] !== k);
    }
    toString() {
      return this._pairs
        .map(([k, v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v))
        .join('&');
    }
  }

  if (!g.TextEncoder) g.TextEncoder = TextEncoder;
  if (!g.TextDecoder) g.TextDecoder = TextDecoder;
  if (!g.URLSearchParams) g.URLSearchParams = URLSearchParams;

  function toUint8(data) {
    if (data == null) return undefined;
    if (data instanceof Uint8Array) return data;
    if (data instanceof ArrayBuffer) return new Uint8Array(data);
    if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    throw new TypeError('Binary payload must be a Uint8Array or ArrayBuffer');
  }

  function call(method, meta = {}, bytes) {
    const bin = toUint8(bytes);
    const res = bin !== undefined
      ? rawHost(method, JSON.stringify(meta ?? {}), bin)
      : rawHost(method, JSON.stringify(meta ?? {}));
    const parsed = res.meta ? JSON.parse(res.meta) : null;
    if (res.bytes !== undefined) {
      const outBytes = new Uint8Array(res.bytes);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        Object.defineProperty(parsed, 'bytes', { value: outBytes, enumerable: true });
        return parsed;
      }
      return outBytes;
    }
    return parsed;
  }

  const qingye = {
    rawCall: call,
    env: Object.freeze({
      info: () => call('env.info', {})
    }),
    config: Object.freeze({
      get: (key) => call('config.get', { key: key ?? '' }),
      set: (key, value) => call('config.set', { key: String(key), value })
    }),
    secrets: Object.freeze({
      get: (key) => call('secrets.get', { key: String(key) }),
      set: (key, value) => call('secrets.set', { key: String(key), value: String(value ?? '') })
    }),
    kv: Object.freeze({
      get: (key, fallback = null) => {
        const val = call('kv.get', { key: String(key) });
        return val === undefined || val === null ? fallback : val;
      },
      set: (key, value) => call('kv.set', { key: String(key), value }),
      delete: (key) => call('kv.delete', { key: String(key) }),
      keys: () => call('kv.keys', {})
    }),
    fs: Object.freeze({
      readText: (path) => call('fs.readText', { path: String(path) }),
      readBytes: (path) => {
        const r = call('fs.readBytes', { path: String(path) });
        return r instanceof Uint8Array ? r : (r && r.bytes ? r.bytes : new Uint8Array(0));
      },
      writeText: (path, text) => call('fs.writeText', { path: String(path), text: String(text ?? '') }),
      writeBytes: (path, bytes) => call('fs.writeBytes', { path: String(path) }, bytes),
      list: (path = '') => call('fs.list', { path: String(path) }),
      remove: (path) => call('fs.remove', { path: String(path) })
    }),
    http: Object.freeze({
      request: (options, bodyBytes) => call('http.request', options || {}, bodyBytes),
      get: (url, options = {}) => call('http.request', Object.assign({}, options, { url: String(url), method: 'GET' })),
      post: (url, body, options = {}) => {
        if (body instanceof Uint8Array || body instanceof ArrayBuffer || ArrayBuffer.isView(body)) {
          return call('http.request', Object.assign({}, options, { url: String(url), method: 'POST' }), body);
        }
        return call('http.request', Object.assign({}, options, { url: String(url), method: 'POST', body }));
      }
    }),
    parser: Object.freeze({
      css: (html, rule) => call('parser.css', { html: String(html ?? ''), rule: String(rule) }),
      cssAll: (html, rule) => call('parser.cssAll', { html: String(html ?? ''), rule: String(rule) }),
      xpath: (html, expr) => call('parser.xpath', { html: String(html ?? ''), expr: String(expr) }),
      jsonpath: (json, expr) => call('parser.jsonpath', {
        json: typeof json === 'string' ? json : JSON.stringify(json),
        expr: String(expr)
      }),
      regex: (text, pattern, replacement) => call('parser.regex', {
        text: String(text ?? ''),
        pattern: String(pattern),
        replacement: replacement === undefined ? null : String(replacement)
      })
    }),
    crypto: Object.freeze({
      hash: (algorithm, data) => {
        if (typeof data === 'string') return call('crypto.hash', { algorithm, text: data });
        return call('crypto.hash', { algorithm }, data);
      },
      hmac: (algorithm, key, data) => {
        const meta = { algorithm };
        if (key && typeof key === 'object') {
          if (typeof key.base64 === 'string') meta.keyBase64 = key.base64;
          else if (typeof key.hex === 'string') meta.keyHex = key.hex;
          else if (typeof key.utf8 === 'string') meta.key = key.utf8;
          else meta.key = String(key);
        } else {
          meta.key = String(key ?? '');
        }
        if (typeof data === 'string') {
          meta.text = data;
          return call('crypto.hmac', meta);
        }
        return call('crypto.hmac', meta, data);
      },
      aesEncrypt: (options, plainBytes) => call('crypto.aesEncrypt', options || {}, plainBytes),
      aesDecrypt: (options, cipherBytes) => call('crypto.aesDecrypt', options || {}, cipherBytes),
      base64Encode: (data) => {
        if (typeof data === 'string') return call('crypto.base64Encode', { text: data });
        return call('crypto.base64Encode', {}, data);
      },
      base64Decode: (b64) => {
        const r = call('crypto.base64Decode', { text: String(b64 ?? '') });
        return r instanceof Uint8Array ? r : (r && r.bytes ? r.bytes : new Uint8Array(0));
      }
    }),
    reader: Object.freeze({
      getBookContext: () => call('reader.getBookContext', {}),
      getAnnotations: (chapterIndex = -1) => call('reader.getAnnotations', { chapterIndex }),
      addAnnotation: (spec) => call('reader.addAnnotation', spec || {})
    }),
    source: Object.freeze({
      getSummary: () => call('source.getSummary', {}),
      openRoute: (target) => call('source.openRoute', { target: String(target ?? '') })
    }),
    ui: Object.freeze({
      toast: (message) => call('ui.toast', { message: String(message ?? '') }),
      openPanel: (spec) => call('ui.openPanel', spec || {}),
      postPanelMessage: (data) => call('ui.postPanelMessage', { data }),
      emitSearch: (items) => call('ui.emitSearch', { items: Array.isArray(items) ? items : [] }),
      verifyWeb: (spec) => call('ui.verifyWeb', spec || {})
    }),
    log: Object.freeze({
      info: (...args) => call('log.write', { level: 'info', message: args.map(String).join(' ') }),
      warn: (...args) => call('log.write', { level: 'warn', message: args.map(String).join(' ') }),
      error: (...args) => call('log.write', { level: 'error', message: args.map(String).join(' ') })
    })
  };

  g.qingye = Object.freeze(qingye);
  g.console = Object.freeze({
    log: (...args) => qingye.log.info(...args),
    info: (...args) => qingye.log.info(...args),
    warn: (...args) => qingye.log.warn(...args),
    error: (...args) => qingye.log.error(...args)
  });
})(globalThis);
)JS";

std::string JsToStdString(JSContext* ctx, JSValueConst value)
{
    size_t len = 0;
    const char* raw = JS_ToCStringLen(ctx, &len, value);
    if (!raw) return "";
    std::string out(raw, len);
    JS_FreeCString(ctx, raw);
    return out;
}

std::string TakeJsException(JSContext* ctx)
{
    JSValue exc = JS_GetException(ctx);
    std::string msg = JsToStdString(ctx, exc);
    if (JS_IsObject(exc)) {
        JSValue stack = JS_GetPropertyStr(ctx, exc, "stack");
        if (!JS_IsUndefined(stack) && !JS_IsNull(stack)) {
            std::string st = JsToStdString(ctx, stack);
            if (!st.empty() && st != msg) {
                if (!msg.empty()) msg += "\n";
                msg += st;
            }
        }
        JS_FreeValue(ctx, stack);
    }
    JS_FreeValue(ctx, exc);
    return msg.empty() ? "QuickJS execution error" : msg;
}

bool ExtractBytes(JSContext* ctx, JSValueConst value, std::vector<uint8_t>& out, std::string& errOut)
{
    size_t size = 0;
    uint8_t* ptr = JS_GetArrayBuffer(ctx, &size, value);
    JSValue holder = JS_UNDEFINED;
    if (!ptr) {
        JSValue err = JS_GetException(ctx);
        const bool emptyAb = size == 0 && (JS_IsNull(err) || JS_IsUndefined(err));
        JS_FreeValue(ctx, err);
        if (emptyAb) {
            out.clear();
            return true;
        }
        size_t offset = 0;
        size_t elemSize = 0;
        holder = JS_GetTypedArrayBuffer(ctx, value, &offset, &size, &elemSize);
        if (JS_IsException(holder)) {
            errOut = TakeJsException(ctx);
            return false;
        }
        size_t bufSize = 0;
        ptr = JS_GetArrayBuffer(ctx, &bufSize, holder);
        if (!ptr) {
            JSValue err2 = JS_GetException(ctx);
            const bool emptyView = bufSize == 0 && (JS_IsNull(err2) || JS_IsUndefined(err2));
            JS_FreeValue(ctx, err2);
            if (!emptyView) {
                JS_FreeValue(ctx, holder);
                errOut = "invalid ArrayBuffer backing TypedArray";
                return false;
            }
        }
        if (elemSize != 1 || offset > bufSize || size > bufSize - offset) {
            JS_FreeValue(ctx, holder);
            errOut = "binary payload must be ArrayBuffer or Uint8Array";
            return false;
        }
        if (ptr) ptr += offset;
    }
    if (size > MAX_PLUGIN_BINARY_BYTES) {
        JS_FreeValue(ctx, holder);
        errOut = "binary payload exceeds 32 MiB limit";
        return false;
    }
    out.clear();
    if (size > 0 && ptr) {
        out.assign(ptr, ptr + size);
    }
    JS_FreeValue(ctx, holder);
    return true;
}

std::string DirNameOf(const std::string& relPath)
{
    size_t slash = relPath.find_last_of('/');
    return slash == std::string::npos ? "" : relPath.substr(0, slash);
}

class QuickJsGuestEngine final : public GuestEngine {
public:
    ~QuickJsGuestEngine() override
    {
        if (ctx_) {
            JS_FreeContext(ctx_);
            ctx_ = nullptr;
        }
        if (rt_) {
            JS_FreeRuntime(rt_);
            rt_ = nullptr;
        }
    }

    bool initialize(
        const std::string& pluginRoot,
        size_t memoryLimitBytes,
        size_t stackLimitBytes,
        HostInvoker invoker,
        std::string& errorOut) override
    {
        pluginRoot_ = pluginRoot;
        invoker_ = std::move(invoker);

        rt_ = JS_NewRuntime();
        if (!rt_) {
            errorOut = "failed to create QuickJS runtime";
            return false;
        }
        JS_SetMemoryLimit(rt_, memoryLimitBytes);
        JS_SetMaxStackSize(rt_, stackLimitBytes);
        JS_SetInterruptHandler(rt_, &QuickJsGuestEngine::OnInterrupt, this);
        JS_SetModuleLoaderFunc(rt_, &QuickJsGuestEngine::NormalizeModule, &QuickJsGuestEngine::LoadModule, this);

        ctx_ = JS_NewContext(rt_);
        if (!ctx_) {
            errorOut = "failed to create QuickJS context";
            return false;
        }
        JS_SetContextOpaque(ctx_, this);

        JSValue global = JS_GetGlobalObject(ctx_);
        JS_SetPropertyStr(ctx_, global, "__qy_host",
            JS_NewCFunction(ctx_, &QuickJsGuestEngine::HostBridge, "__qy_host", 3));
        JS_FreeValue(ctx_, global);

        deadline_ = Clock::now() + std::chrono::milliseconds(5000);
        JSValue initVal = JS_Eval(ctx_, kJsPrelude, std::strlen(kJsPrelude), "<qingye-prelude>", JS_EVAL_TYPE_GLOBAL);
        if (JS_IsException(initVal)) {
            errorOut = TakeJsException(ctx_);
            return false;
        }
        JS_FreeValue(ctx_, initVal);
        return true;
    }

    bool loadEntry(
        const std::string& entryRelPath,
        int cpuTimeoutMs,
        std::string& errorOut,
        bool& timedOut,
        bool& cancelled) override
    {
        std::string cleanEntry;
        if (!NormalizeSafeRelativePath("", entryRelPath, cleanEntry)) {
            errorOut = "invalid JS entry path: " + entryRelPath;
            return false;
        }

        clearInterrupt();
        timedOut_ = false;
        cancelled_ = false;
        deadline_ = Clock::now() + std::chrono::milliseconds(cpuTimeoutMs);

        std::string escaped;
        escaped.reserve(cleanEntry.size() + 8);
        for (char c : cleanEntry) {
            if (c == '\\' || c == '\'') escaped.push_back('\\');
            escaped.push_back(c);
        }
        std::string boot = "import * as __m from './" + escaped + "'; globalThis.__qy_entry = __m;";
        JSValue val = JS_Eval(ctx_, boot.c_str(), boot.size(), "<plugin-entry-loader>", JS_EVAL_TYPE_MODULE);
        if (JS_IsException(val)) {
            errorOut = FinishFailure(timedOut, cancelled);
            return false;
        }
        if (!DrainAndUnwrap(val, errorOut)) {
            JS_FreeValue(ctx_, val);
            if (timedOut_ || cancelled_) errorOut = FinishFailure(timedOut, cancelled);
            return false;
        }
        JS_FreeValue(ctx_, val);
        return true;
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
        clearInterrupt();
        timedOut_ = false;
        cancelled_ = false;
        deadline_ = Clock::now() + std::chrono::milliseconds(cpuTimeoutMs);

        JSValue global = JS_GetGlobalObject(ctx_);
        JSValue entryNs = JS_GetPropertyStr(ctx_, global, "__qy_entry");
        JSValue fn = JS_UNDEFINED;
        if (JS_IsObject(entryNs)) {
            fn = JS_GetPropertyStr(ctx_, entryNs, exportName.c_str());
            if (JS_IsUndefined(fn)) {
                JSValue defObj = JS_GetPropertyStr(ctx_, entryNs, "default");
                if (JS_IsObject(defObj)) {
                    fn = JS_GetPropertyStr(ctx_, defObj, exportName.c_str());
                }
                JS_FreeValue(ctx_, defObj);
            }
        }
        if (JS_IsUndefined(fn)) {
            fn = JS_GetPropertyStr(ctx_, global, exportName.c_str());
        }
        JS_FreeValue(ctx_, entryNs);
        JS_FreeValue(ctx_, global);

        if (!JS_IsFunction(ctx_, fn)) {
            JS_FreeValue(ctx_, fn);
            errorOut = "exported handler not found: " + exportName;
            return false;
        }

        const std::string& jsonStr = input.metaJson.empty() ? "{}" : input.metaJson;
        JSValue arg0 = JS_ParseJSON(ctx_, jsonStr.c_str(), jsonStr.size(), "<invoke-arg>");
        if (JS_IsException(arg0)) {
            JS_FreeValue(ctx_, fn);
            errorOut = TakeJsException(ctx_);
            return false;
        }

        JSValue argv[2] = { arg0, JS_UNDEFINED };
        int argc = 1;
        if (input.hasBytes) {
            JSValue ab = JS_NewArrayBufferCopy(ctx_, input.bytes.data(), input.bytes.size());
            if (JS_IsException(ab)) {
                JS_FreeValue(ctx_, arg0);
                JS_FreeValue(ctx_, fn);
                errorOut = TakeJsException(ctx_);
                return false;
            }
            JSValue globalObj = JS_GetGlobalObject(ctx_);
            JSValue u8Ctor = JS_GetPropertyStr(ctx_, globalObj, "Uint8Array");
            JS_FreeValue(ctx_, globalObj);
            argv[1] = JS_CallConstructor(ctx_, u8Ctor, 1, &ab);
            JS_FreeValue(ctx_, u8Ctor);
            JS_FreeValue(ctx_, ab);
            if (JS_IsException(argv[1])) {
                JS_FreeValue(ctx_, arg0);
                JS_FreeValue(ctx_, fn);
                errorOut = TakeJsException(ctx_);
                return false;
            }
            argc = 2;
        }

        JSValue ret = JS_Call(ctx_, fn, JS_UNDEFINED, argc, argv);
        JS_FreeValue(ctx_, arg0);
        if (argc > 1) JS_FreeValue(ctx_, argv[1]);
        JS_FreeValue(ctx_, fn);

        if (JS_IsException(ret)) {
            errorOut = FinishFailure(timedOut, cancelled);
            return false;
        }

        if (!DrainAndUnwrap(ret, errorOut)) {
            JS_FreeValue(ctx_, ret);
            if (timedOut_ || cancelled_) errorOut = FinishFailure(timedOut, cancelled);
            return false;
        }

        const bool serialized = SerializeResult(ret, output, errorOut);
        JS_FreeValue(ctx_, ret);
        return serialized;
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
        if (rt_) JS_RunGC(rt_);
    }

    size_t memoryUsageBytes() const override
    {
        if (!rt_) return 0;
        JSMemoryUsage usage {};
        JS_ComputeMemoryUsage(rt_, &usage);
        return usage.memory_used_size > 0 ? static_cast<size_t>(usage.memory_used_size) : 0;
    }

private:
    static int OnInterrupt(JSRuntime* /*rt*/, void* opaque)
    {
        auto* self = static_cast<QuickJsGuestEngine*>(opaque);
        if (self->interrupted_.load()) {
            self->cancelled_ = true;
            return 1;
        }
        if (Clock::now() >= self->deadline_) {
            self->timedOut_ = true;
            return 1;
        }
        return 0;
    }

    static char* NormalizeModule(
        JSContext* ctx,
        const char* moduleBaseName,
        const char* moduleName,
        void* /*opaque*/)
    {
        std::string baseDir;
        if (moduleBaseName && moduleBaseName[0] != '<') {
            baseDir = DirNameOf(moduleBaseName);
        }
        std::string req(moduleName ? moduleName : "");
        if (!req.empty() && req.find('.') == std::string::npos) {
            req += ".js";
        } else if (req.size() >= 2 && (req.rfind("./", 0) == 0 || req.rfind("../", 0) == 0)) {
            size_t lastSlash = req.find_last_of('/');
            std::string tail = lastSlash == std::string::npos ? req : req.substr(lastSlash + 1);
            if (tail.find('.') == std::string::npos) {
                req += ".js";
            }
        }
        std::string normalized;
        if (!NormalizeSafeRelativePath(baseDir, req, normalized)) {
            JS_ThrowReferenceError(ctx, "disallowed module specifier '%s'", moduleName ? moduleName : "");
            return nullptr;
        }
        return js_strdup(ctx, normalized.c_str());
    }

    static JSModuleDef* LoadModule(JSContext* ctx, const char* moduleName, void* opaque)
    {
        auto* self = static_cast<QuickJsGuestEngine*>(opaque);
        std::string source;
        std::string err;
        if (!ReadPluginTextFile(self->pluginRoot_, moduleName ? moduleName : "", source, err)) {
            JS_ThrowReferenceError(ctx, "%s", err.c_str());
            return nullptr;
        }
        JSValue funcVal = JS_Eval(
            ctx,
            source.c_str(),
            source.size(),
            moduleName,
            JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
        if (JS_IsException(funcVal)) {
            return nullptr;
        }
        auto* m = static_cast<JSModuleDef*>(JS_VALUE_GET_PTR(funcVal));
        JS_FreeValue(ctx, funcVal);
        return m;
    }

    static JSValue HostBridge(JSContext* ctx, JSValueConst /*thisVal*/, int argc, JSValueConst* argv)
    {
        auto* self = static_cast<QuickJsGuestEngine*>(JS_GetContextOpaque(ctx));
        if (!self || argc < 2) {
            return JS_ThrowTypeError(ctx, "__qy_host requires (method, metaJson[, bytes])");
        }
        std::string method = JsToStdString(ctx, argv[0]);
        HostPayload req;
        req.metaJson = JsToStdString(ctx, argv[1]);
        if (argc >= 3 && !JS_IsUndefined(argv[2]) && !JS_IsNull(argv[2])) {
            std::string binErr;
            if (!ExtractBytes(ctx, argv[2], req.bytes, binErr)) {
                return JS_ThrowTypeError(ctx, "%s", binErr.c_str());
            }
            req.hasBytes = true;
        }

        HostPayload resp;
        std::string hostErr;
        const auto waitStart = Clock::now();
        const bool ok = self->invoker_(method, req, resp, hostErr);
        const auto waited = Clock::now() - waitStart;
        self->deadline_ += waited;

        if (!ok) {
            JSValue errObj = JS_NewError(ctx);
            JS_SetPropertyStr(ctx, errObj, "message", JS_NewStringLen(ctx, hostErr.c_str(), hostErr.size()));
            return JS_Throw(ctx, errObj);
        }

        JSValue outObj = JS_NewObject(ctx);
        JS_SetPropertyStr(ctx, outObj, "meta",
            JS_NewStringLen(ctx, resp.metaJson.c_str(), resp.metaJson.size()));
        if (resp.hasBytes) {
            JSValue ab = JS_NewArrayBufferCopy(ctx, resp.bytes.data(), resp.bytes.size());
            if (JS_IsException(ab)) {
                JS_FreeValue(ctx, outObj);
                return JS_EXCEPTION;
            }
            JS_SetPropertyStr(ctx, outObj, "bytes", ab);
        }
        return outObj;
    }

    bool DrainAndUnwrap(JSValue& val, std::string& errorOut)
    {
        JSContext* jobCtx = nullptr;
        while (JS_IsJobPending(rt_)) {
            int r = JS_ExecutePendingJob(rt_, &jobCtx);
            if (r < 0) {
                errorOut = TakeJsException(jobCtx ? jobCtx : ctx_);
                return false;
            }
        }
        if (JS_IsObject(val)) {
            JSPromiseStateEnum st = JS_PromiseState(ctx_, val);
            if (st == JS_PROMISE_FULFILLED) {
                JSValue unwrapped = JS_PromiseResult(ctx_, val);
                JS_FreeValue(ctx_, val);
                val = unwrapped;
            } else if (st == JS_PROMISE_REJECTED) {
                JSValue reason = JS_PromiseResult(ctx_, val);
                errorOut = JsToStdString(ctx_, reason);
                JS_FreeValue(ctx_, reason);
                return false;
            } else if (st == JS_PROMISE_PENDING) {
                errorOut = "Promise remained pending without timers";
                return false;
            }
        }
        return true;
    }

    bool SerializeResult(JSValueConst val, HostPayload& output, std::string& errorOut)
    {
        output = HostPayload {};
        if (JS_IsUndefined(val) || JS_IsNull(val)) {
            output.metaJson = "null";
            return true;
        }

        std::vector<uint8_t> directBytes;
        std::string dummyErr;
        if (JS_IsObject(val) && ExtractBytes(ctx_, val, directBytes, dummyErr)) {
            output.metaJson = "null";
            output.hasBytes = true;
            output.bytes = std::move(directBytes);
            return true;
        }

        if (JS_IsObject(val)) {
            JSValue bytesProp = JS_GetPropertyStr(ctx_, val, "__bytes");
            if (!JS_IsUndefined(bytesProp) && !JS_IsNull(bytesProp)) {
                std::string binErr;
                if (!ExtractBytes(ctx_, bytesProp, output.bytes, binErr)) {
                    JS_FreeValue(ctx_, bytesProp);
                    errorOut = binErr;
                    return false;
                }
                output.hasBytes = true;
            }
            JS_FreeValue(ctx_, bytesProp);
        }

        JSValue jsonVal = JS_JSONStringify(ctx_, val, JS_UNDEFINED, JS_UNDEFINED);
        if (JS_IsException(jsonVal)) {
            errorOut = TakeJsException(ctx_);
            return false;
        }
        output.metaJson = JS_IsUndefined(jsonVal) ? "null" : JsToStdString(ctx_, jsonVal);
        JS_FreeValue(ctx_, jsonVal);
        return true;
    }

    std::string FinishFailure(bool& timedOut, bool& cancelled)
    {
        JS_ResetUncatchableError(ctx_);
        std::string exc = TakeJsException(ctx_);
        timedOut = timedOut_;
        cancelled = cancelled_;
        if (cancelled_) return "plugin execution cancelled";
        if (timedOut_) return "plugin CPU budget exceeded";
        return exc;
    }

    std::string pluginRoot_;
    HostInvoker invoker_;
    JSRuntime* rt_ = nullptr;
    JSContext* ctx_ = nullptr;
    std::atomic<bool> interrupted_ { false };
    bool timedOut_ = false;
    bool cancelled_ = false;
    Clock::time_point deadline_ {};
};

} // namespace

std::unique_ptr<GuestEngine> CreateQuickJsGuest()
{
    return std::make_unique<QuickJsGuestEngine>();
}

} // namespace qyplugin
