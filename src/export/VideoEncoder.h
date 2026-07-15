#pragma once

#include <vector>

struct AVCodecContext;
struct AVFormatContext;
struct AVFrame;
struct AVPacket;
struct AVStream;

namespace ghita::export_ {

struct ExportProfile;

// Owns the H264 (libx264) encoder context + output stream. The caller sets
// frame->pts (presentation order) before encodeFrame(); this unit only encodes.
class VideoEncoder {
public:
    VideoEncoder(AVFormatContext* outFmt, const ExportProfile& profile, int crf);
    ~VideoEncoder();

    bool ok() const { return vCtx_ != nullptr; }
    AVStream* stream() const { return videoStream_; }

    // Encode one frame; appends owned packets to `out` (caller frees with av_packet_free).
    void encodeFrame(AVFrame* frame, std::vector<AVPacket*>& out);
    void flush(std::vector<AVPacket*>& out);

private:
    AVCodecContext* vCtx_ = nullptr;
    AVStream* videoStream_ = nullptr;
};

} // namespace ghita::export_
