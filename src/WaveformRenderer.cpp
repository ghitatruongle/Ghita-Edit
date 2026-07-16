// WaveformRenderer.cpp — Decode audio, compute RMS envelope, cache results.
//
// Follows the same FFmpeg decode pattern as ThumbnailExtractor: open format
// context, iterate packets, send to decoder, resample to 48 kHz stereo float
// via libswresample, then pack into interleaved Frame::rgba.

#include "WaveformRenderer.h"
#include <QDateTime>
#include <QDir>
#include <QDebug>
#include <QMap>
#include <cmath>

WaveformRenderer::WaveformRenderer(QObject *parent)
    : QObject(parent)
{
}

WaveformRenderer::~WaveformRenderer()
{
}

float WaveformRenderer::rms(const float *samples, int count)
{
    if (count <= 0) return 0.0f;
    double sum = 0.0;
    for (int i = 0; i < count; ++i) {
        sum += samples[i] * samples[i];
    }
    return static_cast<float>(std::sqrt(sum / count));
}

QVector<float> WaveformRenderer::decodeAudioToPCM(const QString &mediaPath)
{
    AVFormatContext *fmtCtx = avformat_alloc_context();
    if (!fmtCtx) return {};

    std::string pathStr = mediaPath.toStdString();
    if (avformat_open_input(&fmtCtx, pathStr.c_str(), nullptr, nullptr) < 0) {
        avformat_free_context(fmtCtx);
        return {};
    }
    if (avformat_find_stream_info(fmtCtx, nullptr) < 0) {
        avformat_close_input(&fmtCtx);
        return {};
    }

    // Find audio stream.
    int audioStreamIndex = -1;
    for (unsigned i = 0; i < fmtCtx->nb_streams; ++i) {
        if (fmtCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audioStreamIndex = static_cast<int>(i);
            break;
        }
    }

    if (audioStreamIndex < 0) {
        avformat_close_input(&fmtCtx);
        return {};
    }

    AVStream *audioStream = fmtCtx->streams[audioStreamIndex];
    AVCodecParameters *codecPar = audioStream->codecpar;

    const AVCodec *codec = avcodec_find_decoder(codecPar->codec_id);
    if (!codec) {
        avformat_close_input(&fmtCtx);
        return {};
    }

    AVCodecContext *codecCtx = avcodec_alloc_context3(codec);
    if (avcodec_parameters_to_context(codecCtx, codecPar) < 0) {
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        return {};
    }
    if (avcodec_open2(codecCtx, codec, nullptr) < 0) {
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        return {};
    }

    // Setup resampler: decode format -> interleaved float 48 kHz stereo.
    SwrContext *swrCtx = swr_alloc();
    av_opt_set_chlayout(swrCtx, "in_chlayout", &codecCtx->ch_layout, 0);
    av_opt_set_int(swrCtx, "in_sample_rate", codecCtx->sample_rate, 0);
    av_opt_set_sample_fmt(swrCtx, "in_sample_fmt", codecCtx->sample_fmt, 0);

    AVChannelLayout outLayout;
    av_channel_layout_default(&outLayout, 2);
    av_opt_set_chlayout(swrCtx, "out_chlayout", &outLayout, 0);
    av_opt_set_int(swrCtx, "out_sample_rate", 48000, 0);
    av_opt_set_sample_fmt(swrCtx, "out_sample_fmt", AV_SAMPLE_FMT_FLT, 0);

    if (swr_init(swrCtx) < 0) {
        qWarning() << "[WaveformRenderer] swr_init failed";
        swr_free(&swrCtx);
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        return {};
    }
    av_channel_layout_uninit(&outLayout);

    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();

    // Accumulate all decoded/resampled PCM samples (interleaved L,R).
    QVector<float> pcm;
    pcm.reserve(48000 * 60 * 2); // Up to 60 min stereo at 48 kHz.

    while (av_read_frame(fmtCtx, packet) >= 0) {
        if (packet->stream_index != audioStreamIndex) {
            av_packet_unref(packet);
            continue;
        }

        if (avcodec_send_packet(codecCtx, packet) < 0) {
            av_packet_unref(packet);
            continue;
        }
        av_packet_unref(packet);

        while (avcodec_receive_frame(codecCtx, frame) == 0) {
            int outSamples = swr_get_out_samples(swrCtx, frame->nb_samples);
            if (outSamples <= 0) continue;

            uint8_t *outBuf = nullptr;
            int ret = av_samples_alloc(&outBuf, nullptr, 2, outSamples,
                                       AV_SAMPLE_FMT_FLT, 0);
            if (ret < 0) continue;

            int converted = swr_convert(swrCtx, &outBuf, outSamples,
                                        const_cast<const uint8_t **>(frame->data),
                                        frame->nb_samples);
            if (converted > 0) {
                float *f = reinterpret_cast<float *>(outBuf);
                for (int s = 0; s < converted; ++s) {
                    pcm.append(f[s]);
                }
            }

            av_freep(&outBuf);
        }
    }

    av_frame_free(&frame);
    av_packet_free(&packet);
    swr_free(&swrCtx);
    avcodec_free_context(&codecCtx);
    avformat_close_input(&fmtCtx);

    return pcm;
}

QVector<float> WaveformRenderer::downsampleEnvelope(
        const QVector<float> &full, int targetColumns)
{
    if (full.isEmpty() || targetColumns <= 0) return {};

    int totalBins = static_cast<int>(full.size());
    int samplesPerCol = totalBins / targetColumns;
    if (samplesPerCol <= 0) samplesPerCol = 1;

    QVector<float> envelope;
    envelope.reserve(targetColumns);

    for (int col = 0; col < targetColumns; ++col) {
        int start = col * samplesPerCol;
        int end = (col == targetColumns - 1)
                      ? totalBins
                      : start + samplesPerCol;
        int count = end - start;
        if (count <= 0) {
            envelope.append(0.0f);
            continue;
        }
        double sum = 0.0;
        for (int b = start; b < end; ++b) {
            sum += full[b] * full[b];
        }
        envelope.append(static_cast<float>(std::sqrt(sum / count)));
    }

    // Normalize to 0..1 range.
    float peak = 0.0f;
    for (float v : envelope) {
        if (v > peak) peak = v;
    }
    if (peak > 0.0f) {
        for (float &v : envelope) {
            v /= peak;
        }
    }

    return envelope;
}

QVector<float> WaveformRenderer::computeEnvelope(const QString &mediaPath, int columns)
{
    QVector<float> pcm = decodeAudioToPCM(mediaPath);
    if (pcm.isEmpty()) return {};

    // Compute per-bin RMS with a sliding window of ~10 ms bins.
    // pcm is interleaved L,R so every 2 floats = 1 stereo frame.
    const int binSize = 480; // 10 ms at 48 kHz (per channel)

    QVector<float> fullEnvelope;
    int totalFrames = static_cast<int>(pcm.size()) / 2;

    for (int i = 0; i < totalFrames; i += binSize) {
        int count = qMin(binSize, totalFrames - i);
        double sum = 0.0;
        for (int j = 0; j < count; ++j) {
            int idx = (i + j) * 2;
            if (idx + 1 >= static_cast<int>(pcm.size())) break;
            sum += pcm[idx] * pcm[idx] + pcm[idx + 1] * pcm[idx + 1];
        }
        fullEnvelope.append(static_cast<float>(std::sqrt(sum / (count * 2))));
    }

    return downsampleEnvelope(fullEnvelope, columns);
}

QVector<float> WaveformRenderer::getOrComputeEnvelope(
        const QString &mediaPath, int columns)
{
    // Simple LRU-style cache keyed by (mediaPath + columns).
    qint64 now = QDateTime::currentMSecsSinceEpoch();
    qint64 cutoff = now - (kCacheAgeMinutes * 60LL * 1000LL);

    // Evict stale entries first.
    QVector<CacheEntry> fresh;
    fresh.reserve(cache_.size());
    for (const auto &entry : cache_) {
        if (entry.timestamp >= cutoff) {
            fresh.append(entry);
        }
    }
    cache_ = std::move(fresh);

    // Check for a matching entry.
    QString cacheKey = mediaPath + QString::number(columns);
    for (const auto &entry : cache_) {
        if (entry.key == cacheKey) {
            return entry.envelope;
        }
    }

    // Compute and cache.
    QVector<float> env = computeEnvelope(mediaPath, columns);
    if (!env.isEmpty()) {
        CacheEntry ce;
        ce.key = cacheKey;
        ce.envelope = std::move(env);
        ce.timestamp = now;
        cache_.append(ce);
    }

    return cache_.last().envelope;
}
