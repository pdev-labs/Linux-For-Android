#!/usr/bin/env python3
"""Read USB descriptors from a file descriptor inherited from Termux:API.

Termux:API's ``termux-usb -E -e COMMAND`` runs COMMAND with the real usbdevfs
file descriptor in ``TERMUX_USB_FD``.  LFA forwards that descriptor into the
guest through proot, so this script can talk to the device with plain
``USBDEVFS_CONTROL`` ioctls.  It needs neither libusb nor udev, and it never
creates a device node.

The result is written as JSON and as one tab-separated row consumable by the
``lsusb`` shim.  All values are strings so the shell side stays simple.

Usage:
    python3 usb-desc.py [--fd N] [--path /dev/bus/usb/001/002]
                        [--bus 001] [--dev 002] [--out FILE] [--tsv FILE]
                        [--blob descriptors.bin] [--sysfs DIR] [--speed N]
    python3 usb-desc.py --selftest

With --sysfs the script writes a real sysfs-shaped device directory
(busnum, devnum, descriptors, uevent, strings) for `lfa usb attach`, so
unmodified libusb tools can enumerate the device inside the guest.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import fcntl
import json
import os
import struct
import sys
from typing import Any, Dict, List, Optional

GET_DESCRIPTOR = 0x06
DESCRIPTOR_DEVICE = 0x01
DESCRIPTOR_CONFIG = 0x02
DESCRIPTOR_STRING = 0x03
DT_DEVICE = 1
DT_CONFIG = 2
DT_STRING = 3
DT_INTERFACE = 4
DT_ENDPOINT = 5


class UsbError(Exception):
    """A descriptor request failed."""


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


def _ioc(direction: int, kind: int, nr: int, size: int) -> int:
    # Linux _IOC layout used by arm, aarch64 and x86 (14-bit size field).
    return (direction << 30) | (size << 16) | (kind << 8) | nr


USBDEVFS_CONTROL = _ioc(3, ord("U"), 0, ctypes.sizeof(CtrlTransfer))


def _u16(data: bytes, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0]


def _hex8(value: int) -> str:
    return "%02x" % (value & 0xFF)


def _bcd(value: int) -> str:
    return "%x.%02x" % (value >> 8, value & 0xFF)


def control_transfer(fd: int, request_type: int, request: int, value: int,
                     index: int, length: int, timeout: int = 2000) -> bytes:
    """Issue one USBDEVFS_CONTROL ioctl and return the payload bytes."""
    buf = ctypes.create_string_buffer(max(int(length), 1))
    transfer = CtrlTransfer(
        request_type & 0xFF,
        request & 0xFF,
        value & 0xFFFF,
        index & 0xFFFF,
        length & 0xFFFF,
        timeout & 0xFFFFFFFF,
        ctypes.cast(buf, ctypes.c_void_p),
    )
    try:
        fcntl.ioctl(fd, USBDEVFS_CONTROL, transfer)
    except OSError as exc:
        name = errno.errorcode.get(exc.errno or 0, "EIO")
        raise UsbError("USBDEVFS_CONTROL failed: %s (%s)" % (exc.strerror, name)) from exc
    raw = bytes(buf.raw)
    return raw[:length]


def get_descriptor(fd: int, dtype: int, index: int = 0, length: int = 255,
                   langid: int = 0) -> bytes:
    return control_transfer(fd, 0x80, GET_DESCRIPTOR,
                            (dtype << 8) | (index & 0xFF), langid, length)


def parse_device_descriptor(data: bytes) -> Dict[str, Any]:
    if len(data) < 18 or data[0] < 18 or data[1] != DT_DEVICE:
        raise UsbError("short or invalid device descriptor")
    return {
        "bcdUSB": _u16(data, 2),
        "usb_version": _bcd(_u16(data, 2)),
        "class": _hex8(data[4]),
        "subclass": _hex8(data[5]),
        "protocol": _hex8(data[6]),
        "max_packet_size": data[7],
        "vid": "%04x" % _u16(data, 8),
        "pid": "%04x" % _u16(data, 10),
        "bcdDevice": _bcd(_u16(data, 12)),
        "iManufacturer": data[14],
        "iProduct": data[15],
        "iSerialNumber": data[16],
        "num_configurations": data[17],
    }


def parse_config_descriptor(data: bytes) -> Dict[str, Any]:
    if len(data) < 9 or data[0] < 9 or data[1] != DT_CONFIG:
        raise UsbError("short or invalid configuration descriptor")
    config = {
        "value": data[5],
        "iConfiguration": data[6],
        "attributes": data[7],
        "self_powered": bool(data[7] & 0x40),
        "remote_wakeup": bool(data[7] & 0x20),
        "max_power_ma": data[8] * 2,
        "interfaces": [],
    }
    current: Optional[Dict[str, Any]] = None
    offset = 0
    end = min(len(data), _u16(data, 2))
    while offset + 2 <= end:
        length = data[offset]
        dtype = data[offset + 1]
        if length < 2 or offset + length > end:
            break
        chunk = data[offset:offset + length]
        if dtype == DT_INTERFACE and len(chunk) >= 9:
            current = {
                "number": chunk[2],
                "alternate": chunk[3],
                "class": _hex8(chunk[5]),
                "subclass": _hex8(chunk[6]),
                "protocol": _hex8(chunk[7]),
                "iInterface": chunk[8],
                "endpoints": [],
            }
            config["interfaces"].append(current)
        elif dtype == DT_ENDPOINT and len(chunk) >= 7 and current is not None:
            current["endpoints"].append({
                "address": "0x%02x" % chunk[2],
                "attributes": "0x%02x" % chunk[3],
                "max_packet_size": _u16(chunk, 4),
                "interval": chunk[6],
            })
        offset += length
    return config


def read_string(fd: int, index: int, langid: int) -> str:
    if index == 0:
        return ""
    data = get_descriptor(fd, DESCRIPTOR_STRING, index, 255, langid)
    if len(data) < 2 or data[0] < 2 or data[1] != DT_STRING:
        return ""
    payload = data[2:min(data[0], len(data))]
    return payload.decode("utf-16-le", "replace").rstrip("\x00")


def read_langid(fd: int) -> int:
    try:
        data = get_descriptor(fd, DESCRIPTOR_STRING, 0, 255, 0)
    except UsbError:
        return 0x0409
    if len(data) >= 4 and data[1] == DT_STRING:
        return _u16(data, 2)
    return 0x0409


def read_device(fd: int, path: str = "", bus: str = "", dev: str = "") -> Dict[str, Any]:
    device = parse_device_descriptor(get_descriptor(fd, DESCRIPTOR_DEVICE, 0, 18))
    langid = read_langid(fd)
    result: Dict[str, Any] = {
        "source": "termux-api",
        "path": path,
        "bus": bus,
        "dev": dev,
        "vid": device["vid"],
        "pid": device["pid"],
        "usb_version": device["usb_version"],
        "class": device["class"],
        "subclass": device["subclass"],
        "protocol": device["protocol"],
        "bcdDevice": device["bcdDevice"],
        "max_packet_size": device["max_packet_size"],
        "num_configurations": device["num_configurations"],
        "manufacturer": "",
        "product": "",
        "serial": "",
        "language_id": "0x%04x" % langid,
        "configurations": [],
        "errors": [],
    }
    for key, index in (("manufacturer", device["iManufacturer"]),
                       ("product", device["iProduct"]),
                       ("serial", device["iSerialNumber"])):
        try:
            result[key] = read_string(fd, index, langid)
        except UsbError as exc:
            result["errors"].append("%s: %s" % (key, exc))
    raw_device = get_descriptor(fd, DESCRIPTOR_DEVICE, 0, 18)
    result["_raw_device"] = raw_device.hex()
    result["_raw_configs"] = []
    for index in range(min(int(device["num_configurations"]), 8)):
        try:
            head = get_descriptor(fd, DESCRIPTOR_CONFIG, index, 9)
            total = _u16(head, 2) if len(head) >= 4 else 9
            total = min(max(total, 9), 16384)
            config_data = get_descriptor(fd, DESCRIPTOR_CONFIG, index, total)
            result["configurations"].append(parse_config_descriptor(config_data))
            result["_raw_configs"].append(config_data.hex())
        except UsbError as exc:
            result["errors"].append("configuration %d: %s" % (index, exc))
    if device["class"] == "09":
        # Hub class descriptor: only bNbrPorts is interesting, and the
        # kernel may refuse the request while its hub driver owns the
        # device, so a failure here is not fatal.
        try:
            hub = control_transfer(fd, 0xA0, 6, 0x2900, 0, 9)
            if len(hub) >= 3:
                result["num_ports"] = hub[2]
        except UsbError:
            pass
    return result


def descriptors_blob(result: Dict[str, Any]) -> bytes:
    """Return the sysfs `descriptors` blob: device + all configs, raw."""
    blob = bytes.fromhex(result.get("_raw_device", ""))
    for raw in result.get("_raw_configs", []):
        blob += bytes.fromhex(raw)
    return blob


def _sysfs_value(value: Any) -> str:
    return str(value).replace("\n", " ").replace("\r", " ").strip()


def _device_sysname(bus: str, dev: str) -> str:
    try:
        return "%d-%d" % (int(bus, 10), int(dev, 10))
    except (TypeError, ValueError):
        return "%s-%s" % (bus, dev)


_ENDPOINT_TYPES = {
    0x00: "Control", 0x01: "Isoc", 0x02: "Bulk", 0x03: "Interrupt",
}


def _write_text(directory: str, key: str, value: str) -> None:
    with open(os.path.join(directory, key), "w", encoding="utf-8") as handle:
        handle.write(value + "\n")


def _write_interfaces(directory: str, sysname: str,
                      result: Dict[str, Any]) -> None:
    """Write the interface and endpoint directories libusb walks."""
    vid = str(result.get("vid", "0000")).lower()
    pid = str(result.get("pid", "0000")).lower()
    bcd = str(result.get("bcdDevice", "0.00")).replace(".", "")
    try:
        bcd_value = int(bcd, 16) & 0xFFFF
    except ValueError:
        bcd_value = 0
    for config in result.get("configurations", []):
        for iface in config.get("interfaces", []):
            try:
                number = int(iface.get("number", 0))
                alternate = int(iface.get("alternate", 0))
            except (TypeError, ValueError):
                continue
            iclass = str(iface.get("class", "00")).lower()
            isub = str(iface.get("subclass", "00")).lower()
            iproto = str(iface.get("protocol", "00")).lower()
            idir = os.path.join(directory, "%s:%d.%d" %
                                 (sysname, number, alternate))
            os.makedirs(idir, exist_ok=True)
            endpoints = iface.get("endpoints", [])
            _write_text(idir, "bInterfaceNumber", "%02x" % number)
            _write_text(idir, "bAlternateSetting", "%d" % alternate)
            _write_text(idir, "bInterfaceClass", iclass)
            _write_text(idir, "bInterfaceSubClass", isub)
            _write_text(idir, "bInterfaceProtocol", iproto)
            _write_text(idir, "bNumEndpoints", "%d" % len(endpoints))
            _write_text(idir, "uevent", "\n".join([
                "DEVTYPE=usb_interface",
                "INTERFACE=%s/%s/%s" % (iclass, isub, iproto),
                "MODALIAS=usb:v%sp%sd%04xdc00dsc00dp00ic%sisc%sip%s" % (
                    vid, pid, bcd_value, iclass, isub, iproto),
            ]))
            for endpoint in endpoints:
                try:
                    address = int(str(endpoint.get("address", "0x00")), 16)
                    attributes = int(str(endpoint.get("attributes", "0x00")), 16)
                    packet = int(endpoint.get("max_packet_size", 0))
                    interval = int(endpoint.get("interval", 0))
                except (TypeError, ValueError):
                    continue
                edir = os.path.join(idir, "ep_%02x" % address)
                os.makedirs(edir, exist_ok=True)
                _write_text(edir, "bEndpointAddress", "%02x" % address)
                _write_text(edir, "bmAttributes", "%02x" % attributes)
                _write_text(edir, "wMaxPacketSize", "%04x" % packet)
                _write_text(edir, "interval", "%d" % interval)
                _write_text(edir, "type",
                            _ENDPOINT_TYPES.get(attributes & 0x03, "Bulk"))
                _write_text(edir, "uevent", "\n".join([
                    "DEVTYPE=usb_endpoint",
                    "TYPE=%d/%d/%d" % (attributes, 0, 0),
                    "INTERFACE=%s/%s/%s" % (iclass, isub, iproto),
                ]))


def write_sysfs(tree: str, result: Dict[str, Any], speed: int = 480) -> str:
    """Write a sysfs-shaped directory and return its path."""
    bus = result.get("bus", "")
    dev = result.get("dev", "")
    name = _device_sysname(bus, dev)
    directory = os.path.join(tree, name)
    os.makedirs(directory, exist_ok=True)

    blob = descriptors_blob(result)
    if not blob:
        raise UsbError("no descriptors were read; cannot build sysfs")

    config_value = 0
    interfaces = 0
    for config in result.get("configurations", []):
        config_value = int(config.get("value", 0))
        interfaces = len(config.get("interfaces", []))
        break

    product = result.get("product", "")
    manufacturer = result.get("manufacturer", "")
    serial = result.get("serial", "")
    bcd = str(result.get("bcdDevice", "0.00")).replace(".", "")
    try:
        bcd_int = int(bcd, 16)
    except ValueError:
        bcd_int = 0

    try:
        max_packet = int(result.get("max_packet_size", 64) or 64)
    except (TypeError, ValueError):
        max_packet = 64
    try:
        config_count = int(result.get("num_configurations", 1) or 1)
    except (TypeError, ValueError):
        config_count = 1
    config_attributes = 0
    for config in result.get("configurations", []):
        config_attributes = int(config.get("attributes", 0) or 0)
        break
    text = {
        "busnum": "%d" % int(bus, 10) if bus.isdigit() else bus,
        "bMaxPacketSize0": "%d" % max_packet,
        "bNumConfigurations": "%d" % config_count,
        "bcdDevice": "%04x" % bcd_int,
        "bmAttributes": "%02x" % config_attributes,
        "configuration": "%d" % config_value,
        "maxchild": "%d" % int(result.get("num_ports", 0) or 0),
        "rx_lanes": "0",
        "tx_lanes": "0",
        "devnum": "%d" % int(dev, 10) if dev.isdigit() else dev,
        "speed": "%d" % speed,
        "devpath": "%d" % (int(dev, 10) if dev.isdigit() else 1),
        "bConfigurationValue": "%d" % config_value,
        "bNumInterfaces": "%d" % interfaces,
        "bDeviceClass": result.get("class", "00"),
        "bDeviceSubClass": result.get("subclass", "00"),
        "bDeviceProtocol": result.get("protocol", "00"),
        "idVendor": result.get("vid", ""),
        "idProduct": result.get("pid", ""),
        "manufacturer": _sysfs_value(manufacturer),
        "product": _sysfs_value(product),
        "serial": _sysfs_value(serial),
        "version": " " + result.get("usb_version", "2.00"),
        "bMaxPower": "500mA",
    }
    for key, value in text.items():
        with open(os.path.join(directory, key), "w", encoding="utf-8") as handle:
            handle.write(value + "\n")

    uevent = (
        "MAJOR=189\n"
        "MINOR=%d\n"
        "DEVNAME=bus/usb/%s/%s\n"
        "DEVTYPE=usb_device\n"
        "DRIVER=usb\n"
        "PRODUCT=%s/%s/%04x\n"
        "TYPE=%s/%s/%s\n"
        "BUSNUM=%s\n"
        "DEVNUM=%s\n"
    ) % (
        (int(dev, 10) if dev.isdigit() else 0),
        bus, dev,
        result.get("vid", "0000"), result.get("pid", "0000"), bcd_int & 0xFFFF,
        result.get("class", "00"), result.get("subclass", "00"),
        result.get("protocol", "00"), bus, dev,
    )
    with open(os.path.join(directory, "uevent"), "w", encoding="utf-8") as handle:
        handle.write(uevent)

    subsystem = os.path.join(directory, "subsystem")
    if os.path.lexists(subsystem):
        os.unlink(subsystem)
    os.symlink("../../../../bus/usb", subsystem)

    with open(os.path.join(directory, "descriptors"), "wb") as handle:
        handle.write(blob)

    _write_interfaces(os.path.dirname(directory), name, result)
    return directory


def _clean(value: Any) -> str:
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ")


def tsv_row(result: Dict[str, Any]) -> str:
    interfaces: List[str] = []
    for config in result.get("configurations", []):
        for iface in config.get("interfaces", []):
            interfaces.append("%d:%s:%s:%s:%d" % (
                iface["number"], iface["class"], iface["subclass"],
                iface["protocol"], len(iface["endpoints"])))
    columns = [
        result.get("bus", ""),
        result.get("dev", ""),
        result.get("path", ""),
        result.get("vid", ""),
        result.get("pid", ""),
        result.get("usb_version", ""),
        result.get("class", ""),
        result.get("subclass", ""),
        result.get("protocol", ""),
        result.get("manufacturer", ""),
        result.get("product", ""),
        result.get("serial", ""),
        ";".join(interfaces),
        "scan",
    ]
    return "\t".join(_clean(column) for column in columns) + "\n"


def write_atomic(path: str, text: str) -> None:
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    temporary = "%s.tmp.%d" % (path, os.getpid())
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(temporary, path)


def selftest() -> int:
    # One device descriptor and a configuration with one HID interface.
    device = bytes.fromhex(
        "12 01 00 02 00 00 00 40 6b 1d 02 00 00 01 01 02 03 01")
    parsed = parse_device_descriptor(device)
    assert parsed["vid"] == "1d6b"
    assert parsed["pid"] == "0002"
    assert parsed["usb_version"] == "2.00"
    assert parsed["num_configurations"] == 1
    config = bytes.fromhex(
        "09 02 22 00 01 01 00 80 32"
        "09 04 00 00 01 03 01 01 00"
        "07 05 81 03 08 00 0a")
    parsed_config = parse_config_descriptor(config)
    assert parsed_config["value"] == 1
    assert parsed_config["max_power_ma"] == 100
    assert len(parsed_config["interfaces"]) == 1
    iface = parsed_config["interfaces"][0]
    assert iface["class"] == "03"
    assert iface["subclass"] == "01"
    assert iface["protocol"] == "01"
    assert len(iface["endpoints"]) == 1
    row = tsv_row({
        "bus": "001", "dev": "002", "path": "/dev/bus/usb/001/002",
        "vid": "1d6b", "pid": "0002", "usb_version": "2.00",
        "class": "09", "subclass": "00", "protocol": "00",
        "manufacturer": "Linux", "product": "Root Hub", "serial": "",
        "configurations": [parsed_config],
    })
    assert row.split("\t")[0:5] == ["001", "002", "/dev/bus/usb/001/002",
                                    "1d6b", "0002"]
    assert "0:03:01:01:1" in row

    # --sysfs writes the blob and attributes libudev needs to enumerate.
    import tempfile
    result = {
        "bus": "001", "dev": "002", "path": "/dev/bus/usb/001/002",
        "vid": "1d6b", "pid": "0002", "usb_version": "2.00",
        "class": "09", "subclass": "00", "protocol": "00",
        "bcdDevice": "2.00", "manufacturer": "Linux", "product": "Root Hub",
        "serial": "", "num_configurations": 1,
        "configurations": [parsed_config],
        "_raw_device": device.hex(), "_raw_configs": [config.hex()],
    }
    with tempfile.TemporaryDirectory() as tree:
        directory = write_sysfs(tree, result, 480)
        assert os.path.basename(directory) == "1-2"
        with open(os.path.join(directory, "descriptors"), "rb") as handle:
            assert handle.read() == device + config
        with open(os.path.join(directory, "busnum"), encoding="utf-8") as handle:
            assert handle.read() == "1\n"
        with open(os.path.join(directory, "uevent"), encoding="utf-8") as handle:
            assert "DEVNAME=bus/usb/001/002" in handle.read()
        assert os.path.islink(os.path.join(directory, "subsystem"))
        assert descriptors_blob(result) == device + config
        ifaces = [entry for entry in os.listdir(tree)
                  if entry.startswith("1-2:")]
        assert ifaces, "no interface directory was written"
        iface_dir = os.path.join(tree, ifaces[0])
        with open(os.path.join(iface_dir, "bNumEndpoints"),
                  encoding="utf-8") as handle:
            assert int(handle.read()) == 1
        eps = [entry for entry in os.listdir(iface_dir)
               if entry.startswith("ep_")]
        assert eps, "no endpoint directory was written"
    print("selftest: ok")
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read USB descriptors from a Termux:API file descriptor.")
    parser.add_argument("--fd", type=int, default=None,
                        help="usbdevfs descriptor (default: $TERMUX_USB_FD)")
    parser.add_argument("--path", default=os.environ.get("LFA_USB_PATH", ""),
                        help="Android device path for the report")
    parser.add_argument("--bus", default="", help="bus number (001)")
    parser.add_argument("--dev", default="", help="device number (002)")
    parser.add_argument("--json", action="store_true",
                        help="print JSON (the default)")
    parser.add_argument("--out", default="",
                        help="write JSON here instead of stdout")
    parser.add_argument("--tsv", default="",
                        help="write one tab-separated row here")
    parser.add_argument("--pretty", action="store_true",
                        help="indent JSON output")
    parser.add_argument("--blob", default="",
                        help="write the raw sysfs descriptors blob here")
    parser.add_argument("--sysfs", default="",
                        help="write a sysfs device directory under this tree")
    parser.add_argument("--speed", type=int, default=480,
                        help="speed attribute for --sysfs (default 480)")
    parser.add_argument("--selftest", action="store_true",
                        help="run the descriptor parser self-test")
    parser.add_argument("--version", action="version",
                        version="lfa-usb-desc 1.0")
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()

    fd = args.fd
    if fd is None:
        raw = os.environ.get("TERMUX_USB_FD", "").strip()
        if not raw:
            print("lfa-usb-desc: no USB descriptor. Start with "
                  "'lfa usb exec DEV -- %s' in Termux." % sys.argv[0],
                  file=sys.stderr)
            return 3
        try:
            fd = int(raw)
        except ValueError:
            print("lfa-usb-desc: TERMUX_USB_FD is not a number: %r" % raw,
                  file=sys.stderr)
            return 3

    try:
        result = read_device(fd, args.path, args.bus, args.dev)
    except UsbError as exc:
        payload = {"error": str(exc), "path": args.path,
                   "bus": args.bus, "dev": args.dev}
        text = json.dumps(payload, indent=2 if args.pretty else None) + "\n"
        if args.out:
            try:
                write_atomic(args.out, text)
            except OSError:
                pass
        print("lfa-usb-desc: %s" % exc, file=sys.stderr)
        return 2

    text = json.dumps(result, indent=2 if args.pretty else None) + "\n"
    if args.out:
        try:
            write_atomic(args.out, text)
        except OSError as exc:
            print("lfa-usb-desc: cannot write %s: %s" % (args.out, exc),
                  file=sys.stderr)
            return 2
    else:
        sys.stdout.write(text)

    if args.tsv:
        try:
            write_atomic(args.tsv, tsv_row(result))
        except OSError as exc:
            print("lfa-usb-desc: cannot write %s: %s" % (args.tsv, exc),
                  file=sys.stderr)
            return 2

    if args.blob:
        try:
            directory = os.path.dirname(args.blob) or "."
            os.makedirs(directory, exist_ok=True)
            temporary = "%s.tmp.%d" % (args.blob, os.getpid())
            with open(temporary, "wb") as handle:
                handle.write(descriptors_blob(result))
            os.replace(temporary, args.blob)
        except OSError as exc:
            print("lfa-usb-desc: cannot write %s: %s" % (args.blob, exc),
                  file=sys.stderr)
            return 2

    if args.sysfs:
        try:
            write_sysfs(args.sysfs, result, args.speed)
        except (OSError, UsbError) as exc:
            print("lfa-usb-desc: cannot write --sysfs: %s" % exc,
                  file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
