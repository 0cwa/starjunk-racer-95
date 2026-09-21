#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "AGENTS.md",
    "docs/README.md",
    "engine/source-lock.json",
    "tools/engine/apply_starjunk_port_patches.py",
    "tools/engine/prepare_port_candidate.sh",
    "tools/engine/build_webgpu_rust_deps.sh",
    "tools/engine/forward_port_probe.sh",
    "tools/engine/export_webgpu_benchmark.sh",
    "tools/engine/export_webgpu_playable.sh",
    "tools/perf/webgpu_browser_smoke.py",
    "game/tests/perf/webgpu_boot/webgpu_boot.gd",
    "game/tests/perf/webgpu_boot/webgpu_boot.tscn",
    "game/tests/integration/web_playable_smoke.gd",
    "game/tests/integration/web_playable_smoke.tscn",
    ".github/workflows/webgpu-candidate-build.yml",
    ".github/workflows/webgpu-forward-port-probe.yml",
    "networking/source-lock.json",
    "networking/spritely/web/bootstrap.mjs",
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

    for path in [
        "engine/source-lock.json",
        "networking/source-lock.json",
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
    if lock.get("emscripten") != "6.0.9":
        raise SystemExit("WebGPU candidate Emscripten must remain pinned to 6.0.9")

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
        'spritely/reflect.js',
        'globalThis.HootScheme = Scheme',
        'spritely/bootstrap.mjs',
    ):
        if marker not in export_presets:
            raise SystemExit(f"Web Playable export is missing Spritely bootstrap marker: {marker}")

    print("Repository invariants OK")


if __name__ == "__main__":
    main()
