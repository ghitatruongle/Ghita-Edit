// src/timeline/ZoomDissolveTransition.cpp
#include "ZoomDissolveTransition.h"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace ghita::timeline {

namespace {

// Bilinear sample of a YUV plane at fractional coordinates (fx, fy).
// Assumes the plane is at least as large as the source frame.
inline uint8_t samplePlane(const uint8_t* data, int stride,
                           int w, int h, float fx, float fy) {
    // Clamp to valid range.
    int ix = static_cast<int>(std::floor(fx));
    int iy = static_cast<int>(std::floor(fy));
    ix = std::max(0, std::min(w - 2, ix));
    iy = std::max(0, std::min(h - 2, iy));

    float dx = fx - ix;
    float dy = fy - iy;

    uint8_t p00 = data[iy * stride + ix];
    uint8_t p10 = data[iy * stride + ix + 1];
    uint8_t p01 = data[(iy + 1) * stride + ix];
    uint8_t p11 = data[(iy + 1) * stride + ix + 1];

    uint8_t top = static_cast<uint8_t>(p00 * (1.0f - dx) + p10 * dx + 0.5f);
    uint8_t bot = static_cast<uint8_t>(p01 * (1.0f - dx) + p11 * dx + 0.5f);
    return static_cast<uint8_t>(top * (1.0f - dy) + bot * dy + 0.5f);
}

} // anonymous namespace

AVFrame* ZoomDissolveTransition::apply(AVFrame* fromFrame, AVFrame* toFrame,
                                        float progress) {
    if (!fromFrame || !toFrame) return nullptr;

    AVFrame* output = av_frame_alloc();
    output->format = fromFrame->format;
    output->width = fromFrame->width;
    output->height = fromFrame->height;
    if (av_frame_get_buffer(output, 0) < 0) {
        av_frame_free(&output);
        return nullptr;
    }

    progress = std::max(0.0f, std::min(1.0f, progress));

    const int w = fromFrame->width;
    const int h = fromFrame->height;
    const float halfW = w / 2.0f;
    const float halfH = h / 2.0f;

    // Zoom scale: fromFrame zooms out (scale decreases), toFrame zooms in (scale increases).
    const float fromScale = 1.0f + intensity_ * (1.0f - progress);
    const float toScale = 1.0f / (0.1f + intensity_ * progress);

    // Rotation angle (radians).
    const float angle = rotation_ == 0
        ? progress * 3.14159265f
        : -progress * 3.14159265f;
    const float cosA = std::cos(angle);
    const float sinA = std::sin(angle);

    // Process each plane.
    for (int p = 0; p < 3; ++p) {
        const int pw = (p == 0) ? w : w / 2;
        const int ph = (p == 0) ? h : h / 2;
        const float centerScale = (p == 0) ? 1.0f : 0.5f;

        uint8_t* outRow = output->data[p];
        const uint8_t* fromData = fromFrame->data[p];
        const uint8_t* toData = toFrame->data[p];

        for (int y = 0; y < ph; ++y) {
            uint8_t* d = outRow + y * output->linesize[p];

            for (int x = 0; x < pw; ++x) {
                // Map output pixel to fromFrame coordinates (zoom out + rotate).
                float fxFrom = (x - halfW * centerScale) / fromScale * (1.0f / centerScale) + halfW;
                float fyFrom = (y - halfH * centerScale) / fromScale * (1.0f / centerScale) + halfH;

                // Rotate fromFrame coordinates.
                float rxFrom = fxFrom - halfW;
                float ryFrom = fyFrom - halfH;
                float rxFinal = rxFrom * cosA - ryFrom * sinA + halfW;
                float ryFinal = rxFrom * sinA + ryFrom * cosA + halfH;

                // Map output pixel to toFrame coordinates (zoom in + rotate).
                float fxTo = (x - halfW * centerScale) / toScale * (1.0f / centerScale) + halfW;
                float fyTo = (y - halfH * centerScale) / toScale * (1.0f / centerScale) + halfH;

                // Rotate toFrame coordinates.
                float rxTo = fxTo - halfW;
                float ryTo = fyTo - halfH;
                float rxFinalTo = rxTo * cosA - ryTo * sinA + halfW;
                float ryFinalTo = rxTo * sinA + ryTo * cosA + halfH;

                // Sample both frames.
                uint8_t fromVal = samplePlane(fromData, fromFrame->linesize[p],
                                              pw, ph, rxFinal, ryFinal);
                uint8_t toVal = samplePlane(toData, toFrame->linesize[p],
                                            pw, ph, rxFinalTo, ryFinalTo);

                // Blend based on progress.
                d[x] = static_cast<uint8_t>(fromVal * (1.0f - progress) + toVal * progress + 0.5f);
            }
        }
    }

    return output;
}

} // namespace ghita::timeline
