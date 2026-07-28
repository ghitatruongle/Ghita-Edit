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

/**
 * @brief Transition effects supported for timeline clips.
 */
enum class TransitionType {
    None = 0,
    FadeIn = 1,
    FadeOut = 2,
    Crossfade = 3
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
private:
    int64_t m_durationMs{60000};
};

/**
 * @brief Production-ready FFmpeg media decoder pipeline integration framework.
 * Resolves media container format, extracts PCM audio spectrum, and produces decoded RGBA frames.
 */
class RealFFmpegMediaDecoder : public IMediaDecoder {
public:
    RealFFmpegMediaDecoder() = default;
    bool open(const std::string& filePath) override;
    bool decodeFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs, int filterType, float filterIntensity) override;
    int64_t getDurationMs() const override { return m_durationMs; }
    int getWidth() const override { return m_width; }
    int getHeight() const override { return m_height; }

    /**
     * @brief Extract decoded PCM audio samples for real waveform visualizer.
     */
    bool extractPcmAudioSamples(float* outSamples, int sampleCount, float volume);

private:
    int64_t m_durationMs{60000};
    int m_width{1920};
    int m_height{1080};
    std::string m_filePath;
};

/**
 * @brief Legacy stub for FFmpeg native decoder integration.
 */
class FFmpegMediaDecoderStub : public IMediaDecoder {
public:
    FFmpegMediaDecoderStub() = default;
    bool open(const std::string& filePath) override;
    bool decodeFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs, int filterType, float filterIntensity) override;
    int64_t getDurationMs() const override { return m_durationMs; }
    int getWidth() const override { return 1920; }
    int getHeight() const override { return 1080; }
private:
    int64_t m_durationMs{60000};
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
};

/**
 * @brief Core native multimedia rendering engine with C++20 concurrency primitives.
 */
class GhitaEngine {
public:
    // Rule of Five: Explicitly declare all special member functions to prevent undefined behavior
    GhitaEngine() = default;
    
    // Delete copy operations (unique_ptr<m_decoder> makes copying invalid)
    GhitaEngine(const GhitaEngine&) = delete;
    GhitaEngine& operator=(const GhitaEngine&) = delete;
    
    // Move operations — safe and necessary
    GhitaEngine(GhitaEngine&& other) noexcept 
        : m_engineMutex(std::move(other.m_engineMutex)),
          m_isPlaying(std::move(other.m_isPlaying)),
          m_ready(std::move(other.m_ready)),
          m_currentPosMs(std::move(other.m_currentPosMs)),
          m_durationMs(std::move(other.m_durationMs)),
          m_width(std::move(other.m_width)),
          m_height(std::move(other.m_height)),
          m_loadedFilePath(std::move(other.m_loadedFilePath)),
          m_volume(std::move(other.m_volume)),
          m_snappingFps(std::move(other.m_snappingFps)),
          m_activeFilterType(other.m_activeFilterType),
          m_filterIntensity(std::move(other.m_filterIntensity)),
          m_lastTickTime(other.m_lastTickTime),
          m_decoder(std::move(other.m_decoder)),
          m_directFrameBuffer(std::move(other.m_directFrameBuffer)),
          m_clips(std::move(other.m_clips)),
          m_nextClipId(other.m_nextClipId),
          m_isExporting(std::move(other.m_isExporting)),
          m_cancelExportFlag(std::move(other.m_cancelExportFlag)),
          m_exportProgress(std::move(other.m_exportProgress)),
          m_exportOutputPath(std::move(other.m_exportOutputPath)),
          m_exportThread(std::move(other.m_exportThread)) {}
    
    GhitaEngine& operator=(GhitaEngine&& other) noexcept {
        if (this != &other) {
            // Cleanup existing resources first
            cancelExport();
            if (m_exportThread.joinable()) {
                m_exportThread.join();
            }
            
            // Move assign all members
            m_engineMutex = std::move(other.m_engineMutex);
            m_isPlaying = std::move(other.m_isPlaying);
            m_ready = std::move(other.m_ready);
            m_currentPosMs = std::move(other.m_currentPosMs);
            m_durationMs = std::move(other.m_durationMs);
            m_width = std::move(other.m_width);
            m_height = std::move(other.m_height);
            m_loadedFilePath = std::move(other.m_loadedFilePath);
            m_volume = std::move(other.m_volume);
            m_snappingFps = std::move(other.m_snappingFps);
            m_activeFilterType = other.m_activeFilterType;
            m_filterIntensity = std::move(other.m_filterIntensity);
            m_lastTickTime = other.m_lastTickTime;
            m_decoder = std::move(other.m_decoder);
            m_directFrameBuffer = std::move(other.m_directFrameBuffer);
            m_clips = std::move(other.m_clips);
            m_nextClipId = other.m_nextClipId;
            m_isExporting = std::move(other.m_isExporting);
            m_cancelExportFlag = std::move(other.m_cancelExportFlag);
            m_exportProgress = std::move(other.m_exportProgress);
            m_exportOutputPath = std::move(other.m_exportOutputPath);
            m_exportThread = std::move(other.m_exportThread);
        }
        return *this;
    }
    
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

    // Audio Waveform
    bool getAudioWaveform(float* outSamples, int sampleCount);

    // Export pipeline
    bool startExport(const std::string& outputPath, int width, int height, int fps);
    float getExportProgress() const;
    bool isExporting() const;
    void cancelExport();

    // Engine self-test (used by test runner)
    static bool selfTest();

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
    std::string m_exportOutputPath;
    std::thread m_exportThread;

    void updateClock();
    void recalculateDuration();
    void runExportLoop(std::string outputPath, int width, int height, int fps);
};

#endif // GHITA_ENGINE_H
