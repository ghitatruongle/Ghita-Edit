#include "WindowsPlatformHelper.h"

#include <QGuiApplication>
#include <QMenu>
#include <QMessageBox>
#include <QFileDialog>
#include <QTimer>
#include <QStandardPaths>
#include <QSettings>
#include <QLoggingCategory>
#include <QWindow>

#include <windows.h>
#include <registry.h>
#include <shobjidl_core.h>
#include <abjaapi.h>

#include <pathcch.h>
#pragma comment(lib, "pathcch.lib")

Q_DECLARE_LOGGING_CATEGORY(lcPlatform)
Q_LOGGING_CATEGORY(lcPlatform, "ghita.platform")

namespace ghita::platform {

namespace {

constexpr wchar_t kRegPath[] = LR"(SOFTWARE\Ghita\GhitaEdit)";
constexpr wchar_t kFileExt[] = L".ghita";
constexpr wchar_t kFileType[] = L"GhitaEdit.Project";
constexpr wchar_t kFileDesc[] = L"Ghita Edit Project";

// Resolve the executable path for file association / registry entries.
static QString exePath() {
    return QGuiApplication::applicationFilePath();
}

static QString exeDir() {
    return QGuiApplication::applicationDirPath();
}

} // namespace

// ---------------------------------------------------------------------------
// Dark-mode detection via Windows registry (PreferredAppMode).
// ---------------------------------------------------------------------------
bool WindowsPlatformHelper::detectWindowsDarkMode() {
    HKEY key;
    LONG rc = RegOpenKeyExW(HKEY_CURRENT_USER,
                              L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                              0, KEY_READ, &key);
    if (rc != ERROR_SUCCESS) {
        qCDebug(lcPlatform) << "Cannot open Themes registry key";
        return false;
    }

    DWORD value = 1; // default: light
    DWORD size = sizeof(value);
    rc = RegQueryValueExW(key, L"AppsUseLightTheme", nullptr, nullptr,
                          reinterpret_cast<LPBYTE>(&value), &size);
    RegCloseKey(key);

    if (rc != ERROR_SUCCESS) {
        qCDebug(lcPlatform) << "AppsUseLightTheme not found";
        return false;
    }

    return (value == 0); // 0 = dark mode
}

// ---------------------------------------------------------------------------
// Constructor / Destructor
// ---------------------------------------------------------------------------
WindowsPlatformHelper::WindowsPlatformHelper(QObject* parent)
    : QObject(parent), m_darkMode(detectWindowsDarkMode()) {

    // Poll dark-mode periodically (in case user toggles it while app is running).
    m_darkModePollTimer = new QTimer(this);
    m_darkModePollTimer->setInterval(5000);
    connect(m_darkModePollTimer, &QTimer::timeout, this, [this]() {
        bool newMode = detectWindowsDarkMode();
        if (newMode != m_darkMode) {
            m_darkMode = newMode;
            qCInfo(lcPlatform) << "Dark mode changed:" << (m_darkMode ? "ON" : "OFF");
            emit darkModeChanged();
        }
    });
    m_darkModePollTimer->start();

    createSystemTray();
    buildJumpList();

    // Auto-register file association on first run.
    registerFileAssociation();
}

WindowsPlatformHelper::~WindowsPlatformHelper() {
    if (m_darkModePollTimer) {
        m_darkModePollTimer->stop();
    }
    if (m_trayIcon) {
        m_trayIcon->hide();
        delete m_trayIcon;
    }
    if (m_jumpList) {
        m_jumpList->clearAllCategories();
        delete m_jumpList;
    }
}

// ---------------------------------------------------------------------------
// System Tray
// ---------------------------------------------------------------------------
void WindowsPlatformHelper::createSystemTray() {
    m_trayIcon = new QSystemTrayIcon(this);

    // Try to load an icon from the assets folder; fall back to a generic one.
    QIcon trayIcon;
    QString iconPath = exeDir() + "/assets/icon.png";
    if (QFile::exists(iconPath)) {
        trayIcon.addFile(iconPath, QSize(64, 64));
    }
    if (trayIcon.isNull()) {
        // Fallback: use the application icon.
        trayIcon = QGuiApplication::windowIcon();
    }
    m_trayIcon->setIcon(trayIcon);
    m_trayIcon->setToolTip("Ghita Edit");
    m_trayIcon->setVisible(true);

    // Context menu.
    m_trayMenu = new QMenu();
    m_actionShow = m_trayMenu->addAction("Show Ghita Edit");
    m_actionMinimizeToTray = m_trayMenu->addAction("Minimize to Tray");
    m_actionMinimizeToTray->setCheckable(true);
    m_actionMinimizeToTray->setChecked(m_minimizeToTray);
    m_trayMenu->addSeparator();
    m_actionQuit = m_trayMenu->addAction("Quit");

    m_trayIcon->setContextMenu(m_trayMenu);

    connect(m_trayIcon, &QSystemTrayIcon::activated,
            this, &WindowsPlatformHelper::onSystemTrayActivated);
    connect(m_actionShow, &QAction::triggered, this, [this]() {
        QGuiApplication::primaryWindow()->showNormal();
        QGuiApplication::primaryWindow()->raise();
        QGuiApplication::primaryWindow()->activateWindow();
    });
    connect(m_actionQuit, &QAction::triggered, qApp, &QCoreApplication::quit);
    connect(m_actionMinimizeToTray, &QAction::triggered, this,
            [this](bool checked) { setMinimizeToTray(checked); });
}

void WindowsPlatformHelper::onSystemTrayActivated(
        QSystemTrayIcon::ActivationReason reason) {
    if (reason == QSystemTrayIcon::Trigger) {
        QGuiApplication::primaryWindow()->showNormal();
        QGuiApplication::primaryWindow()->raise();
        QGuiApplication::primaryWindow()->activateWindow();
    }
}

// ---------------------------------------------------------------------------
// Taskbar Progress
// ---------------------------------------------------------------------------
void WindowsPlatformHelper::updateTaskbarProgress(int percent) {
    QWindow* window = QGuiApplication::primaryWindow();
    if (!window) return;

    HWND hwnd = reinterpret_cast<HWND>(window->winId());
    if (!hwnd) return;

    // Qt 6.5+ has QWinTaskBarProgress; use it when available.
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    Q_UNUSED(hwnd);
    QWinTaskBarProgress::setValue(percent);
#else
    // Fallback: use the Windows Taskbar API directly.
    static ITaskbarList3* taskbar = nullptr;
    if (!taskbar) {
        CoInitialize(nullptr);
        CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&taskbar));
    }
    if (taskbar) {
        if (percent >= 100) {
            taskbar->SetProgressState(hwnd, TBPF_DONE);
        } else {
            taskbar->SetProgressValue(hwnd, static_cast<DWORD>(percent), 100);
        }
    }
#endif
}

// ---------------------------------------------------------------------------
// Jump List (Recent Files)
// ---------------------------------------------------------------------------
void WindowsPlatformHelper::buildJumpList() {
    m_jumpList = new QWinJumpList(this);

    m_recentCategory = new QWinJumpListCategory(this);
    m_recentCategory->setTitle("Recent");

    // "New Project" button.
    QWinJumpListLink* newProject = new QWinJumpListLink(this);
    newProject->setArguments("");
    newProject->setTitle("New Project");
    newProject->setWorkingDir(exeDir());
    connect(newProject, &QWinJumpListLink::activated, this,
            &WindowsPlatformHelper::openNewProjectRequested);
    m_recentCategory->addJumpListLink(newProject);

    m_jumpList->addJumpListCategory(m_recentCategory);
    m_jumpList->setCategories({m_recentCategory});
    m_jumpList->update();
}

void WindowsPlatformHelper::addToRecentFiles(const QString& filePath) {
    if (filePath.isEmpty()) return;

    // Remove duplicate if already present.
    QList<QWinJumpListLink*> links = m_recentCategory->jumpListLinks();
    for (QWinJumpListLink* link : links) {
        if (link->arguments() == filePath) {
            m_recentCategory->removeJumpListLink(link);
            delete link;
            break;
        }
    }

    // Add as recent file link.
    QWinJumpListLink* recentLink = new QWinJumpListLink(filePath, this);
    recentLink->setTitle(QFileInfo(filePath).fileName());
    recentLink->setArguments(filePath);
    recentLink->setWorkingDir(exeDir());
    connect(recentLink, &QWinJumpListLink::activated, this,
            [this, filePath]() {
                emit openRecentFileRequested(filePath);
            });
    m_recentCategory->addJumpListLink(recentLink);

    // Limit to 10 recent files.
    if (m_recentCategory->jumpListLinks().size() > 10) {
        auto allLinks = m_recentCategory->jumpListLinks();
        for (int i = 10; i < static_cast<int>(allLinks.size()); ++i) {
            m_recentCategory->removeJumpListLink(allLinks[i]);
            delete allLinks[i];
        }
    }

    m_jumpList->update();
    emit recentFilesChanged();
}

void WindowsPlatformHelper::clearRecentFiles() {
    if (!m_recentCategory) return;
    auto links = m_recentCategory->jumpListLinks();
    for (QWinJumpListLink* link : links) {
        m_recentCategory->removeJumpListLink(link);
        delete link;
    }
    m_jumpList->update();
    emit recentFilesChanged();
}

// ---------------------------------------------------------------------------
// File Association (.ghita)
// ---------------------------------------------------------------------------
void WindowsPlatformHelper::registerFileAssociation() {
    QString exe = exePath();
    if (exe.isEmpty()) return;

    HKEY key;
    LONG rc = RegCreateKeyExW(HKEY_CURRENT_USER, kRegPath, 0, nullptr,
                              REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &key, nullptr);
    if (rc != ERROR_SUCCESS) {
        qCWarning(lcPlatform) << "Failed to create registry key for file association";
        return;
    }

    // Associate extension .ghita with our FileType.
    RegSetValueExW(key, kFileExt, 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(kFileType),
                   static_cast<DWORD>((wcslen(kFileType) + 1) * sizeof(WCHAR)));

    // Create FileType sub-key with shell open command pointing to our exe.
    HKEY typeKey;
    rc = RegCreateKeyExW(key, kFileType, 0, nullptr, REG_OPTION_NON_VOLATILE,
                         KEY_WRITE, nullptr, &typeKey, nullptr);
    if (rc == ERROR_SUCCESS) {
        // Friendly name.
        RegSetValueExW(typeKey, nullptr, 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(kFileDesc),
                       static_cast<DWORD>((wcslen(kFileDesc) + 1) * sizeof(WCHAR)));

        // Default icon.
        QString iconPath = exe + ",0";
        std::wstring iconW(iconPath.length(), L'\0');
        iconPath.toWCharArray(iconW.data());
        iconW[iconPath.length()] = L'\0';
        RegSetValueExW(typeKey, L"DefaultIcon", 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(iconW.c_str()),
                       static_cast<DWORD>((iconW.length() + 1) * sizeof(WCHAR)));

        // Open command.
        QString cmd = exe + R"( %1)";
        std::wstring cmdW(cmd.length(), L'\0');
        cmd.toWCharArray(cmdW.data());
        cmdW[cmd.length()] = L'\0';
        HKEY shellKey, openKey, execKey;
        RegCreateKeyExW(typeKey, L"shell", 0, nullptr, REG_OPTION_NON_VOLATILE,
                        KEY_WRITE, nullptr, &shellKey, nullptr);
        RegCreateKeyExW(shellKey, L"open", 0, nullptr, REG_OPTION_NON_VOLATILE,
                        KEY_WRITE, nullptr, &openKey, nullptr);
        RegCreateKeyExW(openKey, L"command", 0, nullptr, REG_OPTION_NON_VOLATILE,
                        KEY_WRITE, nullptr, &execKey, nullptr);
        RegSetValueExW(execKey, nullptr, 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(cmdW.c_str()),
                       static_cast<DWORD>((cmdW.length() + 1) * sizeof(WCHAR)));

        RegCloseKey(execKey);
        RegCloseKey(openKey);
        RegCloseKey(shellKey);
        RegCloseKey(typeKey);
    }

    RegCloseKey(key);
    qCInfo(lcPlatform) << "Registered .ghita file association";
}

void WindowsPlatformHelper::unregisterFileAssociation() {
    LONG rc = RegDeleteKeyExW(HKEY_CURRENT_USER, kRegPath, 0, 0);
    if (rc == ERROR_SUCCESS) {
        qCInfo(lcPlatform) << "Unregistered .ghita file association";
    } else {
        qCWarning(lcPlatform) << "Failed to unregister file association";
    }
}

// ---------------------------------------------------------------------------
// Native File Dialogs
// ---------------------------------------------------------------------------
QStringList WindowsPlatformHelper::openNativeFileDialog(
        const QString& title, const QString& filter, const QString& initialDir) {
    // On Windows, QFileDialog::getOpenFileNames respects the native-dialog
    // hint set via QSysInfo. Qt 6 on Windows uses the native dialog by
    // default when QFileDialog::DontUseNativeDialog is NOT set.
    QStringList files = QFileDialog::getOpenFileNames(
        nullptr, title, initialDir, filter);
    return files;
}

QString WindowsPlatformHelper::openNativeSaveFileDialog(
        const QString& title, const QString& filter,
        const QString& initialDir, const QString& defaultName) {
    QString path = QFileDialog::getSaveFileName(
        nullptr, title, initialDir + "/" + defaultName, filter);
    return path;
}

// ---------------------------------------------------------------------------
// Window Close Handler
// ---------------------------------------------------------------------------
void WindowsPlatformHelper::handleWindowCloseRequest() {
    if (m_minimizeToTray) {
        QGuiApplication::primaryWindow()->hide();
    } else {
        // Let the default close behavior proceed.
        QGuiApplication::primaryWindow()->close();
    }
}

// ---------------------------------------------------------------------------
// Export progress bridge (called from Application.cpp).
// ---------------------------------------------------------------------------
void WindowsPlatformHelper::onExportProgressFromExporter(int percent) {
    setExportProgress(percent);
}

void WindowsPlatformHelper::onExportFinishedFromExporter(bool success) {
    if (success) {
        setExportProgress(100);
        // Reset taskbar progress to "done" state after a short delay.
        QTimer::singleShot(3000, this, [this]() {
            setExportProgress(0);
        });
    } else {
        // Reset on failure.
        setExportProgress(0);
    }
}

} // namespace ghita::platform
