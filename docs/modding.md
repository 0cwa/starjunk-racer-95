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

Downloaded ZIP packages pass through `CommunityPackageArchive` before any manifest or GLB is trusted. The archive's central directory is preflighted before decompression: encrypted/ZIP64 entries are rejected, names are restricted to unambiguous safe ASCII package-relative paths, duplicate/case-colliding paths are rejected, Unix symlinks are rejected, and hard archive/entry/expanded-size/compression-ratio limits are enforced. Only then are files copied into a fresh `user://` staging directory.

The extractor writes every ZIP entry itself rather than restoring archive permissions, so an archive cannot create filesystem symlinks or executable permission state. A root `manifest.json` is required and is validated before the staging result is accepted.

## Runtime car visual import

`CommunityCarImporter` now loads a validated car GLB at runtime.

The importer reads the GLB bytes itself, enforces a size cap, inspects the GLB JSON chunk, and rejects any non-`data:` URI. It then calls `GLTFDocument.append_from_buffer` with an empty base path, so the import cannot roam the filesystem for sidecar assets.

After Godot generates the scene, the importer removes scripts, animation players, cameras, lights, audio nodes, ray/shape casts and collision nodes. Generation-1 community cars therefore contribute a visual node tree only. The caller receives that visual tree together with a separately resolved trusted `VehiclePerformanceProfile`.

This is deliberately asymmetric: custom geometry is open; competitive collision and physics are not supplied by the package.

## Runtime track import

`CommunityTrackImporter` keeps presentation and race collision separate.

- The environment GLB is embedded-only, size/node/light capped, and sanitized to visual `Node3D` content. Cameras, collision nodes, audio nodes, casts, scripts and non-3D helper nodes are removed.
- The collision GLB is never instantiated as an authored scene. Meshes are read from the generated GLB tree and converted into game-owned `StaticBody3D` + `CollisionShape3D` nodes.
- Collision mesh count and total triangle count are capped to prevent a community track from turning physics into an accidental denial-of-service workload.
- Checkpoints and spawn transforms come from the declarative manifest and are validated for finite coordinates, positive checkpoint extents, uniqueness and bounded counts.

This means track authors control road shape and race layout without supplying engine scripts or arbitrary physics objects.

## Future programmable mods

If programmable mods are introduced, they must run in a sandbox with explicit capabilities, such as reading beat timing or spawning cosmetic particles. They must not receive ambient filesystem/network authority or permission to alter authoritative race results.

## Decentralized sharing

Spritely-style object capabilities are a natural fit for sharing/forking/publishing content references. Storage/distribution details must remain behind the content service boundary so packages can also be imported from local files.
