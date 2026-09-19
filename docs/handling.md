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

## Tyre force model

`TireForceModel` is a pure-math layer intended for each raycast wheel. Its lateral curve has a linear small-slip region, reaches `mu * normal_load` at the configured peak slip angle, then falls smoothly toward a controllable sliding-grip plateau.

Longitudinal and lateral requests are constrained by a normalized friction ellipse. This is where braking/throttle must give up lateral authority during hard combined manoeuvres instead of allowing impossible independent peak forces.

The model is deliberately independent of `RigidBody3D`, suspension raycasts and input code so it can be unit-tested and reused by headless balance simulations.

## Wheel slip kinematics

`WheelSlipKinematics` converts contact-patch motion into the slip quantities consumed by tyre forces.

Lateral slip angle uses velocity in the wheel's **steered local frame** and floors the longitudinal reference speed near rest, preventing tiny lateral noise from becoming an artificial 90-degree tyre event.

Longitudinal slip compares wheel circumferential speed with road speed using a symmetric, low-speed-safe denominator. Pure rolling is zero, a locked wheel under forward motion is -1, and driven-wheel overspeed is positive.

The future wheel controller is responsible for transforming the rigid body's point velocity into each steered wheel frame before using these helpers.

## Suspension model

Suspension parameters are trusted performance-profile values and do **not** change with the realism slider.

`SuspensionModel` converts ray-contact distance into bounded compression, derives compression velocity, then computes a one-way spring/damper normal force. Separate bump and rebound damping let profiles control landing/compression response versus extension response.

The force is clamped at zero so the suspension never pulls the chassis toward the road, and at a profile maximum so extreme contact events cannot create unbounded impulses.

The future raycast wheel adapter should retain previous compression per wheel, call this model each physics tick, and feed its normal load into `TireForceModel`.

## First raycast vehicle integration

`RaycastVehicleController` and `RaycastWheel3D` are intentionally thin adapters over the pure handling modules:

1. a wheel ray gathers contact point/normal/distance;
2. `SuspensionModel` produces normal load;
3. rigid-body point velocity becomes wheel-frame slip through `WheelSlipKinematics`;
4. `TireForceModel` produces lateral force and clamps it together with requested drive/brake force;
5. Godot receives the resulting positioned force.

The prototype uses rear-wheel drive and front-wheel steering. Each wheel now owns angular velocity and rotational inertia: drive/brake requests become torques, longitudinal slip produces tyre force, and the actual friction-ellipse-clamped force feeds reaction torque back into the wheel. This permits wheelspin and lockup without introducing a second handling model.

The integration test builds a flat road and four-wheel car entirely in code, lets it settle on its suspension, then applies throttle and requires forward motion without non-finite state. CI uses `--fixed-fps 60` so the physics frames execute deterministically without real-time waiting.


## Arcade handling assists

`HandlingAssistModel` is a pure-math layer between player intent and the single physical vehicle model. At realism `1.0`, every assist strength resolves to zero and the controller receives the driver's steering unchanged.

At lower realism values:

- speed-sensitive steering reduces high-speed twitch without increasing the car's maximum steering angle;
- countersteer assistance steers into the direction of lateral slide using chassis slip angle;
- yaw stability applies corrective torque only while the chassis is sliding, rather than acting as permanent angular damping;
- grip recovery raises the post-peak tyre-force plateau toward the existing peak-friction limit, so a slide is easier to catch without creating more than `mu * normal_load` lateral grip.

These are race-wide feel settings in competitive multiplayer. They do not change mass, drive force, brake force, dimensions, suspension values, or the peak tyre-friction envelope.

`drift_entry_assist` is still intentionally unused; it should not be wired until we can validate its effect with drift-entry telemetry instead of adding hidden yaw impulses by feel.


## Wheel rotation and longitudinal slip

`WheelRotationModel` is a pure angular integrator. Drive torque, tyre reaction torque and angular damping are integrated first; brake torque then removes angular speed without numerically driving the wheel through zero. A trusted maximum angular speed bounds pathological airborne spin.

`RaycastWheel3D` computes longitudinal slip from contact-patch road speed versus wheel circumferential speed. `TireForceModel.longitudinal_force_n` uses the same shaped peak/post-peak philosophy as the lateral curve. The requested longitudinal and lateral forces still share one friction ellipse, so wheelspin does not create extra grip.

Wheel inertia, longitudinal stiffness, peak longitudinal slip and maximum angular speed are trusted performance-profile values and are independent of the realism slider. The race-wide realism setting may raise post-peak recovery grip for easier slide recovery, but it does not change the peak friction envelope.


The rotational integrator clamps tyre-reaction movement at the instantaneous rolling-speed equilibrium. This is a numerical stability rule, not traction control: drive torque may still push a driven wheel beyond rolling speed and brakes may still hold it below rolling speed, but an undriven tyre cannot overshoot from positive to negative slip solely because a 60 Hz explicit reaction-torque step was too large.


The current prototype's drive-force ceiling is tuned so the characterization harness at 65% throttle operates near, but below, static rear-axle peak traction. Full throttle still exceeds static rear grip and can produce deliberate wheelspin. This is provisional until longitudinal load transfer is modeled.


## Trusted road surfaces

Road surface behavior is a third axis, separate from both car identity and the race-wide realism setting. `RoadSurfaceRegistry` owns the coefficients for generation-1 surfaces:

- `asphalt` — baseline tyre response;
- `wet` — lower peak grip/stiffness with a slightly wider slip envelope;
- `gravel` — substantially lower/stiffer-response grip with a much wider usable slip envelope.

A track package may select only a trusted `surface_profile` ID. It cannot supply friction coefficients, tyre curves, scripts, or arbitrary physics resources. Imported collision bodies are rebuilt by the game and tagged with that trusted ID.

Each raycast wheel resolves the collider's trusted surface metadata at contact time and applies the registry multipliers to the existing lateral/longitudinal tyre curves and friction ellipse. Missing or invalid metadata falls back to `asphalt`. Surface ID and grip multiplier are included in wheel telemetry.

The realism slider still changes only assistance/recovery behavior. It does not change which road surface is under the tyre or the surface's peak-friction multiplier.
