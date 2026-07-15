#include "VideoEncoder.h"
#include "ExportProfile.h"

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
}

#include <QDebug>

namespace ghita::export_ {

VideoEncoder::VideoEncoder(AVFormatContext* outFmt, const ExportProfile& profile, int crf) {
    // Prefer the libx264 software encoder (most portable, supports yuv420p).
    const AVCodec* vCodec = avcodec_find_encoder_by_name("libx264");
    if (!vCodec) {
        vCodec = avcodec_find_encoder(AV_CODEC_ID_H264);
    }
    if (!vCodec) { qWarning() << "[VideoEncoder] No H264 encoder"; return; }

    videoStream_ = avformat_new_stream(outFmt, nullptr);
    vCtx_ = avcodec_alloc_context3(vCodec);
    vCtx_->codec_id = AV_CODEC_ID_H264;
    vCtx_->codec_type = AVMEDIA_TYPE_VIDEO;
    vCtx_->width = profile.outW;
    vCtx_->height = profile.outH;
    vCtx_->pix_fmt = AV_PIX_FMT_YUV420P;
    vCtx_->time_base = {1, 30000};
    vCtx_->framerate = profile.outFps;
    vCtx_->gop_size = 15;
    vCtx_->max_b_frames = 3;
    vCtx_->sample_aspect_ratio = profile.outSar;
    av_opt_set(vCtx_->priv_data, "preset", "medium", 0);
    av_opt_set_int(vCtx_->priv_data, "crf", crf, 0);
    if (outFmt->oformat->flags & AVFMT_GLOBALHEADER)
        vCtx_->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

    if (avcodec_open2(vCtx_, vCodec, nullptr) < 0) {
        qWarning() << "[VideoEncoder] Cannot open video encoder";
        avcodec_free_context(&vCtx_);
        vCtx_ = nullptr;
        videoStream_ = nullptr;
        return;
    }
    avcodec_parameters_from_context(videoStream_->codecpar, vCtx_);
    videoStream_->time_base = {1, 30000};
}

VideoEncoder::~VideoEncoder() {
    if (vCtx_) avcodec_free_context(&vCtx_);
}

void VideoEncoder::encodeFrame(AVFrame* frame, std::vector<AVPacket*>& out) {
    if (!vCtx_) return;
    avcodec_send_frame(vCtx_, frame);
    AVPacket* pkt = av_packet_alloc();
    while (avcodec_receive_packet(vCtx_, pkt) >= 0) {
        pkt->stream_index = videoStream_->index;
        out.push_back(pkt);
        pkt = av_packet_alloc();
    }
    av_packet_free(&pkt);
}

void VideoEncoder::flush(std::vector<AVPacket*>& out) {
    if (!vCtx_) return;
    avcodec_send_frame(vCtx_, nullptr);
    AVPacket* pkt = av_packet_alloc();
    while (avcodec_receive_packet(vCtx_, pkt) >= 0) {
        pkt->stream_index = videoStream_->index;
        out.push_back(pkt);
        pkt = av_packet_alloc();
    }
    av_packet_free(&pkt);
}

} // namespace ghita::export_
