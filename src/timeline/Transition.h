// src/timeline/Transition.h
#pragma once

#include <QString>
#include <QVariantMap>
#include <memory>

extern "C" {
#include <libavcodec/avcodec.h>
}

namespace ghita::timeline {

class TransitionEffect;

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

/// Factory function: creates a TransitionEffect from a type string and params.
/// Supported types: "crossfade", "fades", "iriswipe", "directionalwipe",
///                   "blurdissolve", "zoomdissolve".
/// Returns nullptr if the type is unknown.
std::unique_ptr<TransitionEffect> createTransitionEffect(const QString& type,
                                                          const QVariantMap& params = {});

/// Return a list of all supported transition type names.
QVector<QString> supportedTransitionTypes();

/// Return human-readable label for a transition type.
QString transitionLabel(const QString& type);

/// Return icon unicode character for a transition type.
QString transitionIcon(const QString& type);

} // namespace ghita::timeline
