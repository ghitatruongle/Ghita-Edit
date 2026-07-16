#include "AudioEngine.h"

#include <QDebug>
#include <algorithm>
#include <cmath>

namespace ghita::audio {

AudioEngine::AudioEngine(QObject* parent) : QObject(parent) {
    // Every track starts at unity gain so audio is audible by default
    // (trackGain_ is value-initialized to 0.0f, which would be silent).
    trackGain_.fill(1.0f);
    qInfo() << "[AudioEngine] constructed (M0)";
}

AudioEngine::~AudioEngine() {
    if (stream_) {
        Pa_StopStream(stream_);
        Pa_CloseStream(stream_);
    }
    Pa_Terminate();
}

bool AudioEngine::init() {
    PaError err = Pa_Initialize();
    if (err != paNoError) {
        qWarning() << "[AudioEngine] Pa_Initialize failed:" << Pa_GetErrorText(err);
        return false;
    }

    PaStreamParameters out{};
    out.device = Pa_GetDefaultOutputDevice();
    if (out.device == paNoDevice) {
        qWarning() << "[AudioEngine] No default output device";
        return false;
    }
    out.channelCount = 2;
    out.sampleFormat = paFloat32;
    out.suggestedLatency =
        Pa_GetDeviceInfo(out.device)->defaultLowOutputLatency;
    out.hostApiSpecificStreamInfo = nullptr;

    err = Pa_OpenStream(&stream_, nullptr, &out,
                        48000,
                        paFramesPerBufferUnspecified,
                        paClipOff,
                        &AudioEngine::paCallback,
                        this);
    if (err != paNoError) {
        qWarning() << "[AudioEngine] Pa_OpenStream failed:" << Pa_GetErrorText(err);
        return false;
    }

    qInfo() << "[AudioEngine] PortAudio initialized, 48kHz stereo";
    return true;
}

void AudioEngine::start(qint64 startUs) {
    if (!stream_ || active_) return;
    staging_.clear();
    stagingPos_ = 0;
    PaError err = Pa_StartStream(stream_);
    if (err != paNoError) {
        qWarning() << "[AudioEngine] Pa_StartStream failed:" << Pa_GetErrorText(err);
        return;
    }
    clock_.start(startUs);
    active_ = true;
    emit activeChanged(active_);
    qInfo() << "[AudioEngine] stream started";
}

void AudioEngine::stop() {
    if (!active_) return;
    Pa_StopStream(stream_);
    clock_.stop();
    active_ = false;
    emit activeChanged(active_);
    qInfo() << "[AudioEngine] stream stopped";
}

int AudioEngine::paCallback(const void* /*input*/, void* output,
                            unsigned long frameCount,
                            const PaStreamCallbackTimeInfo* /*timeInfo*/,
                            PaStreamCallbackFlags /*statusFlags*/,
                            void* userData) {
    auto* self = static_cast<AudioEngine*>(userData);
    auto* out = static_cast<float*>(output);
    const unsigned long total = frameCount * 2;

    // Timeline mixer path: delegate the whole buffer to the mixer, which
    // reads live per-track state and mixes directly into `out`.
    if (self->mixer_) {
        self->mixer_->mix(out, frameCount, self->clock_.positionUs() / 1000, self);
        return paContinue;
    }

    unsigned long written = 0;
    while (written < total) {
        // Refill staging from the next queued frame when exhausted.
        if (self->stagingPos_ >= self->staging_.size()) {
            ghita::engine::Frame f;
            if (!self->queue_ || !self->queue_->try_pop(f)) {
                // No data yet: output silence and keep the clock running.
                for (unsigned long i = written; i < total; ++i) out[i] = 0.0f;
                return paContinue;
            }
            self->staging_.assign(
                reinterpret_cast<const float*>(f.rgba.data()),
                reinterpret_cast<const float*>(f.rgba.data()) + f.rgba.size() / sizeof(float));
            self->stagingPos_ = 0;
        }
        out[written++] = self->staging_[self->stagingPos_++] * self->masterGain_;
    }

    // Advance master clock by the samples we just consumed (frames * 2 ch).
    // (clock_ is wall-based in M0; replacing with sample-count later.)
    return paContinue;
}

// ---- Per-track mixing ----

void AudioEngine::setTrackVolume(int trackIndex, float linearGain) {
    if (trackIndex >= 0 && trackIndex < kMaxTracks)
        trackGain_[trackIndex] = std::clamp(linearGain, 0.0f, 2.0f);
}
float AudioEngine::trackVolume(int trackIndex) const {
    return (trackIndex >= 0 && trackIndex < kMaxTracks) ? trackGain_[trackIndex] : 1.0f;
}
void AudioEngine::setTrackPan(int trackIndex, float pan) {
    if (trackIndex >= 0 && trackIndex < kMaxTracks)
        trackPan_[trackIndex] = std::clamp(pan, -1.0f, 1.0f);
}
float AudioEngine::trackPan(int trackIndex) const {
    return (trackIndex >= 0 && trackIndex < kMaxTracks) ? trackPan_[trackIndex] : 0.0f;
}
void AudioEngine::setTrackMute(int trackIndex, bool muted) {
    if (trackIndex >= 0 && trackIndex < kMaxTracks)
        trackMuted_[trackIndex] = muted;
}
bool AudioEngine::isTrackMuted(int trackIndex) const {
    return (trackIndex >= 0 && trackIndex < kMaxTracks) ? trackMuted_[trackIndex] : false;
}
void AudioEngine::setMasterVolume(float linearGain) {
    masterGain_ = std::clamp(linearGain, 0.0f, 2.0f);
}
float AudioEngine::masterVolume() const { return masterGain_; }

} // namespace ghita::audio
