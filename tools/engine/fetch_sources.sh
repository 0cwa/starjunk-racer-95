#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="$ROOT/engine/source-lock.json"
DEST="${1:-$ROOT/engine/worktrees}"
mkdir -p "$DEST"

python3 - "$LOCK" "$DEST" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

lock = json.loads(Path(sys.argv[1]).read_text())
dest = Path(sys.argv[2])
for name in ("godot_upstream", "webgpu_primary", "webgpu_secondary"):
    item = lock[name]
    target = dest / name
    if not target.exists():
        subprocess.run(["git", "clone", "--filter=blob:none", item["repository"], str(target)], check=True)
    subprocess.run(["git", "-C", str(target), "fetch", "origin", item["commit"]], check=True)
    subprocess.run(["git", "-C", str(target), "checkout", "--detach", item["commit"]], check=True)
    actual = subprocess.check_output(["git", "-C", str(target), "rev-parse", "HEAD"], text=True).strip()
    if actual != item["commit"]:
        raise SystemExit(f"{name}: expected {item['commit']}, got {actual}")
    print(f"{name}: {actual}")
PY
