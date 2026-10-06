@echo off
rem Installieren.cmd - Doppelklick-Installer fuer dellprint (Dell C1660w).
rem Startet install.ps1 (Windows PowerShell), ohne dass die
rem PowerShell-Ausfuehrungsrichtlinie geaendert werden muss.
title dellprint installieren
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
