// src/timeline/DirectionalWipeTransition.h
#pragma once

#include "Transition.h"

namespace ghita::timeline {

/// Directional wipe: a straight line sweeps across the frame in a given
/// direction (left, right, up, down, diagonal), revealing the destination
/// clip behind it.
class DirectionalWipeTransition : public TransitionEffect {
public:
    AVFrame* apply(AVFrame* fromFrame, AVFrame* toFrame, float progress) override;
    const char* name() const override { return "DirectionalWipe"; }
    int defaultDurationMs() const override { return 600; }

    // Direction: 0=left-to-right, 1=right-to-left, 2=top-to-bottom,
    // 3=bottom-to-top, 4=diagonal (top-left to bottom-right),
    // 5=diagonal (top-right to bottom-left).
    void setDirection(int d) { direction_ = d; }
    int direction() const { return direction_; }

    // Softness in pixels (0 = hard edge, 10 = feathered).
    void setSoftness(int px) { softness_ = px; }
    int softness() const { return softness_; }

private:
    int direction_ = 0;
    int softness_ = 0;
};

} // namespace ghita::timeline
