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

## Content identity

A package's location and its identity are separate concepts. `CommunityPackageIdentity` hashes every file in a validated package using SHA-256, sorts the package-relative paths, and hashes a canonical file index into a package content ID of the form `sha256:<hex>`.

The descriptor includes each file's path, byte size, and SHA-256 digest. Directory enumeration order does not affect the result; changing any file bytes, path, or size changes the package ID.

This is intentionally complementary to Spritely capabilities:

- a **content ID** answers “which exact immutable package bytes are we talking about?”;
- a **capability** answers “who has authority to retrieve, use, re-share, fork, or publish this content?”

Race invitations should ultimately bind both so a mutable publisher capability cannot cause different peers to race on different track bytes.

The identity builder rejects symlinks/reparse points and applies the same path/count/file/total-size limits as archive staging. Hashing is streamed in chunks rather than loading large package files into memory.

## Content-addressed local library

`CommunityContentLibrary` persists validated packages under `user://starjunk95/library/<sha256-digest>/`. The directory name comes only from a strictly validated SHA-256 content ID; user-supplied paths are never joined into the library root.

Installation is transactional:

1. build the staged package's canonical `CommunityPackageIdentity` descriptor;
2. copy files into a fresh temporary sibling while re-checking portable paths and refusing links;
3. rebuild the descriptor from the copied bytes and require the exact same content ID;
4. atomically rename the verified temporary directory to its immutable digest path.

Installing the same bytes again deduplicates to the existing directory. Resolving an installed content ID re-hashes the directory every time, so manual disk changes are surfaced as integrity failures rather than silently becoming new trusted content.

The library has no mutable index inside package directories; enumeration scans digest directories and returns verified packages separately from corrupt entries. This keeps content identity stable and gives Spritely capabilities a durable local object to resolve by exact ID.

## Content service boundary

`CommunityContentService` is the application-facing entry point for local community content. UI and future Spritely adapters should use this service instead of manipulating staging directories or package roots directly.

- `install_zip()` stages an untrusted ZIP under a service-owned temporary `user://` directory, validates/extracts it through `CommunityPackageArchive`, installs the verified bytes in `CommunityContentLibrary`, and removes staging data on both success and failure.
- `catalog()` exposes verified metadata suitable for selection UI without exposing mutable filesystem roots.
- `build_race_bundle(car_content_id, track_content_id)` resolves and re-hashes the immutable IDs, verifies car/track package kinds, imports them through `CommunityRaceBundle`, and requires the returned IDs to match the requested IDs before returning runtime nodes.
- `uninstall()` delegates to the content-addressed library.

The final content-ID comparison closes the time-of-check/time-of-use gap between library resolution and GLB import. The playable race still receives only a sanitized bundle and never receives archive, hash, or path authority.

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

## Race-ready community bundles

`CommunityRaceBundle` is the assembly boundary between staged community packages and race code. It computes canonical content descriptors for a car and track, verifies the expected package kinds, imports both through the existing sanitizers, and returns one race-ready dictionary containing:

- exact car and track content IDs;
- sanitized car visual plus its trusted game-owned performance profile;
- sanitized track visual plus game-owned collision nodes;
- validated checkpoints and spawn transforms;
- immutable copies of both manifests.

Bundle construction is atomic: if the second import fails, nodes created by the first import are freed. `release()` frees a successful bundle's runtime nodes. This keeps the playable race from needing to know archive, hashing, GLB, or trust-boundary details.

A future multiplayer room can therefore bind a capability reference to a specific `content_id` before asking the race runtime to mount the bundle.

## Song-reactive presentation

Tracks can optionally reference a declarative `starjunk95/cue-set/1` JSON file. `SongCueTimeline` validates the cue set, sorts equal-time cues deterministically by ID, and advances presentation events from song time.

Cue events are deliberately presentation-only: palette, lighting, particles, scenery phase changes, post-processing and beat markers. They do not alter vehicle physics, collision, checkpoints, lap state or capability authority. Seeking the music resets timeline position without replaying every earlier cue; callers decide whether to reconstruct presentation state from persistent theme data.

This lets official Starjunk 95 courses and community tracks share one song-reactive mechanism without loading arbitrary scripts.

## Future programmable mods

If programmable mods are introduced, they must run in a sandbox with explicit capabilities, such as reading beat timing or spawning cosmetic particles. They must not receive ambient filesystem/network authority or permission to alter authoritative race results.

## Decentralized sharing

Spritely-style object capabilities are a natural fit for sharing/forking/publishing content references. Storage/distribution details must remain behind the content service boundary so packages can also be imported from local files.
