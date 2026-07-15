#include "MediaEngine.h"
#include "../audio/AudioEngine.h"
#include "../audio/AudioClock.h"

#include <QDebug>

namespace ghita::engine {

MediaEngine::MediaEngine(ghita::audio::AudioEngine* audio, QObject* parent)
    : QObject(parent), audio_(audio) {
    positionTimer_ = new QTimer(this);
    positionTimer_->setInterval(50); // 20 fps position updates
    connect(positionTimer_, &QTimer::timeout, this, &MediaEngine::onPositionTick);
    qInfo() << "[MediaEngine] constructed (M1)";
}

MediaEngine::~MediaEngine() {
    stop();
}

void MediaEngine::open(const QString& path) {
    stop();
    mediaPath_ = path;

    decoder_ = std::make_unique<Decoder>();
    if (!decoder_->open(path.toStdString())) {
        qWarning() << "[MediaEngine] failed to open" << path;
        decoder_.reset();
        emit mediaPathChanged(QString{});
        return;
    }
    qInfo() << "[MediaEngine] opened" << path;
    durationMs_ = decoder_->durationMs();
    emit durationChanged(durationMs_);
    emit mediaPathChanged(mediaPath_);
}

qint64 MediaEngine::positionMs() const {
    if (!audio_) return 0;
    return audio_->clock().positionUs() / 1000;
}

void MediaEngine::seek(qint64 targetMs) {
    if (!decoder_) return;

    bool wasPlaying = playing_;
    if (wasPlaying) {
        stopWorker();
        if (audio_) audio_->stop();
        playing_ = false;
        emit playingChanged(playing_);
    }

    decoder_->seek(targetMs);
    if (audio_) audio_->clock().start(); // reset clock from zero
    emit positionChanged(targetMs);

    if (wasPlaying) {
        // Restart decode from new position.
        play();
    }
}

void MediaEngine::stopWorker() {
    if (!worker_) return;
    emit requestStop();
    workerThread_.quit();
    workerThread_.wait();
    worker_ = nullptr; // deleteLater was scheduled via finished->deleteLater
}

void MediaEngine::play() {
    if (!decoder_ || playing_) return;
    if (worker_) return;                 // a worker is already alive
    if (workerThread_.isRunning()) return;

    // Bind audio queue to the audio engine and start playback.
    if (audio_) {
        audio_->setSourceQueue(&audioQ_);
        audio_->start();
    }

    worker_ = new DecodeWorker(decoder_.get(), &videoQ_, &audioQ_);
    worker_->moveToThread(&workerThread_);
    connect(&workerThread_, &QThread::finished, worker_, &QObject::deleteLater);
    connect(this, &MediaEngine::startDecode, worker_, &DecodeWorker::run);
    connect(worker_, &DecodeWorker::frameReady,
            this, &MediaEngine::onFrameReady);
    connect(worker_, &DecodeWorker::finished,
            this, &MediaEngine::onDecodeFinished);
    connect(this, &MediaEngine::requestStop, worker_, &DecodeWorker::stop);

    workerThread_.start();
    playing_ = true;
    positionTimer_->start();
    emit playingChanged(playing_);
    emit startDecode();
    qInfo() << "[MediaEngine] playback started";
}

void MediaEngine::pause() {
    if (!playing_) return;
    stopWorker();
    if (audio_) audio_->stop();
    positionTimer_->stop();
    playing_ = false;
    emit playingChanged(playing_);
    qInfo() << "[MediaEngine] paused";
}

void MediaEngine::stop() {
    stopWorker();
    if (audio_) audio_->stop();
    positionTimer_->stop();
    playing_ = false;
    decoder_.reset();
    while (videoQ_.size() > 0) { Frame f; videoQ_.try_pop(f); }
    while (audioQ_.size() > 0) { Frame f; audioQ_.try_pop(f); }
    qInfo() << "[MediaEngine] stopped";
    emit playingChanged(playing_);
    emit mediaPathChanged(QString{});
}

void MediaEngine::onFrameReady(int width, int height, const QByteArray& rgba) {
    if (preview_) preview_->setFrame(width, height, rgba);
}

void MediaEngine::onDecodeFinished() {
    positionTimer_->stop();
    playing_ = false;
    emit playingChanged(playing_);
    qInfo() << "[MediaEngine] decode finished (end of stream)";
}

void MediaEngine::onPositionTick() {
    emit positionChanged(positionMs());
}

} // namespace ghita::engine
