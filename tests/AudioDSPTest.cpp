#include "fx/AudioDSP.h"
#include <gtest/gtest.h>
#include <vector>

using ghita::fx::AudioDSP;

TEST(AudioDSPTest, applyGainScalesSamples) {
    const int N = 8;
    std::vector<float> l(N, 0.5f), r(N, -0.25f);
    float* planes[2] = {l.data(), r.data()};
    AudioDSP::applyGain(planes, 2, N, 2.0f);
    for (int i = 0; i < N; ++i) {
        EXPECT_FLOAT_EQ(l[i], 1.0f);
        EXPECT_FLOAT_EQ(r[i], -0.5f);
    }
}

TEST(AudioDSPTest, applyGainUnityIsNoop) {
    const int N = 4;
    std::vector<float> l(N, 0.5f), r(N, 0.5f);
    float* planes[2] = {l.data(), r.data()};
    AudioDSP::applyGain(planes, 2, N, 1.0f); // early return
    EXPECT_FLOAT_EQ(l[0], 0.5f);
}

TEST(AudioDSPTest, applyFadeInRampsFromZero) {
    const int N = 100;
    std::vector<float> l(N, 1.0f), r(N, 1.0f);
    float* planes[2] = {l.data(), r.data()};
    // startSample=0, total=1000, fade-in over first 100 samples, no fade-out
    AudioDSP::applyFade(planes, 2, N, 0, 1000, 100, 0);
    EXPECT_FLOAT_EQ(l[0], 0.0f);                 // pos 0 -> gain 0
    EXPECT_NEAR(l[99], 0.99f, 1e-3f);            // pos 99 -> gain ~0.99
    EXPECT_NEAR(l[50], 0.5f, 1e-3f);             // midpoint
}

TEST(AudioDSPTest, applyFadeOutRampsToZero) {
    const int N = 100;
    std::vector<float> l(N, 1.0f), r(N, 1.0f);
    float* planes[2] = {l.data(), r.data()};
    // clip of 1000 samples, fade-out over last 100; this frame starts at 901
    AudioDSP::applyFade(planes, 2, N, 901, 1000, 0, 100);
    EXPECT_NEAR(l[0], 0.99f, 1e-3f);             // pos 901 -> remain 99/100
    EXPECT_FLOAT_EQ(l[99], 0.0f);                // pos 1000 -> gain 0
}
