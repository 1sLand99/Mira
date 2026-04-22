cmake_minimum_required(VERSION 3.22)

project(mira_pty_native C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

add_library(mira_pty SHARED
    src/pty_core.c
    platform/android/pty_android.c
    bridge/jni/mira_pty_jni.c
)

target_include_directories(mira_pty
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_definitions(mira_pty
    PRIVATE
        _GNU_SOURCE
        _XOPEN_SOURCE=600
)
