#pragma once

#include <cstdint>
#include <vector>
#include <atomic>
#include <memory>

namespace ghita::engine {

// A decoded frame. For M0 the video frame carries an RGBA pixel buffer
// produced by the Decoder via sws_scale; later milestones may instead carry
// a GPU texture handle for hardware-decoded frames.
struct Frame {
    int64_t pts = 0;          // presentation timestamp (stream timebase)
    int64_t ptsMs = 0;        // pts converted to milliseconds (for A/V sync)
    int width = 0;
    int height = 0;
    int64_t pictureNumber = 0;
    int streamIndex = -1;     // which stream produced this frame
    std::vector<uint8_t> rgba; // RGBA pixels, row-major, size = w*h*4
};

// Lock-free single-producer / single-consumer ring buffer.
//
// The Decoder (producer, on the engine worker thread) pushes decoded frames;
// the Preview surface / audio callback (consumer) pops them.
//
// Optimization notes for later milestones:
//   - Back with aligned, pre-allocated buffers (SIMD-friendly, 32/64-byte align).
//   - For GPU decode (NVDEC/VAAPI) keep frames as texture handles and avoid
//     the host round-trip; only map when CPU FX is required.
//   - Consider a pool of reusable Frame objects to avoid per-frame allocation.
template <typename T, size_t Capacity>
class RingBuffer {
public:
    static constexpr size_t kCapacity = Capacity;

public:
    bool try_push(T&& item) {
        size_t next = (writePos_.load(std::memory_order_relaxed) + 1) % Capacity;
        if (next == readPos_.load(std::memory_order_acquire))
            return false; // full
        items_[next] = std::move(item);
        writePos_.store(next, std::memory_order_release);
        return true;
    }

    bool try_pop(T& out) {
        size_t read = readPos_.load(std::memory_order_relaxed);
        if (read == writePos_.load(std::memory_order_acquire))
            return false; // empty
        size_t next = (read + 1) % Capacity;
        out = std::move(items_[next]);
        readPos_.store(next, std::memory_order_release);
        return true;
    }

    size_t size() const {
        size_t w = writePos_.load(std::memory_order_acquire);
        size_t r = readPos_.load(std::memory_order_acquire);
        return (w + Capacity - r) % Capacity;
    }

private:
    std::vector<T> items_{Capacity};
    std::atomic<size_t> writePos_{0};
    std::atomic<size_t> readPos_{0};
};

// Frame queues used between Decoder and consumers.
using VideoFrameQueue = RingBuffer<Frame, 4>;
using AudioFrameQueue = RingBuffer<Frame, 16>;

} // namespace ghita::engine
