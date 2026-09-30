#!/bin/bash
# Deinstallieren.command - entfernt dellprint (Doppelklick).
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "$PKG" || exit 1
LOG="$HOME/Library/Logs/dellprint-install.log"
mkdir -p "$HOME/Library/Logs"
exec > >(tee -a "$LOG") 2>&1

echo "dellprint wird deinstalliert ($(date '+%d.%m.%Y %H:%M:%S')) ..."
rc=0
./uninstall.sh || rc=$?
echo
if [ "$rc" -eq 0 ]; then
    echo "Fertig. Der Eintrag im PDF-Menue und das Programm sind entfernt."
    echo "Homebrew und Ghostscript bleiben installiert (sie schaden nicht und werden"
    echo "ggf. von anderen Programmen genutzt). Ihre Einstellungen (Drucker-Adresse) und"
    echo "das Druckprotokoll bleiben ebenfalls erhalten."
else
    echo "!! FEHLER: Die Deinstallation ist fehlgeschlagen (Code $rc). Protokoll: $LOG"
fi
if [ -t 0 ]; then
    echo
    printf 'Zum Schliessen des Fensters bitte die Eingabetaste druecken ... '
    read -r _
fi
exit "$rc"
