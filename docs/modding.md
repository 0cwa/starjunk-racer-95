# Community content and mods

## Goals

Players should be able to create, exchange, fork and race with custom cars and tracks without requiring a central workshop.

## Package shape

Generation 1 packages are data, not arbitrary executable code.

A car package contains a manifest plus GLB/media and references a game-owned `performance_profile`. Its visible geometry cannot change competitive collision/physics.

A track package contains visual/collision GLB data plus declarative checkpoints, spawn points, surfaces and optional song/presentation metadata.

Schemas live in `packages/schemas/`. Runtime policy lives behind `StarjunkPackageLoader`.

## Trust boundaries

Treat every community package as untrusted input.

Asset references must stay within the package root. The runtime rejects absolute paths, drive-qualified paths, backslashes and traversal components such as `..`. Generation-1 geometry must be GLB; a package cannot load a `.gd`, `.tscn` or other executable/engine-native payload merely by naming it as its model.

A car's `performance_profile` must exist in `PerformanceProfileRegistry`. Community content may select a trusted profile ID but cannot define or replace the resource behind that ID.

Archive extraction, when added, must independently enforce the same no-traversal rule before writing files.

## Future programmable mods

If programmable mods are introduced, they must run in a sandbox with explicit capabilities, such as reading beat timing or spawning cosmetic particles. They must not receive ambient filesystem/network authority or permission to alter authoritative race results.

## Decentralized sharing

Spritely-style object capabilities are a natural fit for sharing/forking/publishing content references. Storage/distribution details must remain behind the content service boundary so packages can also be imported from local files.
