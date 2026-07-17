#pragma once

#include <QObject>
#include <QString>
#include <QSystemTrayIcon>
#include <QWinTaskBarProgress>
#include <QWinJumpList>

#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
#include <QWinUser>
#endif

class QTimer;

namespace ghita::platform {

// Windows-specific native integration.
// Provides: taskbar progress, jump list, system tray, dark-mode detection,
// file-association registration, and native-file-dialog hint.
class WindowsPlatformHelper : public QObject {
    Q_OBJECT

    // Whether the OS is in dark mode.
    Q_PROPERTY(bool darkMode READ darkMode NOTIFY darkModeChanged)

    // Minimize-to-tray enabled/disabled.
    Q_PROPERTY(bool minimizeToTray READ minimizeToTray WRITE setMinimizeToTray
               NOTIFY minimizeToTrayChanged)

    // Current export progress (0-100).
    Q_PROPERTY(int exportProgress READ exportProgress WRITE setExportProgress NOTIFY exportProgressChanged)

    // Whether the system tray icon is visible.
    Q_PROPERTY(bool trayVisible READ trayVisible NOTIFY trayVisibleChanged)

public:
    explicit WindowsPlatformHelper(QObject* parent = nullptr);
    ~WindowsPlatformHelper() override;

    bool darkMode() const { return m_darkMode; }
    bool minimizeToTray() const { return m_minimizeToTray; }
    void setMinimizeToTray(bool v) {
        if (m_minimizeToTray == v) return;
        m_minimizeToTray = v;
        emit minimizeToTrayChanged();
    }
    int exportProgress() const { return m_exportProgress; }
    void setExportProgress(int v) {
        if (v < 0) v = 0;
        if (v > 100) v = 100;
        if (m_exportProgress == v) return;
        m_exportProgress = v;
        emit exportProgressChanged();
        updateTaskbarProgress(v);
    }
    bool trayVisible() const { return m_trayIcon != nullptr && m_trayIcon->isVisible(); }

    // Register .ghita file association so Explorer shows our icon and "Open with Ghita Edit".
    Q_INVOKABLE void registerFileAssociation();

    // Unregister .ghita file association.
    Q_INVOKABLE void unregisterFileAssociation();

    // Add a recent file to the Jump List.
    Q_INVOKABLE void addToRecentFiles(const QString& filePath);

    // Clear all Jump List entries.
    Q_INVOKABLE void clearRecentFiles();

    // Emit a window-state-change signal from QML when the user presses the
    // Windows close button (minimize vs. close).
    Q_INVOKABLE void handleWindowCloseRequest();

    // Open a native file dialog and return the selected path(s).
    Q_INVOKABLE QStringList openNativeFileDialog(const QString& title,
                                                  const QString& filter,
                                                  const QString& initialDir);

    Q_INVOKABLE QString openNativeSaveFileDialog(const QString& title,
                                                  const QString& filter,
                                                  const QString& initialDir,
                                                  const QString& defaultName);

signals:
    void darkModeChanged();
    void minimizeToTrayChanged();
    void exportProgressChanged();
    void trayVisibleChanged();
    void windowStateChanged(Qt::WindowStates state);
    void recentFilesChanged();

    // Requested by QML when user clicks a Jump List category.
    void openNewProjectRequested();
    void openRecentFileRequested(const QString& path);

private slots:
    void onSystemTrayActivated(QSystemTrayIcon::ActivationReason reason);
    void onExportProgressFromExporter(int percent);
    void onExportFinishedFromExporter(bool success);

private:
    void createSystemTray();
    void updateTaskbarProgress(int percent);
    bool detectWindowsDarkMode();
    void buildJumpList();

    bool m_darkMode = false;
    bool m_minimizeToTray = false;
    int m_exportProgress = 0;

    QSystemTrayIcon* m_trayIcon = nullptr;
    QMenu* m_trayMenu = nullptr;
    QAction* m_actionShow = nullptr;
    QAction* m_actionQuit = nullptr;
    QAction* m_actionMinimizeToTray = nullptr;

    QWinJumpList* m_jumpList = nullptr;
    QWinJumpListCategory* m_recentCategory = nullptr;

    QTimer* m_darkModePollTimer = nullptr;
};

} // namespace ghita::platform
