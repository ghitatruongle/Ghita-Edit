# GhitaDependencies.cmake
# OS/toolchain-aware dependency resolution for Ghita Edit.
#
# Resolution order:
#   - MINGW  (MSYS2 ucrt64 shell, GCC/MinGW): Qt6 via find_package,
#            FFmpeg + PortAudio via pkg-config (prebuilt by pacman).
#   - WIN32  (Visual Studio + vcpkg): vcpkg toolchain provides everything.
#   - else   (Linux / WSL): system packages + pkg-config.

if(MINGW)
    # ---- MSYS2 / MinGW-w64 (ucrt64) ----
    find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 OpenGL Concurrent)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(AV REQUIRED IMPORTED_TARGET
        libavformat libavcodec libavutil libswscale libswresample)
    set(GHITA_FFMPEG_LIBS PkgConfig::AV)
    pkg_check_modules(PA REQUIRED IMPORTED_TARGET portaudio-2.0)
    set(GHITA_PORTAUDIO_LIB PkgConfig::PA)
    message(STATUS "[GhitaEdit] MINGW deps: Qt6 + pkg-config FFmpeg/PortAudio")

elseif(WIN32)
    # ---- Windows: Qt6 from aqtinstall + FFmpeg/PortAudio from vcpkg ----
    find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 OpenGL Concurrent)

    # vcpkg provides a FindFFMPEG module (not a config package).
    list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")
    find_package(FFMPEG REQUIRED)
    set(GHITA_FFMPEG_LIBS ${FFMPEG_LIBRARIES})
    include_directories(${FFMPEG_INCLUDE_DIRS})

    find_package(portaudio REQUIRED)
    set(GHITA_PORTAUDIO_LIB portaudio)

    # Workaround: fix x264 include path with spaces (common on Windows with
    # "Program Files" or "Ghita Edit" paths).
    if(TARGET PkgConfig::x264)
        get_target_property(_x264_inc PkgConfig::x264 INTERFACE_INCLUDE_DIRECTORIES)
        if(_x264_inc MATCHES ";")
            # Path got split at space; reconstruct it.
            list(GET _x264_inc 0 _first)
            list(GET _x264_inc 1 _second)
            string(REGEX REPLACE "/$" "" _first "${_first}")
            set(_fixed "${_first} ${_second}")
            set_target_properties(PkgConfig::x264 PROPERTIES
                INTERFACE_INCLUDE_DIRECTORIES "${_fixed}")
        endif()
    endif()

else()
    # ---- Linux / WSL: system packages + pkg-config ----
    find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 OpenGL Concurrent)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(AV REQUIRED IMPORTED_TARGET
        libavformat libavcodec libavutil libswscale libswresample)
    set(GHITA_FFMPEG_LIBS PkgConfig::AV)
    pkg_check_modules(PA REQUIRED IMPORTED_TARGET portaudio-2.0)
    set(GHITA_PORTAUDIO_LIB PkgConfig::PA)
endif()

message(STATUS "[GhitaEdit] FFmpeg libs: ${GHITA_FFMPEG_LIBS}")
message(STATUS "[GhitaEdit] PortAudio lib: ${GHITA_PORTAUDIO_LIB}")
