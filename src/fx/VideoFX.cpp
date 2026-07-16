#include "VideoFX.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <QImage>

namespace ghita::fx {

void VideoFX::applyColorGrade(AVFrame* frame, double brightness, double contrast,
                              double saturation, double temperature, double tint,
                              double highlight, double shadow, double hueShift,
                              double dryWet) {
    if (!frame || frame->format != AV_PIX_FMT_YUV420P) return;

    // Scale parameters by dryWet so that dryWet=0 gives identity regardless
    // of what the user set. This avoids needing a second frame buffer.
    const double dw = std::max(0.0, std::min(1.0, dryWet));
    const double b = (brightness * 255.0) * dw;
    const double c = 1.0 + (contrast - 1.0) * dw;
    const double s = 1.0 + (saturation - 1.0) * dw;
    const double tShift = temperature * dw;
    const double tiShift = tint * dw;
    const double hlAmt = (highlight * 64.0) * dw;
    const double shAmt = (shadow * 64.0) * dw;
    const int w = frame->width;
    const int h = frame->height;

    // Hue shift: map [-180,180] to chroma angle rotation, scaled by dryWet.
    const double hueRad = (hueShift * dw) * M_PI / 180.0;
    const double cosH = std::cos(hueRad);
    const double sinH = std::sin(hueRad);

    // Early exit when dryWet is 0 (fully dry = no effect).
    if (dw <= 0.0) return;

    // Luma (Y) plane: brightness + contrast around mid-grey, plus highlight
    // and shadow masking.
    for (int y = 0; y < h; ++y) {
        uint8_t* row = frame->data[0] + y * frame->linesize[0];
        for (int x = 0; x < w; ++x) {
            // Normalise to 0..1 around mid-grey (128).
            double v = (row[x] - 128.0) * c + 128.0 + b;

            // Shadow mask: applies shadow lift only to darker pixels.
            if (shAmt != 0.0 && row[x] < 128) {
                const double shadowMask = 1.0 - (row[x] / 128.0);
                v += shAmt * shadowMask;
            }

            // Highlight mask: applies highlight lift only to brighter pixels.
            if (hlAmt != 0.0 && row[x] > 128) {
                const double highlightMask = (row[x] - 128.0) / 127.0;
                v += hlAmt * highlightMask;
            }

            if (v < 0.0) v = 0.0;
            else if (v > 255.0) v = 255.0;
            row[x] = static_cast<uint8_t>(v + 0.5);
        }
    }

    // Chroma (U/V) planes: saturation around 128, plus temperature/tint shifts,
    // plus hue rotation.
    const double uShift = (-tShift + tiShift) * 0.15;
    const double vShift = ( tShift + tiShift) * 0.15;
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

    // Apply hue rotation to chroma planes.
    if (hueShift != 0.0 && dw > 0.0) {
        for (int y = 0; y < ch; ++y) {
            uint8_t* uRow = frame->data[1] + y * frame->linesize[1];
            uint8_t* vRow = frame->data[2] + y * frame->linesize[2];
            for (int x = 0; x < cw; ++x) {
                double u = uRow[x] - 128.0;
                double v = vRow[x] - 128.0;
                double nu = u * cosH - v * sinH;
                double nv = u * sinH + v * cosH;
                nu = std::max(-128.0, std::min(127.0, nu));
                nv = std::max(-128.0, std::min(127.0, nv));
                uRow[x] = static_cast<uint8_t>(nu + 128.0 + 0.5);
                vRow[x] = static_cast<uint8_t>(nv + 128.0 + 0.5);
            }
        }
    }
}

// ---- Crop ----

void VideoFX::applyCrop(const QImage& src, QImage& dst,
                        double left, double top, double right, double bottom) {
    if (src.isNull()) return;

    // Clamp crop values.
    left = qBound(0.0, left, 1.0);
    top = qBound(0.0, top, 1.0);
    right = qBound(0.0, right, 1.0);
    bottom = qBound(0.0, bottom, 1.0);

    // Nothing to crop => full copy.
    if (left == 0.0 && top == 0.0 && right == 0.0 && bottom == 0.0) {
        dst = src.copy();
        return;
    }

    // Validate crop doesn't exceed bounds.
    const int w = src.width();
    const int h = src.height();
    if (left + right >= 1.0 || top + bottom >= 1.0) {
        dst = QImage();
        return;
    }

    const int x1 = qRound(left * w);
    const int y1 = qRound(top * h);
    const int x2 = w - qRound(right * w);
    const int y2 = h - qRound(bottom * h);

    if (x2 <= x1 || y2 <= y1) {
        dst = QImage();
        return;
    }

    dst = src.copy(x1, y1, x2 - x1, y2 - y1);
}

} // namespace ghita::fx
