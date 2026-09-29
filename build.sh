#!/bin/bash
# build.sh - baut foo2hbpl1 und hbpldecode nativ (arm64) aus foo2zjs.
#
# Upstream-Quelle: https://github.com/mikerr/foo2zjs, gepinnt auf einen Commit
# (derselbe wie im Projekt BThacker/dell-c1660w-airprint, Dockerfile FOO2ZJS_REF).
#
# ABWEICHUNG vom Upstream-Makefile: Das Repository enthaelt fertig
# eingecheckte Linux-x86-64-ELF-Binaries (foo2hbpl1, hbpldecode ...). `make`
# haelt sie fuer aktuell und baut NICHTS. Deshalb wird hier direkt mit cc
# uebersetzt (Quellen und Flags entsprechen den Makefile-Regeln: -O2 -Wall).
set -euo pipefail

FOO2ZJS_REPO="https://github.com/mikerr/foo2zjs"
FOO2ZJS_REF="5bf0142d1e3d4363684608ac42933510d3b66e27"

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/build/foo2zjs"
BIN="$ROOT/bin"

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
    if [ "$got" != "$FOO2ZJS_REF" ]; then
        echo "FEHLER: falscher Commit $got (erwartet $FOO2ZJS_REF)" >&2
        exit 1
    fi
fi

mkdir -p "$BIN" "$ROOT/licenses"
CFLAGS=(-arch arm64 -O2 -Wall)

echo "Baue foo2hbpl1 ..."
cc "${CFLAGS[@]}" -o "$BIN/foo2hbpl1" "$SRC/foo2hbpl1.c"

echo "Baue hbpldecode ..."
cc "${CFLAGS[@]}" -I"$SRC" -o "$BIN/hbpldecode" \
    "$SRC/hbpldecode.c" "$SRC/jbig.c" "$SRC/jbig_ar.c"

cp "$SRC/COPYING" "$ROOT/licenses/foo2zjs-COPYING" 2>/dev/null || true

for f in foo2hbpl1 hbpldecode; do
    file "$BIN/$f"
    if ! lipo -archs "$BIN/$f" | grep -qx arm64; then
        echo "FEHLER: $f ist nicht arm64" >&2
        exit 1
    fi
done
echo "Fertig: $BIN"
