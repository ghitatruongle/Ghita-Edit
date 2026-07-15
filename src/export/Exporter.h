#pragma once

#include "timeline/TimelineModel.h"

#include <QObject>
#include <QString>
#include <QFuture>

namespace ghita::fx {
class FxController;
}

namespace ghita::export_ {

// Exporter: FFmpeg-based encode + mux pipeline.
//
// M4: takes the timeline model and renders the edited project to an output
// file (MP4 with H.264 video + AAC audio). For each clip, it seeks the source
// to clip.srcInMs, decodes frames until clip.srcOutMs, and re-encodes them
// into the output stream. Video and audio are muxed together.
//
// Uses software libx264 / aac by default (most portable). Hardware encode
// (NVENC/AMF/QuickSync) is a later optimization.
class Exporter : public QObject {
    Q_OBJECT

public:
    explicit Exporter(QObject* parent = nullptr);

    // Export the timeline to outputPath. Returns true on success.
    // Blocking call — run on a worker thread for UI responsiveness.
    Q_INVOKABLE bool exportProject(ghita::timeline::TimelineModel* model,
                                    const QString& outputPath);

    // Asynchronous export (runs on an internal thread, emits progress/finished).
    Q_INVOKABLE void exportAsync(ghita::timeline::TimelineModel* model,
                                 const QString& outputPath);

    // Config knobs.
    Q_INVOKABLE void setBitrate(int64_t bps) { bitrate_ = bps; }
    Q_INVOKABLE void setCrf(int crf) { crf_ = crf; } // 0..51, lower = better quality

    // Override the output resolution (export presets). 0 = use source dims.
    Q_INVOKABLE void setTargetSize(int w, int h);

    // Optional effect controller (brightness/contrast/gain/normalize/fade).
    void setFxController(fx::FxController* fx);

    // Convert a QML FileDialog URL (file://...) to a local filesystem path,
    // across Windows/Linux. Used so export/open accept dialog output directly.
    Q_INVOKABLE static QString urlToLocalPath(const QString& url);

signals:
    void progressChanged(int percent);
    void exportFinished(bool success);

private:
    bool runExport(ghita::timeline::TimelineModel* model,
                   const QString& outputPath);

    int64_t bitrate_ = 8'000'000; // 8 Mbps
    int crf_ = 23;                // x264 quality
    int targetW_ = 0;             // 0 = use source dimensions
    int targetH_ = 0;
    fx::FxController* fx_ = nullptr;
    QFuture<void> exportFuture_;  // holds the async task so it stays alive
};

} // namespace ghita::export_
