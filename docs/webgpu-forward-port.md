# Godot WebGPU 4.7.2 forward-port plan

The primary `dwalter/godotwebgpu` implementation remains the browser-correctness/performance reference and is based on Godot 4.6.2. The pinned `davnotdev/godot` WebGPU branch is the bridge into 4.7-era interfaces. We reconstruct the candidate from exact commits instead of maintaining a long-lived engine merge in the game repository.

## Pinned references

See `engine/source-lock.json`. Never forward-port from floating branches.

The merge probe combines Godot 4.7.2 `ed1daf0...` with WebGPU `2502ae7...` and records conflicts as machine-readable evidence. The shader bridge also depends on pinned `naga-native` and `spirv-webgpu-transform` revisions.

## Current executable milestone

The current acceptance gate is deliberately small: compile the pinned WebGPU web template, export `game/tests/perf/webgpu_boot/`, and require that scene to reach GDScript in headless Chromium with:

- Godot's Mobile rendering method;
- a rendering driver whose name contains `WebGPU`;
- a real browser `navigator.gpu` adapter.

Do not add the renderer torture workload to this workflow until the minimal boot gate is green.

## Toolchain findings

The candidate pins Emscripten **6.0.9**. With that SDK, the pinned WebGPU C++ source compiles. The fork's two Rust shader libraries are rebuilt from their pinned commits with `--locked` for `wasm32-unknown-emscripten`; their TAG files in the engine source must match our lock before the build proceeds.

Godot 4.7 added `swap_chain_get_hdr_output_supported()` to `RenderingDeviceDriver`. The Starjunk compatibility shim returns false for the current browser path, matching the backend's SDR behavior until HDR surface negotiation is implemented.

Emdawn's timed/infinite `wgpuInstanceWaitAny` path can suspend Wasm through Asyncify in ways that surface an uncaught `unwind` promise. The browser shim therefore uses zero-time polling plus `emscripten_sleep(0)` yields for adapter/device/readback futures. Desktop Dawn keeps blocking waits.

## Latest browser evidence

The 2026-09-19 candidate successfully reconstructed the pinned merge, built the pinned Rust shader dependencies, compiled the WebGPU Godot template, exported the minimal boot scene, and loaded it in Chromium. `navigator.gpu.requestAdapter()` returned Google's SwiftShader adapter.

Godot then failed before GDScript because device creation hard-required Dawn/experimental feature `texture-formats-tier1`. Chromium rejected `requestDevice()` with:

`Unsupported feature: texture-formats-tier1`

The current compatibility patch keeps those tier1/tier2/subgroup/texture-swizzle requirements for desktop Dawn but does not make them hard device requirements under Emdawn/browser WebGPU. Core requirements remain unchanged; if the boot gate exposes another missing core capability, that failure must be handled explicitly rather than blanket-disabling validation.

## Repeatable probes

- `tools/engine/forward_port_probe.sh` — source merge/conflict inventory.
- `tools/engine/prepare_port_candidate.sh` — reconstruct pinned candidate and apply fail-closed compatibility shims.
- `tools/engine/apply_starjunk_port_patches.py` — narrow source patches with exact anchors.
- `tools/engine/build_webgpu_rust_deps.sh` — reconstruct and validate pinned shader dependencies.
- `tools/engine/export_webgpu_benchmark.sh` — export a chosen test scene with the custom candidate template.
- `tools/perf/webgpu_browser_smoke.py` — Chromium/CDP gate with WebGPU adapter probe and detailed failure diagnostics.
- `WebGPU Forward Port Probe` and `WebGPU 4.7.2 Candidate Build` — hosted CI gates on relevant pull requests and `main`.

## Phases

1. **Browser boot correctness:** make the minimal Mobile/WebGPU scene reach GDScript.
2. **Shader/RenderingDevice correctness:** resolve concrete runtime incompatibilities in the engine layer.
3. **Forward Mobile feature correctness:** validate sky, canvas, shadows, materials, skeletons, GPU particles and particle trails.
4. **Playable Web export:** export the real game with the WebGPU template, package the already-proven Spritely runtime, and prove the Godot page observes `StarjunkSpritelyReady`.
5. **Performance:** run the permanent torture workload on comparable browser/GPU runners and only then reintroduce measured optimizations.

## Exit criteria

The WebGPU build renders the torture workload correctly in supported desktop browsers, produces machine-readable benchmark results, preserves the Spritely/Game boundary, and does not require gameplay code to know it is running on an engine fork.
