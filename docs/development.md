# Development workflow

1. Read the nearest `AGENTS.md`.
2. Make the smallest coherent change.
3. Run `make check`.
4. If Godot is available, import/load affected scenes headlessly.
5. For rendering-density changes, run the benchmark on a comparable runner and attach results to the PR.
6. Update docs/ADRs when architecture changes.

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
GODOT_BIN=/path/to/project-webgpu-godot \
  "$GODOT_BIN" --headless --path game --export-release "Web Playable"
tools/networking/package_spritely_web.sh build/web-playable
```

`run_spike.sh` verifies the pinned Goblins/Hoot package families and leaves the
compiled room Wasm plus the exact Hoot runtime assets under `build/spritely/`.
The packager refuses an export whose HTML is missing the expected bootstrap
markers, copies the runtime into `spritely/`, and writes `SHA256SUMS`.

The `Web Playable` target is intended for the project WebGPU export template.
The networking package itself is renderer-independent so it can be validated
separately from the engine forward-port.
