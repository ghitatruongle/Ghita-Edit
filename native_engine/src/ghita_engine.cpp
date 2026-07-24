#include "ghita_engine.h"
#include <algorithm>
#include <cstring>

namespace {
    // SIMD-style inline helpers for per-pixel filters
    struct Vec3 { uint8_t r, g, b; };

    Vec3 applyGrayscale(uint8_t r, uint8_t g, uint8_t b, float intensity) {
        const float wR = 0.299f, wG = 0.587f, wB = 0.114f;
        int gray = static_cast<int>(wR * r + wG * g + wB * b);
        return {
            static_cast<uint8_t>(std::clamp(r * (1 - intensity) + gray * intensity, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(g * (1 - intensity) + gray * intensity, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(b * (1 - intensity) + gray * intensity, 0.0f, 255.0f))
        };
    }

    Vec3 applySepia(uint8_t r, uint8_t g, uint8_t b, float intensity) {
        int sr = std::clamp(static_cast<int>(0.393f * r + 0.769f * g + 0.189f * b), 0, 255);
        int sg = std::clamp(static_cast<int>(0.349f * r + 0.686f * g + 0.168f * b), 0, 255);
        int sb = std::clamp(static_cast<int>(0.272f * r + 0.534f * g + 0.131f * b), 0, 255);
        return {
            static_cast<uint8_t>(std::clamp(r * (1 - intensity) + sr * intensity, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(g * (1 - intensity) + sg * intensity, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(b * (1 - intensity) + sb * intensity, 0.0f, 255.0f))
        };
    }

    Vec3 applyInvert(uint8_t r, uint8_t g, uint8_t b, float intensity) {
        return {
            static_cast<uint8_t>(std::clamp(r * (1 - intensity) + (255 - r) * intensity, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(g * (1 - intensity) + (255 - g) * intensity, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(b * (1 - intensity) + (255 - b) * intensity, 0.0f, 255.0f))
        };
    }

    Vec3 applyBrightness(uint8_t r, uint8_t g, uint8_t b, float intensity) {
        float factor = 1.0f + intensity; // intensity 0..1 -> multiplier 1.0..2.0
        return {
            static_cast<uint8_t>(std::clamp(r * factor, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(g * factor, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(b * factor, 0.0f, 255.0f))
        };
    }
}

GhitaEngine::GhitaEngine() {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    m_ready = false;
}

GhitaEngine::~GhitaEngine() {
    // Directly stop playback without calling pause() — pause() also locks
    // m_engineMutex which would deadlock since std::mutex is non-recursive.
    std::lock_guard<std::mutex> lock(m_engineMutex);
    m_isPlaying.store(false);
    m_ready = false;
}

bool GhitaEngine::initialize() {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    if (m_ready.load()) return true; // already initialized

    m_isPlaying.store(false);
    m_currentPosMs.store(0);
    m_volume.store(1.0f);
    m_filterIntensity.store(1.0f);
    m_activeFilterType = 0;
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    m_ready = true;
    return true;
}

bool GhitaEngine::loadMedia(const std::string& filePath) {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    m_loadedFilePath = filePath;
    m_width.store(1280);
    m_height.store(720);
    m_durationMs = 60000;
    m_currentPosMs.store(0);
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    return true;
}

void GhitaEngine::play() {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    if (!m_ready.load()) return;
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    m_isPlaying.store(true);
}

void GhitaEngine::pause() {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    m_isPlaying.store(false);
}

bool GhitaEngine::isPlaying() const {
    return m_isPlaying.load();
}

void GhitaEngine::seek(int64_t positionMs) {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    if (!m_ready.load()) return;
    m_currentPosMs = std::clamp(positionMs, (int64_t)0, m_durationMs);
    m_lastTickTime = std::chrono::high_resolution_clock::now();
}

int64_t GhitaEngine::getPositionMs() const {
    return m_currentPosMs.load();
}

int64_t GhitaEngine::getDurationMs() const {
    return m_durationMs;
}

void GhitaEngine::setVolume(float volume) {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    m_volume.store(std::clamp(volume, 0.0f, 2.0f));
}

float GhitaEngine::getVolume() const {
    return m_volume.load();
}

void GhitaEngine::applyFilter(int filterType, float intensity) {
    std::lock_guard<std::mutex> lock(m_engineMutex);
    if (filterType >= 0 && filterType <= 4) {
        m_activeFilterType = filterType;
        m_filterIntensity.store(std::clamp(intensity, 0.0f, 1.0f));
    }
}

int GhitaEngine::getActiveFilterType() const {
    return m_activeFilterType.load();
}

float GhitaEngine::getFilterIntensity() const {
    return m_filterIntensity.load();
}

void GhitaEngine::updateClock() {
    if (!m_isPlaying.load()) return;

    auto now = std::chrono::high_resolution_clock::now();
    auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastTickTime).count();
    if (elapsedMs > 0) {
        m_lastTickTime = now;
        int64_t newPos = m_currentPosMs.load() + elapsedMs;
        if (newPos >= m_durationMs) {
            newPos = m_durationMs;
            m_isPlaying.store(false);
        }
        m_currentPosMs.store(newPos);
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

    const int filterType = m_activeFilterType;
    const float intensity = m_filterIntensity.load();

    // Precompute filter weights once per frame (reduce branch overhead inside pixel loop)
    const float inv = 1.0f - intensity;

    float rCoeff[3] = {}, gCoeff[3] = {}, bCoeff[3] = {};
    switch (filterType) {
        case 1: // Grayscale
            rCoeff[0] = 0.299f; rCoeff[1] = 0.587f; rCoeff[2] = 0.114f;
            break;
        case 2: // Sepia
            rCoeff[0] = 0.393f; rCoeff[1] = 0.769f; rCoeff[2] = 0.189f;
            break;
        case 3: // Invert — uses original RGB directly
            break;
        case 4: // Brightness — uses original RGB directly
            break;
        default: // None
            break;
    }

    const float brightnessMul = 1.0f + intensity;

    // Bouncing ball
    const float cx = (std::sin(t * 2.0f) * 0.35f + 0.5f) * width;
    const float cy = (std::cos(t * 2.5f) * 0.35f + 0.5f) * height;
    const float ballR2 = 40.0f * 40.0f;

    for (int y = 0; y < height; ++y) {
        const float ny = static_cast<float>(y) / static_cast<float>(height);
        for (int x = 0; x < width; ++x) {
            const float nx = static_cast<float>(x) / static_cast<float>(width);

            // Base gradient colors
            uint8_t r = static_cast<uint8_t>((std::sin(nx * 3.14159f + t) * 0.5f + 0.5f) * 200 + 30);
            uint8_t g = static_cast<uint8_t>((std::cos(ny * 3.14159f + t * 1.5f) * 0.5f + 0.5f) * 180 + 20);
            uint8_t b = static_cast<uint8_t>((std::sin((nx + ny) * 3.14159f - t * 2.0f) * 0.5f + 0.5f) * 220 + 30);

            // Bouncing ball indicator (applied after filter to preserve effect)
            const float dx = static_cast<float>(x) - cx;
            const float dy = static_cast<float>(y) - cy;
            if (dx * dx + dy * dy < ballR2) {
                r = 255; g = 230; b = 50;
            } else if (filterType != 0) {
                Vec3 c;
                switch (filterType) {
                    case 1: c = applyGrayscale(r, g, b, intensity); break;
                    case 2: c = applySepia(r, g, b, intensity); break;
                    case 3: c = applyInvert(r, g, b, intensity); break;
                    case 4: c = applyBrightness(r, g, b, intensity); break;
                    default: c = {r, g, b}; break;
                }
                r = c.r; g = c.g; b = c.b;
            }

            const int idx = (y * width + x) * 4;
            outBuffer[idx + 0] = r;
            outBuffer[idx + 1] = g;
            outBuffer[idx + 2] = b;
            outBuffer[idx + 3] = 255; // Alpha
        }
    }
}

bool GhitaEngine::selfTest() {
    // Minimal sanity check
    GhitaEngine engine;
    if (!engine.initialize()) return false;
    if (!engine.renderFrameRGBA(nullptr, 1, 1)) return false;

    uint8_t buf[16] = {};
    if (!engine.renderFrameRGBA(buf, 4, 4)) return false;
    if (buf[3] != 255) return false; // alpha should be 255

    engine.setVolume(0.0f);
    if (engine.getVolume() != 0.0f) return false;
    engine.setVolume(3.0f);
    if (engine.getVolume() > 2.0f) return false; // clamped

    engine.applyFilter(1, 1.0f);
    if (engine.getActiveFilterType() != 1) return false;

    return true;
}
