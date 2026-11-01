@echo off
title FiveM localhost - Connexion
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\connect.ps1"
if errorlevel 1 pause
