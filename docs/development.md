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
