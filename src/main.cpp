#include "app/Application.h"

#include <QGuiApplication>
#include <QQuickStyle>

int main(int argc, char* argv[]) {
    // Use Basic style to avoid Windows-native style customization warnings
    QQuickStyle::setStyle("Basic");

    QGuiApplication app(argc, argv);
    app.setApplicationName("Ghita Edit");
    app.setOrganizationName("Ghita");
    app.setApplicationVersion("0.1.0");

    ghita::app::Application ghita;
    if (!ghita.initialize()) {
        return 1;
    }

    return app.exec();
}
