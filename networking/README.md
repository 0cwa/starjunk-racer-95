# Networking

Spritely is the decentralized authority/control layer; Godot remains isolated behind `game/src/networking/multiplayer_adapter.gd`.

Read:

- `source-lock.json` — pinned Goblins/Hoot and Starjunk protocol versions.
- `spritely-bridge.md` — browser/native bridge, control/data plane split and capability facets.
- `../docs/networking.md` — game-level networking architecture.

The next executable spike should compile a minimal Goblins 0.18 room actor with Hoot 0.9 and prove: create room → register sturdyref → enliven from a second client → grant racer facet → exchange one control event. Only after that should it negotiate the realtime state lane.


## Executable capability spike

`spritely/starjunk/race-room.scm` contains the first real Goblins actors. The CI spike uses **two separate Goblins vats and two WebSocket netlayers** on localhost:

1. host spawns a room actor;
2. host registers it with MyCapN and serializes its OCapN sturdyref;
3. client parses/enlivens that sturdyref over a real WebSocket CapTP connection;
4. client asks the remote room for a racer facet;
5. the returned racer capability is confirmed to be a remote reference and invoked.

This specifically verifies reference passing rather than merely serializing room IDs.

A second CI step compiles `spritely/hoot-room-smoke.scm` with Hoot 0.9.0. It imports the Goblins CapTP/WebSocket modules and references a browser bootstrap constructor, ensuring the browser-side dependency graph remains Hoot-compilable.
