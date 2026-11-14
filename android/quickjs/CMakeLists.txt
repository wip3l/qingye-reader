# 安卓版 libquickjs.so：QuickJS 本体 + harmony-book-source-engine/quickjs 里原有的 NAPI 封装，
# 链接 ArkUI-X 引擎里的 NAPI 实现。由 scripts/android/build-android.mjs 调用，不单独使用。
#   QJS_SRC_DIR   QuickJS 源码目录（版本须与封装里的头文件一致）
#   WRAP_SRC_DIR  harmony-book-source-engine/quickjs/src/main/cpp
#   ARKUIX_SDK    ArkUI-X SDK 的 arkui-x 目录
#   QJS_VERSION   写进 CONFIG_VERSION 的版本串
cmake_minimum_required(VERSION 3.10)
project(quickjs C CXX)

foreach(var QJS_SRC_DIR WRAP_SRC_DIR ARKUIX_SDK QJS_VERSION)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "缺少 -D${var}=...")
  endif()
endforeach()

if(CMAKE_ANDROID_ARCH_ABI STREQUAL "x86_64")
  set(ARKUIX_LIBDIR ${ARKUIX_SDK}/engine/lib/arkui/android-x86_64)
elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
  set(ARKUIX_LIBDIR ${ARKUIX_SDK}/engine/lib/arkui/android-arm64-release)
else()
  message(FATAL_ERROR "未处理的 ABI: ${CMAKE_ANDROID_ARCH_ABI}")
endif()

add_library(arkui_android SHARED IMPORTED)
set_target_properties(arkui_android PROPERTIES IMPORTED_LOCATION ${ARKUIX_LIBDIR}/libarkui_android.so)

add_library(quickjs SHARED
  ${WRAP_SRC_DIR}/napi_init.cpp
  ${WRAP_SRC_DIR}/quickjs_ext.cpp
  ${WRAP_SRC_DIR}/script_session.cpp
  ${QJS_SRC_DIR}/quickjs.c
  ${QJS_SRC_DIR}/libregexp.c
  ${QJS_SRC_DIR}/libunicode.c
  ${QJS_SRC_DIR}/cutils.c
  ${QJS_SRC_DIR}/libbf.c)
target_compile_definitions(quickjs PRIVATE CONFIG_VERSION="${QJS_VERSION}" CONFIG_BIGNUM _GNU_SOURCE)
target_include_directories(quickjs PRIVATE ${WRAP_SRC_DIR} ${WRAP_SRC_DIR}/include ${ARKUIX_SDK}/engine/lib/include)
target_compile_options(quickjs PRIVATE -O2 -fvisibility=hidden -Wno-everything)
set_target_properties(quickjs PROPERTIES CXX_STANDARD 17 C_STANDARD 11)
target_link_libraries(quickjs PRIVATE arkui_android log m)
