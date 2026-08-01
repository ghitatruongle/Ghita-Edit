#include "ghita_engine.h"
#include <cmath>
#include <algorithm>
#include <cstring>
#include <fstream>
#include <iostream>

// ====================================================================
// Pixel shader helpers (applied in RGBA space)
// ====================================================================
namespace {

struct RGBA { uint8_t r, g, b, a; };

void applyGrayscale(uint8_t* buf, int pixelCount) {
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        uint8_t y = static_cast<uint8_t>(0.299f * p.r + 0.587f * p.g + 0.114f * p.b);
        p.r = p.g = p.b = y;
    }
}

void applySepia(uint8_t* buf, int pixelCount) {
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        uint8_t r = p.r, g = p.g, b = p.b;
        p.r = std::min(255, static_cast<int>(0.393f * r + 0.769f * g + 0.189f * b));
        p.g = std::min(255, static_cast<int>(0.349f * r + 0.686f * g + 0.168f * b));
        p.b = std::min(255, static_cast<int>(0.272f * r + 0.534f * g + 0.131f * b));
    }
}

void applyInvert(uint8_t* buf, int pixelCount) {
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        p.r = 255 - p.r;
        p.g = 255 - p.g;
        p.b = 255 - p.b;
    }
}

void applyBrightness(uint8_t* buf, int pixelCount, float intensity) {
    int delta = static_cast<int>((intensity - 0.5f) * 2.0f * 128);
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        p.r = std::clamp(static_cast<int>(p.r) + delta, 0, 255);
        p.g = std::clamp(static_cast<int>(p.g) + delta, 0, 255);
        p.b = std::clamp(static_cast<int>(p.b) + delta, 0, 255);
    }
}

void applyBlur(uint8_t* buf, int width, int height, float intensity) {
    int radius = std::max(1, static_cast<int>(intensity * 10.0f));
    std::vector<uint8_t> tmp(width * height * 4);
    std::memcpy(tmp.data(), buf, tmp.size());

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int r = 0, g = 0, b = 0, count = 0;
            for (int dy = -radius; dy <= radius; ++dy) {
                for (int dx = -radius; dx <= radius; ++dx) {
                    int sx = x + dx, sy = y + dy;
                    if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
                        int idx = (sy * width + sx) * 4;
                        r += tmp[idx];
                        g += tmp[idx + 1];
                        b += tmp[idx + 2];
                        ++count;
                    }
                }
            }
            int idx = (y * width + x) * 4;
            buf[idx]     = static_cast<uint8_t>(count > 0 ? r / count : 0);
            buf[idx + 1] = static_cast<uint8_t>(count > 0 ? g / count : 0);
            buf[idx + 2] = static_cast<uint8_t>(count > 0 ? b / count : 0);
        }
    }
}

void applyEdgeDetect(uint8_t* buf, int width, int height, float /*intensity*/) {
    std::vector<uint8_t> tmp(width * height * 4);
    std::memcpy(tmp.data(), buf, tmp.size());

    const int sobelX[3][3] = {{-1, 0, 1}, {-2, 0, 2}, {-1, 0, 1}};
    const int sobelY[3][3] = {{-1, -2, -1}, {0, 0, 0}, {1, 2, 1}};

    for (int y = 1; y < height - 1; ++y) {
        for (int x = 1; x < width - 1; ++x) {
            int gx = 0, gy = 0;
            for (int ky = -1; ky <= 1; ++ky) {
                for (int kx = -1; kx <= 1; ++kx) {
                    int idx = ((y + ky) * width + (x + kx)) * 4;
                    uint8_t gray = static_cast<uint8_t>(
                        0.299f * tmp[idx] + 0.587f * tmp[idx + 1] + 0.114f * tmp[idx + 2]);
                    gx += gray * sobelX[ky + 1][kx + 1];
                    gy += gray * sobelY[ky + 1][kx + 1];
                }
            }
            int magnitude = std::min(255, static_cast<int>(std::sqrt(gx * gx + gy * gy)));
            int idx = (y * width + x) * 4;
            buf[idx] = buf[idx + 1] = buf[idx + 2] = static_cast<uint8_t>(magnitude);
        }
    }
}

void applyColorGrading(uint8_t* buf, int pixelCount, float /*intensity*/) {
    // Warm tone color matrix (slight orange shift)
    const float matrix[3][3] = {
        {1.1f, 0.0f, 0.0f},
        {0.0f, 0.9f, 0.0f},
        {0.0f, 0.0f, 0.8f}
    };
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        float r = p.r * matrix[0][0] + p.g * matrix[0][1] + p.b * matrix[0][2];
        float g = p.r * matrix[1][0] + p.g * matrix[1][1] + p.b * matrix[1][2];
        float b = p.r * matrix[2][0] + p.g * matrix[2][1] + p.b * matrix[2][2];
        p.r = std::clamp(static_cast<int>(r), 0, 255);
        p.g = std::clamp(static_cast<int>(g), 0, 255);
        p.b = std::clamp(static_cast<int>(b), 0, 255);
    }
}

void applyAdjust(uint8_t* buf, int pixelCount, float intensity) {
    // Combined brightness, contrast, saturation, hue adjustment
    float brightness = 0.5f + intensity * 0.5f;
    float contrast = 1.0f + (intensity - 0.5f) * 0.5f;
    float saturation = 0.5f + intensity * 0.5f;

    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        float r = p.r / 255.0f, g = p.g / 255.0f, b = p.b / 255.0f;
        // Contrast
        r = (r - 0.5f) * contrast + 0.5f;
        g = (g - 0.5f) * contrast + 0.5f;
        b = (b - 0.5f) * contrast + 0.5f;
        // Saturation
        float gray = 0.299f * r + 0.587f * g + 0.114f * b;
        r = gray + (r - gray) * saturation;
        g = gray + (g - gray) * saturation;
        b = gray + (b - gray) * saturation;
        // Brightness
        r *= brightness; g *= brightness; b *= brightness;
        p.r = std::clamp(static_cast<int>(r * 255), 0, 255);
        p.g = std::clamp(static_cast<int>(g * 255), 0, 255);
        p.b = std::clamp(static_cast<int>(b * 255), 0, 255);
    }
}

void applyPixelate(uint8_t* buf, int width, int height, float intensity) {
    int blockSize = std::max(2, static_cast<int>(intensity * 20.0f));
    for (int y = 0; y < height; y += blockSize) {
        for (int x = 0; x < width; x += blockSize) {
            int idx = (y * width + x) * 4;
            uint8_t r = buf[idx], g = buf[idx + 1], b = buf[idx + 2];
            for (int dy = 0; dy < blockSize && y + dy < height; ++dy) {
                for (int dx = 0; dx < blockSize && x + dx < width; ++dx) {
                    int pIdx = ((y + dy) * width + (x + dx)) * 4;
                    buf[pIdx] = r;
                    buf[pIdx + 1] = g;
                    buf[pIdx + 2] = b;
                }
            }
        }
    }
}

void applyFilterToBuffer(uint8_t* buf, int width, int height, int filterType, float filterIntensity) {
    int pixelCount = width * height;
    switch (filterType) {
        case 1: applyGrayscale(buf, pixelCount); break;
        case 2: applySepia(buf, pixelCount); break;
        case 3: applyInvert(buf, pixelCount); break;
        case 4: applyBrightness(buf, pixelCount, filterIntensity); break;
        case 5: applyBlur(buf, width, height, filterIntensity); break;
        case 6: applyEdgeDetect(buf, width, height, filterIntensity); break;
        case 7: applyColorGrading(buf, pixelCount, filterIntensity); break;
        case 8: applyAdjust(buf, pixelCount, filterIntensity); break;
        case 9: applyPixelate(buf, width, height, filterIntensity); break;
        case 10: applyPixelate(buf, width, height, filterIntensity); break; // Mosaic = Pixelate
        default: break;
    }
}

} // anonymous namespace

// ====================================================================
// SYNTHETIC MEDIA DECODER
// ====================================================================

bool SyntheticMediaDecoder::open(const std::string& filePath) {
    m_filePath = filePath;
    m_durationMs = 60000;
    return true;
}

MediaInfo SyntheticMediaDecoder::getMediaInfo() const {
    MediaInfo info;
    info.filePath = m_filePath;
    info.durationMs = m_durationMs;
    info.width = 1280;
    info.height = 720;
    info.fps = 30.0;
    info.hasVideo = true;
    info.hasAudio = true;
    info.videoCodec = "synthetic";
    info.audioCodec = "synthetic";
    info.audioSampleRate = 44100;
    info.audioChannels = 2;
    info.bitrate = 5000000;
    return info;
}

bool SyntheticMediaDecoder::decodeFrame(uint8_t* outBuffer, int width, int height,
                                         int64_t timeMs, int filterType, float filterIntensity) {
    if (!outBuffer || width <= 0 || height <= 0) return false;

    float t = static_cast<float>(timeMs) / 1000.0f;
    float cx = 0.5f + 0.3f * std::sin(t * 0.5f);
    float cy = 0.5f + 0.3f * std::cos(t * 0.3f);

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            float nx = static_cast<float>(x) / static_cast<float>(width);
            float ny = static_cast<float>(y) / static_cast<float>(height);
            float dx = nx - cx, dy = ny - cy;
            float dist = std::sqrt(dx * dx + dy * dy);

            uint8_t r, g, b;
            if (dist < 0.05f) {
                r = 255; g = 255; b = 0; // Yellow moving dot
            } else {
                r = static_cast<uint8_t>(128 + 127 * std::sin(nx * 10.0f + t * 2.0f));
                g = static_cast<uint8_t>(128 + 127 * std::sin(ny * 10.0f + t * 1.5f));
                b = static_cast<uint8_t>(128 + 127 * std::sin((nx + ny) * 8.0f + t * 1.0f));
            }

            const int idx = (y * width + x) * 4;
            outBuffer[idx + 0] = r;
            outBuffer[idx + 1] = g;
            outBuffer[idx + 2] = b;
            outBuffer[idx + 3] = 255;
        }
    }

    // Apply filter
    applyFilterToBuffer(outBuffer, width, height, filterType, filterIntensity);
    return true;
}

// ====================================================================
// REAL FFMPEG MEDIA DECODER (v0.4.5)
// ====================================================================

RealFFmpegMediaDecoder::RealFFmpegMediaDecoder()
    : m_hasFFmpeg(false)
{
#ifdef GHITA_HAS_FFMPEG
    // Register all codecs and formats (av_register_all is deprecated in newer FFmpeg)
    // In FFmpeg >= 4.0, this is automatic
#if LIBAVFORMAT_VERSION_INT < AV_VERSION_INT(58, 9, 100)
    av_register_all();
#endif
#endif
}

RealFFmpegMediaDecoder::~RealFFmpegMediaDecoder() {
#ifdef GHITA_HAS_FFMPEG
    destroyFFmpegContexts();
#endif
}

bool RealFFmpegMediaDecoder::open(const std::string& filePath) {
    m_filePath = filePath;

#ifdef GHITA_HAS_FFMPEG
    if (initFFmpegContexts()) {
        m_hasFFmpeg = true;
        m_mediaInfo = getMediaInfo();
        m_durationMs = m_mediaInfo.durationMs;
        m_width = m_mediaInfo.width;
        m_height = m_mediaInfo.height;
        return true;
    }
    // FFmpeg init failed — fall through to synthetic
    destroyFFmpegContexts();
#endif

    // Fallback: use synthetic decoder values
    m_durationMs = 60000;
    m_width = 1920;
    m_height = 1080;
    m_hasFFmpeg = false;
    return true;
}

bool RealFFmpegMediaDecoder::decodeFrame(uint8_t* outBuffer, int width, int height,
                                          int64_t timeMs, int filterType, float filterIntensity) {
    if (!outBuffer || width <= 0 || height <= 0) return false;

#ifdef GHITA_HAS_FFMPEG
    if (m_hasFFmpeg && m_videoCodecCtx) {
        return decodeVideoFrameAt(timeMs, outBuffer, width, height, filterType, filterIntensity);
    }
#endif

    // Fallback to synthetic (no filter — already applied inside synth)
    SyntheticMediaDecoder synth;
    return synth.decodeFrame(outBuffer, width, height, timeMs, filterType, filterIntensity);
}

bool RealFFmpegMediaDecoder::extractPcmAudioSamples(float* outSamples, int sampleCount, float volume) {
    if (!outSamples || sampleCount <= 0) return false;

#ifdef GHITA_HAS_FFMPEG
    if (m_hasFFmpeg && m_audioCodecCtx) {
        return decodeAudioSamples(outSamples, sampleCount, volume);
    }
#endif

    // Fallback: synthetic multi-frequency PCM
    for (int i = 0; i < sampleCount; ++i) {
        float phase = static_cast<float>(i) / static_cast<float>(sampleCount);
        float fundamental = std::sin(phase * 15.707f) * 0.5f;
        float harmonic2 = std::sin(phase * 31.415f) * 0.3f;
        float harmonic4 = std::cos(phase * 62.831f) * 0.2f;
        float rawPcm = fundamental + harmonic2 + harmonic4;
        outSamples[i] = std::abs(rawPcm) * volume;
    }
    return true;
}

MediaInfo RealFFmpegMediaDecoder::getMediaInfo() const {
    if (m_hasFFmpeg && !m_mediaInfo.filePath.empty()) {
        return m_mediaInfo;
    }

    MediaInfo info;
    info.filePath = m_filePath;
    info.durationMs = m_durationMs;
    info.width = m_width;
    info.height = m_height;
    info.hasVideo = true;
    info.hasAudio = true;
    info.fps = 30.0;
    info.bitrate = 5000000;
    info.videoCodec = m_hasFFmpeg ? "ffmpeg" : "synthetic (fallback)";
    info.audioCodec = m_hasFFmpeg ? "ffmpeg" : "synthetic (fallback)";
    info.audioSampleRate = 44100;
    info.audioChannels = 2;
    return info;
}

#ifdef GHITA_HAS_FFMPEG

bool RealFFmpegMediaDecoder::initFFmpegContexts() {
    // v0.7.8: Release any previous contexts first — reloading a second file
    // used to leak the whole FFmpeg context chain of the first one.
    destroyFFmpegContexts();

    // Open file
    m_formatCtx = nullptr;
    if (avformat_open_input(&m_formatCtx, m_filePath.c_str(), nullptr, nullptr) != 0) {
        return false;
    }

    if (avformat_find_stream_info(m_formatCtx, nullptr) < 0) {
        return false;
    }

    // Find video and audio streams
    m_videoStreamIdx = -1;
    m_audioStreamIdx = -1;
    for (unsigned i = 0; i < m_formatCtx->nb_streams; ++i) {
        AVCodecParameters* params = m_formatCtx->streams[i]->codecpar;
        if (params->codec_type == AVMEDIA_TYPE_VIDEO && m_videoStreamIdx < 0) {
            m_videoStreamIdx = static_cast<int>(i);
        } else if (params->codec_type == AVMEDIA_TYPE_AUDIO && m_audioStreamIdx < 0) {
            m_audioStreamIdx = static_cast<int>(i);
        }
    }

    if (m_videoStreamIdx < 0 && m_audioStreamIdx < 0) {
        return false;
    }

    // Open video decoder
    if (m_videoStreamIdx >= 0) {
        AVCodecParameters* params = m_formatCtx->streams[m_videoStreamIdx]->codecpar;
        const AVCodec* codec = avcodec_find_decoder(params->codec_id);
        if (!codec) return false;

        m_videoCodecCtx = avcodec_alloc_context3(codec);
        if (!m_videoCodecCtx) return false;

        if (avcodec_parameters_to_context(m_videoCodecCtx, params) < 0) return false;
        if (avcodec_open2(m_videoCodecCtx, codec, nullptr) < 0) return false;
    }

    // Open audio decoder
    if (m_audioStreamIdx >= 0) {
        AVCodecParameters* params = m_formatCtx->streams[m_audioStreamIdx]->codecpar;
        const AVCodec* codec = avcodec_find_decoder(params->codec_id);
        if (!codec) return false;

        m_audioCodecCtx = avcodec_alloc_context3(codec);
        if (!m_audioCodecCtx) return false;

        if (avcodec_parameters_to_context(m_audioCodecCtx, params) < 0) return false;
        if (avcodec_open2(m_audioCodecCtx, codec, nullptr) < 0) return false;
    }

    // Allocate packet and frame
    m_packet = av_packet_alloc();
    m_frame = av_frame_alloc();
    m_rgbFrame = av_frame_alloc();

    // Allocate RGB buffer for sws_scale
    if (m_videoCodecCtx) {
        m_rgbBufferSize = av_image_get_buffer_size(AV_PIX_FMT_RGBA, m_videoCodecCtx->width,
                                                    m_videoCodecCtx->height, 1);
        m_rgbBuffer = static_cast<uint8_t*>(av_malloc(m_rgbBufferSize));
        av_image_fill_arrays(m_rgbFrame->data, m_rgbFrame->linesize,
                             m_rgbBuffer, AV_PIX_FMT_RGBA,
                             m_videoCodecCtx->width, m_videoCodecCtx->height, 1);

        // Create SWS context for RGB conversion
        m_swsCtx = sws_getContext(
            m_videoCodecCtx->width, m_videoCodecCtx->height, m_videoCodecCtx->pix_fmt,
            m_videoCodecCtx->width, m_videoCodecCtx->height, AV_PIX_FMT_RGBA,
            SWS_BILINEAR, nullptr, nullptr, nullptr);
    }

    // Create SWR context for audio resampling
    if (m_audioCodecCtx) {
        int swrRet = swr_alloc_set_opts2(
            &m_swrCtx,
            &m_audioCodecCtx->ch_layout, AV_SAMPLE_FMT_FLT, m_audioCodecCtx->sample_rate,
            &m_audioCodecCtx->ch_layout, m_audioCodecCtx->sample_fmt, m_audioCodecCtx->sample_rate,
            0, nullptr);
        if (swrRet >= 0 && m_swrCtx) {
            swr_init(m_swrCtx);
        }
    }

    // Build media info
    m_mediaInfo.filePath = m_filePath;
    m_mediaInfo.hasVideo = (m_videoStreamIdx >= 0);
    m_mediaInfo.hasAudio = (m_audioStreamIdx >= 0);

    if (m_videoStreamIdx >= 0) {
        AVStream* vs = m_formatCtx->streams[m_videoStreamIdx];
        // Duration from stream: stream->duration is in stream time_base units
        // Convert to ms: duration_sec = stream->duration * av_q2d(time_base)
        // duration_ms = duration_sec * 1000
        double timeBase = av_q2d(vs->time_base);
        int64_t streamDurationMs = static_cast<int64_t>(vs->duration * timeBase * 1000.0);
        // Fallback to format duration (in AV_TIME_BASE = microseconds)
        int64_t fmtDurationMs = (m_formatCtx->duration > 0)
            ? (m_formatCtx->duration / 1000)
            : 60000;
        m_mediaInfo.durationMs = (streamDurationMs > 0) ? streamDurationMs : fmtDurationMs;
        m_mediaInfo.width = m_videoCodecCtx->width;
        m_mediaInfo.height = m_videoCodecCtx->height;
        m_mediaInfo.fps = av_q2d(vs->avg_frame_rate);
        if (m_mediaInfo.fps <= 0) m_mediaInfo.fps = av_q2d(vs->r_frame_rate);
        m_mediaInfo.bitrate = m_formatCtx->bit_rate;
    }

    if (m_videoStreamIdx >= 0 && m_videoCodecCtx && m_videoCodecCtx->codec) {
        m_mediaInfo.videoCodec = m_videoCodecCtx->codec->name;
    }

    if (m_audioStreamIdx >= 0 && m_audioCodecCtx && m_audioCodecCtx->codec) {
        m_mediaInfo.audioCodec = m_audioCodecCtx->codec->name;
        m_mediaInfo.audioSampleRate = m_audioCodecCtx->sample_rate;
        m_mediaInfo.audioChannels = m_audioCodecCtx->ch_layout.nb_channels;
    }

    if (m_mediaInfo.durationMs <= 0) {
        m_mediaInfo.durationMs = 60000;
    }

    return true;
}

void RealFFmpegMediaDecoder::destroyFFmpegContexts() {
    if (m_swsCtx) { sws_freeContext(m_swsCtx); m_swsCtx = nullptr; }
    if (m_swrCtx) { swr_free(&m_swrCtx); }
    if (m_rgbBuffer) { av_free(m_rgbBuffer); m_rgbBuffer = nullptr; }
    if (m_rgbFrame) { av_frame_free(&m_rgbFrame); }
    if (m_frame) { av_frame_free(&m_frame); }
    if (m_packet) { av_packet_free(&m_packet); }
    if (m_videoCodecCtx) { avcodec_free_context(&m_videoCodecCtx); }
    if (m_audioCodecCtx) { avcodec_free_context(&m_audioCodecCtx); }
    if (m_formatCtx) { avformat_close_input(&m_formatCtx); }
}

bool RealFFmpegMediaDecoder::decodeVideoFrameAt(int64_t timeMs, uint8_t* outBuffer,
                                                  int outWidth, int outHeight,
                                                  int filterType, float filterIntensity) {
    if (!m_formatCtx || m_videoStreamIdx < 0 || !m_videoCodecCtx) return false;

    AVStream* stream = m_formatCtx->streams[m_videoStreamIdx];
    // Convert timeMs to stream time_base units:
    // PTS = time_seconds / time_base_seconds = (timeMs / 1000) / av_q2d(time_base)
    double timeBase = av_q2d(stream->time_base);
    int64_t targetPts = static_cast<int64_t>((timeMs / 1000.0) / timeBase);

    // Seek to target
    if (av_seek_frame(m_formatCtx, m_videoStreamIdx, targetPts, AVSEEK_FLAG_BACKWARD) < 0) {
        return false;
    }
    avcodec_flush_buffers(m_videoCodecCtx);

    // Decode until we reach the target frame
    bool frameDecoded = false;
    while (av_read_frame(m_formatCtx, m_packet) >= 0) {
        if (m_packet->stream_index == m_videoStreamIdx) {
            if (avcodec_send_packet(m_videoCodecCtx, m_packet) == 0) {
                int ret = avcodec_receive_frame(m_videoCodecCtx, m_frame);
                if (ret == 0) {
                    // Check if this frame is close enough to target
                    int64_t framePts = m_frame->pts;
                    if (framePts >= targetPts) {
                        frameDecoded = true;
                        break;
                    }
                }
            }
        }
        av_packet_unref(m_packet);
    }

    if (!frameDecoded && m_frame) {
        // Use last decoded frame even if not perfect match
        frameDecoded = (m_frame->data[0] != nullptr);
    }

    if (!frameDecoded) return false;

    // Convert to RGBA
    if (m_swsCtx) {
        sws_scale(m_swsCtx, m_frame->data, m_frame->linesize,
                  0, m_videoCodecCtx->height,
                  m_rgbFrame->data, m_rgbFrame->linesize);
    }

    // Scale to output dimensions if needed
    if (m_videoCodecCtx->width == outWidth && m_videoCodecCtx->height == outHeight) {
        std::memcpy(outBuffer, m_rgbBuffer, static_cast<size_t>(outWidth * outHeight * 4));
    } else {
        // Simple bilinear resize
        float scaleX = static_cast<float>(m_videoCodecCtx->width) / outWidth;
        float scaleY = static_cast<float>(m_videoCodecCtx->height) / outHeight;
        for (int y = 0; y < outHeight; ++y) {
            for (int x = 0; x < outWidth; ++x) {
                int srcX = std::min(static_cast<int>(x * scaleX), m_videoCodecCtx->width - 1);
                int srcY = std::min(static_cast<int>(y * scaleY), m_videoCodecCtx->height - 1);
                int srcIdx = (srcY * m_videoCodecCtx->width + srcX) * 4;
                int dstIdx = (y * outWidth + x) * 4;
                outBuffer[dstIdx]     = m_rgbBuffer[srcIdx];
                outBuffer[dstIdx + 1] = m_rgbBuffer[srcIdx + 1];
                outBuffer[dstIdx + 2] = m_rgbBuffer[srcIdx + 2];
                outBuffer[dstIdx + 3] = 255;
            }
        }
    }

    // Apply filter
    applyFilterToBuffer(outBuffer, outWidth, outHeight, filterType, filterIntensity);
    return true;
}

bool RealFFmpegMediaDecoder::decodeAudioSamples(float* outSamples, int sampleCount, float volume) {
    if (!m_formatCtx || m_audioStreamIdx < 0 || !m_audioCodecCtx) return false;

    std::vector<float> accum(sampleCount, 0.0f);
    int samplesCollected = 0;

    // Allocate conversion buffer for swr_convert output
    std::vector<float> convBuffer(static_cast<size_t>(sampleCount));

    av_seek_frame(m_formatCtx, m_audioStreamIdx, 0, AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(m_audioCodecCtx);

    while (av_read_frame(m_formatCtx, m_packet) >= 0 && samplesCollected < sampleCount) {
        if (m_packet->stream_index == m_audioStreamIdx) {
            if (avcodec_send_packet(m_audioCodecCtx, m_packet) == 0) {
                int ret = avcodec_receive_frame(m_audioCodecCtx, m_frame);
                if (ret == 0 && m_frame->data[0]) {
                    float* floatData = reinterpret_cast<float*>(m_frame->data[0]);
                    int frames = m_frame->nb_samples;

                    // Convert to float if needed via swr_convert
                    if (m_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_FLT && m_swrCtx) {
                        uint8_t* convOut[1] = {reinterpret_cast<uint8_t*>(convBuffer.data())};
                        // v0.7.8: out_count must never exceed the conversion
                        // buffer — nb_samples can be up to 8192 while the
                        // buffer is sized to sampleCount (e.g. 200). Previously
                        // this overflowed the heap buffer (heap corruption).
                        int requested = std::min(frames, sampleCount);
                        int outFrames = swr_convert(m_swrCtx, convOut, requested,
                                                    const_cast<const uint8_t**>(m_frame->data), frames);
                        if (outFrames > 0) {
                            floatData = reinterpret_cast<float*>(convOut[0]);
                            frames = std::min(outFrames, requested);
                        }
                    }

                    int toCopy = std::min(frames, sampleCount - samplesCollected);
                    for (int i = 0; i < toCopy; ++i) {
                        accum[samplesCollected + i] += floatData[i] * volume;
                    }
                    samplesCollected += toCopy;
                }
            }
        }
        av_packet_unref(m_packet);
    }

    if (samplesCollected == 0) return false;

    // Copy to output (rectified for waveform display)
    for (int i = 0; i < sampleCount; ++i) {
        outSamples[i] = std::abs(accum[i]) * volume;
    }
    return true;
}

#endif // GHITA_HAS_FFMPEG

// ====================================================================
// FFMPEG MEDIA DECODER STUB (kept for ABI compatibility)
// ====================================================================

bool FFmpegMediaDecoderStub::open(const std::string& /*filePath*/) {
    m_durationMs = 60000;
    return true;
}

bool FFmpegMediaDecoderStub::decodeFrame(uint8_t* outBuffer, int width, int height,
                                          int64_t timeMs, int filterType, float filterIntensity) {
    // Delegate to synthetic which applies filter internally
    SyntheticMediaDecoder synth;
    return synth.decodeFrame(outBuffer, width, height, timeMs, filterType, filterIntensity);
}

MediaInfo FFmpegMediaDecoderStub::getMediaInfo() const {
    MediaInfo info;
    info.durationMs = 60000;
    info.width = 1920;
    info.height = 1080;
    info.fps = 30.0;
    info.hasVideo = true;
    info.hasAudio = true;
    info.videoCodec = "stub";
    info.audioCodec = "stub";
    return info;
}

// ====================================================================
// ENGINE CORE
// ====================================================================

GhitaEngine::GhitaEngine() {
    m_lastTickTime = std::chrono::high_resolution_clock::now();
    m_ready = false;
    m_decoder = std::make_unique<RealFFmpegMediaDecoder>();
}

GhitaEngine::~GhitaEngine() {
    cancelExport();
    {
        // v0.7.8: Same join guard as cancelExport (see above)
        std::lock_guard<std::mutex> joinLock(m_exportJoinMutex);
        if (m_exportThread.joinable()) {
            m_exportThread.join();
        }
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
    int64_t duration = m_durationMs.load();
    positionMs = std::clamp(positionMs, int64_t(0), duration);
    m_currentPosMs.store(positionMs);
    m_lastTickTime = std::chrono::high_resolution_clock::now();
}

int64_t GhitaEngine::getPositionMs() const {
    return m_currentPosMs.load();
}

int64_t GhitaEngine::getDurationMs() const {
    return m_durationMs.load();
}

void GhitaEngine::setVolume(float volume) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_volume.store(std::clamp(volume, 0.0f, 2.0f));
}

// v0.5.5: Playback rate control
void GhitaEngine::setPlaybackRate(float rate) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_playbackRate.store(std::clamp(rate, 0.25f, 4.0f));
}

void GhitaEngine::applyFilter(int filterType, float intensity) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_activeFilterType = std::clamp(filterType, 0, 10);
    m_filterIntensity.store(std::clamp(intensity, 0.0f, 1.0f));
}

int GhitaEngine::getActiveFilterType() const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    return m_activeFilterType;
}

bool GhitaEngine::renderFrameRGBA(uint8_t* outBuffer, int width, int height) {
    if (!outBuffer || !m_ready.load()) return false;

    std::shared_lock<std::shared_mutex> lock(m_engineMutex);

    int64_t pos = m_currentPosMs.load();
    int64_t duration = m_durationMs.load();

    if (m_isPlaying.load()) {
        auto now = std::chrono::high_resolution_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastTickTime).count();
        m_lastTickTime = now;
        pos += elapsed;
        if (pos >= duration) {
            pos = 0;
        }
        m_currentPosMs.store(pos);
    }

    if (!m_decoder) return false;
    return m_decoder->decodeFrame(outBuffer, width, height, pos,
                                   m_activeFilterType, m_filterIntensity.load());
}

uint8_t* GhitaEngine::getFrameDirectBufferPointer(int* outWidth, int* outHeight) {
    if (!outWidth || !outHeight) return nullptr;
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    if (!m_ready.load()) return nullptr;

    int w = m_width.load();
    int h = m_height.load();
    size_t needed = static_cast<size_t>(w * h * 4);

    if (m_directFrameBuffer.size() != needed) {
        m_directFrameBuffer.resize(needed);
    }

    if (m_decoder) {
        m_decoder->decodeFrame(m_directFrameBuffer.data(), w, h,
                                m_currentPosMs.load(), m_activeFilterType,
                                m_filterIntensity.load());
    }

    *outWidth = w;
    *outHeight = h;
    return m_directFrameBuffer.data();
}

std::string GhitaEngine::getMediaInfoJson() const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    if (m_decoder) {
        MediaInfo info = m_decoder->getMediaInfo();
        return info.toJson();
    }
    return "{}";
}

std::string GhitaEngine::getAvailableFiltersJson() const {
    return R"([
        {"id":0, "name":"None", "category":"basic"},
        {"id":1, "name":"Grayscale", "category":"basic"},
        {"id":2, "name":"Sepia", "category":"basic"},
        {"id":3, "name":"Invert", "category":"basic"},
        {"id":4, "name":"Brightness", "category":"adjust"},
        {"id":5, "name":"Blur", "category":"blur"},
        {"id":6, "name":"Edge Detect", "category":"artistic"},
        {"id":7, "name":"Color Grading", "category":"color"},
        {"id":8, "name":"Adjust", "category":"color"},
        {"id":9, "name":"Pixelate", "category":"artistic"},
        {"id":10, "name":"Mosaic", "category":"artistic"}
    ])";
}

void GhitaEngine::setFrameSnappingFps(int fps) {
    m_snappingFps.store(std::clamp(fps, 1, 120));
}

// ========== TIMELINE / CLIP OPERATIONS ==========

int GhitaEngine::addClip(const std::string& filePath, int64_t startMs, int64_t durationMs, int trackIndex) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    NativeClip clip;
    clip.id = m_nextClipId++;
    clip.filePath = filePath;
    clip.startMs = std::max(int64_t(0), startMs);
    clip.durationMs = std::max(int64_t(100), durationMs);
    clip.trackIndex = std::max(0, trackIndex);
    clip.filterType = 0;
    clip.filterIntensity = 1.0f;
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
            clip.startMs = std::max(int64_t(0), startMs);
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
            clip.filterType = std::clamp(filterType, 0, 10);
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
            clip.transition.durationMs = std::max(0, durationMs);
            return true;
        }
    }
    return false;
}

bool GhitaEngine::addClipKeyframe(int clipId, int64_t timeMs, float value) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.keyframes.push_back({timeMs, value});
            // Sort by time
            std::sort(clip.keyframes.begin(), clip.keyframes.end(),
                      [](const Keyframe& a, const Keyframe& b) { return a.timeMs < b.timeMs; });
            return true;
        }
    }
    return false;
}

bool GhitaEngine::clearClipKeyframes(int clipId) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.keyframes.clear();
            return true;
        }
    }
    return false;
}

// v0.5.5: Keyframe interpolation
bool GhitaEngine::setClipKeyframeInterpolation(int clipId, KeyframeInterpolation interpolation) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            // Store interpolation type in the first keyframe's timeMs as a flag
            // (negative time values indicate interpolation type metadata)
            if (!clip.keyframes.empty()) {
                // Use a sentinel approach: store in a separate map-like structure
                // For simplicity, we just note it's supported and store in keyframe metadata
                // In a full implementation, NativeClip would have an interpolation field
            }
            return true;
        }
    }
    return false;
}

KeyframeInterpolation GhitaEngine::getClipKeyframeInterpolation(int clipId) const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    for (const auto& clip : m_clips) {
        if (clip.id == clipId) {
            return KeyframeInterpolation::Linear; // Default
        }
    }
    return KeyframeInterpolation::Linear;
}

// v0.5.5: Text overlay rendering (basic rasterizer stub)
bool GhitaEngine::renderTextOverlay(uint8_t* outBuffer, int width, int height,
                                     const char* text, int fontSize, float r, float g, float b, float a) {
    if (!outBuffer || !text || width <= 0 || height <= 0) return false;

    const int textLen = static_cast<int>(std::strlen(text));
    const int boxW = std::min(width, std::max(40, textLen * fontSize / 2));
    const int boxH = std::min(height, fontSize * 2);
    const int boxX = 20;
    const int boxY = height - boxH - 20;

    // Draw filled rectangle for text background
    for (int y = boxY; y < boxY + boxH && y < height; ++y) {
        for (int x = boxX; x < boxX + boxW && x < width; ++x) {
            int idx = (y * width + x) * 4;
            outBuffer[idx]     = static_cast<uint8_t>(r * 255);
            outBuffer[idx + 1] = static_cast<uint8_t>(g * 255);
            outBuffer[idx + 2] = static_cast<uint8_t>(b * 255);
            outBuffer[idx + 3] = static_cast<uint8_t>(a * 255);
        }
    }

    return true;
}

void GhitaEngine::recalculateDuration() {
    int64_t maxEnd = 60000; // Minimum 60s
    for (const auto& clip : m_clips) {
        int64_t end = clip.startMs + clip.durationMs;
        if (end > maxEnd) maxEnd = end;
    }
    m_durationMs.store(maxEnd);
}

void GhitaEngine::updateClock() {
    if (!m_isPlaying.load()) return;
    auto now = std::chrono::high_resolution_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastTickTime).count();
    m_lastTickTime = now;
    int64_t pos = m_currentPosMs.load() + elapsed;
    int64_t duration = m_durationMs.load();
    if (pos >= duration) {
        pos = 0;
    }
    m_currentPosMs.store(pos);
}

// ========== AUDIO WAVEFORM ==========

bool GhitaEngine::getAudioWaveform(float* outSamples, int sampleCount) {
    if (!outSamples || sampleCount <= 0) return false;
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);

    if (auto realDec = dynamic_cast<RealFFmpegMediaDecoder*>(m_decoder.get())) {
        return realDec->extractPcmAudioSamples(outSamples, sampleCount, m_volume.load());
    }

    // Fallback: synthetic waveform
    for (int i = 0; i < sampleCount; ++i) {
        float phase = static_cast<float>(i) / static_cast<float>(sampleCount);
        outSamples[i] = (std::sin(phase * 20.0f) * 0.5f + 0.5f) * m_volume.load();
    }
    return true;
}

// ========== ASYNC EXPORT PIPELINE ==========

bool GhitaEngine::startExport(const std::string& outputPath, int width, int height, int fps) {
    return startExportEx(outputPath, width, height, fps, "h264", 10000000, true);
}

bool GhitaEngine::startExportEx(const std::string& outputPath, int width, int height, int fps,
                                 const std::string& codec, int64_t bitrate, bool includeAudio) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (!m_ready.load() || m_isExporting.load()) return false;
    if (outputPath.empty() || width <= 0 || height <= 0 || fps <= 0) return false;

    if (m_exportThread.joinable()) {
        m_exportThread.join();
    }

    // v0.7.8: Snapshot the media path under the engine lock — the export
    // thread reads it without locking (previously a data race with loadMedia).
    m_exportMediaPath = m_loadedFilePath;

    // v0.7.8: Reset the error flag BEFORE publishing isExporting — otherwise
    // a poller could observe a stale failure from a previous export.
    m_exportError.store(false);
    m_exportOutputPath = outputPath;
    m_isExporting.store(true);
    m_cancelExportFlag.store(false);
    m_exportProgress.store(0.0f);
    m_exportFileSize.store(0);

    try {
        m_exportThread = std::thread([this, outputPath, width, height, fps, codec, bitrate, includeAudio]() {
            runExportLoopEx(outputPath, width, height, fps, codec, bitrate, includeAudio);
        });
    } catch (...) {
        m_isExporting.store(false);
        return false;
    }
    return true;
}

void GhitaEngine::runExportLoop(std::string outputPath, int width, int height, int fps) {
    runExportLoopEx(outputPath, width, height, fps, "h264", 10000000, true);
}

void GhitaEngine::runExportLoopEx(std::string outputPath, int width, int height, int fps,
                                   std::string codec, int64_t bitrate, bool includeAudio) {
    m_exportError.store(false);
    const int totalFrames = static_cast<int>((m_durationMs.load() / 1000.0f) * fps);
    if (totalFrames <= 0) {
        m_isExporting.store(false);
        m_exportError.store(true);
        return;
    }

    std::vector<uint8_t> frameBuffer(static_cast<size_t>(width * height * 4));
    RealFFmpegMediaDecoder decoder;
    decoder.open(m_exportMediaPath.empty() ? "synthetic" : m_exportMediaPath);

    // v0.7.8: Only a fully written output counts as success
    bool writeCompleted = false;

#ifdef GHITA_HAS_FFMPEG
    // FFmpeg encoding pipeline
    AVFormatContext* fmtCtx = nullptr;
    AVStream* videoStream = nullptr;
    AVCodecContext* encCtx = nullptr;
    const AVCodec* encoder = nullptr;
    AVFrame* encFrame = nullptr;
    AVPacket* encPkt = nullptr;
    SwsContext* swsCtx = nullptr;

    // Determine encoder name
    std::string encoderName = "libx264";
    if (codec == "h265" || codec == "hevc") encoderName = "libx265";
    else if (codec == "vp9") encoderName = "libvpx-vp9";

    // Open output format
    avformat_alloc_output_context2(&fmtCtx, nullptr, nullptr, outputPath.c_str());
    if (fmtCtx) {
        encoder = avcodec_find_encoder_by_name(encoderName.c_str());
        if (!encoder) encoder = avcodec_find_encoder(AV_CODEC_ID_H264);

        if (encoder) {
            encCtx = avcodec_alloc_context3(encoder);
            if (encCtx) {
                encCtx->width = width;
                encCtx->height = height;
                encCtx->time_base = {1, fps};
                encCtx->framerate = {fps, 1};
                encCtx->pix_fmt = AV_PIX_FMT_YUV420P;
                encCtx->bit_rate = bitrate;
                encCtx->gop_size = fps * 2;
                encCtx->max_b_frames = 2;

                if (fmtCtx->oformat->flags & AVFMT_GLOBALHEADER) {
                    encCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
                }

                if (avcodec_open2(encCtx, encoder, nullptr) >= 0) {
                    videoStream = avformat_new_stream(fmtCtx, encoder);
                    if (videoStream) {
                        avcodec_parameters_from_context(videoStream->codecpar, encCtx);

                        // Open output file
                        if (!(fmtCtx->oformat->flags & AVFMT_NOFILE)) {
                            // v0.7.8: Bail out cleanly when the output path is
                            // unwritable — previously the failure was ignored
                            // and avformat_write_header crashed on a null pb.
                            if (avio_open(&fmtCtx->pb, outputPath.c_str(), AVIO_FLAG_WRITE) < 0) {
                                m_exportError.store(true);
                                goto export_cleanup;
                            }
                        }

                        if (avformat_write_header(fmtCtx, nullptr) >= 0) {
                            encFrame = av_frame_alloc();
                            encFrame->width = width;
                            encFrame->height = height;
                            encFrame->format = AV_PIX_FMT_YUV420P;
                            av_frame_get_buffer(encFrame, 0);

                            encPkt = av_packet_alloc();

                            // SWS context for RGB → YUV conversion
                            swsCtx = sws_getContext(
                                width, height, AV_PIX_FMT_RGBA,
                                width, height, AV_PIX_FMT_YUV420P,
                                SWS_BILINEAR, nullptr, nullptr, nullptr);

                            // Encode loop
                            for (int frame = 0; frame < totalFrames; ++frame) {
                                if (m_cancelExportFlag.load()) break;

                                int64_t frameTimeMs = static_cast<int64_t>(
                                    (static_cast<float>(frame) / fps) * 1000.0f);
                                decoder.decodeFrame(frameBuffer.data(), width, height, frameTimeMs,
                                                      m_activeFilterType, m_filterIntensity.load());

                                // Convert RGBA → YUV420P
                                if (swsCtx) {
                                    uint8_t* srcSlice[1] = {frameBuffer.data()};
                                    int srcStride[1] = {width * 4};
                                    sws_scale(swsCtx, srcSlice, srcStride, 0, height,
                                              encFrame->data, encFrame->linesize);
                                }

                                encFrame->pts = frame;
                                int ret = avcodec_send_frame(encCtx, encFrame);
                                while (ret >= 0) {
                                    ret = avcodec_receive_packet(encCtx, encPkt);
                                    if (ret == 0) {
                                        av_packet_rescale_ts(encPkt, encCtx->time_base, videoStream->time_base);
                                        encPkt->stream_index = videoStream->index;
                                        av_interleaved_write_frame(fmtCtx, encPkt);
                                        av_packet_unref(encPkt);
                                    } else {
                                        break;
                                    }
                                }

                                float progress = static_cast<float>(frame + 1) / static_cast<float>(totalFrames);
                                m_exportProgress.store(progress);
                            }

                            // Flush encoder
                            avcodec_send_frame(encCtx, nullptr);
                            while (avcodec_receive_packet(encCtx, encPkt) == 0) {
                                av_packet_rescale_ts(encPkt, encCtx->time_base, videoStream->time_base);
                                encPkt->stream_index = videoStream->index;
                                av_interleaved_write_frame(fmtCtx, encPkt);
                                av_packet_unref(encPkt);
                            }

                            // Write trailer
                            av_write_trailer(fmtCtx);
                            writeCompleted = true;

                            // Get file size
                            if (fmtCtx->pb) {
                                m_exportFileSize.store(avio_size(fmtCtx->pb));
                            }
                        }
                    }
                }
            }
        }
    }

    // v0.7.8: avio_open failure jumps here (skips encode, still cleans up)
export_cleanup:
    // Cleanup (safe even if pointers are null)
    if (swsCtx) sws_freeContext(swsCtx);
    av_packet_free(&encPkt);
    av_frame_free(&encFrame);
    avcodec_free_context(&encCtx);
    if (fmtCtx && !(fmtCtx->oformat->flags & AVFMT_NOFILE)) {
        avio_closep(&fmtCtx->pb);
    }
    avformat_free_context(fmtCtx);
#else
    // Fallback: write raw RGBA data (legacy behavior, no FFmpeg available)
    std::unique_ptr<FILE, int(*)(FILE*)> outFile(nullptr, fclose);
    if (!outputPath.empty()) {
        FILE* rawFp = fopen(outputPath.c_str(), "wb");
        if (rawFp) outFile.reset(rawFp);
    }

    for (int frame = 0; frame < totalFrames; ++frame) {
        if (m_cancelExportFlag.load()) break;

        int64_t frameTimeMs = static_cast<int64_t>(
            (static_cast<float>(frame) / fps) * 1000.0f);
        decoder.decodeFrame(frameBuffer.data(), width, height, frameTimeMs,
                              m_activeFilterType, m_filterIntensity.load());

        if (outFile) {
            fwrite(frameBuffer.data(), 1, frameBuffer.size(), outFile.get());
            m_exportFileSize.store(static_cast<int64_t>(outFile ? ftell(outFile.get()) : 0));
        }

        float progress = static_cast<float>(frame + 1) / static_cast<float>(totalFrames);
        m_exportProgress.store(progress);
    }
    if (outFile) writeCompleted = true;
#endif

    if (!writeCompleted && !m_cancelExportFlag.load()) {
        m_exportError.store(true);
    }

    m_isExporting.store(false);
    if (!m_cancelExportFlag.load() && !m_exportError.load()) {
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
        // v0.7.8: Serialize joins — destructor and cancelExport can run from
        // different threads; a second join() on the same std::thread throws.
        std::lock_guard<std::mutex> joinLock(m_exportJoinMutex);
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

    // Verify alpha is opaque
    for (int i = 0; i < 4; ++i) {
        if (buf[i * 4 + 3] != 255) return false;
    }

    // Test clip operations
    int id = engine.addClip("test.mp4", 0, 5000, 0);
    if (id <= 0) return false;
    if (engine.getClipCount() != 1) return false;

    // Test keyframe
    if (!engine.addClipKeyframe(id, 0, 0.0f)) return false;
    if (!engine.addClipKeyframe(id, 5000, 1.0f)) return false;
    if (!engine.clearClipKeyframes(id)) return false;

    // Test export start/cancel
    if (!engine.startExport("test_out.mp4", 1920, 1080, 60)) return false;
    engine.cancelExport();
    if (engine.isExporting()) return false;

    // Test media info
    engine.loadMedia("test.mp4");
    std::string infoJson = engine.getMediaInfoJson();
    if (infoJson.empty()) return false;

    return true;
}
