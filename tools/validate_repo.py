#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "AGENTS.md",
    "docs/README.md",
    "engine/source-lock.json",
    "engine/patches/spirv-webgpu-transform-fix-opnop.patch",
    "engine/patches/spirv-webgpu-transform-fix-binding-array-call.patch",
    "tools/engine/apply_starjunk_port_patches.py",
    "tools/engine/prepare_port_candidate.sh",
    "tools/engine/build_webgpu_rust_deps.sh",
    "tools/engine/forward_port_probe.sh",
    "tools/engine/export_webgpu_benchmark.sh",
    "tools/engine/export_webgpu_playable.sh",
    "tools/engine/analyze_spirv_dumps.sh",
    "tools/perf/webgpu_browser_smoke.py",
    "game/tests/perf/webgpu_boot/webgpu_boot.gd",
    "game/tests/perf/webgpu_boot/webgpu_boot.tscn",
    "game/tests/integration/web_playable_smoke.gd",
    "game/tests/integration/web_playable_smoke_test.tscn",
    ".github/workflows/webgpu-candidate-build.yml",
    ".github/workflows/webgpu-forward-port-probe.yml",
    "networking/source-lock.json",
    "networking/spritely/web/bootstrap.mjs",
    "tools/godot/run_test_suite.py",
    "tools/godot/test_suite.json",
    "tools/networking/package_spritely_web.sh",
    "game/project.godot",
    "game/export_presets.cfg",
    "game/tests/perf/renderer_torture/renderer_torture.tscn",
    "game/tests/perf/renderer_torture/renderer_torture.gd",
    "packages/schemas/car.schema.json",
    "packages/schemas/track.schema.json",
    "packages/schemas/cue-set.schema.json",
    "perf/budgets.json",
    ".github/workflows/ci.yml",
    ".github/workflows/nightly-performance.yml",
]


def _extract_literal(path: str, pattern: str, label: str) -> str:
    content = (ROOT / path).read_text(encoding="utf-8")
    match = re.search(pattern, content, re.MULTILINE)
    if match is None:
        raise SystemExit(f"Unable to read {label} from {path}")
    return match.group(1)


def main() -> None:
    missing = [path for path in REQUIRED if not (ROOT / path).is_file()]
    if missing:
        raise SystemExit("Missing required repository files: " + ", ".join(missing))

    # The candidate workflow invokes this helper directly; a non-executable
    # Git mode passes shell syntax checks but stops delivery after the build.
    playable_export = ROOT / "tools/engine/export_webgpu_playable.sh"
    if not os.access(playable_export, os.X_OK):
        raise SystemExit(f"WebGPU playable export helper is not executable: {playable_export}")

    for path in [
        "engine/source-lock.json",
        "networking/source-lock.json",
        "tools/godot/test_suite.json",
        "packages/schemas/car.schema.json",
        "packages/schemas/track.schema.json",
        "packages/schemas/cue-set.schema.json",
        "perf/budgets.json",
    ]:
        with (ROOT / path).open("r", encoding="utf-8") as handle:
            json.load(handle)

    lock = json.loads((ROOT / "engine/source-lock.json").read_text(encoding="utf-8"))
    for key in ("godot_upstream", "webgpu_primary", "webgpu_secondary"):
        commit = lock[key]["commit"]
        if len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit):
            raise SystemExit(f"{key} is not pinned to a full SHA")

    for key in ("naga_native", "spirv_webgpu_transform"):
        commit = lock["webgpu_rust_dependencies"][key]["commit"]
        if len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit):
            raise SystemExit(f"webgpu_rust_dependencies.{key} is not pinned to a full SHA")

    transform_dependency = lock["webgpu_rust_dependencies"]["spirv_webgpu_transform"]
    expected_transform_patches = [
        "engine/patches/spirv-webgpu-transform-fix-opnop.patch",
        "engine/patches/spirv-webgpu-transform-fix-binding-array-call.patch",
    ]
    if transform_dependency.get("patches") != expected_transform_patches:
        raise SystemExit(
            "spirv_webgpu_transform must declare the reviewed local patch series"
        )

    if lock.get("emscripten") != "6.0.9":
        raise SystemExit("WebGPU candidate Emscripten must remain pinned to 6.0.9")

    transform_patch = (
        ROOT / "engine/patches/spirv-webgpu-transform-fix-opnop.patch"
    ).read_text(encoding="utf-8")
    if (
        "-pub const SPV_INSTRUCTION_OP_NOP: u16 = 1;" not in transform_patch
        or "+pub const SPV_INSTRUCTION_OP_NOP: u16 = 0;" not in transform_patch
    ):
        raise SystemExit("SPIR-V transform patch must correct OpNop from opcode 1 to 0")

    binding_array_patch = (
        ROOT / "engine/patches/spirv-webgpu-transform-fix-binding-array-call.patch"
    ).read_text(encoding="utf-8")
    for marker in (
        "An opaque binding-array element may be passed directly to a helper",
        "function_call_args.contains(&old_result_id)",
        "Some((result_type_id, result_id))",
    ):
        if marker not in binding_array_patch:
            raise SystemExit(
                "SPIR-V binding-array patch is missing direct function-call handling"
            )

    rust_build = (ROOT / "tools/engine/build_webgpu_rust_deps.sh").read_text(
        encoding="utf-8"
    )
    if 'SPIRV_PATCH_RELS=("${VALUES[@]:4}")' not in rust_build:
        raise SystemExit("WebGPU Rust dependency build must read the locked patch series")

    candidate_workflow = (
        ROOT / ".github/workflows/webgpu-candidate-build.yml"
    ).read_text(encoding="utf-8")
    if "'engine/patches/*.patch'" not in candidate_workflow:
        raise SystemExit("WebGPU candidate cache key must include local patch contents")

    network_lock = json.loads(
        (ROOT / "networking/source-lock.json").read_text(encoding="utf-8")
    )
    game_control_protocol = _extract_literal(
        "game/src/networking/race_protocol.gd",
        r'^const CONTROL_PROTOCOL := "([^"]+)"$',
        "game control protocol",
    )
    game_realtime_protocol = _extract_literal(
        "game/src/networking/race_protocol.gd",
        r'^const REALTIME_PROTOCOL := "([^"]+)"$',
        "game realtime protocol",
    )
    spritely_control_protocol = _extract_literal(
        "networking/spritely/starjunk/race-room.scm",
        r'^\(define race-control-protocol "([^"]+)"\)$',
        "Spritely control protocol",
    )

    if network_lock.get("starjunk_control_protocol") != game_control_protocol:
        raise SystemExit(
            "networking/source-lock.json control protocol does not match RaceProtocol"
        )
    if spritely_control_protocol != game_control_protocol:
        raise SystemExit(
            "Spritely race-room control protocol does not match RaceProtocol"
        )
    if network_lock.get("starjunk_realtime_protocol") != game_realtime_protocol:
        raise SystemExit(
            "networking/source-lock.json realtime protocol does not match RaceProtocol"
        )

    export_presets = (ROOT / "game/export_presets.cfg").read_text(encoding="utf-8")
    for marker in (
        'name="Web Playable"',
        "spritely/reflect.js",
        "globalThis.HootScheme = Scheme",
        "spritely/bootstrap.mjs",
    ):
        if marker not in export_presets:
            raise SystemExit(f"Web Playable export is missing Spritely bootstrap marker: {marker}")

    print("Repository invariants OK")


if __name__ == "__main__":
    main()
