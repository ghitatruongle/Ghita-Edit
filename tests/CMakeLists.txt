# Fixture generation (run once, then commit the result):
# ffmpeg -y -f lavfi -i testsrc=duration=3:size=1280x720:rate=30 \
#        -f lavfi -i sine=frequency=440:duration=3:sample_rate=48000 \
#        -c:v libx264 -pix_fmt yuv420p -crf 23 -c:a aac -shortest \
#        ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/sample.mp4

include(FetchContent)
FetchContent_Declare(googletest
    URL https://github.com/google/googletest/archive/refs/tags/v1.14.0.zip)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(GhitaEditTests
    SnapEngineTest.cpp
    TimelineModelTest.cpp
    AudioDSPTest.cpp
    VideoFXTest.cpp
    ExporterRoundTripTest.cpp
    ${CMAKE_SOURCE_DIR}/src/timeline/SnapEngine.cpp
    ${CMAKE_SOURCE_DIR}/src/timeline/TimelineModel.cpp
    ${CMAKE_SOURCE_DIR}/src/timeline/TimelineCommands.cpp
    ${CMAKE_SOURCE_DIR}/src/fx/AudioDSP.cpp
    ${CMAKE_SOURCE_DIR}/src/fx/VideoFX.cpp
    ${CMAKE_SOURCE_DIR}/src/fx/FxController.cpp
    ${CMAKE_SOURCE_DIR}/src/export/Exporter.cpp
    ${CMAKE_SOURCE_DIR}/src/export/VideoEncoder.cpp
    ${CMAKE_SOURCE_DIR}/src/export/AudioEncoder.cpp
    ${CMAKE_SOURCE_DIR}/src/export/PacketMuxer.cpp
)

target_include_directories(GhitaEditTests PRIVATE ${CMAKE_SOURCE_DIR}/src)

target_compile_definitions(GhitaEditTests PRIVATE
    TEST_FIXTURE_PATH="${CMAKE_CURRENT_SOURCE_DIR}/fixtures/sample.mp4")

target_link_libraries(GhitaEditTests PRIVATE
    GTest::gtest
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::OpenGL
    Qt6::Concurrent
    ${GHITA_FFMPEG_LIBS}
)

# Use gtest_add_tests (static source-file scanning) instead of
# gtest_discover_tests (which runs the test executable at build time).
# The latter fails in this environment because the test binary needs Qt,
# FFmpeg, and other DLLs that are not on PATH during the build step.
include(GoogleTest)
gtest_add_tests(TARGET GhitaEditTests
    SOURCES
        SnapEngineTest.cpp
        TimelineModelTest.cpp
        AudioDSPTest.cpp
        VideoFXTest.cpp
        ExporterRoundTripTest.cpp
    TEST_LIST GhitaEditTests_TESTS
)
