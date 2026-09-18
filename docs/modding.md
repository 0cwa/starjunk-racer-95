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

## Runtime car visual import

`CommunityCarImporter` now loads a validated car GLB at runtime.

The importer reads the GLB bytes itself, enforces a size cap, inspects the GLB JSON chunk, and rejects any non-`data:` URI. It then calls `GLTFDocument.append_from_buffer` with an empty base path, so the import cannot roam the filesystem for sidecar assets.

After Godot generates the scene, the importer removes scripts, animation players, cameras, lights, audio nodes, ray/shape casts and collision nodes. Generation-1 community cars therefore contribute a visual node tree only. The caller receives that visual tree together with a separately resolved trusted `VehiclePerformanceProfile`.

This is deliberately asymmetric: custom geometry is open; competitive collision and physics are not supplied by the package.

## Future programmable mods

If programmable mods are introduced, they must run in a sandbox with explicit capabilities, such as reading beat timing or spawning cosmetic particles. They must not receive ambient filesystem/network authority or permission to alter authoritative race results.

## Decentralized sharing

Spritely-style object capabilities are a natural fit for sharing/forking/publishing content references. Storage/distribution details must remain behind the content service boundary so packages can also be imported from local files.


## Runtime track import

`CommunityTrackImporter` loads generation-1 custom tracks from two self-contained GLBs plus declarative race metadata.

- The **environment GLB** is visual-only and receives the same script/camera/light/collision sanitization as community car visuals.
- The **collision GLB** is never inserted as a scene. Its triangle meshes are converted into game-created `ConcavePolygonShape3D` nodes under a single `StaticBody3D`, with a hard shape-count cap.
- **Checkpoints** are game-created `Area3D` boxes from manifest IDs, transforms and sizes.
- **Spawn points** are game-created transforms from the manifest.

This means track authors control the physical road geometry—as they must for custom tracks—but still do not supply executable Godot scenes, scripts, cameras or arbitrary physics objects.
