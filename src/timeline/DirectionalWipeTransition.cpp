// src/timeline/DirectionalWipeTransition.cpp
#include "DirectionalWipeTransition.h"
#include <algorithm>
#include <cmath>

namespace ghita::timeline {

AVFrame* DirectionalWipeTransition::apply(AVFrame* fromFrame, AVFrame* toFrame, float progress) {
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

    // Compute the sweep fraction for each direction.
    double sweep = 0.0;
    int dir = direction_ % 6;

    switch (dir) {
        case 0: // Left to right
            sweep = progress;
            break;
        case 1: // Right to left
            sweep = 1.0 - progress;
            break;
        case 2: // Top to bottom
            sweep = progress;
            break;
        case 3: // Bottom to top
            sweep = 1.0 - progress;
            break;
        case 4: // Diagonal: top-left to bottom-right
            sweep = (progress * (w + h)) / static_cast<double>(w + h);
            // For diagonal, position along the diagonal axis.
            break;
        case 5: // Diagonal: top-right to bottom-left
            sweep = 1.0 - progress;
            break;
    }

    // Process each plane.
    for (int p = 0; p < 3; ++p) {
        const int pw = (p == 0) ? w : w / 2;
        const int ph = (p == 0) ? h : h / 2;
        const double sx = sweep * pw;
        const double sy = sweep * ph;
        const double ss = softness_ * ((p == 0) ? 1.0 : 0.5);

        uint8_t* outRow = output->data[p];
        const uint8_t* fromRow = fromFrame->data[p];
        const uint8_t* toRow = toFrame->data[p];

        for (int y = 0; y < ph; ++y) {
            uint8_t* d = outRow + y * output->linesize[p];
            const uint8_t* f = fromRow + y * fromFrame->linesize[p];
            const uint8_t* t = toRow + y * toFrame->linesize[p];

            for (int x = 0; x < pw; ++x) {
                double alpha = 0.0;

                switch (dir) {
                    case 0: // Left to right
                        alpha = (x <= sx) ? 1.0 : 0.0;
                        break;
                    case 1: // Right to left
                        alpha = (x >= pw - sx) ? 1.0 : 0.0;
                        break;
                    case 2: // Top to bottom
                        alpha = (y <= sy) ? 1.0 : 0.0;
                        break;
                    case 3: // Bottom to top
                        alpha = (y >= ph - sy) ? 1.0 : 0.0;
                        break;
                    case 4: // Diagonal TL to BR
                        // Guard against pw + ph <= 2 which causes divide-by-zero.
                        if (pw + ph <= 2) { alpha = 1.0; break; }
                        alpha = ((static_cast<double>(x) + static_cast<double>(y)) / (pw + ph - 2.0) <= sweep) ? 1.0 : 0.0;
                        break;
                    case 5: // Diagonal TR to BL
                        if (pw + ph <= 2) { alpha = 1.0; break; }
                        alpha = ((static_cast<double>(pw - 1 - x) + static_cast<double>(y)) / (pw + ph - 2.0) <= sweep) ? 1.0 : 0.0;
                        break;
                }

                // Apply softness (feather edge).
                if (ss > 0) {
                    double dist = 0.0;
                    switch (dir) {
                        case 0: dist = (alpha > 0.5) ? (sx - x) : (x - sx); break;
                        case 1: dist = (alpha > 0.5) ? (x - (pw - sx)) : ((pw - sx) - x); break;
                        case 2: dist = (alpha > 0.5) ? (sy - y) : (y - sy); break;
                        case 3: dist = (alpha > 0.5) ? (y - (ph - sy)) : ((ph - sy) - y); break;
                        case 4: dist = (alpha > 0.5) ? ((sx + sy) - (x + y)) : ((x + y) - (sx + sy)); break;
                        case 5: dist = (alpha > 0.5) ? ((pw - sx + sy) - (pw - 1 - x + y)) : ((pw - 1 - x + y) - (pw - sx + sy)); break;
                    }
                    if (std::abs(dist) < ss) {
                        alpha = std::max(0.0, std::min(1.0, (ss - std::abs(dist)) / ss));
                    }
                }

                d[x] = static_cast<uint8_t>(
                    (1.0 - alpha) * f[x] + alpha * t[x] + 0.5);
            }
        }
    }

    return output;
}

} // namespace ghita::timeline
