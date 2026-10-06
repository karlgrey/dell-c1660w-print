#!/bin/bash
# Installieren.command - Doppelklick-Installer fuer dellprint (Dell C1660w).
# Installiert bei Bedarf Homebrew + Ghostscript und danach dellprint ins
# Benutzerverzeichnis (Skript install.sh, kein sudo fuer dellprint selbst).
#
# Test-Hooks (nur fuer Entwickler, im Normalbetrieb ungesetzt):
#   DELLPRINT_BREW_CANDIDATES  Leerzeichen-Liste statt /opt/homebrew/bin/brew /usr/local/bin/brew
#   DELLPRINT_BREW_INSTALLER   lokales Skript statt des offiziellen Homebrew-Installers

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "$PKG" || exit 1

LOG="$HOME/Library/Logs/dellprint-install.log"
mkdir -p "$HOME/Library/Logs"
exec > >(tee -a "$LOG") 2>&1

export DELLPRINT_NO_PATH_HINT=1   # PATH tragen wir unten selbst in ~/.zprofile ein
export DELLPRINT_HOST="${DELLPRINT_HOST:-}"   # leer = Drucker per Bonjour suchen
BREW_CANDIDATES="${DELLPRINT_BREW_CANDIDATES:-/opt/homebrew/bin/brew /usr/local/bin/brew}"
BREW_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
DELLPRINT_BIN="$HOME/.local/bin/dellprint"
STEP=0
STEPS=6

pause_if_interactive() {
    if [ -t 0 ]; then
        echo
        printf 'Zum Schliessen des Fensters bitte die Eingabetaste druecken ... '
        read -r _
    fi
}

heading() {
    STEP=$((STEP + 1))
    echo
    echo "=============================================================="
    echo " Schritt $STEP von $STEPS: $1"
    echo "=============================================================="
}

fail() { # $1 = Problem, weitere Argumente = Hinweiszeilen
    local msg="$1" l
    shift
    echo
    echo "!! FEHLER: $msg"
    for l in "$@"; do echo "   $l"; done
    echo "   Protokoll: $LOG"
    echo "   Bitte dieses Protokoll bzw. einen Screenshot dieses Fensters weitergeben."
    pause_if_interactive
    exit 1
}

find_brew() {
    local c
    for c in $BREW_CANDIDATES; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done
    command -v brew 2>/dev/null
}

echo "dellprint-Installer  -  $(date '+%d.%m.%Y %H:%M:%S')"
echo "Paketordner: $PKG"

# ---------------------------------------------------------------- 1
heading "Vorbereitung und Systempruefung"
if /usr/bin/xattr -dr com.apple.quarantine "$PKG" 2>/dev/null; then
    echo "Sperrmarkierung (Quarantaene) vom Paketordner entfernt."
else
    echo "Hinweis: Sperrmarkierung konnte nicht entfernt werden - wird ignoriert."
fi
ARCH="$(uname -m)"
MACOS="$(sw_vers -productVersion 2>/dev/null || echo unbekannt)"
case "$ARCH" in
    arm64)  echo "Mac-Typ: Apple Silicon (arm64), macOS $MACOS" ;;
    x86_64) echo "Mac-Typ: Intel (x86_64), macOS $MACOS" ;;
    *)      fail "Unbekannter Mac-Typ '$ARCH'." "Dieses Paket gibt es nur fuer Apple-Silicon- und Intel-Macs." ;;
esac
for f in install.sh dellprint bin/foo2hbpl1 bin/hbpldecode test/testseite.pdf; do
    [ -e "$PKG/$f" ] || fail "Im Paket fehlt die Datei '$f'." \
        "Bitte das Zip erneut entpacken (ganzen Ordner verwenden, nichts loeschen)."
done
if [ -x "$DELLPRINT_BIN" ]; then
    echo "dellprint ist bereits installiert - es wird auf den Stand dieses Pakets gebracht."
fi

# ---------------------------------------------------------------- 2
heading "Homebrew (Programm-Verwaltung)"
BREW="$(find_brew)"
if [ -n "$BREW" ]; then
    echo "Homebrew ist bereits installiert: $BREW"
else
    echo "Homebrew ist noch nicht installiert und wird jetzt installiert."
    echo "Dabei fragt der Mac einmal nach Ihrem Anmelde-Passwort (Eingabe bleibt unsichtbar,"
    echo "einfach tippen und mit der Eingabetaste bestaetigen) und richtet ggf. die"
    echo "Entwickler-Werkzeuge von Apple ein. Das kann einige Minuten dauern - bitte warten."
    echo
    if [ -n "${DELLPRINT_BREW_INSTALLER:-}" ]; then
        /bin/bash "$DELLPRINT_BREW_INSTALLER" || fail "Die Homebrew-Installation ist fehlgeschlagen."
    else
        SCRIPT="$(curl -fsSL "$BREW_URL")" && [ -n "$SCRIPT" ] || fail \
            "Der Homebrew-Installer konnte nicht heruntergeladen werden." \
            "Ist der Mac mit dem Internet verbunden? Bitte spaeter erneut versuchen."
        /bin/bash -c "$SCRIPT" || fail "Die Homebrew-Installation ist fehlgeschlagen." \
            "Haeufige Ursache: falsches Passwort oder Benutzer ohne Administratorrechte."
    fi
    BREW="$(find_brew)"
    [ -n "$BREW" ] || fail "Homebrew wurde nicht gefunden, obwohl die Installation durchlief."
    echo "Homebrew installiert: $BREW"
fi
eval "$("$BREW" shellenv)"
ZPROFILE="$HOME/.zprofile"
if grep -qs 'brew shellenv' "$ZPROFILE"; then
    echo "Homebrew ist bereits in ~/.zprofile eingetragen."
else
    # shellcheck disable=SC2016  # $(...) soll wörtlich in die Datei
    printf '\n# Homebrew\neval "$(%s shellenv)"\n' "$BREW" >>"$ZPROFILE"
    echo "Homebrew fuer neue Terminal-Fenster in ~/.zprofile eingetragen."
fi

# ---------------------------------------------------------------- 3
heading "Ghostscript (wandelt PDF-Dateien fuer den Drucker um)"
PREFIX="$("$BREW" --prefix)"
GS="$PREFIX/bin/gs"
if [ -x "$GS" ]; then
    echo "Ghostscript ist bereits installiert."
else
    echo "Ghostscript wird jetzt mit Homebrew installiert. Das kann einige Minuten dauern."
    echo "Falls fuer Ihr macOS noch kein fertiges Paket existiert, baut Homebrew das Programm"
    echo "selbst - dann dauert es deutlich laenger (evtl. 30 Minuten und mehr). Bitte einfach warten."
    echo
    "$BREW" install ghostscript || fail "Ghostscript konnte nicht installiert werden." \
        "Bitte das Protokoll weitergeben; danach Installieren.command erneut starten."
fi
[ -x "$GS" ] || fail "Ghostscript wurde nicht gefunden ($GS)."
GS_VERSION="$("$GS" --version 2>&1)" || fail "Ghostscript laesst sich nicht starten." \
    "Ausgabe: $GS_VERSION"
echo "Ghostscript funktioniert: Version $GS_VERSION"

# ---------------------------------------------------------------- 4
heading "dellprint installieren"
if ! ./install.sh; then
    fail "install.sh ist fehlgeschlagen." "Die Meldung steht oben im Protokoll."
fi
[ -x "$DELLPRINT_BIN" ] || fail "dellprint wurde nicht installiert ($DELLPRINT_BIN fehlt)."
CONF="$HOME/.config/dellprint/config"
if grep -qs '\.local/bin' "$ZPROFILE"; then
    :
else
    # shellcheck disable=SC2016  # $HOME/$PATH sollen wörtlich in die Datei
    printf '\n# dellprint\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$ZPROFILE"
    echo "Befehl 'dellprint' fuer neue Terminal-Fenster in ~/.zprofile eingetragen."
fi
echo "Drucker-Adresse in der Konfiguration: $(grep '^HOST=' "$CONF" 2>/dev/null || echo 'HOST=(nicht gesetzt)')"

# ---------------------------------------------------------------- 5
heading "Selbsttest (es wird nichts gedruckt)"
if "$DELLPRINT_BIN" --dry-run test/testseite.pdf; then
    echo
    echo "Selbsttest bestanden: Testseite wurde umgewandelt und geprueft."
else
    fail "Der Selbsttest ist fehlgeschlagen." \
        "Die Meldung von dellprint steht direkt darueber."
fi

# ---------------------------------------------------------------- 6
heading "Probedruck"
echo "Jetzt kann eine Testseite (2 Seiten, mit Farben) gedruckt werden."
echo "Voraussetzung: Der Drucker ist eingeschaltet und im selben WLAN wie dieser Mac."
printf 'Probedruck jetzt senden? [j/N] '
ANSWER=""
read -r ANSWER || ANSWER=""
echo
case "$ANSWER" in
    j|J|ja|Ja|JA)
        if "$DELLPRINT_BIN" test/testseite.pdf; then
            echo "Probedruck gesendet - gleich sollte der Drucker anlaufen."
        else
            echo "Der Probedruck ist fehlgeschlagen (Meldung siehe oben)."
            echo "Die Installation selbst ist trotzdem fertig. Ist der Drucker an und im selben WLAN?"
            echo "Danach im Druckdialog erneut versuchen (siehe ANLEITUNG.txt)."
        fi
        ;;
    *) echo "Probedruck uebersprungen." ;;
esac

# ---------------------------------------------------------------- Ende
echo
echo "=============================================================="
echo " FERTIG - dellprint ist installiert"
echo "=============================================================="
echo "  Programm:      $DELLPRINT_BIN"
echo "  Konfiguration: $CONF"
echo "  PDF-Menue:     $HOME/Library/PDF Services/An Dell C1660w senden.app"
echo "  Protokoll:     $LOG"
echo
echo "Drucken ab jetzt in jedem Programm:"
echo "  ⌘P  ->  Menue \"PDF\" (unten links)  ->  \"An Dell C1660w senden\""
pause_if_interactive
exit 0
