#!/bin/bash
# Erzeugt ein Test-PDF: 2 Seiten A4, Farbflaechen C/M/Y/K/R/G/B, Text,
# Randrahmen 5 mm vom Blattrand.  Aufruf: make-testpdf.sh ausgabe.pdf
set -euo pipefail
OUT="${1:?Ausgabedatei fehlt}"
GS="${GS:-/opt/homebrew/bin/gs}"
"$GS" -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sPAPERSIZE=a4 -sOutputFile="$OUT" - <<'PS'
/mm { 2.834646 mul } def
/frame { 0 setgray 0.5 setlinewidth 5 mm 5 mm 210 mm 10 mm sub 297 mm 10 mm sub rectstroke } def
/box { % r g b x y  -> Flaeche 25x25 mm; setzt Farbe ueber cmyk oder rgb (siehe unten)
  gsave 25 mm 25 mm rectfill grestore } def
/lab { /Helvetica findfont 9 scalefont setfont 0 setgray moveto show } def
/cmykbox { % c m y k x y
  gsave translate setcmykcolor 0 0 25 mm 25 mm rectfill grestore } def
/rgbbox { gsave translate setrgbcolor 0 0 25 mm 25 mm rectfill grestore } def
% Seite 1: Farben
frame
/Helvetica-Bold findfont 20 scalefont setfont 0 setgray 20 mm 270 mm moveto (Dell C1660w Testseite 1/2) show
1 0 0 0  20 mm 220 mm cmykbox  (Cyan) 20 mm 215 mm lab
0 1 0 0  55 mm 220 mm cmykbox  (Magenta) 55 mm 215 mm lab
0 0 1 0  90 mm 220 mm cmykbox  (Gelb) 90 mm 215 mm lab
0 0 0 1  125 mm 220 mm cmykbox (Schwarz) 125 mm 215 mm lab
1 0 0    20 mm 170 mm rgbbox   (Rot) 20 mm 165 mm lab
0 1 0    55 mm 170 mm rgbbox   (Gruen) 55 mm 165 mm lab
0 0 1    90 mm 170 mm rgbbox   (Blau) 90 mm 165 mm lab
0 setgray /Times-Roman findfont 12 scalefont setfont 20 mm 130 mm moveto
(Franz jagt im komplett verwahrlosten Taxi quer durch Bayern. aeoeue 0123456789) show
showpage
% Seite 2: Text + Rahmen
frame
/Helvetica-Bold findfont 20 scalefont setfont 0 setgray 20 mm 270 mm moveto (Dell C1660w Testseite 2/2) show
/Courier findfont 10 scalefont setfont
20 mm 250 mm moveto (Zweite Seite: Text und Rahmen 5 mm vom Blattrand.) show
0 0 0 1 20 mm 200 mm cmykbox  (K-Flaeche) 20 mm 195 mm lab
0.5 0.5 0.5 0.5 55 mm 200 mm cmykbox (Mix) 55 mm 195 mm lab
showpage
PS
echo "$OUT"
