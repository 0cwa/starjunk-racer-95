# Executable Spritely spike

This directory contains versioned probes that turn the networking architecture into executable evidence.

## Gates

CI proves four things against the pinned Goblins 0.18 / Hoot 0.9 package families:

1. **Native TCP+TLS CapTP:** a host registers a room, a second node enlivens its sturdyref, receives a racer facet, and calls that facet remotely.
2. **Native WebSocket CapTP:** two separate Goblins vats use actual WebSocket netlayers; the client enlivens a remote room, receives a racer capability, and proves positive readiness while binding canonical car/track SHA-256 IDs.
3. **Hoot browser compilation:** the CapTP/WebSocket dependency graph and Starjunk room actor compile into browser-targeted Wasm.
4. **Browser host contract:** CI records `WebAssembly.Module.imports()` for that Wasm, removes the standard Hoot runtime modules, and requires the remaining Goblins WebCrypto, typed-array and WebSocket imports to exactly match `browser-host.mjs`. The same probe exercises Ed25519 sign/verify, SHA-256, typed arrays and WebSocket callback semantics under JavaScript.

The native tests deliberately do not send high-frequency car snapshots through Goblins. CapTP authorizes rooms/facets/content and the realtime data lane remains a separate adapter.

## Files

- `captp_room_smoke.scm` — two-node TCP+TLS capability proof.
- `tests/captp-websocket-two-node.scm` — two-vat WebSocket capability proof.
- `starjunk/race-room.scm` — first reusable Starjunk room/racer actor shape.
- `hoot-room-smoke.scm` — browser-relevant Goblins/WebSocket compilation entrypoint.
- `browser-host.mjs` — browser-only Goblins host imports; it deliberately contains no game-domain or Godot API.
- `tests/browser-host-contract.mjs` — executable import-surface and JavaScript primitive probe.
- `run_in_container.sh` — pinned-package test harness used by CI.
- `.github/workflows/spritely-spike.yml` — delegates to the same container harness developers can run locally.

Hoot supplies its generic runtime/FFI/I/O/finalization modules. Starjunk owns only the Goblins-specific browser imports that need ambient browser APIs, keeping those capabilities out of gameplay code.

The next slice is to package Hoot's pinned browser runtime assets with the compiled room module, instantiate the module in a real browser, and expose only race-domain operations through a narrow Godot-facing multiplayer bridge.
