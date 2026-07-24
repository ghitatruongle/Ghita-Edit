cmake_minimum_required(VERSION 3.15)
project(ghita_engine VERSION 0.1.0 LANGUAGES CXX C)

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

add_library(ghita_engine SHARED
    ${ENGINE_SOURCES}
    ${ENGINE_HEADERS}
)

target_include_directories(ghita_engine PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

if(WIN32)
    set_target_properties(ghita_engine PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS ON
    )
endif()
