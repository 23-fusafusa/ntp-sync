@echo off
title NTP Time Sync - Setup

rem ============================================================
rem  Single entry point. Double-click this file.
rem  Elevates via UAC, copies the scripts to C:\ntp_sync,
rem  then registers the scheduled task.
rem
rem  Pure ASCII on purpose: batch files are read in the console
rem  OEM code page, so any non-ASCII byte here is a corruption
rem  risk on a differently-localized machine.
rem ============================================================

rem --- Re-launch elevated if not already administrator ---
net session >nul 2>&1
if %errorlevel% equ 0 goto admin

echo  Requesting administrator rights... Please click "Yes".
set "SELF=%~f0"
powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
exit /b

:admin
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_local.ps1"
set "RC=%errorlevel%"
popd

echo.
if not "%RC%"=="0" (
    echo  === Setup FAILED ^(exit=%RC%^). See the messages above. ===
) else (
    echo  === Setup complete. ===
    echo      Log       : C:\ntp_sync\ntp_sync.log
    echo      To remove : C:\ntp_sync\uninstall.bat
)
echo.
pause
exit /b %RC%
