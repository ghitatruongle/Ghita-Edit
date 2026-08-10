#include "ghita_engine.h"
#include <cmath>
#include <algorithm>
#include <cstring>
#include <fstream>
#include <iostream>

// v0.8.0: GDI text rendering for text/sticker clips (Windows only).
// NOMINMAX keeps windows.h from defining min/max macros (std::clamp uses them).
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <mmsystem.h>
#endif

// ====================================================================
// Pixel shader helpers (applied in RGBA space)
// ====================================================================
namespace {

struct RGBA { uint8_t r, g, b, a; };

void applyGrayscale(uint8_t* buf, int pixelCount) {
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        uint8_t y = static_cast<uint8_t>(0.299f * p.r + 0.587f * p.g + 0.114f * p.b);
        p.r = p.g = p.b = y;
    }
}

void applySepia(uint8_t* buf, int pixelCount) {
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        uint8_t r = p.r, g = p.g, b = p.b;
        p.r = std::min(255, static_cast<int>(0.393f * r + 0.769f * g + 0.189f * b));
        p.g = std::min(255, static_cast<int>(0.349f * r + 0.686f * g + 0.168f * b));
        p.b = std::min(255, static_cast<int>(0.272f * r + 0.534f * g + 0.131f * b));
    }
}

void applyInvert(uint8_t* buf, int pixelCount) {
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        p.r = 255 - p.r;
        p.g = 255 - p.g;
        p.b = 255 - p.b;
    }
}

void applyBrightness(uint8_t* buf, int pixelCount, float intensity) {
    int delta = static_cast<int>((intensity - 0.5f) * 2.0f * 128);
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        p.r = std::clamp(static_cast<int>(p.r) + delta, 0, 255);
        p.g = std::clamp(static_cast<int>(p.g) + delta, 0, 255);
        p.b = std::clamp(static_cast<int>(p.b) + delta, 0, 255);
    }
}

// v0.7.9: Separable Gaussian blur — O(n·r) two-pass instead of the old
// O(n·r²) box blur (which sampled the whole radius box per pixel). Precomputed
// kernel, clamp-to-edge sampling, ~4-5x faster at typical radii.
void applyBlur(uint8_t* buf, int width, int height, float intensity) {
    int radius = std::max(1, static_cast<int>(intensity * 10.0f));

    // Precompute normalized Gaussian kernel
    std::vector<float> kernel(2 * radius + 1);
    float sum = 0.0f;
    const float sigma = radius > 0 ? radius / 2.0f : 1.0f;
    for (int i = -radius; i <= radius; ++i) {
        kernel[i + radius] = std::exp(-(i * i) / (2.0f * sigma * sigma));
        sum += kernel[i + radius];
    }
    for (float& w : kernel) w /= sum;

    std::vector<uint8_t> tmp(width * height * 4);

    // Horizontal pass (clamp-to-edge)
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            float r = 0.0f, g = 0.0f, b = 0.0f;
            for (int dx = -radius; dx <= radius; ++dx) {
                int sx = std::clamp(x + dx, 0, width - 1);
                int idx = (y * width + sx) * 4;
                float w = kernel[dx + radius];
                r += buf[idx]     * w;
                g += buf[idx + 1] * w;
                b += buf[idx + 2] * w;
            }
            int outIdx = (y * width + x) * 4;
            tmp[outIdx]     = static_cast<uint8_t>(r);
            tmp[outIdx + 1] = static_cast<uint8_t>(g);
            tmp[outIdx + 2] = static_cast<uint8_t>(b);
            tmp[outIdx + 3] = buf[outIdx + 3];
        }
    }

    // Vertical pass (clamp-to-edge)
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            float r = 0.0f, g = 0.0f, b = 0.0f;
            for (int dy = -radius; dy <= radius; ++dy) {
                int sy = std::clamp(y + dy, 0, height - 1);
                int idx = (sy * width + x) * 4;
                float w = kernel[dy + radius];
                r += tmp[idx]     * w;
                g += tmp[idx + 1] * w;
                b += tmp[idx + 2] * w;
            }
            int outIdx = (y * width + x) * 4;
            buf[outIdx]     = static_cast<uint8_t>(r);
            buf[outIdx + 1] = static_cast<uint8_t>(g);
            buf[outIdx + 2] = static_cast<uint8_t>(b);
        }
    }
}

void applyEdgeDetect(uint8_t* buf, int width, int height, float /*intensity*/) {
    std::vector<uint8_t> tmp(width * height * 4);
    std::memcpy(tmp.data(), buf, tmp.size());

    const int sobelX[3][3] = {{-1, 0, 1}, {-2, 0, 2}, {-1, 0, 1}};
    const int sobelY[3][3] = {{-1, -2, -1}, {0, 0, 0}, {1, 2, 1}};

    for (int y = 1; y < height - 1; ++y) {
        for (int x = 1; x < width - 1; ++x) {
            int gx = 0, gy = 0;
            for (int ky = -1; ky <= 1; ++ky) {
                for (int kx = -1; kx <= 1; ++kx) {
                    int idx = ((y + ky) * width + (x + kx)) * 4;
                    uint8_t gray = static_cast<uint8_t>(
                        0.299f * tmp[idx] + 0.587f * tmp[idx + 1] + 0.114f * tmp[idx + 2]);
                    gx += gray * sobelX[ky + 1][kx + 1];
                    gy += gray * sobelY[ky + 1][kx + 1];
                }
            }
            int magnitude = std::min(255, static_cast<int>(std::sqrt(gx * gx + gy * gy)));
            int idx = (y * width + x) * 4;
            buf[idx] = buf[idx + 1] = buf[idx + 2] = static_cast<uint8_t>(magnitude);
        }
    }
}

void applyColorGrading(uint8_t* buf, int pixelCount, float /*intensity*/) {
    // Warm tone color matrix (slight orange shift)
    const float matrix[3][3] = {
        {1.1f, 0.0f, 0.0f},
        {0.0f, 0.9f, 0.0f},
        {0.0f, 0.0f, 0.8f}
    };
    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        float r = p.r * matrix[0][0] + p.g * matrix[0][1] + p.b * matrix[0][2];
        float g = p.r * matrix[1][0] + p.g * matrix[1][1] + p.b * matrix[1][2];
        float b = p.r * matrix[2][0] + p.g * matrix[2][1] + p.b * matrix[2][2];
        p.r = std::clamp(static_cast<int>(r), 0, 255);
        p.g = std::clamp(static_cast<int>(g), 0, 255);
        p.b = std::clamp(static_cast<int>(b), 0, 255);
    }
}

void applyAdjust(uint8_t* buf, int pixelCount, float intensity) {
    // Combined brightness, contrast, saturation, hue adjustment
    float brightness = 0.5f + intensity * 0.5f;
    float contrast = 1.0f + (intensity - 0.5f) * 0.5f;
    float saturation = 0.5f + intensity * 0.5f;

    for (int i = 0; i < pixelCount; ++i) {
        auto& p = reinterpret_cast<RGBA*>(buf)[i];
        float r = p.r / 255.0f, g = p.g / 255.0f, b = p.b / 255.0f;
        // Contrast
        r = (r - 0.5f) * contrast + 0.5f;
        g = (g - 0.5f) * contrast + 0.5f;
        b = (b - 0.5f) * contrast + 0.5f;
        // Saturation
        float gray = 0.299f * r + 0.587f * g + 0.114f * b;
        r = gray + (r - gray) * saturation;
        g = gray + (g - gray) * saturation;
        b = gray + (b - gray) * saturation;
        // Brightness
        r *= brightness; g *= brightness; b *= brightness;
        p.r = std::clamp(static_cast<int>(r * 255), 0, 255);
        p.g = std::clamp(static_cast<int>(g * 255), 0, 255);
        p.b = std::clamp(static_cast<int>(b * 255), 0, 255);
    }
}

void applyPixelate(uint8_t* buf, int width, int height, float intensity) {
    int blockSize = std::max(2, static_cast<int>(intensity * 20.0f));
    for (int y = 0; y < height; y += blockSize) {
        for (int x = 0; x < width; x += blockSize) {
            int idx = (y * width + x) * 4;
            uint8_t r = buf[idx], g = buf[idx + 1], b = buf[idx + 2];
            for (int dy = 0; dy < blockSize && y + dy < height; ++dy) {
                for (int dx = 0; dx < blockSize && x + dx < width; ++dx) {
                    int pIdx = ((y + dy) * width + (x + dx)) * 4;
                    buf[pIdx] = r;
                    buf[pIdx + 1] = g;
                    buf[pIdx + 2] = b;
                }
            }
        }
    }
}

// ====================================================================
// v0.8.0: Filters 11-20 (previously shown as "Coming soon")
// ====================================================================

// Deterministic pseudo-random in [0,1) from pixel coords — keeps the effects
// stable across frames (no flicker) and thread-safe (no shared state).
float hash01(int x, int y) {
    uint32_t h = static_cast<uint32_t>(x) * 374761393u + static_cast<uint32_t>(y) * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    return static_cast<float>((h ^ (h >> 16)) & 0xFFFFu) / 65536.0f;
}

void applyVhs(uint8_t* buf, int width, int height, float intensity) {
    const int pixelCount = width * height;
    for (int i = 0; i < pixelCount; ++i) {
        int x = i % width;
        int y = i / width;
        int idx = i * 4;
        // Scanlines every 3 rows.
        if (y % 3 == 0) {
            buf[idx]     = static_cast<uint8_t>(buf[idx] * 0.7f);
            buf[idx + 1] = static_cast<uint8_t>(buf[idx + 1] * 0.7f);
            buf[idx + 2] = static_cast<uint8_t>(buf[idx + 2] * 0.7f);
        }
        // Horizontal noise bands.
        if (hash01(x, y) < 0.02f * intensity) {
            buf[idx]     = static_cast<uint8_t>(buf[idx] * 0.4f);
            buf[idx + 1] = static_cast<uint8_t>(buf[idx + 1] * 0.4f);
            buf[idx + 2] = static_cast<uint8_t>(buf[idx + 2] * 0.4f);
        }
        // Slight color bleed.
        buf[idx + 1] = static_cast<uint8_t>(buf[idx + 1] * 0.92f + buf[idx + 2] * 0.08f);
    }
}

void applyGlitch(uint8_t* buf, int width, int height, float intensity) {
    // Slice the frame into horizontal bands and displace a subset.
    const int bandH = std::max(8, height / 12);
    for (int y0 = 0; y0 < height; y0 += bandH) {
        const int y1 = std::min(height, y0 + bandH);
        if (hash01(y0, 0) < 0.35f * intensity) {
            const int shift = static_cast<int>((hash01(y0, 1) - 0.5f) * width * 0.12f * intensity);
            if (shift == 0) continue;
            std::vector<uint8_t> row(width * 4);
            for (int y = y0; y < y1; ++y) {
                std::memcpy(row.data(), buf + y * width * 4, width * 4);
                for (int x = 0; x < width; ++x) {
                    const int srcX = (x - shift + width) % width;
                    int dst = (y * width + x) * 4;
                    // v1.1.0 (PLAN 1.1/Track 1 deep review): src must be
                    // ROW-RELATIVE — the old code indexed `row` with the
                    // absolute buffer offset ((y*width + srcX)*4), which
                    // reads past the row's end for every y > 0 (vector OOB
                    // under bounds-checking builds, heap overread otherwise).
                    int src = srcX * 4;
                    buf[dst] = row[src];
                    buf[dst + 1] = row[src + 1];
                    buf[dst + 2] = row[src + 2];
                }
            }
        }
    }
    // RGB split along the band edges.
    const int split = std::max(2, static_cast<int>(8.0f * intensity));
    for (int y = 0; y < height; y += 2) {
        int idx = (y * width) * 4;
        for (int x = width - 1; x >= split; --x) {
            int d = idx + x * 4;
            buf[d] = buf[d - split * 4]; // R trails
        }
    }
}

void applyChromaticAberration(uint8_t* buf, int width, int height, float intensity) {
    const int shift = std::max(1, static_cast<int>(4.0f * intensity));
    std::vector<uint8_t> copy(buf, buf + static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int dst = (y * width + x) * 4;
            const int rx = std::min(width - 1, x + shift);
            const int bx = std::max(0, x - shift);
            buf[dst]     = copy[(y * width + rx) * 4];
            buf[dst + 1] = copy[(y * width + x) * 4 + 1];
            buf[dst + 2] = copy[(y * width + bx) * 4 + 2];
        }
    }
}

void applyVignette(uint8_t* buf, int width, int height, float intensity) {
    const float cx = width * 0.5f;
    const float cy = height * 0.5f;
    const float maxDist = std::sqrt(cx * cx + cy * cy);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const float dx = (x - cx) / maxDist;
            const float dy = (y - cy) / maxDist;
            const float falloff = std::clamp(1.0f - (dx * dx + dy * dy) * (0.9f + intensity), 0.25f, 1.0f);
            int idx = (y * width + x) * 4;
            buf[idx]     = static_cast<uint8_t>(buf[idx] * falloff);
            buf[idx + 1] = static_cast<uint8_t>(buf[idx + 1] * falloff);
            buf[idx + 2] = static_cast<uint8_t>(buf[idx + 2] * falloff);
        }
    }
}

void applyFilmGrain(uint8_t* buf, int width, int height, float intensity) {
    const int pixelCount = width * height;
    for (int i = 0; i < pixelCount; ++i) {
        const float n = (hash01(i % width, i / width) - 0.5f) * 2.0f * 30.0f * intensity;
        int idx = i * 4;
        buf[idx]     = static_cast<uint8_t>(std::clamp(buf[idx] + n, 0.0f, 255.0f));
        buf[idx + 1] = static_cast<uint8_t>(std::clamp(buf[idx + 1] + n, 0.0f, 255.0f));
        buf[idx + 2] = static_cast<uint8_t>(std::clamp(buf[idx + 2] + n, 0.0f, 255.0f));
    }
}

void applyLightLeak(uint8_t* buf, int width, int height, float intensity) {
    // Warm diagonal gradient from the top-left corner.
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const float dist = (static_cast<float>(x) + static_cast<float>(y)) /
                               static_cast<float>(width + height);
            const float leak = std::clamp((1.0f - dist) * 0.85f * intensity, 0.0f, 0.8f);
            int idx = (y * width + x) * 4;
            buf[idx]     = static_cast<uint8_t>(std::min(255.0f, buf[idx] * (1.0f + leak) + leak * 60.0f));
            buf[idx + 1] = static_cast<uint8_t>(std::min(255.0f, buf[idx + 1] * (1.0f + leak * 0.5f) + leak * 20.0f));
            buf[idx + 2] = static_cast<uint8_t>(std::min(255.0f, buf[idx + 2] * (1.0f - leak * 0.3f)));
        }
    }
}

void applySharpen(uint8_t* buf, int width, int height, float intensity) {
    std::vector<uint8_t> copy(buf, buf + static_cast<size_t>(width) * height * 4);
    const float amount = 0.35f + intensity * 0.65f;
    for (int y = 1; y < height - 1; ++y) {
        for (int x = 1; x < width - 1; ++x) {
            int idx = (y * width + x) * 4;
            // v1.0.0: explicit float casts — MSVC C4244 warned about implicit
            // int→float promotion when assigning the uint8_t sample value.
            for (int c = 0; c < 3; ++c) {
                const float center  = static_cast<float>(copy[idx + c]);
                const float top     = static_cast<float>(copy[((y - 1) * width + x) * 4 + c]);
                const float bottom  = static_cast<float>(copy[((y + 1) * width + x) * 4 + c]);
                const float left    = static_cast<float>(copy[(y * width + x - 1) * 4 + c]);
                const float right   = static_cast<float>(copy[(y * width + x + 1) * 4 + c]);
                const float sum = top + bottom + left + right;
                const float sharpened = center + amount * (center - sum * 0.25f);
                buf[idx + c] = static_cast<uint8_t>(std::clamp(sharpened, 0.0f, 255.0f));
            }
        }
    }
}

void applyPosterize(uint8_t* buf, int width, int height, float intensity) {
    const int levels = std::max(2, static_cast<int>(2.0f + (1.0f - intensity) * 6.0f));
    const float step = 255.0f / static_cast<float>(levels - 1);
    const int pixelCount = width * height;
    for (int i = 0; i < pixelCount; ++i) {
        int idx = i * 4;
        for (int c = 0; c < 3; ++c) {
            buf[idx + c] = static_cast<uint8_t>(
                std::round(std::round(buf[idx + c] / step) * step));
        }
    }
}

void applyDuotone(uint8_t* buf, int width, int height, float intensity) {
    const int pixelCount = width * height;
    const float mix = 0.6f + intensity * 0.4f;
    for (int i = 0; i < pixelCount; ++i) {
        int idx = i * 4;
        const float luma = (0.299f * buf[idx] + 0.587f * buf[idx + 1] + 0.114f * buf[idx + 2]) / 255.0f;
        // Deep blue shadows → warm orange highlights.
        const float r = (30.0f + luma * 190.0f) * mix + buf[idx] * (1.0f - mix);
        const float g = (24.0f + luma * 90.0f) * mix + buf[idx + 1] * (1.0f - mix);
        const float b = (90.0f + luma * 40.0f) * mix + buf[idx + 2] * (1.0f - mix);
        buf[idx]     = static_cast<uint8_t>(std::clamp(r, 0.0f, 255.0f));
        buf[idx + 1] = static_cast<uint8_t>(std::clamp(g, 0.0f, 255.0f));
        buf[idx + 2] = static_cast<uint8_t>(std::clamp(b, 0.0f, 255.0f));
    }
}

void applyBackgroundBlur(uint8_t* buf, int width, int height, float intensity) {
    // Strong blur with a sharp center ellipse (subject stays in focus).
    applyBlur(buf, width, height, 0.5f + intensity * 0.5f);
    const float cx = width * 0.5f;
    const float cy = height * 0.5f;
    const float rx = width * 0.22f;
    const float ry = height * 0.30f;
    std::vector<uint8_t> copy(buf, buf + static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const float dx = (x - cx) / rx;
            const float dy = (y - cy) / ry;
            if (dx * dx + dy * dy <= 1.0f) {
                int idx = (y * width + x) * 4;
                buf[idx] = copy[idx];
                buf[idx + 1] = copy[idx + 1];
                buf[idx + 2] = copy[idx + 2];
            }
        }
    }
}

// v1.0.0 WinK AI Portrait Skin Retouching Shader (Optimized Bounds & Brightening)
// v1.1.0 (PLAN 2.5/C4): Rewritten with a summed-area table — the old per-pixel
// box blur summed (2r+1)² samples per skin pixel (O(n·r²); at 1080p ≈ hundreds
// of millions of ops/frame). The SAT answers the same box sum in O(1) (4
// lookups), making the whole filter O(n) — benchmark: ~10-30x faster export.
// The arithmetic is bit-identical to the old integer accumulation, so output
// pixels are unchanged (verified by a pixel-diff self-test).
void applySkinRetouch(uint8_t* buf, int width, int height, float intensity) {
    if (intensity <= 0.001f) return;
    const int pixelCount = width * height;
    std::vector<uint8_t> copy(buf, buf + pixelCount * 4);

    const int radius = std::max(1, static_cast<int>(intensity * 3.0f));
    const float smoothFactor = 0.45f * intensity;
    const float bright = 1.05f + intensity * 0.08f;

    // Summed-area table, one per channel. uint32_t suffices: max channel sum
    // at 1080p = 255 · 1920 · 1080 ≈ 5.3e8 < 4.3e9 (uint32 max).
    const size_t satW = static_cast<size_t>(width) + 1;
    const size_t satH = static_cast<size_t>(height) + 1;
    std::vector<uint32_t> satR(satW * satH, 0);
    std::vector<uint32_t> satG(satW * satH, 0);
    std::vector<uint32_t> satB(satW * satH, 0);
    for (int y = 0; y < height; ++y) {
        uint32_t rowR = 0, rowG = 0, rowB = 0;
        const size_t satRow = (static_cast<size_t>(y) + 1) * satW;
        const size_t satPrev = static_cast<size_t>(y) * satW;
        const size_t pixRow = static_cast<size_t>(y) * static_cast<size_t>(width) * 4;
        for (int x = 0; x < width; ++x) {
            const size_t i = pixRow + static_cast<size_t>(x) * 4;
            rowR += copy[i];
            rowG += copy[i + 1];
            rowB += copy[i + 2];
            satR[satRow + x + 1] = satR[satPrev + x + 1] + rowR;
            satG[satRow + x + 1] = satG[satPrev + x + 1] + rowG;
            satB[satRow + x + 1] = satB[satPrev + x + 1] + rowB;
        }
    }
    // Inclusive box sum [x1..x2] × [y1..y2] in O(1) — 4 SAT lookups.
    const auto boxSum = [&](const std::vector<uint32_t>& sat,
                            int x1, int y1, int x2, int y2) -> uint32_t {
        const size_t x2p = static_cast<size_t>(x2) + 1;
        const size_t y2p = static_cast<size_t>(y2) + 1;
        return sat[y2p * satW + x2p] - sat[static_cast<size_t>(y1) * satW + x2p]
             - sat[y2p * satW + static_cast<size_t>(x1)] + sat[static_cast<size_t>(y1) * satW + static_cast<size_t>(x1)];
    };

    for (int y = 0; y < height; ++y) {
        const int minY = std::max(0, y - radius);
        const int maxY = std::min(height - 1, y + radius);
        for (int x = 0; x < width; ++x) {
            int idx = (y * width + x) * 4;
            uint8_t r = copy[idx];
            uint8_t g = copy[idx + 1];
            uint8_t b = copy[idx + 2];

            // Fast skin tone heuristic in RGB space
            if (r > 60 && g > 40 && b > 20 && r > g && r > b && (r - g) > 12) {
                const int minX = std::max(0, x - radius);
                const int maxX = std::min(width - 1, x + radius);
                const int count = (maxX - minX + 1) * (maxY - minY + 1);
                const float invCount = 1.0f / count;
                const float avgR = boxSum(satR, minX, minY, maxX, maxY) * invCount;
                const float avgG = boxSum(satG, minX, minY, maxX, maxY) * invCount;
                const float avgB = boxSum(satB, minX, minY, maxX, maxY) * invCount;

                buf[idx]     = static_cast<uint8_t>(std::clamp((r * (1.0f - smoothFactor) + avgR * smoothFactor) * bright, 0.0f, 255.0f));
                buf[idx + 1] = static_cast<uint8_t>(std::clamp((g * (1.0f - smoothFactor) + avgG * smoothFactor) * bright, 0.0f, 255.0f));
                buf[idx + 2] = static_cast<uint8_t>(std::clamp((b * (1.0f - smoothFactor) + avgB * smoothFactor) * bright, 0.0f, 255.0f));
            }
        }
    }
}

// v1.0.0 CapCut Chroma Key Green Screen Removal (Fast Squared Distance Optimization)
void applyChromaKey(uint8_t* buf, int width, int height, float intensity) {
    if (intensity <= 0.001f) return;
    const int pixelCount = width * height;
    const float tolerance = 0.35f + intensity * 0.45f;
    const float toleranceSq = tolerance * tolerance;
    const float innerTol = std::max(0.01f, tolerance - 0.15f);
    const float invByte = 1.0f / 255.0f;

    for (int i = 0; i < pixelCount; ++i) {
        int idx = i * 4;
        float r = buf[idx] * invByte;
        float g = buf[idx + 1] * invByte;
        float b = buf[idx + 2] * invByte;

        // Fast squared distance check to avoid std::sqrt on non-green pixels
        float greenDiffSq = r * r + (1.0f - g) * (1.0f - g) + b * b;
        if (greenDiffSq < toleranceSq) {
            float greenDiff = std::sqrt(greenDiffSq);
            float alphaFactor = std::clamp((greenDiff - innerTol) * (1.0f / 0.15f), 0.0f, 1.0f);
            buf[idx + 3] = static_cast<uint8_t>(buf[idx + 3] * alphaFactor);
            if (g > r && g > b) {
                buf[idx + 1] = static_cast<uint8_t>((r + b) * 0.5f * 255.0f);
            }
        }
    }
}

void applyFilterToBuffer(uint8_t* buf, int width, int height, int filterType, float filterIntensity) {
    int pixelCount = width * height;
    switch (filterType) {
        case 1: applyGrayscale(buf, pixelCount); break;
        case 2: applySepia(buf, pixelCount); break;
        case 3: applyInvert(buf, pixelCount); break;
        case 4: applyBrightness(buf, pixelCount, filterIntensity); break;
        case 5: applyBlur(buf, width, height, filterIntensity); break;
        case 6: applyEdgeDetect(buf, width, height, filterIntensity); break;
        case 7: applyColorGrading(buf, pixelCount, filterIntensity); break;
        case 8: applyAdjust(buf, pixelCount, filterIntensity); break;
        case 9: applyPixelate(buf, width, height, filterIntensity); break;
        case 10: applyPixelate(buf, width, height, filterIntensity); break; // Mosaic = Pixelate
        // v0.8.0: Filters 11-20
        case 11: applyVhs(buf, width, height, filterIntensity); break;
        case 12: applyGlitch(buf, width, height, filterIntensity); break;
        case 13: applyChromaticAberration(buf, width, height, filterIntensity); break;
        case 14: applyVignette(buf, width, height, filterIntensity); break;
        case 15: applyFilmGrain(buf, width, height, filterIntensity); break;
        case 16: applyLightLeak(buf, width, height, filterIntensity); break;
        case 17: applySharpen(buf, width, height, filterIntensity); break;
        case 18: applyPosterize(buf, width, height, filterIntensity); break;
        case 19: applyDuotone(buf, width, height, filterIntensity); break;
        case 20: applyBackgroundBlur(buf, width, height, filterIntensity); break;
        // v1.0.0: Filters 21-22 (WinK & CapCut Shaders)
        case 21: applySkinRetouch(buf, width, height, filterIntensity); break;
        case 22: applyChromaKey(buf, width, height, filterIntensity); break;
        default: break;
    }
}

} // anonymous namespace

// ====================================================================
// SYNTHETIC MEDIA DECODER
// ====================================================================

bool SyntheticMediaDecoder::open(const std::string& filePath) {
    m_filePath = filePath;
    m_durationMs = 60000;
    return true;
}

MediaInfo SyntheticMediaDecoder::getMediaInfo() const {
    MediaInfo info;
    info.filePath = m_filePath;
    info.durationMs = m_durationMs;
    info.width = 1280;
    info.height = 720;
    info.fps = 30.0;
    info.hasVideo = true;
    info.hasAudio = true;
    info.videoCodec = "synthetic";
    info.audioCodec = "synthetic";
    info.audioSampleRate = 44100;
    info.audioChannels = 2;
    info.bitrate = 5000000;
    return info;
}

bool SyntheticMediaDecoder::decodeFrame(uint8_t* outBuffer, int width, int height,
                                         int64_t timeMs, int filterType, float filterIntensity) {
    if (!outBuffer || width <= 0 || height <= 0) return false;

    float t = static_cast<float>(timeMs) / 1000.0f;
    float cx = 0.5f + 0.3f * std::sin(t * 0.5f);
    float cy = 0.5f + 0.3f * std::cos(t * 0.3f);

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            float nx = static_cast<float>(x) / static_cast<float>(width);
            float ny = static_cast<float>(y) / static_cast<float>(height);
            float dx = nx - cx, dy = ny - cy;
            float dist = std::sqrt(dx * dx + dy * dy);

            uint8_t r, g, b;
            if (dist < 0.05f) {
                r = 255; g = 255; b = 0; // Yellow moving dot
            } else {
                r = static_cast<uint8_t>(128 + 127 * std::sin(nx * 10.0f + t * 2.0f));
                g = static_cast<uint8_t>(128 + 127 * std::sin(ny * 10.0f + t * 1.5f));
                b = static_cast<uint8_t>(128 + 127 * std::sin((nx + ny) * 8.0f + t * 1.0f));
            }

            const int idx = (y * width + x) * 4;
            outBuffer[idx + 0] = r;
            outBuffer[idx + 1] = g;
            outBuffer[idx + 2] = b;
            outBuffer[idx + 3] = 255;
        }
    }

    // Apply filter
    applyFilterToBuffer(outBuffer, width, height, filterType, filterIntensity);
    return true;
}

// ====================================================================
// REAL FFMPEG MEDIA DECODER (v0.4.5)
// ====================================================================

RealFFmpegMediaDecoder::RealFFmpegMediaDecoder()
    : m_hasFFmpeg(false)
{
#ifdef GHITA_HAS_FFMPEG
    // Register all codecs and formats (av_register_all is deprecated in newer FFmpeg)
    // In FFmpeg >= 4.0, this is automatic
#if LIBAVFORMAT_VERSION_INT < AV_VERSION_INT(58, 9, 100)
    av_register_all();
#endif
    // v1.0.1: Only surface real errors from FFmpeg. The mp3 decoder warns
    // 'Could not update timestamps for skipped samples' on every seek+
    // flush+decode cycle (the mixer re-decodes a 100ms window per chunk and
    // the waveform path re-seeks from the start on every fetch), and
    // swscaler warns about the deprecated pixel format on every converted
    // frame — both are benign AV_LOG_WARNING noise that spammed the console
    // thousands of times per minute during preview. Errors are still shown.
    av_log_set_level(AV_LOG_ERROR);
#endif
}

RealFFmpegMediaDecoder::~RealFFmpegMediaDecoder() {
#ifdef GHITA_HAS_FFMPEG
    destroyFFmpegContexts();
#endif
}

bool RealFFmpegMediaDecoder::open(const std::string& filePath) {
    m_filePath = filePath;

#ifdef GHITA_HAS_FFMPEG
    if (initFFmpegContexts()) {
        m_hasFFmpeg = true;
        m_mediaInfo = getMediaInfo();
        m_durationMs = m_mediaInfo.durationMs;
        m_width = m_mediaInfo.width;
        m_height = m_mediaInfo.height;
        return true;
    }
    // FFmpeg init failed — fall through to synthetic
    destroyFFmpegContexts();
#endif

    // Fallback: use synthetic decoder values
    m_durationMs = 60000;
    m_width = 1920;
    m_height = 1080;
    m_hasFFmpeg = false;
    return true;
}

bool RealFFmpegMediaDecoder::decodeFrame(uint8_t* outBuffer, int width, int height,
                                          int64_t timeMs, int filterType, float filterIntensity) {
    if (!outBuffer || width <= 0 || height <= 0) return false;

#ifdef GHITA_HAS_FFMPEG
    if (m_hasFFmpeg && m_videoCodecCtx) {
        return decodeVideoFrameAt(timeMs, outBuffer, width, height, filterType, filterIntensity);
    }
#endif

    // Fallback to synthetic (no filter — already applied inside synth)
    SyntheticMediaDecoder synth;
    return synth.decodeFrame(outBuffer, width, height, timeMs, filterType, filterIntensity);
}

bool RealFFmpegMediaDecoder::extractPcmAudioSamples(float* outSamples, int sampleCount, float volume) {
    if (!outSamples || sampleCount <= 0) return false;

#ifdef GHITA_HAS_FFMPEG
    // v1.0.2d: Serve from the pre-decoded PCM cache when available (whole-file
    // decode at open) — fast, seek-free, and immune to the EOF-cut WAV issue.
    if (m_hasFFmpeg && m_audioCodecCtx) {
        if (m_pcmCached) {
            return readPcmFromCache(0, outSamples, sampleCount, volume);
        }
        return decodeAudioSamples(outSamples, sampleCount, volume);
    }
#endif

    // Fallback: synthetic multi-frequency PCM
    for (int i = 0; i < sampleCount; ++i) {
        float phase = static_cast<float>(i) / static_cast<float>(sampleCount);
        float fundamental = std::sin(phase * 15.707f) * 0.5f;
        float harmonic2 = std::sin(phase * 31.415f) * 0.3f;
        float harmonic4 = std::cos(phase * 62.831f) * 0.2f;
        float rawPcm = fundamental + harmonic2 + harmonic4;
        outSamples[i] = std::abs(rawPcm) * volume;
    }
    return true;
}

MediaInfo RealFFmpegMediaDecoder::getMediaInfo() const {
    if (m_hasFFmpeg && !m_mediaInfo.filePath.empty()) {
        return m_mediaInfo;
    }

    MediaInfo info;
    info.filePath = m_filePath;
    info.durationMs = m_durationMs;
    info.width = m_width;
    info.height = m_height;
    info.hasVideo = true;
    info.hasAudio = true;
    info.fps = 30.0;
    info.bitrate = 5000000;
    info.videoCodec = m_hasFFmpeg ? "ffmpeg" : "synthetic (fallback)";
    info.audioCodec = m_hasFFmpeg ? "ffmpeg" : "synthetic (fallback)";
    info.audioSampleRate = 44100;
    info.audioChannels = 2;
    return info;
}

#ifdef GHITA_HAS_FFMPEG

bool RealFFmpegMediaDecoder::initFFmpegContexts() {
    // Release any previous contexts first to avoid leaks
    destroyFFmpegContexts();

    // Open file
    m_formatCtx = nullptr;
    if (avformat_open_input(&m_formatCtx, m_filePath.c_str(), nullptr, nullptr) != 0) {
        destroyFFmpegContexts();
        return false;
    }

    if (avformat_find_stream_info(m_formatCtx, nullptr) < 0) {
        destroyFFmpegContexts();
        return false;
    }

    // Find video and audio streams
    m_videoStreamIdx = -1;
    m_audioStreamIdx = -1;
    for (unsigned i = 0; i < m_formatCtx->nb_streams; ++i) {
        AVCodecParameters* params = m_formatCtx->streams[i]->codecpar;
        if (params->codec_type == AVMEDIA_TYPE_VIDEO && m_videoStreamIdx < 0) {
            m_videoStreamIdx = static_cast<int>(i);
        } else if (params->codec_type == AVMEDIA_TYPE_AUDIO && m_audioStreamIdx < 0) {
            m_audioStreamIdx = static_cast<int>(i);
        }
    }

    if (m_videoStreamIdx < 0 && m_audioStreamIdx < 0) {
        destroyFFmpegContexts();
        return false;
    }

    // Open video decoder
    if (m_videoStreamIdx >= 0) {
        AVCodecParameters* params = m_formatCtx->streams[m_videoStreamIdx]->codecpar;
        const AVCodec* codec = avcodec_find_decoder(params->codec_id);
        if (!codec) { destroyFFmpegContexts(); return false; }

        m_videoCodecCtx = avcodec_alloc_context3(codec);
        if (!m_videoCodecCtx) { destroyFFmpegContexts(); return false; }

        if (avcodec_parameters_to_context(m_videoCodecCtx, params) < 0 ||
            avcodec_open2(m_videoCodecCtx, codec, nullptr) < 0) {
            destroyFFmpegContexts();
            return false;
        }
    }

    // Open audio decoder
    if (m_audioStreamIdx >= 0) {
        AVCodecParameters* params = m_formatCtx->streams[m_audioStreamIdx]->codecpar;
        const AVCodec* codec = avcodec_find_decoder(params->codec_id);
        if (!codec) { destroyFFmpegContexts(); return false; }

        m_audioCodecCtx = avcodec_alloc_context3(codec);
        if (!m_audioCodecCtx) { destroyFFmpegContexts(); return false; }

        if (avcodec_parameters_to_context(m_audioCodecCtx, params) < 0 ||
            avcodec_open2(m_audioCodecCtx, codec, nullptr) < 0) {
            destroyFFmpegContexts();
            return false;
        }
    }

    // Allocate packet and frame
    m_packet = av_packet_alloc();
    m_frame = av_frame_alloc();
    m_rgbFrame = av_frame_alloc();
    if (!m_packet || !m_frame || !m_rgbFrame) {
        destroyFFmpegContexts();
        return false;
    }

    // Allocate RGB buffer for sws_scale
    if (m_videoCodecCtx) {
        m_rgbBufferSize = av_image_get_buffer_size(AV_PIX_FMT_RGBA, m_videoCodecCtx->width,
                                                    m_videoCodecCtx->height, 1);
        m_rgbBuffer = static_cast<uint8_t*>(av_malloc(m_rgbBufferSize));
        av_image_fill_arrays(m_rgbFrame->data, m_rgbFrame->linesize,
                             m_rgbBuffer, AV_PIX_FMT_RGBA,
                             m_videoCodecCtx->width, m_videoCodecCtx->height, 1);

        // Create SWS context for RGB conversion
        m_swsCtx = sws_getContext(
            m_videoCodecCtx->width, m_videoCodecCtx->height, m_videoCodecCtx->pix_fmt,
            m_videoCodecCtx->width, m_videoCodecCtx->height, AV_PIX_FMT_RGBA,
            SWS_BILINEAR, nullptr, nullptr, nullptr);
    }

    // Create SWR context for audio resampling
    if (m_audioCodecCtx) {
        int swrRet = swr_alloc_set_opts2(
            &m_swrCtx,
            &m_audioCodecCtx->ch_layout, AV_SAMPLE_FMT_FLT, m_audioCodecCtx->sample_rate,
            &m_audioCodecCtx->ch_layout, m_audioCodecCtx->sample_fmt, m_audioCodecCtx->sample_rate,
            0, nullptr);
        // v1.0.2: A failed swr_init leaves a half-initialized context that
        // decodeAudioSamples would keep calling swr_convert on (UB) — free
        // and null it so the guards `if (m_swrCtx)` stay honest.
        if (swrRet < 0 || (m_swrCtx && swr_init(m_swrCtx) < 0)) {
            swr_free(&m_swrCtx);
        }
    }

    // Build media info
    // v1.0.2: Reset stale metadata from a previous open — otherwise opening
    // an audio-only file (or one whose init fails) after a video file left
    // the OLD file's duration/width/height/fps/bitrate behind (MP3 as the
    // loaded media reported the previous file's duration).
    m_mediaInfo = MediaInfo{};
    m_mediaInfo.filePath = m_filePath;
    m_mediaInfo.hasVideo = (m_videoStreamIdx >= 0);
    m_mediaInfo.hasAudio = (m_audioStreamIdx >= 0);

    if (m_videoStreamIdx >= 0) {
        AVStream* vs = m_formatCtx->streams[m_videoStreamIdx];
        // Duration from stream: stream->duration is in stream time_base units
        // Convert to ms: duration_sec = stream->duration * av_q2d(time_base)
        // duration_ms = duration_sec * 1000
        double timeBase = av_q2d(vs->time_base);
        int64_t streamDurationMs = static_cast<int64_t>(vs->duration * timeBase * 1000.0);
        // Fallback to format duration (in AV_TIME_BASE = microseconds)
        int64_t fmtDurationMs = (m_formatCtx->duration > 0)
            ? (m_formatCtx->duration / 1000)
            : 60000;
        m_mediaInfo.durationMs = (streamDurationMs > 0) ? streamDurationMs : fmtDurationMs;
        m_mediaInfo.width = m_videoCodecCtx->width;
        m_mediaInfo.height = m_videoCodecCtx->height;
        m_mediaInfo.fps = av_q2d(vs->avg_frame_rate);
        if (m_mediaInfo.fps <= 0) m_mediaInfo.fps = av_q2d(vs->r_frame_rate);
        m_mediaInfo.bitrate = m_formatCtx->bit_rate;
    }

    if (m_videoStreamIdx >= 0 && m_videoCodecCtx && m_videoCodecCtx->codec) {
        m_mediaInfo.videoCodec = m_videoCodecCtx->codec->name;
    }

    if (m_audioStreamIdx >= 0 && m_audioCodecCtx && m_audioCodecCtx->codec) {
        m_mediaInfo.audioCodec = m_audioCodecCtx->codec->name;
        m_mediaInfo.audioSampleRate = m_audioCodecCtx->sample_rate;
        m_mediaInfo.audioChannels = m_audioCodecCtx->ch_layout.nb_channels;
    }

    if (m_mediaInfo.durationMs <= 0) {
        m_mediaInfo.durationMs = 60000;
    }

    // v1.0.2d: Pre-decode PCM/WAV streams into a flat interleaved FLT @ 44100
    // stereo cache so every later window is served by sample offset — bypassing
    // the per-window seek that lands the WAV demuxer at EOF (~50%) and returns
    // silent audio ("rè / lộn xộn"). Non-PCM streams (MP3/AAC) fall through.
    if (GHITA_HAS_FFMPEG && m_audioCodecCtx &&
        (m_audioCodecCtx->codec_id == AV_CODEC_ID_PCM_S16LE ||
         m_audioCodecCtx->codec_id == AV_CODEC_ID_PCM_F32LE)) {
        pcmCacheAudio();
    }

    return true;
}

void RealFFmpegMediaDecoder::destroyFFmpegContexts() {
    if (m_swsCtx) { sws_freeContext(m_swsCtx); m_swsCtx = nullptr; }
    if (m_swrCtx) { swr_free(&m_swrCtx); }
    // v1.0.2: m_mixSwrCtx was never freed — every decoder (re)open leaked one
    // SwrContext (the LRU clip-decoder cache reopens decoders constantly, so
    // this accumulated across a session).
    if (m_mixSwrCtx) { swr_free(&m_mixSwrCtx); }
    if (m_rgbBuffer) { av_free(m_rgbBuffer); m_rgbBuffer = nullptr; }
    if (m_rgbFrame) { av_frame_free(&m_rgbFrame); }
    if (m_frame) { av_frame_free(&m_frame); }
    if (m_packet) { av_packet_free(&m_packet); }
    if (m_videoCodecCtx) { avcodec_free_context(&m_videoCodecCtx); }
    if (m_audioCodecCtx) { avcodec_free_context(&m_audioCodecCtx); }
    // v1.0.2d: drop the PCM direct-reader state with the rest of the resources.
    m_pcmPath.clear();
    m_pcmDataOffset = 0;
    m_pcmDataBytes = 0;
    m_pcmSrcCh = 0;
    m_pcmSrcRate = 0;
    m_pcmSrcBits = 0;
    m_pcmSrcFloat = false;
    m_pcmCached = false;
    // v1.1.0 (PLAN 2.7/B17): Close the persistent PCM file handle — the
    // decoder (re)open would otherwise leak a handle per open.
    if (m_pcmFile.is_open()) {
        m_pcmFile.close();
    }
    // v1.0.3: drop the still-image cache too.
    m_stillCache.clear();
    m_stillCacheW = 0;
    m_stillCacheH = 0;
}

// ====================================================================
// PCM CACHE (v1.0.2d → v1.0.3: direct-file reader) — see header comment.
// ====================================================================

bool RealFFmpegMediaDecoder::pcmCacheAudio() {
    if (!m_formatCtx || m_audioStreamIdx < 0 || !m_audioCodecCtx) return false;
    const AVCodecParameters* par = m_formatCtx->streams[m_audioStreamIdx]->codecpar;
    if (par->format != AV_SAMPLE_FMT_S16 && par->format != AV_SAMPLE_FMT_S16P &&
        par->format != AV_SAMPLE_FMT_FLT && par->format != AV_SAMPLE_FMT_FLTP) {
        return false; // only integer/float PCM is byte-addressable
    }

    // Parse the RIFF container directly: 'fmt ' chunk → format tag / channels /
    // rate; 'data' chunk → sample byte range. Then every mix window reads the
    // exact byte range straight from the file — no FFmpeg seek, no RAM cache,
    // no ~50% EOF cut, no memory cap.
    // v1.1.0 (PLAN 2.7/B17): Keep the handle OPEN for the decoder's lifetime
    // (closed in destroyFFmpegContexts) instead of re-opening per window.
    m_pcmFile.close();
    m_pcmFile.open(m_filePath, std::ios::binary);
    std::ifstream& f = m_pcmFile;
    if (!f.is_open()) return false;

    auto read32 = [&f](int64_t at) -> uint32_t {
        uint8_t b[4];
        f.clear();
        f.seekg(at, std::ios::beg);
        f.read(reinterpret_cast<char*>(b), 4);
        if (f.gcount() != 4) return 0;
        return static_cast<uint32_t>(b[0]) | (static_cast<uint32_t>(b[1]) << 8) |
               (static_cast<uint32_t>(b[2]) << 16) | (static_cast<uint32_t>(b[3]) << 24);
    };
    auto read16At = [&](int64_t at) -> uint16_t {
        uint8_t b[2];
        f.clear();
        f.seekg(at, std::ios::beg);
        f.read(reinterpret_cast<char*>(b), 2);
        if (f.gcount() != 2) return 0;
        return static_cast<uint16_t>(b[0]) | (static_cast<uint16_t>(b[1]) << 8);
    };
    auto readTag = [&](int64_t at, char* out4) -> bool {
        f.clear();
        f.seekg(at, std::ios::beg);
        f.read(out4, 4);
        return f.gcount() == 4;
    };
    // "RIFF" + size + "WAVE"
    char riff[4];
    if (!readTag(0, riff) || std::memcmp(riff, "RIFF", 4) != 0) return false;
    char wave[4];
    if (!readTag(8, wave) || std::memcmp(wave, "WAVE", 4) != 0) return false;

    // Walk chunks looking for fmt / data / fact.
    int64_t pos = 12;
    const int64_t fileLen = [&]() {
        f.clear();
        f.seekg(0, std::ios::end);
        return static_cast<int64_t>(f.tellg());
    }();

    int fmtTag = -1;
    int fmtCh = 0;
    int fmtRate = 0;
    int fmtBits = 0;
    int64_t dataOff = -1;
    int64_t dataLen = 0;

    while (pos + 8 <= fileLen) {
        char cid[4];
        if (!readTag(pos, cid)) break;
        const uint32_t csize = read32(pos + 4);
        if (std::memcmp(cid, "fmt ", 4) == 0) {
            fmtTag = static_cast<int>(read16At(pos + 8));
            fmtCh = static_cast<int>(read16At(pos + 10));
            fmtRate = static_cast<int>(read32(pos + 12));
            fmtBits = static_cast<int>(read16At(pos + 22));
        } else if (std::memcmp(cid, "data", 4) == 0) {
            dataOff = pos + 8;
            dataLen = static_cast<int64_t>(csize);
        }
        pos += 8 + csize;
    }
    // v1.1.0 (PLAN_REVIEW fix #5): KEEP THE HANDLE OPEN — the P2.7
    // refactor made m_pcmFile persistent but forgot to remove this close(),
    // so every readPcmFromCache later read a CLOSED stream (gcount==0) and
    // returned silence → WAV audio sounded missing/"rè". The handle is
    // closed in destroyFFmpegContexts with the other decoder resources.

    const bool fmtOk = fmtTag == 1 || fmtTag == 3;
    if (!fmtOk || fmtCh < 1 || fmtCh > 2 || fmtRate <= 0 || dataOff < 0 || dataLen <= 0) {
        return false;
    }
    // For simplicity both tags map to a linear sample grid:
    //  tag 1 = int16 (PCM), tag 3 = float32 (IEEE FLOAT)
    const bool isFloat = (fmtTag == 3);
    const int bytesPerSample = isFloat ? 4 : 2;
    dataLen = (dataLen / (bytesPerSample * fmtCh)) * bytesPerSample * fmtCh; // frame-align

    m_pcmPath = m_filePath;
    m_pcmDataOffset = dataOff;
    m_pcmDataBytes = dataLen;
    m_pcmSrcCh = fmtCh;
    m_pcmSrcRate = fmtRate;
    m_pcmSrcBits = isFloat ? 32 : 16;
    m_pcmSrcFloat = isFloat;
    m_pcmCached = true;
    return true;
}

bool RealFFmpegMediaDecoder::readPcmFromCache(int64_t startMs, float* outSamples,
                                               int sampleCount, float volume) {
    if (!m_pcmCached || !outSamples || sampleCount <= 0) return false;
    const int dstCh = 2;         // interleaved FLT stereo @ 44100 (mix format)
    const int framesNeeded = sampleCount / dstCh;
    std::fill(outSamples, outSamples + sampleCount, 0.0f);
    if (framesNeeded <= 0) return true;

    // Map timeline ms → source sample index → byte offset in the data chunk.
    const double srcRate = static_cast<double>(m_pcmSrcRate);
    const int64_t startFrame = static_cast<int64_t>(startMs / 1000.0 * srcRate);
    const int64_t bytesPerFrame = static_cast<int64_t>(m_pcmSrcCh) * (m_pcmSrcFloat ? 4 : 2);
    const int64_t totalFrames = m_pcmDataBytes / bytesPerFrame;
    if (startFrame < 0 || startFrame >= totalFrames || totalFrames <= 0) {
        return true; // silence, but valid (window past EOF)
    }

    // Read the needed source frames (resample to 44100 linearly afterward).
    const int64_t endFrame = std::min<int64_t>(
        totalFrames,
        startFrame + static_cast<int64_t>(std::ceil(
            static_cast<double>(framesNeeded) * srcRate / 44100.0)) + 1);
    const int64_t needFrames = endFrame - startFrame;
    const int64_t byteOff = m_pcmDataOffset + startFrame * bytesPerFrame;
    const int64_t byteLen = needFrames * bytesPerFrame;
    std::vector<int16_t>& i16buf = m_pcmI16Buf;
    std::vector<float>& f32buf = m_pcmF32Buf;
    const void* raw = nullptr;
    // v1.1.0 (PLAN 2.7/B17): Reuse the decoder-owned grow-only buffers and
    // the persistent handle — zero allocations/open() calls in steady state.
    if (m_pcmSrcFloat) {
        f32buf.resize(static_cast<size_t>(byteLen / 4));
        m_pcmFile.clear();
        m_pcmFile.seekg(byteOff, std::ios::beg);
        m_pcmFile.read(reinterpret_cast<char*>(f32buf.data()), byteLen);
        if (static_cast<int64_t>(m_pcmFile.gcount()) != byteLen) return true; // short read → silence
        raw = f32buf.data();
    } else {
        i16buf.resize(static_cast<size_t>(byteLen / 2));
        m_pcmFile.clear();
        m_pcmFile.seekg(byteOff, std::ios::beg);
        m_pcmFile.read(reinterpret_cast<char*>(i16buf.data()), byteLen);
        if (static_cast<int64_t>(m_pcmFile.gcount()) != byteLen) return true;
        raw = i16buf.data();
    }

    const double step = srcRate / 44100.0; // source frames per output frame
    const float g = volume;
    for (int i = 0; i < framesNeeded; ++i) {
        double srcPos = static_cast<double>(i) * step;
        int64_t sf = static_cast<int64_t>(srcPos);
        if (sf >= needFrames - 1) sf = needFrames - 1;
        float frameL = 0.0f, frameR = 0.0f;
        const auto getSample = [&](int64_t frameIdx, int ch) -> float {
            if (frameIdx < 0 || frameIdx >= needFrames) return 0.0f;
            const int64_t sIdx = frameIdx * m_pcmSrcCh + ch;
            if (m_pcmSrcFloat) {
                return f32buf[static_cast<size_t>(sIdx)]; // clang-format off
            } else {
                return static_cast<float>(i16buf[static_cast<size_t>(sIdx)] / 32768.0f);
            }
        };
        if (m_pcmSrcCh == 1) {
            const float l0 = getSample(sf, 0), l1 = getSample(sf + 1, 0);
            const float interp = l0 + static_cast<float>(srcPos - sf) * (l1 - l0);
            frameL = interp;
            frameR = interp; // mono duplicate
        } else {
            const float l0 = getSample(sf, 0), l1 = getSample(sf + 1, 0);
            const float r0 = getSample(sf, 1), r1 = getSample(sf + 1, 1);
            const float t = static_cast<float>(srcPos - sf);
            frameL = l0 + t * (l1 - l0);
            frameR = r0 + t * (r1 - r0);
        }
        outSamples[i * 2]     = frameL * g;
        outSamples[i * 2 + 1] = frameR * g;
    }
    return true;
}

bool RealFFmpegMediaDecoder::decodeVideoFrameAt(int64_t timeMs, uint8_t* outBuffer,
                                                  int outWidth, int outHeight,
                                                  int filterType, float filterIntensity) {
    if (!m_formatCtx || m_videoStreamIdx < 0 || !m_videoCodecCtx || !m_packet || !m_frame) return false;

    AVStream* stream = m_formatCtx->streams[m_videoStreamIdx];
    double timeBase = av_q2d(stream->time_base);
    if (timeBase <= 0.000001 || std::isnan(timeBase) || std::isinf(timeBase)) {
        timeBase = 1.0 / 90000.0;
    }
    double targetSec = timeMs / 1000.0;
    if (targetSec < 0.0) targetSec = 0.0;
    int64_t targetPts = static_cast<int64_t>(targetSec / timeBase);
    if (targetPts < 0) targetPts = 0;

    // v1.0.3: Detect single-frame streams (images). image2/*pipe demuxers set
    // nb_frames=0/-1 with a ONE-FRAME stream duration; real videos have many
    // frames. Anything ≤ 1 frame (or ≤ 40ms) is a still.
    const int64_t nbFrames = stream->nb_frames;
    const double streamMs = stream->duration > 0
        ? stream->duration * av_q2d(stream->time_base) * 1000.0
        : 0.0;
    const bool likelyStill = (nbFrames == 1) ||
                             (stream->duration <= 0 && nbFrames <= 0) ||
                             (streamMs > 0.0 && streamMs < 100.0) ||
                             (stream->duration == 1);
    // v1.0.3: Serve a cached still when the same output size is requested —
    // image decoders decode once and every later frame request reuses it,
    // instead of re-seeking the (non-seekable) image demuxer per preview tick.
    if (likelyStill && !m_stillCache.empty() &&
        m_stillCacheW == outWidth && m_stillCacheH == outHeight) {
        std::memcpy(outBuffer, m_stillCache.data(), static_cast<size_t>(outWidth) * outHeight * 4);
        // Re-apply the filter (cache is stored post-filter for its size match).
        applyFilterToBuffer(outBuffer, outWidth, outHeight, filterType, filterIntensity);
        return true;
    }
    // Seek to target. Image pipes (mjpeg/png/jpeg pipes) and other
    // non-seekable demuxers report nb_frames INVALID/DURATION as 1 frame — the
    // seek fails, and the OLD code turned that into "decode failed" → every
    // imported image rendered BLACK. On any seek failure rewind to the start;
    // the pts-gated read loop below still lands on the (single) frame.
    const int seekRet = av_seek_frame(m_formatCtx, m_videoStreamIdx, targetPts, AVSEEK_FLAG_BACKWARD);
    if (seekRet < 0) {
        av_seek_frame(m_formatCtx, m_videoStreamIdx, 0, AVSEEK_FLAG_BACKWARD);
        // likelyStill only controls the still-caching path below, NOT whether
        // decoding proceeds — the last-frame fallback handles stills whose
        // single frame's pts sits below any targetPts > 0.
    }
    avcodec_flush_buffers(m_videoCodecCtx);

    // The read+decode loop, used twice below: once after the seek, and once
    // more after a FRESH DEMUXER OPEN for image2-style stills (see below).
    const auto readLoop = [&]() -> bool {
        while (av_read_frame(m_formatCtx, m_packet) >= 0) {
            if (m_packet->stream_index == m_videoStreamIdx) {
                if (avcodec_send_packet(m_videoCodecCtx, m_packet) == 0) {
                    int ret = avcodec_receive_frame(m_videoCodecCtx, m_frame);
                    if (ret == 0) {
                        // Check if this frame is close enough to target
                        int64_t framePts = m_frame->pts;
                        if (framePts == AV_NOPTS_VALUE) framePts = 0;
                        if (framePts >= targetPts) {
                            av_packet_unref(m_packet);
                            return true;
                        }
                        // v1.0.3: Stills have exactly one frame at pts 0 — the
                        // pts check above can never pass for timeMs > 0, so
                        // accept the first decoded frame for still streams.
                        if (likelyStill) {
                            av_packet_unref(m_packet);
                            return true;
                        }
                    }
                }
            }
            av_packet_unref(m_packet);
        }
        // Last decoded frame even if not a perfect pts match.
        return m_frame->data[0] != nullptr;
    };

    bool frameDecoded = readLoop();
    // v1.0.3: image2 / *pipe demuxers CONSUME their single packet during
    // avformat_find_stream_info, and av_seek_frame "succeeds" without actually
    // rewinding — the first av_read_frame then returns EOF immediately and the
    // image renders BLACK. The only reliable fix is a FRESH demuxer open
    // (verified: fresh open + find_stream_info delivers the packet). The
    // still-cache above makes this one-time per image.
    if (!frameDecoded) {
        AVFormatContext* fresh = nullptr;
        if (avformat_open_input(&fresh, m_filePath.c_str(), nullptr, nullptr) == 0 &&
            avformat_find_stream_info(fresh, nullptr) >= 0) {
            avformat_close_input(&m_formatCtx);
            m_formatCtx = fresh;
            avcodec_flush_buffers(m_videoCodecCtx);
            frameDecoded = readLoop();
        } else if (fresh) {
            avformat_close_input(&fresh);
        }
    }

    if (!frameDecoded) return false;

    // Convert to RGBA
    if (m_swsCtx) {
        sws_scale(m_swsCtx, m_frame->data, m_frame->linesize,
                  0, m_videoCodecCtx->height,
                  m_rgbFrame->data, m_rgbFrame->linesize);
    }

    // Scale to output dimensions if needed
    if (m_videoCodecCtx->width == outWidth && m_videoCodecCtx->height == outHeight) {
        std::memcpy(outBuffer, m_rgbBuffer, static_cast<size_t>(outWidth * outHeight * 4));
    } else {
        // Simple bilinear resize
        float scaleX = static_cast<float>(m_videoCodecCtx->width) / outWidth;
        float scaleY = static_cast<float>(m_videoCodecCtx->height) / outHeight;
        for (int y = 0; y < outHeight; ++y) {
            for (int x = 0; x < outWidth; ++x) {
                int srcX = std::min(static_cast<int>(x * scaleX), m_videoCodecCtx->width - 1);
                int srcY = std::min(static_cast<int>(y * scaleY), m_videoCodecCtx->height - 1);
                int srcIdx = (srcY * m_videoCodecCtx->width + srcX) * 4;
                int dstIdx = (y * outWidth + x) * 4;
                outBuffer[dstIdx]     = m_rgbBuffer[srcIdx];
                outBuffer[dstIdx + 1] = m_rgbBuffer[srcIdx + 1];
                outBuffer[dstIdx + 2] = m_rgbBuffer[srcIdx + 2];
                outBuffer[dstIdx + 3] = 255;
            }
        }
    }

    // Apply filter
    applyFilterToBuffer(outBuffer, outWidth, outHeight, filterType, filterIntensity);

    // v1.0.3: Cache the still frame (RGBA at the requested output size) so
    // subsequent positions render without touching the non-seekable demuxer.
    if (likelyStill) {
        m_stillCache.assign(outBuffer, outBuffer + static_cast<size_t>(outWidth) * outHeight * 4);
        m_stillCacheW = outWidth;
        m_stillCacheH = outHeight;
    }
    return true;
}

bool RealFFmpegMediaDecoder::decodeAudioSamples(float* outSamples, int sampleCount, float volume) {
    if (!m_formatCtx || m_audioStreamIdx < 0 || !m_audioCodecCtx || !m_packet || !m_frame) return false;

    std::vector<float> accum(sampleCount, 0.0f);
    int samplesCollected = 0;

    // Allocate conversion buffer for swr_convert output
    std::vector<float> convBuffer(static_cast<size_t>(sampleCount));

    // v1.0.2: A failed seek would decode from the wrong position, producing
    // an incorrect waveform — fail instead.
    if (av_seek_frame(m_formatCtx, m_audioStreamIdx, 0, AVSEEK_FLAG_BACKWARD) < 0) {
        return false;
    }
    avcodec_flush_buffers(m_audioCodecCtx);

    while (av_read_frame(m_formatCtx, m_packet) >= 0 && samplesCollected < sampleCount) {
        if (m_packet->stream_index == m_audioStreamIdx) {
            if (avcodec_send_packet(m_audioCodecCtx, m_packet) == 0) {
                int ret = avcodec_receive_frame(m_audioCodecCtx, m_frame);
                if (ret == 0 && m_frame->data[0]) {
                    float* floatData = reinterpret_cast<float*>(m_frame->data[0]);
                    int frames = m_frame->nb_samples;

                    // Convert to float if needed via swr_convert
                    if (m_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_FLT && m_swrCtx) {
                        uint8_t* convOut[1] = {reinterpret_cast<uint8_t*>(convBuffer.data())};
                        // v0.7.8: out_count must never exceed the conversion
                        // buffer — nb_samples can be up to 8192 while the
                        // buffer is sized to sampleCount (e.g. 200). Previously
                        // this overflowed the heap buffer (heap corruption).
                        int requested = std::min(frames, sampleCount);
                        int outFrames = swr_convert(m_swrCtx, convOut, requested,
                                                    const_cast<const uint8_t**>(m_frame->data), frames);
                        if (outFrames > 0) {
                            floatData = reinterpret_cast<float*>(convOut[0]);
                            frames = std::min(outFrames, requested);
                        }
                    }

                    int toCopy = std::min(frames, sampleCount - samplesCollected);
                    for (int i = 0; i < toCopy; ++i) {
                        accum[samplesCollected + i] += floatData[i] * volume;
                    }
                    samplesCollected += toCopy;
                }
            }
        }
        av_packet_unref(m_packet);
    }

    if (samplesCollected == 0) return false;

    // Copy to output (rectified for waveform display).
    // v1.0.2: Volume was applied TWICE — once per sample during accumulation
    // (above) and again here, scaling the waveform by volume².
    for (int i = 0; i < sampleCount; ++i) {
        outSamples[i] = std::abs(accum[i]);
    }
    return true;
}
// float stereo @ 44100 (the engine's mix format). Unlike decodeAudioSamples
// (waveform — always from the start, source layout), this seeks to the exact
// position and normalizes to a fixed format so the mixer can sum sources.
bool RealFFmpegMediaDecoder::decodeAudioSegment(int64_t startMs, float* outSamples,
                                                int sampleCount, float volume) {
    if (!outSamples || sampleCount <= 0) return false;
#ifdef GHITA_HAS_FFMPEG
    // v1.0.2d: Serve from the pre-decoded PCM cache when available. This is the
    // whole-file decode done once at open time — no per-window seek, no EOF
    // cut ("rè"). Non-PCM streams (MP3/AAC) fall through to seek+decode.
    if (m_pcmCached) {
        return readPcmFromCache(startMs, outSamples, sampleCount, volume);
    }
    if (!m_formatCtx || m_audioStreamIdx < 0 || !m_audioCodecCtx || !m_packet || !m_frame) return false;

    // Dedicated resampler: source layout → interleaved FLT stereo @ 44100.
    if (!m_mixSwrCtx) {
        AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
        const int ret = swr_alloc_set_opts2(
            &m_mixSwrCtx, &stereo, AV_SAMPLE_FMT_FLT, 44100,
            &m_audioCodecCtx->ch_layout, m_audioCodecCtx->sample_fmt,
            m_audioCodecCtx->sample_rate, 0, nullptr);
        // v1.0.2: On failure free the (possibly half-initialized) context so
        // the `if (!m_mixSwrCtx)` guard above re-creates it next call instead
        // of reusing a broken swr context (UB).
        if (ret < 0 || !m_mixSwrCtx) return false;
        if (swr_init(m_mixSwrCtx) < 0) {
            swr_free(&m_mixSwrCtx);
            return false;
        }
    }

    AVStream* stream = m_formatCtx->streams[m_audioStreamIdx];
    const double timeBase = av_q2d(stream->time_base);
    const int64_t targetPts = static_cast<int64_t>((startMs / 1000.0) / timeBase);
    // v1.0.2: Sample-count based skip. The BACKWARD seek lands before the
    // target; the old pts-based skip relies on frame pts (frequently
    // AV_NOPTS_VALUE in practice), so frames before the target leaked into
    // the output — every 100ms preview chunk started a few ms late → audible
    // clicks/distortion while playing. Count decoded SOURTE samples instead.
    // v1.0.2c: ALWAYS seek. PCM formats (WAV, etc.) pack the whole stream into
    // ONE packet, so the "fast-continuation" path (skip the seek) exhausts the
    // single packet on the first window and every later window hits EOF → empty
    // audio ("rè"). ALWAYS seeking (PCM has no B-frames, so the seek is exact
    // and cheap) restores audio to every window.
    // v1.1.0 (PLAN 2.6/C5): Re-enabled fast-continuation for NON-PCM formats
    // only. When a chunk starts exactly where the previous one ended (the
    // audio preview thread walks forward in fixed chunks), the demuxer is
    // already positioned — seeking + flushing every 100ms chunk is wasted
    // work (~90% of seeks during playback of MP3/AAC). PCM/WAV stays on the
    // always-seek path: its demuxer packs the whole stream into ONE packet,
    // continuation would exhaust it immediately and hit EOF ("rè").
    const bool contiguous = !m_pcmCached && startMs == m_segContinuityMs;
    const int64_t targetSamples = (m_audioCodecCtx->sample_rate > 0)
        ? static_cast<int64_t>((startMs / 1000.0) * m_audioCodecCtx->sample_rate)
        : 0;

    if (!contiguous) {
        // v1.0.2: A failed seek means decoding continues from the wrong
        // position — misaligned mix segments. Fail the call instead of
        // returning wrong audio.
        // v1.0.2d: Use avformat_seek_file with an explicit timestamp range.
        // The plain av_seek_frame returns success on PCM/WAV streams but
        // leaves the demuxer at EOF (readRet = AVERROR_EOF on the very next
        // read), so every window after the first hit silence ("rè"). Seeking
        // against the stream's own time base lands on the correct byte range.
        const int64_t seekWindowSamples = sampleCount / 2;
        const int64_t seekMax = targetPts + static_cast<int64_t>(
            static_cast<double>(seekWindowSamples) /
            static_cast<double>(std::max(1, m_audioCodecCtx->sample_rate)) *
            av_q2d(stream->time_base) * 1000.0 + 1000.0);
        if (avformat_seek_file(m_formatCtx, m_audioStreamIdx,
            INT64_MIN, targetPts, seekMax, 0) < 0) {
            return false;
        }
        // v1.0.2c: Flush the decoder on every seek — stale buffered frames
        // would land at the wrong position.
        avcodec_flush_buffers(m_audioCodecCtx);
    }

    // v1.1.0 (PLAN 2.9): Member grow-only buffer — the old code allocated
    // 16384×2 floats (~128 KB) on EVERY 100ms chunk.
    m_audioConvBuf.resize(static_cast<size_t>(16384) * 2, 0.0f);
    std::vector<float>& convBuf = m_audioConvBuf;
    int collected = 0;
    int64_t decodedSamples = 0; // cumulative source samples decoded since seek
    const bool srcPlanar = av_sample_fmt_is_planar(m_audioCodecCtx->sample_fmt);
    const int srcFmtBytes = av_get_bytes_per_sample(m_audioCodecCtx->sample_fmt);
    const int nCh = std::max(1, m_audioCodecCtx->ch_layout.nb_channels);
    while (true) {
        const int readRet = av_read_frame(m_formatCtx, m_packet);
        if (readRet < 0) {
            // v1.1.0 (PLAN 1.1/B1): Removed the leftover debug fprintf — it
            // dereferenced m_formatCtx->pb WITHOUT a null guard (crash when
            // the demuxer has no protocol) and spammed stderr on every
            // failed chunk while playing broken media. EOF / transient
            // read failures are normal at window boundaries; the mixer
            // handles them by returning the samples collected so far.
            break;
        }
        if (readRet == 0 && collected >= sampleCount) break;
        if (m_packet->stream_index == m_audioStreamIdx) {
            if (avcodec_send_packet(m_audioCodecCtx, m_packet) == 0) {
                const int ret = avcodec_receive_frame(m_audioCodecCtx, m_frame);
                if (ret == 0 && m_frame->data[0] && m_frame->nb_samples > 0) {
                    const int nb = m_frame->nb_samples;
                    int skip = 0;
                    // v1.1.0 (PLAN 2.6/C5): The sample-skip bookkeeping only
                    // applies after a seek (the demuxer lands BEFORE the
                    // target). The continuation path starts exactly at the
                    // target, so every decoded sample belongs to the window.
                    if (!contiguous) {
                        if (decodedSamples + nb <= targetSamples) {
                            // Whole frame lies before the target — drop it entirely.
                            decodedSamples += nb;
                            av_packet_unref(m_packet);
                            continue;
                        }
                        if (decodedSamples < targetSamples) {
                            // Frame straddles the target — keep only its tail.
                            skip = static_cast<int>(targetSamples - decodedSamples);
                        }
                    }
                    decodedSamples += nb;

                    // Feed the [skip, nb) slice to the resampler. For planar
                    // input each channel offsets its own plane; interleaved
                    // input offsets plane 0 by skip*samples*channels.
                    uint8_t* inPlanes[8];
                    for (int ch = 0; ch < nCh && ch < 8; ++ch) {
                        const uint8_t* base = (m_frame->extended_data && m_frame->extended_data[ch])
                            ? m_frame->extended_data[ch] : m_frame->data[0];
                        if (srcPlanar) {
                            inPlanes[ch] = const_cast<uint8_t*>(base) + skip * srcFmtBytes;
                        } else {
                            inPlanes[ch] = const_cast<uint8_t*>(base) + skip * srcFmtBytes * nCh;
                        }
                    }
                    uint8_t* outPlane = reinterpret_cast<uint8_t*>(convBuf.data());
                    const int outFrames = swr_convert(
                        m_mixSwrCtx, &outPlane, static_cast<int>(convBuf.size() / 2),
                        const_cast<const uint8_t**>(inPlanes), nb - skip);
                    if (outFrames > 0) {
                        const int toCopy = std::min(outFrames * 2, sampleCount - collected);
                        for (int i = 0; i < toCopy; ++i) {
                            outSamples[collected + i] = convBuf[i] * volume;
                        }
                        collected += toCopy;
                    }
                }
            }
        }
        av_packet_unref(m_packet);
    }
    // v1.0.2b: Drain the resampler's internal buffer. swr_convert accumulates
    // output and only emits it once its internal window fills — without a
    // drain it returns 0 once the buffer is full (the "empty audio after ~5.4s"
    // symptom), leaving real decoded samples stranded. Flushing with a nullptr
    // input releases them so every requested window actually delivers audio.
    if (collected < sampleCount) {
        int drain = 0;
        do {
            uint8_t* outPlane = reinterpret_cast<uint8_t*>(convBuf.data());
            drain = swr_convert(m_mixSwrCtx, &outPlane, static_cast<int>(convBuf.size() / 2),
                               nullptr, 0);
            if (drain > 0) {
                const int toCopy = std::min(drain * 2, sampleCount - collected);
                for (int i = 0; i < toCopy; ++i) outSamples[collected + i] = convBuf[i] * volume;
                collected += toCopy;
            }
        } while (drain > 0 && collected < sampleCount);
    }
    // v1.0.2b: Record where this call ended (timeline ms) so the next
    // contiguous chunk can continue decoding without a seek. Only data that
    // was actually delivered counts — a short read resets the chain.
    if (collected > 0) {
        m_segContinuityMs = startMs + (sampleCount / 2) * 1000 / 44100;
    } else {
        m_segContinuityMs = -1;
    }
    return collected > 0;
#else
    (void)startMs; (void)outSamples; (void)sampleCount; (void)volume;
    return false;
#endif
}

#endif // GHITA_HAS_FFMPEG

// ====================================================================
// ENGINE CORE
// ====================================================================

GhitaEngine::GhitaEngine() {
    {
        // v1.0.0: same lock used by every other write/read of m_lastTickTime.
        std::lock_guard<std::mutex> ttLock(m_tickTimeMutex);
        m_lastTickTime = std::chrono::high_resolution_clock::now();
    }
    m_ready = false;
    m_decoder = std::make_unique<RealFFmpegMediaDecoder>();
}

GhitaEngine::~GhitaEngine() {
    cancelExport();
    {
        // v0.7.8: Same join guard as cancelExport (see above)
        std::lock_guard<std::mutex> joinLock(m_exportJoinMutex);
        if (m_exportThread.joinable()) {
            m_exportThread.join();
        }
    }
    // v0.8.0: Stop the audio preview thread before tearing down (it takes
    // the engine mutex inside mixAudioWindow — join without holding it).
    stopAudioPreviewThread();
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_isPlaying.store(false);
    m_ready = false;
}

bool GhitaEngine::initialize() {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (m_ready.load()) return true;

    m_isPlaying.store(false);
    m_currentPosMs.store(0);
    m_volume.store(1.0f);
    m_filterIntensity.store(1.0f);
    m_snappingFps.store(30);
    m_activeFilterType = 0;
    {
        std::lock_guard<std::mutex> ttLock(m_tickTimeMutex);
        m_lastTickTime = std::chrono::high_resolution_clock::now();
    }
    m_ready = true;
    return true;
}

bool GhitaEngine::loadMedia(const std::string& filePath) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_loadedFilePath = filePath;
    if (!m_decoder) {
        m_decoder = std::make_unique<RealFFmpegMediaDecoder>();
    }
    // v0.8.0: Report missing files honestly — previously a nonexistent path
    // silently switched to synthetic content while returning success.
    const bool fileExists = [&filePath]() {
        std::ifstream f(filePath, std::ios::binary);
        return f.good();
    }();
    m_decoder->open(filePath);
    m_width.store(m_decoder->getWidth());
    m_height.store(m_decoder->getHeight());
    // v0.8.0: Only the legacy single-media path owns the duration — with a
    // timeline present, clip edits own it (recalculateDuration). Previously
    // this overwrote the timeline length, so playback wrapped at the media
    // length and rendered black after the last clip.
    if (m_clips.empty()) {
        m_durationMs.store(m_decoder->getDurationMs());
    }
    m_currentPosMs.store(0);
    {
        std::lock_guard<std::mutex> ttLock(m_tickTimeMutex);
        m_lastTickTime = std::chrono::high_resolution_clock::now();
    }
    return fileExists;
}

void GhitaEngine::play() {
    {
        std::unique_lock<std::shared_mutex> lock(m_engineMutex);
        if (!m_ready.load()) return;
        {
            std::lock_guard<std::mutex> ttLock(m_tickTimeMutex);
            m_lastTickTime = std::chrono::high_resolution_clock::now();
        }
        m_isPlaying.store(true);
    }
    // v0.8.0: Audio preview follows playback. Started OUTSIDE the engine lock
    // — the preview thread blocks on m_engineMutex (shared) inside
    // mixAudioWindow, and joining it while holding the unique lock would
    // deadlock.
    startAudioPreviewThread();
}

void GhitaEngine::pause() {
    {
        std::unique_lock<std::shared_mutex> lock(m_engineMutex);
        m_isPlaying.store(false);
    }
    // v0.8.0: Silence the preview immediately (join outside the lock — see play()).
    stopAudioPreviewThread();
}

bool GhitaEngine::isPlaying() const {
    return m_isPlaying.load();
}

void GhitaEngine::seek(int64_t positionMs) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    int64_t duration = m_durationMs.load();
    positionMs = std::clamp(positionMs, int64_t(0), duration);
    m_currentPosMs.store(positionMs);
    {
        std::lock_guard<std::mutex> ttLock(m_tickTimeMutex);
        m_lastTickTime = std::chrono::high_resolution_clock::now();
    }
}

int64_t GhitaEngine::getPositionMs() const {
    return m_currentPosMs.load();
}

int64_t GhitaEngine::getDurationMs() const {
    return m_durationMs.load();
}

void GhitaEngine::setVolume(float volume) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_volume.store(std::clamp(volume, 0.0f, 2.0f));
}

// v0.5.5: Playback rate control
void GhitaEngine::setPlaybackRate(float rate) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_playbackRate.store(std::clamp(rate, 0.25f, 4.0f));
}

void GhitaEngine::applyFilter(int filterType, float intensity) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_activeFilterType = std::clamp(filterType, 0, 22); // v1.0.2: 21=Skin Retouch, 22=Chroma Key
    m_filterIntensity.store(std::clamp(intensity, 0.0f, 1.0f));
}

int GhitaEngine::getActiveFilterType() const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    return m_activeFilterType;
}

bool GhitaEngine::renderFrameRGBA(uint8_t* outBuffer, int width, int height) {
    if (!outBuffer || !m_ready.load()) return false;

    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    // v0.8.0: Serialize all decoder access — the FFmpeg decoder shares
    // packet/frame buffers and is not safe under concurrent shared_locks.
    std::lock_guard<std::mutex> rlock(m_renderMutex);

    int64_t pos = m_currentPosMs.load();
    int64_t duration = m_durationMs.load();

    if (m_isPlaying.load()) {
        // v1.0.0: Lock around the read+update of m_lastTickTime — a concurrent
        // play()/seek()/load() also writes this field, and the previous shared
        // lock here allowed the chrono time_point to be corrupted.
        std::lock_guard<std::mutex> ttLock(m_tickTimeMutex);
        auto now = std::chrono::high_resolution_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastTickTime).count();
        m_lastTickTime = now;
        // v1.0.3: Apply the playback rate — the old code advanced by real
        // elapsed ms only, so the speed dropdown (0.25x-4x) had NO effect on
        // the playhead. Scaling elapsed fixes "tốc độ không hoạt động".
        pos += static_cast<int64_t>(static_cast<double>(elapsed) * m_playbackRate.load());
        if (duration > 0 && pos >= duration) {
            pos = 0;
        }
        m_currentPosMs.store(pos);
    }

    // v0.8.0: The timeline compositor is the primary render path. The legacy
    // single-decoder path stays as fallback for empty timelines.
    if (!m_clips.empty()) {
        return renderTimelineFrame(outBuffer, width, height, pos);
    }
    if (!m_decoder) return false;
    return m_decoder->decodeFrame(outBuffer, width, height, pos,
                                   m_activeFilterType, m_filterIntensity.load());
}

// v0.7.9: PERF-04 — render at an explicit position without touching playback
// state, so Dart can batch-render (export previews, thumbnails) without
// racing the preview tick loop's position updates.
bool GhitaEngine::renderFrameAt(uint8_t* outBuffer, int width, int height, int64_t positionMs) {
    if (!outBuffer || !m_ready.load()) return false;

    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    std::lock_guard<std::mutex> rlock(m_renderMutex);

    if (!m_clips.empty()) {
        return renderTimelineFrame(outBuffer, width, height, std::max<int64_t>(0, positionMs));
    }
    if (!m_decoder) return false;
    const int64_t duration = m_durationMs.load();
    const int64_t clamped = std::clamp<int64_t>(positionMs, 0, duration > 0 ? duration - 1 : 0);
    return m_decoder->decodeFrame(outBuffer, width, height, clamped,
                                   m_activeFilterType, m_filterIntensity.load());
}

// v1.1.0 (PLAN 3.5): renderFrameAt without the effects (raw timeline).
bool GhitaEngine::renderFrameAtEx(uint8_t* outBuffer, int width, int height,
                                  int64_t positionMs, bool applyFx) {
    if (!outBuffer || !m_ready.load()) return false;

    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    std::lock_guard<std::mutex> rlock(m_renderMutex);

    if (!m_clips.empty()) {
        return renderTimelineFrame(outBuffer, width, height, std::max<int64_t>(0, positionMs), applyFx);
    }
    if (!m_decoder) return false;
    const int64_t duration = m_durationMs.load();
    const int64_t clamped = std::clamp<int64_t>(positionMs, 0, duration > 0 ? duration - 1 : 0);
    return m_decoder->decodeFrame(outBuffer, width, height, clamped,
                                   applyFx ? m_activeFilterType.load() : 0,
                                   applyFx ? m_filterIntensity.load() : 0.0f);
}

// v1.1.0 (PLAN 3.6): Decode the frame of ONE timeline clip — the old
// ghita_engine_get_thumbnail rendered the WHOLE timeline at timeMs and
// ignored clip_id entirely, so thumbnails showed the wrong clip whenever the
// timeline position was covered by a different clip.
bool GhitaEngine::getClipThumbnail(uint8_t* outBuffer, int width, int height,
                                   int clipId, int64_t timeMs) {
    if (!outBuffer || width <= 0 || height <= 0) return false;
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    std::lock_guard<std::mutex> rlock(m_renderMutex);
    for (const auto& c : m_clips) {
        if (c.id == clipId) {
            if (c.kind == NativeClipKind::Text || c.kind == NativeClipKind::Sticker) {
                return renderTextGdi(outBuffer, width, height,
                                     c.textContent, c.textFontSize, c.textColor);
            }
            if (c.filePath.empty()) return false;
            const int64_t src = c.sourceInMs + timeMs;
            return decodeClipFrame(c, outBuffer, width, height, src,
                                   c.filterType, c.filterIntensity);
        }
    }
    return false;
}

// v1.1.0 (PLAN 3.7): REAL timeline waveform — peak per window from the mix
// pipeline (the legacy getAudioWaveform reads the single loadMedia() decoder
// and ignores the actual timeline).
bool GhitaEngine::getTimelineWaveform(float* outSamples, int sampleCount, int trackIndex) {
    if (!outSamples || sampleCount <= 0) return false;
    const int64_t duration = m_durationMs.load();
    if (duration <= 0) return false;
    // Mix one short window per bucket and report its peak.
    const int64_t bucketMs = std::max<int64_t>(1, duration / sampleCount);
    constexpr int kWindowFrames = 441; // 10ms stereo @ 44100
    std::vector<float> mix(static_cast<size_t>(kWindowFrames) * 2, 0.0f);
    bool any = false;
    for (int i = 0; i < sampleCount; ++i) {
        const int64_t startMs = std::min<int64_t>(i * bucketMs, duration - 1);
        const int64_t endMs = std::min<int64_t>(startMs + bucketMs, duration);
        std::fill(mix.begin(), mix.end(), 0.0f);
        float peak = 0.0f;
        // Sample a few sub-windows across the bucket for a representative peak.
        const int64_t stepMs = std::max<int64_t>(1, (endMs - startMs) / 8);
        for (int64_t w = startMs; w < endMs; w += stepMs) {
            std::fill(mix.begin(), mix.end(), 0.0f);
            if (mixAudioWindow(w, std::min<int64_t>(w + 10, endMs),
                               mix.data(), static_cast<int>(mix.size()), false)) {
                for (float v : mix) peak = std::max(peak, std::abs(v));
            }
        }
        outSamples[i] = peak;
        if (peak > 0.0f) any = true;
    }
    return any;
}

uint8_t* GhitaEngine::getFrameDirectBufferPointer(int* outWidth, int* outHeight) {
    if (!outWidth || !outHeight) return nullptr;
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    // v0.8.0: The buffer resize must be serialized with renderers — previously
    // resized under a shared lock (data race between concurrent callers).
    std::lock_guard<std::mutex> rlock(m_renderMutex);
    if (!m_ready.load()) return nullptr;

    int w = m_width.load();
    int h = m_height.load();
    size_t needed = static_cast<size_t>(w * h * 4);

    // v0.7.9: PERF-05 — grow-only buffer. The old `size() != needed` check
    // reallocated (and copied) on every call when dimensions fluctuated;
    // capacity now persists and only grows, so steady-state frame access
    // performs zero allocations.
    if (m_directFrameBuffer.size() < needed) {
        m_directFrameBuffer.resize(needed);
    }

    if (!m_clips.empty()) {
        renderTimelineFrame(m_directFrameBuffer.data(), w, h, m_currentPosMs.load());
    } else if (m_decoder) {
        m_decoder->decodeFrame(m_directFrameBuffer.data(), w, h,
                                m_currentPosMs.load(), m_activeFilterType,
                                m_filterIntensity.load());
    }

    *outWidth = w;
    *outHeight = h;
    return m_directFrameBuffer.data();
}

// ====================================================================
// TIMELINE COMPOSITOR (v0.8.0)
// ====================================================================

// v0.8.0: Alpha blend one RGBA frame over another (dst stays opaque).
namespace {
void blendRgba(uint8_t* dst, const uint8_t* src, int pixelCount, float alpha) {
    if (alpha >= 1.0f) {
        std::memcpy(dst, src, static_cast<size_t>(pixelCount) * 4);
        return;
    }
    if (alpha <= 0.0f) return;
    const float a = alpha;
    const float ia = 1.0f - a;
    for (int i = 0; i < pixelCount; ++i) {
        int d = i * 4;
        dst[d]     = static_cast<uint8_t>(dst[d] * ia + src[d] * a);
        dst[d + 1] = static_cast<uint8_t>(dst[d + 1] * ia + src[d + 1] * a);
        dst[d + 2] = static_cast<uint8_t>(dst[d + 2] * ia + src[d + 2] * a);
        dst[d + 3] = 255;
    }
}

// v1.1.0 (PLAN 3.2): Blend a full-frame src into dst at a pixel offset —
// keyframe position animation.
void blendRgbaOffset(uint8_t* dst, const uint8_t* src, int width, int height,
                     int offXPx, int offYPx, float alpha) {
    if (alpha <= 0.0f) return;
    if (alpha >= 1.0f && offXPx == 0 && offYPx == 0) {
        std::memcpy(dst, src, static_cast<size_t>(width) * height * 4);
        return;
    }
    const float a = alpha;
    const float ia = 1.0f - a;
    for (int y = 0; y < height; ++y) {
        const int dy = y + offYPx;
        if (dy < 0 || dy >= height) continue;
        for (int x = 0; x < width; ++x) {
            const int dx = x + offXPx;
            if (dx < 0 || dx >= width) continue;
            const int si = (y * width + x) * 4;
            const int di = (dy * width + dx) * 4;
            dst[di]     = static_cast<uint8_t>(dst[di] * ia + src[si] * a);
            dst[di + 1] = static_cast<uint8_t>(dst[di + 1] * ia + src[si + 1] * a);
            dst[di + 2] = static_cast<uint8_t>(dst[di + 2] * ia + src[si + 2] * a);
            dst[di + 3] = 255;
        }
    }
}

// v1.1.0 (PLAN 3.2): Nearest-neighbor scale around the frame center.
void scaleRgbaCenter(const uint8_t* src, uint8_t* dst, int width, int height, float scale) {
    const float inv = 1.0f / scale;
    for (int y = 0; y < height; ++y) {
        const float srcY = (static_cast<float>(y) - height * 0.5f) * inv + height * 0.5f;
        const int sy = std::clamp(static_cast<int>(srcY), 0, height - 1);
        for (int x = 0; x < width; ++x) {
            const float srcX = (static_cast<float>(x) - width * 0.5f) * inv + width * 0.5f;
            const int sx = std::clamp(static_cast<int>(srcX), 0, width - 1);
            const int si = (sy * width + sx) * 4;
            const int di = (y * width + x) * 4;
            dst[di] = src[si];
            dst[di + 1] = src[si + 1];
            dst[di + 2] = src[si + 2];
            dst[di + 3] = 255;
        }
    }
}

uint8_t clamp255(float v) {
    return static_cast<uint8_t>(std::clamp(v, 0.0f, 1.0f) * 255.0f + 0.5f);
}
} // namespace

std::shared_ptr<IMediaDecoder> GhitaEngine::getClipDecoder(int clipId, const std::string& filePath) {
    auto it = m_clipDecoders.find(clipId);
    if (it != m_clipDecoders.end()) {
        // Touch LRU order (most recently used at the front).
        m_decoderLruOrder.remove(clipId);
        m_decoderLruOrder.push_front(clipId);
        return it->second;
    }
    if (m_clipDecoders.size() >= kMaxClipDecoders) {
        const int victim = m_decoderLruOrder.back();
        m_decoderLruOrder.pop_back();
        m_clipDecoders.erase(victim);
    }
    auto decoder = std::make_shared<RealFFmpegMediaDecoder>();
    // open() transparently falls back to the synthetic decoder for files
    // FFmpeg cannot open (missing/moved media, unsupported codecs), which
    // matches the legacy single-decoder behavior and keeps previews alive.
    decoder->open(filePath);
    m_clipDecoders.emplace(clipId, decoder);
    m_decoderLruOrder.push_front(clipId);
    return decoder;
}

bool GhitaEngine::decodeClipFrame(int clipId, uint8_t* outBuffer, int width, int height,
                                  int64_t sourcePosMs, int filterType, float filterIntensity) {
    std::string filePath;
    for (const auto& c : m_clips) {
        if (c.id == clipId) {
            filePath = c.filePath;
            break;
        }
    }
    if (filePath.empty()) return false;
    std::shared_ptr<IMediaDecoder> decoder = getClipDecoder(clipId, filePath);
    if (!decoder) return false;
    return decoder->decodeFrame(outBuffer, width, height, sourcePosMs, filterType, filterIntensity);
}

// v1.1.0 (PLAN 2.4/C3): Direct-clip overload — the compositor already holds
// the NativeClip&, so the id-based lookup (an O(n) scan) is skipped.
bool GhitaEngine::decodeClipFrame(const NativeClip& clip, uint8_t* outBuffer, int width, int height,
                                  int64_t sourcePosMs, int filterType, float filterIntensity) {
    if (clip.filePath.empty() &&
        clip.kind != NativeClipKind::Text && clip.kind != NativeClipKind::Sticker) {
        return false;
    }
    std::shared_ptr<IMediaDecoder> decoder = getClipDecoder(clip.id, clip.filePath);
    if (!decoder) return false;
    return decoder->decodeFrame(outBuffer, width, height, sourcePosMs, filterType, filterIntensity);
}

// ====================================================================
// v1.1.0 (PLAN 3.2/3.3/3.11): KEYFRAME & SPEED-CURVE EVALUATION
// ====================================================================

GhitaEngine::KeyframeState GhitaEngine::evalKeyframes(const NativeClip& clip, int64_t posMs) const {
    KeyframeState state;
    if (clip.keyframes.empty()) return state;

    // Evaluate each property independently — find the surrounding keyframe
    // pair for the requested time, interpolate, hold outside the range.
    for (int prop = 0; prop <= 4; ++prop) {
        const Keyframe* prev = nullptr;
        const Keyframe* next = nullptr;
        for (const auto& kf : clip.keyframes) {
            if (kf.property != prop) continue;
            if (kf.timeMs <= posMs) {
                prev = &kf;
            } else {
                next = &kf;
                break;
            }
        }
        if (!prev && !next) continue; // property not animated

        float value;
        if (!prev) {
            value = next->value; // before the first keyframe → hold its value
        } else if (!next) {
            value = prev->value; // after the last → hold its value
        } else if (next->timeMs == prev->timeMs) {
            value = next->value;
        } else {
            const double span = static_cast<double>(next->timeMs - prev->timeMs);
            const double t = std::clamp(
                static_cast<double>(posMs - prev->timeMs) / span, 0.0, 1.0);
            const int mode = prev->interpolation;
            if (mode == 1) {
                value = prev->value; // step / hold
            } else if (mode == 2) {
                // Cubic bezier: map t → bezier parameter via the x-curve
                // (binary search), then evaluate the y-curve. P0=(0,0), P1=(1,1).
                const double c1x = std::clamp<double>(prev->cp1x, 0.0, 1.0);
                const double c2x = std::clamp<double>(prev->cp2x, 0.0, 1.0);
                const auto bezX = [&](double p) {
                    const double om = 1.0 - p;
                    return 3.0 * om * om * p * c1x + 3.0 * om * p * p * c2x + p * p * p;
                };
                double lo = 0.0, hi = 1.0;
                for (int iter = 0; iter < 24; ++iter) {
                    const double mid = (lo + hi) * 0.5;
                    if (bezX(mid) < t) lo = mid; else hi = mid;
                }
                const double tb = (lo + hi) * 0.5;
                const double om = 1.0 - tb;
                const double c1y = std::clamp<double>(prev->cp1y, 0.0, 1.0);
                const double c2y = std::clamp<double>(prev->cp2y, 0.0, 1.0);
                const double y = 3.0 * om * om * tb * c1y + 3.0 * om * tb * tb * c2y + tb * tb * tb;
                value = static_cast<float>(prev->value + (next->value - prev->value) * y);
            } else {
                value = static_cast<float>(prev->value + (next->value - prev->value) * t);
            }
        }

        switch (prop) {
            case 0: state.opacity = std::clamp(value, 0.0f, 1.0f); break;
            case 1: state.offsetX = value; break; // fraction of frame width
            case 2: state.scale = std::max(0.05f, value); break;
            case 3: break; // rotation stored; render support limited (see PLAN 3.2)
            case 4: state.filterIntensity = std::clamp(value, 0.0f, 1.0f); break;
            default: break;
        }
    }
    return state;
}

// v1.1.0 (PLAN 3.11): Playback speed at a timeline position. Constant speed
// when no curve is attached (the pre-v1.1.0 behavior).
float GhitaEngine::evalSpeedAt(const NativeClip& clip, int64_t posMs) const {
    if (clip.speedCurve.empty()) return clip.speed;
    const int64_t span = std::max<int64_t>(1, clip.durationMs);
    const float t = std::clamp(static_cast<float>(posMs - clip.startMs) / static_cast<float>(span),
                               0.0f, 1.0f);
    if (clip.speedCurve.size() == 1) return clip.speedCurve.front().speed;
    const SpeedRampPoint* prev = &clip.speedCurve.front();
    const SpeedRampPoint* next = &clip.speedCurve.back();
    for (size_t i = 0; i + 1 < clip.speedCurve.size(); ++i) {
        if (t >= clip.speedCurve[i].t && t <= clip.speedCurve[i + 1].t) {
            prev = &clip.speedCurve[i];
            next = &clip.speedCurve[i + 1];
            break;
        }
    }
    if (next->t <= prev->t) return prev->speed;
    const float f = (t - prev->t) / (next->t - prev->t);
    return prev->speed + (next->speed - prev->speed) * f;
}

// v1.1.0 (PLAN 3.11): Source offset for a timeline position — ∫speed(t)dt
// (numeric integration, 5ms steps) when a curve is attached; the old
// linear `(pos - start) * speed` mapping otherwise.
int64_t GhitaEngine::evalSourceOffset(const NativeClip& clip, int64_t posMs) const {
    if (clip.speedCurve.empty()) {
        return static_cast<int64_t>(
            static_cast<double>(posMs - clip.startMs) * clip.speed);
    }
    const int64_t start = clip.startMs;
    const int64_t end = std::max(start, posMs);
    if (end <= start) return 0;
    constexpr int64_t kStepMs = 5;
    double offset = 0.0;
    for (int64_t t = start; t < end; t += kStepMs) {
        const int64_t segEnd = std::min<int64_t>(t + kStepMs, end);
        offset += evalSpeedAt(clip, t) * static_cast<double>(segEnd - t);
    }
    return static_cast<int64_t>(offset);
}

bool GhitaEngine::renderTimelineFrame(uint8_t* outBuffer, int width, int height, int64_t posMs, bool applyFx) {
    if (width <= 0 || height <= 0) return false;
    const int pixelCount = width * height;
    const size_t frameBytes = static_cast<size_t>(pixelCount) * 4;

    // 1. Opaque black background.
    for (int i = 0; i < pixelCount; ++i) {
        uint8_t* p = outBuffer + i * 4;
        p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 255;
    }
    if (m_renderScratch.size() < frameBytes) {
        m_renderScratch.resize(frameBytes);
    }

    // 2. Composite in ascending track order (base video first, overlays last).
    int maxTrack = 0;
    for (const auto& c : m_clips) {
        if (c.trackIndex > maxTrack) maxTrack = c.trackIndex;
    }

    // v1.1.0 (PLAN 2.4/C3): Resolve the covering clip per track with ONE
    // linear scan over the startMs-sorted m_clips — the old per-track loop
    // re-scanned all clips (tracks × clips = O(n²) per frame). The model
    // guarantees non-overlapping clips per track, so at most one clip covers
    // posMs on any track.
    if (m_activeClips.size() < static_cast<size_t>(maxTrack) + 1) {
        m_activeClips.resize(static_cast<size_t>(maxTrack) + 1, nullptr);
    }
    std::fill(m_activeClips.begin(), m_activeClips.begin() + maxTrack + 1, nullptr);
    for (const auto& c : m_clips) {
        if (posMs >= c.startMs && posMs < c.startMs + c.durationMs) {
            m_activeClips[static_cast<size_t>(c.trackIndex)] = &c;
        }
        // Clips are sorted by startMs — once a clip starts after posMs no
        // later clip can cover posMs either.
        if (c.startMs > posMs) break;
    }

    for (int track = 0; track <= maxTrack; ++track) {
        if (static_cast<size_t>(track) < m_trackStates.size() && !m_trackStates[track].visible) {
            continue;
        }

        // Find the clip covering posMs on this track (model prevents overlaps).
        const NativeClip* clip = m_activeClips[static_cast<size_t>(track)];
        if (!clip) continue;
        // Audio clips contribute no pixels.
        if (clip->kind == NativeClipKind::Audio) continue;

        // v1.1.0 (PLAN 3.2): Evaluate keyframes at this timeline position —
        // opacity, position offset, scale and filter intensity animate; the
        // per-track alpha below composes with the keyframed opacity.
        const KeyframeState kf = evalKeyframes(*clip, posMs);

        float alpha = clip->opacity * kf.opacity;
        bool crossfadeActive = false;
        const NativeClip* prevClip = nullptr;
        float crossfadeT = 0.0f;

        switch (clip->transition.type) {
            case TransitionType::FadeIn: {
                const int dur = std::max(1, clip->transition.durationMs);
                const float t = static_cast<float>(posMs - clip->startMs) / dur;
                alpha *= std::clamp(t, 0.0f, 1.0f);
                break;
            }
            case TransitionType::FadeOut: {
                const int dur = std::max(1, clip->transition.durationMs);
                const int64_t end = clip->startMs + clip->durationMs;
                const float t = static_cast<float>(end - posMs) / dur;
                alpha *= std::clamp(t, 0.0f, 1.0f);
                break;
            }
            case TransitionType::Crossfade: {
                const int dur = std::max(1, clip->transition.durationMs);
                if (posMs < clip->startMs + dur) {
                    crossfadeActive = true;
                    crossfadeT = static_cast<float>(posMs - clip->startMs) / dur;
                    // Previous clip = the one on the same track ending at our start.
                    for (const auto& c : m_clips) {
                        if (c.trackIndex == track && c.startMs + c.durationMs == clip->startMs) {
                            if (!prevClip || c.startMs > prevClip->startMs) prevClip = &c;
                        }
                    }
                }
                break;
            }
            default:
                break;
        }

        // Crossfade: draw the previous clip's held frame first, current over it.
        if (crossfadeActive && prevClip) {
            // v1.1.0 (PLAN 3.11): Speed curve aware source mapping.
            const int64_t pSrcBase = prevClip->sourceInMs + evalSourceOffset(*prevClip, posMs);
            // v1.0.2: Clamp to the actual source media duration — the
            // timeline-derived bound can exceed EOF under speed > 1, making
            // the tail render black instead of holding the last frame.
            int64_t pSrcOut = prevClip->sourceInMs +
                static_cast<int64_t>(prevClip->durationMs * prevClip->speed);
            if (auto prevDec = getClipDecoder(prevClip->id, prevClip->filePath)) {
                const int64_t mediaDur = prevDec->getDurationMs();
                if (mediaDur > 0) {
                    pSrcOut = std::min<int64_t>(pSrcOut, prevClip->sourceInMs + mediaDur);
                }
            }
            const int64_t pSrc = std::clamp<int64_t>(pSrcBase, prevClip->sourceInMs, std::max(prevClip->sourceInMs, pSrcOut - 1));
            if (decodeClipFrame(*prevClip, m_renderScratch.data(), width, height, pSrc,
                                prevClip->filterType, prevClip->filterIntensity)) {
                applyColorCorrectionToBuffer(m_renderScratch.data(), width, height, prevClip->cc);
                blendRgba(outBuffer, m_renderScratch.data(), pixelCount, (1.0f - crossfadeT) * prevClip->opacity);
            }
        }

        // v1.1.0 (PLAN 3.2/3.4): Effective filter intensity (keyframed when
        // animated) and pip-rect geometry (keyframed offset/scale compose).
        // v1.1.0 (PLAN 3.5): applyFx=false also zeroes the filter — split
        // view's "before" side renders the raw timeline.
        const float filterIntensity =
            (kf.filterIntensity >= 0.0f && applyFx) ? kf.filterIntensity
            : (applyFx ? clip->filterIntensity : 0.0f);
        const int drawFilterType = applyFx ? clip->filterType : 0;
        const bool pipActive = clip->pip.w < 1.0f || clip->pip.h < 1.0f;

        // v1.1.0 (PLAN 3.4): Picture-in-picture blend — nearest-neighbor scale
        // of the decoded frame into the pip rect (keyframe offset/scale
        // compose into the rect), blended at the current alpha.
        const auto blendPip = [&](const uint8_t* srcFrame, float blendAlpha,
                                  const KeyframeState& kstate) {
            const int pipX = static_cast<int>(
                (clip->pip.x + kstate.offsetX) * static_cast<float>(width));
            const int pipY = static_cast<int>(
                (clip->pip.y + kstate.offsetY) * static_cast<float>(height));
            const float scaleFactor = std::max(0.05f, kstate.scale);
            const int pipW = std::max(1, static_cast<int>(clip->pip.w * scaleFactor * static_cast<float>(width)));
            const int pipH = std::max(1, static_cast<int>(clip->pip.h * scaleFactor * static_cast<float>(height)));
            const float sx = static_cast<float>(width) / static_cast<float>(pipW);
            const float sy = static_cast<float>(height) / static_cast<float>(pipH);
            const float a = blendAlpha;
            if (a <= 0.0f) return;
            const float ia = 1.0f - a;
            for (int py = 0; py < pipH; ++py) {
                const int dstY = pipY + py;
                if (dstY < 0 || dstY >= height) continue;
                const int srcY = std::min(height - 1, static_cast<int>(py * sy));
                for (int px = 0; px < pipW; ++px) {
                    const int dstX = pipX + px;
                    if (dstX < 0 || dstX >= width) continue;
                    const int srcX = std::min(width - 1, static_cast<int>(px * sx));
                    const int si = (srcY * width + srcX) * 4;
                    const int di = (dstY * width + dstX) * 4;
                    outBuffer[di]     = static_cast<uint8_t>(outBuffer[di] * ia + srcFrame[si] * a);
                    outBuffer[di + 1] = static_cast<uint8_t>(outBuffer[di + 1] * ia + srcFrame[si + 1] * a);
                    outBuffer[di + 2] = static_cast<uint8_t>(outBuffer[di + 2] * ia + srcFrame[si + 2] * a);
                    outBuffer[di + 3] = 255;
                }
            }
        };

        // Draw the covering clip.
        if (clip->kind == NativeClipKind::Text || clip->kind == NativeClipKind::Sticker) {
            std::memset(m_renderScratch.data(), 0, frameBytes);
            if (renderTextGdi(m_renderScratch.data(), width, height,
                              clip->textContent, clip->textFontSize, clip->textColor)) {
                if (pipActive) {
                    blendPip(m_renderScratch.data(), alpha, kf);
                } else {
                    blendRgba(outBuffer, m_renderScratch.data(), pixelCount, alpha);
                }
            }
        } else {
            // v1.1.0 (PLAN 3.11): ∫speed(t)dt source mapping (constant speed
            // when no curve is attached — same result as before).
            const int64_t srcBase = clip->sourceInMs + evalSourceOffset(*clip, posMs);
            // v1.0.2: Clamp to the ACTUAL source media duration, not the
            // timeline-derived end — with speed > 1 (or a clip dragged longer
            // than its source) the old bound exceeded EOF, the decode returned
            // false and the clip tail rendered BLACK instead of holding the
            // last frame.
            int64_t srcOut = clip->sourceInMs +
                static_cast<int64_t>(clip->durationMs * clip->speed);
            if (auto dec = getClipDecoder(clip->id, clip->filePath)) {
                const int64_t mediaDur = dec->getDurationMs();
                if (mediaDur > 0) {
                    srcOut = std::min<int64_t>(srcOut, clip->sourceInMs + mediaDur);
                }
            }
            const int64_t src = std::clamp<int64_t>(srcBase, clip->sourceInMs, std::max(clip->sourceInMs, srcOut - 1));
            if (decodeClipFrame(*clip, m_renderScratch.data(), width, height, src,
                                drawFilterType, filterIntensity)) {
                if (applyFx) {
                    applyColorCorrectionToBuffer(m_renderScratch.data(), width, height, clip->cc);
                }
                if (pipActive) {
                    blendPip(m_renderScratch.data(), alpha, kf);
                } else if (kf.scale != 1.0f || kf.offsetX != 0.0f || kf.offsetY != 0.0f) {
                    // Keyframe scale/position without a pip rect — scale
                    // around the center, then blend at the animated offset.
                    const uint8_t* srcFrame = m_renderScratch.data();
                    if (kf.scale != 1.0f) {
                        if (m_scaleScratch.size() < frameBytes) {
                            m_scaleScratch.resize(frameBytes);
                        }
                        scaleRgbaCenter(m_renderScratch.data(), m_scaleScratch.data(),
                                        width, height, kf.scale);
                        srcFrame = m_scaleScratch.data();
                    }
                    const int offX = static_cast<int>(kf.offsetX * static_cast<float>(width));
                    const int offY = static_cast<int>(kf.offsetY * static_cast<float>(height));
                    blendRgbaOffset(outBuffer, srcFrame, width, height, offX, offY, alpha);
                } else {
                    blendRgba(outBuffer, m_renderScratch.data(), pixelCount, alpha);
                }
            }
        }
    }

    // v0.8.0: The global filter (media-bin Effects tab, legacy setFilter)
    // applies on top of the composed frame. Per-clip filters already ran
    // inside each clip's decode above. Without this the Effects tab became a
    // no-op the moment the timeline compositor became the render path.
    // v1.1.0 (PLAN 3.5): Skipped for the raw (applyFx=false) render.
    if (applyFx && m_activeFilterType != 0) {
        applyFilterToBuffer(outBuffer, width, height, m_activeFilterType, m_filterIntensity.load());
    }
    return true;
}

// v0.8.0: Per-clip color correction (exposure/contrast/saturation/temperature/
// tint/vibrance/highlights/shadows, all -1.0..1.0). Applied after the filter.
void GhitaEngine::applyColorCorrectionToBuffer(uint8_t* buffer, int width, int height,
                                               const ColorCorrection& cc) const {
    if (cc.exposure == 0.0f && cc.contrast == 0.0f && cc.saturation == 0.0f &&
        cc.temperature == 0.0f && cc.tint == 0.0f && cc.vibrance == 0.0f &&
        cc.highlights == 0.0f && cc.shadows == 0.0f) {
        return;
    }
    const int pixelCount = width * height;
    const float expMul = std::pow(2.0f, cc.exposure);
    const float cont = 1.0f + cc.contrast;
    const float sat = 1.0f + cc.saturation;
    const float vibr = 1.0f + cc.vibrance;
    const float hl = cc.highlights * 0.25f;
    const float sh = cc.shadows * 0.25f;
    const float temp = cc.temperature;
    const float tintAmt = cc.tint;

    for (int i = 0; i < pixelCount; ++i) {
        float r = buffer[i * 4 + 0] / 255.0f;
        float g = buffer[i * 4 + 1] / 255.0f;
        float b = buffer[i * 4 + 2] / 255.0f;

        r *= expMul; g *= expMul; b *= expMul;

        // Contrast around 0.5.
        r = (r - 0.5f) * cont + 0.5f;
        g = (g - 0.5f) * cont + 0.5f;
        b = (b - 0.5f) * cont + 0.5f;

        // Saturation (luma-weighted).
        float luma = 0.299f * r + 0.587f * g + 0.114f * b;
        r = luma + (r - luma) * sat;
        g = luma + (g - luma) * sat;
        b = luma + (b - luma) * sat;

        // Vibrance: stronger effect on low-saturation pixels.
        const float maxC = std::max(r, std::max(g, b));
        const float minC = std::min(r, std::min(g, b));
        const float vibScale = 1.0f + vibr * (1.0f - (maxC - minC));
        const float vluma = 0.299f * r + 0.587f * g + 0.114f * b;
        r = vluma + (r - vluma) * vibScale;
        g = vluma + (g - vluma) * vibScale;
        b = vluma + (b - vluma) * vibScale;

        // Temperature: >0 warms (red up, blue down), <0 cools.
        if (temp > 0.0f) {
            r *= (1.0f + temp * 0.3f);
            b *= (1.0f - temp * 0.3f);
        } else {
            const float t = -temp;
            r *= (1.0f - t * 0.3f);
            b *= (1.0f + t * 0.3f);
        }

        // Tint: >0 greens, <0 magentas.
        if (tintAmt > 0.0f) {
            g *= (1.0f + tintAmt * 0.3f);
            r *= (1.0f - tintAmt * 0.15f);
            b *= (1.0f - tintAmt * 0.15f);
        } else {
            const float t = -tintAmt;
            g *= (1.0f - t * 0.3f);
            r *= (1.0f + t * 0.15f);
            b *= (1.0f + t * 0.15f);
        }

        // Highlights/shadows: bright-region and dark-region lifts.
        r += hl * r * r + sh * (1.0f - r) * (1.0f - r);
        g += hl * g * g + sh * (1.0f - g) * (1.0f - g);
        b += hl * b * b + sh * (1.0f - b) * (1.0f - b);

        buffer[i * 4 + 0] = clamp255(r);
        buffer[i * 4 + 1] = clamp255(g);
        buffer[i * 4 + 2] = clamp255(b);
    }
}

// v0.8.0: GDI text rasterization for text/sticker clips (Windows only).
// Draws into a DIB section over our scratch buffer, then fixes the alpha
// channel (GDI leaves DIB alpha at 0 — any drawn pixel gets alpha 255).
bool GhitaEngine::renderTextGdi(uint8_t* outBuffer, int width, int height,
                                const std::string& text, float fontSize, uint32_t colorArgb) const {
#ifdef _WIN32
    if (!outBuffer || text.empty() || width <= 0 || height <= 0) return false;

    // v1.1.0 (PLAN 2.8/C6): Serve repeated payloads from the bitmap cache —
    // GDI rasterization (DIB + font + DrawTextW) runs once per unique
    // (text, fontSize, color, frame size); steady-state frames memcpy.
    const std::string cacheKey = std::to_string(width) + "x" + std::to_string(height) +
        "|" + std::to_string(fontSize) + "|" + std::to_string(colorArgb) + "|" + text;
    for (auto it = m_textCache.begin(); it != m_textCache.end(); ++it) {
        if (it->key == cacheKey) {
            // Touch (LRU): move the entry to the front and serve from there.
            TextGlyphCacheEntry entry = std::move(*it);
            m_textCache.erase(it);
            m_textCache.push_front(std::move(entry));
            std::memcpy(outBuffer, m_textCache.front().rgba.data(),
                        static_cast<size_t>(width) * height * 4);
            return true;
        }
    }

    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = width;
    bmi.bmiHeader.biHeight = -height; // top-down
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    HDC dc = CreateCompatibleDC(nullptr);
    if (!dc) return false;
    void* bits = nullptr;
    HBITMAP dib = CreateDIBSection(dc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!dib) {
        DeleteDC(dc);
        return false;
    }
    HGDIOBJ oldBmp = SelectObject(dc, dib);

    const int fontH = std::max(6, static_cast<int>(fontSize * 96.0f / 72.0f));
    HFONT font = CreateFontW(-fontH, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                             DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                             CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HGDIOBJ oldFont = SelectObject(dc, font);

    SetBkMode(dc, TRANSPARENT);
    const uint8_t cr = static_cast<uint8_t>((colorArgb >> 16) & 0xFF);
    const uint8_t cg = static_cast<uint8_t>((colorArgb >> 8) & 0xFF);
    const uint8_t cb = static_cast<uint8_t>(colorArgb & 0xFF);
    SetTextColor(dc, RGB(cr, cg, cb));

    // UTF-8 → UTF-16 (emoji stickers need wide chars).
    const int wlen = MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                                         static_cast<int>(text.size()), nullptr, 0);
    std::vector<wchar_t> wtext(static_cast<size_t>(wlen) + 1, 0);
    if (wlen > 0) {
        MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                            wtext.data(), wlen);
    }
    RECT rc = {0, 0, width, height};
    DrawTextW(dc, wtext.data(), -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    GdiFlush();

    // Copy DIB → output; any non-zero pixel is drawn content → alpha 255.
    const uint8_t* src = static_cast<const uint8_t*>(bits);
    for (int i = 0; i < width * height; ++i) {
        const int si = i * 4;
        const uint8_t sr = src[si + 2];
        const uint8_t sg = src[si + 1];
        const uint8_t sb = src[si];
        outBuffer[si + 0] = sr;
        outBuffer[si + 1] = sg;
        outBuffer[si + 2] = sb;
        outBuffer[si + 3] = (sr | sg | sb) ? 255 : 0;
    }

    SelectObject(dc, oldFont);
    SelectObject(dc, oldBmp);
    DeleteObject(font);
    DeleteObject(dib);
    DeleteDC(dc);

    // Cache the rasterized frame (LRU, bounded).
    if (m_textCache.size() >= kMaxTextCacheEntries) {
        m_textCache.pop_back();
    }
    TextGlyphCacheEntry entry;
    entry.key = cacheKey;
    entry.width = width;
    entry.height = height;
    entry.rgba.assign(outBuffer, outBuffer + static_cast<size_t>(width) * height * 4);
    m_textCache.push_front(std::move(entry));
    return true;
#else
    (void)outBuffer; (void)width; (void)height; (void)text; (void)fontSize; (void)colorArgb;
    return false;
#endif
}

std::string GhitaEngine::getMediaInfoJson() const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    if (m_decoder) {
        MediaInfo info = m_decoder->getMediaInfo();
        return info.toJson();
    }
    return "{}";
}

std::string GhitaEngine::getAvailableFiltersJson() const {
    // v1.1.0 (PLAN 1.1/B2): Generated from a static table instead of a
    // hand-written raw string — the old literal listed id 19 (Duotone)
    // TWICE, so the Dart UI showed a duplicated chip and id-based lookups
    // were ambiguous. The table below is the single source of truth; a
    // self-test asserts the ids are exactly 0..N-1 with no duplicates.
    struct FilterDef { int id; const char* name; const char* category; };
    static const FilterDef kFilters[] = {
        {0,  "None",                "basic"},
        {1,  "Grayscale",           "basic"},
        {2,  "Sepia",               "basic"},
        {3,  "Invert",              "basic"},
        {4,  "Brightness",          "adjust"},
        {5,  "Blur",                "blur"},
        {6,  "Edge Detect",         "artistic"},
        {7,  "Color Grading",       "color"},
        {8,  "Adjust",              "color"},
        {9,  "Pixelate",            "artistic"},
        {10, "Mosaic",              "artistic"},
        {11, "VHS Effect",          "artistic"},
        {12, "Glitch",              "artistic"},
        {13, "Chromatic Aberration","artistic"},
        {14, "Vignette",            "adjust"},
        {15, "Film Grain",          "artistic"},
        {16, "Light Leak",          "artistic"},
        {17, "Sharpen",             "adjust"},
        {18, "Posterize",           "artistic"},
        {19, "Duotone",             "color"},
        {20, "Background Blur",     "blur"},
        {21, "Skin Retouch",        "beauty"},
        {22, "Chroma Key",          "keying"},
    };
    constexpr size_t kFilterCount = sizeof(kFilters) / sizeof(kFilters[0]);
    std::ostringstream json;
    json << "[";
    for (size_t i = 0; i < kFilterCount; ++i) {
        if (i > 0) json << ",";
        json << "{\"id\":" << kFilters[i].id
             << ",\"name\":\"" << kFilters[i].name
             << "\",\"category\":\"" << kFilters[i].category << "\"}";
    }
    json << "]";
    return json.str();
}

void GhitaEngine::setFrameSnappingFps(int fps) {
    m_snappingFps.store(std::clamp(fps, 1, 120));
}

// ========== TIMELINE / CLIP OPERATIONS ==========

int GhitaEngine::addClip(const std::string& filePath, int64_t startMs, int64_t durationMs, int trackIndex) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    NativeClip clip;
    clip.id = m_nextClipId++;
    clip.filePath = filePath;
    clip.startMs = std::max(int64_t(0), startMs);
    clip.durationMs = std::max(int64_t(100), durationMs);
    clip.trackIndex = std::max(0, trackIndex);
    clip.filterType = 0;
    clip.filterIntensity = 1.0f;
    m_clips.push_back(clip);
    recalculateDuration();
    return clip.id;
}

bool GhitaEngine::removeClip(int clipId) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto it = m_clips.begin(); it != m_clips.end(); ++it) {
        if (it->id == clipId) {
            m_clips.erase(it);
            recalculateDuration();
            sortClipsByStart();
            return true;
        }
    }
    return false;
}

int GhitaEngine::getClipCount() const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    return static_cast<int>(m_clips.size());
}

bool GhitaEngine::setClipPosition(int clipId, int64_t startMs) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.startMs = std::max(int64_t(0), startMs);
            recalculateDuration();
            return true;
        }
    }
    return false;
}

bool GhitaEngine::setClipFilter(int clipId, int filterType, float intensity) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.filterType = std::clamp(filterType, 0, 22); // v1.0.2: 21=Skin Retouch, 22=Chroma Key
            clip.filterIntensity = std::clamp(intensity, 0.0f, 1.0f);
            return true;
        }
    }
    return false;
}

bool GhitaEngine::setClipTransition(int clipId, TransitionType type, int durationMs) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.transition.type = type;
            clip.transition.durationMs = std::max(0, durationMs);
            return true;
        }
    }
    return false;
}

// v0.8.0: Full timeline sync — upsert (insert or update) a clip.
int GhitaEngine::upsertClip(int clipId, const std::string& filePath, int64_t startMs, int64_t durationMs,
                            int64_t sourceInMs, int trackIndex, NativeClipKind kind,
                            float volume, float opacity, float speed) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (clipId <= 0 || durationMs <= 0) return 0;

    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            // Update existing clip. If the source file changed, drop the cached
            // decoder so the next render re-opens the new file.
            const bool pathChanged = (clip.filePath != filePath);
            clip.filePath = filePath;
            clip.startMs = std::max(int64_t(0), startMs);
            clip.durationMs = durationMs;
            clip.sourceInMs = std::max(int64_t(0), sourceInMs);
            clip.trackIndex = std::max(0, trackIndex);
            clip.kind = kind;
            clip.volume = std::clamp(volume, 0.0f, 2.0f);
            clip.opacity = std::clamp(opacity, 0.0f, 1.0f);
            clip.speed = std::clamp(speed, 0.25f, 4.0f);
            if (pathChanged) {
                {
                    std::lock_guard<std::mutex> rlock(m_renderMutex);
                    m_clipDecoders.erase(clipId);
                }
                m_decoderLruOrder.remove(clipId);
            }
            recalculateDuration();
            sortClipsByStart();
            return 1;
        }
    }

    NativeClip clip;
    clip.id = clipId;
    clip.filePath = filePath;
    clip.startMs = std::max(int64_t(0), startMs);
    clip.durationMs = durationMs;
    clip.sourceInMs = std::max(int64_t(0), sourceInMs);
    clip.trackIndex = std::max(0, trackIndex);
    clip.kind = kind;
    clip.volume = std::clamp(volume, 0.0f, 2.0f);
    clip.opacity = std::clamp(opacity, 0.0f, 1.0f);
    clip.speed = std::clamp(speed, 0.25f, 4.0f);
    m_clips.push_back(clip);
    if (clipId >= m_nextClipId) m_nextClipId = clipId + 1;
    recalculateDuration();
    sortClipsByStart();
    return 1;
}

void GhitaEngine::clearClips() {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    m_clips.clear();
    m_trackStates.clear();
    {
        std::lock_guard<std::mutex> rlock(m_renderMutex);
        m_clipDecoders.clear();
        m_decoderLruOrder.clear();
    }
    recalculateDuration();
}

// v1.1.0 (PLAN 2.4/C3): Keep m_clips sorted by startMs so the compositor can
// resolve the covering clip per track with a single linear scan. Called after
// every timeline mutation (upsert/remove). Must be called with m_engineMutex
// held.
void GhitaEngine::sortClipsByStart() {
    std::sort(m_clips.begin(), m_clips.end(),
              [](const NativeClip& a, const NativeClip& b) {
                  return a.startMs < b.startMs;
              });
}

int GhitaEngine::setTrackState(int trackIndex, bool muted, bool visible, float volume) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    if (trackIndex < 0) return 0;
    if (static_cast<size_t>(trackIndex) >= m_trackStates.size()) {
        m_trackStates.resize(static_cast<size_t>(trackIndex) + 1);
    }
    m_trackStates[static_cast<size_t>(trackIndex)].muted = muted;
    m_trackStates[static_cast<size_t>(trackIndex)].visible = visible;
    m_trackStates[static_cast<size_t>(trackIndex)].volume = std::clamp(volume, 0.0f, 2.0f);
    return 1;
}

int GhitaEngine::setClipColorCorrection(int clipId, const ColorCorrection& cc) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.cc = cc;
            return 1;
        }
    }
    return 0;
}

int GhitaEngine::setClipText(int clipId, const std::string& text, float fontSize, uint32_t colorArgb) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.textContent = text;
            clip.textFontSize = std::max(4.0f, fontSize);
            clip.textColor = colorArgb;
            return 1;
        }
    }
    return 0;
}

bool GhitaEngine::hasClip(int clipId) const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    for (const auto& clip : m_clips) {
        if (clip.id == clipId) return true;
    }
    return false;
}

bool GhitaEngine::addClipKeyframe(int clipId, int64_t timeMs, float value) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.keyframes.push_back({timeMs, value, 0, 0, 0, 0, 0, 0});
            // Sort by time
            std::sort(clip.keyframes.begin(), clip.keyframes.end(),
                      [](const Keyframe& a, const Keyframe& b) { return a.timeMs < b.timeMs; });
            return true;
        }
    }
    return false;
}

bool GhitaEngine::clearClipKeyframes(int clipId) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.keyframes.clear();
            return true;
        }
    }
    return false;
}

// v1.1.0 (PLAN 3.1): Extended keyframe insertion — property/interpolation/
// bezier aware. Sorted by timeMs; same-time keyframes of DIFFERENT properties
// are kept (a single timestamp can animate several properties at once).
int GhitaEngine::addClipKeyframeEx(int clipId, int64_t timeMs, float value, int property,
                                   int interpolation, float cp1x, float cp1y, float cp2x, float cp2y) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            // Replace an existing keyframe at the same time AND property.
            for (auto& kf : clip.keyframes) {
                if (kf.timeMs == timeMs && kf.property == property) {
                    kf.value = value;
                    kf.interpolation = interpolation;
                    kf.cp1x = cp1x; kf.cp1y = cp1y; kf.cp2x = cp2x; kf.cp2y = cp2y;
                    return 0;
                }
            }
            Keyframe kf;
            kf.timeMs = timeMs;
            kf.value = value;
            kf.property = property;
            kf.interpolation = interpolation;
            kf.cp1x = cp1x; kf.cp1y = cp1y; kf.cp2x = cp2x; kf.cp2y = cp2y;
            clip.keyframes.push_back(kf);
            std::sort(clip.keyframes.begin(), clip.keyframes.end(),
                      [](const Keyframe& a, const Keyframe& b) {
                          if (a.timeMs != b.timeMs) return a.timeMs < b.timeMs;
                          return a.property < b.property;
                      });
            return 0;
        }
    }
    return -1;
}

// v1.1.0 (PLAN 3.3): REAL bezier setter — the v1.0.0 implementation called
// addClipKeyframe(keyframe_index*1000, cp1y), discarding all four control
// points and injecting a junk keyframe. Now the control points land on the
// keyframe at [keyframeIndex] (same time, same property).
int GhitaEngine::setKeyframeBezierEx(int clipId, int keyframeIndex,
                                     float cp1x, float cp1y, float cp2x, float cp2y) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            if (keyframeIndex < 0 || static_cast<size_t>(keyframeIndex) >= clip.keyframes.size()) {
                return -1;
            }
            Keyframe& kf = clip.keyframes[static_cast<size_t>(keyframeIndex)];
            kf.cp1x = cp1x; kf.cp1y = cp1y; kf.cp2x = cp2x; kf.cp2y = cp2y;
            kf.interpolation = 2; // bezier
            return 0;
        }
    }
    return -1;
}

int GhitaEngine::getClipKeyframeCount(int clipId) const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    for (const auto& clip : m_clips) {
        if (clip.id == clipId) {
            return static_cast<int>(clip.keyframes.size());
        }
    }
    return -1;
}

// v1.1.0 (PLAN 3.4): Picture-in-picture geometry setter.
int GhitaEngine::setClipPip(int clipId, const PipGeometry& pip) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.pip = pip;
            return 0;
        }
    }
    return -1;
}

// v1.1.0 (PLAN 3.11): Speed-ramp curve setter (points sorted by t).
int GhitaEngine::setClipSpeedCurve(int clipId, const std::vector<SpeedRampPoint>& curve) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.speedCurve = curve;
            std::sort(clip.speedCurve.begin(), clip.speedCurve.end(),
                      [](const SpeedRampPoint& a, const SpeedRampPoint& b) { return a.t < b.t; });
            return 0;
        }
    }
    return -1;
}

// v1.1.0 (PLAN 3.11): Append a single speed-ramp point (replaces a point at
// the same t, keeps the list sorted).
int GhitaEngine::addSpeedRampPoint(int clipId, float t, float speed) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            for (auto& p : clip.speedCurve) {
                if (p.t == t) {
                    p.speed = speed;
                    return 0;
                }
            }
            SpeedRampPoint p;
            p.t = t;
            p.speed = speed;
            clip.speedCurve.push_back(p);
            std::sort(clip.speedCurve.begin(), clip.speedCurve.end(),
                      [](const SpeedRampPoint& a, const SpeedRampPoint& b) { return a.t < b.t; });
            return 0;
        }
    }
    return -1;
}

// v0.5.5: Keyframe interpolation
// v1.1.0 (PLAN 3.3): REAL — stores the default interpolation on the clip
// (applied between keyframes that don't carry their own). The v1.0.0
// implementation was a silent no-op ("For simplicity, we just note it's
// supported") and the getter hardcoded Linear.
bool GhitaEngine::setClipKeyframeInterpolation(int clipId, KeyframeInterpolation interpolation) {
    std::unique_lock<std::shared_mutex> lock(m_engineMutex);
    for (auto& clip : m_clips) {
        if (clip.id == clipId) {
            clip.keyframeInterpolation = static_cast<int>(interpolation);
            return true;
        }
    }
    return false;
}

KeyframeInterpolation GhitaEngine::getClipKeyframeInterpolation(int clipId) const {
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    for (const auto& clip : m_clips) {
        if (clip.id == clipId) {
            return static_cast<KeyframeInterpolation>(clip.keyframeInterpolation);
        }
    }
    return KeyframeInterpolation::Linear;
}

// v0.5.5: Text overlay rendering (basic rasterizer stub)
bool GhitaEngine::renderTextOverlay(uint8_t* outBuffer, int width, int height,
                                     const char* text, int fontSize, float r, float g, float b, float a) {
    if (!outBuffer || !text || width <= 0 || height <= 0) return false;

    const int textLen = static_cast<int>(std::strlen(text));
    const int boxW = std::min(width, std::max(40, textLen * fontSize / 2));
    const int boxH = std::min(height, fontSize * 2);
    const int boxX = 20;
    // v0.8.0: Underflow fix — a large fontSize (boxH == height) produced a
    // negative boxY and the draw loop below wrote at negative indices.
    const int boxY = std::max(0, height - boxH - 20);

    // Draw filled rectangle for text background
    for (int y = boxY; y < boxY + boxH && y < height; ++y) {
        for (int x = boxX; x < boxX + boxW && x < width; ++x) {
            int idx = (y * width + x) * 4;
            outBuffer[idx]     = static_cast<uint8_t>(r * 255);
            outBuffer[idx + 1] = static_cast<uint8_t>(g * 255);
            outBuffer[idx + 2] = static_cast<uint8_t>(b * 255);
            outBuffer[idx + 3] = static_cast<uint8_t>(a * 255);
        }
    }

    return true;
}

void GhitaEngine::recalculateDuration() {
    // v0.8.0: Timeline duration is the end of the last clip — the old 60s
    // minimum made empty timelines play 60s of black and mis-scaled previews.
    int64_t maxEnd = 0;
    for (const auto& clip : m_clips) {
        int64_t end = clip.startMs + clip.durationMs;
        if (end > maxEnd) maxEnd = end;
    }
    m_durationMs.store(maxEnd);
}

// ========== AUDIO WAVEFORM ==========

bool GhitaEngine::getAudioWaveform(float* outSamples, int sampleCount) {
    if (!outSamples || sampleCount <= 0) return false;
    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    // v1.0.2: The decoder is NOT thread-safe — extractPcmAudioSamples seeks
    // and decodes through the shared FFmpeg context. Every other decoder
    // accessor takes m_renderMutex; this one was the only site missing it,
    // racing the preview render thread (corrupted frames / crashes).
    std::lock_guard<std::mutex> rlock(m_renderMutex);

    if (auto realDec = dynamic_cast<RealFFmpegMediaDecoder*>(m_decoder.get())) {
        return realDec->extractPcmAudioSamples(outSamples, sampleCount, m_volume.load());
    }

    // Fallback: synthetic waveform
    for (int i = 0; i < sampleCount; ++i) {
        float phase = static_cast<float>(i) / static_cast<float>(sampleCount);
        outSamples[i] = (std::sin(phase * 20.0f) * 0.5f + 0.5f) * m_volume.load();
    }
    return true;
}

// ====================================================================
// AUDIO MIXING (v0.8.0)
// ====================================================================

// v0.8.0: Mix interleaved float-stereo PCM @ 44100 for [startMs, endMs) from
// every clip that overlaps the window. Applies clip volume, track
// volume/mute and (optionally) the master volume. Returns true when at least
// one clip contributed audio. Takes its own engine (shared) + render locks.
bool GhitaEngine::mixAudioWindow(int64_t startMs, int64_t endMs, float* outSamples,
                                 int sampleCount, bool applyMasterVolume) {
    if (!outSamples || sampleCount <= 0 || endMs <= startMs) return false;
    std::fill(outSamples, outSamples + sampleCount, 0.0f);

    std::shared_lock<std::shared_mutex> lock(m_engineMutex);
    std::lock_guard<std::mutex> rlock(m_renderMutex);

    const float master = applyMasterVolume ? m_volume.load() : 1.0f;
    bool anyAudio = false;
    constexpr int kSampleRate = 44100;

    // v1.1.0 (PLAN 2.4/C3): m_clips is sorted by startMs — a clip that
    // starts at/after endMs cannot overlap this window, and neither can any
    // later clip, so break instead of scanning the rest.
    for (const auto& clip : m_clips) {
        if (clip.startMs >= endMs) break;
        const int64_t clipEnd = clip.startMs + clip.durationMs;
        if (clipEnd <= startMs) continue;

        float trackVol = 1.0f;
        if (static_cast<size_t>(clip.trackIndex) < m_trackStates.size()) {
            if (m_trackStates[clip.trackIndex].muted) continue;
            trackVol = m_trackStates[clip.trackIndex].volume;
        }
        const float gain = clip.volume * trackVol * master;
        if (gain <= 0.0f) continue;

        // Overlap window on the timeline → source-time window (speed-scaled).
        const int64_t ovStart = std::max(startMs, clip.startMs);
        const int64_t ovEnd = std::min(endMs, clipEnd);
        if (ovEnd <= ovStart) continue;
        const int64_t srcStart = clip.sourceInMs +
            static_cast<int64_t>(static_cast<double>(ovStart - clip.startMs) * clip.speed);
        // v1.0.3: THE "rè" FIX — the mixing format is interleaved FLOAT STEREO
        // (2 floats per frame), but ovSamples below counts FRAMES. The old code
        // used the frame count as the float count, so decodeAudioSegment only
        // filled the first HALF of every 100ms window and the second half
        // stayed ZERO → every chunk was 50ms audio + 50ms silence = a harsh
        // 10Hz crackle ("rè / tua nhanh bị vỡ"). Multiply by 2 everywhere.
        const int ovFrames = static_cast<int>(std::ceil(
            static_cast<double>(ovEnd - ovStart) / 1000.0 * kSampleRate));
        const int ovFloats = ovFrames * 2;
        const int outOffsetFrames = static_cast<int>(
            static_cast<double>(ovStart - startMs) / 1000.0 * kSampleRate);
        const int maxCopy = std::min(ovFloats, sampleCount - outOffsetFrames * 2);
        if (maxCopy <= 0) continue;

        // Clip kinds without media (text/sticker) contribute no audio.
        if (clip.kind == NativeClipKind::Text || clip.kind == NativeClipKind::Sticker) continue;

        auto realDecoder = std::dynamic_pointer_cast<RealFFmpegMediaDecoder>(getClipDecoder(clip.id, clip.filePath));
        if (!realDecoder || !realDecoder->hasAudioStream()) continue;

        // v1.1.0 (PLAN 2.9): Member grow-only segment buffer — no per-clip
        // per-window allocation (serialized by m_renderMutex).
        m_mixSegBuf.resize(static_cast<size_t>(maxCopy), 0.0f);
        std::vector<float>& seg = m_mixSegBuf;
        if (realDecoder->decodeAudioSegment(srcStart, seg.data(), maxCopy, gain)) {
            for (int i = 0; i < maxCopy; ++i) {
                outSamples[outOffsetFrames * 2 + i] += seg[i];
            }
            anyAudio = true;
        }
    }

    // v1.0.3: Noise suppression ("làm rõ âm thanh") — one-pole low-cut (DC
    // blocker, ≈85 Hz) applied per channel to the mixed preview. Removes hum
    // & rumble without touching the source files. Preview-only; export is
    // unaffected (export mixes without this flag set).
    if (m_noiseSuppress.load()) {
        constexpr double kR = 0.98;
        double lpL = 0.0, lpR = 0.0;
        for (int i = 0; i < sampleCount; i += 2) {
            double inL = outSamples[i];
            double inR = outSamples[i + 1];
            lpL = kR * lpL + (1.0 - kR) * inL;
            lpR = kR * lpR + (1.0 - kR) * inR;
            outSamples[i] = static_cast<float>(inL - lpL);
            outSamples[i + 1] = static_cast<float>(inR - lpR);
        }
    }

    for (int i = 0; i < sampleCount; ++i) {
        outSamples[i] = std::clamp(outSamples[i], -1.0f, 1.0f);
    }
    return anyAudio;
}

// ====================================================================
// AUDIO PREVIEW (v0.8.0, waveOut on Windows)
// ====================================================================

void GhitaEngine::audioPreviewLoop() {
#ifdef _WIN32
    // v0.8.0: Nothing to play on an empty timeline — don't spin waveOut.
    {
        std::shared_lock<std::shared_mutex> lock(m_engineMutex);
        if (m_clips.empty()) {
            m_audioThreadRunning.store(false);
            return;
        }
    }
    constexpr int kSampleRate = 44100;
    constexpr int kChunkMs = 100;
    constexpr int kChunkFrames = kSampleRate * kChunkMs / 1000; // 4410
    constexpr int kNumBuffers = 4;
    constexpr int kBufBytes = kChunkFrames * 2 * static_cast<int>(sizeof(int16_t));

    WAVEFORMATEX wfx{};
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 2;
    wfx.nSamplesPerSec = kSampleRate;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = 2 * 2;
    wfx.nAvgBytesPerSec = kSampleRate * wfx.nBlockAlign;

    HWAVEOUT hWaveOut = nullptr;
    if (waveOutOpen(&hWaveOut, WAVE_MAPPER, &wfx, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR) {
        m_audioThreadRunning.store(false);
        return;
    }

    std::vector<WAVEHDR> hdrs(kNumBuffers);
    std::vector<std::vector<uint8_t>> datas(kNumBuffers, std::vector<uint8_t>(kBufBytes));
    std::vector<float> mixBuf(static_cast<size_t>(kChunkFrames) * 2, 0.0f);
    for (int i = 0; i < kNumBuffers; ++i) {
        hdrs[i] = {};
        hdrs[i].lpData = reinterpret_cast<LPSTR>(datas[i].data());
        hdrs[i].dwBufferLength = kBufBytes;
        hdrs[i].dwUser = static_cast<DWORD_PTR>(i);
    }

    int fillIdx = 0;
    int activeBuffers = 0;
    int64_t nextPosMs = m_currentPosMs.load();

    while (!m_audioStopFlag.load()) {
        // Resync when the engine position jumped (seek) or wrapped.
        const int64_t enginePos = m_currentPosMs.load();
        const int64_t duration = m_durationMs.load();
        if (enginePos < nextPosMs - 250 || enginePos > nextPosMs + 250) {
            // v0.8.0: Fully unprepare queued headers — resetting only their
            // dwFlags left them in a half-prepared state and the next
            // waveOutPrepareHeader could fail, stalling playback.
            waveOutReset(hWaveOut);
            for (int i = 0; i < kNumBuffers; ++i) {
                if (hdrs[i].dwFlags & WHDR_PREPARED) {
                    waveOutUnprepareHeader(hWaveOut, &hdrs[i], sizeof(WAVEHDR));
                }
                hdrs[i].dwFlags = 0;
            }
            activeBuffers = 0;
            fillIdx = 0;
            nextPosMs = enginePos;
        }
        if (duration > 0 && nextPosMs >= duration) {
            nextPosMs = 0;
        }
        if (nextPosMs < 0) nextPosMs = 0;

        // Reap finished buffers.
        while (activeBuffers > 0 && (hdrs[fillIdx].dwFlags & WHDR_DONE)) {
            waveOutUnprepareHeader(hWaveOut, &hdrs[fillIdx], sizeof(WAVEHDR));
            activeBuffers--;
            fillIdx = (fillIdx + 1) % kNumBuffers;
        }
        if (activeBuffers >= kNumBuffers) {
            // All buffers queued — wait for the device to free one.
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }

        // Mix the next chunk.
        const bool hasAudio = mixAudioWindow(nextPosMs, nextPosMs + kChunkMs,
                                             mixBuf.data(), kChunkFrames * 2, true);
        int16_t* s16 = reinterpret_cast<int16_t*>(datas[fillIdx].data());
        if (hasAudio) {
            for (int i = 0; i < kChunkFrames * 2; ++i) {
                s16[i] = static_cast<int16_t>(std::clamp(mixBuf[i], -1.0f, 1.0f) * 32767.0f);
            }
        } else {
            std::memset(s16, 0, kBufBytes);
        }

        hdrs[fillIdx].dwFlags = 0;
        hdrs[fillIdx].dwUser = static_cast<DWORD_PTR>(fillIdx);
        if (waveOutPrepareHeader(hWaveOut, &hdrs[fillIdx], sizeof(WAVEHDR)) == MMSYSERR_NOERROR &&
            waveOutWrite(hWaveOut, &hdrs[fillIdx], sizeof(WAVEHDR)) == MMSYSERR_NOERROR) {
            activeBuffers++;
            // v1.0.3: Advance by the playback rate so the audio thread keeps
            // pace with the (rate-scaled) engine playhead — previously it
            // always advanced 100ms per chunk, so at 2x the audio lagged the
            // video and the ±250ms resync fired constantly (audible "rè").
            nextPosMs += static_cast<int64_t>(
                static_cast<double>(kChunkMs) * m_playbackRate.load());
            fillIdx = (fillIdx + 1) % kNumBuffers;
        } else {
            waveOutUnprepareHeader(hWaveOut, &hdrs[fillIdx], sizeof(WAVEHDR));
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
    }

    waveOutReset(hWaveOut);
    for (auto& h : hdrs) {
        if (h.dwFlags & WHDR_PREPARED) {
            waveOutUnprepareHeader(hWaveOut, &h, sizeof(WAVEHDR));
        }
    }
    waveOutClose(hWaveOut);
#endif
    m_audioThreadRunning.store(false);
}

void GhitaEngine::startAudioPreviewThread() {
    // v1.0.2: Serialize with stopAudioPreviewThread — a concurrent pause()
    // could otherwise join() the thread while this assigns it (data race on
    // the std::thread handle).
    std::lock_guard<std::mutex> lock(m_audioThreadMutex);
    if (m_audioThreadRunning.load() || !m_audioPreviewEnabled.load()) return;
    m_audioStopFlag.store(false);
    m_audioThreadRunning.store(true);
    try {
        m_audioThread = std::thread([this]() { audioPreviewLoop(); });
    } catch (...) {
        m_audioThreadRunning.store(false);
    }
}

void GhitaEngine::stopAudioPreviewThread() {
    // v1.0.2: Same serialization as startAudioPreviewThread (see above).
    std::lock_guard<std::mutex> lock(m_audioThreadMutex);
    if (!m_audioThreadRunning.load()) {
        // v0.8.0: The thread may have exited on its own (empty timeline, no
        // audio device) — the handle must still be joined, otherwise the
        // std::thread destructor calls std::terminate.
        if (m_audioThread.joinable()) {
            m_audioThread.join();
        }
        return;
    }
    m_audioStopFlag.store(true);
    if (m_audioThread.joinable()) {
        m_audioThread.join();
    }
    m_audioThreadRunning.store(false);
}

// ========== ASYNC EXPORT PIPELINE ==========

bool GhitaEngine::startExport(const std::string& outputPath, int width, int height, int fps) {
    return startExportEx(outputPath, width, height, fps, "h264", 10000000, true);
}

bool GhitaEngine::startExportEx(const std::string& outputPath, int width, int height, int fps,
                                 const std::string& codec, int64_t bitrate, bool includeAudio) {
    if (outputPath.empty()) return false;
    // v1.1.0 (PLAN 3.8/BUG FIX): Audio-only (MP3) exports pass 0×0×0 — the
    // old guard rejected them, so the "Audio Only (MP3)" preset could NEVER
    // start (silent failure despite the v1.0.0 changelog claiming it works).
    if (codec != "mp3" && (width <= 0 || height <= 0 || fps <= 0)) return false;

    // v1.1.0 (PLAN 1.1/P1.9): Two-phase publish — claim the export slot under
    // the engine lock, then join the previous (finished) thread OUTSIDE it.
    // The old code joined under the unique engine lock, and the export loop
    // takes a SHARED engine lock per frame: joining while holding the unique
    // lock could deadlock (export thread blocked on the lock we hold, while we
    // block on its exit). Publishing m_isExporting first preserves the
    // "only one starter" guarantee the lock used to provide, so the
    // m_exportThread handle is still joined/assigned by exactly one thread.
    {
        std::unique_lock<std::shared_mutex> lock(m_engineMutex);
        if (!m_ready.load() || m_isExporting.load()) return false;

        // v0.7.8: Snapshot the media path under the engine lock — the export
        // thread reads it without locking (previously a data race with loadMedia).
        m_exportMediaPath = m_loadedFilePath;

        // v0.7.8: Reset the error flag BEFORE publishing isExporting — otherwise
        // a poller could observe a stale failure from a previous export.
        m_exportError.store(false);
        m_exportOutputPath = outputPath;
        m_isExporting.store(true);
        m_cancelExportFlag.store(false);
        m_exportProgress.store(0.0f);
        m_exportFileSize.store(0);
    }

    {
        // v1.0.2: Serialize with cancelExport()/~GhitaEngine() — a racing
        // cancelExport could otherwise reach a SECOND join() on the same
        // std::thread (std::system_error, and std::terminate if it happens
        // inside the destructor). The join mutex already guards the other
        // two join sites; this one was missing it.
        // v1.1.0: Now executed WITHOUT the engine lock held (see above).
        std::lock_guard<std::mutex> joinLock(m_exportJoinMutex);
        if (m_exportThread.joinable() && std::this_thread::get_id() != m_exportThread.get_id()) {
            m_exportThread.join();
        }
    }

    try {
        m_exportThread = std::thread([this, outputPath, width, height, fps, codec, bitrate, includeAudio]() {
            runExportLoopEx(outputPath, width, height, fps, codec, bitrate, includeAudio);
        });
    } catch (...) {
        m_isExporting.store(false);
        return false;
    }
    return true;
}

void GhitaEngine::runExportLoop(std::string outputPath, int width, int height, int fps) {
    runExportLoopEx(outputPath, width, height, fps, "h264", 10000000, true);
}

void GhitaEngine::runExportLoopEx(std::string outputPath, int width, int height, int fps,
                                   std::string codec, int64_t bitrate, bool includeAudio) {
    m_exportError.store(false);
    // v1.1.0 (PLAN 3.12): GIF is an image container — it can't carry audio.
    // A caller passing includeAudio=true (e.g. custom GIF export) used to
    // make avformat_write_header fail ("gif muxer does not support any
    // stream of type audio"). The engine now drops the audio stream for gif.
    if (codec == "gif") {
        includeAudio = false;
    }
    const int totalFrames = static_cast<int>((m_durationMs.load() / 1000.0f) * fps);
    // v1.0.0: Audio-only (MP3) exports use a duration check, not totalFrames
    // — the dialog passes width=0, height=0, fps=0 for the MP3 preset, so
    // totalFrames would be 0 and we'd bail out before any encoding happens.
    if (codec == "mp3") {
        if (m_durationMs.load() <= 0) {
            m_isExporting.store(false);
            m_exportError.store(true);
            return;
        }
    } else if (totalFrames <= 0) {
        m_isExporting.store(false);
        m_exportError.store(true);
        return;
    }

    std::vector<uint8_t> frameBuffer(static_cast<size_t>(std::max(width, 1)) *
                                      static_cast<size_t>(std::max(height, 1)) * 4);
    RealFFmpegMediaDecoder decoder;

    // v0.7.9: Deep-review fix — open() failure used to be ignored: the export
    // loop then encoded blank frames, wrote a (corrupt) file, set
    // writeCompleted=true and reported SUCCESS. Fail loudly instead so the
    // Dart side surfaces a real error message.
    if (!decoder.open(m_exportMediaPath.empty() ? "synthetic" : m_exportMediaPath)) {
        m_exportError.store(true);
        m_isExporting.store(false);
        return;
    }

    // v0.7.8: Only a fully written output counts as success
    bool writeCompleted = false;

#ifdef GHITA_HAS_FFMPEG
    // FFmpeg encoding pipeline
    AVFormatContext* fmtCtx = nullptr;
    AVStream* videoStream = nullptr;
    AVCodecContext* encCtx = nullptr;
    const AVCodec* encoder = nullptr;
    AVFrame* encFrame = nullptr;
    AVPacket* encPkt = nullptr;
    SwsContext* swsCtx = nullptr;
    // v0.8.0: Audio encoder state — function scope so export_cleanup can free
    // it on every exit path (including avio_open/header failures).
    AVCodecContext* audioEncCtx = nullptr;
    AVStream* audioStream = nullptr;
    SwrContext* audioSwr = nullptr;
    AVFrame* audioFrame = nullptr;
    AVPacket* audioPkt = nullptr;

    // Determine encoder name — v0.8.0: robust fallback chain. MSVC/vcpkg
    // FFmpeg builds ship no libx264 (only hardware encoders that reject
    // yuv420p), so export must keep trying until it finds an encoder that
    // accepts the YUV420P pipeline — mpeg4 is the always-available last resort.
    auto pickEncoder = [](const std::vector<const char*>& names) -> const AVCodec* {
        for (const char* n : names) {
            const AVCodec* c = avcodec_find_encoder_by_name(n);
            if (!c) continue;
            // v1.0.0: AVCodec::pix_fmts is deprecated in FFmpeg 7+ — use the
            // config-based API to enumerate the supported pixel formats.
            // v1.0.0b (CI fix): avcodec_get_supported_config /
            // AV_CODEC_CONFIG_PIX_FORMAT only exist in FFmpeg ≥ 7.0
            // (libavcodec ≥ 61.3); older distros (e.g. Ubuntu 24.04, FFmpeg
            // 6.1) keep the legacy pix_fmts member. Guard by version so CI
            // builds on both.
            bool yuv420 = false;
#if LIBAVCODEC_VERSION_INT >= AV_VERSION_INT(61, 3, 100) // FFmpeg 7.0+/libavcodec 61.3+
            const AVPixelFormat* fmts = nullptr;
            int nFmts = 0;
            if (avcodec_get_supported_config(nullptr, c, AV_CODEC_CONFIG_PIX_FORMAT,
                                             0, reinterpret_cast<const void**>(&fmts),
                                             &nFmts) < 0 || !fmts) {
                continue;
            }
            for (int i = 0; i < nFmts; ++i) {
                if (fmts[i] == AV_PIX_FMT_YUV420P) { yuv420 = true; break; }
            }
#else
            const AVPixelFormat* fmts = c->pix_fmts;
            if (fmts) {
                for (int i = 0; fmts[i] != AV_PIX_FMT_NONE; ++i) {
                    if (fmts[i] == AV_PIX_FMT_YUV420P) { yuv420 = true; break; }
                }
            } else {
                yuv420 = true; // unknown list — let the open attempt decide
            }
#endif
            if (!yuv420) continue;
            return c;
        }
        return nullptr;
    };
    if (codec == "h265" || codec == "hevc") {
        encoder = pickEncoder({"libx265", "hevc"});
    } else if (codec == "vp9") {
        encoder = pickEncoder({"libvpx-vp9", "vp9"});
    } else if (codec == "gif") {
        // v1.0.0: GIF — dedicated encoder (BGRA pix_fmt, no YUV420P pipeline).
        // The pickEncoder helper above skips any encoder whose pix_fmts list
        // doesn't include YUV420P, which rules out gif — use a direct lookup.
        encoder = avcodec_find_encoder(AV_CODEC_ID_GIF);
    } else if (codec == "mp3") {
        // v1.0.0: MP3 — audio-only export, no video stream at all. The
        // encoder stays null and the video stream creation below is skipped.
        encoder = nullptr;
    } else if (codec == "prores") {
        // v1.1.0 (PLAN 3.10): REAL ProRes — the old code let 'prores' fall
        // through to the H.264 chain and silently wrote H.264 into a .mov
        // labeled "ProRes". Now the encoder is looked up explicitly and the
        // export FAILS loudly when the build has none.
        encoder = avcodec_find_encoder_by_name("prores_ks");
        if (!encoder) encoder = avcodec_find_encoder_by_name("prores");
        if (!encoder) encoder = avcodec_find_encoder(AV_CODEC_ID_PRORES);
    } else {
        encoder = pickEncoder({"libx264", "libopenh264", "h264", "mpeg4"});
    }
    if (!encoder && codec != "mp3") {
        // Absolute last resort: any H.264/MPEG-4 encoder the build provides.
        encoder = avcodec_find_encoder(AV_CODEC_ID_H264);
        if (!encoder) encoder = avcodec_find_encoder(AV_CODEC_ID_MPEG4);
    }

    // Open output format
    avformat_alloc_output_context2(&fmtCtx, nullptr, nullptr, outputPath.c_str());
    // v1.0.0: audio-only MP3 exports have no video encoder; the condition
    // gates on "have a muxer AND (have a video encoder OR this is audio-only)".
    if (fmtCtx && (encoder || codec == "mp3")) {
        // v0.8.0: The audio stream MUST exist before avformat_write_header
        // or the muxer never registers the track.
        // v1.0.2: Moved OUT of the video chain — MP3 exports keep encoder
        // null, and the old nesting made the whole MP3 path dead code.
        const AVCodec* audioCodec = nullptr;
        if (codec == "mp3") {
            audioCodec = avcodec_find_encoder(AV_CODEC_ID_MP3);
        } else if (includeAudio) {
            audioCodec = avcodec_find_encoder(AV_CODEC_ID_AAC);
        }
        if (audioCodec) {
            audioEncCtx = avcodec_alloc_context3(audioCodec);
            if (audioEncCtx) {
                audioEncCtx->sample_rate = 44100;
                audioEncCtx->ch_layout = AV_CHANNEL_LAYOUT_STEREO;
                audioEncCtx->sample_fmt = AV_SAMPLE_FMT_FLTP;
                // v1.0.0: Audio bitrate was hardcoded to 128k for every
                // codec — MP3 users picking 192/256/320 kbps in the dialog
                // got a 128k file anyway. Honor the bitrate parameter for
                // audio-only exports (128000–320000 sensible range).
                if (codec == "mp3" && bitrate >= 32000 && bitrate <= 320000) {
                    audioEncCtx->bit_rate = bitrate;
                } else {
                    audioEncCtx->bit_rate = 128000;
                }
                if (fmtCtx->oformat->flags & AVFMT_GLOBALHEADER) {
                    audioEncCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
                }
                if (avcodec_open2(audioEncCtx, audioCodec, nullptr) >= 0) {
                    audioStream = avformat_new_stream(fmtCtx, audioCodec);
                    if (audioStream) {
                        avcodec_parameters_from_context(audioStream->codecpar, audioEncCtx);
                        audioStream->time_base = AVRational{1, 44100};
                    }
                }
            }
        }

        // v1.0.2: Video chain — only for video exports (MP3 keeps encoder null).
        if (encoder) {
            encCtx = avcodec_alloc_context3(encoder);
            if (encCtx) {
                encCtx->width = width;
                encCtx->height = height;
                encCtx->time_base = {1, fps};
                encCtx->framerate = {fps, 1};
                encCtx->pix_fmt = (codec == "gif")
                    ? AV_PIX_FMT_BGRA  // v1.0.0: GIF encoder is BGRA, not YUV420P
                    // v1.1.0 (PLAN 3.10): ProRes encodes 4:2:2 10-bit.
                    : (codec == "prores") ? AV_PIX_FMT_YUV422P10LE
                                          : AV_PIX_FMT_YUV420P;
                encCtx->bit_rate = bitrate;
                encCtx->gop_size = (codec == "gif") ? 0 : fps * 2; // GIF is intra-only
                encCtx->max_b_frames = (codec == "gif") ? 0 : 2;

                if (fmtCtx->oformat->flags & AVFMT_GLOBALHEADER) {
                    encCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
                }

                if (avcodec_open2(encCtx, encoder, nullptr) >= 0) {
                    videoStream = avformat_new_stream(fmtCtx, encoder);
                    if (videoStream) {
                        avcodec_parameters_from_context(videoStream->codecpar, encCtx);
                    }
                }
            }
        }

        // Open output file
        if (!(fmtCtx->oformat->flags & AVFMT_NOFILE)) {
            // v0.7.8: Bail out cleanly when the output path is
            // unwritable — previously the failure was ignored
            // and avformat_write_header crashed on a null pb.
            if (avio_open(&fmtCtx->pb, outputPath.c_str(), AVIO_FLAG_WRITE) < 0) {
                m_exportError.store(true);
                goto export_cleanup;
            }
        }

        if (avformat_write_header(fmtCtx, nullptr) >= 0) {
            // v1.0.2: Video encode resources — only for video exports.
            if (encoder) {
                encFrame = av_frame_alloc();
                encFrame->width = width;
                encFrame->height = height;
                // v1.1.0 (PLAN 3.10): ProRes is 4:2:2 10-bit.
                encFrame->format = (codec == "gif")
                    ? AV_PIX_FMT_BGRA
                    : (codec == "prores") ? AV_PIX_FMT_YUV422P10LE
                                          : AV_PIX_FMT_YUV420P;
                av_frame_get_buffer(encFrame, 0);

                encPkt = av_packet_alloc();

                // SWS context for RGB → pixel format conversion.
                // v1.0.0: GIF needs RGBA → BGRA; other video codecs
                // keep RGBA → YUV420P (ProRes → YUV422P10LE).
                const AVPixelFormat swsDstFmt = (codec == "gif")
                    ? AV_PIX_FMT_BGRA
                    : (codec == "prores") ? AV_PIX_FMT_YUV422P10LE
                                          : AV_PIX_FMT_YUV420P;
                swsCtx = sws_getContext(
                    width, height, AV_PIX_FMT_RGBA,
                    width, height, swsDstFmt,
                    SWS_BILINEAR, nullptr, nullptr, nullptr);
            }

            // v0.8.0: Audio encode resources (after the header — needs
            // audioEncCtx->frame_size).
            // v1.0.2: Shared by the video-with-audio path AND the audio-only
            // (MP3) path, so it lives outside the if(encoder) block.
            if (audioEncCtx && audioStream) {
                AVChannelLayout fltStereo = AV_CHANNEL_LAYOUT_STEREO;
                AVChannelLayout fltpStereo = AV_CHANNEL_LAYOUT_STEREO;
                if (swr_alloc_set_opts2(&audioSwr, &fltpStereo, AV_SAMPLE_FMT_FLTP, 44100,
                                        &fltStereo, AV_SAMPLE_FMT_FLT, 44100, 0, nullptr) >= 0) {
                    swr_init(audioSwr);
                }
                audioFrame = av_frame_alloc();
                audioFrame->format = AV_SAMPLE_FMT_FLTP;
                av_channel_layout_copy(&audioFrame->ch_layout, &fltpStereo);
                audioFrame->sample_rate = 44100;
                audioFrame->nb_samples =
                    audioEncCtx->frame_size > 0 ? audioEncCtx->frame_size : 1024;
                av_frame_get_buffer(audioFrame, 0);
                audioPkt = av_packet_alloc();
            }
            const int frameSamples =
                std::max(1, static_cast<int>(std::round(44100.0 / static_cast<double>(fps))));
            // v1.0.2: The audio window must cover frameSamples samples — the
            // old `1000 / fps` integer division (16 ms at 60 fps) under-filled
            // the mix buffer by ~29 samples per frame, encoding periodic
            // silence. Derive the window from the sample count instead.
            const int64_t audioWindowMs = std::max<int64_t>(1,
                static_cast<int64_t>(std::ceil(frameSamples * 1000.0 / 44100.0)));
            std::vector<float> mixBuf(static_cast<size_t>(frameSamples) * 2, 0.0f);
            int64_t audioPtsAccum = 0;
            // v0.8.0: AAC priming delay — packet pts = frame pts − delay;
            // offsetting keeps the stream's pts non-negative (some builds
            // expose delay, others don't — fall back to the 1024 spec value).
            const int audioDelay = audioEncCtx
                ? (audioEncCtx->delay > 0 ? audioEncCtx->delay : 1024)
                : 0;

            // v1.0.2: Video encode loop — guarded so audio-only (MP3) exports
            // skip video rendering entirely.
            if (encoder) {
                for (int frame = 0; frame < totalFrames; ++frame) {
                    if (m_cancelExportFlag.load()) break;

                    int64_t frameTimeMs = static_cast<int64_t>(
                        (static_cast<float>(frame) / fps) * 1000.0f);

                    // v0.8.0: Render the ACTUAL timeline (multi-clip
                    // composition) instead of the single loaded media.
                    {
                        std::shared_lock<std::shared_mutex> elock(m_engineMutex);
                        std::lock_guard<std::mutex> rlock(m_renderMutex);
                        if (!m_clips.empty()) {
                            renderTimelineFrame(frameBuffer.data(), width, height, frameTimeMs);
                        } else {
                            // v0.7.9: Deep-review — a decode failure mid
                            // export used to produce a truncated/corrupt
                            // file that still reported success. Fail loudly.
                            if (!decoder.decodeFrame(frameBuffer.data(), width, height, frameTimeMs,
                                                      m_activeFilterType, m_filterIntensity.load())) {
                                m_exportError.store(true);
                                break;
                            }
                        }
                    }

                    // Convert RGBA → YUV420P
                    if (swsCtx) {
                        uint8_t* srcSlice[1] = {frameBuffer.data()};
                        int srcStride[1] = {width * 4};
                        sws_scale(swsCtx, srcSlice, srcStride, 0, height,
                                  encFrame->data, encFrame->linesize);
                    }

                    // v0.8.0: Mix + encode the audio for this frame's window.
                    if (audioEncCtx && audioSwr && audioFrame && audioPkt) {
                        mixAudioWindow(frameTimeMs, frameTimeMs + audioWindowMs,
                                       mixBuf.data(), frameSamples * 2, true);
                        int consumed = 0;
                        while (consumed < frameSamples) {
                            const int n = std::min(audioFrame->nb_samples, frameSamples - consumed);
                            float* src = mixBuf.data() + consumed * 2;
                            // v1.0.0b (CI fix): swr_convert takes
                            // `const uint8_t**` input planes — GCC/Clang reject
                            // a plain uint8_t** here (MSVC silently accepted).
                            const uint8_t* inPlane = reinterpret_cast<const uint8_t*>(src);
                            const uint8_t* inPlanes[2] = {inPlane, inPlane};
                            uint8_t* outPlanes[2] = {audioFrame->data[0], audioFrame->data[1]};
                            const int got = swr_convert(audioSwr, outPlanes, n, inPlanes, n);
                            if (got > 0) {
                                // v0.8.0: Offset by the encoder priming delay (AAC = 1024 samples) —
                                // otherwise the first packets carry NEGATIVE pts and the mov
                                // muxer crashes (SIGFPE) computing durations.
                                audioFrame->pts = audioPtsAccum + audioDelay;
                                audioPtsAccum += got;
                                avcodec_send_frame(audioEncCtx, audioFrame);
                                while (avcodec_receive_packet(audioEncCtx, audioPkt) == 0) {
                                    av_packet_rescale_ts(audioPkt, audioEncCtx->time_base, audioStream->time_base);
                                    audioPkt->stream_index = audioStream->index;
                                    // v1.0.2: A failed write means the output is
                                    // corrupt — stop early instead of reporting
                                    // success for a truncated file.
                                    if (av_interleaved_write_frame(fmtCtx, audioPkt) < 0) {
                                        m_exportError.store(true);
                                        goto export_cleanup;
                                    }
                                    av_packet_unref(audioPkt);
                                }
                            }
                            consumed += n;
                        }
                    }

                    encFrame->pts = frame;
                    int ret = avcodec_send_frame(encCtx, encFrame);
                    while (ret >= 0) {
                        ret = avcodec_receive_packet(encCtx, encPkt);
                        if (ret == 0) {
                            av_packet_rescale_ts(encPkt, encCtx->time_base, videoStream->time_base);
                            encPkt->stream_index = videoStream->index;
                            if (av_interleaved_write_frame(fmtCtx, encPkt) < 0) {
                                m_exportError.store(true);
                                goto export_cleanup;
                            }
                            av_packet_unref(encPkt);
                        } else {
                            break;
                        }
                    }

                    float progress = static_cast<float>(frame + 1) / static_cast<float>(totalFrames);
                    m_exportProgress.store(progress);
                }

                // Flush video encoder
                avcodec_send_frame(encCtx, nullptr);
                while (avcodec_receive_packet(encCtx, encPkt) == 0) {
                    av_packet_rescale_ts(encPkt, encCtx->time_base, videoStream->time_base);
                    encPkt->stream_index = videoStream->index;
                    if (av_interleaved_write_frame(fmtCtx, encPkt) < 0) {
                        m_exportError.store(true);
                        goto export_cleanup;
                    }
                    av_packet_unref(encPkt);
                }
            } // end video encode loop + flush

            // v1.0.0: Audio-only (MP3) encode loop — walks the full timeline
            // duration in mp3-frame-sized chunks, no video rendering involved.
            // v1.0.2: Now reachable — it used to sit inside if(encoder) (which
            // is false for MP3 by construction), so no MP3 file was ever made.
            if (!encoder && audioEncCtx && audioSwr && audioFrame && audioPkt && audioStream) {
                const int64_t totalMs = std::max<int64_t>(1, m_durationMs.load());
                const int chunkSamples = audioFrame->nb_samples > 0
                    ? audioFrame->nb_samples : 1152; // mp3 frame size
                const int64_t chunkMs = std::max<int64_t>(1,
                    static_cast<int64_t>(static_cast<double>(chunkSamples) * 1000.0 / 44100.0));
                int64_t audioPtsAccum = 0;
                int64_t posMs = 0;
                std::vector<float> mixBuf(static_cast<size_t>(chunkSamples) * 2, 0.0f);
                const int audioDelay = audioEncCtx->delay > 0 ? audioEncCtx->delay : 0;
                while (posMs < totalMs && !m_cancelExportFlag.load()) {
                    if (!mixAudioWindow(posMs, std::min<int64_t>(posMs + chunkMs, totalMs),
                                        mixBuf.data(), chunkSamples * 2, true)) {
                        // No contributing clips in this window — zero
                        // buffer still produces a valid mp3 silent frame.
                    }
                    uint8_t* outPlanes[2] = {audioFrame->data[0], audioFrame->data[1]};
                    const uint8_t* inPlane = reinterpret_cast<const uint8_t*>(mixBuf.data());
                    const uint8_t* inPlanes[2] = {inPlane, inPlane};
                    const int got = swr_convert(audioSwr, outPlanes, chunkSamples, inPlanes, chunkSamples);
                    if (got > 0) {
                        audioFrame->pts = audioPtsAccum + audioDelay;
                        audioPtsAccum += got;
                        avcodec_send_frame(audioEncCtx, audioFrame);
                        while (avcodec_receive_packet(audioEncCtx, audioPkt) == 0) {
                            av_packet_rescale_ts(audioPkt, audioEncCtx->time_base, audioStream->time_base);
                            audioPkt->stream_index = audioStream->index;
                            if (av_interleaved_write_frame(fmtCtx, audioPkt) < 0) {
                                m_exportError.store(true);
                                goto export_cleanup;
                            }
                            av_packet_unref(audioPkt);
                        }
                    }
                    posMs += chunkMs;
                    m_exportProgress.store(static_cast<float>(posMs) / static_cast<float>(totalMs));
                }
            } // end audio-only loop

            // v0.8.0: Flush the audio encoder.
            if (audioEncCtx) {
                avcodec_send_frame(audioEncCtx, nullptr);
                while (audioPkt && avcodec_receive_packet(audioEncCtx, audioPkt) == 0) {
                    av_packet_rescale_ts(audioPkt, audioEncCtx->time_base, audioStream->time_base);
                    audioPkt->stream_index = audioStream->index;
                    if (av_interleaved_write_frame(fmtCtx, audioPkt) < 0) {
                        m_exportError.store(true);
                        goto export_cleanup;
                    }
                    av_packet_unref(audioPkt);
                }
            }

            // Write trailer — v1.0.2: only a successful trailer counts as a
            // completed write (a failed trailer means a truncated file).
            if (av_write_trailer(fmtCtx) >= 0) {
                writeCompleted = true;
            } else {
                m_exportError.store(true);
            }

            // Get file size
            if (fmtCtx->pb) {
                m_exportFileSize.store(avio_size(fmtCtx->pb));
            }
        }
    } // end outer if (fmtCtx && ...)

    // v0.7.8: avio_open failure jumps here (skips encode, still cleans up)
export_cleanup:
    if (swsCtx) sws_freeContext(swsCtx);
    av_packet_free(&encPkt);
    av_frame_free(&encFrame);
    avcodec_free_context(&encCtx);
    // v0.8.0: Audio resources — created in the outer scope (before the
    // header), so they are freed here for every exit path.
    if (audioSwr) swr_free(&audioSwr);
    av_packet_free(&audioPkt);
    av_frame_free(&audioFrame);
    avcodec_free_context(&audioEncCtx);
    if (fmtCtx && !(fmtCtx->oformat->flags & AVFMT_NOFILE)) {
        avio_closep(&fmtCtx->pb);
    }
    avformat_free_context(fmtCtx);

    // v0.8.0: Capture the real output size — avio_size() on the (possibly
    // already-closed) pb was unreliable and reported 0 for a valid file,
    // which made the Dart side treat a successful export as a failure
    // (its success rule is progress >= 1.0 AND fileSize > 0).
    if (writeCompleted) {
        std::ifstream fs(outputPath, std::ios::binary | std::ios::ate);
        if (fs.good()) {
            m_exportFileSize.store(static_cast<int64_t>(fs.tellg()));
        }
    }
#else
    // Fallback: write raw RGBA data (legacy behavior, no FFmpeg available)
    std::unique_ptr<FILE, int(*)(FILE*)> outFile(nullptr, fclose);
    if (!outputPath.empty()) {
        FILE* rawFp = fopen(outputPath.c_str(), "wb");
        if (rawFp) outFile.reset(rawFp);
    }

    for (int frame = 0; frame < totalFrames; ++frame) {
        if (m_cancelExportFlag.load()) break;

        int64_t frameTimeMs = static_cast<int64_t>(
            (static_cast<float>(frame) / fps) * 1000.0f);
        // v0.7.9: Deep-review — same decode-failure guard as the FFmpeg path.
        if (!decoder.decodeFrame(frameBuffer.data(), width, height, frameTimeMs,
                                  m_activeFilterType, m_filterIntensity.load())) {
            m_exportError.store(true);
            break;
        }

        if (outFile) {
            fwrite(frameBuffer.data(), 1, frameBuffer.size(), outFile.get());
            m_exportFileSize.store(static_cast<int64_t>(outFile ? ftell(outFile.get()) : 0));
        }

        float progress = static_cast<float>(frame + 1) / static_cast<float>(totalFrames);
        m_exportProgress.store(progress);
    }
    if (outFile) writeCompleted = true;
#endif

    if (!writeCompleted && !m_cancelExportFlag.load()) {
        m_exportError.store(true);
    }

    m_isExporting.store(false);
    if (!m_cancelExportFlag.load() && !m_exportError.load()) {
        m_exportProgress.store(1.0f);
    }
}

float GhitaEngine::getExportProgress() const {
    return m_exportProgress.load();
}

bool GhitaEngine::isExporting() const {
    return m_isExporting.load();
}

void GhitaEngine::cancelExport() {
    if (m_isExporting.load()) {
        m_cancelExportFlag.store(true);
        // v0.7.8: Serialize joins — destructor and cancelExport can run from
        // different threads; a second join() on the same std::thread throws.
        std::lock_guard<std::mutex> joinLock(m_exportJoinMutex);
        if (m_exportThread.joinable() && std::this_thread::get_id() != m_exportThread.get_id()) {
            m_exportThread.join();
        }
    }
}

// ========== SELF TEST ==========

bool GhitaEngine::selfTest() {
    GhitaEngine engine;
    if (!engine.initialize()) return false;
    if (!engine.renderFrameRGBA(nullptr, 1, 1)) return false;

    uint8_t buf[16] = {};
    if (!engine.renderFrameRGBA(buf, 4, 4)) return false;

    // Verify alpha is opaque
    for (int i = 0; i < 4; ++i) {
        if (buf[i * 4 + 3] != 255) return false;
    }

    // Test clip operations
    int id = engine.addClip("test.mp4", 0, 5000, 0);
    if (id <= 0) return false;
    if (engine.getClipCount() != 1) return false;

    // Test keyframe
    if (!engine.addClipKeyframe(id, 0, 0.0f)) return false;
    if (!engine.addClipKeyframe(id, 5000, 1.0f)) return false;
    if (!engine.clearClipKeyframes(id)) return false;

    // Test export start/cancel
    if (!engine.startExport("test_out.mp4", 1920, 1080, 60)) return false;
    engine.cancelExport();
    if (engine.isExporting()) return false;

    // Test media info
    engine.loadMedia("test.mp4");
    std::string infoJson = engine.getMediaInfoJson();
    if (infoJson.empty()) return false;

    return true;
}
