#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends   ca-certificates   guile-3.0   guile-goblins   guile-hoot   guile-gnutls   guile-websocket   nodejs

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

# Nested least-authority content capability: descriptor -> blob facet -> bounded chunks.
timeout 60s guile -L networking/spritely   networking/spritely/tests/captp-content-reader.scm

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
grep -q '"module": "crypto"' build/spritely/starjunk-spritely-room.imports.json

cat build/spritely/starjunk-spritely-room.imports.json
printf 'Spritely native + browser compile probes passed\n'
