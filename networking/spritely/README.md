# Executable Spritely spike

This directory contains versioned probes that turn the networking architecture into executable evidence.

## Gates

CI proves six things against the pinned Goblins 0.18 / Hoot 0.9 package families:

1. **Native TCP+TLS CapTP:** a host registers a room, a second node enlivens its sturdyref, receives a racer facet, and calls that facet remotely.
2. **Native WebSocket CapTP:** two separate Goblins vats use actual WebSocket netlayers; the client enlivens a remote room, receives a racer capability, proves positive readiness while binding canonical car/track SHA-256 IDs, then becomes unready without content IDs.
3. **Hoot browser compilation:** the CapTP/WebSocket dependency graph and Starjunk room actor compile into browser-targeted Wasm.
4. **Browser host contract:** CI records `WebAssembly.Module.imports()` for that Wasm, removes the standard Hoot runtime modules, and requires the remaining Goblins WebCrypto, typed-array and WebSocket imports to exactly match `browser-host.mjs`. The same probe exercises Ed25519 sign/verify, SHA-256, typed arrays and WebSocket callback semantics under JavaScript.
5. **Real-browser instantiation:** CI copies `reflect.js`, `reflect.wasm` and `wtf8.wasm` from the exact pinned Hoot package, serves them with the compiled Starjunk module over localhost, and requires headless Chromium to instantiate the module with the Starjunk browser host imports.
6. **Race-domain browser seam:** the Hoot module keeps remote room/racer references private, `browser-race-bridge.mjs` exposes only primitive/opaque race-domain values, and Chromium proves join → content-bound readiness → unready-without-content-IDs → leave against a live native room. Leaving explicitly drops the browser-held racer capability. No reflected Scheme/Goblins object is returned by the public JavaScript façade.
7. **Godot Web package bootstrap:** CI assembles the exact pinned Hoot runtime, compiled Starjunk Wasm and narrow browser façade into the same `spritely/` layout referenced by the Godot `Web Playable` export preset, verifies package checksums, and boots that packaged layout in Chromium.

The native tests deliberately do not send high-frequency car snapshots through Goblins. CapTP authorizes rooms/facets/content and the realtime data lane remains a separate adapter.

## Files

- `captp_room_smoke.scm` — two-node TCP+TLS capability proof.
- `tests/captp-websocket-two-node.scm` — two-vat WebSocket capability proof.
- `starjunk/race-room.scm` — reusable Starjunk room/racer actor shape plus shared ready-content validation.
- `hoot-room-smoke.scm` — browser-relevant Goblins/WebSocket entrypoint and private bridge dispatcher.
- `browser-host.mjs` — browser-only Goblins host imports; it deliberately contains no game-domain or Godot API.
- `browser-race-bridge.mjs` — race-domain JavaScript façade; reflected Hoot/Goblins values stay private.
- `tests/browser-host-contract.mjs` — executable import-surface and JavaScript primitive probe.
- `tests/browser-smoke.html` / `tests/browser-smoke.mjs` — real-browser Hoot + race-domain bridge bootstrap.
- `tests/run-browser-smoke.mjs` — localhost server and headless-Chromium assertion harness.
- `web/bootstrap.mjs` — export-time bootstrap that publishes `StarjunkSpritelyReady` and installs the Godot-visible primitive façade.
- `../../tools/networking/package_spritely_web.sh` — deterministic post-export packager; copies only build outputs/runtime assets and writes SHA-256 checksums.
- `run_in_container.sh` — pinned-package test harness used by CI.
- `.github/workflows/spritely-spike.yml` — delegates to the same container harness developers can run locally.

Hoot supplies its generic runtime/FFI/I/O/finalization modules. Starjunk owns only the Goblins-specific browser imports that need ambient browser APIs, keeping those capabilities out of gameplay code. The real-browser probe deliberately packages Hoot's runtime assets from the installed pinned package rather than committing a duplicate copy.

Godot now has a tested `SpritelyMultiplayerAdapter` boundary, a tiny web-only JavaScriptBridge port, and a reproducible Web package/bootstrap layout. The next slice is to run the actual `Web Playable` export with the project WebGPU template in CI and prove Godot gameplay can observe `StarjunkSpritelyReady` from that exported page. High-frequency snapshots remain on the separate realtime lane.
