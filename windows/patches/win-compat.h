/*
 * win-compat.h - Windows-Anpassung fuer foo2hbpl1 und hbpldecode (dellprint).
 *
 * Wird von windows/patches/0001-windows-binaermodus.patch in die beiden
 * Quelldateien eingebunden und von build-windows.sh ins Quellverzeichnis
 * kopiert.  Lizenz wie foo2zjs: GPL-2.0-or-later.
 *
 * Problem: Unter Windows oeffnet die C-Laufzeit stdin/stdout und fopen(.., "r")
 * im Textmodus (0x0A <-> 0x0D 0x0A, 0x1A = Dateiende).  Die Rasterdaten
 * (Eingabe) und der HBPL-Datenstrom (Ausgabe) sind binaer und wuerden so
 * zerstoert.
 */
#ifndef WIN_COMPAT_H
#define WIN_COMPAT_H
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <stdio.h>
/* Alle Dateien (auch fopen "r"/"w") standardmaessig binaer. */
#define WIN_BINARY_STDIO() \
    do { \
        _fmode = _O_BINARY; \
        _setmode(_fileno(stdin),  _O_BINARY); \
        _setmode(_fileno(stdout), _O_BINARY); \
    } while (0)
#else
#define WIN_BINARY_STDIO() do { } while (0)
#endif
#endif
