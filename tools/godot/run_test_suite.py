#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
GAME_ROOT = ROOT / "game"
DEFAULT_MANIFEST = ROOT / "tools" / "godot" / "test_suite.json"
TEST_GROUPS = ("unit", "integration")


class SuiteError(ValueError):
    pass


def _positive_int(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise SuiteError(f"{label} must be a positive integer")
    return value


def discover_test_scenes() -> list[str]:
    scenes: list[str] = []
    for group in TEST_GROUPS:
        group_root = GAME_ROOT / "tests" / group
        for path in sorted(group_root.rglob("*_test.tscn")):
            scenes.append("res://" + path.relative_to(GAME_ROOT).as_posix())
    return scenes


def load_suite(path: Path) -> list[dict[str, Any]]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SuiteError(f"test suite manifest does not exist: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SuiteError(f"invalid JSON in {path}: {exc}") from exc

    if not isinstance(raw, dict) or raw.get("schema_version") != 1:
        raise SuiteError("test suite manifest must use schema_version 1")

    tests = raw.get("tests")
    if not isinstance(tests, list) or not tests:
        raise SuiteError("test suite manifest must contain a non-empty tests array")

    validated: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, entry in enumerate(tests):
        label = f"tests[{index}]"
        if not isinstance(entry, dict):
            raise SuiteError(f"{label} must be an object")

        scene = entry.get("scene")
        if not isinstance(scene, str):
            raise SuiteError(f"{label}.scene must be a string")
        if not any(scene.startswith(f"res://tests/{group}/") for group in TEST_GROUPS):
            raise SuiteError(f"{label}.scene must be a unit or integration test scene")
        if not scene.endswith("_test.tscn"):
            raise SuiteError(f"{label}.scene must end with _test.tscn")
        if scene in seen:
            raise SuiteError(f"duplicate test scene: {scene}")
        seen.add(scene)

        disk_path = GAME_ROOT / scene.removeprefix("res://")
        if not disk_path.is_file():
            raise SuiteError(f"registered test scene does not exist: {scene}")

        normalized: dict[str, Any] = {"scene": scene}
        if "fixed_fps" in entry:
            normalized["fixed_fps"] = _positive_int(entry["fixed_fps"], f"{label}.fixed_fps")
        if "timeout_seconds" in entry:
            normalized["timeout_seconds"] = _positive_int(
                entry["timeout_seconds"], f"{label}.timeout_seconds"
            )
        unknown = set(entry) - {"scene", "fixed_fps", "timeout_seconds"}
        if unknown:
            raise SuiteError(f"{label} has unknown keys: {', '.join(sorted(unknown))}")
        validated.append(normalized)

    discovered = set(discover_test_scenes())
    registered = {entry["scene"] for entry in validated}
    missing = sorted(discovered - registered)
    stale = sorted(registered - discovered)
    problems: list[str] = []
    if missing:
        problems.append("unregistered test scenes: " + ", ".join(missing))
    if stale:
        problems.append("manifest entries without matching test scenes: " + ", ".join(stale))
    if problems:
        raise SuiteError("; ".join(problems))

    return validated


def build_command(godot_bin: str, test: dict[str, Any]) -> list[str]:
    command = [godot_bin, "--headless"]
    if "fixed_fps" in test:
        command.extend(["--fixed-fps", str(test["fixed_fps"])])
    command.extend(["--path", str(GAME_ROOT), test["scene"]])
    return command


def run_suite(godot_bin: str, tests: list[dict[str, Any]]) -> int:
    total = len(tests)
    for index, test in enumerate(tests, start=1):
        scene = test["scene"]
        timeout = test.get("timeout_seconds")
        timeout_text = f", timeout={timeout}s" if timeout is not None else ""
        fps_text = f", fixed_fps={test['fixed_fps']}" if "fixed_fps" in test else ""
        print(f"[godot-test {index:02d}/{total:02d}] {scene}{fps_text}{timeout_text}", flush=True)
        try:
            completed = subprocess.run(
                build_command(godot_bin, test),
                cwd=ROOT,
                check=False,
                timeout=timeout,
            )
        except FileNotFoundError:
            print(f"Godot executable not found: {godot_bin}", file=sys.stderr)
            return 127
        except subprocess.TimeoutExpired:
            print(f"Godot test timed out after {timeout}s: {scene}", file=sys.stderr)
            return 124

        if completed.returncode != 0:
            print(
                f"Godot test failed with exit code {completed.returncode}: {scene}",
                file=sys.stderr,
            )
            return completed.returncode
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate and run the Starjunk Racer 95 Godot unit/integration suite."
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="test suite manifest path",
    )
    parser.add_argument(
        "--godot-bin",
        default=os.environ.get("GODOT_BIN", "godot"),
        help="Godot executable (defaults to GODOT_BIN or godot)",
    )
    parser.add_argument(
        "--filter",
        default="",
        help="run only scenes whose res:// path contains this substring",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="print registered test scenes without running them",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="validate manifest coverage without running Godot",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        tests = load_suite(args.manifest)
    except SuiteError as exc:
        print(f"Godot test suite configuration error: {exc}", file=sys.stderr)
        return 2

    if args.filter:
        tests = [test for test in tests if args.filter in test["scene"]]
        if not tests:
            print(f"No registered Godot tests match filter: {args.filter}", file=sys.stderr)
            return 2

    if args.list:
        for test in tests:
            print(test["scene"])
        return 0

    if args.validate_only:
        print(f"Godot test suite manifest OK ({len(tests)} scenes)")
        return 0

    return run_suite(args.godot_bin, tests)


if __name__ == "__main__":
    raise SystemExit(main())
