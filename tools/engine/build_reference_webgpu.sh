#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${1:-$ROOT/engine/worktrees/webgpu_primary}"

if [[ ! -f "$SOURCE/SConstruct" ]]; then
  echo "WebGPU source not found. Run tools/engine/fetch_sources.sh first." >&2
  exit 2
fi

python3 -m pip install --user scons
export PATH="$HOME/.local/bin:$PATH"

scons -C "$SOURCE"   platform=web   target=template_release   dlink_enabled=yes   webgpu=yes   opengl3=no   threads=no   dev_mode=yes   tests=no   debug_symbols=no
