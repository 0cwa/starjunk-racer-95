# Playable prototype race

The default project scene is now a small local vertical slice rather than an empty bootstrap.

## Current loop

- one trusted prototype-balanced raycast car;
- flat physics surface with a neon oval course;
- ordered checkpoint/lap tracking;
- chase camera;
- live speed/slip/lap HUD;
- interactive realism slider;
- keyboard and standard gamepad input;
- reset/recovery control;
- lightweight GPU spark field so the prototype already exercises the intended saturated/glowing visual direction.

The course geometry is deliberately generated from code and uses `MultiMeshInstance3D` for repeated road/rail pieces. It is a mechanics sandbox, not one of the final song-inspired courses.

## Controls

- **W / Up / right trigger:** throttle
- **S / Down / left trigger:** brake
- **A/D / arrows / left stick:** steer
- **R / gamepad Back:** reset car
- **[ / ]:** decrease/increase realism
- The realism slider can also be manipulated directly with mouse/keyboard UI input.

## Why this scene exists

This is the shortest playable loop for continuous development. New vehicle, camera, input and visual changes should remain testable here before they are multiplied across content.

`prototype_race_test.tscn` loads the same scene headlessly, verifies its controls/HUD/checkpoints, settles the actual raycast vehicle, drives it forward and exercises the realism/reset paths.

## Next gameplay work

The next meaningful handling additions are wheel rotational inertia/longitudinal slip, better drift-entry behavior with telemetry, and real road-surface metadata. The next content step is to allow a validated community car visual and community track package to replace the prototype presentation while retaining trusted race physics/rules.
