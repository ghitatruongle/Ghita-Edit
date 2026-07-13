// src/audio/AudioClip.h
#pragma once

#include <cstdint>

namespace ghita::audio {

struct AudioClip {
    float volume = 1.0f;       // 0.0 - 2.0 (dB linear)
    float pan = 0.0f;          // -1.0 (left) to 1.0 (right)
    int fadeInMs = 0;
    int fadeOutMs = 0;

    // EQ (3-band)
    float eqLow = 1.0f;        // Low gain
    float eqMid = 1.0f;        // Mid gain
    float eqHigh = 1.0f;       // High gain
};

} // namespace ghita::audio
