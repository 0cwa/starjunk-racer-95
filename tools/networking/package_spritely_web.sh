#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPORT_DIR="${1:-}"
if [[ -z "$EXPORT_DIR" ]]; then
  echo "usage: tools/networking/package_spritely_web.sh <godot-web-export-dir>" >&2
  exit 2
fi

ROOM_WASM="${STARJUNK_SPRITELY_WASM:-$ROOT/build/spritely/starjunk-spritely-room.wasm}"
RUNTIME_DIR="${STARJUNK_HOOT_RUNTIME_DIR:-$ROOT/build/spritely/runtime}"
INDEX="$EXPORT_DIR/index.html"
DEST="$EXPORT_DIR/spritely"

if [[ ! -s "$INDEX" ]]; then
  echo "Expected Godot Web export index at $INDEX" >&2
  exit 3
fi

for required in   'spritely/reflect.js'   'globalThis.HootScheme = Scheme'   'spritely/bootstrap.mjs'
do
  if ! grep -Fq "$required" "$INDEX"; then
    echo "Godot Web export is missing Spritely bootstrap marker: $required" >&2
    exit 3
  fi
done

for asset in   "$ROOM_WASM"   "$RUNTIME_DIR/reflect.js"   "$RUNTIME_DIR/reflect.wasm"   "$RUNTIME_DIR/wtf8.wasm"   "$ROOT/networking/spritely/browser-host.mjs"   "$ROOT/networking/spritely/browser-race-bridge.mjs"   "$ROOT/networking/spritely/web/bootstrap.mjs"
do
  if [[ ! -s "$asset" ]]; then
    echo "Missing Spritely Web package asset: $asset" >&2
    exit 4
  fi
done

rm -rf "$DEST"
mkdir -p "$DEST"
install -m 0644 "$RUNTIME_DIR/reflect.js" "$DEST/reflect.js"
install -m 0644 "$RUNTIME_DIR/reflect.wasm" "$DEST/reflect.wasm"
install -m 0644 "$RUNTIME_DIR/wtf8.wasm" "$DEST/wtf8.wasm"
install -m 0644 "$ROOM_WASM" "$DEST/starjunk-spritely-room.wasm"
install -m 0644 "$ROOT/networking/spritely/browser-host.mjs" "$DEST/browser-host.mjs"
install -m 0644 "$ROOT/networking/spritely/browser-race-bridge.mjs" "$DEST/browser-race-bridge.mjs"
install -m 0644 "$ROOT/networking/spritely/web/bootstrap.mjs" "$DEST/bootstrap.mjs"

(
  cd "$DEST"
  sha256sum     bootstrap.mjs     browser-host.mjs     browser-race-bridge.mjs     reflect.js     reflect.wasm     starjunk-spritely-room.wasm     wtf8.wasm     > SHA256SUMS
)

echo "Packaged Spritely Web runtime at $DEST"
