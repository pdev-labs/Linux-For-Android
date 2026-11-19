# USB devices through Termux:API

LFA gives the Linux guest a **real userspace USB port**: the device list comes
from Android, the descriptors come from the device, and every transfer goes
through the usbfs descriptor that Termux:API opened. Inside the guest you get
`/dev/bus/usb/001/002` for libusb programs and `/dev/ttyUSB0` for serial
programs, so unmodified tools such as `lsusb`, PyUSB, dfu-util, picocom and
`esptool` work the way they do on a desktop.

Nothing is simulated at the transfer level. What *is* virtualised is the
filesystem name: proot cannot create device nodes (`mknod` needs root), so a
small preload object maps `open()` on the node path to the inherited usbfs
descriptor. Everything after `open()` — `ioctl`, `read`, `write`, `close` — is
the real kernel object.

## What is real, and what is not

| Thing | Status |
|---|---|
| Device list (`Bus`, `Device`, path) | real, from `termux-usb -l` |
| Descriptors, strings, interfaces, endpoints | real, read with `USBDEVFS_CONTROL` |
| `/dev/bus/usb/BBB/DDD` | real descriptor exposed by a preload; proot cannot mknod |
| Data transfers, control/bulk/interrupt requests | real, straight to the kernel driver |
| `/sys/bus/usb/devices` | synthetic files, but filled with the **real** descriptors |
| `/dev/ttyUSB0` | pty bridged to the device's real bulk endpoints |
| Hotplug events | polled with `lfa usb watch`; Termux:API has no event stream |
| Kernel drivers (`usbhid`, `usb-storage`, ALSA USB audio) | not attached; userspace access only |

The mental model is "a real USB client with a real port name", not "a second
kernel USB stack". Programs that need a kernel driver (mounting a USB stick,
USB audio, a printer queue) still cannot use the device, because Android owns
the kernel side.

## Requirements

- Termux with the `termux-api` client package: `pkg install termux-api`
- `termux-api-package` 0.57 or newer, which supports `-E` (descriptor as
  `TERMUX_USB_FD`); update with `pkg upgrade termux-api`
- The Termux:API app from F-Droid (the client alone is not enough)
- An OTG adapter or a USB-C port with host mode
- Python 3 with `ctypes` in the guest for descriptor reads and the serial
  bridge (`apt install python3` on Debian/Ubuntu/Kali, `apk add python3` on
  Alpine, `python3-ctypes` if Alpine's `import ctypes` fails)
- A C compiler *or* the bundled preload. `lfa usb enable` and the session
  commands build `lib/lfa-usb-node.c` with `clang` (or the host `cc`), and
  fall back to `lib/prebuilt/lfa-usb-node-<arch>.so`. arm64 devices are
  covered by the bundled object; other architectures need `pkg install clang`
  or a guest compiler.

Check the device side first:

```bash
lfa usb status
```

`USB host feature: not advertised` means Android's feature list has no
`android.hardware.usb.host` entry. Many phones still work with an OTG
adapter, so try it; a powered hub helps with devices that draw more than a
few milliamps.

`Termux:API app: installed (pm cannot list it)` is normal on Android 11 and
newer: `pm list packages` cannot see other apps, so LFA treats a working
`termux-usb -l` as proof that the app is present.

## Quick start

```bash
# 1. See what Android exposes right now.
lfa usb list
lfa usb refresh

# 2. Read descriptors. Android shows one permission dialog per device.
lfa usb scan

# 3. Install the guest helpers, the libusb preload, and the tty bridge.
lfa usb enable -i ubuntu

# 4. Open a session with a real device port.
lfa usb attach -i ubuntu            # shell with /dev/bus/usb + sysfs
lsusb
lsusb -v -d 1d6b:0002

# 5. Or a serial port.
lfa usb tty -i ubuntu               # shell with /dev/ttyUSB0

# 6. Flashing: esptool runs inside the guest, driven from Termux.
lfa usb flash --install
lfa usb flash probe
lfa usb flash write 0x0 /sdcard/firmware.bin
```

`lfa usb attach` prints what it mapped, then runs your command (or a login
shell) inside the guest. `lfa usb list` still works without any session: it
reads the published bridge and needs no permission dialog.

## Commands

```
lfa usb status                 Termux:API, host feature, bridge, preload state
lfa usb list [--json]          live devices; descriptors when already cached
lfa usb refresh                re-read `termux-usb -l` and rewrite the guest view
lfa usb scan [DEV...]          request permission and read real descriptors
lfa usb watch [--interval N]   poll for hotplug, print add/remove events
lfa usb enable [-i NAME]       install helpers, preload, and the tty bridge
lfa usb disable [-i NAME]      remove those helpers
lfa usb attach [DEV] [-- CMD]  session with /dev/bus/usb/BBB/DDD and sysfs
lfa usb tty [DEV] [-- CMD]     session with /dev/ttyUSB0
lfa usb exec DEV -- CMD        raw descriptor only (no preload, no node)
lfa usb flash [--install] ...  run esptool in the guest through the tty bridge
```

`DEV` is exactly what `termux-usb -l` reports (`/dev/bus/usb/001/002`).
`001/002` and `001:002` are accepted too. With one device attached, `DEV` may
be omitted.

Sessions accept `-i NAME`, `--user NAME`, `--root`, `--cwd DIR`,
`--no-permission`, and (for `attach`) `--no-sysfs`. `tty` and `flash` also
accept `--baud N` and `--device DEV`.

`lfa usb enable -i NAME` remembers that instance, so later `scan`, `attach`,
`tty` and `flash` work without repeating `-i` even when several distributions
are installed. If the remembered instance no longer exists, they print the
exact `-i NAME` form instead of exiting quietly.

## How the node works

`termux-usb -E -e COMMAND` opens the device and puts the real usbfs file
descriptor in `TERMUX_USB_FD`. File descriptors survive `fork` and `exec`, so
the descriptor is still valid after proot has entered the guest. The session
does three things:

1. It writes a sysfs-shaped directory for the device from the real
   descriptors (device, configuration, interfaces, endpoints) and binds it
   over `/sys/bus/usb/devices` with `proot-distro login --bind`.
2. It creates a placeholder path `/dev/bus/usb/BBB/DDD` and preloads
   `/usr/local/lib/lfa-usb-node.so`.
3. It sets `LFA_USB_MAP=BBB/DDD=<fd>` and starts the guest command.

The preload (`lib/lfa-usb-node.c`, built for the guest architecture) then:

- returns a duplicate of the real descriptor when a program opens the node;
- reports `SYSFS_MAGIC` for `statfs()` on `/sys`, because libudev rejects
  syspaths that are not on a sysfs filesystem;
- replaces the udev hotplug monitor with an idle pipe, because Android has no
  udev daemon for libusb to subscribe to. Enumeration still uses the real
  libudev and the synthetic tree; only hotplug notifications are missing.

Because the descriptor is duplicated, `fcntl`, `ioctl`, `read`, `write` and
`USBDEVFS_*` requests behave exactly as they do for a native usbfs client.
libusb 1.0's Linux backend (with or without udev) sees a normal device.

`lfa usb attach` needs the guest to read descriptors once, which is why it
opens the device twice: a short descriptor pass, then the session. Android
shows the permission dialog only for the first pass.

### Pointers for libusb code

Most programs need no changes at all. If you write your own code and the
device is already open, both of these work:

- libusb 1.0.23 or newer: `libusb_wrap_sys_device(NULL, fd, &handle)`
- PyUSB: `usb.core.device_from_fd(fd)` (newer PyUSB)

The plain `/dev/bus/usb/BBB/DDD` path also works, including `libusb_open()`.

The sysfs view has the device, configuration, interface (`1-2:1.0`) and
endpoint (`ep_81`) directories that libusb and usbutils walk, filled from the
real descriptors, so `lsusb -v` prints the real classes and endpoints. There
is no host-controller root hub in that tree (Termux:API does not expose one),
which is why `lsusb -t` prints nothing: topology needs the root hub entry.

`lfa usb enable` installs an `lsusb` helper in `/usr/local/bin` that reads the
bridge files. In a mapped session it hands over to the distribution's real
`usbutils` binary when one is installed (`apt install usbutils`), so
`lsusb -v` uses libusb against the real node; without usbutils the helper
still prints the device list from `lfa usb scan`.

## Serial port and flashing

`lfa usb tty` claims the device's bulk interface and exposes it as a pty at
`/dev/ttyUSB0`. A child shell inherits the pty descriptor, and the preload
maps the node path onto it, so serial programs do not need a devpts mount of
their own.

The bridge understands the usual USB-UART chips:

| Chip | IDs | Baud/line control |
|---|---|---|
| CDC ACM | interface class `02`/`0a` | standard `SET_LINE_CODING` / `SET_CONTROL_LINE_STATE` |
| CP210x | `10c4:*` | `SET_BAUDRATE`, `SET_LINE_CTL`, `SET_MHS` |
| CH340 | `1a86:7523` | WCH divisor registers and `MODEM_CTRL` |
| other | any | raw 8N1 pipe, no baud changes (use 115200 if the chip defaults to it) |

Baud changes made by the client are read from the pty termios and forwarded to
the real chip. DTR/RTS changes (`TIOCMBIS`/`TIOCMBIC`/`TIOCMSET`) are caught by
the preload and sent to the bridge, which keeps the two lines in step —
setting one does not clear the other — so esptool's automatic reset sequence
reaches the board. `TIOCMGET` reports DTR and RTS as set and CTS/DSR as
asserted, which is what a board with a working auto-reset circuit looks like
to pyserial. If a board has no auto-reset circuit, hold **BOOT**, tap
**EN/RST**, release **BOOT**, then run the flash command.

`lfa usb flash` is a thin wrapper around `esptool` inside the distribution:

```bash
lfa usb flash --install                 # pip install esptool in the guest
lfa usb flash probe                     # read the chip ID
lfa usb flash write 0x0 /sdcard/firmware.bin
lfa usb flash --baud 460800 write 0x0 /sdcard/app.bin
```

Firmware paths are guest paths. `/sdcard` is shared with the guest, so it is
the easiest place to keep a `.bin` file. Keep `--baud` the same in the bridge
and in esptool; the wrapper passes it to both.

The friendly verbs are translated to whichever esptool is installed
(`write` → `write_flash` on v4 and `write-flash` on v5, and the same for
`probe`/`verify`/`erase`/`read`). Any exact esptool command also works
unchanged.

### When a chip is busy

Android binds kernel drivers for some classes (notably `cdc_acm` for CDC-ACM
devices and `usb-storage` for mass storage). A userspace claim then fails with
`EBUSY`; without root, Android cannot detach the driver. The bridge reports
this clearly. Native-USB ESP32 bootloaders and CP210x/CH340 boards normally
have no bound driver, which is why they work.

## Raw descriptor mode: `lfa usb exec`

If the preload cannot be built for a guest, or you want the smallest possible
surface, `lfa usb exec` still forwards the descriptor without any filesystem
changes:

```bash
lfa usb exec 001/002 -i ubuntu -- lfa-usb desc
lfa usb exec 001/002 -i ubuntu -- python3 -c \
  'import os; print("fd", os.environ["TERMUX_USB_FD"])'
```

Guest helper `lfa-usb`:

```
lfa-usb list                 same as lsusb
lfa-usb info BUS DEV         cached descriptor fields
lfa-usb status               bridge and fd state
lfa-usb fd                   print TERMUX_USB_FD
lfa-usb run CMD [args]       run with the inherited fd
lfa-usb desc [FD]            read descriptors from FD
lfa-usb path BUS DEV         print the Android device path
```

`lfa-usb desc` performs raw `USBDEVFS_CONTROL` ioctls and needs neither libusb
nor udev, which is why it works in minbase distros.

## Where the data lives

`lfa usb refresh` writes into `$PREFIX/tmp/lfa-usb`. Every LFA guest sees that
directory as `/tmp/lfa-usb` because proot uses `--shared-tmp`:

```
devices.json    raw `termux-usb -l` output
devices.tsv     bus, dev, path, VID, PID, USB version, class, subclass,
                protocol, manufacturer, product, serial, interfaces, source
sys/BUS-DEV/    small files shaped like sysfs (busnum, idVendor, ...)
scan-*.json     full descriptors from `lfa usb scan`
scan-*.tsv      one-line form of the same descriptors
prep-*.json     descriptors read by the last attach session
session-sys/    sysfs tree bound over /sys/bus/usb/devices by attach
state.env       USB_COUNT, USB_UPDATED, USB_SOURCE
events.log      add/remove lines from `lfa usb watch`
```

`lfa usb enable` also creates `/run/lfa-usb -> /tmp/lfa-usb` in the guest so
scripts have a stable-looking path. It is a symlink, not a mount.

Preload builds are cached in `~/.cache/linux-for-android/usb/build/`. The
descriptor cache lives in `~/.cache/linux-for-android/usb/`. It is keyed by
bus and device number. **Bus/device numbers are reused** when devices are
swapped; run `lfa usb scan` again after replacing a device if you need fresh
strings.

## One device at a time

A session maps one device. Termux:API grants one descriptor per `termux-usb`
invocation, and Android permissions are per device. Run two sessions from two
Termux shells if you need two devices; `lfa usb watch` still shows all of them.

## Security

- Android grants USB access per app, per device, per connection. LFA cannot
  bypass that dialog.
- Sessions run as the desktop user by default. `--root` is explicit for a
  reason: a USB device is untrusted input. A malicious device can exploit a
  buggy driver or program.
- Everyone in the guest can read `/tmp/lfa-usb`, including serial numbers.
  Do not put secrets in the bridge directory.
- The callback, descriptor reader, preload source and tty bridge are plain
  files you can read: `$PREFIX/bin/lfa-usb-callback`, `lib/usb-desc.py`,
  `lib/lfa-usb-node.c` and `lib/lfa-usb-tty.py`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `termux-usb is not installed` | `lfa android install`, then reopen Termux |
| `cannot export a USB descriptor (-E)` | `termux-api-package` is older than 0.57. Run `pkg upgrade termux-api` |
| `termux-usb returned nothing` | Termux:API app was killed or is asleep. Open it once, run `lfa android test` |
| `Permission denied` during `scan` | You dismissed the Android dialog, or the app lost access. Replug the device and retry |
| `No USB devices are visible` | No OTG adapter, device is charge-only, or Android did not enumerate it. Try a powered hub |
| `ID ----:----` in `lsusb` | Live list works, descriptors are not cached. Run `lfa usb scan` |
| `usbfs preload could not be built` | `pkg install clang`, then `lfa usb enable -i NAME` again, or use `lfa usb exec` |
| `lsusb` prints nothing in a session | the command ran outside `lfa usb attach`, or the preload/sysfs is missing. Check `lfa usb status` |
| Saving session output | redirect both streams, e.g. `lfa usb attach -- lsusb > log 2>&1`; Termux:API captures stdout in a pipe, so a session keeps it on the terminal unless both are redirected |
| `lsusb -t` is empty | there is no root hub in the synthetic tree; use `lsusb` or `lsusb -v` |
| `interface N is already claimed by a kernel driver` | Android bound `cdc_acm`/`usb-storage`. Unplug, use the native USB bootloader port, or a board without that driver |
| `esptool: command not found` | `lfa usb flash --install` |
| Flashing stops at "connecting" | Hold BOOT while plugging in, or check that the bridge picked the right chip (`lfa-usb-tty` prints it) |
| Device works in Termux but not in a plain guest shell | Use `lfa usb attach`; a shell started with `lfa shell` has no inherited descriptor |
| Device disappears after a while | Android power management closed it, or the OTG cable lost contact. `lfa usb watch` shows removals |

## Testing

The host suite fakes `termux-usb` and `proot-distro` and checks enumeration,
the bridge files, the descriptor cache, guest `lsusb`, `lfa-usb`, `exec`,
`attach`, `tty`, `flash`, `watch`, enable/disable, missing clients and
malformed output. The descriptor parser and the serial bridge have self-tests
that need no hardware:

```bash
python3 lib/usb-desc.py --selftest
python3 lib/lfa-usb-tty.py --selftest
```

The preload can also be checked without a device: opening a mapped path must
return a duplicate of the supplied descriptor. The host suite does this with
a regular file standing in for the usbfs descriptor, plus a fake sysfs tree
and the real libusb/lsusb from the host.

Real hardware still needs a device test: connect a known stick or keyboard,
run `lfa usb scan`, then `lfa usb attach DEV -- lsusb -v` and compare the
output with a PC. Flashing a board is the other end-to-end check. Those are
deliberately not claimed until they are run on a phone.
