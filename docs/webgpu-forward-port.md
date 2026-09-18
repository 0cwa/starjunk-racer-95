# Godot WebGPU 4.7.2 forward-port plan

The primary reference fork is large enough that a blind merge is unacceptable. Port in reviewable phases against pinned sources.

## Pinned references

See `engine/source-lock.json`.

## Phase 0 — validation harness

Keep upstream Godot 4.7.2 smoke tests green and make the renderer torture scene the acceptance workload.

## Phase 1 — driver/build skeleton

Bring over WebGPU build detection, RenderingDeviceDriver registration, context creation and minimal browser device bootstrap. Target a clear-color/minimal scene before shader breadth.

## Phase 2 — shader translation

Port the SPIR-V preprocessing and Tint/WGSL translation path with its tests. Keep translation failures reproducible as small fixtures.

## Phase 3 — RenderingDevice compatibility

Reconcile interface changes between 4.6.2 and 4.7.2 deliberately. Do not patch gameplay code around engine failures.

## Phase 4 — Forward Mobile correctness

Bring Mobile renderer/shader compatibility changes over in small groups. Validate sky, canvas, shadows, materials, skeletons, particles and particle trails.

## Phase 5 — browser integration

Port export/bootstrap changes, async GPU readback semantics, feature detection and graceful WebGPU-unavailable behavior.

## Phase 6 — performance optimizations

Only after correctness, reintroduce measured optimizations such as batching/pass reduction. Benchmark each group against the torture scene.

## Exit criteria

The WebGPU build renders the torture workload correctly in supported desktop browsers, produces machine-readable benchmark results, and does not require game-domain code to know it is running on a fork.
