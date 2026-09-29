#!/usr/bin/env python3
"""Lokaler Test-Listener: nimmt N Verbindungen an (127.0.0.1:PORT), haengt alle
empfangenen Bytes an DATEI an.  Ersatz fuer einen Drucker bei den Tests."""
import socket, sys
port, count, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port))
s.listen(5)
open(out, "ab").close()
for _ in range(count):
    c, _a = s.accept()
    with open(out, "ab") as f:
        while True:
            d = c.recv(65536)
            if not d:
                break
            f.write(d)
    c.close()
