#include "Decoder.h"

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
}

#include <QDebug>
#include <atomic>

namespace ghita::engine {

// Global network init reference counter: avformat_network_init/deinit are
// process-global and must only be balanced (one init per deinit).  We use an
// atomic counter so that the first Decoder instance initializes the network
// subsystem and the last one to be destroyed tears it down.
namespace {
    std::atomic<int> g_networkRefCount{0};
}

Decoder::Decoder() {
    if (g_networkRefCount.fetch_add(1) == 0) {
        avformat_network_init();
    }
    pkt_ = av_packet_alloc();
    frame_ = av_frame_alloc();
}

Decoder::~Decoder() {
    if (hwDeviceCtx_) av_buffer_unref(&hwDeviceCtx_);
    if (swrCtx_) swr_free(&swrCtx_);
    if (swsCtx_) sws_freeContext(swsCtx_);
    if (videoCtx_) avcodec_free_context(&videoCtx_);
    if (audioCtx_) avcodec_free_context(&audioCtx_);
    if (fmtCtx_)   avformat_close_input(&fmtCtx_);
    if (frame_)    av_frame_free(&frame_);
    if (pkt_)      av_packet_free(&pkt_);
    if (g_networkRefCount.fetch_sub(1) == 1) {
        avformat_network_deinit();
    }
}

bool Decoder::open(std::string path) {
    path_ = std::move(path);
    int ret = avformat_open_input(&fmtCtx_, path_.c_str(), nullptr, nullptr);
    if (ret < 0) {
        qWarning() << "[Decoder] Failed to open" << path_ << "rc=" << ret;
        return false;
    }
    if (avformat_find_stream_info(fmtCtx_, nullptr) < 0) {
        qWarning() << "[Decoder] No stream info for" << path_;
        return false;
    }

    // Pick first video + first audio stream.
    for (unsigned i = 0; i < fmtCtx_->nb_streams; ++i) {
        auto type = fmtCtx_->streams[i]->codecpar->codec_type;
        if (type == AVMEDIA_TYPE_VIDEO && videoStreamIndex_ < 0)
            videoStreamIndex_ = static_cast<int>(i);
        else if (type == AVMEDIA_TYPE_AUDIO && audioStreamIndex_ < 0)
            audioStreamIndex_ = static_cast<int>(i);
    }
    if (videoStreamIndex_ < 0) {
        qWarning() << "[Decoder] No video stream in" << path_;
        return false;
    }

    if (!openStream(videoStreamIndex_, videoCtx_)) return false;
    if (audioStreamIndex_ >= 0)
        openStream(audioStreamIndex_, audioCtx_);

    // Cache video timebase + audio params for PTS and resampling.
    auto* vst = fmtCtx_->streams[videoStreamIndex_];
    videoTimeBaseNum_ = vst->time_base.num;
    videoTimeBaseDen_ = vst->time_base.den;

    if (audioCtx_) {
        audioSampleRate_ = audioCtx_->sample_rate;
        audioChannels_ = audioCtx_->ch_layout.nb_channels;
        // Resampler: decode codec format -> interleaved float, 48k stereo.
        swrCtx_ = swr_alloc();
        av_opt_set_chlayout(swrCtx_, "in_chlayout",
                            &audioCtx_->ch_layout, 0);
        av_opt_set_int(swrCtx_, "in_sample_rate",
                       audioCtx_->sample_rate, 0);
        av_opt_set_sample_fmt(swrCtx_, "in_sample_fmt",
                              audioCtx_->sample_fmt, 0);
        AVChannelLayout outLayout;
        av_channel_layout_default(&outLayout, 2);
        av_opt_set_chlayout(swrCtx_, "out_chlayout", &outLayout, 0);
        av_opt_set_int(swrCtx_, "out_sample_rate", 48000, 0);
        av_opt_set_sample_fmt(swrCtx_, "out_sample_fmt",
                              AV_SAMPLE_FMT_FLT, 0);
        if (swr_init(swrCtx_) < 0) {
            qWarning() << "[Decoder] swr_init failed";
            swr_free(&swrCtx_);
        }
        av_channel_layout_uninit(&outLayout);
    }

    // Try to initialize hardware acceleration.
    hwBackend_ = selectBackend();
    if (hwBackend_ != HWBackend::None) {
        if (!initHardwareDecode()) {
            qWarning() << "[Decoder] HW decode init failed, falling back to software";
            hwBackend_ = HWBackend::None;
            hwInitFailed_ = true;
        } else {
            qInfo() << "[Decoder] Hardware decode initialized:"
                    << QString::fromUtf8(to_string(hwBackend_).data());
        }
    }

    qInfo() << "[Decoder] Opened" << path_
            << "video=" << videoCtx_->width << "x" << videoCtx_->height
            << "audio=" << audioSampleRate_ << "Hz/" << audioChannels_
            << "backend=" << QString::fromUtf8(
                   to_string(hwBackend_).data(),
                   static_cast<int>(to_string(hwBackend_).size()));
    return true;
}

// ---------------------------------------------------------------------------
// Hardware decode initialization (NVDEC on Windows, VA-API on Linux)
// ---------------------------------------------------------------------------

bool Decoder::initHardwareDecode() {
    if (!fmtCtx_ || !videoCtx_) return false;

    // Determine which AVHWDeviceType to use.
    enum AVHWDeviceType devType = AV_HWDEVICE_TYPE_NONE;
    switch (hwBackend_) {
        case HWBackend::NVDEC:
#ifdef GHITA_HW_NVDEC
            devType = av_hwdevice_find_type_by_name("cuda");
            if (devType != AV_HWDEVICE_TYPE_NONE) break;
            devType = av_hwdevice_find_type_by_name("d3d11va");
#endif
            break;
        case HWBackend::QuickSync:
#ifdef GHITA_HW_QUICKSYNC
            devType = av_hwdevice_find_type_by_name("qsv");
#endif
            break;
        case HWBackend::AMF:
#ifdef GHITA_HW_AMF
            devType = av_hwdevice_find_type_by_name("videotoolbox");
#endif
            break;
        case HWBackend::VAAPI:
#ifdef GHITA_HW_VAAPI
            devType = av_hwdevice_find_type_by_name("vaapi");
#endif
            break;
        default:
            break;
    }

    if (devType == AV_HWDEVICE_TYPE_NONE) {
        qWarning() << "[Decoder] No HW device type found for backend"
                   << QString::fromUtf8(to_string(hwBackend_).data());
        return false;
    }

    // Create the hardware device context.
    if (av_hwdevice_ctx_create(&hwDeviceCtx_, devType, nullptr, nullptr, 0) < 0) {
        qWarning() << "[Decoder] Failed to create HW device context";
        return false;
    }

    // Re-open the video codec with the hardware device context.
    const AVCodec* codec = avcodec_find_decoder(videoCtx_->codec_id);
    if (!codec) {
        qWarning() << "[Decoder] Cannot re-find decoder for HW";
        return false;
    }

    // Allocate a new codec context for hardware decoding.
    AVCodecContext* hwCtx = avcodec_alloc_context3(codec);
    if (!hwCtx) {
        qWarning() << "[Decoder] Cannot alloc HW codec context";
        return false;
    }

    // Copy parameters from the original context.
    hwCtx->width = videoCtx_->width;
    hwCtx->height = videoCtx_->height;
    hwCtx->pix_fmt = videoCtx_->sw_pix_fmt;
    hwCtx->time_base = videoCtx_->time_base;
    hwCtx->framerate = videoCtx_->framerate;
    hwCtx->hw_frames_ctx = av_buffer_ref(videoCtx_->hw_frames_ctx);
    hwCtx->extradata = videoCtx_->extradata;
    hwCtx->extradata_size = videoCtx_->extradata_size;

    // Set the hardware device context.
    hwCtx->hw_device_ctx = av_buffer_ref(hwDeviceCtx_);

    // Tell the decoder to produce hardware frames.
    hwCtx->pix_fmt = devType == AV_HWDEVICE_TYPE_CUDA ? AV_PIX_FMT_CUDA :
                     devType == AV_HWDEVICE_TYPE_VAAPI ? AV_PIX_FMT_VAAPI :
                     AV_PIX_FMT_NV12;

    if (avcodec_open2(hwCtx, codec, nullptr) < 0) {
        qWarning() << "[Decoder] Cannot open codec for HW decode";
        avcodec_free_context(&hwCtx);
        return false;
    }

    // Replace the software codec context with the hardware one.
    avcodec_free_context(&videoCtx_);
    videoCtx_ = hwCtx;

    return true;
}

bool Decoder::tryHardwareDecode(AVFrame* frame, VideoFrameQueue& videoQ) {
    // Only attempt if we have a hardware device context and the frame
    // is in a hardware pixel format.
    if (!hwDeviceCtx_ || !videoCtx_) return false;

    // Check if the frame came from hardware.
    if (!av_buffer_is_available(&frame->hw_frames_ctx)) return false;

    // Map the hardware frame to a software format (NV12 -> RGBA).
    AVFrame* swFrame = av_frame_alloc();
    if (!swFrame) return false;

    int ret = av_hwframe_transfer_data(swFrame, frame, 0);
    if (ret < 0) {
        // Transfer failed -- fall back to software decode path.
        av_frame_free(&swFrame);
        return false;
    }

    // Build the output frame.
    Frame out;
    out.width = swFrame->width;
    out.height = swFrame->height;
    out.streamIndex = videoStreamIndex_;
    out.pts = swFrame->pts;
    out.ptsMs = static_cast<int64_t>(
        swFrame->pts * 1000.0 * videoTimeBaseNum_ / videoTimeBaseDen_);
    out.pictureNumber = pictureCounter_++;

    // Upload to RGBA via sws_scale.
    out.rgba.resize(static_cast<size_t>(out.width) * out.height * 4);
    uint8_t* dst[] = { out.rgba.data() };
    int dstStride[] = { out.width * 4 };

    if (!swsCtx_ || swsCtx_->srcW != swFrame->width
                   || swsCtx_->srcH != swFrame->height
                   || swsCtx_->srcFormat != AVPixelFormat(swFrame->format)) {
        sws_freeContext(swsCtx_);
        swsCtx_ = sws_getContext(
            swFrame->width, swFrame->height, AVPixelFormat(swFrame->format),
            swFrame->width, swFrame->height, AV_PIX_FMT_RGBA,
            SWS_BILINEAR, nullptr, nullptr, nullptr);
    }

    sws_scale(swsCtx_, swFrame->data, swFrame->linesize, 0,
              swFrame->height, dst, dstStride);

    av_frame_free(&swFrame);

    return videoQ.try_push(std::move(out));
}

bool Decoder::openStream(int index, AVCodecContext*& ctx) {
    auto* par = fmtCtx_->streams[index]->codecpar;
    const AVCodec* codec = avcodec_find_decoder(par->codec_id);
    if (!codec) {
        qWarning() << "[Decoder] Unsupported codec id" << par->codec_id;
        return false;
    }
    ctx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(ctx, par);
    if (avcodec_open2(ctx, codec, nullptr) < 0) {
        qWarning() << "[Decoder] Cannot open codec";
        avcodec_free_context(&ctx);
        return false;
    }
    return true;
}

HWBackend Decoder::selectBackend() const {
#if defined(GHITA_HW_ACCEL_ENABLED)
    // Hardware acceleration is enabled at compile time.
    // Choose the best backend for the current platform.
#if defined(_WIN32)
    return HWBackend::NVDEC;
#elif defined(__linux__)
    return HWBackend::VAAPI;
#else
    return HWBackend::None;
#endif
#else
    // Hardware acceleration is disabled -- always use software.
    return HWBackend::None;
#endif
}

double Decoder::videoFps() const {
    if (videoStreamIndex_ < 0) return 0.0;
    auto* st = fmtCtx_->streams[videoStreamIndex_];
    if (st->avg_frame_rate.num && st->avg_frame_rate.den)
        return av_q2d(st->avg_frame_rate);
    return 0.0;
}

int64_t Decoder::durationMs() const {
    if (!fmtCtx_) return 0;
    if (fmtCtx_->duration != AV_NOPTS_VALUE)
        return fmtCtx_->duration / (AV_TIME_BASE / 1000);
    // Fallback: use stream duration if container doesn't report one.
    if (videoStreamIndex_ >= 0) {
        auto* st = fmtCtx_->streams[videoStreamIndex_];
        if (st->duration != AV_NOPTS_VALUE)
            return static_cast<int64_t>(
                st->duration * av_q2d(st->time_base) * 1000.0);
    }
    return 0;
}

bool Decoder::seek(int64_t targetMs) {
    if (!fmtCtx_) return false;

    // Convert milliseconds to AV_TIME_BASE units.
    int64_t target = (targetMs * AV_TIME_BASE) / 1000;

    int ret = av_seek_frame(fmtCtx_, -1, target, AVSEEK_FLAG_BACKWARD);
    if (ret < 0) {
        qWarning() << "[Decoder] seek failed, rc=" << ret;
        return false;
    }

    // Flush codec buffers so stale frames aren't returned.
    if (videoCtx_) avcodec_flush_buffers(videoCtx_);
    if (audioCtx_) avcodec_flush_buffers(audioCtx_);

    eof_ = false;
    qInfo() << "[Decoder] seeked to" << targetMs << "ms";
    return true;
}

bool Decoder::decodeStep(VideoFrameQueue& videoQ, AudioFrameQueue& audioQ) {
    if (eof_) return false;

    while (av_read_frame(fmtCtx_, pkt_) >= 0) {
        int stream = pkt_->stream_index;
        AVCodecContext* ctx =
            (stream == videoStreamIndex_) ? videoCtx_ :
            (stream == audioStreamIndex_) ? audioCtx_ : nullptr;
        if (!ctx) { av_packet_unref(pkt_); continue; }

        if (avcodec_send_packet(ctx, pkt_) < 0) {
            av_packet_unref(pkt_);
            continue;
        }
        av_packet_unref(pkt_);

        while (avcodec_receive_frame(ctx, frame_) >= 0) {
            if (stream == videoStreamIndex_) {
                if (decodeVideoFrame(frame_, videoQ)) {
                    return true; // produced one video frame
                }
            } else if (stream == audioStreamIndex_) {
                decodeAudioFrame(frame_, audioQ);
            }
        }
        return true; // consumed one packet
    }

    eof_ = true;
    return false;
}

bool Decoder::decodeVideoFrame(AVFrame* frame, VideoFrameQueue& videoQ) {
    // If hardware decode is active, attempt to use it first.
    if (hwBackend_ != HWBackend::None && !hwInitFailed_) {
        if (tryHardwareDecode(frame, videoQ)) {
            return true;
        }
        // tryHardwareDecode returned false -- fall through to software path.
        qWarning() << "[Decoder] HW decode transfer failed, falling back to SW";
        hwInitFailed_ = true;
        hwBackend_ = HWBackend::None;
    }

    // Software decode path: convert decoded frame to RGBA.
    // Recreate swsCtx_ if dimensions or pixel format changed.
    if (!swsCtx_ || swsCtx_->srcW != frame->width
                   || swsCtx_->srcH != frame->height
                   || swsCtx_->srcFormat != AVPixelFormat(frame->format)) {
        sws_freeContext(swsCtx_);
        swsCtx_ = sws_getContext(
            frame->width, frame->height, AVPixelFormat(frame->format),
            frame->width, frame->height, AV_PIX_FMT_RGBA,
            SWS_BILINEAR, nullptr, nullptr, nullptr);
    }
    Frame out;
    out.width = frame->width;
    out.height = frame->height;
    out.streamIndex = videoStreamIndex_;
    out.pts = frame->pts;
    out.ptsMs = static_cast<int64_t>(
        frame->pts * 1000.0 * videoTimeBaseNum_ / videoTimeBaseDen_);
    out.pictureNumber = pictureCounter_++;

    out.rgba.resize(static_cast<size_t>(out.width) * out.height * 4);
    uint8_t* dst[] = { out.rgba.data() };
    int dstStride[] = { out.width * 4 };
    sws_scale(swsCtx_, frame->data, frame->linesize, 0,
              frame->height, dst, dstStride);

    return videoQ.try_push(std::move(out));
}

bool Decoder::decodeAudioFrame(AVFrame* frame, AudioFrameQueue& audioQ) {
    if (!swrCtx_) return false;

    // Convert decoded frame to interleaved float, 48k, stereo.
    const int outRate = 48000;
    int outSamples = swr_get_out_samples(swrCtx_, frame->nb_samples);
    if (outSamples <= 0) return false;

    Frame out;
    out.streamIndex = audioStreamIndex_;
    out.pts = frame->pts;
    out.ptsMs = static_cast<int64_t>(
        frame->pts * 1000.0 / audioCtx_->sample_rate);
    out.width = outSamples;        // reuse fields: samples count
    out.height = 2;                // channels
    out.rgba.resize(static_cast<size_t>(outSamples) * 2 * sizeof(float));

    float* outBuf = reinterpret_cast<float*>(out.rgba.data());
    uint8_t* outPtr[] = { reinterpret_cast<uint8_t*>(outBuf) };
    int converted = swr_convert(swrCtx_, outPtr, outSamples,
                                const_cast<const uint8_t**>(frame->data),
                                frame->nb_samples);
    if (converted <= 0) return false;

    // Trim buffer to actual converted samples.
    out.rgba.resize(static_cast<size_t>(converted) * 2 * sizeof(float));
    return audioQ.try_push(std::move(out));
}

} // namespace ghita::engine
