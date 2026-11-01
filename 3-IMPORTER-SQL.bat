@echo off
title FiveM localhost - Import SQL
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\import-sql.ps1"
echo.
pause
