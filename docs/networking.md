# Spritely networking direction

Use Spritely Goblins/OCapN for decentralized identity, capabilities, invitations, room ownership and content references.

Godot talks only to `MultiplayerAdapter`-style game concepts. Keep high-frequency rigid-body simulation out of capability-object messaging.

Initial multiplayer spike:

1. create/join a race room;
2. represent racers through capability references;
3. exchange compact input/state snapshots;
4. publish checkpoint/lap events;
5. survive disconnect/reconnect;
6. share a content package reference.

Pin protocol/library versions. Network-version upgrades must be explicit.
