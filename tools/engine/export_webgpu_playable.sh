#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${1:?usage: export_webgpu_playable.sh GODOT_BIN TEMPLATE_ZIP OUTPUT_DIR [MAIN_SCENE]}"
TEMPLATE_ZIP="${2:?missing template zip}"
OUTPUT_DIR="${3:?missing output dir}"
MAIN_SCENE="${4:-}"

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
import re
import sys
from pathlib import Path

project_path = Path(sys.argv[1])
preset_path = Path(sys.argv[2])
template = str(Path(sys.argv[3]).resolve()).replace("\\", "/")
main_scene = sys.argv[4]

if main_scene:
    project = project_path.read_text(encoding="utf-8")
    project, substitutions = re.subn(
        r'^run/main_scene="[^"]+"$',
        f'run/main_scene="{main_scene}"',
        project,
        count=1,
        flags=re.MULTILINE,
    )
    if substitutions != 1:
        raise SystemExit(
            f"expected exactly one main-scene setting, replaced {substitutions}"
        )
    project_path.write_text(project, encoding="utf-8")

preset = preset_path.read_text(encoding="utf-8")
marker = "[preset.1.options]\n"
if marker not in preset:
    raise SystemExit("Web Playable preset options section not found")
custom_line = f'custom_template/release="{template}"\n'
preset = preset.replace(marker, marker + "\n" + custom_line, 1)
preset_path.write_text(preset, encoding="utf-8")
PY

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

"$GODOT_BIN" --headless --path "$ROOT/game" --editor --quit-after 2
"$GODOT_BIN" --headless --path "$ROOT/game" \
  --export-release "Web Playable" "$OUTPUT_DIR/index.html"

test -s "$OUTPUT_DIR/index.html"
test -s "$OUTPUT_DIR/index.wasm"
test -s "$OUTPUT_DIR/index.pck"

for marker in \
  'spritely/reflect.js' \
  'globalThis.HootScheme = Scheme' \
  'spritely/bootstrap.mjs'
do
  grep -Fq "$marker" "$OUTPUT_DIR/index.html"
done

printf 'Exported WebGPU playable scene %s to %s\n' \
  "${MAIN_SCENE:-<project default>}" "$OUTPUT_DIR"
