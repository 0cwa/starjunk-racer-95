# Spritely networking direction

Use Spritely Goblins/OCapN for decentralized identity, capabilities, invitations, room ownership and content references. The current integration target is Goblins 0.18.0; that release changed OCapN protocol compatibility, so networking dependencies are explicitly pinned in `networking/source-lock.json`.

Godot talks only to `MultiplayerAdapter` game concepts and validated `RaceProtocol` payloads. Keep high-frequency rigid-body simulation out of capability-object messaging.

## Protocol split

- `starjunk95/race-control/2` — low-frequency room/racer lifecycle, checkpoint/lap/finish events, content references and realtime-lane authorization. Track and shared-content capabilities are bound to canonical `sha256:` content IDs so authority and immutable byte identity are separate.
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


## Control protocol v2 content binding

Version 2 is an intentional pre-release breaking change from `race-control/1`. A race room now carries both `track_reference` (the OCapN capability granting authority/access) and `track_content_id` (the immutable SHA-256 package identity). Content-reference events similarly require both fields.

The realtime snapshot protocol remains `starjunk95/race-state/1`; its wire semantics did not change.


## Content-reader capabilities

Community package bytes are not embedded directly in race events. A race/content reference binds an immutable package content ID to an OCapN capability. That capability can resolve to a read-only content object whose descriptor identifies files/hashes and whose `open-blob` method returns a narrower blob-reader facet.

Blob reads are ranged and capped at 64 KiB. This keeps CapTP messages bounded and means a peer can stream, hash, and stage a large GLB/package incrementally without receiving publisher authority.

Publish/update/fork authority will be modeled as separate capabilities rather than methods on the reader facet.
