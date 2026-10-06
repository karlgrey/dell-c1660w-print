# install.ps1 - installiert dellprint für Windows 11 (x64) ins Benutzerverzeichnis.
#   %LOCALAPPDATA%\dellprint\   Programm (dellprint.ps1, sendto.cmd, bin\, test\, licenses\)
#   %APPDATA%\dellprint\config.txt   Einstellungen (wird nie überschrieben)
#   %APPDATA%\Microsoft\Windows\SendTo\Dell C1660w.lnk   "Senden an"-Eintrag
# Einzige Aktion mit Administrator-Rechten: die Installation von Ghostscript
# durch winget (Windows fragt selbst per UAC).
#
# Test-Haken (nur für Entwickler/CI):
#   DELLPRINT_HOST             Drucker-Adresse, überspringt die Nachfrage
#   DELLPRINT_NONINTERACTIVE   1 = keine Nachfragen, kein Probedruck
#
# Datei als UTF-8 MIT BOM speichern (Windows PowerShell 5.1).
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$pkg = $PSScriptRoot
$progDir = Join-Path $env:LOCALAPPDATA "dellprint"
$confDir = Join-Path $env:APPDATA "dellprint"
$confFile = Join-Path $confDir "config.txt"
$sendTo = Join-Path $env:APPDATA "Microsoft\Windows\SendTo"
$lnkFile = Join-Path $sendTo "Dell C1660w.lnk"
$logFile = Join-Path $progDir "install.log"

New-Item -ItemType Directory -Path $progDir -Force | Out-Null
$interactive = (-not $env:DELLPRINT_NONINTERACTIVE) -and (-not [Console]::IsInputRedirected)

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

function Say([string]$m) {
    Write-Host $m
    try {
        [System.IO.File]::AppendAllText($logFile, ("{0}  {1}`r`n" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m),
            (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

$script:step = 0
$steps = 8
function Heading([string]$t) {
    $script:step++
    Say ""
    Say "=============================================================="
    Say " Schritt $($script:step) von ${steps}: $t"
    Say "=============================================================="
}

function Fail-Install([string]$problem, [string[]]$hints) {
    Say ""
    Say "!! FEHLER: $problem"
    foreach ($h in $hints) { Say "   $h" }
    Say "   Protokoll: $logFile"
    Say "   Bitte dieses Protokoll bzw. einen Screenshot dieses Fensters weitergeben."
    exit 1
}

Say "dellprint-Installation gestartet ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))"

# ---- 1. System prüfen ---------------------------------------------------------------
Heading "System prüfen"
$arch = $env:PROCESSOR_ARCHITEW6432
if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
if (-not [Environment]::Is64BitOperatingSystem -or $arch -ne "AMD64") {
    Fail-Install "Dieses Paket ist nur für Windows 11 mit 64-Bit-Intel/AMD-Prozessor (x64)." @(
        "Gefunden: Prozessor-Architektur $arch.")
}
if ($PSVersionTable.PSVersion -lt [version]"5.1") {
    Fail-Install "Windows PowerShell 5.1 oder neuer wird benötigt (gefunden: $($PSVersionTable.PSVersion))." @()
}
Say "Windows x64, PowerShell $($PSVersionTable.PSVersion) - in Ordnung."

# Paket vollständig? (Zip nicht entpackt gestartet -> Dateien fehlen)
$srcBin = Join-Path $pkg "bin"
if (-not (Test-Path -LiteralPath (Join-Path $srcBin "foo2hbpl1.exe"))) {
    $dev = Join-Path $pkg "..\bin-win"      # Entwickler-Layout (Repo: windows\ + bin-win\)
    if (Test-Path -LiteralPath (Join-Path $dev "foo2hbpl1.exe")) { $srcBin = $dev }
}
foreach ($need in @((Join-Path $pkg "dellprint.ps1"), (Join-Path $pkg "sendto.cmd"),
                    (Join-Path $srcBin "foo2hbpl1.exe"), (Join-Path $srcBin "hbpldecode.exe"))) {
    if (-not (Test-Path -LiteralPath $need)) {
        Fail-Install "Im Paket fehlt: $need" @(
            "Bitte die Zip-Datei zuerst vollständig entpacken (Rechtsklick -> Alle extrahieren)",
            "und Installieren.cmd aus dem entpackten Ordner starten.")
    }
}

# ---- 2. Dateien freigeben (Mark of the Web) -----------------------------------------
Heading "Dateien freigeben"
Get-ChildItem -LiteralPath $pkg -Recurse -File -ErrorAction SilentlyContinue |
    ForEach-Object { try { Unblock-File -LiteralPath $_.FullName } catch { } }
Say "Paketdateien freigegeben (Internet-Markierung aus dem Download entfernt)."

# ---- 3. Ghostscript -----------------------------------------------------------------
Heading "Ghostscript"
function Find-Gs {
    $g = & (Join-Path $pkg "dellprint.ps1") -FindGs
    if ($g) { return "$g".Trim() }
    return $null
}
$gs = Find-Gs
if ($gs) {
    Say "Ghostscript vorhanden: $gs"
} else {
    $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $winget) {
        Fail-Install "Ghostscript fehlt, und winget ist nicht verfügbar." @(
            "Bitte Ghostscript (64 Bit) von https://ghostscript.com/releases/gsdnld.html installieren",
            "und Installieren.cmd danach noch einmal starten.")
    }
    Say "Installiere Ghostscript per winget (Windows fragt nach der Erlaubnis - bitte mit 'Ja' bestätigen) ..."
    & winget.exe install -e --id ArtifexSoftware.GhostScript --accept-package-agreements --accept-source-agreements
    $wrc = $LASTEXITCODE
    $gs = Find-Gs
    if (-not $gs) {
        Fail-Install "Ghostscript konnte nicht installiert werden (winget Exit-Code $wrc)." @(
            "Bitte Ghostscript (64 Bit) von https://ghostscript.com/releases/gsdnld.html installieren",
            "und Installieren.cmd danach noch einmal starten.")
    }
    Say "Ghostscript installiert: $gs"
}

# ---- 4. Programm kopieren -----------------------------------------------------------
Heading "Programm kopieren"
foreach ($d in @("bin", "test", "licenses")) {
    New-Item -ItemType Directory -Path (Join-Path $progDir $d) -Force | Out-Null
}
Copy-Item -LiteralPath (Join-Path $pkg "dellprint.ps1") -Destination $progDir -Force
Copy-Item -LiteralPath (Join-Path $pkg "sendto.cmd") -Destination $progDir -Force
Copy-Item -LiteralPath (Join-Path $pkg "uninstall.ps1") -Destination $progDir -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $srcBin "foo2hbpl1.exe") -Destination (Join-Path $progDir "bin") -Force
Copy-Item -LiteralPath (Join-Path $srcBin "hbpldecode.exe") -Destination (Join-Path $progDir "bin") -Force
$tp = Join-Path $pkg "test\testseite.pdf"
if (Test-Path -LiteralPath $tp) { Copy-Item -LiteralPath $tp -Destination (Join-Path $progDir "test") -Force }
$lic = Join-Path $pkg "licenses"
if (Test-Path -LiteralPath $lic) { Copy-Item -Path (Join-Path $lic "*") -Destination (Join-Path $progDir "licenses") -Force }
Say "Programm liegt in $progDir"

# ---- 5. Einstellungen ---------------------------------------------------------------
Heading "Einstellungen"
function Test-Printer([string]$h) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $ar = $c.BeginConnect($h, 9100, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne(3000, $false) -and $c.Connected
        $c.Close()
        return $ok
    } catch { return $false }
}
New-Item -ItemType Directory -Path $confDir -Force | Out-Null
if (Test-Path -LiteralPath $confFile) {
    Say "Einstellungen bleiben unverändert: $confFile"
} else {
    $h = $env:DELLPRINT_HOST
    if (-not $h -and $interactive) {
        Say "Wie lautet die Adresse des Druckers? Sie steht auf der Statusseite des Druckers"
        Say "oder im Router (Name wie DELLxxxxxx.local oder Zahlen wie 192.168.178.40)."
        $h = (Read-Host "Drucker-Adresse (leer lassen = später eintragen)").Trim()
    }
    if (-not $h) { $h = "" }
    $cfgText = @"
# dellprint-Konfiguration (wird gelesen, nicht ausgeführt)
# Drucker-Adresse: Name (DELLxxxxxx.local) oder IP-Adresse
HOST=$h
PAPER=a4
# Nur setzen, wenn Ghostscript nicht automatisch gefunden wird:
# GS=C:\Program Files\gs\gs10.04.0\bin\gswin64c.exe
"@
    [System.IO.File]::WriteAllText($confFile, ($cfgText -replace "`r?`n", "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Say "Einstellungen angelegt: $confFile"
    if ($h) {
        if (Test-Printer $h) { Say "Drucker $h antwortet." }
        else { Say "WARNUNG: Drucker $h antwortet gerade nicht (aus? Ruhezustand? Adresse falsch?). Die Installation geht trotzdem weiter." }
    } else {
        Say "WARNUNG: Keine Drucker-Adresse eingetragen. Bitte HOST= in $confFile ergänzen."
    }
}

# ---- 6. "Senden an"-Eintrag ---------------------------------------------------------
Heading "Senden-an-Eintrag"
New-Item -ItemType Directory -Path $sendTo -Force | Out-Null
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkFile)
$lnk.TargetPath = Join-Path $progDir "sendto.cmd"
$lnk.WorkingDirectory = $progDir
$lnk.WindowStyle = 1
$lnk.Description = "PDF an den Dell C1660w senden (dellprint)"
$lnk.IconLocation = "$env:SystemRoot\System32\shell32.dll,16"
$lnk.Save()
Say "Verknüpfung angelegt: $lnkFile"

# ---- 7. Selbsttest ------------------------------------------------------------------
Heading "Selbsttest"
$installed = Join-Path $progDir "dellprint.ps1"
$testPdf = Join-Path $progDir "test\testseite.pdf"
if (Test-Path -LiteralPath $testPdf) {
    $out = & $installed -DryRun $testPdf 2>&1 | ForEach-Object { "$_" }
    $trc = $LASTEXITCODE
    foreach ($l in $out) { Say "  $l" }
    if ($trc -ne 0) {
        Fail-Install "Der Selbsttest ist fehlgeschlagen (Exit-Code $trc)." @("Die Meldungen oben zeigen den Grund.")
    }
    Say "Selbsttest bestanden."
} else {
    Say "Hinweis: Keine Testseite im Paket - Selbsttest übersprungen."
}

# ---- 8. Probedruck ------------------------------------------------------------------
Heading "Probedruck"
if ($interactive -and (Test-Path -LiteralPath $testPdf)) {
    $a = (Read-Host "Probedruck jetzt senden? [j/N]").Trim()
    if ($a -match '^(?i:j|ja|y|yes)$') {
        & $installed $testPdf 2>&1 | ForEach-Object { Say "  $_" }
        if ($LASTEXITCODE -ne 0) { Say "WARNUNG: Der Probedruck ist fehlgeschlagen (siehe Meldung oben)." }
    } else { Say "Kein Probedruck." }
} else {
    Say "Kein Probedruck (nicht interaktiv)."
}

Say ""
Say "Fertig. Drucken: PDF mit der rechten Maustaste anklicken -> Senden an -> Dell C1660w"
Say "(Windows 11: zuerst 'Weitere Optionen anzeigen' wählen).."
exit 0
