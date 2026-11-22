#!/usr/bin/env python3
"""Talk USB mass storage directly, without a block device node.

Android's ``usb-storage`` driver owns a card reader's interface and vold
mounts the card, so an app has no path to ``/dev/block/...``.  That is the
only reason raw writes look impossible: the block layer is closed, the USB
device is not.

Termux:API hands over the real usbfs descriptor.  On that descriptor this
script detaches the kernel driver, claims the mass-storage interface and
speaks the USB Mass Storage Bulk-Only Transport (BOT) protocol itself:

    lfa-usb-bot.py --probe            INQUIRY + READ CAPACITY + sector 0
    lfa-usb-bot.py --write IMAGE      SCSI WRITE(10) + read-back verification
    lfa-usb-bot.py --selftest         protocol bytes, no device

Read-only by default.  ``--write`` needs ``--yes`` and erases the card.

Usage:
    python3 lfa-usb-bot.py [--fd N] --probe [--json]
    python3 lfa-usb-bot.py [--fd N] --write IMAGE [--no-verify] [--yes]
    python3 lfa-usb-bot.py [--fd N] --export FILE
    python3 lfa-usb-bot.py [--fd N] --import FILE [--full] [--yes]
    python3 lfa-usb-bot.py --selftest

--export writes the whole card to a sparse file so ordinary tools (fdisk,
sfdisk, mkfs, dd, fsck) can work on it inside the guest; --import writes the
file back, touching only the 1 MiB chunks that differ.

The descriptor comes from ``$TERMUX_USB_FD`` when ``--fd`` is absent, which
is what ``termux-usb -E -e`` sets up.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import fcntl
import hashlib
import json
import os
import struct
import sys
import time
from typing import Any, Dict, List, Optional, Tuple


# --------------------------------------------------------------------------
# usbfs plumbing
# --------------------------------------------------------------------------

def _ioc(direction: int, kind: int, nr: int, size: int) -> int:
    return (direction << 30) | (size << 16) | (kind << 8) | nr


class CtrlTransfer(ctypes.Structure):
    _fields_ = [
        ("bRequestType", ctypes.c_uint8),
        ("bRequest", ctypes.c_uint8),
        ("wValue", ctypes.c_uint16),
        ("wIndex", ctypes.c_uint16),
        ("wLength", ctypes.c_uint16),
        ("timeout", ctypes.c_uint32),
        ("data", ctypes.c_void_p),
    ]


class BulkTransfer(ctypes.Structure):
    _fields_ = [
        ("ep", ctypes.c_uint),
        ("len", ctypes.c_uint),
        ("timeout", ctypes.c_uint),
        ("data", ctypes.c_void_p),
    ]


class DisconnectClaim(ctypes.Structure):
    _fields_ = [
        ("interface", ctypes.c_uint),
        ("flags", ctypes.c_uint),
        ("driver", ctypes.c_char * 256),
    ]


USBDEVFS_CONTROL = _ioc(3, ord("U"), 0, ctypes.sizeof(CtrlTransfer))
USBDEVFS_BULK = _ioc(3, ord("U"), 2, ctypes.sizeof(BulkTransfer))
USBDEVFS_CLAIMINTERFACE = _ioc(2, ord("U"), 15, 4)
USBDEVFS_RELEASEINTERFACE = _ioc(2, ord("U"), 16, 4)
USBDEVFS_CLEAR_HALT = _ioc(2, ord("U"), 21, 4)
# _IOR, not _IOWR: the kernel header defines it with _IOC_READ, and a
# direction mismatch makes usbfs reject the request with ENOTTY before it
# ever looks at the permission or the driver name.
USBDEVFS_DISCONNECT_CLAIM = _ioc(2, ord("U"), 27, ctypes.sizeof(DisconnectClaim))

GET_DESCRIPTOR = 0x06
DT_DEVICE = 1
DT_CONFIG = 2
DT_INTERFACE = 4
DT_ENDPOINT = 5

MASS_STORAGE_CLASS = 0x08
BOT_PROTOCOL = 0x50


class BotError(Exception):
    """A transport or SCSI failure."""


def _errno_name(exc: OSError) -> str:
    return errno.errorcode.get(exc.errno or 0, "EIO")


def _ioctl(fd: int, request: int, arg: Any) -> int:
    try:
        return int(fcntl.ioctl(fd, request, arg))
    except OSError as exc:
        raise BotError("%s (%s)" % (exc.strerror, _errno_name(exc))) from exc


def control_transfer(fd: int, request_type: int, request: int, value: int,
                     index: int, length: int, timeout: int = 3000) -> bytes:
    buf = ctypes.create_string_buffer(max(int(length), 1))
    transfer = CtrlTransfer(
        request_type & 0xFF, request & 0xFF, value & 0xFFFF, index & 0xFFFF,
        length & 0xFFFF, timeout & 0xFFFFFFFF, ctypes.cast(buf, ctypes.c_void_p),
    )
    _ioctl(fd, USBDEVFS_CONTROL, transfer)
    return bytes(buf.raw)[:length]


def get_descriptor(fd: int, dtype: int, index: int = 0, length: int = 255,
                   langid: int = 0) -> bytes:
    return control_transfer(fd, 0x80, GET_DESCRIPTOR,
                            (dtype << 8) | (index & 0xFF), langid, length)


# usbfs refuses a single USBDEVFS_BULK request larger than this, so a data
# phase is split into slices; USB bulk is a stream, the device cannot tell.
MAX_BULK = 16384


def bulk_out(fd: int, ep: int, data: bytes, timeout: int = 15000) -> int:
    """Host -> device; returns the number of bytes the device accepted."""
    total = 0
    for offset in range(0, len(data), MAX_BULK):
        piece = data[offset:offset + MAX_BULK]
        buf = (ctypes.c_ubyte * len(piece)).from_buffer_copy(piece)
        transfer = BulkTransfer(ep, len(piece), timeout,
                                ctypes.cast(buf, ctypes.c_void_p))
        done = _ioctl(fd, USBDEVFS_BULK, transfer)
        total += done
        if done != len(piece):
            break
    return total


def bulk_in(fd: int, ep: int, length: int, timeout: int = 15000) -> bytes:
    """Device -> host; returns at most ``length`` bytes (short is legal)."""
    out = bytearray()
    while len(out) < length:
        want = min(MAX_BULK, length - len(out))
        buf = (ctypes.c_ubyte * max(want, 1))()
        transfer = BulkTransfer(ep, want, timeout,
                                ctypes.cast(buf, ctypes.c_void_p))
        done = _ioctl(fd, USBDEVFS_BULK, transfer)
        if done <= 0:
            break
        out += bytes(bytearray(buf))[:done]
        if done < want:
            break
    return bytes(out)


def clear_halt(fd: int, ep: int) -> None:
    try:
        fcntl.ioctl(fd, USBDEVFS_CLEAR_HALT, struct.pack("I", ep))
    except OSError:
        pass


def parse_config(data: bytes) -> Dict[str, Any]:
    if len(data) < 9 or data[0] < 9 or data[1] != DT_CONFIG:
        raise BotError("invalid configuration descriptor")
    total = struct.unpack_from("<H", data, 2)[0]
    end = min(len(data), total)
    interfaces: List[Dict[str, Any]] = []
    current: Optional[Dict[str, Any]] = None
    off = 0
    while off + 2 <= end:
        length = data[off]
        dtype = data[off + 1]
        if length < 2 or off + length > end:
            break
        chunk = data[off:off + length]
        if dtype == DT_INTERFACE and len(chunk) >= 9:
            current = {
                "number": chunk[2], "alternate": chunk[3],
                "class": chunk[5], "subclass": chunk[6], "protocol": chunk[7],
                "endpoints": [],
            }
            interfaces.append(current)
        elif dtype == DT_ENDPOINT and len(chunk) >= 7 and current is not None:
            current["endpoints"].append({
                "address": chunk[2],
                "type": chunk[3] & 0x03,
                "max_packet": struct.unpack_from("<H", chunk, 4)[0],
            })
        off += length
    return {"interfaces": interfaces}


def find_bot_interface(config: Dict[str, Any]) -> Tuple[int, int, int, int]:
    """Return (interface, alt, ep_in, ep_out) for mass storage bulk-only."""
    fallback = None
    for intf in config["interfaces"]:
        bulk = [e for e in intf["endpoints"] if e["type"] == 0x02]
        ep_in = next((e["address"] for e in bulk if e["address"] & 0x80), None)
        ep_out = next((e["address"] for e in bulk if not e["address"] & 0x80), None)
        if ep_in is None or ep_out is None:
            continue
        if intf["class"] == MASS_STORAGE_CLASS and intf["protocol"] == BOT_PROTOCOL:
            return intf["number"], intf["alternate"], ep_in, ep_out
        if fallback is None:
            fallback = (intf["number"], intf["alternate"], ep_in, ep_out)
    if fallback is None:
        raise BotError("no interface with two bulk endpoints (not mass storage?)")
    return fallback


def claim_interface(fd: int, interface: int, verbose: bool = True) -> str:
    """Claim, detaching Android's kernel driver if it holds the interface."""
    try:
        fcntl.ioctl(fd, USBDEVFS_CLAIMINTERFACE, struct.pack("I", interface))
        return "free"
    except OSError as exc:
        first = _errno_name(exc)
    # flags 0 / IF_DRIVER("usb-storage") / EXCEPT_DRIVER(""):
    # the kernel's exact semantics vary, so try each and keep the one that works.
    attempts = [(0, b""), (1, b"usb-storage"), (2, b"")]
    errors = []
    for flags, driver in attempts:
        dc = DisconnectClaim(interface, flags, driver)
        try:
            fcntl.ioctl(fd, USBDEVFS_DISCONNECT_CLAIM, dc)
            if verbose:
                print("[*] detached the kernel driver and claimed interface %d"
                      % interface)
            return "detached"
        except OSError as exc:
            errors.append("flags=%d:%s" % (flags, _errno_name(exc)))
    raise BotError("cannot claim interface %d (claim: %s; disconnect: %s)"
                   % (interface, first, ", ".join(errors)))


# --------------------------------------------------------------------------
# Bulk-Only Transport
# --------------------------------------------------------------------------

CBW_SIGNATURE = 0x43425355
CSW_SIGNATURE = 0x53425355


def build_cbw(tag: int, transfer_length: int, direction_in: bool, lun: int,
              cdb: bytes) -> bytes:
    if len(cdb) > 16:
        raise BotError("CDB is longer than 16 bytes")
    cb = bytes(cdb) + b"\x00" * (16 - len(cdb))
    return struct.pack("<IIIBBB16s", CBW_SIGNATURE, tag, transfer_length,
                       0x80 if direction_in else 0x00, lun & 0x0F,
                       len(cdb) & 0x1F, cb)


def parse_csw(raw: bytes, tag: int) -> Tuple[int, int]:
    if len(raw) != 13:
        raise BotError("short CSW (%d bytes)" % len(raw))
    signature, got_tag, residue, status = struct.unpack("<IIIB", raw)
    if signature != CSW_SIGNATURE:
        raise BotError("bad CSW signature 0x%08x" % signature)
    if got_tag != (tag & 0xFFFFFFFF):
        raise BotError("CSW tag mismatch (%d != %d)" % (got_tag, tag))
    return residue, status


class Bot:
    def __init__(self, fd: int, interface: int, ep_in: int, ep_out: int,
                 lun: int = 0):
        self.fd = fd
        self.interface = interface
        self.ep_in = ep_in
        self.ep_out = ep_out
        self.lun = lun
        self.tag = int(time.time()) & 0x7FFFFFFF

    def _next_tag(self) -> int:
        self.tag = (self.tag + 1) & 0xFFFFFFFF
        return self.tag

    def reset_recovery(self) -> None:
        try:
            control_transfer(self.fd, 0x21, 0xFF, 0, self.interface, 0, timeout=3000)
        except BotError:
            pass
        clear_halt(self.fd, self.ep_in)
        clear_halt(self.fd, self.ep_out)

    def command(self, cdb: bytes, length: int = 0, direction_in: bool = False,
                data: Optional[bytes] = None, retries: int = 1) -> Tuple[bytes, int]:
        """Run one SCSI command; return (payload_in, data_residue)."""
        attempt = 0
        while True:
            attempt += 1
            tag = self._next_tag()
            cbw = build_cbw(tag, length, direction_in, self.lun, cdb)
            try:
                sent = bulk_out(self.fd, self.ep_out, cbw)
                if sent != len(cbw):
                    raise BotError("short CBW write (%d of %d)" % (sent, len(cbw)))
                payload = b""
                if direction_in and length:
                    payload = bulk_in(self.fd, self.ep_in, length)
                elif (not direction_in) and length and data is not None:
                    sent = bulk_out(self.fd, self.ep_out, data)
                    if sent != length:
                        raise BotError("short data write (%d of %d)" % (sent, length))
                csw = bulk_in(self.fd, self.ep_in, 13)
            except BotError:
                if attempt > retries:
                    raise
                self.reset_recovery()
                continue
            residue, status = parse_csw(csw, tag)
            if status == 0:
                return payload, residue
            if status == 2:
                self.reset_recovery()
                if attempt <= retries:
                    continue
                raise BotError("phase error after reset recovery")
            # status 1: command failed; caller decides whether to ask for sense
            raise BotError("command failed (CSW status 1, residue %d)" % residue)

    # --- SCSI commands ---------------------------------------------------
    def inquiry(self, length: int = 36) -> Dict[str, Any]:
        payload, _ = self.command(b"\x12\x00\x00\x00" + bytes([length]) + b"\x00",
                                  length, True)
        if len(payload) < 36:
            raise BotError("short INQUIRY response")
        return {
            "peripheral": payload[0] & 0x1F,
            "vendor": payload[8:16].decode("ascii", "replace").strip(),
            "product": payload[16:32].decode("ascii", "replace").strip(),
            "revision": payload[32:36].decode("ascii", "replace").strip(),
        }

    def test_unit_ready(self) -> None:
        self.command(b"\x00" * 6, 0, False)

    def wait_ready(self, tries: int = 8) -> None:
        last: Optional[BotError] = None
        for _ in range(tries):
            try:
                self.test_unit_ready()
                return
            except BotError as exc:
                last = exc
                time.sleep(0.25)
        raise BotError("device never became ready: %s" % last)

    def capacity(self) -> Dict[str, int]:
        payload, _ = self.command(b"\x25" + b"\x00" * 9, 8, True)
        if len(payload) != 8:
            raise BotError("short READ CAPACITY response")
        last_lba, block = struct.unpack(">II", payload)
        return {"last_lba": last_lba, "blocks": last_lba + 1, "block_size": block}

    def read10(self, lba: int, blocks: int, block_size: int) -> bytes:
        cdb = struct.pack(">BBIBHB", 0x28, 0, lba, 0, blocks, 0)
        payload, residue = self.command(cdb, blocks * block_size, True)
        if len(payload) != blocks * block_size:
            raise BotError("short READ(10) payload (%d of %d)"
                           % (len(payload), blocks * block_size))
        if residue:
            raise BotError("READ(10) residue %d" % residue)
        return payload

    def write10(self, lba: int, data: bytes, block_size: int) -> None:
        blocks = len(data) // block_size
        cdb = struct.pack(">BBIBHB", 0x2A, 0, lba, 0, blocks, 0)
        _, residue = self.command(cdb, blocks * block_size, False, data)
        if residue:
            raise BotError("WRITE(10) residue %d" % residue)

    def sync_cache(self) -> None:
        self.command(b"\x35" + b"\x00" * 9, 0, False)


# --------------------------------------------------------------------------
# Device open / probe / write
# --------------------------------------------------------------------------

def human(n: int) -> str:
    value = float(n)
    for unit in ("B", "K", "M", "G", "T"):
        if value < 1024 or unit == "T":
            return "%.1f%s" % (value, unit) if unit != "B" else "%d%s" % (n, unit)
        value /= 1024.0
    return "%d" % n


def open_bot(fd: int, verbose: bool = True) -> Tuple[Bot, Dict[str, Any]]:
    device = get_descriptor(fd, DT_DEVICE, 0, 18)
    if len(device) < 18 or device[1] != DT_DEVICE:
        raise BotError("cannot read the device descriptor")
    vid = struct.unpack_from("<H", device, 8)[0]
    pid = struct.unpack_from("<H", device, 10)[0]
    config_head = get_descriptor(fd, DT_CONFIG, 0, 9)
    total = struct.unpack_from("<H", config_head, 2)[0]
    config = parse_config(get_descriptor(fd, DT_CONFIG, 0, total))
    interface, alt, ep_in, ep_out = find_bot_interface(config)
    if verbose:
        print("[*] %04x:%04x interface %d alt %d, bulk in 0x%02x out 0x%02x"
              % (vid, pid, interface, alt, ep_in, ep_out))
    mode = claim_interface(fd, interface, verbose)
    # Some readers need the alternate setting selected; most only have alt 0.
    if alt:
        try:
            control_transfer(fd, 0x01, 0x0B, alt, interface, 0)
        except BotError:
            pass
    bot = Bot(fd, interface, ep_in, ep_out)
    # usb-storage may have been interrupted mid-command while we detached it.
    bot.reset_recovery()
    try:
        luns = control_transfer(fd, 0xA1, 0xFE, 0, interface, 1)
        if luns:
            bot.lun = 0  # only LUN 0 is supported by this tool
    except BotError:
        clear_halt(fd, 0)
    return bot, {"vid": "%04x" % vid, "pid": "%04x" % pid, "claim": mode,
                 "interface": interface, "ep_in": ep_in, "ep_out": ep_out}


def parse_mbr(sector: bytes) -> Dict[str, Any]:
    if len(sector) < 512:
        return {"signature": None, "partitions": []}
    result: Dict[str, Any] = {
        "signature": "0x%04x" % struct.unpack_from("<H", sector, 510)[0],
        "partitions": [],
    }
    for index in range(4):
        base = 446 + index * 16
        status, ptype = sector[base], sector[base + 4]
        start, count = struct.unpack_from("<II", sector, base + 8)
        if ptype == 0 or count == 0:
            continue
        result["partitions"].append({
            "index": index + 1,
            "bootable": status == 0x80,
            "type": "0x%02x" % ptype,
            "start_lba": start,
            "sectors": count,
            "bytes": count * 512,
        })
    if result["partitions"] and result["partitions"][0]["type"] == "0xee":
        result["table"] = "gpt"
    else:
        result["table"] = "mbr"
    return result


def probe(fd: int, as_json: bool) -> int:
    bot, info = open_bot(fd)
    try:
        bot.wait_ready()
        inquiry = bot.inquiry()
        cap = bot.capacity()
        sector = bot.read10(0, 1, cap["block_size"] or 512)
        mbr = parse_mbr(sector)
        result = dict(info)
        result.update({"inquiry": inquiry, "capacity": cap, "mbr": mbr})
        if as_json:
            print(json.dumps(result))
            return 0
        print("Device:   %s %s (rev %s)" % (inquiry["vendor"], inquiry["product"],
                                            inquiry["revision"]))
        print("Capacity: %s in %d blocks of %d bytes"
              % (human(cap["blocks"] * cap["block_size"]), cap["blocks"],
                 cap["block_size"]))
        print("Sector 0: %s table, signature %s"
              % (mbr["table"].upper(), mbr["signature"]))
        if not mbr["partitions"]:
            print("          no partitions (blank or not yet flashed)")
        for part in mbr["partitions"]:
            print("          #%d type %s start %d (%s) size %s%s"
                  % (part["index"], part["type"], part["start_lba"],
                     human(part["start_lba"] * 512), human(part["bytes"]),
                     " bootable" if part["bootable"] else ""))
        print("RAW WRITE: possible without root through this transport")
        print("           lfa usb bot --write IMAGE --yes")
    finally:
        try:
            fcntl.ioctl(fd, USBDEVFS_RELEASEINTERFACE, struct.pack("I", bot.interface))
        except OSError:
            pass
    print("[*] Android usually remounts the card on its own; replug the"
          " reader if it does not")
    return 0


def write_image(fd: int, path: str, verify: bool) -> int:
    size = os.path.getsize(path)
    if size == 0:
        print("[!] image is empty", file=sys.stderr)
        return 2
    bot, info = open_bot(fd)
    try:
        bot.wait_ready()
        inquiry = bot.inquiry()
        cap = bot.capacity()
        block = cap["block_size"] or 512
        if block not in (512, 1024, 2048, 4096):
            print("[!] unsupported logical block size %d" % block, file=sys.stderr)
            return 2
        if size > cap["blocks"] * block:
            print("[!] image is larger than the card (%s > %s)"
                  % (human(size), human(cap["blocks"] * block)), file=sys.stderr)
            return 2
        print("[*] %s %s: writing %s in %d-byte blocks"
              % (inquiry["vendor"], inquiry["product"], human(size), block))
        chunk_blocks = max(1, (1024 * 1024) // block)
        written = 0
        with open(path, "rb") as handle:
            lba = 0
            while True:
                data = handle.read(chunk_blocks * block)
                if not data:
                    break
                if len(data) % block:
                    data += b"\x00" * (block - len(data) % block)
                bot.write10(lba, data, block)
                written += len(data)
                lba += len(data) // block
                pct = min(100, int(written * 100 / max(size, 1)))
                sys.stderr.write("\r[*] %3d%% %s" % (pct, human(written)))
                sys.stderr.flush()
        sys.stderr.write("\n")
        bot.sync_cache()
        print("[+] wrote %s" % human(written))
        if verify:
            print("[*] reading the card back")
            digest = hashlib.sha256()
            remaining = size
            with open(path, "rb") as handle:
                lba = 0
                while remaining > 0:
                    want = min(chunk_blocks * block, remaining)
                    blocks = (want + block - 1) // block
                    back = bot.read10(lba, blocks, block)[:want]
                    expect = handle.read(want)
                    if back != expect:
                        print("[!] verification failed at byte %d"
                              % (size - remaining), file=sys.stderr)
                        return 4
                    digest.update(back)
                    remaining -= want
                    lba += blocks
            with open(path, "rb") as handle:
                want = hashlib.sha256(handle.read()).hexdigest()
            if digest.hexdigest() != want:
                print("[!] verification failed: checksum mismatch", file=sys.stderr)
                return 4
            print("[+] verified: card matches the image")
    finally:
        try:
            fcntl.ioctl(fd, USBDEVFS_RELEASEINTERFACE, struct.pack("I", bot.interface))
        except OSError:
            pass
    print("[*] Android usually remounts the card on its own; replug the"
          " reader if it does not")
    return 0


# --------------------------------------------------------------------------
# Card <-> image file, for tools that only accept files
# --------------------------------------------------------------------------

CHUNK = 1024 * 1024


def _chunk_geometry(block: int) -> Tuple[int, int]:
    blocks = max(1, CHUNK // block)
    return blocks, blocks * block


def _progress(done: int, total: int, label: str) -> None:
    pct = min(100, int(done * 100 / max(total, 1)))
    sys.stderr.write("\r[%s] %3d%% %s of %s" % (label, pct, human(done), human(total)))
    sys.stderr.flush()


def export_image(fd: int, path: str) -> int:
    """Read the card into a sparse file: holes for all-zero chunks."""
    bot, info = open_bot(fd)
    try:
        bot.wait_ready()
        cap = bot.capacity()
        block = cap["block_size"] or 512
        blocks_per_chunk, chunk_size = _chunk_geometry(block)
        total = cap["blocks"] * block
        holes = 0
        written = 0
        lba = 0
        with open(path, "wb") as out:
            out.truncate(total)
            while lba < cap["blocks"]:
                blocks = min(blocks_per_chunk, cap["blocks"] - lba)
                data = bot.read10(lba, blocks, block)
                if data.count(0) == len(data):
                    holes += len(data)          # leave a hole in the file
                else:
                    out.seek(lba * block)
                    out.write(data)
                    written += len(data)
                lba += blocks
                _progress(lba * block, total, "export")
            out.flush()
            os.fsync(out.fileno())
        sys.stderr.write("\n")
        print("[+] %s: %s (%s data, %s holes)"
              % (path, human(total), human(written), human(holes)))
        print("[*] work on it with fdisk/sfdisk/mkfs/dd, then: lfa usb bot"
              " --import %s" % os.path.basename(path))
    finally:
        try:
            fcntl.ioctl(fd, USBDEVFS_RELEASEINTERFACE, struct.pack("I", bot.interface))
        except OSError:
            pass
    print("[*] Android usually remounts the card on its own; replug the"
          " reader if it does not")
    return 0


def import_image(fd: int, path: str, full: bool) -> int:
    """Write a card image back, rewriting only the chunks that differ."""
    size = os.path.getsize(path)
    bot, info = open_bot(fd)
    try:
        bot.wait_ready()
        cap = bot.capacity()
        block = cap["block_size"] or 512
        blocks_per_chunk, chunk_size = _chunk_geometry(block)
        total = cap["blocks"] * block
        if size > total:
            print("[!] image is larger than the card (%s > %s)"
                  % (human(size), human(total)), file=sys.stderr)
            return 2
        changed: List[Tuple[int, int]] = []
        changed_bytes = 0
        offset = 0
        with open(path, "rb") as src:
            while offset < size:
                want = min(chunk_size, size - offset)
                blocks = (want + block - 1) // block
                expect = src.read(want)
                if len(expect) < blocks * block:
                    expect += b"\x00" * (blocks * block - len(expect))
                current = bot.read10(offset // block, blocks, block)
                if full or current != expect:
                    bot.write10(offset // block, expect, block)
                    changed.append((offset, len(expect)))
                    changed_bytes += len(expect)
                offset += want
                _progress(offset, size, "import")
        sys.stderr.write("\n")
        bot.sync_cache()
        print("[+] wrote %s in %d chunk(s)" % (human(changed_bytes), len(changed)))
        if not changed:
            print("[*] card already matched the image; nothing to verify")
            print("[*] Android usually remounts the card on its own; replug the"
          " reader if it does not")
            return 0
        print("[*] verifying the chunks that changed")
        with open(path, "rb") as src:
            for offset, length in changed:
                src.seek(offset)
                expect = src.read(length)
                if len(expect) < length:
                    expect += b"\x00" * (length - len(expect))
                back = bot.read10(offset // block, length // block, block)
                if back != expect:
                    print("[!] verification failed at byte %d" % offset,
                          file=sys.stderr)
                    return 4
        print("[+] verified %d chunk(s)" % len(changed))
    finally:
        try:
            fcntl.ioctl(fd, USBDEVFS_RELEASEINTERFACE, struct.pack("I", bot.interface))
        except OSError:
            pass
    print("[*] Android usually remounts the card on its own; replug the"
          " reader if it does not")
    return 0


# --------------------------------------------------------------------------
# Self test (no device, runs in CI)
# --------------------------------------------------------------------------

def selftest() -> int:
    read10_cdb = b"\x28\x00\x00\x00\x00\x00\x00\x10\x00\x00"
    cbw = build_cbw(0x11223344, 512, True, 0, read10_cdb)
    assert len(cbw) == 31, len(cbw)
    assert struct.unpack_from("<I", cbw, 0)[0] == CBW_SIGNATURE
    assert struct.unpack_from("<I", cbw, 4)[0] == 0x11223344
    assert struct.unpack_from("<I", cbw, 8)[0] == 512
    assert cbw[12] == 0x80 and cbw[13] == 0 and cbw[14] == 10
    assert cbw[15:25] == read10_cdb
    assert cbw[0:4] == b"USBC"

    csw = struct.pack("<IIIB", CSW_SIGNATURE, 0x11223344, 0, 0)
    assert parse_csw(csw, 0x11223344) == (0, 0)
    try:
        parse_csw(csw, 0x11223345)
        return 1
    except BotError:
        pass

    # A configuration holding one mass-storage interface with two bulk endpoints.
    config = bytes([
        9, DT_CONFIG, 32, 0, 1, 1, 0, 0x80, 50,
        9, DT_INTERFACE, 0, 0, 2, 0x08, 0x06, 0x50, 0,
        7, DT_ENDPOINT, 0x81, 0x02, 0x00, 0x02, 0,
        7, DT_ENDPOINT, 0x02, 0x02, 0x00, 0x02, 0,
    ])
    parsed = parse_config(config)
    interface, alt, ep_in, ep_out = find_bot_interface(parsed)
    assert (interface, alt, ep_in, ep_out) == (0, 0, 0x81, 0x02)

    sector = bytearray(512)
    sector[446 + 4] = 0x07
    struct.pack_into("<II", sector, 446 + 8, 2048, 1000)
    struct.pack_into("<H", sector, 510, 0xAA55)
    mbr = parse_mbr(bytes(sector))
    assert mbr["signature"] == "0xaa55" and mbr["table"] == "mbr"
    assert mbr["partitions"][0]["start_lba"] == 2048

    assert human(1024) == "1.0K" and human(1536) == "1.5K"

    # The ioctl encodings must match <linux/usbdevice_fs.h>; a wrong
    # direction bit is indistinguishable from "unsupported" at runtime.
    assert USBDEVFS_CONTROL == 0xC0185500
    assert USBDEVFS_BULK == 0xC0185502
    assert USBDEVFS_CLAIMINTERFACE == 0x8004550F
    assert USBDEVFS_RELEASEINTERFACE == 0x80045510
    assert USBDEVFS_CLEAR_HALT == 0x80045515
    assert USBDEVFS_DISCONNECT_CLAIM == 0x8108551B
    print("selftest: ok")
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="USB mass storage over Bulk-Only Transport, no block node")
    parser.add_argument("--fd", default=os.environ.get("TERMUX_USB_FD", ""),
                        help="usbdevfs descriptor (default: $TERMUX_USB_FD)")
    parser.add_argument("--probe", action="store_true",
                        help="INQUIRY, capacity and sector 0 (read-only)")
    parser.add_argument("--write", metavar="IMAGE",
                        help="write IMAGE to the card (erases it)")
    parser.add_argument("--no-verify", action="store_true",
                        help="skip reading the image back after --write")
    parser.add_argument("--export", metavar="FILE",
                        help="write the whole card to a sparse file (read-only)")
    parser.add_argument("--import", dest="import_file", metavar="FILE",
                        help="write FILE back, touching only changed chunks")
    parser.add_argument("--full", action="store_true",
                        help="with --import: write every chunk, not only the"
                             " ones that differ")
    parser.add_argument("--yes", action="store_true",
                        help="confirm that the card will be erased")
    parser.add_argument("--json", action="store_true", help="machine output")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()
    actions = [bool(args.probe), bool(args.write), bool(args.export),
               bool(args.import_file)]
    if sum(actions) != 1:
        parser.print_help()
        return 2
    if args.full and not args.import_file:
        print("[!] --full only applies to --import", file=sys.stderr)
        return 2
    if not args.fd:
        print("[!] no USB descriptor: TERMUX_USB_FD is empty", file=sys.stderr)
        return 2
    try:
        fd = int(args.fd)
    except ValueError:
        print("[!] TERMUX_USB_FD is not a number: %r" % args.fd, file=sys.stderr)
        return 2
    try:
        if args.write:
            if not args.yes:
                print("[!] --write erases the card. Add --yes when you mean it.",
                      file=sys.stderr)
                return 2
            return write_image(fd, args.write, not args.no_verify)
        if args.export:
            return export_image(fd, args.export)
        if args.import_file:
            if not args.yes:
                print("[!] --import overwrites the card. Add --yes when you mean it.",
                      file=sys.stderr)
                return 2
            return import_image(fd, args.import_file, args.full)
        return probe(fd, args.json)
    except BotError as exc:
        print("[!] %s" % exc, file=sys.stderr)
        if "ENOTTY" in str(exc):
            print("    ENOTTY means the kernel does not know that ioctl at all;"
                  " this is an LFA bug, not a permission problem.", file=sys.stderr)
        print("    Android may refuse the driver detach on this device.", file=sys.stderr)
        print("    If it does, the card's files are still available via"
              " 'lfa usb storage'.", file=sys.stderr)
        return 5
    except Exception as exc:                      # noqa: BLE001 - CLI boundary
        print("[!] unexpected failure: %s: %s" % (type(exc).__name__, exc),
              file=sys.stderr)
        print("    Run with --probe again; if it repeats, please report it.",
              file=sys.stderr)
        return 5


if __name__ == "__main__":
    sys.exit(main())
