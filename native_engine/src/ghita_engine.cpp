#include "ghita_engine.h"
#include <cmath>
#include <cstring>
#include <algorithm>

GhitaEngine::GhitaEngine() {
    m_lastTickTime = std::chrono::high_resolution_clock::now();
}

GhitaEngine::~GhitaEngine() {
    pause();
}

bool GhitaEngine::initialize() {
    m_isPlaying = false;
    m_currentPosMs = 0;
    return true;
}

bool GhitaEngine::loadMedia(const std::string& filePath) {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    m_loadedFilePath = filePath;
    m_width = 1280;
    m_height = 720;
    m_durationMs = 60000; // 60 seconds placeholder media
    m_currentPosMs = 0;
    return true;
}

void GhitaEngine::play() {
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    m_isPlaying = true;
}

void GhitaEngine::pause() {
    m_isPlaying = false;
}

bool GhitaEngine::isPlaying() const {
    return m_isPlaying;
}

void GhitaEngine::seek(int64_t positionMs) {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    m_currentPosMs = std::clamp(positionMs, (int64_t)0, m_durationMs);
    m_lastTickTime = std::chrono::high_resolution_clock::now();
}

int64_t GhitaEngine::getPositionMs() const {
    const_cast<GhitaEngine*>(this)->updateClock();
    return m_currentPosMs.load();
}

int64_t GhitaEngine::getDurationMs() const {
    return m_durationMs;
}

void GhitaEngine::setVolume(float volume) {
    m_volume = std::clamp(volume, 0.0f, 2.0f);
}

void GhitaEngine::applyFilter(int filterType, float intensity) {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    m_activeFilterType = filterType;
    m_filterIntensity = std::clamp(intensity, 0.0f, 1.0f);
}

void GhitaEngine::updateClock() {
    if (!m_isPlaying) return;

    auto now = std::chrono::high_resolution_clock::now();
    auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastTickTime).count();
    if (elapsedMs > 0) {
        m_lastTickTime = now;
        int64_t newPos = m_currentPosMs.load() + elapsedMs;
        if (newPos >= m_durationMs) {
            newPos = m_durationMs;
            m_isPlaying = false;
        }
        m_currentPosMs = newPos;
    }
}

bool GhitaEngine::renderFrameRGBA(uint8_t* outBuffer, int width, int height) {
    if (!outBuffer || width <= 0 || height <= 0) return false;

    updateClock();
    int64_t timeMs = m_currentPosMs.load();

    generateSyntheticFrame(outBuffer, width, height, timeMs);
    return true;
}

void GhitaEngine::generateSyntheticFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs) {
    float t = static_cast<float>(timeMs) / 1000.0f;

    // Generate dynamic color gradient background with moving shapes
    for (int y = 0; y < height; ++y) {
        float ny = static_cast<float>(y) / height;
        for (int x = 0; x < width; ++x) {
            float nx = static_cast<float>(x) / width;

            // Gradient pattern
            uint8_t r = static_cast<uint8_t>((std::sin(nx * 3.14159f + t) * 0.5f + 0.5f) * 200 + 30);
            uint8_t g = static_cast<uint8_t>((std::cos(ny * 3.14159f + t * 1.5f) * 0.5f + 0.5f) * 180 + 20);
            uint8_t b = static_cast<uint8_t>((std::sin((nx + ny) * 3.14159f - t * 2.0f) * 0.5f + 0.5f) * 220 + 30);

            // Bouncing ball indicator
            float cx = (std::sin(t * 2.0f) * 0.35f + 0.5f) * width;
            float cy = (std::cos(t * 2.5f) * 0.35f + 0.5f) * height;
            float dx = static_cast<float>(x) - cx;
            float dy = static_cast<float>(y) - cy;
            if (dx * dx + dy * dy < 40.0f * 40.0f) {
                r = 255; g = 230; b = 50;
            }

            // Apply Filters
            if (m_activeFilterType == 1) { // Grayscale
                uint8_t gray = static_cast<uint8_t>(0.299f * r + 0.587f * g + 0.114f * b);
                r = static_cast<uint8_t>(r * (1.0f - m_filterIntensity) + gray * m_filterIntensity);
                g = static_cast<uint8_t>(g * (1.0f - m_filterIntensity) + gray * m_filterIntensity);
                b = static_cast<uint8_t>(b * (1.0f - m_filterIntensity) + gray * m_filterIntensity);
            } else if (m_activeFilterType == 2) { // Sepia
                uint8_t sr = std::min(255, static_cast<int>(0.393f * r + 0.769f * g + 0.189f * b));
                uint8_t sg = std::min(255, static_cast<int>(0.349f * r + 0.686f * g + 0.168f * b));
                uint8_t sb = std::min(255, static_cast<int>(0.272f * r + 0.534f * g + 0.131f * b));
                r = static_cast<uint8_t>(r * (1.0f - m_filterIntensity) + sr * m_filterIntensity);
                g = static_cast<uint8_t>(g * (1.0f - m_filterIntensity) + sg * m_filterIntensity);
                b = static_cast<uint8_t>(b * (1.0f - m_filterIntensity) + sb * m_filterIntensity);
            } else if (m_activeFilterType == 3) { // Invert
                r = static_cast<uint8_t>(r * (1.0f - m_filterIntensity) + (255 - r) * m_filterIntensity);
                g = static_cast<uint8_t>(g * (1.0f - m_filterIntensity) + (255 - g) * m_filterIntensity);
                b = static_cast<uint8_t>(b * (1.0f - m_filterIntensity) + (255 - b) * m_filterIntensity);
            }

            int idx = (y * width + x) * 4;
            outBuffer[idx + 0] = r;
            outBuffer[idx + 1] = g;
            outBuffer[idx + 2] = b;
            outBuffer[idx + 3] = 255; // Alpha
        }
    }
}
