#!/bin/bash
# Tests fuer dellprint - senden NIE an einen echten Drucker (nur lokaler Listener).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
export DELLPRINT_CONFIG="$T/config" DELLPRINT_LOG="$T/log"
DP="$ROOT/dellprint"
DEC="$ROOT/bin/hbpldecode"
PASS=0 FAIL=0
ok()  { echo "PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
check() { # Name, Bedingung-Exitcode
    if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi
}
# Vergleich ohne PJL-Kopf (enthaelt Datum/Uhrzeit des Umwandelns)
same() { [ "$(wc -c <"$1")" -eq "$(wc -c <"$2")" ] && cmp -s <(tail -c +400 "$1") <(tail -c +400 "$2"); }
expect_fail() { # Name, erwarteter Text, Befehl...
    local name="$1" pat="$2"; shift 2
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "$pat"; then ok "$name (rc=$rc: $(printf '%s' "$out" | tail -n 1))"
    else bad "$name (rc=$rc, Ausgabe: $out)"; fi
}

"$ROOT/tests/make-testpdf.sh" "$T/test.pdf" >/dev/null

echo "== Umwandlung =="
if "$DP" --out "$T/color.hbpl" "$T/test.pdf" >"$T/o1" 2>&1; then ok "--out Farbe rc=0"; else bad "--out Farbe rc=0"; fi
if "$DP" --out "$T/mono.hbpl" --mono "$T/test.pdf" >"$T/o2" 2>&1; then ok "--out --mono rc=0"; else bad "--out --mono rc=0"; fi
if "$DP" --dry-run "$T/test.pdf" >"$T/o3" 2>&1; then ok "--dry-run rc=0"; else bad "--dry-run rc=0"; fi
if grep -q "nichts gesendet" "$T/o3"; then ok "--dry-run sendet nichts"; else bad "--dry-run sendet nichts"; fi
if "$DP" --out "$T/letter.hbpl" --paper letter "$T/test.pdf" >/dev/null 2>&1; then ok "--paper letter rc=0"; else bad "--paper letter rc=0"; fi

echo "== Eigene Dekodierung mit hbpldecode =="
"$DEC" <"$T/color.hbpl" >"$T/dc" 2>&1; "$DEC" <"$T/mono.hbpl" >"$T/dm" 2>&1; "$DEC" <"$T/letter.hbpl" >"$T/dl" 2>&1
if [ "$(grep -c 'image found' "$T/dc")" = 2 ]; then ok "Farbe: 2 Seiten"; else bad "Farbe: 2 Seiten"; fi
if [ "$(grep -c 'image found' "$T/dm")" = 2 ]; then ok "Mono: 2 Seiten"; else bad "Mono: 2 Seiten"; fi
if [ "$(grep -c 'paper=A4' "$T/dc")" = 2 ]; then ok "Farbe: Papier A4"; else bad "Farbe: Papier A4"; fi
if grep -q 'SET RESOLUTION=600' "$T/dc"; then ok "Aufloesung 600 dpi"; else bad "Aufloesung 600 dpi"; fi
if grep -q 'RENDERMODE=COLOR' "$T/dc" && grep -q '\[Color\]' "$T/dc"; then ok "Farbe: RENDERMODE=COLOR, [Color]"; else bad "Farbe: RENDERMODE=COLOR, [Color]"; fi
if grep -q 'RENDERMODE=GRAYSCALE' "$T/dm" && grep -q '\[Mono\]' "$T/dm" && ! grep -q '\[Color\]' "$T/dm"; then ok "Mono: RENDERMODE=GRAYSCALE, [Mono]"; else bad "Mono: RENDERMODE=GRAYSCALE, [Mono]"; fi
if grep -q 'paper=Letter' "$T/dl"; then ok "Letter: Papier Letter"; else bad "Letter: Papier Letter"; fi
if grep -q 'a2 c4: 4968x7016' "$T/dc"; then ok "A4 Seitengroesse 4968x7016 px (4961 auf Vielfaches von 8 aufgefuellt)"; else bad "A4 Seitengroesse 4968x7016 px (4961 auf Vielfaches von 8 aufgefuellt)"; fi

echo "== Bildinhalt (dekodierte Rasterseite 1, Farbe vs. Mono) =="
mkdir -p "$T/img"
"$DEC" -d "$T/img/c" <"$T/color.hbpl" >/dev/null 2>&1; "$DEC" -d "$T/img/m" <"$T/mono.hbpl" >/dev/null 2>&1
(cd "$T/img" && echo *)
if ! cmp -s "$T/img/c-01.ppm" "$T/img/m-01.pgm"; then ok "Raster Farbe != Raster Mono"; else bad "Raster Farbe != Raster Mono"; fi
if [ "$(wc -c <"$T/color.hbpl")" -gt 0 ]; then ok "Datenstrom nicht leer"; else bad "Datenstrom nicht leer"; fi
# Mono-Bild: dekodiert als PPM mit nur Grauwerten? (R=G=B je Pixel)
python3 - "$T/img/m-01.pgm" "$T/img/c-01.ppm" <<'PY'
import sys
def load(p):
    d=open(p,'rb').read()
    nl=d.index(b'\n'); hd=d[:nl].split()   # "Px w h 255"
    return int(hd[1]),int(hd[2]),d[nl+1:],hd[0]
w,h,m,mt=load(sys.argv[1]); _,_,c,ct=load(sys.argv[2])
print("Mono-Raster:",mt.decode(),"(P5=Graustufen)  Farb-Raster:",ct.decode(),"(P6=RGB)")
def colored(buf):
    n=0
    if len(buf)==0: return 0
    for i in range(0,len(buf)-2,3*997):
        r,g,b=buf[i],buf[i+1],buf[i+2]
        if not (abs(r-g)<8 and abs(g-b)<8): n+=1
    return n
print("Bild %dx%d  farbige Stichproben: Mono=%d  Farbe=%d"%(w,h,colored(m),colored(c)))
sys.exit(0 if mt==b"P5" and colored(c)>0 else 1)
PY
check "Mono-Bild grau, Farb-Bild enthaelt Farben" $?

echo "== Fehlerfaelle =="
expect_fail "Datei fehlt" "nicht gefunden" "$DP" --dry-run "$T/gibtsnicht.pdf"
echo "kein pdf" >"$T/x.txt"
expect_fail "Datei ist kein PDF" "keine PDF" "$DP" --dry-run "$T/x.txt"
printf '%%PDF-1.4\nkaputt\n' >"$T/kaputt.pdf"
expect_fail "PDF defekt" "nicht lesbar\|fehlgeschlagen\|keine Seiten" "$DP" --dry-run "$T/kaputt.pdf"
expect_fail "Host nicht erreichbar" "nicht erreichbar" "$DP" --host 192.0.2.1 "$T/test.pdf"
expect_fail "Unbekannte Option" "Unbekannte Option" "$DP" --foo "$T/test.pdf"
expect_fail "Papier ungueltig" "Unbekanntes Papierformat" "$DP" --paper a3 "$T/test.pdf"
expect_fail "copies ungueltig" "copies" "$DP" --copies 0 "$T/test.pdf"
# Bonjour: dns-sd-Ersatz ohne Treffer
printf '#!/bin/sh\nexit 0\n' >"$T/dnssd-none"; chmod +x "$T/dnssd-none"
DELLPRINT_DNSSD="$T/dnssd-none" DELLPRINT_BROWSE_SECS=1 \
  expect_fail "Kein Drucker per Bonjour" "Kein Drucker per Bonjour" "$DP" "$T/test.pdf"
if grep -q 'ergebnis=FEHLER' "$T/log"; then ok "Fehler im Protokoll"; else bad "Fehler im Protokoll"; fi

echo "== Sendeweg gegen lokalen Listener (127.0.0.1) =="
printf 'HOST=127.0.0.1\nPORT=19100\n' >"$T/config"
# Listener nimmt zuerst die Erreichbarkeitspruefung (leer), dann den Auftrag an
python3 "$ROOT/tests/listener.py" 19100 2 "$T/recv.bin" &
LPID=$!; sleep 1
"$DP" "$T/test.pdf" >"$T/send.out" 2>&1; rc=$?; check "Senden rc=0" $rc
sleep 1; wait $LPID 2>/dev/null
if same "$T/recv.bin" "$T/color.hbpl"; then ok "Empfangene Bytes == --out-Datei (ohne Zeitstempel-Kopf) ($(wc -c <"$T/recv.bin" | tr -d ' ') Bytes)"; else bad "Empfangene Bytes == --out-Datei (ohne Zeitstempel-Kopf) ($(wc -c <"$T/recv.bin" | tr -d ' ') Bytes)"; fi
tail -n 2 "$T/send.out"
# Kopien: 2 Verbindungen nacheinander
: >"$T/recv2.bin"
python3 "$ROOT/tests/listener.py" 19100 3 "$T/recv2.bin" &
sleep 1
if "$DP" --copies 2 "$T/test.pdf" >"$T/send2.out" 2>&1; then ok "Senden --copies 2 rc=0"; else bad "Senden --copies 2 rc=0"; fi
sleep 1
if echo "recv2=$(wc -c <"$T/recv2.bin") erwartet=$((2 * $(wc -c <"$T/color.hbpl")))"; [ "$(wc -c <"$T/recv2.bin")" -eq $((2 * $(wc -c <"$T/color.hbpl"))) ]; then ok "2 Kopien = doppelte Bytes"; else bad "2 Kopien = doppelte Bytes"; fi
# Bonjour-Ersatz mit Treffer -> Adresse aufloesen -> senden
cat >"$T/dnssd-fake" <<'FAKE'
#!/bin/sh
case "$1" in
  -B) echo "Timestamp A/R Flags if Domain Service Type Instance Name"
      echo "12:00:00.000  Add  2  4 local.  _pdl-datastream._tcp.  Dell C1660w Color Printer (ABC123)"
      sleep 30 ;;
  -L) echo "Dell C1660w Color Printer (ABC123)._pdl-datastream._tcp.local. can be reached at localhost.:19100 (interface 4)"
      sleep 30 ;;
esac
FAKE
chmod +x "$T/dnssd-fake"
printf 'PAPER=a4\nPORT=9999\n' >"$T/config"
python3 "$ROOT/tests/listener.py" 19100 2 "$T/recv3.bin" &
sleep 1
sleep 1
if DELLPRINT_DNSSD="$T/dnssd-fake" DELLPRINT_BROWSE_SECS=1 "$DP" "$T/test.pdf" >"$T/send3.out" 2>&1; then ok "Bonjour-Treffer -> senden rc=0"; else bad "Bonjour-Treffer -> senden rc=0"; fi
sleep 1
if echo "recv3=$(wc -c <"$T/recv3.bin") color=$(wc -c <"$T/color.hbpl")"; same "$T/recv3.bin" "$T/color.hbpl"; then ok "Bonjour-Weg: Bytes identisch"; else bad "Bonjour-Weg: Bytes identisch"; fi
grep "Bonjour\|gefunden" "$T/send3.out"
echo "== Protokoll =="; tail -n 3 "$T/log"
echo
echo "Ergebnis: $PASS bestanden, $FAIL fehlgeschlagen"
[ "$FAIL" -eq 0 ]
