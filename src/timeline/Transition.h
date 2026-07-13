// src/timeline/Transition.h
#pragma once

extern "C" {
#include <libavcodec/avcodec.h>
}

namespace ghita::timeline {

/// Abstract base class for video transitions between clips.
///
/// **Ownership:** The apply() method transfers ownership of the returned
/// AVFrame* to the caller.  The caller is responsible for calling
/// av_frame_free() on the returned frame when it is no longer needed.
/// On failure, apply() returns nullptr and no frame is allocated.
class TransitionEffect {
public:
    virtual ~TransitionEffect() = default;

    /// Apply transition between two frames.
    /// progress: 0.0 = fully fromFrame, 1.0 = fully toFrame.
    /// @returns A newly allocated AVFrame (caller owns it) or nullptr on error.
    virtual AVFrame* apply(AVFrame* fromFrame, AVFrame* toFrame, float progress) = 0;

    // Get transition name
    virtual const char* name() const = 0;

    // Get default duration in milliseconds
    virtual int defaultDurationMs() const = 0;
};

} // namespace ghita::timeline
