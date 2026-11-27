cmake_minimum_required(VERSION 3.10)
project(plugin_runtime C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

add_definitions(
    "-DLOG_DOMAIN=0xd0d1"
    "-DLOG_TAG=\"plugin_runtime\""
    "-DPK_ENABLE_THREAD=1"
    "-DPK_ENABLE_OS=0"
    "-DPK_NO_EXPORT_C_API=1"
)

set(QJS_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../harmony-book-source-engine/quickjs)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/pocketpy
    ${QJS_ROOT}/src/main/cpp/include
)

add_library(plugin_runtime SHARED
    napi_init.cpp
    plugin_session.cpp
    path_sandbox.cpp
    qjs_guest.cpp
    py_guest.cpp
)

target_compile_options(plugin_runtime PRIVATE -O2 -fvisibility=hidden -Wno-unused-parameter)

target_link_libraries(plugin_runtime PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    ${QJS_ROOT}/libs/${OHOS_ARCH}/libquickjs.a
)
