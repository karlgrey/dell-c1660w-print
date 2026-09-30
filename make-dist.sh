#!/bin/bash
# make-dist.sh - baut das Weitergabe-Paket dist/dellprint-installer.zip
# (Universal-Binaries arm64 + x86_64, Installer-Skripte, Anleitung, Testseite).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
NAME="dellprint-installer"
STAGE="$DIST/$NAME"
ZIP="$DIST/$NAME.zip"

rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE/bin" "$STAGE/test" "$STAGE/licenses"

echo "== Universal-Binaries bauen =="
"$ROOT/build.sh" --universal "$STAGE/bin"

echo "== Paket zusammenstellen =="
cp "$ROOT/dellprint" "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/README.md" "$STAGE/"
cp -R "$ROOT/pdf-service" "$STAGE/pdf-service"
cp "$ROOT"/licenses/* "$STAGE/licenses/"
cp "$ROOT/installer/Installieren.command" "$ROOT/installer/Deinstallieren.command" \
   "$ROOT/installer/ANLEITUNG.txt" "$STAGE/"
"$ROOT/tests/make-testpdf.sh" "$STAGE/test/testseite.pdf" >/dev/null

chmod 755 "$STAGE"/*.command "$STAGE/dellprint" "$STAGE/install.sh" "$STAGE/uninstall.sh" \
    "$STAGE/pdf-service"/*.sh "$STAGE/bin"/*
chmod 644 "$STAGE/ANLEITUNG.txt" "$STAGE/README.md" "$STAGE/test/testseite.pdf" \
    "$STAGE/pdf-service"/*.applescript "$STAGE/licenses"/*

# Keine Symlinks, keine AppleDouble-Reste
if [ -n "$(find "$STAGE" -type l)" ]; then
    echo "FEHLER: Symlinks im Paket" >&2
    exit 1
fi
find "$STAGE" \( -name '.DS_Store' -o -name '._*' \) -delete

# -X: keine Extra-Attribute (uid, Zeitstempel-Extras); -r: rekursiv; Rechte bleiben erhalten
(cd "$DIST" && COPYFILE_DISABLE=1 zip -qrX "$NAME.zip" "$NAME")

echo "== Pruefung =="
for f in foo2hbpl1 hbpldecode; do
    a="$(lipo -archs "$STAGE/bin/$f" | tr ' ' '\n' | sort | tr '\n' ' ')"
    [ "$a" = "arm64 x86_64 " ] || { echo "FEHLER: $f hat Architekturen '$a'" >&2; exit 1; }
done
unzip -Z "$ZIP" | grep -q '^l' && { echo "FEHLER: Symlink im Zip" >&2; exit 1; }
unzip -Zl "$ZIP" | tail -n 1
echo "Fertig: $ZIP"
