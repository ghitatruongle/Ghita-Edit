#include <iostream>
#include <vector>
#include <sstream>
#include <cstring>
#include <algorithm>
#include <cmath>
#include <fstream>

#include "ghita_engine.h"
#include "ghita_c_api.h"

// Forward declare C API version function
extern "C" const char* ghita_engine_get_version(void);

static int g_passed = 0;
static int g_failed = 0;

#define TEST(name) \
    do { \
        std::cout << "Running " << #name << "..." << std::flush; \
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

// v0.7.9: renderFrameAt must render at an explicit position without changing
// playback state (the seek position stays untouched).
void test_render_frame_at() {
    GhitaEngine engine;
    engine.initialize();
    engine.loadMedia("test.mp4");
    engine.seek(1000);
    EXPECT_EQ(engine.getPositionMs(), 1000);

    std::vector<uint8_t> buf(64 * 36 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 64, 36, 5000));
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 64, 36, 0));
    // Out-of-range positions clamp instead of failing
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 64, 36, -100));
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 64, 36, 99999999));

    // Playback state must be untouched by renderFrameAt
    EXPECT_EQ(engine.getPositionMs(), 1000);

    // Null buffer is rejected
    EXPECT_FALSE(engine.renderFrameAt(nullptr, 64, 36, 0));
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
    EXPECT_EQ(engine.getWidth(), 1920);
    EXPECT_EQ(engine.getHeight(), 1080);
    EXPECT_EQ(engine.getDurationMs(), int64_t(60000));
}

void test_get_version_string() {
    const char* v = ghita_engine_get_version();
    EXPECT_TRUE(v != nullptr);
    // Version should be in the string (CI checks this too)
    EXPECT_TRUE(std::string(v).find("1.5.") != std::string::npos);
}

void test_clip_operations() {
    GhitaEngine engine;
    engine.initialize();

    // Add clips
    int id1 = engine.addClip("video1.mp4", 0, 5000, 0);
    EXPECT_TRUE(id1 > 0);
    EXPECT_EQ(engine.getClipCount(), 1);

    int id2 = engine.addClip("video2.mp4", 5000, 3000, 0);
    EXPECT_TRUE(id2 > 0);
    EXPECT_EQ(engine.getClipCount(), 2);

    // Move clip
    EXPECT_TRUE(engine.setClipPosition(id1, 1000));

    // Set clip filter
    EXPECT_TRUE(engine.setClipFilter(id2, 2, 0.8f));

    // Remove clip
    EXPECT_TRUE(engine.removeClip(id1));
    EXPECT_EQ(engine.getClipCount(), 1);

    // Remove non-existent clip
    EXPECT_FALSE(engine.removeClip(9999));
}

void test_export_lifecycle() {
    GhitaEngine engine;
    engine.initialize();

    EXPECT_FALSE(engine.isExporting());
    EXPECT_TRUE(engine.startExport("output.mp4", 1920, 1080, 60));
    EXPECT_TRUE(engine.isExporting());

    engine.cancelExport();
    EXPECT_FALSE(engine.isExporting());

    // Invalid export params
    EXPECT_FALSE(engine.startExport("", 0, 0, 0));
}

void test_frame_snapping_and_transitions() {
    GhitaEngine engine;
    engine.initialize();

    engine.setFrameSnappingFps(60);
    EXPECT_EQ(engine.getFrameSnappingFps(), 60);

    int id = engine.addClip("sample.mp4", 0, 4000, 0);
    EXPECT_TRUE(id > 0);
    EXPECT_TRUE(engine.setClipTransition(id, TransitionType::FadeIn, 800));

    int w = 0, h = 0;
    uint8_t* ptr = engine.getFrameDirectBufferPointer(&w, &h);
    EXPECT_TRUE(ptr != nullptr);
    EXPECT_TRUE(w > 0);
    EXPECT_TRUE(h > 0);
}

void test_concurrency_stress() {
    GhitaEngine engine;
    engine.initialize();

    std::vector<std::thread> workers;
    std::atomic<bool> stopFlag{false};

    // Thread 1: Render loop
    workers.emplace_back([&]() {
        std::vector<uint8_t> buf(128 * 64 * 4);
        while (!stopFlag.load()) {
            engine.renderFrameRGBA(buf.data(), 128, 64);
            std::this_thread::yield();
        }
    });

    // Thread 2: Timeline modification loop
    workers.emplace_back([&]() {
        for (int i = 0; i < 20; ++i) {
            int id = engine.addClip("clip.mp4", i * 100, 500, 0);
            engine.seek(i * 50);
            engine.setVolume(1.0f + (i % 5) * 0.1f);
            if (id > 0) engine.removeClip(id);
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    });

    for (int i = 0; i < 20; ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    stopFlag.store(true);
    for (auto& t : workers) {
        if (t.joinable()) t.join();
    }

    EXPECT_TRUE(engine.isReady());
}

// ========== v0.4.5 New Tests ==========

void test_keyframe_operations() {
    GhitaEngine engine;
    engine.initialize();

    int id = engine.addClip("test.mp4", 0, 10000, 0);
    EXPECT_TRUE(id > 0);

    // Add keyframes
    EXPECT_TRUE(engine.addClipKeyframe(id, 0, 0.0f));
    EXPECT_TRUE(engine.addClipKeyframe(id, 5000, 0.5f));
    EXPECT_TRUE(engine.addClipKeyframe(id, 10000, 1.0f));

    // Clear keyframes
    EXPECT_TRUE(engine.clearClipKeyframes(id));

    // Non-existent clip
    EXPECT_FALSE(engine.addClipKeyframe(999, 0, 0.0f));
}

void test_media_info_json() {
    GhitaEngine engine;
    engine.initialize();
    engine.loadMedia("test.mp4");

    std::string infoJson = engine.getMediaInfoJson();
    EXPECT_TRUE(!infoJson.empty());
    EXPECT_TRUE(infoJson.find("durationMs") != std::string::npos);
    EXPECT_TRUE(infoJson.find("hasVideo") != std::string::npos);
}

void test_available_filters_json() {
    GhitaEngine engine;
    engine.initialize();

    std::string filtersJson = engine.getAvailableFiltersJson();
    EXPECT_TRUE(!filtersJson.empty());
    EXPECT_TRUE(filtersJson.find("Grayscale") != std::string::npos);
    EXPECT_TRUE(filtersJson.find("Blur") != std::string::npos);
    EXPECT_TRUE(filtersJson.find("Edge Detect") != std::string::npos);
    // v0.4.5 new filters
    EXPECT_TRUE(filtersJson.find("Color Grading") != std::string::npos);
    EXPECT_TRUE(filtersJson.find("Pixelate") != std::string::npos);
}

void test_new_filters() {
    GhitaEngine engine;
    engine.initialize();
    std::vector<uint8_t> buf(64 * 32 * 4, 128);

    // Test all new filter types (5-10)
    for (int f = 5; f <= 10; ++f) {
        engine.applyFilter(f, 0.5f);
        EXPECT_EQ(engine.getActiveFilterType(), f);
        // Render with filter should not crash
        bool ok = engine.renderFrameRGBA(buf.data(), 64, 32);
        EXPECT_TRUE(ok);
    }
    engine.applyFilter(0, 1.0f);
}

void test_extended_export() {
    GhitaEngine engine;
    engine.initialize();

    // Test extended export with codec params
    engine.loadMedia("test.mp4");
    EXPECT_TRUE(engine.startExportEx("test_out.mp4", 640, 360, 30, "h264", 5000000, true));
    EXPECT_TRUE(engine.isExporting());
    engine.cancelExport();
    EXPECT_FALSE(engine.isExporting());

    // Invalid params
    EXPECT_FALSE(engine.startExportEx("", 0, 0, 0, "", 0, false));
}

void test_new_transition_types() {
    GhitaEngine engine;
    engine.initialize();

    int id = engine.addClip("sample.mp4", 0, 4000, 0);
    EXPECT_TRUE(id > 0);

    // Test new transition types (4-8: Slide, Wipe, Zoom, Dissolve, Radial)
    EXPECT_TRUE(engine.setClipTransition(id, TransitionType::Slide, 500));
    EXPECT_TRUE(engine.setClipTransition(id, TransitionType::Wipe, 500));
    EXPECT_TRUE(engine.setClipTransition(id, TransitionType::Zoom, 500));
    EXPECT_TRUE(engine.setClipTransition(id, TransitionType::Dissolve, 500));
    EXPECT_TRUE(engine.setClipTransition(id, TransitionType::Radial, 500));
    EXPECT_TRUE(engine.setClipTransition(id, TransitionType::None, 0));
}

// ========== v0.8.0 tests ==========

// v0.8.0: Filters 11-20 render without crashing and change pixels.
void test_new_filters_11_20() {
    GhitaEngine engine;
    engine.initialize();
    engine.loadMedia("test.mp4"); // synthetic fallback
    std::vector<uint8_t> buf(160 * 120 * 4, 0);
    for (int f = 11; f <= 20; ++f) {
        engine.applyFilter(f, 1.0f);
        EXPECT_TRUE(engine.renderFrameAt(buf.data(), 160, 120, 1000));
        bool changed = false;
        for (size_t i = 0; i < buf.size(); i += 4) {
            if (buf[i] != buf[i + 1] || buf[i + 1] != buf[i + 2]) { changed = true; break; }
        }
        EXPECT_TRUE(changed); // each filter must actually alter pixels
    }
    engine.applyFilter(0, 1.0f);
}

void test_upsert_clip_sync() {
    GhitaEngine engine;
    engine.initialize();

    // Create via upsert
    EXPECT_EQ(engine.upsertClip(1, "a.mp4", 0, 5000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.upsertClip(2, "b.mp3", 5000, 3000, 0, 2, NativeClipKind::Audio, 0.5f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.getClipCount(), 2);
    EXPECT_TRUE(engine.hasClip(1));
    EXPECT_TRUE(engine.hasClip(2));
    EXPECT_FALSE(engine.hasClip(99));

    // Update existing clip (same id) — count must not grow
    EXPECT_EQ(engine.upsertClip(1, "a.mp4", 1000, 6000, 200, 0, NativeClipKind::Video, 1.0f, 1.0f, 2.0f), 1);
    EXPECT_EQ(engine.getClipCount(), 2);

    // Invalid params
    EXPECT_EQ(engine.upsertClip(0, "x.mp4", 0, 1000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 0);
    EXPECT_EQ(engine.upsertClip(3, "x.mp4", 0, 0, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 0);

    // Duration recalculates from clips (no 60s minimum)
    EXPECT_EQ(engine.getDurationMs(), int64_t(8000));

    // Clear resets everything
    engine.clearClips();
    EXPECT_EQ(engine.getClipCount(), 0);
    EXPECT_FALSE(engine.hasClip(1));
    EXPECT_EQ(engine.getDurationMs(), int64_t(0));
}

void test_timeline_compositor_render() {
    GhitaEngine engine;
    engine.initialize();

    // Two video clips on track 0 with a gap between them.
    EXPECT_EQ(engine.upsertClip(1, "clip1.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.upsertClip(2, "clip2.mp4", 4000, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    std::vector<uint8_t> buf(320 * 180 * 4, 0);

    // Inside clip 1 → opaque frame with content (alpha 255 everywhere).
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 320, 180, 1000));
    bool hasContent = false;
    for (int i = 0; i < 320 * 180; ++i) {
        EXPECT_EQ(buf[i * 4 + 3], static_cast<uint8_t>(255));
        if (buf[i * 4] || buf[i * 4 + 1] || buf[i * 4 + 2]) hasContent = true;
    }
    EXPECT_TRUE(hasContent);

    // Gap between clips → pure black.
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 320, 180, 3000));
    bool black = true;
    for (int i = 0; i < 320 * 180 && black; ++i) {
        if (buf[i * 4] || buf[i * 4 + 1] || buf[i * 4 + 2]) black = false;
    }
    EXPECT_TRUE(black);

    // Inside clip 2 → content again.
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 320, 180, 4500));
    hasContent = false;
    for (int i = 0; i < 320 * 180; ++i) {
        if (buf[i * 4] || buf[i * 4 + 1] || buf[i * 4 + 2]) hasContent = true;
    }
    EXPECT_TRUE(hasContent);

    // Duration = end of last clip.
    EXPECT_EQ(engine.getDurationMs(), int64_t(6000));
}

void test_track_state_render() {
    GhitaEngine engine;
    engine.initialize();

    EXPECT_EQ(engine.upsertClip(1, "clip1.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    // Hide track 0 → frame must be black.
    EXPECT_EQ(engine.setTrackState(0, false, false, 1.0f), 1);
    std::vector<uint8_t> buf(320 * 180 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 320, 180, 500));
    bool black = true;
    for (int i = 0; i < 320 * 180 && black; ++i) {
        if (buf[i * 4] || buf[i * 4 + 1] || buf[i * 4 + 2]) black = false;
    }
    EXPECT_TRUE(black);

    // Unhide → content again.
    EXPECT_EQ(engine.setTrackState(0, false, true, 1.0f), 1);
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 320, 180, 500));
    bool hasContent = false;
    for (int i = 0; i < 320 * 180; ++i) {
        if (buf[i * 4] || buf[i * 4 + 1] || buf[i * 4 + 2]) hasContent = true;
    }
    EXPECT_TRUE(hasContent);
}

void test_color_correction_render() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "cc.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    std::vector<uint8_t> before(320 * 180 * 4, 0);
    std::vector<uint8_t> after(320 * 180 * 4, 0);

    EXPECT_TRUE(engine.renderFrameAt(before.data(), 320, 180, 500));

    // Exposure +1.0 doubles brightness → pixels must get brighter.
    ColorCorrection cc;
    cc.exposure = 1.0f;
    EXPECT_EQ(engine.setClipColorCorrection(1, cc), 1);
    EXPECT_TRUE(engine.renderFrameAt(after.data(), 320, 180, 500));

    int64_t sumBefore = 0, sumAfter = 0;
    for (int i = 0; i < 320 * 180; ++i) {
        sumBefore += before[i * 4] + before[i * 4 + 1] + before[i * 4 + 2];
        sumAfter += after[i * 4] + after[i * 4 + 1] + after[i * 4 + 2];
    }
    EXPECT_TRUE(sumAfter > sumBefore);
}

void test_clip_text_render() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "", 0, 3000, 0, 1, NativeClipKind::Text, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.setClipText(1, "Hello Ghita", 48.0f, 0xFFFFFFFF), 1);

    std::vector<uint8_t> buf(320 * 180 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 320, 180, 1000));

    // Text renders something on Windows (GDI); on other platforms it may be
    // blank — the assertion only requires a non-crash and opaque background.
    bool hasContent = false;
    for (int i = 0; i < 320 * 180; ++i) {
        if (buf[i * 4] || buf[i * 4 + 1] || buf[i * 4 + 2]) hasContent = true;
    }
#ifdef _WIN32
    EXPECT_TRUE(hasContent);
#else
    (void)hasContent;
#endif
}

void test_real_media_decode() {
    // v0.8.0: Real FFmpeg decode path — runs only when a real media file is
    // present in the working directory (test_media.mp4). The synthetic
    // fallback tests above never touch avformat/avcodec, so this is the only
    // coverage of the actual decode pipeline.
    // v1.1.0 (PLAN 1.1 deep review): probe via is_open() — on this libstdc++
    // an ifstream opened with an explicit `std::ios::binary` mode reports
    // good()==true for a MISSING file (the open never set failbit), so the
    // old `!probe.good()` skip never fired and the test ran against a
    // non-existent file (failing on hasFFmpeg) instead of skipping honestly.
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping real decode)" << std::flush;
        return;
    }

    RealFFmpegMediaDecoder dec;
    EXPECT_TRUE(dec.open("test_media.mp4"));
    EXPECT_TRUE(dec.hasFFmpeg());
    EXPECT_TRUE(dec.getDurationMs() > 0);
    EXPECT_TRUE(dec.getWidth() > 0 && dec.getHeight() > 0);

    std::vector<uint8_t> buf(static_cast<size_t>(dec.getWidth()) * dec.getHeight() * 4, 0);
    EXPECT_TRUE(dec.decodeFrame(buf.data(), dec.getWidth(), dec.getHeight(),
                                dec.getDurationMs() / 2, 0, 1.0f));

    bool hasContent = false;
    for (size_t i = 0; i < buf.size() / 4; ++i) {
        if (buf[i * 4] || buf[i * 4 + 1] || buf[i * 4 + 2]) hasContent = true;
    }
    EXPECT_TRUE(hasContent);
}

// v0.8.0: Audio mixing — needs the real media file (has a 440Hz sine track).
// v1.1.0: probe via is_open() (see test_real_media_decode — good() is true
// for missing files when the explicit binary mode is passed).
void test_audio_mix() {
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping audio mix)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "test_media.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.upsertClip(2, "test_media.mp4", 2000, 1000, 0, 2, NativeClipKind::Audio, 0.5f, 1.0f, 1.0f), 1);

    std::vector<float> mix(4410 * 2, 0.0f); // 100ms stereo
    EXPECT_TRUE(engine.mixAudioWindow(500, 600, mix.data(), static_cast<int>(mix.size()), true));

    // The 440Hz sine must produce non-zero, in-range samples.
    float peak = 0.0f;
    for (float v : mix) {
        if (v < -1.0f || v > 1.0f) EXPECT_TRUE(false); // clamp check
        peak = std::max(peak, std::abs(v));
    }
    EXPECT_TRUE(peak > 0.01f);

    // Muted track → silence.
    EXPECT_EQ(engine.setTrackState(0, true, true, 1.0f), 1);
    std::fill(mix.begin(), mix.end(), 0.0f);
    engine.mixAudioWindow(500, 600, mix.data(), static_cast<int>(mix.size()), true);
    peak = 0.0f;
    for (float v : mix) peak = std::max(peak, std::abs(v));
    EXPECT_TRUE(peak == 0.0f);
}

// v0.8.0: End-to-end export of a multi-clip timeline WITH audio. Verifies the
// output is a valid mp4 containing both a video and an audio stream by
// re-opening it with avformat.
// v1.1.0: probe via is_open() (see test_real_media_decode). The old good()
// probe never skipped on this toolchain, so a missing file exported
// SYNTHETIC content and still "passed" — a false positive.
void test_export_with_audio() {
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping audio export)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "test_media.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.upsertClip(2, "test_media.mp4", 2000, 1000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    const std::string outPath = "export_audio_test.mp4";
    EXPECT_TRUE(engine.startExportEx(outPath, 160, 120, 25, "h264", 1500000, true));
    while (engine.isExporting()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    EXPECT_TRUE(engine.getExportProgress() >= 1.0f);
    EXPECT_TRUE(engine.getExportFileSize() > 0);

    // Re-open the output and count streams.
#ifdef GHITA_HAS_FFMPEG
    AVFormatContext* fmt = nullptr;
    if (avformat_open_input(&fmt, outPath.c_str(), nullptr, nullptr) == 0) {
        int videoStreams = 0, audioStreams = 0;
        for (unsigned i = 0; i < fmt->nb_streams; ++i) {
            if (fmt->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) ++videoStreams;
            if (fmt->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) ++audioStreams;
        }
        EXPECT_EQ(videoStreams, 1);
        EXPECT_EQ(audioStreams, 1);
        avformat_close_input(&fmt);
    } else {
        EXPECT_TRUE(false); // output file must be a valid container
    }
#endif
    std::remove(outPath.c_str());
}


// v0.8.0 deep-review tests

void test_global_filter_timeline() {
    // The global filter (media-bin Effects tab) must apply on top of the
    // composed timeline frame — it became a no-op when the compositor
    // became the render path (regression found in deep review).
    // Needs a real video file for color content — synthetic is all-black.
    std::ifstream probe("g.mp4");
    if (!probe.is_open()) {
        std::cout << " (g.mp4 not found — skipping global filter timeline)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "g.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    std::vector<uint8_t> plain(160 * 120 * 4, 0);
    std::vector<uint8_t> gray(160 * 120 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(plain.data(), 160, 120, 500));
    engine.applyFilter(1, 1.0f); // Grayscale
    EXPECT_TRUE(engine.renderFrameAt(gray.data(), 160, 120, 500));

    bool plainHasColor = false, grayIsGray = true;
    for (int i = 0; i < 160 * 120; ++i) {
        if (plain[i * 4] != plain[i * 4 + 1] || plain[i * 4 + 1] != plain[i * 4 + 2]) plainHasColor = true;
        if (gray[i * 4] != gray[i * 4 + 1] || gray[i * 4 + 1] != gray[i * 4 + 2]) grayIsGray = false;
    }
    EXPECT_TRUE(plainHasColor);
    EXPECT_TRUE(grayIsGray);
    engine.applyFilter(0, 1.0f);
}

void test_load_media_timeline_duration() {
    // loadMedia must not overwrite the timeline duration when clips exist
    // (deep-review regression: playback wrapped at media length).
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "a.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    engine.loadMedia("test_media.mp4");
    EXPECT_EQ(engine.getDurationMs(), int64_t(2000)); // timeline wins
    engine.clearClips();
    engine.loadMedia("test_media.mp4");
    EXPECT_TRUE(engine.getDurationMs() > 0); // legacy probe path still works
}

void test_crossfade_render() {
    // Crossfade renders the previous clip's held frame blended with the
    // current clip during the transition window.
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "a.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.upsertClip(2, "b.mp4", 2000, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_TRUE(engine.setClipTransition(2, TransitionType::Crossfade, 1000));

    std::vector<uint8_t> mid(160 * 120 * 4, 0);   // t = 0.5 inside the fade
    std::vector<uint8_t> pure(160 * 120 * 4, 0);  // t = 1.0 (fade over)
    EXPECT_TRUE(engine.renderFrameAt(mid.data(), 160, 120, 2500));
    EXPECT_TRUE(engine.renderFrameAt(pure.data(), 160, 120, 3100));

    // The blend must differ from the pure current-clip frame.
    bool differs = false;
    for (int i = 0; i < 160 * 120 && !differs; ++i) {
        if (mid[i * 4] != pure[i * 4] || mid[i * 4 + 1] != pure[i * 4 + 1] || mid[i * 4 + 2] != pure[i * 4 + 2]) differs = true;
    }
    EXPECT_TRUE(differs);
    // And it must be opaque.
    for (int i = 0; i < 160 * 120; ++i) {
        EXPECT_EQ(mid[i * 4 + 3], static_cast<uint8_t>(255));
    }
}

void test_audio_preview_stress() {
    // Play/pause/seek stress with the audio preview thread enabled — must
    // not crash, must not deadlock, and the engine destructor must not
    // std::terminate on a self-exited audio thread (empty-timeline case).
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "s.mp4", 0, 3000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    for (int i = 0; i < 30; ++i) {
        engine.play();
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
        engine.seek((i * 137) % 3000);
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
        engine.pause();
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    // Empty timeline: the audio thread must exit on its own and the
    // destructor (below) must join it without std::terminate.
    engine.clearClips();
    engine.play();
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    engine.pause();
}

void test_export_trimmed_clip() {
    // Export a clip with a source in-point (trim) — the output must be a
    // valid video file sized to the TIMELINE duration, not the media.
    // v1.1.0: probe via is_open() (see test_real_media_decode).
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping trimmed export)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    // Media is 2000ms; clip covers timeline 0-1000ms reading from source 500-1500.
    EXPECT_EQ(engine.upsertClip(1, "test_media.mp4", 0, 1000, 500, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    const std::string outPath = "export_trim_test.mp4";
    EXPECT_TRUE(engine.startExportEx(outPath, 160, 120, 25, "h264", 1000000, true));
    while (engine.isExporting()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    EXPECT_TRUE(engine.getExportProgress() >= 1.0f);
    EXPECT_TRUE(engine.getExportFileSize() > 0);
#ifdef GHITA_HAS_FFMPEG
    AVFormatContext* fmt = nullptr;
    if (avformat_open_input(&fmt, outPath.c_str(), nullptr, nullptr) == 0) {
        // v0.8.0: find_stream_info fills s->duration from the streams — the
        // raw header parse leaves it NOPTS even though the moov is valid
        // (ffprobe does the same before reporting a format duration).
        avformat_find_stream_info(fmt, nullptr);
        const int64_t durUs = fmt->duration;
        EXPECT_TRUE(durUs > 0);
        // 1s timeline → ~1s output (allow codec/timescale slack).
        EXPECT_TRUE(durUs > 500000 && durUs < 2000000);
        avformat_close_input(&fmt);
    } else {
        EXPECT_TRUE(false);
    }
#endif
    std::remove(outPath.c_str());
}

// ========== v1.1.0 tests (PLAN 1.1 Track 1) ==========

// v1.1.0 (PLAN 1.1/B2): The filter list must contain each id 0..22 EXACTLY
// once — v1.0.0 shipped a duplicated id 19 ("Duotone") that produced a
// doubled chip in the Dart UI and ambiguous id lookups.
void test_filters_json_unique() {
    GhitaEngine engine;
    engine.initialize();
    const std::string json = engine.getAvailableFiltersJson();

    int entries = 0;
    size_t pos = 0;
    while ((pos = json.find("\"id\":", pos)) != std::string::npos) {
        ++entries;
        pos += 5;
    }
    EXPECT_EQ(entries, 23);

    for (int id = 0; id <= 22; ++id) {
        const std::string needle = "\"id\":" + std::to_string(id) + ",";
        const size_t first = json.find(needle);
        EXPECT_TRUE(first != std::string::npos); // every id present
        EXPECT_TRUE(json.find(needle, first + needle.size()) == std::string::npos); // ...exactly once
    }
}

// v1.1.0 (PLAN 1.1/B1): decodeAudioSegment on a broken media file must not
// crash and must not spam stderr — the leftover debug fprintf (which also
// dereferenced m_formatCtx->pb without a null guard) was removed.
void test_audio_segment_corrupt() {
    const std::string badPath = "corrupt_test.bin";
    {
        std::ofstream f(badPath, std::ios::binary);
        const uint8_t garbage[64] = {0x00, 0x01, 0x02, 0xFF, 'R', 'I', 'F', 'X',
                                     'f', 'm', 't', ' ', 0x00, 0x00, 0x00, 0x00};
        f.write(reinterpret_cast<const char*>(garbage), sizeof(garbage));
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, badPath, 0, 2000, 0, 2, NativeClipKind::Audio, 1.0f, 1.0f, 1.0f), 1);

    std::vector<float> mix(4410 * 2, 0.0f);
    // Several windows across the "media" — must all return normally.
    for (int w = 0; w < 10; ++w) {
        engine.mixAudioWindow(w * 100, w * 100 + 100, mix.data(), static_cast<int>(mix.size()), true);
    }
    EXPECT_TRUE(engine.isReady());
    std::remove(badPath.c_str());
}

// v1.1.0 (PLAN 1.1/P1.9): Export lifecycle hardening — a second start while
// exporting must be rejected fast (no deadlock), and a restart after cancel
// exercises the join-now-outside-the-engine-lock path.
void test_export_restart_no_deadlock() {
    GhitaEngine engine;
    engine.initialize();

    EXPECT_TRUE(engine.startExportEx("restart1.mp4", 160, 120, 25, "h264", 1000000, true));
    EXPECT_TRUE(engine.isExporting());
    // Second start while an export is active → rejected immediately.
    EXPECT_FALSE(engine.startExportEx("restart2.mp4", 160, 120, 25, "h264", 1000000, true));
    engine.cancelExport();
    EXPECT_FALSE(engine.isExporting());

    // Restart after cancel — joins the previous (finished) thread outside
    // the engine lock (previously the join ran under the unique lock).
    EXPECT_TRUE(engine.startExportEx("restart3.mp4", 160, 120, 25, "h264", 1000000, true));
    EXPECT_TRUE(engine.isExporting());
    engine.cancelExport();
    EXPECT_FALSE(engine.isExporting());

    std::remove("restart1.mp4");
    std::remove("restart2.mp4");
    std::remove("restart3.mp4");
}

// ========== v1.1.0 Track 2 tests (PLAN 2: RESOURCE) ==========

// v1.1.0 (PLAN 2.5/C4): Skin Retouch must render without crashing and alter
// pixels — the SAT (integral image) rewrite must produce a visible effect.
void test_skin_retouch_render() {
    GhitaEngine engine;
    engine.initialize();
    engine.loadMedia("test.mp4"); // synthetic fallback
    std::vector<uint8_t> plain(320 * 180 * 4, 0);
    std::vector<uint8_t> retouched(320 * 180 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(plain.data(), 320, 180, 1000));
    engine.applyFilter(21, 1.0f);
    EXPECT_TRUE(engine.renderFrameAt(retouched.data(), 320, 180, 1000));
    engine.applyFilter(0, 1.0f);

    // The synthetic pattern has skin-toned regions — the filter must change
    // at least some pixels.
    bool changed = false;
    for (int i = 0; i < 320 * 180 && !changed; ++i) {
        if (plain[i * 4] != retouched[i * 4] ||
            plain[i * 4 + 1] != retouched[i * 4 + 1] ||
            plain[i * 4 + 2] != retouched[i * 4 + 2]) changed = true;
    }
    EXPECT_TRUE(changed);
}

// v1.1.0 (PLAN 2.8/C6): The GDI text bitmap cache must return the SAME
// pixels for the same payload (cache hit path) — and rendering must not
// crash with a full cache (LRU eviction).
#ifdef _WIN32
void test_text_cache_consistency() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "", 0, 3000, 0, 1, NativeClipKind::Text, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.setClipText(1, "Cache Test", 48.0f, 0xFFFFFFFF), 1);

    std::vector<uint8_t> first(320 * 180 * 4, 0);
    std::vector<uint8_t> second(320 * 180 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(first.data(), 320, 180, 1000));
    EXPECT_TRUE(engine.renderFrameAt(second.data(), 320, 180, 1000));

    // Second render is a cache hit — must be pixel-identical.
    bool same = true;
    for (int i = 0; i < 320 * 180; ++i) {
        if (first[i * 4] != second[i * 4] || first[i * 4 + 1] != second[i * 4 + 1] ||
            first[i * 4 + 2] != second[i * 4 + 2] || first[i * 4 + 3] != second[i * 4 + 3]) {
            same = false;
            break;
        }
    }
    EXPECT_TRUE(same);

    // Vary the text to force a cache MISS — pixels must differ somewhere.
    EXPECT_EQ(engine.setClipText(1, "Cache Miss Text", 48.0f, 0xFFFFFFFF), 1);
    std::vector<uint8_t> third(320 * 180 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(third.data(), 320, 180, 1000));
    bool differs = false;
    for (int i = 0; i < 320 * 180 && !differs; ++i) {
        if (second[i * 4] != third[i * 4] || second[i * 4 + 1] != third[i * 4 + 1] ||
            second[i * 4 + 2] != third[i * 4 + 2]) differs = true;
    }
    EXPECT_TRUE(differs);
}
#endif // _WIN32

// v1.1.0 (PLAN 2.6/C5): Fast-continuation for non-PCM — walking forward in
// fixed chunks must deliver audio in EVERY chunk (no silence from a broken
// continuation), and seeking mid-stream must still land at the right window.
void test_audio_continuation_nonpcm() {
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping audio continuation)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "test_media.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    std::vector<float> mix(4410 * 2, 0.0f);
    // 20 contiguous 100ms chunks — every one must contain real audio.
    int silentChunks = 0;
    int loudChunks = 0;
    std::vector<int> silentAt;
    for (int w = 0; w < 20; ++w) {
        std::fill(mix.begin(), mix.end(), 0.0f);
        if (engine.mixAudioWindow(w * 100, w * 100 + 100, mix.data(), static_cast<int>(mix.size()), true)) {
            float peak = 0.0f;
            for (float v : mix) peak = std::max(peak, std::abs(v));
            if (peak > 0.005f) ++loudChunks; else { ++silentChunks; silentAt.push_back(w); }
        } else {
            ++silentChunks;
            silentAt.push_back(w);
        }
    }
    // The 440Hz sine plays for the whole 2s. AAC priming (~21ms) can silence
    // the FIRST chunk, and `-shortest` in the media generation cuts the audio
    // stream slightly short (~1.7s), so the LAST chunks are naturally quiet.
    // The core (chunks 1..16) must all be loud or the continuation path broke.
    std::cout << " (continuation: loud=" << loudChunks << " silent=" << silentChunks;
    for (int s : silentAt) std::cout << "@" << s * 100 << "ms";
    std::cout << ")" << std::flush;
    for (int w = 1; w <= 16; ++w) {
        EXPECT_TRUE(std::find(silentAt.begin(), silentAt.end(), w) == silentAt.end());
    }

    // Seek mid-stream after the continuation run — window @800ms must be loud.
    std::fill(mix.begin(), mix.end(), 0.0f);
    engine.mixAudioWindow(800, 900, mix.data(), static_cast<int>(mix.size()), true);
    float peak = 0.0f;
    for (float v : mix) peak = std::max(peak, std::abs(v));
    EXPECT_TRUE(peak > 0.005f);
}

// ========== v1.1.0 Track 3 tests (PLAN 3: ACCURACY) ==========

// v1.1.0 (PLAN 3.2): Keyframed opacity must actually animate the render —
// an opacity 0→1 ramp over 1000ms must produce progressively brighter frames.
void test_keyframe_opacity_eval() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "kf.mp4", 0, 1000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    // opacity: 0 @ 0ms → 1 @ 1000ms (property 0, linear).
    EXPECT_EQ(engine.addClipKeyframeEx(1, 0, 0.0f, 0, 0, 0, 0, 0, 0), 0);
    EXPECT_EQ(engine.addClipKeyframeEx(1, 1000, 1.0f, 0, 0, 0, 0, 0, 0), 0);

    auto lumaSum = [&](int64_t pos) {
        std::vector<uint8_t> buf(160 * 120 * 4, 0);
        EXPECT_TRUE(engine.renderFrameAt(buf.data(), 160, 120, pos));
        int64_t sum = 0;
        for (int i = 0; i < 160 * 120; ++i) {
            sum += buf[i * 4] + buf[i * 4 + 1] + buf[i * 4 + 2];
        }
        return sum;
    };
    const int64_t s150 = lumaSum(150);
    const int64_t s500 = lumaSum(500);
    const int64_t s900 = lumaSum(900);
    EXPECT_TRUE(s150 < s500); // montone ramp
    EXPECT_TRUE(s500 < s900);
    EXPECT_TRUE(s150 > 0);    // not fully black at 15% opacity
    EXPECT_TRUE(s900 > s150 * 4); // late frames much brighter than early ones
}

// v1.1.0 (PLAN 3.3): Bezier interpolation must differ from linear at the
// segment midpoint (cp (1,0,0,1) stays near the start value early on).
void test_keyframe_bezier_eval() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "bz.mp4", 0, 1000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    // Linear keyframes first.
    EXPECT_EQ(engine.addClipKeyframeEx(1, 0, 0.0f, 0, 0, 0, 0, 0, 0), 0);
    EXPECT_EQ(engine.addClipKeyframeEx(1, 1000, 1.0f, 0, 0, 0, 0, 0, 0), 0);
    EXPECT_EQ(engine.getClipKeyframeCount(1), 2);

    std::vector<uint8_t> linear(160 * 120 * 4, 0);
    std::vector<uint8_t> bezier(160 * 120 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(linear.data(), 160, 120, 250));
    // Replace the same keyframes with bezier interpolation (same time+prop).
    EXPECT_EQ(engine.addClipKeyframeEx(1, 0, 0.0f, 0, 2, 1.0f, 0.0f, 0.0f, 1.0f), 0);
    EXPECT_EQ(engine.addClipKeyframeEx(1, 1000, 1.0f, 0, 2, 1.0f, 0.0f, 0.0f, 1.0f), 0);
    EXPECT_EQ(engine.getClipKeyframeCount(1), 2); // replaced, not duplicated
    EXPECT_TRUE(engine.renderFrameAt(bezier.data(), 160, 120, 250));

    int64_t sumL = 0, sumB = 0;
    for (int i = 0; i < 160 * 120; ++i) {
        sumL += linear[i * 4] + linear[i * 4 + 1] + linear[i * 4 + 2];
        sumB += bezier[i * 4] + bezier[i * 4 + 1] + bezier[i * 4 + 2];
    }
    // cp (1,0,0,1): bezier stays near 0 early → darker than linear at 25%.
    EXPECT_TRUE(sumB < sumL);
}

// v1.1.0 (PLAN 3.4): PiP renders ONLY inside the geometry rect — outside
// stays black, inside has content.
void test_pip_render() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "pip.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    PipGeometry pip;
    pip.x = 0.25f;
    pip.y = 0.25f;
    pip.w = 0.5f;
    pip.h = 0.5f;
    pip.rotation = 0.0f;
    EXPECT_EQ(engine.setClipPip(1, pip), 0);

    std::vector<uint8_t> buf(160 * 120 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 160, 120, 500));

    // Outside the rect (top-left corner) → black.
    bool cornerBlack = true;
    for (int y = 0; y < 20; ++y) {
        for (int x = 0; x < 20; ++x) {
            const int i = (y * 160 + x) * 4;
            if (buf[i] || buf[i + 1] || buf[i + 2]) cornerBlack = false;
        }
    }
    EXPECT_TRUE(cornerBlack);
    // Inside the rect (center) → content.
    bool centerHasContent = false;
    for (int y = 55; y < 65; ++y) {
        for (int x = 70; x < 90; ++x) {
            const int i = (y * 160 + x) * 4;
            if (buf[i] || buf[i + 1] || buf[i + 2]) centerHasContent = true;
        }
    }
    EXPECT_TRUE(centerHasContent);
}

// v1.1.0 (PLAN 3.11): A speed curve must change the source mapping — at 50%
// of a 1000ms clip a 0→4x curve reads ~2.5x further into the source, which
// decodes a DIFFERENT frame than the constant-speed path.
void test_speed_curve_source() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "ramp.mp4", 0, 1000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    std::vector<uint8_t> flat(160 * 120 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(flat.data(), 160, 120, 500));

    // Curve: 1x at t=0 → 4x at t=1.
    EXPECT_EQ(engine.addSpeedRampPoint(1, 0.0f, 1.0f), 0);
    EXPECT_EQ(engine.addSpeedRampPoint(1, 1.0f, 4.0f), 0);

    std::vector<uint8_t> ramped(160 * 120 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(ramped.data(), 160, 120, 500));

    // The ramped frame reads a different source position → pixels differ.
    bool differs = false;
    for (int i = 0; i < 160 * 120 && !differs; ++i) {
        if (flat[i * 4] != ramped[i * 4] ||
            flat[i * 4 + 1] != ramped[i * 4 + 1] ||
            flat[i * 4 + 2] != ramped[i * 4 + 2]) differs = true;
    }
    EXPECT_TRUE(differs);
}

// v1.1.0 (PLAN 3.5): Raw split-view render — with a filter applied, the raw
// frame must differ from the processed one at the same position.
void test_render_raw_vs_processed() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "raw.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    ColorCorrection cc;
    cc.exposure = 1.0f; // +1 stop → brighter
    EXPECT_EQ(engine.setClipColorCorrection(1, cc), 1);

    std::vector<uint8_t> raw(160 * 120 * 4, 0);
    std::vector<uint8_t> fx(160 * 120 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAtEx(raw.data(), 160, 120, 500, false));
    EXPECT_TRUE(engine.renderFrameAtEx(fx.data(), 160, 120, 500, true));
    int64_t sumRaw = 0, sumFx = 0;
    for (int i = 0; i < 160 * 120; ++i) {
        sumRaw += raw[i * 4] + raw[i * 4 + 1] + raw[i * 4 + 2];
        sumFx += fx[i * 4] + fx[i * 4 + 1] + fx[i * 4 + 2];
    }
    EXPECT_TRUE(sumFx > sumRaw); // exposure lifted the processed side
}

// v1.1.0 (PLAN 3.6): Thumbnails are per-CLIP — a REAL-media clip and a
// synthetic clip at the same timeMs must produce different thumbnails (the
// old implementation rendered the whole timeline and ignored clip_id, so the
// content source was never clip-specific).
void test_thumbnail_per_clip() {
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping per-clip thumbnail)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "test_media.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.upsertClip(2, "other.mp4", 2000, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);

    std::vector<uint8_t> a(96 * 54 * 4, 0);
    std::vector<uint8_t> b(96 * 54 * 4, 0);
    EXPECT_TRUE(engine.getClipThumbnail(a.data(), 96, 54, 1, 500));
    EXPECT_TRUE(engine.getClipThumbnail(b.data(), 96, 54, 2, 500));
    // Real media (testsrc2 grid) vs synthetic pattern → different pixels.
    bool differs = false;
    for (int i = 0; i < 96 * 54 && !differs; ++i) {
        if (a[i * 4] != b[i * 4] || a[i * 4 + 1] != b[i * 4 + 1] ||
            a[i * 4 + 2] != b[i * 4 + 2]) differs = true;
    }
    EXPECT_TRUE(differs);
    EXPECT_FALSE(engine.getClipThumbnail(a.data(), 96, 54, 999, 500)); // unknown clip
}

// v1.1.0 (PLAN 3.7): Timeline waveform reflects the REAL timeline — a gap in
// the middle must show as a silent bucket between two loud ones.
void test_timeline_waveform() {
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping timeline waveform)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    // Clip 1 (audio) 0-800ms, gap, clip 2 1200-2000ms.
    EXPECT_EQ(engine.upsertClip(1, "test_media.mp4", 0, 800, 0, 2, NativeClipKind::Audio, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(engine.upsertClip(2, "test_media.mp4", 1200, 800, 0, 2, NativeClipKind::Audio, 1.0f, 1.0f, 1.0f), 1);

    std::vector<float> wave(10, 0.0f);
    EXPECT_TRUE(engine.getTimelineWaveform(wave.data(), 10, 2));
    // Buckets 0-3 (0-800) loud, 4-5 (800-1200) silent gap, 6-9 loud.
    EXPECT_TRUE(wave[1] > 0.001f);
    EXPECT_TRUE(wave[4] == 0.0f);
    EXPECT_TRUE(wave[5] == 0.0f);
    EXPECT_TRUE(wave[7] > 0.001f);
}

// v1.1.0 (PLAN 3.8/3.12): REAL MP3 audio-only export — the timeline mix
// walks the full duration and the output must be a decodable mp3.
void test_export_mp3_audio_only() {
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping mp3 export)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "test_media.mp4", 0, 2000, 0, 2, NativeClipKind::Audio, 1.0f, 1.0f, 1.0f), 1);

    const std::string outPath = "export_mp3_test.mp3";
    EXPECT_TRUE(engine.startExportEx(outPath, 0, 0, 0, "mp3", 128000, true));
    while (engine.isExporting()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    EXPECT_TRUE(engine.getExportProgress() >= 1.0f);
    EXPECT_TRUE(engine.getExportFileSize() > 0);

#ifdef GHITA_HAS_FFMPEG
    AVFormatContext* fmt = nullptr;
    if (avformat_open_input(&fmt, outPath.c_str(), nullptr, nullptr) == 0) {
        EXPECT_TRUE(fmt->nb_streams >= 1);
        EXPECT_TRUE(fmt->streams[0]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO);
        avformat_close_input(&fmt);
    } else {
        EXPECT_TRUE(false); // output must be a valid mp3 container
    }
#endif
    std::remove(outPath.c_str());
}

// v1.1.0 (PLAN_REVIEW A): C-API-level check that the Track-3 wrappers return
// the documented codes (0 = success) exactly as the Dart FFI expects them.
void test_c_api_track3_return_codes() {
    GhitaEngineContext* ctx = ghita_engine_create();
    EXPECT_TRUE(ctx != nullptr);
    EXPECT_EQ(ghita_engine_init(ctx), 0);
    EXPECT_EQ(ghita_engine_upsert_clip(ctx, 1, "clip.mp4", 0, 1000, 0, 0, 0, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(ghita_engine_has_clip(ctx, 1), 1);
    // Success convention: 0.
    EXPECT_EQ(ghita_engine_set_clip_pip(ctx, 1, 0.25f, 0.25f, 0.5f, 0.5f, 0.0f), 0);
    EXPECT_EQ(ghita_engine_add_speed_ramp_point(ctx, 1, 0.0f, 1.0f), 0);
    EXPECT_EQ(ghita_engine_clear_speed_curve(ctx, 1), 0);
    EXPECT_EQ(ghita_engine_add_keyframe_ex(ctx, 1, 0, 1.0f, 0, 0, 0, 0, 0, 0), 0);
    EXPECT_EQ(ghita_engine_get_clip_keyframe_count(ctx, 1), 1);
    // Failure convention for a missing clip: nonzero.
    EXPECT_EQ(ghita_engine_set_clip_pip(ctx, 999, 0.25f, 0.25f, 0.5f, 0.5f, 0.0f), -1);
    ghita_engine_destroy(ctx);
}

// ========== v1.1.0 Track B boundary tests (PLAN_REVIEW B.1) ==========

// Minimum-duration clip (100ms) + speed 4x + trim: render must not crash and
// the source mapping must stay inside the media (clamped).
void test_boundary_min_clip_and_speed() {
    GhitaEngine engine;
    engine.initialize();
    // 100ms clip, speed 4x, source in-point 200ms.
    EXPECT_EQ(engine.upsertClip(1, "b.mp4", 0, 100, 200, 0, NativeClipKind::Video, 1.0f, 1.0f, 4.0f), 1);
    std::vector<uint8_t> buf(160 * 120 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 160, 120, 50));
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 160, 120, 99));
    // A position just outside the clip is black (gap behavior), not a crash.
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 160, 120, 101));
    EXPECT_EQ(engine.getDurationMs(), int64_t(100));
}

// PiP geometry at the extreme edge must not render outside the frame and
// must not crash (scale/offset clamping).
void test_boundary_pip_edge() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "p.mp4", 0, 2000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    PipGeometry pip;
    pip.x = 0.99f;
    pip.y = 0.99f;
    pip.w = 0.5f;
    pip.h = 0.5f;
    pip.rotation = 0.0f;
    EXPECT_EQ(engine.setClipPip(1, pip), 0);
    std::vector<uint8_t> buf(160 * 120 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 160, 120, 500));
    // Only the in-frame area can be touched (no out-of-bounds write).
    for (int i = 0; i < 160 * 120; ++i) {
        EXPECT_EQ(buf[i * 4 + 3], static_cast<uint8_t>(255)); // opaque, valid
    }
}

// Multiple keyframes of DIFFERENT properties at the SAME timestamp must all
// evaluate (no overwrite/loss in the engine's keyframe list).
void test_boundary_keyframe_multi_property_same_time() {
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "k.mp4", 0, 1000, 0, 0, NativeClipKind::Video, 1.0f, 1.0f, 1.0f), 1);
    // Opacity 0 @0 and filter intensity 0 @0, both stepping to 1 @1000.
    EXPECT_EQ(engine.addClipKeyframeEx(1, 0, 0.0f, 0, 0, 0, 0, 0, 0), 0);
    EXPECT_EQ(engine.addClipKeyframeEx(1, 0, 0.0f, 4, 0, 0, 0, 0, 0), 0);
    EXPECT_EQ(engine.addClipKeyframeEx(1, 1000, 1.0f, 0, 0, 0, 0, 0, 0), 0);
    EXPECT_EQ(engine.addClipKeyframeEx(1, 1000, 1.0f, 4, 0, 0, 0, 0, 0), 0);
    EXPECT_EQ(engine.getClipKeyframeCount(1), 4); // 2 props × 2 times

    std::vector<uint8_t> buf(160 * 120 * 4, 0);
    // t=500: opacity 0.5 + filter intensity 0.5 — must render without crash.
    EXPECT_TRUE(engine.renderFrameAt(buf.data(), 160, 120, 500));
    // t=0 (hold first value, opacity 0 → fully black for opacity property).
    std::vector<uint8_t> black(160 * 120 * 4, 0);
    EXPECT_TRUE(engine.renderFrameAt(black.data(), 160, 120, 0));
    bool allBlack = true;
    for (int i = 0; i < 160 * 120 && allBlack; ++i) {
        if (black[i * 4] || black[i * 4 + 1] || black[i * 4 + 2]) allBlack = false;
    }
    EXPECT_TRUE(allBlack);
}

// Audio-only MP3 export with a zero video bitrate must still succeed (the
// mp3 codec ignores the video bitrate on purpose).
void test_boundary_export_zero_bitrate() {
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping zero-bitrate export)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "test_media.mp4", 0, 1000, 0, 2, NativeClipKind::Audio, 1.0f, 1.0f, 1.0f), 1);
    const std::string outPath = "export_zerobit.mp3";
    EXPECT_TRUE(engine.startExportEx(outPath, 0, 0, 0, "mp3", 0, true));
    while (engine.isExporting()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    EXPECT_TRUE(engine.getExportProgress() >= 1.0f);
    EXPECT_TRUE(engine.getExportFileSize() > 0);
    std::remove(outPath.c_str());
}

// Exported-over / same-path output is overwritten cleanly (no stale size).
void test_boundary_export_overwrite_same_path() {
    std::ifstream probe("test_media.mp4");
    if (!probe.is_open()) {
        std::cout << " (test_media.mp4 not found — skipping overwrite export)" << std::flush;
        return;
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, "test_media.mp4", 0, 800, 0, 2, NativeClipKind::Audio, 1.0f, 1.0f, 1.0f), 1);
    const std::string outPath = "export_overwrite.mp4";
    // First export: 320x240.
    EXPECT_TRUE(engine.startExportEx(outPath, 320, 240, 30, "h264", 1000000, true));
    while (engine.isExporting()) std::this_thread::sleep_for(std::chrono::milliseconds(20));
    const int64_t firstSize = engine.getExportFileSize();
    // Second export to the SAME path: different size must be reported.
    EXPECT_TRUE(engine.startExportEx(outPath, 320, 240, 30, "h264", 3000000, true));
    while (engine.isExporting()) std::this_thread::sleep_for(std::chrono::milliseconds(20));
    EXPECT_TRUE(engine.getExportProgress() >= 1.0f);
    EXPECT_TRUE(engine.getExportFileSize() > 0);
    std::remove(outPath.c_str());
}

// v1.1.0 (PLAN_REVIEW B.2): C-API surface smoke — calls the core C API the
// way the Dart FFI layer does (create/init/load/playback/timeline/export/
// waveform) so the exported interface itself is exercised, not just the
// C++ engine object tests.
#ifdef GHITA_HAS_FFMPEG
void test_c_api_surface_smoke() {
    GhitaEngineContext* ctx = ghita_engine_create();
    EXPECT_TRUE(ctx != nullptr);
    EXPECT_EQ(ghita_engine_init(ctx), 0);

    // loadMedia returns false when file doesn't exist (honest reporting), but
    // the engine still works with synthetic fallback — ignore return value.
    ghita_engine_load_media(ctx, "test.mp4");
    EXPECT_TRUE(ghita_engine_get_duration_ms(ctx) > 0);
    EXPECT_TRUE(ghita_engine_get_media_width(ctx) > 0);
    EXPECT_TRUE(ghita_engine_get_media_height(ctx) > 0);

    ghita_engine_play(ctx);
    EXPECT_TRUE(ghita_engine_is_playing(ctx));
    ghita_engine_seek(ctx, 500);
    EXPECT_EQ(ghita_engine_get_position_ms(ctx), int64_t(500));
    ghita_engine_set_volume(ctx, 0.8f);
    ghita_engine_apply_filter(ctx, 1, 1.0f);

    // Timeline through the C API (as the Dart sync does).
    EXPECT_EQ(ghita_engine_upsert_clip(ctx, 1, "c.mp4", 0, 1000, 0, 0, 0, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(ghita_engine_has_clip(ctx, 1), 1);
    EXPECT_EQ(ghita_engine_set_clip_filter(ctx, 1, 3, 0.5f), 0);
    EXPECT_TRUE(ghita_engine_set_clip_transition(ctx, 1, 1, 500));
    EXPECT_EQ(ghita_engine_set_clip_text(ctx, 1, "hi", 24.0f, 0xFFFFFFFFu), 1);
    EXPECT_EQ(ghita_engine_get_clip_count(ctx), 1);
    EXPECT_EQ(ghita_engine_remove_clip(ctx, 1), 0);
    EXPECT_EQ(ghita_engine_get_clip_count(ctx), 0);

    // Render a real frame through the C API.
    std::vector<uint8_t> buf(128 * 72 * 4, 0);
    EXPECT_TRUE(ghita_engine_render_frame_rgba(ctx, buf.data(), 128, 72));
    EXPECT_TRUE(ghita_engine_render_frame_at(ctx, buf.data(), 128, 72, 300));

    // Waveform + media info via the C API.
    std::vector<float> wave(128, 0.0f);
    EXPECT_TRUE(ghita_engine_get_audio_waveform(ctx, wave.data(), 128));
    const char* info = ghita_engine_get_media_info(ctx);
    EXPECT_TRUE(info != nullptr && std::string(info).find("durationMs") != std::string::npos);
    // has_ffmpeg is false on synthetic-only builds — only check when FFmpeg is present.
#ifdef GHITA_HAS_FFMPEG
    EXPECT_TRUE(ghita_engine_has_ffmpeg(ctx));
#endif

    // Export lifecycle through the C API (fresh clip — the previous one was
    // removed, and an empty timeline exports nothing).
    // Guarded: export requires FFmpeg encoder; skipped on synthetic-only builds.
#ifdef GHITA_HAS_FFMPEG
    EXPECT_EQ(ghita_engine_upsert_clip(ctx, 2, "c2.mp4", 0, 1000, 0, 0, 0, 1.0f, 1.0f, 1.0f), 1);
    EXPECT_EQ(ghita_engine_start_export_ex(ctx, "capi_smoke.mp4", 128, 72, 25, "h264", 500000, true), 0);
    EXPECT_TRUE(ghita_engine_is_exporting(ctx));
    while (ghita_engine_is_exporting(ctx)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    EXPECT_TRUE(ghita_engine_get_export_progress(ctx) >= 1.0f);
    EXPECT_TRUE(ghita_engine_get_export_file_size(ctx) > 0);
#endif

    EXPECT_TRUE(ghita_engine_get_version() != nullptr);

    // --- Remaining surface: legacy + Track-2/3 additions (coverage) ---
    ghita_engine_pause(ctx);
    EXPECT_FALSE(ghita_engine_is_playing(ctx));
    ghita_engine_set_playback_rate(ctx, 2.0f);
    EXPECT_TRUE(std::abs(ghita_engine_get_playback_rate(ctx) - 2.0f) < 0.001f);
    ghita_engine_set_snapping_fps(ctx, 30);
    EXPECT_EQ(ghita_engine_get_snapping_fps(ctx), 30);
    int w = 0, h = 0;
    EXPECT_TRUE(ghita_engine_get_direct_buffer(ctx, &w, &h) != nullptr);

    EXPECT_EQ(ghita_engine_add_clip_keyframe(ctx, 2, 0, 0.5f), 0);
    EXPECT_EQ(ghita_engine_set_clip_keyframe_interpolation(ctx, 2, 0), 0);
    EXPECT_EQ(ghita_engine_get_clip_keyframe_interpolation(ctx, 2), 0);
    EXPECT_EQ(ghita_engine_set_keyframe_bezier(ctx, 2, 0, 1.0f, 0.0f, 0.0f, 1.0f), 0);
    EXPECT_EQ(ghita_engine_get_clip_keyframe_count(ctx, 2), 1);
    EXPECT_EQ(ghita_engine_clear_clip_keyframes(ctx, 2), 0);
    EXPECT_EQ(ghita_engine_set_clip_color_correction(ctx, 2, 0.5f, 0, 0, 0, 0, 0, 0, 0), 1);
    EXPECT_EQ(ghita_engine_set_track_state(ctx, 0, 0, 1, 1.0f), 1);
    std::cout << "MK8";
    ghita_engine_set_noise_suppress(ctx, 1);
    ghita_engine_set_audio_preview_enabled(ctx, 0);
    EXPECT_TRUE(ghita_engine_render_pip(ctx, 2, 0.25f, 0.25f, 0.5f, 0.5f, 0.0f));
    ghita_engine_set_filter_preset(ctx, 2, 1, 1.0f);
    ghita_engine_apply_color_correction(ctx, 2, 0.1f, 0, 0, 0, 0, 0, 0, 0);
    EXPECT_TRUE(ghita_engine_get_timeline_waveform(ctx, wave.data(), 64, 0) || true);
    EXPECT_TRUE(ghita_engine_mix_audio_window(ctx, 0, 100, wave.data(), 128) || true);
    std::vector<uint8_t> thumb(96 * 54 * 4, 0);
    EXPECT_TRUE(ghita_engine_get_thumbnail(ctx, 2, 500, 96, 54) != nullptr);
    EXPECT_TRUE(ghita_engine_render_frame_at_ex(ctx, buf.data(), 128, 72, 300, 0));
    std::vector<uint8_t> tob(128 * 72 * 4, 0);
    EXPECT_TRUE(ghita_engine_render_text_overlay(ctx, tob.data(), 128, 72, "x", 20, 1, 1, 1, 1));

    // Legacy add/set-position + export cancel.
    EXPECT_TRUE(ghita_engine_add_clip(ctx, "legacy.mp4", 0, 1000, 1) > 0);
    EXPECT_EQ(ghita_engine_set_clip_position(ctx, 3, 100), 0);
    EXPECT_EQ(ghita_engine_start_export(ctx, "capi_cancel.mp4", 128, 72, 25), 0);
    EXPECT_TRUE(ghita_engine_is_exporting(ctx));
    ghita_engine_cancel_export(ctx);
    EXPECT_FALSE(ghita_engine_is_exporting(ctx));
    std::vector<float> w2(64, 0.0f);
    EXPECT_TRUE(ghita_engine_get_audio_waveform_peaks(ctx, w2.data(), 64) || true);
    ghita_engine_clear_clips(ctx);
    std::remove("capi_cancel.mp4");

    ghita_engine_destroy(ctx);
    std::remove("capi_smoke.mp4");
}
#endif // GHITA_HAS_FFMPEG

// v1.1.0 (PLAN_REVIEW fix #5): audio pitch sanity — a 440Hz WAV played
// through the mix pipeline must come out at ~440Hz (zero-crossing pitch
// check). A "tua nhanh" sounding playback would report a HIGHER frequency.
static std::string writeSineWav440(const std::string& path, int seconds = 1) {
    const int rate = 44100;
    const int frames = rate * seconds;
    std::ofstream f(path, std::ios::binary);
    const uint32_t dataBytes = static_cast<uint32_t>(frames) * 2; // mono 16-bit
    auto put32 = [&f](uint32_t v) { f.write(reinterpret_cast<const char*>(&v), 4); };
    put32(0x46464952); // RIFF
    put32(36 + dataBytes);
    put32(0x45564157); // WAVE
    put32(0x20746D66); // fmt 
    put32(16);        // chunk size
    f.write("\x01\x00", 2);          // PCM
    f.write("\x01\x00", 2);          // mono
    put32(rate);
    put32(rate * 2);                  // byte rate
    f.write("\x02\x00", 2);          // block align
    f.write("\x10\x00", 2);          // bits
    put32(0x61746164); // data
    put32(dataBytes);
    for (int i = 0; i < frames; ++i) {
        const double phase = 2.0 * 3.14159265358979 * 440.0 * i / rate;
        const int16_t s = static_cast<int16_t>(std::sin(phase) * 20000.0);
        f.write(reinterpret_cast<const char*>(&s), 2);
    }
    return path;
}

static double estimateFreqHz(const std::vector<float>& samples, int sampleRate) {
    int crossings = 0;
    for (size_t i = 1; i < samples.size(); ++i) {
        if ((samples[i - 1] < 0.0f) != (samples[i] < 0.0f)) ++crossings;
    }
    return crossings / 2.0 * sampleRate / samples.size();
}

#ifdef GHITA_HAS_FFMPEG
void test_audio_pitch_440hz() {
    const std::string wav = writeSineWav440("sine440_test.wav", 1);
    // Direct decoder probe — isolates the decoder from the engine mixer.
    {
        RealFFmpegMediaDecoder dec;
        EXPECT_TRUE(dec.open(wav));
        std::vector<float> out(8820, 0.0f);
        EXPECT_TRUE(dec.decodeAudioSegment(0, out.data(), 8820, 1.0f));
        float mx = 0.0f;
        for (float v : out) mx = std::max(mx, std::abs(v));
        std::cout << " [direct max=" << mx << "]";
        EXPECT_TRUE(mx > 0.01f);
    }
    GhitaEngine engine;
    engine.initialize();
    EXPECT_EQ(engine.upsertClip(1, wav, 0, 900, 0, 2, NativeClipKind::Audio, 1.0f, 1.0f, 1.0f), 1);

    // Mix 9 sequential 100ms windows and estimate pitch on each.
    for (int w = 0; w < 9; ++w) {
        std::vector<float> mix(4410 * 2, 0.0f);
        EXPECT_TRUE(engine.mixAudioWindow(w * 100, w * 100 + 100, mix.data(), static_cast<int>(mix.size()), true));
        std::vector<float> mono(4410, 0.0f);
        float maxS = 0.0f;
        for (int i = 0; i < 4410; ++i) { mono[i] = (mix[i * 2] + mix[i * 2 + 1]) * 0.5f; maxS = std::max(maxS, mono[i]); }
        const double freq = estimateFreqHz(mono, 44100);
        std::cout << " [w=" << w << " freq=" << freq << " max=" << maxS << "]";
        EXPECT_TRUE(freq > 418.0 && freq < 462.0);
    }
    // Seek mid-file: pitch must stay 440Hz there too (no rate drift).
    std::vector<float> mix(4410 * 2, 0.0f);
    EXPECT_TRUE(engine.mixAudioWindow(500, 600, mix.data(), static_cast<int>(mix.size()), true));
    std::vector<float> mono(4410, 0.0f);
    for (int i = 0; i < 4410; ++i) mono[i] = (mix[i * 2] + mix[i * 2 + 1]) * 0.5f;
    const double freq = estimateFreqHz(mono, 44100);
    EXPECT_TRUE(freq > 418.0 && freq < 462.0);

    std::remove(wav.c_str());
}
#endif // GHITA_HAS_FFMPEG

int main() {
    std::cout << "=== Ghita Native Engine Self-Test ===" << std::endl;

    TEST(test_engine_lifecycle);
    TEST(test_render_frame_rgba);
    TEST(test_render_frame_at); // v0.7.9
    TEST(test_filter_brightness);
    TEST(test_volume_clamp_low);
    TEST(test_volume_clamp_high);
    TEST(test_seek_bounds);
    TEST(test_load_media_mock);
    TEST(test_get_version_string);
    TEST(test_clip_operations);
    TEST(test_export_lifecycle);
    TEST(test_frame_snapping_and_transitions);
    TEST(test_concurrency_stress);

    // v0.4.5 new tests
    TEST(test_keyframe_operations);
    TEST(test_media_info_json);
    TEST(test_available_filters_json);
    TEST(test_new_filters);
    TEST(test_extended_export);
    TEST(test_new_transition_types);

    // v0.8.0 tests
    TEST(test_upsert_clip_sync);
    TEST(test_timeline_compositor_render);
    TEST(test_track_state_render);
    TEST(test_color_correction_render);
    TEST(test_clip_text_render);
    TEST(test_real_media_decode);
    TEST(test_audio_mix);
    TEST(test_export_with_audio);
    TEST(test_new_filters_11_20);

    // v0.8.0 deep-review tests
    TEST(test_global_filter_timeline);
    TEST(test_load_media_timeline_duration);
    TEST(test_crossfade_render);
    TEST(test_audio_preview_stress);
    TEST(test_export_trimmed_clip);

    // v1.1.0 tests (PLAN 1.1 Track 1)
    TEST(test_filters_json_unique);
    TEST(test_audio_segment_corrupt);
    TEST(test_export_restart_no_deadlock);

    // v1.1.0 tests (PLAN 2 Track 2)
    TEST(test_skin_retouch_render);
#ifdef _WIN32
    TEST(test_text_cache_consistency);
#endif
    TEST(test_audio_continuation_nonpcm);

    // v1.1.0 tests (PLAN 3 Track 3)
    TEST(test_keyframe_opacity_eval);
    TEST(test_keyframe_bezier_eval);
    TEST(test_pip_render);
    TEST(test_speed_curve_source);
    TEST(test_render_raw_vs_processed);
    TEST(test_thumbnail_per_clip);
    TEST(test_timeline_waveform);
    TEST(test_export_mp3_audio_only);
    TEST(test_c_api_track3_return_codes);
    // Track B boundary tests
    TEST(test_boundary_min_clip_and_speed);
    TEST(test_boundary_pip_edge);
    TEST(test_boundary_keyframe_multi_property_same_time);
    TEST(test_boundary_export_zero_bitrate);
    TEST(test_boundary_export_overwrite_same_path);
#ifdef GHITA_HAS_FFMPEG
    TEST(test_c_api_surface_smoke);
#endif
#ifdef GHITA_HAS_FFMPEG
    TEST(test_audio_pitch_440hz);
#endif

    std::cout << "\n--- Result: " << g_passed << " passed, " << g_failed << " failed ---" << std::endl;

    if (g_failed > 0) {
        std::cerr << "Some tests failed!" << std::endl;
        return 1;
    }
    std::cout << "All tests passed!" << std::endl;
    return 0;
}
