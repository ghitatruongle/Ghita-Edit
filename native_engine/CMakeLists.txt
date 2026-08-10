cmake_minimum_required(VERSION 3.15)
project(ghita_engine VERSION 1.1.1 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_definitions(-DGHITA_ENGINE_EXPORTS)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

set(ENGINE_SOURCES
    src/ghita_engine.cpp
    src/ghita_c_api.cpp
)

set(ENGINE_HEADERS
    include/ghita_engine.h
    include/ghita_c_api.h
)

# --- FFmpeg detection ---
find_package(PkgConfig QUIET)

# v1.1.0 (PLAN_REVIEW B.1): opt-out for bounds-checking builds. The MinGW
# FFmpeg DLLs resolve mingw64's libstdc++ while an assertions build uses the
# ucrt64 runtime — the two cannot coexist in one process. GHITA_DISABLE_FFMPEG
# yields a synthetic-only build that CAN run under -D_GLIBCXX_ASSERTIONS
# (real-media tests then report "skipped").
option(GHITA_DISABLE_FFMPEG "Build without FFmpeg (synthetic only)" OFF)
if(GHITA_DISABLE_FFMPEG)
    set(FFMPEG_LIBS)
    set(FFMPEG_INCLUDE_DIRS)
endif()

# v0.8.0: Prefer a MinGW-built FFmpeg when compiling with MinGW. MSVC-built
# FFmpeg (vcpkg) frees memory through the MSVC CRT while MinGW code allocates
# on its own CRT heap — mixing them corrupted the heap and crashed on real
# media decode. MinGW FFmpeg from msys64 shares the CRT and works.
if(MINGW AND EXISTS "C:/msys64/mingw64/include/libavcodec/avcodec.h")
    set(MSYS64_FFMPEG "C:/msys64/mingw64")
    message(STATUS "FFmpeg found via msys64 MinGW at ${MSYS64_FFMPEG}")
    list(APPEND FFMPEG_INCLUDE_DIRS "${MSYS64_FFMPEG}/include")
    list(APPEND FFMPEG_LIBS
        "${MSYS64_FFMPEG}/lib/libavcodec.dll.a"
        "${MSYS64_FFMPEG}/lib/libavformat.dll.a"
        "${MSYS64_FFMPEG}/lib/libavutil.dll.a"
        "${MSYS64_FFMPEG}/lib/libswscale.dll.a"
        "${MSYS64_FFMPEG}/lib/libswresample.dll.a"
    )
endif()

# Check vcpkg environment variable for MSVC builds
# v0.7.8: Verify the path actually contains FFmpeg before using it — a stale
# VCPKG_ROOT env var (e.g. C:\dev\vcpkg) used to silently disable FFmpeg even
# though a valid installation existed at C:/vcpkg.
if(NOT FFMPEG_LIBS AND DEFINED ENV{VCPKG_ROOT} AND EXISTS "$ENV{VCPKG_ROOT}/installed/x64-windows/include/libavcodec/avcodec.h")
    set(VCPKG_ROOT "$ENV{VCPKG_ROOT}")
elseif(NOT FFMPEG_LIBS AND EXISTS "C:/vcpkg/installed/x64-windows/include/libavcodec/avcodec.h")
    set(VCPKG_ROOT "C:/vcpkg")
endif()

if(VCPKG_ROOT AND NOT PkgConfig_FOUND)
    set(VCPKG_INSTALLED "${VCPKG_ROOT}/installed/x64-windows")
    if(EXISTS "${VCPKG_INSTALLED}/include/libavcodec/avcodec.h")
        message(STATUS "FFmpeg found via vcpkg at ${VCPKG_INSTALLED}")
        list(APPEND FFMPEG_INCLUDE_DIRS "${VCPKG_INSTALLED}/include")
        list(APPEND FFMPEG_LIBS
            "${VCPKG_INSTALLED}/lib/avcodec.lib"
            "${VCPKG_INSTALLED}/lib/avformat.lib"
            "${VCPKG_INSTALLED}/lib/avutil.lib"
            "${VCPKG_INSTALLED}/lib/swscale.lib"
            "${VCPKG_INSTALLED}/lib/swresample.lib"
        )
    endif()
endif()

if(NOT FFMPEG_LIBS AND PkgConfig_FOUND)
    pkg_check_modules(AVCODEC libavcodec QUIET IMPORTED_TARGET)
    pkg_check_modules(AVFORMAT libavformat QUIET IMPORTED_TARGET)
    pkg_check_modules(AVUTIL libavutil QUIET IMPORTED_TARGET)
    pkg_check_modules(SWSCALE libswscale QUIET IMPORTED_TARGET)
    pkg_check_modules(SWRESAMPLE libswresample QUIET IMPORTED_TARGET)

    if(AVCODEC_FOUND AND AVFORMAT_FOUND AND AVUTIL_FOUND AND SWSCALE_FOUND AND SWRESAMPLE_FOUND)
        message(STATUS "FFmpeg found via pkg-config")
        list(APPEND FFMPEG_LIBS
            PkgConfig::AVCODEC
            PkgConfig::AVFORMAT
            PkgConfig::AVUTIL
            PkgConfig::SWSCALE
            PkgConfig::SWRESAMPLE
        )
    endif()
endif()

# Fallback: try vcpkg or system paths (Windows / manual install)
if(NOT FFMPEG_LIBS)
    find_path(AVCODEC_INCLUDE_DIR libavcodec/avcodec.h)
    find_path(AVFORMAT_INCLUDE_DIR libavformat/avformat.h)
    find_path(AVUTIL_INCLUDE_DIR libavutil/avutil.h)
    find_path(SWSCALE_INCLUDE_DIR libswscale/swscale.h)
    find_path(SWRESAMPLE_INCLUDE_DIR libswresample/swresample.h)

    find_library(AVCODEC_LIBRARY avcodec)
    find_library(AVFORMAT_LIBRARY avformat)
    find_library(AVUTIL_LIBRARY avutil)
    find_library(SWSCALE_LIBRARY swscale)
    find_library(SWRESAMPLE_LIBRARY swresample)

    if(AVCODEC_INCLUDE_DIR AND AVFORMAT_INCLUDE_DIR AND AVUTIL_INCLUDE_DIR
       AND SWSCALE_INCLUDE_DIR AND SWRESAMPLE_INCLUDE_DIR
       AND AVCODEC_LIBRARY AND AVFORMAT_LIBRARY AND AVUTIL_LIBRARY
       AND SWSCALE_LIBRARY AND SWRESAMPLE_LIBRARY)
        message(STATUS "FFmpeg found via find_path/find_library")
        list(APPEND FFMPEG_INCLUDE_DIRS
            ${AVCODEC_INCLUDE_DIR}
            ${AVFORMAT_INCLUDE_DIR}
            ${AVUTIL_INCLUDE_DIR}
            ${SWSCALE_INCLUDE_DIR}
            ${SWRESAMPLE_INCLUDE_DIR}
        )
        list(APPEND FFMPEG_LIBS
            ${AVCODEC_LIBRARY}
            ${AVFORMAT_LIBRARY}
            ${AVUTIL_LIBRARY}
            ${SWSCALE_LIBRARY}
            ${SWRESAMPLE_LIBRARY}
        )
    endif()
endif()

# Force-off after ALL detection branches — GHITA_DISABLE_FFMPEG wins even if
# a detection path populated the lists above (synthetic-only build).
if(GHITA_DISABLE_FFMPEG)
    set(FFMPEG_LIBS)
    set(FFMPEG_INCLUDE_DIRS)
endif()
if(FFMPEG_LIBS)
    message(STATUS "FFmpeg integration enabled")
    add_definitions(-DGHITA_HAS_FFMPEG)
else()
    message(WARNING "FFmpeg not found — building with synthetic decoder only")
endif()

# --- Shared library target ---
add_library(ghita_engine SHARED
    ${ENGINE_SOURCES}
    ${ENGINE_HEADERS}
)

# v0.8.0 + v1.0.1: Copy the FFmpeg runtime DLLs next to the engine DLL so
# development runs (flutter run -d windows) resolve them without relying on
# PATH, and expose the directory so the Flutter Windows runner bundles them
# into the Release output.
# v1.0.1: This must ALSO run for MSVC builds. Previously only the MinGW path
# set GHITA_FFMPEG_BIN_DIR, so MSVC Release builds shipped without the FFmpeg
# DLLs — the engine DLL failed to load, the app silently fell back to Demo
# Mode, and (in v1.0.0) stayed stuck on the loading shell with nothing
# importable.
if(WIN32)
    if(DEFINED MSYS64_FFMPEG)
        # MinGW build — msys64 MinGW FFmpeg shares the CRT with the engine.
        set(GHITA_FFMPEG_BIN_DIR "${MSYS64_FFMPEG}/bin")
    elseif(DEFINED VCPKG_INSTALLED AND EXISTS "${VCPKG_INSTALLED}/bin")
        # MSVC build (the Flutter Windows toolchain) — vcpkg FFmpeg DLLs use
        # the MSVC CRT (matches the engine) and are self-contained (no extra
        # MinGW runtime dependencies like libbluray/libgnutls).
        set(GHITA_FFMPEG_BIN_DIR "${VCPKG_INSTALLED}/bin")
    else()
        set(GHITA_FFMPEG_BIN_DIR "")
    endif()
    set(GHITA_FFMPEG_BIN_DIR "${GHITA_FFMPEG_BIN_DIR}" CACHE INTERNAL "FFmpeg runtime DLL directory")
    if(GHITA_FFMPEG_BIN_DIR)
        file(GLOB FFMPEG_RUNTIME_DLLS
            "${GHITA_FFMPEG_BIN_DIR}/av*.dll"
            "${GHITA_FFMPEG_BIN_DIR}/sw*.dll")
        foreach(dll ${FFMPEG_RUNTIME_DLLS})
            add_custom_command(TARGET ghita_engine POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different "${dll}" "$<TARGET_FILE_DIR:ghita_engine>"
                COMMENT "Copying FFmpeg runtime DLL: ${dll}")
        endforeach()
    endif()
endif()

# v0.8.0: Statically link the C++ runtime on MinGW. The engine DLL must not
# depend on a versioned libstdc++-6.dll from a random PATH entry — a
# mismatched one (e.g. msys2's vs CodeBlocks') corrupted the heap and crashed
# on std::ifstream/std::string usage. Static linking makes the DLL
# self-contained apart from the FFmpeg DLLs.
if(MINGW)
    target_link_options(ghita_engine PRIVATE -static-libstdc++ -static-libgcc)
endif()

target_include_directories(ghita_engine PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

if(FFMPEG_INCLUDE_DIRS)
    target_include_directories(ghita_engine PRIVATE ${FFMPEG_INCLUDE_DIRS})
endif()

if(FFMPEG_LIBS)
    target_link_libraries(ghita_engine PRIVATE ${FFMPEG_LIBS})
endif()

# v0.8.0: waveOut for audio preview (Windows multimedia API).
if(WIN32)
    target_link_libraries(ghita_engine PRIVATE winmm)
endif()

if(WIN32)
    set_target_properties(ghita_engine PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS ON
    )
endif()

# --- Self-contained test runner (linked static lib for portability) ---
option(BUILD_TESTING "Build native engine tests" ON)

if(BUILD_TESTING)
  enable_testing()

  add_library(ghita_engine_static STATIC ${ENGINE_SOURCES})
  target_include_directories(ghita_engine_static PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_compile_definitions(ghita_engine_static PRIVATE GHITA_ENGINE_STATIC)

  if(FFMPEG_INCLUDE_DIRS)
      target_include_directories(ghita_engine_static PUBLIC ${FFMPEG_INCLUDE_DIRS})
  endif()
  if(FFMPEG_LIBS)
      target_link_libraries(ghita_engine_static PRIVATE ${FFMPEG_LIBS})
  endif()
  # v0.8.0: waveOut — the static lib must carry its own system libs so the
  # test runner links (the shared target's winmm is PRIVATE and not visible).
  if(WIN32)
      target_link_libraries(ghita_engine_static PRIVATE winmm)
  endif()

  add_executable(native_engine_test test/native_engine_self_test.cpp)
  target_link_libraries(native_engine_test PRIVATE ghita_engine_static)
  # v1.0.0e (CI fix): when FFmpeg is detected via pkg-config (macOS/Linux),
  # FFMPEG_INCLUDE_DIRS is empty — the include dirs live on the
  # PkgConfig::* IMPORTED targets, whose interface does NOT propagate to the
  # test executable through a PRIVATE link on the static lib. Without this,
  # the macOS CI build failed with "libavcodec/avcodec.h file not found"
  # while compiling native_engine_self_test.cpp.
  if(FFMPEG_INCLUDE_DIRS)
      target_include_directories(native_engine_test PRIVATE ${FFMPEG_INCLUDE_DIRS})
  endif()
  if(FFMPEG_LIBS)
      target_link_libraries(native_engine_test PRIVATE ${FFMPEG_LIBS})
  endif()
  add_test(NAME native_engine_self_test COMMAND native_engine_test)

  if(WIN32)
    add_dependencies(native_engine_test ghita_engine)
  endif()
endif()
