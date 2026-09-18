# Spritely bridge architecture

## Version pin

The first implementation target is **Spritely Goblins 0.18.0** and **Hoot 0.9.0**. OCapN is still evolving and Goblins 0.18 changed protocol compatibility, so upgrades must be deliberate and tested against invitations/sturdyrefs created by the supported version.

See `source-lock.json`.

## Browser shape

The browser build should run a Hoot-compiled Goblins module next to Godot Web/WebGPU. Godot sees only a narrow bridge API and JSON-compatible `RaceProtocol` payloads; it does not import Goblins actor concepts.

Goblins' browser-capable WebSocket netlayer is a bootstrap route. Browser clients cannot host WebSocket servers, so decentralized reachability should use the Prelay model (or a later suitable netlayer) rather than pretending a browser tab is a directly reachable server.

## Two planes

### Capability/control plane — Goblins/OCapN

Use capabilities for:

- room creation and invitation;
- racer/spectator membership facets;
- ready state and race lifecycle;
- checkpoint/lap/finish events;
- authorization to open a realtime lane;
- sharing read-only or publish-capable content references;
- reconnect identity/authority.

A room invitation is an OCapN sturdyref. Treat it as an opaque bearer capability; do not extract identity or permissions from URI text.

### Realtime state plane

High-frequency car snapshots are **not** individual Goblins actor messages. A room capability authorizes/negotiates a realtime lane, then a transport adapter carries `starjunk95/race-state/1` snapshots.

The first implementation may use a relay-friendly WebSocket lane for simplicity. WebRTC/WebTransport can be evaluated later without changing gameplay or capability semantics.

Snapshots are prediction/interpolation input, not race authority. Checkpoints, laps, finish state and content authority remain control-plane concepts.

## Capability facets

Do not hand every participant one all-powerful room object. Prefer separate capabilities:

- **host/admin facet:** configure/start/cancel race and grant racer/spectator facets;
- **racer facet:** ready, publish race events belonging to that racer, request realtime lane;
- **spectator facet:** receive race state without racer authority;
- **content reader facet:** obtain manifest/blob references;
- **content publisher facet:** publish/fork content when explicitly granted.

This maps moderation and mod publishing to possession of specific authority rather than account roles baked into a central service.

## Bridge contract

The bridge between Godot and Goblins must:

1. validate `RaceProtocol` payloads before crossing either direction;
2. attach monotonically increasing sequence numbers;
3. enforce size/rate limits independently of the remote peer;
4. surface disconnect/reconnect as state, not fatal process errors;
5. never expose ambient filesystem/network authority to downloaded mods;
6. preserve OCapN references as opaque strings on the Godot side.

## Persistence

Goblins persistence can retain room/content objects, but a live race should not depend on serializing Godot rigid-body state. Persist durable identity, invitations and content authority; reconstruct ephemeral realtime state after reconnect.
