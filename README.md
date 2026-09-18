# Starjunk Racer 95

A neo-retro racing game with saturated, sparkly 2.5D/3D visuals, balanced but characterful cars, song-driven courses, decentralized multiplayer/content sharing, and first-class community mods.

## Technical direction

- **Engine:** Godot 4.7.2.
- **Browser rendering:** keep gameplay/content renderer-agnostic while forward-porting the GodotWebGPU Mobile renderer backend.
- **Native rendering:** Mobile is the common visual baseline; Forward+ may add optional enhancements.
- **Multiplayer/content:** Spritely Goblins/OCapN behind a narrow adapter.
- **Community content:** engine-independent declarative packages plus GLB assets; competitive car physics come from game-owned performance profiles.
- **Collaboration:** Git is canonical; Backstitch is encouraged as a live Godot collaboration layer when useful.
- **Performance:** the renderer torture test is permanent infrastructure, not a disposable demo.

## Start here

Read `AGENTS.md`, then `docs/README.md`.

Common commands:

~~~sh
make check
make perf-test
GODOT_BIN=/path/to/godot tools/perf/run_godot_benchmark.sh
~~~

No performance baseline should be committed until it was captured on a named, repeatable runner. Never “fix” a regression by replacing the baseline without an explanation.
