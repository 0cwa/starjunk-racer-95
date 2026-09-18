# Vehicle handling architecture

## Two independent axes

A car's **performance profile** defines its trusted physical/competitive identity. The **realism setting** defines how directly players experience that profile.

Do not implement the realism slider by swapping between separate physics engines.

## Performance profile

A game-owned profile contains mass, dimensions, drive/brake force and tyre personality. Community car packages reference a profile ID; their visual model does not provide authoritative competitive physics.

The current `prototype_balanced_01` profile exists to establish the data contract, not to claim final tuning.

Future car archetypes may differ substantially in rotation, stability, drift retention and corner style while remaining close over a representative suite of micro-tracks.

## Realism resolver

`HandlingResolver` maps `0.0...1.0` through a smooth interpolation.

At the arcade end it adds countersteer, yaw stabilization, drift-entry help, grip recovery and speed-sensitive steering assistance while widening/softening the recoverable slip envelope.

At `1.0`, assists resolve to zero and tyre values return to the profile's physical baseline.

Physical identity values such as mass, wheelbase and drive force do not change when the slider moves.

## Multiplayer rule

For competitive races, realism is a **race setting**, shared by all racers. It must not become a per-player performance choice. Casual/local modes may eventually allow per-player assistance where fairness is not relevant.

## Next implementation

The eventual vehicle controller should be one `RigidBody3D`-based model with raycast suspension and explicit tyre-force calculation. The resolver supplies parameters to that single model.

Before adding multiple final profiles, build automated micro-tracks and telemetry so profile balance can be measured rather than guessed.
