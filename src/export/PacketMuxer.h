#pragma once

#include <vector>
#include <cstdint>

struct AVFormatContext;
struct AVStream;
struct AVPacket;

namespace ghita::export_ {

struct QueuedPkt {
    AVPacket* pkt;
    int64_t dtsKey;
};

// Queues encoded packets and writes them interleaved by dts. Writing all video
// then all audio directly makes av_interleaved_write_frame drop "late" packets,
// truncating the output — so we sort by dts here.
class PacketMuxer {
public:
    // Copy pkt, attach to st, queue keyed by dts (in AV_TIME_BASE units).
    void add(AVPacket* pkt, AVStream* st);
    // Sort by dts and write interleaved to outFmt, freeing every packet.
    void finalize(AVFormatContext* outFmt);

private:
    std::vector<QueuedPkt> queue_;
};

} // namespace ghita::export_
