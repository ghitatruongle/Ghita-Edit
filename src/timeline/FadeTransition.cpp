// src/timeline/FadeTransition.cpp
#include "FadeTransition.h"
#include <algorithm>
#include <cstring>

namespace ghita::timeline {

AVFrame* FadeTransition::apply(AVFrame* fromFrame, AVFrame* toFrame, float progress) {
    if (!fromFrame || !toFrame) return nullptr;

    // Create output frame
    AVFrame* output = av_frame_alloc();
    output->format = fromFrame->format;
    output->width = fromFrame->width;
    output->height = fromFrame->height;
    if (av_frame_get_buffer(output, 0) < 0) {
        av_frame_free(&output);
        return nullptr;
    }

    // Clamp progress
    progress = std::max(0.0f, std::min(1.0f, progress));

    // Blend frames: output = from * (1 - progress) + to * progress
    int size = fromFrame->width * fromFrame->height;
    uint8_t* fromY = fromFrame->data[0];
    uint8_t* toY = toFrame->data[0];
    uint8_t* outY = output->data[0];

    float alpha = 1.0f - progress;
    float beta = progress;

    // Y plane
    for (int i = 0; i < size; i++) {
        outY[i] = static_cast<uint8_t>(fromY[i] * alpha + toY[i] * beta);
    }

    // U plane (half size, linesize-aware)
    const int uw = fromFrame->width / 2;
    const int uh = fromFrame->height / 2;
    for (int row = 0; row < uh; ++row) {
        uint8_t* fromU = fromFrame->data[1] + row * fromFrame->linesize[1];
        uint8_t* toU = toFrame->data[1] + row * toFrame->linesize[1];
        uint8_t* outU = output->data[1] + row * output->linesize[1];
        for (int col = 0; col < uw; ++col) {
            outU[col] = static_cast<uint8_t>(fromU[col] * alpha + toU[col] * beta);
        }
    }

    // V plane (half size, linesize-aware)
    for (int row = 0; row < uh; ++row) {
        uint8_t* fromV = fromFrame->data[2] + row * fromFrame->linesize[2];
        uint8_t* toV = toFrame->data[2] + row * toFrame->linesize[2];
        uint8_t* outV = output->data[2] + row * output->linesize[2];
        for (int col = 0; col < uw; ++col) {
            outV[col] = static_cast<uint8_t>(fromV[col] * alpha + toV[col] * beta);
        }
    }

    return output;
}

} // namespace ghita::timeline
