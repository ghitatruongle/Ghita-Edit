#include "VideoFXEffects.h"

#include <QPainter>
#include <QtMath>
#include <algorithm>
#include <cmath>

namespace ghita::fx {

// ---- EffectEntry helpers ----

QString EffectEntry::displayName() const {
    switch (type) {
        case EffectType::BrightnessContrast: return "Brightness / Contrast";
        case EffectType::Blur:               return "Blur";
        case EffectType::Sharpen:            return "Sharpen";
        case EffectType::Vignette:           return "Vignette";
    }
    return "Unknown";
}

QString EffectEntry::icon() const {
    switch (type) {
        case EffectType::BrightnessContrast: return "\u2600"; // sun
        case EffectType::Blur:               return "\u25CE"; // circle
        case EffectType::Sharpen:            return "\u27A4"; // arrow
        case EffectType::Vignette:           return "\u25CF"; // dot
    }
    return "";
}

// ---- Chain application ----

void VideoFXEffects::applyChain(QImage& img,
                                const std::vector<EffectEntry>& chain) {
    if (img.isNull()) return;

    for (const auto& fx : chain) {
        if (!fx.enabled) continue;

        switch (fx.type) {
            case EffectType::BrightnessContrast:
                applyBrightnessContrast(img, fx.brightness, fx.contrast, fx.intensity);
                break;
            case EffectType::Blur:
                applyBlur(img, fx.blurRadius, fx.intensity);
                break;
            case EffectType::Sharpen:
                applySharpen(img, fx.intensity, fx.intensity);
                break;
            case EffectType::Vignette:
                applyVignette(img, fx.vignetteStrength, fx.intensity);
                break;
        }
    }
}

// ---- Brightness / Contrast ----

void VideoFXEffects::applyBrightnessContrast(QImage& img, double brightness,
                                              double contrast, double intensity) {
    if (img.isNull()) return;

    // Scale parameters by intensity so the slider controls effect strength.
    const double b = brightness * intensity;
    const double c = 1.0 + (contrast - 1.0) * intensity;

    if (b == 0.0 && c == 1.0) return;

    const int w = img.width();
    const int h = img.height();

    for (int y = 0; y < h; ++y) {
        uint32_t* row = reinterpret_cast<uint32_t*>(img.scanLine(y));
        for (int x = 0; x < w; ++x) {
            uint32_t p = row[x];
            double r = qRed(p);
            double g = qGreen(p);
            double bl = qBlue(p);

            r = r * c + b * 255.0;
            g = g * c + b * 255.0;
            bl = bl * c + b * 255.0;

            r = qBound(0.0, r, 255.0);
            g = qBound(0.0, g, 255.0);
            bl = qBound(0.0, bl, 255.0);

            row[x] = qRgba(static_cast<int>(r),
                           static_cast<int>(g),
                           static_cast<int>(bl),
                           qAlpha(p));
        }
    }
}

// ---- Blur (box blur via multi-pass scaling) ----

void VideoFXEffects::applyBlur(QImage& img, double radius, double intensity) {
    if (img.isNull()) return;

    const int effectiveRadius = qBound(1, static_cast<int>(radius * intensity * 10), 100);
    if (effectiveRadius < 1) return;

    // Multi-pass downscale/upscale approach for performance.
    QImage blurred = img.scaled(img.width() / (effectiveRadius / 3 + 1),
                                 img.height() / (effectiveRadius / 3 + 1),
                                 Qt::IgnoreAspectRatio,
                                 Qt::SmoothTransformation);
    blurred = blurred.scaled(img.width(), img.height(),
                             Qt::IgnoreAspectRatio,
                             Qt::SmoothTransformation);

    // Blend original and blurred by intensity.
    if (intensity >= 1.0) {
        img = std::move(blurred);
    } else {
        QPainter painter(&img);
        painter.setCompositionMode(QPainter::CompositionMode_SourceOver);
        painter.setOpacity(1.0 - intensity);
        painter.drawImage(0, 0, img);
        painter.setOpacity(intensity);
        painter.drawImage(0, 0, blurred);
        painter.end();
    }
}

// ---- Sharpen (unsharp mask) ----

void VideoFXEffects::applySharpen(QImage& img, double amount, double intensity) {
    if (img.isNull()) return;

    const double effectiveAmount = amount * intensity;
    if (effectiveAmount <= 0.01) return;

    // Create a slightly blurred version for the mask.
    QImage blurred = img.scaled(img.width() / 2, img.height() / 2,
                                Qt::IgnoreAspectRatio,
                                Qt::SmoothTransformation);
    blurred = blurred.scaled(img.width(), img.height(),
                             Qt::IgnoreAspectRatio,
                             Qt::SmoothTransformation);

    // Unsharp mask: sharpened = original + amount * (original - blurred)
    const int w = img.width();
    const int h = img.height();
    for (int y = 0; y < h; ++y) {
        uint32_t* origRow = reinterpret_cast<uint32_t*>(img.scanLine(y));
        uint32_t* blurRow = reinterpret_cast<uint32_t*>(blurred.scanLine(y));
        for (int x = 0; x < w; ++x) {
            uint32_t orig = origRow[x];
            uint32_t blur = blurRow[x];

            double or_ = qRed(orig);
            double og = qGreen(orig);
            double ob = qBlue(orig);
            double br = qRed(blur);
            double bg = qGreen(blur);
            double bb = qBlue(blur);

            or_ = or_ + effectiveAmount * (or_ - br);
            og = og + effectiveAmount * (og - bg);
            ob = ob + effectiveAmount * (ob - bb);

            or_ = qBound(0.0, or_, 255.0);
            og = qBound(0.0, og, 255.0);
            ob = qBound(0.0, ob, 255.0);

            origRow[x] = qRgba(static_cast<int>(or_),
                               static_cast<int>(og),
                               static_cast<int>(ob),
                               qAlpha(orig));
        }
    }
}

// ---- Vignette (radial gradient darkening) ----

void VideoFXEffects::applyVignette(QImage& img, double strength, double intensity) {
    if (img.isNull()) return;

    const double effectiveStrength = strength * intensity;
    if (effectiveStrength <= 0.01) return;

    const int w = img.width();
    const int h = img.height();
    const double cx = w / 2.0;
    const double cy = h / 2.0;
    const double maxDist = std::abs(cx) + std::abs(cy);

    for (int y = 0; y < h; ++y) {
        uint32_t* row = reinterpret_cast<uint32_t*>(img.scanLine(y));
        for (int x = 0; x < w; ++x) {
            double dist = std::abs(x - cx) + std::abs(y - cy);
            double norm = dist / maxDist;

            // Smooth falloff: vignette kicks in after 40% from center.
            double factor = 1.0;
            if (norm > 0.4) {
                factor = 1.0 - (norm - 0.4) / 0.6;
                factor = qBound(0.0, factor, 1.0);
            }
            factor = 1.0 - effectiveStrength * (1.0 - factor);
            factor = qBound(0.0, factor, 1.0);

            uint32_t p = row[x];
            row[x] = qRgba(static_cast<int>(qRed(p) * factor),
                           static_cast<int>(qGreen(p) * factor),
                           static_cast<int>(qBlue(p) * factor),
                           qAlpha(p));
        }
    }
}

// ---- Presets ----

std::vector<EffectEntry> VideoFXEffects::loadPreset(const QString& name) {
    std::vector<EffectEntry> chain;

    auto add = [&](EffectType type, bool enabled, double intensity,
                   double brightness, double contrast,
                   double blurRadius, double vignetteStrength) {
        EffectEntry e;
        e.type = type;
        e.enabled = enabled;
        e.intensity = intensity;
        e.brightness = brightness;
        e.contrast = contrast;
        e.blurRadius = blurRadius;
        e.vignetteStrength = vignetteStrength;
        chain.push_back(std::move(e));
    };

    if (name == "Cinematic") {
        add(EffectType::BrightnessContrast, true, 1.0, -0.02, 1.15, 0, 0);
        add(EffectType::Blur, false, 0, 0, 1, 3, 0);
        add(EffectType::Sharpen, true, 0.3, 0, 1, 0, 0);
        add(EffectType::Vignette, true, 0.8, 0, 1, 0, 0.6);
    } else if (name == "Vintage") {
        add(EffectType::BrightnessContrast, true, 1.0, 0.05, 1.1, 0, 0);
        add(EffectType::Blur, false, 0, 0, 1, 1, 0);
        add(EffectType::Sharpen, false, 0, 0, 1, 0, 0);
        add(EffectType::Vignette, true, 0.6, 0, 1, 0, 0.4);
    } else if (name == "HDR") {
        add(EffectType::BrightnessContrast, true, 1.0, 0.0, 1.3, 0, 0);
        add(EffectType::Blur, false, 0, 0, 1, 0, 0);
        add(EffectType::Sharpen, true, 1.0, 0, 1, 0, 0);
        add(EffectType::Vignette, false, 0, 0, 1, 0, 0);
    } else if (name == "Soft") {
        add(EffectType::BrightnessContrast, true, 0.5, 0.02, 0.95, 0, 0);
        add(EffectType::Blur, true, 0.3, 0, 1, 2, 0);
        add(EffectType::Sharpen, false, 0, 0, 1, 0, 0);
        add(EffectType::Vignette, false, 0, 0, 1, 0, 0);
    } else if (name == "Dramatic") {
        add(EffectType::BrightnessContrast, true, 1.0, -0.05, 1.3, 0, 0);
        add(EffectType::Blur, false, 0, 0, 1, 0, 0);
        add(EffectType::Sharpen, true, 0.4, 0, 1, 0, 0);
        add(EffectType::Vignette, true, 1.0, 0, 1, 0, 0.8);
    } else if (name == "Fresh") {
        add(EffectType::BrightnessContrast, true, 1.0, 0.03, 1.05, 0, 0);
        add(EffectType::Blur, false, 0, 0, 1, 0, 0);
        add(EffectType::Sharpen, true, 0.2, 0, 1, 0, 0);
        add(EffectType::Vignette, false, 0, 0, 1, 0, 0);
    } else {
        // Identity: no effects.
    }

    return chain;
}

QStringList VideoFXEffects::availablePresets() {
    return { "None", "Cinematic", "Vintage", "HDR", "Soft", "Dramatic", "Fresh" };
}

} // namespace ghita::fx
