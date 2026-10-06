#!/bin/bash
# make-dist-windows.sh - baut das Weitergabe-Paket dist/dellprint-windows.zip
# (Windows 11 x64: Skripte, foo2hbpl1.exe/hbpldecode.exe, Anleitung, Testseite).
# Voraussetzung: bin-win/ (./build-windows.sh) und Ghostscript fuer die Testseite
# (Umgebungsvariable GS, Standard wie tests/make-testpdf.sh).
# .cmd/.ps1/.txt im Paket haben CRLF-Zeilenenden (BOM bleibt erhalten).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
NAME="dellprint-windows"
STAGE="$DIST/$NAME"
ZIP="$DIST/$NAME.zip"
BINWIN="${BINWIN:-$ROOT/bin-win}"

for f in foo2hbpl1.exe hbpldecode.exe; do
    [ -f "$BINWIN/$f" ] || { echo "FEHLER: $BINWIN/$f fehlt - erst ./build-windows.sh ausfuehren." >&2; exit 1; }
done

rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE/bin" "$STAGE/test" "$STAGE/licenses"

crlf() { # $1 = Quelle, $2 = Ziel: Zeilenenden auf CRLF
    sed -e 's/\r$//' -e 's/$/\r/' "$1" >"$2"
}

echo "== Paket zusammenstellen =="
for f in Installieren.cmd Deinstallieren.cmd sendto.cmd install.ps1 gs-install.ps1 uninstall.ps1 dellprint.ps1 ANLEITUNG.txt; do
    crlf "$ROOT/windows/$f" "$STAGE/$f"
done
crlf "$ROOT/README.md" "$STAGE/README.md"
cp "$BINWIN/foo2hbpl1.exe" "$BINWIN/hbpldecode.exe" "$STAGE/bin/"
cp "$ROOT"/licenses/* "$STAGE/licenses/"
"$ROOT/tests/make-testpdf.sh" "$STAGE/test/testseite.pdf" >/dev/null

# Quellcode-Angebot (GPL): Patch + Compat-Header liegen bei
mkdir -p "$STAGE/licenses/patches"
cp "$ROOT"/windows/patches/* "$STAGE/licenses/patches/"

if [ -n "$(find "$STAGE" -type l)" ]; then
    echo "FEHLER: Symlinks im Paket" >&2
    exit 1
fi
find "$STAGE" \( -name '.DS_Store' -o -name '._*' \) -delete

(cd "$DIST" && COPYFILE_DISABLE=1 zip -qrX "$NAME.zip" "$NAME")

echo "== Pruefung =="
for f in Installieren.cmd Deinstallieren.cmd sendto.cmd install.ps1 gs-install.ps1 uninstall.ps1 dellprint.ps1; do
    # CRLF durchgehend?
    n_lf="$(grep -c '' "$STAGE/$f")"
    n_crlf="$(grep -c $'\r$' "$STAGE/$f")"
    [ "$n_lf" = "$n_crlf" ] || { echo "FEHLER: $f hat nicht ueberall CRLF" >&2; exit 1; }
done
for f in install.ps1 gs-install.ps1 uninstall.ps1 dellprint.ps1 ANLEITUNG.txt; do
    head -c 3 "$STAGE/$f" | od -An -tx1 | grep -qE 'ef +bb +bf' || { echo "FEHLER: $f ohne UTF-8-BOM" >&2; exit 1; }
done
unzip -Z "$ZIP" | grep -q '^l' && { echo "FEHLER: Symlink im Zip" >&2; exit 1; }
unzip -Zl "$ZIP" | tail -n 1
echo "Fertig: $ZIP"
