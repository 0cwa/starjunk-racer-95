#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "AGENTS.md",
    "docs/README.md",
    "engine/source-lock.json",
    "game/project.godot",
    "game/tests/perf/renderer_torture/renderer_torture.tscn",
    "game/tests/perf/renderer_torture/renderer_torture.gd",
    "packages/schemas/car.schema.json",
    "packages/schemas/track.schema.json",
    "perf/budgets.json",
    ".github/workflows/ci.yml",
    ".github/workflows/nightly-performance.yml",
]

def main() -> None:
    missing = [path for path in REQUIRED if not (ROOT / path).is_file()]
    if missing:
        raise SystemExit("Missing required repository files: " + ", ".join(missing))

    for path in [
        "engine/source-lock.json",
        "packages/schemas/car.schema.json",
        "packages/schemas/track.schema.json",
        "perf/budgets.json",
    ]:
        with (ROOT / path).open("r", encoding="utf-8") as handle:
            json.load(handle)

    lock = json.loads((ROOT / "engine/source-lock.json").read_text(encoding="utf-8"))
    for key in ("godot_upstream", "webgpu_primary", "webgpu_secondary"):
        commit = lock[key]["commit"]
        if len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit):
            raise SystemExit(f"{key} is not pinned to a full SHA")

    print("Repository invariants OK")

if __name__ == "__main__":
    main()
