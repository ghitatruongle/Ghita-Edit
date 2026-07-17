#pragma once

#include "engine/MediaEngine.h"
#include "audio/AudioEngine.h"
#include "timeline/TimelineModel.h"
#include "timeline/SnapEngine.h"
#include "export/Exporter.h"
#include "fx/FxController.h"
#include "engine/ScrubEngine.h"
#include "MediaBinModel.h"
#include "AppState.h"

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
    // Declaration order matters: C++ initializes members in declaration order.
    // audioEngine_ must be declared before mediaEngine_ because
    // MediaEngine's constructor takes an AudioEngine pointer.
    audio::AudioEngine audioEngine_;
    engine::MediaEngine mediaEngine_;
    timeline::TimelineModel timelineModel_;
    timeline::SnapEngine snapEngine_;
    export_::Exporter exporter_;
    fx::FxController fxController_;
    MediaBinModel mediaBinModel_;
    AppState appState_;
    engine::ScrubEngine scrubEngine_;
    QQmlApplicationEngine qmlEngine_;
signals:
    // Forwarded from the Exporter so main.cpp can wire the taskbar progress.
    void exportProgressUpdated(int percent);
    void exportFinishedSignal(bool success);
};

} // namespace ghita::app
