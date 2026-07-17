// Integration test for the full export pipeline (decode -> color grade / DSP
// -> encode -> mux -> remux). Drives ghita::export_::Exporter over the committed
// fixture and verifies the output is a playable MP4 with the expected streams.
//
// Encoder availability is checked at runtime: if this FFmpeg build was compiled
// without H.264/AAC, the tests are skipped rather than failing (the app would
// hit the same limitation). Re-run with a GPL-enabled FFmpeg to exercise them.

#include "export/Exporter.h"
#include "timeline/TimelineModel.h"
#include "fx/FxController.h"

#include <gtest/gtest.h>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
}

#include <QCoreApplication>
#include <QString>

#include <cstdlib>
#include <filesystem>
#include <string>

namespace fs = std::filesystem;

static std::string fixturePath() {
#ifdef TEST_FIXTURE_PATH
    return TEST_FIXTURE_PATH;
#else
    return "";
#endif
}

static bool fileExists(const std::string& p) {
    std::error_code ec;
    return fs::exists(p, ec);
}

// One video clip (track 0) + one audio clip (track 1) from the same source.
static ghita::timeline::TimelineModel* buildTimeline(const std::string& src,
                                                     int64_t durationMs) {
    auto* m = new ghita::timeline::TimelineModel();
    m->addClip(QString::fromStdString(src), 0, durationMs, 0, 0); // video V1
    m->addClip(QString::fromStdString(src), 0, durationMs, 0, 1); // audio A1
    return m;
}

static bool exportWith(const std::string& src, const std::string& out,
                       double brightness) {
    auto* model = buildTimeline(src, 3000);
    ghita::fx::FxController fx;
    fx.setBrightness(brightness);
    ghita::export_::Exporter exporter;
    exporter.setFxController(&fx);
    exporter.setCrf(23);
    bool ok = exporter.exportProject(model, QString::fromStdString(out));
    delete model;
    return ok;
}

struct StreamInfo {
    int video = 0;
    int audio = 0;
};

static StreamInfo probeStreams(const std::string& path) {
    StreamInfo info;
    AVFormatContext* fmt = nullptr;
    if (avformat_open_input(&fmt, path.c_str(), nullptr, nullptr) != 0)
        return info;
    avformat_find_stream_info(fmt, nullptr);
    for (unsigned i = 0; i < fmt->nb_streams; ++i) {
        if (fmt->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO)
            info.video++;
        else if (fmt->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO)
            info.audio++;
    }
    avformat_close_input(&fmt);
    return info;
}

// Mean luma (Y) of the first decoded video frame, or -1 on failure.
static int meanYOfFirstFrame(const std::string& path) {
    int result = -1;
    AVFormatContext* fmt = nullptr;
    if (avformat_open_input(&fmt, path.c_str(), nullptr, nullptr) != 0)
        return result;
    avformat_find_stream_info(fmt, nullptr);

    int vIdx = -1;
    const AVCodec* dec = nullptr;
    AVCodecContext* ctx = nullptr;
    for (unsigned i = 0; i < fmt->nb_streams; ++i) {
        if (fmt->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            vIdx = static_cast<int>(i);
            dec = avcodec_find_decoder(fmt->streams[i]->codecpar->codec_id);
            if (!dec) break;
            ctx = avcodec_alloc_context3(dec);
            avcodec_parameters_to_context(ctx, fmt->streams[i]->codecpar);
            avcodec_open2(ctx, dec, nullptr);
            break;
        }
    }

    if (vIdx >= 0 && ctx) {
        AVPacket* pkt = av_packet_alloc();
        AVFrame* frame = av_frame_alloc();
        while (av_read_frame(fmt, pkt) >= 0) {
            if (pkt->stream_index != vIdx) {
                av_packet_unref(pkt);
                continue;
            }
            avcodec_send_packet(ctx, pkt);
            if (avcodec_receive_frame(ctx, frame) >= 0) {
                long sum = 0;
                for (int y = 0; y < frame->height; ++y)
                    for (int x = 0; x < frame->width; ++x)
                        sum += frame->data[0][y * frame->linesize[0] + x];
                result = static_cast<int>(sum / (frame->width * frame->height));
                av_frame_unref(frame);
                av_packet_unref(pkt);
                break;
            }
            av_packet_unref(pkt);
        }
        av_packet_free(&pkt);
        av_frame_free(&frame);
        avcodec_free_context(&ctx);
    }
    avformat_close_input(&fmt);
    return result;
}

TEST(ExporterRoundTripTest, exportProducesPlayableFile) {
    const std::string fixture = fixturePath();
    if (fixture.empty() || !fileExists(fixture))
        GTEST_SKIP() << "Fixture missing: " << fixture;
    // Require the software libx264 encoder — the D3D12VA hardware encoder
    // that avcodec_find_encoder(AV_CODEC_ID_H264) may return does not
    // support yuv420p, which the VideoEncoder requires.
    if (!avcodec_find_encoder_by_name("libx264") ||
        !avcodec_find_encoder(AV_CODEC_ID_AAC))
        GTEST_SKIP() << "libx264 / AAC encoder unavailable in this FFmpeg build";

    fs::path out = fs::temp_directory_path() / "ghita_roundtrip_identity.mp4";
    std::error_code ec;
    fs::remove(out, ec);

    ASSERT_TRUE(exportWith(fixture, out.string(), 0.0))
        << "exportProject returned false";
    ASSERT_TRUE(fileExists(out.string())) << "output file not created";

    const StreamInfo info = probeStreams(out.string());
    EXPECT_GE(info.video, 1) << "expected at least one video stream";
    EXPECT_GE(info.audio, 1) << "expected at least one audio stream";

    const int y = meanYOfFirstFrame(out.string());
    EXPECT_GT(y, 0) << "first frame luma degenerate (all black)";
    EXPECT_LT(y, 255) << "first frame luma degenerate (all white)";
}

TEST(ExporterRoundTripTest, brightnessIncreasesMeanLuma) {
    const std::string fixture = fixturePath();
    if (fixture.empty() || !fileExists(fixture))
        GTEST_SKIP() << "Fixture missing: " << fixture;
    if (!avcodec_find_encoder_by_name("libx264"))
        GTEST_SKIP() << "libx264 encoder unavailable — trying with D3D12VA would fail";

    // The AAC encoder check is done in the first test; assume it passes.

    fs::path outId = fs::temp_directory_path() / "ghita_rt_identity.mp4";
    fs::path outBright = fs::temp_directory_path() / "ghita_rt_bright.mp4";
    std::error_code ec;
    fs::remove(outId, ec);
    fs::remove(outBright, ec);

    ASSERT_TRUE(exportWith(fixture, outId.string(), 0.0));
    ASSERT_TRUE(exportWith(fixture, outBright.string(), 0.5));

    const int yId = meanYOfFirstFrame(outId.string());
    const int yBright = meanYOfFirstFrame(outBright.string());
    ASSERT_GT(yId, 0) << "identity export produced a degenerate frame";
    EXPECT_GT(yBright, yId) << "brightness boost should raise mean luma";
}

// Custom entry point: a QCoreApplication is required so the Qt-based model and
// effect controller (QObject subclasses) behave correctly under test.
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
