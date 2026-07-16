cmake_minimum_required(VERSION 3.24)

project(GhitaEdit
    VERSION 0.1.5
    DESCRIPTION "Ghita Edit - high-performance video/audio editor (C++20 + Qt6 QML + FFmpeg)"
    LANGUAGES CXX)

# ---- Project-wide settings ----
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

option(GHITA_BUILD_TESTS "Build unit/integration tests" OFF)
option(GHITA_WERROR "Treat compiler warnings as errors" OFF)

# ---- Dependencies (OS-aware) ----
include(cmake/GhitaDependencies.cmake)

# ---- Hardware acceleration (opt-in) ----
# These backends are NOT wired yet (HW frame upload lands in a later step), so
# they are disabled by default to avoid a misleading "enabled" state.
option(GHITA_HW_ACCEL "Enable hardware decode acceleration (NVDEC/QuickSync/AMF/VA-API)" OFF)
if(GHITA_HW_ACCEL)
    add_compile_definitions(
        GHITA_HW_NVDEC
        GHITA_HW_QUICKSYNC
        GHITA_HW_AMF
        GHITA_HW_VAAPI
    )
endif()

# ---- Sources ----
set(GHITA_SOURCES
    src/main.cpp
    src/app/Application.cpp
    src/engine/MediaEngine.cpp
    src/engine/Decoder.cpp
    src/engine/ScrubEngine.cpp
    src/render/PreviewSurface.cpp
    src/audio/AudioEngine.cpp
    src/audio/AudioMixerController.cpp
    src/audio/TimelineAudioMixer.cpp
    src/timeline/TimelineModel.cpp
    src/timeline/TimelineCommands.cpp
    src/timeline/SnapEngine.cpp
    src/timeline/TextOverlayClip.cpp
    src/timeline/FadeTransition.cpp
    src/timeline/IrisWipeTransition.cpp
    src/timeline/DirectionalWipeTransition.cpp
    src/timeline/BlurDissolveTransition.cpp
    src/timeline/ZoomDissolveTransition.cpp
    src/timeline/TransitionFactory.cpp
    src/export/Exporter.cpp
    src/export/Compositor.cpp
    src/export/VideoEncoder.cpp
    src/export/AudioEncoder.cpp
    src/export/PacketMuxer.cpp
    src/fx/VideoFX.cpp
    src/fx/VideoFXEffects.cpp
    src/fx/AudioDSP.cpp
    src/fx/FxController.cpp
    src/MediaBinModel.cpp
    src/ThumbnailExtractor.cpp
    src/WaveformRenderer.cpp
)

set(GHITA_HEADERS
    src/app/Application.h
    src/app/AppState.h
    src/engine/MediaEngine.h
    src/engine/Decoder.h
    src/engine/ScrubEngine.h
    src/engine/DecodeWorker.h
    src/engine/FramePool.h
    src/engine/HWAccel.h
    src/audio/AudioEngine.h
    src/audio/AudioMixerController.h
    src/audio/AudioClock.h
    src/audio/AudioClip.h
    src/audio/TimelineAudioMixer.h
    src/render/PreviewSurface.h
    src/timeline/Clip.h
    src/timeline/TimelineModel.h
    src/timeline/TimelineCommands.h
    src/timeline/UndoStack.h
    src/timeline/SnapEngine.h
    src/timeline/TextOverlayClip.h
    src/timeline/Transition.h
    src/timeline/FadeTransition.h
    src/timeline/IrisWipeTransition.h
    src/timeline/DirectionalWipeTransition.h
    src/timeline/BlurDissolveTransition.h
    src/timeline/ZoomDissolveTransition.h
    src/timeline/Keyframe.h
    src/fx/VideoFX.h
    src/fx/VideoFXEffects.h
    src/fx/AudioDSP.h
    src/fx/FxController.h
    src/export/Exporter.h
    src/export/Compositor.h
    src/MediaBinModel.h
    src/ThumbnailExtractor.h
    src/WaveformRenderer.h
)

# ---- Executable ----
add_executable(GhitaEdit ${GHITA_SOURCES} ${GHITA_HEADERS})

target_include_directories(GhitaEdit PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_link_libraries(GhitaEdit PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::OpenGL
    Qt6::Concurrent
    ${GHITA_FFMPEG_LIBS}
    ${GHITA_PORTAUDIO_LIB}
)

if(GHITA_WERROR)
    target_compile_options(GhitaEdit PRIVATE
        $<$<CXX_COMPILER_ID:MSVC>:/WX>
        $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Werror>)
endif()

# Fix for MSVC -external:W0 suppressing STL header resolution through Qt headers.
# Qt6's CMake config marks Qt include dirs as -external:I and adds -external:W0,
# which tells MSVC to stop searching default include paths for headers included
# transitively through those external dirs. This breaks compilation when Qt
# headers include <type_traits>, <cstdint>, etc.
#
# Root cause: -external:W0 disables the implicit default include search when
# processing headers that were pulled in through -external:I paths.
#
# Solution: add the MSVC STL and CRT include directories as -external:I so
# that headers transitively included through Qt can still resolve <type_traits>,
# <cstdint>, crtdbg.h, etc.
if(MSVC)
    # CMAKE_CXX_COMPILER -> .../VC/Tools/MSVC/<ver>/bin/HostX64/x64/cl.exe
    # Path hierarchy:
    #   MSVC_ROOT = .../VC/Tools/MSVC/<ver>
    #   BIN       = MSVC_ROOT/bin
    #   HOSTX64   = BIN/HostX64
    #   X64       = HOSTX64/x64  (parent of cl.exe)
    #
    # We need:
    #   STL_INC = MSVC_ROOT/include/
    #   CRT_INC = HOSTX64/include/
    get_filename_component(_ghita_x64 "${CMAKE_CXX_COMPILER}" DIRECTORY)
    get_filename_component(_ghita_hostx64 "${_ghita_x64}/.." ABSOLUTE)
    get_filename_component(_ghita_bin     "${_ghita_hostx64}/.." ABSOLUTE)
    get_filename_component(_ghita_msvc    "${_ghita_bin}/.." ABSOLUTE)
    set(_ghita_stl_inc "${_ghita_msvc}/include")
    set(_ghita_crt_inc "${_ghita_hostx64}/include")
    message(STATUS "[GhitaEdit] MSVC toolset: ${_ghita_msvc}")
    message(STATUS "[GhitaEdit] MSVC STL:     ${_ghita_stl_inc}")
    message(STATUS "[GhitaEdit] MSVC CRT:     ${_ghita_crt_inc}")
    target_compile_options(GhitaEdit PRIVATE
        "/external:I${_ghita_stl_inc}"
        "/external:I${_ghita_crt_inc}")
    unset(_ghita_x64)
    unset(_ghita_hostx64)
    unset(_ghita_bin)
    unset(_ghita_msvc)
    unset(_ghita_stl_inc)
    unset(_ghita_crt_inc)
endif()

if(GHITA_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# Standalone, GoogleTest-free verification of the export pipeline. Used to
# confirm the av_seek_frame time_base fix offline (GoogleTest FetchContent is
# unavailable in some environments). Enabled only when explicitly requested.
option(GHITA_BUILD_SELFTEST "Build the standalone export self-test" OFF)
if(GHITA_BUILD_SELFTEST)
    # GhitaSelftest provides its own main(); exclude src/main.cpp which also
    # defines main().
    set(GHITA_SELFTEST_SOURCES ${GHITA_SOURCES})
    list(REMOVE_ITEM GHITA_SELFTEST_SOURCES src/main.cpp)
    add_executable(GhitaSelftest
        tools/selftest_main.cpp
        ${GHITA_SELFTEST_SOURCES}
        ${GHITA_HEADERS}
    )
    target_include_directories(GhitaSelftest PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_compile_definitions(GhitaSelftest PRIVATE
        TEST_FIXTURE_PATH="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/sample.mp4")
    target_link_libraries(GhitaSelftest PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::OpenGL
        Qt6::Concurrent
        ${GHITA_FFMPEG_LIBS}
        ${GHITA_PORTAUDIO_LIB}
    )
endif()

# QML resources: embed qml/ as Qt resource so the binary is self-contained.
set(GHITA_QML_QRC ${CMAKE_CURRENT_BINARY_DIR}/ghita_qml.qrc)
file(WRITE ${GHITA_QML_QRC} "<RCC>\n  <qresource prefix=\"/\">\n")
file(GLOB GHITA_QML_FILES "${CMAKE_CURRENT_SOURCE_DIR}/qml/*.qml")
foreach(qmlfile ${GHITA_QML_FILES})
    get_filename_component(qmlname ${qmlfile} NAME)
    file(APPEND ${GHITA_QML_QRC} "    <file alias=\"${qmlname}\">${qmlfile}</file>\n")
endforeach()

# Include qmldir if it exists (needed for singleton type registration)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/qml/qmldir")
    file(APPEND ${GHITA_QML_QRC} "    <file alias=\"qmldir\">${CMAKE_CURRENT_SOURCE_DIR}/qml/qmldir</file>\n")
endif()

file(APPEND ${GHITA_QML_QRC} "  </qresource>\n</RCC>\n")
target_sources(GhitaEdit PRIVATE ${GHITA_QML_QRC})

	if(WIN32)
	    set_target_properties(GhitaEdit PROPERTIES
	        WIN32_EXECUTABLE TRUE)

    # Deploy Qt + QML modules next to the executable so the app is runnable
    # standalone. --qmldir points windeployqt at the QML sources (they are
    # embedded in a resource, so windeployqt cannot discover imports otherwise).
    find_program(WINDEPLOYQT_EXECUTABLE windeployqt
        HINTS "${Qt6_DIR}/../../../bin" "${Qt6_DIR}/../../bin")
    if(WINDEPLOYQT_EXECUTABLE)
        add_custom_command(TARGET GhitaEdit POST_BUILD
            COMMAND "${WINDEPLOYQT_EXECUTABLE}"
                --qmldir "${CMAKE_CURRENT_SOURCE_DIR}/qml"
                --no-translations
                "$<TARGET_FILE:GhitaEdit>"
            COMMENT "Deploying Qt + QML via windeployqt")
    endif()
endif()

install(TARGETS GhitaEdit RUNTIME DESTINATION bin)
