#!/bin/bash
# "An Dell C1660w senden" - Aufrufziel fuer das PDF-Menue des Druckdialogs.
# macOS uebergibt drei Argumente: $1 = Titel, $2 = CUPS-Optionen, $3 = PDF-Pfad.
# Die CUPS-Optionen ($2) werden bewusst ignoriert (siehe README, Grenzen).
# Minimaler PATH im Druckdialog -> alles mit absoluten Pfaden.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

DELLPRINT="${DELLPRINT_BIN:-@DELLPRINT@}"
TITLE="${1:-Dokument}"
PDF="${3:-}"

notify() { # $1 = Text, $2 = Titel
    [ -n "${DELLPRINT_NO_NOTIFY:-}" ] && return 0
    /usr/bin/osascript -e 'on run argv' \
        -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
        -e 'end run' -- "$1" "$2" >/dev/null 2>&1 || true
}

if [ -z "$PDF" ] || [ ! -f "$PDF" ]; then
    msg="Keine PDF-Datei uebergeben."
    notify "$msg" "Dell C1660w - Fehler"
    echo "$msg" >&2
    exit 1
fi

out="$("$DELLPRINT" "$PDF" 2>&1)"
rc=$?
last="$(printf '%s\n' "$out" | tail -n 1)"
if [ "$rc" -eq 0 ]; then
    notify "\"$TITLE\" wurde gesendet." "Dell C1660w"
    echo "$last"
    exit 0
fi
notify "$last" "Dell C1660w - Fehler"
echo "$last" >&2
exit "$rc"
