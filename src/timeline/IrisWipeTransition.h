// src/timeline/IrisWipeTransition.h
#pragma once

#include "Transition.h"

namespace ghita::timeline {

/// Iris wipe: a circular mask that expands (or contracts) from the center point,
/// revealing the destination clip inside the circle.
class IrisWipeTransition : public TransitionEffect {
public:
    AVFrame* apply(AVFrame* fromFrame, AVFrame* toFrame, float progress) override;
    const char* name() const override { return "IrisWipe"; }
    int defaultDurationMs() const override { return 800; }

    // Configurable parameters (exposed to QML via transition params).
    // centerFractionX/Y in [0,1] — where the iris originates (default 0.5, 0.5).
    void setCenter(double cx, double cy) { centerX_ = cx; centerY_ = cy; }
    double centerX() const { return centerX_; }
    double centerY() const { return centerY_; }

    // Direction: 0 = expand (reveal), 1 = contract (close).
    void setDirection(int d) { direction_ = d; }
    int direction() const { return direction_; }

private:
    double centerX_ = 0.5;
    double centerY_ = 0.5;
    int direction_ = 0; // 0 = expand, 1 = contract
};

} // namespace ghita::timeline
