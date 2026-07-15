@echo off
REM Sets up the MSVC x64 build environment for Ghita Edit.
REM Usage: vs-env.bat <command> [args...]
REM Example: vs-env.bat cmake --build build-win --config Release
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
%*
