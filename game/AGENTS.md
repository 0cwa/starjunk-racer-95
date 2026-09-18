# Godot game instructions

Target Godot 4.7.2 APIs unless the WebGPU port requires a narrowly documented compatibility shim.

Keep gameplay/domain code independent of renderer forks and Spritely internals. Prefer typed GDScript. Treat scene/resource files as source code: keep diffs intentional.

Any new signature rendering feature should be represented in `tests/perf/renderer_torture/`.
