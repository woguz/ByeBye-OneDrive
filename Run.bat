@echo off
title ByeBye-OneDrive Launcher
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\ByeBye-OneDrive.ps1"
pause
