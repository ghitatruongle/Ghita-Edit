#pragma once

#include <cstdint>

namespace ghita::fx {

// AudioDSP: offline audio processing applied to planar float PCM during export
// (M2). Real-time preview processing on the audio thread is a later step.
class AudioDSP {
public:
    // Multiply every sample by `gain` (linear factor).
    static void applyGain(float** planes, int channels, int samples, float gain);

    // Apply a linear fade-in over the first `fadeInSamples` and fade-out over
    // the last `fadeOutSamples` of a clip. `startSample` is this frame's offset
    // within the clip; `totalSamples` is the clip length (0 disables fade-out).
    static void applyFade(float** planes, int channels, int samples,
                          int64_t startSample, int64_t totalSamples,
                          int64_t fadeInSamples, int64_t fadeOutSamples);
};

} // namespace ghita::fx
