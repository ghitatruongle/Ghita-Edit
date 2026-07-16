// src/timeline/ZoomDissolveTransition.h
#pragma once

#include "Transition.h"

namespace ghita::timeline {

/// Zoom dissolve: the destination clip "zooms in" from a tiny circle while
/// the source clip simultaneously zooms out. Creates a dynamic spinning
/// transition effect.
class ZoomDissolveTransition : public TransitionEffect {
public:
    AVFrame* apply(AVFrame* fromFrame, AVFrame* toFrame, float progress) override;
    const char* name() const override { return "ZoomDissolve"; }
    int defaultDurationMs() const override { return 700; }

    // Zoom intensity: 1.0 = mild, 2.0 = moderate, 3.0 = strong.
    void setIntensity(double i) { intensity_ = i; }
    double intensity() const { return intensity_; }

    // Rotation direction: 0 = clockwise, 1 = counter-clockwise.
    void setRotation(int r) { rotation_ = r; }
    int rotation() const { return rotation_; }

private:
    double intensity_ = 1.5;
    int rotation_ = 0; // 0 = CW, 1 = CCW
};

} // namespace ghita::timeline
