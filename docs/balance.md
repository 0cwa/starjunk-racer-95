# Vehicle balance and characterization

Starjunk Racer 95 should have cars with strong personalities but no universally superior choice. We need measurements before we need balance scores.

## Characterization harness

`game/tests/characterization/vehicle_characterization.tscn` runs the trusted prototype profile through deterministic scripted scenarios at 60 physics ticks per second:

- **straight launch** — sustained throttle from rest;
- **hard brake** — standardized braking after a fixed launch;
- **steady corner** — fixed throttle and steering input.

Each scenario records distance, starting/ending/mean/max speed, lateral speed, yaw rate, lateral wheel slip, longitudinal slip ratio, wheel angular speed and grounded-contact ratio. Longitudinal slip is especially important when tuning drive torque, wheel inertia and post-peak traction: a slower launch should not be “fixed” until we know whether it reflects intended tyre slip or pathological wheelspin. CI uploads the JSON as `vehicle-characterization`.

The balance characterization uses `realism = 1.0` so car identity is measured without the race-wide arcade-assist layer. We can separately characterize feel settings when needed.

## What this is not

These measurements are not yet a leaderboard and CI does not reject a car for being faster in one scenario. One profile exists today, so there is no useful dominance comparison yet.

When we add real archetypes, balance gates should compare a **suite** of scenarios. A profile may lead one dimension if it pays for that advantage elsewhere. Avoid a single aggregate “power score” that hides track-specific strengths.

## Future balance gates

Once at least three credible profiles exist:

1. add representative acceleration, braking, slalom, long-corner, hairpin and rough-surface scenarios;
2. collect the same telemetry for every profile;
3. define tolerances from observed distributions, not arbitrary equalization;
4. flag Pareto-dominant profiles (better or effectively equal across all meaningful dimensions);
5. keep song/course-specific testing separate so a profile can have legitimate track affinities without becoming the universal best choice.

The harness should stay deterministic and headless so agents can run it continuously while tuning.
