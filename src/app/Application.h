#pragma once

#include "engine/MediaEngine.h"
#include "audio/AudioEngine.h"
#include "timeline/TimelineModel.h"
#include "timeline/SnapEngine.h"
#include "export/Exporter.h"
#include "fx/FxController.h"
#include "MediaBinModel.h"

#include <QObject>
#include <QQmlApplicationEngine>

namespace ghita::app {

// Application: owns the engine/audio singletons and bridges them to QML.
// Exposes `mediaEngine`, `audioEngine`, `timeline`, `snapEngine`, `exporter`,
// and `fx` as QML context properties.
class Application : public QObject {
    Q_OBJECT

public:
    explicit Application(QObject* parent = nullptr);

    // Build the QML engine and expose context properties. Returns false on
    // load failure.
    bool initialize();

    audio::AudioEngine& audioEngine() { return audioEngine_; }

private:
    engine::MediaEngine mediaEngine_;
    audio::AudioEngine audioEngine_;
    timeline::TimelineModel timelineModel_;
    timeline::SnapEngine snapEngine_;
    export_::Exporter exporter_;
    fx::FxController fxController_;
    MediaBinModel mediaBinModel_;
    QQmlApplicationEngine qmlEngine_;
};

} // namespace ghita::app
