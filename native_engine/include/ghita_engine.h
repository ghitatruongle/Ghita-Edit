#ifndef GHITA_ENGINE_H
#define GHITA_ENGINE_H

#include <string>
#include <vector>
#include <chrono>
#include <atomic>
#include <cstdint>
#include <mutex>

/// Represents a clip in the native timeline.
struct NativeClip {
    int id;
    std::string filePath;
    int64_t startMs;
    int64_t durationMs;
    int trackIndex;
    int filterType;
    float filterIntensity;
};

class GhitaEngine {
public:
    GhitaEngine();
    ~GhitaEngine();

    bool initialize();
    bool loadMedia(const std::string& filePath);

    void play();
    void pause();
    bool isPlaying() const;
    void seek(int64_t positionMs);
    int64_t getPositionMs() const;
    int64_t getDurationMs() const;

    int getWidth() const { return m_width.load(); }
    int getHeight() const { return m_height.load(); }

    void setVolume(float volume);
    float getVolume() const { return m_volume.load(); }

    void applyFilter(int filterType, float intensity);
    int getActiveFilterType() const { return m_activeFilterType; }
    float getFilterIntensity() const { return m_filterIntensity.load(); }

    bool isReady() const { return m_ready.load(); }

    bool renderFrameRGBA(uint8_t* outBuffer, int width, int height);

    // Timeline / Clip operations (v0.2.0)
    int addClip(const std::string& filePath, int64_t startMs, int64_t durationMs, int trackIndex);
    bool removeClip(int clipId);
    int getClipCount() const;
    bool setClipPosition(int clipId, int64_t startMs);
    bool setClipFilter(int clipId, int filterType, float intensity);

    // Export pipeline (v0.2.0)
    bool startExport(const std::string& outputPath, int width, int height, int fps);
    float getExportProgress() const;
    bool isExporting() const;
    void cancelExport();

    // Engine self-test (used by test runner)
    static bool selfTest();

private:
    mutable std::mutex m_engineMutex;
    std::atomic<bool> m_isPlaying{false};
    std::atomic<bool> m_ready{false};
    std::atomic<int64_t> m_currentPosMs{0};
    int64_t m_durationMs{30000};

    std::atomic<int> m_width{1280};
    std::atomic<int> m_height{720};
    std::string m_loadedFilePath;

    std::atomic<float> m_volume{1.0f};

    int m_activeFilterType{0};
    std::atomic<float> m_filterIntensity{1.0f};

    std::chrono::high_resolution_clock::time_point m_lastTickTime;

    // Timeline clips (v0.2.0)
    std::vector<NativeClip> m_clips;
    int m_nextClipId{1};

    // Export state (v0.2.0)
    std::atomic<bool> m_isExporting{false};
    std::atomic<float> m_exportProgress{0.0f};
    std::string m_exportOutputPath;

    void updateClock();
    void generateSyntheticFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs);
    void recalculateDuration();
};

#endif // GHITA_ENGINE_H
