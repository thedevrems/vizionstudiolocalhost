@echo off
title FiveM localhost - Arret de la base de donnees
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop-db.ps1"
echo.
pause
