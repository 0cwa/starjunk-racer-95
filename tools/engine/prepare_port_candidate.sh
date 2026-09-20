#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="$ROOT/engine/source-lock.json"
OUT_DIR="${1:-$ROOT/build/webgpu-port-candidate}"
WORK_DIR="$OUT_DIR/godot"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

readarray -t VALUES < <(python3 - "$LOCK" <<'PY'
import json
import sys
from pathlib import Path
lock = json.loads(Path(sys.argv[1]).read_text())
print(lock["godot_upstream"]["repository"])
print(lock["godot_upstream"]["commit"])
print(lock["webgpu_secondary"]["repository"])
print(lock["webgpu_secondary"]["commit"])
PY
)

UPSTREAM_REPO="${VALUES[0]}"
UPSTREAM_SHA="${VALUES[1]}"
WEBGPU_REPO="${VALUES[2]}"
WEBGPU_SHA="${VALUES[3]}"

git clone --filter=blob:none --no-checkout "$UPSTREAM_REPO" "$WORK_DIR"
git -C "$WORK_DIR" checkout --detach "$UPSTREAM_SHA"
git -C "$WORK_DIR" remote add webgpu "$WEBGPU_REPO"
git -C "$WORK_DIR" fetch --filter=blob:none webgpu "$WEBGPU_SHA"

git -C "$WORK_DIR" config user.name "Starjunk WebGPU Port"
git -C "$WORK_DIR" config user.email "webgpu-port@invalid"
git -C "$WORK_DIR" merge --no-commit --no-ff "$WEBGPU_SHA"

if git -C "$WORK_DIR" diff --name-only --diff-filter=U | grep -q .; then
  echo "Unexpected merge conflicts in pinned WebGPU candidate." >&2
  git -C "$WORK_DIR" diff --name-only --diff-filter=U >&2
  exit 3
fi

python3 "$ROOT/tools/engine/apply_starjunk_port_patches.py" "$WORK_DIR"

printf '%s\n' "$WORK_DIR"
