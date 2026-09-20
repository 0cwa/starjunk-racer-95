# Spritely networking direction

Use Spritely Goblins/OCapN for decentralized identity, capabilities, invitations, room ownership and content references. The current integration target is Goblins 0.18.0; that release changed OCapN protocol compatibility, so networking dependencies are explicitly pinned in `networking/source-lock.json`.

Godot talks only to `MultiplayerAdapter` game concepts and validated `RaceProtocol` payloads. Keep high-frequency rigid-body simulation out of capability-object messaging.

## Protocol split

- `starjunk95/race-control/3` — low-frequency room/racer lifecycle, checkpoint/lap/finish events, content references and realtime-lane authorization. Track and shared-content capabilities are bound to canonical `sha256:` content IDs so authority and immutable byte identity are separate.
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


## Control protocol v3 readiness binding

Version 3 keeps the v2 separation between capability authority and immutable content identity, and extends it to positive racer readiness.

A race room carries both `track_reference` (the OCapN capability granting authority/access) and `track_content_id` (the immutable SHA-256 package identity). Car/track content-reference events likewise pair an OCapN reference with a canonical content ID.

`racer_ready { ready: true }` now also requires the exact `car_content_id` and `track_content_id`. `RaceContentAgreement` will only manufacture that event after the local `CommunityContentService` re-verifies that the room track ID resolves to an installed track package and the advertised car ID resolves to an installed car package. A peer can become unready without IDs.

The Spritely racer facet mirrors the wire contract with narrow capability methods: positive readiness uses `ready` plus both canonical IDs, while `racer_ready { ready: false }` maps to `unready` and carries no content IDs. This does not grant new authority; positive readiness proves which immutable bytes the racer says it is ready to use.

The realtime snapshot protocol remains `starjunk95/race-state/1`; its wire semantics did not change.
