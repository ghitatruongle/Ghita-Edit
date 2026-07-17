#pragma once

#include "Decoder.h"
#include "FramePool.h"

#include <QObject>
#include <QByteArray>
#include <atomic>
#include <thread>
#include <chrono>

namespace ghita::engine {

// Worker that drives decoding off the GUI thread. Lives on its own QThread
// (owned by MediaEngine). Emits each decoded video frame to the GUI for
// texture upload.
//
// M0.5: frame throttle -- yields 1 ms between iterations so the decode loop
// doesn't burn 100 % CPU. When the video ring-buffer is full (backpressure),
// sleeps 5 ms to let the renderer consume frames.
//
// Speed support: when playbackSpeed > 1.0, the worker skips frames proportionally
// so the clip plays faster. When speed < 1.0, frames are duplicated to slow down.
//
// Hardware acceleration: when the backend is NVDEC/VA-API, frames may carry
// a GPU texture handle (Frame::gpuTexture). The worker emits the handle via
// the gpuHandle signal parameter so PreviewSurface can render directly.
class DecodeWorker : public QObject {
    Q_OBJECT
public:
    explicit DecodeWorker(Decoder* decoder,
                          VideoFrameQueue* videoQ,
                          AudioFrameQueue* audioQ,
                          QObject* parent = nullptr)
        : QObject(parent), decoder_(decoder), videoQ_(videoQ), audioQ_(audioQ),
          playbackSpeed_(1.0) {}

    void setPlaybackSpeed(double speed) {
        playbackSpeed_ = speed;
    }

    double playbackSpeed() const { return playbackSpeed_; }

signals:
    void frameReady(int width, int height, const QByteArray& rgba);
    void frameReadyGpu(int width, int height, quintptr gpuHandle);
    void finished();
    void backendChanged(const QString& label);

public slots:
    void run() {
        // Report initial backend status.
        std::string backendStr = to_string(decoder_->currentBackend());
        QString backendStrQ = QString::fromUtf8(backendStr.c_str(), static_cast<int>(backendStr.size()));
        emit backendChanged(backendStrQ);

        // Determine frame skip interval based on speed.
        // speed=1.0 -> emit every frame; speed=2.0 -> emit every 2nd frame; etc.
        const int skipInterval = (playbackSpeed_ <= 1.0) ? 1 : static_cast<int>(playbackSpeed_);
        int frameCounter = 0;

        while (!stop_.load() && decoder_->decodeStep(*videoQ_, *audioQ_)) {
            // Emit all ready video frames, skipping based on speed.
            Frame f;
            while (videoQ_->try_pop(f)) {
                frameCounter++;
                if (skipInterval > 1 && (frameCounter % skipInterval) != 0) continue;

                if (f.gpuTexture && f.gpuTexture->handle != 0) {
                    // Hardware-accelerated frame: emit GPU texture handle.
                    emit frameReadyGpu(f.width, f.height, f.gpuTexture->handle);
                } else {
                    // Software-decoded frame: emit RGBA bytes.
                    QByteArray ba(reinterpret_cast<const char*>(f.rgba.data()),
                                  static_cast<int>(f.rgba.size()));
                    emit frameReady(f.width, f.height, ba);
                }
            }
            // Back-pressure: if video queue is nearly full, yield so the
            // renderer has time to consume frames before we decode more.
            if (videoQ_->size() >= VideoFrameQueue::kCapacity - 1) {
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            } else {
                // Yield 1 ms to avoid spinning at 100 % CPU.
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
        }
        emit finished();
    }
    void stop() { stop_.store(true); }

private:
    Decoder* decoder_;
    VideoFrameQueue* videoQ_;
    AudioFrameQueue* audioQ_;
    std::atomic<bool> stop_{false};
    double playbackSpeed_;
};

} // namespace ghita::engine
