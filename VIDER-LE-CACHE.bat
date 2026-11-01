@echo off
title FiveM localhost - Vider le cache
if exist "%~dp0server-data\cache" (
    rmdir /s /q "%~dp0server-data\cache"
    echo Cache du serveur supprime : server-data\cache
) else (
    echo Pas de cache a supprimer.
)
echo.
pause
