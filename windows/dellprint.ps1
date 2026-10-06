# dellprint.ps1 - PDF ohne Druckertreiber an den Dell C1660w schicken (Windows 11 x64).
#
# Pipeline (wie das Bash-Programm "dellprint" auf dem Mac, ohne Druckertreiber):
#   Ghostscript (PDF -> Raster 600x600) | foo2hbpl1.exe (Raster -> HBPL1) | TCP :9100
#
# Laeuft mit Windows PowerShell 5.1 (powershell.exe), pwsh ist nicht noetig.
# Diese Datei muss als UTF-8 MIT BOM gespeichert sein, sonst zerlegt
# PowerShell 5.1 die Umlaute.
#
# Binaerdaten laufen NIE durch PowerShell-Pipes (PS 5.1 behandelt Pipes als
# Text): Umwandlung per cmd.exe (cmd-Pipes sind binaersicher), Senden per
# System.Net.Sockets.TcpClient mit Stream-Kopie aus der Datei.
#
# Abweichungen vom Mac-Programm (alle bewusst):
#  - Keine Bonjour-Suche (Nicht-Ziel v1): ohne Host kommt eine Fehlermeldung.
#  - Mehrere PDFs nacheinander (Senden an mit Mehrfachauswahl); Exit 1, wenn
#    eine fehlschlug.
#  - Die PDF wird vor dem Umwandeln als in.pdf in das Temp-Verzeichnis des
#    Auftrags kopiert: Ghostscript bekommt so nie Sonderzeichen/Umlaute aus
#    dem Originalpfad auf der Kommandozeile.
#  - -Gui: am Ende eine MessageBox (Senden-an-Verknuepfung hat sonst keine
#    sichtbare Rueckmeldung).
#
# Lizenz dieses Skripts: GPL-2.0-or-later (siehe README, "Lizenz").

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$PrinterHost = "",
    [switch]$Mono,
    [string]$Paper = "",
    [string]$Copies = "1",
    [string]$Out = "",
    [switch]$DryRun,
    [switch]$Gui,
    [switch]$Help,
    [switch]$Version,
    [switch]$FindGs,    # intern: Ghostscript suchen und Pfad ausgeben (vom Installer genutzt)
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Files = @()
)

$ErrorActionPreference = 'Stop'
$script:DP_VERSION = "1.0"
$script:PROG = "dellprint"

# Umlaute auch bei umgeleiteter Ausgabe korrekt (Konsole ggf. ohne Handle -> ignorieren)
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# ---- Festwerte, abgeleitet aus foo2hbpl1-wrapper.in / Dell-C1660.ppd (wie dellprint auf dem Mac) ----
$RES = "600x600"          # Wrapper: RES=600x600 "do not change this"
$CLIP = "51,51,51,51"     # Wrapper: set_clipping 51 51 51 51 (0,085 inch)
$MEDIA = "1"              # Wrapper: MEDIA=1 (Plain), PPD: MediaType plain -> -m1
$DIM_A4 = "4961x7016"     # Wrapper: 1|a4|A4)  DIM=4961x7016
$DIM_LETTER = "5100x6600" # Wrapper: 4|letter) DIM=5100x6600

$CONFIG = $env:DELLPRINT_CONFIG
if (-not $CONFIG) { $CONFIG = Join-Path $env:APPDATA "dellprint\config.txt" }
$LOGFILE = $env:DELLPRINT_LOG
if (-not $LOGFILE) { $LOGFILE = Join-Path $env:LOCALAPPDATA "dellprint\dellprint.log" }

# Fehler, die das aktuelle PDF abbrechen (Exit-Code 1) bzw. den Aufruf (2)
class DellprintError : System.Exception {
    [int]$Code
    DellprintError([string]$msg, [int]$code) : base($msg) { $this.Code = $code }
}

function Fail([string]$msg, [int]$code = 1) {
    throw (New-Object DellprintError($msg, $code))
}

function Say([string]$msg) { Write-Host $msg }

function Err([string]$msg) { [Console]::Error.WriteLine($msg) }

# ---- Protokoll (gleiches Tab-Format wie auf dem Mac) -------------------------------
$script:INPUT = "-"
$script:PAGES = "?"
$script:TARGET = "-"
function Log-Line([string]$result) {
    try {
        $d = Split-Path -Parent $LOGFILE
        if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        $line = "{0}`tdatei={1}`tseiten={2}`tziel={3}`tergebnis={4}`r`n" -f `
            (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $script:INPUT, $script:PAGES, $script:TARGET, $result
        [System.IO.File]::AppendAllText($LOGFILE, $line, (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Usage {
    @"
Aufruf: dellprint.ps1 [Optionen] datei.pdf [datei2.pdf ...]

Optionen:
  -PrinterHost <IP|Name>  Drucker-Adresse (sonst Config)
  -Mono                   Schwarzweiß (Standard: Farbe)
  -Paper a4|letter        Papierformat (Standard: a4)
  -Copies N               Anzahl Kopien, 1-99 (Standard: 1)
  -Out <datei>            HBPL-Datenstrom nur in Datei schreiben, nichts senden
  -DryRun                 umwandeln und mit hbpldecode prüfen, nichts senden
  -Gui                    am Ende ein Meldungsfenster (für 'Senden an')
  -Help                   diese Hilfe
  -Version                Version

Konfiguration: $CONFIG
  (HOST=, PORT=, PAPER=, GS=, FOO2HBPL1=, HBPLDECODE=)
Protokoll:     $LOGFILE
"@
}

# ---- Config laden (KEY=WERT, wird geparst, NICHT ausgeführt) -----------------------
function Read-Config([string]$path) {
    $cfg = @{}
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $cfg }
    foreach ($raw in [System.IO.File]::ReadAllLines($path)) {
        $l = $raw.Trim()
        if ($l -eq "" -or $l.StartsWith("#")) { continue }
        $i = $l.IndexOf("=")
        if ($i -lt 1) { continue }
        $k = $l.Substring(0, $i).Trim().ToUpperInvariant()
        $v = $l.Substring($i + 1).Trim()
        if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $cfg[$k] = $v
    }
    return $cfg
}

# ---- Ghostscript finden: Config -> Registry -> Program Files -> PATH ---------------
function Parse-Ver([string]$s) {
    $m = [regex]::Match($s, '\d+(\.\d+)+')
    if ($m.Success) { try { return [version]$m.Value } catch { } }
    return [version]"0.0"
}

function Find-Ghostscript([string]$fromConfig) {
    # 1. Config
    if ($fromConfig) {
        if (Test-Path -LiteralPath $fromConfig -PathType Leaf) { return $fromConfig }
        return $null   # gesetzt, aber ungültig: nicht stillschweigend woanders suchen
    }
    # 2. Registry (GPL Ghostscript, neueste Version zuerst)
    try {
        $keys = @(Get-ChildItem -Path "HKLM:\SOFTWARE\GPL Ghostscript" -ErrorAction Stop |
                  Sort-Object { Parse-Ver $_.PSChildName } -Descending)
        foreach ($k in $keys) {
            $dll = (Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue).GS_DLL
            if ($dll) {
                $exe = Join-Path (Split-Path -Parent $dll) "gswin64c.exe"
                if (Test-Path -LiteralPath $exe -PathType Leaf) { return $exe }
            }
        }
    } catch { }
    # 3. C:\Program Files\gs\gs*\bin\gswin64c.exe (neueste)
    try {
        $pf = $env:ProgramFiles
        if (-not $pf) { $pf = "C:\Program Files" }
        $cands = @(Get-ChildItem -Path (Join-Path $pf "gs\gs*\bin\gswin64c.exe") -ErrorAction Stop |
                   Sort-Object { Parse-Ver $_.Directory.Parent.Name } -Descending)
        if ($cands.Count -gt 0) { return $cands[0].FullName }
    } catch { }
    # 4. PATH
    foreach ($n in @("gswin64c.exe", "gswin64c", "gs.exe")) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Source }
    }
    return $null
}

# ---- Hilfen für cmd.exe-Skripte ----------------------------------------------------
# Binärdaten-Pipelines laufen in einer temporären .cmd-Datei (keine Quoting-
# Fallen auf der PowerShell-Kommandozeile).  Geschrieben in der OEM-Codepage,
# die cmd.exe beim Lesen verwendet.
function Run-Cmd([string]$dir, [string[]]$lines) {
    $f = Join-Path $dir ("job-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".cmd")
    $enc = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    [System.IO.File]::WriteAllText($f, ("@echo off`r`n" + ($lines -join "`r`n") + "`r`n"), $enc)
    $ErrorActionPreference = 'Continue'
    & $f > $null 2>&1
    return $LASTEXITCODE
}

function Q([string]$p) { '"' + ($p -replace '%', '%%') + '"' }   # für .cmd-Dateien

# ---- Erreichbarkeit / Senden (TcpClient) --------------------------------------------
function Open-Tcp([string]$hostName, [int]$port, [int]$timeoutMs) {
    # Alle Adressen des Namens probieren (IPv4 zuerst); .local-Namen löst Windows per mDNS auf.
    $addrs = @()
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($hostName, [ref]$ip)) { $addrs = @($ip) }
    else {
        $addrs = @([System.Net.Dns]::GetHostAddresses($hostName) |
                   Sort-Object { if ($_.AddressFamily -eq 'InterNetwork') { 0 } else { 1 } })
    }
    $last = $null
    foreach ($a in $addrs) {
        $c = New-Object System.Net.Sockets.TcpClient($a.AddressFamily)
        try {
            $ar = $c.BeginConnect($a, $port, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne($timeoutMs, $false)) {
                $c.EndConnect($ar)
                return $c
            }
            $last = "Zeitüberschreitung"
        } catch { $last = $_.Exception.Message }
        $c.Close()
    }
    throw "Verbindung fehlgeschlagen: $last"
}

function Test-Tcp([string]$hostName, [int]$port, [int]$timeoutMs) {
    try { $c = Open-Tcp $hostName $port $timeoutMs; $c.Close(); return $true } catch { return $false }
}

function Send-File([string]$hostName, [int]$port, [string]$file) {
    $c = Open-Tcp $hostName $port 5000
    try {
        $c.SendTimeout = 60000
        $ns = $c.GetStream()
        $fs = [System.IO.File]::OpenRead($file)
        try { $fs.CopyTo($ns, 65536) } finally { $fs.Dispose() }
        $ns.Flush()
        try { $c.Client.Shutdown([System.Net.Sockets.SocketShutdown]::Send) } catch { }
    } finally { $c.Close() }
}

# ---- Ein PDF verarbeiten ------------------------------------------------------------
function Convert-One([string]$pdf, $o) {
    $script:INPUT = $pdf; $script:PAGES = "?"; $script:TARGET = "-"

    if (-not (Test-Path -LiteralPath $pdf)) { Fail "Datei nicht gefunden: $pdf" }
    if (-not (Test-Path -LiteralPath $pdf -PathType Leaf)) { Fail "Das ist keine normale Datei: $pdf" }
    try {
        $fs = [System.IO.File]::OpenRead($pdf)
        try { $buf = New-Object byte[] 1024; $n = $fs.Read($buf, 0, 1024) } finally { $fs.Dispose() }
    } catch { Fail "Datei nicht lesbar: $pdf" }
    if ([System.Text.Encoding]::ASCII.GetString($buf, 0, $n).IndexOf("%PDF-") -lt 0) {
        Fail "Das ist keine PDF-Datei: $pdf"
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dellprint." + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $in = Join-Path $tmp "in.pdf"
        Copy-Item -LiteralPath $pdf -Destination $in -Force

        # ---- Seitenzahl ----
        $inPs = ($in -replace '\\', '/') -replace '\(', '\(' -replace '\)', '\)'
        # stderr von gs (Warnungen bei reparierten PDFs) darf unter PS 5.1 keine
        # NativeCommandError-Ausnahme auslösen -> Fehlerverhalten hier lokal lockern
        $eapSave = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $cnt = & $o.GS -q -dNODISPLAY -dNOSAFER -c "($inPs) (r) file runpdfbegin pdfpagecount = quit" 2>$null }
        finally { $ErrorActionPreference = $eapSave }
        $last = @($cnt | Where-Object { "$_".Trim() -ne "" } | ForEach-Object { "$_".Trim() }) | Select-Object -Last 1
        if (-not $last -or $last -notmatch '^\d+$') { Fail "PDF nicht lesbar (Seitenzahl nicht ermittelbar): $pdf" }
        $script:PAGES = $last
        $pages = [int]$last
        if ($pages -lt 1) { Fail "PDF enthält keine Seiten: $pdf" }

        # ---- Umwandeln ----
        $stream = Join-Path $tmp "job.hbpl"
        $gserr = Join-Path $tmp "gs.err"
        $foerr = Join-Path $tmp "foo.err"
        $gsrc = Join-Path $tmp "gs.rc"
        if ($o.Mono) { $gsdev = "pgmraw"; $modeName = "Mono" }       # Wrapper: GSDEV=-sDEVICE=pgmraw (Monochrom)
        else { $gsdev = "pamcmyk32"; $modeName = "Color" }           # Wrapper: bei -c GSDEV=-sDEVICE=pamcmyk32
        $jobName = ([regex]::Replace([System.IO.Path]::GetFileName($pdf), '[^A-Za-z0-9._ -]', '_'))
        if ($jobName.Length -gt 40) { $jobName = $jobName.Substring(0, 40) }
        $userName = ([regex]::Replace("$env:USERNAME", '[^A-Za-z0-9._-]', '_'))
        if ($userName -eq "") { $userName = "user" }
        if ($userName.Length -gt 30) { $userName = $userName.Substring(0, 30) }

        Say "Wandle um: $pdf ($pages Seite(n), $($o.PaperName), $modeName, $RES dpi) ..."
        # -dFIXEDMEDIA -dPDFFitPage: PDF-Seite auf das feste Blatt skalieren (der
        # Wrapper bekommt von CUPS schon fertig passendes PostScript; hier nicht).
        # Die Klammer um gs sammelt dessen Exit-Code in gs.rc (cmd liefert bei
        # einer Pipe sonst nur den Code des letzten Programms).
        $gsCmd = "(" + (Q $o.GS) + " -q -dBATCH -dSAFER -dQUIET -dNOPAUSE -dFIXEDMEDIA -dPDFFitPage" +
                 " -sPAPERSIZE=$($o.Paper) -g$($o.Dim) -r$RES -sDEVICE=$gsdev -sOutputFile=- " + (Q $in) +
                 " 2>" + (Q $gserr) + " & call echo %%errorlevel%%>" + (Q $gsrc) + ")"
        $fooCmd = (Q $o.Foo) + " -m$MEDIA -u$CLIP -J " + (Q $jobName) + " -U " + (Q $userName) +
                  " >" + (Q $stream) + " 2>" + (Q $foerr)
        $rcFoo = Run-Cmd $tmp @("$gsCmd | $fooCmd", "exit /b %errorlevel%")
        $rcGs = "?"
        if (Test-Path -LiteralPath $gsrc) { $rcGs = ([System.IO.File]::ReadAllText($gsrc)).Trim() }
        $errText = ""
        foreach ($ef in @($gserr, $foerr)) {
            if (Test-Path -LiteralPath $ef) { $errText += [System.IO.File]::ReadAllText($ef) + "`n" }
        }
        if ($rcGs -ne "0" -or $rcFoo -ne 0) {
            $detail = (($errText -split "`r?`n" | Where-Object { $_ -ne "" } | Select-Object -First 3) -join " ")
            Fail "Umwandlung fehlgeschlagen (gs=$rcGs, foo2hbpl1=$rcFoo): $detail"
        }
        if (-not (Test-Path -LiteralPath $stream) -or (Get-Item -LiteralPath $stream).Length -eq 0) {
            Fail "Umwandlung lieferte keine Daten."
        }
        if ($errText.Contains("Not an acceptable")) { Fail "foo2hbpl1 meldet ungültige Rasterdaten." }

        # ---- Prüfen mit hbpldecode ----
        $dec = Join-Path $tmp "decode.txt"
        $decLine = (Q $o.Dec) + " <" + (Q $stream) + " >" + (Q $dec) + " 2>&1"
        $rcDec = Run-Cmd $tmp @($decLine, "exit /b %errorlevel%")
        if ($rcDec -ne 0) {
            $dd = ""
            if (Test-Path -LiteralPath $dec) { $dd = (([System.IO.File]::ReadAllLines($dec) | Select-Object -Last 2) -join " ") }
            Fail "hbpldecode konnte den Datenstrom nicht lesen (Exit-Code $rcDec): $dd"
        }
        $dl = [System.IO.File]::ReadAllLines($dec)
        $dPages = @($dl | Where-Object { $_ -match 'image found' }).Count
        $dPaper = (@($dl | ForEach-Object { if ($_ -match '\[paper=([^\]]*)\]') { $Matches[1] } } | Sort-Object -Unique) -join " ")
        $dMode = (@($dl | ForEach-Object { if ($_ -match '\[(Color|Mono)\]') { $Matches[1] } } | Sort-Object -Unique) -join " ")
        $dRes = ""
        foreach ($l in $dl) { if ($l -match 'SET RESOLUTION=(\d+)') { $dRes = $Matches[1]; break } }
        $dSize = (@($dl | ForEach-Object { if ($_ -match 'a2 c4: (\d+x\d+) ') { $Matches[1] } } | Sort-Object -Unique) -join " ")
        Say "Prüfung: Seiten=$dPages Papier=$dPaper Modus=$dMode Auflösung=${dRes}dpi Seitengröße(px)=$dSize"
        if ("$dPages" -ne "$pages") { Fail "Seitenzahl im Datenstrom ($dPages) weicht vom PDF ($pages) ab." }
        if ($dPaper -ne $o.PaperName) { Fail "Papierformat im Datenstrom ($dPaper) weicht ab (erwartet $($o.PaperName))." }
        if ($dMode -ne $modeName) { Fail "Farbmodus im Datenstrom ($dMode) weicht ab (erwartet $modeName)." }
        if ($dRes -ne "600") { Fail "Auflösung im Datenstrom ($dRes) ist nicht 600 dpi." }

        # ---- Ausgabe: Datei / Trockenlauf ----
        if ($o.Out) {
            try { Copy-Item -LiteralPath $stream -Destination $o.Out -Force } catch { Fail "Ausgabedatei nicht schreibbar: $($o.Out)" }
            $script:TARGET = "datei:$($o.Out)"
            Say "Datenstrom geschrieben: $($o.Out) ($((Get-Item -LiteralPath $o.Out).Length) Bytes)"
            Log-Line "OK (nur Datei)"
            return "Datenstrom geschrieben: $($o.Out), $pages Seite(n)"
        }
        if ($o.DryRun) {
            $script:TARGET = "dry-run"
            Say "Trockenlauf: nichts gesendet."
            Log-Line "OK (Trockenlauf)"
            return "Trockenlauf (nichts gesendet): $([System.IO.Path]::GetFileName($pdf)), $pages Seite(n)"
        }

        # ---- Host ----
        if (-not $o.Host) {
            Fail "Kein Drucker konfiguriert. Bitte -PrinterHost <IP|Name> angeben oder HOST=<IP|Name> in $CONFIG eintragen (Adresse z. B. von der Statusseite des Druckers oder aus dem Router)."
        }
        $script:TARGET = "$($o.Host):$($o.Port)"

        # ---- Erreichbarkeit + Senden ----
        # Aus dem Ruhezustand antwortet der Drucker erst nach ein paar Sekunden
        # (beobachtet 30.09.2026 auf dem Mac) - deshalb mehrere Versuche.
        $reachable = $false
        for ($try = 1; $try -le 4; $try++) {
            if (Test-Tcp $o.Host $o.Port 3000) { $reachable = $true; break }
            if ($try -lt 4) { Say "Drucker antwortet noch nicht (Versuch $try/4), warte ..."; Start-Sleep -Seconds 3 }
        }
        if (-not $reachable) { Fail "Drucker $($o.Host):$($o.Port) nicht erreichbar. Eingeschaltet? Im WLAN? IP korrekt?" }

        for ($n = 1; $n -le $o.Copies; $n++) {
            Say "Sende Kopie $n von $($o.Copies) an $($o.Host):$($o.Port) ..."
            try { Send-File $o.Host $o.Port $stream }
            catch { Fail "Senden an $($o.Host):$($o.Port) fehlgeschlagen (Kopie $n): $($_.Exception.Message)" }
        }
        Say "Fertig: $pages Seite(n) x $($o.Copies) an $($o.Host):$($o.Port) gesendet."
        Log-Line "OK gesendet ($($o.Copies)x)"
        return "An Dell C1660w gesendet: $([System.IO.Path]::GetFileName($pdf)), $pages Seite(n)"
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ================================ Hauptprogramm =======================================
if ($Help) { Usage; exit 0 }
if ($Version) { Say "$PROG $script:DP_VERSION"; exit 0 }

$cfg = Read-Config $CONFIG

if ($FindGs) {
    $g = Find-Ghostscript $cfg["GS"]
    if ($g) { Write-Output $g; exit 0 }
    exit 1
}

$results = @()     # Zeilen für die MessageBox
$failed = 0
try {
    # ---- Argumente ----
    foreach ($f in $Files) {
        if ($f -match '^-' ) { Fail "Unbekannte Option: $f (siehe -Help)" 2 }
    }
    if ($Files.Count -lt 1) { Usage | ForEach-Object { Err $_ }; Fail "Mindestens eine PDF-Datei angeben." 2 }

    $hostName = $cfg["HOST"]; if ($PrinterHost) { $hostName = $PrinterHost }
    $paperSel = $cfg["PAPER"]; if ($Paper) { $paperSel = $Paper }
    if (-not $paperSel) { $paperSel = "a4" }
    $port = $cfg["PORT"]; if (-not $port) { $port = "9100" }

    # ---- Werte prüfen ----
    switch -Regex ($paperSel) {
        '^(?i:a4)$'     { $paperKey = "a4";     $dim = $DIM_A4;     $paperName = "A4" }
        '^(?i:letter)$' { $paperKey = "letter"; $dim = $DIM_LETTER; $paperName = "Letter" }
        default         { Fail "Unbekanntes Papierformat '$paperSel' (erlaubt: a4, letter)." 2 }
    }
    if ($Copies -notmatch '^\d+$') { Fail "-Copies muss eine Zahl von 1 bis 99 sein." 2 }
    $copiesN = [int]$Copies
    if ($copiesN -lt 1 -or $copiesN -gt 99) { Fail "-Copies muss zwischen 1 und 99 liegen." 2 }
    if ($port -notmatch '^\d+$') { Fail "PORT in der Config ist ungültig." 2 }

    # ---- Werkzeuge finden ----
    $gs = Find-Ghostscript $cfg["GS"]
    if (-not $gs) {
        Fail "Ghostscript nicht gefunden. Bitte Installieren.cmd erneut ausführen (installiert Ghostscript) oder GS= in $CONFIG setzen."
    }
    $foo = $cfg["FOO2HBPL1"]; if (-not $foo) { $foo = Join-Path $PSScriptRoot "bin\foo2hbpl1.exe" }
    $dec = $cfg["HBPLDECODE"]; if (-not $dec) { $dec = Join-Path $PSScriptRoot "bin\hbpldecode.exe" }
    if (-not (Test-Path -LiteralPath $foo -PathType Leaf)) { Fail "foo2hbpl1.exe nicht gefunden ($foo). Bitte neu installieren." }
    if (-not (Test-Path -LiteralPath $dec -PathType Leaf)) { Fail "hbpldecode.exe nicht gefunden ($dec). Bitte neu installieren." }

    $opts = @{
        GS = $gs; Foo = $foo; Dec = $dec; Host = $hostName; Port = [int]$port
        Paper = $paperKey; PaperName = $paperName; Dim = $dim; Mono = [bool]$Mono
        Copies = $copiesN; Out = $Out; DryRun = [bool]$DryRun
    }

    foreach ($pdf in $Files) {
        try {
            $results += (Convert-One $pdf $opts)
        } catch [DellprintError] {
            $failed++
            Err "${PROG}: $($_.Exception.Message)"
            Log-Line ("FEHLER: " + $_.Exception.Message)
            $results += "FEHLER ($([System.IO.Path]::GetFileName($pdf))): $($_.Exception.Message)"
        } catch {
            $failed++
            Err "${PROG}: Unerwarteter Fehler: $($_.Exception.Message)"
            Log-Line ("FEHLER: " + $_.Exception.Message)
            $results += "FEHLER ($([System.IO.Path]::GetFileName($pdf))): $($_.Exception.Message)"
        }
    }
    $exitCode = 0; if ($failed -gt 0) { $exitCode = 1 }
} catch [DellprintError] {
    $failed++
    Err "${PROG}: $($_.Exception.Message)"
    $script:INPUT = "-"
    Log-Line ("FEHLER: " + $_.Exception.Message)
    $results += "FEHLER: $($_.Exception.Message)"
    $exitCode = $_.Exception.Code
}

if ($Gui) {
    $text = ($results -join "`r`n")
    if ($env:DELLPRINT_GUI_STUB) {
        # Test-Haken: Text in Datei statt MessageBox
        [System.IO.File]::WriteAllText($env:DELLPRINT_GUI_STUB, $text, (New-Object System.Text.UTF8Encoding($false)))
    } else {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $icon = [System.Windows.Forms.MessageBoxIcon]::Information
            if ($failed -gt 0) { $icon = [System.Windows.Forms.MessageBoxIcon]::Error }
            # unsichtbares TopMost-Fenster als Besitzer: Meldung erscheint nicht hinter anderen Fenstern
            $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
            try { [void][System.Windows.Forms.MessageBox]::Show($owner, $text, "Dell C1660w", [System.Windows.Forms.MessageBoxButtons]::OK, $icon) }
            finally { $owner.Dispose() }
        } catch { }
    }
}
exit $exitCode
