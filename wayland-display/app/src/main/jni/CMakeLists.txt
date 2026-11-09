cmake_minimum_required(VERSION 3.20)
project(wayland-compositor C)

# Minimal shm Wayland compositor for the LFA display app.
#
# Sources come from Trierarch's trierarch-wayland (GPL-3.0), with two local
# changes:
#   * compositor_create_from_fd() adopts a listening socket created by the
#     Termux-side bridge instead of binding its own path
#   * linux-dmabuf is not advertised unless LFA_WL_DMABUF is defined, so
#     clients (and the nested compositor) allocate wl_shm buffers
#
# Expects WAYLAND_PREFIX to point at a wayland build for Android that provides
# include/wayland-server*.h and lib/libwayland-server.so.

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT DEFINED WAYLAND_PREFIX)
  message(FATAL_ERROR "WAYLAND_PREFIX is required (prefix with wayland-server for Android)")
endif()

set(COMPOSITOR_SOURCES
  src/compositor.c
  src/buffer.c
  src/linux_dmabuf.c
  src/surface.c
  src/subcompositor.c
  src/android_wlegl.c
  src/xdg_shell.c
  src/output.c
  src/seat.c
  src/pointer_input.c
  src/keyboard_input.c
  src/data_device.c
  src/single_pixel_buffer.c
  src/viewporter.c
  src/xdg_decoration.c
  src/xdg_output.c
  src/fractional_scale.c
  src/pointer_constraints.c
  src/relative_pointer.c
  src/presentation.c
  src/renderer.c
  src/jni_bridge.c
  src/keycode_map.c
  protocol/xdg-shell-server-protocol.c
  protocol/single-pixel-buffer-v1-server-protocol.c
  protocol/viewporter-server-protocol.c
  protocol/xdg-decoration-unstable-v1-server-protocol.c
  protocol/xdg-output-unstable-v1-server-protocol.c
  protocol/fractional-scale-v1-server-protocol.c
  protocol/pointer-constraints-unstable-v1-server-protocol.c
  protocol/relative-pointer-unstable-v1-server-protocol.c
  protocol/presentation-time-server-protocol.c
  protocol/linux-dmabuf-v1-server-protocol.c
  protocol/android-wlegl-server-protocol.c
)

add_library(wayland-compositor SHARED ${COMPOSITOR_SOURCES})

target_include_directories(wayland-compositor PRIVATE
  src
  protocol
  "${WAYLAND_PREFIX}/include"
)

target_link_directories(wayland-compositor PRIVATE "${WAYLAND_PREFIX}/lib")

target_link_libraries(wayland-compositor
  wayland-server
  EGL
  GLESv2
  android
  log
  m
)

target_compile_options(wayland-compositor PRIVATE -Wall -Wextra -Wno-unused-parameter)

# Tiny dependency-free helper loaded by the Termux-side bridge (app_process).
add_library(lfabridge SHARED src/bridge_socket.c)
target_link_libraries(lfabridge log)
target_compile_options(lfabridge PRIVATE -Wall -Wextra)
