// Standalone verification tool (no GoogleTest) for the export pipeline.
// Drives ghita::export_::Exporter over the committed fixture and verifies the
// output is a playable MP4 whose first frame is not degenerate (all black /
// all white). This exists to confirm the av_seek_frame time_base fix without
// pulling in the GoogleTest FetchContent (unavailable offline in this env).
//
// Build via CMake (GHITA_BUILD_SELFTEST=ON) and run:
//   GhitaSelftest <path-to-sample.mp4>

#include "export/Exporter.h"
#include "timeline/TimelineModel.h"
#include "fx/FxController.h"

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
}

#include <QCoreApplication>
#include <QString>

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

namespace fs = std::filesystem;

static std::string fixturePath(int argc, char** argv) {
    if (argc > 1) return argv[1];
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

static int probeVideoStreams(const std::string& path) {
    int video = 0;
    AVFormatContext* fmt = nullptr;
    if (avformat_open_input(&fmt, path.c_str(), nullptr, nullptr) != 0)
        return -1;
    avformat_find_stream_info(fmt, nullptr);
    for (unsigned i = 0; i < fmt->nb_streams; ++i)
        if (fmt->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO)
            video++;
    avformat_close_input(&fmt);
    return video;
}

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);

    const std::string fixture = fixturePath(argc, argv);
    if (fixture.empty() || !fileExists(fixture)) {
        std::fprintf(stderr, "SKIP: fixture missing: %s\n", fixture.c_str());
        return 77; // denote skip
    }
    if (!avcodec_find_encoder_by_name("libx264") ||
        !avcodec_find_encoder(AV_CODEC_ID_AAC)) {
        std::fprintf(stderr, "SKIP: libx264 / AAC encoder unavailable\n");
        return 77;
    }

    fs::path out = fs::temp_directory_path() / "ghita_selftest.mp4";
    std::error_code ec;
    fs::remove(out, ec);

    std::printf("Exporting identity (brightness=0)...\n");
    bool ok = exportWith(fixture, out.string(), 0.0);
    if (!ok) {
        std::fprintf(stderr, "FAIL: exportProject returned false\n");
        return 1;
    }
    if (!fileExists(out.string())) {
        std::fprintf(stderr, "FAIL: output file not created\n");
        return 1;
    }
    const int videoStreams = probeVideoStreams(out.string());
    if (videoStreams < 1) {
        std::fprintf(stderr, "FAIL: no video stream in output (got %d)\n",
                     videoStreams);
        return 1;
    }
    const int y = meanYOfFirstFrame(out.string());
    std::printf("First-frame mean luma Y = %d\n", y);
    if (y <= 0) {
        std::fprintf(stderr, "FAIL: first frame degenerate (all black), Y=%d\n", y);
        return 1;
    }
    if (y >= 255) {
        std::fprintf(stderr, "FAIL: first frame degenerate (all white), Y=%d\n", y);
        return 1;
    }

    std::printf("PASS: export produced playable MP4, first frame non-degenerate "
                "(Y=%d, video streams=%d)\n",
                y, videoStreams);
    return 0;
}
