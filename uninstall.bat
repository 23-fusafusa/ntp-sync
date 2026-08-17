@echo off
title NTP Time Sync - Uninstall

rem ============================================================
rem  Undoes everything setup.bat did:
rem    - removes the scheduled task
rem    - restores Windows Time service defaults
rem    - deletes C:\ntp_sync
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
set "INSTALL=C:\ntp_sync"
echo.
echo   Uninstalling:
echo     - remove the scheduled task "NTP Time Sync (NICT)"
echo     - reset the Windows Time service to its default settings
echo     - delete C:\ntp_sync (including the log)

rem No pushd here on purpose: it would make the install folder this shell's
rem current directory, and Windows refuses to delete a folder that a running
rem process is sitting in.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
set "RC=%errorlevel%"

echo.
if not "%RC%"=="0" (
    echo  === Uninstall FAILED ^(exit=%RC%^). See the messages above. ===
) else (
    echo  === Uninstall complete. ===
)
echo.
pause

rem Last act: delete this file and the folder it lives in. A running batch
rem file CAN delete itself, but cmd then has nothing left to read, so this
rem must be the final line - anything after it would never run.
rem Guarded on the path so that running this from the distribution folder
rem (shared drive, USB, Downloads) never deletes that folder.
if /i not "%~dp0"=="%INSTALL%\" exit /b %RC%
cd /d "%SystemRoot%"
rd /s /q "%INSTALL%" 2>nul
exit /b %RC%
