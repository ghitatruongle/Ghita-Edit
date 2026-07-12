#include "Application.h"
#include "render/PreviewSurface.h"

#include <QGuiApplication>
#include <QQmlContext>
#include <QDebug>

namespace ghita::app {

Application::Application(QObject* parent)
    : QObject(parent),
      mediaEngine_(&audioEngine_, this),
      audioEngine_(this),
      timelineModel_(this),
      snapEngine_(this) {}

bool Application::initialize() {
    if (!audioEngine_.init()) {
        qWarning() << "[Application] audio init failed - continuing without audio";
    }

    qmlEngine_.rootContext()->setContextProperty("mediaEngine", &mediaEngine_);
    qmlEngine_.rootContext()->setContextProperty("audioEngine", &audioEngine_);
    qmlEngine_.rootContext()->setContextProperty("timeline", &timelineModel_);
    qmlEngine_.rootContext()->setContextProperty("snapEngine", &snapEngine_);
    qmlEngine_.rootContext()->setContextProperty("exporter", &exporter_);
    qmlEngine_.rootContext()->setContextProperty("fx", &fxController_);
    qmlEngine_.rootContext()->setContextProperty("mediaBinModel", &mediaBinModel_);

    // The exporter reads effect parameters from the shared FxController.
    exporter_.setFxController(&fxController_);

    // Register the OpenGL preview surface as a QML type.
    qmlRegisterType<ghita::render::PreviewSurface>("Ghita.Render", 1, 0, "PreviewSurface");

    // Register GhitaTheme singletons directly (avoid QRC qmldir resolution issues).
    qmlRegisterSingletonType(QUrl("qrc:/Theme.qml"), "GhitaTheme", 1, 0, "Theme");
    qmlRegisterSingletonType(QUrl("qrc:/Icons.qml"), "GhitaTheme", 1, 0, "Icons");

    // Surface QML load/parse errors (the engine's default handler routes
    // them to qWarning, but make sure they are explicit).
    QObject::connect(&qmlEngine_, &QQmlApplicationEngine::warnings,
                     this, [](const QList<QQmlError>& warnings) {
                         for (const auto& w : warnings)
                             qWarning() << "[QML]" << w.toString();
                     });

    // QML is embedded via Qt resource (see ghita_qml.qrc generated in CMake).
    qmlEngine_.load(QUrl(QStringLiteral("qrc:/Main.qml")));
    if (qmlEngine_.rootObjects().isEmpty()) {
        qCritical() << "[Application] Failed to load Main.qml (see QML warnings above)";
        return false;
    }
    qInfo() << "[Application] Ghita Edit started (stub build)";
    return true;
}

} // namespace ghita::app
