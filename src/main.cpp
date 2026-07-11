#include "app/Application.h"

#include <QGuiApplication>

int main(int argc, char* argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("Ghita Edit");
    app.setOrganizationName("Ghita");
    app.setApplicationVersion("0.0.1");

    ghita::app::Application ghita;
    if (!ghita.initialize()) {
        return 1;
    }

    return app.exec();
}
