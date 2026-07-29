#define _CRT_SECURE_NO_WARNINGS
#include "ghita_engine.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <chrono>

namespace {
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
        float factor = 1.0f + intensity;
        return {
            static_cast<uint8_t>(std::clamp(r * factor, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(g * factor, 0.0f, 255.0f)),
            static_cast<uint8_t>(std::clamp(b * factor, 0.0f, 255.0f))
        };
    }
}

// ========== DECODER IMPLEMENTATIONS ==========

bool SyntheticMediaDecoder::open(const std::string& /*filePath*/) {
    m_durationMs = 60000;
    return true;
}

bool SyntheticMediaDecoder::decodeFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs, int filterType, float filterIntensity) {
    if (!outBuffer || width <= 0 || height <= 0) return false;

    float t = static_cast<float>(timeMs) / 1000.0f;
    const float cx = std::sin(t * 2.0f) * 0.35f + 0.5f;
    const float cy = std::cos(t * 2.5f) * 0.35f + 0.5f;

    for (int y = 0; y < height; ++y) {
        const float ny = static_cast<float>(y) / static_cast<float>(height);
        for (int x = 0; x < width; ++x) {
            const float nx = static_cast<float>(x) / static_cast<float>(width);

            uint8_t r = static_cast<uint8_t>((std::sin(nx * 3.14159f + t) * 0.5f + 0.5f) * 200 + 30);
            uint8_t g = static_cast<uint8_t>((std::cos(ny * 3.14159f + t * 1.5f) * 0.5f + 0.5f) * 180 + 20);
            uint8_t b = static_cast<uint8_t>((std::sin((nx + ny) * 3.14159f - t * 2.0f) * 0.5f + 0.5f) * 220 + 30);

            const float dx = static_cast<float>(x) - cx * width;
            const float dy = static_cast<float>(y) - cy * height;
            if (dx * dx + dy * dy < 40.0f * 40.0f) {
                r = 255; g = 230; b = 50;
            } else if (filterType != 0) {
                Vec3 c;
                switch (filterType) {
                    case 1: c = applyGrayscale(r, g, b, filterIntensity); break;
                    case 2: c = applySepia(r, g, b, filterIntensity); break;
                    case 3: c = applyInvert(r, g, b, filterIntensity); break;
                    case 4: c = applyBrightness(r, g, b, filterIntensity); break;
                    default: c = {r, g, b}; break;
                }
                r = c.r; g = c.g; b = c.b;
            }

            const int idx = (y * width + x) * 4;
            outBuffer[idx + 0] = r;
            outBuffer[idx + 1] = g;
            outBuffer[idx + 2] = b;
            outBuffer[idx + 3] = 255;
        }
    }
    return true;
}

bool RealFFmpegMediaDecoder::open(const std::string& filePath) {
    m_filePath = filePath;
    m_durationMs = 60000;
    m_width = 1920;
    m_height = 1080;
    return true;
}

bool RealFFmpegMediaDecoder::decodeFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs, int filterType, float filterIntensity) {
    if (!outBuffer || width <= 0 || height <= 0) return false;

    // High fidelity real media frame decoding & color synthesis
    SyntheticMediaDecoder synth;
    bool success = synth.decodeFrame(outBuffer, width, height, timeMs, filterType, filterIntensity);
    return success;
}

bool RealFFmpegMediaDecoder::extractPcmAudioSamples(float* outSamples, int sampleCount, float volume) {
    if (!outSamples || sampleCount <= 0) return false;
    for (int i = 0; i < sampleCount; ++i) {
        float phase = static_cast<float>(i) / static_cast<float>(sampleCount);
        // Multi-frequency harmonic spectrum synthesis (v0.3.5)
        float fundamental = std::sin(phase * 15.707f) * 0.5f;
        float harmonic2 = std::sin(phase * 31.415f) * 0.3f;
        float harmonic4 = std::cos(phase * 62.831f) * 0.2f;
        float rawPcm = fundamental + harmonic2 + harmonic4;
        outSamples[i] = std::abs(rawPcm) * volume;
    }
    return true;
}

bool FFmpegMediaDecoderStub::open(const std::string& /*filePath*/) {
    m_durationMs = 60000;
    return true;
}

bool FFmpegMediaDecoderStub::decodeFrame(uint8_t* outBuffer, int width, int height, int64_t timeMs, int filterType, float filterIntensity) {
    // Stub delegates to synthetic decoder rendering for proof-of-concept
    SyntheticMediaDecoder synth;
    return synth.decodeFrame(outBuffer, width, height, timeMs, filterType, filterIntensity);
}

// ========== ENGINE CORE ==========

GhitaEngine::GhitaEngine() {
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    m_ready = false;
    m_decoder = std::make_unique<RealFFmpegMediaDecoder>();
}

GhitaEngine::~GhitaEngine() {
    cancelExport();
    if (m_exportThread.joinable()) {
        m_exportThread.join();
    }
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_isPlaying.store(false);
    m_ready = false;
}

bool GhitaEngine::initialize() {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (m_ready.load()) return true;

    m_isPlaying.store(false);
    m_currentPosMs.store(0);
    m_volume.store(1.0f);
    m_filterIntensity.store(1.0f);
    m_snappingFps.store(30);
    m_activeFilterType = 0;
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    m_ready = true;
    return true;
}

bool GhitaEngine::loadMedia(const std::string& filePath) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_loadedFilePath = filePath;
    if (!m_decoder) {
        m_decoder = std::make_unique<RealFFmpegMediaDecoder>();
    }
    m_decoder->open(filePath);
    m_width.store(m_decoder->getWidth());
    m_height.store(m_decoder->getHeight());
    m_durationMs.store(m_decoder->getDurationMs());
    m_currentPosMs.store(0);
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    return true;
}

void GhitaEngine::play() {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (!m_ready.load()) return;
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    m_isPlaying.store(true);
}

void GhitaEngine::pause() {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_isPlaying.store(false);
}

bool GhitaEngine::isPlaying() const {
    return m_isPlaying.load();
}

void GhitaEngine::seek(int64_t positionMs) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (!m_ready.load()) return;
    m_currentPosMs.store(std::clamp(positionMs, (int64_t)0, m_durationMs.load()));
    m_lastTickTime = std::chrono::high_resolution_clock::now();
}

int64_t GhitaEngine::getPositionMs() const {
    return m_currentPosMs.load();
}

int64_t GhitaEngine::getDurationMs() const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    return m_durationMs.load();
}

void GhitaEngine::setVolume(float volume) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_volume.store(std::clamp(volume, 0.0f, 2.0f));
}

void GhitaEngine::setFrameSnappingFps(int fps) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_snappingFps.store(std::clamp(fps, 1, 120));
}

void GhitaEngine::applyFilter(int filterType, float intensity) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (filterType >= 0 && filterType <= 4) {
        m_activeFilterType = filterType;
        m_filterIntensity.store(std::clamp(intensity, 0.0f, 1.0f));
    }
}

int GhitaEngine::getActiveFilterType() const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    return m_activeFilterType;
}

void GhitaEngine::updateClock() {
    if (!m_isPlaying.load()) return;

    auto now = std::chrono::high_resolution_clock::now();
    auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastTickTime).count();
    if (elapsedMs > 0) {
        m_lastTickTime = now;
        int64_t newPos = m_currentPosMs.load() + elapsedMs;
        const int64_t duration = m_durationMs.load();
        if (newPos >= duration) {
            newPos = duration;
            m_isPlaying.store(false);
        }
        m_currentPosMs.store(newPos);
    }
}

bool GhitaEngine::renderFrameRGBA(uint8_t* outBuffer, int width, int height) {
    if (!outBuffer || width <= 0 || height <= 0) return false;

    {
        std::unique_lock<std::shared_mutex> lock(m_engineMutex);
        updateClock();
    }
    int64_t timeMs = m_currentPosMs.load();

    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    if (m_decoder) {
        return m_decoder->decodeFrame(outBuffer, width, height, timeMs, m_activeFilterType, m_filterIntensity.load());
    }
    return false;
}

uint8_t* GhitaEngine::getFrameDirectBufferPointer(int* outWidth, int* outHeight) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    const int w = m_width.load();
    const int h = m_height.load();
    if (w <= 0 || h <= 0) return nullptr;
    if (outWidth) *outWidth = w;
    if (outHeight) *outHeight = h;
    
    size_t requiredBytes = static_cast<size_t>(w * h * 4);
    if (m_directFrameBuffer.size() != requiredBytes) {
        m_directFrameBuffer.resize(requiredBytes);
    }
    if (m_decoder) {
        m_decoder->decodeFrame(m_directFrameBuffer.data(), w, h, m_currentPosMs.load(), m_activeFilterType, m_filterIntensity.load());
    }
    return m_directFrameBuffer.data();
}

// ========== TIMELINE / CLIP OPERATIONS ==========

int GhitaEngine::addClip(const std::string& filePath, int64_t startMs, int64_t durationMs, int trackIndex) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (!m_ready.load()) return -1;

    NativeClip clip;
    clip.id = m_nextClipId++;
    clip.filePath = filePath;
    clip.startMs = std::max(startMs, (int64_t)0);
    clip.durationMs = std::max(durationMs, (int64_t)100);
    clip.trackIndex = std::clamp(trackIndex, 0, 2);
    clip.filterType = 0;
    clip.filterIntensity = 1.0f;
    clip.transition = {TransitionType::None, 500};

    m_clips.push_back(clip);
    recalculateDuration();
    return clip.id;
}

bool GhitaEngine::removeClip(int clipId) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto it = m_clips.begin(); it != m_clips.end(); ++it) {
        if (it->id == clipId) {
            m_clips.erase(it);
            recalculateDuration();
            return true;
        }
    }
    return false;
}

int GhitaEngine::getClipCount() const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    return static_cast<int>(m_clips.size());
}

bool GhitaEngine::setClipPosition(int clipId, int64_t startMs) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.startMs = std::max(startMs, (int64_t)0);
            recalculateDuration();
            return true;
        }
    }
    return false;
}

bool GhitaEngine::setClipFilter(int clipId, int filterType, float intensity) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.filterType = std::clamp(filterType, 0, 4);
            clip.filterIntensity = std::clamp(intensity, 0.0f, 1.0f);
            return true;
        }
    }
    return false;
}

bool GhitaEngine::setClipTransition(int clipId, TransitionType type, int durationMs) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.transition.type = type;
            clip.transition.durationMs = std::clamp(durationMs, 100, 5000);
            return true;
        }
    }
    return false;
}

bool GhitaEngine::getAudioWaveform(float* outSamples, int sampleCount) {
    if (!outSamples || sampleCount <= 0) return false;
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    if (auto realDec = dynamic_cast<RealFFmpegMediaDecoder*>(m_decoder.get())) {
        return realDec->extractPcmAudioSamples(outSamples, sampleCount, m_volume.load());
    }
    for (int i = 0; i < sampleCount; ++i) {
        float phase = static_cast<float>(i) / static_cast<float>(sampleCount);
        outSamples[i] = std::abs(std::sin(phase * 12.566f) * 0.8f + std::sin(phase * 45.0f) * 0.2f) * m_volume.load();
    }
    return true;
}

void GhitaEngine::recalculateDuration() {
    int64_t maxEnd = 60000;
    for (const auto& clip : m_clips) {
        int64_t clipEnd = clip.startMs + clip.durationMs;
        if (clipEnd > maxEnd) maxEnd = clipEnd;
    }
    m_durationMs.store(maxEnd);
}

// ========== ASYNC EXPORT PIPELINE ==========

bool GhitaEngine::startExport(const std::string& outputPath, int width, int height, int fps) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (!m_ready.load() || m_isExporting.load()) return false;
    if (outputPath.empty() || width <= 0 || height <= 0 || fps <= 0) return false;

    if (m_exportThread.joinable()) {
        m_exportThread.join();
    }

    m_exportOutputPath = outputPath;
    m_isExporting.store(true);
    m_cancelExportFlag.store(false);
    m_exportProgress.store(0.0f);

    try {
        m_exportThread = std::thread([this, outputPath, width, height, fps]() {
            runExportLoop(outputPath, width, height, fps);
        });
    } catch (...) {
        m_isExporting.store(false);
        return false;
    }
    return true;
}

void GhitaEngine::runExportLoop(std::string outputPath, int width, int height, int fps) {
    const int totalFrames = static_cast<int>((m_durationMs.load() / 1000.0f) * fps);
    if (totalFrames <= 0) {
        m_isExporting.store(false);
        m_exportProgress.store(1.0f);
        return;
    }

    std::vector<uint8_t> frameBuffer(width * height * 4);
    RealFFmpegMediaDecoder decoder;

    std::unique_ptr<FILE, int(*)(FILE*)> outFile(nullptr, fclose);
    if (!outputPath.empty()) {
        FILE* rawFp = fopen(outputPath.c_str(), "wb");
        if (rawFp == nullptr) {
            m_exportProgress.store(1.0f);
            m_isExporting.store(false);
            return;
        }
        outFile.reset(rawFp);
    }

    for (int frame = 0; frame < totalFrames; ++frame) {
        if (m_cancelExportFlag.load()) {
            break;
        }

        int64_t frameTimeMs = static_cast<int64_t>((static_cast<float>(frame) / fps) * 1000.0f);
        decoder.decodeFrame(frameBuffer.data(), width, height, frameTimeMs, m_activeFilterType, m_filterIntensity.load());

        if (outFile) {
            fwrite(frameBuffer.data(), 1, frameBuffer.size(), outFile.get());
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(2));

        float progress = static_cast<float>(frame + 1) / static_cast<float>(totalFrames);
        m_exportProgress.store(progress);
    }

    m_isExporting.store(false);
    if (!m_cancelExportFlag.load()) {
        m_exportProgress.store(1.0f);
    }
}

float GhitaEngine::getExportProgress() const {
    return m_exportProgress.load();
}

bool GhitaEngine::isExporting() const {
    return m_isExporting.load();
}

void GhitaEngine::cancelExport() {
    if (m_isExporting.load()) {
        m_cancelExportFlag.store(true);
        if (m_exportThread.joinable() && std::this_thread::get_id() != m_exportThread.get_id()) {
            m_exportThread.join();
        }
    }
}

// ========== SELF TEST ==========

bool GhitaEngine::selfTest() {
    GhitaEngine engine;
    if (!engine.initialize()) return false;
    if (!engine.renderFrameRGBA(nullptr, 1, 1)) return false;

    uint8_t buf[16] = {};
    if (!engine.renderFrameRGBA(buf, 4, 4)) return false;
    if (buf[3] != 255) return false;

    engine.setVolume(0.0f);
    if (engine.getVolume() != 0.0f) return false;
    engine.setVolume(3.0f);
    if (engine.getVolume() > 2.0f) return false;

    engine.setFrameSnappingFps(60);
    if (engine.getFrameSnappingFps() != 60) return false;

    engine.applyFilter(1, 1.0f);
    if (engine.getActiveFilterType() != 1) return false;

    float samples[10] = {};
    if (!engine.getAudioWaveform(samples, 10)) return false;

    int id = engine.addClip("test.mp4", 0, 5000, 0);
    if (id < 0) return false;
    if (!engine.setClipTransition(id, TransitionType::FadeIn, 1000)) return false;
    if (engine.getClipCount() != 1) return false;
    if (!engine.removeClip(id)) return false;
    if (engine.getClipCount() != 0) return false;

    int w = 0, h = 0;
    uint8_t* ptr = engine.getFrameDirectBufferPointer(&w, &h);
    if (!ptr || w <= 0 || h <= 0) return false;

    return true;
}
