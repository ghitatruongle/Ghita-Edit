; Ghita Edit — Windows Installer Script (Inno Setup 6)
; Creates: Desktop shortcut + Start Menu shortcut + Uninstaller
;
; Version is NOT hardcoded here — it is parsed at compile time from
; lib/src/core/version.dart (the single source of truth), so the installer
; can never drift from the app. If version.dart is missing or unreadable,
; compilation fails loudly instead of shipping a stale version.

#define MyAppName "Ghita Edit"
#define MyAppPublisher "Ghita"
#define MyAppExeName "ghita_edit.exe"

; ---------------------------------------------------------------------------
; Read the version constants from lib/src/core/version.dart.
; Lines (1-based): 1-3 header/blank, 4 kAppName, 5 kMajor, 6 kMinor, 7 kPatch.
; ---------------------------------------------------------------------------
#define VersionFile "..\lib\src\core\version.dart"
#define VerFileHandle FileOpen(VersionFile)
#define _V1 FileRead(VerFileHandle)
#define _V2 FileRead(VerFileHandle)
#define _V3 FileRead(VerFileHandle)
#define _V4 FileRead(VerFileHandle)
#define VerMajorLine FileRead(VerFileHandle)
#define VerMinorLine FileRead(VerFileHandle)
#define VerPatchLine FileRead(VerFileHandle)
#define _V8 FileRead(VerFileHandle)
#define _V9 FileClose(VerFileHandle)

; Extract the integer from "const kMajorVersion = 1;" → "1"
#define GetNum(Line) StringChange(Trim(Copy(Line, Pos("=", Line) + 1, 16)), ";", "")

; Guard: if the layout of version.dart changes (header lines added/removed,
; constants reordered), fail loudly instead of silently shipping a wrong
; version — the exact drift this file was written to prevent.
#if Pos("kMajorVersion", VerMajorLine) == 0
  #error "Cannot locate kMajorVersion in lib/src/core/version.dart — layout changed"
#endif
#if Pos("kMinorVersion", VerMinorLine) == 0
  #error "Cannot locate kMinorVersion in lib/src/core/version.dart — layout changed"
#endif
#if Pos("kPatchVersion", VerPatchLine) == 0
  #error "Cannot locate kPatchVersion in lib/src/core/version.dart — layout changed"
#endif

#define MyAppVersion GetNum(VerMajorLine) + "." + GetNum(VerMinorLine) + "." + GetNum(VerPatchLine)

[Setup]
AppId={{8F5E9A1C-2B4D-4E7A-9C3D-1A6B8F0E5D2C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Ghita Edit
DefaultGroupName=Ghita Edit
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=GhitaEdit-{#MyAppVersion}-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

; License page shown during install (plain text).
LicenseFile=license.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"; Flags: checkedonce

[Files]
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
