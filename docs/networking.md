# Spritely networking direction

Use Spritely Goblins/OCapN for decentralized identity, capabilities, invitations, room ownership and content references. The current integration target is Goblins 0.18.0; that release changed OCapN protocol compatibility, so networking dependencies are explicitly pinned in `networking/source-lock.json`.

Godot talks only to `MultiplayerAdapter` game concepts and validated `RaceProtocol` payloads. Keep high-frequency rigid-body simulation out of capability-object messaging.

## Protocol split

- `starjunk95/race-control/1` — low-frequency room/racer lifecycle, checkpoint/lap/finish events, content references and realtime-lane authorization.
- `starjunk95/race-state/1` — compact sequenced car state/control snapshots for prediction and interpolation.

The split lets us use Spritely where object capabilities are most valuable without coupling rendering/physics tick rate to CapTP latency or protocol overhead.

## Browser strategy

A Hoot-compiled Goblins module can live beside the Godot browser build. Goblins supports a browser WebSocket netlayer; because browser tabs cannot host WebSocket servers, WebSocket should bootstrap into Prelay or another decentralized netlayer rather than being treated as direct peer hosting.

See `networking/spritely-bridge.md` for capability facets and bridge boundaries.

## Initial multiplayer spike

1. create/join a room through a sturdyref invitation;
2. grant a racer facet rather than a global room/admin reference;
3. authorize a realtime lane and exchange validated snapshots;
4. publish checkpoint/lap/finish events on the control plane;
5. survive disconnect/reconnect without persisting rigid-body state;
6. share a custom car/track content capability reference.

Network-version upgrades are explicit compatibility work, not dependency bumps.
