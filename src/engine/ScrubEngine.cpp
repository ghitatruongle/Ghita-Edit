#include "ScrubEngine.h"

#include <QDebug>

namespace ghita::engine {

ScrubEngine::ScrubEngine(QObject* parent)
    : QObject(parent) {
    decoder_ = nullptr;
    fps_ = 30;
}

void ScrubEngine::open(const QString& path) {
    std::lock_guard<std::mutex> lk(mutex_);
    decoder_ = std::make_unique<Decoder>();
    if (decoder_->open(path.toStdString())) {
        fps_ = static_cast<int>(decoder_->videoFps());
        if (fps_ <= 0) fps_ = 30;
        qInfo() << "[ScrubEngine] opened" << path << "fps=" << fps_;
    } else {
        qWarning() << "[ScrubEngine] failed to open" << path;
        decoder_.reset();
    }
    emit readyChanged();
    emit fpsChanged();
}

void ScrubEngine::close() {
    std::lock_guard<std::mutex> lk(mutex_);
    decoder_.reset();
    fps_ = 30;
    emit readyChanged();
    emit fpsChanged();
}

QByteArray ScrubEngine::scrubTo(qint64 targetMs, int& outWidth, int& outHeight) {
    std::lock_guard<std::mutex> lk(mutex_);
    if (!decoder_) {
        outWidth = 0;
        outHeight = 0;
        return {};
    }

    // Seek to the target position.
    if (!decoder_->seek(targetMs)) {
        outWidth = 0;
        outHeight = 0;
        return {};
    }
    currentPositionMs_ = targetMs;

    // Decode exactly one video frame.
    VideoFrameQueue videoQ;
    AudioFrameQueue audioQ;
    Frame frame;

    while (decoder_->decodeStep(videoQ, audioQ)) {
        if (videoQ.try_pop(frame)) {
            outWidth = frame.width;
            outHeight = frame.height;
            return QByteArray(reinterpret_cast<const char*>(frame.rgba.data()),
                              static_cast<int>(frame.rgba.size()));
        }
    }

    outWidth = 0;
    outHeight = 0;
    return {};
}

QByteArray ScrubEngine::stepFrame(int direction, int& outWidth, int& outHeight) {
    std::lock_guard<std::mutex> lk(mutex_);
    if (!decoder_) {
        outWidth = 0;
        outHeight = 0;
        return {};
    }

    // Decode frames until we reach the desired direction count.
    VideoFrameQueue videoQ;
    AudioFrameQueue audioQ;
    Frame frame;
    int steps = 0;
    int target = (direction > 0) ? 1 : -1;

    // Forward stepping: decode one frame at a time.
    if (direction > 0) {
        while (decoder_->decodeStep(videoQ, audioQ)) {
            if (videoQ.try_pop(frame)) {
                outWidth = frame.width;
                outHeight = frame.height;
                return QByteArray(reinterpret_cast<const char*>(frame.rgba.data()),
                                  static_cast<int>(frame.rgba.size()));
            }
        }
    }

    // Backward stepping: seek back by one frame duration and decode.
    if (direction < 0) {
        int64_t frameDuration = (fps_ > 0) ? (1000 / fps_) : 33;
        int64_t seekPos = currentPositionMs_ - frameDuration;
        if (seekPos < 0) seekPos = 0;
        if (decoder_->seek(seekPos)) {
            currentPositionMs_ = seekPos;
            while (decoder_->decodeStep(videoQ, audioQ)) {
                if (videoQ.try_pop(frame)) {
                    outWidth = frame.width;
                    outHeight = frame.height;
                    return QByteArray(reinterpret_cast<const char*>(frame.rgba.data()),
                                      static_cast<int>(frame.rgba.size()));
                }
            }
        }
    }

    outWidth = 0;
    outHeight = 0;
    return {};
}

qint64 ScrubEngine::snap(qint64 candidateMs, const QVariantList& targets) const {
    qint64 bestDist = 10 + 1; // default threshold = 10 ms
    qint64 bestSnap = candidateMs;

    for (const auto& v : targets) {
        qint64 target = v.toLongLong();
        qint64 dist = std::abs(candidateMs - target);
        if (dist < bestDist) {
            bestDist = dist;
            bestSnap = target;
        }
    }

    return bestSnap;
}

} // namespace ghita::engine
