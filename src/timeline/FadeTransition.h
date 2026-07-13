// src/timeline/FadeTransition.h
#pragma once

#include "Transition.h"

namespace ghita::timeline {

class FadeTransition : public TransitionEffect {
public:
    AVFrame* apply(AVFrame* fromFrame, AVFrame* toFrame, float progress) override;
    const char* name() const override { return "Fade"; }
    int defaultDurationMs() const override { return 1000; }
};

} // namespace ghita::timeline
