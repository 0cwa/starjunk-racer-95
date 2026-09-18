# Starjunk package format

The `starjunk95/*/1` formats are deliberately engine-independent public contracts.

## Generation 1 rules

- Manifests are JSON.
- 3D payloads are GLB.
- GLBs must be self-contained: non-`data:` external URI dependencies are rejected at runtime.
- Asset paths are package-relative POSIX paths.
- Absolute paths, drive-qualified paths, backslashes, `.` and `..` path components are rejected.
- Car packages select a game-owned `performance_profile`; they cannot ship competitive physics.
- Imported car models are visual-only; collision/physics authority remains game-owned.
- Track packages declare geometry and race structure, not arbitrary GDScript.
- Imported packages should be treated as untrusted input before any files are opened or instantiated.

The JSON schemas define portable structure. The Godot-side loader adds runtime policy checks that schemas alone cannot express, such as whether a requested performance profile is trusted by this game version.

- Runtime track import separates visual GLB from collision GLB. Collision meshes become game-created static trimesh shapes; checkpoint/spawn nodes are generated from validated manifest data.
