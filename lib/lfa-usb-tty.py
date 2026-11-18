#!/usr/bin/env python3
"""USB serial bridge for Linux-for-Android guests.

Android gives Termux a usbfs file descriptor, not a tty.  This script claims
the bulk endpoints behind that descriptor and exposes them as a pty, so
ordinary Linux serial tools (esptool, avrdude, minicom, picocom, pyserial)
see a normal /dev/ttyUSB0.  Together with the session preload
(liblfa-usb-node.so) the pty is inherited by the guest shell as a descriptor
and mapped onto the node path, which works even where a proot guest has no
devpts of its own.

Supported bridges:
  CDC ACM   (class 0x02/0x0a: ESP32-S2/S3/C3 native USB bootloader)
  CP210x    (0x10c4: ESP32 DevKit, many boards)
  CH340     (0x1a86:7523: cheap ESP32/Arduino boards)

Baud changes made by the client (termios on the pty) are forwarded to the
real chip, and DTR/RTS changes are forwarded through the session preload so
esptool's automatic reset sequence works.

Usage:
    lfa-usb-tty.py [--fd N] [--node /dev/ttyUSB0] [--baud 115200]
                   [--command CMD] [-- ARGS...]
    lfa-usb-tty.py --selftest
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import fcntl
import importlib.util
import os
import pty
import select
import struct
import sys
import termios
import time
import tty
from typing import Any, Dict, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))


def _load_desc() -> Any:
    for candidate in (os.path.join(HERE, "usb-desc.py"),
                      os.path.join(HERE, "lfa-usb-desc.py"),
                      "/usr/local/libexec/lfa-usb-desc.py"):
        if os.path.exists(candidate):
            path = candidate
            break
    else:
        raise RuntimeError("usb-desc.py is not installed next to lfa-usb-tty.py")
    spec = importlib.util.spec_from_file_location("lfa_usb_desc", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


desc = _load_desc()

TIOCM_DTR = 0x002
TIOCM_RTS = 0x004


class BulkTransfer(ctypes.Structure):
    _fields_ = [
        ("ep", ctypes.c_uint),
        ("len", ctypes.c_uint),
        ("timeout", ctypes.c_uint),
        ("data", ctypes.c_void_p),
    ]


def _ioc(direction: int, kind: int, nr: int, size: int) -> int:
    return (direction << 30) | (size << 16) | (kind << 8) | nr


USBDEVFS_BULK = _ioc(3, ord("U"), 2, ctypes.sizeof(BulkTransfer))
USBDEVFS_CLAIMINTERFACE = _ioc(2, ord("U"), 15, 4)
USBDEVFS_RELEASEINTERFACE = _ioc(2, ord("U"), 16, 4)
USBDEVFS_CLEAR_HALT = _ioc(2, ord("U"), 21, 4)


class BridgeError(Exception):
    """The device cannot be used as a serial port."""


# ---------------------------------------------------------------------------
# Chip-specific control requests
# ---------------------------------------------------------------------------


def control(fd: int, request_type: int, request: int, value: int,
            index: int, data: bytes = b"", length: Optional[int] = None) -> None:
    length = len(data) if length is None else length
    desc.control_transfer(fd, request_type, request, value, index,
                          length if data else 0)


class CdcAcm:
    name = "cdc-acm"

    def __init__(self, fd: int, interface: int) -> None:
        self.fd = fd
        self.interface = interface
        self.baud = 0
        self.dtr = False
        self.rts = False

    def open(self) -> None:
        self.set_lines(TIOCM_DTR | TIOCM_RTS, 0)
        self.set_baud(115200)

    def set_baud(self, baud: int) -> None:
        if baud == self.baud:
            return
        payload = struct.pack("<IBBB", baud, 0, 0, 8)
        control(self.fd, 0x21, 0x20, 0, self.interface, payload)
        self.baud = baud

    def set_lines(self, set_bits: int, clear_bits: int) -> None:
        if set_bits & TIOCM_DTR:
            self.dtr = True
        if set_bits & TIOCM_RTS:
            self.rts = True
        if clear_bits & TIOCM_DTR:
            self.dtr = False
        if clear_bits & TIOCM_RTS:
            self.rts = False
        value = (1 if self.dtr else 0) | (2 if self.rts else 0)
        control(self.fd, 0x21, 0x22, value, self.interface)


class Cp210x:
    name = "cp210x"

    def __init__(self, fd: int, interface: int) -> None:
        self.fd = fd
        self.interface = interface
        self.baud = 0
        self.dtr = False
        self.rts = False

    def open(self) -> None:
        control(self.fd, 0x41, 0x00, 1, self.interface)          # IFC_ENABLE
        self.set_baud(115200)
        self.set_lines(TIOCM_DTR | TIOCM_RTS, 0)

    def set_baud(self, baud: int) -> None:
        if baud == self.baud:
            return
        control(self.fd, 0x41, 0x1E, 0, self.interface,
                struct.pack("<I", baud))                          # SET_BAUDRATE
        control(self.fd, 0x41, 0x03, 0x0800, self.interface)        # 8N1
        self.baud = baud

    def set_lines(self, set_bits: int, clear_bits: int) -> None:
        if set_bits & TIOCM_DTR:
            self.dtr = True
        if set_bits & TIOCM_RTS:
            self.rts = True
        if clear_bits & TIOCM_DTR:
            self.dtr = False
        if clear_bits & TIOCM_RTS:
            self.rts = False
        value = 0x100 | 0x200  # WRITE_DTR | WRITE_RTS
        if self.dtr:
            value |= 0x01
        if self.rts:
            value |= 0x02
        control(self.fd, 0x41, 0x07, value, self.interface)         # SET_MHS


class Ch340:
    name = "ch340"
    CLKRATE = 48000000

    def __init__(self, fd: int, interface: int) -> None:
        self.fd = fd
        self.interface = interface
        self.baud = 0
        self.version = 0x30
        self.dtr = False
        self.rts = False

    def _out(self, request: int, value: int, index: int) -> None:
        control(self.fd, 0x40, request, value, index)

    def open(self) -> None:
        try:
            data = desc.control_transfer(self.fd, 0xC0, 0x5F, 0, 0, 2)
            if len(data) >= 1:
                self.version = data[0]
        except desc.UsbError:
            pass
        self._out(0xA1, 0, 0)                                      # SERIAL_INIT
        self.set_baud(115200)

    def divisor(self, baud: int) -> int:
        baud = max(50, min(baud, self.CLKRATE // 2))
        fact = 1
        ps = 3
        for candidate in (3, 2, 1, 0):
            if baud > self.CLKRATE // ((1 << (12 - 3 * candidate - 1)) * 512):
                ps = candidate
                break
        else:
            ps = 0
        clk_div = 1 << (12 - 3 * ps - fact)
        div = self.CLKRATE // (clk_div * baud)
        if div < 9 or div > 255:
            div //= 2
            clk_div *= 2
            fact = 0
        div = max(2, min(255, div))
        if div < 255:
            first = 16 * self.CLKRATE // (clk_div * div) - 16 * baud
            second = 16 * baud - 16 * self.CLKRATE // (clk_div * (div + 1))
            if first >= second:
                div += 1
        if fact == 1 and div % 2 == 0:
            div //= 2
            fact = 0
        return ((0x100 - div) << 8) | (fact << 2) | ps

    def set_baud(self, baud: int) -> None:
        if baud == self.baud:
            return
        value = self.divisor(baud)
        if self.version > 0x27:
            value |= 0x80
        self._out(0x9A, 0x1312, value)                             # divisor
        if self.version >= 0x30:
            self._out(0x9A, 0x2518, 0xC3)                          # 8N1
        self.baud = baud

    def set_lines(self, set_bits: int, clear_bits: int) -> None:
        if set_bits & TIOCM_DTR:
            self.dtr = True
        if set_bits & TIOCM_RTS:
            self.rts = True
        if clear_bits & TIOCM_DTR:
            self.dtr = False
        if clear_bits & TIOCM_RTS:
            self.rts = False
        mcr = 0
        if self.dtr:
            mcr |= 1 << 5
        if self.rts:
            mcr |= 1 << 6
        self._out(0xA4, (~mcr) & 0xFFFF, 0)                        # MODEM_CTRL


def pick_bridge(result: Dict[str, Any]) -> Tuple[str, int, Optional[Any]]:
    """Return (kind, interface, bridge) for a descriptor report."""
    vid = str(result.get("vid", "")).lower()
    for config in result.get("configurations", []):
        for iface in config.get("interfaces", []):
            if iface.get("class") == "02":
                return "cdc-acm", int(iface.get("number", 0)), None
    for config in result.get("configurations", []):
        for iface in config.get("interfaces", []):
            endpoints = iface.get("endpoints", [])
            bulk = [ep for ep in endpoints
                    if int(str(ep.get("attributes", "0x0")), 0) & 3 == 2]
            if vid == "10c4" and len(bulk) >= 2:
                return "cp210x", int(iface.get("number", 0)), None
            if vid == "1a86" and len(bulk) >= 2:
                return "ch340", int(iface.get("number", 0)), None
    return "generic", 0, None


def find_endpoints(result: Dict[str, Any], interface: int,
                   cdc: bool) -> Tuple[int, int, int]:
    """Return (bulk_in, bulk_out, data_interface) endpoint addresses."""
    wanted = interface
    candidates: List[Dict[str, Any]] = []
    for config in result.get("configurations", []):
        for iface in config.get("interfaces", []):
            if cdc:
                if iface.get("class") == "0a":
                    candidates.append(iface)
            elif int(iface.get("number", -1)) == wanted:
                candidates.append(iface)
    for iface in candidates:
        ep_in = ep_out = 0
        for ep in iface.get("endpoints", []):
            attributes = int(str(ep.get("attributes", "0x0")), 0) & 3
            if attributes != 2:
                continue
            address = int(str(ep.get("address", "0x0")), 0)
            if address & 0x80 and not ep_in:
                ep_in = address
            elif not (address & 0x80) and not ep_out:
                ep_out = address
        if ep_in and ep_out:
            return ep_in, ep_out, int(iface.get("number", 0))
    raise BridgeError("no bulk IN/OUT endpoint pair on this device")


def bulk_transfer(fd: int, endpoint: int, data: Any, timeout: int = 100) -> Tuple[int, bytes]:
    """Transfer bytes, or read up to `data` bytes when it is an int."""
    if isinstance(data, int):
        payload = b""
        length = data
    else:
        payload = data
        length = len(data)
    buffer = ctypes.create_string_buffer(max(length, 1))
    if payload:
        ctypes.memmove(buffer, payload, length)
    transfer = BulkTransfer(endpoint, length, timeout,
                            ctypes.cast(buffer, ctypes.c_void_p))
    count = fcntl.ioctl(fd, USBDEVFS_BULK, transfer)
    return int(count), bytes(buffer.raw[:max(count, 0)])


def claim(fd: int, interface: int) -> None:
    try:
        fcntl.ioctl(fd, USBDEVFS_CLAIMINTERFACE, struct.pack("I", interface))
    except OSError as exc:
        if exc.errno == errno.EBUSY:
            raise BridgeError(
                "interface %d is already claimed by a kernel driver; "
                "Android cannot detach it without root" % interface) from exc
        raise BridgeError("cannot claim interface %d: %s" % (interface, exc)) from exc


def release(fd: int, interface: int) -> None:
    try:
        fcntl.ioctl(fd, USBDEVFS_RELEASEINTERFACE, struct.pack("I", interface))
    except OSError:
        pass


def termios_bauds() -> Dict[int, int]:
    table: Dict[int, int] = {}
    for name in dir(termios):
        if name.startswith("B") and name[1:].isdigit():
            table[getattr(termios, name)] = int(name[1:])
    return table


BAUDS = termios_bauds()


def read_baud(fd: int) -> int:
    try:
        attrs = termios.tcgetattr(fd)
    except termios.error:
        return 0
    speed = attrs[5] or attrs[4]
    return BAUDS.get(speed, 0)


def make_pty() -> Tuple[int, int]:
    master, slave = pty.openpty()
    try:
        tty.setraw(slave, termios.TCSANOW)
    except termios.error:
        pass
    mode = termios.tcgetattr(slave)
    mode[0] = 0
    mode[1] = 0
    mode[3] = 0
    mode[4] = termios.B115200
    mode[5] = termios.B115200
    try:
        termios.tcsetattr(slave, termios.TCSANOW, mode)
    except termios.error:
        pass
    try:
        os.chmod(os.ttyname(slave), 0o666)
    except OSError:
        pass
    os.set_blocking(master, False)
    return master, slave


def serve(fd: int, result: Dict[str, Any], node: str, baud: int,
          command: List[str]) -> int:
    kind, interface, _ = pick_bridge(result)
    ep_in, ep_out, data_interface = find_endpoints(
        result, interface, kind == "cdc-acm")

    if kind == "cdc-acm":
        bridge: Any = CdcAcm(fd, interface)
    elif kind == "cp210x":
        bridge = Cp210x(fd, interface)
    elif kind == "ch340":
        bridge = Ch340(fd, interface)
    else:
        bridge = None

    claim(fd, interface)
    if data_interface != interface:
        claim(fd, data_interface)
    try:
        if bridge is not None:
            bridge.open()
            bridge.set_baud(baud)
        else:
            print("lfa-usb-tty: unknown bridge chip; raw 8N1 pipe only",
                  file=sys.stderr)

        master, slave = make_pty()
        node_created = False
        try:
            if not os.path.lexists(node):
                os.symlink(os.ttyname(slave), node)
                node_created = True
        except OSError:
            pass

        ctl_r, ctl_w = os.pipe()
        os.set_inheritable(ctl_w, True)
        os.set_inheritable(slave, True)

        child = os.fork()
        if child == 0:                                       # pragma: no cover
            try:
                os.close(master)
                os.close(ctl_r)
                if slave != 9:
                    os.dup2(slave, 9)
                    os.close(slave)
                os.set_inheritable(9, True)
                environment = dict(os.environ)
                environment["LFA_USB_TTY"] = node
                environment["LFA_USB_TTY_FD"] = "9"
                environment["LFA_USB_TTY_CTL"] = str(ctl_w)
                environment["TERM"] = environment.get("TERM", "xterm-256color")
                if command:
                    os.execvpe(command[0], command, environment)
                shell = environment.get("SHELL", "/bin/bash")
                os.execvpe(shell, [shell, "-l"], environment)
            finally:
                os._exit(127)

        os.close(slave)
        os.close(ctl_w)

        print("lfa-usb-tty: %s on %s (bulk %02x/%02x, baud %d)" % (
            kind, node, ep_in, ep_out, baud), file=sys.stderr, flush=True)
        if kind == "cdc-acm":
            print("lfa-usb-tty: tip: esptool --port %s" % node,
                  file=sys.stderr, flush=True)

        output = b""
        last_baud = read_baud(master)
        last_poll = time.monotonic()
        status = 0
        done = 0
        try:
            while True:
                if output:
                    try:
                        written = os.write(master, output)
                        output = output[written:]
                    except BlockingIOError:
                        pass
                waitables = [ctl_r, master]
                ready, _, _ = select.select(waitables, [], [], 0.02)
                if ctl_r in ready:
                    message = os.read(ctl_r, 64)
                    for offset in range(0, len(message) - 4, 5):
                        op = message[offset:offset + 1]
                        bits = struct.unpack("<i", message[offset + 1:offset + 5])[0]
                        if bridge is not None:
                            if op == b"s":
                                bridge.set_lines(bits, 0)
                            elif op == b"c":
                                bridge.set_lines(0, bits)
                            elif op == b"m":
                                bridge.set_lines(bits, ~bits & (TIOCM_DTR | TIOCM_RTS))
                if master in ready and not output:
                    try:
                        chunk = os.read(master, 4096)
                    except BlockingIOError:
                        chunk = b""
                    except OSError as exc:
                        if exc.errno == errno.EIO:
                            break          # every pty slave was closed
                        raise
                    if chunk:
                        offset = 0
                        while offset < len(chunk):
                            try:
                                count, _ = bulk_transfer(fd, ep_out, chunk[offset:], 500)
                            except OSError as exc:
                                if exc.errno == errno.ETIMEDOUT:
                                    break
                                raise
                            if count <= 0:
                                break
                            offset += count
                try:
                    if len(output) < 65536:
                        count, payload = bulk_transfer(fd, ep_in, 4096, 20)
                        if count > 0:
                            output += payload
                except OSError as exc:
                    if exc.errno not in (errno.ETIMEDOUT, errno.EAGAIN):
                        raise

                now = time.monotonic()
                if now - last_poll > 0.2:
                    last_poll = now
                    wanted = read_baud(master)
                    if wanted and wanted != last_baud:
                        last_baud = wanted
                        if bridge is not None:
                            bridge.set_baud(wanted)

                done, status = os.waitpid(child, os.WNOHANG)
                if done:
                    status = os.waitstatus_to_exitcode(status)
                    break
            if not done:
                _, status = os.waitpid(child, 0)
                status = os.waitstatus_to_exitcode(status)
        finally:
            os.close(master)
            os.close(ctl_r)
            release(fd, interface)
            if data_interface != interface:
                release(fd, data_interface)
            if node_created:
                try:
                    os.unlink(node)
                except OSError:
                    pass
        return status
    except Exception:
        release(fd, interface)
        if data_interface != interface:
            release(fd, data_interface)
        raise


def selftest() -> int:
    # CH340 divisor for 115200 must be in the documented range.
    chip = Ch340(-1, 0)
    value = chip.divisor(115200)
    assert 0 < value <= 0xFFFF
    assert (value & 0x0F) <= 3
    payload = struct.pack("<IBBB", 115200, 0, 0, 8)
    assert len(payload) == 7
    # Endpoint selection from a synthetic CDC descriptor report.
    report = {"vid": "303a", "configurations": [{"interfaces": [
        {"number": 0, "class": "02", "endpoints": [
            {"address": "0x83", "attributes": "0x03"}]},
        {"number": 1, "class": "0a", "endpoints": [
            {"address": "0x81", "attributes": "0x02"},
            {"address": "0x02", "attributes": "0x02"}]},
    ]}]}
    assert pick_bridge(report)[0] == "cdc-acm"
    assert find_endpoints(report, 0, True) == (0x81, 0x02, 1)
    cp = {"vid": "10c4", "configurations": [{"interfaces": [
        {"number": 0, "class": "ff", "endpoints": [
            {"address": "0x81", "attributes": "0x02"},
            {"address": "0x01", "attributes": "0x02"},
            {"address": "0x82", "attributes": "0x03"}]}]}]}
    assert pick_bridge(cp)[0] == "cp210x"
    assert find_endpoints(cp, 0, False) == (0x81, 0x01, 0)
    # DTR/RTS changes must merge with the current state: esptool sets and
    # clears one line at a time, and the other must survive.
    calls = []
    saved = globals()["control"]

    def fake_control(fd, request_type, request, value, index, data=b""):
        calls.append((request, value))

    globals()["control"] = fake_control
    try:
        cdc = CdcAcm(-1, 0)
        cdc.set_lines(TIOCM_DTR, 0)
        cdc.set_lines(TIOCM_RTS, 0)
        assert calls[-1] == (0x22, 3)
        cdc.set_lines(0, TIOCM_DTR)
        assert calls[-1] == (0x22, 2)      # RTS survives a DTR clear
        chip = Ch340(-1, 0)
        chip.set_lines(TIOCM_DTR, 0)
        chip.set_lines(TIOCM_RTS, 0)
        assert calls[-1][0] == 0xA4
        assert (~calls[-1][1]) & 0x60 == 0x60
        chip.set_lines(0, TIOCM_DTR)
        assert (~calls[-1][1]) & 0x60 == 0x40
    finally:
        globals()["control"] = saved
    print("selftest: ok")
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Expose a Termux:API usbfs descriptor as a serial pty.")
    parser.add_argument("--fd", type=int, default=None)
    parser.add_argument("--node", default="/dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()

    fd = args.fd
    if fd is None:
        raw = os.environ.get("TERMUX_USB_FD", "").strip()
        if not raw:
            print("lfa-usb-tty: no USB descriptor; start with "
                  "'lfa usb tty' in Termux", file=sys.stderr)
            return 3
        fd = int(raw)

    command = [item for item in args.command if item != "--"]
    path = os.environ.get("LFA_USB_PATH", "")
    bus = os.environ.get("LFA_USB_BUS", "")
    dev = os.environ.get("LFA_USB_DEV", "")
    try:
        result = desc.read_device(fd, path, bus, dev)
        return serve(fd, result, args.node, args.baud, command)
    except (desc.UsbError, BridgeError) as exc:
        print("lfa-usb-tty: %s" % exc, file=sys.stderr)
        return 4
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
