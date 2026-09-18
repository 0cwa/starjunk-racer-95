# Executable Spritely spike

This directory contains disposable-but-versioned probes used to turn the networking architecture into evidence.

- `captp_room_smoke.scm` creates two Goblins nodes, registers a room object, serializes its sturdyref, enlivens it from the second node, obtains a racer facet from the remote room, and calls that facet.
- `hoot_room_smoke.scm` compiles the same room/racer capability shape through Hoot so browser deployment stays a tested constraint.
- `.github/workflows/spritely-spike.yml` runs these against Debian sid packages for Goblins 0.18 and Hoot 0.9.

These probes deliberately avoid real car snapshots. The next step after both gates pass is to expose the room/facet operations through a narrow Hoot↔JavaScript bridge and have Godot call that bridge through `MultiplayerAdapter`.


## Proven gates

The spike now proves two separate things in CI:

1. Native Goblins/OCapN authority works end-to-end: a host registers a room, a second node enlivens its sturdyref, receives a racer facet, and calls that facet remotely.
2. The same room/facet actor shape compiles through Hoot 0.9 into browser-targeted Wasm.

Hoot's local `--run` VM is intentionally not used as the browser runtime test because it does not provide Goblins' browser host imports such as `crypto.signEd25519`. CI records the Wasm import list instead. The next browser networking slice should implement that explicit JavaScript host contract and then run the Hoot bundle in a real browser.
