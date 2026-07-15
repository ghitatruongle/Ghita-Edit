#include "AudioEncoder.h"

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <libavutil/channel_layout.h>
#include <libswresample/swresample.h>
}

#include "fx/AudioDSP.h"

#include <algorithm>
#include <cmath>
#include <QDebug>

namespace ghita::export_ {

AudioEncoder::AudioEncoder(AVFormatContext* outFmt, float gainLinear, int fadeInMs, int fadeOutMs)
    : gain_(gainLinear), fadeInSamples_(fadeInMs * 48), fadeOutSamples_(fadeOutMs * 48) {
    const AVCodec* aCodec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!aCodec) { qWarning() << "[AudioEncoder] No AAC encoder"; return; }

    audioStream_ = avformat_new_stream(outFmt, nullptr);
    aCtx_ = avcodec_alloc_context3(aCodec);
    aCtx_->codec_id = AV_CODEC_ID_AAC;
    aCtx_->codec_type = AVMEDIA_TYPE_AUDIO;
    aCtx_->sample_rate = sr_;
    aCtx_->ch_layout = AV_CHANNEL_LAYOUT_STEREO;
    aCtx_->sample_fmt = AV_SAMPLE_FMT_FLTP;
    aCtx_->bit_rate = 192000;
    aCtx_->time_base = {1, sr_};
    if (outFmt->oformat->flags & AVFMT_GLOBALHEADER)
        aCtx_->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

    if (avcodec_open2(aCtx_, aCodec, nullptr) < 0) {
        qWarning() << "[AudioEncoder] Cannot open audio encoder";
        avcodec_free_context(&aCtx_);
        aCtx_ = nullptr;
        audioStream_ = nullptr;
        return;
    }
    avcodec_parameters_from_context(audioStream_->codecpar, aCtx_);
    audioStream_->time_base = {1, sr_};
    frameSize_ = aCtx_->frame_size;
    // Standard AAC frame size fallback if encoder reports 0.
    if (frameSize_ <= 0) frameSize_ = 1024;
}

AudioEncoder::~AudioEncoder() {
    if (swr_) swr_free(&swr_);
    if (aCtx_) avcodec_free_context(&aCtx_);
}

void AudioEncoder::configureResampler(const AVChannelLayout& inLayout, int inRate, AVSampleFormat inFmt) {
    if (swr_) swr_free(&swr_);
    swr_ = swr_alloc();
    av_opt_set_chlayout(swr_, "in_chlayout", &inLayout, 0);
    av_opt_set_int(swr_, "in_sample_rate", inRate, 0);
    av_opt_set_sample_fmt(swr_, "in_sample_fmt", inFmt, 0);
    AVChannelLayout outLayout = AV_CHANNEL_LAYOUT_STEREO;
    av_opt_set_chlayout(swr_, "out_chlayout", &outLayout, 0);
    av_opt_set_int(swr_, "out_sample_rate", sr_, 0);
    av_opt_set_sample_fmt(swr_, "out_sample_fmt", AV_SAMPLE_FMT_FLTP, 0);
    int swrRet = swr_init(swr_);
    av_channel_layout_uninit(&outLayout);
    if (swrRet < 0) {
        qWarning() << "[AudioEncoder] swr_init failed";
        swr_free(&swr_);
    }
}

float AudioEncoder::scanPeak(AVFrame* decoded) {
    if (!swr_) return 0.0f;
    int outSamples = swr_get_out_samples(swr_, decoded->nb_samples);
    AVFrame* tmp = av_frame_alloc();
    tmp->format = AV_SAMPLE_FMT_FLTP;
    tmp->ch_layout = AV_CHANNEL_LAYOUT_STEREO;
    tmp->sample_rate = sr_;
    tmp->nb_samples = outSamples;
    av_frame_get_buffer(tmp, 0);
    swr_convert(swr_, tmp->data, outSamples,
                (const uint8_t**)decoded->data, decoded->nb_samples);
    float peak = 0.0f;
    for (int c = 0; c < channels_; ++c) {
        float* p = reinterpret_cast<float*>(tmp->data[c]);
        for (int i = 0; i < outSamples; ++i)
            peak = std::max(peak, static_cast<float>(std::fabs(static_cast<double>(p[i]))));
    }
    av_frame_free(&tmp);
    return peak;
}

void AudioEncoder::applyNormalize(float peak) {
    if (peak > 0.0f) {
        float normGain = 0.99f / peak;
        gain_ = std::min(gain_, normGain);
        if (gain_ > 20.0f) gain_ = 20.0f; // cap (~26 dB)
    }
}

void AudioEncoder::beginClip(int64_t clipSamples) {
    clipStartSample_ = aPts_;
    clipSamples_ = clipSamples;
}

void AudioEncoder::encodeBuffered(std::vector<AVPacket*>& out) {
    while (chBuf_[0].size() >= static_cast<size_t>(frameSize_)) {
        int64_t startSample = aPts_;
        AVFrame* encFrame = av_frame_alloc();
        encFrame->format = aCtx_->sample_fmt;
        av_channel_layout_copy(&encFrame->ch_layout, &aCtx_->ch_layout);
        encFrame->sample_rate = aCtx_->sample_rate;
        encFrame->nb_samples = frameSize_;
        av_frame_get_buffer(encFrame, 0);
        for (int c = 0; c < channels_; ++c) {
            float* dst = reinterpret_cast<float*>(encFrame->data[c]);
            const float* src = chBuf_[c].data();
            std::copy(src, src + frameSize_, dst);
        }
        float** planes = reinterpret_cast<float**>(encFrame->data);
        fx::AudioDSP::applyGain(planes, channels_, frameSize_, gain_);
        fx::AudioDSP::applyFade(planes, channels_, frameSize_,
                                startSample - clipStartSample_, clipSamples_,
                                fadeInSamples_, fadeOutSamples_);
        encFrame->pts = aPts_;
        int sret = avcodec_send_frame(aCtx_, encFrame);
        if (sret == AVERROR(EAGAIN)) {
            AVPacket* pkt = av_packet_alloc();
            while (avcodec_receive_packet(aCtx_, pkt) >= 0) {
                pkt->stream_index = audioStream_->index;
                out.push_back(pkt);
                pkt = av_packet_alloc();
            }
            av_packet_free(&pkt);
            avcodec_send_frame(aCtx_, encFrame);
        }
        AVPacket* pkt = av_packet_alloc();
        while (avcodec_receive_packet(aCtx_, pkt) >= 0) {
            pkt->stream_index = audioStream_->index;
            out.push_back(pkt);
            pkt = av_packet_alloc();
        }
        av_packet_free(&pkt);
        av_frame_free(&encFrame);
        aPts_ += frameSize_;
        for (int c = 0; c < channels_; ++c)
            chBuf_[c].erase(chBuf_[c].begin(), chBuf_[c].begin() + frameSize_);
    }
}

void AudioEncoder::feedFrame(AVFrame* decoded, std::vector<AVPacket*>& out) {
    if (!swr_) return;
    int outSamples = swr_get_out_samples(swr_, decoded->nb_samples);
    AVFrame* outFrame = av_frame_alloc();
    outFrame->format = AV_SAMPLE_FMT_FLTP;
    outFrame->ch_layout = AV_CHANNEL_LAYOUT_STEREO;
    outFrame->sample_rate = sr_;
    outFrame->nb_samples = outSamples;
    av_frame_get_buffer(outFrame, 0);
    int converted = swr_convert(swr_, outFrame->data, outSamples,
                                (const uint8_t**)decoded->data, decoded->nb_samples);
    if (converted < 0) converted = 0;
    float** planes = reinterpret_cast<float**>(outFrame->data);
    for (int c = 0; c < channels_; ++c)
        chBuf_[c].insert(chBuf_[c].end(), planes[c], planes[c] + converted);
    av_frame_free(&outFrame);
    encodeBuffered(out);
}

void AudioEncoder::endClip(std::vector<AVPacket*>& out) {
    if (!chBuf_[0].empty()) {
        size_t need = static_cast<size_t>(frameSize_) - chBuf_[0].size();
        for (int c = 0; c < channels_; ++c)
            chBuf_[c].insert(chBuf_[c].end(), need, 0.0f);
        encodeBuffered(out);
    }
}

void AudioEncoder::flush(std::vector<AVPacket*>& out) {
    // Drain any residual buffered samples (padded to a full frame).
    if (!chBuf_[0].empty()) {
        size_t need = static_cast<size_t>(frameSize_) - chBuf_[0].size();
        for (int c = 0; c < channels_; ++c)
            chBuf_[c].insert(chBuf_[c].end(), need, 0.0f);
        encodeBuffered(out);
    }
    // Flush the AAC encoder to retrieve trailing packets.
    avcodec_send_frame(aCtx_, nullptr);
    AVPacket* pkt = av_packet_alloc();
    while (avcodec_receive_packet(aCtx_, pkt) >= 0) {
        pkt->stream_index = audioStream_->index;
        out.push_back(pkt);
        pkt = av_packet_alloc();
    }
    av_packet_free(&pkt);
}

void AudioEncoder::insertSilence(int64_t numSamples, std::vector<AVPacket*>& out) {
    if (numSamples <= 0 || !ok()) return;
    // Feed zero-valued buffers directly, bypassing the resampler.
    int64_t remaining = numSamples;
    while (remaining > 0) {
        int64_t chunk = qMin(remaining, static_cast<int64_t>(frameSize_));
        // Pad chBuf_ with zeros and encode.
        for (int c = 0; c < channels_; ++c)
            chBuf_[c].insert(chBuf_[c].end(), static_cast<size_t>(chunk), 0.0f);
        clipSamples_ += chunk;
        encodeBuffered(out);
        remaining -= chunk;
    }
}

} // namespace ghita::export_
