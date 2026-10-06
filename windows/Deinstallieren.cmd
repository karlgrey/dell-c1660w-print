@echo off
rem Deinstallieren.cmd - entfernt dellprint (Verknuepfung + Programmordner).
rem Einstellungen und Protokoll bleiben; mit "Deinstallieren.cmd -Purge" werden
rem auch sie geloescht.
title dellprint deinstallieren
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
echo.
pause
