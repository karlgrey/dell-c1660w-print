# uninstall.ps1 - entfernt, was install.ps1 angelegt hat (nur Benutzerverzeichnis).
# Config und Protokoll bleiben, ausser mit -Purge.  Ghostscript bleibt installiert.
# Datei als UTF-8 MIT BOM speichern (Windows PowerShell 5.1).
[CmdletBinding()]
param([switch]$Purge)

$ErrorActionPreference = 'Stop'
$prog = Join-Path $env:LOCALAPPDATA "dellprint"
$conf = Join-Path $env:APPDATA "dellprint"
$lnk = Join-Path $env:APPDATA "Microsoft\Windows\SendTo\Dell C1660w.lnk"

Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue

# Nur die von install.ps1 angelegten Teile entfernen: Protokolle liegen im selben Ordner.
foreach ($n in @("dellprint.ps1", "sendto.cmd", "uninstall.ps1", "bin", "test", "licenses")) {
    Remove-Item -LiteralPath (Join-Path $prog $n) -Recurse -Force -ErrorAction SilentlyContinue
}
if ($Purge) {
    Remove-Item -LiteralPath $conf -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $prog -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Einstellungen und Protokoll ebenfalls entfernt."
} else {
    # Ordner nur löschen, wenn nichts (Protokoll) darin übrig ist
    if ((Test-Path -LiteralPath $prog) -and -not (Get-ChildItem -LiteralPath $prog -Force)) {
        Remove-Item -LiteralPath $prog -Force
    }
    Write-Host "Einstellungen ($conf) und Protokolle ($prog) bleiben; -Purge entfernt sie."
}
Write-Host "dellprint deinstalliert."
