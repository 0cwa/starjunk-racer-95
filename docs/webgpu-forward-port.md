# Godot WebGPU 4.7.2 forward-port plan

The primary `dwalter/godotwebgpu` implementation remains the browser-correctness/performance reference. It is based on Godot 4.6.2. The newer `davnotdev/godot` WebGPU branch is our preferred bridge into 4.7-era interfaces.

## Pinned references

See `engine/source-lock.json`. Never forward-port from floating branches.

The 2026-09-18 reconnaissance found merge base `e06dd8106e4c9113f2a3b20e4ceef16f3e85735e`. Our Actions probe merges pinned WebGPU commit `2502ae7...` into pinned Godot 4.7.2 `ed1daf0...` cleanly with zero conflicts.

## Toolchain findings

The first candidate build used Emscripten 4.0.11 because that is the polished Walter fork's documented toolchain. Compilation reached the WebGPU driver but failed because the September 2026 davnotdev source expects a newer WebGPU C API.

The candidate now pins Emscripten **6.0.9**, released 2026-09-01, contemporary with the pinned davnotdev commit. With that SDK, the WebGPU C++ source compiles.

Godot 4.7 added `swap_chain_get_hdr_output_supported()` to `RenderingDeviceDriver`. Our explicit compatibility shim returns false for WebGPU, matching the driver's existing `SUPPORTS_HDR_OUTPUT = false` behavior until browser HDR surface negotiation is deliberately implemented.

The next link gate exposed two intentionally external Rust static libraries. The Godot fork only carries their generated C headers and TAG commit IDs. We therefore pin and build:

- `davnotdev/naga-native@87cd2a99...`;
- `davnotdev/spirv-webgpu-transform@285f70a8...`.

`naga-native` itself uses a lockfile that pins the patched Naga source revision. CI builds it with `--locked` and only the `spv-in,wgsl-out` features needed by Godot. Both crates are compiled to `wasm32-unknown-emscripten` static archives and copied into the third-party directories that the fork's SCons files already search.

## Repeatable probes

- `tools/engine/forward_port_probe.sh` performs the source merge and emits a conflict inventory.
- `tools/engine/prepare_port_candidate.sh` reconstructs the pinned merged tree and applies narrow Starjunk compatibility shims.
- `tools/engine/apply_starjunk_port_patches.py` fails closed if an expected patch anchor drifts.
- `tools/engine/build_webgpu_rust_deps.sh` reconstructs the pinned shader dependencies from source and validates their TAGs.
- `WebGPU 4.7.2 Candidate Build` compiles a web template against the pinned toolchain.

## Phases

1. **Buildable driver/backend:** make the 4.7.2 candidate compile; patch one concrete incompatibility group at a time.
2. **Shader translation:** validate the bridge translation path, then compare against the Walter/Tint implementation and preserve minimal fixtures.
3. **RenderingDevice compatibility:** resolve runtime/API differences in the engine layer, never gameplay.
4. **Forward Mobile correctness:** validate sky, canvas, shadows, materials, skeletons, GPU particles and particle trails.
5. **Browser integration:** validate device bootstrap, async GPU readback, feature detection and failure behavior.
6. **Performance:** only after correctness, import measured optimizations in isolated groups and benchmark each against the permanent torture workload.

## Exit criteria

The WebGPU build renders the torture workload correctly in supported desktop browsers, produces machine-readable benchmark results, and game-domain code does not know it is running on an engine fork.


## Browser async bootstrap finding

The first exported Chromium boot gate proved that the page loaded and Chrome exposed a real WebGPU adapter through SwiftShader, but the tiny Godot scene never reached GDScript. The pinned bridge used `wgpuInstanceWaitAny(..., UINT64_MAX)` under Emdawn/Asyncify for adapter creation, device creation, and readback mapping.

Emscripten has a known browser failure mode where timed/infinite `wgpuInstanceWaitAny` suspension can surface an uncaught Asyncify `unwind` promise. Starjunk's Emdawn compatibility shim therefore uses zero-time `wgpuInstanceWaitAny` polling plus `emscripten_sleep(0)` between polls. This keeps the WebGPU call itself non-suspending while explicitly yielding the JavaScript event loop. Desktop Dawn retains its original blocking waits.

The browser smoke harness now starts Chromium on `about:blank`, installs error/unhandled-rejection listeners before navigation, enables Runtime/Log/Network/Page DevTools domains, and records console, exception, network-failure, page-state, resource-timing, and Chromium stderr diagnostics on failure.

CI also persists toolchain-keyed Emscripten, SCons, and Cargo target caches. The caches are acceleration only: SCons/compiler keys and the pinned source/toolchain lock remain authoritative.
