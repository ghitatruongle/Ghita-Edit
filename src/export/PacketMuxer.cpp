#include "PacketMuxer.h"

extern "C" {
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
}

#include <algorithm>
#include <QDebug>

namespace ghita::export_ {

void PacketMuxer::add(AVPacket* pkt, AVStream* st) {
    AVPacket* copy = av_packet_alloc();
    av_packet_ref(copy, pkt);
    int64_t dts = copy->dts;
    if (dts == AV_NOPTS_VALUE) dts = copy->pts;
    int64_t key = av_rescale_q(dts, st->time_base, AV_TIME_BASE_Q);
    queue_.push_back({copy, key});
}

void PacketMuxer::finalize(AVFormatContext* outFmt) {
    std::sort(queue_.begin(), queue_.end(),
              [](const QueuedPkt& a, const QueuedPkt& b) { return a.dtsKey < b.dtsKey; });
    for (auto& e : queue_) {
        av_interleaved_write_frame(outFmt, e.pkt);
        av_packet_free(&e.pkt);
    }
    queue_.clear();
}

} // namespace ghita::export_
