#include "TimelineAudioMixer.h"

#include "../timeline/TimelineModel.h"
#include "../timeline/Clip.h"
#include "../engine/Decoder.h"
#include "AudioEngine.h"

#include <algorithm>
#include <cmath>

namespace ghita::audio {

bool TimelineAudioMixer::prepare(const ghita::timeline::TimelineModel* timeline) {
    reset();
    if (!timeline) return false;

    for (const auto& clip : timeline->allClips()) {
        if (clip.kind != ghita::timeline::ClipKind::Audio) continue;

        ghita::engine::Decoder d;
        if (!d.open(clip.sourcePath.toStdString())) continue;

        // Seek to the clip's source-in point so decoding starts at the right offset.
        d.seek(clip.srcInMs);

        ghita::engine::VideoFrameQueue vq;
        ghita::engine::AudioFrameQueue aq;

        // Pre-allocate buffer: 48 kHz * 2 ch * 4 bytes/sample * estimated duration.
        int64_t estSamples = static_cast<int64_t>(clip.srcDurationMs() / 1000.0 * 48000.0);
        QVector<float> clipBuf;
        clipBuf.reserve(static_cast<int>(estSamples * 2));

        int64_t srcOutMs = clip.srcOutMs;  // 0 = decode to EOF
        while (d.decodeStep(vq, aq)) {
            ghita::engine::Frame f;
            while (aq.try_pop(f)) {
                const float* p = reinterpret_cast<const float*>(f.rgba.data());
                int n = static_cast<int>(f.rgba.size() / (2 * sizeof(float)));
                for (int s = 0; s < n; ++s) {
                    clipBuf.append(p[s * 2]);
                    clipBuf.append(p[s * 2 + 1]);
                }
                // Early stop: once we've crossed the clip's source-out boundary.
                if (srcOutMs > 0 && f.ptsMs >= srcOutMs) goto done_decode;
            }
        }
    done_decode:

        clips_.append(ClipAudio{
            clip.id,
            clip.trackIndex,
            clip.timelineStartMs,
            clip.timelineEndMs,
            clip.srcInMs,
            clip.playbackSpeed,
            std::move(clipBuf),
        });
    }

    return !clips_.isEmpty();
}

void TimelineAudioMixer::reset() {
    clips_.clear();
}

void TimelineAudioMixer::mix(float* out, unsigned long frameCount,
                              qint64 startMs, const AudioEngine* audio) {
    const double msPerSample = 1000.0 / 48000.0;

    // Snapshot per-track state at the start of the callback to avoid data races
    // with the Qt event thread (slider writes happen on the UI thread while
    // PortAudio reads on the audio thread).
    float masterGain = 1.0f;
    QVector<float> gains;
    QVector<float> pans;
    QVector<bool>  muted;
    if (audio) {
        masterGain = audio->masterVolume();
        const int kMaxTracks = 16;
        gains.reserve(kMaxTracks);
        pans.reserve(kMaxTracks);
        muted.reserve(kMaxTracks);
        for (int i = 0; i < kMaxTracks; ++i) {
            gains.append(audio->trackVolume(i));
            pans.append(audio->trackPan(i));
            muted.append(audio->isTrackMuted(i));
        }
    }

    for (unsigned long i = 0; i < frameCount; ++i) {
        qint64 tMs = startMs + static_cast<qint64>(i * msPerSample);
        float L = 0.0f, R = 0.0f;

        for (const auto& c : clips_) {
            if (tMs < c.timelineStartMs || tMs >= c.timelineEndMs) continue;
            if (c.trackIndex >= 0 && c.trackIndex < muted.size() && muted[c.trackIndex]) continue;

            const double speed = c.playbackSpeed > 0.0 ? c.playbackSpeed : 1.0;
            qint64 srcOffsetMs = c.srcInMs + static_cast<qint64>((tMs - c.timelineStartMs) * speed);
            int64_t sampleIdx = static_cast<int64_t>(srcOffsetMs / msPerSample);
            if (sampleIdx < 0) continue;
            if (sampleIdx * 2 + 1 >= static_cast<int64_t>(c.pcm.size())) continue;

            float sL = c.pcm[sampleIdx * 2];
            float sR = c.pcm[sampleIdx * 2 + 1];

            float gain = (c.trackIndex >= 0 && c.trackIndex < gains.size())
                         ? gains[c.trackIndex] : 1.0f;
            float pan  = (c.trackIndex >= 0 && c.trackIndex < pans.size())
                         ? pans[c.trackIndex] : 0.0f;

            // Equal-power-ish pan: attenuate the opposite channel slightly.
            float leftFactor  = (pan <= 0.0f) ? 1.0f : 1.0f - pan * 0.5f;
            float rightFactor = (pan >= 0.0f) ? 1.0f : 1.0f + pan * 0.5f;

            L += sL * gain * leftFactor;
            R += sR * gain * rightFactor;
        }

        out[i * 2]     = std::clamp(L * masterGain, -1.0f, 1.0f);
        out[i * 2 + 1] = std::clamp(R * masterGain, -1.0f, 1.0f);
    }
}

} // namespace ghita::audio
