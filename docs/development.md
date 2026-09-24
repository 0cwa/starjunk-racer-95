# Development workflow

1. Read the nearest `AGENTS.md`.
2. Read `docs/development-state.md`, GitHub issue #48, and the active workstream issue(s) relevant to the task.
3. Reconcile issue state with current `main`, open PRs, and exact-head CI.
4. Make the smallest coherent change.
5. Run `make check`.
6. If Godot is available, run `GODOT_BIN=/path/to/godot make godot-test`; use `tools/godot/run_test_suite.py --filter <substring>` for a focused subset while iterating.
7. For rendering-density changes, run the benchmark on a comparable runner and attach results to the PR.
8. Update docs/ADRs when architecture changes.
9. Before ending a substantial development slice, update the affected workstream issue and issue #48 when project-level focus or priority changed.

The unit/integration suite is declared in `tools/godot/test_suite.json`. `make check`
compares that manifest with every `game/tests/unit/**/*_test.tscn` and
`game/tests/integration/**/*_test.tscn` scene, so adding a test without registering
it fails fast before CI. Characterization, export, and performance scenes remain
separate gates because they produce artifacts or have different execution semantics.

## Git and Backstitch

Git is canonical history and recovery. Backstitch may be used for live Godot scene/resource collaboration, but it must not be the only durable copy of project state.

## Engine source

`engine/source-lock.json` pins upstream and WebGPU references. `tools/engine/fetch_sources.sh` refuses floating refs. Engine work belongs in a separate engine worktree/fork and should be upstreamable or removable.


## Playable Web networking package

The Godot `Web Playable` preset contains only stable bootstrap tags. Spritely/Hoot
runtime binaries are build outputs and are not vendored in Git.

A reproducible local package flow is:

```sh
networking/spritely/run_spike.sh
GODOT_BIN=/path/to/project-webgpu-godot
"$GODOT_BIN" --headless --path game --export-release "Web Playable"
tools/networking/package_spritely_web.sh build/web-playable
```

`run_spike.sh` verifies the pinned Goblins/Hoot package families and leaves the
compiled room Wasm plus the exact Hoot runtime assets under `build/spritely/`.
The packager refuses an export whose HTML is missing the expected bootstrap
markers, copies the runtime into `spritely/`, and writes `SHA256SUMS`.

The `Web Playable` target is intended for the project WebGPU export template.
Until that renderer runs the full race reliably, `.github/workflows/browser-demo.yml`
produces a separately labeled browser demo using Godot 4.7.2's pinned
Compatibility/WebGL template. It runs the real race and Spritely Chromium gate
before uploading a complete static site; it is a delivery fallback, not a
replacement for the Mobile/WebGPU correctness milestone or a GPU benchmark.
The networking package itself is renderer-independent.


## Development-state handoff

GitHub Issues are the operational handoff layer for current development state.

- **Issue #48 — Development State — Start Here** is the compact project-level snapshot: active workstreams, current primary focus, current blockers, and priority order.
- **`[Workstream]` issues** hold the detailed state for efforts expected to span multiple commits or PRs.
- **Pull requests** are implementation/review units, not the canonical roadmap.
- **Repository docs and ADRs** hold durable architecture and policy, not ephemeral status.

A workstream issue should keep these sections current:

- Goal.
- Current state.
- Latest evidence, preferably exact commit/PR/workflow-run evidence.
- Next steps in execution order.
- Blockers/dependencies.
- Done criteria.
- Durable constraints that matter specifically to the workstream.

Update the issue body when the current snapshot changes materially. Use comments for noteworthy historical evidence that does not belong in the compact current snapshot. Close a workstream issue when its stated milestone is complete; open a successor issue if the next milestone is materially different.

Do not copy large architecture documents into issues. Link the durable source instead. If issue text and executable repository evidence disagree, update the issue rather than coding against stale state.
