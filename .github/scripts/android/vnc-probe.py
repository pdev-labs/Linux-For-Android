#!/usr/bin/env python3
"""Minimal VNC/RFB client used as a real end-to-end check.

It performs the handshake, authenticates with VNC auth, requests one raw
framebuffer update, and asserts that the screen is not a single black frame.
A listening port alone is not proof that the desktop rendered.

Usage:
  vnc-probe.py [--host 127.0.0.1] [--port 5901] [--password lfaci]
"""

from __future__ import annotations

import argparse
import socket
import subprocess
import sys
import time


def read_exact(sock: socket.socket, n: int) -> bytes:
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise RuntimeError("VNC server closed the connection")
        data += chunk
    return data


def vnc_des_key(password: str) -> bytes:
    raw = password.encode("utf-8")[:8].ljust(8, b"\0")
    # VNC reverses the bit order of every password byte before using it as
    # the DES key.
    return bytes(int(f"{byte:08b}"[::-1], 2) for byte in raw)


def des_encrypt(key: bytes, challenge: bytes) -> bytes:
    try:
        from Crypto.Cipher import DES  # type: ignore

        return DES.new(key, DES.MODE_ECB).encrypt(challenge)
    except Exception:
        pass
    try:
        result = subprocess.run(
            [
                "openssl", "enc", "-des-ecb", "-nopad",
                "-K", key.hex(),
                "-provider", "legacy", "-provider", "default",
            ],
            input=challenge,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        if len(result.stdout) != 16:
            raise RuntimeError("openssl returned the wrong number of bytes")
        return result.stdout
    except Exception as exc:  # noqa: BLE001 - report the real reason
        raise RuntimeError(
            "cannot compute the VNC DES response; install pycryptodome or a "
            "Python with the OpenSSL legacy provider"
        ) from exc


def connect(host: str, port: int, timeout: float = 10.0) -> socket.socket:
    return socket.create_connection((host, port), timeout=timeout)


def handshake(sock: socket.socket, password: str) -> tuple[int, int, str]:
    version = read_exact(sock, 12)
    if not version.startswith(b"RFB "):
        raise RuntimeError(f"not an RFB server: {version!r}")
    # 3.8 is the highest version we implement; servers accept the lower one.
    sock.sendall(b"RFB 003.008\n")

    count = read_exact(sock, 1)[0]
    if count == 0:
        reason_len = int.from_bytes(read_exact(sock, 4), "big")
        reason = read_exact(sock, reason_len).decode("utf-8", "replace")
        raise RuntimeError(f"server refused the connection: {reason}")
    types = read_exact(sock, count)
    if 2 in types:
        sock.sendall(b"\x02")
        challenge = read_exact(sock, 16)
        sock.sendall(des_encrypt(vnc_des_key(password), challenge))
        result = int.from_bytes(read_exact(sock, 4), "big")
        if result != 0:
            raise RuntimeError("VNC authentication failed")
    elif 1 in types:
        sock.sendall(b"\x01")
    else:
        raise RuntimeError(f"no supported security type: {list(types)}")

    sock.sendall(b"\x01")  # ClientInit, shared
    width = int.from_bytes(read_exact(sock, 2), "big")
    height = int.from_bytes(read_exact(sock, 2), "big")
    _pixel_format = read_exact(sock, 16)
    name_len = int.from_bytes(read_exact(sock, 4), "big")
    name = read_exact(sock, name_len).decode("utf-8", "replace")

    # Ask for 32bpp true colour, little-endian, RGB shifts 16/8/0.
    sock.sendall(
        b"\x00\x00\x00\x00"
        + bytes([32, 24, 0, 1, 255, 255, 255, 16, 8, 0, 0, 0, 0, 0, 0, 0])
    )
    # Raw encoding only.
    sock.sendall(b"\x02\x00\x00\x01\x00\x00\x00\x00")
    return width, height, name


def one_update(sock: socket.socket, width: int, height: int) -> bytes:
    sock.sendall(b"\x03\x00" + (0).to_bytes(2, "big") * 2
                 + width.to_bytes(2, "big") + height.to_bytes(2, "big"))
    pixels = b""
    while len(pixels) < width * height * 4:
        msg_type = read_exact(sock, 1)[0]
        if msg_type != 0:
            # Bell, server cut text, etc. We requested one update; skip
            # anything else without guessing at its length.
            if msg_type == 2:
                raise RuntimeError("server sent an unexpected cut-text message")
            raise RuntimeError(f"unexpected RFB message type {msg_type}")
        _pad = read_exact(sock, 1)
        rects = int.from_bytes(read_exact(sock, 2), "big")
        for _ in range(rects):
            _x = int.from_bytes(read_exact(sock, 2), "big")
            _y = int.from_bytes(read_exact(sock, 2), "big")
            rw = int.from_bytes(read_exact(sock, 2), "big")
            rh = int.from_bytes(read_exact(sock, 2), "big")
            encoding = int.from_bytes(read_exact(sock, 4), "big", signed=True)
            if encoding != 0:
                raise RuntimeError(f"server used unsupported encoding {encoding}")
            pixels += read_exact(sock, rw * rh * 4)
            if len(pixels) >= width * height * 4:
                break
    return pixels


def analyse(pixels: bytes) -> tuple[int, float]:
    unique: set[bytes] = set()
    total = 0
    count = 0
    for i in range(0, len(pixels), 4):
        b, g, r, _ = pixels[i : i + 4]
        unique.add(bytes((r, g, b)))
        total += (r + g + b) // 3
        count += 1
        if len(unique) > 256:
            # Enough evidence; stop collecting to keep this cheap.
            break
    return len(unique), (total / count if count else 0.0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5901)
    parser.add_argument("--password", default="lfaci")
    parser.add_argument("--wait", type=int, default=60,
                        help="seconds to wait for the server to accept")
    args = parser.parse_args()

    deadline = time.time() + args.wait
    last_error: Exception | None = None
    sock: socket.socket | None = None
    while time.time() < deadline:
        try:
            sock = connect(args.host, args.port)
            break
        except OSError as exc:
            last_error = exc
            time.sleep(2)
    if sock is None:
        print(f"FAIL: could not connect to {args.host}:{args.port}: {last_error}", file=sys.stderr)
        return 1

    try:
        width, height, name = handshake(sock, args.password)
        pixels = one_update(sock, width, height)
    except Exception as exc:  # noqa: BLE001 - this is a test probe
        print(f"FAIL: RFB handshake/update failed: {exc}", file=sys.stderr)
        return 1
    finally:
        sock.close()

    unique, mean = analyse(pixels)
    print(f"RFB desktop: {width}x{height}, name={name!r}, unique colours={unique}, mean={mean:.1f}")
    if width < 640 or height < 480:
        print("FAIL: framebuffer is smaller than any supported desktop", file=sys.stderr)
        return 1
    if unique < 4 or mean < 2.0:
        print("FAIL: framebuffer looks blank (black or a single cursor)", file=sys.stderr)
        return 1

    print("PASS: VNC returned a rendered desktop framebuffer")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
