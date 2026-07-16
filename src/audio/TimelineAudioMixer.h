#pragma once

#include <QString>
#include <cstdint>
#include <QVector>

namespace ghita::timeline { class TimelineModel; }
namespace ghita::audio { class AudioEngine; }

namespace ghita::audio {

// Mixes the timeline's audio clips into a single 48kHz stereo float stream.
// Each clip's PCM is decoded once (prepare()) into memory; mix() samples from
// those buffers at the playhead and applies per-track gain/pan/mute + master.
class TimelineAudioMixer {
public:
    // Decode PCM for every audio clip in the timeline. Returns true if at
    // least one audio clip was prepared (caller should use the mixer).
    bool prepare(const ghita::timeline::TimelineModel* timeline);

    // Free all decoded buffers.
    void reset();

    // Fill `out` (interleaved float L,R, `frameCount` frames) for the playhead
    // starting at `startMs`. Reads live per-track state from `audio` so slider
    // changes take effect immediately. Multiplies by master gain internally.
    void mix(float* out, unsigned long frameCount, qint64 startMs,
              const ghita::audio::AudioEngine* audio);

    bool hasClips() const { return !clips_.isEmpty(); }

private:
    struct ClipAudio {
        int64_t clipId = 0;
        int trackIndex = 0;
        int64_t timelineStartMs = 0;
        int64_t timelineEndMs = 0;
        int64_t srcInMs = 0;
        double playbackSpeed = 1.0;
        QVector<float> pcm; // interleaved 48k stereo float
    };
    QVector<ClipAudio> clips_;
};

} // namespace ghita::audio
