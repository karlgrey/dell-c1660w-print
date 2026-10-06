# dellprint für Windows 11 (x64) — Design

Stand 06.10.2026, freigegeben von Micha (Ansatz A, Abschnitt 1; „zieh durch").

## Ziel
PDFs ohne Dell-Treiber auf dem Dell C1660w drucken, unter Windows 11 x64
(der Dell-Treiber lief unter Windows 10, unter der aktuellen Windows-11-Version
nicht mehr). Erstnutzer: ein konkreter Familienrechner (Admin-Rechte vorhanden);
zugleich Teil des öffentlichen Repos. Nur PDF, nur x64 (ARM später).

**Erfolg:** Rechtsklick auf PDF → „Senden an" → „Dell C1660w" druckt das
Dokument; Installation per Doppelklick durch einen Nicht-Techniker.

## Nicht-Ziele (v1)
Virtueller Drucker im Druckdialog, Bonjour-Suche, ARM64, Duplex/Fach,
Code-Signing, Änderungen am Mac-Code.

## Architektur
Gleiche Pipeline wie macOS (`dellprint`, Bash):

```
PDF --gswin64c--> Raster 600x600 --foo2hbpl1.exe--> HBPL1 --TCP--> Drucker:9100
```

Alle Festwerte (RES, CLIP, MEDIA, DIM_A4/DIM_LETTER, GS-Devices pgmraw/pamcmyk32,
foo2hbpl1-Argumente, Seitenzählung per `runpdfbegin pdfpagecount`,
-dFIXEDMEDIA -dPDFFitPage) werden 1:1 aus `dellprint` übernommen.

**Binärdaten nie durch PowerShell-Pipes** (PS 5.1 behandelt Pipes als Text):
Umwandlung über `cmd.exe /c "gs … -sOutputFile=- | foo2hbpl1 … > job.hbpl"`
(cmd-Pipes sind binärsicher), Senden per `System.Net.Sockets.TcpClient`
mit Stream-Kopie aus der Datei.

## Dateien
```
windows/dellprint.ps1        Hauptprogramm (Windows PowerShell 5.1, kein pwsh nötig)
windows/sendto.cmd           Ziel der Senden-an-Verknüpfung → dellprint.ps1 -Gui %*
windows/Installieren.cmd     Doppelklick → powershell -ExecutionPolicy Bypass -File install.ps1
windows/install.ps1, windows/uninstall.ps1, windows/Deinstallieren.cmd
windows/ANLEITUNG.txt        eine Seite, deutsch, für Nicht-Techniker
windows/patches/             Patch(es) für foo2zjs-Quellen (Binärmodus stdio u. ä.)
build-windows.sh             Cross-Build (macOS: brew mingw-w64; Linux: apt mingw-w64)
make-dist-windows.sh         → dist/dellprint-windows.zip
tests/windows/run-tests.ps1  Tests (Listener: tests/listener.py)
.github/workflows/windows.yml  CI
```

## Build (`build-windows.sh`)
- Gleiche Quelle wie `build.sh` (foo2zjs, gepinnter Commit `FOO2ZJS_REF` —
  aus `build.sh` lesen bzw. eine gemeinsame Variable, nicht duplizieren).
- `x86_64-w64-mingw32-gcc -O2 -Wall -static` → `bin-win/foo2hbpl1.exe`,
  `bin-win/hbpldecode.exe` (bin-win/ in .gitignore). Keine DLL-Abhängigkeiten.
- Patch: `_setmode(_fileno(stdin|stdout), _O_BINARY)` am Programmanfang beider
  Tools; nötige POSIX-Lücken über minimalen Compat-Header. Jede Abweichung
  im Kopf von `build-windows.sh` dokumentieren (wie in `build.sh`).

## dellprint.ps1 (Verhalten)
- Aufruf: `dellprint.ps1 [-PrinterHost <IP|Name>] [-Mono] [-Paper a4|letter]
  [-Copies 1-99] [-Out <datei>] [-DryRun] [-Gui] <pdf> [<pdf> …]`.
  Mehrere PDFs (Senden an mit Mehrfachauswahl) nacheinander; Exit 1, wenn
  eine fehlschlug.
- Config `%APPDATA%\dellprint\config.txt` (KEY=WERT, wird geparst, NICHT
  ausgeführt): HOST, PORT (9100), PAPER, GS, FOO2HBPL1, HBPLDECODE.
  Kommandozeile hat Vorrang. Override per Env `DELLPRINT_CONFIG`/`DELLPRINT_LOG`
  (für Tests).
- Ghostscript finden: Config GS → Registry `HKLM:\SOFTWARE\GPL Ghostscript\*`
  (neueste Version) → `C:\Program Files\gs\gs*\bin\gswin64c.exe` (neueste) → PATH.
- Tools: Config, sonst neben dem Skript `bin\`.
- Prüfungen wie macOS: Datei existiert/ist PDF (%PDF-Header), Seitenzahl ≥ 1,
  hbpldecode-Prüfung (Seiten, Papier, Farbmodus, 600 dpi) — Abweichung = Abbruch.
- Kein Host → klare deutsche Fehlermeldung mit Hinweis auf config.txt.
- Erreichbarkeit: TCP-Connect mit 3 s Timeout, bis 4 Versuche, 3 s Pause
  (Ruhezustand). Senden je Kopie eine Verbindung.
- Protokoll `%LOCALAPPDATA%\dellprint\dellprint.log`, gleiches Tab-Format wie macOS.
- Exit-Codes: 0 ok, 1 Fehler, 2 Aufruffehler.
- `-Gui`: Konsolenfenster zeigt Fortschritt; am Ende MessageBox
  („An Dell C1660w gesendet: <datei>, N Seiten" bzw. Fehlermeldung).
- Meldungen deutsch, Umlaute korrekt (Skriptdateien UTF-8 **mit BOM**, sonst
  zerlegt PS 5.1 die Umlaute).

## Installer (install.ps1)
1. Prüfen: Windows x64, PowerShell ≥ 5.1.
2. `Unblock-File` auf alle Paketdateien (Mark-of-the-Web aus dem Zip).
3. Ghostscript: vorhanden → überspringen; sonst
   `winget install -e --id ArtifexSoftware.GhostScript --accept-package-agreements
   --accept-source-agreements` (UAC-Abfrage, Admin vorhanden). Danach erneut suchen.
4. Kopieren nach `%LOCALAPPDATA%\dellprint\` (dellprint.ps1, sendto.cmd, bin\, test\,
   licenses\, uninstall.ps1).
5. Config nur anlegen, wenn keine existiert: Adresse abfragen (Hinweis: Name
   `DELLxxxxxx.local` bzw. IP von der Statusseite des Druckers oder aus dem
   Router), Env `DELLPRINT_HOST` überspringt die Frage. Kurzer TCP-Test, bei
   Fehlschlag Warnung (nicht Abbruch).
6. Verknüpfung `%APPDATA%\Microsoft\Windows\SendTo\Dell C1660w.lnk` → sendto.cmd
   (WScript.Shell, minimiertes Fenster ok).
7. Selbsttest: `-DryRun` mit test\testseite.pdf.
8. Frage „Probedruck jetzt senden? [j/N]".
Idempotent; Protokoll `%LOCALAPPDATA%\dellprint\install.log`.
`uninstall.ps1` entfernt Verknüpfung + Programmordner; Config/Log bleiben, `-Purge`
löscht beides. Ghostscript bleibt.

## Paket (`make-dist-windows.sh`)
`dist/dellprint-windows.zip`: Installieren.cmd, Deinstallieren.cmd,
ANLEITUNG.txt, windows-Skripte, bin\*.exe, test\testseite.pdf (wie macOS-Paket
erzeugt), licenses\, README.md. Zeilenenden der .cmd/.ps1 im Paket CRLF.

## Tests / CI
`.github/workflows/windows.yml` (push + PR):
- Job `build` (ubuntu-latest): apt mingw-w64 + ghostscript; `build-windows.sh`;
  zusätzlich nativ `build.sh`-Äquivalent für Linux, Referenz-Datenstrom aus
  Test-PDF erzeugen und mit nativem hbpldecode dekodieren → Artifacts
  (exe, Test-PDF, Referenz-Decode, Zip aus make-dist-windows.sh).
- Job `test` (windows-latest, **Windows PowerShell 5.1 = `powershell.exe`**):
  `choco install ghostscript`; `tests/windows/run-tests.ps1`:
  Umwandlung Farbe/Mono (-Out), hbpldecode-Prüfung, Decode-Ausgabe der .exe =
  Referenz-Decode aus Linux (gleichwertiger Encoder), Fehlerfälle (keine Datei,
  kein PDF, kein Host, Drucker nicht erreichbar, ungültige Copies/Paper),
  Senden an 127.0.0.1 per tests/listener.py (1 und 2 Kopien, Bytes = -Out-Datei
  ohne PJL-Kopf), Mehrfachdateien, Config-Vorrang, Log-Zeile,
  install.ps1 nicht-interaktiv (DELLPRINT_HOST gesetzt, Ghostscript vorhanden)
  → Verknüpfung existiert, uninstall.ps1 entfernt sie.
- Bestehende macOS-Tests (`tests/run-tests.sh`) bleiben grün (lokal).

## Doku
README: Abschnitt „Windows 11" (Installation, Benutzung, Grenzen, Build).
Hinweis SmartScreen: „Weitere Informationen → Trotzdem ausführen".
