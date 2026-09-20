# Networking

Spritely is the decentralized authority/control layer; Godot remains isolated behind `game/src/networking/multiplayer_adapter.gd`.

Read:

- `source-lock.json` — pinned Goblins/Hoot and Starjunk protocol versions.
- `spritely-bridge.md` — browser/native bridge, control/data plane split and capability facets.
- `../docs/networking.md` — game-level networking architecture.

The executable spike now proves the native capability flow and the browser runtime boundary. The next networking slice is to extend the private Hoot race-domain dispatcher/façade with asynchronous room join and racer-readiness operations, returning only lifecycle state and opaque OCapN sturdyref strings, then connect those operations to Godot's `MultiplayerAdapter`. High-frequency `starjunk95/race-state/1` snapshots remain on the separate realtime lane.

## Executable capability spike

`spritely/starjunk/race-room.scm` contains the first real Goblins actors. The CI spike uses **two separate Goblins vats and two WebSocket netlayers** on localhost:

1. host spawns a room actor;
2. host registers it with MyCapN and serializes its OCapN sturdyref;
3. client parses/enlivens that sturdyref over a real WebSocket CapTP connection;
4. client asks the remote room for a racer facet;
5. the returned racer capability is confirmed to be a remote reference and invoked;
6. positive readiness is bound to canonical car and track SHA-256 content IDs.

The Spritely CI lane also compiles the CapTP/WebSocket graph with Hoot 0.9.0, checks the exact Goblins browser-host import surface, loads Hoot's pinned runtime assets in headless Chromium, and crosses the private race-domain JavaScript façade without exposing Scheme/Goblins objects to gameplay code.

This verifies reference passing and browser execution rather than merely serializing room IDs. Capability/control messages remain deliberately separate from the realtime snapshot transport.
