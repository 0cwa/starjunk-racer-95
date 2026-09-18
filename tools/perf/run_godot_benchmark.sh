#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
RUNNER_ID="${STARJUNK_RUNNER_ID:-local-unregistered}"
OUTPUT="${1:-$ROOT/perf/results/renderer-torture.json}"
WARMUP="${STARJUNK_WARMUP_FRAMES:-180}"
FRAMES="${STARJUNK_SAMPLE_FRAMES:-600}"

mkdir -p "$(dirname "$OUTPUT")"
export STARJUNK_RUNNER_ID="$RUNNER_ID"

"$GODOT_BIN" --path "$ROOT/game"   res://tests/perf/renderer_torture/renderer_torture.tscn   --   --benchmark   "--warmup=$WARMUP"   "--frames=$FRAMES"   "--output=$OUTPUT"

test -s "$OUTPUT"
echo "Wrote $OUTPUT"
