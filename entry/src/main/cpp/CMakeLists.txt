cmake_minimum_required(VERSION 3.5.0)
project(entry_native)

# 听书字幕：本地音频解码成 16 kHz 单声道 PCM，供字幕 Worker 做语音识别。
add_library(subtitle_audio SHARED subtitle_audio.cpp)
target_compile_features(subtitle_audio PRIVATE cxx_std_17)
target_compile_options(subtitle_audio PRIVATE -O2 -Wall -Wextra)
target_link_libraries(subtitle_audio PUBLIC
    libace_napi.z.so
    libnative_media_codecbase.so
    libnative_media_core.so
    libnative_media_acodec.so
    libnative_media_avdemuxer.so
    libnative_media_avsource.so)
