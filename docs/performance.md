# Performance policy

Performance is a continuous product constraint.

## Permanent benchmark

`game/tests/perf/renderer_torture/` is a permanent scene that intentionally stresses the visual language we expect to use in real tracks: instancing, dynamic lights, emission/glow, transparency, GPU particles and particle trails.

Do not simplify it merely to make numbers look better. Add representative signature effects as the game evolves.

The authoritative `default` profile retains the full workload. Hosted browser CI runs a `browser_smoke` density profile that keeps the same feature classes (instancing, dynamic lights/shadows, emission/glow, transparency, GPU particles and ribbon particle trails) at reduced counts because GitHub-hosted Chromium uses software WebGPU. Smoke results are correctness evidence only and must never become performance baselines.

## Result identity

Results are comparable only when these match:

- scenario and scenario version;
- stress profile/settings hash;
- engine build;
- renderer and rendering driver;
- runner identity/GPU class;
- resolution and relevant quality settings.

The comparison tool rejects mismatched identities.

## Baselines

A baseline must come from a named repeatable runner. It requires review. Replacing a baseline needs a reason and benchmark evidence.

GitHub-hosted runners are useful for syntax/import smoke tests, not authoritative GPU performance. Nightly authoritative runs use a labeled self-hosted GPU runner and are enabled with the repository variable `PERF_RUNNER_ENABLED=true`.

## Regression policy

Start with relative budgets in `perf/budgets.json`. Prefer implementation improvements over budget increases. Track both frame-time tails and structural counters such as draw calls.
