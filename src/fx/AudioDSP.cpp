#include "AudioDSP.h"

#include <algorithm>

namespace ghita::fx {

void AudioDSP::applyGain(float** planes, int channels, int samples, float gain) {
    if (gain == 1.0f) return;
    for (int c = 0; c < channels; ++c) {
        float* p = planes[c];
        for (int i = 0; i < samples; ++i) p[i] *= gain;
    }
}

void AudioDSP::applyFade(float** planes, int channels, int samples,
                         int64_t startSample, int64_t totalSamples,
                         int64_t fadeInSamples, int64_t fadeOutSamples) {
    if (fadeInSamples <= 0 && fadeOutSamples <= 0) return;
    for (int i = 0; i < samples; ++i) {
        int64_t pos = startSample + i;
        float g = 1.0f;
        if (fadeInSamples > 0 && pos < fadeInSamples)
            g *= static_cast<float>(pos) / static_cast<float>(fadeInSamples);
        if (fadeOutSamples > 0 && totalSamples > 0 &&
            pos > totalSamples - fadeOutSamples) {
            int64_t remain = totalSamples - pos;
            g *= static_cast<float>(remain) / static_cast<float>(fadeOutSamples);
        }
        for (int c = 0; c < channels; ++c) planes[c][i] *= g;
    }
}

} // namespace ghita::fx
