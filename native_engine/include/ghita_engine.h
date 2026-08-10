#ifndef GHITA_ENGINE_H
#define GHITA_ENGINE_H

#include <string>
#include <vector>
#include <chrono>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <shared_mutex>
#include <memory>
#include <thread>
#include <sstream>
#include <unordered_map>
#include <list>
#include <iomanip>
#include <fstream>

#ifdef GHITA_HAS_FFMPEG
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
}
#endif

/**
 * @brief Transition effects supported for timeline clips.
 */
enum class TransitionType {
    None = 0,
    FadeIn = 1,
    FadeOut = 2,
    Crossfade = 3,
    // v0.4.5 new transitions
    Slide = 4,
    Wipe = 5,
    Zoom = 6,
    Dissolve = 7,
    Radial = 8
};

/**
 * @brief Keyframe interpolation types for animation curves.
 */
enum class KeyframeInterpolation {
    Linear = 0,
    EaseIn = 1,
    EaseOut = 2,
    Hold = 3
};

/**
 * @brief Media metadata structure returned by getMediaInfo.
 */
struct MediaInfo {
    std::string filePath;
    int64_t durationMs{0};
    int width{0};
    int height{0};
    double fps{0.0};
    int64_t bitrate{0};
    std::string videoCodec;
    std::string audioCodec;
    int audioSampleRate{0};
    int audioChannels{0};
    bool hasVideo{false};
    bool hasAudio{false};

    /** Serialize to JSON string. */
    std::string toJson() const {
        // v0.8.0: Escape JSON string fields — file paths containing quotes or
        // backslashes produced invalid JSON that broke Dart's parser.
        auto esc = [](const std::string& s) {
            std::ostringstream out;
            for (char c : s) {
                switch (c) {
                    case '"': out << "\\\""; break;
                    case '\\': out << "\\\\"; break;
                    case '\n': out << "\\n"; break;
                    case '\r': out << "\\r"; break;
                    case '\t': out << "\\t"; break;
                    default:
                        if (static_cast<unsigned char>(c) < 0x20) {
                            out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                                << static_cast<int>(static_cast<unsigned char>(c)) << std::dec;
                        } else {
                            out << c;
                        }
                }
            }
            return out.str();
        };
        std::ostringstream json;
        json << "{"
             << "\"filePath\":\"" << esc(filePath) << "\","
             << "\"durationMs\":" << durationMs << ","
             << "\"width\":" << width << ","
             << "\"height\":" << height << ","
             << "\"fps\":" << fps << ","
             << "\"bitrate\":" << bitrate << ","
             << "\"videoCodec\":\"" << esc(videoCodec) << "\","
             << "\"audioCodec\":\"" << esc(audioCodec) << "\","
             << "\"audioSampleRate\":" << audioSampleRate << ","
             << "\"audioChannels\":" << audioChannels << ","
             << "\"hasVideo\":" << (hasVideo ? "true" : "false") << ","
             << "\"hasAudio\":" << (hasAudio ? "true" : "false")
             << "}";
        return json.str();
    }
};

/**
 * @brief Interface for media frame decoding.
 */
class IMediaDecoder {
public:
    virtual ~IMediaDecoder() = default;

    /**
     * @brief Opens a media file.
     * @param filePath Path to input file.
     * @return true if successfully opened.
     */
    virtual bool open(const std::string& filePath) = 0;

    /**
     * @brief Decodes a single RGBA frame at the specified time position.
     */
    virtual bool decodeFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs, int filterType, float filterIntensity) = 0;

    /**
     * @brief Returns total media duration in milliseconds.
     */
    virtual int64_t getDurationMs() const = 0;

    /**
     * @brief Returns native media width in pixels.
     */
    virtual int getWidth() const = 0;

    /**
     * @brief Returns native media height in pixels.
     */
    virtual int getHeight() const = 0;

    /**
     * @brief Returns detailed media info.
     */
    virtual MediaInfo getMediaInfo() const = 0;
};

/**
 * @brief High-performance synthetic frame decoder with multi-threaded pixel synthesis.
 */
class SyntheticMediaDecoder : public IMediaDecoder {
public:
    SyntheticMediaDecoder() = default;
    bool open(const std::string& filePath) override;
    bool decodeFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs, int filterType, float filterIntensity) override;
    int64_t getDurationMs() const override { return m_durationMs; }
    int getWidth() const override { return 1280; }
    int getHeight() const override { return 720; }
    MediaInfo getMediaInfo() const override;
private:
    int64_t m_durationMs{60000};
    std::string m_filePath;
};

/**
 * @brief Production-ready FFmpeg media decoder with actual video/audio decoding.
 *
 * Uses libavformat for container parsing, libavcodec for decoding,
 * libswscale for RGB conversion, and libswresample for PCM extraction.
 * Gracefully falls back to SyntheticMediaDecoder when FFmpeg is unavailable.
 */
class RealFFmpegMediaDecoder : public IMediaDecoder {
public:
    RealFFmpegMediaDecoder();
    ~RealFFmpegMediaDecoder() override;

    bool open(const std::string& filePath) override;
    bool decodeFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs, int filterType, float filterIntensity) override;
    int64_t getDurationMs() const override { return m_durationMs; }
    int getWidth() const override { return m_width; }
    int getHeight() const override { return m_height; }
    MediaInfo getMediaInfo() const override;

    /**
     * @brief Extract decoded PCM audio samples for real waveform visualizer.
     */
    bool extractPcmAudioSamples(float* outSamples, int sampleCount, float volume);

    /**
     * @brief v0.8.0: Decode a PCM segment starting at startMs, resampled to
     * interleaved float stereo at 44100 Hz (the mixing format). Returns false
     * when the file has no decodable audio stream.
     */
    bool decodeAudioSegment(int64_t startMs, float* outSamples, int sampleCount, float volume);

    /**
     * @brief Returns true if FFmpeg is actually being used (not fallback).
     */
    bool hasFFmpeg() const { return m_hasFFmpeg; }

    /**
     * @brief v0.8.0: True when the file actually has a decodable audio stream
     * (used by the audio mixer to skip silent sources).
     */
    bool hasAudioStream() const {
#ifdef GHITA_HAS_FFMPEG
        return m_hasFFmpeg && m_audioStreamIdx >= 0;
#else
        return false;
#endif
    }

private:
    int64_t m_durationMs{60000};
    int m_width{1920};
    int m_height{1080};
    std::string m_filePath;
    bool m_hasFFmpeg{false};
    MediaInfo m_mediaInfo;

#ifdef GHITA_HAS_FFMPEG
    // FFmpeg contexts
    AVFormatContext* m_formatCtx{nullptr};
    AVCodecContext* m_videoCodecCtx{nullptr};
    AVCodecContext* m_audioCodecCtx{nullptr};
    SwsContext* m_swsCtx{nullptr};
    SwrContext* m_swrCtx{nullptr};
    // v0.8.0: Dedicated resampler to interleaved FLT stereo @ 44100 (mix format).
    SwrContext* m_mixSwrCtx{nullptr};
    // v1.0.2: When decodeAudioSegment requests a position that continues the
    // PREVIOUS call (the audio preview thread walks forward in fixed chunks),
    // skip the seek entirely and keep decoding — the per-chunk seek was the
    // source of audible ticks/stutter ("rè / lộn xộn"). -1 = no contiguous
    // position to continue from.
    int64_t m_segContinuityMs{-1};

    // v1.0.2d: PCM/WAV direct-file reader. PCM streams pack the whole file into a
    // handful of packets with no seekable index, so per-window FFmpeg
    // seek+flush lands the demuxer at EOF partway through (~50%) and the later
    // windows come back silent ("rè / lộn xộn"). v1.0.3: instead of decoding
    // the whole file into RAM (the old FLT cache peaked at ~350 KB/s of audio),
    // locate the WAV 'data' chunk once and read sample bytes directly from the
    // FILE per window — O(1) memory, no demuxer seek, works for any length.
    std::string m_pcmPath;        // file path of the PCM/WAV source
    int64_t m_pcmDataOffset{0};   // byte offset of the first sample
    int64_t m_pcmDataBytes{0};    // total bytes of sample data
    int m_pcmSrcCh{0};            // 1 or 2
    int m_pcmSrcRate{0};          // source sample rate (Hz)
    int m_pcmSrcBits{0};          // 16 (PCM int) or 32 (IEEE float)
    bool m_pcmSrcFloat{false};    // format tag 3 = float32 samples
    bool m_pcmCached{false};
    bool pcmCacheAudio();
    bool readPcmFromCache(int64_t startMs, float* outSamples, int sampleCount, float volume);
    // v1.1.0 (PLAN 2.7/B17): Persistent file handle + grow-only sample
    // buffers. The old code opened the file and allocated two vectors on
    // EVERY 100ms chunk (~10-20 opens + allocations per second of playback).
    // All access happens under m_renderMutex, so the shared handle is safe.
    std::ifstream m_pcmFile;
    std::vector<int16_t> m_pcmI16Buf;
    std::vector<float> m_pcmF32Buf;
    // v1.1.0 (PLAN 2.9): Grow-only conversion buffer for decodeAudioSegment —
    // 16384×2 floats ≈ 128 KB allocated per 100ms chunk was pure churn during
    // playback. Guarded by m_renderMutex like the other decoder buffers.
    std::vector<float> m_audioConvBuf;

    int m_videoStreamIdx{-1};
    int m_audioStreamIdx{-1};
    AVPacket* m_packet{nullptr};
    AVFrame* m_frame{nullptr};
    AVFrame* m_rgbFrame{nullptr};
    uint8_t* m_rgbBuffer{nullptr};
    int m_rgbBufferSize{0};
    // v1.0.3: Cached decoded RGBA for still images (PNG/JPEG single-frame
    // streams). Image demuxers are non-seekable — the first decode caches the
    // scaled frame and all later positions reuse it instead of re-seeking.
    std::vector<uint8_t> m_stillCache;
    int m_stillCacheW{0};
    int m_stillCacheH{0};

    bool initFFmpegContexts();
    void destroyFFmpegContexts();
    bool decodeVideoFrameAt(int64_t timeMs, uint8_t* outBuffer, int width, int height, int filterType, float filterIntensity);
    bool decodeAudioSamples(float* outSamples, int sampleCount, float volume);
#endif
};

/**
 * @brief Keyframe for animation curves.
 * v1.1.0 (PLAN 3.1-3.3): Extended — property, interpolation mode and Bezier
 * control points so keyframes are actually EVALUATED at render time (v1.0.0
 * stored them but the compositor never read them).
 */
struct Keyframe {
    int64_t timeMs{0};
    float value{0.0f};
    // Property animated by this keyframe:
    //   0 = opacity (0..1)        1 = position X offset (fraction of frame width)
    //   2 = scale (0.1..4)        3 = rotation (degrees — stored, render limited)
    //   4 = filter intensity (0..1)
    int property{0};
    // Interpolation toward the NEXT keyframe of the same property:
    //   0 = linear, 1 = step (hold), 2 = bezier (cubic via control points)
    int interpolation{0};
    // Bezier control points (only for interpolation == 2). x/y are normalized
    // to the segment between this keyframe and the next one.
    float cp1x{0.0f}, cp1y{0.0f}, cp2x{0.0f}, cp2y{0.0f};
};

/**
 * @brief Picture-in-picture geometry (v1.1.0, PLAN 3.4). All values are
 * fractions of the output frame: x/y = top-left anchor, w/h = size. The
 * overlay clip is decoded, scaled and blended at this rect.
 */
struct PipGeometry {
    float x{0.0f};
    float y{0.0f};
    float w{1.0f};
    float h{1.0f};
    float rotation{0.0f};
};

/**
 * @brief Speed-ramp point (v1.1.0, PLAN 3.11): normalized timeline position
 * [0..1] mapped to a playback speed multiplier.
 */
struct SpeedRampPoint {
    float t{0.0f};       // normalized position within the clip's timeline span
    float speed{1.0f};   // multiplier at that position
};

/**
 * @brief Transition configuration for a native timeline clip.
 */
struct NativeTransition {
    TransitionType type{TransitionType::None};
    int durationMs{500};
};

/**
 * @brief Kind of a native timeline clip (v0.8.0).
 */
enum class NativeClipKind {
    Video = 0,
    Audio = 1,
    Image = 2,
    Text = 3,
    Sticker = 4
};

/**
 * @brief Per-clip color correction parameters (v0.8.0, ranges -1.0..1.0).
 */
struct ColorCorrection {
    float exposure{0.0f};
    float contrast{0.0f};
    float saturation{0.0f};
    float temperature{0.0f};
    float tint{0.0f};
    float vibrance{0.0f};
    float highlights{0.0f};
    float shadows{0.0f};
};

/**
 * @brief Represents a clip in the native timeline.
 */
struct NativeClip {
    int id;
    std::string filePath;
    int64_t startMs;
    int64_t durationMs;
    // v0.8.0: Source in-point (where to start reading from the media file).
    int64_t sourceInMs{0};
    int trackIndex;
    int filterType;
    float filterIntensity;
    // v0.8.0: Per-clip playback properties mirrored from the Dart model.
    float volume{1.0f};   // 0.0 - 2.0
    float opacity{1.0f};  // 0.0 - 1.0
    float speed{1.0f};    // 0.25 - 4.0
    NativeClipKind kind{NativeClipKind::Video};
    // v0.8.0: Text/sticker payload (rendered via GDI on Windows).
    std::string textContent;
    float textFontSize{48.0f};
    uint32_t textColor{0xFFFFFFFF};
    // v0.8.0: Per-clip color correction (applied after the filter).
    ColorCorrection cc;
    NativeTransition transition;
    std::vector<Keyframe> keyframes; // v0.4.5: keyframe animation (v1.1.0: evaluated at render)
    // v1.1.0 (PLAN 3.3): Default interpolation applied between keyframes that
    // don't carry their own (setClipKeyframeInterpolation was a no-op before).
    int keyframeInterpolation{0};
    // v1.1.0 (PLAN 3.4): Picture-in-picture geometry — when w/h < 1 the clip
    // is rendered scaled into a rect instead of filling the frame.
    PipGeometry pip;
    // v1.1.0 (PLAN 3.11): Speed-ramp curve — when non-empty, playback speed
    // varies over the clip's timeline span instead of being constant.
    std::vector<SpeedRampPoint> speedCurve;
};

/**
 * @brief Per-track render state (v0.8.0): mute/visibility/volume.
 */
struct NativeTrackState {
    bool muted{false};
    bool visible{true};
    float volume{1.0f};
};

/**
 * @brief Core native multimedia rendering engine with C++20 concurrency primitives.
 */
class GhitaEngine {
public:
    GhitaEngine();
    
    // GhitaEngine manages atomic variables, shared_mutex, and thread resources, so copying and moving are deleted
    GhitaEngine(const GhitaEngine&) = delete;
    GhitaEngine& operator=(const GhitaEngine&) = delete;
    GhitaEngine(GhitaEngine&&) = delete;
    GhitaEngine& operator=(GhitaEngine&&) = delete;
    ~GhitaEngine();

    /** @brief Initializes the engine state and clock. */
    bool initialize();

    /** @brief Loads a media file into the active decoder. */
    bool loadMedia(const std::string& filePath);

    /** @brief Starts timeline playback. */
    void play();

    /** @brief Pauses timeline playback. */
    void pause();

    /** @brief Checks if playback is active. */
    bool isPlaying() const;

    /** @brief Seeks to target position in milliseconds. */
    void seek(int64_t positionMs);

    /** @brief Gets current playback position in milliseconds. */
    int64_t getPositionMs() const;

    /** @brief Gets total project timeline duration in milliseconds. */
    int64_t getDurationMs() const;

    /** @brief Gets target rendering frame width. */
    int getWidth() const { return m_width.load(); }

    /** @brief Gets target rendering frame height. */
    int getHeight() const { return m_height.load(); }

    /** @brief Sets master volume scaling factor (0.0 to 2.0). */
    void setVolume(float volume);

    /** @brief Gets master volume setting. */
    float getVolume() const { return m_volume.load(); }

    /** @brief Applies active filter type and intensity. */
    void applyFilter(int filterType, float intensity);

    /** @brief Returns active filter type. */
    int getActiveFilterType() const;

    /** @brief Returns active filter intensity. */
    float getFilterIntensity() const { return m_filterIntensity.load(); }

    /** @brief Checks if engine is ready for rendering. */
    bool isReady() const { return m_ready.load(); }

    // v0.8.0: Audio preview (waveOut on Windows). The engine mixes PCM from
    // the timeline's audio-bearing clips while playing and streams it to the
    // default audio device. Falls back to silence on any failure.
    void setAudioPreviewEnabled(bool enabled) { m_audioPreviewEnabled.store(enabled); }
    bool isAudioPreviewEnabled() const { return m_audioPreviewEnabled.load(); }

    // v1.0.3: Noise suppression toggle ("làm rõ âm thanh"). Applied to the
    // mixed preview audio only (one-pole low-cut); export is unaffected.
    void setNoiseSuppress(bool enabled) { m_noiseSuppress.store(enabled); }
    bool isNoiseSuppressEnabled() const { return m_noiseSuppress.load(); }

    /**
     * @brief v0.8.0: Mixs PCM (interleaved float stereo @ 44100) for the
     * window [startMs, endMs) from all clips that overlap it, applying clip
     * volume, track volume/mute and the master volume. The output buffer must
     * hold sampleCount floats. Returns true when any clip contributed audio.
     * Must be called with m_engineMutex held (read) — it takes m_renderMutex
     * for the decoder access.
     */
    bool mixAudioWindow(int64_t startMs, int64_t endMs, float* outSamples, int sampleCount, bool applyMasterVolume);

    /** @brief Renders current RGBA frame into destination memory buffer. */
    bool renderFrameRGBA(uint8_t* outBuffer, int width, int height);

    /**
     * @brief v0.7.9: Renders the frame at an explicit timeline position
     * without mutating playback state (no seek/position race). Foundation
     * for batch/thumbnail rendering from Dart.
     */
    bool renderFrameAt(uint8_t* outBuffer, int width, int height, int64_t positionMs);

    /**
     * @brief v1.1.0 (PLAN 3.5): Same as renderFrameAt but with the effects
     * (per-clip filter + color correction + global filter) skipped when
     * [applyFx] is false — the split-view "before" side renders the raw
     * timeline for a real before/after comparison.
     */
    bool renderFrameAtEx(uint8_t* outBuffer, int width, int height, int64_t positionMs, bool applyFx);

    /** @brief Returns direct memory buffer pointer for zero-copy GPU texture sharing. */
    uint8_t* getFrameDirectBufferPointer(int* outWidth, int* outHeight);

    /** @brief Returns media info as JSON string (v0.4.5). */
    std::string getMediaInfoJson() const;

    /** @brief Returns list of available filters as JSON string (v0.4.5). */
    std::string getAvailableFiltersJson() const;

    // Frame Snapping (v0.4.0)
    void setFrameSnappingFps(int fps);
    int getFrameSnappingFps() const { return m_snappingFps.load(); }

    // Timeline / Clip operations
    int addClip(const std::string& filePath, int64_t startMs, int64_t durationMs, int trackIndex);
    bool removeClip(int clipId);
    int getClipCount() const;
    bool setClipPosition(int clipId, int64_t startMs);
    bool setClipFilter(int clipId, int filterType, float intensity);
    bool setClipTransition(int clipId, TransitionType type, int durationMs);

    // v0.8.0: Full timeline sync API — the Dart side resyncs the whole
    // timeline through upsert/clear instead of the legacy addClip path.
    /** @brief Inserts or updates a clip. Returns 1 on success, 0 on failure. */
    int upsertClip(int clipId, const std::string& filePath, int64_t startMs, int64_t durationMs,
                   int64_t sourceInMs, int trackIndex, NativeClipKind kind,
                   float volume, float opacity, float speed);
    /** @brief Removes all clips and resets the timeline (new project/load). */
    void clearClips();
    /** @brief Sets mute/visible/volume for a track. Returns 1 on success. */
    int setTrackState(int trackIndex, bool muted, bool visible, float volume);
    /** @brief Sets per-clip color correction (all values -1.0..1.0). */
    int setClipColorCorrection(int clipId, const ColorCorrection& cc);
    /** @brief Sets text/sticker payload for a clip (used by GDI renderer). */
    int setClipText(int clipId, const std::string& text, float fontSize, uint32_t colorArgb);
    /** @brief Returns true when the clip exists in the native timeline. */
    bool hasClip(int clipId) const;

    // v0.4.5: Keyframe animation
    bool addClipKeyframe(int clipId, int64_t timeMs, float value);
    bool clearClipKeyframes(int clipId);

    // v1.1.0 (PLAN 3.1-3.3): Extended keyframe API — property/interpolation/
    // bezier aware. Returns 0 on success, -1 on error (mirrors C API).
    int addClipKeyframeEx(int clipId, int64_t timeMs, float value, int property,
                          int interpolation, float cp1x, float cp1y, float cp2x, float cp2y);
    int setKeyframeBezierEx(int clipId, int keyframeIndex,
                            float cp1x, float cp1y, float cp2x, float cp2y);
    int getClipKeyframeCount(int clipId) const;
    // v1.1.0 (PLAN 3.4): Picture-in-picture geometry.
    int setClipPip(int clipId, const PipGeometry& pip);
    // v1.1.0 (PLAN 3.11): Speed-ramp curve (points sorted by t).
    int setClipSpeedCurve(int clipId, const std::vector<SpeedRampPoint>& curve);
    // v1.1.0 (PLAN 3.11): Append a single speed-ramp point (kept sorted).
    int addSpeedRampPoint(int clipId, float t, float speed);

    // v0.5.5: Keyframe interpolation
    bool setClipKeyframeInterpolation(int clipId, KeyframeInterpolation interpolation);
    KeyframeInterpolation getClipKeyframeInterpolation(int clipId) const;

    // v0.5.5: Playback rate control
    void setPlaybackRate(float rate);
    float getPlaybackRate() const { return m_playbackRate.load(); }

    // v0.5.5: Text overlay rendering (basic rasterizer stub)
    bool renderTextOverlay(uint8_t* outBuffer, int width, int height,
                           const char* text, int fontSize, float r, float g, float b, float a);

    // Audio Waveform
    bool getAudioWaveform(float* outSamples, int sampleCount);

    // Export pipeline (v0.4.0 API — extended in v0.4.5 with codec params)
    bool startExport(const std::string& outputPath, int width, int height, int fps);
    float getExportProgress() const;
    bool isExporting() const;
    void cancelExport();

    // v0.4.5 Export enhancements
    bool startExportEx(const std::string& outputPath, int width, int height, int fps,
                       const std::string& codec, int64_t bitrate, bool includeAudio);
    int64_t getExportFileSize() const { return m_exportFileSize.load(); }

    // Engine self-test (used by test runner)
    static bool selfTest();

    /**
     * @brief v1.1.0 (PLAN 3.7): Extracts timeline waveform peaks for an audio
     * track — splits the timeline into [sampleCount] windows and reports the
     * peak of the real mixAudioWindow output per window (the old
     * getAudioWaveform reads the legacy single loadMedia() decoder, which
     * ignores trims/moves/multi-clip timelines).
     */
    bool getTimelineWaveform(float* outSamples, int sampleCount, int trackIndex);

    /**
     * @brief v1.1.0 (PLAN 3.6): Decodes the frame of ONE timeline clip at an
     * explicit source time (unlike getThumbnail's timeline-position hack).
     */
    bool getClipThumbnail(uint8_t* outBuffer, int width, int height, int clipId, int64_t timeMs);

    /** @brief Filter indices for runtime filter selection. */
    enum FilterType {
        FILTER_NONE = 0,
        FILTER_GRAYSCALE = 1,
        FILTER_SEPIA = 2,
        FILTER_INVERT = 3,
        FILTER_BRIGHTNESS = 4,
        // v0.4.5 new filters
        FILTER_BLUR = 5,
        FILTER_EDGE_DETECT = 6,
        FILTER_COLOR_GRADING = 7,
        FILTER_ADJUST = 8,
        FILTER_PIXELATE = 9,
        FILTER_MOSAIC = 10
    };

private:
    mutable std::shared_mutex m_engineMutex;
    std::atomic<bool> m_isPlaying{false};
    std::atomic<bool> m_ready{false};
    std::atomic<int64_t> m_currentPosMs{0};
    std::atomic<int64_t> m_durationMs{60000};

    std::atomic<int> m_width{1280};
    std::atomic<int> m_height{720};
    std::string m_loadedFilePath;

    std::atomic<float> m_volume{1.0f};
    std::atomic<int> m_snappingFps{30};

    // v0.5.5: Playback rate
    std::atomic<float> m_playbackRate{1.0f};

    // v0.7.8: Filter type is read by the export thread without the engine
    // lock — was a plain int (torn-read data race).
    std::atomic<int> m_activeFilterType{0};
    std::atomic<float> m_filterIntensity{1.0f};

    std::chrono::high_resolution_clock::time_point m_lastTickTime;

    // Active Decoder & Direct Memory Buffer
    std::unique_ptr<IMediaDecoder> m_decoder;
    std::vector<uint8_t> m_directFrameBuffer;

    // Timeline clips
    std::vector<NativeClip> m_clips;
    int m_nextClipId{1};

    // v0.8.0: Per-track render state (mute/visible/volume), indexed by trackIndex.
    std::vector<NativeTrackState> m_trackStates;

    // v0.8.0: Serializes all decoder access. RealFFmpegMediaDecoder is NOT
    // thread-safe (shared packets/frames), so concurrent render calls were a
    // data race before this mutex. The audio preview thread also takes it.
    mutable std::mutex m_renderMutex;
    // v1.0.0: Dedicated mutex for m_lastTickTime — previously the render path
    // read+updated this time_point under a shared engine lock, racing with
    // play()/seek() writes done under their own short-lived locks.
    mutable std::mutex m_tickTimeMutex;

    // v0.8.0: Per-clip decoder cache (LRU, capped) so each timeline clip keeps
    // its own FFmpeg context instead of re-opening the file every frame.
    std::unordered_map<int, std::shared_ptr<IMediaDecoder>> m_clipDecoders;
    std::list<int> m_decoderLruOrder;
    static constexpr size_t kMaxClipDecoders = 8;
    // v0.8.0: Scratch buffer for compositing (one full frame).
    std::vector<uint8_t> m_renderScratch;
    // v1.1.0 (PLAN 2.4/C3): Grow-only scratch for the per-track covering-clip
    // resolution — renderTimelineFrame fills it in ONE linear scan over the
    // startMs-sorted m_clips instead of a tracks×clips nested loop.
    std::vector<const NativeClip*> m_activeClips;
    // v1.1.0 (PLAN 2.9): Grow-only per-window mix segment buffer — allocated
    // once, reused by every mixAudioWindow call (serialized by m_renderMutex).
    std::vector<float> m_mixSegBuf;
    // v1.1.0 (PLAN 3.2): Grow-only scratch for keyframe-scaled frames.
    std::vector<uint8_t> m_scaleScratch;

    // Export state & async worker
    std::atomic<bool> m_isExporting{false};
    std::atomic<bool> m_cancelExportFlag{false};
    // v0.7.8: Set when the export pipeline fails mid-way so callers
    // can distinguish a real success (progress 1.0) from a silent failure
    std::atomic<bool> m_exportError{false};
    std::atomic<float> m_exportProgress{0.0f};
    std::atomic<int64_t> m_exportFileSize{0};
    std::string m_exportOutputPath;
    // v0.7.8: Snapshot of the media path taken under the engine lock before
    // the export thread starts (avoids racing loadMedia on m_loadedFilePath).
    std::string m_exportMediaPath;
    // v0.7.8: Serializes join() calls between cancelExport and ~GhitaEngine.
    std::mutex m_exportJoinMutex;
    std::thread m_exportThread;

    // v0.8.0: Audio preview state. The preview thread mixes 100ms chunks and
    // streams them via waveOut; it is stopped on pause/seek/destroy.
    std::atomic<bool> m_audioPreviewEnabled{true};
    std::atomic<bool> m_audioThreadRunning{false};
    std::atomic<bool> m_audioStopFlag{false};
    std::thread m_audioThread;
    // v1.0.3: Noise suppression ("làm rõ âm thanh") — a DC blocker / low-cut
    // applied to the mixed preview audio when the DAW toggle is on. Simple
    // one-pole high-pass (≈85Hz) that removes hum & rumble without touching
    // the original file data (export is unaffected).
    std::atomic<bool> m_noiseSuppress{false};
    // v1.0.2: Serializes startAudioPreviewThread/stopAudioPreviewThread —
    // play() and pause() can run on different Dart threads, and a concurrent
    // assignment/join on the same std::thread object is UB.
    std::mutex m_audioThreadMutex;

    void startAudioPreviewThread();
    void stopAudioPreviewThread();
    void audioPreviewLoop();

    void recalculateDuration();
    void runExportLoop(std::string outputPath, int width, int height, int fps);
    void runExportLoopEx(std::string outputPath, int width, int height, int fps,
                         std::string codec, int64_t bitrate, bool includeAudio);

    // v0.8.0: Timeline compositor internals (must be called with m_engineMutex
    // held; they take m_renderMutex for the actual decode).
    // v1.1.0 (PLAN 3.5): [applyFx] skips per-clip filter/cc and the global
    // filter — the "before" side of split view.
    bool renderTimelineFrame(uint8_t* outBuffer, int width, int height, int64_t posMs, bool applyFx = true);
    bool decodeClipFrame(int clipId, uint8_t* outBuffer, int width, int height,
                         int64_t sourcePosMs, int filterType, float filterIntensity);
    // v1.1.0 (PLAN 2.4/C3): Direct-clip overload — the compositor holds the
    // NativeClip& already; looking it up by id again was an O(n) scan per
    // clip per frame.
    bool decodeClipFrame(const NativeClip& clip, uint8_t* outBuffer, int width, int height,
                         int64_t sourcePosMs, int filterType, float filterIntensity);
    std::shared_ptr<IMediaDecoder> getClipDecoder(int clipId, const std::string& filePath);
    void applyColorCorrectionToBuffer(uint8_t* buffer, int width, int height,
                                      const ColorCorrection& cc) const;
    bool renderTextGdi(uint8_t* outBuffer, int width, int height, const std::string& text,
                       float fontSize, uint32_t colorArgb) const;
    // v1.1.0 (PLAN 2.8/C6): GDI text bitmap cache (LRU, bounded) — creating
    // a DIB section + font + DrawTextW per frame per text clip is expensive
    // (timeline with several text clips re-rasterizes every preview tick).
    // Identical payloads (text/font size/color/frame size) reuse the bitmap.
    // renderTextGdi is const, hence mutable. Guarded by m_renderMutex (every
    // caller of renderTextGdi holds it).
    struct TextGlyphCacheEntry {
        std::string key;
        int width{0};
        int height{0};
        std::vector<uint8_t> rgba;
    };
    mutable std::list<TextGlyphCacheEntry> m_textCache;
    static constexpr size_t kMaxTextCacheEntries = 16; // 16 × 640×360×4 ≈ 15 MB worst case

    // v1.1.0 (PLAN 2.4/C3): Keeps m_clips sorted by startMs — the timeline
    // render then resolves the covering clip per track with ONE linear scan
    // instead of a tracks×clips nested loop.
    void sortClipsByStart();

    /**
     * @brief v1.1.0 (PLAN 3.2): Keyframe state evaluated at a timeline position.
     */
    struct KeyframeState {
        float opacity{1.0f};
        float offsetX{0.0f};  // fraction of frame width
        float offsetY{0.0f};  // fraction of frame height
        float scale{1.0f};
        float filterIntensity{-1.0f}; // < 0 = use clip's own intensity
    };
    KeyframeState evalKeyframes(const NativeClip& clip, int64_t posMs) const;
    // v1.1.0 (PLAN 3.11): Playback speed at a timeline position (integrated
    // source offset helper). Constant speed when no curve is attached.
    float evalSpeedAt(const NativeClip& clip, int64_t posMs) const;
    int64_t evalSourceOffset(const NativeClip& clip, int64_t posMs) const;
};

#endif // GHITA_ENGINE_H
