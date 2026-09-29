#!/bin/bash
# uninstall.sh - entfernt alles, was install.sh angelegt hat (nur Benutzerverzeichnis).
# Config und Protokoll bleiben, ausser mit --purge.
set -euo pipefail
rm -f "$HOME/.local/bin/dellprint" "$HOME/.local/bin/dellprint-pdfservice"
rm -rf "$HOME/.local/share/dellprint"
rm -rf "$HOME/Library/PDF Services/An Dell C1660w senden.app"
rm -f "$HOME/Library/PDF Services/An Dell C1660w senden"
if [ "${1:-}" = "--purge" ]; then
    rm -rf "$HOME/.config/dellprint"
    rm -f "$HOME/Library/Logs/dellprint.log"
    echo "Config und Protokoll ebenfalls entfernt."
else
    echo "Config ($HOME/.config/dellprint) und Protokoll bleiben; --purge entfernt sie."
fi
echo "dellprint deinstalliert."
