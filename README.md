# dell-c1660w-print

PDFs ohne Druckertreiber auf dem **Dell C1660w** ausdrucken (macOS, Apple Silicon).

Der C1660w versteht weder AirPrint noch PDF/PostScript, sondern nur **HBPL Version 1**
(host-basiert) über Raw-TCP auf Port 9100. Der Dell-Originaltreiber fällt ab macOS 27
weg. `dellprint` umgeht CUPS-Treiber komplett:

```
PDF --Ghostscript--> Raster 600x600 --foo2hbpl1--> HBPL1 --nc--> Drucker:9100
```

Es wird **keine CUPS-Warteschlange, keine PPD und kein Filter in /Library** angelegt.
Alles liegt im Benutzerverzeichnis, kein `sudo`.

## Installation

```sh
brew install ghostscript      # einmalig
./build.sh                    # holt foo2zjs (gepinnt), baut foo2hbpl1 + hbpldecode für arm64 nach bin/
./install.sh                  # installiert ins Benutzerverzeichnis
```

`install.sh` legt an:

| Ziel | Inhalt |
|---|---|
| `~/.local/bin/dellprint` | das Kommandozeilenprogramm |
| `~/.local/bin/dellprint-pdfservice` | Aufrufziel für den Druckdialog (3 Argumente) |
| `~/.local/share/dellprint/bin/` | `foo2hbpl1`, `hbpldecode` |
| `~/.config/dellprint/config` | Konfiguration (wird nie überschrieben) |
| `~/Library/PDF Services/An Dell C1660w senden.app` | Eintrag im PDF-Menü |

`~/.local/bin` muss im `PATH` liegen (z. B. in `~/.zshrc`:
`export PATH="$HOME/.local/bin:$PATH"`). Entfernen: `./uninstall.sh` (`--purge` löscht
auch Config und Protokoll).

## Benutzung

```sh
dellprint [Optionen] datei.pdf
  --host <IP|Name>    Drucker-Adresse
  --mono              Schwarzweiß (Standard: Farbe)
  --paper a4|letter   Papierformat (Standard: a4)
  --copies N          Kopien 1-99 (Standard: 1)
  --out <datei>       Datenstrom nur in Datei schreiben, nichts senden
  --dry-run           umwandeln + mit hbpldecode prüfen, nichts senden
```

Vor jedem Senden (auch bei `--out`/`--dry-run`) wird der erzeugte Datenstrom mit
`hbpldecode` dekodiert und geprüft: Seitenzahl = Seitenzahl des PDFs, Papierformat,
Farbmodus und 600 dpi. Weicht etwas ab, bricht `dellprint` mit Exit-Code 1 ab.

**Konfiguration** `~/.config/dellprint/config` (Shell-Syntax, `KEY=WERT`):
`HOST`, `PORT` (Standard 9100), `PAPER`, `GS` (Ghostscript-Pfad, von `install.sh` via
`brew --prefix` ermittelt), `FOO2HBPL1`, `HBPLDECODE`. Die Kommandozeile hat Vorrang.
Ist weder `--host` noch `HOST` gesetzt, sucht `dellprint` per Bonjour
(`_pdl-datastream._tcp`, Name beginnt mit „Dell C1660w Color Printer") und löst die
Adresse auf. Schlägt das fehl, kommt eine deutsche Fehlermeldung.
Empfohlen ist `HOST=DELLxxxxxx.local` (Bonjour-Hostname des Druckers, die letzten
sechs Stellen der MAC-Adresse; unabhängig von der IP-Vergabe des Routers); dann entfällt
die Suche. Aus dem Ruhezustand antwortet
der Drucker erst nach einigen Sekunden, `dellprint` prüft die Erreichbarkeit deshalb
bis zu viermal.

**Protokoll:** `~/Library/Logs/dellprint.log` (Zeit, Datei, Seiten, Ziel, Ergebnis).

**Druckdialog:** In jeder App *Drucken → PDF ▾ → An Dell C1660w senden*. Es erscheint
eine macOS-Mitteilung „gesendet" bzw. die Fehlermeldung.

### Warum eine .app statt eines Skripts im PDF-Menü?

Die Schnittstelle (`~/Library/PDF Services/`) ist undokumentiert. Klassisch reichte
ein ausführbares Skript, das die drei Argumente *Titel, CUPS-Optionen, PDF-Pfad*
bekommt. Berichte (u. a. Apple Developer Forums „PDF Service no longer working in
Big Sur", benwiggy/PDFsuite) sagen: seit Big Sur laufen rohe Skripte und Workflows
dort wegen der Sandbox nicht mehr zuverlässig; als robust gilt eine **Automator-/
AppleScript-App**, die die PDF als Dokument bekommt. Deshalb installiert
`install.sh` eine per `osacompile` gebaute Droplet-App, die
`dellprint-pdfservice` (das 3-Argument-Skript aus `pdf-service/`) aufruft.
**Getestet 30.09.2026 auf macOS 26.6.2:** Eintrag erscheint im PDF-Menü, Druck läuft
durch, Farben und Ränder auf dem echten Gerät in Ordnung.

## Woher stammen die Parameter?

Quelle: `foo2hbpl1-wrapper.in` und `PPD/Dell-C1660.ppd` aus mikerr/foo2zjs
(Commit `5bf0142d1e3d4363684608ac42933510d3b66e27`).

| Parameter | Wert | Herkunft |
|---|---|---|
| Auflösung | `-r600x600` | Wrapper: `RES=600x600 # do not change this`; Encoder setzt `RESOLUTION=600` |
| Gerät Farbe | `-sDEVICE=pamcmyk32` | Wrapper: bei `-c` (PPD `ColorMode Color` → `-c`) |
| Gerät Mono | `-sDEVICE=pgmraw` | Wrapper: `GSDEV=-sDEVICE=pgmraw` ohne `-c` |
| A4 | `-sPAPERSIZE=a4 -g4961x7016`, `foo2hbpl1` erkennt Format über die Pixelgröße | Wrapper: `1\|a4\|A4) DIM=4961x7016`; PPD `PageSize A4` → `-p1` |
| Letter | `-sPAPERSIZE=letter -g5100x6600` | Wrapper: `4\|letter) DIM=5100x6600` |
| Ränder | `foo2hbpl1 -u51,51,51,51` | Wrapper: `set_clipping 51 51 51 51` (0,085 inch) |
| Medium | `foo2hbpl1 -m1` (Normalpapier) | PPD `MediaType plain` → `-m1`, Wrapper `MEDIA=1` |
| Gs-Grundflags | `-q -dBATCH -dSAFER -dQUIET -dNOPAUSE` | Wrapper: `GS=...` |
| Jobname/User | `-J <Dateiname> -U <Benutzer>` | Wrapper: `-J "$LPJOB" -U "$USER"` |

Eigene Zusätze (nicht aus dem Wrapper): `-dFIXEDMEDIA -dPDFFitPage` skaliert die PDF-Seite
aufs Blatt (der Wrapper bekommt von CUPS bereits passendes PostScript); Querformat-Seiten
werden dadurch ins Hochformat gedreht.

## Abweichungen vom Wrapper / Unsicherheiten

* **Keine Farbprofile (CRD).** Der Wrapper nutzt im Farbmodus standardmäßig
  `COLORMODE=1` mit `crd/qpdl/CLP-300cms` + `black-text.ps` unter
  `/usr/share/foo2hbpl/crd/`. Diese Dateien sind für den *Samsung CLP-300* und werden vom
  Upstream-Makefile gar nicht nach `share/foo2hbpl` installiert (nur nach `foo2zjs`/`foo2qpdl`).
  `dellprint` schickt daher Ghostscripts CMYK ungeändert. Ob die Farben auf dem
  C1660w gut aussehen, ist **ungeprüft**; Nachjustieren wäre hier möglich.
* **Kopien:** `foo2hbpl1` hat keine Kopien-Option (der Wrapper parst `-n`, reicht es aber
  nicht weiter; im Strom steht immer `COPIES=1`). `--copies N` sendet den Auftrag
  daher N-mal nacheinander als eigenen Auftrag (jeweils komplett sortiert).
* **Upstream-Makefile:** Das Repo enthält fertige Linux-x86-64-Binaries
  (`foo2hbpl1` …); `make` hält sie für aktuell und baut nichts. `build.sh` kompiliert
  daher direkt mit `cc -arch arm64 -O2 -Wall` (Quellen: `foo2hbpl1.c`; `hbpldecode.c`,
  `jbig.c`, `jbig_ar.c`).
* Die Erreichbarkeitsprüfung öffnet kurz eine leere TCP-Verbindung (`nc -z`) auf Port 9100.
  Ob der Drucker das folgenlos wegsteckt, ist ohne Gerät ungeprüft.
* Im Bilddecoder erscheint am linken Rand eine 1-Pixel-Spalte; vermutlich Artefakt von
  `hbpldecode` (Bildbereich ist über `-u` ohnehin 51 px weiß). Ungeprüft.

## Grenzen

* Keine Fach-/Duplexwahl, keine Medienwahl, keine Optionen aus dem Druckdialog
  (das CUPS-Optionsargument wird ignoriert).
* Nur dieser Mac (Skripte und Binaries liegen im Benutzerverzeichnis). Kein iPhone/iPad.
* Farbe ohne Kalibrierung, siehe oben.

## Weitergabe an einen anderen Mac

`./make-dist.sh` baut `dist/dellprint-installer.zip` (`dist/` ist nicht im Git). Das
Paket ist für Nicht-Techniker gedacht und läuft auf Apple Silicon und Intel:

| Inhalt | Zweck |
|---|---|
| `Installieren.command` | Doppelklick-Installer: prüft macOS/Architektur, installiert bei Bedarf Homebrew (offizieller Installer, fragt nach dem Anmeldepasswort) und `ghostscript`, ruft `install.sh` auf (Config mit `HOST` aus `DELLPRINT_HOST`, leer = Bonjour-Suche), Selbsttest per `--dry-run`, optionaler Probedruck (Frage `[j/N]`). Idempotent; Protokoll in `~/Library/Logs/dellprint-install.log`. Trägt `brew shellenv` und `~/.local/bin` in `~/.zprofile` ein. |
| `Deinstallieren.command` | ruft `uninstall.sh` auf (Homebrew/Ghostscript bleiben; Config und Protokoll ebenfalls) |
| `ANLEITUNG.txt` | Anleitung für die Benutzerin (deutsch, eine Seite) |
| `dellprint`, `install.sh`, `uninstall.sh`, `pdf-service/`, `licenses/`, `README.md` | wie im Projekt |
| `bin/foo2hbpl1`, `bin/hbpldecode` | **Universal-Binaries** (arm64 + x86_64), gebaut mit `./build.sh --universal` |
| `test/testseite.pdf` | Testseite (2 Seiten) für Selbsttest und Probedruck |

`bin/` im Projekt bleibt der reine arm64-Build für diesen Mac (`./build.sh` ohne Option);
die Universal-Binaries entstehen nur im Paket. Das Zip enthält keine Symlinks, Skripte
sind ausführbar (`zip -X`, Rechte bleiben erhalten).

**Gatekeeper:** Das Paket ist weder signiert noch notarisiert. Beim ersten Start muss
`Installieren.command` per Rechtsklick → *Öffnen* gestartet werden; blockiert macOS
trotzdem: Systemeinstellungen → Datenschutz & Sicherheit → *Dennoch öffnen*. Der
Installer entfernt danach die Quarantäne-Markierung vom Paketordner. Die Binaries
tragen nur die Ad-hoc-Signatur des Linkers.

**Ungeprüft:** Lauf auf macOS 27 und auf Intel-Macs, echte Homebrew-Erstinstallation
(nur mit Ersatz-Installer getestet), Ghostscript-Bottle bzw. Quellbau unter macOS 27.

## Windows 11 (x64)

Zweite Variante für Windows 11 x64 (der Dell-Treiber läuft dort nicht mehr). Gleiche
Pipeline wie auf dem Mac, mit den gleichen Festwerten, nur mit Windows-Werkzeugen:

```
PDF --Ghostscript--> Raster 600x600 --foo2hbpl1.exe--> HBPL1 --TCP--> Drucker:9100
```

Nur PDF, nur x64. Kein virtueller Drucker im Druckdialog, keine Bonjour-Suche (Adresse
wird einmal eingetragen), kein Duplex/Fach, kein ARM64. Der Mac-Teil bleibt unverändert.

**Installation (Nicht-Techniker):** `dellprint-windows.zip` entpacken, `Installieren.cmd`
doppelklicken (Anleitung: `ANLEITUNG.txt` im Paket). Der Installer installiert
Ghostscript bei Bedarf (offizieller Installer aus dem GitHub-Release
`ArtifexSoftware/ghostpdl-downloads`, auf Version 10.08.0 und SHA256 gepinnt, still installiert,
UAC-Abfrage; kein winget – die Paket-ID existiert dort nicht mehr), kopiert dellprint nach
`%LOCALAPPDATA%\dellprint\`, legt `%APPDATA%\dellprint\config.txt` an (fragt die
Drucker-Adresse; `DELLPRINT_HOST` überspringt die Frage), trägt „Senden an → Dell C1660w“
ein, macht einen Selbsttest (`-DryRun`) und bietet einen Probedruck an.
**Ghostscript aktualisieren:** `gh api repos/ArtifexSoftware/ghostpdl-downloads/releases/latest`
liefert Tag und Asset-URL (`gs<ver>w64.exe`); SHA256 per `Get-FileHash`/`shasum -a 256`; dann
`$GS_VERSION`, `$GS_URL`, `$GS_SHA256` im Kopf von `windows/install.ps1` anpassen.
**SmartScreen:** Das Paket ist nicht signiert. Beim ersten Start „Weitere Informationen →
Trotzdem ausführen“.

**Benutzung:** PDF rechtsklicken → Senden an → Dell C1660w (Windows 11: zuerst „Weitere
Optionen anzeigen“). Kommandozeile (Windows PowerShell 5.1):

```powershell
dellprint.ps1 [-PrinterHost <IP|Name>] [-Mono] [-Paper a4|letter] [-Copies 1-99]
              [-Out <datei>] [-DryRun] [-Gui] datei.pdf [datei2.pdf ...]
```

Konfiguration `%APPDATA%\dellprint\config.txt` (`KEY=WERT`, wird geparst, nicht
ausgeführt): `HOST`, `PORT`, `PAPER`, `GS`, `FOO2HBPL1`, `HBPLDECODE`; die Kommandozeile
hat Vorrang. Ghostscript wird gesucht in: Config `GS` → Registry → `C:\Program
Files\gs\gs*\bin\gswin64c.exe` → `PATH`. Protokoll: `%LOCALAPPDATA%\dellprint\dellprint.log`.
Prüfungen und Exit-Codes (0/1/2) wie auf dem Mac. Entfernen: `Deinstallieren.cmd`
(`-Purge` löscht auch Config und Protokolle).

**Binärdaten** laufen nie durch PowerShell-Pipes (PS 5.1 behandelt sie als Text): die
Umwandlung läuft über `cmd.exe`-Pipes, gesendet wird per `TcpClient` aus der Datei.

**Bauen:** `./build-windows.sh` (macOS: `brew install mingw-w64`; Linux: `apt install
mingw-w64`) erzeugt `bin-win/foo2hbpl1.exe` und `hbpldecode.exe` (statisch, x64) aus
demselben gepinnten foo2zjs-Commit wie `build.sh`, mit Binärmodus-Patch
(`windows/patches/`). `GS=gs ./make-dist-windows.sh` baut `dist/dellprint-windows.zip`.

**Tests:** `.github/workflows/windows.yml` (GitHub Actions): Linux-Job baut Binaries,
Referenz-Datenstrom (nativer Encoder) und Paket; Windows-Job (`windows-latest`, Windows
PowerShell 5.1, Ghostscript per `choco`) führt `tests/windows/run-tests.ps1` aus
(Umwandlung, Dekodierung, Encoder-Gleichheit gegen die Referenz, Fehlerfälle, Senden an
einen lokalen Listener, Mehrfachdateien, Config-Vorrang, Protokoll, Installer/Deinstaller).

**Ungeprüft:** Lauf auf einem echten Windows-11-Rechner mit echtem Drucker,
Download von github.com durch Firmen-Proxy/Virenscanner, Auflösung von `DELLxxxxxx.local` per mDNS, Farbwiedergabe.

## Tests

`tests/run-tests.sh` (kein echter Drucker, Senden nur gegen `127.0.0.1`; benötigt
`python3` für den Test-Listener). Testet Umwandlung, Dekodierung, Farbe vs. Mono, Fehlerfälle,
Bonjour-Pfad (mit Ersatz-`dns-sd`), Sendeweg und Kopien.

## Lizenz

`foo2zjs` (`foo2hbpl1`, `hbpldecode`, JBIG-Code) steht unter der **GPL-2.0-or-later**;
Copyright Rick Richardson u. a. (siehe `licenses/foo2zjs-COPYING`, Quelle:
https://github.com/mikerr/foo2zjs). Die Skripte dieses Projekts stehen ebenfalls unter
GPL-2.0-or-later. Wer die gebauten Binaries weitergibt, muss den Quellcode
mitliefern bzw. anbieten. Ghostscript (AGPL) wird nur als externes Programm aufgerufen.
