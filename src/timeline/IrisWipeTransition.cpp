// src/timeline/IrisWipeTransition.cpp
#include "IrisWipeTransition.h"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace ghita::timeline {

AVFrame* IrisWipeTransition::apply(AVFrame* fromFrame, AVFrame* toFrame, float progress) {
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

    // Compute circle radius based on progress and direction.
    const double cx = centerX_ * fromFrame->width;
    const double cy = centerY_ * fromFrame->height;
    const double maxRadius = std::sqrt(cx * cx + cy * cy); // distance to farthest corner

    double radius;
    if (direction_ == 0) {
        // Expand: starts at 0, grows to cover the whole frame.
        radius = maxRadius * progress;
    } else {
        // Contract: starts full, shrinks to nothing.
        radius = maxRadius * (1.0f - progress);
    }

    const double invRadius = (radius > 0.0) ? (1.0 / radius) : 0.0;

    // Process each plane (Y, U, V).
    for (int p = 0; p < 3; ++p) {
        const int w = (p == 0) ? fromFrame->width : fromFrame->width / 2;
        const int h = (p == 0) ? fromFrame->height : fromFrame->height / 2;
        const double cxp = cx * ((p == 0) ? 1.0 : 0.5);
        const double cyp = cy * ((p == 0) ? 1.0 : 0.5);

        uint8_t* outRow = output->data[p];
        const uint8_t* fromRow = fromFrame->data[p];
        const uint8_t* toRow = toFrame->data[p];

        for (int y = 0; y < h; ++y) {
            uint8_t* d = outRow + y * output->linesize[p];
            const uint8_t* f = fromRow + y * fromFrame->linesize[p];
            const uint8_t* t = toRow + y * toFrame->linesize[p];

            for (int x = 0; x < w; ++x) {
                const double dx = (x - cxp) * invRadius;
                const double dy = (y - cyp) * invRadius;
                const double distSq = dx * dx + dy * dy;

                if (distSq <= 1.0) {
                    // Inside circle: show toFrame.
                    d[x] = t[x];
                } else {
                    // Outside circle: show fromFrame.
                    d[x] = f[x];
                }
            }
        }
    }

    return output;
}

} // namespace ghita::timeline
