; =============================================================================
; Ghita Edit Windows Installer
; NSIS script for creating the Windows installer package
; =============================================================================

; Version -- must match CMakeLists.txt VERSION
!define GHITA_VERSION "0.0.0"
!define GHITA_NAME "Ghita Edit"
!define GHITA_PUBLISHER "Ghita Edit Contributors"
!define GHITA_URL "https://github.com/ghita-edit/GhitaEdit"

; Default install directory
!define DEFAULT_INSTALL_DIR "$PROGRAMFILES64\Ghita Edit"

; Input directory: the release build output (where windeployqt placed DLLs)
; This is passed from CMake or the release script via /D flag
; e.g. makensis /DRELEASE_DIR="E:\ghita-build\release" NSIS.nsi
!if !defined RELEASE_DIR
    !define RELEASE_DIR "."
!endif

Unicode true
RequestExecutionLevel user

; -------------------------------------------------------
; Includes
; -------------------------------------------------------
!include "MUI2.nsh"
!include "x64.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "WinVer.nsh"

; -------------------------------------------------------
; Installer output name
; -------------------------------------------------------
OutFile "${RELEASE_DIR}\GhitaEdit-${GHITA_VERSION}-Setup.exe"
InstallDir "$LOCALAPPDATA\Ghita Edit"
InstallDirRegKey HKCU "Software\${GHITA_NAME}" "InstallPath"
BrandingText "Ghita Edit Installer"
ShowInstDetails show
ShowUninstDetails show

; -------------------------------------------------------
; Page order
; -------------------------------------------------------
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

Var StartMenuFolder

!define MUI_STARTMENUPAGE_DEFAULTFOLDER "Ghita Edit"
!define MUI_STARTMENUPAGE_REGISTRY_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${GHITA_NAME}"
!define MUI_STARTMENUPAGE_REGISTRY_VALUENAME "${GHITA_NAME}"
!insertmacro MUI_STARTMENU_GETFOLDER_DEFAULT StartMenuFolder

!insertmacro MUI_PAGE_STARTMENU Application $StartMenuFolder

!insertmacro MUI_PAGE_FINISH

; Uninstaller pages
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; -------------------------------------------------------
; Languages
; -------------------------------------------------------
!insertmacro MUI_LANGUAGE "English"

; -------------------------------------------------------
; Installer sections
; -------------------------------------------------------
Section "GhitaEdit Main Application" SecMain

    SetOutPath "$INSTDIR"

    ; --- Executable ---
    File "${RELEASE_DIR}\GhitaEdit.exe"

    ; --- Qt DLLs (copied by windeployqt into the release dir) ---
    ; Core / QML / Quick
    File "${RELEASE_DIR}\Qt6Core.dll"
    File "${RELEASE_DIR}\Qt6Gui.dll"
    File "${RELEASE_DIR}\Qt6Qml.dll"
    File "${RELEASE_DIR}\Qt6QmlModels.dll"
    File "${RELEASE_DIR}\Qt6QmlWorkerScript.dll"
    File "${RELEASE_DIR}\Qt6Network.dll"
    File "${RELEASE_DIR}\Qt6OpenGL.dll"
    File "${RELEASE_DIR}\Qt6Quick.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2.dll"
    File "${RELEASE_DIR}\Qt6QuickDialogs2.dll"
    File "${RELEASE_DIR}\Qt6QuickDialogs2QuickImpl.dll"
    File "${RELEASE_DIR}\Qt6QuickDialogs2Utils.dll"
    File "${RELEASE_DIR}\Qt6QuickLayouts.dll"
    File "${RELEASE_DIR}\Qt6QuickShapes.dll"
    File "${RELEASE_DIR}\Qt6QuickTemplates2.dll"
    File "${RELEASE_DIR}\Qt6LabsFolderListModel.dll"

    ; SVG support
    File "${RELEASE_DIR}\Qt6Svg.dll"

    ; Qt Quick Controls styles
    File "${RELEASE_DIR}\Qt6QuickControls2Basic.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2BasicStyleImpl.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2Fusion.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2FusionStyleImpl.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2Imagine.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2ImagineStyleImpl.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2Impl.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2Material.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2MaterialStyleImpl.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2Universal.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2UniversalStyleImpl.dll"
    File "${RELEASE_DIR}\Qt6QuickControls2WindowsStyleImpl.dll"

    ; --- Platform plugin ---
    File /r "${RELEASE_DIR}\platforms\*.*"

    ; --- Image format plugins ---
    File /r "${RELEASE_DIR}\imageformats\*.*"

    ; --- Qt QML runtime ---
    File /r "${RELEASE_DIR}\qml\*.*"

    ; --- TLS / network backend ---
    File /r "${RELEASE_DIR}\tls\*.*"

    ; --- Generic handler ---
    File /r "${RELEASE_DIR}\generic\*.*"

    ; --- Network information ---
    File /r "${RELEASE_DIR}\networkinformation\*.*"

    ; --- Icon engines ---
    File /r "${RELEASE_DIR}\iconengines\*.*"

    ; --- DirectX runtime DLLs ---
    File "${RELEASE_DIR}\d3dcompiler_47.dll"
    File "${RELEASE_DIR}\dxcompiler.dll"
    File "${RELEASE_DIR}\dxil.dll"
    File "${RELEASE_DIR}\opengl32sw.dll"

    ; --- FFmpeg DLLs ---
    File "${RELEASE_DIR}\avcodec-62.dll"
    File "${RELEASE_DIR}\avformat-62.dll"
    File "${RELEASE_DIR}\avutil-60.dll"
    File "${RELEASE_DIR}\swresample-6.dll"
    File "${RELEASE_DIR}\swscale-9.dll"
    File "${RELEASE_DIR}\libx264-164.dll"

    ; --- PortAudio ---
    File "${RELEASE_DIR}\portaudio.dll"

    ; --- Qt translation files (optional, minimal) ---
    ; If present in release dir, copy them
    IfFileExists "${RELEASE_DIR}\qt*.dll" 0 qt_skip_trans
    File "${RELEASE_DIR}\qt*.dll"
    qt_skip_trans:

    ; Create registry entry for uninstall info
    WriteRegStr HKCU "Software\${GHITA_NAME}" "InstallPath" "$INSTDIR"
    WriteRegStr HKCU "Software\${GHITA_NAME}" "Version" "${GHITA_VERSION}"
    WriteRegStr HKCU "Software\${GHITA_NAME}" "URL" "${GHITA_URL}"

    ; --- Uninstaller registration ---
    WriteUninstaller "$INSTDIR\Uninstall.exe"

    ; --- Start Menu ---
    !insertmacro MUI_STARTMENU_WRITE_BEGIN Application

    CreateDirectory "$SMPROGRAMS\$StartMenuFolder"
    CreateShortcut "$SMPROGRAMS\$StartMenuFolder\${GHITA_NAME}.lnk" "$INSTDIR\GhitaEdit.exe"
    CreateShortcut "$SMPROGRAMS\$StartMenuFolder\Uninstall ${GHITA_NAME}.lnk" "$INSTDIR\Uninstall.exe"

    !insertmacro MUI_STARTMENU_WRITE_END

    ; --- Desktop Shortcut (optional, user can disable) ---
    ; CreateShortcut "$DESKTOP\${GHITA_NAME}.lnk" "$INSTDIR\GhitaEdit.exe"

    ; --- File associations ---
    ; Register .ghita project files (custom format, future-proofing)
    WriteRegStr HKCR ".ghita" "" "GhitaEdit.Project"
    WriteRegStr HKCR "GhitaEdit.Project" "" "Ghita Edit Project"
    WriteRegStr HKCR "GhitaEdit.Project\DefaultIcon" "" "$INSTDIR\GhitaEdit.exe,0"
    WriteRegStr HKCR "GhitaEdit.Project\shell\open\command" "" '"$INSTDIR\GhitaEdit.exe" "%1"'

    ; --- Installation size ---
    ; Calculate and store for uninstaller
    InitPluginsDir
    nsExec::ExecToStack '"$INSTDIR\Uninstall.exe" /GETSIZE'
    Pop $R0

SectionEnd

; -------------------------------------------------------
; Uninstaller section
; -------------------------------------------------------
Section "Uninstall"

    ; Remove Start Menu entries
    !insertmacro MUI_STARTMENU_GETFOLDER Application StartMenuFolder
    Delete "$SMPROGRAMS\$StartMenuFolder\${GHITA_NAME}.lnk"
    Delete "$SMPROGRAMS\$StartMenuFolder\Uninstall ${GHITA_NAME}.lnk"
    RMDir "$SMPROGRAMS\$StartMenuFolder"

    ; Remove registry entries
    DeleteRegKey HKCR ".ghita"
    DeleteRegKey HKCR "GhitaEdit.Project"

    ; Remove installed files
    RMDir /r "$INSTDIR\platforms"
    RMDir /r "$INSTDIR\imageformats"
    RMDir /r "$INSTDIR\qml"
    RMDir /r "$INSTDIR\tls"
    RMDir /r "$INSTDIR\generic"
    RMDir /r "$INSTDIR\networkinformation"
    RMDir /r "$INSTDIR\iconengines"

    Delete "$INSTDIR\Qt6Core.dll"
    Delete "$INSTDIR\Qt6Gui.dll"
    Delete "$INSTDIR\Qt6Qml.dll"
    Delete "$INSTDIR\Qt6QmlModels.dll"
    Delete "$INSTDIR\Qt6QmlWorkerScript.dll"
    Delete "$INSTDIR\Qt6Network.dll"
    Delete "$INSTDIR\Qt6OpenGL.dll"
    Delete "$INSTDIR\Qt6Quick.dll"
    Delete "$INSTDIR\Qt6QuickControls2.dll"
    Delete "$INSTDIR\Qt6QuickDialogs2.dll"
    Delete "$INSTDIR\Qt6QuickDialogs2QuickImpl.dll"
    Delete "$INSTDIR\Qt6QuickDialogs2Utils.dll"
    Delete "$INSTDIR\Qt6QuickLayouts.dll"
    Delete "$INSTDIR\Qt6QuickShapes.dll"
    Delete "$INSTDIR\Qt6QuickTemplates2.dll"
    Delete "$INSTDIR\Qt6LabsFolderListModel.dll"
    Delete "$INSTDIR\Qt6Svg.dll"
    Delete "$INSTDIR\Qt6QuickControls2Basic.dll"
    Delete "$INSTDIR\Qt6QuickControls2BasicStyleImpl.dll"
    Delete "$INSTDIR\Qt6QuickControls2Fusion.dll"
    Delete "$INSTDIR\Qt6QuickControls2FusionStyleImpl.dll"
    Delete "$INSTDIR\Qt6QuickControls2Imagine.dll"
    Delete "$INSTDIR\Qt6QuickControls2ImagineStyleImpl.dll"
    Delete "$INSTDIR\Qt6QuickControls2Impl.dll"
    Delete "$INSTDIR\Qt6QuickControls2Material.dll"
    Delete "$INSTDIR\Qt6QuickControls2MaterialStyleImpl.dll"
    Delete "$INSTDIR\Qt6QuickControls2Universal.dll"
    Delete "$INSTDIR\Qt6QuickControls2UniversalStyleImpl.dll"
    Delete "$INSTDIR\Qt6QuickControls2WindowsStyleImpl.dll"
    Delete "$INSTDIR\d3dcompiler_47.dll"
    Delete "$INSTDIR\dxcompiler.dll"
    Delete "$INSTDIR\dxil.dll"
    Delete "$INSTDIR\opengl32sw.dll"
    Delete "$INSTDIR\avcodec-62.dll"
    Delete "$INSTDIR\avformat-62.dll"
    Delete "$INSTDIR\avutil-60.dll"
    Delete "$INSTDIR\swresample-6.dll"
    Delete "$INSTDIR\swscale-9.dll"
    Delete "$INSTDIR\libx264-164.dll"
    Delete "$INSTDIR\portaudio.dll"
    Delete "$INSTDIR\GhitaEdit.exe"
    Delete "$INSTDIR\Uninstall.exe"

    ; Remove registry keys
    DeleteRegKey HKCU "Software\${GHITA_NAME}"

    ; Remove installation directory
    RMDir "$INSTDIR"

SectionEnd
