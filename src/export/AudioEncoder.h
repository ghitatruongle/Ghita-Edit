#pragma once

#include <vector>
#include <cstdint>

struct AVCodecContext;
struct AVFormatContext;
struct AVFrame;
struct AVStream;
struct AVPacket;
struct SwrContext;
struct AVChannelLayout;
enum AVSampleFormat;

namespace ghita::export_ {

// Owns the AAC encoder + resampler, and applies gain / normalize / fade.
// Per clip: configureResampler() once, optionally scanPeak()+applyNormalize()
// (pass 1), then beginClip() + feedFrame() (pass 2), then endClip().
class AudioEncoder {
public:
    AudioEncoder(AVFormatContext* outFmt, float gainLinear, int fadeInMs, int fadeOutMs);
    ~AudioEncoder();

    bool ok() const { return aCtx_ != nullptr; }
    AVStream* stream() const { return audioStream_; }
    int64_t currentPts() const { return aPts_; }

    void configureResampler(const AVChannelLayout& inLayout, int inRate, AVSampleFormat inFmt);
    float scanPeak(AVFrame* decoded);          // pass 1: peak abs sample after resample
    void applyNormalize(float peak);           // lower gain toward 0.99/peak (capped)
    void beginClip(int64_t clipSamples);       // record this clip's output start sample
    void feedFrame(AVFrame* decoded, std::vector<AVPacket*>& out);
    void endClip(std::vector<AVPacket*>& out);
    void flush(std::vector<AVPacket*>& out);    // drain buffer + flush AAC encoder
    void insertSilence(int64_t numSamples, std::vector<AVPacket*>& out);

private:
    void encodeBuffered(std::vector<AVPacket*>& out);

    AVCodecContext* aCtx_ = nullptr;
    AVStream* audioStream_ = nullptr;
    SwrContext* swr_ = nullptr;
    float gain_ = 1.0f;
    int fadeInSamples_ = 0;
    int fadeOutSamples_ = 0;
    int64_t aPts_ = 0;
    int64_t clipStartSample_ = 0;
    int64_t clipSamples_ = 0;
    const int channels_ = 2;
    const int sr_ = 48000;
    int frameSize_ = 0;
    std::vector<float> chBuf_[2];
};

} // namespace ghita::export_
