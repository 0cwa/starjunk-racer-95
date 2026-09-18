# Community-content runtime instructions

This subtree processes attacker-controlled content. Treat every path, archive field, manifest value, GLB node, mesh size and content reference as untrusted.

- Validate container metadata before allocating/decompressing large payloads.
- Never extract archive-provided permissions, symlinks or absolute paths.
- Never instantiate downloaded Godot scenes/scripts.
- Community car geometry is visual-only; trusted performance profiles own competitive physics.
- Community track collision must be rebuilt into game-owned physics nodes with explicit complexity limits.
- Keep limits named and tested. Raising a limit is a security/performance decision and must be documented.
- On validation failure, fail closed and remove partial staging data.
