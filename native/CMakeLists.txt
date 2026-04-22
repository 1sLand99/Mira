cmake_minimum_required(VERSION 3.22)

project(mira_pty_native C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

set(MIRA_PTY_CORE_SOURCES
    src/pty/pty_core.c
    src/posix/pty_spawn_posix.c
)

if(ANDROID)
    add_library(mira_pty SHARED
        ${MIRA_PTY_CORE_SOURCES}
        src/platform/android/pty_pair_android.c
        bridge/android/jni/mira_pty_jni.c
    )
elseif(APPLE)
    add_library(mira_pty STATIC
        ${MIRA_PTY_CORE_SOURCES}
        src/platform/darwin/pty_pair_darwin.c
        bridge/ios/mira_pty_ios_shim.c
    )
else()
    add_library(mira_pty SHARED
        ${MIRA_PTY_CORE_SOURCES}
        src/platform/android/pty_pair_android.c
    )
endif()

target_include_directories(mira_pty
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/bridge/ios
)

target_compile_definitions(mira_pty
    PRIVATE
        _GNU_SOURCE
        _XOPEN_SOURCE=600
)
