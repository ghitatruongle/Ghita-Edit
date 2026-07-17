#include "app/Application.h"
#if defined(Q_OS_WIN)
#include "platform/WindowsPlatformHelper.h"
#endif

#include <QGuiApplication>
#include <QScreen>
#include <QQuickStyle>

int main(int argc, char* argv[]) {
    // Enable Qt HiDPI / DPI-aware scaling so all layout, font, and icon
    // sizes scale proportionally on high-DPI displays (e.g. 150 %, 200 %,
    // 300 %).  Qt6 also respects the OS per-monitor DPI policy.
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);

    // Use Basic style to avoid Windows-native style customization warnings
    QQuickStyle::setStyle("Basic");

    QGuiApplication app(argc, argv);
    app.setApplicationName("Ghita Edit");
    app.setOrganizationName("Ghita");
    app.setApplicationVersion("0.0.0");

    ghita::app::Application ghita(&app);
    if (!ghita.initialize()) {
        return 1;
    }

#if defined(Q_OS_WIN)
    // Create the Windows native-integration helper with app as parent so it
    // is destroyed before ghita signals fire at shutdown.
    ghita::platform::WindowsPlatformHelper* winPlatform = new ghita::platform::WindowsPlatformHelper(&app);
    // Wire the exporter progress signal into the taskbar progress bar.
    QObject::connect(&ghita, &ghita::app::Application::exportProgressUpdated,
                     winPlatform,
                     &ghita::platform::WindowsPlatformHelper::onExportProgressFromExporter);
    QObject::connect(&ghita, &ghita::app::Application::exportFinishedSignal,
                     winPlatform,
                     &ghita::platform::WindowsPlatformHelper::onExportFinishedFromExporter);
#endif

    return app.exec();
}
