#pragma once

#include "HWAccel.h"
#include "FramePool.h"

#include <string>
#include <vector>

struct AVFormatContext;
struct AVCodecContext;
struct AVFrame;
struct AVPacket;
struct SwsContext;
struct SwrContext;

namespace ghita::engine {

// Decoder: opens a media file, selects a hardware backend, and decodes
// video (to RGBA) and audio (to float PCM) frames into the queues.
//
// M0: software decode path is implemented (most portable, works on any GPU).
// The HW backend selection API exists but defaults to software for M0 to
// keep the pipeline deterministic; NVDEC/VA-API upload lands in a later step.
class Decoder {
public:
    Decoder();
    ~Decoder();

    bool open(std::string path);
    HWBackend selectBackend() const;

    // Decode one packet worth of frames (video and/or audio) and push them
    // into the respective queues. Returns false at end of stream or on error.
    bool decodeStep(VideoFrameQueue& videoQ, AudioFrameQueue& audioQ);

    // Seek to a position in milliseconds. Flushes codec buffers and resets EOF.
    // The next decodeStep() call will start from the new position.
    bool seek(int64_t targetMs);

    bool isOpen() const { return fmtCtx_ != nullptr; }
    bool atEnd() const { return eof_; }
    int videoIndex() const { return videoStreamIndex_; }
    int audioIndex() const { return audioStreamIndex_; }
    double videoFps() const;
    int audioSampleRate() const { return audioSampleRate_; }
    int audioChannels() const { return audioChannels_; }

    bool hasVideo() const { return videoStreamIndex_ >= 0; }
    bool hasAudio() const { return audioStreamIndex_ >= 0; }

    // Total duration in milliseconds (from container format).
    int64_t durationMs() const;

private:
    bool openStream(int index, AVCodecContext*& ctx);
    bool decodeVideoFrame(AVFrame* frame, VideoFrameQueue& videoQ);
    bool decodeAudioFrame(AVFrame* frame, AudioFrameQueue& audioQ);

    std::string path_;
    AVFormatContext* fmtCtx_ = nullptr;
    AVCodecContext* videoCtx_ = nullptr;
    AVCodecContext* audioCtx_ = nullptr;
    SwsContext* swsCtx_ = nullptr;
    SwrContext* swrCtx_ = nullptr;
    int videoStreamIndex_ = -1;
    int audioStreamIndex_ = -1;
    int audioSampleRate_ = 0;
    int audioChannels_ = 0;
    int64_t videoTimeBaseNum_ = 1;
    int64_t videoTimeBaseDen_ = 1;
    AVPacket* pkt_ = nullptr;
    AVFrame* frame_ = nullptr;
    bool eof_ = false;
    int64_t pictureCounter_ = 0;
};

} // namespace ghita::engine
