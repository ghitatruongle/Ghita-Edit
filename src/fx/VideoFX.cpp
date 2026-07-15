#include "VideoFX.h"

#include <algorithm>
#include <cstdint>

namespace ghita::fx {

void VideoFX::applyColorGrade(AVFrame* frame, double brightness, double contrast,
                              double saturation, double temperature, double tint) {
    if (!frame || frame->format != AV_PIX_FMT_YUV420P) return;
    // Skip when effectively identity to avoid needless work.
    if (brightness == 0.0 && contrast == 1.0 && saturation == 1.0 &&
        temperature == 0.0 && tint == 0.0) return;

    const double b = brightness * 255.0;
    const double c = contrast;
    const double s = saturation;
    const int w = frame->width;
    const int h = frame->height;

    // Luma (Y) plane: brightness + contrast around mid-grey.
    for (int y = 0; y < h; ++y) {
        uint8_t* row = frame->data[0] + y * frame->linesize[0];
        for (int x = 0; x < w; ++x) {
            double v = (row[x] - 128.0) * c + 128.0 + b;
            if (v < 0.0) v = 0.0;
            else if (v > 255.0) v = 255.0;
            row[x] = static_cast<uint8_t>(v + 0.5);
        }
    }

    // Chroma (U/V) planes: saturation around 128, plus temperature/tint shifts.
    // U ~ blue-yellow (+ = blue), V ~ red-green (+ = red).
    //   temperature > 0 => warmer => less blue, more red  => U-, V+
    //   tint       > 0 => magenta  => more red & blue     => U+, V+
    const double uShift = (-temperature + tint) * 0.15;
    const double vShift = ( temperature + tint) * 0.15;
    const int cw = (w + 1) / 2;
    const int ch = (h + 1) / 2;
    for (int p = 1; p <= 2; ++p) {
        const double shift = (p == 1) ? uShift : vShift;
        for (int y = 0; y < ch; ++y) {
            uint8_t* row = frame->data[p] + y * frame->linesize[p];
            for (int x = 0; x < cw; ++x) {
                double v = (row[x] - 128.0) * s + 128.0 + shift;
                if (v < 0.0) v = 0.0;
                else if (v > 255.0) v = 255.0;
                row[x] = static_cast<uint8_t>(v + 0.5);
            }
        }
    }
}

} // namespace ghita::fx
