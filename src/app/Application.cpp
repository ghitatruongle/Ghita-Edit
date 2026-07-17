#include "Application.h"
#include "render/PreviewSurface.h"
#include "audio/AudioMixerController.h"
#include "timeline/TimelineModel.h"
#include "fx/VideoFXEffects.h"

#include <QGuiApplication>
#include <QQmlContext>
#include <QDebug>
#include <QFile>
#include <QTextStream>

namespace ghita::app {

Application::Application(QObject* parent)
    : QObject(parent),
      mediaEngine_(&audioEngine_, this),
      audioEngine_(this),
      timelineModel_(this),
      snapEngine_(this),
      scrubEngine_(this) {
    mediaEngine_.setTimeline(&timelineModel_);
}

bool Application::initialize() {
    if (!audioEngine_.init()) {
        qWarning() << "[Application] audio init failed - continuing without audio";
    }

    qmlEngine_.rootContext()->setContextProperty("mediaEngine", &mediaEngine_);
    qmlEngine_.rootContext()->setContextProperty("audioEngine", &audioEngine_);
    qmlEngine_.rootContext()->setContextProperty("timeline", &timelineModel_);
    qmlEngine_.rootContext()->setContextProperty("snapEngine", &snapEngine_);
    qmlEngine_.rootContext()->setContextProperty("scrubEngine", &scrubEngine_);
    qmlEngine_.rootContext()->setContextProperty("exporter", &exporter_);
    qmlEngine_.rootContext()->setContextProperty("fx", &fxController_);
    qmlEngine_.rootContext()->setContextProperty("mediaBinModel", &mediaBinModel_);
    qmlEngine_.rootContext()->setContextProperty("appState", &appState_);

    // Per-track / master audio mixer bridge.
    auto* audioMixer = new ghita::audio::AudioMixerController(&audioEngine_, this);
    qmlEngine_.rootContext()->setContextProperty("audioMixer", audioMixer);

    // The exporter reads effect parameters from the shared FxController.
    exporter_.setFxController(&fxController_);

    // Wire FxController into PreviewSurface for real-time effect preview.
    qmlEngine_.rootContext()->setContextProperty("fxControllerPtr", &fxController_);

    // Expose the exporter's progress signal so QML can drive the taskbar
    // progress bar via the WindowsPlatformHelper.
    QObject::connect(&exporter_, &export_::Exporter::progressChanged,
                     this, &Application::exportProgressUpdated);
    QObject::connect(&exporter_, &export_::Exporter::exportFinished,
                     this, &Application::exportFinishedSignal);

    // Register the OpenGL preview surface as a QML type.
    qmlRegisterType<ghita::render::PreviewSurface>("Ghita.Render", 1, 0, "PreviewSurface");

    // Register the EffectType enum so QML can reference it.
    qmlRegisterUncreatableMetaType<ghita::fx::EffectType>(
        "Ghita.Fx", 1, 0, "EffectType",
        "EffectType is an enum -- use fx.addEffect(typeName) instead.");

    // Register GhitaTheme singletons directly (avoid QRC qmldir resolution issues).
    qmlRegisterSingletonType(QUrl("qrc:/Theme.qml"), "GhitaTheme", 1, 0, "Theme");
    qmlRegisterSingletonType(QUrl("qrc:/Icons.qml"), "GhitaTheme", 1, 0, "Icons");

    // Surface QML load/parse errors (the engine's default handler routes
    // them to qWarning, but make sure they are explicit). Also mirror them to
    // a log file since a Windows-subsystem build discards stderr.
    QObject::connect(&qmlEngine_, &QQmlApplicationEngine::warnings,
                     this, [](const QList<QQmlError>& warnings) {
                         for (const auto& w : warnings) {
                             qWarning() << "[QML]" << w.toString();
                             QFile f("ghita_qml.log");
                             if (f.open(QIODevice::Append | QIODevice::Text)) {
                                 QTextStream ts(&f);
                                 ts << "[QML] " << w.toString() << "\n";
                             }
                         }
                     });

    // QML is embedded via Qt resource (see ghita_qml.qrc generated in CMake).
    qmlEngine_.load(QUrl(QStringLiteral("qrc:/Main.qml")));
    if (qmlEngine_.rootObjects().isEmpty()) {
        qCritical() << "[Application] Failed to load Main.qml (see QML warnings above)";
        QFile f("ghita_qml.log");
        if (f.open(QIODevice::Append | QIODevice::Text)) {
            QTextStream ts(&f);
            ts << "[Application] Failed to load Main.qml\n";
        }
        return false;
    }
    qInfo() << "[Application] Ghita Edit started (stub build)";
    QFile f("ghita_qml.log");
    if (f.open(QIODevice::Append | QIODevice::Text)) {
        QTextStream ts(&f);
        ts << "[Application] Ghita Edit started OK\n";
    }
    return true;
}

} // namespace ghita::app
