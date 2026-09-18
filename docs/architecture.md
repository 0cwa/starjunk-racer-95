# Architecture

## Runtime layers

1. **Game domain:** race rules, vehicle model, checkpoints, presentation state.
2. **Godot adapters:** rendering, input, audio, asset loading and local physics.
3. **Multiplayer adapter:** stable race/lobby/content interfaces.
4. **Spritely implementation:** Goblins/OCapN identity, capabilities, invitations, decentralized object references and content authority.
5. **Community package layer:** GLB/media plus validated declarative manifests.

Gameplay code must not depend directly on Goblins internals or WebGPU fork internals.

## Renderer contract

The canonical visual target is Godot's **Mobile RenderingDevice renderer**. WebGPU should run that renderer in browsers. Native Forward+ can add optional luxuries but cannot be required for track readability or the core look. Compatibility/WebGL can eventually be a reduced fallback.

## Content contract

A custom car's visual model is separate from its competitive physics profile. A custom track declares checkpoints, spawn points, surfaces and presentation metadata without arbitrary engine code.

## Determinism and multiplayer

Do not require bit-identical rigid-body simulation across peers. Locally simulate the controlled car and exchange inputs/state snapshots with interpolation/prediction. Race-critical events are narrow, explicit protocol concepts.

## Performance

The renderer torture test is versioned production infrastructure. A feature that materially changes rendering cost should either appear in it or be covered by a separate benchmark with the same identity/baseline rules.
