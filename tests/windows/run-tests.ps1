# run-tests.ps1 - Tests für dellprint unter Windows (Windows PowerShell 5.1).
# Sendet NIE an einen echten Drucker (nur lokaler Listener, tests\listener.py).
#
# Aufruf (aus dem Repo-Stamm):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\windows\run-tests.ps1 -Pkg <entpacktes Paket> -Ref <Referenzordner>
#   -Pkg  entpacktes dist\dellprint-windows (dellprint.ps1, install.ps1, bin\ ...)
#   -Ref  Ausgabe von tests/windows/make-reference.sh (Linux/Mac-Referenz)
# Datei als UTF-8 MIT BOM speichern.
param(
    [Parameter(Mandatory = $true)][string]$Pkg,
    [Parameter(Mandatory = $true)][string]$Ref
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$Pkg = (Resolve-Path $Pkg).Path
$Ref = (Resolve-Path $Ref).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$DP = Join-Path $Pkg "dellprint.ps1"
$FOO = Join-Path $Pkg "bin\foo2hbpl1.exe"
$DEC = Join-Path $Pkg "bin\hbpldecode.exe"
$LISTENER = Join-Path $Repo "tests\listener.py"
$T = Join-Path ([System.IO.Path]::GetTempPath()) ("dpt." + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $T -Force | Out-Null
$env:DELLPRINT_CONFIG = Join-Path $T "config.txt"
$env:DELLPRINT_LOG = Join-Path $T "log.txt"
Remove-Item Env:DELLPRINT_HOST -ErrorAction SilentlyContinue
Remove-Item Env:DELLPRINT_GUI_STUB -ErrorAction SilentlyContinue

$py = (Get-Command python.exe, python3.exe, py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $py) { Write-Host "FEHLER: python nicht gefunden (Listener)."; exit 1 }

$script:pass = 0; $script:fail = 0
function Ok([string]$n) { Write-Host "PASS  $n"; $script:pass++ }
function Bad([string]$n) { Write-Host "FAIL  $n"; $script:fail++ }
function Check([string]$n, [bool]$c) { if ($c) { Ok $n } else { Bad $n } }

function Run-DP([string[]]$a) {
    $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DP @a 2>&1 | Out-String
    return @{ Out = $o; Rc = $LASTEXITCODE }
}
function Expect-Fail([string]$name, [int]$rc, [string]$pat, [string[]]$a) {
    $r = Run-DP $a
    if ($r.Rc -eq $rc -and $r.Out -match $pat) { Ok "$name (rc=$($r.Rc))" }
    else { Bad "$name (rc=$($r.Rc), erwartet $rc / '$pat', Ausgabe: $($r.Out.Trim()))" }
}
function Write-Config([string]$text) {
    [System.IO.File]::WriteAllText($env:DELLPRINT_CONFIG, $text, (New-Object System.Text.UTF8Encoding($false)))
}
# Befehle mit binärsicherer Umleitung über eine .cmd-Datei
function Run-Lines([string[]]$lines) {
    $f = Join-Path $T ("t-" + [guid]::NewGuid().ToString("N").Substring(0, 6) + ".cmd")
    [System.IO.File]::WriteAllText($f, ("@echo off`r`n" + ($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::Default)
    & $f > $null 2>&1
    return $LASTEXITCODE
}
function Encode([string]$in, [string]$out) {
    return Run-Lines @("`"$FOO`" -m1 -u51,51,51,51 -J testseite.pdf -U ci <`"$in`" >`"$out`" 2>nul")
}
function Decode([string]$in, [string]$out) {
    return Run-Lines @("`"$DEC`" <`"$in`" >`"$out`" 2>&1")
}
function Decode-Raster([string]$in, [string]$prefix) {
    return Run-Lines @("`"$DEC`" -d `"$prefix`" <`"$in`" >nul 2>&1")
}
# Datenstrom ab "ENTER LANGUAGE=HBPL" (davor stehen Datum/Uhrzeit/Rechnername)
function Body-Hash([string]$file) {
    $b = [System.IO.File]::ReadAllBytes($file)
    $s = [System.Text.Encoding]::GetEncoding(28591).GetString($b)
    $i = $s.IndexOf("ENTER LANGUAGE=HBPL")
    if ($i -lt 0) { return "kein-marker" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return ([BitConverter]::ToString($sha.ComputeHash($b, $i, $b.Length - $i)) + ":" + ($b.Length - $i))
}
function Dec-Lines([string]$file) {
    @([System.IO.File]::ReadAllLines($file) | Where-Object { $_ -notmatch 'COMMENT (DATE|TIME)=|CNAM=' })
}
function Start-Listener([int]$port, [int]$count, [string]$out) {
    [System.IO.File]::WriteAllBytes($out, (New-Object byte[] 0))
    $p = Start-Process -FilePath $py -ArgumentList @("`"$LISTENER`"", "$port", "$count", "`"$out`"") -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2
    return $p
}
function Stop-Listener($p) {
    if (-not $p.WaitForExit(15000)) { try { $p.Kill() } catch { } }
}

$pdf = Join-Path $Ref "test.pdf"
$stamp = [System.IO.File]::ReadAllBytes($DP)
Check "dellprint.ps1 hat UTF-8-BOM" ($stamp[0] -eq 0xEF -and $stamp[1] -eq 0xBB -and $stamp[2] -eq 0xBF)
Check "Paket-Skripte haben CRLF" (([System.IO.File]::ReadAllText($DP)).Contains("`r`n"))

Write-Host "== Ghostscript-Suche =="
Write-Config "PAPER=a4`r`n"
$r = Run-DP @("-FindGs")
Check "-FindGs findet gswin64c.exe ($($r.Out.Trim()))" ($r.Rc -eq 0 -and $r.Out.Trim() -match 'gswin64c\.exe$')
Write-Config "GS=C:\gibt\es\nicht\gs.exe`r`n"
Expect-Fail "Config-GS ungültig -> Fehler" 1 "Ghostscript nicht gefunden" @("-DryRun", $pdf)

Write-Host "== Umwandlung =="
Write-Config "PAPER=a4`r`n"
$color = Join-Path $T "color.hbpl"; $mono = Join-Path $T "mono.hbpl"; $letter = Join-Path $T "letter.hbpl"
$r = Run-DP @("-Out", $color, $pdf);                    Check "-Out Farbe rc=0" ($r.Rc -eq 0)
Check "Umlaute in der Ausgabe korrekt (Prüfung)" ($r.Out -match 'Prüfung:')
$r = Run-DP @("-Out", $mono, "-Mono", $pdf);            Check "-Out -Mono rc=0" ($r.Rc -eq 0)
$r = Run-DP @("-DryRun", $pdf);                         Check "-DryRun rc=0" ($r.Rc -eq 0)
Check "-DryRun sendet nichts" ($r.Out -match 'nichts gesendet')
$r = Run-DP @("-Out", $letter, "-Paper", "letter", $pdf); Check "-Paper letter rc=0" ($r.Rc -eq 0)

Write-Host "== Dekodierung mit hbpldecode.exe =="
$dc = Join-Path $T "dc.txt"; $dm = Join-Path $T "dm.txt"; $dl = Join-Path $T "dl.txt"
[void](Decode $color $dc); [void](Decode $mono $dm); [void](Decode $letter $dl)
$tc = [System.IO.File]::ReadAllText($dc); $tm = [System.IO.File]::ReadAllText($dm); $tl = [System.IO.File]::ReadAllText($dl)
Check "Farbe: 2 Seiten" (([regex]::Matches($tc, 'image found')).Count -eq 2)
Check "Mono: 2 Seiten" (([regex]::Matches($tm, 'image found')).Count -eq 2)
Check "Farbe: Papier A4" (([regex]::Matches($tc, 'paper=A4')).Count -eq 2)
Check "Auflösung 600 dpi" ($tc -match 'SET RESOLUTION=600')
Check "Farbe: RENDERMODE=COLOR, [Color]" ($tc -match 'RENDERMODE=COLOR' -and $tc -match '\[Color\]')
Check "Mono: RENDERMODE=GRAYSCALE, [Mono]" ($tm -match 'RENDERMODE=GRAYSCALE' -and $tm -match '\[Mono\]' -and $tm -notmatch '\[Color\]')
Check "Letter: Papier Letter" ($tl -match 'paper=Letter')
Check "A4 Seitengröße 4968x7016 px" ($tc -match 'a2 c4: 4968x7016')

Write-Host "== Bildinhalt (dekodierte Rasterseite 1, Farbe vs. Mono) =="
$img = Join-Path $T "img"; New-Item -ItemType Directory -Path $img -Force | Out-Null
[void](Decode-Raster $color (Join-Path $img "c")); [void](Decode-Raster $mono (Join-Path $img "m"))
$cf = Get-ChildItem $img -Filter "c-01.*" | Select-Object -First 1
$mf = Get-ChildItem $img -Filter "m-01.*" | Select-Object -First 1
Check "Raster Farbe/Mono dekodiert (PPM/PGM)" ($cf -and $mf -and $cf.Extension -eq ".ppm" -and $mf.Extension -eq ".pgm")
if ($cf -and $mf) {
    $cb = [System.IO.File]::ReadAllBytes($cf.FullName)
    $colored = 0
    for ($i = 20; $i -lt $cb.Length - 3; $i += 3 * 997) {
        if ([Math]::Abs($cb[$i] - $cb[$i + 1]) -ge 8 -or [Math]::Abs($cb[$i + 1] - $cb[$i + 2]) -ge 8) { $colored++ }
    }
    Check "Farb-Bild enthält Farben ($colored Stichproben)" ($colored -gt 0)
    Check "Mono-Bild ist P5 (Graustufen)" ([System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($mf.FullName), 0, 2) -eq "P5")
}

Write-Host "== Encoder-Gleichwertigkeit gegen Linux-/Mac-Referenz (Binärmodus-Patch) =="
foreach ($k in @(@("color", "color.pam", "Farbe"), @("mono", "mono.pnm", "Mono"))) {
    $out = Join-Path $T "$($k[0]).exe.hbpl"; $decOut = Join-Path $T "$($k[0]).exe.dec.txt"
    $rc = Encode (Join-Path $Ref $k[1]) $out
    Check "$($k[2]): foo2hbpl1.exe rc=0, Ausgabe nicht leer" ($rc -eq 0 -and (Get-Item $out).Length -gt 1000)
    $h1 = Body-Hash $out; $h2 = Body-Hash (Join-Path $Ref "$($k[0]).ref.hbpl")
    Check "$($k[2]): HBPL-Datenstrom (ab ENTER LANGUAGE) byte-identisch zur Referenz [$h1]" ($h1 -eq $h2 -and $h1 -ne "kein-marker")
    [void](Decode $out $decOut)
    $a = Dec-Lines $decOut; $b = Dec-Lines (Join-Path $Ref "$($k[0]).ref.dec.txt")
    Check "$($k[2]): Dekodierung identisch zur Referenz ($($a.Count) Zeilen)" ($a.Count -gt 10 -and (($a -join "`n") -ceq ($b -join "`n")))
}

Write-Host "== Fehlerfälle =="
Expect-Fail "Datei fehlt" 1 "nicht gefunden" @("-DryRun", (Join-Path $T "gibtsnicht.pdf"))
$txt = Join-Path $T "x.txt"; Set-Content -Path $txt -Value "kein pdf"
Expect-Fail "Datei ist kein PDF" 1 "keine PDF" @("-DryRun", $txt)
$kaputt = Join-Path $T "kaputt.pdf"; [System.IO.File]::WriteAllText($kaputt, "%PDF-1.4`nkaputt`n")
Expect-Fail "PDF defekt" 1 "nicht lesbar|fehlgeschlagen|keine Seiten" @("-DryRun", $kaputt)
Write-Config "PAPER=a4`r`n"
Expect-Fail "Kein Host" 1 "Kein Drucker konfiguriert.*config\.txt|Kein Drucker konfiguriert" @($pdf)
Write-Config "HOST=127.0.0.1`r`nPORT=1`r`n"
Expect-Fail "Drucker nicht erreichbar" 1 "nicht erreichbar" @($pdf)
Write-Config "PAPER=a4`r`n"
Expect-Fail "Unbekannte Option" 2 "Unbekannte Option" @("-foo", $pdf)
Expect-Fail "Papier ungültig" 2 "Unbekanntes Papierformat" @("-Paper", "a3", $pdf)
Expect-Fail "Copies 0" 2 "Copies" @("-Copies", "0", $pdf)
Expect-Fail "Copies 100" 2 "Copies" @("-Copies", "100", $pdf)
Expect-Fail "Copies keine Zahl" 2 "Copies" @("-Copies", "abc", $pdf)
Expect-Fail "Keine Datei angegeben" 2 "PDF-Datei" @()
Write-Config "PORT=abc`r`n"
Expect-Fail "PORT in Config ungültig" 2 "PORT" @($pdf)
if ((Get-Content $env:DELLPRINT_LOG -Raw) -match 'ergebnis=FEHLER') { Ok "Fehler im Protokoll" } else { Bad "Fehler im Protokoll" }

Write-Host "== Config wird geparst, nicht ausgeführt =="
$pwned = Join-Path $T "pwned.txt"
Write-Config ("EVIL=`$(Set-Content -Path '$pwned' -Value x)`r`nSet-Content -Path '$pwned' -Value x`r`n# Kommentar`r`nPAPER=a4`r`n")
$r = Run-DP @("-DryRun", $pdf)
Check "Config-Zeilen mit Code werden nicht ausgeführt" ($r.Rc -eq 0 -and -not (Test-Path $pwned))

Write-Host "== Sendeweg gegen lokalen Listener (127.0.0.1) =="
Write-Config "HOST=127.0.0.1`r`nPORT=19100`r`n"
$recv = Join-Path $T "recv.bin"
$p = Start-Listener 19100 2 $recv      # 1. Verbindung = Erreichbarkeitsprüfung (leer), 2. = Auftrag
$r = Run-DP @($pdf)
Stop-Listener $p
Check "Senden rc=0" ($r.Rc -eq 0)
Check "Meldung 'gesendet'" ($r.Out -match 'Fertig: 2 Seite\(n\) x 1 an 127\.0\.0\.1:19100 gesendet')
Check "Empfangene Bytes == -Out-Datei (ab ENTER LANGUAGE) ($((Get-Item $recv).Length) Bytes)" ((Body-Hash $recv) -eq (Body-Hash $color))
Check "Empfangene Länge == -Out-Datei" ((Get-Item $recv).Length -eq (Get-Item $color).Length)

$recv2 = Join-Path $T "recv2.bin"
$p = Start-Listener 19100 3 $recv2
$r = Run-DP @("-Copies", "2", $pdf)
Stop-Listener $p
Check "Senden -Copies 2 rc=0" ($r.Rc -eq 0)
Check "2 Kopien = doppelte Bytes" ((Get-Item $recv2).Length -eq 2 * (Get-Item $color).Length)

$recv3 = Join-Path $T "recv3.bin"
$p = Start-Listener 19100 2 $recv3     # Mono über Senden
$r = Run-DP @("-Mono", $pdf)
Stop-Listener $p
Check "Senden -Mono: Bytes == Mono-Datei" ($r.Rc -eq 0 -and (Body-Hash $recv3) -eq (Body-Hash $mono))

Write-Host "== Mehrere Dateien =="
$recv4 = Join-Path $T "recv4.bin"
$pdf2 = Join-Path $T "zweite datei (ä).pdf"; Copy-Item $pdf $pdf2
$p = Start-Listener 19100 4 $recv4      # je Datei: Prüfung + Auftrag
$r = Run-DP @($pdf, $pdf2)
Stop-Listener $p
Check "2 PDFs nacheinander rc=0 (Sonderzeichen im Namen)" ($r.Rc -eq 0)
# Der Auftragsname (im PJL-Kopf) hängt vom Dateinamen ab -> Länge nur ungefähr doppelt
$d4 = (Get-Item $recv4).Length - 2 * (Get-Item $color).Length
Check "2 PDFs = doppelte Bytes (Abweichung $d4 durch Auftragsname)" ([Math]::Abs($d4) -lt 100)
$r = Run-DP @("-DryRun", $pdf, (Join-Path $T "fehlt.pdf"))
Check "Mehrere Dateien: eine fehlt -> rc=1, die andere wird verarbeitet" ($r.Rc -eq 1 -and $r.Out -match 'Trockenlauf' -and $r.Out -match 'nicht gefunden')

Write-Host "== Config-Vorrang =="
Write-Config "HOST=192.0.2.1`r`nPORT=19100`r`nPAPER=letter`r`n"
$recv5 = Join-Path $T "recv5.bin"
$p = Start-Listener 19100 2 $recv5
$r = Run-DP @("-PrinterHost", "127.0.0.1", "-Paper", "a4", $pdf)
Stop-Listener $p
Check "Kommandozeile schlägt Config (Host + Papier)" ($r.Rc -eq 0 -and $r.Out -match 'Papier=A4' -and (Body-Hash $recv5) -eq (Body-Hash $color))
$r = Run-DP @("-DryRun", $pdf)
Check "Config-Papier gilt ohne Kommandozeile" ($r.Rc -eq 0 -and $r.Out -match 'Papier=Letter')

Write-Host "== Reparierbares PDF (gs-Warnungen auf stderr) =="
$bytes = [System.IO.File]::ReadAllBytes($pdf)
$shift = New-Object byte[] ($bytes.Length + 12)
$pre = [System.Text.Encoding]::ASCII.GetBytes("%junk-junk-`n")
[Array]::Copy($pre, 0, $shift, 0, 12); [Array]::Copy($bytes, 0, $shift, 12, $bytes.Length)
$repair = Join-Path $T "repariert.pdf"; [System.IO.File]::WriteAllBytes($repair, $shift)
Write-Config "PAPER=a4`r`n"
$r = Run-DP @("-DryRun", $repair)
Check "PDF mit falschen xref-Offsets wird repariert und verarbeitet (rc=0, 2 Seiten)" ($r.Rc -eq 0 -and $r.Out -match 'Seiten=2')
Write-Config "HOST=127.0.0.1`r`nPORT=19100`r`n"

Write-Host "== TEMP mit Umlaut und Leerzeichen =="
$oldTmp = @{ A = $env:TEMP; B = $env:TMP }
$odd = Join-Path $T "Jürgen Ä"; New-Item -ItemType Directory -Path $odd -Force | Out-Null
$env:TEMP = $odd; $env:TMP = $odd
$recv7 = Join-Path $T "recv7.bin"
$p = Start-Listener 19100 2 $recv7
$r = Run-DP @($pdf)
Stop-Listener $p
Check "Farbe senden mit TEMP='$odd' (rc=0, Bytes wie Referenz)" ($r.Rc -eq 0 -and (Body-Hash $recv7) -eq (Body-Hash $color))
$env:TEMP = $oldTmp.A; $env:TMP = $oldTmp.B

Write-Host "== Protokoll =="
$log = Get-Content $env:DELLPRINT_LOG
Check "Log-Zeile OK gesendet im Tab-Format" (@($log | Where-Object { $_ -match "^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d`tdatei=.*`tseiten=2`tziel=127\.0\.0\.1:19100`tergebnis=OK gesendet" }).Count -ge 1)
$log | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }

Write-Host "== -Gui (Meldungsfenster, mit Test-Haken) =="
Write-Config "HOST=127.0.0.1`r`nPORT=19100`r`n"
$stub = Join-Path $T "gui.txt"; $env:DELLPRINT_GUI_STUB = $stub
$r = Run-DP @("-Gui", "-DryRun", $pdf)
Check "-Gui Trockenlauf: Meldungstext" ($r.Rc -eq 0 -and (Test-Path $stub) -and ([System.IO.File]::ReadAllText($stub) -match 'Trockenlauf.*2 Seite'))
Remove-Item $stub -ErrorAction SilentlyContinue
$r = Run-DP @("-Gui", "-DryRun", (Join-Path $T "fehlt.pdf"))
Check "-Gui Fehler: Meldungstext" ($r.Rc -eq 1 -and ([System.IO.File]::ReadAllText($stub) -match 'FEHLER.*nicht gefunden'))
Remove-Item Env:DELLPRINT_GUI_STUB

Write-Host "== Installer (nicht interaktiv, eigene APPDATA/LOCALAPPDATA) =="
$saved = @{ A = $env:APPDATA; L = $env:LOCALAPPDATA; C = $env:DELLPRINT_CONFIG; G = $env:DELLPRINT_LOG }
$fakeApp = Join-Path $T "AppData\Roaming"; $fakeLocal = Join-Path $T "AppData\Local"
New-Item -ItemType Directory -Path $fakeApp, $fakeLocal -Force | Out-Null
$env:APPDATA = $fakeApp; $env:LOCALAPPDATA = $fakeLocal
Remove-Item Env:DELLPRINT_CONFIG, Env:DELLPRINT_LOG
$env:DELLPRINT_HOST = "127.0.0.1"; $env:DELLPRINT_NONINTERACTIVE = "1"
$io = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Pkg "install.ps1") 2>&1 | Out-String
$irc = $LASTEXITCODE
Write-Host ($io -split "`r?`n" | Select-Object -Last 14 | Out-String)
$lnk = Join-Path $fakeApp "Microsoft\Windows\SendTo\Dell C1660w.lnk"
$inst = Join-Path $fakeLocal "dellprint"
Check "install.ps1 rc=0" ($irc -eq 0)
Check "Verknüpfung existiert" (Test-Path $lnk)
if (Test-Path $lnk) {
    $target = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath
    Check "Verknüpfung zeigt auf sendto.cmd ($target)" ($target -eq (Join-Path $inst "sendto.cmd"))
}
Check "Programmdateien installiert" ((Test-Path (Join-Path $inst "dellprint.ps1")) -and (Test-Path (Join-Path $inst "bin\foo2hbpl1.exe")) -and (Test-Path (Join-Path $inst "bin\hbpldecode.exe")) -and (Test-Path (Join-Path $inst "test\testseite.pdf")) -and (Test-Path (Join-Path $inst "uninstall.ps1")))
$cfgFile = Join-Path $fakeApp "dellprint\config.txt"
Check "Config enthält HOST=127.0.0.1" ((Test-Path $cfgFile) -and ((Get-Content $cfgFile) -contains "HOST=127.0.0.1"))
Check "Selbsttest im Installer bestanden" ($io -match 'Selbsttest bestanden')
Check "install.log angelegt" (Test-Path (Join-Path $inst "install.log"))
# Idempotenz: Config bleibt, zweiter Lauf ok
Add-Content -Path $cfgFile -Value "PORT=19100"
$io2 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Pkg "install.ps1") 2>&1 | Out-String
Check "zweiter Lauf rc=0 (idempotent), Config unverändert" ($LASTEXITCODE -eq 0 -and $io2 -match 'bleiben unverändert' -and ((Get-Content $cfgFile) -contains "PORT=19100"))
# Senden-an-Kette: sendto.cmd -> dellprint.ps1 -Gui (mit Listener auf 19100)
$stub2 = Join-Path $T "gui2.txt"; $env:DELLPRINT_GUI_STUB = $stub2
$recv6 = Join-Path $T "recv6.bin"
$p = Start-Listener 19100 2 $recv6
$src = Run-Lines @("call `"$(Join-Path $inst 'sendto.cmd')`" `"$pdf`"")
Stop-Listener $p
Check "sendto.cmd -> Meldung 'An Dell C1660w gesendet'" ($src -eq 0 -and (Test-Path $stub2) -and ([System.IO.File]::ReadAllText($stub2) -match 'An Dell C1660w gesendet: test\.pdf, 2 Seite'))
Check "sendto.cmd: Bytes angekommen" ((Get-Item $recv6).Length -eq (Get-Item $color).Length)
Remove-Item Env:DELLPRINT_GUI_STUB
# Deinstallieren
$uo = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $inst "uninstall.ps1") 2>&1 | Out-String
Check "uninstall.ps1 rc=0, Verknüpfung entfernt" ($LASTEXITCODE -eq 0 -and -not (Test-Path $lnk))
Check "Programmdateien entfernt, Config + Protokoll bleiben" (-not (Test-Path (Join-Path $inst "dellprint.ps1")) -and -not (Test-Path (Join-Path $inst "bin")) -and (Test-Path $cfgFile) -and (Test-Path (Join-Path $inst "install.log")))
$uo = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Pkg "uninstall.ps1") -Purge 2>&1 | Out-String
Check "uninstall.ps1 -Purge löscht Config und Ordner" ($LASTEXITCODE -eq 0 -and -not (Test-Path $cfgFile) -and -not (Test-Path $inst))
# Ghostscript-Download mit falscher Prüfsumme -> Abbruch (Installation wird erzwungen)
$env:DELLPRINT_FORCE_GS_INSTALL = "1"
$env:DELLPRINT_GS_SHA256 = "0000000000000000000000000000000000000000000000000000000000000000"
$bo = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Pkg "install.ps1") 2>&1 | Out-String
Check "falscher Ghostscript-Hash -> rc=1 und Meldung zur Prüfsumme" ($LASTEXITCODE -ne 0 -and $bo -match 'Prüfsumme des Ghostscript-Downloads stimmt nicht' -and $bo -notmatch 'Ghostscript installiert:')
Check "Download nach Hash-Fehler gelöscht" (@(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter "gs-installer-*.exe" -ErrorAction SilentlyContinue).Count -eq 0)
Remove-Item Env:DELLPRINT_FORCE_GS_INSTALL, Env:DELLPRINT_GS_SHA256 -ErrorAction SilentlyContinue
$env:APPDATA = $saved.A; $env:LOCALAPPDATA = $saved.L
Remove-Item Env:DELLPRINT_HOST, Env:DELLPRINT_NONINTERACTIVE -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Ergebnis: $($script:pass) bestanden, $($script:fail) fehlgeschlagen"
Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
if ($script:fail -eq 0) { exit 0 } else { exit 1 }
