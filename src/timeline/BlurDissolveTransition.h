// src/timeline/BlurDissolveTransition.h
#pragma once

#include "Transition.h"

namespace ghita::timeline {

/// Blur dissolve: both frames are blurred proportionally as the transition
/// progresses, then sharpen back to the destination. Creates a dreamy dissolve.
class BlurDissolveTransition : public TransitionEffect {
public:
    AVFrame* apply(AVFrame* fromFrame, AVFrame* toFrame, float progress) override;
    const char* name() const override { return "BlurDissolve"; }
    int defaultDurationMs() const override { return 1000; }

    // Max blur radius in pixels (1..20).
    void setMaxBlur(int px) { maxBlur_ = px; }
    int maxBlur() const { return maxBlur_; }

    // Blur curve: 0 = linear, 1 = ease-in-out (more blur in the middle).
    void setCurve(int c) { curve_ = c; }
    int curve() const { return curve_; }

private:
    int maxBlur_ = 5;
    int curve_ = 1; // 0 = linear, 1 = ease
};

} // namespace ghita::timeline
