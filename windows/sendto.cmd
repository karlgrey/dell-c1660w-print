@echo off
rem sendto.cmd - Ziel der "Senden an"-Verknuepfung "Dell C1660w".
rem Uebergibt die markierten PDFs an dellprint.ps1 (Fortschritt im Fenster,
rem am Ende ein Meldungsfenster).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dellprint.ps1" -Gui %*
