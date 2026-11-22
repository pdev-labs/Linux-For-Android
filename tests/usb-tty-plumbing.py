#!/usr/bin/env python3
"""Plumbing test for lib/lfa-usb-tty.py (no USB hardware needed).

Runs the real serial bridge against a fake device: a socketpair stands in
for the bulk endpoints, control requests are accepted and ignored, and the
child command writes to the pty and reads the echo back.  This exercises the
pty setup, the fork/inherit hand-off, the relay loop, and the exit path.
"""

from __future__ import annotations

import importlib.util
import os
import signal
import socket
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "lfa_usb_tty", os.path.join(REPO, "lib", "lfa-usb-tty.py"))
tty = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(tty)

device, guest = socket.socketpair()
device.setblocking(False)
guest.setblocking(False)

tty.claim = lambda fd, interface: None
tty.release = lambda fd, interface: None
tty.desc.control_transfer = lambda *args, **kwargs: b"\x02\x00"


def fake_bulk(fd, endpoint, data, timeout=100):
    if endpoint & 0x80:
        size = data if isinstance(data, int) else len(data)
        try:
            chunk = guest.recv(size)
        except BlockingIOError:
            raise OSError(110, "timeout") from None
        return len(chunk), chunk
    if data:
        device.sendall(data)
    return len(data), b""


tty.bulk_transfer = fake_bulk

report = {
    "vid": "303a", "bus": "001", "dev": "002",
    "configurations": [{"interfaces": [
        {"number": 0, "class": "02", "endpoints": []},
        {"number": 1, "class": "0a", "endpoints": [
            {"address": "0x81", "attributes": "0x02"},
            {"address": "0x02", "attributes": "0x02"}]},
    ]}],
}


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        node = os.path.join(tmp, "ttyUSB0")
        command = ["/bin/sh", "-c",
                   "printf ping > %s; dd if=%s bs=4 count=1 2>/dev/null"
                   % (node, node)]
        signal.alarm(30)
        rc = tty.serve(3, report, node, 115200, command)
        signal.alarm(0)
        if rc != 0:
            print("plumbing: bridge exited %d" % rc, file=sys.stderr)
            return 1
    print("plumbing: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
