#!/bin/bash
# make-reference.sh - erzeugt die Referenzdaten fuer die Windows-Tests (laeuft in der CI
# auf Linux, lokal auch auf dem Mac):
#   test.pdf                    Test-PDF (2 Seiten A4, tests/make-testpdf.sh)
#   color.pam / mono.pnm        Ghostscript-Raster 600x600 (Eingabe fuer foo2hbpl1)
#   color.ref.hbpl / .dec.txt   nativ gebauter foo2hbpl1 + hbpldecode (Linux/Mac)
#   mono.ref.hbpl  / .dec.txt
# Die Windows-Tests fuettern DIESELBEN Raster in foo2hbpl1.exe und vergleichen
# Datenstrom und Dekodierung - das belegt, dass die Windows-Binaries (Binaermodus-Patch)
# denselben HBPL-Strom erzeugen.  Das Raster stammt bewusst nicht aus dem Ghostscript
# des Windows-Laufers (andere gs-Version koennte andere Pixel liefern).
#
# Aufruf: tests/windows/make-reference.sh <Zielordner>    (Umgebung: GS=gs-Pfad)
# Voraussetzung: build/foo2zjs (gepinnte Quellen, legt build-windows.sh an).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?Zielordner fehlt}"
GS="${GS:-gs}"
SRC="$ROOT/build/foo2zjs"
[ -f "$SRC/foo2hbpl1.c" ] || { echo "FEHLER: $SRC fehlt - erst ./build-windows.sh ausfuehren." >&2; exit 1; }
mkdir -p "$OUT"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "Baue native Referenz-Tools ..."
# gleiche Flags wie build-windows.sh (siehe dort, Abweichung 4); clang kennt
# -fno-aggressive-loop-optimizations nicht
EXTRA=()
if echo 'int main(void){return 0;}' | cc -x c -fno-aggressive-loop-optimizations -o /dev/null - 2>/dev/null; then
    EXTRA=(-fno-aggressive-loop-optimizations)
fi
cc -O2 -Wall ${EXTRA[@]+"${EXTRA[@]}"} -o "$T/foo2hbpl1" "$SRC/foo2hbpl1.c" 2>/dev/null
cc -O2 -Wall -I"$SRC" -o "$T/hbpldecode" "$SRC/hbpldecode.c" "$SRC/jbig.c" "$SRC/jbig_ar.c" 2>/dev/null

export GS
"$ROOT/tests/make-testpdf.sh" "$OUT/test.pdf" >/dev/null

raster() { # Geraet, Ausgabe
    "$GS" -q -dBATCH -dSAFER -dQUIET -dNOPAUSE -dFIXEDMEDIA -dPDFFitPage \
        -sPAPERSIZE=a4 -g4961x7016 -r600x600 -sDEVICE="$1" -sOutputFile="$2" "$OUT/test.pdf"
}
raster pamcmyk32 "$OUT/color.pam"
raster pgmraw    "$OUT/mono.pnm"

# Feste Auftragsangaben: dieselben Argumente verwenden die Windows-Tests (-J testseite.pdf -U ci)
enc() { "$T/foo2hbpl1" -m1 -u51,51,51,51 -J testseite.pdf -U ci <"$1" >"$2"; }
enc "$OUT/color.pam" "$OUT/color.ref.hbpl"
enc "$OUT/mono.pnm"  "$OUT/mono.ref.hbpl"
for k in color mono; do
    "$T/hbpldecode" <"$OUT/$k.ref.hbpl" >"$OUT/$k.ref.dec.txt" 2>&1
done
ls -l "$OUT"
