#ifndef GHITA_ENGINE_H
#define GHITA_ENGINE_H

#include <string>
#include <vector>
#include <chrono>
#include <atomic>
#include <cstdint>
#include <mutex>

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

    int getWidth() const { return m_width; }
    int getHeight() const { return m_height; }

    void setVolume(float volume);
    float getVolume() const { return m_volume; }

    void applyFilter(int filterType, float intensity);

    bool renderFrameRGBA(uint8_t* outBuffer, int width, int height);

private:
    std::string m_loadedFilePath;
    int m_width{1280};
    int m_height{720};
    int64_t m_durationMs{30000}; // Default 30s demo duration
    
    std::atomic<bool> m_isPlaying{false};
    std::atomic<int64_t> m_currentPosMs{0};
    float m_volume{1.0f};

    int m_activeFilterType{0}; // 0 = None, 1 = Grayscale, 2 = Sepia, 3 = Invert, 4 = Brightness
    float m_filterIntensity{1.0f};

    std::chrono::high_resolution_clock::time_point m_lastTickTime;
    mutable std::mutex m_engineMutex;

    void updateClock();
    void generateSyntheticFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs);
};

#endif // GHITA_ENGINE_H
