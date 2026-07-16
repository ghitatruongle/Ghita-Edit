#pragma once

#include <QImage>
#include <QString>
#include <vector>
#include <functional>

namespace ghita::fx {

// Effect types supported in the real-time preview chain.
enum class EffectType {
    BrightnessContrast,
    Blur,
    Sharpen,
    Vignette
};

// Represents a single effect instance in the chain.
struct EffectEntry {
    EffectType type = EffectType::BrightnessContrast;
    bool enabled = true;
    double intensity = 1.0; // [0, 1]

    // Per-effect parameters.
    double brightness = 0.0; // [-1, 1]
    double contrast = 1.0;   // [0, 2]
    double blurRadius = 3.0; // [0, 20]
    double vignetteStrength = 0.5; // [0, 1]

    QString displayName() const;
    QString icon() const;
};

// VideoFXEffects: CPU-based image effects applied via QPainter / QImage
// operations. Optimised for real-time preview (runs at frame rate on the
// QSG render thread). These effects mirror the colour-grade path in
// VideoFX but operate on RGBA QImage data so they compose correctly with
// the PreviewSurface texture pipeline.
class VideoFXEffects {
public:
    // Apply the effect chain to `img` (RGBA, in-place). Effects are applied
    // in the order they appear in `chain`. Disabled effects are skipped.
    static void applyChain(QImage& img,
                           const std::vector<EffectEntry>& chain);

    // ---- Individual effect implementations ----

    // Brightness/contrast: adjust luma via RGB space.
    static void applyBrightnessContrast(QImage& img, double brightness,
                                        double contrast, double intensity);

    // Box blur approximation via repeated QImage blurring.
    static void applyBlur(QImage& img, double radius, double intensity);

    // Unsharp mask for sharpening.
    static void applySharpen(QImage& img, double amount, double intensity);

    // Radial gradient vignette (darken edges).
    static void applyVignette(QImage& img, double strength, double intensity);

    // Resolve a preset name to a list of effect entries.
    static std::vector<EffectEntry> loadPreset(const QString& name);

    // List of available preset names.
    static QStringList availablePresets();

private:
    // Helper: apply a separable box blur kernel via QImage::scaled trick.
    static void boxBlur(QImage& img, int radius);
};

} // namespace ghita::fx
