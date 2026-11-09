# wayland-display

A dedicated Wayland display for Android, in the spirit of Termux:X11, so a real
desktop compositor (Hyprland, Sway, anything xdg-shell) can run inside the
Linux-For-Android guest and draw into an Android app window.

This directory holds the app, the build glue and the host-side spike that
proves the compositor can run without a DRM render node.

## Status

Stage A (host proof) is done. Nested Hyprland 0.56.2 renders clients into
`wl_shm` buffers at 1280x720 on a machine with no usable DRM node, and a parent
Sway displays the result. The Android app and its CI build are next.

## Why a patch series

Hyprland's Aquamarine backend assumes a DRM render node: it opens
`/dev/dri/renderD*`, allocates GBM buffers and hands out dmabufs. Inside a
Termux-like sandbox there is no DRM node the guest may open, and a nested
compositor's parent may not offer `zwp_linux_dmabuf_v1` at all.

The patch series in `scripts/apply-shm-patches.py` removes both assumptions:

* **Aquamarine**
  * a memfd-backed `CSHMAllocator`/`CSHMBuffer` (`AQ_ALLOCATOR_TYPE_SHM`)
  * allocator fallback when no implementation exposes a DRM fd
  * `wl_shm` buffer creation in the Wayland backend when dmabuf is missing
  * linear shm render formats instead of an empty dmabuf format list
  * protocol binds clamped to the version the parent advertises
  * output announcement moved to the first `xdg_surface.configure`, so the
    monitor gets a real size instead of 0x0
* **Hyprland**
  * surfaceless EGL (`EGL_MESA_platform_surfaceless`) when the DRM fd is -1
  * a GL renderbuffer for shm output buffers, with a `glReadPixels` copy back
    into the memfd (`presentToShm`)
  * software-renderer detection that asks GL when the DRM probe never ran

Pinned versions: Aquamarine `v0.15.1`, Hyprland `v0.56.2`. The script is
idempotent and asserts every anchor, so a version bump fails loudly instead of
patching the wrong lines.

## Reproducing the host spike

```sh
# build the scanner, patch and build Aquamarine + Hyprland
python3 wayland-display/scripts/apply-shm-patches.py <aquamarine-src> <hyprland-src>

# parent compositor with no GPU node
WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1 sway -c sway.conf &

# nested Hyprland
WAYLAND_DISPLAY=wayland-1 Hyprland -c hypr-nested.conf
```

`hypr-nested.conf` is the minimal config used for the spike: no hardware
cursors, no blur or shadows, stdout logs on.

Measured on an Intel HD 4400 with llvmpipe: 1280x720, kitty and a wl_shm test
client render correctly; the readback costs a full-frame copy per frame.

## Roadmap

1. **Stage B** — app displays Sway at a chosen resolution; touch, IME and extra
   keys work.
2. **Stage C** — Hyprland session on the app display with the host config.
3. **Stage D** — CI release (APK, bridge daemon, patched Aquamarine), `lfa wd`
   commands, device tests, docs.
4. **Stage E** — optional VirGL path for GPU acceleration.
