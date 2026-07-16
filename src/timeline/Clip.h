#pragma once

#include <cstdint>
#include <QString>
#include <QColor>
#include <QVector>
#include <QPair>
#include <QVariantMap>
#include <algorithm>

namespace ghita::timeline {

// What kind of content a clip holds. Video/Audio already existed; Text and
// Sticker are the new overlay clip kinds rendered above the main video track.
enum class ClipKind { Video, Audio, Text, Sticker, PipVideo, PipImage };

// A single animatable property's keyframes. Linear interpolation between
// points. Times are milliseconds from project start, sorted ascending.
struct KeyframeTrack {
    QString property;                                  // "posX" | "posY" | "scale" | "rotation" | "opacity" | "cropLeft" | "cropTop" | "cropRight" | "cropBottom"
    QVector<QPair<qint64, double>> points;             // (timeMs, value)

    double valueAt(qint64 t) const {
        if (points.isEmpty()) return 0.0;
        if (t <= points.first().first) return points.first().second;
        if (t >= points.last().first)  return points.last().second;
        for (int i = 0; i < points.size() - 1; ++i) {
            const auto& a = points[i];
            const auto& b = points[i + 1];
            if (t >= a.first && t <= b.first) {
                double f = (b.first == a.first)
                               ? 0.0
                               : double(t - a.first) / double(b.first - a.first);
                return a.second + f * (b.second - a.second);
            }
        }
        return points.last().second;
    }

    // Remove the point nearest to t within tol ms (used when dragging a keyframe).
    void removeNear(qint64 t, qint64 tol) {
        for (int i = 0; i < points.size(); ++i) {
            if (std::abs(points[i].first - t) <= tol) { points.removeAt(i); return; }
        }
    }

    // Move a keyframe from oldT to newT with a new value (overwrites either end).
    void move(qint64 oldT, qint64 newT, double value) {
        removeNear(oldT, 1);
        for (auto& pt : points) {
            if (pt.first == newT) { pt.second = value; return; }
        }
        points.append({newT, value});
        std::sort(points.begin(), points.end(),
                  [](const QPair<qint64, double>& a,
                     const QPair<qint64, double>& b) { return a.first < b.first; });
    }
};

// All keyframe tracks for one clip (overlay clips and, later, video clips).
struct Keyframes {
    QVector<KeyframeTrack> tracks;

    const KeyframeTrack* find(const QString& prop) const {
        for (const auto& tr : tracks)
            if (tr.property == prop) return &tr;
        return nullptr;
    }

    double valueAt(const QString& prop, qint64 t, double fallback) const {
        for (const auto& tr : tracks)
            if (tr.property == prop) return tr.valueAt(t);
        return fallback;
    }

    void set(const QString& prop, qint64 t, double value) {
        for (auto& tr : tracks) {
            if (tr.property == prop) {
                for (auto& pt : tr.points) {
                    if (pt.first == t) { pt.second = value; return; }
                }
                tr.points.append({t, value});
                std::sort(tr.points.begin(), tr.points.end(),
                          [](const QPair<qint64, double>& a,
                             const QPair<qint64, double>& b) { return a.first < b.first; });
                return;
            }
        }
        KeyframeTrack tr;
        tr.property = prop;
        tr.points.append({t, value});
        tracks.append(tr);
    }

    void clear(const QString& prop) {
        for (int i = 0; i < tracks.size(); ++i) {
            if (tracks[i].property == prop) { tracks.removeAt(i); return; }
        }
    }

    // Move a keyframe on the named track (creates the track if needed).
    void move(const QString& prop, qint64 oldT, qint64 newT, double value) {
        for (auto& tr : tracks) {
            if (tr.property == prop) { tr.move(oldT, newT, value); return; }
        }
        KeyframeTrack tr;
        tr.property = prop;
        tr.move(oldT, newT, value);
        tracks.append(tr);
    }

    // Remove the keyframe on the named track nearest to t (within tol ms).
    void removeNear(const QString& prop, qint64 t, qint64 tol) {
        for (auto& tr : tracks)
            if (tr.property == prop) { tr.removeNear(t, tol); return; }
    }
};

// Visual/styling data for Text and Sticker overlay clips. Positions are
// normalized to the project frame (0..1), so they are resolution-independent.
struct OverlayData {
    // Text content (Text clips).
    QString text;
    QString fontFamily;       // empty => system default
    double fontSize = 48;     // pt, relative to project height
    bool bold = false;
    QColor color = Qt::white;
    int align = 1;            // 0 left, 1 center, 2 right
    QColor bgColor = Qt::transparent;

    // Sticker image path (Sticker clips); empty for Text.
    QString stickerPath;

    // Transform (normalized / degrees / 0..1).
    double posX = 0.5;
    double posY = 0.5;
    double scale = 1.0;
    double rotation = 0.0;    // degrees
    double opacity = 1.0;     // 0..1

    // Crop offsets as fractions of the source (0..1).
    // 0 = no crop, 1 = crop the entire edge.
    double cropLeft = 0.0;
    double cropTop = 0.0;
    double cropRight = 0.0;
    double cropBottom = 0.0;

    // Aspect-ratio lock for crop handles (true => all sides scale together).
    bool cropLockAspect = false;

    // Snap-to-center flag (centered on release if true).
    bool cropSnapCenter = false;

    // ---- PIP-specific properties ----
    // Border / stroke around the PIP overlay.
    double pipBorderWidth = 0.0;       // pixels, 0 = no border
    QColor pipBorderColor = Qt::black;
    // Rounded corners for PIP (0 = sharp, >0 = radius in pixels).
    double pipCornerRadius = 0.0;
    // Drop shadow for PIP.
    bool pipShadowEnabled = false;
    int pipShadowBlur = 16;
    int pipShadowOffsetX = 4;
    int pipShadowOffsetY = 4;
    QColor pipShadowColor = QColor(0, 0, 0, 128);

    Keyframes kf;
};

// A transition between two adjacent video clips.
struct Transition {
    int64_t clipAId = 0;
    int64_t clipBId = 0;
    QString type = "crossfade"; // crossfade, fades, iriswipe, directionalwipe, blurdissolve, zoomdissolve
    int64_t durationMs = 500;    // 300..1000
    QVariantMap params;          // Per-transition-type config (direction, center, softness, etc.)
};

// A single clip on the timeline.
//
// Each clip references a region of a source file (srcInMs..srcOutMs) and
// places it at a position on the timeline (timelineStartMs..timelineEndMs).
// Trimming adjusts srcIn/srcOut while keeping the timeline position stable
// (or vice versa for a "ripple" trim, which is a later milestone). Text and
// Sticker clips have no source file (or an image for stickers) and live on the
// overlay track (index 2).
struct Clip {
    int64_t id = 0;
    QString sourcePath;
    ClipKind kind = ClipKind::Video;

    // Timeline placement (milliseconds from project start).
    int64_t timelineStartMs = 0;
    int64_t timelineEndMs = 0;

    // Source region within the file (milliseconds).
    int64_t srcInMs = 0;
    int64_t srcOutMs = 0;

    // Track index (0 = video V1, 1 = audio A1, 2 = overlay V2).
    int trackIndex = 0;

    // Visual hint color (derived from track or user-assigned).
    QString color;

    // Overlay styling (Text/Sticker clips).
    OverlayData overlay;

    // Playback speed multiplier (0.25x .. 4.0x, default 1.0x).
    // Affects how quickly the playhead traverses this clip's duration.
    double playbackSpeed = 1.0;

    // Whether to correct audio pitch when speed changes (default true).
    bool pitchCorrection = true;

    // Duration helpers.
    int64_t durationMs() const { return timelineEndMs - timelineStartMs; }
    int64_t srcDurationMs() const { return srcOutMs - srcInMs; }
    // Effective source duration adjusted by playback speed.
    int64_t effectiveSrcDurationMs() const {
        if (playbackSpeed <= 0.0) return srcDurationMs();
        return static_cast<int64_t>(double(srcDurationMs()) / playbackSpeed);
    }

    bool isValid() const {
        if (durationMs() <= 0) return false;
        if (kind == ClipKind::Video && sourcePath.isEmpty()) return false;
        if (kind == ClipKind::Sticker && stickerPath().isEmpty()) return false;
        return true;
    }

private:
    QString stickerPath() const { return overlay.stickerPath; }
};

} // namespace ghita::timeline
