@echo off
REM =============================================================================
REM Ghita Edit - Release Build Script
REM Builds a clean release and packages it into:
REM   1. NSIS installer (GhitaEdit-VERSION-Setup.exe)
REM   2. Portable ZIP archive (GhitaEdit-VERSION-win64.zip)
REM =============================================================================

setlocal EnableDelayedExpansion

REM --- Configuration ---
set "PROJECT_DIR=%~dp0.."
set "BUILD_DIR=%PROJECT_DIR%\..\ghita-build"
set "BUILD_TYPE=Release"
set "VERSION=0.1.5"

REM --- Paths ---
set "RELEASE_DIR=%BUILD_DIR%\%BUILD_TYPE%"
set "PACKAGE_DIR=%BUILD_DIR%\package"
set "ZIP_NAME=GhitaEdit-%VERSION%-win64.zip"
set "SETUP_NAME=GhitaEdit-%VERSION%-Setup.exe"

echo ============================================================
echo  Ghita Edit %VERSION% Release Builder
echo ============================================================
echo.

REM Check if build directory exists
if not exist "%BUILD_DIR%" (
    echo [1/5] Creating build directory...
    mkdir "%BUILD_DIR%"
)

REM Clean previous build
echo [1/5] Cleaning previous build...
if exist "%RELEASE_DIR%\GhitaEdit.exe" (
    del /q "%RELEASE_DIR%\GhitaEdit.exe" 2>nul
    del /q "%RELEASE_DIR%\*.dll" 2>nul
    rmdir /s /q "%RELEASE_DIR%\platforms" 2>nul
    rmdir /s /q "%RELEASE_DIR%\imageformats" 2>nul
    rmdir /s /q "%RELEASE_DIR%\qml" 2>nul
    rmdir /s /q "%RELEASE_DIR%\tls" 2>nul
    rmdir /s /q "%RELEASE_DIR%\generic" 2>nul
    rmdir /s /q "%RELEASE_DIR%\networkinformation" 2>nul
    rmdir /s /q "%RELEASE_DIR%\iconengines" 2>nul
    del /q "%RELEASE_DIR%\ghita_qml.qrc" 2>nul
)

REM Configure
echo [2/5] Configuring CMake...
cd /d "%BUILD_DIR%"
cmake -G "Ninja" -DCMAKE_BUILD_TYPE=%BUILD_TYPE% "%PROJECT_DIR%" > configure.log 2>&1
if errorlevel 1 (
    echo ERROR: CMake configuration failed. See configure.log
    exit /b 1
)
echo       Configuration complete.

REM Build
echo [3/5] Building (Release)...
cmake --build . --config %BUILD_TYPE% > build.log 2>&1
if errorlevel 1 (
    echo ERROR: Build failed. See build.log
    exit /b 1
)
echo       Build complete.

REM Verify output
if not exist "%RELEASE_DIR%\GhitaEdit.exe" (
    echo ERROR: GhitaEdit.exe not found in %RELEASE_DIR%
    exit /b 1
)
echo       GhitaEdit.exe verified.

REM Prepare package directory
echo [4/5] Preparing release package...
if exist "%PACKAGE_DIR%" (
    rmdir /s /q "%PACKAGE_DIR%"
)
mkdir "%PACKAGE_DIR%"

REM Copy release files to package directory
xcopy "%RELEASE_DIR%\GhitaEdit.exe" "%PACKAGE_DIR%\" /Y >nul
xcopy "%RELEASE_DIR%\*.dll" "%PACKAGE_DIR%\" /Y >nul
xcopy "%RELEASE_DIR%\platforms" "%PACKAGE_DIR%\platforms\" /E /Y >nul
xcopy "%RELEASE_DIR%\imageformats" "%PACKAGE_DIR%\imageformats\" /E /Y >nul
xcopy "%RELEASE_DIR%\qml" "%PACKAGE_DIR%\qml\" /E /Y >nul
xcopy "%RELEASE_DIR%\tls" "%PACKAGE_DIR%\tls\" /E /Y >nul
xcopy "%RELEASE_DIR%\generic" "%PACKAGE_DIR%\generic\" /E /Y >nul
xcopy "%RELEASE_DIR%\networkinformation" "%PACKAGE_DIR%\networkinformation\" /E /Y >nul
xcopy "%RELEASE_DIR%\iconengines" "%PACKAGE_DIR%\iconengines\" /E /Y >nul

echo       Package directory prepared.

REM --- Build NSIS Installer ---
echo [5/5] Building NSIS installer...
where makensis >nul 2>&1
if errorlevel 1 (
    echo WARNING: makensis not found in PATH. Skipping installer build.
    echo          Install NSIS from https://nsis.sourceforge.io/Download
    echo          Then re-run this script.
) else (
    cd /d "%PROJECT_DIR%"
    makensis /DRELEASE_DIR="%RELEASE_DIR%" NSIS.nsi > installer.log 2>&1
    if errorlevel 1 (
        echo ERROR: NSIS build failed. See installer.log
    ) else (
        if exist "%RELEASE_DIR%\%SETUP_NAME%" (
            echo       Installer created: %RELEASE_DIR%\%SETUP_NAME%
        ) else (
            echo WARNING: Installer may have been created with a different name.
        )
    )
)

REM --- Create ZIP Archive ---
echo.
echo --- Portable ZIP Archive ---
where 7z >nul 2>&1
if errorlevel 1 (
    where tar >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Neither 7-Zip nor tar found. Cannot create ZIP.
        echo          Please install 7-Zip (https://www.7-zip.org/) or use PowerShell:
        echo          Compress-Archive -Path "%PACKAGE_DIR%\*" -DestinationPath "%RELEASE_DIR%\%ZIP_NAME%"
    ) else (
        cd /d "%RELEASE_DIR%"
        tar -a -c -f "%ZIP_NAME%" -C "%PACKAGE_DIR%" . >nul 2>&1
        if exist "%RELEASE_DIR%\%ZIP_NAME%" (
            echo       ZIP created: %RELEASE_DIR%\%ZIP_NAME%
        )
    )
) else (
    cd /d "%PACKAGE_DIR%"
    7z a -tzip "%RELEASE_DIR%\%ZIP_NAME%" . >nul 2>&1
    if exist "%RELEASE_DIR%\%ZIP_NAME%" (
        echo       ZIP created: %RELEASE_DIR%\%ZIP_NAME%
    )
)

REM --- Summary ---
echo.
echo ============================================================
echo  Release build complete!
echo ============================================================
echo  Output directory: %RELEASE_DIR%
echo.
if exist "%RELEASE_DIR%\%SETUP_NAME%" (
    echo  Installer: %RELEASE_DIR%\%SETUP_NAME%
)
echo  ZIP:       %RELEASE_DIR%\%ZIP_NAME%
echo ============================================================
echo.

REM Cleanup
rmdir /s /q "%PACKAGE_DIR%"

exit /b 0
