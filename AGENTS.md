# AGENTS.md — Starjunk Racer 95

These instructions apply to the whole repository. A deeper `AGENTS.md` overrides them for its subtree.

## Mission

Build a fast, beautiful, highly moddable racing game. Preserve these constraints:

1. The browser experience is first-class.
2. The visual identity is saturated, pixel-conscious, sparkly and neo-retro.
3. Cars should differ in character, not in overall competitive strength.
4. Handling realism is a continuous game parameter, not two unrelated physics implementations.
5. Community cars/tracks are first-class and safe to exchange.
6. Spritely is an integration boundary, not a dependency that leaks through gameplay code.
7. Performance regressions are defects. Measure early and continuously.

## Repository boundaries

- `game/`: Godot game code and assets.
- `packages/`: engine-independent mod/content contracts.
- `networking/`: protocol notes and Spritely-side work.
- `engine/`: engine-source locks, patches and forward-port work only.
- `perf/`: baselines/budgets/results policy.
- `tools/`: deterministic developer and CI tooling.
- `docs/`: architecture, decisions and workflows.

Do not put gameplay logic in `engine/`. Do not put arbitrary executable code in community packages.

## Before changing code

1. Read the closest `AGENTS.md`, relevant ADRs, and `docs/performance.md` if rendering/physics/content density changes.
2. Read `docs/development-state.md`, then fetch the canonical **Development State — Start Here** issue (#48) and the active workstream issues it links.
3. Inspect current `main`, referenced open PRs, and exact-head CI before choosing the next change.
4. Do not infer priority from an open PR. Unless #48 or an active workstream explicitly references it, treat it as deferred/historical until you inspect its current disposition.
5. If an issue snapshot disagrees with the repository, tests, CI, or implementation, treat the executable repository evidence as authoritative and update the issue before proceeding.

Do not rely on prior chat/session context as the only record of current development state.

## Required validation

Run `make check` for every change. If a Godot binary is available, also load the affected scene headlessly. Rendering changes should run the torture benchmark on a comparable runner when possible.

## Performance discipline

- Never compare results from different renderer/driver/runner/profile identities.
- Never silently replace a baseline.
- Prefer reducing work over merely raising budgets.
- Benchmark scenes must remain deterministic enough for trend detection.
- New signature effects should be represented in the renderer torture test.

## Mod/security discipline

Community packages are data by default: manifests, meshes, textures, music metadata and declarative behaviors. Do not load untrusted GDScript from downloaded mods. Future programmable mods must run in a capability-limited sandbox.

## Git

Keep commits narrow and descriptive. Generated benchmark results do not belong in Git except approved baselines.

For substantial multi-PR work, use a `[Workstream]` GitHub issue as the operational handoff record. Keep its current state, evidence, next steps, blockers/dependencies, and done criteria current. Before ending a substantial development slice, update that workstream issue and update issue #48 if project-level focus or priority changed. Issues do not replace durable docs/ADRs for architectural decisions.
