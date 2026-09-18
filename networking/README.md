# Networking

Spritely is the decentralized authority/control layer; Godot remains isolated behind `game/src/networking/multiplayer_adapter.gd`.

Read:

- `source-lock.json` — pinned Goblins/Hoot and Starjunk protocol versions.
- `spritely-bridge.md` — browser/native bridge, control/data plane split and capability facets.
- `../docs/networking.md` — game-level networking architecture.

The next executable spike should compile a minimal Goblins 0.18 room actor with Hoot 0.9 and prove: create room → register sturdyref → enliven from a second client → grant racer facet → exchange one control event. Only after that should it negotiate the realtime state lane.
