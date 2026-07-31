cmake_minimum_required(VERSION 3.15)
project(ghita_engine VERSION 0.5.5 LANGUAGES CXX C)

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

set(FFMPEG_LIBS)
set(FFMPEG_INCLUDE_DIRS)

# Check vcpkg environment variable for MSVC builds
if(DEFINED ENV{VCPKG_ROOT})
    set(VCPKG_ROOT "$ENV{VCPKG_ROOT}")
elseif(EXISTS "C:/vcpkg")
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

  add_executable(native_engine_test test/native_engine_self_test.cpp)
  target_link_libraries(native_engine_test PRIVATE ghita_engine_static)
  add_test(NAME native_engine_self_test COMMAND native_engine_test)

  if(WIN32)
    add_dependencies(native_engine_test ghita_engine)
  endif()
endif()
