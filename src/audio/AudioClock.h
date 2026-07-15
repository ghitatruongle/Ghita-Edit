#pragma once

#include <cstdint>
#include <chrono>

namespace ghita::audio {

// Master clock for A/V synchronization.
//
// STUB: audio is the master clock in Ghita Edit (low jitter, hardware-paced).
// The clock exposes the current playback position in microseconds; the video
// renderer aligns frames to it. API is defined but not yet driven by PortAudio.
class AudioClock {
public:
    void start() { start_ = now(); running_ = true; }
    void stop()  { running_ = false; }

    // Current playback position in microseconds since start().
    int64_t positionUs() const {
        if (!running_) return 0;
        return std::chrono::duration_cast<std::chrono::microseconds>(
                   now() - start_).count();
    }

    // TODO(M1): advance the clock from the PortAudio callback using the
    // number of frames consumed, not wall-clock, to avoid drift.

private:
    static std::chrono::steady_clock::time_point now() {
        return std::chrono::steady_clock::now();
    }
    std::chrono::steady_clock::time_point start_{};
    bool running_ = false;
};

} // namespace ghita::audio
