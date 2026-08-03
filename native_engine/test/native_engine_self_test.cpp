#include <iostream>
#include <vector>
#include <sstream>
#include <cstring>
#include <algorithm>
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
    // v1.0.0 should be in the string
    EXPECT_TRUE(std::string(v).find("1.0.0") != std::string::npos);
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
    std::ifstream probe("test_media.mp4", std::ios::binary);
    if (!probe.good()) {
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
void test_audio_mix() {
    std::ifstream probe("test_media.mp4", std::ios::binary);
    if (!probe.good()) {
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
void test_export_with_audio() {
    std::ifstream probe("test_media.mp4", std::ios::binary);
    if (!probe.good()) {
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
    std::ifstream probe("test_media.mp4", std::ios::binary);
    if (!probe.good()) {
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

    std::cout << "\n--- Result: " << g_passed << " passed, " << g_failed << " failed ---" << std::endl;

    if (g_failed > 0) {
        std::cerr << "Some tests failed!" << std::endl;
        return 1;
    }
    std::cout << "All tests passed!" << std::endl;
    return 0;
}
