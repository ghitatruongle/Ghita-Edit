#pragma once

#include "Decoder.h"
#include "FramePool.h"

#include <QObject>
#include <QVariantList>
#include <atomic>
#include <memory>
#include <mutex>
#include <vector>

namespace ghita::engine {

// ScrubEngine: provides fast frame-by-frame seeking and single-frame decoding
// for timeline scrubbing. Unlike the full MediaEngine playback pipeline, this
// creates a lightweight Decoder, seeks to the requested position, and decodes
// exactly one frame. It also supports snapping to clip edges via SnapEngine.
class ScrubEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(int fps READ fps NOTIFY fpsChanged)

public:
    explicit ScrubEngine(QObject* parent = nullptr);
    ~ScrubEngine() override = default;

    // Whether the engine has an active decoder (a media file is open).
    bool ready() const { return decoder_ != nullptr; }
    int fps() const { return fps_; }

    // Open a media file for scrubbing. Creates a lightweight Decoder.
    Q_INVOKABLE void open(const QString& path);

    // Close the active decoder.
    Q_INVOKABLE void close();

    // Seek to a position (ms) and decode exactly one frame. Returns the
    // RGBA frame if successful, or an empty QByteArray.
    Q_INVOKABLE QByteArray scrubTo(qint64 targetMs, int& outWidth, int& outHeight);

    // Frame-by-frame step in the given direction (1 = forward, -1 = backward).
    Q_INVOKABLE QByteArray stepFrame(int direction, int& outWidth, int& outHeight);

    // Snap a candidate position to the nearest snap target within threshold.
    Q_INVOKABLE qint64 snap(qint64 candidateMs, const QVariantList& targets) const;

signals:
    void readyChanged();
    void fpsChanged();
    void scrubFrameReady(int width, int height, const QByteArray& rgba);

private:
    std::unique_ptr<Decoder> decoder_;
    int fps_ = 30;
    mutable std::mutex mutex_;
};

} // namespace ghita::engine
