#!/bin/bash
# build-windows.sh - baut foo2hbpl1.exe und hbpldecode.exe (Windows x64) per
# Cross-Compiler aus foo2zjs.  Laeuft auf macOS (brew install mingw-w64) und
# Linux (apt install mingw-w64).
#
# Quelle: dieselbe wie build.sh (gepinnter Commit FOO2ZJS_REF) - der Wert wird
# aus build.sh gelesen, nicht dupliziert.  Die Quellen liegen in build/foo2zjs
# (gemeinsam mit build.sh); gepatcht wird eine KOPIE (build/foo2zjs-win), damit
# der native Mac-Build unberuehrt bleibt.
#
# ABWEICHUNGEN vom Upstream:
#  1. Wie in build.sh: das Upstream-Makefile baut wegen eingecheckter
#     Linux-ELF-Binaries nichts - es wird direkt mit dem Compiler uebersetzt
#     (Flags wie im Makefile: -O2 -Wall).
#  2. Binaermodus: windows/patches/0001-windows-binaermodus.patch + win-compat.h
#     setzen am Programmanfang beider Tools _fmode = _O_BINARY sowie
#     _setmode(_fileno(stdin|stdout), _O_BINARY).  Ohne das wuerde die
#     Windows-C-Laufzeit 0x0A/0x1A in Raster- und HBPL-Daten verfaelschen.
#  3. POSIX-Luecken: nur getopt() wird gebraucht und liegt in mingw-w64
#     (unistd.h).  utsname/uname sind in foo2hbpl1.c ohnehin nur unter
#     "#ifdef linux" - unter Windows bleibt der Rechnername im PJL-Kopf leer
#     (wie auf dem Mac, wo "linux" ebenfalls nicht definiert ist).
#  4. Upstream-Fehler in foo2hbpl1.c (encode_page): die Papiertabellen-Schleife
#     laeuft mit i++ statt i+=3 und liest am Ende ueber das Array hinaus; gcc
#     meldet "-Waggressive-loop-optimizations".  Das Verhalten wird NICHT
#     geaendert (Ausgabe soll dem bewaehrten Mac-Build entsprechen), aber mit
#     -fno-aggressive-loop-optimizations wird verhindert, dass der Compiler die
#     Schleife wegen des undefinierten Verhaltens umbaut.  Die CI vergleicht
#     die Ausgabe gegen einen nativen Linux-Build (tests/windows/make-reference.sh).
#  5. -static: keine DLL-Abhaengigkeiten (geprueft unten per objdump).
#
# Aufruf:  ./build-windows.sh [Zielordner]     (Standard: bin-win/)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CC="${CC_WIN:-x86_64-w64-mingw32-gcc}"
BIN="${1:-$ROOT/bin-win}"
SRC="$ROOT/build/foo2zjs"
WSRC="$ROOT/build/foo2zjs-win"

command -v "$CC" >/dev/null 2>&1 || {
    echo "FEHLER: $CC nicht gefunden. macOS: 'brew install mingw-w64', Linux: 'apt install mingw-w64'." >&2
    exit 1
}

FOO2ZJS_REPO="$(sed -n 's/^FOO2ZJS_REPO="\(.*\)"$/\1/p' "$ROOT/build.sh")"
FOO2ZJS_REF="$(sed -n 's/^FOO2ZJS_REF="\(.*\)"$/\1/p' "$ROOT/build.sh")"
[ -n "$FOO2ZJS_REPO" ] && [ -n "$FOO2ZJS_REF" ] || { echo "FEHLER: FOO2ZJS_REF nicht in build.sh gefunden." >&2; exit 1; }

if [ -d "$SRC/.git" ] && [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$FOO2ZJS_REF" ]; then
    echo "Quellen bereits vorhanden ($FOO2ZJS_REF)."
else
    rm -rf "$SRC"
    mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin "$FOO2ZJS_REPO"
    git -C "$SRC" fetch -q --depth 1 origin "$FOO2ZJS_REF"
    git -C "$SRC" checkout -q FETCH_HEAD
    got="$(git -C "$SRC" rev-parse HEAD)"
    [ "$got" = "$FOO2ZJS_REF" ] || { echo "FEHLER: falscher Commit $got (erwartet $FOO2ZJS_REF)" >&2; exit 1; }
fi

# Gepatchte Arbeitskopie (nur die gebrauchten Dateien)
rm -rf "$WSRC"
mkdir -p "$WSRC" "$BIN" "$ROOT/licenses"
for f in foo2hbpl1.c hbpldecode.c jbig.c jbig_ar.c jbig.h jbig_ar.h COPYING; do
    cp "$SRC/$f" "$WSRC/$f"
done
cp "$ROOT/windows/patches/win-compat.h" "$WSRC/"
(cd "$WSRC" && patch -p1 -s <"$ROOT/windows/patches/0001-windows-binaermodus.patch")

CFLAGS=(-O2 -Wall -static -fno-aggressive-loop-optimizations)

echo "Baue foo2hbpl1.exe ..."
"$CC" "${CFLAGS[@]}" -o "$BIN/foo2hbpl1.exe" "$WSRC/foo2hbpl1.c"

echo "Baue hbpldecode.exe ..."
"$CC" "${CFLAGS[@]}" -I"$WSRC" -o "$BIN/hbpldecode.exe" \
    "$WSRC/hbpldecode.c" "$WSRC/jbig.c" "$WSRC/jbig_ar.c"

cp "$WSRC/COPYING" "$ROOT/licenses/foo2zjs-COPYING" 2>/dev/null || true

# Pruefung: x64-PE und keine fremden DLLs (nur Windows-System-DLLs erlaubt)
OBJDUMP="${CC%-gcc}-objdump"
for f in foo2hbpl1.exe hbpldecode.exe; do
    file "$BIN/$f"
    if ! file "$BIN/$f" | grep -q 'PE32+ executable.*x86-64'; then
        echo "FEHLER: $f ist keine x64-PE-Datei" >&2; exit 1
    fi
    if command -v "$OBJDUMP" >/dev/null 2>&1; then
        dlls="$("$OBJDUMP" -p "$BIN/$f" | sed -n 's/^.*DLL Name: //p' | tr 'A-Z' 'a-z' | sort -u | tr '\n' ' ')"
        echo "$f: DLLs: $dlls"
        for d in $dlls; do
            case "$d" in
                kernel32.dll|msvcrt.dll|api-ms-win-crt-*.dll|ucrtbase.dll) ;;
                *) echo "FEHLER: $f haengt von $d ab" >&2; exit 1 ;;
            esac
        done
    fi
done
echo "Fertig: $BIN"
