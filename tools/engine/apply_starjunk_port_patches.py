#!/usr/bin/env python3
"""Apply the minimal Starjunk compatibility layer to the pinned WebGPU candidate.

These are forward-port shims, not gameplay changes. Every replacement fails
closed when its expected source snippet changes so upstream drift is visible.
"""

from __future__ import annotations

import sys
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one patch anchor, found {count}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_starjunk_port_patches.py GODOT_SOURCE")
    source = Path(sys.argv[1]).resolve()

    header = source / "drivers/webgpu/rendering_device_driver_webgpu.h"
    device_implementation = source / "drivers/webgpu/rendering_device_driver_webgpu.cpp"
    context_implementation = source / "drivers/webgpu/rendering_context_driver_webgpu.cpp"
    platform_header = source / "drivers/webgpu/webgpu_platform.h"

    replace_once(
        header,
        """\tvirtual DataFormat swap_chain_get_format(SwapChainID p_swap_chain) override final;
\tvirtual ColorSpace swap_chain_get_color_space(SwapChainID p_swap_chain) override final;
\tvirtual void swap_chain_free(SwapChainID p_swap_chain) override final;
""",
        """\tvirtual DataFormat swap_chain_get_format(SwapChainID p_swap_chain) override final;
\tvirtual ColorSpace swap_chain_get_color_space(SwapChainID p_swap_chain) override final;
\tvirtual bool swap_chain_get_hdr_output_supported(SwapChainID p_swap_chain) override final;
\tvirtual void swap_chain_free(SwapChainID p_swap_chain) override final;
""",
    )

    replace_once(
        device_implementation,
        """RenderingDeviceDriver::ColorSpace RenderingDeviceDriverWebGpu::swap_chain_get_color_space(SwapChainID p_swap_chain) {
\t// TODO: Look into this.
\treturn ColorSpace::COLOR_SPACE_REC709_NONLINEAR_SRGB;
\t;
}

void RenderingDeviceDriverWebGpu::swap_chain_free(SwapChainID p_swap_chain) {
""",
        """RenderingDeviceDriver::ColorSpace RenderingDeviceDriverWebGpu::swap_chain_get_color_space(SwapChainID p_swap_chain) {
\t// TODO: Look into this.
\treturn ColorSpace::COLOR_SPACE_REC709_NONLINEAR_SRGB;
\t;
}

bool RenderingDeviceDriverWebGpu::swap_chain_get_hdr_output_supported(SwapChainID p_swap_chain) {
\t// The current browser surface path is SDR-only. Keep this conservative
\t// until HDR canvas/surface negotiation is explicitly implemented.
\treturn false;
}

void RenderingDeviceDriverWebGpu::swap_chain_free(SwapChainID p_swap_chain) {
""",
    )

    replace_once(
        platform_header,
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP) || defined(WEBGPU_BACKEND_EMDAWN)
#include <webgpu/webgpu.h>
#endif

#endif
""",
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP) || defined(WEBGPU_BACKEND_EMDAWN)
#include <webgpu/webgpu.h>
#endif

#ifdef WEBGPU_BACKEND_EMDAWN
#include <emscripten.h>

// Emdawn's timed/infinite WaitAny path suspends Wasm through Asyncify. That
// path can throw an uncaught "unwind" promise in browser execution. Polling
// with timeout 0 does not suspend inside WebGPU; emscripten_sleep(0) yields
// explicitly so browser promises can resolve before the next poll.
static inline WGPUWaitStatus starjunk_webgpu_emdawn_wait_future(
        WGPUInstance p_instance,
        WGPUFuture p_future,
        double p_timeout_ms = 30000.0) {
    WGPUFutureWaitInfo wait_info = { .future = p_future, .completed = false };
    const double deadline_ms = emscripten_get_now() + p_timeout_ms;
    WGPUWaitStatus wait_status = wgpuInstanceWaitAny(p_instance, 1, &wait_info, 0);
    while (wait_status != WGPUWaitStatus_Success && emscripten_get_now() < deadline_ms) {
        emscripten_sleep(0);
        wait_info.completed = false;
        wait_status = wgpuInstanceWaitAny(p_instance, 1, &wait_info, 0);
    }
    return wait_status;
}
#endif

#endif
""",
    )

    replace_once(
        device_implementation,
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP) || defined(WEBGPU_BACKEND_EMDAWN)
\t\tWGPUFeatureName_TextureFormatsTier1,
\t\tWGPUFeatureName_TextureFormatsTier2,
\t\tWGPUFeatureName_Subgroups,
\t\tWGPUFeatureName_TextureComponentSwizzle,
#elif defined(WEBGPU_BACKEND_WGPU_DESKTOP)
""",
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP)
\t\tWGPUFeatureName_TextureFormatsTier1,
\t\tWGPUFeatureName_TextureFormatsTier2,
\t\tWGPUFeatureName_Subgroups,
\t\tWGPUFeatureName_TextureComponentSwizzle,
#elif defined(WEBGPU_BACKEND_EMDAWN)
\t\t// Browser WebGPU must not request Dawn-native/experimental extensions
\t\t// that the adapter does not advertise. Chromium rejected device
\t\t// creation when texture-formats-tier1 was a hard requirement.
#elif defined(WEBGPU_BACKEND_WGPU_DESKTOP)
""",
    )

    replace_once(
        context_implementation,
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP) || defined(WEBGPU_BACKEND_EMDAWN)
\tstatic const WGPUInstanceFeatureName required_features[] = { WGPUInstanceFeatureName_TimedWaitAny };
#endif
""",
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP)
\tstatic const WGPUInstanceFeatureName required_features[] = { WGPUInstanceFeatureName_TimedWaitAny };
#endif
""",
    )

    replace_once(
        context_implementation,
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP) || defined(WEBGPU_BACKEND_EMDAWN)
\tinstance_descriptor.requiredFeatureCount = sizeof(required_features) / sizeof(WGPUInstanceFeatureName);
\tinstance_descriptor.requiredFeatures = required_features;
#endif
""",
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP)
\tinstance_descriptor.requiredFeatureCount = sizeof(required_features) / sizeof(WGPUInstanceFeatureName);
\tinstance_descriptor.requiredFeatures = required_features;
#endif
""",
    )

    replace_once(
        context_implementation,
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP) || defined(WEBGPU_BACKEND_EMDAWN)
\tWGPUFutureWaitInfo wait_infos[] = {
\t\t{ .future = high_power_future, .completed = false },
\t\t{ .future = low_power_future, .completed = false },
\t};
\tfor (WGPUFutureWaitInfo &wait_info : wait_infos) {
\t\tWGPUWaitStatus wait_status = wgpuInstanceWaitAny(instance, 1, &wait_info, UINT64_MAX);
\t\tERR_FAIL_COND_V_MSG(wait_status != WGPUWaitStatus_Success, ERR_CANT_CREATE,
\t\t\t\t"Failed to wait on WebGPU adapter request.");
\t}
#elif defined(WEBGPU_BACKEND_WGPU_DESKTOP)
""",
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP)
\tWGPUFutureWaitInfo wait_infos[] = {
\t\t{ .future = high_power_future, .completed = false },
\t\t{ .future = low_power_future, .completed = false },
\t};
\tfor (WGPUFutureWaitInfo &wait_info : wait_infos) {
\t\tWGPUWaitStatus wait_status = wgpuInstanceWaitAny(instance, 1, &wait_info, UINT64_MAX);
\t\tERR_FAIL_COND_V_MSG(wait_status != WGPUWaitStatus_Success, ERR_CANT_CREATE,
\t\t\t\t"Failed to wait on WebGPU adapter request.");
\t}
#elif defined(WEBGPU_BACKEND_EMDAWN)
\tWGPUWaitStatus high_power_status = starjunk_webgpu_emdawn_wait_future(instance, high_power_future);
\tERR_FAIL_COND_V_MSG(high_power_status != WGPUWaitStatus_Success, ERR_CANT_CREATE,
\t\t\t"Failed to wait on high-power WebGPU adapter request.");
\tWGPUWaitStatus low_power_status = starjunk_webgpu_emdawn_wait_future(instance, low_power_future);
\tERR_FAIL_COND_V_MSG(low_power_status != WGPUWaitStatus_Success, ERR_CANT_CREATE,
\t\t\t"Failed to wait on low-power WebGPU adapter request.");
#elif defined(WEBGPU_BACKEND_WGPU_DESKTOP)
""",
    )

    replace_once(
        device_implementation,
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP) || defined(WEBGPU_BACKEND_EMDAWN)
\tWGPUFutureWaitInfo wait_info = { .future = device_future, .completed = false };
\tWGPUWaitStatus wait_status = wgpuInstanceWaitAny(context_driver->instance_get(), 1, &wait_info, UINT64_MAX);
\tERR_FAIL_COND_V_MSG(wait_status != WGPUWaitStatus_Success, FAILED,
\t\t\t"Failed to wait on WebGPU device request.");
#elif defined(WEBGPU_BACKEND_WGPU_DESKTOP)
""",
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP)
\tWGPUFutureWaitInfo wait_info = { .future = device_future, .completed = false };
\tWGPUWaitStatus wait_status = wgpuInstanceWaitAny(context_driver->instance_get(), 1, &wait_info, UINT64_MAX);
\tERR_FAIL_COND_V_MSG(wait_status != WGPUWaitStatus_Success, FAILED,
\t\t\t"Failed to wait on WebGPU device request.");
#elif defined(WEBGPU_BACKEND_EMDAWN)
\tWGPUWaitStatus wait_status = starjunk_webgpu_emdawn_wait_future(context_driver->instance_get(), device_future);
\tERR_FAIL_COND_V_MSG(wait_status != WGPUWaitStatus_Success, FAILED,
\t\t\t"Failed to wait on WebGPU device request.");
#elif defined(WEBGPU_BACKEND_WGPU_DESKTOP)
""",
    )

    replace_once(
        device_implementation,
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP) || defined(WEBGPU_BACKEND_EMDAWN)
\t\t\tWGPUFutureWaitInfo wait_info = { .future = future, .completed = false };
\t\t\twgpuInstanceWaitAny(context_driver->instance_get(), 1, &wait_info, UINT64_MAX);
#elif defined(WEBGPU_BACKEND_WGPU_DESKTOP)
""",
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP)
\t\t\tWGPUFutureWaitInfo wait_info = { .future = future, .completed = false };
\t\t\twgpuInstanceWaitAny(context_driver->instance_get(), 1, &wait_info, UINT64_MAX);
#elif defined(WEBGPU_BACKEND_EMDAWN)
\t\t\tWGPUWaitStatus wait_status = starjunk_webgpu_emdawn_wait_future(context_driver->instance_get(), future);
\t\t\tERR_FAIL_COND_V_MSG(wait_status != WGPUWaitStatus_Success, nullptr,
\t\t\t\t\t"Failed to wait for WebGPU buffer mapping.");
#elif defined(WEBGPU_BACKEND_WGPU_DESKTOP)
""",
    )

    print("Applied Starjunk WebGPU 4.7 compatibility patches")


if __name__ == "__main__":
    main()
