#!/usr/bin/env python3
"""Apply the wl_shm patch series to aquamarine and Hyprland.

Usage:
    apply-shm-patches.py <aquamarine-src> <hyprland-src>

The patch makes a compositor run without a DRM render node:

* aquamarine: memfd-backed `CSHMAllocator` + `CSHMBuffer`, a backend
  fallback when no implementation exposes a DRM fd, a `wl_shm` path for
  `CWaylandBuffer`, and shm render formats for the Wayland backend.
* Hyprland: surfaceless EGL when the DRM fd is negative, a GL renderbuffer
  for shm output buffers, and a `glReadPixels` copy back into the memfd.

Both trees are pinned by the caller. The script is idempotent: re-running it
after a partial apply is safe because every edit asserts its input.
"""

import pathlib
import sys


def patch(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text()
    if new in text and old not in text:
        return  # already applied
    if old not in text:
        raise SystemExit(f"pattern not found in {path}:\n{old[:200]}")
    path.write_text(text.replace(old, new, 1))


def write(path: pathlib.Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def patch_aquamarine(root: pathlib.Path) -> None:
    allocator_hpp = root / "include/aquamarine/allocator/Allocator.hpp"
    if "AQ_ALLOCATOR_TYPE_SHM" not in allocator_hpp.read_text():
        patch(
            allocator_hpp,
            "        AQ_ALLOCATOR_TYPE_GBM = 0,\n        AQ_ALLOCATOR_TYPE_DRM_DUMB,\n",
            "        AQ_ALLOCATOR_TYPE_GBM = 0,\n        AQ_ALLOCATOR_TYPE_DRM_DUMB,\n        AQ_ALLOCATOR_TYPE_SHM,\n",
        )

    write(
        root / "include/aquamarine/allocator/SHM.hpp",
        r'''#pragma once

#include "Allocator.hpp"

namespace Aquamarine {
    class CSHMAllocator;
    class CBackend;
    class CSwapchain;

    class CSHMBuffer : public IBuffer {
      public:
        virtual ~CSHMBuffer();

        virtual eBufferCapability                      caps();
        virtual eBufferType                            type();
        virtual void                                   update(const Hyprutils::Math::CRegion& damage);
        virtual bool                                   isSynchronous();
        virtual bool                                   good();
        virtual SSHMAttrs                              shm();
        virtual std::tuple<uint8_t*, uint32_t, size_t> beginDataPtr(uint32_t flags);
        virtual void                                   endDataPtr();

      private:
        CSHMBuffer(const SAllocatorBufferParams& params, Hyprutils::Memory::CWeakPointer<CSHMAllocator> allocator_,
                   Hyprutils::Memory::CSharedPointer<CSwapchain> swapchain);

        Hyprutils::Memory::CWeakPointer<CSHMAllocator> allocator;

        SSHMAttrs attrs{.success = false};
        uint8_t*  data = nullptr;
        size_t    len  = 0;

        friend class CSHMAllocator;
    };

    class CSHMAllocator : public IAllocator {
      public:
        ~CSHMAllocator();
        static Hyprutils::Memory::CSharedPointer<CSHMAllocator> create(Hyprutils::Memory::CWeakPointer<CBackend> backend_);

        virtual Hyprutils::Memory::CSharedPointer<IBuffer>      acquire(const SAllocatorBufferParams& params, Hyprutils::Memory::CSharedPointer<CSwapchain> swapchain_);
        virtual Hyprutils::Memory::CSharedPointer<CBackend>     getBackend();
        virtual int                                             drmFD();
        virtual eAllocatorType                                  type();
        virtual void                                            destroyBuffers();

        Hyprutils::Memory::CWeakPointer<CSHMAllocator> self;

      private:
        CSHMAllocator(Hyprutils::Memory::CWeakPointer<CBackend> backend_);

        std::vector<Hyprutils::Memory::CWeakPointer<CSHMBuffer>> buffers;
        Hyprutils::Memory::CWeakPointer<CBackend>                backend;

        friend class CSHMBuffer;
    };
};
''',
    )

    write(
        root / "src/allocator/SHM.cpp",
        r'''#include <aquamarine/allocator/SHM.hpp>
#include <aquamarine/allocator/Swapchain.hpp>
#include <aquamarine/backend/Backend.hpp>
#include <drm_fourcc.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <cstring>
#include <linux/memfd.h>

using namespace Aquamarine;
using namespace Hyprutils::Memory;
#define SP CSharedPointer

Aquamarine::CSHMBuffer::CSHMBuffer(const SAllocatorBufferParams& params, Hyprutils::Memory::CWeakPointer<CSHMAllocator> allocator_,
                                   Hyprutils::Memory::CSharedPointer<CSwapchain> swapchain) : allocator(allocator_) {
    if (params.size.x <= 0 || params.size.y <= 0) {
        allocator->backend->log(AQ_LOG_ERROR, "SHM: invalid buffer size");
        return;
    }

    attrs.format = params.format == DRM_FORMAT_INVALID ? DRM_FORMAT_XRGB8888 : params.format;
    attrs.size   = params.size;
    size         = attrs.size;
    attrs.stride = (int)params.size.x * 4;
    attrs.offset = 0;
    len          = (size_t)attrs.stride * (size_t)params.size.y;

    int fd = memfd_create("aquamarine-shm", MFD_CLOEXEC);
    if (fd < 0) {
        allocator->backend->log(AQ_LOG_ERROR, std::format("SHM: memfd_create failed: {}", strerror(errno)));
        return;
    }

    if (ftruncate(fd, len) < 0) {
        allocator->backend->log(AQ_LOG_ERROR, std::format("SHM: ftruncate failed: {}", strerror(errno)));
        close(fd);
        return;
    }

    data = (uint8_t*)mmap(nullptr, len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        allocator->backend->log(AQ_LOG_ERROR, std::format("SHM: mmap failed: {}", strerror(errno)));
        data = nullptr;
        close(fd);
        return;
    }

    memset(data, 0, len);

    attrs.fd      = fd;
    attrs.success = true;

    allocator->backend->log(AQ_LOG_DEBUG, std::format("SHM: allocated {}x{} buffer, fd {}, len {}", (int)attrs.size.x, (int)attrs.size.y, fd, len));
}

Aquamarine::CSHMBuffer::~CSHMBuffer() {
    events.destroy.emit();

    if (data)
        munmap(data, len);

    if (attrs.fd >= 0)
        close(attrs.fd);

    attrs.fd      = -1;
    attrs.success = false;
}

eBufferCapability Aquamarine::CSHMBuffer::caps() {
    return eBufferCapability::BUFFER_CAPABILITY_DATAPTR;
}

eBufferType Aquamarine::CSHMBuffer::type() {
    return eBufferType::BUFFER_TYPE_SHM;
}

void Aquamarine::CSHMBuffer::update(const Hyprutils::Math::CRegion& damage) {
    ;
}

bool Aquamarine::CSHMBuffer::isSynchronous() {
    return true;
}

bool Aquamarine::CSHMBuffer::good() {
    return attrs.success && data;
}

SSHMAttrs Aquamarine::CSHMBuffer::shm() {
    return attrs;
}

std::tuple<uint8_t*, uint32_t, size_t> Aquamarine::CSHMBuffer::beginDataPtr(uint32_t flags) {
    return {data, attrs.format, len};
}

void Aquamarine::CSHMBuffer::endDataPtr() {
    ;
}

Aquamarine::CSHMAllocator::~CSHMAllocator() {
    ;
}

SP<CSHMAllocator> Aquamarine::CSHMAllocator::create(Hyprutils::Memory::CWeakPointer<CBackend> backend_) {
    auto p  = SP<CSHMAllocator>(new CSHMAllocator(backend_));
    p->self = p;
    return p;
}

Aquamarine::CSHMAllocator::CSHMAllocator(Hyprutils::Memory::CWeakPointer<CBackend> backend_) : backend(backend_) {
    ;
}

SP<IBuffer> Aquamarine::CSHMAllocator::acquire(const SAllocatorBufferParams& params, SP<CSwapchain> swapchain_) {
    auto buf = SP<CSHMBuffer>(new CSHMBuffer(params, self, swapchain_));
    if (!buf->good())
        return nullptr;

    buffers.emplace_back(buf);
    return buf;
}

SP<CBackend> Aquamarine::CSHMAllocator::getBackend() {
    return backend.lock();
}

int Aquamarine::CSHMAllocator::drmFD() {
    return -1;
}

eAllocatorType Aquamarine::CSHMAllocator::type() {
    return eAllocatorType::AQ_ALLOCATOR_TYPE_SHM;
}

void Aquamarine::CSHMAllocator::destroyBuffers() {
    buffers.clear();
}
''',
    )

    patch(
        root / "src/backend/Backend.cpp",
        "#include <aquamarine/allocator/GBM.hpp>",
        "#include <aquamarine/allocator/GBM.hpp>\n#include <aquamarine/allocator/SHM.hpp>",
    )

    patch(
        root / "src/backend/Backend.cpp",
        '''    if (!primaryAllocator && (implementations.empty() || implementations.at(0)->type() != AQ_BACKEND_NULL)) {
        log(AQ_LOG_CRITICAL, "Cannot open backend: no allocator available");
        return false;
    }''',
        '''    if (!primaryAllocator && (implementations.empty() || implementations.at(0)->type() != AQ_BACKEND_NULL)) {
        // No DRM node: nested Wayland sessions and headless machines have no
        // GBM device. Fall back to memfd-backed wl_shm buffers.
        log(AQ_LOG_WARNING, "No DRM allocator available, falling back to wl_shm");
        primaryAllocator = CSHMAllocator::create(self);
        if (!primaryAllocator) {
            log(AQ_LOG_CRITICAL, "Cannot open backend: no allocator available");
            return false;
        }
    }''',
    )

    patch(
        root / "include/aquamarine/backend/Wayland.hpp",
        '''        struct {
            Hyprutils::Memory::CSharedPointer<CCWlBuffer> buffer;
        } waylandState;''',
        '''        struct {
            Hyprutils::Memory::CSharedPointer<CCWlBuffer>  buffer;
            Hyprutils::Memory::CSharedPointer<CCWlShmPool> pool;
        } waylandState;''',
    )

    patch(
        root / "src/backend/Wayland.cpp",
        '''    if (!waylandState.xdg || !waylandState.compositor || !waylandState.seat || !waylandState.dmabuf || waylandState.dmabufFailed || !waylandState.shm) {
        backend->log(AQ_LOG_ERROR, "Wayland backend cannot start: Missing protocols");
        return false;
    }''',
        '''    if (!waylandState.xdg || !waylandState.compositor || !waylandState.seat || !waylandState.shm) {
        backend->log(AQ_LOG_ERROR, "Wayland backend cannot start: Missing protocols");
        return false;
    }

    if (!waylandState.dmabuf || waylandState.dmabufFailed)
        backend->log(AQ_LOG_WARNING, "Wayland backend: no usable zwp_linux_dmabuf_v1, using wl_shm buffers");''',
    )

    patch(
        root / "src/backend/Wayland.cpp",
        '''std::vector<SDRMFormat> Aquamarine::CWaylandBackend::getRenderFormats() {
    return dmabufFormats;
}''',
        '''std::vector<SDRMFormat> Aquamarine::CWaylandBackend::getRenderFormats() {
    if (dmabufFormats.empty()) {
        // shm-only parent: advertise the formats a memfd-backed buffer can carry.
        return {SDRMFormat{.drmFormat = DRM_FORMAT_XRGB8888, .modifiers = {DRM_FORMAT_MOD_LINEAR}},
                SDRMFormat{.drmFormat = DRM_FORMAT_ARGB8888, .modifiers = {DRM_FORMAT_MOD_LINEAR}}};
    }

    return dmabufFormats;
}''',
    )

    patch(
        root / "src/backend/Wayland.cpp",
        '''    } else if (auto attrs = buffer->dmabuf(); attrs.success) {
        auto params = makeShared<CCZwpLinuxBufferParamsV1>(backend->waylandState.dmabuf->sendCreateParams());''',
        '''    } else if (auto attrs = buffer->dmabuf(); attrs.success && backend->waylandState.dmabuf) {
        auto params = makeShared<CCZwpLinuxBufferParamsV1>(backend->waylandState.dmabuf->sendCreateParams());''',
    )

    patch(
        root / "src/backend/Wayland.cpp",
        '''Aquamarine::CWaylandBuffer::CWaylandBuffer(SP<IBuffer> buffer_, Hyprutils::Memory::CWeakPointer<CWaylandBackend> backend_) : buffer(buffer_), backend(backend_) {
    auto params = makeShared<CCZwpLinuxBufferParamsV1>(backend->waylandState.dmabuf->sendCreateParams());''',
        '''Aquamarine::CWaylandBuffer::CWaylandBuffer(SP<IBuffer> buffer_, Hyprutils::Memory::CWeakPointer<CWaylandBackend> backend_) : buffer(buffer_), backend(backend_) {
    if (buffer->shm().success) {
        const auto attrs = buffer->shm();
        const auto len   = (size_t)attrs.stride * (size_t)attrs.size.y;

        if (attrs.fd < 0 || len == 0) {
            backend->backend->log(AQ_LOG_ERROR, "WaylandBuffer: invalid shm buffer");
            return;
        }

        waylandState.pool = makeShared<CCWlShmPool>(backend->waylandState.shm->sendCreatePool(attrs.fd, len));

        if (!waylandState.pool || !waylandState.pool->resource()) {
            backend->backend->log(AQ_LOG_ERROR, "WaylandBuffer: failed to create a wl_shm pool");
            return;
        }

        waylandState.buffer = makeShared<CCWlBuffer>(waylandState.pool->sendCreateBuffer(attrs.offset, attrs.size.x, attrs.size.y, attrs.stride,
                                                                                          shmFormatFromDRM(attrs.format)));
        if (waylandState.buffer)
            waylandState.buffer->setRelease([this](CCWlBuffer* r) { pendingRelease = false; });

        return;
    }

    auto params = makeShared<CCZwpLinuxBufferParamsV1>(backend->waylandState.dmabuf->sendCreateParams());''',
    )

    patch(
        root / "src/allocator/Swapchain.cpp",
        '''    options = options_;
    if (options.format == DRM_FORMAT_INVALID)
        options.format = buffers.at(0)->dmabuf().format;''',
        '''    options = options_;
    if (options.format == DRM_FORMAT_INVALID)
        options.format = buffers.at(0)->type() == BUFFER_TYPE_SHM ? buffers.at(0)->shm().format : buffers.at(0)->dmabuf().format;''',
    )



def patch_wayland_binds(root: pathlib.Path) -> None:
    """Clamp protocol binds to the version the parent advertises.

    Binding a higher version than advertised is a protocol violation; the
    object stays unusable and a nested compositor never gets its configure
    (wlroots advertises xdg_wm_base v5, aquamarine asks for v6).
    """
    wayland = root / "src/backend/Wayland.cpp"

    patch(
        wayland,
        "            waylandState.seat = makeShared<CCWlSeat>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &wl_seat_interface, 9));",
        """            waylandState.seat = makeShared<CCWlSeat>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &wl_seat_interface,
                                                                                    std::min<uint32_t>(version, 9)));""",
    )
    patch(
        wayland,
        "            waylandState.xdg = makeShared<CCXdgWmBase>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &xdg_wm_base_interface, 6));",
        """            waylandState.xdg = makeShared<CCXdgWmBase>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &xdg_wm_base_interface,
                                                                                  std::min<uint32_t>(version, 6)));""",
    )
    patch(
        wayland,
        "            waylandState.compositor = makeShared<CCWlCompositor>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &wl_compositor_interface, 6));",
        """            waylandState.compositor = makeShared<CCWlCompositor>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &wl_compositor_interface,
                                                                                            std::min<uint32_t>(version, 6)));""",
    )
    patch(
        wayland,
        "            waylandState.shm = makeShared<CCWlShm>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &wl_shm_interface, 1));",
        """            waylandState.shm = makeShared<CCWlShm>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &wl_shm_interface,
                                                                             std::min<uint32_t>(version, 1)));""",
    )
    patch(
        wayland,
        "                makeShared<CCZwpLinuxDmabufV1>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &zwp_linux_dmabuf_v1_interface, 4));",
        """                makeShared<CCZwpLinuxDmabufV1>((wl_proxy*)wl_registry_bind((wl_registry*)waylandState.registry->resource(), id, &zwp_linux_dmabuf_v1_interface,
                                                                             std::min<uint32_t>(version, 4)));""",
    )



def patch_wayland_output_announce(root: pathlib.Path) -> None:
    """Backport aquamarine 0.16's configure-before-announce behaviour.

    In 0.15 the Wayland output is announced before the parent configures the
    toplevel, so Hyprland creates a monitor with a 0x0 mode and never gets a
    valid one. 0.16 waits for xdg_surface.configure, stores the size as the
    output mode, and only then emits newOutput.
    """
    header = root / "include/aquamarine/backend/Wayland.hpp"
    if "applyConfigure();" not in header.read_text():
        patch(
            header,
            "        void                                              onFrameDone();",
            "        void                                              onFrameDone();\n        void                                              applyConfigure();",
        )
    patch(
        header,
        """            Hyprutils::Math::Vector2D                        surfaceSize;
        } waylandState;""",
        """            Hyprutils::Math::Vector2D                        surfaceSize;
            Hyprutils::Math::Vector2D                        pendingSize;
            bool                                             announced = false;
        } waylandState;""",
    )

    wayland = root / "src/backend/Wayland.cpp"
    patch(
        wayland,
        """    waylandState.xdgSurface->setConfigure([this](CCXdgSurface* r, uint32_t serial) {
        backend->backend->log(AQ_LOG_DEBUG, std::format("Output {}: configure surface with {}", name, serial));
        r->sendAckConfigure(serial);
    });""",
        """    waylandState.xdgSurface->setConfigure([this](CCXdgSurface* r, uint32_t serial) {
        backend->backend->log(AQ_LOG_DEBUG, std::format("Output {}: configure surface with {}", name, serial));
        r->sendAckConfigure(serial);

        // Retain the acknowledged size for consumers that attach their
        // listeners later.
        if (modes.empty())
            modes.emplace_back(makeShared<SOutputMode>(SOutputMode{.refreshRate = 60000, .preferred = true}));
        modes.front()->pixelSize = waylandState.pendingSize;
        applyConfigure();
    });""",
    )
    patch(
        wayland,
        """        events.state.emit(SStateEvent{.size = {w, h}});
        // Kick off the first frame synchronously: the consumer expects events.frame in
        // the same dispatch cycle as the toplevel configure. Deferring via scheduleFrame's
        // idle races the first commit and can leave the output blank until the next event.
        needsFrame = true;
        sched.frameReady.emit();""",
        """        // The following xdg_surface.configure completes and acknowledges this size.
        waylandState.pendingSize = {w, h};""",
    )
    # 0.15.1 announces the output from an idle callback; 0.16 defers it to
    # the configure. Accept either starting point and end in the same place.
    if "Start the configure handshake even when there is no other host traffic." not in wayland.read_text():
      patch(
        wayland,
        """    o->self = o;
    if (backend->ready)
        o->swapchain = CSwapchain::create(backend->primaryAllocator, self.lock());
    idleCallbacks.emplace_back([this, o]() { backend->events.newOutput.emit(SP<IOutput>(o)); });""",
        """    o->self = o;
    if (backend->ready)
        o->swapchain = CSwapchain::create(backend->primaryAllocator, self.lock());
    // Announcement happens on the first xdg_surface.configure, once the
    // parent has given us a real size. See applyConfigure().""",
    )
    patch(
        wayland,
        """    o->self = o;
    if (backend->ready)
        o->swapchain = CSwapchain::create(backend->primaryAllocator, self.lock());
    // Announcement happens on the first xdg_surface.configure, once the
    // parent has given us a real size. See applyConfigure().""",
        """    o->self = o;
    if (backend->ready)
        o->swapchain = CSwapchain::create(backend->primaryAllocator, self.lock());
    // Start the configure handshake even when there is no other host traffic.""",
      )
    if "void Aquamarine::CWaylandOutput::applyConfigure()" not in wayland.read_text():
            patch(
                wayland,
                """Aquamarine::CWaylandOutput::~CWaylandOutput() {""",
            """void Aquamarine::CWaylandOutput::applyConfigure() {
        if (!backend->backend->ready || !swapchain || modes.empty())
            return;

        // Signal handlers may destroy the output. Keep it alive and stop notifying it
        // if it is removed from the backend during an announcement or state change.
        const auto OUTPUT = self.lock();
        const auto ACTIVE = [&]() { return std::ranges::find(backend->outputs, OUTPUT) != backend->outputs.end(); };
        if (!ACTIVE())
            return;

        if (!waylandState.announced) {
            waylandState.announced = true;
            backend->backend->events.newOutput.emit(SP<IOutput>(OUTPUT));
            if (!ACTIVE())
                return;
        }

        events.state.emit(SStateEvent{.size = modes.front()->pixelSize});
        if (!ACTIVE())
            return;

        needsFrame = true;
        sched.frameReady.emit();
}

Aquamarine::CWaylandOutput::~CWaylandOutput() {""",
        )


def patch_hyprland(root: pathlib.Path) -> None:
    patch(
        root / "src/render/OpenGL.hpp",
        "        void                             initEGL(bool gbm);",
        "        void                             initEGL(bool gbm, bool surfaceless = false);",
    )

    if "presentToShm" not in (root / "src/render/Renderbuffer.hpp").read_text():
        patch(
            root / "src/render/Renderbuffer.hpp",
            '''        virtual void            bind()   = 0;
        virtual void            unbind() = 0;''',
            '''        virtual void            bind()   = 0;
        virtual void            unbind() = 0;

        // Copy the rendered frame into the backing shm buffer, if this
        // renderbuffer wraps a wl_shm buffer. No-op for dmabuf buffers.
        virtual void            presentToShm() {}''',
        )

    if "presentToShm() override" not in (root / "src/render/gl/GLRenderbuffer.hpp").read_text():
            patch(
                root / "src/render/gl/GLRenderbuffer.hpp",
                '''        void bind() override;
        void unbind() override;

      private:
        void*  m_image = nullptr;
        GLuint m_rbo   = 0;''',
            '''        void bind() override;
        void unbind() override;
        void presentToShm() override;

      private:
        void*  m_image = nullptr;
        GLuint m_rbo   = 0;
        bool   m_shm   = false;''',
    )

    patch(
        root / "src/render/gl/GLRenderbuffer.cpp",
        '''CGLRenderbuffer::CGLRenderbuffer(SP<Aquamarine::IBuffer> buffer, uint32_t format) : IRenderbuffer(buffer, format) {
    auto dma = buffer->dmabuf();

    m_image = g_pHyprOpenGL->createEGLImage(dma);
    if (m_image == EGL_NO_IMAGE_KHR) {
        Log::logger->log(Log::ERR, "rb: createEGLImage failed");
        return;
    }

    glGenRenderbuffers(1, &m_rbo);
    glBindRenderbuffer(GL_RENDERBUFFER, m_rbo);
    g_pHyprOpenGL->m_proc.glEGLImageTargetRenderbufferStorageOES(GL_RENDERBUFFER, m_image);
    glBindRenderbuffer(GL_RENDERBUFFER, 0);

    m_framebuffer = makeShared<CGLFramebuffer>();
    glGenFramebuffers(1, &GLFB(m_framebuffer)->m_fb);
    GLFB(m_framebuffer)->m_fbAllocated = true;
    m_framebuffer->m_size              = buffer->size;
    m_framebuffer->m_drmFormat         = dma.format;''',
        '''CGLRenderbuffer::CGLRenderbuffer(SP<Aquamarine::IBuffer> buffer, uint32_t format) : IRenderbuffer(buffer, format) {
    auto       dma = buffer->dmabuf();
    const auto SHM = buffer->shm();

    m_shm = SHM.success;

    if (!m_shm) {
        m_image = g_pHyprOpenGL->createEGLImage(dma);
        if (m_image == EGL_NO_IMAGE_KHR) {
            Log::logger->log(Log::ERR, "rb: createEGLImage failed");
            return;
        }
    }

    glGenRenderbuffers(1, &m_rbo);
    glBindRenderbuffer(GL_RENDERBUFFER, m_rbo);

    if (m_shm)
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, (int)buffer->size.x, (int)buffer->size.y);
    else
        g_pHyprOpenGL->m_proc.glEGLImageTargetRenderbufferStorageOES(GL_RENDERBUFFER, m_image);

    glBindRenderbuffer(GL_RENDERBUFFER, 0);

    m_framebuffer = makeShared<CGLFramebuffer>();
    glGenFramebuffers(1, &GLFB(m_framebuffer)->m_fb);
    GLFB(m_framebuffer)->m_fbAllocated = true;
    m_framebuffer->m_size              = buffer->size;
    m_framebuffer->m_drmFormat         = m_shm ? SHM.format : dma.format;''',
    )

    if "void CGLRenderbuffer::presentToShm()" not in (root / "src/render/gl/GLRenderbuffer.cpp").read_text():
            patch(
                root / "src/render/gl/GLRenderbuffer.cpp",
                '''void CGLRenderbuffer::unbind() {
    GLFB(m_framebuffer)->unbind();
}''',
            '''void CGLRenderbuffer::unbind() {
    GLFB(m_framebuffer)->unbind();
}

void CGLRenderbuffer::presentToShm() {
    if (!m_shm || !m_hlBuffer)
            return;

    const auto BUFFER = m_hlBuffer.lock();
    if (!BUFFER)
            return;

    const auto ATTRS = BUFFER->shm();
    if (!ATTRS.success || ATTRS.fd < 0)
            return;

    auto [data, fmt, len] = BUFFER->beginDataPtr(0);
    if (!data || len == 0)
            return;

    const int W = (int)ATTRS.size.x, H = (int)ATTRS.size.y;
    if (W <= 0 || H <= 0 || ATTRS.stride <= 0)
            return;

    g_pHyprOpenGL->makeEGLCurrent();

    m_framebuffer->bind();
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);

    // GL reads bottom-up and gives RGBA; wl_shm wants top-down BGRA in the
    // DRM_FORMAT_XRGB8888/ARGB8888 layout. Flip and swap red/blue while
    // copying into the memfd.
    const size_t ROW = (size_t)W * 4;
    std::vector<uint8_t> scratch(ROW * (size_t)H);
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, scratch.data());

    for (int y = 0; y < H; ++y) {
            const uint8_t* src = scratch.data() + (size_t)(H - 1 - y) * ROW;
            uint8_t*       dst = data + (size_t)y * (size_t)ATTRS.stride;

            for (int x = 0; x < W; ++x) {
                dst[x * 4 + 0] = src[x * 4 + 2];
                dst[x * 4 + 1] = src[x * 4 + 1];
                dst[x * 4 + 2] = src[x * 4 + 0];
                dst[x * 4 + 3] = src[x * 4 + 3];
            }
    }

    GLFB(m_framebuffer)->unbind();
    glFlush();
}''',
    )

    if "#include <vector>" not in (root / "src/render/gl/GLRenderbuffer.cpp").read_text():
        patch(
            root / "src/render/gl/GLRenderbuffer.cpp",
            "#include <dlfcn.h>",
            "#include <dlfcn.h>\n#include <vector>\n#include <cstring>",
        )

    patch(
        root / "src/render/OpenGL.cpp",
        "void CHyprOpenGLImpl::initEGL(bool gbm) {",
        "void CHyprOpenGLImpl::initEGL(bool gbm, bool surfaceless) {",
    )

    patch(
        root / "src/render/OpenGL.cpp",
        "    m_eglDisplay = m_proc.eglGetPlatformDisplayEXT(gbm ? EGL_PLATFORM_GBM_KHR : EGL_PLATFORM_DEVICE_EXT, gbm ? m_gbmDevice : m_eglDevice, attrs.data());",
        '''    if (surfaceless)
        m_eglDisplay = m_proc.eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, attrs.data());
    else
        m_eglDisplay = m_proc.eglGetPlatformDisplayEXT(gbm ? EGL_PLATFORM_GBM_KHR : EGL_PLATFORM_DEVICE_EXT, gbm ? m_gbmDevice : m_eglDevice, attrs.data());''',
    )

    patch(
        root / "src/render/OpenGL.cpp",
        '''    bool success = false;
    if (EGLEXTENSIONS.contains("EXT_platform_device") || !m_proc.eglQueryDevicesEXT || !m_proc.eglQueryDeviceStringEXT) {
        m_eglDevice = eglDeviceFromDRMFD(m_drmFD);''',
        '''    bool success = false;

    if (m_drmFD < 0) {
        // Nested Wayland / headless: there is no DRM node to open. Render on
        // the surfaceless Mesa platform; output buffers are wl_shm memfds.
        RASSERT(EGLEXTENSIONS.contains("EGL_MESA_platform_surfaceless"), "EGL: no DRM node and EGL_MESA_platform_surfaceless is missing");
        success = true;
        initEGL(false, true);
    } else if (EGLEXTENSIONS.contains("EXT_platform_device") || !m_proc.eglQueryDevicesEXT || !m_proc.eglQueryDeviceStringEXT) {
        m_eglDevice = eglDeviceFromDRMFD(m_drmFD);''',
    )

    patch(
        root / "src/render/OpenGL.cpp",
        '''        blend(true);

        g_pHyprRenderer->m_renderData.useNearestNeighbor = false;''',
        '''        blend(true);

        // shm output: copy the finished frame back into the memfd buffer.
        if (auto* const GLRENDERER = dc<CHyprGLRenderer*>(g_pHyprRenderer.get()); GLRENDERER && GLRENDERER->m_currentRenderbuffer)
            GLRENDERER->m_currentRenderbuffer->presentToShm();

        g_pHyprRenderer->m_renderData.useNearestNeighbor = false;''',
    )

    patch(
        root / "src/render/Renderer.cpp",
        '''bool IHyprRenderer::isSoftware() {
    return m_software;
}''',
        '''bool IHyprRenderer::isSoftware() {
    if (!m_software && Render::GL::g_pHyprOpenGL) {
        // No DRM node means the DRM-driver probe above never ran. Ask GL.
        const auto RENDERER = rc<const char*>(glGetString(GL_RENDERER));
        if (RENDERER) {
            const std::string NAME = RENDERER;
            if (NAME.contains("llvmpipe") || NAME.contains("softpipe") || NAME.contains("Software Rasterizer"))
                m_software = true;
        }
    }

    return m_software;
}''',
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    patch_aquamarine(pathlib.Path(sys.argv[1]))
    patch_wayland_binds(pathlib.Path(sys.argv[1]))
    patch_wayland_output_announce(pathlib.Path(sys.argv[1]))
    patch_hyprland(pathlib.Path(sys.argv[2]))
    print("shm patches applied")


if __name__ == "__main__":
    main()
