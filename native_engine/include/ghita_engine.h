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
        std::ostringstream json;
        json << "{"
             << "\"filePath\":\"" << filePath << "\","
             << "\"durationMs\":" << durationMs << ","
             << "\"width\":" << width << ","
             << "\"height\":" << height << ","
             << "\"fps\":" << fps << ","
             << "\"bitrate\":" << bitrate << ","
             << "\"videoCodec\":\"" << videoCodec << "\","
             << "\"audioCodec\":\"" << audioCodec << "\","
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
     * @brief Returns true if FFmpeg is actually being used (not fallback).
     */
    bool hasFFmpeg() const { return m_hasFFmpeg; }

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

    int m_videoStreamIdx{-1};
    int m_audioStreamIdx{-1};
    AVPacket* m_packet{nullptr};
    AVFrame* m_frame{nullptr};
    AVFrame* m_rgbFrame{nullptr};
    uint8_t* m_rgbBuffer{nullptr};
    int m_rgbBufferSize{0};

    bool initFFmpegContexts();
    void destroyFFmpegContexts();
    bool decodeVideoFrameAt(int64_t timeMs, uint8_t* outBuffer, int width, int height, int filterType, float filterIntensity);
    bool decodeAudioSamples(float* outSamples, int sampleCount, float volume);
#endif
};

/**
 * @brief Legacy stub for FFmpeg native decoder integration (kept for ABI compatibility).
 */
class FFmpegMediaDecoderStub : public IMediaDecoder {
public:
    FFmpegMediaDecoderStub() = default;
    bool open(const std::string& filePath) override;
    bool decodeFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs, int filterType, float filterIntensity) override;
    int64_t getDurationMs() const override { return m_durationMs; }
    int getWidth() const override { return 1920; }
    int getHeight() const override { return 1080; }
    MediaInfo getMediaInfo() const override;
private:
    int64_t m_durationMs{60000};
};

/**
 * @brief Keyframe for animation curves.
 */
struct Keyframe {
    int64_t timeMs{0};
    float value{0.0f};
};

/**
 * @brief Transition configuration for a native timeline clip.
 */
struct NativeTransition {
    TransitionType type{TransitionType::None};
    int durationMs{500};
};

/**
 * @brief Represents a clip in the native timeline.
 */
struct NativeClip {
    int id;
    std::string filePath;
    int64_t startMs;
    int64_t durationMs;
    int trackIndex;
    int filterType;
    float filterIntensity;
    NativeTransition transition;
    std::vector<Keyframe> keyframes; // v0.4.5: keyframe animation
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

    /** @brief Renders current RGBA frame into destination memory buffer. */
    bool renderFrameRGBA(uint8_t* outBuffer, int width, int height);

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

    // v0.4.5: Keyframe animation
    bool addClipKeyframe(int clipId, int64_t timeMs, float value);
    bool clearClipKeyframes(int clipId);

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

    int m_activeFilterType{0};
    std::atomic<float> m_filterIntensity{1.0f};

    std::chrono::high_resolution_clock::time_point m_lastTickTime;

    // Active Decoder & Direct Memory Buffer
    std::unique_ptr<IMediaDecoder> m_decoder;
    std::vector<uint8_t> m_directFrameBuffer;

    // Timeline clips
    std::vector<NativeClip> m_clips;
    int m_nextClipId{1};

    // Export state & async worker
    std::atomic<bool> m_isExporting{false};
    std::atomic<bool> m_cancelExportFlag{false};
    std::atomic<float> m_exportProgress{0.0f};
    std::atomic<int64_t> m_exportFileSize{0};
    std::string m_exportOutputPath;
    std::thread m_exportThread;

    void updateClock();
    void recalculateDuration();
    void runExportLoop(std::string outputPath, int width, int height, int fps);
    void runExportLoopEx(std::string outputPath, int width, int height, int fps,
                         std::string codec, int64_t bitrate, bool includeAudio);
};

#endif // GHITA_ENGINE_H
