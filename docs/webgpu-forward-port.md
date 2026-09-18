# Godot WebGPU 4.7.2 forward-port plan

The primary `dwalter/godotwebgpu` implementation is a valuable browser-first reference, but it is based on Godot 4.6.2 and contains a large accumulated delta. The newer `davnotdev/godot` WebGPU branch is our preferred **bridge** into 4.7-era engine interfaces, while the Walter implementation remains the primary reference for browser correctness, Mobile-renderer behavior and performance techniques.

## Pinned references

See `engine/source-lock.json`. Never forward-port from a floating branch.

As of the repository's 2026-09-18 investigation, GitHub reports the pinned davnotdev WebGPU commit and Godot 4.7.2 as diverged: the WebGPU side has 110 commits not in 4.7.2, while 4.7.2 has 802 commits not in that branch, with merge base `e06dd8106e4c9113f2a3b20e4ceef16f3e85735e`. These are reconnaissance numbers, not a claim that all 110 commits should be imported.

## Repeatable merge probe

`tools/engine/forward_port_probe.sh` clones the pinned upstream/secondary sources, attempts a no-commit three-way merge and emits a machine-readable conflict inventory. A conflicted merge is a successful probe result; setup failures are not.

The `WebGPU Forward Port Probe` workflow runs this on the spike branch and uploads the raw report.

## Phase 0 — validation harness

Keep upstream Godot 4.7.2 smoke tests green and make the renderer torture scene the acceptance workload.

## Phase 1 — driver/build skeleton

Bring over WebGPU build detection, RenderingDeviceDriver registration, context creation and minimal browser device bootstrap. Prefer the 4.7-era secondary implementation where it matches current interfaces. Target a clear-color/minimal scene before shader breadth.

## Phase 2 — shader translation

Port the SPIR-V preprocessing and WGSL translation path. Use the Walter/Tint implementation as the browser-focused reference and preserve small translation fixtures.

## Phase 3 — RenderingDevice compatibility

Resolve interface changes between the secondary branch and 4.7.2 deliberately. Do not patch gameplay code around engine failures.

## Phase 4 — Forward Mobile correctness

Bring Mobile renderer/shader compatibility changes over in small groups. Validate sky, canvas, shadows, materials, skeletons, particles and particle trails.

## Phase 5 — browser integration

Port export/bootstrap changes, async GPU readback semantics, feature detection and graceful WebGPU-unavailable behavior.

## Phase 6 — performance optimizations

Only after correctness, reintroduce measured optimizations such as batching/pass reduction. Benchmark each group against the torture scene.

## Exit criteria

The WebGPU build renders the torture workload correctly in supported desktop browsers, produces machine-readable benchmark results, and does not require game-domain code to know it is running on a fork.
