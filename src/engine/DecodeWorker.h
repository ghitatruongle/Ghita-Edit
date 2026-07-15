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
// M0.5: frame throttle — yields 1 ms between iterations so the decode loop
// doesn't burn 100 % CPU. When the video ring-buffer is full (backpressure),
// sleeps 5 ms to let the renderer consume frames.
class DecodeWorker : public QObject {
    Q_OBJECT
public:
    explicit DecodeWorker(Decoder* decoder,
                          VideoFrameQueue* videoQ,
                          AudioFrameQueue* audioQ,
                          QObject* parent = nullptr)
        : QObject(parent), decoder_(decoder), videoQ_(videoQ), audioQ_(audioQ) {}

signals:
    void frameReady(int width, int height, const QByteArray& rgba);
    void finished();

public slots:
    void run() {
        while (!stop_.load() && decoder_->decodeStep(*videoQ_, *audioQ_)) {
            // Emit all ready video frames.
            Frame f;
            while (videoQ_->try_pop(f)) {
                QByteArray ba(reinterpret_cast<const char*>(f.rgba.data()),
                              static_cast<int>(f.rgba.size()));
                emit frameReady(f.width, f.height, ba);
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
};

} // namespace ghita::engine
