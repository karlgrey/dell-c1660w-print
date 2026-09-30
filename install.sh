#!/bin/bash
# install.sh - installiert dellprint NUR ins Benutzerverzeichnis (kein sudo).
#   ~/.local/bin/dellprint, ~/.local/bin/dellprint-pdfservice
#   ~/.local/share/dellprint/bin/{foo2hbpl1,hbpldecode}
#   ~/.config/dellprint/config
#   ~/Library/PDF Services/An Dell C1660w senden.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -ne 0 ] || { echo "Nicht als root ausfuehren." >&2; exit 1; }

BINDIR="$HOME/.local/bin"
SHAREDIR="$HOME/.local/share/dellprint/bin"
CONFDIR="$HOME/.config/dellprint"
PDFSVC="$HOME/Library/PDF Services"
APP="$PDFSVC/An Dell C1660w senden.app"

# Drucker-Adresse fuer eine NEUE Config (leer = Bonjour-Suche). Beispiel:
#   DELLPRINT_HOST=DELL0C56BA.local ./install.sh
HOST_VALUE="${DELLPRINT_HOST:-}"

# Ghostscript: Pfad ueber 'brew --prefix' ermitteln
GS=""
if command -v brew >/dev/null 2>&1; then
    GS="$(brew --prefix)/bin/gs"
fi
if [ -z "$GS" ] || [ ! -x "$GS" ]; then
    for c in /opt/homebrew/bin/gs /usr/local/bin/gs; do
        [ -x "$c" ] && { GS="$c"; break; }
    done
fi
if [ -z "$GS" ] || [ ! -x "$GS" ]; then
    echo "Ghostscript fehlt. Bitte 'brew install ghostscript' ausfuehren." >&2
    exit 1
fi

# Binaries aus bin/ nehmen; nur im Projekt (mit build.sh) bei Bedarf bauen
if [ ! -x "$ROOT/bin/foo2hbpl1" ] || [ ! -x "$ROOT/bin/hbpldecode" ]; then
    if [ -x "$ROOT/build.sh" ]; then
        "$ROOT/build.sh"
    else
        echo "bin/foo2hbpl1 bzw. bin/hbpldecode fehlen im Paket." >&2
        exit 1
    fi
fi

mkdir -p "$BINDIR" "$SHAREDIR" "$CONFDIR" "$PDFSVC"
install -m 755 "$ROOT/bin/foo2hbpl1" "$ROOT/bin/hbpldecode" "$SHAREDIR/"
install -m 755 "$ROOT/dellprint" "$BINDIR/dellprint"
sed "s|@DELLPRINT@|$BINDIR/dellprint|" "$ROOT/pdf-service/an-dell-c1660w-senden.sh" \
    >"$BINDIR/dellprint-pdfservice"
chmod 755 "$BINDIR/dellprint-pdfservice"

# Config nur anlegen, wenn es noch keine gibt (HOST leer -> Bonjour, sonst DELLPRINT_HOST)
if [ ! -e "$CONFDIR/config" ]; then
    cat >"$CONFDIR/config" <<CFG
# dellprint-Konfiguration (wird von dellprint als Shell-Datei gelesen)
# Drucker-Adresse; leer lassen = per Bonjour suchen
HOST=$HOST_VALUE
PAPER=a4
GS=$GS
FOO2HBPL1=$SHAREDIR/foo2hbpl1
HBPLDECODE=$SHAREDIR/hbpldecode
CFG
    echo "Config angelegt: $CONFDIR/config"
else
    echo "Config bleibt unveraendert: $CONFDIR/config"
fi

# PDF-Service als Droplet-App (Automator/AppleScript-App; siehe README)
tmp="$(mktemp -t dellsvc).applescript"
sed "s|@SERVICE@|$BINDIR/dellprint-pdfservice|" "$ROOT/pdf-service/Dell-C1660w.applescript" >"$tmp"
rm -rf "$APP"
osacompile -o "$APP" "$tmp"
rm -f "$tmp"
# Droplet: PDFs annehmen, App nicht im Dock zeigen
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes array" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0 dict" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string PDF" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string com.adobe.pdf" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo
echo "Installiert:"
echo "  $BINDIR/dellprint"
echo "  $BINDIR/dellprint-pdfservice"
echo "  $SHAREDIR/{foo2hbpl1,hbpldecode}"
echo "  $APP"
[ -n "${DELLPRINT_NO_PATH_HINT:-}" ] || case ":$PATH:" in *":$BINDIR:"*) ;; *) echo "Hinweis: $BINDIR ist nicht im PATH (z. B. in ~/.zshrc ergaenzen)." ;; esac
echo "Test: dellprint --help"
