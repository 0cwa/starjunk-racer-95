# Godot WebGPU 4.7.2 forward-port plan

The primary `dwalter/godotwebgpu` implementation is a valuable browser-first reference, but it is based on Godot 4.6.2 and contains a large accumulated delta. The newer `davnotdev/godot` WebGPU branch is our preferred **bridge** into 4.7-era engine interfaces, while the Walter implementation remains the primary reference for browser correctness, Mobile-renderer behavior and performance techniques.

## Pinned references

See `engine/source-lock.json`. Never forward-port from a floating branch.

The 2026-09-18 reconnaissance found merge base `e06dd8106e4c9113f2a3b20e4ceef16f3e85735e`. GitHub reports 110 WebGPU-side commits absent from 4.7.2 and 802 4.7.2-side commits absent from that branch.

More importantly, our Actions probe merged pinned WebGPU commit `2502ae7...` into pinned Godot 4.7.2 commit `ed1daf0...` **cleanly with zero merge conflicts**. This is only a source-merge result; compilation and rendering correctness are separate gates.

## Repeatable probes

- `tools/engine/forward_port_probe.sh` performs the merge and emits a conflict inventory.
- `tools/engine/prepare_port_candidate.sh` reconstructs the clean merged tree for compilation.
- `WebGPU 4.7.2 Candidate Build` compiles a web template against Emscripten 4.0.11.

## Phase 0 — validation harness

Keep upstream Godot 4.7.2 smoke tests green and make the renderer torture scene the acceptance workload.

## Phase 1 — buildable driver/backend

First make the cleanly merged 4.7.2 candidate compile as a WebGPU web template. Fix build/interface problems as narrow engine patches and document each one.

## Phase 2 — shader translation

Validate the secondary branch's translation path, then compare against the Walter/Tint implementation for browser-focused correctness and coverage. Preserve small shader fixtures for each issue.

## Phase 3 — RenderingDevice compatibility

Resolve runtime/API differences deliberately. Do not patch gameplay code around engine failures.

## Phase 4 — Forward Mobile correctness

Validate sky, canvas, shadows, materials, skeletons, GPU particles, particle trails and the permanent renderer torture workload.

## Phase 5 — browser integration

Validate device bootstrap, async GPU readback semantics, feature detection and graceful WebGPU-unavailable behavior.

## Phase 6 — performance optimizations

Only after correctness, import measured optimizations from the Walter implementation in isolated groups and benchmark each group.

## Exit criteria

The WebGPU build renders the torture workload correctly in supported desktop browsers, produces machine-readable benchmark results, and does not require game-domain code to know it is running on a fork.
