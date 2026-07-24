#include <iostream>
#include <vector>
#include <sstream>
#include <cstring>
#include <algorithm>

#include "ghita_engine.h"
#include "ghita_c_api.h"

// Forward declare C API version function
extern "C" const char* ghita_engine_get_version(void);

static int g_passed = 0;
static int g_failed = 0;

#define TEST(name) \
    do { \
        std::cout << "Running " << name << "..." << std::flush; \
        try { \
            name(); \
            std::cout << " [PASS]" << std::endl; \
            ++g_passed; \
        } catch (const std::exception& e) { \
            std::cout << " [FAIL] " << e.what() << std::endl; \
            ++g_failed; \
        } catch (...) { \
            std::cout << " [FAIL] unknown exception" << std::endl; \
            ++g_failed; \
        } \
    } while (0)

#define EXPECT_TRUE(expr) \
    if (!(expr)) { throw std::runtime_error("EXPECT_TRUE failed: " #expr); }

#define EXPECT_FALSE(expr) \
    if (expr) { throw std::runtime_error("EXPECT_FALSE failed: " #expr); }

#define EXPECT_EQ(a, b) \
    do { \
        auto _a = (a); auto _b = (b); \
        if (!(_a == _b)) { \
            std::ostringstream _ss; \
            _ss << "EXPECT_EQ failed: " << _a << " != " << _b; \
            throw std::runtime_error(_ss.str()); \
        } \
    } while (0)

void test_engine_lifecycle() {
    GhitaEngine engine;
    EXPECT_TRUE(engine.initialize());
    EXPECT_TRUE(engine.isReady());
    engine.loadMedia("test.mp4");
    engine.play();
    EXPECT_TRUE(engine.isPlaying());
    engine.pause();
    EXPECT_FALSE(engine.isPlaying());
}

void test_render_frame_rgba() {
    GhitaEngine engine;
    engine.initialize();
    std::vector<uint8_t> buf(128 * 64 * 4, 0);
    EXPECT_TRUE(engine.renderFrameRGBA(buf.data(), 128, 64));

    for (int i = 0; i < 128 * 64; ++i) {
        EXPECT_EQ(buf[i * 4 + 3], static_cast<uint8_t>(255));
    }
}

void test_filter_brightness() {
    GhitaEngine engine;
    engine.initialize();
    engine.applyFilter(4, 0.5f);
    EXPECT_EQ(engine.getActiveFilterType(), 4);
}

void test_volume_clamp_low() {
    GhitaEngine engine;
    engine.initialize();
    engine.setVolume(-1.0f);
    EXPECT_EQ(engine.getVolume(), 0.0f);
}

void test_volume_clamp_high() {
    GhitaEngine engine;
    engine.initialize();
    engine.setVolume(5.0f);
    EXPECT_EQ(engine.getVolume(), 2.0f);
}

void test_seek_bounds() {
    GhitaEngine engine;
    engine.initialize();
    engine.seek(-100);
    EXPECT_EQ(engine.getPositionMs(), int64_t(0));

    engine.seek(99999999);
    EXPECT_EQ(engine.getPositionMs(), int64_t(60000));
}

void test_load_media_mock() {
    GhitaEngine engine;
    engine.initialize();
    engine.loadMedia("/fake/path/video.mp4");
    EXPECT_EQ(engine.getWidth(), 1280);
    EXPECT_EQ(engine.getHeight(), 720);
    EXPECT_EQ(engine.getDurationMs(), int64_t(60000));
}

void test_get_version_string() {
    const char* v = ghita_engine_get_version();
    EXPECT_TRUE(v != nullptr);
}

int main() {
    std::cout << "=== Ghita Native Engine Self-Test ===" << std::endl;

    TEST(test_engine_lifecycle);
    TEST(test_render_frame_rgba);
    TEST(test_filter_brightness);
    TEST(test_volume_clamp_low);
    TEST(test_volume_clamp_high);
    TEST(test_seek_bounds);
    TEST(test_load_media_mock);
    TEST(test_get_version_string);

    std::cout << "\n--- Result: " << g_passed << " passed, " << g_failed << " failed ---" << std::endl;

    if (g_failed > 0) {
        std::cerr << "Some tests failed!" << std::endl;
        return 1;
    }
    std::cout << "All tests passed!" << std::endl;
    return 0;
}
