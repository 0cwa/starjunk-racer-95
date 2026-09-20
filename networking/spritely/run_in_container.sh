#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends   ca-certificates   chromium   guile-3.0   guile-goblins   guile-hoot   guile-gnutls   guile-websocket   nodejs

GOBLINS_VERSION="$(dpkg-query -W -f='${Version}' guile-goblins)"
HOOT_VERSION="$(dpkg-query -W -f='${Version}' guile-hoot)"
echo "guile-goblins=$GOBLINS_VERSION"
echo "guile-hoot=$HOOT_VERSION"
case "$GOBLINS_VERSION" in
  0.18.0-*) ;;
  *) echo "Expected Goblins 0.18.0 package family" >&2; exit 2 ;;
esac
case "$HOOT_VERSION" in
  0.9.0-*) ;;
  *) echo "Expected Hoot 0.9.0 package family" >&2; exit 2 ;;
esac

# Prove CapTP over two native transports. TCP+TLS exercises the direct native
# netlayer; WebSocket exercises the same bootstrap transport browsers use.
timeout 60s guile networking/spritely/captp_room_smoke.scm
timeout 60s guile -L networking/spritely   networking/spritely/tests/captp-websocket-two-node.scm

mkdir -p build/spritely

GOBLINS_FILE="$(dpkg -L guile-goblins | awk '/\/goblins\.scm$/ { print; exit }')"
test -n "$GOBLINS_FILE"
test -f "$GOBLINS_FILE"
GOBLINS_SITE_ROOT="$(dirname "$GOBLINS_FILE")"

# Do not expose Hoot's Guile-side sources through the guest load path. Copy
# only Goblins, otherwise host modules can shadow Hoot's declarative builtins.
GOBLINS_HOOT_ROOT=/tmp/starjunk-goblins-hoot
rm -rf "$GOBLINS_HOOT_ROOT"
mkdir -p "$GOBLINS_HOOT_ROOT"
cp "$GOBLINS_FILE" "$GOBLINS_HOOT_ROOT/goblins.scm"
cp -a "$GOBLINS_SITE_ROOT/goblins" "$GOBLINS_HOOT_ROOT/goblins"

# Compile the browser-relevant CapTP/WebSocket graph, not only local actor code.
hoot compile --bundle   -L networking/spritely   -L "$GOBLINS_HOOT_ROOT"   -o build/spritely/starjunk-spritely-room.wasm   networking/spritely/hoot-room-smoke.scm

test -s build/spritely/starjunk-spritely-room.wasm

# Record the exact JS host contract emitted by the pinned Goblins/Hoot pair.
node - <<'NODE' > build/spritely/starjunk-spritely-room.imports.json
const fs = require('fs');
const bytes = fs.readFileSync('build/spritely/starjunk-spritely-room.wasm');
const module = new WebAssembly.Module(bytes);
console.log(JSON.stringify(WebAssembly.Module.imports(module), null, 2));
NODE

test -s build/spritely/starjunk-spritely-room.imports.json
node networking/spritely/tests/browser-host-contract.mjs   build/spritely/starjunk-spritely-room.imports.json

# Use the runtime assets shipped by the exact Hoot package under test. Do not
# vendor a second copy that can drift independently from the compiler/runtime.
HOOT_REFLECT_JS="$(dpkg -L guile-hoot | awk '/\/reflect-js\/reflect\.js$/ { print; exit }')"
HOOT_REFLECT_WASM="$(dpkg -L guile-hoot | awk '/\/reflect-wasm\/reflect\.wasm$/ { print; exit }')"
HOOT_WTF8_WASM="$(dpkg -L guile-hoot | awk '/\/reflect-wasm\/wtf8\.wasm$/ { print; exit }')"
for asset in "$HOOT_REFLECT_JS" "$HOOT_REFLECT_WASM" "$HOOT_WTF8_WASM"; do
  test -n "$asset"
  test -s "$asset"
done

BROWSER_ROOT=build/spritely/browser
rm -rf "$BROWSER_ROOT"
mkdir -p "$BROWSER_ROOT"
cp "$HOOT_REFLECT_JS" "$BROWSER_ROOT/reflect.js"
cp "$HOOT_REFLECT_WASM" "$BROWSER_ROOT/reflect.wasm"
cp "$HOOT_WTF8_WASM" "$BROWSER_ROOT/wtf8.wasm"
cp build/spritely/starjunk-spritely-room.wasm "$BROWSER_ROOT/"
cp networking/spritely/browser-host.mjs "$BROWSER_ROOT/"
cp networking/spritely/browser-race-bridge.mjs "$BROWSER_ROOT/"
cp networking/spritely/tests/browser-smoke.html "$BROWSER_ROOT/"
cp networking/spritely/tests/browser-smoke.mjs "$BROWSER_ROOT/"

ROOM_HOST_LOG=build/spritely/browser-room-host.log
ROOM_REFERENCE="$BROWSER_ROOT/room-reference.txt"
rm -f "$ROOM_REFERENCE" "$ROOM_HOST_LOG"

guile -L networking/spritely   networking/spritely/tests/browser-room-host.scm   "$ROOM_REFERENCE" >"$ROOM_HOST_LOG" 2>&1 &
ROOM_HOST_PID=$!

cleanup_room_host() {
  if kill -0 "$ROOM_HOST_PID" 2>/dev/null; then
    kill "$ROOM_HOST_PID" 2>/dev/null || true
    wait "$ROOM_HOST_PID" 2>/dev/null || true
  fi
}
trap cleanup_room_host EXIT

for _ in $(seq 1 100); do
  if [[ -s "$ROOM_REFERENCE" ]]; then
    break
  fi
  if ! kill -0 "$ROOM_HOST_PID" 2>/dev/null; then
    cat "$ROOM_HOST_LOG" >&2
    echo "Browser room host exited before producing a sturdyref" >&2
    exit 3
  fi
  sleep 0.1
done

if [[ ! -s "$ROOM_REFERENCE" ]]; then
  cat "$ROOM_HOST_LOG" >&2
  echo "Timed out waiting for browser room sturdyref" >&2
  exit 3
fi

cat "$ROOM_HOST_LOG"
cat "$ROOM_REFERENCE"

node networking/spritely/tests/run-browser-smoke.mjs "$BROWSER_ROOT" chromium

cleanup_room_host
trap - EXIT

cat build/spritely/starjunk-spritely-room.imports.json
printf 'Spritely native + browser remote room/readiness probes passed\n'
