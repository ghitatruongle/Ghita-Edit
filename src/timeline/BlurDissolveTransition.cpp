// src/timeline/BlurDissolveTransition.cpp
#include "BlurDissolveTransition.h"
#include <algorithm>
#include <cmath>
#include <vector>

namespace ghita::timeline {

namespace {

// Simple box blur on a single plane. kernelSize must be odd and >= 1.
void boxBlurPlane(uint8_t* dst, const uint8_t* src, int w, int h,
                  int stride, int kernelSize) {
    if (kernelSize <= 1) {
        memcpy(dst, src, static_cast<size_t>(stride) * h);
        return;
    }
    const int r = kernelSize / 2;
    std::vector<int32_t> temp(static_cast<size_t>(w) * h);

    // Horizontal pass.
    for (int y = 0; y < h; ++y) {
        const uint8_t* row = src + y * stride;
        int32_t* trow = temp.data() + y * w;
        int32_t sum = 0;
        for (int x = 0; x < w + 2 * r; ++x) {
            sum += (x < w) ? row[x] : row[0];
            if (x >= 2 * r) {
                trow[x - 2 * r] = sum;
            }
        }
    }

    // Vertical pass.
    for (int x = 0; x < w; ++x) {
        int32_t sum = 0;
        for (int y = 0; y < h + 2 * r; ++y) {
            int32_t val = (y < h) ? temp[y * w + x] : temp[0];
            sum += val;
            if (y >= 2 * r) {
                dst[(y - 2 * r) * stride + x] =
                    static_cast<uint8_t>(std::max(0, std::min(255,
                    static_cast<int>(sum / kernelSize))));
            }
        }
    }
}

// Compute blur amount based on progress and curve setting.
// Returns blur radius in [1, maxBlur].
int blurAmount(float progress, int maxBlur, int curve) {
    if (curve == 0) {
        // Linear: max at midpoint (0.5), tapering to 1 at ends.
        float t = std::abs(progress - 0.5f) * 2.0f; // 1.0 at ends, 0.0 at midpoint
        return static_cast<int>(1.0f + (maxBlur - 1.0f) * (1.0f - t));
    } else {
        // Ease: more blur in the middle of the transition.
        float t = std::sin(progress * 3.14159265f); // peaks at 0.5
        return static_cast<int>(1.0f + (maxBlur - 1.0f) * t);
    }
}

} // anonymous namespace

AVFrame* BlurDissolveTransition::apply(AVFrame* fromFrame, AVFrame* toFrame,
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

    // Blend alpha: standard crossfade.
    float alpha = progress;

    // Blur amount depends on progress — more blur near the midpoint.
    const int blur = blurAmount(progress, maxBlur_, curve_);

    // Process each plane.
    for (int p = 0; p < 3; ++p) {
        const int w = (p == 0) ? fromFrame->width : fromFrame->width / 2;
        const int h = (p == 0) ? fromFrame->height : fromFrame->height / 2;

        // Temporary buffers for blurred frames.
        std::vector<uint8_t> fromBlurred(static_cast<size_t>(fromFrame->linesize[p]) * h);
        std::vector<uint8_t> toBlurred(static_cast<size_t>(output->linesize[p]) * h);

        // Box blur on fromFrame.
        boxBlurPlane(fromBlurred.data(), fromFrame->data[p], w, h,
                     fromFrame->linesize[p], blur);

        // Box blur on toFrame.
        boxBlurPlane(toBlurred.data(), toFrame->data[p], w, h,
                     toFrame->linesize[p], blur);

        // Blend blurred versions.
        uint8_t* outRow = output->data[p];
        for (int y = 0; y < h; ++y) {
            uint8_t* d = outRow + y * output->linesize[p];
            const uint8_t* fb = fromBlurred.data() + y * fromFrame->linesize[p];
            const uint8_t* tb = toBlurred.data() + y * toFrame->linesize[p];

            for (int x = 0; x < w; ++x) {
                d[x] = static_cast<uint8_t>(fb[x] * (1.0f - alpha) + tb[x] * alpha + 0.5f);
            }
        }
    }

    return output;
}

} // namespace ghita::timeline
