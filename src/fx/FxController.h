#pragma once

#include <QObject>

namespace ghita::fx {

// FxController: holds the global effect parameters edited in the UI and read
// by the Exporter during render (M2 audio DSP + M3 video FX).
class FxController : public QObject {
    Q_OBJECT

    Q_PROPERTY(double brightness READ brightness WRITE setBrightness NOTIFY changed)
    Q_PROPERTY(double contrast   READ contrast   WRITE setContrast   NOTIFY changed)
    Q_PROPERTY(double saturation READ saturation WRITE setSaturation NOTIFY changed)
    Q_PROPERTY(double temperature READ temperature WRITE setTemperature NOTIFY changed)
    Q_PROPERTY(double tint       READ tint       WRITE setTint       NOTIFY changed)
    Q_PROPERTY(double gainDb     READ gainDb     WRITE setGainDb     NOTIFY changed)
    Q_PROPERTY(bool   normalize  READ normalize  WRITE setNormalize  NOTIFY changed)
    Q_PROPERTY(int    fadeInMs   READ fadeInMs   WRITE setFadeInMs   NOTIFY changed)
    Q_PROPERTY(int    fadeOutMs  READ fadeOutMs  WRITE setFadeOutMs  NOTIFY changed)

public:
    explicit FxController(QObject* parent = nullptr) : QObject(parent) {}

    double brightness() const { return brightness_; }
    double contrast()   const { return contrast_; }
    double saturation() const { return saturation_; }
    double temperature() const { return temperature_; }
    double tint()       const { return tint_; }
    double gainDb()     const { return gainDb_; }
    bool   normalize()  const { return normalize_; }
    int    fadeInMs()   const { return fadeInMs_; }
    int    fadeOutMs()   const { return fadeOutMs_; }

public slots:
    void setBrightness(double v) { if (v!=brightness_){ brightness_=v; emit changed(); } }
    void setContrast(double v)   { if (v!=contrast_)  { contrast_=v;   emit changed(); } }
    void setSaturation(double v) { if (v!=saturation_){ saturation_=v; emit changed(); } }
    void setTemperature(double v) { if (v!=temperature_){ temperature_=v; emit changed(); } }
    void setTint(double v)       { if (v!=tint_){ tint_=v; emit changed(); } }
    void setGainDb(double v)     { if (v!=gainDb_)    { gainDb_=v;     emit changed(); } }
    void setNormalize(bool v)    { if (v!=normalize_) { normalize_=v;  emit changed(); } }
    void setFadeInMs(int v)      { if (v!=fadeInMs_)  { fadeInMs_=v;   emit changed(); } }
    void setFadeOutMs(int v)     { if (v!=fadeOutMs_) { fadeOutMs_=v;  emit changed(); } }

    // Reset everything to identity.
    void reset() {
        brightness_ = 0.0; contrast_ = 1.0; saturation_ = 1.0;
        temperature_ = 0.0; tint_ = 0.0;
        gainDb_ = 0.0; normalize_ = false; fadeInMs_ = 0; fadeOutMs_ = 0;
        emit changed();
    }

signals:
    void changed();

private:
    double brightness_ = 0.0;  // [-1, 1]
    double contrast_   = 1.0;  // [0, 2]
    double saturation_ = 1.0;  // [0, 2]
    double temperature_ = 0.0; // [-100, 100]
    double tint_       = 0.0;  // [-100, 100]
    double gainDb_     = 0.0;  // dB
    bool   normalize_  = false;
    int    fadeInMs_   = 0;
    int    fadeOutMs_   = 0;
};

} // namespace ghita::fx
