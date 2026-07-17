#pragma once

#include <QMutex>
#include <QObject>
#include <QString>
#include <vector>
#include <functional>

#include "VideoFXEffects.h"

namespace ghita::fx {

// FxController: holds the global effect parameters edited in the UI and read
// by the Exporter during render (M2 audio DSP + M3 video FX).
//
// Extended for real-time preview: manages an effect chain (Brightness/Contrast,
// Blur, Sharpen, Vignette) with per-effect on/off toggles, intensity sliders,
// and reorderable layers. Also supports applying preset chains instantly.
class FxController : public QObject {
    Q_OBJECT

    // --- Legacy colour-grade properties (unchanged) ---
    Q_PROPERTY(double brightness READ brightness WRITE setBrightness NOTIFY changed)
    Q_PROPERTY(double contrast   READ contrast   WRITE setContrast   NOTIFY changed)
    Q_PROPERTY(double saturation READ saturation WRITE setSaturation NOTIFY changed)
    Q_PROPERTY(double temperature READ temperature WRITE setTemperature NOTIFY changed)
    Q_PROPERTY(double tint       READ tint       WRITE setTint       NOTIFY changed)
    Q_PROPERTY(double highlight READ highlight WRITE setHighlight NOTIFY changed)
    Q_PROPERTY(double shadow    READ shadow    WRITE setShadow    NOTIFY changed)
    Q_PROPERTY(double hueShift   READ hueShift   WRITE setHueShift   NOTIFY changed)
    Q_PROPERTY(double dryWet     READ dryWet     WRITE setDryWet     NOTIFY changed)
    Q_PROPERTY(double gainDb     READ gainDb     WRITE setGainDb     NOTIFY changed)
    Q_PROPERTY(bool   normalize  READ normalize  WRITE setNormalize  NOTIFY changed)
    Q_PROPERTY(int    fadeInMs   READ fadeInMs   WRITE setFadeInMs   NOTIFY changed)
    Q_PROPERTY(int    fadeOutMs  READ fadeOutMs  WRITE setFadeOutMs  NOTIFY changed)

    // --- New: effect chain ---
    Q_PROPERTY(QString currentPreset READ currentPreset WRITE setCurrentPreset NOTIFY currentPresetChanged)

public:
    explicit FxController(QObject* parent = nullptr) : QObject(parent) {}

    // Legacy colour-grade getters/setters.
    double brightness() const { return brightness_; }
    double contrast()   const { return contrast_; }
    double saturation() const { return saturation_; }
    double temperature() const { return temperature_; }
    double tint()       const { return tint_; }
    double highlight()  const { return highlight_; }
    double shadow()     const { return shadow_; }
    double hueShift()   const { return hueShift_; }
    double dryWet()     const { return dryWet_; }
    double gainDb()     const { return gainDb_; }
    bool   normalize()  const { return normalize_; }
    int    fadeInMs()   const { return fadeInMs_; }
    int    fadeOutMs()  const { return fadeOutMs_; }

public slots:
    // Legacy setters.
    void setBrightness(double v) { if (v!=brightness_){ brightness_=v; emit changed(); } }
    void setContrast(double v)   { if (v!=contrast_)  { contrast_=v;   emit changed(); } }
    void setSaturation(double v) { if (v!=saturation_){ saturation_=v; emit changed(); } }
    void setTemperature(double v) { if (v!=temperature_){ temperature_=v; emit changed(); } }
    void setTint(double v)       { if (v!=tint_){ tint_=v; emit changed(); } }
    void setHighlight(double v)  { if (v!=highlight_){ highlight_=v; emit changed(); } }
    void setShadow(double v)     { if (v!=shadow_){ shadow_=v; emit changed(); } }
    void setHueShift(double v)   { if (v!=hueShift_){ hueShift_=v; emit changed(); } }
    void setDryWet(double v)     { if (v!=dryWet_){ dryWet_=v; emit changed(); } }
    void setGainDb(double v)     { if (v!=gainDb_)    { gainDb_=v;     emit changed(); } }
    void setNormalize(bool v)    { if (v!=normalize_) { normalize_=v;  emit changed(); } }
    void setFadeInMs(int v)      { if (v!=fadeInMs_)  { fadeInMs_=v;   emit changed(); } }
    void setFadeOutMs(int v)     { if (v!=fadeOutMs_) { fadeOutMs_=v;  emit changed(); } }

    // Reset everything to identity.
    void reset() {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        brightness_ = 0.0; contrast_ = 1.0; saturation_ = 1.0;
        temperature_ = 0.0; tint_ = 0.0; highlight_ = 0.0; shadow_ = 0.0;
        hueShift_ = 0.0; dryWet_ = 1.0;
        gainDb_ = 0.0; normalize_ = false; fadeInMs_ = 0; fadeOutMs_ = 0;
        effectChain_.clear();
        currentPreset_ = "None";
        emit changed();
        emit effectChainChanged();
        emit currentPresetChanged(currentPreset_);
    }

    // ---- Effect chain management ----

    // Get the current effect chain (copy).
    std::vector<EffectEntry> effectChain() const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        return effectChain_;
    }

    // Set the effect chain (full replacement).
    void setEffectChain(const std::vector<EffectEntry>& chain) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        effectChain_ = chain;
        emit effectChainChanged();
    }

    // Apply a preset by name. Clears existing chain and loads the preset.
    void applyPreset(const QString& name) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (name.isEmpty() || name == "None") {
            effectChain_.clear();
            currentPreset_ = "None";
        } else {
            effectChain_ = VideoFXEffects::loadPreset(name);
            currentPreset_ = name;
        }
        emit currentPresetChanged(currentPreset_);
        emit effectChainChanged();
    }

    // Get current preset name.
    QString currentPreset() const { return currentPreset_; }
    void setCurrentPreset(const QString& name) { applyPreset(name); }

    // ---- Per-effect manipulation ----

    // Add an effect by string name (convenient for QML).
    Q_INVOKABLE void addEffectByName(const QString& name) {
        if (name == "brightness") addEffect(EffectType::BrightnessContrast);
        else if (name == "blur") addEffect(EffectType::Blur);
        else if (name == "sharpen") addEffect(EffectType::Sharpen);
        else if (name == "vignette") addEffect(EffectType::Vignette);
    }

    // Add an effect entry to the chain.
    Q_INVOKABLE void addEffect(EffectType type) {
        EffectEntry e;
        e.type = type;
        e.enabled = true;
        e.intensity = 1.0;
        switch (type) {
            case EffectType::BrightnessContrast:
                e.brightness = 0.0; e.contrast = 1.0; break;
            case EffectType::Blur:
                e.blurRadius = 3.0; break;
            case EffectType::Sharpen:
                break;
            case EffectType::Vignette:
                e.vignetteStrength = 0.5; break;
        }
        std::lock_guard<QMutex> lk(effectChainMutex_);
        effectChain_.push_back(std::move(e));
        emit effectChainChanged();
    }

    // Remove an effect by index.
    Q_INVOKABLE void removeEffect(int index) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return;
        effectChain_.erase(effectChain_.begin() + index);
        emit effectChainChanged();
    }

    // Toggle an effect on/off.
    Q_INVOKABLE void setEffectEnabled(int index, bool enabled) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return;
        effectChain_[index].enabled = enabled;
        emit effectChainChanged();
    }

    // Set effect intensity (0..1).
    Q_INVOKABLE void setEffectIntensity(int index, double intensity) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return;
        effectChain_[index].intensity = qBound(0.0, intensity, 1.0);
        emit effectChainChanged();
    }

    // Set brightness for the brightness/contrast effect at index.
    Q_INVOKABLE void setEffectBrightness(int index, double val) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return;
        if (effectChain_[index].type == EffectType::BrightnessContrast) {
            effectChain_[index].brightness = val;
            emit effectChainChanged();
        }
    }

    // Set contrast for the brightness/contrast effect at index.
    Q_INVOKABLE void setEffectContrast(int index, double val) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return;
        if (effectChain_[index].type == EffectType::BrightnessContrast) {
            effectChain_[index].contrast = val;
            emit effectChainChanged();
        }
    }

    // Set blur radius.
    Q_INVOKABLE void setEffectBlurRadius(int index, double val) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return;
        if (effectChain_[index].type == EffectType::Blur) {
            effectChain_[index].blurRadius = val;
            emit effectChainChanged();
        }
    }

    // Set vignette strength.
    Q_INVOKABLE void setEffectVignetteStrength(int index, double val) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return;
        if (effectChain_[index].type == EffectType::Vignette) {
            effectChain_[index].vignetteStrength = val;
            emit effectChainChanged();
        }
    }

    // Move an effect up in the chain (swap with previous).
    Q_INVOKABLE void moveEffectUp(int index) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index <= 0 || index >= static_cast<int>(effectChain_.size())) return;
        std::swap(effectChain_[index], effectChain_[index - 1]);
        emit effectChainChanged();
    }

    // Move an effect down in the chain (swap with next).
    Q_INVOKABLE void moveEffectDown(int index) {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size()) - 1) return;
        std::swap(effectChain_[index], effectChain_[index + 1]);
        emit effectChainChanged();
    }

    // Get the number of effects in the chain.
    Q_INVOKABLE int effectCount() const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        return static_cast<int>(effectChain_.size());
    }

    // Get effect type name at index (for QML display).
    Q_INVOKABLE QString effectTypeName(int index) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return "";
        switch (effectChain_[index].type) {
            case EffectType::BrightnessContrast: return "BrightnessContrast";
            case EffectType::Blur:               return "Blur";
            case EffectType::Sharpen:            return "Sharpen";
            case EffectType::Vignette:           return "Vignette";
        }
        return "";
    }

    // Get effect display name at index.
    Q_INVOKABLE QString effectDisplayName(int index) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return "";
        return effectChain_[index].displayName();
    }

    // Get effect icon at index.
    Q_INVOKABLE QString effectIcon(int index) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return "";
        return effectChain_[index].icon();
    }

    // Get effect enabled at index.
    Q_INVOKABLE bool effectEnabled(int index) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return false;
        return effectChain_[index].enabled;
    }

    // Get effect intensity at index.
    Q_INVOKABLE double effectIntensity(int index) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return 0;
        return effectChain_[index].intensity;
    }

    // Get effect brightness at index.
    Q_INVOKABLE double effectBrightness(int index) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return 0;
        return effectChain_[index].brightness;
    }

    // Get effect contrast at index.
    Q_INVOKABLE double effectContrast(int index) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return 1;
        return effectChain_[index].contrast;
    }

    // Get effect blur radius at index.
    Q_INVOKABLE double effectBlurRadius(int index) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return 3;
        return effectChain_[index].blurRadius;
    }

    // Get effect vignette strength at index.
    Q_INVOKABLE double effectVignetteStrength(int index) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (index < 0 || index >= static_cast<int>(effectChain_.size())) return 0.5;
        return effectChain_[index].vignetteStrength;
    }

    // List available presets for QML.
    Q_INVOKABLE static QStringList listPresets() {
        return VideoFXEffects::availablePresets();
    }

    // Apply the current effect chain to an RGBA image (for PreviewSurface).
    void applyEffectsToImage(QImage& img) const {
        std::lock_guard<QMutex> lk(effectChainMutex_);
        if (img.isNull() || effectChain_.empty()) return;
        VideoFXEffects::applyChain(img, effectChain_);
    }

signals:
    void changed();
    void effectChainChanged();
    void currentPresetChanged(const QString& name);

private:
    double brightness_ = 0.0;  // [-1, 1]
    double contrast_   = 1.0;  // [0, 2]
    double saturation_ = 1.0;  // [0, 2]
    double temperature_ = 0.0; // [-100, 100]
    double tint_       = 0.0;  // [-100, 100]
    double highlight_  = 0.0;  // [-1, 1]
    double shadow_     = 0.0;  // [-1, 1]
    double hueShift_   = 0.0;  // [-180, 180]
    double dryWet_     = 1.0;  // [0, 1]
    double gainDb_     = 0.0;  // dB
    bool   normalize_  = false;
    int    fadeInMs_   = 0;
    int    fadeOutMs_   = 0;

    // Effect chain (reorderable, each entry is a layer).
    std::vector<EffectEntry> effectChain_;
    QString currentPreset_ = "None";
};

} // namespace ghita::fx
