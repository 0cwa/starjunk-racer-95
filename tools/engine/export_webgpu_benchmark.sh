#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${1:?usage: export_webgpu_benchmark.sh GODOT_BIN TEMPLATE_ZIP OUTPUT_DIR [MAIN_SCENE]}"
TEMPLATE_ZIP="${2:?missing template zip}"
OUTPUT_DIR="${3:?missing output dir}"
MAIN_SCENE="${4:-res://tests/perf/renderer_torture/renderer_torture.tscn}"

test -x "$GODOT_BIN"
test -s "$TEMPLATE_ZIP"

PROJECT_FILE="$ROOT/game/project.godot"
PRESET_FILE="$ROOT/game/export_presets.cfg"
PROJECT_BACKUP="$(mktemp)"
PRESET_BACKUP="$(mktemp)"
cp "$PROJECT_FILE" "$PROJECT_BACKUP"
cp "$PRESET_FILE" "$PRESET_BACKUP"
cleanup() {
  cp "$PROJECT_BACKUP" "$PROJECT_FILE"
  cp "$PRESET_BACKUP" "$PRESET_FILE"
  rm -f "$PROJECT_BACKUP" "$PRESET_BACKUP"
}
trap cleanup EXIT

python3 - "$PROJECT_FILE" "$PRESET_FILE" "$TEMPLATE_ZIP" "$MAIN_SCENE" <<'PY'
import sys
from pathlib import Path

project_path = Path(sys.argv[1])
preset_path = Path(sys.argv[2])
template = str(Path(sys.argv[3]).resolve()).replace("\\", "/")
main_scene = sys.argv[4]

project = project_path.read_text(encoding="utf-8")
old_main = 'run/main_scene="res://src/bootstrap/main.tscn"'
new_main = f'run/main_scene="{main_scene}"'
if old_main not in project:
    raise SystemExit("expected main-scene anchor not found")
project_path.write_text(project.replace(old_main, new_main, 1), encoding="utf-8")

preset = preset_path.read_text(encoding="utf-8")
marker = "[preset.0.options]\n"
if marker not in preset:
    raise SystemExit("Web Benchmark preset options section not found")
custom_line = f'custom_template/release="{template}"\n'
preset = preset.replace(marker, marker + "\n" + custom_line, 1)
preset_path.write_text(preset, encoding="utf-8")
PY

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

"$GODOT_BIN" --headless --path "$ROOT/game" --editor --quit-after 2
"$GODOT_BIN" --headless --path "$ROOT/game"   --export-release "Web Benchmark" "$OUTPUT_DIR/index.html"

test -s "$OUTPUT_DIR/index.html"
test -s "$OUTPUT_DIR/index.wasm"
test -s "$OUTPUT_DIR/index.pck"
printf 'Exported WebGPU scene %s to %s\n' "$MAIN_SCENE" "$OUTPUT_DIR"
