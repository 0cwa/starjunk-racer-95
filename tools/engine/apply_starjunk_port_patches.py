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
    shader_container_implementation = source / "drivers/webgpu/rendering_shader_container_webgpu.cpp"
    translate_implementation = source / "drivers/webgpu/webgpu_translate.cpp"
    context_implementation = source / "drivers/webgpu/rendering_context_driver_webgpu.cpp"
    platform_header = source / "drivers/webgpu/webgpu_platform.h"
    main_implementation = source / "main/main.cpp"
    forward_mobile_implementation = source / "servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp"
    forward_mobile_shader_include = source / "servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile_inc.glsl"

    replace_once(
        device_implementation,
        """static constexpr uint32_t UNIFORM_DYN_MASK = (1u << UNIFORM_DYN_BITS) - 1u;
""",
        """static constexpr uint32_t UNIFORM_DYN_MASK = (1u << UNIFORM_DYN_BITS) - 1u;


static WGPUTextureFormat starjunk_webgpu_storage_format(
		WGPUTextureFormat p_format,
		bool p_has_texture_formats_tier1) {
	switch (p_format) {
		case WGPUTextureFormat_R8Unorm:
		case WGPUTextureFormat_R8Snorm:
			return p_has_texture_formats_tier1 ? p_format : WGPUTextureFormat_R32Float;
		case WGPUTextureFormat_R8Uint:
			return p_has_texture_formats_tier1 ? p_format : WGPUTextureFormat_R32Uint;
		case WGPUTextureFormat_R8Sint:
			return p_has_texture_formats_tier1 ? p_format : WGPUTextureFormat_R32Sint;
		case WGPUTextureFormat_RG8Unorm:
		case WGPUTextureFormat_RG8Snorm:
			return p_has_texture_formats_tier1 ? p_format : WGPUTextureFormat_RG32Float;
		case WGPUTextureFormat_RG8Uint:
			return p_has_texture_formats_tier1 ? p_format : WGPUTextureFormat_RG32Uint;
		case WGPUTextureFormat_RG8Sint:
			return p_has_texture_formats_tier1 ? p_format : WGPUTextureFormat_RG32Sint;
		case WGPUTextureFormat_R16Unorm:
		case WGPUTextureFormat_R16Snorm:
		case WGPUTextureFormat_R16Float:
			return WGPUTextureFormat_R32Float;
		case WGPUTextureFormat_R16Uint:
			return WGPUTextureFormat_R32Uint;
		case WGPUTextureFormat_R16Sint:
			return WGPUTextureFormat_R32Sint;
		case WGPUTextureFormat_RG16Unorm:
		case WGPUTextureFormat_RG16Snorm:
		case WGPUTextureFormat_RG16Float:
			return WGPUTextureFormat_RG32Float;
		case WGPUTextureFormat_RG16Uint:
			return WGPUTextureFormat_RG32Uint;
		case WGPUTextureFormat_RG16Sint:
			return WGPUTextureFormat_RG32Sint;
		case WGPUTextureFormat_RGBA16Unorm:
		case WGPUTextureFormat_RGBA16Snorm:
			return WGPUTextureFormat_RGBA16Float;
		default:
			return p_format;
	}
}
""",
    )

    replace_once(
        forward_mobile_implementation,
        """\tbool using_subpass_post_process = true; // If true: we can do our post processing in a subpass
""",
        """\t// The bridge WebGPU backend does not implement render subpasses: its
\t// command_next_render_subpass() is a no-op and render_pass_create() ignores
\t// subpass descriptions. Use Forward Mobile's existing separate post-pass
\t// path until the full WebGPU subpass emulation from the polished reference
\t// is forward-ported.
\tbool using_subpass_post_process =
\t\t\tRD::get_singleton()->get_device_capabilities().device_family != RDD::DEVICE_WEBGPU;
""",
    )

    replace_once(
        forward_mobile_implementation,
        """\t\t//lightmaps
\t\tscene_state.max_lightmaps = MAX_LIGHTMAPS;
\t\tdefines += "\\n#define MAX_LIGHTMAP_TEXTURES " + itos(scene_state.max_lightmaps) + "\\n";
""",
        """\t\t// The bridge WebGPU shader transform expands binding arrays into one
\t\t// binding per element. Chromium SwiftShader exposes only 16 sampled
\t\t// textures per stage, while the normal Mobile lightmap array alone is
\t\t// MAX_LIGHTMAPS * 2 (lightmap + shadowmask). Keep one active lightmap
\t\t// on this bridge path until the polished backend's binding-array
\t\t// flattening is forward-ported.
\t\tscene_state.max_lightmaps =
\t\t\t\tRD::get_singleton()->get_device_capabilities().device_family == RDD::DEVICE_WEBGPU ? 1 : MAX_LIGHTMAPS;
\t\tdefines += "\\n#define MAX_LIGHTMAP_TEXTURES " + itos(scene_state.max_lightmaps) + "\\n";
""",
    )

    replace_once(
        main_implementation,
        """		GLOBAL_DEF_RST(PropertyInfo(Variant::STRING, "rendering/rendering_device/driver.macos", PROPERTY_HINT_ENUM, "metal,vulkan"), "metal");

		GLOBAL_DEF_RST("rendering/rendering_device/fallback_to_vulkan", true);
""",
        """		GLOBAL_DEF_RST(PropertyInfo(Variant::STRING, "rendering/rendering_device/driver.macos", PROPERTY_HINT_ENUM, "metal,vulkan"), "metal");
		GLOBAL_DEF_RST(PropertyInfo(Variant::STRING, "rendering/rendering_device/driver.web", PROPERTY_HINT_ENUM, "webgpu"), "webgpu");

		GLOBAL_DEF_RST("rendering/rendering_device/fallback_to_vulkan", true);
""",
    )

    replace_once(
        main_implementation,
        """	GLOBAL_DEF_RST_BASIC(PropertyInfo(Variant::STRING, "rendering/renderer/rendering_method.web", PROPERTY_HINT_ENUM, "gl_compatibility"), "gl_compatibility"); // This is a bit of a hack until we have WebGPU support.
""",
        """	GLOBAL_DEF_RST_BASIC(PropertyInfo(Variant::STRING, "rendering/renderer/rendering_method.web", PROPERTY_HINT_ENUM, "forward_plus,mobile,gl_compatibility"), "gl_compatibility"); // WebGPU enables RD renderers on Web while retaining compatibility as the default.
""",
    )

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
        shader_container_implementation,
        """static const char WEBGPU_WGSL_PRELUDE[] =
\t\t"enable subgroups;\\n"
\t\t"diagnostic(off, derivative_uniformity);\\n"
\t\t"diagnostic(off, subgroup_uniformity);\\n";
""",
        """#if defined(WEBGPU_BACKEND_DAWN_DESKTOP)
static const char WEBGPU_WGSL_PRELUDE[] =
\t\t"enable subgroups;\\n"
\t\t"diagnostic(off, derivative_uniformity);\\n"
\t\t"diagnostic(off, subgroup_uniformity);\\n";
#else
// Browser WebGPU only permits the subgroups WGSL extension when the device
// explicitly enables the corresponding adapter feature. The Emdawn path does
// not request that optional feature, so do not make every shader depend on it.
static const char WEBGPU_WGSL_PRELUDE[] =
\t\t"diagnostic(off, derivative_uniformity);\\n";
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
        device_implementation,
        """\tWGPULimits required_limits = WGPU_LIMITS_INIT;
\trequired_limits.maxBindGroups = WEBGPU_MAX_BIND_GROUPS;
\t// required_limits.maxImmediateSize = WEBGPU_MAX_IMMEDIATE_SIZE;
\trequired_limits.maxImmediateSize = 64;
\trequired_limits.maxSampledTexturesPerShaderStage = 48;
\trequired_limits.maxStorageBuffersPerShaderStage = 12;
\trequired_limits.maxStorageTexturesPerShaderStage = 8;
""",
        """\tWGPULimits required_limits = WGPU_LIMITS_INIT;
\trequired_limits.maxBindGroups = WEBGPU_MAX_BIND_GROUPS;
\t// required_limits.maxImmediateSize = WEBGPU_MAX_IMMEDIATE_SIZE;
\trequired_limits.maxImmediateSize = 64;
#if defined(WEBGPU_BACKEND_EMDAWN)
\t// Browser adapters may expose only the WebGPU baseline per-stage limits.
\t// Ask for the fork's preferred limits only when the adapter actually
\t// supports them; later renderer/shader gates will reveal whether lower
\t// limits need architectural handling rather than making device creation
\t// impossible up front.
\tWGPULimits adapter_limits = WGPU_LIMITS_INIT;
\tWGPUStatus adapter_limits_status = wgpuAdapterGetLimits(adapter, &adapter_limits);
\tERR_FAIL_COND_V_MSG(adapter_limits_status != WGPUStatus_Success, FAILED,
\t\t\t"Failed to query WebGPU adapter limits.");
\trequired_limits.maxSampledTexturesPerShaderStage =
\t\t\tMIN((uint32_t)48, adapter_limits.maxSampledTexturesPerShaderStage);
\trequired_limits.maxStorageBuffersPerShaderStage =
\t\t\tMIN((uint32_t)12, adapter_limits.maxStorageBuffersPerShaderStage);
\trequired_limits.maxStorageTexturesPerShaderStage =
\t\t\tMIN((uint32_t)8, adapter_limits.maxStorageTexturesPerShaderStage);
#else
\trequired_limits.maxSampledTexturesPerShaderStage = 48;
\trequired_limits.maxStorageBuffersPerShaderStage = 12;
\trequired_limits.maxStorageTexturesPerShaderStage = 8;
#endif
""",
    )

    replace_once(
        device_implementation,
        """uint64_t RenderingDeviceDriverWebGpu::limit_get(Limit p_limit) {
\tWGPULimits limits = (WGPULimits){};

#ifdef WEBGPU_BACKEND_WGPU_DESKTOP
\tWGPUNativeLimits extras;
\tlimits.nextInChain = &extras.chain;
#endif

\twgpuDeviceGetLimits(device, &limits);
\treturn rd_limit_from_webgpu(p_limit, limits);
}
""",
        """uint64_t RenderingDeviceDriverWebGpu::limit_get(Limit p_limit) {
\tWGPULimits limits = (WGPULimits){};

#ifdef WEBGPU_BACKEND_WGPU_DESKTOP
\tWGPUNativeLimits extras;
\tlimits.nextInChain = &extras.chain;
#endif

\twgpuDeviceGetLimits(device, &limits);
#if defined(WEBGPU_BACKEND_EMDAWN)
\t// Browser WebGPU must expose the limits of the device we actually
\t// requested, not the bridge's historical UINT64_MAX placeholders.
\t// Renderer feature selection relies on these values to avoid generating
\t// resource layouts the adapter cannot validate.
\tswitch (p_limit) {
\t\tcase LIMIT_MAX_TEXTURES_PER_UNIFORM_SET:
\t\t\treturn limits.maxSampledTexturesPerShaderStage;
\t\tcase LIMIT_MAX_SAMPLERS_PER_UNIFORM_SET:
\t\t\treturn limits.maxSamplersPerShaderStage;
\t\tcase LIMIT_MAX_STORAGE_BUFFERS_PER_UNIFORM_SET:
\t\t\treturn limits.maxStorageBuffersPerShaderStage;
\t\tcase LIMIT_MAX_STORAGE_IMAGES_PER_UNIFORM_SET:
\t\t\treturn limits.maxStorageTexturesPerShaderStage;
\t\tcase LIMIT_SUBGROUP_SIZE:
\t\tcase LIMIT_SUBGROUP_MIN_SIZE:
\t\tcase LIMIT_SUBGROUP_MAX_SIZE:
\t\tcase LIMIT_SUBGROUP_IN_SHADERS:
\t\tcase LIMIT_SUBGROUP_OPERATIONS:
\t\t\treturn 0;
\t\tdefault:
\t\t\tbreak;
\t}
#endif
\treturn rd_limit_from_webgpu(p_limit, limits);
}
""",
    )

    replace_once(
        device_implementation,
        """BitField<RenderingDeviceDriver::TextureUsageBits> RenderingDeviceDriverWebGpu::texture_get_usages_supported_by_format(DataFormat p_format, bool p_cpu_readable) {
	for (WGPUTextureFormat format : WEBGPU_CORE_SUPPORTED_FORMATS) {
		if (webgpu_texture_format_from_rd(p_format) == format) {
			// TODO: Read this https://www.w3.org/TR/webgpu/#texture-format-caps
			BitField<RDD::TextureUsageBits> supported = INT64_MAX;
			return supported;
		}
	}

	return 0;
}
""",
        """BitField<RenderingDeviceDriver::TextureUsageBits> RenderingDeviceDriverWebGpu::texture_get_usages_supported_by_format(DataFormat p_format, bool p_cpu_readable) {
	for (WGPUTextureFormat format : WEBGPU_CORE_SUPPORTED_FORMATS) {
		if (webgpu_texture_format_from_rd(p_format) == format) {
			BitField<RDD::TextureUsageBits> supported = INT64_MAX;
#if defined(WEBGPU_BACKEND_EMDAWN)
			// The bridge implementation used to claim every core WebGPU format
			// supported every texture usage. Forward Mobile relies on this query
			// to choose its raster fallbacks. In particular, A2B10G10R10 is a
			// color target on WebGPU but not a storage texture, so claiming storage
			// support incorrectly enables the octmap compute path and produces
			// invalid RGB10A2 storage bindings in Chromium.
			bool storage_supported = false;
			switch (p_format) {
				case DATA_FORMAT_R8_UNORM:
				case DATA_FORMAT_R8_SNORM:
				case DATA_FORMAT_R8_UINT:
				case DATA_FORMAT_R8_SINT:
				case DATA_FORMAT_R8G8_UNORM:
				case DATA_FORMAT_R8G8_SNORM:
				case DATA_FORMAT_R8G8_UINT:
				case DATA_FORMAT_R8G8_SINT:
				case DATA_FORMAT_R8G8B8A8_UNORM:
				case DATA_FORMAT_R8G8B8A8_SNORM:
				case DATA_FORMAT_R8G8B8A8_UINT:
				case DATA_FORMAT_R8G8B8A8_SINT:
				case DATA_FORMAT_R16_UNORM:
				case DATA_FORMAT_R16_SNORM:
				case DATA_FORMAT_R16_SFLOAT:
				case DATA_FORMAT_R16_UINT:
				case DATA_FORMAT_R16_SINT:
				case DATA_FORMAT_R16G16_UNORM:
				case DATA_FORMAT_R16G16_SNORM:
				case DATA_FORMAT_R16G16_SFLOAT:
				case DATA_FORMAT_R16G16_UINT:
				case DATA_FORMAT_R16G16_SINT:
				case DATA_FORMAT_R16G16B16A16_UNORM:
				case DATA_FORMAT_R16G16B16A16_SNORM:
				case DATA_FORMAT_R16G16B16A16_SFLOAT:
				case DATA_FORMAT_R16G16B16A16_UINT:
				case DATA_FORMAT_R16G16B16A16_SINT:
				case DATA_FORMAT_R32_SFLOAT:
				case DATA_FORMAT_R32_UINT:
				case DATA_FORMAT_R32_SINT:
				case DATA_FORMAT_R32G32_SFLOAT:
				case DATA_FORMAT_R32G32_UINT:
				case DATA_FORMAT_R32G32_SINT:
				case DATA_FORMAT_R32G32B32A32_SFLOAT:
				case DATA_FORMAT_R32G32B32A32_UINT:
				case DATA_FORMAT_R32G32B32A32_SINT:
					storage_supported = true;
					break;
				default:
					break;
			}
			if (!storage_supported) {
				supported.clear_flag(TEXTURE_USAGE_STORAGE_BIT);
				supported.clear_flag(TEXTURE_USAGE_STORAGE_ATOMIC_BIT);
			}
#endif
			return supported;
		}
	}

	return 0;
}
""",
    )

    replace_once(
        device_implementation,
        """	WGPUTextureFormat texture_format = webgpu_texture_format_from_rd(p_format.format);
	WGPUTextureFormat view_format = webgpu_texture_format_from_rd(p_view.format);
	WGPUTextureUsage usage = (WGPUTextureUsage)usage_bits;
	WGPUTextureAspect aspect = webgpu_texture_aspect_from_rd_format(p_format.format);
""",
        """	WGPUTextureFormat texture_format = webgpu_texture_format_from_rd(p_format.format);
	WGPUTextureFormat view_format = webgpu_texture_format_from_rd(p_view.format);
#if defined(WEBGPU_BACKEND_EMDAWN)
	if (p_format.usage_bits & TEXTURE_USAGE_STORAGE_BIT) {
		const bool has_texture_formats_tier1 =
				wgpuDeviceHasFeature(device, WGPUFeatureName_TextureFormatsTier1);
		texture_format = starjunk_webgpu_storage_format(
				texture_format, has_texture_formats_tier1);
		view_format = starjunk_webgpu_storage_format(
				view_format, has_texture_formats_tier1);
	}
#endif
	WGPUTextureUsage usage = (WGPUTextureUsage)usage_bits;
	WGPUTextureAspect aspect = webgpu_texture_aspect_from_rd_format(p_format.format);
""",
    )

    replace_once(
        device_implementation,
        """	for (uint32_t i = 0; i < p_format.shareable_formats.size(); i++) {
		DataFormat format = p_format.shareable_formats[i];
		view_formats.push_back(webgpu_texture_format_from_rd(format));
	}
	view_formats.push_back(view_format);
""",
        """	for (uint32_t i = 0; i < p_format.shareable_formats.size(); i++) {
		DataFormat format = p_format.shareable_formats[i];
		WGPUTextureFormat shareable_format = webgpu_texture_format_from_rd(format);
#if defined(WEBGPU_BACKEND_EMDAWN)
		if (p_format.usage_bits & TEXTURE_USAGE_STORAGE_BIT) {
			shareable_format = starjunk_webgpu_storage_format(
					shareable_format,
					wgpuDeviceHasFeature(device, WGPUFeatureName_TextureFormatsTier1));
		}
#endif
		view_formats.push_back(shareable_format);
	}
	view_formats.push_back(view_format);
""",
    )

    replace_once(
        device_implementation,
        """					layout_entry.storageTexture = (WGPUStorageTextureBindingLayout){
						.access = access,
						.format = webgpu_texture_format_from_rd(info.image_format),
						.viewDimension = viewDimension,
					};
""",
        """					WGPUTextureFormat storage_format =
							webgpu_texture_format_from_rd(info.image_format);
#if defined(WEBGPU_BACKEND_EMDAWN)
					storage_format = starjunk_webgpu_storage_format(
							storage_format,
							wgpuDeviceHasFeature(device, WGPUFeatureName_TextureFormatsTier1));
#endif
					layout_entry.storageTexture = (WGPUStorageTextureBindingLayout){
						.access = access,
						.format = storage_format,
						.viewDimension = viewDimension,
					};
""",
    )

    replace_once(
        device_implementation,
        """		ERR_FAIL_COND_V_MSG(!ok, ShaderID(), vformat("Failed to decompress WGSL on shader stage %s.", String(SHADER_STAGE_NAMES[shader.shader_stage])));

		WGPUShaderSourceWGSL source = (WGPUShaderSourceWGSL){
""",
        """		ERR_FAIL_COND_V_MSG(!ok, ShaderID(), vformat("Failed to decompress WGSL on shader stage %s.", String(SHADER_STAGE_NAMES[shader.shader_stage])));

		const char *wgsl_source_data = (const char *)decompressed_code.ptr();
		size_t wgsl_source_length = source_size;
		String starjunk_wgsl;
		CharString starjunk_wgsl_utf8;
#if defined(WEBGPU_BACKEND_EMDAWN)
		starjunk_wgsl = String::utf8((const char *)decompressed_code.ptr(), source_size);
		const bool has_texture_formats_tier1 =
				wgpuDeviceHasFeature(device, WGPUFeatureName_TextureFormatsTier1);
		if (!has_texture_formats_tier1) {
			starjunk_wgsl = starjunk_wgsl.replace("rg8unorm", "rg32float");
			starjunk_wgsl = starjunk_wgsl.replace("rg8snorm", "rg32float");
			starjunk_wgsl = starjunk_wgsl.replace("rg8uint", "rg32uint");
			starjunk_wgsl = starjunk_wgsl.replace("rg8sint", "rg32sint");
			starjunk_wgsl = starjunk_wgsl.replace("r8unorm", "r32float");
			starjunk_wgsl = starjunk_wgsl.replace("r8snorm", "r32float");
			starjunk_wgsl = starjunk_wgsl.replace("r8uint", "r32uint");
			starjunk_wgsl = starjunk_wgsl.replace("r8sint", "r32sint");
		}
		starjunk_wgsl = starjunk_wgsl.replace("rgba16snorm", "rgba16float");
		starjunk_wgsl = starjunk_wgsl.replace("rgba16unorm", "rgba16float");
		starjunk_wgsl = starjunk_wgsl.replace("rg16float", "rg32float");
		starjunk_wgsl = starjunk_wgsl.replace("rg16snorm", "rg32float");
		starjunk_wgsl = starjunk_wgsl.replace("rg16unorm", "rg32float");
		starjunk_wgsl = starjunk_wgsl.replace("rg16uint", "rg32uint");
		starjunk_wgsl = starjunk_wgsl.replace("rg16sint", "rg32sint");
		starjunk_wgsl = starjunk_wgsl.replace("r16float", "r32float");
		starjunk_wgsl = starjunk_wgsl.replace("r16snorm", "r32float");
		starjunk_wgsl = starjunk_wgsl.replace("r16unorm", "r32float");
		starjunk_wgsl = starjunk_wgsl.replace("r16uint", "r32uint");
		starjunk_wgsl = starjunk_wgsl.replace("r16sint", "r32sint");
		starjunk_wgsl_utf8 = starjunk_wgsl.utf8();
		wgsl_source_data = starjunk_wgsl_utf8.get_data();
		wgsl_source_length = (size_t)starjunk_wgsl_utf8.length();
#endif

		WGPUShaderSourceWGSL source = (WGPUShaderSourceWGSL){
""",
    )

    replace_once(
        device_implementation,
        """			.code = (WGPUStringView){
					.data = (const char *)decompressed_code.ptr(),
					.length = source_size,
			},
		};

		shader_info->shader_contents.push_back(String((const char *)decompressed_code.ptr()));
""",
        """			.code = (WGPUStringView){
					.data = wgsl_source_data,
					.length = wgsl_source_length,
			},
		};

#if defined(WEBGPU_BACKEND_EMDAWN)
		shader_info->shader_contents.push_back(starjunk_wgsl);
#else
		shader_info->shader_contents.push_back(String((const char *)decompressed_code.ptr()));
#endif
""",
    )

    replace_once(
        device_implementation,
        """\t\t\t\tdefault: {
\t\t\t\t\tmemdelete(shader_info);
\t\t\t\t\tDEV_ASSERT(false);
\t\t\t\t\treturn ShaderID();
\t\t\t\t}
""",
        """\t\t\t\tdefault: {
\t\t\t\t\tconst UniformType unsupported_type = corrected_binding.original_type;
\t\t\t\t\tconst String unsupported_shader_name = shader_info->shader_name;
\t\t\t\t\tmemdelete(shader_info);
\t\t\t\t\tERR_FAIL_V_MSG(ShaderID(), vformat(
\t\t\t\t\t\t\t"WebGpu shader %s uses unsupported uniform type %d at set %d binding %d.",
\t\t\t\t\t\t\tunsupported_shader_name, unsupported_type, set_idx, corrected_binding.corrected_binding_idx));
\t\t\t\t}
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


    # The legacy bridge intentionally refused CubeToDp and Bokeh DOF before
    # attempting translation. The polished WebGPU reference has no such shader
    # exclusions, and Godot eagerly initializes raster Bokeh on Mobile even
    # when a scene does not enable DOF. Let both shaders flow through the normal
    # transform/translator path so unsupported constructs fail with actionable
    # diagnostics rather than leaving permanently null pipelines.
    replace_once(
        shader_container_implementation,
        """\t\t"BokehDofRasterShaderRD:0",
\t\t"CubeToDpShaderRD:0",

\t\t// HACK: Requires vertex writable storage.
""",
        """\t\t// HACK: Requires vertex writable storage.
""",
    )

    # Browser WebGPU exposes texture-component-swizzle as an optional feature.
    # Keep the browser device portable by requesting it only when advertised.
    replace_once(
        device_implementation,
        """\tWGPULimits required_limits = WGPU_LIMITS_INIT;
""",
        """#if defined(WEBGPU_BACKEND_EMDAWN)
\tVector<WGPUFeatureName> starjunk_required_features;
\tfor (WGPUFeatureName feature : required_features) {
\t\tstarjunk_required_features.push_back(feature);
\t}
\tif (wgpuAdapterHasFeature(adapter, WGPUFeatureName_TextureComponentSwizzle)) {
\t\tstarjunk_required_features.push_back(WGPUFeatureName_TextureComponentSwizzle);
\t}
#endif

\tWGPULimits required_limits = WGPU_LIMITS_INIT;
""",
    )

    replace_once(
        device_implementation,
        """\tWGPUDeviceDescriptor device_desc = (WGPUDeviceDescriptor){
\t\t.requiredFeatureCount = sizeof(required_features) / sizeof(WGPUFeatureName),
\t\t.requiredFeatures = required_features,
\t\t.requiredLimits = &required_limits,
""",
        """\tWGPUDeviceDescriptor device_desc = (WGPUDeviceDescriptor){
#if defined(WEBGPU_BACKEND_EMDAWN)
\t\t.requiredFeatureCount = (size_t)starjunk_required_features.size(),
\t\t.requiredFeatures = starjunk_required_features.ptr(),
#else
\t\t.requiredFeatureCount = sizeof(required_features) / sizeof(WGPUFeatureName),
\t\t.requiredFeatures = required_features,
#endif
\t\t.requiredLimits = &required_limits,
""",
    )

    # The bridge chained the optional swizzle descriptor onto every view,
    # including identity RGBA render targets. Only chain it when the feature
    # was enabled. If a browser lacks the feature, identity views remain valid
    # while a genuinely swizzled view fails explicitly rather than rendering
    # incorrect channels.
    replace_once(
        device_implementation,
        """\tWGPUTextureViewDescriptor texture_view_desc = (WGPUTextureViewDescriptor){
\t\t.nextInChain = (WGPUChainedStruct *)&texture_view_desc_extras,
\t\t.format = view_format,
\t\t.dimension = view_dimension,
""",
        """\tWGPUChainedStruct *starjunk_texture_view_next = (WGPUChainedStruct *)&texture_view_desc_extras;
#if defined(WEBGPU_BACKEND_EMDAWN)
\tif (!wgpuDeviceHasFeature(device, WGPUFeatureName_TextureComponentSwizzle)) {
\t\tconst bool identity_swizzle =
\t\t\t\tp_view.swizzle_r == TEXTURE_SWIZZLE_R &&
\t\t\t\tp_view.swizzle_g == TEXTURE_SWIZZLE_G &&
\t\t\t\tp_view.swizzle_b == TEXTURE_SWIZZLE_B &&
\t\t\t\tp_view.swizzle_a == TEXTURE_SWIZZLE_A;
\t\tERR_FAIL_COND_V_MSG(!identity_swizzle, TextureID(),
\t\t\t\t"Browser WebGPU adapter does not support required texture component swizzle.");
\t\tstarjunk_texture_view_next = nullptr;
\t}
#endif
\tWGPUTextureViewDescriptor texture_view_desc = (WGPUTextureViewDescriptor){
\t\t.nextInChain = starjunk_texture_view_next,
\t\t.format = view_format,
\t\t.dimension = view_dimension,
""",
    )

    replace_once(
        device_implementation,
        """\tWGPUTextureViewDescriptor texture_view_desc = (WGPUTextureViewDescriptor){
\t\t.nextInChain = (WGPUChainedStruct *)&texture_view_desc_extras,
\t\t.format = webgpu_texture_format_from_rd(p_view.format),
\t\t.mipLevelCount = texture_info->texture_view_desc.mipLevelCount,
""",
        """\tWGPUChainedStruct *starjunk_texture_view_next = (WGPUChainedStruct *)&texture_view_desc_extras;
#if defined(WEBGPU_BACKEND_EMDAWN)
\tif (!wgpuDeviceHasFeature(device, WGPUFeatureName_TextureComponentSwizzle)) {
\t\tconst bool identity_swizzle =
\t\t\t\tp_view.swizzle_r == TEXTURE_SWIZZLE_R &&
\t\t\t\tp_view.swizzle_g == TEXTURE_SWIZZLE_G &&
\t\t\t\tp_view.swizzle_b == TEXTURE_SWIZZLE_B &&
\t\t\t\tp_view.swizzle_a == TEXTURE_SWIZZLE_A;
\t\tERR_FAIL_COND_V_MSG(!identity_swizzle, TextureID(),
\t\t\t\t"Browser WebGPU adapter does not support required texture component swizzle.");
\t\tstarjunk_texture_view_next = nullptr;
\t}
#endif
\tWGPUTextureViewDescriptor texture_view_desc = (WGPUTextureViewDescriptor){
\t\t.nextInChain = starjunk_texture_view_next,
\t\t.format = webgpu_texture_format_from_rd(p_view.format),
\t\t.mipLevelCount = texture_info->texture_view_desc.mipLevelCount,
""",
    )

    replace_once(
        device_implementation,
        """\tWGPUTextureFormat view_format = webgpu_texture_format_from_rd(p_view.format);
\tWGPUTextureAspect aspect = webgpu_texture_aspect_from_rd_format(p_view.format);
\tWGPUTextureViewDescriptor texture_view_desc = (WGPUTextureViewDescriptor){
\t\t.nextInChain = (WGPUChainedStruct *)&texture_view_desc_extras,
\t\t.format = view_format,
\t\t.dimension = texture_info->texture_view_desc.dimension,
""",
        """\tWGPUTextureFormat view_format = webgpu_texture_format_from_rd(p_view.format);
\tWGPUTextureAspect aspect = webgpu_texture_aspect_from_rd_format(p_view.format);
\tWGPUChainedStruct *starjunk_texture_view_next = (WGPUChainedStruct *)&texture_view_desc_extras;
#if defined(WEBGPU_BACKEND_EMDAWN)
\tif (!wgpuDeviceHasFeature(device, WGPUFeatureName_TextureComponentSwizzle)) {
\t\tconst bool identity_swizzle =
\t\t\t\tp_view.swizzle_r == TEXTURE_SWIZZLE_R &&
\t\t\t\tp_view.swizzle_g == TEXTURE_SWIZZLE_G &&
\t\t\t\tp_view.swizzle_b == TEXTURE_SWIZZLE_B &&
\t\t\t\tp_view.swizzle_a == TEXTURE_SWIZZLE_A;
\t\tERR_FAIL_COND_V_MSG(!identity_swizzle, TextureID(),
\t\t\t\t"Browser WebGPU adapter does not support required texture component swizzle.");
\t\tstarjunk_texture_view_next = nullptr;
\t}
#endif
\tWGPUTextureViewDescriptor texture_view_desc = (WGPUTextureViewDescriptor){
\t\t.nextInChain = starjunk_texture_view_next,
\t\t.format = view_format,
\t\t.dimension = texture_info->texture_view_desc.dimension,
""",
    )

    # Surface capability formats are ordered by preference. The bridge used to
    # keep overwriting its selection and therefore picked the last supported
    # format, which forces Chromium/Emdawn to insert an avoidable canvas copy.
    replace_once(
        context_implementation,
        """\t// Godot only supports these swapchain formats.
\tfor (uint32_t i = 0; i < capabilities.formatCount; i++) {
\t\tWGPUTextureFormat format = capabilities.formats[i];
\t\tswitch (format) {
\t\t\tcase WGPUTextureFormat_BGRA8Unorm:
\t\t\t\tthis->format = format;
\t\t\t\tthis->rd_format = RDD::DATA_FORMAT_B8G8R8A8_UNORM;
\t\t\t\tbreak;
\t\t\tcase WGPUTextureFormat_RGBA8Unorm:
\t\t\t\tthis->format = format;
\t\t\t\tthis->rd_format = RDD::DATA_FORMAT_R8G8B8A8_UNORM;
\t\t\t\tbreak;
\t\t\tdefault:
\t\t\t\tbreak;
\t\t}
\t}

\t// TODO: Complete full surface config.
""",
        """\t// Surface formats are ordered by preference. Select the first format
\t// Godot supports instead of accidentally retaining the last one.
\tbool found_surface_format = false;
\tfor (uint32_t i = 0; i < capabilities.formatCount && !found_surface_format; i++) {
\t\tWGPUTextureFormat format = capabilities.formats[i];
\t\tswitch (format) {
\t\t\tcase WGPUTextureFormat_BGRA8Unorm:
\t\t\t\tthis->format = format;
\t\t\t\tthis->rd_format = RDD::DATA_FORMAT_B8G8R8A8_UNORM;
\t\t\t\tfound_surface_format = true;
\t\t\t\tbreak;
\t\t\tcase WGPUTextureFormat_RGBA8Unorm:
\t\t\t\tthis->format = format;
\t\t\t\tthis->rd_format = RDD::DATA_FORMAT_R8G8B8A8_UNORM;
\t\t\t\tfound_surface_format = true;
\t\t\t\tbreak;
\t\t\tdefault:
\t\t\t\tbreak;
\t\t}
\t}
\twgpuSurfaceCapabilitiesFreeMembers(capabilities);
\tERR_FAIL_COND_MSG(!found_surface_format, "WebGPU surface exposes no Godot-supported color format.");

\t// TODO: Complete full surface config.
""",
    )

    # Promote the translator's named failure to a renderer error. The bridge
    # previously used print_line(), which our browser artifact intentionally
    # truncates as ordinary console noise, leaving only Godot's generic
    # "Failed to compile code to native for SPIR-V" downstream error.
    replace_once(
        shader_container_implementation,
        """\t\tif (result.error_string != nullptr) {
\t\t\tprint_line("[WGPU] WGSL compilation ", shader_name_str, "on step", (int)result.failure_stage, ":", result.error_string.ptr());
\t\t\treturn false;
\t\t}
""",
        """\t\tif (result.error_string != nullptr) {
\t\t\tERR_PRINT(vformat(
\t\t\t\t\t"WebGPU WGSL translation failed for %s stage %s at translator step %d: %s",
\t\t\t\t\tshader_name_str,
\t\t\t\t\tString(RenderingDeviceCommons::SHADER_STAGE_NAMES[patched[i].shader_stage]),
\t\t\t\t\t(int)result.failure_stage,
\t\t\t\t\tString::utf8(result.error_string.ptr())));
\t\t\treturn false;
\t\t}
""",
    )

    # Preserve translator failure stage for front-end and validation failures.
    # The bridge only populated failure_stage for WGSL back-end failures, which
    # makes earlier failures appear as NONE/0 in diagnostics.
    replace_once(
        translate_implementation,
        """\tif (!success) {
\t\treturn (ConvertResult){
\t\t\t.wgsl_string = nullptr,
\t\t\t.error_string = strdup(front_result.fmt_error),
\t\t};
\t}
""",
        """\tif (!success) {
\t\treturn (ConvertResult){
\t\t\t.wgsl_string = nullptr,
\t\t\t.error_string = strdup(front_result.fmt_error),
\t\t\t.failure_stage = stage,
\t\t};
\t}
""",
    )

    replace_once(
        translate_implementation,
        """\tif (!success) {
\t\treturn (ConvertResult){
\t\t\t.wgsl_string = nullptr,
\t\t\t.error_string = strdup(valid_result.fmt_error),
\t\t};
\t}
""",
        """\tif (!success) {
\t\treturn (ConvertResult){
\t\t\t.wgsl_string = nullptr,
\t\t\t.error_string = strdup(valid_result.fmt_error),
\t\t\t.failure_stage = stage,
\t\t};
\t}
""",
    )

    # Diagnose which legacy SPIR-V transform first makes the known failing
    # Forward Mobile / SMAA shaders unacceptable to Naga. This does not alter
    # shader output: snapshots are translated only after the normal final
    # translation has already failed.
    replace_once(
        shader_container_implementation,
        """\tpatched.resize(p_spirv.size());
\tcorrection_maps.resize(p_spirv.size());

\tconst uint32_t immediates_set = MIN((uint32_t)p_shader.uniform_sets.size(), (uint32_t)(WEBGPU_MAX_BIND_GROUPS - 1));
""",
        """\tpatched.resize(p_spirv.size());
\tcorrection_maps.resize(p_spirv.size());

\tstruct StarjunkTransformProbe {
\t\tString name;
\t\tVector<uint8_t> spirv;
\t};
\tconst bool starjunk_probe_shader =
\t\t\tshader_name_str.contains("SceneForwardMobileShaderRD") ||
\t\t\tshader_name_str.contains("Smaa");
\tVector<Vector<StarjunkTransformProbe>> starjunk_transform_probes;
\tif (starjunk_probe_shader) {
\t\tstarjunk_transform_probes.resize(p_spirv.size());
\t}
\tauto starjunk_capture_probe = [&](uint32_t p_stage_index, const char *p_name, const uint32_t *p_words, uint32_t p_word_count) {
\t\tif (!starjunk_probe_shader || p_stage_index >= (uint32_t)starjunk_transform_probes.size() || p_words == nullptr || p_word_count == 0) {
\t\t\treturn;
\t\t}
\t\tStarjunkTransformProbe probe;
\t\tprobe.name = p_name;
\t\tprobe.spirv.resize((int64_t)p_word_count * sizeof(uint32_t));
\t\tmemcpy(probe.spirv.ptrw(), p_words, probe.spirv.size());
\t\tstarjunk_transform_probes.write[p_stage_index].push_back(probe);
\t};

\tconst uint32_t immediates_set = MIN((uint32_t)p_shader.uniform_sets.size(), (uint32_t)(WEBGPU_MAX_BIND_GROUPS - 1));
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tmemcpy(in_spirv.ptrw(), stage_spirv.ptr(), stage_spirv.size() * sizeof(uint32_t));

#ifdef DEBUG_SHADERS
""",
        """\t\tmemcpy(in_spirv.ptrw(), stage_spirv.ptr(), stage_spirv.size() * sizeof(uint32_t));
\t\tstarjunk_capture_probe(i, "raw", in_spirv.ptr(), in_spirv.size());

#ifdef DEBUG_SHADERS
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tspirv_webgpu_transform_combimgsampsplitter_alloc(in_spirv.ptrw(), in_spirv.size(), &combimg_out_spv, &combimg_out_count, &map);

\t\tuint32_t *dref_out_spv = nullptr;
""",
        """\t\tspirv_webgpu_transform_combimgsampsplitter_alloc(in_spirv.ptrw(), in_spirv.size(), &combimg_out_spv, &combimg_out_count, &map);
\t\tstarjunk_capture_probe(i, "split_combined", combimg_out_spv, combimg_out_count);

\t\tuint32_t *dref_out_spv = nullptr;
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tspirv_webgpu_transform_drefsplitter_alloc(combimg_out_spv, combimg_out_count, &dref_out_spv, &dref_out_count, &map);

\t\tuint32_t *isnanisinf_out_spv = nullptr;
""",
        """\t\tspirv_webgpu_transform_drefsplitter_alloc(combimg_out_spv, combimg_out_count, &dref_out_spv, &dref_out_count, &map);
\t\tstarjunk_capture_probe(i, "split_dref", dref_out_spv, dref_out_count);

\t\tuint32_t *isnanisinf_out_spv = nullptr;
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tspirv_webgpu_transform_isnanisinfpatch_alloc(dref_out_spv, dref_out_count, &isnanisinf_out_spv, &isnanisinf_out_count);

\t\tuint32_t *storagecube_out_spv = nullptr;
""",
        """\t\tspirv_webgpu_transform_isnanisinfpatch_alloc(dref_out_spv, dref_out_count, &isnanisinf_out_spv, &isnanisinf_out_count);
\t\tstarjunk_capture_probe(i, "isnan_isinf", isnanisinf_out_spv, isnanisinf_out_count);

\t\tuint32_t *storagecube_out_spv = nullptr;
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tspirv_webgpu_transform_storagecubepatch_alloc(isnanisinf_out_spv, isnanisinf_out_count, &storagecube_out_spv, &storagecube_out_count, &map);

\t\tuint32_t *immediates_out_spv = nullptr;
""",
        """\t\tspirv_webgpu_transform_storagecubepatch_alloc(isnanisinf_out_spv, isnanisinf_out_count, &storagecube_out_spv, &storagecube_out_count, &map);
\t\tstarjunk_capture_probe(i, "storage_cube", storagecube_out_spv, storagecube_out_count);

\t\tuint32_t *immediates_out_spv = nullptr;
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tspirv_webgpu_transform_immediatespatch_alloc(storagecube_out_spv, storagecube_out_count, &immediates_out_spv, &immediates_out_count, &map);

\t\tuint32_t *bindingarray_out_spv = nullptr;
""",
        """\t\tspirv_webgpu_transform_immediatespatch_alloc(storagecube_out_spv, storagecube_out_count, &immediates_out_spv, &immediates_out_count, &map);
\t\tstarjunk_capture_probe(i, "immediates", immediates_out_spv, immediates_out_count);

\t\tuint32_t *bindingarray_out_spv = nullptr;
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tspirv_webgpu_transform_splitbindingarray_alloc(immediates_out_spv, immediates_out_count, &bindingarray_out_spv, &bindingarray_out_count, &map);

\t\tuint32_t *pruneunuseddref_out_spv = nullptr;
""",
        """\t\tspirv_webgpu_transform_splitbindingarray_alloc(immediates_out_spv, immediates_out_count, &bindingarray_out_spv, &bindingarray_out_count, &map);
\t\tstarjunk_capture_probe(i, "split_binding_array", bindingarray_out_spv, bindingarray_out_count);

\t\tuint32_t *pruneunuseddref_out_spv = nullptr;
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tspirv_webgpu_transform_pruneunuseddref_alloc(bindingarray_out_spv, bindingarray_out_count, &pruneunuseddref_out_spv, &pruneunuseddref_out_count);

\t\tVector<uint8_t> out_spirv;
""",
        """\t\tspirv_webgpu_transform_pruneunuseddref_alloc(bindingarray_out_spv, bindingarray_out_count, &pruneunuseddref_out_spv, &pruneunuseddref_out_count);
\t\tstarjunk_capture_probe(i, "prune_unused_dref", pruneunuseddref_out_spv, pruneunuseddref_out_count);

\t\tVector<uint8_t> out_spirv;
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tright_spirv.resize(out_right_spirv_count * sizeof(uint32_t));
\t\tmemcpy(right_spirv.ptrw(), out_right_spirv, right_spirv.size());

\t\t// Right is always right! (Right is the fragment shader which is typically chonkier but this doesn't matter.)
""",
        """\t\tright_spirv.resize(out_right_spirv_count * sizeof(uint32_t));
\t\tmemcpy(right_spirv.ptrw(), out_right_spirv, right_spirv.size());
\t\tstarjunk_capture_probe(0, "mirror_patch", (const uint32_t *)left_spirv.ptr(), left_spirv.size() / sizeof(uint32_t));
\t\tstarjunk_capture_probe(1, "mirror_patch", (const uint32_t *)right_spirv.ptr(), right_spirv.size() / sizeof(uint32_t));

\t\t// Right is always right!
""",
    )

    replace_once(
        shader_container_implementation,
        """\t\tif (result.error_string != nullptr) {
\t\t\tERR_PRINT(vformat(
\t\t\t\t\t"WebGPU WGSL translation failed for %s stage %s at translator step %d: %s",
\t\t\t\t\tshader_name_str,
\t\t\t\t\tString(RenderingDeviceCommons::SHADER_STAGE_NAMES[patched[i].shader_stage]),
\t\t\t\t\t(int)result.failure_stage,
\t\t\t\t\tString::utf8(result.error_string.ptr())));
\t\t\treturn false;
\t\t}
""",
        """\t\tif (result.error_string != nullptr) {
\t\t\tERR_PRINT(vformat(
\t\t\t\t\t"WebGPU WGSL translation failed for %s stage %s at translator step %d: %s",
\t\t\t\t\tshader_name_str,
\t\t\t\t\tString(RenderingDeviceCommons::SHADER_STAGE_NAMES[patched[i].shader_stage]),
\t\t\t\t\t(int)result.failure_stage,
\t\t\t\t\tString::utf8(result.error_string.ptr())));
\t\t\tif (starjunk_probe_shader && i < starjunk_transform_probes.size()) {
\t\t\t\tfor (const StarjunkTransformProbe &probe : starjunk_transform_probes[i]) {
\t\t\t\t\tConvertResult probe_result = webgpu_translate_spirv_to_wgsl(
\t\t\t\t\t\t\t(const uint32_t *)probe.spirv.ptr(),
\t\t\t\t\t\t\tprobe.spirv.size() / sizeof(uint32_t));
\t\t\t\t\tif (probe_result.error_string != nullptr) {
\t\t\t\t\t\tERR_PRINT(vformat(
\t\t\t\t\t\t\t\t"WebGPU transform probe FAIL for %s stage %s after %s at translator step %d: %s",
\t\t\t\t\t\t\t\tshader_name_str,
\t\t\t\t\t\t\t\tString(RenderingDeviceCommons::SHADER_STAGE_NAMES[patched[i].shader_stage]),
\t\t\t\t\t\t\t\tprobe.name,
\t\t\t\t\t\t\t\t(int)probe_result.failure_stage,
\t\t\t\t\t\t\t\tString::utf8(probe_result.error_string.ptr())));
\t\t\t\t\t} else {
\t\t\t\t\t\tERR_PRINT(vformat(
\t\t\t\t\t\t\t\t"WebGPU transform probe PASS for %s stage %s after %s",
\t\t\t\t\t\t\t\tshader_name_str,
\t\t\t\t\t\t\t\tString(RenderingDeviceCommons::SHADER_STAGE_NAMES[patched[i].shader_stage]),
\t\t\t\t\t\t\t\tprobe.name));
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t\t\treturn false;
\t\t}
""",
    )

    # Godot 4.7 glslang emits newer SPIR-V operations that the pinned legacy
    # Naga frontend does not handle. The polished WebGPU backend rewrites these
    # two operations before translation; forward-port the same compatibility
    # shim here without changing descriptor/binding semantics.
    replace_once(
        translate_implementation,
        """ConvertResult webgpu_translate_spirv_to_wgsl(const uint32_t *spv, uint32_t spv_count) {
\tuint8_t success;
""",
        """static Vector<uint32_t> starjunk_webgpu_preprocess_modern_spirv(const uint32_t *p_spv, uint32_t p_spv_count) {
\tVector<uint32_t> out;
\tout.resize(p_spv_count);
\tif (p_spv_count > 0) {
\t\tmemcpy(out.ptrw(), p_spv, (size_t)p_spv_count * sizeof(uint32_t));
\t}
\tif (p_spv_count < 5) {
\t\treturn out;
\t}

\tstatic constexpr uint16_t SPV_OP_COPY_OBJECT = 83;
\tstatic constexpr uint16_t SPV_OP_KILL = 252;
\tstatic constexpr uint16_t SPV_OP_COPY_LOGICAL = 400;
\tstatic constexpr uint16_t SPV_OP_TERMINATE_INVOCATION = 4416;

\tuint32_t pos = 5;
\twhile (pos < p_spv_count) {
\t\tuint32_t word0 = out[pos];
\t\tuint32_t word_count = word0 >> 16;
\t\tuint16_t opcode = (uint16_t)(word0 & 0xFFFF);
\t\tif (word_count == 0 || pos + word_count > p_spv_count) {
\t\t\tbreak;
\t\t}
\t\tif (opcode == SPV_OP_COPY_LOGICAL) {
\t\t\tout.write[pos] = (word_count << 16) | SPV_OP_COPY_OBJECT;
\t\t} else if (opcode == SPV_OP_TERMINATE_INVOCATION) {
\t\t\tout.write[pos] = (word_count << 16) | SPV_OP_KILL;
\t\t}
\t\tpos += word_count;
\t}
\treturn out;
}

ConvertResult webgpu_translate_spirv_to_wgsl(const uint32_t *spv, uint32_t spv_count) {
\tVector<uint32_t> starjunk_preprocessed_spirv = starjunk_webgpu_preprocess_modern_spirv(spv, spv_count);
\tspv = starjunk_preprocessed_spirv.ptr();
\tspv_count = starjunk_preprocessed_spirv.size();

\tuint8_t success;
""",
    )

    replace_once(
        shader_container_implementation,
        """#include "core/error/error_macros.h"
#include "core/io/marshalls.h"
""",
        """#include "core/error/error_macros.h"
#include "core/crypto/crypto_core.h"
#include "core/io/marshalls.h"
""",
    )

    # Emit exact failing SPIR-V bytes through structured console chunks so the
    # browser harness can reconstruct real .spv artifacts for spirv-val /
    # disassembly. This runs only after translation has already failed and does
    # not alter shader code or renderer behavior.
    replace_once(
        shader_container_implementation,
        """\t\tif (result.error_string != nullptr) {
\t\t\tERR_PRINT(vformat(
\t\t\t\t\t"WebGPU WGSL translation failed for %s stage %s at translator step %d: %s",
""",
        """\t\tif (result.error_string != nullptr) {
\t\t\tauto starjunk_emit_spirv_dump = [&](const char *p_kind, const uint8_t *p_bytes, size_t p_size) {
\t\t\t\tif (!starjunk_probe_shader || p_bytes == nullptr || p_size == 0) {
\t\t\t\t\treturn;
\t\t\t\t}
\t\t\t\tString encoded = CryptoCore::b64_encode_str(p_bytes, p_size);
\t\t\t\tstatic constexpr int64_t STARJUNK_DUMP_CHUNK = 12000;
\t\t\t\tint64_t chunk_count = (encoded.length() + STARJUNK_DUMP_CHUNK - 1) / STARJUNK_DUMP_CHUNK;\n\t\t\t\tif (chunk_count < 1) {\n\t\t\t\t\tchunk_count = 1;\n\t\t\t\t}
\t\t\t\tfor (int64_t chunk_index = 0; chunk_index < chunk_count; chunk_index++) {
\t\t\t\t\tprint_line(
\t\t\t\t\t\t\t"STARJUNK_SPIRV_DUMP:",
\t\t\t\t\t\t\tshader_name_str, "|",
\t\t\t\t\t\t\titos((int)patched[i].shader_stage), "|",
\t\t\t\t\t\t\tp_kind, "|",
\t\t\t\t\t\t\titos(chunk_index), "|",
\t\t\t\t\t\t\titos(chunk_count), "|",
\t\t\t\t\t\t\tencoded.substr(chunk_index * STARJUNK_DUMP_CHUNK, STARJUNK_DUMP_CHUNK));
\t\t\t\t}
\t\t\t};
\t\t\tSpan<uint32_t> starjunk_raw_stage = p_spirv[i].spirv();
\t\t\tstarjunk_emit_spirv_dump(
\t\t\t\t\t"raw",
\t\t\t\t\t(const uint8_t *)starjunk_raw_stage.ptr(),
\t\t\t\t\tstarjunk_raw_stage.size() * sizeof(uint32_t));
\t\t\tstarjunk_emit_spirv_dump("final", spv_bytes.ptr(), spv_bytes.size());

\t\t\tERR_PRINT(vformat(
\t\t\t\t\t"WebGPU WGSL translation failed for %s stage %s at translator step %d: %s",
""",
    )

    # shader_count_for() only packs NONE/SINGLE/MULTIPLE (0/1/2), but the
    # GLSL helper has no syntactic fallback for the unused 2-bit value 3.
    # Vulkan accepts the resulting OpUndef return path; the pinned legacy Naga
    # validator rejects the otherwise-valid helper. Give the unreachable state
    # deterministic NONE semantics so WebGPU translation has total control flow.
    replace_once(
        forward_mobile_shader_include,
        """uint option_to_count(uint option, uint bound) {
\tswitch (option) {
\t\tcase SHADER_COUNT_NONE:
\t\t\treturn 0;
\t\tcase SHADER_COUNT_SINGLE:
\t\t\treturn 1;
\t\tcase SHADER_COUNT_MULTIPLE:
\t\t\treturn bound;
\t}
}
""",
        """uint option_to_count(uint option, uint bound) {
\tswitch (option) {
\t\tcase SHADER_COUNT_NONE:
\t\t\treturn 0;
\t\tcase SHADER_COUNT_SINGLE:
\t\t\treturn 1;
\t\tcase SHADER_COUNT_MULTIPLE:
\t\t\treturn bound;
\t}
\t// The C++ specialization packer only emits values 0..2. Keep the unused
\t// value deterministic for WebGPU translators that require total returns.
\treturn 0;
}
""",
    )


    # The legacy backend stores persistent dynamic-buffer frames contiguously at
    # the logical slice size. WebGPU dynamic uniform/storage offsets must be
    # 256-byte aligned, so sizes such as 2848 produce invalid offsets (5696 for
    # frame 2). Preserve the logical binding size but use an aligned frame stride.
    replace_once(
        device_implementation,
        """\tconst uint64_t slice_size = p_size;
\tconst uint64_t alloc_size = is_dynamic ? slice_size * frame_count : slice_size;
""",
        """\tconst uint64_t slice_size = p_size;
\t// WebGPU dynamic offsets are required to be 256-byte aligned. Keep the
\t// logical slice size for binding ranges, but separate frame slices by an
\t// aligned stride so frame_idx never produces an invalid dynamic offset.
\tconst uint64_t slice_stride = is_dynamic ? STEPIFY(slice_size, 256) : slice_size;
\tconst uint64_t alloc_size = is_dynamic ? slice_stride * frame_count : slice_size;
""",
    )

    replace_once(
        device_implementation,
        """\t\tdyn->persistent_size = slice_size * frame_count;
""",
        """\t\tdyn->persistent_size = slice_stride * frame_count;
""",
    )

    replace_once(
        device_implementation,
        """\treturn dyn->persistent_ptr + dyn->frame_idx * dyn->size;
""",
        """\tconst uint64_t slice_stride = dyn->persistent_size / frame_count;
\treturn dyn->persistent_ptr + dyn->frame_idx * slice_stride;
""",
    )

    replace_once(
        device_implementation,
        """\tfor (BufferDynamicInfo *dyn : dirty_dynamic_buffers) {
\t\tconst uint64_t offset = dyn->frame_idx * dyn->size;
\t\twgpuQueueWriteBuffer(queue, dyn->buffer, offset, dyn->persistent_ptr + offset, dyn->size);
\t}
""",
        """\tfor (BufferDynamicInfo *dyn : dirty_dynamic_buffers) {
\t\tconst uint64_t slice_stride = dyn->persistent_size / frame_count;
\t\tconst uint64_t offset = dyn->frame_idx * slice_stride;
\t\twgpuQueueWriteBuffer(queue, dyn->buffer, offset, dyn->persistent_ptr + offset, dyn->size);
\t}
""",
    )

    replace_once(
        device_implementation,
        """\t\t// Peel one slot per dynamic binding and convert frame_idx -> byte offset.
\t\tfor (const BufferDynamicInfo *dyn : uniform_set_info->dynamic_buffers) {
\t\t\tuint32_t frame_idx = (p_dynamic_offsets >> shift) & UNIFORM_DYN_MASK;
\t\t\tshift += UNIFORM_DYN_BITS;
\t\t\tcmd.dynamic_offsets.push_back(uint32_t(frame_idx * dyn->size));
\t\t}
""",
        """\t\t// Peel one slot per dynamic binding and convert frame_idx -> aligned byte offset.
\t\tfor (const BufferDynamicInfo *dyn : uniform_set_info->dynamic_buffers) {
\t\t\tuint32_t frame_idx = (p_dynamic_offsets >> shift) & UNIFORM_DYN_MASK;
\t\t\tshift += UNIFORM_DYN_BITS;
\t\t\tconst uint64_t slice_stride = dyn->persistent_size / frame_count;
\t\t\tcmd.dynamic_offsets.push_back(uint32_t(frame_idx * slice_stride));
\t\t}
""",
    )

    replace_once(
        device_implementation,
        """\t\tfor (const BufferDynamicInfo *dyn : uniform_set_info->dynamic_buffers) {
\t\t\tuint32_t frame_idx = (p_dynamic_offsets >> shift) & UNIFORM_DYN_MASK;
\t\t\tshift += UNIFORM_DYN_BITS;
\t\t\tcmd.dynamic_offsets.push_back(uint32_t(frame_idx * dyn->size));
\t\t}
\t\tcommand_buffer_info->commands.push_back(cmd);
\t}
}

// Dispatching.
""",
        """\t\tfor (const BufferDynamicInfo *dyn : uniform_set_info->dynamic_buffers) {
\t\t\tuint32_t frame_idx = (p_dynamic_offsets >> shift) & UNIFORM_DYN_MASK;
\t\t\tshift += UNIFORM_DYN_BITS;
\t\t\tconst uint64_t slice_stride = dyn->persistent_size / frame_count;
\t\t\tcmd.dynamic_offsets.push_back(uint32_t(frame_idx * slice_stride));
\t\t}
\t\tcommand_buffer_info->commands.push_back(cmd);
\t}
}

// Dispatching.
""",
    )

    replace_once(
        device_implementation,
        """\t\tif (buffer_info->is_dynamic()) {
\t\t\tuint64_t frame_idx = p_dynamic_offsets & VERTEX_DYN_MASK;
\t\t\tp_dynamic_offsets >>= VERTEX_DYN_BITS;
\t\t\toffset += frame_idx * buffer_info->size;
\t\t}
""",
        """\t\tif (buffer_info->is_dynamic()) {
\t\t\tuint64_t frame_idx = p_dynamic_offsets & VERTEX_DYN_MASK;
\t\t\tp_dynamic_offsets >>= VERTEX_DYN_BITS;
\t\t\tconst BufferDynamicInfo *dyn = static_cast<const BufferDynamicInfo *>(buffer_info);
\t\t\tconst uint64_t slice_stride = dyn->persistent_size / frame_count;
\t\t\toffset += frame_idx * slice_stride;
\t\t}
""",
    )

    print("Applied Starjunk WebGPU 4.7 compatibility patches")


if __name__ == "__main__":
    main()
