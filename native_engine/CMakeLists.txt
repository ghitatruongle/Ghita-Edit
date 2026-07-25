cmake_minimum_required(VERSION 3.15)
project(ghita_engine VERSION 0.2.0 LANGUAGES CXX C)

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

# --- Shared library target ---
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

# --- Self-contained test runner (linked static lib for portability) ---
option(BUILD_TESTING "Build native engine tests" ON)

if(BUILD_TESTING)
  enable_testing()

  add_library(ghita_engine_static STATIC ${ENGINE_SOURCES})
  target_include_directories(ghita_engine_static PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_compile_definitions(ghita_engine_static PRIVATE GHITA_ENGINE_STATIC)

  add_executable(native_engine_test test/native_engine_self_test.cpp)
  target_link_libraries(native_engine_test PRIVATE ghita_engine_static)
  add_test(NAME native_engine_self_test COMMAND native_engine_test)

  if(WIN32)
    add_dependencies(native_engine_test ghita_engine)
  endif()
endif()
