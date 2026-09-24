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

## Play locally

Install Godot **4.7.2**, then open `game/project.godot` in the editor and press Play. For a command-line launch from the repository root, import the project once first (a fresh checkout needs its generated script-class cache):

~~~sh
godot --headless --path game --editor --quit-after 2
godot --path game
~~~

Set `GODOT_BIN` or substitute your Godot executable for `godot` if it is not on `PATH`. The default scene is the playable prototype race: **W/S** accelerate/brake, **A/D** steer, **R** reset, and **[ / ]** adjust realism. See [prototype controls and scope](docs/prototype-race.md). The tested browser build uses Godot's Compatibility/WebGL renderer for now; the custom Mobile/WebGPU renderer is still under validation. On the default branch, GitHub Actions publishes it as **`starjunk-racer-95-browser-demo-compatibility`** after checking the real race and Spritely bootstrap. Open the artifact's `index.html` from a static web host (WebAssembly needs HTTP; don't open it as a `file://` URL). The artifact is suitable for sharing or static hosting, but isn't deployed to GitHub Pages yet.

## Start here

Read `AGENTS.md`, then `docs/README.md`, then the canonical [Development State — Start Here issue](https://github.com/0cwa/starjunk-racer-95/issues/48). The issue is the current operational snapshot; repository code, tests, CI, docs, and ADRs remain authoritative.

Common commands:

~~~sh
make check
GODOT_BIN=/path/to/godot make godot-test
make perf-test
GODOT_BIN=/path/to/godot tools/perf/run_godot_benchmark.sh
~~~

`make check` validates that every `game/tests/unit/**/*_test.tscn` and
`game/tests/integration/**/*_test.tscn` scene is registered in the deterministic
Godot suite manifest. Use `tools/godot/run_test_suite.py --filter <substring>`
to run a focused subset while iterating.

No performance baseline should be committed until it was captured on a named, repeatable runner. Never “fix” a regression by replacing the baseline without an explanation.
