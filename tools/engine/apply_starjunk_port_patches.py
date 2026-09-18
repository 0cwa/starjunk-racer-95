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
    implementation = source / "drivers/webgpu/rendering_device_driver_webgpu.cpp"

    replace_once(
        header,
        """	virtual DataFormat swap_chain_get_format(SwapChainID p_swap_chain) override final;
	virtual ColorSpace swap_chain_get_color_space(SwapChainID p_swap_chain) override final;
	virtual void swap_chain_free(SwapChainID p_swap_chain) override final;
""",
        """	virtual DataFormat swap_chain_get_format(SwapChainID p_swap_chain) override final;
	virtual ColorSpace swap_chain_get_color_space(SwapChainID p_swap_chain) override final;
	virtual bool swap_chain_get_hdr_output_supported(SwapChainID p_swap_chain) override final;
	virtual void swap_chain_free(SwapChainID p_swap_chain) override final;
""",
    )

    replace_once(
        implementation,
        """RenderingDeviceDriver::ColorSpace RenderingDeviceDriverWebGpu::swap_chain_get_color_space(SwapChainID p_swap_chain) {
	// TODO: Look into this.
	return ColorSpace::COLOR_SPACE_REC709_NONLINEAR_SRGB;
	;
}

void RenderingDeviceDriverWebGpu::swap_chain_free(SwapChainID p_swap_chain) {
""",
        """RenderingDeviceDriver::ColorSpace RenderingDeviceDriverWebGpu::swap_chain_get_color_space(SwapChainID p_swap_chain) {
	// TODO: Look into this.
	return ColorSpace::COLOR_SPACE_REC709_NONLINEAR_SRGB;
	;
}

bool RenderingDeviceDriverWebGpu::swap_chain_get_hdr_output_supported(SwapChainID p_swap_chain) {
	// The current browser surface path is SDR-only. Keep this conservative
	// until HDR canvas/surface negotiation is explicitly implemented.
	return false;
}

void RenderingDeviceDriverWebGpu::swap_chain_free(SwapChainID p_swap_chain) {
""",
    )

    print("Applied Starjunk WebGPU 4.7 compatibility patches")


if __name__ == "__main__":
    main()
