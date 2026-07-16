#include "Exporter.h"

#include <QUrl>
#include <QImage>
#include <cstring>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>
#include <libavutil/channel_layout.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
}

#include "fx/VideoFX.h"
#include "fx/VideoFXEffects.h"
#include "fx/AudioDSP.h"
#include "fx/FxController.h"
#include "export/ExportProfile.h"
#include "export/VideoEncoder.h"
#include "export/AudioEncoder.h"
#include "export/PacketMuxer.h"
#include "export/Compositor.h"
#include "timeline/TimelineModel.h"

#include "timeline/Transition.h"

#include <QDebug>
#include <QtConcurrent>
#include <algorithm>
#include <cmath>
#include <vector>

namespace ghita::export_ {

using ghita::timeline::TimelineModel;
using ghita::timeline::Clip;
using ghita::timeline::Transition;

Exporter::Exporter(QObject* parent) : QObject(parent) {}

void Exporter::setFxController(fx::FxController* fx) { fx_ = fx; }

QString Exporter::urlToLocalPath(const QString& url) {
    return QUrl(url).toLocalFile();
}

bool Exporter::exportProject(TimelineModel* model, const QString& outputPath) {
    return runExport(model, outputPath);
}

void Exporter::exportAsync(TimelineModel* model, const QString& outputPath) {
    exportFuture_ = QtConcurrent::run([this, model, outputPath]() {
        bool ok = runExport(model, outputPath);
        emit exportFinished(ok);
    });
}

void Exporter::setTargetSize(int w, int h) {
    targetW_ = w;
    targetH_ = h;
}

struct ClipInfo {
    QString sourcePath;
    qint64 srcInMs;
    qint64 srcOutMs;
    qint64 timelineStartMs;
    qint64 timelineEndMs;
    int trackIndex;
    qint64 clipId;
    double playbackSpeed = 1.0;
    bool pitchCorrection = true;
};

static void collectClips(TimelineModel* model, std::vector<ClipInfo>& video,
                         std::vector<ClipInfo>& audio) {
    for (int i = 0; i < model->rowCount(); ++i) {
        auto idx = model->index(i, 0);
        ClipInfo ci;
        ci.sourcePath = model->data(idx, TimelineModel::SourcePathRole).toString();
        ci.srcInMs  = model->data(idx, TimelineModel::SrcInRole).toLongLong();
        ci.srcOutMs = model->data(idx, TimelineModel::SrcOutRole).toLongLong();
        ci.timelineStartMs = model->data(idx, TimelineModel::TimelineStartRole).toLongLong();
        ci.timelineEndMs  = model->data(idx, TimelineModel::TimelineEndRole).toLongLong();
        ci.trackIndex = model->data(idx, TimelineModel::TrackIndexRole).toInt();
        ci.clipId = model->data(idx, TimelineModel::IdRole).toLongLong();
        ci.playbackSpeed = model->data(idx, TimelineModel::PlaybackSpeedRole).toDouble();
        ci.pitchCorrection = model->data(idx, TimelineModel::PitchCorrectionRole).toBool();
        // Only Video clips are decoded as the base layer; Audio handled separately.
        if (ci.playbackSpeed <= 0) ci.playbackSpeed = 1.0;
        const int kind = model->data(idx, TimelineModel::KindRole).toInt();
        if (kind == 0) video.push_back(ci);
        else if (kind == 1) audio.push_back(ci);
    }
    auto byStart = [](const ClipInfo& a, const ClipInfo& b) {
        return a.timelineStartMs < b.timelineStartMs;
    };
    std::sort(video.begin(), video.end(), byStart);
    std::sort(audio.begin(), audio.end(), byStart);
}

static ExportProfile probeProfile(const std::vector<ClipInfo>& videoClips) {
    ExportProfile p;
    if (videoClips.empty()) return p;
    const auto& c = videoClips.front();
    AVFormatContext* probe = nullptr;
    if (avformat_open_input(&probe, c.sourcePath.toUtf8().constData(), nullptr, nullptr) == 0) {
        avformat_find_stream_info(probe, nullptr);
        for (unsigned i = 0; i < probe->nb_streams; ++i) {
            if (probe->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                p.outW = probe->streams[i]->codecpar->width;
                p.outH = probe->streams[i]->codecpar->height;
                p.outSar = probe->streams[i]->sample_aspect_ratio;
                if (p.outSar.num <= 0 || p.outSar.den <= 0) p.outSar = {1, 1};
                AVRational fr = probe->streams[i]->avg_frame_rate;
                if (fr.num > 0 && fr.den > 0) p.outFps = fr;
                break;
            }
        }
        avformat_close_input(&probe);
    }
    if (p.outW == 0 || p.outH == 0) { p.outW = 1280; p.outH = 720; }
    return p;
}

// Per-clip decoder that yields scaled YUV420P frames on demand (used by the
// time-driven export loop to pull the exact frame at a timeline position,
// including transition partners).
struct ClipSrc {
    ClipInfo ci;
    int outW, outH;
    AVFormatContext* fmt = nullptr;
    AVCodecContext* dec = nullptr;
    int vIdx = -1;
    AVRational inTb{1, 1};
    SwsContext* sws = nullptr;
    AVFrame* frame = nullptr;

    ClipSrc(const ClipInfo& c, int w, int h) : ci(c), outW(w), outH(h) { open(); }
    ~ClipSrc() { close(); }

    bool open() {
        fmt = avformat_alloc_context();
        if (avformat_open_input(&fmt, ci.sourcePath.toUtf8().constData(), nullptr, nullptr) != 0)
            return false;
        avformat_find_stream_info(fmt, nullptr);
        for (unsigned i = 0; i < fmt->nb_streams; ++i) {
            if (fmt->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                vIdx = (int)i;
                inTb = fmt->streams[i]->time_base;
                const AVCodec* codec = avcodec_find_decoder(fmt->streams[i]->codecpar->codec_id);
                if (!codec) return false;
                dec = avcodec_alloc_context3(codec);
                avcodec_parameters_to_context(dec, fmt->streams[i]->codecpar);
                if (avcodec_open2(dec, codec, nullptr) < 0) return false;
                break;
            }
        }
        if (vIdx < 0) return false;
        sws = sws_getContext(dec->width, dec->height, dec->pix_fmt,
                             outW, outH, AV_PIX_FMT_YUV420P, SWS_BILINEAR, nullptr, nullptr, nullptr);
        if (!sws) return false;
        frame = av_frame_alloc();
        return true;
    }

    // Returns a newly allocated scaled YUV420P frame at the given local time
    // (ms relative to the clip's timeline start), scaled by playback speed.
    // When speed > 1.0, the source region is traversed faster (less source time
    // per timeline ms), so the target source time is: srcInMs + localMs * speed.
    AVFrame* frameAt(qint64 localMs, double speed = 1.0) {
        if (!dec) return nullptr;
        const qint64 target = ci.srcInMs + static_cast<qint64>(localMs * speed);
        const int64_t seekTs = av_rescale_q(target, AVRational{1, 1000}, inTb);
        av_seek_frame(fmt, vIdx, seekTs, AVSEEK_FLAG_BACKWARD);
        avcodec_flush_buffers(dec);
        AVPacket* pkt = av_packet_alloc();
        AVFrame* out = av_frame_alloc();
        out->format = AV_PIX_FMT_YUV420P;
        out->width = outW;
        out->height = outH;
        av_frame_get_buffer(out, 0);
        bool got = false;
        AVRational msTb{1, 1000};
        while (av_read_frame(fmt, pkt) >= 0) {
            if (pkt->stream_index != vIdx) { av_packet_unref(pkt); continue; }
            avcodec_send_packet(dec, pkt);
            while (avcodec_receive_frame(dec, frame) >= 0) {
                int64_t ts = frame->pts;
                if (ts != AV_NOPTS_VALUE) {
                    int64_t fms = av_rescale_q(ts, inTb, msTb);
                    if (fms < target) { av_frame_unref(frame); continue; }
                }
                sws_scale(sws, frame->data, frame->linesize, 0, frame->height,
                          out->data, out->linesize);
                av_frame_unref(frame);
                got = true;
                break;
            }
            av_packet_unref(pkt);
            if (got) break;
        }
        av_packet_free(&pkt);
        if (!got) { av_frame_free(&out); return nullptr; }
        return out;
    }

    void close() {
        if (frame) { av_frame_free(&frame); frame = nullptr; }
        if (sws) { sws_freeContext(sws); sws = nullptr; }
        if (dec) { avcodec_free_context(&dec); dec = nullptr; }
        if (fmt) { avformat_close_input(&fmt); fmt = nullptr; }
    }
};

static void blendYuv(AVFrame* dst, const AVFrame* src, double alpha) {
    if (!dst || !src) return;
    const double a = std::max(0.0, std::min(1.0, alpha));
    const int W = dst->width, H = dst->height;
    for (int p = 0; p < 3; ++p) {
        const int w = (p == 0) ? W : W / 2;
        const int h = (p == 0) ? H : H / 2;
        for (int y = 0; y < h; ++y) {
            uint8_t* d = dst->data[p] + y * dst->linesize[p];
            const uint8_t* s = src->data[p] + y * src->linesize[p];
            for (int x = 0; x < w; ++x)
                d[x] = static_cast<uint8_t>((1.0 - a) * d[x] + a * s[x] + 0.5);
        }
    }
}

bool Exporter::runExport(TimelineModel* model, const QString& outputPath) {
    if (!model) return false;

    std::vector<ClipInfo> videoClips, audioClips;
    collectClips(model, videoClips, audioClips);
    if (videoClips.empty() && audioClips.empty()) {
        qWarning() << "[Exporter] Nothing to export";
        return false;
    }

    double brightness = 0.0, contrast = 1.0, saturation = 1.0;
    double temperature = 0.0, tint = 0.0;
    double highlight = 0.0, shadow = 0.0;
    double hueShift = 0.0, dryWet = 1.0;
    double gainDb = 0.0;
    bool doNormalize = false;
    int fadeInMs = 0, fadeOutMs = 0;
    if (fx_) {
        brightness   = fx_->brightness();
        contrast     = fx_->contrast();
        saturation   = fx_->saturation();
        temperature  = fx_->temperature();
        tint         = fx_->tint();
        highlight    = fx_->highlight();
        shadow       = fx_->shadow();
        hueShift     = fx_->hueShift();
        dryWet       = fx_->dryWet();
        gainDb       = fx_->gainDb();
        doNormalize  = fx_->normalize();
        fadeInMs     = fx_->fadeInMs();
        fadeOutMs    = fx_->fadeOutMs();
    }
    const float gainLinear = static_cast<float>(std::pow(10.0, gainDb / 20.0));

    AVFormatContext* outFmt = nullptr;
    if (avformat_alloc_output_context2(&outFmt, nullptr, "mp4",
                                       outputPath.toUtf8().constData()) < 0 || !outFmt) {
        qWarning() << "[Exporter] Cannot allocate output context";
        return false;
    }

    ExportProfile profile = probeProfile(videoClips);
    if (targetW_ > 0 && targetH_ > 0) {
        profile.outW = targetW_;
        profile.outH = targetH_;
        profile.outSar = {1, 1};
    }
    VideoEncoder videoEncoder(outFmt, profile, crf_);
    AudioEncoder audioEncoder(outFmt, gainLinear, fadeInMs, fadeOutMs);
    PacketMuxer muxer;

    if (!videoClips.empty() && !videoEncoder.ok()) {
        qWarning() << "[Exporter] video encoder unavailable";
        avformat_free_context(outFmt);
        return false;
    }
    if (!audioClips.empty() && !audioEncoder.ok()) {
        qWarning() << "[Exporter] audio encoder unavailable";
        avformat_free_context(outFmt);
        return false;
    }

    if (!(outFmt->oformat->flags & AVFMT_NOFILE)) {
        if (avio_open(&outFmt->pb, outputPath.toUtf8().constData(), AVIO_FLAG_WRITE) < 0) {
            qWarning() << "[Exporter] Cannot open output file";
            avformat_free_context(outFmt);
            return false;
        }
    }
    if (avformat_write_header(outFmt, nullptr) < 0) {
        qWarning() << "[Exporter] Cannot write header";
        avio_closep(&outFmt->pb);
        avformat_free_context(outFmt);
        return false;
    }
    emit progressChanged(5);

    AVRational msTb = {1, 1000};
    const double fps = (profile.outFps.num > 0)
                           ? static_cast<double>(profile.outFps.num) / profile.outFps.den
                           : 30.0;
    const qint64 frameDurMs = std::max(1LL, static_cast<qint64>(1000.0 / fps + 0.5));
    int frameDurTicks = static_cast<int>(30000.0 * profile.outFps.den / profile.outFps.num + 0.5);
    if (frameDurTicks < 1) frameDurTicks = 1;

    const qint64 totalDur = std::max(model->durationMs(), frameDurMs);
    const int totalFrames = static_cast<int>(totalDur / frameDurMs) + 1;

    // Open one decoder per video clip.
    std::vector<ClipSrc> vdec;
    vdec.reserve(videoClips.size());
    for (auto& ci : videoClips) vdec.emplace_back(ci, profile.outW, profile.outH);

    // Reusable intermediate frames + converters.
    AVFrame* rgbaFrame = av_frame_alloc();
    rgbaFrame->format = AV_PIX_FMT_RGBA;
    rgbaFrame->width = profile.outW;
    rgbaFrame->height = profile.outH;
    av_frame_get_buffer(rgbaFrame, 0);

    AVFrame* yuvFrame = av_frame_alloc();
    yuvFrame->format = AV_PIX_FMT_YUV420P;
    yuvFrame->width = profile.outW;
    yuvFrame->height = profile.outH;
    av_frame_get_buffer(yuvFrame, 0);

    SwsContext* toRgba = sws_getContext(profile.outW, profile.outH, AV_PIX_FMT_YUV420P,
                                        profile.outW, profile.outH, AV_PIX_FMT_RGBA,
                                        SWS_BILINEAR, nullptr, nullptr, nullptr);
    SwsContext* toYuv = sws_getContext(profile.outW, profile.outH, AV_PIX_FMT_RGBA,
                                       profile.outW, profile.outH, AV_PIX_FMT_YUV420P,
                                       SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (!toRgba || !toYuv) {
        qWarning() << "[Exporter] sws_getContext failed";
        av_frame_free(&rgbaFrame);
        av_frame_free(&yuvFrame);
        sws_freeContext(toRgba);
        sws_freeContext(toYuv);
        avio_closep(&outFmt->pb);
        avformat_free_context(outFmt);
        return false;
    }

    // ---- Video (time-driven, with overlays + transitions) ----
    int64_t vPtsTicks = 0;
    for (int f = 0; f < totalFrames; ++f) {
        const qint64 t = f * frameDurMs;

        // Active base (V1) clip at time t.
        int activeIdx = -1;
        for (size_t k = 0; k < videoClips.size(); ++k) {
            if (t >= videoClips[k].timelineStartMs && t < videoClips[k].timelineEndMs) {
                activeIdx = static_cast<int>(k);
                break;
            }
        }

        // Clear RGBA to transparent black.
        memset(rgbaFrame->data[0], 0, rgbaFrame->linesize[0] * profile.outH);

        AVFrame* baseYuv = nullptr;
        if (activeIdx >= 0) {
            const double speed = videoClips[activeIdx].playbackSpeed;
            baseYuv = vdec[activeIdx].frameAt(t - videoClips[activeIdx].timelineStartMs, speed);
        }

        // Transition dispatch: create the effect once and reuse per frame.
        static std::unique_ptr<TransitionEffect> currentEffect;
        static int64_t lastClipA = -1;
        static int64_t lastClipB = -1;
        static QString lastType;

        const Transition* tr = model->transitionAt(t);
        bool trChanged = false;
        if (tr) {
            if (tr->clipAId != lastClipA || tr->clipBId != lastClipB || tr->type != lastType) {
                currentEffect = createTransitionEffect(tr->type, tr->params);
                lastClipA = tr->clipAId;
                lastClipB = tr->clipBId;
                lastType = tr->type;
                trChanged = true;
            }
        } else if (lastClipA != -1) {
            currentEffect.reset();
            lastClipA = -1;
            lastClipB = -1;
            lastType.clear();
            trChanged = true;
        }

        if (tr && currentEffect && baseYuv) {
            int bi = -1;
            for (size_t k = 0; k < videoClips.size(); ++k) {
                if (videoClips[k].clipId == tr->clipBId) { bi = static_cast<int>(k); break; }
            }
            if (bi >= 0) {
                qint64 bLocalMs = std::max(qint64(0), t - videoClips[bi].timelineStartMs);
                AVFrame* bYuv = vdec[bi].frameAt(bLocalMs);
                if (bYuv) {
                    const qint64 aEnd = videoClips[activeIdx].timelineEndMs;
                    const float prog = static_cast<float>(
                        static_cast<double>(t - (aEnd - tr->durationMs)) /
                        static_cast<double>(tr->durationMs));
                    AVFrame* blended = currentEffect->apply(baseYuv, bYuv, prog);
                    if (blended) {
                        av_frame_free(&baseYuv);
                        baseYuv = blended;
                    }
                    av_frame_free(&bYuv);
                }
            }
        }

        if (baseYuv) {
            sws_scale(toRgba, baseYuv->data, baseYuv->linesize, 0, profile.outH,
                      rgbaFrame->data, rgbaFrame->linesize);
            av_frame_free(&baseYuv);
        }

        // Bake Text/Sticker overlays on top.
        QImage qimg(rgbaFrame->data[0], profile.outW, profile.outH,
                    rgbaFrame->linesize[0], QImage::Format_RGBA8888);
        Compositor::composite(qimg, model, t);

        // Apply the real-time effect chain on the RGBA image (before YUV conversion).
        if (fx_ && !fx_->effectChain().empty()) {
            fx_->applyEffectsToImage(qimg);
        }

        // Back to YUV and apply the color grade.
        sws_scale(toYuv, rgbaFrame->data, rgbaFrame->linesize, 0, profile.outH,
                  yuvFrame->data, yuvFrame->linesize);
        fx::VideoFX::applyColorGrade(yuvFrame, brightness, contrast, saturation,
                                     temperature, tint, highlight, shadow,
                                     hueShift, dryWet);

        yuvFrame->pts = vPtsTicks;
        vPtsTicks += frameDurTicks;
        std::vector<AVPacket*> pkts;
        videoEncoder.encodeFrame(yuvFrame, pkts);
        for (auto* p : pkts) { muxer.add(p, videoEncoder.stream()); av_packet_free(&p); }

        emit progressChanged(5 + static_cast<int>(85.0 * (f + 1) / totalFrames));
    }

    av_frame_free(&rgbaFrame);
    av_frame_free(&yuvFrame);
    sws_freeContext(toRgba);
    sws_freeContext(toYuv);

    // ---- Audio (with timeline position awareness) ----
    if (audioEncoder.ok()) {
        AVFrame* frame = av_frame_alloc();
        size_t total = audioClips.size();
        size_t done = 0;
        for (const auto& clip : audioClips) {
            AVFormatContext* inFmt = nullptr;
            if (avformat_open_input(&inFmt, clip.sourcePath.toUtf8().constData(),
                                    nullptr, nullptr) != 0) {
                qWarning() << "[Exporter] Cannot open" << clip.sourcePath;
                ++done; continue;
            }
            if (avformat_find_stream_info(inFmt, nullptr) < 0) {
                qWarning() << "[Exporter] No stream info for audio" << clip.sourcePath;
                avformat_close_input(&inFmt);
                ++done; continue;
            }
            int aIdx = -1;
            AVCodecContext* dec = nullptr;
            AVRational inTb = {1, 1};
            for (unsigned i = 0; i < inFmt->nb_streams; ++i) {
                if (inFmt->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
                    aIdx = static_cast<int>(i);
                    inTb = inFmt->streams[i]->time_base;
                    const AVCodec* dc = avcodec_find_decoder(inFmt->streams[i]->codecpar->codec_id);
                    dec = avcodec_alloc_context3(dc);
                    avcodec_parameters_to_context(dec, inFmt->streams[i]->codecpar);
                    if (avcodec_open2(dec, dc, nullptr) < 0) {
                        qWarning() << "[Exporter] Cannot open audio decoder";
                        avcodec_free_context(&dec);
                        avformat_close_input(&inFmt);
                        dec = nullptr;
                        break;
                    }
                    break;
                }
            }
            if (aIdx < 0 || !dec) { avformat_close_input(&inFmt); ++done; continue; }

            // Insert silence to match the clip's timeline position.
            int64_t targetStartSamples = static_cast<int64_t>(clip.timelineStartMs) * 48000 / 1000;
            int64_t currentSamples = audioEncoder.currentPts();
            if (targetStartSamples > currentSamples) {
                int64_t silenceSamples = targetStartSamples - currentSamples;
                std::vector<AVPacket*> silencePkts;
                audioEncoder.insertSilence(silenceSamples, silencePkts);
                for (auto* p : silencePkts) { muxer.add(p, audioEncoder.stream()); av_packet_free(&p); }
            }

            audioEncoder.configureResampler(dec->ch_layout, dec->sample_rate, dec->sample_fmt);
            const double speed = clip.playbackSpeed;
            int64_t clipSamples = static_cast<int64_t>((clip.srcOutMs - clip.srcInMs) / 1000.0 * 48000 / speed);

            if (doNormalize) {
                int64_t seekTs = av_rescale_q(clip.srcInMs, AVRational{1, 1000}, inTb);
                av_seek_frame(inFmt, aIdx, seekTs, AVSEEK_FLAG_BACKWARD);
                avcodec_flush_buffers(dec);
                AVPacket* peakPkt = av_packet_alloc();
                float peak = 0.0f;
                while (av_read_frame(inFmt, peakPkt) >= 0) {
                    if (peakPkt->stream_index != aIdx) { av_packet_unref(peakPkt); continue; }
                    avcodec_send_packet(dec, peakPkt);
                    while (avcodec_receive_frame(dec, frame) >= 0) {
                        int64_t ts = frame->pts;
                        if (ts != AV_NOPTS_VALUE) {
                            int64_t fms = av_rescale_q(ts, inTb, msTb);
                            if (fms > clip.srcOutMs) { av_frame_unref(frame); av_packet_unref(peakPkt); goto end_peak; }
                        }
                        peak = std::max(peak, audioEncoder.scanPeak(frame));
                        av_frame_unref(frame);
                    }
                    av_packet_unref(peakPkt);
                }
            end_peak:
                av_packet_free(&peakPkt);
                audioEncoder.applyNormalize(peak);
                av_seek_frame(inFmt, aIdx, seekTs, AVSEEK_FLAG_BACKWARD);
                avcodec_flush_buffers(dec);
            }

            audioEncoder.beginClip(clipSamples);
            AVPacket* inPkt = av_packet_alloc();
            while (av_read_frame(inFmt, inPkt) >= 0) {
                if (inPkt->stream_index != aIdx) { av_packet_unref(inPkt); continue; }
                avcodec_send_packet(dec, inPkt);
                while (avcodec_receive_frame(dec, frame) >= 0) {
                    int64_t ts = frame->pts;
                    if (ts != AV_NOPTS_VALUE) {
                        int64_t fms = av_rescale_q(ts, inTb, msTb);
                        if (fms > clip.srcOutMs) { av_frame_unref(frame); av_packet_unref(inPkt); goto end_audio_clip; }
                        if (fms < clip.srcInMs) { av_frame_unref(frame); continue; }
                    }
                    std::vector<AVPacket*> pkts;
                    audioEncoder.feedFrame(frame, pkts);
                    for (auto* p : pkts) { muxer.add(p, audioEncoder.stream()); av_packet_free(&p); }
                    av_frame_unref(frame);
                }
                av_packet_unref(inPkt);
            }
        end_audio_clip:
            // Flush the decoder to get any buffered frames.
            avcodec_send_packet(dec, nullptr);
            while (avcodec_receive_frame(dec, frame) >= 0) {
                std::vector<AVPacket*> pkts;
                audioEncoder.feedFrame(frame, pkts);
                for (auto* p : pkts) { muxer.add(p, audioEncoder.stream()); av_packet_free(&p); }
                av_frame_unref(frame);
            }
            std::vector<AVPacket*> tail;
            audioEncoder.endClip(tail);
            for (auto* p : tail) { muxer.add(p, audioEncoder.stream()); av_packet_free(&p); }
            av_packet_free(&inPkt);
            avcodec_free_context(&dec);
            avformat_close_input(&inFmt);
            ++done;
            emit progressChanged(90 + static_cast<int>(9.0 * done / total));
        }
        av_frame_free(&frame);
    }

    emit progressChanged(99);

    // ---- Flush encoders ----
    if (videoEncoder.ok()) {
        std::vector<AVPacket*> pkts;
        videoEncoder.flush(pkts);
        for (auto* p : pkts) { muxer.add(p, videoEncoder.stream()); av_packet_free(&p); }
    }
    if (audioEncoder.ok()) {
        std::vector<AVPacket*> pkts;
        audioEncoder.flush(pkts);
        for (auto* p : pkts) { muxer.add(p, audioEncoder.stream()); av_packet_free(&p); }
    }

    muxer.finalize(outFmt);
    av_write_trailer(outFmt);
    avio_closep(&outFmt->pb);
    avformat_free_context(outFmt);

    emit progressChanged(100);
    qInfo() << "[Exporter] Export finished:" << outputPath;
    return true;
}

} // namespace ghita::export_
