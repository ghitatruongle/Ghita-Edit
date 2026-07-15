#include "AudioMixerController.h"
#include "AudioEngine.h"
#include <cmath>

namespace ghita::audio {

AudioMixerController::AudioMixerController(AudioEngine* engine, QObject* parent)
    : QObject(parent), engine_(engine) {}

float AudioMixerController::masterVolume() const { return masterGain_; }

QVariantList AudioMixerController::trackStates() const {
    QVariantList list;
    // Expose per-track state so QML bindings re-run on `changed()`.
    // kMaxTracks is private to AudioEngine; use a matching fixed bound (16).
    const int kTrackCount = 16;
    for (int i = 0; i < kTrackCount; ++i) {
        QVariantMap m;
        m["volume"] = engine_->trackVolume(i);
        m["pan"]    = engine_->trackPan(i);
        m["muted"]  = engine_->isTrackMuted(i);
        list.append(m);
    }
    return list;
}

void AudioMixerController::setMasterVolume(float linearGain) {
    masterGain_ = std::clamp(linearGain, 0.0f, 2.0f);
    engine_->setMasterVolume(masterGain_);
    emit changed();
}

void AudioMixerController::setTrackVolume(int trackIndex, float linearGain) {
    engine_->setTrackVolume(trackIndex, linearGain);
    emit changed();
}

float AudioMixerController::trackVolume(int trackIndex) const {
    return engine_->trackVolume(trackIndex);
}

void AudioMixerController::setTrackPan(int trackIndex, float pan) {
    engine_->setTrackPan(trackIndex, pan);
    emit changed();
}

float AudioMixerController::trackPan(int trackIndex) const {
    return engine_->trackPan(trackIndex);
}

void AudioMixerController::setTrackMute(int trackIndex, bool muted) {
    engine_->setTrackMute(trackIndex, muted);
    emit changed();
}

bool AudioMixerController::isTrackMuted(int trackIndex) const {
    return engine_->isTrackMuted(trackIndex);
}

} // namespace ghita::audio
