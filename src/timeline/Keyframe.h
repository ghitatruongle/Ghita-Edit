// src/timeline/Keyframe.h
#pragma once

#include <vector>

namespace ghita::timeline {

struct Keyframe {
    int timeMs;           // Position on timeline
    float posX, posY;     // Position (relative to frame center)
    float scaleX, scaleY; // Scale (1.0 = 100%)
    float rotation;       // Degrees
    float opacity;        // 0.0 - 1.0

    // Easing
    enum class Easing { Linear, EaseIn, EaseOut, EaseInOut, Bounce };
    Easing easing = Easing::Linear;
};

} // namespace ghita::timeline
