#include "fx/VideoFX.h"
#include <gtest/gtest.h>
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
}

using ghita::fx::VideoFX;

static AVFrame* makeYuv(int w, int h, uint8_t y) {
    AVFrame* f = av_frame_alloc();
    f->format = AV_PIX_FMT_YUV420P;
    f->width = w; f->height = h;
    av_frame_get_buffer(f, 0);
    for (int p = 0; p < 3; ++p) {
        int cw = (p == 0) ? w : (w + 1) / 2;
        int ch = (p == 0) ? h : (h + 1) / 2;
        uint8_t v = (p == 0) ? y : 128;
        for (int yy = 0; yy < ch; ++yy)
            for (int xx = 0; xx < cw; ++xx)
                f->data[p][yy * f->linesize[p] + xx] = v;
    }
    return f;
}

static int meanY(AVFrame* f, int w, int h) {
    long sum = 0;
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x)
            sum += f->data[0][y * f->linesize[0] + x];
    return static_cast<int>(sum / (w * h));
}

TEST(VideoFXTest, identityLeavesLumaUnchanged) {
    AVFrame* f = makeYuv(4, 4, 128);
    VideoFX::applyColorGrade(f, 0.0, 1.0, 1.0); // early-return path
    EXPECT_EQ(meanY(f, 4, 4), 128);
    av_frame_free(&f);
}

TEST(VideoFXTest, brightnessUpClampsToWhite) {
    AVFrame* f = makeYuv(4, 4, 128);
    VideoFX::applyColorGrade(f, 0.5, 1.0, 1.0); // b = 0.5*255 = 127.5 -> 255
    EXPECT_EQ(meanY(f, 4, 4), 255);
    av_frame_free(&f);
}

TEST(VideoFXTest, brightnessDownClampsToBlack) {
    AVFrame* f = makeYuv(4, 4, 128);
    VideoFX::applyColorGrade(f, -1.0, 1.0, 1.0); // b = -255 -> 0
    EXPECT_EQ(meanY(f, 4, 4), 0);
    av_frame_free(&f);
}
