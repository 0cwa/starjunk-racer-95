# Godot WebGPU 4.7.2 forward-port plan

The primary `dwalter/godotwebgpu` implementation remains the browser-correctness/performance reference. It is based on Godot 4.6.2. The newer `davnotdev/godot` WebGPU branch is our preferred bridge into 4.7-era interfaces.

## Pinned references

See `engine/source-lock.json`. Never forward-port from floating branches.

The 2026-09-18 reconnaissance found merge base `e06dd8106e4c9113f2a3b20e4ceef16f3e85735e`. Our Actions probe merges pinned WebGPU commit `2502ae7...` into pinned Godot 4.7.2 `ed1daf0...` cleanly with zero conflicts.

## Toolchain finding

The first candidate build used Emscripten 4.0.11 because that is the polished Walter fork's documented toolchain. Compilation reached the WebGPU driver but failed because the September 2026 davnotdev source expects a newer WebGPU C API (instance features, texture-format tiers and texture-component swizzles).

The candidate therefore pins Emscripten **6.0.9**, released 2026-09-01, which is contemporary with the pinned 2026-09-02 davnotdev commit. Toolchain revisions are part of the candidate identity and must remain pinned.

Godot 4.7 also added `swap_chain_get_hdr_output_supported()` to `RenderingDeviceDriver`. Our first explicit compatibility shim returns false for WebGPU, matching the driver's existing `SUPPORTS_HDR_OUTPUT = false` behavior until browser HDR surface negotiation is deliberately implemented.

## Repeatable probes

- `tools/engine/forward_port_probe.sh` performs the source merge and emits a conflict inventory.
- `tools/engine/prepare_port_candidate.sh` reconstructs the pinned merged tree and applies narrow Starjunk compatibility shims.
- `tools/engine/apply_starjunk_port_patches.py` fails closed if an expected patch anchor drifts.
- `WebGPU 4.7.2 Candidate Build` compiles a web template against the pinned Emscripten version.

## Phases

1. **Buildable driver/backend:** make the 4.7.2 candidate compile; patch one concrete incompatibility group at a time.
2. **Shader translation:** validate the bridge translation path, then compare against the Walter/Tint implementation and preserve minimal fixtures.
3. **RenderingDevice compatibility:** resolve runtime/API differences in the engine layer, never gameplay.
4. **Forward Mobile correctness:** validate sky, canvas, shadows, materials, skeletons, GPU particles and particle trails.
5. **Browser integration:** validate device bootstrap, async GPU readback, feature detection and failure behavior.
6. **Performance:** only after correctness, import measured optimizations in isolated groups and benchmark each against the permanent torture workload.

## Exit criteria

The WebGPU build renders the torture workload correctly in supported desktop browsers, produces machine-readable benchmark results, and game-domain code does not know it is running on an engine fork.
