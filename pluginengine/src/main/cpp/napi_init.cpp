// Copyright (c) 2026 qingye-plugin-reader contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "napi/native_api.h"

namespace qyplugin {
void DefinePluginSessionExports(napi_env env, napi_value exports);
}

EXTERN_C_START
static napi_value InitPluginRuntime(napi_env env, napi_value exports)
{
    qyplugin::DefinePluginSessionExports(env, exports);
    return exports;
}
EXTERN_C_END

static napi_module g_pluginRuntimeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitPluginRuntime,
    .nm_modname = "plugin_runtime",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterPluginRuntimeModule(void)
{
    napi_module_register(&g_pluginRuntimeModule);
}
