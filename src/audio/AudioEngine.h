#pragma once

#include "AudioClock.h"
#include "TimelineAudioMixer.h"
#include "../engine/FramePool.h"

#include <QObject>
#include <QString>
#include <array>

extern "C" {
#include <portaudio.h>
}

namespace ghita::audio {

// AudioEngine: low-latency audio output via PortAudio.
//
// M0: pulls interleaved float PCM frames from the Decoder's AudioFrameQueue
// (48 kHz stereo) and plays them. The clock advances by the number of
// samples consumed, serving as the A/V master clock.
class AudioEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
    explicit AudioEngine(QObject* parent = nullptr);
    ~AudioEngine() override;

    bool active() const { return active_; }

    bool init();

    // Bind the queue the callback will pull PCM from. Call before start().
    void setSourceQueue(ghita::engine::AudioFrameQueue* queue) { queue_ = queue; }

    // When set, the callback delegates mixing to this timeline mixer instead
    // of pulling from the file audio queue. Pass nullptr to restore file mode.
    void setMixerSource(TimelineAudioMixer* m) { mixer_ = m; }

    AudioClock& clock() { return clock_; }

    // ---- Per-track mixing (linear gain 0..2, pan -1..1, mute) ----
    void setTrackVolume(int trackIndex, float linearGain);
    float trackVolume(int trackIndex) const;
    void setTrackPan(int trackIndex, float pan);   // -1.0 left .. 1.0 right
    float trackPan(int trackIndex) const;
    void setTrackMute(int trackIndex, bool muted);
    bool isTrackMuted(int trackIndex) const;
    void setMasterVolume(float linearGain);
    float masterVolume() const;

public slots:
    void start(qint64 startUs = 0);
    void stop();

signals:
    void activeChanged(bool);

private:
    static int paCallback(const void* input, void* output,
                          unsigned long frameCount,
                          const PaStreamCallbackTimeInfo* timeInfo,
                          PaStreamCallbackFlags statusFlags,
                          void* userData);

    PaStream* stream_ = nullptr;
    AudioClock clock_;
    ghita::engine::AudioFrameQueue* queue_ = nullptr;
    TimelineAudioMixer* mixer_ = nullptr;
    bool active_ = false;
    // Reusable staging buffer for the current frame being consumed.
    std::vector<float> staging_;
    size_t stagingPos_ = 0;

    static constexpr int kMaxTracks = 16;
    std::array<float, kMaxTracks> trackGain_ = {};    // 0.0..2.0 (linear)
    std::array<float, kMaxTracks> trackPan_  = {};    // -1.0..1.0
    std::array<bool,  kMaxTracks> trackMuted_ = {};   // true = silent
    float masterGain_ = 1.0f;
};

} // namespace ghita::audio
