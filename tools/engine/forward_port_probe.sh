#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="$ROOT/engine/source-lock.json"
OUT_DIR="${1:-$ROOT/build/forward-port-probe}"
WORK_DIR="$OUT_DIR/work"
REPORT="$OUT_DIR/report.json"

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

MERGE_BASE="$(git -C "$WORK_DIR" merge-base "$UPSTREAM_SHA" "$WEBGPU_SHA")"
git -C "$WORK_DIR" config user.name "Starjunk Forward Port Probe"
git -C "$WORK_DIR" config user.email "forward-port-probe@invalid"

set +e
git -C "$WORK_DIR" merge --no-commit --no-ff "$WEBGPU_SHA" >"$OUT_DIR/merge.stdout" 2>"$OUT_DIR/merge.stderr"
MERGE_EXIT=$?
set -e

mapfile -t CONFLICTS < <(git -C "$WORK_DIR" diff --name-only --diff-filter=U | sort)
git -C "$WORK_DIR" status --short >"$OUT_DIR/status.txt" || true

python3 - "$REPORT" "$UPSTREAM_SHA" "$WEBGPU_SHA" "$MERGE_BASE" "$MERGE_EXIT" "${CONFLICTS[@]}" <<'PY'
import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
upstream, webgpu, merge_base = sys.argv[2:5]
merge_exit = int(sys.argv[5])
conflicts = sys.argv[6:]
report = {
    "schema_version": 1,
    "upstream_commit": upstream,
    "webgpu_commit": webgpu,
    "merge_base": merge_base,
    "merge_exit_code": merge_exit,
    "clean_merge": merge_exit == 0 and not conflicts,
    "conflict_count": len(conflicts),
    "conflict_files": conflicts,
}
report_path.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
PY

# A conflicted merge is an expected probe result, not a workflow failure.
if git -C "$WORK_DIR" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  git -C "$WORK_DIR" merge --abort || true
fi
