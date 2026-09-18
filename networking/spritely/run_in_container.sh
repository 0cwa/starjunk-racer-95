#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends   ca-certificates   guile-3.0   guile-goblins   guile-hoot   guile-websocket   nodejs

timeout 60s guile networking/spritely/captp_room_smoke.scm

mkdir -p build/spritely

GOBLINS_FILE="$(dpkg -L guile-goblins | awk '/\/goblins\.scm$/ { print; exit }')"
test -n "$GOBLINS_FILE"
test -f "$GOBLINS_FILE"
GOBLINS_SITE_ROOT="$(dirname "$GOBLINS_FILE")"

# Debian installs Goblins and Hoot into the same Guile site root. Passing that
# whole directory to Hoot makes its library-group builder ingest Hoot's own
# host-side modules. Copy only Goblins into an isolated guest module root.
GOBLINS_HOOT_ROOT=/tmp/starjunk-goblins-hoot
rm -rf "$GOBLINS_HOOT_ROOT"
mkdir -p "$GOBLINS_HOOT_ROOT"
cp "$GOBLINS_FILE" "$GOBLINS_HOOT_ROOT/goblins.scm"
cp -a "$GOBLINS_SITE_ROOT/goblins" "$GOBLINS_HOOT_ROOT/goblins"

# Hoot's local --run VM does not provide Goblins' browser host imports
# (for example crypto.signEd25519). Compilation is the browser portability
# gate here; runtime host imports will be validated in an actual browser.
hoot compile   -L "$GOBLINS_HOOT_ROOT"   --bundle=build/spritely   -o build/spritely/starjunk-spritely-room.wasm   networking/spritely/hoot_room_smoke.scm

test -s build/spritely/starjunk-spritely-room.wasm

# Capture the exact host import contract emitted by the pinned Goblins/Hoot pair.
# Hoot emits Wasm GC/reference types that Debian's current wabt does not parse,
# while the browser-generation Node runtime does.
node - <<'NODE' > build/spritely/starjunk-spritely-room.imports.json
const fs = require('fs');
const bytes = fs.readFileSync('build/spritely/starjunk-spritely-room.wasm');
const module = new WebAssembly.Module(bytes);
console.log(JSON.stringify(WebAssembly.Module.imports(module), null, 2));
NODE

grep -q '"module": "crypto"' build/spritely/starjunk-spritely-room.imports.json
cat build/spritely/starjunk-spritely-room.imports.json
