#pragma once

#include "Decoder.h"
#include "FramePool.h"
#include "DecodeWorker.h"
#include "render/PreviewSurface.h"
#include "../audio/TimelineAudioMixer.h"

#include <QObject>
#include <QString>
#include <QThread>
#include <QTimer>
#include <atomic>
#include <memory>

namespace ghita::audio { class AudioEngine; }
namespace ghita::timeline { class TimelineModel; }

namespace ghita::engine {

// MediaEngine: top-level orchestrator. Owns the Decoder and runs a worker
// thread that decodes frames; emits each decoded video frame to the GUI
// (PreviewSurface) and feeds audio frames to the AudioEngine.
class MediaEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(QString mediaPath READ mediaPath NOTIFY mediaPathChanged)
    Q_PROPERTY(ghita::render::PreviewSurface* preview READ preview CONSTANT)
    Q_PROPERTY(qint64 durationMs READ durationMs NOTIFY durationChanged)
    Q_PROPERTY(qint64 positionMs READ positionMs NOTIFY positionChanged)
    Q_PROPERTY(double playbackSpeed READ playbackSpeed WRITE setPlaybackSpeed NOTIFY playbackSpeedChanged)

public:
    explicit MediaEngine(ghita::audio::AudioEngine* audio, QObject* parent = nullptr);
    ~MediaEngine() override;

    bool playing() const { return playing_; }
    QString mediaPath() const { return mediaPath_; }
    ghita::render::PreviewSurface* preview() { return preview_; }
    qint64 durationMs() const { return durationMs_; }
    qint64 positionMs() const;
    Q_INVOKABLE void setPreview(ghita::render::PreviewSurface* p) { preview_ = p; }

    // Seek to a position in milliseconds.
    Q_INVOKABLE void seek(qint64 targetMs);

    // Playback speed (0.25 to 4.0). Applied to the current clip during preview.
    Q_INVOKABLE double playbackSpeed() const { return playbackSpeed_; }
    void setPlaybackSpeed(double speed);

    // Bind the timeline whose audio clips should be mixed during playback.
    void setTimeline(ghita::timeline::TimelineModel* t) { timeline_ = t; }

public slots:
    void open(const QString& path);
    void play(qint64 startUs = 0);
    void pause();
    void stop();

signals:
    void playingChanged(bool);
    void mediaPathChanged(const QString&);
    void durationChanged(qint64);
    void positionChanged(qint64);
    void startDecode();
    void requestStop();
    void playbackSpeedChanged(double);

private slots:
    void onFrameReady(int width, int height, const QByteArray& rgba);
    void onDecodeFinished();
    void onPositionTick();

private:
    void stopWorker();  // tear down the decode worker + thread, clear worker_

    ghita::render::PreviewSurface* preview_ = nullptr;
    ghita::audio::AudioEngine* audio_ = nullptr;
    ghita::timeline::TimelineModel* timeline_ = nullptr;
    ghita::audio::TimelineAudioMixer audioMixer_;
    std::unique_ptr<Decoder> decoder_;
    VideoFrameQueue videoQ_;
    AudioFrameQueue audioQ_;
    QThread workerThread_;
    DecodeWorker* worker_ = nullptr;
    bool playing_ = false;
    QString mediaPath_;
    qint64 durationMs_ = 0;
    QTimer* positionTimer_ = nullptr;
    double playbackSpeed_ = 1.0;
};

} // namespace ghita::engine
