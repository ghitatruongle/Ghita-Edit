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

    // U plane (half size)
    size = (fromFrame->width / 2) * (fromFrame->height / 2);
    uint8_t* fromU = fromFrame->data[1];
    uint8_t* toU = toFrame->data[1];
    uint8_t* outU = output->data[1];

    for (int i = 0; i < size; i++) {
        outU[i] = static_cast<uint8_t>(fromU[i] * alpha + toU[i] * beta);
    }

    // V plane (half size)
    uint8_t* fromV = fromFrame->data[2];
    uint8_t* toV = toFrame->data[2];
    uint8_t* outV = output->data[2];

    for (int i = 0; i < size; i++) {
        outV[i] = static_cast<uint8_t>(fromV[i] * alpha + toV[i] * beta);
    }

    return output;
}

} // namespace ghita::timeline
