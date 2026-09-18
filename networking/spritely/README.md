# Executable Spritely spike

This directory contains disposable-but-versioned probes used to turn the networking architecture into evidence.

- `captp_room_smoke.scm` creates two Goblins nodes, registers a room object, serializes its sturdyref, enlivens it from the second node, obtains a racer facet from the remote room, and calls that facet.
- `hoot_room_smoke.scm` compiles the same room/racer capability shape through Hoot so browser deployment stays a tested constraint.
- `.github/workflows/spritely-spike.yml` runs these against Debian sid packages for Goblins 0.18 and Hoot 0.9.

These probes deliberately avoid real car snapshots. The next step after both gates pass is to expose the room/facet operations through a narrow Hoot↔JavaScript bridge and have Godot call that bridge through `MultiplayerAdapter`.
