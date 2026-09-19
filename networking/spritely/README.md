# Executable Spritely spike

This directory contains versioned probes that turn the networking architecture into executable evidence.

## Gates

CI proves four things against the pinned Goblins 0.18 / Hoot 0.9 package families:

1. **Native TCP+TLS CapTP:** a host registers a room, a second node enlivens its sturdyref, receives a racer facet, and calls that facet remotely.
2. **Native WebSocket CapTP:** two separate Goblins vats use actual WebSocket netlayers; the client enlivens a remote room, receives a racer capability, and proves positive readiness while binding canonical car/track SHA-256 IDs.
3. **Hoot browser compilation:** the CapTP/WebSocket dependency graph and Starjunk room actor compile into browser-targeted Wasm.
4. **Browser host contract capture:** CI records `WebAssembly.Module.imports()` for that Wasm and asserts the expected Goblins crypto host import family is present.

The native tests deliberately do not send high-frequency car snapshots through Goblins. CapTP authorizes rooms/facets/content and the realtime data lane remains a separate adapter.

## Files

- `captp_room_smoke.scm` — two-node TCP+TLS capability proof.
- `tests/captp-websocket-two-node.scm` — two-vat WebSocket capability proof.
- `starjunk/race-room.scm` — first reusable Starjunk room/racer actor shape.
- `hoot-room-smoke.scm` — browser-relevant Goblins/WebSocket compilation entrypoint.
- `run_in_container.sh` — pinned-package test harness used by CI.
- `.github/workflows/spritely-spike.yml` — delegates to the same container harness developers can run locally.

Hoot's local `--run` VM is not used as a browser runtime test because it does not provide Goblins' browser host imports. The next slice should implement those JavaScript host imports, instantiate this Wasm in a real browser, and expose a narrow API to Godot through the multiplayer adapter.
